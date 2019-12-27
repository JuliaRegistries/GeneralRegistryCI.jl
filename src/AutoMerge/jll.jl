function is_jll_name(name::AbstractString)::Bool
    return endswith(name, "_jll")
end

function _get_all_dependencies_nonrecursive(working_directory::AbstractString,
                                            pkg,
                                            version)
    all_dependencies = Vector{String}(undef, 0)
    deps = Pkg.TOML.parsefile(joinpath(working_directory, uppercase(pkg[1:1]), pkg, "Deps.toml"))
    for version_range in keys(deps)
        if version in Pkg.Types.VersionRange(version_range)
            for name in keys(deps[version_range])
            end
        end
    end
    unique!(all_dependencies)
    return all_dependencies
end

function meets_allowed_jll_nonrecursive_dependencies(working_directory::AbstractString,
                                                     pkg,
                                                     version)
    # If you are a JLL package, you are only allowed to have three kinds of dependencies:
    # 1. Pkg
    # 2. Libdl
    # 3. other JLL packages
    all_dependencies = _get_all_dependencies_nonrecursive(working_directory,
                                                          pkg,
                                                          version)
    for dep in all_dependencies
        if !((dep == "Pkg") | (dep == "Libdl") | (is_jll_name(dep)))
            return false, "JLL packages are only allowed to depend on Pkg, Libdl, and other JLL packages"
        end
    end
    return true, ""
end
