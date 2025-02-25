using HTTP: HTTP

# TODO: change this value to `true` once we are ready to re-enable the
# "Require `[compat]` for stdlib dependencies" feature.
#
# For example, we might consider changing this value to `true`
# once Julia 1.6 is no longer the LTS.
const _AUTOMERGE_REQUIRE_STDLIB_COMPAT = false

const guideline_registry_consistency_tests_pass = Guideline(;
    info="Registry consistency tests",
    docs=nothing,
    check=data ->
        meets_registry_consistency_tests_pass(data.registry_head, data.registry_deps),
)

function meets_registry_consistency_tests_pass(
    registry_head::String, registry_deps::Vector{String}
)
    try
        RegistryCI.test(registry_head; registry_deps=registry_deps)
        return true, ""
    catch ex
        @error "" exception = (ex, catch_backtrace())
    end
    return false, "The registry consistency tests failed"
end

const guideline_compat_for_julia = Guideline(;
    info="Compat with upper bound for julia",
    docs=string(
        "There is an upper-bounded `[compat]` entry for `julia` that ",
        "only includes a finite number of breaking releases of Julia.",
    ),
    check=data -> meets_compat_for_julia(data.registry_head, data.pkg, data.version),
)

function meets_compat_for_julia(working_directory::AbstractString, pkg, version)
    package_relpath = get_package_relpath_in_registry(;
        package_name=pkg, registry_path=working_directory
    )
    compat_file = joinpath(working_directory, package_relpath, "Compat.toml")
    compat = maybe_parse_toml(compat_file)
    # Go through all the compat entries looking for the julia compat
    # of the new version. When found, test
    # 1. that it is a bounded range,
    # 2. that the upper bound is not 2 or higher,
    # 3. that the range includes at least one 1.x version.
    for version_range in keys(compat)
        if version in Pkg.Types.VersionRange(version_range)
            if haskey(compat[version_range], "julia")
                julia_compat = Pkg.Types.VersionSpec(compat[version_range]["julia"])
                if !isempty(
                    intersect(
                        julia_compat, Pkg.Types.VersionSpec("$(typemax(Base.VInt))-*")
                    ),
                )
                    return false, "The compat entry for `julia` is unbounded."
                elseif !isempty(intersect(julia_compat, Pkg.Types.VersionSpec("2-*")))
                    return false,
                    "The compat entry for `julia` has an upper bound of 2 or higher."
                elseif isempty(intersect(julia_compat, Pkg.Types.VersionSpec("1")))
                    # For completeness, although this seems rather
                    # unlikely to occur.
                    return false,
                    "The compat entry for `julia` doesn't include any 1.x version."
                else
                    return true, ""
                end
            end
        end
    end

    return false, "There is no compat entry for `julia`."
end

const guideline_compat_for_all_deps = Guideline(;
    info="Compat (with upper bound) for all dependencies",
    docs=string(
        "Dependencies: All dependencies should have `[compat]` entries that ",
        "are upper-bounded and only include a finite number of breaking releases. ",
        "For more information, please see the \"Upper-bounded `[compat]` entries\" subsection under \"Additional information\" below.",
    ),
    check=data -> meets_compat_for_all_deps(data.registry_head, data.pkg, data.version),
)

function compat_violation_message(bad_dependencies)
    return string(
        "The following dependencies do not have a `[compat]` entry ",
        "that is upper-bounded and only includes a finite number ",
        "of breaking releases: ",
        join(bad_dependencies, ", "),
        # Note the indentation here is important for the proper formatting within a bulleted list later
        """

            <details><summary>Extended explanation</summary>

            Your package has a Project.toml file which might look something like the following:

            ```toml
            name = "YourPackage"
            uuid = "random id"
            authors = ["Author Names"]
            version = "major.minor"

            [deps]
            # Package dependencies
            # ...

            [compat]
            # ...
            ```

            Every package listed in `[deps]`, along with `julia` itself, must also be listed under `[compat]` (if you don't have a `[compat]` section, make one!). See the [Pkg docs](https://pkgdocs.julialang.org/v1/compatibility/) for the syntax for compatibility bounds, and [this documentation](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/#Upper-bounded-%5Bcompat%5D-entries) for more on the kinds of compat bounds required for AutoMerge.

            </details>
        """
    )

end

