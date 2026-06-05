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

-- Click-cast settings live on db.char (per-character), not on the shared
-- profile. Bindings reference class-specific spells, and a single AceDB
-- profile is shared across every character on the account by default —
-- storing them on the profile leaked one class's bindings onto another
-- (e.g. Druid bindings appearing on a Paladin alt). GetDB returns the
-- character-scoped wrapper so existing `db.clickCast` access shape is
-- preserved.
local function GetDB()
    return _G.QUI and _G.QUI.db and _G.QUI.db.char or nil
end

-- Forward-declared so Initialize (defined before the migration block)
-- can call it. Body is assigned later in the file.
local MigrateProfileClickCastToChar

-- Upvalue hot-path globals
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local table_insert = table.insert
local table_remove = table.remove

---------------------------------------------------------------------------
-- MODULE TABLE
---------------------------------------------------------------------------
local QUI_GFCC = {}
ns.QUI_GroupFrameClickCast = QUI_GFCC

-- Track registered frames
local registeredFrames = Helpers.CreateStateTable()
local hookedFrames = Helpers.CreateStateTable() -- Tracks frames with OnEnter/OnLeave hooks (permanent)
local secureWrappedFrames = Helpers.CreateStateTable() -- Tracks frames with secure WrapScript (permanent)
local activeBindings = {} -- Resolved mouse bindings for current spec
local keyboardBindings = {} -- Resolved keyboard bindings for current spec
local smartResSwapped = setmetatable({}, { __mode = "k" }) -- Per-frame: true when OnEnter swapped to res
local isEnabled = false
local currentKeyboardFrame = nil
-- Coalesces deferred "recovery" RefreshBindings (the on-hover trigger and the
-- data-ready event handlers) so a burst schedules only one. Declared up here
-- because the OnEnter hook installed in SetupFrameClickCast (below) closes over
-- both this flag and IsUnresolvedButConfigured, which is defined later.
local dataReadyRefreshScheduled = false
local IsUnresolvedButConfigured  -- forward-declared; body assigned after HasConfiguredBindings

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
-- The header owns the override bindings; `currentHoverFrame` (a variable in the
-- header's shared managed environment, like a clickcast header's mouseover
-- tracker) records which frame is the active hover so OnLeave/OnHide clear ONLY
-- for that frame. Without it, ANY frame's leave/hide would clear the whole
-- header, wiping the binding the currently-hovered frame just set — frame layout
-- churn on a cold login fires spurious leaves/hides and the key falls back to a
-- lower binding (e.g. an action-bar keybind on the same key) until /reload.
local ENTER_SNIPPET = [[
    owner:ClearBindings()
    local count = owner:GetAttribute("clickcast-keycount") or 0
    if count == 0 then return end

    local frameName = self:GetName()
    if not frameName then return end

    -- Claim the hover context (owner:ClearBindings above hands off the previous
    -- frame); OnLeave/OnHide only clear while this stays the active frame.
    currentHoverFrame = self

    for i = 1, count do
        local key = owner:GetAttribute("clickcast-key" .. i)
        local vBtn = owner:GetAttribute("clickcast-vbtn" .. i)
        if key and vBtn then
            owner:SetBindingClick(true, key, frameName, vBtn)
        end
    end
]]

-- WrapScript pre-body for OnLeave. Guard on currentHoverFrame so a stale leave
-- from a frame we've already moved off of can't clear the active binding.
local LEAVE_SNIPPET = [[
    if currentHoverFrame == self then
        owner:ClearBindings()
        currentHoverFrame = nil
    end
]]

-- WrapScript pre-body for OnHide — clears override bindings when the frame
-- hides while still hovered (e.g. group member leaves, unit watch hides frame).
-- Guarded like OnLeave so hiding a non-hovered frame (common during cold-login
-- group layout) doesn't wipe the active frame's bindings.
local HIDE_SNIPPET = [[
    if currentHoverFrame == self then
        owner:ClearBindings()
        currentHoverFrame = nil
    end
]]

local CLEAR_HEADER_BINDINGS_SNIPPET = [[
    self:ClearBindings()
    currentHoverFrame = nil
]]

