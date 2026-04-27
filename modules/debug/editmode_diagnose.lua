local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

----------------------------------------------------------------------------
-- Edit Mode Diagnostic — passive capture + on-demand report
--
-- Usage:  /qui diagnose
--
-- Passively records ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN events
-- blamed on QUI into a small ring buffer. When invoked, inspects Edit Mode
-- state and classifies captured events, since server-side corrupt Edit Mode
-- layouts frequently manifest as managed-container protected calls blamed
-- on whichever addon last hooked the frame.
--
-- Edit Mode layouts are stored server-side by Blizzard as account-wide JSON;
-- client-side resets (WTF, addon uninstall, CVars) do NOT fix them. The only
-- known remediation is a Blizzard GM ticket. The report points the user at
-- that path only when the symptom profile matches.
----------------------------------------------------------------------------

local BUFFER_MAX  = 30
local MANAGED_TOKENS = {
    "ManagedFrameContainer",
    "UIParentRight",
    "UIParentLeft",
    "UIParentBottom",
    "ObjectiveTrackerFrame",
    "BossTargetFrameContainer",
    "PetFrame",
    "ClearAllPointsBase",
    "UIWidgetTopCenterContainerFrame",
    "UIWidgetBelowMinimapContainerFrame",
    "ExtraAbilityContainer",
    "CompactRaidFrameContainer",
}
local EDITMODE_TOKENS = {
    "EditMode",
    "EditModeManager",
    "EditModeUtil",
}

-- Ring buffer of captured block events. Each entry:
--   { t = GetTime()-origin, func = string, combat = bool, event = "BLOCKED"|"FORBIDDEN" }
local buffer = {}
local bufferStart = nil

local function RecordBlock(eventKind, addonFunc)
    if not bufferStart then bufferStart = GetTime() end
    local entry = {
        t      = GetTime() - bufferStart,
        func   = tostring(addonFunc or "?"),
        combat = InCombatLockdown() and true or false,
        event  = eventKind,
    }
    buffer[#buffer + 1] = entry
    -- Drop oldest once we exceed cap
    if #buffer > BUFFER_MAX then
        table.remove(buffer, 1)
    end
end

-- Event frame: register once at file load. Cheap — only fires on actual
-- protected-call violations blamed on us, which should be zero in a healthy
-- session.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
eventFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
eventFrame:SetScript("OnEvent", function(_, event, addonName, addonFunc)
    if addonName ~= ADDON_NAME then return end
    local kind = (event == "ADDON_ACTION_BLOCKED") and "BLOCKED" or "FORBIDDEN"
    RecordBlock(kind, addonFunc)
end)

----------------------------------------------------------------------------
-- Classification helpers
----------------------------------------------------------------------------

local function containsAny(str, tokens)
    if type(str) ~= "string" then return false end
    for i = 1, #tokens do
        if str:find(tokens[i], 1, true) then return true end
    end
    return false
end

local function IsManagedContainerBlock(entry)
    return containsAny(entry.func, MANAGED_TOKENS)
end

local function IsEditModeBlock(entry)
    return containsAny(entry.func, EDITMODE_TOKENS)
end

local function IsPetFrameLayoutBlock(entry)
    local func = entry and entry.func
    return type(func) == "string"
        and func:find("PetFrame", 1, true)
        and func:find("ClearAllPointsBase", 1, true)
end

----------------------------------------------------------------------------
-- Edit Mode state probes (defensive — never trust Blizzard state in combat)
----------------------------------------------------------------------------

local function ProbeEditModeState()
    local state = {
        addonLoaded        = false,
        managerPresent     = false,
        layoutInfoPresent  = false,
        activeLayoutIndex  = nil,
        activeLayoutName   = nil,
        layoutCount        = nil,
        suspiciousLayouts  = {},
        probeErrors        = {},
    }

    -- Is the Blizzard_EditMode addon loaded?
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, "Blizzard_EditMode")
        state.addonLoaded = ok and loaded and true or false
    end

    if not EditModeManagerFrame then
        return state
    end
    state.managerPresent = true

    -- layoutInfo is populated asynchronously; it may be nil early after login.
    local info = EditModeManagerFrame.layoutInfo
    if type(info) ~= "table" then
        return state
    end
    state.layoutInfoPresent = true

    local activeIdx = Helpers.SafeToNumber(info.activeLayout, nil)
    state.activeLayoutIndex = activeIdx

    local layouts = info.layouts
    if type(layouts) == "table" then
        state.layoutCount = #layouts
        if activeIdx and layouts[activeIdx] then
            local name = Helpers.SafeToString(layouts[activeIdx].layoutName, nil)
            state.activeLayoutName = name
        end

        -- Scan for known-bad name shapes. Real forum reports show layout names
        -- like "1 7 7 UIParen" / "1 1 UI Parent" — JSON parse residue leaking
        -- frame-graph content into the name field. Flag only highly-specific
        -- patterns to avoid false positives on legitimate user names.
        for i = 1, #layouts do
            local entry = layouts[i]
            local name = entry and Helpers.SafeToString(entry.layoutName, nil)
            if type(name) == "string" then
                local flagged = false
                -- 1. Contains "UIParent" or "UI Parent" substring
                if name:find("UIParent", 1, true) or name:find("UI Parent", 1, true) then
                    flagged = true
                end
                -- 2. Unusually long (real layout names top out around 20 chars)
                if #name > 48 then
                    flagged = true
                end
                -- 3. Contains non-printable control characters
                if name:find("[%z\1-\8\11\12\14-\31]") then
                    flagged = true
                end
                if flagged then
                    state.suspiciousLayouts[#state.suspiciousLayouts + 1] = {
                        index = i,
                        name  = name,
                    }
                end
            end
        end
    end

    return state
