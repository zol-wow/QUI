local ADDON_NAME, ns = ...

-- Run a callback once the first frame has rendered (queues until then, then
-- runs immediately afterward). Lets startup work defer past the initial paint.

local firstFrameRendered = false
local afterFirstFrameQueue = {}

local function StartupRunAfterFirstFrame(callback, delay)
    if type(callback) ~= "function" then return end

    delay = type(delay) == "number" and delay or 0
    if firstFrameRendered then
        if C_Timer and C_Timer.After then
            C_Timer.After(delay, callback)
        else
            callback()
        end
        return
    end

    afterFirstFrameQueue[#afterFirstFrameQueue + 1] = {
        callback = callback,
        delay = delay,
    }
end

local function StartupFlushAfterFirstFrameQueue()
    firstFrameRendered = true

    local queue = afterFirstFrameQueue
    afterFirstFrameQueue = {}
    for i = 1, #queue do
        local item = queue[i]
        if item and type(item.callback) == "function" then
            if C_Timer and C_Timer.After then
                C_Timer.After(item.delay or 0, item.callback)
            else
                item.callback()
            end
        end
    end
end

function ns.RunAfterFirstFrame(callback, delay)
    return StartupRunAfterFirstFrame(callback, delay)
end

-- Run a callback once login is complete. Fires immediately when already
-- logged in — LoadOnDemand sub-addons load after PLAYER_LOGIN and must not
-- wait for an event that already fired.
function ns.WhenLoggedIn(callback)
    if type(callback) ~= "function" then return end
    if IsLoggedIn and IsLoggedIn() then
        callback()
        return
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        callback()
    end)
end

-- Flush the after-first-frame queue once the first frame renders.
if CreateFrame then
    local firstFrameFrame = CreateFrame("Frame")
    firstFrameFrame:RegisterEvent("FIRST_FRAME_RENDERED")
    firstFrameFrame:SetScript("OnEvent", function(self)
        StartupFlushAfterFirstFrameQueue()
        self:UnregisterEvent("FIRST_FRAME_RENDERED")
    end)
end

-- Options-toggle keybind (Lua-managed; Bindings.xml removed). A hidden named
-- button carries a CLICK binding; the key persists in the QUIDB global and is
-- re-applied each login. Bind: /qui bindkey CTRL-O   Clear: /qui bindkey none
local toggleOptionsButton = CreateFrame("Button", "QUI_ToggleOptionsButton", UIParent)
toggleOptionsButton:Hide()
toggleOptionsButton:SetScript("OnClick", function()
    QUI:OpenOptions()
end)

local function ApplyToggleOptionsKeybind()
    local key = QUI.db and QUI.db.global and QUI.db.global.toggleOptionsKey
    if type(key) == "string" and key ~= "" and not InCombatLockdown() then
        SetBindingClick(key, "QUI_ToggleOptionsButton")
    end
end
---@type table|AceAddon
QUI = LibStub("AceAddon-3.0"):NewAddon("QUI", "AceConsole-3.0", "AceEvent-3.0")
QUI._ns = ns
QUI.DEBUG_MODE = false
QUI.pullAliasOwned = false

local QUI_PULL_SLASH_KEY = "QUIPULL_ALIAS"
local QUI_OPTIONS_ADDON = "QUI_Options"
local QUI_DEBUG_ADDON = "QUI_Debug"
local PULL_COMMAND_OWNERS = {
    ["BigWigs"] = true,
    ["BigWigs_Core"] = true,
    ["DBM-Core"] = true,
}

-- Version info
QUI.versionString = C_AddOns.GetAddOnMetadata("QUI", "Version") or "2.00"

local function IsAddonLoaded(addonName)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(addonName)
    end
    if IsAddOnLoaded then
        return IsAddOnLoaded(addonName)
    end
    return false
end

local function LoadAddon(addonName)
    if C_AddOns and C_AddOns.LoadAddOn then
        return C_AddOns.LoadAddOn(addonName)
    end
    if LoadAddOn then
        return LoadAddOn(addonName)
    end
    return nil, "LoadAddOn unavailable"
end

function QUI:IsOptionsLoaded()
    return self.GUI and type(self.GUI.InitializeOptions) == "function"
end

function QUI:EnsureOptionsLoaded()
    if self:IsOptionsLoaded() then
        return true
    end

    if not IsAddonLoaded(QUI_OPTIONS_ADDON) then
        local ok, reason = LoadAddon(QUI_OPTIONS_ADDON)
        if not ok then
            return false, reason or "missing companion addon"
        end
    end

    if self:IsOptionsLoaded() then
        return true
    end

    return false, "settings UI did not initialize"
end

function QUI:IsDebugToolsLoaded()
    return IsAddonLoaded(QUI_DEBUG_ADDON)
end

