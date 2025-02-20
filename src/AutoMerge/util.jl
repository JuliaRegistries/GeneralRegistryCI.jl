function checkout_branch(
    dir::AbstractString, branch::AbstractString; git_command::AbstractString="git"
)
    return Base.run(Cmd(`$(git_command) checkout $(branch)`; dir=dir))
end

clone_repo(repo::GitHub.Repo) = clone_repo(repo_url(repo))

function clone_repo(url::AbstractString)
    parent_dir = mktempdir(; cleanup=true)
    repo_dir = joinpath(parent_dir, "REPO")
    my_retry(() -> _clone_repo_into_dir(url, repo_dir))
    @info("Clone was successful")
    return repo_dir
end

function _clone_repo_into_dir(url::AbstractString, repo_dir)
    @info("Attempting to clone...")
    rm(repo_dir; force=true, recursive=true)
    mkpath(repo_dir)
    LibGit2.clone(url, repo_dir)
    return repo_dir
end

"""
    load_files_from_url_and_tree_hash(f, destination::String, url::String, tree_hash::String) -> Bool

Attempts to clone a git repo from `url` into a temporary directory, runs `f(dir)` on that directory,
then extract the files and folders from a given `tree_hash`, placing them in `destination`.

Returns a boolean indicating if the cloning succeeded.
"""
function load_files_from_url_and_tree_hash(
    f, destination::String, url::String, tree_hash::String
)
    pkg_clone_dir = mktempdir()
    clone_success = try
        _clone_repo_into_dir(url, pkg_clone_dir)
        true
    catch e
        @error "Cloning $url failed" e
        false
    end
    # if cloning failed, bail now
    !clone_success && return clone_success

    f(pkg_clone_dir)
    Tar.extract(Cmd(`git archive $tree_hash`; dir=pkg_clone_dir), destination)
    return clone_success
end

"""
    parse_registry_pkg_info(registry_path, pkg, version=nothing) -> @NamedTuple{uuid::String, repo::String, subdir::String, tree_hash::Union{Nothing, String}}

Searches the registry located at `registry_path` for a package with name `pkg`. Upon finding it,
it parses the associated `Package.toml` file and returns the UUID and repository URI, and `subdir`.

If `version` is supplied, then the associated `tree_hash` will be returned. Otherwise, `tree_hash` will be `nothing`.
"""
function parse_registry_pkg_info(registry_path, pkg, version=nothing)
    # We know the name of this package but not its uuid. Look it up in
    # the registry that includes the current PR.
    packages = TOML.parsefile(joinpath(registry_path, "Registry.toml"))["packages"]
    filter!(packages) do (key, value)
        value["name"] == pkg
    end
    # For Julia >= 1.4 this can be simplified with the `only` function.
    always_assert(length(packages) == 1)
    uuid = convert(String, first(keys(packages)))
    # Also need to find out the package repository.
    package = TOML.parsefile(
        joinpath(registry_path, packages[uuid]["path"], "Package.toml")
    )
    repo = convert(String, package["repo"])
    subdir = convert(String, get(package, "subdir", ""))
    if version === nothing
        tree_hash = nothing
    else
        versions = TOML.parsefile(
            joinpath(registry_path, packages[uuid]["path"], "Versions.toml")
        )
        tree_hash = convert(String, versions[string(version)]["git-tree-sha1"])
    end
    return (; uuid=uuid, repo=repo, subdir=subdir, tree_hash=tree_hash)
end

#####
##### AutoMerge comment
#####

# The AutoMerge comment is divided into numbered sections.
# Besides the "AutoMerge Guidelines which are not met" and "AutoMerge Guidelines have all passed!"
# sections, we keep these minimally customized, and instead simply include or exclude
# whole sections depending on the context. This way, users can understand the message
# without necessarily reading the details of each section each time.
# We hope they will at least read the section titles, and if they aren't
# familiar, hopefully they will also read the sections themselves.

function _comment_bot_intro()
    return string("Hello, I am an automated registration bot.",
    " I help manage the registration process by checking your registration against a set of ","[AutoMerge guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/). ",
    "If all these guidelines are met, this pull request will be merged automatically, completing your registration. It is **strongly recommended** to follow the guidelines, since otherwise ",
    "the pull request needs to be manually reviewed and merged by a human.\n\n")
end

function _new_package_section(n)
    return string("## $n. New package registration", "\n\n",
    "Please make sure that you have read the ",
    "[package naming guidelines](https://pkgdocs.julialang.org/v1/creating-packages/#Package-naming-rules).\n\n")
end

