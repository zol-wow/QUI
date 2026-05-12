local ADDON_NAME, ns = ...

----------------------------------------------------------------------------
-- Aura payload probe
--
-- Usage:
--   /qaura on       enable player/pet UNIT_AURA payload logging
--   /qaura off      disable logging
--   /qaura copy     open a copyable sanitized log
--   /qaura clear    clear the live and copyable logs
--   /qaura status   print current state
--   /qcleu on       enable player/pet combat-log aura event logging
--   /qcleu all      enable player/pet combat-log logging for all subevents
--   /qcleu frameall use direct frame registration for all subevents
--   /qcleu off      disable combat-log aura event logging
--
-- This is a diagnostic surface only. It avoids tostring/concat on secret
-- aura payload fields; secret-bearing lines are rendered into an on-screen
-- C-side message sink using C_StringUtil.WrapString.
----------------------------------------------------------------------------

local PREFIX = "|cff34D399[QAura]|r"
local CLEU_PREFIX = "|cff34D399[QCLEU]|r"
local enabled = false
local cleuEnabled = false
local cleuLogAll = false
local cleuRegistered = false
local cleuFrameRegistered = false
local cleuMode = "callback"
local cleuEventCount = 0
local frame = CreateFrame("Frame")
local cleuOwner = CreateFrame("Frame")

local outputFrame
local outputMessages
local OUTPUT_MAX_LINES = 1000
local COPY_MAX_LINES = 1000

local copyLines = {}
local cleuCopyLines = {}
local copyFrame
local copyEditBox

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function EnsureOutputFrame()
    if outputFrame then return end

    outputFrame = CreateFrame("Frame", "QUI_AuraProbeFrame", UIParent)
    outputFrame:SetSize(1120, 520)
    outputFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 60, -170)
    outputFrame:SetFrameStrata("DIALOG")
    outputFrame:EnableMouse(true)
    outputFrame:SetMovable(true)
    outputFrame:RegisterForDrag("LeftButton")
    outputFrame:SetScript("OnDragStart", outputFrame.StartMoving)
    outputFrame:SetScript("OnDragStop", outputFrame.StopMovingOrSizing)

    local bg = outputFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.72)

    local title = outputFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("[QAura/QCLEU] drag to move - mouse wheel scrolls - /qaura copy opens sanitized text")

    outputMessages = CreateFrame("ScrollingMessageFrame", nil, outputFrame)
    outputMessages:SetPoint("TOPLEFT", 8, -24)
    outputMessages:SetPoint("BOTTOMRIGHT", -8, 8)
    outputMessages:SetFontObject("GameFontHighlightSmall")
    outputMessages:SetJustifyH("LEFT")
    outputMessages:SetFading(false)
    outputMessages:SetMaxLines(OUTPUT_MAX_LINES)
    outputMessages:EnableMouseWheel(true)
    outputMessages:SetScript("OnMouseWheel", function(self, delta)
        if delta and delta > 0 then
            self:ScrollUp()
        else
            self:ScrollDown()
        end
    end)
end

local function ClearOutput()
    if outputMessages then
        outputMessages:Clear()
    end
    for i = #copyLines, 1, -1 do
        copyLines[i] = nil
    end
    for i = #cleuCopyLines, 1, -1 do
        cleuCopyLines[i] = nil
    end
    if copyEditBox then
        copyEditBox:SetText("")
    end
end

local function AppendLiveLine(message)
    EnsureOutputFrame()
    if not outputMessages then return end
    outputMessages:AddMessage(message)
    outputMessages:ScrollToBottom()
end

local function ReadField(tbl, key)
    if type(tbl) ~= "table" then return nil, false end
    local ok, value = pcall(function() return tbl[key] end)
    if not ok then return "<error>", false end
    return value, IsSecret(value)
end

local function FormatCleanValue(value)
    if value == nil then return "nil" end
    if type(value) == "boolean" then return value and "true" or "false" end
    return tostring(value)
end

local function FormatCopyValue(value, secret)
    if secret then
        return "<secret:" .. type(value) .. ">"
    end
    return FormatCleanValue(value)
end

