-- modules/chat/combat_log_tab.lua
-- Embeds Blizzard's real combat-log frame (ChatFrame2) as a pinned tab in the
-- QUI custom chat display (window 1 only). Combat-log content + filtering stay
-- 100% Blizzard: we reparent ChatFrame2 and the native quick-filter bar
-- (CombatLogQuickButtonFrame_Custom) into the window container when the tab is
-- active, hide QUI's own render (SMF + scrollbar) for that window, and park the
-- frame on a SHOWN clipped off-screen anchor otherwise (see filter-taint notes
-- below). blizzard_suppress reads GetHostParent()/GetParkParent() to decide
-- ChatFrame2's enforced parent so it cooperates instead of yanking the frame
-- back to its park.
--
-- Taint posture: ChatFrame2 is an EditModeSystem frame and :ClearAllPoints /
-- :SetPoint are protected functions, so geometry mutation is insecure and must
-- never run during combat (protected-frame block). install() therefore defers
-- to PLAYER_REGEN_ENABLED while InCombatLockdown(). The content path itself is
-- Blizzard-internal; full taint validation is Drew's in-game pass. Fallback if
-- combat-log dispatch ever taints: detach ChatFrame2 from Edit Mode once before
-- owning geometry (docs/superpowers/specs/2026-06-09-combat-log-tab-design.md §6).
--
-- FILTER taint (the "all combat events show" bug): Blizzard_CombatLog wraps
-- ChatFrame2's OnShow/OnHide (Blizzard_CombatLog.lua:1456-1469) — OnShow runs
-- Blizzard_CombatLog_QuickButton_OnClick(currentFilter), which writes the
-- Blizzard_CombatLog_CurrentSettings/currentFilter globals and calls
-- C_CombatLog.ApplyFilterSettings; the filters land via the SecureOnly
-- C_CombatLogSecure.AddEventFilter AFTER C_CombatLogSecure.ClearEventFilters
-- (Blizzard_CombatLogProcessor.lua:121-183). If that wrapper fires on a
-- QUI-tainted path (our SetParent/Show flipping effective visibility), the
-- apply half-completes — filters cleared, re-add blocked — and the combat log
-- shows EVERYTHING from then on; the tainted globals keep every later apply
-- broken too. Two rules keep the wrapper off our execution path:
--   1. ChatFrame2 parks on a SHOWN, clipped, off-screen anchor — reparenting
--      between park and host container never changes effective visibility, so
--      OnShow/OnHide never fire from a QUI reparent.
--   2. The one Show() the embed may need (ChatFrame2 arrives hidden when it
--      was a docked, unselected tab) goes through a SecureHandler Execute so
--      the wrapper — and the whole filter re-apply — runs untainted
--      (same pattern as the WorldMap/Mail secure reposition).
local ADDON_NAME, ns = ... -- luacheck: ignore ADDON_NAME

local I = assert(ns.QUI.Chat and ns.QUI.Chat._internals,
    "QUI Chat: combat_log_tab.lua loaded before chat.lua. Check QUI_Chat.toc — chat.lua must precede combat_log_tab.lua.")

ns.QUI.Chat.CombatLogTab = ns.QUI.Chat.CombatLogTab or {}
local CombatLogTab = ns.QUI.Chat.CombatLogTab

local hostByWindow = {}  -- windowID -> container while active (else nil)
local activeWindow      -- the single window currently showing the combat log
local hiddenAnchor      -- shared hidden parent for parked chrome/quick-bar
local loadWaiter        -- waits for the LoadOnDemand combat-log addon/frame
local combatWaiter      -- waits for PLAYER_REGEN_ENABLED to finish a deferred embed
local stockFont         -- {file, height, flags} captured before the first QUI apply
local stockJustifyH     -- ChatFrame2's pre-QUI horizontal justification ("LEFT" stock)
local fontHookInstalled -- SetFont durability post-hook (installed once, gated on activeWindow)

local function HiddenAnchor()
    if not hiddenAnchor and _G.CreateFrame then
        hiddenAnchor = _G.CreateFrame("Frame", "QUI_CombatLogPark", _G.UIParent)
        hiddenAnchor:Hide()
    end
    return hiddenAnchor
end

