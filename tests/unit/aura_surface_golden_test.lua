local function fail(msg)
    print("FAIL: aura_surface_golden_test - " .. msg)
    os.exit(1)
end

local function serialise(v, depth)
    depth = depth or 0
    if depth > 6 then return "..." end
    local t = type(v)
    if t ~= "table" then return t .. ":" .. tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        local k = keys[i]
        local val = v[k]
        if val == nil then val = v[tonumber(k)] end
        parts[#parts + 1] = k .. "=" .. serialise(val, depth + 1)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local captured = { unitframes = {}, groupframes = {} }
local anchors = { unitframes = {}, groupframes = {} }
local activeSurface

local function RecordConfigure(_container, profile, groups)
    local bucket = captured[activeSurface]
    bucket[#bucket + 1] = {
        index = #bucket + 1,
        profile = serialise(profile),
        groups = serialise(groups),
    }
end

local function RecordAnchor(point, relativePoint, offsetX, offsetY)
    local bucket = anchors[activeSurface]
    bucket[#bucket + 1] = {
        index = #bucket + 1,
        anchor = serialise({
            point = point, relativePoint = relativePoint,
            offsetX = offsetX, offsetY = offsetY,
        }),
    }
end

local function FixedElements(E)
    local strip = E.NewFilterStripElement("HARMFUL")
    strip.iconSize = 20
    strip.maxIcons = 4
    strip.spacing = 3
    strip.anchor = "BOTTOMLEFT"
    strip.offsetX = 5
    strip.offsetY = -7
    local buffStrip = E.NewFilterStripElement("HELPFUL")
    buffStrip.iconSize = 18
    buffStrip.maxIcons = 6
    local tracked = E.NewTrackedElement({ 1234 }, "icon")
    tracked.iconSize = 24
    tracked.maxIcons = 1
    return { strip, buffStrip, tracked }
end

local function LoadSurface(name, build)
    activeSurface = name
    build(RecordConfigure, FixedElements)
end

local function NewStub(kind)
    local s = {}
    function s:RegisterEvent() end
    function s:UnregisterAllEvents() end
    function s:SetScript(k, h) self._scripts = self._scripts or {}; self._scripts[k] = h end
    function s:GetScript(k) return self._scripts and self._scripts[k] end
    function s:SetSize() end
    function s:ClearAllPoints() end
    function s:SetPoint() end
    function s:SetAllPoints() end
    function s:SetTexCoord() end
    function s:SetColorTexture() end
    function s:DisablePixelSnap() end
    function s:SetTextColor() end
    function s:SetAlpha() end
    function s:SetFont() end
    function s:SetText() end
    function s:SetHideCountdownNumbers() end
    function s:SetDrawSwipe() end
    function s:SetReverse() end
    function s:SetStatusBarTexture() end
    function s:SetOrientation() end
    function s:SetStatusBarColor() end
    function s:SetIcon() end
    function s:AddDispelTypeTexture() end
    function s:ClearDispelTypeTextures() end
    function s:SetDispelTypeText() end
    function s:SetDurationCooldown() end
    function s:SetDurationText() end
    function s:SetApplicationCount() end
    function s:SetDurationBar() end
    function s:SetCancelAuraButtons() end
    function s:SetUnit(u) self._unit = u end
    function s:SetEnabled(v) self._enabled = v end
    function s:SetFrameLevel(v) self._frameLevel = v end
    function s:GetFrameLevel() return self._frameLevel or 1 end
    function s:Show() self._shown = true end
    function s:Hide() self._shown = false end
    function s:CreateTexture() return NewStub() end
    function s:CreateFontString() return NewStub() end
    function s:AddAuraSlot(key, _filter, opts)
        local slot = NewStub()
        if opts and opts.initializeFrame then opts.initializeFrame(slot) end
        self._slots = self._slots or {}
        self._slots[key] = slot
        return slot
    end
    function s:SetAuraSlotFilterString() end
    function s:SetAuraSlotCandidateFilters() end
    if kind == "AuraContainer" then
        function s:SetPoint(point, _relativeTo, relativePoint, offsetX, offsetY)
            RecordAnchor(point, relativePoint, offsetX, offsetY)
        end
    end
    return s
end

_G.CreateFrame = function(kind) return NewStub(kind) end
_G.InCombatLockdown = function() return false end
_G.AuraContainerSortMethod = { Default = 1 }
_G.AuraContainerSortDirection = { Normal = 1, Reverse = 2 }
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local function LoadAuraCore(ns)
    assert(loadfile("core/aura_theme.lua"))("QUI", ns)
    assert(loadfile("core/aura_skin.lua"))("QUI", ns)
    assert(loadfile("core/aura_elements.lua"))("QUI", ns)
    assert(loadfile("core/aura_glue.lua"))("QUI", ns)
    assert(loadfile("core/aura_slots.lua"))("QUI", ns)
    assert(loadfile("core/aura_surface.lua"))("QUI", ns)
end

LoadSurface("unitframes", function(recordConfigure, fixedElements)
    local ns = { SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end }
    LoadAuraCore(ns)
    ns.Addon.AuraSkin.Configure = recordConfigure

    local elements = fixedElements(ns.AuraElements)
    local auras = { elementsSeeded = true, elements = { ["*"] = elements } }

    ns.QUI_UnitFrames = {
        GetFrameUnit = function(frame) return frame.unitKey end,
        _GetUnitSettings = function(_unitKey) return { auras = auras } end,
    }

    assert(loadfile("QUI_UnitFrames/unitframes/unitframe_auras.lua"))("QUI_UnitFrames", ns)

    local frame = { unitKey = "player" }
    ns.QUI_UnitFrames.ApplyContainerConfig(frame)
end)

LoadSurface("groupframes", function(recordConfigure, fixedElements)
    local ns = { SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end }
    LoadAuraCore(ns)
    assert(loadfile("QUI_GroupFrames/groupframes/groupframes_aura_model.lua"))("QUI_GroupFrames", ns)
    ns.Addon.AuraSkin.Configure = recordConfigure

    local elements = fixedElements(ns.AuraElements)
    local auras = { elementsSeeded = true, elements = { ["*"] = elements } }
    local db = { auras = auras }

    ns.Helpers = {
        IsSecretValue = function() return false end,
        SafeValue = function(v) return v end,
        SafeToNumber = function(v) return tonumber(v) end,
        CreateDBGetter = function(_moduleName) return function() return db end end,
    }
    ns.QUI_GroupFrames = {
        GetFrameUnit = function(frame) return frame.unit end,
    }

    assert(loadfile("QUI_GroupFrames/groupframes/groupframes_auras.lua"))("QUI_GroupFrames", ns)

    local frame = { unit = "party1", GetFrameLevel = function() return 1 end }
    ns.QUI_GroupFrameAuras.ApplyStripContainers(frame)
end)

local FIXTURE = "tests/fixtures/aura_surface/golden.lua"

if os.getenv("QUI_WRITE_GOLDEN") == "1" then
    local out = assert(io.open(FIXTURE, "w"))
    out:write("return {\n")
    for _, surface in ipairs({ "unitframes", "groupframes" }) do
        out:write(string.format("  %s = {\n", surface))
        for _, rec in ipairs(captured[surface]) do
            out:write(string.format("    { index = %d, profile = %q, groups = %q },\n",
                rec.index, rec.profile, rec.groups))
        end
        out:write("  },\n")
    end
    for _, surface in ipairs({ "unitframes", "groupframes" }) do
        out:write(string.format("  %sAnchors = {\n", surface))
        for _, rec in ipairs(anchors[surface]) do
            out:write(string.format("    { index = %d, anchor = %q },\n",
                rec.index, rec.anchor))
        end
        out:write("  },\n")
    end
    out:write("}\n")
    out:close()
    print("wrote " .. FIXTURE)
    os.exit(0)
end

local golden = assert(loadfile(FIXTURE))()
for _, surface in ipairs({ "unitframes", "groupframes" }) do
    local key = surface .. "Anchors"
    local want, got = golden[key], anchors[surface]
    if #want ~= #got then
        fail(string.format("%s: expected %d anchor calls, got %d", key, #want, #got))
    end
    for i = 1, #want do
        if want[i].anchor ~= got[i].anchor then
            fail(string.format("%s call %d: anchor changed\n  want %s\n  got  %s",
                key, i, want[i].anchor, got[i].anchor))
        end
    end
end

for _, surface in ipairs({ "unitframes", "groupframes" }) do
    local want, got = golden[surface], captured[surface]
    if #want ~= #got then
        fail(string.format("%s: expected %d Configure calls, got %d", surface, #want, #got))
    end
    for i = 1, #want do
        if want[i].profile ~= got[i].profile then
            fail(string.format("%s call %d: profile changed\n  want %s\n  got  %s",
                surface, i, want[i].profile, got[i].profile))
        end
        if want[i].groups ~= got[i].groups then
            fail(string.format("%s call %d: groups changed\n  want %s\n  got  %s",
                surface, i, want[i].groups, got[i].groups))
        end
    end
end

print("PASS: aura_surface_golden_test")