function QUI:EnsureDebugToolsLoaded()
    if self:IsDebugToolsLoaded() then
        return true
    end

    local ok, reason = LoadAddon(QUI_DEBUG_ADDON)
    if not ok then
        return false, reason or "missing debug companion addon"
    end

    return self:IsDebugToolsLoaded(), "debug companion addon did not initialize"
end

function QUI:OpenOptions()
    local ok, reason = self:EnsureOptionsLoaded()
    if not ok then
        print("|cFF56D1FFQUI:|r " .. ns.L["Options could not be loaded (%s)."]:format(tostring(reason)))
        return false
    end

    if self.GUI and type(self.GUI.Toggle) == "function" then
        self.GUI:Toggle()
        return true
    end

    print("|cFF56D1FFQUI:|r " .. ns.L["Options are not available yet. Try again in a moment."])
    return false
end

function QUI:ShowOptions()
    local ok, reason = self:EnsureOptionsLoaded()
    if not ok then
        print("|cFF56D1FFQUI:|r " .. ns.L["Options could not be loaded (%s)."]:format(tostring(reason)))
        return false
    end

    if self.GUI and type(self.GUI.Show) == "function" then
        self.GUI:Show()
        return true
    end

    return false
end

local function OpenQUIOptions()
    QUI:OpenOptions()
end

local blizzardSettingsAttempts = 0
local function CreateBlizzardSettingsPanel()
    if _G.QUI_BlizzardSettingsPanel then
        return
    end
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        blizzardSettingsAttempts = blizzardSettingsAttempts + 1
        if blizzardSettingsAttempts < 20 and C_Timer and C_Timer.After then
            C_Timer.After(0.5, CreateBlizzardSettingsPanel)
        end
        return
    end

    local panel = CreateFrame("Frame", "QUI_BlizzardSettingsPanel")
    panel.name = "QUI"

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("QUI")

    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetWidth(520)
    desc:SetJustifyH("LEFT")
    desc:SetText(ns.L["Open the QUI configuration window."])

    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(180, 32)
    btn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    btn:SetText(ns.L["Open QUI"])
    btn:SetScript("OnClick", OpenQUIOptions)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "QUI")
    Settings.RegisterAddOnCategory(category)
end

ns.RunAfterFirstFrame(CreateBlizzardSettingsPanel, 0.1)

-- Deferred importstring loading: importstring files register loaders
-- instead of eagerly constructing large tables at login. Data is built
-- on first access (when the user opens the Import tab).
QUI._importLoaders = {}
QUI.imports = setmetatable({}, {
    __index = function(self, key)
        local loader = QUI._importLoaders[key]
        if loader then
            local data = loader()
            rawset(self, key, data)
            QUI._importLoaders[key] = nil -- free the loader closure
            return data
        end
        return nil
    end,
})

-- Preset profiles: bundled QUI profile strings that users can install as
-- real AceDB profiles from the Profiles tab. Each entry maps an
-- _importLoaders key to a human-friendly profile name and description.
-- To add a new preset, just append an entry here and ship the matching
-- importstring file — the UI picks it up automatically.
QUI._presetProfiles = {
    { key = "StarterProfile", profileName = "Starter Profile", description = "QUI's shipped starter layout (same as a fresh install)" },
}

---@type table
QUI.defaults = {
    global = {
        ---@type string
        toggleOptionsKey = "",
    },
    char = {
        ---@type table
        debug = {
            ---@type boolean
            reload = false
        },
        ---@type table
        ncdm = {
            essential = {
                customEntries = { enabled = true, placement = "after", entries = {} },
            },
            utility = {
                customEntries = { enabled = true, placement = "after", entries = {} },
            },
        },
    }
}

function QUI:OnInitialize()
    -- Transient early DB so QUI.db is non-nil before QUICore:OnInitialize
    -- reassigns it to the live "QUIDB" store (core/main.lua). Not persisted:
    -- the legacy "QUI_DB" SavedVariable was retired.
    ---@type AceDBObject-3.0
    self.db = LibStub("AceDB-3.0"):New("QUI_InitTransientDB", self.defaults, "Default")

    -- NOTE: the new-profile seed is registered on the LIVE profile DB in
    -- core/main.lua (QUICore:OnInitialize / "QUIDB"), not here. This transient
    -- instance is overwritten by QUI.db = self.db there and is not the
    -- profile store, so an OnNewProfile seed on it would never fire for users.

    self:RegisterChatCommand("qui", "SlashCommandOpen")
    self:RegisterChatCommand("quaziiui", "SlashCommandOpen")
    self:RegisterChatCommand("rl", "SlashCommandReload")
    self:RegisterChatCommand("qpull", "SlashCommandPull")
    self:RegisterChatCommand("quipull", "SlashCommandPull")
    -- Register our media files with LibSharedMedia
    self:CheckMediaRegistration()
end

