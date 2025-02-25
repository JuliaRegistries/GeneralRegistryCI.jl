using Dates
# using GitCommand
using GitHub
using JSON
using Pkg
using Printf
using RegistryCI
using Test
using TimeZones

const AutoMerge = RegistryCI.AutoMerge


TEMP_DEPOT_FOR_TESTING = nothing

function setup_global_depot()::String
    global TEMP_DEPOT_FOR_TESTING
    if TEMP_DEPOT_FOR_TESTING isa String
        return TEMP_DEPOT_FOR_TESTING
    end
    tmp_depot = mktempdir()
    env1 = copy(ENV)
    env1["JULIA_DEPOT_PATH"] = tmp_depot
    delete!(env1, "JULIA_LOAD_PATH")
    delete!(env1, "JULIA_PROJECT")
    env2 = copy(env1)
    env2["JULIA_PKG_SERVER"] = ""
    run(setenv(`julia -e 'import Pkg; Pkg.Registry.add("General")'`, env2))
    run(setenv(`julia -e 'import Pkg; Pkg.add(["RegistryCI"])'`, env1))
    TEMP_DEPOT_FOR_TESTING = tmp_depot
    tmp_depot
end


# helper for testing `AutoMerge.meets_version_has_osi_license`
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

strip_equal(x, y) = strip(x) == strip(y)

# Here we reference test all the permutations of the AutoMerge comments.
# This allows us to see the diffs in PRs that change the AutoMerge comment.
# You can set `ENV["JULIA_REFERENCETESTS_UPDATE"] = true` to easily update the reference tests.
function comment_reference_test()
    for pass in (true, false),
        (type_name,type) in (("new_version", AutoMerge.NewVersion()), ("new_package", AutoMerge.NewPackage())),
        suggest_onepointzero in (true, false),
        # some code depends on above or below v"1"
        version in (v"0.1", v"1")

        if pass
            for is_jll in (true, false)
                name = string("comment", "_pass_", pass, "_type_", type_name,
                "_suggest_onepointzero_", suggest_onepointzero,
                "_version_", version, "_is_jll_", is_jll)
                @test_reference "reference_comments/$name.md" AutoMerge.comment_text_pass(type, suggest_onepointzero, version, is_jll, new_package_waiting_period=Day(3)) by=strip_equal
            end
        else
            for point_to_slack in (true, false)
                name = string("comment", "_pass_", pass, "_type_", type_name,
                "_suggest_onepointzero_", suggest_onepointzero,
                "_version_", version, "_point_to_slack_", point_to_slack)
                reasons = [
                            AutoMerge.compat_violation_message(["julia"]),
                            AutoMerge.breaking_explanation_message(true, v"1.0.0"),
                            AutoMerge.breaking_explanation_message(false, v"1.0.0"),
                            AutoMerge.breaking_explanation_message(true, v"0.2.0"),
                            "Example guideline failed. Please fix it."]
                fail_text = AutoMerge.comment_text_fail(type, reasons, suggest_onepointzero, version; point_to_slack=point_to_slack)

                @test_reference "reference_comments/$name.md" fail_text by=strip_equal

                # `point_to_slack=false` should yield no references to Slack in the text
                if !point_to_slack
                    @test !occursin("slack", fail_text)
                end
            end
        end
    end
end

@testset "Utilities" begin
    @testset "comment_reference_test" begin
        comment_reference_test()
    end
    @testset "Customized `new_package_waiting_period` in AutoMerge comment " begin
        text = AutoMerge.comment_text_pass(AutoMerge.NewPackage(), false, v"1", false; new_package_waiting_period=Minute(45))
        @test occursin("(45 minutes)", text)
    end
    @testset "`AutoMerge.parse_registry_pkg_info`" begin
        registry_path = joinpath(DEPOT_PATH[1], "registries", "General")
        result = AutoMerge.parse_registry_pkg_info(registry_path, "RegistryCI", "1.0.0")
        @test result == (;
            uuid="0c95cc5f-2f7e-43fe-82dd-79dbcba86b32",
            repo="https://github.com/JuliaRegistries/RegistryCI.jl.git",
            subdir="",
            tree_hash="1036c9c4d600468785fbd9dae87587e59d2f66a9",
        )
        result = AutoMerge.parse_registry_pkg_info(registry_path, "RegistryCI")
        @test result == (;
            uuid="0c95cc5f-2f7e-43fe-82dd-79dbcba86b32",
            repo="https://github.com/JuliaRegistries/RegistryCI.jl.git",
            subdir="",
            tree_hash=nothing,
        )

        result = AutoMerge.parse_registry_pkg_info(
            registry_path, "SnoopCompileCore", "2.5.2"
        )
        @test result == (;
            uuid="e2b509da-e806-4183-be48-004708413034",
            repo="https://github.com/timholy/SnoopCompile.jl.git",
            subdir="SnoopCompileCore",
            tree_hash="bb6d6df44d9aa3494c997aebdee85b713b92c0de",
        )
    end
end

