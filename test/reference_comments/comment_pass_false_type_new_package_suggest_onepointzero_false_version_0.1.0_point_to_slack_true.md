Hello, I am an automated registration bot. I help manage the registration process by checking your registration against a set of [AutoMerge guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/). Meeting these guidelines is only required for the pull request to be **merged automatically**. However, it is **strongly recommended** to follow them, since otherwise the pull request needs to be manually reviewed and merged by a human.

### 1. New package registration

Since you are registering a new package, please make sure that you have read the [package naming guidelines](https://julialang.github.io/Pkg.jl/dev/creating-packages/#Package-naming-guidelines-1).

### 2. [AutoMerge Guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/) which are not met ❌

- Example guideline failed. Please fix it.

### 3. *Needs action*: here's what to do next

1. Please try to update your package to conform to these guidelines. The [General registry's README](https://github.com/JuliaRegistries/General/blob/master/README.md) has an FAQ that can help figure out how to do so. You can also leave a comment on this PR (and include `[noblock]`) or send a message to the `#pkg-registration` channel in the [public Julia Slack](https://julialang.org/slack/) to ask for help. Include a link to this pull request if you do so!
2. After you have fixed the AutoMerge issues, simply retrigger Registrator, the same way you did in the initial registration. This will automatically update this pull request. You do not need to change the version number in your `Project.toml` file (unless of course the AutoMerge issue is that you skipped a version number, in which case you should change the version number).

If you do not want to fix the AutoMerge issues, please post a comment explaining why you would like this pull request to be manually merged. Then, send a message to the `#pkg-registration` channel in the [public Julia Slack](https://julialang.org/slack/) to ask for help.

### 4. To pause or stop registration

If you want to prevent this pull request from being auto-merged, simply leave a comment. If you want to post a comment without blocking auto-merging, you must include the text `[noblock]` in your comment. You can edit blocking comments, adding `[noblock]` to them in order to unblock auto-merging.

<!-- [noblock] -->