-- Quick Keybind Mode shortcut (/kb)
SLASH_QUIKB1 = "/kb"
SlashCmdList["QUIKB"] = function()
    local LibKeyBound = LibStub("LibKeyBound-1.0", true)
    if LibKeyBound then
        LibKeyBound:Toggle()
    elseif QuickKeybindFrame then
        -- Fallback to Blizzard's Quick Keybind Mode (no mousewheel support)
        ShowUIPanel(QuickKeybindFrame)
    else
        print("|cff60A5FAQUI:|r " .. ns.L["Quick Keybind Mode not available."])
    end
end

-- Cooldown Settings shortcut (/cdm)
SLASH_QUI_CDM1 = "/cdm"
SlashCmdList["QUI_CDM"] = function()
    if CooldownViewerSettings then
        CooldownViewerSettings:SetShown(not CooldownViewerSettings:IsShown())
    else
        print("|cff60A5FAQUI:|r " .. ns.L["Cooldown Settings not available. Enable CDM first."])
    end
end

function QUI:SlashCommandOpen(input)
    if input and input == "debug" then
        self.db.char.debug.reload = true
        QUI:SafeReload()
    elseif input and (input == "layout" or input == "unlock" or input == "editmode") then
        -- Toggle Layout Mode (with backward compat aliases)
        if _G.QUI_ToggleLayoutMode then
            _G.QUI_ToggleLayoutMode()
        else
            print("|cff60A5FAQUI:|r " .. ns.L["Layout Mode not loaded yet."])
        end
        return
    elseif input and input == "cdm" then
        if _G.QUI_OpenCDMComposer then
            _G.QUI_OpenCDMComposer()
        else
            print("|cff60A5FAQUI:|r " .. ns.L["CDM Spell Composer not available. Enable CDM first."])
        end
        return
    elseif input and input:match("^cdm_cache") then
        -- /qui cdm_cache               → status (cache sizes + dirty flags)
        -- /qui cdm_cache status        → same
        -- /qui cdm_cache reset         → wipe + rebuild (OOC only, aggressive)
        local sub = input:match("^cdm_cache%s+(%S+)") or "status"
        local SD   = ns.CDMSpellData
        local IC   = ns.CDMIcons
        local BR   = ns.CDMBars
        if not SD then
            print("|cff60A5FAQUI:|r " .. ns.L["CDM not loaded."])
            return
        end
        if sub == "status" then
            local s     = SD.GetCacheStats and SD:GetCacheStats() or {}
            local ic    = (IC and IC.GetCacheStats) and IC:GetCacheStats() or {}
            local br    = (BR and BR.GetCacheStats) and BR:GetCacheStats() or {}
            local fr    = ns.GetCDMFrameCacheStats and ns.GetCDMFrameCacheStats() or {}
            local bm    = (ns.CDMBlizzMirror and ns.CDMBlizzMirror.GetCacheStats)
                and ns.CDMBlizzMirror.GetCacheStats() or {}
            local rt    = (ns.CDMRuntimeStore and ns.CDMRuntimeStore.GetStats)
                and ns.CDMRuntimeStore.GetStats() or {}
            local rs    = (ns.CDMResolvers and ns.CDMResolvers.GetMirrorPolicyStats)
                and ns.CDMResolvers.GetMirrorPolicyStats() or {}
            local combat = InCombatLockdown() and "true" or "false"
            print(("|cff60A5FAQUI cdm_cache:|r status (combat=%s)"):format(combat))
            print(("  hud_visibility frames:    dirty=%s size=%d"):format(
                tostring(fr.dirty), tonumber(fr.size) or 0))
            print(("  child map (spellID→child): dirty=%s size=%d"):format(
                tostring(s.childMapDirty), tonumber(s.childMapSize) or 0))
            print(("  captured aura index:      entries=%d units=%d spellKeys=%d nameKeys=%d"):format(
                tonumber(s.capturedAuraEntries) or 0,
                tonumber(s.capturedAuraUnits) or 0,
                tonumber(s.capturedAuraSpellKeys) or 0,
                tonumber(s.capturedAuraNameKeys) or 0))
            print(("  Blizzard mirror:          states=%d info=%d spellMap=%d directMap=%d"):format(
                tonumber(bm.mirrorStates) or 0,
                tonumber(bm.cooldownInfo) or 0,
                tonumber(bm.spellMapEntries) or 0,
                tonumber(bm.directSpellMapEntries) or 0))
            print(("  runtime store:            states=%d version=%d"):format(
                tonumber(rt.states) or 0,
                tonumber(rt.version) or 0))
            print(("  stale mirror skips:       gcd=%d inactive=%d total=%d"):format(
                tonumber(rs.staleGCDSkips) or 0,
                tonumber(rs.staleInactiveSkips) or 0,
                tonumber(rs.staleMirrorSkips) or 0))
            print(("  learned cooldowns:        dirty=%s size=%d"):format(
                tostring(s.learnedDirty), tonumber(s.learnedSize) or 0))
            print(("  tick aura caches:         data=%d dur=%d exp=%d app=%d"):format(
                tonumber(s.tickAuraData) or 0,
                tonumber(s.tickAuraDuration) or 0,
                tonumber(s.tickAuraExpiration) or 0,
                tonumber(s.tickAuraApplication) or 0))
            print(("  resolve memos:            icon=%d auraActive=%d"):format(
                tonumber(s.resolveIconMemo) or 0,
                tonumber(s.resolveAuraMemo) or 0))
            print(("  totem slot map:           size=%d"):format(
                tonumber(s.totemSlotMap) or 0))
            print(("  texture cycle cache:      size=%d"):format(
                tonumber(ic.textureCycleCache) or 0))
            print(("  bar pool:                 active=%d"):format(
                tonumber(br.activeBars) or 0))
            print(("  icon update:              barsDirty=%s pending=%s"):format(
                tostring(ic.barsDirty), tostring(ic.updatePending)))
            if ic.iconEventProfileTop and #ic.iconEventProfileTop > 0 then
                print(("  icon events:              window=%.1fs"):format(
                    tonumber(ic.iconEventProfileWindow) or 0))
                for _, row in ipairs(ic.iconEventProfileTop) do
                    print(("    %-30s %6.2f ms/s  %5.0f/s"):format(
                        tostring(row.event),
                        tonumber(row.msPerSec) or 0,
                        tonumber(row.callsPerSec) or 0))
                end
            end
            print("  run |cFFFFFF00/qui cdm_cache reset|r to wipe and rebuild (OOC only).")
            return
        elseif sub == "reset" then
            if InCombatLockdown() then
                print("|cff60A5FAQUI:|r " .. ns.L["cdm_cache reset blocked in combat — try again out of combat."])
                return
            end
            -- Wipe — order doesn't matter, all are independent.
            if ns.InvalidateCDMFrameCache then ns.InvalidateCDMFrameCache() end
            if SD.InvalidateLearnedCache then SD:InvalidateLearnedCache() end
            if SD.ClearChildCaches       then SD:ClearChildCaches()       end
            if IC and IC.ClearTextureCycleCache then IC:ClearTextureCycleCache() end
            if BR and BR.ClearPerBarCaches      then BR:ClearPerBarCaches()      end
            if ns.CDMRuntimeStore and ns.CDMRuntimeStore.ClearAll then ns.CDMRuntimeStore.ClearAll() end
            if ns.CDMResolvers and ns.CDMResolvers.ResetMirrorPolicyStats then ns.CDMResolvers.ResetMirrorPolicyStats() end
            -- Rebuild — re-derive owned spells from current viewer state.
            if SD.CheckAllDormantSpells   then SD:CheckAllDormantSpells()   end
            if SD.ReconcileAllContainers  then SD:ReconcileAllContainers()  end
            -- Force a full repaint even if reconcile didn't add anything.
            if _G.QUI_OnSpellDataChanged then _G.QUI_OnSpellDataChanged() end
            if IC and IC.RequestFullUpdate then IC:RequestFullUpdate() end
            print("|cff60A5FAQUI:|r " .. ns.L["cdm_cache reset — caches wiped, full rebuild scheduled."])
            return
        else
            print("|cff60A5FAQUI:|r " .. ns.L["unknown cdm_cache subcommand '%s'."]:format(tostring(sub)))
            print("  usage: |cFFFFFF00/qui cdm_cache|r [status|reset]")
            return
        end
    elseif input and input:match("^bindkey") then
        -- /qui bindkey            → show current key
        -- /qui bindkey CTRL-O     → bind (session binding, re-applied at login)
        -- /qui bindkey none       → clear
        local key = input:match("^bindkey%s+(%S+)")
        local current = self.db.global.toggleOptionsKey or ""
        if not key then
            print("|cff60A5FAQUI:|r " .. ns.L["options keybind: %1$s — usage: |cFFFFFF00/qui bindkey CTRL-O|r or |cFFFFFF00/qui bindkey none|r"]:format(current ~= "" and current or "none"))
            return
        end
        if InCombatLockdown() then
            print("|cff60A5FAQUI:|r " .. ns.L["cannot change keybinds in combat."])
            return
        end
        if key:lower() == "none" or key:lower() == "off" then
            if current ~= "" then SetBinding(current) end
            self.db.global.toggleOptionsKey = ""
            print("|cff60A5FAQUI:|r " .. ns.L["options keybind cleared."])
            return
        end
        key = key:upper()
        if current ~= "" and current ~= key then SetBinding(current) end
        self.db.global.toggleOptionsKey = key
        SetBindingClick(key, "QUI_ToggleOptionsButton")
        print("|cff60A5FAQUI:|r " .. ns.L["options keybind set to %1$s."]:format(key))
        return
    elseif input and input:match("^gse") then
        -- /qui gse          → dump current override state
        -- /qui gse debug    → toggle click-event logging
        -- /qui gse tail [N] → print last N events from the log
        local sub, arg = input:match("^gse%s+(%S+)%s*(%S*)")
        if sub == "debug" then
            if _G.QUI_GSEToggleDebug then _G.QUI_GSEToggleDebug() end
        elseif sub == "tail" then
            if _G.QUI_GSETail then _G.QUI_GSETail(tonumber(arg) or 20) end
        else
            if _G.QUI_GSEDump then
                _G.QUI_GSEDump()
            else
                print("|cff60A5FAQUI:|r " .. ns.L["GSE compat shim not loaded."])
            end
        end
        return
    elseif input and input:match("^migration") then
        -- /qui migration             → status (current schema version + backup slots)
        -- /qui migration status      → same
        -- /qui migration restore     → roll back to most recent snapshot (slot 1)
        -- /qui migration restore N   → roll back to snapshot in slot N (1 = newest)
        local sub, arg = input:match("^migration%s+(%S+)%s*(%S*)")
        sub = sub or "status"
        local Mig = self.Migrations
        local profile = self.db and self.db.profile
        if not (Mig and profile) then
            print("|cff60A5FAQUI:|r " .. ns.L["Migration system not available."])
            return
        end
        if sub == "status" then
            local v = tonumber(profile._schemaVersion) or 0
            print(("|cff60A5FAQUI migration:|r current profile schema version = v%d"):format(v))
            local container = Mig.GetBackupInfo and Mig.GetBackupInfo(profile)
            local slots = container and container.slots
            if slots and #slots > 0 then
                print(("  %d backup slot(s) available (1 = newest):"):format(#slots))
                for i, entry in ipairs(slots) do
                    local savedAtStr = "unknown"
                    if type(entry.savedAt) == "number" and entry.savedAt > 0 then
                        savedAtStr = date("%Y-%m-%d %H:%M:%S", entry.savedAt)
                    end
                    print(("    [%d] v%s → v%s (saved %s)"):format(
                        i,
                        tostring(entry.fromVersion or "?"),
                        tostring(entry.toVersion or "?"),
                        savedAtStr))
                end
                print("  run |cFFFFFF00/qui migration restore [N]|r to roll back to slot N (default 1).")
            else
                print("  no migration backup on file for this profile.")
            end
        elseif sub == "restore" then
            if not Mig.Restore then
                print("|cff60A5FAQUI:|r " .. ns.L["Restore not supported by this build."])
                return
            end
            local slotIndex = tonumber(arg) or 1
            local ok, info = Mig.Restore(profile, slotIndex)
            if ok then
                print(("|cff60A5FAQUI migration:|r restored profile from slot %d to pre-migration state (v%s). Reloading..."):format(
                    slotIndex,
                    tostring(info and info.fromVersion or "?")))
                QUI:SafeReload()
            else
                print("|cff60A5FAQUI migration:|r " .. tostring(info or ns.L["restore failed"]))
            end
        else
            print("|cff60A5FAQUI:|r " .. ns.L["unknown migration subcommand. Use: status, restore [N]"])
        end
        return
    elseif input and input == "miglog" then
        -- Dump the buffered migration debug log. Migrations run during
        -- OnInitialize/OnEnable when the chat frame isn't ready, so they
        -- buffer messages into _G.QUI_MIGRATION_LOG instead of printing
        -- directly. To enable buffering on next /reload, run:
        --   /run QUI_MIGRATION_DEBUG = true
        -- and then /reload. After login, /qui miglog dumps it.
        local log = _G.QUI_MIGRATION_LOG
        if type(log) ~= "table" or #log == 0 then
            print("|cff60A5FAQUI:|r " .. ns.L["migration log is empty."])
            print("  Enable with |cFFFFFF00/run QUI_MIGRATION_DEBUG = true|r then |cFFFFFF00/reload|r.")
            return
        end
        print(("|cff60A5FAQUI migration log (%d lines):|r"):format(#log))
        for i, line in ipairs(log) do
            print(("  |cff888888%3d|r %s"):format(i, tostring(line)))
        end
        return
    elseif input and input == "miglog clear" then
        _G.QUI_MIGRATION_LOG = {}
        print("|cff60A5FAQUI:|r " .. ns.L["migration log cleared."])
        return
    elseif input and input == "anchordump" then
        -- Live dump of frameAnchoring entries for the active profile.
        -- Shows both raw SV and proxy-merged values for keys we care about.
        local profile = self.db and self.db.profile
        if not profile then
            print("|cff60A5FAQUI:|r " .. ns.L["no profile loaded."])
            return
        end
        local raw = self.db.sv and self.db.sv.profiles
            and self.db.sv.profiles[self.db:GetCurrentProfile()]
        local rawFa = raw and raw.frameAnchoring
        local proxyFa = profile.frameAnchoring
        print(("|cff60A5FAQUI anchordump:|r profile=%s schema=%s"):format(
            tostring(self.db:GetCurrentProfile()),
            tostring(profile._schemaVersion)))
        local function dump(label, fa, key)
            local e = fa and fa[key]
            if not e then
                print(("  %s.%s = nil"):format(label, key))
                return
            end
            print(("  %s.%s = {parent=%s point=%s rel=%s ofs=%s/%s enabled=%s keepInPlace=%s}"):format(
                label, key,
                tostring(e.parent), tostring(e.point), tostring(e.relative),
                tostring(e.offsetX), tostring(e.offsetY),
                tostring(e.enabled), tostring(e.keepInPlace)))
        end
        for _, key in ipairs({"debuffFrame", "buffFrame", "minimap", "bar1", "bar2", "bar3"}) do
            dump("RAW  ", rawFa, key)
            dump("PROXY", proxyFa, key)
        end
        -- Also dump live frame positions if frames exist
        local function framePos(name, frameKey)
            local frame = nil
            if frameKey == "debuffFrame" then frame = _G.QUI_DebuffIconContainer end
            if frameKey == "buffFrame" then frame = _G.QUI_BuffIconContainer end
            if frameKey == "minimap" then frame = _G.Minimap end
            if not frame or not frame.GetPoint then return end
            local n = frame:GetNumPoints() or 0
            if n == 0 then
                print(("  LIVE %s = (no points, %dx%d)"):format(name, frame:GetWidth() or 0, frame:GetHeight() or 0))
                return
            end
            for i = 1, n do
                local pt, rt, rp, x, y = frame:GetPoint(i)
                local rtName = type(rt) == "table" and (rt.GetName and rt:GetName() or "anon") or tostring(rt)
                print(("  LIVE %s [%d/%d] = %s -> %s.%s ofs=%.0f/%.0f"):format(
                    name, i, n, tostring(pt), rtName, tostring(rp), x or 0, y or 0))
            end
        end
        framePos("debuffFrame", "debuffFrame")
        framePos("buffFrame", "buffFrame")
        framePos("minimap", "minimap")
        return
    elseif input and input:match("^tooltipdebug") then
        -- /qui tooltipdebug on [N]  -> print tooltip churn samples every N seconds
        -- /qui tooltipdebug report  -> print the current sample without resetting
        -- /qui tooltipdebug slow N  -> log functions slower than N ms in samples
        -- /qui tooltipdebug bypass qol|skin|all|off -> isolate tooltip processors
        local subcmd, arg = input:match("^tooltipdebug%s+(%S+)%s*(%S*)")
        if _G.QUI_TooltipDebug then
            _G.QUI_TooltipDebug(subcmd, arg)
        else
            print("|cff60A5FAQUI:|r " .. ns.L["Tooltip debug sampler not loaded yet."])
        end
        return
    elseif input and input == "tooltipdbg" then
        local isS = issecretvalue
        local count = 0
        local f = EnumerateFrames()
        while f do
            local vis = f:IsVisible()
            if not isS(vis) and vis then
                -- Check for white backdrop color (explicit white via GetBackdropColor)
                if f.GetBackdropColor then
                    local r, g, b = f:GetBackdropColor()
                    if not isS(r) and r and r > 0.9 and g > 0.9 and b > 0.9 then
                        local h = f:GetHeight()
                        if not isS(h) and h and h > 10 then
                            count = count + 1
                            print("|cffff0000WHITE BACKDROP:|r", f:GetName() or tostring(f), ("r=%.2f g=%.2f b=%.2f h=%.0f"):format(r, g, b, h))
                            local p = f:GetParent()
                            if p then
                                print("  parent:", p:GetName() or tostring(p))
                            end
                        end
                    end
                end
                -- Check for orphaned overlay: has BackdropTemplate + backdrop with bgFile,
                -- but backdropColor is nil — CENTER piece renders as default white.
                -- Border-only backdrops (no bgFile) are excluded — no background to be white.
                if f.backdropInfo and f.backdropInfo.bgFile and not f.backdropColor and f.GetBackdropColor then
                    local h = f:GetHeight()
                    if not isS(h) and h and h > 10 then
                        count = count + 1
                        print("|cffff4400ORPHANED OVERLAY:|r", f:GetName() or tostring(f), ("h=%.0f backdropColor=nil"):format(h))
                        local p = f:GetParent()
                        if p then
                            print("  parent:", p:GetName() or tostring(p))
                        end
                        -- If it has _qui color fields, recover automatically
                        if f._quiBgR then
                            print("  _qui colors present — recovering")
                            pcall(f.SetBackdropColor, f, f._quiBgR, f._quiBgG, f._quiBgB, f._quiBgA or 1)
                            if f._quiBorderR then
                                pcall(f.SetBackdropBorderColor, f, f._quiBorderR, f._quiBorderG, f._quiBorderB, f._quiBorderA or 1)
                            end
                        end
                    end
                end
                -- Check for NineSlice with alpha > 0
                if f.NineSlice then
                    local a = f.NineSlice:GetAlpha()
                    if not isS(a) and a and a > 0 then
                        count = count + 1
                        print("|cffff8800NINESLICE VISIBLE:|r", f:GetName() or tostring(f), ("alpha=%.2f"):format(a))
                    end
                end
            end
            f = EnumerateFrames(f)
        end
        if count == 0 then
            print("|cff60A5FAQUI:|r No white backdrops or visible NineSlices found.")
        else
            print("|cff60A5FAQUI:|r Found", count, "issues above.")
        end
        return
    elseif input and input:match("^memaudit") then
        if _G.QUI_MemAudit then
            -- Greedy capture for trailing args so `memaudit exp <name> on/off`
            -- reaches the handler intact. Existing one-arg subcommands (auto N,
            -- gc, diff) still work because the handler treats `arg` as opaque.
            local subcmd, arg = input:match("^memaudit%s+(%S+)%s+(.+)$")
            if not subcmd then
                subcmd = input:match("^memaudit%s+(%S+)$")
            end
            _G.QUI_MemAudit(subcmd, arg)
        else
            print("|cff60A5FAQUI:|r " .. ns.L["Memory audit not loaded yet."])
        end
        return
    elseif input and input:match("^diagnose") then
        -- /qui diagnose        → report Edit Mode state + recent ADDON_ACTION_BLOCKED events
        -- /qui diagnose clear  → clear the diagnostic ring buffer
        if _G.QUI_DiagnoseEditMode then
            local subcmd = input:match("^diagnose%s+(%S+)")
            _G.QUI_DiagnoseEditMode(subcmd)
        else
            print("|cff60A5FAQUI:|r " .. ns.L["Edit Mode diagnostic not loaded yet."])
        end
        return
    elseif input and input == "perf" then
        if _G.QUI_TogglePerfMonitor then
            _G.QUI_TogglePerfMonitor()
        else
            print("|cff60A5FAQUI:|r " .. ns.L["Performance Monitor not loaded yet."])
        end
        return
    elseif input and input:match("^combatprof") then
        -- /qui combatprof [on|off|report|reset]
        --   Diagnoses combat-end stutter: wraps named CDM functions, watches
        --   C_Timer.After scheduling, and detects >50ms frame spikes within
        --   2s of PLAYER_REGEN_ENABLED. Auto-prints a report after each combat.
        if _G.QUI_CombatProf then
            local sub = input:match("^combatprof%s+(%S+)")
            _G.QUI_CombatProf(sub)
        else
            print("|cff60A5FAQUI:|r " .. ns.L["combat profiler not loaded yet."])
        end
        return
    end

    -- Default: Open custom GUI
    self:OpenOptions()
end

function QUI:SlashCommandReload()
    QUI:SafeReload()
end

function QUI:SlashCommandPull(input)
    if not (C_PartyInfo and C_PartyInfo.DoCountdown) then
        self:Print(ns.L["Pull countdown is not available on this client."])
        return
    end

    local secs = tonumber(input)
    if not secs then
        secs = 10
    end
    secs = math.floor(secs + 0.5)
    if secs < 1 then
        secs = 1
    elseif secs > 60 then
        secs = 60
    end

    local ok = C_PartyInfo.DoCountdown(secs)
    if not ok then
        self:Print(ns.L["Could not start pull countdown (need to be in a group and have permission)."])
    end
end

function QUI:OnEnable()
    -- Run backward-compatibility migrations now that QUICore:OnInitialize()
    -- has created the real profile database (QUIDB → QUI.db).
    -- OnEnable runs after all OnInitialize calls but still during ADDON_LOADED.
    self:BackwardsCompat()

    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("ADDON_LOADED")
    self:RegisterOptionalPullAlias()

    -- Initialize QUICore (AceDB-based integration)
    if self.QUICore then
        -- Show intro message if enabled (defaults to true)
        if self.db.profile.chat.showIntroMessage ~= false then
            print("|cFF30D1FFQUI|r " .. ns.L["loaded. |cFFFFFF00/qui|r to setup."])
            print("|cFF30D1FFQUI REMINDER:|r")
            print("|cff60A5FA1.|r " .. ns.L["ENABLE |cFFFFFF00Cooldown Manager|r in Options > Gameplay Enhancement"])
            print("|cff60A5FA2.|r " .. ns.L["Action Bars & Menu Bar |cFFFFFF00HIDDEN|r on mouseover |cFFFFFF00by default|r. Go to |cFFFFFF00'Actionbars'|r tab in |cFFFFFF00/qui|r to unhide."])
            print("|cff60A5FA3.|r " .. ns.L["Use |cFFFFFF00100% Icon Size|r on CDM Essential & Utility bars for best results."])
            print("|cff60A5FA4.|r " .. ns.L["Use |cFFFFFF00/qui layout|r to position frames, then click |cFFFFFF00Save|r."])
        end
    end
end

function QUI:RegisterOptionalPullAlias()
    local existingOwner = hash_SlashCmdList and hash_SlashCmdList["/PULL"]
    if existingOwner then
        self.pullAliasOwned = false
        return false
    end

    SlashCmdList[QUI_PULL_SLASH_KEY] = function(msg)
        QUI:SlashCommandPull(msg)
    end
    _G["SLASH_" .. QUI_PULL_SLASH_KEY .. "1"] = "/pull"
    self.pullAliasOwned = true
    return true
end

function QUI:UnregisterOptionalPullAlias()
    if not self.pullAliasOwned then
        return
    end

    SlashCmdList[QUI_PULL_SLASH_KEY] = nil
    _G["SLASH_" .. QUI_PULL_SLASH_KEY .. "1"] = nil
    if hash_SlashCmdList and hash_SlashCmdList["/PULL"] == QUI_PULL_SLASH_KEY then
        hash_SlashCmdList["/PULL"] = nil
    end
    self.pullAliasOwned = false
end

function QUI:ADDON_LOADED(_, addonName)
    if not addonName or not PULL_COMMAND_OWNERS[addonName] then
        return
    end

    self:UnregisterOptionalPullAlias()
end

-- Recover QUI frames with orphaned overlays (backdropInfo set, backdropColor nil).
-- Uses backup _quiBg* fields stored by Helpers.SetFrameBackdropColor.
-- Falls back to default dark color for QUI-named frames without backup fields.
local strsub = string.sub
local function RecoverQUIBackdrops()
    local f = EnumerateFrames()
    while f do
        if f.backdropInfo and f.backdropInfo.bgFile and not f.backdropColor then
            if f._quiBgR then
                pcall(f.SetBackdropColor, f, f._quiBgR, f._quiBgG, f._quiBgB, f._quiBgA or 1)
                if f._quiBorderR then
                    pcall(f.SetBackdropBorderColor, f, f._quiBorderR, f._quiBorderG, f._quiBorderB, f._quiBorderA or 1)
                end
            else
                -- Fallback: QUI-named frames without backup colors get default dark.
                -- No QUI frame intentionally has a white background; a nil backdropColor
                -- means the initial SetBackdropColor was lost (taint, error, timing).
                local name = f.GetName and f:GetName()
                if name and type(name) == "string" and strsub(name, 1, 4) == "QUI_" then
                    pcall(f.SetBackdropColor, f, 0.05, 0.05, 0.05, 0.95)
                    pcall(f.SetBackdropBorderColor, f, 0, 0, 0, 1)
                end
            end
        end
        f = EnumerateFrames(f)
    end
end

function QUI:PLAYER_REGEN_ENABLED()
    -- Recover any QUI backdrops that got orphaned during combat
    -- (SetBackdrop can error on secret values, preventing SetBackdropColor from running)
    RecoverQUIBackdrops()
end

function QUI:PLAYER_ENTERING_WORLD(_, isInitialLogin, isReloadingUi)
    -- Ensure debug table exists
    if not self.db.char.debug then
        self.db.char.debug = { reload = false }
    end

    if not self.DEBUG_MODE then
        if self.db.char.debug.reload then
            self.DEBUG_MODE = true
            self.db.char.debug.reload = false
        end
    end

    if self.DEBUG_MODE then
        local ok, reason = self:EnsureDebugToolsLoaded()
        if not ok then
            self:Print("|cff60A5FAQUI:|r " .. ns.L["Debug tools could not be loaded (%s)."]:format(tostring(reason)))
        end
        self:DebugPrint("Debug Mode Enabled")
    end

    -- Re-apply the Lua-managed options keybind (session bindings don't persist).
    ApplyToggleOptionsKeybind()

    -- Auto-recover QUI frame backdrops after the first rendered frame.
    ns.RunAfterFirstFrame(RecoverQUIBackdrops, 0.5)
end

function QUI:DebugPrint(...)
    if self.DEBUG_MODE then
        self:Print(...)
    end
end

-- ADDON COMPARTMENT FUNCTIONS --
function QUI_CompartmentClick()
    QUI:OpenOptions()
end

local GameTooltip = GameTooltip
function QUI_CompartmentOnEnter(self, button)
    GameTooltip:ClearLines()
    GameTooltip:SetOwner(type(self) ~= "string" and self or button, "ANCHOR_LEFT")
    GameTooltip:AddLine("QUI v" .. QUI.versionString)
    GameTooltip:AddLine(ns.L["Left Click: Open Options"])
    GameTooltip:Show()
end

function QUI_CompartmentOnLeave()
    GameTooltip:Hide()
end