@testset "Guidelines for new packages" begin
    @testset "Package name is a valid identifier" begin
        @test AutoMerge.meets_name_is_identifier("Hello")[1]
        @test !AutoMerge.meets_name_is_identifier("Hello-GoodBye")[1]
    end
    @testset "Normal capitalization" begin
        @test AutoMerge.meets_normal_capitalization("Zygote")[1]  # Regular name
        @test AutoMerge.meets_normal_capitalization("Zygote")[1]
        @test !AutoMerge.meets_normal_capitalization("HTTP")[1]  # All upper-case
        @test !AutoMerge.meets_normal_capitalization("HTTP")[1]
        @test AutoMerge.meets_normal_capitalization("ForwardDiff2")[1]  # Ends with a number
        @test AutoMerge.meets_normal_capitalization("ForwardDiff2")[1]
        @test !AutoMerge.meets_normal_capitalization("JSON2")[1]  # All upper-case and ends with number
        @test !AutoMerge.meets_normal_capitalization("JSON2")[1]
        @test AutoMerge.meets_normal_capitalization("RegistryCI")[1]  # Ends with upper-case
        @test AutoMerge.meets_normal_capitalization("RegistryCI")[1]
    end
    @testset "Not too short - at least five letters" begin
        @test AutoMerge.meets_name_length("Zygote")[1]
        @test AutoMerge.meets_name_length("Zygote")[1]
        @test !AutoMerge.meets_name_length("Flux")[1]
        @test !AutoMerge.meets_name_length("Flux")[1]
    end
    @testset "Name does not include \"julia\", start with \"Ju\", or end with \"jl\"" begin
        @test AutoMerge.meets_julia_name_check("Zygote")[1]
        @test AutoMerge.meets_julia_name_check("RegistryCI")[1]
        @test !AutoMerge.meets_julia_name_check("JuRegistryCI")[1]
        @test !AutoMerge.meets_julia_name_check("ZygoteJulia")[1]
        @test !AutoMerge.meets_julia_name_check("Zygotejulia")[1]
        @test !AutoMerge.meets_julia_name_check("Sortingjl")[1]
        @test !AutoMerge.meets_julia_name_check("BananasJL")[1]
        @test !AutoMerge.meets_julia_name_check("AbcJuLiA")[1]
    end
    @testset "Package name is ASCII" begin
        @test !AutoMerge.meets_name_ascii("ábc")[1]
        @test AutoMerge.meets_name_ascii("abc")[1]
    end
    @testset "Package name match check" begin
        @test AutoMerge.meets_name_match_check("Flux", ["Abc", "Def"])[1]
        @test !AutoMerge.meets_name_match_check("Websocket", ["websocket"])[1]
    end
    @testset "Package name distance" begin
        @test AutoMerge.meets_distance_check("Flux", ["Abc", "Def"])[1]
        @test !AutoMerge.meets_distance_check("Flux", ["FIux", "Abc", "Def"])[1]
        @test !AutoMerge.meets_distance_check("Websocket", ["WebSockets"])[1]
        @test !AutoMerge.meets_distance_check("ThreabTooIs", ["ThreadTools"])[1]
        @test !AutoMerge.meets_distance_check("JiII", ["Jill"])[1]
        @test !AutoMerge.meets_distance_check(
            "FooBar",
            ["FOO8ar"];
            DL_cutoff=0,
            sqrt_normalized_vd_cutoff=0,
            DL_lowercase_cutoff=1,
        )[1]
        @test !AutoMerge.meets_distance_check(
            "ReallyLooooongNameCD", ["ReallyLooooongNameAB"]
        )[1]
    end
    @testset "perform_distance_check" begin
        @test AutoMerge.perform_distance_check(nothing)
        @test AutoMerge.perform_distance_check([GitHub.Label(; name="hi")])
        @test !AutoMerge.perform_distance_check([GitHub.Label(; name="Override AutoMerge: name similarity is okay")])
        @test !AutoMerge.perform_distance_check([GitHub.Label(; name="hi"), GitHub.Label(; name="Override AutoMerge: name similarity is okay")])
    end
    @testset "has_author_approved_label" begin
        @test !AutoMerge.has_package_author_approved_label(nothing)
        @test !AutoMerge.has_package_author_approved_label([GitHub.Label(; name="hi")])
        @test AutoMerge.has_package_author_approved_label([GitHub.Label(; name="Override AutoMerge: package author approved")])
        @test AutoMerge.has_package_author_approved_label([GitHub.Label(; name="hi"), GitHub.Label(; name="Override AutoMerge: package author approved")])
    end
    @testset "pr_comment_is_blocking" begin
        @test AutoMerge.pr_comment_is_blocking(GitHub.Comment(; body="hi"))
        @test AutoMerge.pr_comment_is_blocking(GitHub.Comment(; body="block"))
        @test !AutoMerge.pr_comment_is_blocking(GitHub.Comment(; body="[noblock]"))
        @test !AutoMerge.pr_comment_is_blocking(GitHub.Comment(; body="[noblock]hi"))
        @test !AutoMerge.pr_comment_is_blocking(GitHub.Comment(; body="[merge approved] abc"))
    end
    @testset "`get_all_non_jll_package_names`" begin
        registry_path = joinpath(DEPOT_PATH[1], "registries", "General")
        packages = AutoMerge.get_all_non_jll_package_names(registry_path)
        @test "RegistryCI" ∈ packages
        @test "Logging" ∈ packages
        @test "Poppler_jll" ∉ packages
    end
    @testset "Standard initial version number" begin
        @test AutoMerge.meets_standard_initial_version_number(v"0.0.1")[1]
        @test AutoMerge.meets_standard_initial_version_number(v"0.1.0")[1]
        @test AutoMerge.meets_standard_initial_version_number(v"1.0.0")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"0.0.2")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"0.1.1")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"0.2.0")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"1.0.1")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"1.1.0")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"1.1.1")[1]
        @test AutoMerge.meets_standard_initial_version_number(v"2.0.0")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"2.0.1")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"2.1.0")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"2.1.1")[1]
        @test AutoMerge.meets_standard_initial_version_number(v"3.0.0")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"3.0.1")[1]
        @test !AutoMerge.meets_standard_initial_version_number(v"3.1.0")[1]
    end
    @testset "Repo URL ends with /name.jl.git where name is the package name" begin
        @test AutoMerge.url_has_correct_ending(
            "https://github.com/FluxML/Flux.jl.git", "Flux"
        )[1]
        @test !AutoMerge.url_has_correct_ending(
            "https://github.com/FluxML/Flux.jl", "Flux"
        )[1]
        @test !AutoMerge.url_has_correct_ending(
            "https://github.com/FluxML/Zygote.jl.git", "Flux"
        )[1]
        @test !AutoMerge.url_has_correct_ending(
            "https://github.com/FluxML/Zygote.jl", "Flux"
        )[1]
    end
