Hello, I am an automated registration bot. I help manage the registration process by checking your registration against a set of [AutoMerge guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/). Meeting these guidelines is only required for the pull request to be **merged automatically**. However, it is **strongly recommended** to follow them, since otherwise the pull request needs to be manually reviewed and merged by a human.

### 1. [AutoMerge Guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/) are all met! ✅

Your new version registration met all of the guidelines for auto-merging and is scheduled to be merged in the next round.

### 2. Declare v1.0?

On a separate note, I see that you are registering a release with a version number of the form `v0.X.Y`.

Does your package have a stable public API? If so, then it's time for you to register version `v1.0.0` of your package. (This is not a requirement. It's just a recommendation.)

If your package does not yet have a stable public API, then of course you are not yet ready to release version `v1.0.0`.

### 3. To pause or stop registration

If you want to prevent this pull request from being auto-merged, simply leave a comment. If you want to post a comment without blocking auto-merging, you must include the text `[noblock]` in your comment. You can edit blocking comments, adding `[noblock]` to them in order to unblock auto-merging.

<!-- [noblock] -->