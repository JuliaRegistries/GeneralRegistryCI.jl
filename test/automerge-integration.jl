include("automerge-integration-utils.jl")

AUTOMERGE_INTEGRATION_TEST_REPO = ENV["AUTOMERGE_INTEGRATION_TEST_REPO"]::String
TEST_USER_GITHUB_TOKEN = ENV["BCBI_TEST_USER_GITHUB_TOKEN"]::String
GIT = "git"
auth = GitHub.authenticate(TEST_USER_GITHUB_TOKEN)
whoami = RegistryCI.AutoMerge.username(auth)
repo_url_without_auth = "https://github.com/$(AUTOMERGE_INTEGRATION_TEST_REPO)"
repo_url_with_auth = "https://$(whoami):$(TEST_USER_GITHUB_TOKEN)@github.com/$(AUTOMERGE_INTEGRATION_TEST_REPO)"
repo = GitHub.repo(AUTOMERGE_INTEGRATION_TEST_REPO; auth = auth)
@test success(`$(GIT) --version`)
@info("Authenticated to GitHub as \"$(whoami)\"")

close_all_pull_requests(repo; auth = auth, state = "open")
delete_stale_branches(repo_url_with_auth; GIT = GIT)

with_master_branch(templates("master_1"), "master"; GIT = GIT, repo_url = repo_url_with_auth) do master_1
    with_feature_branch(templates("feature_1"), master_1; GIT = GIT, repo_url = repo_url_with_auth) do feature_1
        params = Dict("title" => "New package: Requires v1.0.0",
                      "head" => feature_1,
                      "base" => master_1)
        pr = GitHub.create_pull_request(repo; auth = auth, params = params)
        println(typeof(pr))
    end
end

close_all_pull_requests(repo; auth = auth, state = "open")
delete_stale_branches(repo_url_with_auth; GIT = GIT)