local REFRESH_HEADER_BINDINGS_SNIPPET = [[
    self:ClearBindings()

    local frame = self:GetFrameRef("clickcast-hover-frame")
    if not frame then return end

    local frameName = frame:GetName()
    if not frameName then return end

    -- Keep the hover tracker in sync so this frame's OnLeave clears correctly.
    currentHoverFrame = frame

    local count = self:GetAttribute("clickcast-keycount") or 0
    if count == 0 then return end

    for i = 1, count do
        local key = self:GetAttribute("clickcast-key" .. i)
        local vBtn = self:GetAttribute("clickcast-vbtn" .. i)
        if key and vBtn then
            self:SetBindingClick(true, key, frameName, vBtn)
        end
    end
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

local function ClearHeaderOverrideBindings()
    if InCombatLockdown() then return end
    if bindingHeader and bindingHeader.Execute then
        bindingHeader:Execute(CLEAR_HEADER_BINDINGS_SNIPPET)
    end
end

local function RefreshHeaderOverrideBindings()
    if InCombatLockdown() then return end

    local header = bindingHeader
    if not header or not header.Execute then return end

    local frame = currentKeyboardFrame
    if frame and registeredFrames[frame] and header.SetFrameRef then
        header:SetFrameRef("clickcast-hover-frame", frame)
        header:Execute(REFRESH_HEADER_BINDINGS_SNIPPET)
    else
        currentKeyboardFrame = nil
        header:Execute(CLEAR_HEADER_BINDINGS_SNIPPET)
    end
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
-- BINDING RESOLUTION: Build active binding set for current spec/loadout
---------------------------------------------------------------------------

-- Resolve the current spell name from a binding's spellID (root spell).
-- If a talent override is active, GetSpellName returns the override name,
-- which is what /cast needs. Falls back to stored spell name string.
local function ResolveSpellName(binding)
    if binding.spellID then
        local name = C_Spell.GetSpellName(binding.spellID)
        if name then return name end
    end
    return binding.spell
end

local function GetCurrentSpecID()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    local specID = GetSpecializationInfo(specIndex)
    if specID and specID ~= 0 then return specID end
    return nil
end

-- Return the stable saved-loadout config ID for the current spec.
-- GetActiveConfigID() returns an ephemeral staging copy that changes each
-- session; GetLastSelectedSavedConfigID() returns the persistent saved ID.
local function GetStableLoadoutID()
    local specID = GetCurrentSpecID()
    if not specID or not C_ClassTalents then return nil, specID end
    local savedID = C_ClassTalents.GetLastSelectedSavedConfigID and C_ClassTalents.GetLastSelectedSavedConfigID(specID)
    if savedID then return savedID, specID end
    local activeID = C_ClassTalents.GetActiveConfigID()
    if activeID and activeID ~= 0 then return activeID, specID end
    return nil, specID
end

-- Look up the correct binding table for the current spec/loadout settings.
local function GetActiveBindingTable()
    local db = GetDB()
    if not db or not db.clickCast then return nil end
    local cc = db.clickCast

    if cc.perSpec then
        local specID = GetCurrentSpecID()
        if not specID then return nil end

        if cc.perLoadout then
            local configID = GetStableLoadoutID()
            if configID and cc.loadoutBindings and cc.loadoutBindings[specID] then
                return cc.loadoutBindings[specID][configID]
            end
            return nil
        end

        local specBindings = cc.specBindings and cc.specBindings[specID]
        if specBindings then return specBindings end
    end

    return cc.bindings
end

local function ResolveBindings()
    wipe(activeBindings)
    wipe(keyboardBindings)

    local db = GetDB()
    if not db or not db.clickCast or not db.clickCast.enabled then return end

    local bindings = GetActiveBindingTable()
    if not bindings then return end

    for _, binding in ipairs(bindings) do
        -- A binding needs a trigger (key or button) and either a spell, macro,
        -- or a non-spell action type (target/focus/assist/menu/ping).
        local actionType = binding.actionType or "spell"
        local hasAction = binding.spell or binding.macro or actionType ~= "spell"
        -- Resolve current spell name from root spellID at apply-time
        local spellName = (actionType == "spell") and ResolveSpellName(binding) or binding.spell

        if binding.key and hasAction then
            -- Keyboard binding
            table_insert(keyboardBindings, {
                key = binding.key,
                modifiers = binding.modifiers or "",
                spell = spellName,
                macro = binding.macro,
                actionType = actionType,
            })
        elseif binding.button and hasAction then
            local scrollKey = SCROLL_WHEEL_KEYS[binding.button]
            if scrollKey then
                -- Scroll wheel uses override bindings (same path as keyboard keys)
                table_insert(keyboardBindings, {
                    key = scrollKey,
                    modifiers = binding.modifiers or "",
                    spell = spellName,
                    macro = binding.macro,
                    actionType = actionType,
                })
            else
                -- Mouse binding
                table_insert(activeBindings, {
                    button = binding.button,
                    modifiers = binding.modifiers or "",
                    spell = spellName,
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
    if not frame then return end
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

        frame:HookScript("OnEnter", function(self)
            if not isEnabled then return end
            currentKeyboardFrame = self
            -- TEMP DIAGNOSTIC (inert unless /run QUI_CC_DEBUG=true). Runs AFTER
            -- the secure OnEnter pre-body, so GetBindingAction reflects whether the
            -- snippet actually bound the key. Remove once the cold-boot keyboard
            -- failure is localized.
            if _G.QUI_CC_DEBUG then
                local hdr = bindingHeader
                local kc = (hdr and hdr:GetAttribute("clickcast-keycount")) or 0
                local b1 = keyboardBindings[1]
                local fullKey = b1 and (ModifiersToBindingPrefix(b1.modifiers) .. b1.key:upper())
                local vbtn = b1 and GetVirtualButtonName(b1)
                print(("|cff00ffffQUI-CC|r name=%s wrapped=%s keycount=%s type[%s]=%s bind[%s]=%s"):format(
                    tostring(self:GetName()),
                    secureWrappedFrames[self] and "Y" or "N",
                    tostring(kc),
                    tostring(vbtn), tostring(vbtn and self:GetAttribute("type-" .. vbtn)),
                    tostring(fullKey), tostring(fullKey and GetBindingAction(fullKey, true))))
            end
            -- On-demand recovery: if click-cast is configured but still unresolved
            -- (secure header stranded at keycount 0 -- spec/loadout data landed
            -- after the startup retry window, or frames laid out late), rebuild now.
            -- The frame is provably present and the player is reaching for the
            -- keybind. Defer out of this (secure) event context via C_Timer.After(0)
            -- so RefreshBindings' protected attribute writes don't taint; the flag
            -- coalesces hovering several still-dead frames into one rebuild.
            if IsUnresolvedButConfigured() and not dataReadyRefreshScheduled then
                dataReadyRefreshScheduled = true
                C_Timer.After(0, function()
                    dataReadyRefreshScheduled = false
                    -- If the data landed mid-combat (player reaching for the
                    -- keybind during a pull), the secure rebuild can't run now.
                    -- Don't drop the recovery: leave a pending request so
                    -- PLAYER_REGEN_ENABLED revives the keybind the instant combat
                    -- ends — otherwise keyboard click-cast stays dead for the rest
                    -- of the session unless the player happens to hover again out
                    -- of combat. Mirrors the talent-event / spec-change handlers.
                    if not InCombatLockdown() then
                        QUI_GFCC:RefreshBindings()
                    else
                        QUI_GFCC.pendingRefresh = true
                    end
                end)
            end
        end)
        frame:HookScript("OnLeave", function(self)
            if currentKeyboardFrame == self then
                currentKeyboardFrame = nil
                ClearHeaderOverrideBindings()
            end
        end)
        frame:HookScript("OnHide", function(self)
            if currentKeyboardFrame == self then
                currentKeyboardFrame = nil
                ClearHeaderOverrideBindings()
            end
        end)

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
                    smartResSwapped[self] = true
                    self:SetAttribute("type1", "macro")
                    self:SetAttribute("macrotext1", resMacro)
                end
            end)
            frame:HookScript("OnLeave", function(self)
                if not smartResSwapped[self] then return end
                smartResSwapped[self] = nil
                if not isEnabled then return end
                if InCombatLockdown() then return end
                -- Restore normal binding (only needed because OnEnter swapped to res)
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
                    -- Default: target (safe fallback when undoing a res swap)
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

local function RegisterHeaderChildren(header)
    if not header then return end
    for i = 1, 40 do
        local child = header:GetAttribute("child" .. i)
        if child then
            SetupFrameClickCast(child)
        end
    end
end

---------------------------------------------------------------------------
-- PUBLIC API
---------------------------------------------------------------------------
function QUI_GFCC:Initialize()
    -- One-time per-character: copy legacy profile.quiGroupFrames.clickCast
    -- onto db.char.clickCast. Initialize can run before PLAYER_ENTERING_WORLD
    -- (groupframes/unitframes call it during their own init), so the
    -- migration must run here too — otherwise the first session after
    -- upgrade reads empty char defaults until PLAYER_ENTERING_WORLD fires.
    MigrateProfileClickCastToChar()

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

    -- Re-entrant Initialize (already set up once): refresh through the
    -- consistent path. A bare re-resolve here updates only the header's key
    -- attributes; if the resolve is transiently empty (spec/loadout data not
    -- ready yet) that would zero the header while frames stay keyboard-wrapped
    -- — silently killing keyboard click-cast (mouse, set directly on the frame,
    -- survives). RefreshBindings rebuilds the header and frames together.
    if isEnabled then
        self:RefreshBindings()
        return
    end

    ResolveBindings()
    UpdateHeaderKeyAttributes()
    isEnabled = true
end

function QUI_GFCC:RegisterFrame(frame)
    if not isEnabled then return end
    SetupFrameClickCast(frame)
end


function QUI_GFCC:RegisterAllFrames()
    if not isEnabled then return end
    local GF = ns.QUI_GroupFrames
    if not GF or not GF.headers then return end

    -- Walk header children directly rather than relying on a cached list.
    -- This always gets current children regardless of creation timing.
    for _, headerKey in ipairs({"party", "raid", "self"}) do
        RegisterHeaderChildren(GF.headers[headerKey])
    end

    -- Raid section headers used for grouped raids and raid self-first ordering.
    -- These are separate from headers.raid and must be registered independently.
    if GF.raidGroupHeaders then
        for _, header in ipairs(GF.raidGroupHeaders) do
            RegisterHeaderChildren(header)
        end
    end

    -- Fallback for split/deferred layout paths. The decorated frame list is
    -- maintained by groupframes_layout.lua and can contain buttons even when a
    -- SecureGroupHeader child walk is temporarily incomplete.
    if GF.allFrames then
        for _, frame in ipairs(GF.allFrames) do
            SetupFrameClickCast(frame)
        end
    end

    -- Spotlight header children
    RegisterHeaderChildren(GF.spotlightHeader)
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
        ClearHeaderOverrideBindings()
        currentKeyboardFrame = nil
        isEnabled = false
        return
    end

    -- Enable/refresh: resolve bindings and re-apply
    isEnabled = true
    ResolveBindings()
    UpdateHeaderKeyAttributes()
    self:RegisterAllFrames()
    self:RegisterUnitFrames()
    RefreshHeaderOverrideBindings()
end

function QUI_GFCC:IsEnabled()
    return isEnabled
end


function QUI_GFCC:GetEditableBindings()
    local db = GetDB()
    if not db or not db.clickCast then return {} end
    local cc = db.clickCast

    if cc.perSpec then
        local specID = GetSpecializationInfo(GetSpecialization() or 1)
        if specID then
            if cc.perLoadout then
                local configID = GetStableLoadoutID()
                if configID then
                    if not cc.loadoutBindings then cc.loadoutBindings = {} end
                    if not cc.loadoutBindings[specID] then cc.loadoutBindings[specID] = {} end
                    if not cc.loadoutBindings[specID][configID] then cc.loadoutBindings[specID][configID] = {} end
                    return cc.loadoutBindings[specID][configID]
                end
            end
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

    table_insert(bindings, binding)

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

    table_remove(bindings, index)

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
-- ROOT SPELL MIGRATION: Convert stored spell names to root spellIDs
---------------------------------------------------------------------------
local function MigrateBindingsToRootSpells(bindingTable)
    if not bindingTable then return end
    for _, binding in ipairs(bindingTable) do
        if (binding.actionType or "spell") == "spell" and not binding.spellID and binding.spell then
            local spellID = C_Spell.GetSpellIDForSpellIdentifier(binding.spell)
            if spellID then
                local baseID = C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(spellID) or spellID
                binding.spellID = baseID
                local rootName = C_Spell.GetSpellName(baseID)
                if rootName then binding.spell = rootName end
            end
        end
    end
end

local function RunRootSpellMigration()
    local db = GetDB()
    if not db or not db.clickCast then return end
    local cc = db.clickCast
    if cc.rootSpellMigrationDone then return end

    -- Migrate shared bindings
    MigrateBindingsToRootSpells(cc.bindings)

    -- Migrate per-spec bindings
    if cc.specBindings then
        for _, specTable in pairs(cc.specBindings) do
            MigrateBindingsToRootSpells(specTable)
        end
    end

    -- Migrate per-loadout bindings
    if cc.loadoutBindings then
        for _, specTable in pairs(cc.loadoutBindings) do
            for _, loadoutTable in pairs(specTable) do
                MigrateBindingsToRootSpells(loadoutTable)
            end
        end
    end

    cc.rootSpellMigrationDone = true
end

---------------------------------------------------------------------------
-- PROFILE → CHAR MIGRATION
-- v3.5.3 moved click-cast settings from db.profile.quiGroupFrames.clickCast
-- to db.char.clickCast so bindings stop leaking across characters that
-- share an AceDB profile. On the first login per character after the
-- upgrade, we deep-copy the legacy profile data over the freshly-seeded
-- char defaults. Stale profile data is left in place so a downgrade can
-- recover it.
---------------------------------------------------------------------------
local DeepCopy = ns.Helpers.DeepCopy

function MigrateProfileClickCastToChar()
    local QUI = _G.QUI
    if not QUI or not QUI.db then return end
    local charDB = QUI.db.char
    local profile = QUI.db.profile
    if not charDB or not profile then return end

    if not charDB.clickCast then charDB.clickCast = {} end
    if charDB.clickCast._migratedFromProfile then return end

    local source = profile.quiGroupFrames and profile.quiGroupFrames.clickCast
    if type(source) == "table" then
        for k, v in pairs(source) do
            charDB.clickCast[k] = DeepCopy(v)
        end
    end

    charDB.clickCast._migratedFromProfile = true
end

---------------------------------------------------------------------------
-- EVENTS: Spec/loadout change and combat end
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
-- Cold-login data-ready signals: spec/talent data can land after the bounded
-- startup retry gives up, so re-resolve when the client says it's available.
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")

local loadoutDebounceTimer = nil
local rosterDebounceTimer = nil

-- Startup catch-up: on a cold login, spec/loadout data lands asynchronously
-- after PLAYER_ENTERING_WORLD, so the first binding resolve can come up empty
-- and leave the secure header at keycount 0 (keyboard click-cast dead) while the
-- directly-applied mouse attributes still work. A single fixed-delay pass loses
-- that race and nothing re-runs it. Retry RefreshBindings until the active
-- binding table actually resolves -- the way an in-world /reload (data already
-- cached) gets it right on the first pass. Bounded so a profile with genuinely
-- no resolvable bindings doesn't spin.
local STARTUP_REFRESH_INTERVAL = 1.0
local STARTUP_REFRESH_MAX_ATTEMPTS = 12
local startupRefreshAttempts = 0

-- True when the character has click-cast bindings configured somewhere (shared /
-- per-spec / per-loadout). Lets the catch-up tell "data not ready yet" (retry)
-- apart from "nothing to apply" (stop).
local function HasConfiguredBindings()
    local db = GetDB()
    if not db or not db.clickCast then return false end
    local cc = db.clickCast
    if cc.bindings and #cc.bindings > 0 then return true end
    if cc.specBindings then
        for _, t in pairs(cc.specBindings) do
            if type(t) == "table" and #t > 0 then return true end
        end
    end
    if cc.loadoutBindings then
        for _, specTable in pairs(cc.loadoutBindings) do
            if type(specTable) == "table" then
                for _, t in pairs(specTable) do
                    if type(t) == "table" and #t > 0 then return true end
                end
            end
        end
    end
    return false
end

-- True when click-cast is on and configured but nothing has resolved yet
-- (both binding tables empty) -- i.e. the secure header is stranded at keycount
-- 0 while spec/loadout data is still landing. Shared by the startup retry guard
-- and the data-ready event handlers so they agree on "still dead". Checking both
-- tables means a legitimately mouse-only or keyboard-only resolve counts as done.
IsUnresolvedButConfigured = function()
    local db = GetDB()
    if not db or not db.clickCast or not db.clickCast.enabled then return false end
    return #activeBindings == 0 and #keyboardBindings == 0 and HasConfiguredBindings()
end

local function RunStartupRefresh()
    -- Secure setup can't run in combat; defer to PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then
        QUI_GFCC.pendingRefresh = true
        return
    end

    startupRefreshAttempts = startupRefreshAttempts + 1
    QUI_GFCC:RefreshBindings()

    -- Bindings configured but nothing resolved => spec/loadout data isn't ready
    -- yet. Retry for a bounded window. If the data lands after the window closes,
    -- two catch-alls pick it up: the PLAYER_TALENT_UPDATE /
    -- ACTIVE_PLAYER_SPECIALIZATION_CHANGED handlers (proactive), and the on-hover
    -- re-resolve (on demand, when the user reaches for the keybind).
    if startupRefreshAttempts < STARTUP_REFRESH_MAX_ATTEMPTS and IsUnresolvedButConfigured() then
        C_Timer.After(STARTUP_REFRESH_INTERVAL, RunStartupRefresh)
    end
end

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

        -- One-time per-character: copy legacy profile.quiGroupFrames.clickCast
        -- onto db.char.clickCast. Must run before RunRootSpellMigration so
        -- the root-spell pass operates on the migrated char-level data.
        MigrateProfileClickCastToChar()

        -- Migrate existing bindings to store root spellIDs
        RunRootSpellMigration()

        -- After /reload or zone transition, re-register all frames.
        -- Spec data and group composition may not be fully available during
        -- ADDON_LOADED, so this catch-up ensures bindings are applied.
        if not isEnabled then
            -- Try to initialize if not done yet (covers case where
            -- ADDON_LOADED ran before DB was ready)
            QUI_GFCC:Initialize()
        end
        if isEnabled then
            startupRefreshAttempts = 0
            C_Timer.After(STARTUP_REFRESH_INTERVAL, RunStartupRefresh)
        end
        return
    end

    if not isEnabled then return end

    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Re-resolve bindings for new spec
        C_Timer.After(0.5, function()
            if not InCombatLockdown() then
                QUI_GFCC:RefreshBindings()
            else
                QUI_GFCC.pendingRefresh = true
            end
        end)
    elseif event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
        -- Spec/talent data may have just become available on a cold login. This is
        -- the catch-all that revives keyboard click-cast if the bounded startup
        -- retry gave up before the data landed. These fire frequently, so act only
        -- while still stranded (keycount 0 with bindings configured) and coalesce
        -- a burst into a single deferred resolve.
        if not dataReadyRefreshScheduled and IsUnresolvedButConfigured() then
            dataReadyRefreshScheduled = true
            C_Timer.After(0.5, function()
                dataReadyRefreshScheduled = false
                if not IsUnresolvedButConfigured() then return end
                if not InCombatLockdown() then
                    QUI_GFCC:RefreshBindings()
                else
                    QUI_GFCC.pendingRefresh = true
                end
            end)
        end
    elseif event == "TRAIT_CONFIG_UPDATED" or event == "ACTIVE_COMBAT_CONFIG_CHANGED" then
        -- Loadout changed within same spec — only relevant if perLoadout is on
        local db = GetDB()
        if not db or not db.clickCast or not db.clickCast.perLoadout then return end

        -- Debounce: talent API may not be ready immediately
        if loadoutDebounceTimer then loadoutDebounceTimer:Cancel() end
        loadoutDebounceTimer = C_Timer.NewTimer(0.5, function()
            loadoutDebounceTimer = nil
            if not InCombatLockdown() then
                QUI_GFCC:RefreshBindings()
            else
                QUI_GFCC.pendingRefresh = true
            end
        end)
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Roster changed (e.g. zoning into a dungeon adds party members, including
        -- NPC followers). Secure group headers create and assign their child unit
        -- buttons lazily as the roster settles — frequently AFTER the one-shot
        -- PLAYER_ENTERING_WORLD catch-up — so frames that appear on a roster change
        -- would otherwise have no click-cast bindings until the next /reload.
        -- Re-register all frames: SetupFrameClickCast is idempotent (it skips
        -- already-registered frames), so this only binds the newly created ones.
        -- Debounce because GRU fires in bursts and the header needs a moment to
        -- create/assign children.
        if rosterDebounceTimer then rosterDebounceTimer:Cancel() end
        rosterDebounceTimer = C_Timer.NewTimer(0.3, function()
            rosterDebounceTimer = nil
            if not InCombatLockdown() then
                QUI_GFCC:RegisterAllFrames()
                QUI_GFCC:RegisterUnitFrames()
                RefreshHeaderOverrideBindings()
            else
                QUI_GFCC.pendingRefresh = true
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
