import HTTP

const guideline_compat_for_all_deps =
    Guideline("Compat (with upper bound) for all dependencies",
              data -> meets_compat_for_all_deps(data.registry_head,
                                                data.pkg,
                                                data.version))

function meets_compat_for_all_deps(working_directory::AbstractString, pkg, version)
    deps = Pkg.TOML.parsefile(joinpath(working_directory, uppercase(pkg[1:1]), pkg, "Deps.toml"))
    compat = Pkg.TOML.parsefile(joinpath(working_directory, uppercase(pkg[1:1]), pkg, "Compat.toml"))
    # First, we construct a Dict in which the keys are the package's
    # dependencies, and the value is always false.
    dep_has_compat_with_upper_bound = Dict{String, Bool}()
    @debug("We always have julia as a dependency")
    dep_has_compat_with_upper_bound["julia"] = false
    for version_range in keys(deps)
        if version in Pkg.Types.VersionRange(version_range)
            for name in keys(deps[version_range])
                if !is_jll_name(name) && !is_julia_stdlib(name)
                    @debug("Found a new (non-stdlib non-JLL) dependency: $(name)")
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
            for compat_entry in compat[version_range]
                name = compat_entry[1]
                value = compat_entry[2]
                if value isa Vector
                    if !isempty(value)
                        value_ranges = Pkg.Types.VersionRange.(value)
                        each_range_has_upper_bound = _has_upper_bound.(value_ranges)
                        if all(each_range_has_upper_bound)
                            @debug("Dependency \"$(name)\" has compat entries that all have upper bounds")
                            dep_has_compat_with_upper_bound[name] = true
                        end
                    end
                else
                    value_range = Pkg.Types.VersionRange(value)
                    if _has_upper_bound(value_range)
                        @debug("Dependency \"$(name)\" has a compat entry with an upper bound")
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
                @error("Dependency \"$(name)\" does not have a compat entry that has an upper bound")
                push!(bad_dependencies, name)
            end
        end
        sort!(bad_dependencies)
        message = string(
            "The following dependencies do not have a `[compat]` entry ",
            "that is upper-bounded and only includes a finite number ",
            "of breaking releases: ",
            join(bad_dependencies, ", ")
        )
        return false, message
    end
end

const guideline_patch_release_does_not_narrow_julia_compat =
    Guideline("If it is a patch release, then it does not narrow the Julia compat range",
              data -> meets_patch_release_does_not_narrow_julia_compat(data.pkg,
                                                                       data.version;
                                                                       registry_head = data.registry_head,
                                                                       registry_master = data.registry_master))

function meets_patch_release_does_not_narrow_julia_compat(pkg::String,
                                                          new_version::VersionNumber;
                                                          registry_head::String,
                                                          registry_master::String)
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
    meets_this_guideline = range_did_not_narrow(julia_compats_for_old_version, julia_compats_for_new_version)
    if meets_this_guideline
        return true, ""
    else
        if (old_version >= v"1") || (new_version >= v"1")
            msg = string("A patch release is not allowed to narrow the ",
                         "supported ranges of Julia versions. ",
                         "The ranges have changed from ",
                         "$(julia_compats_for_old_version) ",
                         "(in $(old_version)) ",
                         "to $(julia_compats_for_new_version) ",
                         "(in $(new_version)).")
            return false, msg
        else
            @info("Narrows Julia compat, but it's OK since package is pre-1.0")
            return true, ""
        end
    end
end

const guideline_name_length =
    Guideline("Name not too short",
              data -> meets_name_length(data.pkg))

function meets_name_length(pkg)
    meets_this_guideline = length(pkg) >= 5
    if meets_this_guideline
        return true, ""
    else
        return false, "Name is not at least five characters long"
    end
end

const guideline_name_ascii =
    Guideline("Name is composed of ASCII characters only",
              data -> meets_name_ascii(data.pkg))

function meets_name_ascii(pkg)
    if isascii(pkg)
        return true, ""
    else
        return false, "Name is not ASCII"
    end
end

const guideline_julia_name_check =
    Guideline("Name does not include \"julia\" or start with \"Ju\"",
              data -> meets_julia_name_check(data.pkg))

function meets_julia_name_check(pkg)
    if occursin("julia", lowercase(pkg))
        return false, "Lowercase package name $(lowercase(pkg)) contains the string \"julia\"."
    elseif startswith(pkg, "Ju")
        return false, "Package name starts with \"Ju\"."
    else
        return true, ""
    end
end

damerau_levenshtein(name1, name2) = StringDistances.DamerauLevenshtein()(name1, name2)
sqrt_normalized_vd(name1, name2) = VisualStringDistances.visual_distance(name1, name2; normalize=x -> 5 + sqrt(x))

