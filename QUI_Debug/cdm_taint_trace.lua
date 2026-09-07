local _, ns = ...

local Trace = {}
ns.CDMTaintTrace = Trace

local providerFields = { "displayData", "displayDataDirty", "layoutManager" }
local displayFields = {
    "orderedCooldownIDs", "cooldownInfoByID", "cooldownDefaultsByID", "defaultOrderedCooldownIDs",
}
local itemFields = {
    "cooldownID", "cooldownInfo", "auraInstanceID", "auraSpellID", "auraDataCached",
    "auraDataUnit", "alertsByEvent", "viewerFrame", "layoutIndex", "isActive", "isActiveSpell",
}

local function Snapshot(frame)
    local result = {}
    local function add(object, fields, prefix)
        if not object or (issecretvalue and issecretvalue(object)) then return end
        for _, field in ipairs(fields) do
            local secure, owner = issecurevariable(object, field)
            result[#result + 1] = { key = prefix .. field, secure = secure, owner = owner }
        end
    end
    local settings = _G.CooldownViewerSettings
    local provider = settings and settings.dataProvider
    add(provider, providerFields, "provider.")
    local display = provider and provider.displayData
    add(display, displayFields, "displayData.")
    add(frame, itemFields, "item.")
    return result
end

local function Changes(before, after)
    local previous, changes = {}, {}
    for _, entry in ipairs(before) do previous[entry.key] = entry.secure end
    for _, entry in ipairs(after) do
        if previous[entry.key] == true and entry.secure == false then
            changes[#changes + 1] = entry.key .. " -> " .. tostring(entry.owner)
        end
    end
    return changes
end

function Trace:Stop()
    ns.CDMNativeCallTrace = nil
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
end

function Trace:Record(label, changes)
    self:Stop()
    self.report = {
        "[CDMTrace] " .. label .. "; calls=" .. tostring(self.calls),
        table.concat(changes, "; "),
        "[CDMTrace] last clean checkpoint: " .. tostring(self.lastClean),
        debugstack(3, 18, 0),
    }
    self:Report()
end

function Trace:Report()
    if self.report then
        for _, line in ipairs(self.report) do print(line) end
    else
        print("[CDMTrace] no transition recorded; calls=" .. tostring(self.calls or 0))
    end
end

function Trace:Checkpoint(label)
    local current = Snapshot(nil)
    local changes = Changes(self.previous, current)
    if #changes > 0 then
        self:Record("ownership changed before checkpoint: " .. label, changes)
    else
        self.previous = current
        self.lastClean = label
    end
end

function Trace:Before(frame, method)
    local snapshot = Snapshot(frame)
    local changes = Changes(self.previous, snapshot)
    if #changes > 0 then
        self:Record("taint already present on entry to " .. method, changes)
        return nil
    end
    self.calls = self.calls + 1
    return snapshot
end

function Trace:After(frame, method, before)
    if ns.CDMNativeCallTrace ~= self then return end
    local after = Snapshot(frame)
    local changes = Changes(before, after)
    if #changes > 0 then
        self:Record("ownership changed during " .. method, changes)
    else
        self.previous = Snapshot(nil)
        self.lastClean = "after " .. method
    end
end

function Trace:Start()
    self:Stop()
    self.report = nil
    self.calls = 0
    self.lastClean = "trace start"
    self.previous = Snapshot(nil)
    if #self.previous == 0 then
        print("[CDMTrace] native provider unavailable")
        return
    end
    for _, entry in ipairs(self.previous) do
        if entry.secure == false then
            print("[CDMTrace] already tainted: " .. entry.key .. "; /reload before starting")
            return
        end
    end
    ns.CDMNativeCallTrace = self
    local ticks = 0
    self.ticker = C_Timer.NewTicker(0.2, function()
        ticks = ticks + 1
        local current = Snapshot(nil)
        local changes = Changes(self.previous, current)
        if #changes > 0 then
            self:Record("ownership change detected by periodic sample", changes)
        elseif ticks >= 300 then
            self:Stop()
            print("[CDMTrace] finished 60 seconds; calls=" .. tostring(self.calls) .. "; no transition captured")
        else
            self.previous = current
        end
    end)
    print("[CDMTrace] started: clean provider; tracing spec refresh and native cooldown setters for 60 seconds")
end