function meets_compat_for_all_deps(working_directory::AbstractString, pkg, version)
    package_relpath = get_package_relpath_in_registry(;
        package_name=pkg, registry_path=working_directory
    )
    compat_file = joinpath(working_directory, package_relpath, "Compat.toml")
    deps_file = joinpath(working_directory, package_relpath, "Deps.toml")
    compat = maybe_parse_toml(compat_file)
    deps = maybe_parse_toml(deps_file)
    # First, we construct a Dict in which the keys are the package's
    # dependencies, and the value is always false.
    dep_has_compat_with_upper_bound = Dict{String,Bool}()
    for version_range in keys(deps)
        if version in Pkg.Types.VersionRange(version_range)
            for name in keys(deps[version_range])
                if _AUTOMERGE_REQUIRE_STDLIB_COMPAT
                    debug_msg = "Found a new (non-JLL) dependency: $(name)"
                    apply_compat_requirement = !is_jll_name(name)
                else
                    debug_msg = "Found a new (non-stdlib non-JLL) dependency: $(name)"
                    apply_compat_requirement = !is_jll_name(name) && !is_julia_stdlib(name)
                end
                if apply_compat_requirement
                    @debug debug_msg
                    dep_has_compat_with_upper_bound[name] = false
                end
            end
        end
    end
    # Now, we go through all the compat entries. If a dependency has a compat
    # entry with an upper bound, we change the corresponding value in the Dict
    # to true.
    for version_range in keys(compat)
        if version in Pkg.Types.VersionRange(version_range)
            for (name, value) in compat[version_range]
                if value isa Vector
                    if !isempty(value)
                        value_ranges = Pkg.Types.VersionRange.(value)
                        each_range_has_upper_bound = _has_upper_bound.(value_ranges)
                        if all(each_range_has_upper_bound)
                            @debug(
                                "Dependency \"$(name)\" has compat entries that all have upper bounds"
                            )
                            dep_has_compat_with_upper_bound[name] = true
                        end
                    end
                else
                    value_range = Pkg.Types.VersionRange(value)
                    if _has_upper_bound(value_range)
                        @debug(
                            "Dependency \"$(name)\" has a compat entry with an upper bound"
                        )
                        dep_has_compat_with_upper_bound[name] = true
                    end
                end
            end
        end
    end
    meets_this_guideline = all(values(dep_has_compat_with_upper_bound))
    if meets_this_guideline
        return true, ""
    else
        bad_dependencies = Vector{String}()
        for name in keys(dep_has_compat_with_upper_bound)
            if !(dep_has_compat_with_upper_bound[name])
                @error(
                    "Dependency \"$(name)\" does not have a compat entry that has an upper bound"
                )
                push!(bad_dependencies, name)
            end
        end
        sort!(bad_dependencies)
        message = compat_violation_message(bad_dependencies)
        return false, message
    end
end

const guideline_patch_release_does_not_narrow_julia_compat = Guideline(;
    info="If it is a patch release on a post-1.0 package, then it does not narrow the `[compat]` range for `julia`.",
    check=data -> meets_patch_release_does_not_narrow_julia_compat(
        data.pkg,
        data.version;
        registry_head=data.registry_head,
        registry_master=data.registry_master,
    ),
)

function meets_patch_release_does_not_narrow_julia_compat(
    pkg::String, new_version::VersionNumber; registry_head::String, registry_master::String
)
    old_version = latest_version(pkg, registry_master)
    if old_version.major != new_version.major || old_version.minor != new_version.minor
        # Not a patch release.
        return true, ""
    end
    julia_compats_for_old_version = julia_compat(pkg, old_version, registry_master)
    julia_compats_for_new_version = julia_compat(pkg, new_version, registry_head)
    if Set(julia_compats_for_old_version) == Set(julia_compats_for_new_version)
        return true, ""
    end
    meets_this_guideline = range_did_not_narrow(
        julia_compats_for_old_version, julia_compats_for_new_version
    )
    if meets_this_guideline
        return true, ""
    else
        if (old_version >= v"1") || (new_version >= v"1")
            msg = string(
                "A patch release is not allowed to narrow the ",
                "supported ranges of Julia versions. ",
                "The ranges have changed from ",
                "$(julia_compats_for_old_version) ",
                "(in $(old_version)) ",
                "to $(julia_compats_for_new_version) ",
                "(in $(new_version)).",
            )
            return false, msg
        else
            @info("Narrows Julia compat, but it's OK since package is pre-1.0")
            return true, ""
        end
    end
end

const _AUTOMERGE_NEW_PACKAGE_MINIMUM_NAME_LENGTH = 5

const guideline_name_length = Guideline(;
    info="Name not too short",
    docs="The name is at least $(_AUTOMERGE_NEW_PACKAGE_MINIMUM_NAME_LENGTH) characters long.",
    check=data -> meets_name_length(data.pkg),
)

function meets_name_length(pkg)
    meets_this_guideline = length(pkg) >= _AUTOMERGE_NEW_PACKAGE_MINIMUM_NAME_LENGTH
    if meets_this_guideline
        return true, ""
    else
        return false,
        "Name is not at least $(_AUTOMERGE_NEW_PACKAGE_MINIMUM_NAME_LENGTH) characters long"
    end
end

const guideline_name_ascii = Guideline(;
    info="Name is composed of ASCII characters only.",
    check=data -> meets_name_ascii(data.pkg),
)

function meets_name_ascii(pkg)
    if isascii(pkg)
        return true, ""
    else
        return false, "Name is not ASCII"
    end
end

const guideline_julia_name_check = Guideline(;
    info="Name does not include \"julia\", start with \"Ju\", or end with \"jl\".",
    check=data -> meets_julia_name_check(data.pkg),
)

function meets_julia_name_check(pkg)
    if occursin("julia", lowercase(pkg))
        return false,
        "Lowercase package name $(lowercase(pkg)) contains the string \"julia\"."
    elseif startswith(pkg, "Ju")
        return false, "Package name starts with \"Ju\"."
    elseif endswith(lowercase(pkg), "jl")
        return false, "Lowercase package name $(lowercase(pkg)) ends with \"jl\"."
    else
        return true, ""
    end
end

damerau_levenshtein(name1, name2) = StringDistances.DamerauLevenshtein()(name1, name2)
function sqrt_normalized_vd(name1, name2)
    return VisualStringDistances.visual_distance(name1, name2; normalize=x -> 5 + sqrt(x))
end

# This check cannot be overridden, since it's important for registry integrity
const guideline_name_match_check = Guideline(;
    info = "Name does not match the name of any existing package names (up-to-case)",
    docs = "Packages must not match the name of existing package up-to-case, since on case-insensitive filesystems, this will break the registry.",
    check=data -> meets_name_match_check(data.pkg, data.registry_master))

function meets_name_match_check(pkg_name::AbstractString, registry_master::AbstractString)
    other_packages = get_all_non_jll_package_names(registry_master)
    return meets_name_match_check(pkg_name, other_packages)
end

