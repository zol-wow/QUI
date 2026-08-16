local function read(path)
    local file = assert(io.open(path, "rb"), "missing workflow: " .. path)
    local body = file:read("*a")
    file:close()
    return body
end

local function contains(body, needle, message)
    assert(body:find(needle, 1, true), message .. ": " .. needle)
end

local workflows = {
    ".github/workflows/codex.yml",
    ".github/workflows/codex-code-review.yml",
    ".github/workflows/codex-issue-triage.yml",
}

for _, path in ipairs(workflows) do
    local body = read(path)
    contains(body, "group: codex-auth-json", path .. " must serialize auth refresh")
    contains(body, "persist-credentials: false", path .. " must hide checkout credentials from Codex")
    contains(body, "secrets.CODEX_AUTH_JSON", path .. " must restore account auth")
    contains(body, "npm install -g @openai/codex", path .. " must install Codex")
    contains(body, "| codex exec", path .. " must run Codex directly")
    contains(body, "--ignore-user-config --ignore-rules", path .. " must isolate runner configuration")
    contains(body, "kernel.apparmor_restrict_unprivileged_userns=0", path .. " must enable Bubblewrap")
    contains(body, "printf '/.lua/\\n/.luarocks/\\n' >> .git/info/exclude", path .. " must ignore runner toolchains")
    contains(body, "secrets.CODEX_AUTH_WRITER_TOKEN", path .. " must persist refreshed auth")
    contains(body, "gh secret set CODEX_AUTH_JSON", path .. " must write back Codex's auth file")
    contains(body, "trap 'rm -f \"$CODEX_HOME/auth.json\"' EXIT", path .. " must delete account auth")
    assert(not body:find("openai/codex-action", 1, true), path .. " cannot use the API-key-only Codex action")
    assert(not body:find("anthropic", 1, true), path .. " still references Anthropic")
    assert(not body:find("CLAUDE_CODE_OAUTH_TOKEN", 1, true), path .. " still references Claude auth")

    local codex = assert(body:find("| codex exec", 1, true))
    local writer = assert(body:find("secrets.CODEX_AUTH_WRITER_TOKEN", 1, true))
    assert(writer > codex, path .. " exposes the writer token before Codex finishes")
end

local onDemand = read(workflows[1])
local review = read(workflows[2])
local triage = read(workflows[3])

contains(onDemand, "contains(github.event.issue.body, '@codex')", "on-demand issue mention missing")
contains(onDemand, "github.event_name == 'issue_comment'", "issue comments must use their own trust check")
contains(onDemand, "github.event_name == 'pull_request_review_comment'", "review comments must use their own trust check")
contains(onDemand, "github.event_name == 'pull_request_review'", "reviews must use their own trust check")
contains(onDemand, "github.event_name == 'issues'", "issues must use their own trust check")
contains(onDemand, "bash tools/test.sh", "on-demand changes must pass the canonical gate")
contains(triage, "contains(github.event.issue.body, '@codex')", "triage partition mention missing")
contains(review, "github.event.pull_request.draft == false", "draft PR review exclusion missing")
contains(review, "github.event.pull_request.head.repo.full_name == github.repository", "fork review exclusion missing")
contains(review, "--sandbox read-only", "reviewer must not edit the checkout")
contains(review, "Run no repository-wide", "reviewer must not run write-producing gates")
contains(triage, "ref: alpha", "triage must branch from alpha")
contains(triage, "bash tools/test.sh", "triage changes must pass the canonical gate")
contains(triage, "gh pr create --draft --base alpha", "triage draft PR gate missing")
contains(triage, "git diff --cached --quiet", "triage must reject staged changes")
contains(triage, ".github/*|tools/*|tests/*|.luacheckrc", "triage forbidden-path gate missing")

local onValidate = assert(onDemand:find("- name: Validate Codex result", 1, true))
local onGates = assert(onDemand:find("bash tools/test.sh", onValidate, true))
local onPublish = assert(onDemand:find("- name: Publish result", onGates, true))
assert(onValidate < onGates and onGates < onPublish, "on-demand gates must run before credentials are published")

local triageValidate = assert(triage:find("- name: Validate Codex triage", 1, true))
local triageGates = assert(triage:find("bash tools/test.sh", triageValidate, true))
local triagePublish = assert(triage:find("- name: Publish triage", triageGates, true))
assert(triageValidate < triageGates and triageGates < triagePublish, "triage gates must run before credentials are published")

for _, path in ipairs({
    ".github/workflows/claude.yml",
    ".github/workflows/claude-code-review.yml",
    ".github/workflows/claude-issue-triage.yml",
}) do
    assert(io.open(path, "rb") == nil, "legacy Claude workflow still exists: " .. path)
end

print("codex_workflow_contract_test OK")