const guideline_distance_check =
    Guideline("Name is not too similar to existing package names",
              data -> meets_distance_check(data.pkg, data.registry_master))

function meets_distance_check(pkg_name::AbstractString,
                              registry_master::AbstractString;
                              kwargs...)
    other_packages = get_all_non_jll_package_names(registry_master)
    return meets_distance_check(pkg_name, other_packages; kwargs...)
end

function meets_distance_check(pkg_name::AbstractString,
                              other_packages::Vector;
                              DL_lowercase_cutoff = 1,
                              DL_cutoff = 2,
                              sqrt_normalized_vd_cutoff = 2.5,
                              comment_collapse_cutoff = 10)
    problem_messages = Tuple{String, Tuple{Float64, Float64, Float64}}[]
    for other_pkg in other_packages
        if pkg_name == other_pkg
            # We short-circuit in this case; more information doesn't help.
            return  (false, "Package name already exists in the registry.")
        elseif lowercase(pkg_name) == lowercase(other_pkg)
            # We'll sort this first
            push!(problem_messages, ("Package name matches existing package name $(other_pkg) up to case.", (0,0,0)))
        else
            msg = ""

            # Distance check 1: DL distance
            dl = damerau_levenshtein(pkg_name, other_pkg)
            if dl <= DL_cutoff
                msg = string(msg, " Damerau-Levenshtein distance $dl is at or below cutoff of $(DL_cutoff).")
            end

            # Distance check 2: lowercase DL distance
            dl_lowercase = damerau_levenshtein(lowercase(pkg_name), lowercase(other_pkg))
            if dl_lowercase <= DL_lowercase_cutoff
                msg = string(msg, " Damerau-Levenshtein distance $(dl_lowercase) between lowercased names is at or below cutoff of $(DL_lowercase_cutoff).")
            end

            # Distance check 3: normalized visual distance,
            # gated by a `dl` check for speed.
            if (sqrt_normalized_vd_cutoff > 0 && dl <= 4)
                nrm_vd = sqrt_normalized_vd(pkg_name, other_pkg)
                if nrm_vd <= sqrt_normalized_vd_cutoff
                    msg = string(msg, " Normalized visual distance ", Printf.@sprintf("%.2f", nrm_vd), " is at or below cutoff of ", Printf.@sprintf("%.2f", sqrt_normalized_vd_cutoff), ".")
                end
            else
                # need to choose something for sorting purposes
                nrm_vd = 10.0
            end

            if msg != ""
                # We must have found a clash.
                push!(problem_messages, (string("Similar to $(other_pkg).", msg), (dl, dl_lowercase, nrm_vd)))
            end
        end
    end

    isempty(problem_messages) && return (true, "")
    sort!(problem_messages, by = Base.tail)
    message = string("Package name similar to $(length(problem_messages)) existing package",
                    length(problem_messages) > 1 ? "s" : "", ".\n")
    if length(problem_messages) > comment_collapse_cutoff
        message *=  """
                    <details>
                    <summary>Similar package names</summary>

                    """
    end
    message *= join(join.(zip(1:length(problem_messages), first.(problem_messages)), Ref(". ")), '\n')
    if length(problem_messages) > comment_collapse_cutoff
        message *=  "\n</details>\n"
    end
    return (false, message)
end

const guideline_normal_capitalization =
    Guideline("Normal capitalization",
              data -> meets_normal_capitalization(data.pkg))

function meets_normal_capitalization(pkg)
    meets_this_guideline = occursin(r"^[A-Z]\w*[a-z]\w*[0-9]?$", pkg)
    if meets_this_guideline
        return true, ""
    else
        return false, "Name does not meet all of the following: starts with an uppercase letter, ASCII alphanumerics only, not all letters are uppercase."
    end
end

const guideline_repo_url_requirement =
    Guideline("Repo URL ends with /name.jl.git",
              data -> meets_repo_url_requirement(data.pkg;
                                                 registry_head = data.registry_head))