function meets_name_match_check(
    pkg_name::AbstractString,
    other_packages::Vector;
)
    for other_pkg in other_packages
        if pkg_name == other_pkg
            # We short-circuit in this case; more information doesn't help.
            return (false, "Package name already exists in the registry.")
        elseif lowercase(pkg_name) == lowercase(other_pkg)
            return (false, "Package name matches existing package name $(other_pkg) up-to-case.")
        end
    end
    return (true, "")
end

# This check checks for an explanation of why a breaking change is breaking
const guideline_breaking_explanation = Guideline(;
    info = "Release notes have not been provided that explain why this is a breaking change.",
    docs = "If this is a breaking change, release notes must be given that explain why this is a breaking change (i.e. mention \"breaking\" or \"changelog\"). To update the release notes, please see the \"Providing and updating release notes\" subsection under \"Additional information\" below.",
    check=data -> meets_breaking_explanation_check(data))

function meets_breaking_explanation_check(data::GitHubAutoMergeData)
    # Look up PR here in case the labels are slow to be applied by the Registrator bot
    # which decides whether to add the BREAKING label
    pr = GitHub.pull_request(data.api, data.registry, data.pr.number; auth=data.auth)
    return meets_breaking_explanation_check(pr.labels, pr.body, data.version)
end

function breaking_explanation_message(has_release_notes, version::VersionNumber)
    msg = if has_release_notes
        """
        This is a breaking change, but the release notes do not mention it. Please add a mention of the breaking change to the release notes (use the words \"breaking\" or \"changelog\").
        """
    else
        """
        This is a breaking change, but no release notes have been provided. Please add release notes that explain the breaking change.
        """
    end
    if version < v"1.0.0"
        msg *= """
        Given this is a pre-v1.0.0 release, you may have not intended to make a breaking change release. [More information](https://pkgdocs.julialang.org/v1/compatibility/#compat-pre-1.0) on Julia's handling of pre-v1.0.0 versioning.
        """
    end
    msg *= """
        <details><summary>Example of adding release notes with breaking notice</summary>

        If you are using the comment bot `@JuliaRegistrator`, you can add release notes to this registration by re-triggering registration while specifying release notes:

        ```
        @JuliaRegistrator register

        Release notes:

        ## Breaking changes

        - Explanation of breaking change, ideally with upgrade tips
        - ...
        ```

        If you are using JuliaHub, trigger registration the same way you did the first time, but enter release notes that specify the breaking changes.

        Either way, you need to mention the words \"breaking\" or \"changelog\", even if it is just to say "there are no breaking changes", or "see the changelog".
        </details>
    """
    return msg
end

function meets_breaking_explanation_check(labels::Vector, body::AbstractString, version::VersionNumber)
    if has_label(labels, BREAKING_LABEL)
        release_notes = get_release_notes(body)
        if release_notes === nothing
            msg = breaking_explanation_message(false, version)
            return false, msg
        elseif !occursin(r"breaking|changelog", lowercase(release_notes))
            msg = breaking_explanation_message(true, version)
            return false, msg
        else
            return true, ""
        end
    else
        return true, ""
    end
end

function get_release_notes(body::AbstractString)
    pattern = r"<!-- BEGIN RELEASE NOTES -->(?s)(.*?)<!-- END RELEASE NOTES -->"
    m = match(pattern, body)
    return m === nothing ? nothing : m.captures[1]
end

# This check looks for similar (but not exactly matching) names. It can be
# overridden by a label.
const guideline_distance_check = Guideline(;
    info="Name is not too similar to existing package names",
    docs="""
To prevent confusion between similarly named packages, the names of new packages must also satisfy the following three checks: (for more information, please see the \"Name similarity distance check\" subsection under \"Additional information\" below)
    - the [Damerau–Levenshtein
      distance](https://en.wikipedia.org/wiki/Damerau%E2%80%93Levenshtein_distance)
      between the package name and the name of any existing package must be at
      least 3.
    - the Damerau–Levenshtein distance between the lowercased version of a
      package name and the lowercased version of the name of any existing
      package must be at least 2.
    - and a visual distance from
      [VisualStringDistances.jl](https://github.com/ericphanson/VisualStringDistances.jl)
      between the package name and any existing package must exceeds a certain
      a hand-chosen threshold (currently 2.5).

These checks can be overridden by applying a label `Override AutoMerge: name similarity is okay` to the PR. This will turn off the check as long as the label is applied to the PR.
  """,
    check=data -> meets_distance_check(data.pkg, data.registry_master),
)

function meets_distance_check(
    pkg_name::AbstractString, registry_master::AbstractString; kwargs...
)
    other_packages = get_all_non_jll_package_names(registry_master)
    return meets_distance_check(pkg_name, other_packages; kwargs...)
end

