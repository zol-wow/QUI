local secret = dofile("tests/helpers/secret_sentinel.lua")
local restore = secret.InstallSecretStub()
local ns = {}
local load = assert(secret.LoadInstrumented("QUI_CDM/cdm/cdm_frame_writes.lua"))
load("QUI", ns)

local renderers = assert(ns.CDMRenderers)
local duration = secret.MakeSecretSentinel()
local cooldownCalls = 0
local timerCalls = 0
local cooldown = {
    SetCooldownFromDurationObject = function(_, value)
        assert(value == duration)
        cooldownCalls = cooldownCalls + 1
    end,
}
local statusBar = {
    SetTimerDuration = function(_, value)
        assert(value == duration)
        timerCalls = timerCalls + 1
    end,
}

assert(renderers.ApplyDurationObjectCooldown(cooldown, duration, true, false) == true)
assert(renderers.SetStatusBarTimerDuration(statusBar, duration) == true)
assert(cooldownCalls == 1)
assert(timerCalls == 1)

secret.RestoreSecretStub(restore)
print("OK: cdm_renderers_secret_duration_test")