function _what_next_if_fail(n; point_to_slack=false)
    msg = """
    ## $n. *Needs action*: here's what to do next

    1. Please try to update your package to conform to these guidelines. The [General registry's README](https://github.com/JuliaRegistries/General/blob/master/README.md) has an FAQ that can help figure out how to do so."""
    msg = string(msg, "\n",
        "2. After you have fixed the AutoMerge issues, simply retrigger Registrator, the same way you did in the initial registration. This will automatically update this pull request. You do not need to change the version number in your `Project.toml` file (unless the AutoMerge issue is that you skipped a version number).",
        "\n\n",
        "If you need help fixing the AutoMerge issues, or want your pull request to be manually merged instead, please post a comment explaining what you need help with or why you would like this pull request to be manually merged.")

    if point_to_slack
        msg = string(msg, " Then, send a message to the `#pkg-registration` channel in the [public Julia Slack](https://julialang.org/slack/) for better visibility.")
    end
    msg = string(msg, "\n\n")
    return msg
end

function _automerge_guidelines_failed_section_title(n)
    return "## $n. [AutoMerge Guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/) which are not met ❌\n\n"
end

function _automerge_guidelines_passed_section_title(n)
    "## $n. [AutoMerge Guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/) are all met! ✅\n\n"
end

function _comment_noblock(n)
    result = string(
        "## $n. To pause or stop registration\n\n",
        "If you want to prevent this pull request from ",
        "being auto-merged, simply leave a comment. ",
        "If you want to post a comment without blocking ",
        "auto-merging, you must include the text ",
        "`[noblock]` in your comment.",
        "\n\n_Tip: You can edit blocking comments to add `[noblock]` ",
        "in order to unblock auto-merging._\n\n",
    )
    return result
end

function comment_text_pass(
    ::NewVersion, suggest_onepointzero::Bool, version::VersionNumber, is_jll::Bool; new_package_waiting_period
)
    # Need to know this ahead of time to get the section numbers right
    suggest_onepointzero &= version < v"1.0.0"
    result = string(
        _comment_bot_intro(),
        _automerge_guidelines_passed_section_title(1),
        "Your new version registration met all of the ",
        "guidelines for auto-merging and is scheduled to ",
        "be merged in the next round (~20 minutes).\n\n",
        _onepointzero_suggestion(2, suggest_onepointzero, version),
        _comment_noblock(suggest_onepointzero ? 3 : 2),
        "<!-- [noblock] -->",
    )
    return result
end

function comment_text_pass(
    ::NewPackage, suggest_onepointzero::Bool, version::VersionNumber, is_jll::Bool; new_package_waiting_period
)
    suggest_onepointzero &= version < v"1.0.0"
    if is_jll
        result = string(
            _comment_bot_intro(),
            _automerge_guidelines_passed_section_title(1),
            "Your new `_jll` package registration met all of the ",
            "guidelines for auto-merging and is scheduled to ",
            "be merged in the next round (~20 minutes).\n\n",
            _onepointzero_suggestion(2, suggest_onepointzero, version),
            _comment_noblock(suggest_onepointzero ? 3 : 2),
            "<!-- [noblock] -->",
        )
    else
        result = string(
            _comment_bot_intro(),
            _new_package_section(1),
            _automerge_guidelines_passed_section_title(2),
            "Your new package registration met all of the ",
            "guidelines for auto-merging and is scheduled to ",
            "be merged when the mandatory waiting period ($new_package_waiting_period) has elapsed.\n\n",
            _onepointzero_suggestion(3, suggest_onepointzero, version),
            _comment_noblock(suggest_onepointzero ? 4 : 3),
            "<!-- [noblock] -->",
        )
    end
    return result
end

function comment_text_fail(
    ::NewPackage,
    reasons::Vector{String},
    suggest_onepointzero::Bool,
    version::VersionNumber;
    point_to_slack::Bool=false,
)
    suggest_onepointzero &= version < v"1.0.0"
    reasons_formatted = string(join(string.("- ", reasons), "\n"), "\n\n")
    result = string(
        _comment_bot_intro(),
        _new_package_section(1),
        _automerge_guidelines_failed_section_title(2),
        reasons_formatted,
        _what_next_if_fail(3; point_to_slack=point_to_slack),
        _onepointzero_suggestion(4, suggest_onepointzero, version),
        _comment_noblock(suggest_onepointzero ? 5 : 4),
        "<!-- [noblock] -->",
    )
    return result
end

function comment_text_fail(
    ::NewVersion,
    reasons::Vector{String},
    suggest_onepointzero::Bool,
    version::VersionNumber;
    point_to_slack::Bool=false,
)
    suggest_onepointzero &= version < v"1.0.0"
    reasons_formatted = string(join(string.("- ", reasons), "\n"), "\n\n")
    result = string(
        _comment_bot_intro(),
        _automerge_guidelines_failed_section_title(1),
        reasons_formatted,
        _what_next_if_fail(2; point_to_slack=point_to_slack),
        _onepointzero_suggestion(3, suggest_onepointzero, version),
        _comment_noblock(suggest_onepointzero ? 4 : 3),
        "<!-- [noblock] -->",
    )
    return result