function meets_distance_check(
    pkg_name::AbstractString,
    other_packages::Vector;
    DL_lowercase_cutoff=1,
    DL_cutoff=2,
    sqrt_normalized_vd_cutoff=2.5,
    comment_collapse_cutoff=10,
)
    problem_messages = Tuple{String,Tuple{Float64,Float64,Float64}}[]
    for other_pkg in other_packages
        if lowercase(pkg_name) == lowercase(other_pkg)
            # We handle this case in `meets_name_match_check`
            continue
        else
            msg = ""

            # Distance check 1: DL distance
            dl = damerau_levenshtein(pkg_name, other_pkg)
            if dl <= DL_cutoff
                msg = string(
                    msg,
                    " Damerau-Levenshtein distance $dl is at or below cutoff of $(DL_cutoff).",
                )
            end

            # Distance check 2: lowercase DL distance
            dl_lowercase = damerau_levenshtein(lowercase(pkg_name), lowercase(other_pkg))
            if dl_lowercase <= DL_lowercase_cutoff
                msg = string(
                    msg,
                    " Damerau-Levenshtein distance $(dl_lowercase) between lowercased names is at or below cutoff of $(DL_lowercase_cutoff).",
                )
            end

            # Distance check 3: normalized visual distance,
            # gated by a `dl` check for speed.
            if (sqrt_normalized_vd_cutoff > 0 && dl <= 4)
                nrm_vd = sqrt_normalized_vd(pkg_name, other_pkg)
                if nrm_vd <= sqrt_normalized_vd_cutoff
                    msg = string(
                        msg,
                        " Normalized visual distance ",
                        Printf.@sprintf("%.2f", nrm_vd),
                        " is at or below cutoff of ",
                        Printf.@sprintf("%.2f", sqrt_normalized_vd_cutoff),
                        ".",
                    )
                end
            else
                # need to choose something for sorting purposes
                nrm_vd = 10.0
            end

            if msg != ""
                # We must have found a clash.
                push!(
                    problem_messages,
                    (string("Similar to $(other_pkg).", msg), (dl, dl_lowercase, nrm_vd)),
                )
            end
        end
    end

    isempty(problem_messages) && return (true, "")
    sort!(problem_messages; by=Base.tail)
    message = string(
        "Package name similar to $(length(problem_messages)) existing package",
        length(problem_messages) > 1 ? "s" : "",
        ".\n",
    )
    use_spoiler = length(problem_messages) > comment_collapse_cutoff
    # we indent each line by two spaces in all the following
    # so that it nests properly in the outer list.
    if use_spoiler
        message *= """
                     <details>
                     <summary>Similar package names</summary>

                   """
    end
    numbers = string.("  ", 1:length(problem_messages))
    message *= join(join.(zip(numbers, first.(problem_messages)), Ref(". ")), '\n')
    if use_spoiler
        message *= "\n\n  </details>\n"
    end
    return (false, message)
end

# Used in `pull_request_build` to determine if we should
# perform the distance check or not.
# We expect to be passed the `labels` field of a PullRequest:
# <https://github.com/JuliaWeb/GitHub.jl/blob/d24bd6798609ae356db308d65577e99aad0cf432/src/issues/pull_requests.jl#L33>
function perform_distance_check(labels)
    # No labels? Do the check
    isnothing(labels) && return true
    for label in labels
        if label.name === "Override AutoMerge: name similarity is okay"
            # found the override! Skip the check
            @debug "Found label; skipping distance check" label.name
            return false
        end
    end
    # Did not find the override. Perform the check.
    return true
end

const guideline_name_identifier = Guideline(;
    info="Name is a Julia identifier",
    docs=string(
        "The package name should be a valid Julia identifier (according to `Base.isidentifier`).",
    ),
    check=data -> meets_name_is_identifier(data.pkg),
)

function meets_name_is_identifier(pkg)
    if Base.isidentifier(pkg)
        return true, ""
    else
        return false, "The package's name ($pkg) is not a valid Julia identifier according to `Base.isidentifier`. Typically this means it contains `-` or other characters that can't be used in defining a variable name or module. The package must be renamed to be registered."
    end
end

const guideline_normal_capitalization = Guideline(;
    info="Normal capitalization",
    docs=string(
        "The package name should start with an upper-case letter, ",
        "contain only ASCII alphanumeric characters, ",
        "and contain at least one lowercase letter.",
    ),
    check=data -> meets_normal_capitalization(data.pkg),
)

function meets_normal_capitalization(pkg)
    # We intentionally do not use `\w` in this regex.
    # `\w` includes underscores, but we don't want to include underscores.
    # So, instead of `\w`, we use `[A-Za-z0-9]`.
    meets_this_guideline = occursin(r"^[A-Z][A-Za-z0-9]*[a-z][A-Za-z0-9]*[0-9]?$", pkg)
    if meets_this_guideline
        return true, ""
    else
        return false,
        "Name does not meet all of the following: starts with an upper-case letter, ASCII alphanumerics only, not all letters are upper-case."
    end
end

const guideline_repo_url_requirement = Guideline(;
    info="Repo URL ends with `/PackageName.jl.git`.",
    check=data -> meets_repo_url_requirement(data.pkg; registry_head=data.registry_head),
)

function meets_repo_url_requirement(pkg::String; registry_head::String)
    package_relpath = get_package_relpath_in_registry(;
        package_name=pkg, registry_path=registry_head
    )
    package_toml_parsed = Pkg.TOML.parsefile(
        joinpath(registry_head, package_relpath, "Package.toml")
    )

    url = package_toml_parsed["repo"]
    subdir = get(package_toml_parsed, "subdir", "")
    is_subdirectory_package = occursin(r"[A-Za-z0-9]", subdir)
    meets_this_guideline = url_has_correct_ending(url, pkg)

    if is_subdirectory_package
        return true, "" # we do not apply this check if the package is a subdirectory package
    end
    if meets_this_guideline
        return true, ""
    end
    return false, "Repo URL does not end with /name.jl.git, where name is the package name"
end

function _invalid_sequential_version(reason::AbstractString)
    return false, "Does not meet sequential version number guideline: $(reason). $PACKAGE_AUTHOR_APPROVAL_INSTRUCTIONS", :invalid
end