local function AppendBoundedLine(lines, line)
    lines[#lines + 1] = line
    while #lines > COPY_MAX_LINES do
        table.remove(lines, 1)
    end
end

local function AppendCopyLine(line, tag)
    AppendBoundedLine(copyLines, line)
    if tag == "[QCLEU]" then
        AppendBoundedLine(cleuCopyLines, line)
    end
end

local function AppendCopyArgsFor(tag, ...)
    local parts = { tag or "[QAura]" }
    local i = 1
    local n = select("#", ...)
    while i <= n do
        local value = select(i, ...)
        if type(value) == "string" and value:sub(-1) == "=" and i < n then
            local nextValue = select(i + 1, ...)
            parts[#parts + 1] = value .. FormatCopyValue(nextValue, IsSecret(nextValue))
            i = i + 2
        else
            parts[#parts + 1] = FormatCopyValue(value, IsSecret(value))
            i = i + 1
        end
    end
    AppendCopyLine(table.concat(parts, " "), tag)
end

local function AppendCopyArgs(...)
    AppendCopyArgsFor("[QAura]", ...)
end

local function EnsureCopyFrame()
    if copyFrame then return end

    copyFrame = CreateFrame("Frame", "QUI_AuraProbeCopyFrame", UIParent, "BackdropTemplate")
    copyFrame:SetSize(840, 420)
    copyFrame:SetPoint("CENTER")
    copyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    copyFrame:SetFrameLevel(500)
    copyFrame:SetToplevel(true)
    copyFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    copyFrame:SetBackdropColor(0, 0, 0, 0.92)
    copyFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    copyFrame:EnableMouse(true)
    copyFrame:SetMovable(true)
    copyFrame:RegisterForDrag("LeftButton")
    copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
    copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)

    local title = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("[QAura] Copy Log")

    local close = CreateFrame("Button", nil, copyFrame, "UIPanelButtonTemplate")
    close:SetSize(80, 22)
    close:SetPoint("TOPRIGHT", -10, -8)
    close:SetText("Close")
    close:SetScript("OnClick", function() copyFrame:Hide() end)

    local scroll = CreateFrame("ScrollFrame", nil, copyFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -34)
    scroll:SetPoint("BOTTOMRIGHT", -30, 12)

    copyEditBox = CreateFrame("EditBox", nil, scroll)
    copyEditBox:SetMultiLine(true)
    copyEditBox:SetMaxLetters(0)
    copyEditBox:SetFontObject("ChatFontNormal")
    copyEditBox:SetWidth(790)
    copyEditBox:SetAutoFocus(false)
    copyEditBox:EnableMouse(true)
    copyEditBox:SetScript("OnEscapePressed", copyEditBox.ClearFocus)
    copyEditBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    scroll:SetScrollChild(copyEditBox)

    copyFrame:Hide()
end

local function OpenCopyFrame(lines, emptyText, printPrefix)
    EnsureCopyFrame()
    if not copyEditBox then return end

    lines = lines or copyLines
    local text = table.concat(lines, "\n")
    if text == "" then
        text = emptyText or "[QAura] no lines captured"
    end
    copyEditBox:SetText(text)
    copyEditBox:SetHeight(math.max(360, (#lines + 1) * 14))
    copyEditBox:HighlightText()
    copyEditBox:SetFocus()
    copyFrame:Show()
    copyFrame:Raise()
    print((printPrefix or PREFIX) .. " copy window opened (" .. tostring(#lines) .. " lines)")
end

local function AppendPart(message, hasSecret, label, value, secret)
    message = message .. " " .. label .. "="
    if secret then
        hasSecret = true
        if C_StringUtil and C_StringUtil.WrapString then
            message = C_StringUtil.WrapString(value, message, "")
        else
            message = message .. "<secret>"
        end
    else
        message = message .. FormatCleanValue(value)
    end
    return message, hasSecret
end

local function EmitWithPrefix(prefix, copyTag, mirrorToChat, ...)
    AppendCopyArgsFor(copyTag, ...)

    local message = prefix
    local hasSecret = false
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        local secret = IsSecret(value)
        if secret then
            hasSecret = true
            if C_StringUtil and C_StringUtil.WrapString then
                message = C_StringUtil.WrapString(value, message .. " ", "")
            else
                message = message .. " <secret>"
            end
        else
            message = message .. " " .. FormatCleanValue(value)
        end
    end

    if not hasSecret then
        if mirrorToChat then
            print(message)
        end
        AppendLiveLine(message)
        return
    end

    AppendLiveLine(message)
end

local function Emit(...)
    EmitWithPrefix(PREFIX, "[QAura]", true, ...)
end

local function EmitCLEU(...)
    EmitWithPrefix(CLEU_PREFIX, "[QCLEU]", false, ...)
end

local function EmitAura(prefix, unit, index, aura)
    local message = PREFIX
    local hasSecret = false
    local copyParts = {
        "[QAura]",
        "event=" .. FormatCopyValue(prefix, false),
        "unit=" .. FormatCopyValue(unit, false),
        "i=" .. FormatCopyValue(index, false),
    }
    message, hasSecret = AppendPart(message, hasSecret, "event", prefix, false)
    message, hasSecret = AppendPart(message, hasSecret, "unit", unit, false)
    message, hasSecret = AppendPart(message, hasSecret, "i", index, false)

    local fields = {
        "name",
        "spellId",
        "auraInstanceID",
        "icon",
        "duration",
        "expirationTime",
        "applications",
        "sourceUnit",
        "isHelpful",
        "isHarmful",
        "isFromPlayerOrPlayerPet",
    }

    for i = 1, #fields do
        local key = fields[i]
        local value, secret = ReadField(aura, key)
        message, hasSecret = AppendPart(message, hasSecret, key, value, secret)
        copyParts[#copyParts + 1] = key .. "=" .. FormatCopyValue(value, secret)
    end

    AppendCopyLine(table.concat(copyParts, " "))

    if not hasSecret then
        print(message)
        AppendLiveLine(message)
        return
    end

    AppendLiveLine(message)
end

local function ProbeUpdatedAura(unit, index, auraInstanceID)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID) then
        Emit("updated", "unit=", unit, "i=", index, "inst=", auraInstanceID, "query=missing")
        return
    end
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, auraInstanceID)
    if ok and aura then
        EmitAura("updated", unit, index, aura)
    else
        Emit("updated", "unit=", unit, "i=", index, "inst=", auraInstanceID, "aura=nil")
    end
end

local function OnUnitAura(_, event, unit, updateInfo)
    if not enabled then return end
    if unit ~= "player" and unit ~= "pet" then return end

    if type(updateInfo) ~= "table" then
        Emit("UNIT_AURA", "unit=", unit, "full-or-nil")
        return
    end

    Emit("UNIT_AURA",
        "unit=", unit,
        "full=", updateInfo.isFullUpdate,
        "added=", updateInfo.addedAuras and #updateInfo.addedAuras or 0,
        "updated=", updateInfo.updatedAuraInstanceIDs and #updateInfo.updatedAuraInstanceIDs or 0,
        "removed=", updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs or 0)

    if type(updateInfo.addedAuras) == "table" then
        for i, aura in ipairs(updateInfo.addedAuras) do
            EmitAura("added", unit, i, aura)
        end
    end

    if type(updateInfo.updatedAuraInstanceIDs) == "table" then
        for i, auraInstanceID in ipairs(updateInfo.updatedAuraInstanceIDs) do
            ProbeUpdatedAura(unit, i, auraInstanceID)
        end
    end

    if type(updateInfo.removedAuraInstanceIDs) == "table" then
        for i, auraInstanceID in ipairs(updateInfo.removedAuraInstanceIDs) do
            Emit("removed", "unit=", unit, "i=", i, "inst=", auraInstanceID)
        end
    end
end

local function SetEnabled(value)
    enabled = value and true or false
    if enabled then
        EnsureOutputFrame()
        outputFrame:Show()
        frame:RegisterUnitEvent("UNIT_AURA", "player", "pet")
        frame:SetScript("OnEvent", OnUnitAura)
        print(PREFIX .. " on - logging player/pet UNIT_AURA payloads")
    else
        frame:UnregisterEvent("UNIT_AURA")
        frame:SetScript("OnEvent", nil)
        print(PREFIX .. " off")
    end
end

local CLEU_AURA_EVENTS = {
    SPELL_AURA_APPLIED = true,
    SPELL_AURA_REFRESH = true,
    SPELL_AURA_REMOVED = true,
    SPELL_AURA_APPLIED_DOSE = true,
    SPELL_AURA_REMOVED_DOSE = true,
    SPELL_AURA_BROKEN = true,
}

local function IsObservedGUID(guid)
    if not guid then return false end
    local playerGUID = UnitGUID and UnitGUID("player")
    if guid == playerGUID then return true end
    local petGUID = UnitGUID and UnitGUID("pet")
    return petGUID and guid == petGUID
end

local function OnCombatLogEvent()
    if not cleuEnabled then return end
    if not CombatLogGetCurrentEventInfo then return end

    local _, subEvent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, spellID, spellName, spellSchool, auraType, amount = CombatLogGetCurrentEventInfo()
    if not cleuLogAll and not (IsObservedGUID(sourceGUID) or IsObservedGUID(destGUID)) then return end
    if not cleuLogAll and not CLEU_AURA_EVENTS[subEvent] then return end

    cleuEventCount = cleuEventCount + 1
    EmitCLEU(subEvent,
        "n=", cleuEventCount,
        "mode=", cleuMode,
        "src=", sourceName or sourceGUID,
        "srcFlags=", sourceFlags,
        "dst=", destName or destGUID,
        "dstFlags=", destFlags,
        "spellID=", spellID,
        "spellName=", spellName,
        "school=", spellSchool,
        "auraType=", auraType,
        "amount=", amount)
end

local function EnsureCLEURegistered()
    if cleuRegistered then return true end
    if not (EventRegistry and EventRegistry.RegisterCallback) then
        return false
    end
    EventRegistry:RegisterCallback("COMBAT_LOG_EVENT_UNFILTERED", OnCombatLogEvent, cleuOwner)
    cleuRegistered = true
    return true
end

local function EnsureCLEUFrameRegistered()
    if cleuFrameRegistered then return true end
    local ok, err = pcall(function()
        cleuOwner:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        cleuOwner:SetScript("OnEvent", OnCombatLogEvent)
    end)
    if not ok then
        EmitCLEU("frame-register-failed", "error=", err)
        return false
    end
    cleuFrameRegistered = true
    return true
end

local function SetCLEUEnabled(value, mode, registerMode)
    if value then
        cleuLogAll = mode == "all"
        cleuMode = registerMode == "frame" and "frame" or "callback"
        if cleuMode == "frame" then
            if not EnsureCLEUFrameRegistered() then
                print(CLEU_PREFIX .. " frame registration failed; see /qcleu copy")
                return
            end
        else
            if not EnsureCLEURegistered() then
                print(CLEU_PREFIX .. " unavailable - EventRegistry callback API missing")
                return
            end
        end
        cleuEnabled = true
        EnsureOutputFrame()
        outputFrame:Show()
        EmitCLEU("enabled",
            "mode=", cleuMode,
            "filter=", cleuLogAll and "all" or "aura",
            "events=", cleuEventCount)
        print(CLEU_PREFIX .. " on - " .. cleuMode .. " mode logging " .. (cleuLogAll and "combat-log events" or "player/pet combat-log aura events"))
    else
        cleuEnabled = false
        EmitCLEU("disabled", "mode=", cleuMode, "events=", cleuEventCount)
        print(CLEU_PREFIX .. " off")
    end
end

SLASH_QUI_AURAPROBE1 = "/qaura"
SlashCmdList["QUI_AURAPROBE"] = function(msg)
    local text = msg and strtrim(msg):lower() or ""
    if text == "" or text == "status" then
        print(PREFIX .. " " .. (enabled and "on" or "off") .. " cleu=" .. (cleuEnabled and "on" or "off") .. " lines=" .. tostring(#copyLines) .. " (/qaura on|off|copy|clear|status)")
    elseif text == "on" or text == "1" or text == "true" then
        SetEnabled(true)
    elseif text == "off" or text == "0" or text == "false" then
        SetEnabled(false)
    elseif text == "copy" then
        OpenCopyFrame()
    elseif text == "clear" then
        ClearOutput()
        print(PREFIX .. " cleared")
    else
        print(PREFIX .. " usage: /qaura on|off|copy|clear|status")
    end
end

SLASH_QUI_CLEUPROBE1 = "/qcleu"
SlashCmdList["QUI_CLEUPROBE"] = function(msg)
    local text = msg and strtrim(msg):lower() or ""
    if text == "" or text == "status" then
        print(CLEU_PREFIX .. " " .. (cleuEnabled and "on" or "off") .. " mode=" .. cleuMode .. " filter=" .. (cleuLogAll and "all" or "aura") .. " events=" .. tostring(cleuEventCount) .. " lines=" .. tostring(#cleuCopyLines) .. " (/qcleu on|all|aura|frameall|off|copy|clear|status)")
    elseif text == "on" or text == "1" or text == "true" then
        SetCLEUEnabled(true, "aura", "callback")
    elseif text == "all" then
        SetCLEUEnabled(true, "all", "callback")
    elseif text == "aura" then
        SetCLEUEnabled(true, "aura", "callback")
    elseif text == "frame" then
        SetCLEUEnabled(true, "aura", "frame")
    elseif text == "frameall" then
        SetCLEUEnabled(true, "all", "frame")
    elseif text == "off" or text == "0" or text == "false" then
        SetCLEUEnabled(false)
    elseif text == "copy" then
        OpenCopyFrame(cleuCopyLines, "[QCLEU] no lines captured", CLEU_PREFIX)
    elseif text == "clear" then
        ClearOutput()
        cleuEventCount = 0
        print(CLEU_PREFIX .. " cleared")
    else
        print(CLEU_PREFIX .. " usage: /qcleu on|all|aura|frame|frameall|off|copy|clear|status")
    end
end

ns.QUI_AuraProbe = {
    SetEnabled = SetEnabled,
    SetCombatLogEnabled = SetCLEUEnabled,
    IsEnabled = function() return enabled end,
    IsCombatLogEnabled = function() return cleuEnabled end,
}