end

@testset "Guidelines for new versions" begin
    @testset "Sequential version number" begin
        @test AutoMerge.meets_sequential_version_number([v"0.0.1"], v"0.0.2")[1]
        @test AutoMerge.meets_sequential_version_number([v"0.1.0"], v"0.1.1")[1]
        @test AutoMerge.meets_sequential_version_number([v"0.1.0"], v"0.2.0")[1]
        @test AutoMerge.meets_sequential_version_number([v"1.0.0"], v"1.0.1")[1]
        @test AutoMerge.meets_sequential_version_number([v"1.0.0"], v"1.1.0")[1]
        @test AutoMerge.meets_sequential_version_number([v"1.0.0"], v"2.0.0")[1]
        @test !AutoMerge.meets_sequential_version_number([v"0.0.1"], v"0.0.3")[1]
        @test !AutoMerge.meets_sequential_version_number([v"0.1.0"], v"0.3.0")[1]
        @test !AutoMerge.meets_sequential_version_number([v"1.0.0"], v"1.0.2")[1]
        @test !AutoMerge.meets_sequential_version_number([v"1.0.0"], v"1.2.0")[1]
        @test !AutoMerge.meets_sequential_version_number([v"1.0.0"], v"3.0.0")[1]
        @test AutoMerge.meets_sequential_version_number([v"0.1.1"], v"0.2.0")[1]
        @test AutoMerge.meets_sequential_version_number([v"0.1.2"], v"0.2.0")[1]
        @test AutoMerge.meets_sequential_version_number([v"0.1.3"], v"0.2.0")[1]
        @test AutoMerge.meets_sequential_version_number([v"1.0.1"], v"1.1.0")[1]
        @test AutoMerge.meets_sequential_version_number([v"1.0.2"], v"1.1.0")[1]
        @test AutoMerge.meets_sequential_version_number([v"1.0.3"], v"1.1.0")[1]
        @test !AutoMerge.meets_sequential_version_number([v"0.1.1"], v"0.2.1")[1]
        @test !AutoMerge.meets_sequential_version_number([v"0.1.2"], v"0.2.2")[1]
        @test !AutoMerge.meets_sequential_version_number([v"1.0.1"], v"1.1.1")[1]
        @test !AutoMerge.meets_sequential_version_number([v"1.0.3"], v"1.2.0")[1]
        @test !AutoMerge.meets_sequential_version_number([v"1.0.3"], v"1.2.1")[1]
        @test !AutoMerge.meets_sequential_version_number([v"1.0.3"], v"1.1.1")[1]
        @test !AutoMerge.meets_sequential_version_number([v"1.0.0"], v"2.0.1")[1]
        @test !AutoMerge.meets_sequential_version_number([v"1.0.0"], v"2.1.0")[1]
        @test !AutoMerge.meets_sequential_version_number([v"1.0.0"], v"2.1.0")[1]
        @test AutoMerge.meets_sequential_version_number([v"0.0.1"], v"0.0.2")[1]
        @test AutoMerge.meets_sequential_version_number([v"0.0.1"], v"0.1.0")[1]
        @test AutoMerge.meets_sequential_version_number([v"0.0.1"], v"1.0.0")[1]
        @test AutoMerge.meets_sequential_version_number([v"0.0.1", v"0.1.0"], v"0.0.2")[1] # issue #49
        @test AutoMerge.meets_sequential_version_number([v"0.0.1", v"0.1.0"], v"0.1.1")[1]
        @test AutoMerge.meets_sequential_version_number([v"0.0.1", v"0.1.0"], v"0.2.0")[1]
        @test AutoMerge.meets_sequential_version_number([v"0.0.1", v"0.1.0"], v"1.0.0")[1]
        @test AutoMerge.meets_sequential_version_number(
            [v"0.0.1", v"0.1.0", v"1.0.0"], v"0.0.2"
        )[1] # issue #49
        @test AutoMerge.meets_sequential_version_number(
            [v"0.0.1", v"0.1.0", v"1.0.0"], v"0.1.1"
        )[1] # issue #49
        @test AutoMerge.meets_sequential_version_number(
            [v"0.0.1", v"0.1.0", v"1.0.0"], v"0.2.0"
        )[1]
        @test AutoMerge.meets_sequential_version_number(
            [v"0.0.1", v"0.1.0", v"1.0.0"], v"1.0.1"
        )[1]
        @test AutoMerge.meets_sequential_version_number(
            [v"0.0.1", v"0.1.0", v"1.0.0"], v"1.1.0"
        )[1]
        @test AutoMerge.meets_sequential_version_number(
            [v"0.0.1", v"0.1.0", v"1.0.0"], v"2.0.0"
        )[1]
        @test AutoMerge.meets_sequential_version_number([v"1", v"2"], v"3")[1]
        @test AutoMerge.meets_sequential_version_number([v"2", v"1"], v"3")[1]
        @test !AutoMerge.meets_sequential_version_number([v"1", v"2"], v"2")[1]
        @test !AutoMerge.meets_sequential_version_number([v"1", v"2", v"3"], v"2")[1]
        @test !AutoMerge.meets_sequential_version_number([v"1", v"2"], v"4")[1]
        @test !AutoMerge.meets_sequential_version_number([v"1", v"2"], v"0")[1]
        @test !AutoMerge.meets_sequential_version_number([v"1", v"2"], v"0.9")[1]
        @test AutoMerge.meets_sequential_version_number([v"1", v"2"], v"2.0.1")[1]
        @test AutoMerge.meets_sequential_version_number([v"1", v"2"], v"2.1")[1]
        @test AutoMerge.meets_sequential_version_number([v"1", v"2"], v"3")[1]
        let vers = [v"2", v"1"]
            @test AutoMerge.meets_sequential_version_number(vers, v"3")[1]
            @test vers == [v"2", v"1"] # no mutation
        end
    end
    @testset "Patch releases cannot narrow Julia compat" begin
        r1 = Pkg.Types.VersionRange("1.3-1.7")
        r2 = Pkg.Types.VersionRange("1.4-1.7")
        r3 = Pkg.Types.VersionRange("1.3-1.6")
        @test AutoMerge.range_did_not_narrow(r1, r1)[1]
        @test AutoMerge.range_did_not_narrow(r2, r2)[1]
        @test AutoMerge.range_did_not_narrow(r3, r3)[1]
        @test AutoMerge.range_did_not_narrow(r2, r1)[1]
        @test AutoMerge.range_did_not_narrow(r3, r1)[1]
        @test !AutoMerge.range_did_not_narrow(r1, r2)[1]
        @test !AutoMerge.range_did_not_narrow(r1, r3)[1]
        @test !AutoMerge.range_did_not_narrow(r2, r3)[1]
        @test !AutoMerge.range_did_not_narrow(r3, r2)[1]
    end

    @testset "Breaking change releases must have explanatory release notes" begin
        body_good = """
        <!-- BEGIN RELEASE NOTES -->
        `````
        ## Breaking changes
        - something
        - something else
        `````
        <!-- END RELEASE NOTES -->
        """
        body_good_changelog = """
        <!-- BEGIN RELEASE NOTES -->
        `````
        See the changelog at xyz for a list of changes.
        `````
        <!-- END RELEASE NOTES -->
        """
        body_bad = """
        <!-- BEGIN RELEASE NOTES -->
        `````
        ## Features
        - something
        - something else
        `````
        <!-- END RELEASE NOTES -->
        """
        body_bad_no_notes = ""
        breaking_label = GitHub.Label(; name="BREAKING")
        @test AutoMerge.meets_breaking_explanation_check([breaking_label], body_good, v"1.0.0")[1]
        @test AutoMerge.meets_breaking_explanation_check([breaking_label], body_good_changelog, v"1.0.0")[1]
        @test !AutoMerge.meets_breaking_explanation_check([breaking_label], body_bad, v"1.0.0")[1]
        @test !AutoMerge.meets_breaking_explanation_check([breaking_label], body_bad_no_notes, v"1.0.0")[1]

        # Maybe this should fail as the label isn't applied by JuliaRegistrator, so the version isn't breaking?
        @test AutoMerge.meets_breaking_explanation_check([], body_good, v"1.0.0")[1]
    end