function _valid_change(old_version::VersionNumber, new_version::VersionNumber)
    diff = difference(old_version, new_version)
    if !(diff isa VersionNumber)
        if diff isa ErrorCannotComputeVersionDifference
            old_msg = diff.msg
        else
            T = typeof(diff)
            old_msg = "Unknown diff type: $(T)"
        end
        new_msg = "Error occured while trying to compute version bump. Message: $(old_msg)"
        return _invalid_sequential_version(new_msg)
    end
    @debug("Difference between versions: ", old_version, new_version, diff)
    if diff == v"0.0.1"
        return true, "", :patch
    elseif diff == v"0.1.0"
        return true, "", :minor
    elseif diff == v"1.0.0"
        return true, "", :major
    else
        return _invalid_sequential_version("increment is not one of: 0.0.1, 0.1.0, 1.0.0")
    end
end

const PACKAGE_AUTHOR_APPROVAL_INSTRUCTIONS = string(
    "**If this was not a mistake and you wish to merge this PR anyway, ",
    "write a comment that says `[merge approved]`.**")

const guideline_sequential_version_number = Guideline(;
    info="Sequential version number",
    docs=string(
        "Version number: Should be a standard increment and not skip versions. ",
        "This means incrementing the patch/minor/major version with +1 compared to ",
        "previous (if any) releases. ",
        "If, for example, `1.0.0` and `1.1.0` are existing versions, ",
        "valid new versions are `1.0.1`, `1.1.1`, `1.2.0` and `2.0.0`. ",
        "Invalid new versions include `1.0.2` (skips `1.0.1`), ",
        "`1.3.0` (skips `1.2.0`), `3.0.0` (skips `2.0.0`) etc.",
    ),
    check=data -> meets_sequential_version_number(
        data.pkg,
        data.version;
        registry_head=data.registry_head,
        registry_master=data.registry_master,
    ),
)

function meets_sequential_version_number(
    existing::Vector{VersionNumber}, ver::VersionNumber
)
    always_assert(!isempty(existing))
    if ver in existing
        return _invalid_sequential_version("version $ver already exists")
    end
    issorted(existing) || (existing = sort(existing))
    idx = searchsortedlast(existing, ver)
    idx > 0 || return _invalid_sequential_version(
        "version $ver less than least existing version $(existing[1])"
    )
    prv = existing[idx]
    always_assert(ver != prv)
    nxt = if thismajor(ver) != thismajor(prv)
        nextmajor(prv)
    elseif thisminor(ver) != thisminor(prv)
        nextminor(prv)
    else
        nextpatch(prv)
    end
    ver <= nxt || return _invalid_sequential_version("version $ver skips over $nxt")
    return _valid_change(prv, ver)
end

function meets_sequential_version_number(
    pkg::String, new_version::VersionNumber; registry_head::String, registry_master::String
)
    _all_versions = all_versions(pkg, registry_master)
    return meets_sequential_version_number(_all_versions, new_version)
end

const guideline_standard_initial_version_number = Guideline(;
    info="Standard initial version number. Must be one of: `0.0.1`, `0.1.0`, `1.0.0`, or `X.0.0`.",
    check=data -> meets_standard_initial_version_number(data.version),
)

function meets_standard_initial_version_number(version)
    meets_this_guideline =
        version == v"0.0.1" ||
        version == v"0.1.0" ||
        version == v"1.0.0" ||
        _is_x_0_0(version)
    if meets_this_guideline
        return true, ""
    else
        return false, "Version number is not 0.0.1, 0.1.0, 1.0.0, or X.0.0"
    end
end

function _is_x_0_0(version::VersionNumber)
    result = (version.major >= 1) && (version.minor == 0) && (version.patch == 0)
    return result
end

const guideline_version_number_no_prerelease = Guideline(;
    info="No prerelease data in the version number",
    docs = "Version number is not allowed to contain prerelease data",
    check = data -> meets_version_number_no_prerelease(
        data.version,
    ),
)
const guideline_version_number_no_build = Guideline(;
    info="No build data in the version number",
    docs = "Version number is not allowed to contain build data",
    check = data -> meets_version_number_no_build(
        data.version,
    ),
)
function meets_version_number_no_prerelease(version::VersionNumber)
    if isempty(version.prerelease)
        return true, ""
    else
        return false, "Version number is not allowed to contain prerelease data"
    end
end
function meets_version_number_no_build(version::VersionNumber)
    if isempty(version.build)
        return true, ""
    else
        return false, "Version number is not allowed to contain build data"
    end
end

const guideline_code_can_be_downloaded = Guideline(;
    info="Code can be downloaded.",
    check=data -> meets_code_can_be_downloaded(
        data.registry_head,
        data.pkg,
        data.version,
        data.pr;
        pkg_code_path=data.pkg_code_path,
    ),
)

function _find_lowercase_duplicates(v)
    elts = Dict{String, String}()
    for x in v
        lower_x = lowercase(x)
        if haskey(elts, lower_x)
            return (elts[lower_x], x)
        else
            elts[lower_x] = x
        end
    end
    return nothing
end

const DISALLOWED_CHARS = ['/', '<', '>', ':', '"', '/', '\\', '|', '?', '*', Char.(0:31)...]

const DISALLOWED_NAMES = ["CON", "PRN", "AUX", "NUL",
                          ("COM$i" for i in 1:9)...,
                          ("LPT$i" for i in 1:9)...]

function meets_file_dir_name_check(name)
    # https://stackoverflow.com/a/31976060
    idx = findfirst(n -> occursin(n, name), DISALLOWED_CHARS)
    if idx !== nothing
        return false, "contains character $(DISALLOWED_CHARS[idx]) which may not be valid as a file or directory name on some platforms"
    end

    base, ext = splitext(name)
    if uppercase(name) in DISALLOWED_NAMES || uppercase(base) in DISALLOWED_NAMES
        return false, "is not allowed"
    end
    if endswith(name, ".") || endswith(name, r"\s")
        return false, "ends with `.` or space"
    end
    return true, ""
