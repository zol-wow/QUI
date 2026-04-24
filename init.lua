-- Keybinding display names (must be global before Bindings.xml loads)
BINDING_NAME_QUI_TOGGLE_OPTIONS = "Open QUI Options"
---@type table|AceAddon
QUI = LibStub("AceAddon-3.0"):NewAddon("QUI", "AceConsole-3.0", "AceEvent-3.0")
QUI.DEBUG_MODE = false
QUI.pullAliasOwned = false

local QUI_PULL_SLASH_KEY = "QUIPULL_ALIAS"
local PULL_COMMAND_OWNERS = {
    ["BigWigs"] = true,
    ["BigWigs_Core"] = true,
    ["DBM-Core"] = true,
}

-- Version info
QUI.versionString = C_AddOns.GetAddOnMetadata("QUI", "Version") or "2.00"

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
    { key = "OakTankDPS",  profileName = "Oak's Tank/DPS", description = "Oak's Tank/DPS UI layout" },
    { key = "OakHealer",   profileName = "Oak's Healer",   description = "Oak's Healer UI layout" },
    { key = "CocoProfile", profileName = "Coco",            description = "Coco's personal UI layout" },
    { key = "NokterianHealing", profileName = "Nokterian Healing Profile", description = "Nokterian's healing UI layout" },
}

---@type table
QUI.defaults = {
    global = {},
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
    -- Migrate old QuaziiUI_DB to QUI_DB if needed
    if QuaziiUI_DB and not QUI_DB then
        QUI_DB = QuaziiUI_DB
    end

    ---@type AceDBObject-3.0
    self.db = LibStub("AceDB-3.0"):New("QUI_DB", self.defaults, "Default")

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
        print("|cff60A5FAQUI:|r Quick Keybind Mode not available.")
    end
end

-- Cooldown Settings shortcut (/cdm)
SLASH_QUI_CDM1 = "/cdm"
SlashCmdList["QUI_CDM"] = function()
    if CooldownViewerSettings then
        CooldownViewerSettings:SetShown(not CooldownViewerSettings:IsShown())
    else
        print("|cff60A5FAQUI:|r Cooldown Settings not available. Enable CDM first.")
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
            print("|cff60A5FAQUI:|r Layout Mode not loaded yet.")
        end
        return
    elseif input and input == "cdm" then
        if _G.QUI_OpenCDMComposer then
            _G.QUI_OpenCDMComposer()
        else
            print("|cff60A5FAQUI:|r CDM Spell Composer not available. Enable CDM first.")
        end
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
                print("|cff60A5FAQUI:|r GSE compat shim not loaded.")
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
            print("|cff60A5FAQUI:|r Migration system not available.")
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
                print("|cff60A5FAQUI:|r Restore not supported by this build.")
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
                print("|cff60A5FAQUI migration:|r " .. tostring(info or "restore failed"))
            end
        else
            print("|cff60A5FAQUI:|r unknown migration subcommand. Use: status, restore [N]")
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
            print("|cff60A5FAQUI:|r migration log is empty.")
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
        print("|cff60A5FAQUI:|r migration log cleared.")
        return
    elseif input and input == "anchordump" then
        -- Live dump of frameAnchoring entries for the active profile.
        -- Shows both raw SV and proxy-merged values for keys we care about.
        local profile = self.db and self.db.profile
        if not profile then
            print("|cff60A5FAQUI:|r no profile loaded.")
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
            local subcmd = input:match("^memaudit%s+(%S+)")
            _G.QUI_MemAudit(subcmd)
        else
            print("|cff60A5FAQUI:|r Memory audit not loaded yet.")
        end
        return
    elseif input and input == "perf" then
        if _G.QUI_TogglePerfMonitor then
            _G.QUI_TogglePerfMonitor()
        else
            print("|cff60A5FAQUI:|r Performance Monitor not loaded yet.")
        end
        return
    end

    -- Default: Open custom GUI
    if self.GUI then
        self.GUI:Toggle()
    else
        print("|cFF56D1FFQUI:|r GUI not loaded yet. Try again in a moment.")
    end
end

function QUI:SlashCommandReload()
    QUI:SafeReload()
end

function QUI:SlashCommandPull(input)
    if not (C_PartyInfo and C_PartyInfo.DoCountdown) then
        self:Print("Pull countdown is not available on this client.")
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
        self:Print("Could not start pull countdown (need to be in a group and have permission).")
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
            print("|cFF30D1FFQUI|r loaded. |cFFFFFF00/qui|r to setup.")
            print("|cFF30D1FFQUI REMINDER:|r")
            print("|cff60A5FA1.|r ENABLE |cFFFFFF00Cooldown Manager|r in Options > Gameplay Enhancement")
            print("|cff60A5FA2.|r Action Bars & Menu Bar |cFFFFFF00HIDDEN|r on mouseover |cFFFFFF00by default|r. Go to |cFFFFFF00'Actionbars'|r tab in |cFFFFFF00/qui|r to unhide.")
            print("|cff60A5FA3.|r Use |cFFFFFF00100% Icon Size|r on CDM Essential & Utility bars for best results.")
            print("|cff60A5FA4.|r Use |cFFFFFF00/qui layout|r to position frames, then click |cFFFFFF00Save|r.")
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
            self:DebugPrint("Debug Mode Enabled")
        end
    else
        self:DebugPrint("Debug Mode Enabled")
    end

    -- Auto-recover QUI frame backdrops after all modules have initialized
    C_Timer.After(3, RecoverQUIBackdrops)
end

function QUI:DebugPrint(...)
    if self.DEBUG_MODE then
        self:Print(...)
    end
end

-- ADDON COMPARTMENT FUNCTIONS --
function QUI_CompartmentClick()
    -- Open the new GUI
    if QUI.GUI then
        QUI.GUI:Toggle()
    end
end

local GameTooltip = GameTooltip
function QUI_CompartmentOnEnter(self, button)
    GameTooltip:ClearLines()
    GameTooltip:SetOwner(type(self) ~= "string" and self or button, "ANCHOR_LEFT")
    GameTooltip:AddLine("QUI v" .. QUI.versionString)
    GameTooltip:AddLine("Left Click: Open Options")
    GameTooltip:Show()
end

function QUI_CompartmentOnLeave()
    GameTooltip:Hide()
end
