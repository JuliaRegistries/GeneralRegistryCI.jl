function is_jll_name(name::AbstractString)::Bool
    return endswith(name, "_jll")
end

function _get_all_dependencies_nonrecursive(working_directory::AbstractString, pkg, version)
    all_dependencies = String[]
    package_relpath = get_package_relpath_in_registry(;
        package_name=pkg, registry_path=working_directory
    )
    deps_file = joinpath(working_directory, package_relpath, "Deps.toml")
    deps = maybe_parse_toml(deps_file)
    for version_range in keys(deps)
        if version in Pkg.Types.VersionRange(version_range)
            for name in keys(deps[version_range])
                push!(all_dependencies, name)
            end
        end
    end
    unique!(all_dependencies)
    return all_dependencies
end

const guideline_allowed_jll_nonrecursive_dependencies = Guideline(;
    info="If this is a JLL package, only deps are Pkg, Libdl, and other JLL packages",
    docs=nothing,
    check=data -> meets_allowed_jll_nonrecursive_dependencies(
        data.registry_head, data.pkg, data.version
    ),
)

function meets_allowed_jll_nonrecursive_dependencies(
    working_directory::AbstractString, pkg, version
)
    # If you are a JLL package, you are only allowed to have the following dependencies:
    # 1. Pkg
    # 2. Libdl
    # 3. Artifacts
    # 4. JLLWrappers (or LazyJLLWrappers)
    # 5. LazyArtifacts
    # 6. TOML
    # 7. MPIPreferences
    # 8. other JLL packages
    all_dependencies = _get_all_dependencies_nonrecursive(working_directory, pkg, version)
    allowed_dependencies = ("Pkg", "Libdl", "Artifacts", "JLLWrappers", "LazyJLLWrappers", "LazyArtifacts", "TOML", "MPIPreferences")
    for dep in all_dependencies
        if dep ∉ allowed_dependencies && !is_jll_name(dep)
            return false,
            "JLL packages are only allowed to depend on $(join(allowed_dependencies, ", ")) and other JLL packages"
        end
    end
    return true, ""
end