end

function meets_src_names_ok(pkg_code_path)
    src = joinpath(pkg_code_path, "src/")
    isdir(src) || return false, "`src` directory not found"
    for (root, dirs, files) in walkdir(src)
        files_dirs = Iterators.flatten((files, dirs))
        result = _find_lowercase_duplicates(files_dirs)
        if result !== nothing
            x = joinpath(root, result[1])
            y = joinpath(root, result[2])
            return false, "Found files or directories in `src` which will cause problems on case insensitive filesystems: `$x` and `$y`"
        end

        for f in files_dirs
            ok, msg = meets_file_dir_name_check(f)
            if !ok
                return false, "the name of file or directory $(joinpath(root, f)) $(msg). This can cause problems on some operating systems or file systems."
            end
        end
    end
    return true, ""
end

const guideline_src_names_OK = Guideline(;
    info="`src` files and directories names are OK",
    check=data -> meets_src_names_ok(data.pkg_code_path),
)

function meets_code_can_be_downloaded(registry_head, pkg, version, pr; pkg_code_path)
    uuid, package_repo, subdir, tree_hash_from_toml = parse_registry_pkg_info(
        registry_head, pkg, version
    )

    # We get the `tree_hash` two ways and check they agree, which helps ensures the `subdir` parameter is correct. Two ways:
    # 1. By the commit hash in the PR body and the subdir parameter
    # 2. By the tree hash in the Versions.toml

    commit_hash = commit_from_pull_request_body(pr)

    local tree_hash_from_commit, tree_hash_from_commit_success
    clone_success = load_files_from_url_and_tree_hash(
        pkg_code_path, package_repo, tree_hash_from_toml
    ) do dir
        tree_hash_from_commit, tree_hash_from_commit_success = try
            readchomp(Cmd(`git rev-parse $(commit_hash):$(subdir)`; dir=dir)), true
        catch e
            @error e
            "", false
        end
    end

    if !clone_success
        return false, "Cloning repository failed."
    end

    if !tree_hash_from_commit_success
        return false,
        "Could not obtain tree hash from commit hash and subdir parameter. Possibly this indicates that an incorrect `subdir` parameter was passed during registration."
    end

    if tree_hash_from_commit != tree_hash_from_toml
        @error "`tree_hash_from_commit != tree_hash_from_toml`" tree_hash_from_commit tree_hash_from_toml
        return false,
        "Tree hash obtained from the commit message and subdirectory does not match the tree hash in the Versions.toml file. Possibly this indicates that an incorrect `subdir` parameter was passed during registration."
    else
        return true, ""
    end
end

function _generate_pkg_add_command(pkg::String, version::VersionNumber)::String
    return "Pkg.add(Pkg.PackageSpec(name=\"$(pkg)\", version=v\"$(string(version))\"));"
end

is_valid_url(str::AbstractString) = !isempty(HTTP.URI(str).scheme) && isvalid(HTTP.URI(str))

const guideline_version_can_be_pkg_added = Guideline(;
    info="Version can be `Pkg.add`ed",
    docs="Package installation: The package should be installable (`Pkg.add(\"PackageName\")`).",
    check=data -> meets_version_can_be_pkg_added(
        data.registry_head,
        data.pkg,
        data.version;
        registry_deps=data.registry_deps,
        environment_variables_to_pass=data.environment_variables_to_pass,
    ),
)

function meets_version_can_be_pkg_added(
    working_directory::String,
    pkg::String,
    version::VersionNumber;
    registry_deps::Vector{<:AbstractString}=String[],
    environment_variables_to_pass::Vector{String},
)
    pkg_add_command = _generate_pkg_add_command(pkg, version)
    _registry_deps = convert(Vector{String}, registry_deps)
    _registry_deps_is_valid_url = is_valid_url.(_registry_deps)
    code = """
        import Pkg;
        Pkg.Registry.add(Pkg.RegistrySpec(path=\"$(working_directory)\"));
        _registry_deps = $(_registry_deps);
        _registry_deps_is_valid_url = $(_registry_deps_is_valid_url);
        for i = 1:length(_registry_deps)
            regdep = _registry_deps[i]
            if _registry_deps_is_valid_url[i]
                Pkg.Registry.add(Pkg.RegistrySpec(url = regdep))
            else
                Pkg.Registry.add(regdep)
            end
        end
        @info("Attempting to `Pkg.add` package...");
        $(pkg_add_command)
        @info("Successfully `Pkg.add`ed package");
        """

    cmd_ran_successfully = _run_pkg_commands(
        working_directory,
        pkg,
        version;
        code=code,
        before_message="Attempting to `Pkg.add` the package",
        environment_variables_to_pass=environment_variables_to_pass,
    )
    if cmd_ran_successfully
        @info "Successfully `Pkg.add`ed the package"
        return true, ""
    else
        @error "Was not able to successfully `Pkg.add` the package"
        return false,
        string(
            "I was not able to install the package ",
            "(i.e. `Pkg.add(\"$(pkg)\")` failed). ",
            "See the AutoMerge logs for details.",
        )
    end
end

const guideline_version_has_osi_license = Guideline(;
    info="Version has OSI-approved license",
    docs=string(
        "License: The package should have an ",
        "[OSI-approved software license](https://opensource.org/licenses/alphabetical) ",
        "located in the top-level directory of the package code, ",
        "e.g. in a file named `LICENSE` or `LICENSE.md`. ",
        "This check is required for the General registry. ",
        "For other registries, registry maintainers have the option to disable this check.",
    ),
    check=data -> meets_version_has_osi_license(data.pkg; pkg_code_path=data.pkg_code_path),
)