-- ChatFrame2's park: SHOWN (never fires the OnShow/OnHide filter wrapper on
-- reparent — see header), clipped to 1px and positioned fully off-screen so a
-- parked combat log renders nothing. The quick bar and stripped chrome keep
-- using the plain hidden anchor (they carry no visibility side effects).
local shownPark
local function ShownPark()
    if not shownPark and _G.CreateFrame then
        shownPark = _G.CreateFrame("Frame", "QUI_CombatLogShownPark", _G.UIParent)
        shownPark:SetSize(1, 1)
        shownPark:SetPoint("TOPRIGHT", _G.UIParent, "BOTTOMLEFT", -20, -20)
        if shownPark.SetClipsChildren then
            shownPark:SetClipsChildren(true)
        end
        -- Explicitly shown: the whole point of this park is that ChatFrame2's
        -- effective visibility never changes while parked here.
        shownPark:Show()
    end
    return shownPark
end

-- Read by blizzard_suppress: where ChatFrame2 parks while its tab is inactive.
function CombatLogTab.GetParkParent()
    return ShownPark() or HiddenAnchor()
end

-- One-time secure Show: a docked, unselected ChatFrame2 arrives with its shown
-- flag false; flipping it from QUI code would run the Blizzard_CombatLog
-- OnShow wrapper tainted (header). A SecureHandler Execute shows it from the
-- restricted environment instead, so the wrapper's filter re-apply stays
-- secure. Falls back to a plain pcall Show when the secure path is
-- unavailable (no worse than the pre-fix behavior).
local secureShowDriver
local function EnsureShownSecure(cf)
    if not cf then return end
    if cf.IsShown and cf:IsShown() then return end
    if not secureShowDriver and _G.CreateFrame then
        local ok, drv = pcall(_G.CreateFrame, "Frame", "QUI_CombatLogSecureShow",
            nil, "SecureHandlerBaseTemplate")
        if ok and drv then secureShowDriver = drv end
    end
    if secureShowDriver and secureShowDriver.SetFrameRef and secureShowDriver.Execute then
        local okRef = pcall(secureShowDriver.SetFrameRef, secureShowDriver, "quiCombatLog", cf)
        if okRef then
            pcall(secureShowDriver.Execute, secureShowDriver, [=[
                local f = self:GetFrameRef("quiCombatLog")
                if f and not f:IsShown() then f:Show() end
            ]=])
        end
    end
    -- Fallback when the secure path didn't take (unprotected frame, missing
    -- template): plain Show — the pre-fix behavior.
    if not (cf.IsShown and cf:IsShown()) and cf.Show then
        pcall(cf.Show, cf)
    end
end

function CombatLogTab.IsEnabled()
    local s = I.GetSettings and I.GetSettings()
    local cd = s and s.customDisplay
    if type(cd) ~= "table" then return true end
    return cd.combatLogTab ~= false
end

-- Read by blizzard_suppress: ChatFrame2's enforced parent while active, else nil.
function CombatLogTab.GetHostParent()
    return activeWindow and hostByWindow[activeWindow] or nil
end

function CombatLogTab.IsActiveWindow(windowID)
    return activeWindow == (tonumber(windowID) or 1)
end

-- Blizzard_CombatLog is LoadOnDemand; CombatLogQuickButtonFrame_Custom is built
-- lazily. Guarantee both exist, then call cb. Returns true if ready now.
function CombatLogTab.EnsureLoaded(cb)
    if _G.CombatLogQuickButtonFrame_Custom and _G.ChatFrame2 then
        if cb then cb() end
        return true
    end
    if _G.C_AddOns and _G.C_AddOns.LoadAddOn then
        pcall(_G.C_AddOns.LoadAddOn, "Blizzard_CombatLog")
    end
    if _G.CombatLogQuickButtonFrame_Custom and _G.ChatFrame2 then
        if cb then cb() end
        return true
    end
    if not loadWaiter and _G.CreateFrame then
        loadWaiter = _G.CreateFrame("Frame")
    end
    if loadWaiter then
        loadWaiter:SetScript("OnEvent", function(self)
            if _G.CombatLogQuickButtonFrame_Custom and _G.ChatFrame2 then
                self:UnregisterAllEvents()
                self:SetScript("OnEvent", nil)
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function() if cb then cb() end end)
                elseif cb then cb() end
            end
        end)
        loadWaiter:RegisterEvent("ADDON_LOADED")
        loadWaiter:RegisterEvent("UPDATE_CHAT_WINDOWS")
    end
    return false
