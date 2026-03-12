--[[
    QUI Click-Casting Framework
    Native click-casting that works independently of Clique.
    Supports group frames (party/raid) and individual unit frames
    (player, target, focus, pet, boss).
    Features: modifier combos, smart resurrection, per-spec profiles,
    Clique coexistence, binding tooltip on frame hover,
    keyboard key bindings for pseudo-mouseover casting.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_GFCC = {}
ns.QUI_GroupFrameClickCast = QUI_GFCC

-- Track registered frames
local registeredFrames = setmetatable({}, { __mode = "k" })
local hookedFrames = setmetatable({}, { __mode = "k" }) -- Tracks frames with OnEnter/OnLeave hooks (permanent)
local secureWrappedFrames = setmetatable({}, { __mode = "k" }) -- Tracks frames with secure WrapScript (permanent)
local activeBindings = {} -- Resolved mouse bindings for current spec
local keyboardBindings = {} -- Resolved keyboard bindings for current spec
local isEnabled = false

---------------------------------------------------------------------------
-- PING MACROS: /ping [@mouseover] <type> for each ping action type
---------------------------------------------------------------------------
local PING_MACROS = {
    ping         = "/ping [@mouseover]",
    ping_assist  = "/ping [@mouseover] assist",
    ping_attack  = "/ping [@mouseover] attack",
    ping_warning = "/ping [@mouseover] warning",
    ping_onmyway = "/ping [@mouseover] onmyway",
}

local PING_LABELS = {
    ping         = "Ping",
    ping_assist  = "Ping: Assist",
    ping_attack  = "Ping: Attack",
    ping_warning = "Ping: Warning",
    ping_onmyway = "Ping: On My Way",
}

---------------------------------------------------------------------------
-- MODIFIER / BUTTON HELPERS
---------------------------------------------------------------------------
local BUTTON_NAMES = {
    LeftButton = "Left Click",
    RightButton = "Right Click",
    MiddleButton = "Middle Click",
    Button4 = "Button 4",
    Button5 = "Button 5",
    ScrollUp = "Scroll Up",
    ScrollDown = "Scroll Down",
}

-- Scroll wheel buttons use override bindings (like keyboard keys),
-- not the SetAttribute("typeN") system used by regular mouse buttons.
local SCROLL_WHEEL_KEYS = {
    ScrollUp = "MOUSEWHEELUP",
    ScrollDown = "MOUSEWHEELDOWN",
}

-- Friendly display names for binding keys shown in tooltips
local KEY_DISPLAY_NAMES = {
    MOUSEWHEELUP = "Scroll Up",
    MOUSEWHEELDOWN = "Scroll Down",
}

local MODIFIER_LABELS = {
    [""]      = "",
    ["shift"] = "Shift+",
    ["ctrl"]  = "Ctrl+",
    ["alt"]   = "Alt+",
    ["shift-ctrl"]  = "Shift+Ctrl+",
    ["shift-alt"]   = "Shift+Alt+",
    ["ctrl-alt"]    = "Ctrl+Alt+",
    ["shift-ctrl-alt"] = "Shift+Ctrl+Alt+",
}

---------------------------------------------------------------------------
-- MODIFIER HELPERS
---------------------------------------------------------------------------
-- Parse modifier string into canonical alphabetical order (alt-ctrl-shift-)
-- for WoW's SecureButton attribute system.
local function ModifiersToAttributePrefix(mods)
    if not mods or mods == "" then return "" end
    local lower = mods:lower()
    local hasAlt   = lower:find("alt") ~= nil
    local hasCtrl  = lower:find("ctrl") ~= nil
    local hasShift = lower:find("shift") ~= nil
    local result = ""
    if hasAlt   then result = result .. "alt-" end
    if hasCtrl  then result = result .. "ctrl-" end
    if hasShift then result = result .. "shift-" end
    return result
end

-- Convert our modifier format to WoW binding prefix ("SHIFT-", "CTRL-ALT-")
-- Binding keys use UPPERCASE, same alphabetical order.
local function ModifiersToBindingPrefix(mods)
    if not mods or mods == "" then return "" end
    local lower = mods:lower()
    local hasAlt   = lower:find("alt") ~= nil
    local hasCtrl  = lower:find("ctrl") ~= nil
    local hasShift = lower:find("shift") ~= nil
    local result = ""
    if hasAlt   then result = result .. "ALT-" end
    if hasCtrl  then result = result .. "CTRL-" end
    if hasShift then result = result .. "SHIFT-" end
    return result
end

---------------------------------------------------------------------------
-- RESURRECTION SPELLS: Per-class res spell IDs
---------------------------------------------------------------------------
local RES_SPELLS = {
    PRIEST      = 2006,   -- Resurrection
    PALADIN     = 7328,   -- Redemption
    SHAMAN      = 2008,   -- Ancestral Spirit
    DRUID       = 50769,  -- Revive
    MONK        = 115178, -- Resuscitate
    EVOKER      = 361227, -- Return
    WARLOCK     = 20707,  -- Soulstone
    DEATHKNIGHT = 61999,  -- Raise Ally
}

local function GetResurrectionSpellName()
    local _, classToken = UnitClass("player")
    local spellID = RES_SPELLS[classToken]
    if spellID then
        local name = C_Spell.GetSpellName(spellID)
        return name
    end
    return nil
end

---------------------------------------------------------------------------
-- SECURE HANDLER: Keyboard binding infrastructure
---------------------------------------------------------------------------
-- The header (SecureHandlerBaseTemplate) owns all override bindings.
-- WrapScript hooks on each frame use `owner` (the header) to call
-- SetBindingClick/ClearBindings — the frame itself does NOT need
-- SecureHandlerBaseTemplate methods.
--
-- On hover: header reads key count + key/vbtn attributes, calls
-- SetBindingClick to route each key to the hovered frame's virtual button.
-- On leave: header clears all override bindings.
---------------------------------------------------------------------------
local bindingHeader

local function GetBindingHeader()
    if not bindingHeader then
        bindingHeader = CreateFrame("Frame", "QUI_ClickCastHeader", UIParent, "SecureHandlerBaseTemplate")
    end
    return bindingHeader
end

-- WrapScript pre-body for OnEnter.
-- `self` = the hovered frame, `owner` = the header (SecureHandlerBaseTemplate).
-- The header owns and manages all override bindings.
local ENTER_SNIPPET = [[
    owner:ClearBindings()
    local count = owner:GetAttribute("clickcast-keycount") or 0
    if count == 0 then return end

    local frameName = self:GetName()
    if not frameName then return end

    for i = 1, count do
        local key = owner:GetAttribute("clickcast-key" .. i)
        local vBtn = owner:GetAttribute("clickcast-vbtn" .. i)
        if key and vBtn then
            owner:SetBindingClick(true, key, frameName, vBtn)
        end
    end
]]

-- WrapScript pre-body for OnLeave.
local LEAVE_SNIPPET = [[
    owner:ClearBindings()
]]

-- WrapScript pre-body for OnHide — clears override bindings when the frame
-- hides while still hovered (e.g. group member leaves, unit watch hides frame).
-- Without this, keyboard override bindings linger on a hidden frame.
local HIDE_SNIPPET = [[
    owner:ClearBindings()
]]

-- Wrap a frame's OnEnter/OnLeave/OnHide with secure handler snippets.
-- Only called once per frame (tracked by secureWrappedFrames).
local function WrapFrameSecureHandlers(frame)
    if secureWrappedFrames[frame] then return end
    if InCombatLockdown() then return end

    local header = GetBindingHeader()
    SecureHandlerWrapScript(frame, "OnEnter", header, ENTER_SNIPPET)
    SecureHandlerWrapScript(frame, "OnLeave", header, LEAVE_SNIPPET)
    SecureHandlerWrapScript(frame, "OnHide", header, HIDE_SNIPPET)

    secureWrappedFrames[frame] = true
end

-- Build virtual button name from a binding's modifiers + key.
local function GetVirtualButtonName(binding)
    return "key" .. (binding.modifiers or ""):gsub("%-", "") .. binding.key:lower()
end

-- Update the header's key-mapping attributes (shared across all frames).
local function UpdateHeaderKeyAttributes()
    local header = GetBindingHeader()
    if InCombatLockdown() then return end

    -- Clear old attributes
    local oldCount = header:GetAttribute("clickcast-keycount") or 0
    for i = 1, oldCount do
        header:SetAttribute("clickcast-key" .. i, nil)
        header:SetAttribute("clickcast-vbtn" .. i, nil)
    end

    -- Set new attributes
    header:SetAttribute("clickcast-keycount", #keyboardBindings)

    for i, binding in ipairs(keyboardBindings) do
        local modPrefix = ModifiersToBindingPrefix(binding.modifiers)
        local fullKey = modPrefix .. binding.key:upper()
        local vBtn = GetVirtualButtonName(binding)
        header:SetAttribute("clickcast-key" .. i, fullKey)
        header:SetAttribute("clickcast-vbtn" .. i, vBtn)
    end
end

-- Set virtual-button action attributes on a frame for keyboard bindings.
local function SetFrameKeyAttributes(frame)
    if InCombatLockdown() then return end
    for _, binding in ipairs(keyboardBindings) do
        local vBtn = GetVirtualButtonName(binding)
        local actionType = binding.actionType or "spell"

        if actionType == "spell" then
            frame:SetAttribute("type-" .. vBtn, "macro")
            frame:SetAttribute("macrotext-" .. vBtn,
                "/cast [@mouseover,help,nodead] " .. binding.spell
                .. "; [@mouseover,harm,nodead] " .. binding.spell
                .. "; [@mouseover] " .. binding.spell)
        elseif actionType == "macro" then
            frame:SetAttribute("type-" .. vBtn, "macro")
            frame:SetAttribute("macrotext-" .. vBtn, binding.macro)
        elseif actionType == "target" then
            frame:SetAttribute("type-" .. vBtn, "target")
        elseif actionType == "focus" then
            frame:SetAttribute("type-" .. vBtn, "focus")
        elseif actionType == "assist" then
            frame:SetAttribute("type-" .. vBtn, "assist")
        elseif actionType == "menu" then
            frame:SetAttribute("type-" .. vBtn, "togglemenu")
        elseif actionType:match("^ping") then
            frame:SetAttribute("type-" .. vBtn, "macro")
            frame:SetAttribute("macrotext-" .. vBtn, PING_MACROS[actionType] or "/ping [@mouseover]")
        end
    end
end

-- Clear virtual-button attributes from a frame.
local function ClearFrameKeyAttributes(frame)
    if InCombatLockdown() then return end
    for _, binding in ipairs(keyboardBindings) do
        local vBtn = GetVirtualButtonName(binding)
        frame:SetAttribute("type-" .. vBtn, nil)
        frame:SetAttribute("macrotext-" .. vBtn, nil)
    end
end

---------------------------------------------------------------------------
-- BINDING RESOLUTION: Build active binding set for current spec
---------------------------------------------------------------------------
local function ResolveBindings()
    wipe(activeBindings)
    wipe(keyboardBindings)

    local db = GetDB()
    if not db or not db.clickCast or not db.clickCast.enabled then return end

    local bindings = db.clickCast.bindings
    if not bindings then return end

    -- If per-spec, filter to current spec
    if db.clickCast.perSpec then
        local specID = GetSpecializationInfo(GetSpecialization() or 1)
        if specID then
            -- Look for spec-specific bindings
            local specBindings = db.clickCast.specBindings and db.clickCast.specBindings[specID]
            if specBindings then
                bindings = specBindings
            end
        end
    end

    for _, binding in ipairs(bindings) do
        -- A binding needs a trigger (key or button) and either a spell, macro,
        -- or a non-spell action type (target/focus/assist/menu/ping).
        local actionType = binding.actionType or "spell"
        local hasAction = binding.spell or binding.macro or actionType ~= "spell"

        if binding.key and hasAction then
            -- Keyboard binding
            table.insert(keyboardBindings, {
                key = binding.key,
                modifiers = binding.modifiers or "",
                spell = binding.spell,
                macro = binding.macro,
                actionType = actionType,
            })
        elseif binding.button and hasAction then
            local scrollKey = SCROLL_WHEEL_KEYS[binding.button]
            if scrollKey then
                -- Scroll wheel uses override bindings (same path as keyboard keys)
                table.insert(keyboardBindings, {
                    key = scrollKey,
                    modifiers = binding.modifiers or "",
                    spell = binding.spell,
                    macro = binding.macro,
                    actionType = actionType,
                })
            else
                -- Mouse binding
                table.insert(activeBindings, {
                    button = binding.button,
                    modifiers = binding.modifiers or "",
                    spell = binding.spell,
                    macro = binding.macro,
                    actionType = actionType,
                })
            end
        end
    end
end

---------------------------------------------------------------------------
-- BUTTON NUMBER HELPER
---------------------------------------------------------------------------
local BUTTON_NUMBERS = {
    LeftButton = "1",
    RightButton = "2",
    MiddleButton = "3",
    Button4 = "4",
    Button5 = "5",
}

---------------------------------------------------------------------------
-- FRAME SETUP: Apply click-cast attributes to a frame
---------------------------------------------------------------------------
local function SetupFrameClickCast(frame)
    if not frame or registeredFrames[frame] then return end
    if InCombatLockdown() then return end

    local db = GetDB()
    if not db or not db.clickCast or not db.clickCast.enabled then return end

    -- Set secure attributes for each mouse binding
    for _, binding in ipairs(activeBindings) do
        local prefix = ModifiersToAttributePrefix(binding.modifiers)

        local btnNum = BUTTON_NUMBERS[binding.button] or "1"
        local actionType = binding.actionType or "spell"

        if actionType == "spell" then
            -- Use macro with @mouseover conditional for reliable targeting
            frame:SetAttribute(prefix .. "type" .. btnNum, "macro")
            frame:SetAttribute(prefix .. "macrotext" .. btnNum,
                "/cast [@mouseover,help,nodead] " .. binding.spell
                .. "; [@mouseover,harm,nodead] " .. binding.spell
                .. "; [@mouseover] " .. binding.spell)
        elseif actionType == "macro" then
            frame:SetAttribute(prefix .. "type" .. btnNum, "macro")
            frame:SetAttribute(prefix .. "macrotext" .. btnNum, binding.macro)
        elseif actionType == "target" then
            frame:SetAttribute(prefix .. "type" .. btnNum, "target")
        elseif actionType == "focus" then
            frame:SetAttribute(prefix .. "type" .. btnNum, "focus")
        elseif actionType == "assist" then
            frame:SetAttribute(prefix .. "type" .. btnNum, "assist")
        elseif actionType == "menu" then
            frame:SetAttribute(prefix .. "type" .. btnNum, "togglemenu")
        elseif actionType:match("^ping") then
            frame:SetAttribute(prefix .. "type" .. btnNum, "macro")
            frame:SetAttribute(prefix .. "macrotext" .. btnNum, PING_MACROS[actionType] or "/ping [@mouseover]")
        end
    end

    -- Set up keyboard bindings (includes scroll wheel):
    -- wrap with secure handlers + set virtual button attributes
    if #keyboardBindings > 0 then
        WrapFrameSecureHandlers(frame)
        SetFrameKeyAttributes(frame)
        -- Enable mouse wheel on the frame so scroll bindings generate events
        frame:EnableMouseWheel(true)
    end

    registeredFrames[frame] = true

    -- Only add script hooks once per frame — HookScript is additive and
    -- cannot be removed, so re-hooking on every RefreshBindings would
    -- duplicate tooltip lines and resurrection swaps.
    if not hookedFrames[frame] then
        hookedFrames[frame] = true

        -- Smart resurrection: hook to swap spell when target is dead.
        -- Always install the hook — check db.clickCast.smartRes at runtime
        -- so toggling the setting takes effect without reload.
        local resSpell = GetResurrectionSpellName()
        if resSpell then
            local resMacro = "/cast [@mouseover] " .. resSpell
            frame:HookScript("OnEnter", function(self)
                if not isEnabled then return end
                local ccdb = GetDB()
                if not ccdb or not ccdb.clickCast or not ccdb.clickCast.smartRes then return end
                if InCombatLockdown() then return end
                local unit = self:GetAttribute("unit")
                if unit and UnitIsDeadOrGhost(unit) and (UnitIsConnected(unit) or not UnitIsPlayer(unit)) then
                    -- Swap left click to res
                    self:SetAttribute("type1", "macro")
                    self:SetAttribute("macrotext1", resMacro)
                end
            end)
            frame:HookScript("OnLeave", function(self)
                if not isEnabled then return end
                local ccdb = GetDB()
                if not ccdb or not ccdb.clickCast or not ccdb.clickCast.smartRes then return end
                if InCombatLockdown() then return end
                -- Restore normal binding
                local normalBinding = nil
                for _, b in ipairs(activeBindings) do
                    if b.button == "LeftButton" and (b.modifiers or "") == "" then
                        normalBinding = b
                        break
                    end
                end
                if normalBinding then
                    local actionType = normalBinding.actionType or "spell"
                    if actionType == "spell" then
                        self:SetAttribute("type1", "macro")
                        self:SetAttribute("macrotext1",
                            "/cast [@mouseover,help,nodead] " .. normalBinding.spell
                            .. "; [@mouseover,harm,nodead] " .. normalBinding.spell
                            .. "; [@mouseover] " .. normalBinding.spell)
                    elseif actionType == "macro" then
                        self:SetAttribute("type1", "macro")
                        self:SetAttribute("macrotext1", normalBinding.macro)
                    elseif actionType:match("^ping") then
                        self:SetAttribute("type1", "macro")
                        self:SetAttribute("macrotext1", PING_MACROS[actionType] or "/ping [@mouseover]")
                    else
                        self:SetAttribute("type1", actionType)
                    end
                else
                    -- Default: target
                    self:SetAttribute("type1", "target")
                end
            end)
        end

        -- Tooltip showing available bindings (mouse + keyboard).
        -- Always install the hook — check db.clickCast.showTooltip at runtime
        -- so toggling the setting takes effect without reload.
        frame:HookScript("OnEnter", function(self)
            if not isEnabled then return end
            local ccdb = GetDB()
            if not ccdb or not ccdb.clickCast or not ccdb.clickCast.showTooltip then return end
            if #activeBindings == 0 and #keyboardBindings == 0 then return end

            -- Check if we should show tooltip (avoid conflict with unit tooltip)
            local existingOwner = GameTooltip:GetOwner()
            if existingOwner == self then
                -- Append to existing unit tooltip
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Click-Cast Bindings:", 0.2, 0.83, 0.6)
                for _, binding in ipairs(activeBindings) do
                    local modLabel = MODIFIER_LABELS[binding.modifiers or ""] or ""
                    local buttonLabel = BUTTON_NAMES[binding.button] or binding.button
                    local at = binding.actionType or "spell"
                    local spellLabel = PING_LABELS[at] or binding.spell or at or "?"
                    GameTooltip:AddDoubleLine(
                        modLabel .. buttonLabel,
                        spellLabel,
                        0.8, 0.8, 0.8, 1, 1, 1
                    )
                end
                for _, binding in ipairs(keyboardBindings) do
                    local modLabel = MODIFIER_LABELS[binding.modifiers or ""] or ""
                    local keyLabel = KEY_DISPLAY_NAMES[binding.key] or binding.key or "?"
                    local at = binding.actionType or "spell"
                    local spellLabel = PING_LABELS[at] or binding.spell or at or "?"
                    GameTooltip:AddDoubleLine(
                        modLabel .. keyLabel,
                        spellLabel,
                        0.8, 0.8, 0.8, 1, 1, 1
                    )
                end
                GameTooltip:Show()
            end
        end)
    end
end

---------------------------------------------------------------------------
-- CLEAR: Remove click-cast attributes from a frame
---------------------------------------------------------------------------
local function ClearFrameClickCast(frame)
    if not frame or not registeredFrames[frame] then return end
    if InCombatLockdown() then return end

    -- Clear all mouse click-cast attributes for every button/modifier combo
    -- Prefixes in canonical alphabetical order (alt-ctrl-shift) to match WoW's secure template
    local modPrefixes = { "", "alt-", "ctrl-", "shift-", "alt-ctrl-", "alt-shift-", "ctrl-shift-", "alt-ctrl-shift-" }
    for _, prefix in ipairs(modPrefixes) do
        for _, btnNum in pairs(BUTTON_NUMBERS) do
            frame:SetAttribute(prefix .. "type" .. btnNum, nil)
            frame:SetAttribute(prefix .. "macrotext" .. btnNum, nil)
        end
    end

    -- Clear keyboard virtual-button attributes
    ClearFrameKeyAttributes(frame)

    -- Restore default target/menu behavior
    frame:SetAttribute("type1", "target")
    frame:SetAttribute("type2", "togglemenu")

    registeredFrames[frame] = nil
end

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------
function QUI_GFCC:Initialize()
    local db = GetDB()
    if not db or not db.clickCast or not db.clickCast.enabled then return end

    -- Check Clique coexistence
    if IsAddOnLoaded and IsAddOnLoaded("Clique") then
        -- Clique is loaded — disable QUI click-cast by default
        -- unless user explicitly enabled it
        if not db.clickCast.forceOverClique then
            return
        end
    end

    ResolveBindings()
    UpdateHeaderKeyAttributes()
    isEnabled = true
end

function QUI_GFCC:RegisterFrame(frame)
    if not isEnabled then return end
    SetupFrameClickCast(frame)
end

function QUI_GFCC:UnregisterFrame(frame)
    ClearFrameClickCast(frame)
end

function QUI_GFCC:RegisterAllFrames()
    if not isEnabled then return end
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.headers then return end

    -- Walk header children directly rather than relying on a cached list.
    -- This always gets current children regardless of creation timing.
    for _, headerKey in ipairs({"party", "raid", "self"}) do
        local header = GF.headers[headerKey]
        if header then
            for i = 1, 40 do
                local child = header:GetAttribute("child" .. i)
                if not child then break end
                SetupFrameClickCast(child)
            end
        end
    end
end

function QUI_GFCC:RegisterUnitFrames()
    if not isEnabled then return end
    local db = GetDB()
    if not db or not db.clickCast then return end

    local ufSettings = db.clickCast.unitFrames
    if not ufSettings then return end

    local UF = ns.QUI_UnitFrames
    if not UF or not UF.frames then return end

    for unitKey, frame in pairs(UF.frames) do
        -- Boss frames: boss1-boss5 all use the "boss" setting
        local settingKey = unitKey:match("^boss%d$") and "boss" or unitKey
        if ufSettings[settingKey] then
            SetupFrameClickCast(frame)
            -- Also register portrait if it exists
            if frame.portrait and frame.portrait.GetAttribute then
                SetupFrameClickCast(frame.portrait)
            end
        end
    end
end

function QUI_GFCC:RefreshBindings()
    if InCombatLockdown() then return end

    local db = GetDB()
    local enabled = db and db.clickCast and db.clickCast.enabled

    -- Clear all existing bindings
    for frame in pairs(registeredFrames) do
        ClearFrameClickCast(frame)
    end
    wipe(registeredFrames)

    if not enabled then
        -- Disable: clear bindings and mark as disabled
        wipe(activeBindings)
        wipe(keyboardBindings)
        UpdateHeaderKeyAttributes()
        isEnabled = false
        return
    end

    -- Enable/refresh: resolve bindings and re-apply
    isEnabled = true
    ResolveBindings()
    UpdateHeaderKeyAttributes()
    self:RegisterAllFrames()
    self:RegisterUnitFrames()
end

function QUI_GFCC:IsEnabled()
    return isEnabled
end

function QUI_GFCC:GetActiveBindings()
    return activeBindings
end

function QUI_GFCC:GetKeyboardBindings()
    return keyboardBindings
end

function QUI_GFCC:GetEditableBindings()
    local db = GetDB()
    if not db or not db.clickCast then return {} end
    local cc = db.clickCast

    if cc.perSpec then
        local specID = GetSpecializationInfo(GetSpecialization() or 1)
        if specID then
            if not cc.specBindings then cc.specBindings = {} end
            if not cc.specBindings[specID] then cc.specBindings[specID] = {} end
            return cc.specBindings[specID]
        end
    end

    if not cc.bindings then cc.bindings = {} end
    return cc.bindings
end

function QUI_GFCC:AddBinding(binding)
    if not binding then return false, "No binding specified" end
    if not binding.button and not binding.key then return false, "No button or key specified" end

    local bindings = self:GetEditableBindings()
    local mod = binding.modifiers or ""

    -- Duplicate detection: same trigger+modifier combo
    for _, existing in ipairs(bindings) do
        if (existing.modifiers or "") == mod then
            if binding.key and existing.key and existing.key == binding.key then
                return false, "A binding for " .. (MODIFIER_LABELS[mod] or "") .. binding.key .. " already exists"
            elseif binding.button and existing.button and existing.button == binding.button then
                return false, "A binding for " .. (MODIFIER_LABELS[mod] or "") .. (BUTTON_NAMES[binding.button] or binding.button) .. " already exists"
            end
        end
    end

    table.insert(bindings, binding)

    if not InCombatLockdown() then
        self:RefreshBindings()
    else
        self.pendingRefresh = true
    end
    return true
end

function QUI_GFCC:RemoveBinding(index)
    local bindings = self:GetEditableBindings()
    if index < 1 or index > #bindings then return false end

    table.remove(bindings, index)

    if not InCombatLockdown() then
        self:RefreshBindings()
    else
        self.pendingRefresh = true
    end
    return true
end

function QUI_GFCC:GetButtonNames()
    return BUTTON_NAMES
end

function QUI_GFCC:GetModifierLabels()
    return MODIFIER_LABELS
end

-- Global ping keybinds use Blizzard's native binding actions directly
-- (TOGGLEPINGLISTENER, PINGATTACK, PINGWARNING, PINGONMYWAY, PINGASSIST).
-- No SecureActionButtons needed — the UI binds keys to these native actions.

---------------------------------------------------------------------------
-- EVENTS: Spec change and combat end
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Migrate old QUI ping bindings (CLICK format and QUI_PING_* action
        -- names) to Blizzard's native ping actions.
        local OLD_TO_NATIVE = {
            ["CLICK QUI_PingButton_Contextual:LeftButton"] = "TOGGLEPINGLISTENER",
            ["CLICK QUI_PingButton_Assist:LeftButton"]     = "PINGASSIST",
            ["CLICK QUI_PingButton_Attack:LeftButton"]     = "PINGATTACK",
            ["CLICK QUI_PingButton_Warning:LeftButton"]    = "PINGWARNING",
            ["CLICK QUI_PingButton_OnMyWay:LeftButton"]    = "PINGONMYWAY",
            ["QUI_PING"]         = "TOGGLEPINGLISTENER",
            ["QUI_PING_ASSIST"]  = "PINGASSIST",
            ["QUI_PING_ATTACK"]  = "PINGATTACK",
            ["QUI_PING_WARNING"] = "PINGWARNING",
            ["QUI_PING_ONMYWAY"] = "PINGONMYWAY",
        }
        local didMigrate = false
        for oldBinding, nativeAction in pairs(OLD_TO_NATIVE) do
            local key1, key2 = GetBindingKey(oldBinding)
            if key1 then SetBinding(key1, nativeAction); didMigrate = true end
            if key2 then SetBinding(key2, nativeAction); didMigrate = true end
        end
        if didMigrate then SaveBindings(GetCurrentBindingSet()) end

        -- After /reload or zone transition, re-register all frames.
        -- Spec data and group composition may not be fully available during
        -- ADDON_LOADED, so this catch-up ensures bindings are applied.
        if not isEnabled then
            -- Try to initialize if not done yet (covers case where
            -- ADDON_LOADED ran before DB was ready)
            QUI_GFCC:Initialize()
        end
        if isEnabled and not InCombatLockdown() then
            C_Timer.After(1.0, function()
                if not InCombatLockdown() then
                    QUI_GFCC:RefreshBindings()
                end
            end)
        end
        return
    end

    if not isEnabled then return end

    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Re-resolve bindings for new spec
        C_Timer.After(0.5, function()
            if not InCombatLockdown() then
                QUI_GFCC:RefreshBindings()
            end
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Apply any deferred binding changes
        if QUI_GFCC.pendingRefresh then
            QUI_GFCC.pendingRefresh = false
            QUI_GFCC:RefreshBindings()
        end
    end
end)