function meets_version_has_osi_license(pkg::String; pkg_code_path)
    pkgdir = pkg_code_path
    if !isdir(pkgdir) || isempty(readdir(pkgdir))
        return false,
        "Could not check license because could not access package code. Perhaps the `can_download_code` check failed earlier."
    end

    license_results = LicenseCheck.find_licenses(pkgdir)

    # Failure mode 1: no licenses
    if isempty(license_results)
        @error "Could not find any licenses"
        return false,
        string(
            "No licenses detected in the package's top-level folder. An OSI-approved license is required.",
        )
    end

    flat_results = [
        (
            filename=lic.license_filename,
            identifier=identifier,
            approved=LicenseCheck.is_osi_approved(identifier),
        ) for lic in license_results for identifier in lic.licenses_found
    ]

    osi_results = [
        string(r.identifier, " license in ", r.filename) for r in flat_results if r.approved
    ]
    non_osi_results = [
        string(r.identifier, " license in ", r.filename) for
        r in flat_results if !r.approved
    ]

    osi_string = string(
        "Found OSI-approved license(s): ", join(osi_results, ", ", ", and "), "."
    )
    non_osi_string = string(
        "Found non-OSI license(s): ", join(non_osi_results, ", ", ", and "), "."
    )

    # Failure mode 2: no OSI-approved licenses, but has some kind of license detected
    if isempty(osi_results)
        @error "Found no OSI-approved licenses" non_osi_string
        return false, string("Found no OSI-approved licenses. ", non_osi_string)
    end

    # Pass: at least one OSI-approved license, possibly other licenses.
    @info "License check passed; results" osi_results non_osi_results
    if !isempty(non_osi_results)
        return true, string(osi_string, " Also ", non_osi_string)
    else
        return true, string(osi_string, " Found no other licenses.")
    end
end

const guideline_version_can_be_imported = Guideline(;
    info="Version can be `import`ed",
    docs="Package loading: The package should be loadable (`import PackageName`).",
    check=data -> meets_version_can_be_imported(
        data.registry_head,
        data.pkg,
        data.version;
        registry_deps=data.registry_deps,
        environment_variables_to_pass=data.environment_variables_to_pass,
    ),
)

function meets_version_can_be_imported(
    working_directory::String,
    pkg::String,
    version::VersionNumber;
    registry_deps::Vector{<:AbstractString}=String[],
    environment_variables_to_pass::Vector{String},
)
    pkg_add_command = _generate_pkg_add_command(pkg, version)
    _registry_deps = convert(Vector{String}, registry_deps)
    _registry_deps_is_valid_url = is_valid_url.(_registry_deps)
    code = """
        import Pkg;
        Pkg.Registry.add(Pkg.RegistrySpec(path=\"$(working_directory)\"));
        _registry_deps = $(_registry_deps);
        _registry_deps_is_valid_url = $(_registry_deps_is_valid_url);
        for i = 1:length(_registry_deps)
            regdep = _registry_deps[i]
            if _registry_deps_is_valid_url[i]
                Pkg.Registry.add(Pkg.RegistrySpec(url = regdep))
            else
                Pkg.Registry.add(regdep)
            end
        end
        @info("Attempting to `Pkg.add` package...");
        $(pkg_add_command)
        @info("Successfully `Pkg.add`ed package");
        @info("Attempting to `import` package");
        Pkg.precompile()
        import $(pkg);
        @info("Successfully `import`ed package");
        """

    cmd_ran_successfully = _run_pkg_commands(
        working_directory,
        pkg,
        version;
        code=code,
        before_message="Attempting to `import` the package",
        environment_variables_to_pass=environment_variables_to_pass,
    )

    if cmd_ran_successfully
        @info "Successfully `import`ed the package"
        return true, ""
    else
        @error "Was not able to successfully `import` the package"
        return false,
        string(
            "I was not able to load the package ",
            "(i.e. `import $(pkg)` failed). ",
            "See the AutoMerge logs for details.",
        )
    end
end