end

-- ChatFrame2 keeps its stock font otherwise; adopt the QUI chat font object
-- resolved by display_layer.ApplyTheme (a per-script font family in-game, so
-- CJK combat-log lines keep rendering). ApplyTheme calls this on every theme
-- refresh so live font changes land while the tab is open.
--
-- Durability: ChatFrame2 is neuter-EXEMPT (blizzard_suppress), so its
-- UPDATE_CHAT_WINDOWS handler stays live and re-asserts the saved per-window
-- font via SetFont (ChatFrameOverrides.lua:114-119) on every settings sync —
-- including at login, AFTER the embed. SetFont also collapses the per-script
-- font family. A post-hook on ChatFrame2.SetFont re-applies the QUI font
-- object whenever an outside SetFont lands while the embed is active; the
-- pre-QUI font is snapshotted once so Deactivate can hand back stock values.
-- SetFontObject adopts the font OBJECT's justification too — the QUI font
-- family carries no explicit justifyH, so applying it re-centers the SMF text
-- (display_layer re-asserts SetJustifyH("LEFT") on its own SMF for the same
-- reason). Re-assert ChatFrame2's pre-QUI justification after every apply.
local function ReassertJustify(cf)
    if cf.SetJustifyH then
        pcall(cf.SetJustifyH, cf, stockJustifyH or "LEFT")
    end
end

function CombatLogTab.RefreshFont()
    if not activeWindow then return end
    local cf = _G.ChatFrame2
    local fo = I.chatFontObject or _G.QUI_CustomChatFontObject
    if not (cf and fo and cf.SetFontObject) then return end
    if not stockFont and cf.GetFont then
        local file, height, flags = cf:GetFont()
        -- GetFont can hand back garbage heights; only keep a sane snapshot.
        if file and type(height) == "number" and height > 0 then
            stockFont = { file = file, height = height, flags = flags or "" }
        end
    end
    if not stockJustifyH and cf.GetJustifyH then
        local j = cf:GetJustifyH()
        if type(j) == "string" and j ~= "" then stockJustifyH = j end
    end
    pcall(cf.SetFontObject, cf, fo)
    ReassertJustify(cf)
    if not fontHookInstalled and _G.hooksecurefunc then
        fontHookInstalled = true
        _G.hooksecurefunc(cf, "SetFont", function(self)
            if not activeWindow then return end
            local cur = I.chatFontObject or _G.QUI_CustomChatFontObject
            -- Re-apply via SetFontObject only: it does not re-enter this
            -- SetFont hook, so there is no recursion.
            if cur and self.SetFontObject then
                pcall(self.SetFontObject, self, cur)
                ReassertJustify(self)
            end
        end)
    end
end

-- Strip Blizzard chrome so the frame blends into the QUI window.
local function StripChrome(cf)
    local park = HiddenAnchor()
    if not park then return end
    local name = cf.GetName and cf:GetName()
    local bg = cf.Background or (name and _G[name .. "Background"])
    if bg and bg.SetParent then pcall(bg.SetParent, bg, park) end
end

-- Reparent + anchor the real combat-log frame into `container`. Protected
-- geometry calls are pcall'd; the combat guard above keeps them out of lockdown.
local function Embed(windowID, container)
    local cf = _G.ChatFrame2
    local qb = _G.CombatLogQuickButtonFrame_Custom
    if not (cf and qb) then return end
    local Display = ns.QUI.Chat.DisplayLayer
    local smf = Display and Display.GetMessageFrame and Display.GetMessageFrame(windowID)

    hostByWindow[windowID] = container
    activeWindow = windowID

    if smf and smf.Hide then smf:Hide() end
    local SB = ns.QUI.Chat.Scrollbar
    if SB and SB.SetShown then SB.SetShown(windowID, false) end

    -- Quick-button bar across the top of the message rect.
    pcall(qb.SetParent, qb, container)
    pcall(qb.ClearAllPoints, qb)
    if smf then
        pcall(qb.SetPoint, qb, "TOPLEFT", smf, "TOPLEFT", 0, 0)
        pcall(qb.SetPoint, qb, "TOPRIGHT", smf, "TOPRIGHT", 0, 0)
    end
    if qb.Show then qb:Show() end

    -- ChatFrame2 fills the rest of the message rect.
    pcall(cf.SetParent, cf, container)
    pcall(cf.ClearAllPoints, cf)
    pcall(cf.SetPoint, cf, "TOPLEFT", qb, "BOTTOMLEFT", 0, -2)
    if smf then
        pcall(cf.SetPoint, cf, "BOTTOMRIGHT", smf, "BOTTOMRIGHT", 0, 0)
    end
    StripChrome(cf)
    CombatLogTab.RefreshFont()
    -- Secure show (header): the Blizzard_CombatLog OnShow wrapper re-applies
    -- the user's combat-log filter; it must not run on QUI's tainted path.
    EnsureShownSecure(cf)