end

@testset "Guidelines for both new packages and new versions" begin
    @testset "Version numbers may not contain prerelease data" begin
        @test AutoMerge.meets_version_number_no_prerelease(v"1.2.3")[1]
        @test !AutoMerge.meets_version_number_no_prerelease(v"1.2.3-alpha")[1]
        @test AutoMerge.meets_version_number_no_prerelease(v"1.2.3+456")[1]
        @test !AutoMerge.meets_version_number_no_prerelease(v"1.2.3-alpha+456")[1]
    end
    @testset "Version numbers may not contain build data" begin
        @test AutoMerge.meets_version_number_no_build(v"1.2.3")[1]
        @test AutoMerge.meets_version_number_no_build(v"1.2.3-alpha")[1]
        @test !AutoMerge.meets_version_number_no_build(v"1.2.3+456")[1]
        @test !AutoMerge.meets_version_number_no_build(v"1.2.3-alpha+456")[1]
    end
end

@testset "Unit tests" begin
    @testset "assert.jl" begin
        @test nothing == @test_nowarn AutoMerge.always_assert(1 == 1)
        @test_throws AutoMerge.AlwaysAssertionError AutoMerge.always_assert(1 == 2)
    end
    @testset "_find_lowercase_duplicates" begin
        @test AutoMerge._find_lowercase_duplicates(("a", "b", "A")) == ("a", "A")
        @test AutoMerge._find_lowercase_duplicates(("ab", "bb", "aB")) == ("ab", "aB")
        @test AutoMerge._find_lowercase_duplicates(["ab", "bc"]) === nothing
        @test AutoMerge._find_lowercase_duplicates(("ab", "bb", "aB", "AB")) == ("ab", "aB")
    end
    @testset "meets_file_dir_name_check" begin
        @test AutoMerge.meets_file_dir_name_check("hi")[1]
        @test AutoMerge.meets_file_dir_name_check("hi bye")[1]
        @test AutoMerge.meets_file_dir_name_check("hi.txt")[1]
        @test AutoMerge.meets_file_dir_name_check("hi.con")[1]
        @test !AutoMerge.meets_file_dir_name_check("con")[1]
        @test !AutoMerge.meets_file_dir_name_check("lpt5")[1]
        @test !AutoMerge.meets_file_dir_name_check("hi.")[1]
        @test !AutoMerge.meets_file_dir_name_check("hi.txt.")[1]
        @test !AutoMerge.meets_file_dir_name_check("hi ")[1]
        @test !AutoMerge.meets_file_dir_name_check("hi:")[1]
        @test !AutoMerge.meets_file_dir_name_check("hi:bye")[1]
        @test !AutoMerge.meets_file_dir_name_check("hi?bye")[1]
        @test !AutoMerge.meets_file_dir_name_check("hi>bye")[1]
    end
    @testset "meets_src_names_ok: duplicates" begin
        @test !AutoMerge.meets_src_names_ok("DOES NOT EXIST")[1]
        tmp = mktempdir()
        @test !AutoMerge.meets_src_names_ok(tmp)[1]
        mkdir(joinpath(tmp, "src"))
        @test AutoMerge.meets_src_names_ok(tmp)[1]
        touch(joinpath(tmp, "src", "a"))
        @test AutoMerge.meets_src_names_ok(tmp)[1]

        if !isdir(joinpath(tmp, "SRC"))
            mkdir(joinpath(tmp, "src", "A"))

            # dir vs file fails
            @test !AutoMerge.meets_src_names_ok(tmp)[1]
            rm(joinpath(tmp, "src", "a"))

            @test AutoMerge.meets_src_names_ok(tmp)[1]

            touch(joinpath(tmp, "src", "A", "b"))
            @test AutoMerge.meets_src_names_ok(tmp)[1]
            touch(joinpath(tmp, "src", "b"))
            # repetition at different levels is OK
            @test AutoMerge.meets_src_names_ok(tmp)[1]

            touch(joinpath(tmp, "src", "A", "B"))
            # repetition at the same level is not OK
            @test !AutoMerge.meets_src_names_ok(tmp)[1]
        else
            @warn "Case insensitive filesystem detected, so skipping some `meets_src_files_distinct` checks."
        end
    end
    @testset "meets_src_names_ok: names" begin
        tmp = mktempdir()
        mkdir(joinpath(tmp, "src"))
        @test AutoMerge.meets_src_names_ok(tmp)[1]
        mkdir(joinpath(tmp, "src", "B"))
        @test AutoMerge.meets_src_names_ok(tmp)[1]
        touch(joinpath(tmp, "src", "B", "con"))
        @test !AutoMerge.meets_src_names_ok(tmp)[1]
    end
    @testset "pull-requests.jl" begin
        @testset "regexes" begin
            @testset "new_package_title_regex" begin
                @test occursin(
                    AutoMerge.new_package_title_regex, "New package: HelloWorld v1.2.3"
                )
                # This one is not a valid package name, but nonetheless we want AutoMerge
                # to run and fail.
                @test occursin(
                    AutoMerge.new_package_title_regex, "New package: Mathieu-Functions v1.0.0"
                )
                @test occursin(
                    AutoMerge.new_package_title_regex, "New package: HelloWorld v1.2.3+0"
                )
                @test !occursin(
                    AutoMerge.new_package_title_regex, "New version: HelloWorld v1.2.3"
                )
                @test !occursin(
                    AutoMerge.new_package_title_regex, "New version: HelloWorld v1.2.3+0"
                )
                let
                    m = match(
                        AutoMerge.new_package_title_regex,
                        "New package: HelloWorld v1.2.3+0",
                    )
                    @test length(m.captures) == 2
                    @test m.captures[1] == "HelloWorld"
                    @test m.captures[2] == "1.2.3+0"
                end
            end
            @testset "new_version_title_regex" begin
                @test !occursin(
                    AutoMerge.new_version_title_regex, "New package: HelloWorld v1.2.3"
                )
                @test !occursin(
                    AutoMerge.new_version_title_regex, "New package: HelloWorld v1.2.3+0"
                )
                @test occursin(
                    AutoMerge.new_version_title_regex, "New version: HelloWorld v1.2.3"
                )
                @test occursin(
                    AutoMerge.new_version_title_regex, "New version: HelloWorld v1.2.3+0"
                )
                let
                    m = match(
                        AutoMerge.new_version_title_regex,
                        "New version: HelloWorld v1.2.3+0",
                    )
                    @test length(m.captures) == 2
                    @test m.captures[1] == "HelloWorld"
                    @test m.captures[2] == "1.2.3+0"
                end
            end
            @testset "commit_regex" begin
                commit_hash = "012345678901234567890123456789abcdef0000"
                @test occursin(AutoMerge.commit_regex, "- Foo\n- Commit: $(commit_hash)\n- Bar")
                @test occursin(AutoMerge.commit_regex, "- Commit: $(commit_hash)\n- Bar")
                @test occursin(AutoMerge.commit_regex, "- Foo\n- Commit: $(commit_hash)")
                @test occursin(AutoMerge.commit_regex, "- Commit: $(commit_hash)")
                @test occursin(AutoMerge.commit_regex, "Commit: $(commit_hash)")
                @test occursin(AutoMerge.commit_regex, "* Foo\n* Commit: $(commit_hash)\n* Bar")
                @test occursin(AutoMerge.commit_regex, "* Commit: $(commit_hash)\n* Bar")
                @test occursin(AutoMerge.commit_regex, "* Foo\n* Commit: $(commit_hash)")
                @test occursin(AutoMerge.commit_regex, "* Commit: $(commit_hash)")
                @test !occursin(AutoMerge.commit_regex, "- Commit: mycommit hash 123")
                let
                    m = match(
                        AutoMerge.commit_regex, "- Foo\n- Commit: $(commit_hash)\n- Bar"
                    )
                    @test length(m.captures) == 1
                    @test m.captures[1] == "$(commit_hash)"
                end
            end
        end
    end
    @testset "semver.jl" begin
        @test AutoMerge.leftmost_nonzero(v"1.2.3") == :major
        @test AutoMerge.leftmost_nonzero(v"0.2.3") == :minor
        @test AutoMerge.leftmost_nonzero(v"0.0.3") == :patch
        @test_throws ArgumentError AutoMerge.leftmost_nonzero(v"0")
        @test_throws ArgumentError AutoMerge.leftmost_nonzero(v"0.0")
        @test_throws ArgumentError AutoMerge.leftmost_nonzero(v"0.0.0")
        @test_throws ArgumentError AutoMerge.is_breaking(v"1.2.3", v"1.2.0")
        @test_throws ArgumentError AutoMerge.is_breaking(v"1.2.3", v"1.2.2")
        @test_throws ArgumentError AutoMerge.is_breaking(v"1.2.3", v"1.2.3")
        @test !AutoMerge.is_breaking(v"1.2.3", v"1.2.4")
        @test !AutoMerge.is_breaking(v"1.2.3", v"1.2.5")
        @test !AutoMerge.is_breaking(v"1.2.3", v"1.3.0")
        @test !AutoMerge.is_breaking(v"1.2.3", v"1.4.0")
        @test AutoMerge.is_breaking(v"1.2.3", v"2.0.0")
        @test AutoMerge.is_breaking(v"1.2.3", v"2.1.0")
        @test AutoMerge.is_breaking(v"1.2.3", v"2.2.0")
        @test AutoMerge.is_breaking(v"1.2.3", v"3.0.0")
        @test AutoMerge.is_breaking(v"1.2.3", v"3.1.0")
        @test AutoMerge.is_breaking(v"1.2.3", v"3.2.0")
        @test !AutoMerge.is_breaking(v"0.2.3", v"0.2.4")
        @test !AutoMerge.is_breaking(v"0.2.3", v"0.2.5")
        @test AutoMerge.is_breaking(v"0.2.3", v"0.3.0")
        @test AutoMerge.is_breaking(v"0.2.3", v"0.4.0")
        @test AutoMerge.is_breaking(v"0.2.3", v"1.0.0")
        @test AutoMerge.is_breaking(v"0.2.3", v"1.1.0")
        @test AutoMerge.is_breaking(v"0.2.3", v"1.2.0")
        @test AutoMerge.is_breaking(v"0.2.3", v"2.0.0")
        @test AutoMerge.is_breaking(v"0.2.3", v"2.1.0")
        @test AutoMerge.is_breaking(v"0.2.3", v"2.2.0")
        @test AutoMerge.is_breaking(v"0.0.3", v"0.0.4")
        @test AutoMerge.is_breaking(v"0.0.3", v"0.0.5")
        @test AutoMerge.is_breaking(v"0.0.3", v"0.1.0")
        @test AutoMerge.is_breaking(v"0.0.3", v"0.2.0")
        @test AutoMerge.is_breaking(v"0.0.3", v"1.0.0")
        @test AutoMerge.is_breaking(v"0.0.3", v"1.1.0")
        @test AutoMerge.is_breaking(v"0.0.3", v"1.2.0")
        @test AutoMerge.is_breaking(v"0.0.3", v"2.0.0")
        @test AutoMerge.is_breaking(v"0.0.3", v"2.1.0")
        @test AutoMerge.is_breaking(v"0.0.3", v"2.2.0")
        @test AutoMerge.thispatch(v"1.2.3") == v"1.2.3"
        @test AutoMerge.thisminor(v"1.2.3") == v"1.2"
        @test AutoMerge.thismajor(v"1.2.3") == v"1"
        @test AutoMerge.nextpatch(v"1.2.3") == v"1.2.4"
        @test AutoMerge.nextminor(v"1.2") == v"1.3"
        @test AutoMerge.nextminor(v"1.2.3") == v"1.3"
        @test AutoMerge.nextmajor(v"1") == v"2"
        @test AutoMerge.nextmajor(v"1.2") == v"2"
        @test AutoMerge.nextmajor(v"1.2.3") == v"2"
        @test AutoMerge.difference(v"1", v"2") == v"1"
        @test AutoMerge.difference(v"1", v"1") isa AutoMerge.ErrorCannotComputeVersionDifference
        @test AutoMerge.difference(v"2", v"1") isa AutoMerge.ErrorCannotComputeVersionDifference
        @test !AutoMerge._has_upper_bound(Pkg.Types.VersionRange("0"))
        @test AutoMerge._has_upper_bound(Pkg.Types.VersionRange("1"))
        @test !AutoMerge._has_upper_bound(Pkg.Types.VersionRange("*"))
        @test !AutoMerge._has_upper_bound(Pkg.Types.VersionRange("0-1"))
        @test AutoMerge._has_upper_bound(Pkg.Types.VersionRange("1-2"))
        @test !AutoMerge._has_upper_bound(Pkg.Types.VersionRange("1-*"))
        @test !AutoMerge._has_upper_bound(Pkg.Types.VersionRange("0-0"))
        @test !AutoMerge._has_upper_bound(Pkg.Types.VersionRange("0-*"))
        @test !AutoMerge._has_upper_bound(Pkg.Types.VersionRange("0.2-0"))
        @test !AutoMerge._has_upper_bound(Pkg.Types.VersionRange("0.2-*"))

        if Base.VERSION >= v"1.4-"
            # We skip this test on Julia 1.3, because it requires `Base.only`.
            @testset "julia_compat" begin
                registry_path = registry_path = joinpath(DEPOT_PATH[1], "registries", "General")
                @test AutoMerge.julia_compat("Example", v"0.5.3", registry_path) isa AbstractVector{<:Pkg.Types.VersionRange}
            end
        end
    end