function _run_pkg_commands(
    working_directory::String,
    pkg::String,
    version::VersionNumber;
    code,
    before_message,
    environment_variables_to_pass::Vector{String},
)
    original_directory = pwd()
    tmp_dir_1 = mktempdir()
    atexit(() -> rm(tmp_dir_1; force=true, recursive=true))
    cd(tmp_dir_1)
    # We need to be careful with what environment variables we pass to the child
    # process. For example, we don't want to pass an environment variable containing
    # our GitHub token to the child process. Because if the Julia package that we are
    # testing has malicious code in its __init__() function, it could try to steal
    # our token. So we only pass these environment variables:
    # 1. HTTP_PROXY. If it's set, it is delegated to the child process.
    # 2. HTTPS_PROXY. If it's set, it is delegated to the child process.
    # 3. JULIA_DEPOT_PATH. We set JULIA_DEPOT_PATH to the temporary directory that
    #    we created. This is because we don't want the child process using our
    #    real Julia depot. So we set up a fake depot for the child process to use.
    # 4. JULIA_PKG_SERVER. If it's set, it is delegated to the child process.
    # 5. JULIA_REGISTRYCI_AUTOMERGE. We set JULIA_REGISTRYCI_AUTOMERGE to "true".
    # 6. PATH. If we don't pass PATH, things break. And PATH should not contain any
    #    sensitive information.
    # 7. PYTHON. We set PYTHON to the empty string. This forces any packages that use
    #    PyCall to install their own version of Python instead of using the system
    #    Python.
    # 8. R_HOME. We set R_HOME to "*".
    # 9. HOME. Lots of things need HOME.
    #
    # If registry maintainers need additional environment variables to be passed
    # to the child process, they can do so by providing the `environment_variables_to_pass`
    # kwarg to the `AutoMerge.run` function.

    env = Dict(
        "JULIA_DEPOT_PATH" => mktempdir(),
        "JULIA_PKG_PRECOMPILE_AUTO" => "0",
        "JULIA_REGISTRYCI_AUTOMERGE" => "true",
        "PYTHON" => "",
        "R_HOME" => "*",
    )
    default_environment_variables_to_pass = [
        "HOME",
        "JULIA_PKG_SERVER",
        "PATH",
        "HTTP_PROXY",
        "HTTPS_PROXY",
    ]
    all_environment_variables_to_pass = vcat(
        default_environment_variables_to_pass,
        environment_variables_to_pass,
    )
    for k in all_environment_variables_to_pass
        if haskey(ENV, k)
            env[k] = ENV[k]
        end
    end

    cmd = Cmd(`$(Base.julia_cmd()) -e $(code)`; env=env)

    # GUI toolkits may need a display just to load the package
    xvfb = Sys.which("xvfb-run")
    @info("xvfb: ", xvfb)
    if xvfb !== nothing
        pushfirst!(cmd.exec, "-a")
        pushfirst!(cmd.exec, xvfb)
    end
    @info(before_message)
    @info("""
        IMPORTANT: If you see any messages of the form "Error: Some registries failed to update"
        or "registry dirty"
        please disregard those messages. Those messages are normal and do not indicate an error.
    """)
    cmd_ran_successfully = success(pipeline(cmd; stdout=stdout, stderr=stderr))
    cd(original_directory)

    rmdir(tmp_dir_1)

    return cmd_ran_successfully
end

function rmdir(dir)
    try
        chmod(dir, 0o700; recursive=true)
    catch
    end
    return rm(dir; force=true, recursive=true)
end

url_has_correct_ending(url, pkg) = endswith(url, "/$(pkg).jl.git")

function get_automerge_guidelines(
    ::NewPackage;
    check_license::Bool,
    this_is_jll_package::Bool,
    this_pr_can_use_special_jll_exceptions::Bool,
    use_distance_check::Bool,
    package_author_approved::Bool, # currently unused for new packages
    check_breaking_explanation::Bool # not valid for new packages
)
    guidelines = [
        # We first verify the name is a valid Julia identifier.
        # If not, we early exit (`:early_exit_if_failed`), since we don't want to proceed further.
        (guideline_name_identifier, true),
        (:early_exit_if_failed, true),
        (guideline_registry_consistency_tests_pass, true),
        (guideline_pr_only_changes_allowed_files, true),
        # (guideline_only_changes_specified_package, true), # not yet implemented
        (guideline_normal_capitalization, !this_pr_can_use_special_jll_exceptions),
        (guideline_name_length, !this_pr_can_use_special_jll_exceptions),
        (guideline_julia_name_check, true),
        (guideline_repo_url_requirement, true),
        (guideline_version_number_no_prerelease, true),
        (guideline_version_number_no_build, !this_pr_can_use_special_jll_exceptions),
        (guideline_compat_for_julia, true),
        (guideline_compat_for_all_deps, true),
        (guideline_allowed_jll_nonrecursive_dependencies, this_is_jll_package),
        (guideline_name_ascii, true),
        (:update_status, true),
        (guideline_version_can_be_pkg_added, true),
        (guideline_code_can_be_downloaded, true),
        # `guideline_version_has_osi_license` must be run
        # after `guideline_code_can_be_downloaded` so
        # that it can use the downloaded code!
        (guideline_version_has_osi_license, check_license),
        (guideline_src_names_OK, true),
        (guideline_version_can_be_imported, true),
        (:update_status, true),
        (guideline_dependency_confusion, true),
        # this is the non-optional part of name checking
        (guideline_name_match_check, true),
        # We always run the `guideline_distance_check`
        # check last, because if the check fails, it
        # prints the list of similar package names in
        # the automerge comment. To make the comment easy
        # to read, we want this list to be at the end.
        (guideline_distance_check, use_distance_check),
    ]
    return guidelines
end

function get_automerge_guidelines(
    ::NewVersion;
    check_license::Bool,
    check_breaking_explanation::Bool,
    this_is_jll_package::Bool,
    this_pr_can_use_special_jll_exceptions::Bool,
    use_distance_check::Bool, # unused for new versions
    package_author_approved::Bool,
)
    guidelines = [
        (guideline_registry_consistency_tests_pass, true),
        (guideline_pr_only_changes_allowed_files, true),
        (guideline_sequential_version_number, !this_pr_can_use_special_jll_exceptions && !package_author_approved),
        (guideline_version_number_no_prerelease, true),
        (guideline_version_number_no_build, !this_pr_can_use_special_jll_exceptions),
        (guideline_compat_for_julia, true),
        (guideline_compat_for_all_deps, true),
        (
            guideline_patch_release_does_not_narrow_julia_compat,
            !this_pr_can_use_special_jll_exceptions,
        ),
        (guideline_allowed_jll_nonrecursive_dependencies, this_is_jll_package),
        (:update_status, true),
        (guideline_version_can_be_pkg_added, true),
        (guideline_code_can_be_downloaded, true),
        # `guideline_version_has_osi_license` must be run
        # after `guideline_code_can_be_downloaded` so
        # that it can use the downloaded code!
        (guideline_version_has_osi_license, check_license),
        (guideline_src_names_OK, true),
        (guideline_version_can_be_imported, true),
        (guideline_breaking_explanation, check_breaking_explanation && !this_is_jll_package),
    ]
    return guidelines
end
