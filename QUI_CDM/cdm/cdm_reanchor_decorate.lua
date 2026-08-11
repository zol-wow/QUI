local _, ns = ...

local CDMReanchorDecorate = {}
ns.CDMReanchorDecorate = CDMReanchorDecorate

local HIDDEN_REGIONS = {
    "DebuffBorder",
    "CooldownFlash",
    "SpellActivationAlert",
}
CDMReanchorDecorate.HIDDEN_REGIONS = HIDDEN_REGIONS

local InstanceMT = { __index = CDMReanchorDecorate }

function CDMReanchorDecorate.New(deps)
    deps = deps or {}
    local self = {
        _deps = deps,
        _done = setmetatable({}, { __mode = "k" }),
    }
    return setmetatable(self, InstanceMT)
end

function CDMReanchorDecorate:Decorate(frame, rowConfig)
    local deps = self._deps
    if self._done[frame] then
        if deps.applyChrome then deps.applyChrome(frame, rowConfig, false) end
        return false
    end
    self._done[frame] = true
    if deps.hideRegion then
        for i = 1, #HIDDEN_REGIONS do
            deps.hideRegion(frame, HIDDEN_REGIONS[i])
        end
    end
    if deps.applyChrome then deps.applyChrome(frame, rowConfig, true) end
    return true
end

function CDMReanchorDecorate:IsDecorated(frame)
    return self._done[frame] == true
end