end

@testset "CIService unit testing" begin
    @testset "Travis CI" begin
        # pull request build
        withenv(
            "TRAVIS_BRANCH" => "master",
            "TRAVIS_EVENT_TYPE" => "pull_request",
            "TRAVIS_PULL_REQUEST" => "42",
            "TRAVIS_PULL_REQUEST_SHA" => "abc123",
            "TRAVIS_BUILD_DIR" => "/tmp/clone",
        ) do
            cfg = AutoMerge.TravisCI()
            @test AutoMerge.conditions_met_for_pr_build(cfg; master_branch="master")
            @test !AutoMerge.conditions_met_for_pr_build(cfg; master_branch="retsam")
            @test !AutoMerge.conditions_met_for_merge_build(cfg; master_branch="master")
            @test AutoMerge.pull_request_number(cfg) == 42
            @test AutoMerge.current_pr_head_commit_sha(cfg) == "abc123"
            @test AutoMerge.directory_of_cloned_registry(cfg) == "/tmp/clone"
        end
        # merge build with cron
        withenv(
            "TRAVIS_BRANCH" => "master",
            "TRAVIS_EVENT_TYPE" => "cron",
            "TRAVIS_PULL_REQUEST" => "false",
            "TRAVIS_PULL_REQUEST_SHA" => "abc123",
            "TRAVIS_BUILD_DIR" => "/tmp/clone",
        ) do
            cfg = AutoMerge.TravisCI()
            @test !AutoMerge.conditions_met_for_pr_build(cfg; master_branch="master")
            @test AutoMerge.conditions_met_for_merge_build(cfg; master_branch="master")
            @test !AutoMerge.conditions_met_for_merge_build(cfg; master_branch="retsam")
            @test !AutoMerge.conditions_met_for_merge_build(
                AutoMerge.TravisCI(; enable_cron_builds=false); master_branch="master"
            )
            @test AutoMerge.current_pr_head_commit_sha(cfg) == "abc123"
            @test AutoMerge.directory_of_cloned_registry(cfg) == "/tmp/clone"
        end
        # merge build with api
        withenv(
            "TRAVIS_BRANCH" => "master",
            "TRAVIS_EVENT_TYPE" => "api",
            "TRAVIS_PULL_REQUEST" => "false",
            "TRAVIS_PULL_REQUEST_SHA" => "abc123",
            "TRAVIS_BUILD_DIR" => "/tmp/clone",
        ) do
            cfg = AutoMerge.TravisCI()
            @test !AutoMerge.conditions_met_for_pr_build(cfg; master_branch="master")
            @test AutoMerge.conditions_met_for_merge_build(cfg; master_branch="master")
            @test !AutoMerge.conditions_met_for_merge_build(cfg; master_branch="retsam")
            @test !AutoMerge.conditions_met_for_merge_build(
                AutoMerge.TravisCI(; enable_api_builds=false); master_branch="master"
            )
            @test AutoMerge.current_pr_head_commit_sha(cfg) == "abc123"
            @test AutoMerge.directory_of_cloned_registry(cfg) == "/tmp/clone"
        end
        # neither pull request nor merge build
        withenv("TRAVIS_BRANCH" => nothing, "TRAVIS_EVENT_TYPE" => nothing) do
            cfg = AutoMerge.TravisCI()
            @test !AutoMerge.conditions_met_for_pr_build(cfg; master_branch="master")
            @test !AutoMerge.conditions_met_for_merge_build(cfg; master_branch="master")
        end
    end

    @testset "GitHub Actions" begin
        mktemp() do file, io
            # mimic the workflow file for GitHub Actions
            workflow = Dict("pull_request" => Dict("head" => Dict("sha" => "abc123")))
            JSON.print(io, workflow)
            close(io)

            # pull request build
            withenv(
                "GITHUB_REF" => "refs/pull/42/merge",
                "GITHUB_EVENT_NAME" => "pull_request",
                "GITHUB_SHA" => "123abc", # "wrong", should be taken from workflow file
                "GITHUB_EVENT_PATH" => file,
                "GITHUB_WORKSPACE" => "/tmp/clone",
            ) do
                cfg = AutoMerge.GitHubActions()
                @test AutoMerge.conditions_met_for_pr_build(cfg; master_branch="master")
                @test_broken !AutoMerge.conditions_met_for_pr_build(
                    cfg; master_branch="retsam"
                )
                @test !AutoMerge.conditions_met_for_merge_build(cfg; master_branch="master")
                @test AutoMerge.pull_request_number(cfg) == 42
                @test AutoMerge.current_pr_head_commit_sha(cfg) == "abc123"
                @test AutoMerge.directory_of_cloned_registry(cfg) == "/tmp/clone"
            end
            # merge build with schedule: cron
            withenv(
                "GITHUB_REF" => "refs/heads/master",
                "GITHUB_EVENT_NAME" => "schedule",
                "GITHUB_SHA" => "123abc",
                "GITHUB_WORKSPACE" => "/tmp/clone",
            ) do
                cfg = AutoMerge.GitHubActions()
                @test !AutoMerge.conditions_met_for_pr_build(cfg; master_branch="master")
                @test AutoMerge.conditions_met_for_merge_build(cfg; master_branch="master")
                @test !AutoMerge.conditions_met_for_merge_build(cfg; master_branch="retsam")
                @test !AutoMerge.conditions_met_for_merge_build(
                    AutoMerge.GitHubActions(; enable_cron_builds=false);
                    master_branch="master",
                )
                @test AutoMerge.directory_of_cloned_registry(cfg) == "/tmp/clone"
            end
            # neither pull request nor merge build
            withenv("GITHUB_REF" => nothing, "GITHUB_EVENT_NAME" => nothing) do
                cfg = AutoMerge.GitHubActions()
                @test !AutoMerge.conditions_met_for_pr_build(cfg; master_branch="master")
                @test !AutoMerge.conditions_met_for_merge_build(cfg; master_branch="master")
            end
        end
    end

    @testset "auto detection" begin
        withenv(
            "TRAVIS_REPO_SLUG" => "JuliaRegistries/General", "GITHUB_REPOSITORY" => nothing
        ) do
            @test AutoMerge.auto_detect_ci_service() == AutoMerge.TravisCI()
            @test AutoMerge.auto_detect_ci_service(; env=ENV) == AutoMerge.TravisCI()
        end
        withenv(
            "TRAVIS_REPO_SLUG" => nothing, "GITHUB_REPOSITORY" => "JuliaRegistries/General"
        ) do
            @test AutoMerge.auto_detect_ci_service() == AutoMerge.GitHubActions()
            @test AutoMerge.auto_detect_ci_service(; env=ENV) == AutoMerge.GitHubActions()
        end
    end

    @testset "`AutoMerge.meets_version_has_osi_license`" begin
        withenv("JULIA_PKG_PRECOMPILE_AUTO" => "0") do
            # Let's install a fresh depot in a temporary directory
            # and add some packages to inspect.
            tmp_depot = setup_global_depot()
            function has_osi_license_in_depot(pkg)
                return AutoMerge.meets_version_has_osi_license(
                    pkg; pkg_code_path=pkgdir_from_depot(tmp_depot, pkg)
                )
            end
            # Let's test ourselves and some of our dependencies that just have MIT licenses:
            result = has_osi_license_in_depot("RegistryCI")
            @test result[1]
            result = has_osi_license_in_depot("UnbalancedOptimalTransport")
            @test result[1]
            result = has_osi_license_in_depot("VisualStringDistances")
            @test result[1]

            # Now, what happens if there's also a non-OSI license in another file?
            pkg_path = pkgdir_from_depot(tmp_depot, "UnbalancedOptimalTransport")
            open(joinpath(pkg_path, "LICENSE2"); write=true) do io
                cc0_bytes = read(joinpath(@__DIR__, "license_data", "CC0.txt"))
                println(io)
                write(io, cc0_bytes)
            end
            result = has_osi_license_in_depot("UnbalancedOptimalTransport")
            @test result[1]

            # What if we also remove the original license, leaving only the CC0 license?
            rm(joinpath(pkg_path, "LICENSE"))
            result = has_osi_license_in_depot("UnbalancedOptimalTransport")
            @test !result[1]

            # What about no license at all?
            pkg_path = pkgdir_from_depot(tmp_depot, "VisualStringDistances")
            rm(joinpath(pkg_path, "LICENSE"))
            result = has_osi_license_in_depot("VisualStringDistances")
            @test !result[1]
        end
    end
end