end

----------------------------------------------------------------------------
-- Report
----------------------------------------------------------------------------

local COLOR_HEAD = "|cff60A5FA"
local COLOR_OK   = "|cff44FF44"
local COLOR_WARN = "|cffFFAA44"
local COLOR_BAD  = "|cffFF4444"
local COLOR_DIM  = "|cff888888"
local RESET      = "|r"

local function line(s) print(s or "") end
local function fmt(color, s) return color .. s .. RESET end

local function SummarizeEvents()
    local managed, editmode, other, combat, petLayout = 0, 0, 0, 0, 0
    for i = 1, #buffer do
        local e = buffer[i]
        if e.combat then combat = combat + 1 end
        if IsPetFrameLayoutBlock(e) then petLayout = petLayout + 1 end
        if IsManagedContainerBlock(e) then
            managed = managed + 1
        elseif IsEditModeBlock(e) then
            editmode = editmode + 1
        else
            other = other + 1
        end
    end
    return managed, editmode, other, combat, petLayout
end

local function PrintReport()
    line(fmt(COLOR_HEAD, "=== QUI Edit Mode Diagnostic ==="))

    local state = ProbeEditModeState()

    ------------------------------------------------------------------ STATE
    line(fmt(COLOR_HEAD, "Edit Mode state:"))
    line(("  Blizzard_EditMode loaded: %s"):format(
        state.addonLoaded and fmt(COLOR_OK, "yes") or fmt(COLOR_BAD, "NO")))
    line(("  EditModeManagerFrame:     %s"):format(
        state.managerPresent and fmt(COLOR_OK, "present") or fmt(COLOR_BAD, "MISSING")))
    line(("  layoutInfo populated:     %s"):format(
        state.layoutInfoPresent and fmt(COLOR_OK, "yes")
            or fmt(COLOR_WARN, "no (may be early in login)")))

    if state.layoutCount then
        line(("  Layout count:             %d"):format(state.layoutCount))
    end
    if state.activeLayoutIndex then
        line(("  Active layout:            [%d] %s"):format(
            state.activeLayoutIndex,
            state.activeLayoutName and ('"' .. state.activeLayoutName .. '"') or "<unnamed>"))
    end

    if #state.suspiciousLayouts > 0 then
        line(fmt(COLOR_BAD, ("  Suspicious layout names:  %d"):format(#state.suspiciousLayouts)))
        for i = 1, #state.suspiciousLayouts do
            local s = state.suspiciousLayouts[i]
            line(("    [%d] %s"):format(s.index, fmt(COLOR_BAD, '"' .. s.name .. '"')))
        end
    else
        line("  Suspicious layout names:  " .. fmt(COLOR_OK, "none"))
    end

    ----------------------------------------------------------------- EVENTS
    line("")
    line(fmt(COLOR_HEAD,
        ("Recent events blamed on QUI this session: %d"):format(#buffer)))
    if #buffer == 0 then
        line("  " .. fmt(COLOR_DIM, "(none captured)"))
    else
        local shown = math.min(#buffer, 15)
        local startIdx = #buffer - shown + 1
        if startIdx > 1 then
            line("  " .. fmt(COLOR_DIM,
                ("(showing last %d of %d)"):format(shown, #buffer)))
        end
        for i = startIdx, #buffer do
            local e = buffer[i]
            local tag = e.combat and fmt(COLOR_BAD, "combat") or fmt(COLOR_DIM, "noncbt")
            line(("  [%d] +%6.1fs  %s  %s  %s"):format(
                i, e.t, e.event, tag, e.func))
        end
    end

    ---------------------------------------------------------------- VERDICT
    line("")
    line(fmt(COLOR_HEAD, "Verdict:"))

    local managed, editmode, other, _, petLayout = SummarizeEvents()
    local haveManaged = managed > 0
    local havePetFrameLayoutBlock = petLayout > 0
    local haveCorruptSigns = (not state.managerPresent and state.addonLoaded)
        or (#state.suspiciousLayouts > 0)

    if #buffer == 0 then
        line("  " .. fmt(COLOR_OK,
            "No ADDON_ACTION_BLOCKED events blamed on QUI this session."))
        line("  " .. fmt(COLOR_DIM,
            "If a problem is reproducible, trigger it once then run /qui diagnose again."))
        return
    end

    if haveManaged and (haveCorruptSigns or havePetFrameLayoutBlock) then
        line("  " .. fmt(COLOR_BAD,
            "Bad Blizzard Edit Mode layout strongly suspected."))
        line("")
        line("  What this means:")
        line("    " .. fmt(COLOR_DIM, "•") ..
            " Edit Mode layouts are stored SERVER-SIDE by Blizzard as account-wide")
        line("      data, not in your WTF folder.")
        line("    " .. fmt(COLOR_DIM, "•") ..
            " Deleting WTF, reinstalling addons, and resetting CVars usually will NOT")
        line("      fix this because the layout is replayed from Blizzard's servers.")
        line("    " .. fmt(COLOR_DIM, "•") ..
            " PetFrame:ClearAllPointsBase() blocks during TotemFrame updates match")
        line("      the known bad-layout symptom on pet classes.")
        line("")
        line("  " .. fmt(COLOR_HEAD, "How to fix:"))
        line("    " .. fmt(COLOR_WARN, "1.") ..
            " Open Blizzard Edit Mode and create a new layout from scratch.")
        line("    " .. fmt(COLOR_WARN, "2.") ..
            " Switch to the new layout, reload, and delete the old layout if errors stop.")
        line("    " .. fmt(COLOR_WARN, "3.") ..
            ' If it persists, open a support ticket requesting: "Please reset my account-wide Edit Mode layout data."')
        return
    end

    if haveManaged then
        line("  " .. fmt(COLOR_WARN,
            "Managed-container protected calls captured, Edit Mode state looks healthy."))
        line("    " .. fmt(COLOR_DIM, "•") ..
            " Most likely another addon hooks a managed-container child first,")
        line("      so Blizzard blames the last addon in the taint chain (QUI).")
        line("    " .. fmt(COLOR_DIM, "•") ..
            " Try: /reload. If it recurs after a loading screen, capture one")
        line("      reproduction with /console taintLog 1 and check Logs/taint.log.")
        return
    end

    if editmode > 0 then
        line("  " .. fmt(COLOR_WARN,
            ("Edit-Mode-adjacent blocks captured (%d), no managed-container calls."):format(editmode)))
        line("    " .. fmt(COLOR_DIM, "•") ..
            " Likely an Edit Mode taint path not covered by our reparent logic.")
        return
    end

    line("  " .. fmt(COLOR_WARN,
        ("%d event(s) captured, not a known Edit Mode pattern."):format(other)))
    line("    " .. fmt(COLOR_DIM, "•") ..
        " Review the event list above and report the function names upstream.")
end

----------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------

_G.QUI_DiagnoseEditMode = function(subcmd)
    if subcmd == "clear" then
        buffer = {}
        bufferStart = nil
        print("|cff60A5FAQUI:|r Edit Mode diagnostic buffer cleared.")
        return
    end
    PrintReport()
end