end

is_julia_stdlib(name) = name in julia_stdlib_list()

function julia_stdlib_list()
    stdlib_list = readdir(Pkg.Types.stdlib_dir())
    # Before Julia v1.6 Artifacts.jl isn't a standard library, but
    # we want to include it because JLL packages depend on the empty
    # placeholder https://github.com/JuliaPackaging/Artifacts.jl
    # in older versions for compatibility.
    if VERSION < v"1.6.0"
        push!(stdlib_list, "Artifacts")
    end
    return stdlib_list
end

function now_utc()
    utc = TimeZones.tz"UTC"
    return Dates.now(utc)
end

function _onepointzero_suggestion(n, suggest_onepointzero::Bool, version::VersionNumber)
    if suggest_onepointzero && version < v"1.0.0"
        result = string(
            "## $n. Declare v1.0?\n\n",
            "On a separate note, I see that you are registering ",
            "a release with a version number of the form ",
            "`v0.X.Y`.\n\n",
            "Does your package have a stable public API? ",
            "If so, then it's time for you to register version ",
            "`v1.0.0` of your package. ",
            "(This is not a requirement. ",
            "It's just a recommendation.)\n\n",
            "If your package does not yet have a stable public ",
            "API, then of course you are not yet ready to ",
            "release version `v1.0.0`.\n\n",
        )
        return result
    else
        return ""
    end
end

function time_is_already_in_utc(dt::Dates.DateTime)
    utc = TimeZones.tz"UTC"
    return TimeZones.ZonedDateTime(dt, utc; from_utc=true)
end

"""
    get_all_non_jll_package_names(registry_dir::AbstractString) -> Vector{String}
    get_all_non_jll_package_names(registry::RegistryInstance) -> Vector{String}

Given either:

- a path to a directory holding an uncompressed registry

or

- a `RegistryInstance` object (from [RegistryInstances.jl](https://github.com/GunnarFarneback/RegistryInstances.jl)) associated to a registry,

returns a sorted list of the names of Julia's standard libraries
and all the non-JLL packages defined in that registry.
"""
function get_all_non_jll_package_names(registry_dir::AbstractString)
    # Mimic the structure of a RegistryInstance
    list = TOML.parsefile(joinpath(registry_dir, "Registry.toml"))["packages"]
    registry = (; pkgs=Dict(k => (; name=v["name"]) for (k,v) in pairs(list)))
    return get_all_non_jll_package_names(registry)
end

# Generic method intended for RegistryInstance (without taking on the dependency,
# which is only valid on Julia 1.7+)
function get_all_non_jll_package_names(registry)
    packages = [entry.name for entry in values(registry.pkgs)]
    append!(packages, (RegistryTools.get_stdlib_name(x) for x in values(RegistryTools.stdlibs())))
    sort!(packages)
    filter!(x -> !endswith(x, "_jll"), packages)
    unique!(packages)
    return packages
end


function has_label(labels, target)
    # No labels? Then no
    isnothing(labels) && return false
    for label in labels
        if label.name === target
            # found it
            @debug "Found `$(target)` label"
            return true
        end
    end
    # Did not find it
    return false
end

const PACKAGE_AUTHOR_APPROVED_LABEL = "Override AutoMerge: package author approved"

has_package_author_approved_label(labels) = has_label(labels, PACKAGE_AUTHOR_APPROVED_LABEL)

"""
    try_remove_label(api, repo, issue, label)

Uses `GitHub.remove_label` to remove the label, if it exists.
Differs from the upstream functionality by not erroring if we receive a 404
response indicating the label did not exist.

Returns whether or not the label was removed.
"""
function try_remove_label(api, repo, issue, label; options...)
    label = HTTP.escapeuri(label)
    path = "/repos/$(GitHub.name(repo))/issues/$(GitHub.name(issue))/labels/$(GitHub.name(label))"
    @debug "Removing label" path
    r = GitHub.remove_label(api, repo, issue, label; handle_error = false, options...)
    r.status == 404 && return false
    GitHub.handle_response_error(r)  # throw errors in other cases if necessary
    return true
end

function maybe_create_label(api, repo, name::String, color::String, description::String; options...)
    path = "/repos/$(GitHub.name(repo))/labels"
    result = GitHub.gh_post(api, path; params=(; name=name, color=color, description=description), handle_error=false, options...)
    @debug "Response from `maybe_create_label`" result
    return result.status == 201
end

"""
    maybe_create_blocked_label(api, repo)

Add the label `$BLOCKED_LABEL` to the repo if it doesn't already exist.

Returns whether or not it created the label.
"""
maybe_create_blocked_label(api, repo; options...) = maybe_create_label(api, repo, BLOCKED_LABEL, "ff0000", "PR blocked by one or more comments lacking the string [noblock]."; options...)