end

function CombatLogTab.Activate(windowID)
    windowID = tonumber(windowID) or 1
    local Display = ns.QUI.Chat.DisplayLayer
    local container = Display and Display.GetContainer and Display.GetContainer(windowID)
    if not container then return false end

    local function install()
        -- Geometry on the protected, Edit-Mode-managed ChatFrame2 must not run
        -- in combat: record intent (so GetHostParent resolves) and finish the
        -- embed once lockdown ends.
        if _G.InCombatLockdown and _G.InCombatLockdown() then
            hostByWindow[windowID] = container
            activeWindow = windowID
            if not combatWaiter and _G.CreateFrame then
                combatWaiter = _G.CreateFrame("Frame")
            end
            if combatWaiter then
                combatWaiter:SetScript("OnEvent", function(self)
                    self:UnregisterAllEvents()
                    self:SetScript("OnEvent", nil)
                    if activeWindow == windowID then Embed(windowID, container) end
                end)
                combatWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
            end
            return
        end
        Embed(windowID, container)
    end

    if not CombatLogTab.EnsureLoaded(install) then
        -- Not loaded yet: record intent so GetHostParent resolves; install fires
        -- when the combat-log addon/frame materializes.
        hostByWindow[windowID] = container
        activeWindow = windowID
    end
    return true
end

function CombatLogTab.Deactivate(windowID)
    windowID = tonumber(windowID) or 1
    if activeWindow == windowID then activeWindow = nil end
    hostByWindow[windowID] = nil

    local park = HiddenAnchor()
    local cf = _G.ChatFrame2
    local qb = _G.CombatLogQuickButtonFrame_Custom
    -- ChatFrame2 parks on the SHOWN clipped anchor (header: a hidden park
    -- would fire the Blizzard_CombatLog OnHide wrapper on our tainted path).
    -- blizzard_suppress enforces the same parent (GetHostParent == nil), but
    -- park it ourselves too so the move happens even if suppression is off.
    local cfPark = CombatLogTab.GetParkParent()
    if cf and cfPark and cf.SetParent then pcall(cf.SetParent, cf, cfPark) end
    if qb and park and qb.SetParent then pcall(qb.SetParent, qb, park) end
    -- Hand the stock font back via explicit SetFont values (NEVER a captured
    -- font object — editbox_setfontobject-self-cycle lesson). activeWindow is
    -- already nil here, so the durability hook lets this through.
    if stockFont and cf and cf.SetFont then
        pcall(cf.SetFont, cf, stockFont.file, stockFont.height, stockFont.flags)
    end
    -- Hand back the pre-QUI justification too (the QUI font object pulled the
    -- text to its own justify; stock combat log is LEFT).
    if cf and cf.SetJustifyH then
        pcall(cf.SetJustifyH, cf, stockJustifyH or "LEFT")
    end

    local Display = ns.QUI.Chat.DisplayLayer
    local smf = Display and Display.GetMessageFrame and Display.GetMessageFrame(windowID)
    if smf and smf.Show then smf:Show() end
    local SB = ns.QUI.Chat.Scrollbar
    if SB and SB.SetShown then SB.SetShown(windowID, true) end
    local TabManager = ns.QUI.Chat.TabManager
    if TabManager and TabManager.ReapplyAll then TabManager.ReapplyAll() end
end
