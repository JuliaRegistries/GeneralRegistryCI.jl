Hello, I am an automated registration bot. I help manage the registration process by checking your registration against a set of [AutoMerge guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/). If all these guidelines are met, this pull request will be merged automatically, completing your registration. It is **strongly recommended** to follow the guidelines, since otherwise the pull request needs to be manually reviewed and merged by a human.

## 1. New package registration

Please make sure that you have read the [package naming guidelines](https://julialang.github.io/Pkg.jl/dev/creating-packages/#Package-naming-guidelines-1).

## 2. [AutoMerge Guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/) which are not met ❌

- The following dependencies do not have a `[compat]` entry that is upper-bounded and only includes a finite number of breaking releases: julia
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

- This is a breaking change, but the release notes do not mention it. Please add a mention of the breaking change to the release notes (use the words "breaking" or "changelog").
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

    Either way, you need to mention the words "breaking" or "changelog", even if it is just to say "there are no breaking changes", or "see the changelog".
    </details>

- This is a breaking change, but no release notes have been provided. Please add release notes that explain the breaking change.
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

    Either way, you need to mention the words "breaking" or "changelog", even if it is just to say "there are no breaking changes", or "see the changelog".
    </details>

- This is a breaking change, but the release notes do not mention it. Please add a mention of the breaking change to the release notes (use the words "breaking" or "changelog").
Given this is a pre-v1.0.0 release, you may have not intended to make a breaking change release. [More information](https://pkgdocs.julialang.org/v1/compatibility/#compat-pre-1.0) on Julia's handling of pre-v1.0.0 versioning.
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

    Either way, you need to mention the words "breaking" or "changelog", even if it is just to say "there are no breaking changes", or "see the changelog".
    </details>

- Example guideline failed. Please fix it.

## 3. *Needs action*: here's what to do next

1. Please try to update your package to conform to these guidelines. The [General registry's README](https://github.com/JuliaRegistries/General/blob/master/README.md) has an FAQ that can help figure out how to do so.
2. After you have fixed the AutoMerge issues, simply retrigger Registrator, the same way you did in the initial registration. This will automatically update this pull request. You do not need to change the version number in your `Project.toml` file (unless the AutoMerge issue is that you skipped a version number).

If you need help fixing the AutoMerge issues, or want your pull request to be manually merged instead, please post a comment explaining what you need help with or why you would like this pull request to be manually merged. Then, send a message to the `#pkg-registration` channel in the [public Julia Slack](https://julialang.org/slack/) for better visibility.

## 4. Declare v1.0?

On a separate note, I see that you are registering a release with a version number of the form `v0.X.Y`.

Does your package have a stable public API? If so, then it's time for you to register version `v1.0.0` of your package. (This is not a requirement. It's just a recommendation.)

If your package does not yet have a stable public API, then of course you are not yet ready to release version `v1.0.0`.

## 5. To pause or stop registration

If you want to prevent this pull request from being auto-merged, simply leave a comment. If you want to post a comment without blocking auto-merging, you must include the text `[noblock]` in your comment.

_Tip: You can edit blocking comments to add `[noblock]` in order to unblock auto-merging._

<!-- [noblock] -->