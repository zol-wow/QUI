-- Gate wrapper: runs the secret-sentinel fixture's self-test inside the
-- tools/test.sh unit glob, so the CAVEAT-pinning assertions (cross-type __eq
-- never fires, __len inert, format("%s", table) throws) run in CI instead of
-- only under a manual `--test` invocation.
local helper = dofile("tests/helpers/secret_sentinel.lua")
assert(type(helper) == "table", "secret_sentinel helper must return its module table")
assert(type(helper.SelfTest) == "function", "secret_sentinel helper must expose SelfTest")
helper.SelfTest()
print("OK secret_sentinel self-test (gate wrapper)")