function meets_repo_url_requirement(pkg::String; registry_head::String)
    package_toml_parsed = Pkg.TOML.parsefile(
        joinpath(
            registry_head,
            uppercase(pkg[1:1]),
            pkg,
            "Package.toml",
        )
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
    return false, "Does not meet sequential version number guideline: $reason", :invalid
end

function _valid_change(old_version::VersionNumber, new_version::VersionNumber)
    diff = difference(old_version, new_version)
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

const guideline_sequential_version_number =
    Guideline("Sequential version number",
              data -> meets_sequential_version_number(data.pkg,
                                                      data.version;
                                                      registry_head = data.registry_head,
                                                      registry_master = data.registry_master))

function meets_sequential_version_number(existing::Vector{VersionNumber}, ver::VersionNumber)
    always_assert(!isempty(existing))
    if ver in existing
        return _invalid_sequential_version("version $ver already exists")
    end
    issorted(existing) || (existing = sort(existing))
    idx = searchsortedlast(existing, ver)
    idx > 0 || return _invalid_sequential_version("version $ver less than least existing version $(existing[1])")
    prv = existing[idx]
    always_assert(ver != prv)
    nxt = thismajor(ver) != thismajor(prv) ? nextmajor(prv) :
          thisminor(ver) != thisminor(prv) ? nextminor(prv) : nextpatch(prv)
    ver <= nxt || return _invalid_sequential_version("version $ver skips over $nxt")
    return _valid_change(prv, ver)
end

_has_prerelease_andor_build_data(version) = !isempty(version.prerelease) || !isempty(version.build)

function meets_sequential_version_number(pkg::String,
                                         new_version::VersionNumber;
                                         registry_head::String,
                                         registry_master::String)
    if _has_prerelease_andor_build_data(new_version)
        return false, "Version number is not allowed to contain prerelease or build data", :invalid
    end
    _all_versions = all_versions(pkg, registry_master)
    return meets_sequential_version_number(_all_versions, new_version)
end

const guideline_standard_initial_version_number =
    Guideline("Standard initial version number ",
              data -> meets_standard_initial_version_number(data.version))

function meets_standard_initial_version_number(version)
    if _has_prerelease_andor_build_data(version)
        return false, "Version number is not allowed to contain prerelease or build data"
    end
    meets_this_guideline = version == v"0.0.1" || version == v"0.1.0" || version == v"1.0.0" || _is_x_0_0(version)
    if meets_this_guideline
        return true, ""
    else
        return false, "Version number is not 0.0.1, 0.1.0, 1.0.0, or X.0.0"
    end
end

function _is_x_0_0(version::VersionNumber)
    if _has_prerelease_andor_build_data(version)
        return false
    end
    result = (version.major >= 1) && (version.minor == 0) && (version.patch == 0)
    return result
end

function _generate_pkg_add_command(pkg::String,
                                   version::VersionNumber)::String
    return "Pkg.add(Pkg.PackageSpec(name=\"$(pkg)\", version=v\"$(string(version))\"));"
end

function _generate_pkg_dev_command(pkg::String,
                                   version::VersionNumber)::String
    return "Pkg.develop(Pkg.PackageSpec(name=\"$(pkg)\"));"
end

is_valid_url(str::AbstractString) = !isempty(HTTP.URI(str).scheme) && isvalid(HTTP.URI(str))

const guideline_version_can_be_pkg_added =
    Guideline("Version can be `Pkg.add`ed",
              data -> meets_version_can_be_pkg_added(data.registry_head,
                                                     data.pkg,
                                                     data.version;
                                                     registry_deps = data.registry_deps,
                                                     depot_path=data.depot_path))

function meets_version_can_be_pkg_added(working_directory::String,
                                        pkg::String,
                                        version::VersionNumber;
                                        registry_deps::Vector{<:AbstractString} = String[],
                                        depot_path)
    pkg_add_command = _generate_pkg_add_command(pkg,
                                                version)
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

    cmd_ran_successfully = _run_pkg_commands(working_directory, pkg,
                                version; code = code,
                                before_message = "Attempting to `Pkg.add` the package",
                                depot_path=depot_path)
    if cmd_ran_successfully
        @info "Successfully `Pkg.add`ed the package"
        return true, ""
    else
        @error "Was not able to successfully `Pkg.add` the package"
        return false, string("I was not able to install the package ",
                             "(i.e. `Pkg.add(\"$(pkg)\")` failed). ",
                             "See the CI logs for details.")
    end
end

const guideline_version_can_be_pkg_deved =
    Guideline("Version can be `Pkg.dev`ed",
              data -> meets_version_can_be_pkg_deved(data.registry_head,
                                                     data.pkg,
                                                     data.version;
                                                     registry_deps = data.registry_deps,
                                                     depot_path=data.depot_path))

function meets_version_can_be_pkg_deved(working_directory::String,
                                        pkg::String,
                                        version::VersionNumber;
                                        registry_deps::Vector{<:AbstractString} = String[],
                                        depot_path)
    pkg_dev_command = _generate_pkg_dev_command(pkg, version)
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
        @info("Attempting to `Pkg.dev` package...");
        $(pkg_dev_command)
        @info("Successfully `Pkg.dev`ed package");
        """

    cmd_ran_successfully = _run_pkg_commands(working_directory, pkg,
                                version; code = code,
                                before_message = "Attempting to `Pkg.dev` the package",
                                depot_path=depot_path)
    if cmd_ran_successfully
        @info "Successfully `Pkg.dev`ed the package"
        return true, ""
    else
        @error "Was not able to successfully `Pkg.dev` the package"
        return false, string("I was not able to install the package ",
                             "(i.e. `Pkg.dev(\"$(pkg)\")` failed). ",
                             "See the CI logs for details.")
    end
end

const guideline_version_has_osi_license =
    Guideline("Version has OSI-approved license",
              data -> meets_version_has_osi_license(data.pkg; depot_path = data.depot_path))

function pkgdir_from_depot(depot_path::String, pkg::String)
    pkgdir_parent = joinpath(depot_path, "packages", pkg)
    isdir(pkgdir_parent) || return nothing
    all_pkgdir_elements = readdir(pkgdir_parent)
    @info "" pkgdir_parent all_pkgdir_elements
    (length(all_pkgdir_elements) == 1) || return nothing
    only_pkgdir_element = all_pkgdir_elements[1]
    only_pkdir = joinpath(pkgdir_parent, only_pkgdir_element)
    isdir(only_pkdir) || return nothing
    return only_pkdir
end

function meets_version_has_osi_license(pkg::String; depot_path)
    pkgdir = pkgdir_from_depot(depot_path, pkg)
    if pkgdir isa Nothing
        return false, "Could not check license because could not access package code. Perhaps the `Pkg.add` step failed earlier."
    end

    license_results = LicenseCheck.find_licenses(pkgdir)

    # Failure mode 1: no licenses
    if isempty(license_results)
        @error "Could not find any licenses"
        return false, string("No licenses detected in the package's top-level folder. An OSI-approved license is required.")
    end

    flat_results = [(filename = lic.license_filename, identifier=identifier, approved=LicenseCheck.is_osi_approved(identifier)) for lic in license_results for identifier in lic.licenses_found ]

    osi_results = [ string(r.identifier, " license in ", r.filename) for r in flat_results if r.approved ]
    non_osi_results = [ string(r.identifier, " license in ", r.filename) for r in flat_results if !r.approved ]

    osi_string = string("Found OSI-approved license(s): ", join(osi_results, ", ", ", and "), ".")
    non_osi_string = string("found non-OSI license(s): ", join(non_osi_results, ", ", ", and "), ".")

    # Failure mode 2: no OSI-approved licenses, but has some kind of license detected
    if isempty(osi_results)
        @error "Found no OSI-approved licenses" non_osi_string
        return false, string("Found no OSI-approved licenses. ",  uppercasefirst(non_osi_string))
    end

    # Pass: at least one OSI-approved license, possibly other licenses.
    @info "License check passed; results" osi_results non_osi_results
    if !isempty(non_osi_results)
        return true, string(osi_string, " Also ", non_osi_string)
    else
        return true, string(osi_string, " Found no other licenses.")
    end
end

const guideline_version_can_be_imported =
    Guideline("Version can be `import`ed",
              data -> meets_version_can_be_imported(data.registry_head,
                                                    data.pkg,
                                                    data.version;
                                                    registry_deps = data.registry_deps,
                                                    depot_path=data.depot_path))

function meets_version_can_be_imported(working_directory::String,
                                       pkg::String,
                                       version::VersionNumber;
                                       registry_deps::Vector{<:AbstractString} = String[],
                                       depot_path::String)
    pkg_add_command = _generate_pkg_add_command(pkg,
                                                version)
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
        import $(pkg);
        @info("Successfully `import`ed package");
        """

    cmd_ran_successfully = _run_pkg_commands(working_directory, pkg,
                                version; code = code,
                                before_message = "Attempting to `import` the package",
                                depot_path=depot_path)

    if cmd_ran_successfully
        @info "Successfully `import`ed the package"
        return true, ""
    else
        @error "Was not able to successfully `import` the package"
        return false, string("I was not able to load the package ",
                             "(i.e. `import $(pkg)` failed). ",
                             "See the CI logs for details.")
    end
end

function _run_pkg_commands(working_directory::String,
                           pkg::String,
                           version::VersionNumber;
                           depot_path,
                           code,
                           before_message)
    original_directory = pwd()
    tmp_dir_1 = mktempdir()
    atexit(() -> rm(tmp_dir_1; force = true, recursive = true))
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

    env = Dict(
        "JULIA_DEPOT_PATH" => depot_path,
        "JULIA_REGISTRYCI_AUTOMERGE" => "true",
        "PYTHON" => "",
        "R_HOME" => "*",
    )
    for k in ("HOME", "PATH", "HTTP_PROXY", "HTTPS_PROXY", "JULIA_PKG_SERVER")
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
    cmd_ran_successfully = success(pipeline(cmd, stdout=stdout, stderr=stderr))
    cd(original_directory)

    rmdir(tmp_dir_1)

    return cmd_ran_successfully
end

function rmdir(dir)
    try
        chmod(dir, 0o700, recursive = true)
    catch
    end
    rm(dir; force = true, recursive = true)
end

url_has_correct_ending(url, pkg) = endswith(url, "/$(pkg).jl.git")
