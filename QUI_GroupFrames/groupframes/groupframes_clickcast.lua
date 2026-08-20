local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local DeepCopy = ns.Helpers.DeepCopy

local function GetDB()
    return _G.QUI and _G.QUI.db and _G.QUI.db.char or nil
end

local MigrateProfileClickCastToChar

local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local table_insert = table.insert
local table_remove = table.remove
local issecretvalue = _G.issecretvalue

local QUI_GFCC = {}
ns.QUI_GroupFrameClickCast = QUI_GFCC

local registeredFrames = Helpers.CreateStateTable()
local hookedFrames = Helpers.CreateStateTable()
local secureWrappedFrames = Helpers.CreateStateTable()
local activeBindings = {}
local keyboardBindings = {}
local globalKeyBindings = {}
local isEnabled = false
local dataReadyRefreshScheduled = false
local IsUnresolvedButConfigured
local HasConfiguredBindings

local PING_MACROS = {
    ping         = "/ping [@mouseover]",
    ping_assist  = "/ping [@mouseover] assist",
    ping_attack  = "/ping [@mouseover] attack",
    ping_warning = "/ping [@mouseover] warning",
    ping_onmyway = "/ping [@mouseover] onmyway",
}

local function BuildMouseoverCastMacro(spell)
    return "/cast [@mouseover,help,nodead] " .. spell
        .. "; [@mouseover,harm,nodead] " .. spell
        .. "; [@mouseover] " .. spell
end

local function BuildPlainMouseoverCastMacro(spell)
    return "/cast [@mouseover] " .. spell
end

local function ButtonAttrName(attr, suffix)
    return attr .. (tonumber(suffix) and "" or "-") .. suffix
end

local PING_LABELS = {
    ping         = "Ping",
    ping_assist  = "Ping: Assist",
    ping_attack  = "Ping: Attack",
    ping_warning = "Ping: Warning",
    ping_onmyway = "Ping: On My Way",
}

local BUTTON_NAMES = {
    LeftButton = "Left Click",
    RightButton = "Right Click",
    MiddleButton = "Middle Click",
    Button4 = "Button 4",
    Button5 = "Button 5",
    ScrollUp = "Scroll Up",
    ScrollDown = "Scroll Down",
}

local SCROLL_WHEEL_KEYS = {
    ScrollUp = "MOUSEWHEELUP",
    ScrollDown = "MOUSEWHEELDOWN",
}

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

local RES_SPELLS = {
    PRIEST      = 2006,
    PALADIN     = 7328,
    SHAMAN      = 2008,
    DRUID       = 50769,
    MONK        = 115178,
    EVOKER      = 361227,
    WARLOCK     = 20707,
    DEATHKNIGHT = 61999,
}

local function GetResurrectionSpellName()
    local _, classToken = UnitClass("player")
    -- @secret-policy: collapse-only — no res spell resolved
    if issecretvalue and issecretvalue(classToken) then classToken = nil end
    local spellID = classToken and RES_SPELLS[classToken]
    if spellID then
        local name = C_Spell.GetSpellName(spellID)
        return name
    end
    return nil
end

local bindingHeader

local DANGLING_SNIPPET = [[
    if name ~= "cc-hasunit" or value ~= "false" then return end
    if not currentHoverFrame then return end
    local x, y = currentHoverFrame:GetMousePosition()
    if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 and currentHoverFrame:IsVisible() then
        return
    end
    self:ClearBindings()
    currentHoverFrame = nil
]]

local function GetBindingHeader()
    if not bindingHeader then
        bindingHeader = CreateFrame("Frame", "QUI_ClickCastHeader", UIParent,
            "SecureHandlerBaseTemplate,SecureHandlerAttributeTemplate")
        bindingHeader:SetAttribute("_onattributechanged", DANGLING_SNIPPET)
        RegisterAttributeDriver(bindingHeader, "cc-hasunit", "[@mouseover,exists] true; false")
    end
    return bindingHeader
end

local ENTER_SNIPPET = [[
    owner:ClearBindings()
    currentHoverFrame = self

    if self:GetAttribute("clickcast-active") ~= 1 then return end

    local pname = self:GetAttribute("clickcast-proxyname")
    if not pname then return end

    local count = owner:GetAttribute("clickcast-keycount") or 0
    if count == 0 then return end

    for i = 1, count do
        local key  = owner:GetAttribute("clickcast-key"  .. i)
        local vbtn = owner:GetAttribute("clickcast-vbtn" .. i)
        if key and vbtn then
            owner:SetBindingClick(true, key, pname, vbtn)
        end
    end
]]

local LEAVE_SNIPPET = [[
    if currentHoverFrame == self then
        owner:ClearBindings()
        currentHoverFrame = nil
    end
]]

local CLEAR_HEADER_BINDINGS_SNIPPET = [[
    self:ClearBindings()
    currentHoverFrame = nil
]]

local function WrapFrameSecureHandlers(frame)
    if secureWrappedFrames[frame] then return end
    if InCombatLockdown() then return end

    local header = GetBindingHeader()
    SecureHandlerWrapScript(frame, "OnEnter", header, ENTER_SNIPPET)
    SecureHandlerWrapScript(frame, "OnLeave", header, LEAVE_SNIPPET)

    secureWrappedFrames[frame] = true
end

local function ClearHeaderOverrideBindings()
    if InCombatLockdown() then return end
    if bindingHeader and bindingHeader.Execute then
        bindingHeader:Execute(CLEAR_HEADER_BINDINGS_SNIPPET)
    end
end

local function GetVirtualButtonName(binding)
    return "key" .. (binding.modifiers or ""):gsub("%-", "") .. binding.key:lower()
end

local KeyboardContextUnresolved

local function UpdateHeaderKeyAttributes()
    local header = GetBindingHeader()
    if InCombatLockdown() then return end

    if #globalKeyBindings == 0 and #keyboardBindings == 0 and KeyboardContextUnresolved() then
        return
    end

    local oldCount = header:GetAttribute("clickcast-keycount") or 0
    for i = 1, oldCount do
        header:SetAttribute("clickcast-key" .. i, nil)
        header:SetAttribute("clickcast-vbtn" .. i, nil)
    end

    local total = #keyboardBindings + #globalKeyBindings
    header:SetAttribute("clickcast-keycount", total)

    local idx = 0
    for _, binding in ipairs(keyboardBindings) do
        idx = idx + 1
        local modPrefix = ModifiersToBindingPrefix(binding.modifiers)
        local fullKey = modPrefix .. binding.key:upper()
        local vBtn = GetVirtualButtonName(binding)
        header:SetAttribute("clickcast-key" .. idx, fullKey)
        header:SetAttribute("clickcast-vbtn" .. idx, vBtn)
    end
    for _, binding in ipairs(globalKeyBindings) do
        idx = idx + 1
        local modPrefix = ModifiersToBindingPrefix(binding.modifiers)
        local fullKey = modPrefix .. binding.key:upper()
        local vBtn = GetVirtualButtonName(binding)
        header:SetAttribute("clickcast-key" .. idx, fullKey)
        header:SetAttribute("clickcast-vbtn" .. idx, vBtn)
    end
end

local targetProxies = setmetatable({}, { __mode = "k" })
local menuProxies = setmetatable({}, { __mode = "k" })

local function GetActionProxy(frame, cache, actionType)
    local proxy = cache[frame]
    if proxy then return proxy end
    if InCombatLockdown() then return nil end
    proxy = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
    proxy:SetSize(1, 1)
    proxy:SetAlpha(0)
    proxy:EnableMouse(false)
    proxy:RegisterForClicks("AnyUp")
    proxy:SetAttribute("type", actionType)
    for i = 1, 5 do proxy:SetAttribute("type" .. i, actionType) end
    proxy:SetAttribute("useparent-unit", true)
    proxy:SetAttribute("useOnKeyDown", false)
    cache[frame] = proxy
    return proxy
end

local function GetTargetProxy(frame) return GetActionProxy(frame, targetProxies, "target") end
local function GetMenuProxy(frame)   return GetActionProxy(frame, menuProxies, "togglemenu") end

local proxyPool      = setmetatable({}, { __mode = "k" })
local proxyBackup    = setmetatable({}, { __mode = "k" })
local proxyRemapVBtns = setmetatable({}, { __mode = "k" })
local frameRoutingWritten = setmetatable({}, { __mode = "k" })
local proxyWrittenAttrs = setmetatable({}, { __mode = "k" })
local proxyCounter = 0

local function RecordCastAttr(proxy, attr, value)
    proxy:SetAttribute(attr, value)
    if value == nil then return end
    local set = proxyWrittenAttrs[proxy]
    if not set then set = {}; proxyWrittenAttrs[proxy] = set end
    set[attr] = true
end

local ALL_MOD_PREFIXES = {
    "", "alt-", "ctrl-", "shift-",
    "alt-ctrl-", "alt-shift-", "ctrl-shift-", "alt-ctrl-shift-",
}

local PROXY_BACKUP_ATTRS = (function()
    local list = {}
    local btns = { "1", "2", "3", "4", "5" }
    for _, pfx in ipairs(ALL_MOD_PREFIXES) do
        for _, n in ipairs(btns) do
            list[#list + 1] = pfx .. "type"        .. n
            list[#list + 1] = pfx .. "clickbutton" .. n
        end
    end
    return list
end)()

local function GetOrCreateProxy(frame)
    local existing = proxyPool[frame]
    if existing then return existing end
    if InCombatLockdown() then return nil end

    proxyCounter = proxyCounter + 1
    local proxy = CreateFrame("Button",
        "QUI_ClickCastProxy" .. proxyCounter,
        frame, "SecureActionButtonTemplate")
    proxy:SetAttribute("useparent-unit", true)
    proxy:SetAttribute("useOnKeyDown", false)
    proxy:RegisterForClicks("AnyUp")

    local backup = {}
    for _, attr in ipairs(PROXY_BACKUP_ATTRS) do
        backup[attr] = frame:GetAttribute(attr)
    end
    proxyBackup[frame] = backup

    proxyPool[frame] = proxy
    return proxy
end

local function ProxyName(frame)
    local proxy = proxyPool[frame]
    if not proxy then return nil end
    return proxy:GetName()
end

local BUTTON_NUMBERS = {
    LeftButton = "1",
    RightButton = "2",
    MiddleButton = "3",
    Button4 = "4",
    Button5 = "5",
}

local function WriteFrameRouting(frame, proxy)
    if InCombatLockdown() then return end

    local written = {}
    frameRoutingWritten[frame] = written

    for _, b in ipairs(activeBindings) do
        if not SCROLL_WHEEL_KEYS[b.button] then
            local prefix = ModifiersToAttributePrefix(b.modifiers)
            local btnNum = BUTTON_NUMBERS[b.button]
            if btnNum then
                local typeAttr   = prefix .. "type"        .. btnNum
                local clickAttr  = prefix .. "clickbutton" .. btnNum
                frame:SetAttribute(typeAttr,  "click")
                frame:SetAttribute(clickAttr, proxy)
                written[#written + 1] = typeAttr
                written[#written + 1] = clickAttr
            end
        end
    end

    frame:SetAttribute("clickcast-proxyname", proxy:GetName())
end

local function TeardownFrameRouting(frame)
    if InCombatLockdown() then return end
    local backup  = proxyBackup[frame]
    local written = frameRoutingWritten[frame]
    if written then
        for _, attr in ipairs(written) do
            local orig = backup and backup[attr]
            frame:SetAttribute(attr, orig)
        end
        frameRoutingWritten[frame] = nil
    end
    frame:SetAttribute("clickcast-proxyname", nil)
end

local function SetFrameKeyAttributes(proxy, frame)
    if InCombatLockdown() then return end
    for _, binding in ipairs(keyboardBindings) do
        local vBtn = GetVirtualButtonName(binding)
        local actionType = binding.actionType or "spell"

        if actionType == "spell" then
            if binding.friend then
                local remapped = "friend" .. vBtn
                proxy:SetAttribute(ButtonAttrName("helpbutton", vBtn), remapped)
                proxy:SetAttribute("type-" .. remapped, "macro")
                proxy:SetAttribute("macrotext-" .. remapped, BuildPlainMouseoverCastMacro(binding.spell))
                local remapSet = proxyRemapVBtns[proxy]
                if not remapSet then remapSet = {}; proxyRemapVBtns[proxy] = remapSet end
                remapSet[ButtonAttrName("helpbutton", vBtn)] = true
                remapSet["type-" .. remapped] = true
                remapSet["macrotext-" .. remapped] = true
            elseif binding.enemy then
                local remapped = "enemy" .. vBtn
                proxy:SetAttribute(ButtonAttrName("harmbutton", vBtn), remapped)
                proxy:SetAttribute("type-" .. remapped, "macro")
                proxy:SetAttribute("macrotext-" .. remapped, BuildPlainMouseoverCastMacro(binding.spell))
                local remapSet = proxyRemapVBtns[proxy]
                if not remapSet then remapSet = {}; proxyRemapVBtns[proxy] = remapSet end
                remapSet[ButtonAttrName("harmbutton", vBtn)] = true
                remapSet["type-" .. remapped] = true
                remapSet["macrotext-" .. remapped] = true
            else
                proxy:SetAttribute("type-" .. vBtn, "macro")
                proxy:SetAttribute("macrotext-" .. vBtn, BuildMouseoverCastMacro(binding.spell))
            end
        elseif actionType == "macro" then
            if binding.friend then
                local remapped = "friend" .. vBtn
                proxy:SetAttribute(ButtonAttrName("helpbutton", vBtn), remapped)
                proxy:SetAttribute("type-" .. remapped, "macro")
                proxy:SetAttribute("macrotext-" .. remapped, binding.macro)
                local remapSet = proxyRemapVBtns[proxy]
                if not remapSet then remapSet = {}; proxyRemapVBtns[proxy] = remapSet end
                remapSet[ButtonAttrName("helpbutton", vBtn)] = true
                remapSet["type-" .. remapped] = true
                remapSet["macrotext-" .. remapped] = true
            elseif binding.enemy then
                local remapped = "enemy" .. vBtn
                proxy:SetAttribute(ButtonAttrName("harmbutton", vBtn), remapped)
                proxy:SetAttribute("type-" .. remapped, "macro")
                proxy:SetAttribute("macrotext-" .. remapped, binding.macro)
                local remapSet = proxyRemapVBtns[proxy]
                if not remapSet then remapSet = {}; proxyRemapVBtns[proxy] = remapSet end
                remapSet[ButtonAttrName("harmbutton", vBtn)] = true
                remapSet["type-" .. remapped] = true
                remapSet["macrotext-" .. remapped] = true
            else
                proxy:SetAttribute("type-" .. vBtn, "macro")
                proxy:SetAttribute("macrotext-" .. vBtn, binding.macro)
            end
        elseif actionType == "target" then
            local tProxy = GetTargetProxy(frame)
            if tProxy then
                proxy:SetAttribute("type-" .. vBtn, "click")
                proxy:SetAttribute("clickbutton-" .. vBtn, tProxy)
            end
        elseif actionType == "focus" then
            proxy:SetAttribute("type-" .. vBtn, "focus")
        elseif actionType == "assist" then
            proxy:SetAttribute("type-" .. vBtn, "assist")
        elseif actionType == "menu" then
            local mProxy = GetMenuProxy(frame)
            if mProxy then
                proxy:SetAttribute("type-" .. vBtn, "click")
                proxy:SetAttribute("clickbutton-" .. vBtn, mProxy)
            end
        elseif actionType:match("^ping") then
            proxy:SetAttribute("type-" .. vBtn, "macro")
            proxy:SetAttribute("macrotext-" .. vBtn, PING_MACROS[actionType] or "/ping [@mouseover]")
        end
    end
end

local function ClearFrameKeyAttributes(proxy)
    if InCombatLockdown() then return end
    for _, binding in ipairs(keyboardBindings) do
        local vBtn = GetVirtualButtonName(binding)
        proxy:SetAttribute("type-" .. vBtn, nil)
        proxy:SetAttribute("macrotext-" .. vBtn, nil)
        proxy:SetAttribute("clickbutton-" .. vBtn, nil)
        proxy:SetAttribute(ButtonAttrName("helpbutton", vBtn), nil)
        proxy:SetAttribute(ButtonAttrName("harmbutton", vBtn), nil)
        proxy:SetAttribute("type-friend" .. vBtn, nil)
        proxy:SetAttribute("macrotext-friend" .. vBtn, nil)
        proxy:SetAttribute("type-enemy" .. vBtn, nil)
        proxy:SetAttribute("macrotext-enemy" .. vBtn, nil)
    end
    local remapSet = proxyRemapVBtns[proxy]
    if remapSet then
        for attr in pairs(remapSet) do
            proxy:SetAttribute(attr, nil)
        end
        proxyRemapVBtns[proxy] = nil
    end
end

local function ResolveSpellName(binding)
    if binding.spellID then
        local name = C_Spell.GetSpellName(binding.spellID)
        if name then return name end
    end
    return binding.spell
end

local function GetCurrentSpecID()
    local specID = Helpers.GetCurrentSpecID()
    if specID and specID ~= 0 then return specID end
    return nil
end

local function GetStableLoadoutID()
    local specID = GetCurrentSpecID()
    if not specID or not C_ClassTalents then return nil, specID end
    local savedID = C_ClassTalents.GetLastSelectedSavedConfigID and C_ClassTalents.GetLastSelectedSavedConfigID(specID)
    if savedID then return savedID, specID end
    local activeID = C_ClassTalents.GetActiveConfigID()
    if activeID and activeID ~= 0 then return activeID, specID end
    return nil, specID
end

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
    wipe(globalKeyBindings)

    local db = GetDB()
    if not db or not db.clickCast or not db.clickCast.enabled then return end

    local bindings = GetActiveBindingTable()
    if not bindings then return end

    for _, binding in ipairs(bindings) do
        local actionType = binding.actionType or "spell"
        local hasAction = binding.spell or binding.macro or actionType ~= "spell"
        local spellName = (actionType == "spell") and ResolveSpellName(binding) or binding.spell

        if binding.key and hasAction then
            table_insert(globalKeyBindings, {
                key = binding.key,
                modifiers = binding.modifiers or "",
                spell = spellName,
                macro = binding.macro,
                actionType = actionType,
                friend = binding.friend,
                enemy = binding.enemy,
            })
        elseif binding.button and hasAction then
            local scrollKey = SCROLL_WHEEL_KEYS[binding.button]
            if scrollKey then
                table_insert(keyboardBindings, {
                    key = scrollKey,
                    modifiers = binding.modifiers or "",
                    spell = spellName,
                    macro = binding.macro,
                    actionType = actionType,
                    friend = binding.friend,
                    enemy = binding.enemy,
                })
            else
                table_insert(activeBindings, {
                    button = binding.button,
                    modifiers = binding.modifiers or "",
                    spell = spellName,
                    macro = binding.macro,
                    actionType = actionType,
                    friend = binding.friend,
                    enemy = binding.enemy,
                })
            end
        end
    end
end

local proxyKeyVBtns = setmetatable({}, { __mode = "k" })

KeyboardContextUnresolved = function()
    local db = GetDB()
    if not db or not db.clickCast or not db.clickCast.perSpec then return false end
    if not GetCurrentSpecID() then return true end
    if db.clickCast.perLoadout and not GetStableLoadoutID() then return true end
    return false
end

local function BuildKeyMacro(binding)
    local actionType = binding.actionType or "spell"
    if actionType == "spell" then
        return BuildMouseoverCastMacro(binding.spell)
    elseif actionType == "macro" then
        return binding.macro or ""
    elseif actionType == "target" then
        return "/target [@mouseover]"
    elseif actionType == "focus" then
        return "/focus [@mouseover]"
    elseif actionType == "assist" then
        return "/assist [@mouseover]"
    elseif actionType:match("^ping") then
        return PING_MACROS[actionType] or "/ping [@mouseover]"
    end
    return nil
end

local function ApplyKeyboardAttrsToProxy(proxy, frame)
    if InCombatLockdown() then return end
    if #globalKeyBindings == 0 and KeyboardContextUnresolved() then return end

    local oldVBtns = proxyKeyVBtns[proxy]
    if oldVBtns then
        for vBtn in pairs(oldVBtns) do
            proxy:SetAttribute("type-" .. vBtn, nil)
            proxy:SetAttribute("macrotext-" .. vBtn, nil)
            proxy:SetAttribute("unit-" .. vBtn, nil)
            proxy:SetAttribute("clickbutton-" .. vBtn, nil)
            proxy:SetAttribute(ButtonAttrName("helpbutton", vBtn), nil)
            proxy:SetAttribute(ButtonAttrName("harmbutton", vBtn), nil)
            proxy:SetAttribute("type-friend" .. vBtn, nil)
            proxy:SetAttribute("macrotext-friend" .. vBtn, nil)
            proxy:SetAttribute("type-enemy" .. vBtn, nil)
            proxy:SetAttribute("macrotext-enemy" .. vBtn, nil)
        end
    end
    proxyRemapVBtns[proxy] = nil
    local vBtnSet = {}
    proxyKeyVBtns[proxy] = vBtnSet

    for _, b in ipairs(globalKeyBindings) do
        local vBtn = GetVirtualButtonName(b)
        vBtnSet[vBtn] = true
        local actionType = b.actionType or "spell"
        if actionType == "menu" then
            proxy:SetAttribute("type-" .. vBtn, "togglemenu")
            proxy:SetAttribute("unit-" .. vBtn, "mouseover")
        elseif actionType == "target" then
            local tProxy = GetTargetProxy(frame)
            if tProxy then
                proxy:SetAttribute("type-" .. vBtn, "click")
                proxy:SetAttribute("clickbutton-" .. vBtn, tProxy)
            end
        else
            local actionType2 = b.actionType or "spell"
            if actionType2 == "spell" and b.friend then
                local remapped = "friend" .. vBtn
                proxy:SetAttribute(ButtonAttrName("helpbutton", vBtn), remapped)
                proxy:SetAttribute("type-" .. remapped, "macro")
                proxy:SetAttribute("macrotext-" .. remapped, BuildPlainMouseoverCastMacro(b.spell))
                local remapSet = proxyRemapVBtns[proxy]
                if not remapSet then remapSet = {}; proxyRemapVBtns[proxy] = remapSet end
                remapSet[ButtonAttrName("helpbutton", vBtn)] = true
                remapSet["type-" .. remapped] = true
                remapSet["macrotext-" .. remapped] = true
            elseif actionType2 == "spell" and b.enemy then
                local remapped = "enemy" .. vBtn
                proxy:SetAttribute(ButtonAttrName("harmbutton", vBtn), remapped)
                proxy:SetAttribute("type-" .. remapped, "macro")
                proxy:SetAttribute("macrotext-" .. remapped, BuildPlainMouseoverCastMacro(b.spell))
                local remapSet = proxyRemapVBtns[proxy]
                if not remapSet then remapSet = {}; proxyRemapVBtns[proxy] = remapSet end
                remapSet[ButtonAttrName("harmbutton", vBtn)] = true
                remapSet["type-" .. remapped] = true
                remapSet["macrotext-" .. remapped] = true
            elseif actionType2 == "macro" and b.friend then
                local remapped = "friend" .. vBtn
                proxy:SetAttribute(ButtonAttrName("helpbutton", vBtn), remapped)
                proxy:SetAttribute("type-" .. remapped, "macro")
                proxy:SetAttribute("macrotext-" .. remapped, b.macro)
                local remapSet = proxyRemapVBtns[proxy]
                if not remapSet then remapSet = {}; proxyRemapVBtns[proxy] = remapSet end
                remapSet[ButtonAttrName("helpbutton", vBtn)] = true
                remapSet["type-" .. remapped] = true
                remapSet["macrotext-" .. remapped] = true
            elseif actionType2 == "macro" and b.enemy then
                local remapped = "enemy" .. vBtn
                proxy:SetAttribute(ButtonAttrName("harmbutton", vBtn), remapped)
                proxy:SetAttribute("type-" .. remapped, "macro")
                proxy:SetAttribute("macrotext-" .. remapped, b.macro)
                local remapSet = proxyRemapVBtns[proxy]
                if not remapSet then remapSet = {}; proxyRemapVBtns[proxy] = remapSet end
                remapSet[ButtonAttrName("harmbutton", vBtn)] = true
                remapSet["type-" .. remapped] = true
                remapSet["macrotext-" .. remapped] = true
            else
                local mt = BuildKeyMacro(b)
                if mt then
                    proxy:SetAttribute("type-" .. vBtn, "macro")
                    proxy:SetAttribute("macrotext-" .. vBtn, mt)
                end
            end
        end
    end
end

local function ClearKeyboardAttrsFromProxy(proxy)
    if InCombatLockdown() then return end
    local oldVBtns = proxyKeyVBtns[proxy]
    if not oldVBtns then return end
    for vBtn in pairs(oldVBtns) do
        proxy:SetAttribute("type-" .. vBtn, nil)
        proxy:SetAttribute("macrotext-" .. vBtn, nil)
        proxy:SetAttribute("unit-" .. vBtn, nil)
        proxy:SetAttribute("clickbutton-" .. vBtn, nil)
        proxy:SetAttribute(ButtonAttrName("helpbutton", vBtn), nil)
        proxy:SetAttribute(ButtonAttrName("harmbutton", vBtn), nil)
        proxy:SetAttribute("type-friend" .. vBtn, nil)
        proxy:SetAttribute("macrotext-friend" .. vBtn, nil)
        proxy:SetAttribute("type-enemy" .. vBtn, nil)
        proxy:SetAttribute("macrotext-enemy" .. vBtn, nil)
    end
    proxyKeyVBtns[proxy] = nil
    local remapSet = proxyRemapVBtns[proxy]
    if remapSet then
        for attr in pairs(remapSet) do
            proxy:SetAttribute(attr, nil)
        end
        proxyRemapVBtns[proxy] = nil
    end
end

local function ApplyGlobalKeyboardBindings()
    if InCombatLockdown() then return end
    for frame in pairs(registeredFrames) do
        local proxy = proxyPool[frame]
        if proxy then
            ApplyKeyboardAttrsToProxy(proxy, frame)
        end
    end
end

local function ClearGlobalKeyboardBindings()
    if InCombatLockdown() then return end
    for frame in pairs(registeredFrames) do
        local proxy = proxyPool[frame]
        if proxy then
            ClearKeyboardAttrsFromProxy(proxy)
        end
    end
end

local function GetButtonDirections()
    local db = GetDB()
    local dir = db and db.clickCast and db.clickCast.clickDirection
    if dir == "both" then
        return "AnyUp", "AnyDown"
    elseif dir == "up" then
        return "AnyUp"
    else
        return "AnyDown"
    end
end

local function UseActionOnKeyDown()
    local db = GetDB()
    local dir = db and db.clickCast and db.clickCast.clickDirection
    return dir ~= "up"
end

local function SetupFrameClickCast(frame)
    if not frame or registeredFrames[frame] then return end
    if InCombatLockdown() then return end

    local db = GetDB()
    if not db or not db.clickCast or not db.clickCast.enabled then return end

    local proxy = GetOrCreateProxy(frame)
    if not proxy then return end

    for _, binding in ipairs(activeBindings) do
        local prefix = ModifiersToAttributePrefix(binding.modifiers)
        local btnNum = BUTTON_NUMBERS[binding.button] or "1"
        local actionType = binding.actionType or "spell"

        if actionType == "spell" then
            if binding.friend then
                local helpAttr = prefix .. "helpbutton" .. btnNum
                local remapped = "friend" .. btnNum
                local typeAttr = prefix .. "type-friend" .. btnNum
                local textAttr = prefix .. "macrotext-friend" .. btnNum
                RecordCastAttr(proxy, helpAttr, remapped)
                local macro
                if db.clickCast.smartRes and prefix == "" and btnNum == "1" then
                    local resSpell = GetResurrectionSpellName()
                    if resSpell then
                        macro = "/cast [@mouseover,help,dead] " .. resSpell
                            .. "; [@mouseover] " .. binding.spell
                    end
                end
                RecordCastAttr(proxy, typeAttr, "macro")
                RecordCastAttr(proxy, textAttr, macro or BuildPlainMouseoverCastMacro(binding.spell))
            elseif binding.enemy then
                local harmAttr = prefix .. "harmbutton" .. btnNum
                local remapped = "enemy" .. btnNum
                local typeAttr = prefix .. "type-enemy" .. btnNum
                local textAttr = prefix .. "macrotext-enemy" .. btnNum
                RecordCastAttr(proxy, harmAttr, remapped)
                RecordCastAttr(proxy, typeAttr, "macro")
                RecordCastAttr(proxy, textAttr, BuildPlainMouseoverCastMacro(binding.spell))
            else
                local macro
                if db.clickCast.smartRes and prefix == "" and btnNum == "1" then
                    local resSpell = GetResurrectionSpellName()
                    if resSpell then
                        macro = "/cast [@mouseover,help,dead] " .. resSpell
                            .. "; [@mouseover,help,nodead] " .. binding.spell
                            .. "; [@mouseover,harm,nodead] " .. binding.spell
                            .. "; [@mouseover] " .. binding.spell
                    end
                end
                RecordCastAttr(proxy, prefix .. "type" .. btnNum, "macro")
                RecordCastAttr(proxy, prefix .. "macrotext" .. btnNum, macro or BuildMouseoverCastMacro(binding.spell))
            end
        elseif actionType == "macro" then
            if binding.friend then
                local helpAttr = prefix .. "helpbutton" .. btnNum
                local remapped = "friend" .. btnNum
                local typeAttr = prefix .. "type-friend" .. btnNum
                local textAttr = prefix .. "macrotext-friend" .. btnNum
                RecordCastAttr(proxy, helpAttr, remapped)
                RecordCastAttr(proxy, typeAttr, "macro")
                RecordCastAttr(proxy, textAttr, binding.macro)
            elseif binding.enemy then
                local harmAttr = prefix .. "harmbutton" .. btnNum
                local remapped = "enemy" .. btnNum
                local typeAttr = prefix .. "type-enemy" .. btnNum
                local textAttr = prefix .. "macrotext-enemy" .. btnNum
                RecordCastAttr(proxy, harmAttr, remapped)
                RecordCastAttr(proxy, typeAttr, "macro")
                RecordCastAttr(proxy, textAttr, binding.macro)
            else
                RecordCastAttr(proxy, prefix .. "type" .. btnNum, "macro")
                RecordCastAttr(proxy, prefix .. "macrotext" .. btnNum, binding.macro)
            end
        elseif actionType == "target" then
            if prefix == "" and btnNum == "1" then
                RecordCastAttr(proxy, prefix .. "type" .. btnNum, "target")
            else
                local tProxy = GetTargetProxy(frame)
                if tProxy then
                    RecordCastAttr(proxy, prefix .. "type" .. btnNum, "click")
                    RecordCastAttr(proxy, prefix .. "clickbutton" .. btnNum, tProxy)
                end
            end
        elseif actionType == "focus" then
            RecordCastAttr(proxy, prefix .. "type" .. btnNum, "focus")
        elseif actionType == "assist" then
            RecordCastAttr(proxy, prefix .. "type" .. btnNum, "assist")
        elseif actionType == "menu" then
            if prefix == "" and btnNum == "2" then
                RecordCastAttr(proxy, prefix .. "type" .. btnNum, "togglemenu")
            else
                local mProxy = GetMenuProxy(frame)
                if mProxy then
                    RecordCastAttr(proxy, prefix .. "type" .. btnNum, "click")
                    RecordCastAttr(proxy, prefix .. "clickbutton" .. btnNum, mProxy)
                end
            end
        elseif actionType:match("^ping") then
            RecordCastAttr(proxy, prefix .. "type" .. btnNum, "macro")
            RecordCastAttr(proxy, prefix .. "macrotext" .. btnNum, PING_MACROS[actionType] or "/ping [@mouseover]")
        end
    end

    if #keyboardBindings > 0 then
        SetFrameKeyAttributes(proxy, frame)
        frame:EnableMouseWheel(true)
    end

    ApplyKeyboardAttrsToProxy(proxy, frame)

    WrapFrameSecureHandlers(frame)

    WriteFrameRouting(frame, proxy)

    frame:RegisterForClicks(GetButtonDirections())

    frame:SetAttribute("clickcast-active", 1)

    registeredFrames[frame] = true

    if not hookedFrames[frame] then
        hookedFrames[frame] = true

        frame:HookScript("OnEnter", function()
            if not isEnabled then return end
            if KeyboardContextUnresolved() then return end
            if not IsUnresolvedButConfigured() then return end
            C_Timer.After(0, function()
                if not isEnabled then return end
                if InCombatLockdown() then
                    QUI_GFCC.pendingRefresh = true
                    return
                end
                QUI_GFCC:RefreshBindings()
            end)
        end)

        frame:HookScript("OnEnter", function(self)
            if not isEnabled then return end
            local ccdb = GetDB()
            if not ccdb or not ccdb.clickCast or not ccdb.clickCast.showTooltip then return end
            if #activeBindings == 0 and #keyboardBindings == 0 and #globalKeyBindings == 0 then return end

            local existingOwner = GameTooltip:GetOwner()
            if existingOwner == self then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(ns.L["Click-Cast Bindings:"], 0.2, 0.83, 0.6)
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
                for _, keyTable in ipairs({ globalKeyBindings, keyboardBindings }) do
                    for _, binding in ipairs(keyTable) do
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
                end
                GameTooltip:Show()
            end
        end)
    end
end

local function ClearFrameClickCast(frame)
    if not frame or not registeredFrames[frame] then return end
    if InCombatLockdown() then return end

    TeardownFrameRouting(frame)

    local proxy = proxyPool[frame]
    if proxy then
        local writtenSet = proxyWrittenAttrs[proxy]
        if writtenSet then
            for attr in pairs(writtenSet) do
                proxy:SetAttribute(attr, nil)
            end
            proxyWrittenAttrs[proxy] = nil
        end
        local remapSet = proxyRemapVBtns[proxy]
        if remapSet then
            for attr in pairs(remapSet) do
                proxy:SetAttribute(attr, nil)
            end
            proxyRemapVBtns[proxy] = nil
        end
        ClearFrameKeyAttributes(proxy)
        ClearKeyboardAttrsFromProxy(proxy)
    end

    frame:SetAttribute("clickcast-active", nil)

    registeredFrames[frame] = nil
end

local function ReassertFrameClickRouting(frame)
    if not registeredFrames[frame] then return end
    if InCombatLockdown() then return end
    local proxy = proxyPool[frame]
    if not proxy then return end
    WriteFrameRouting(frame, proxy)
end

local function ReassertAllFrameClickRouting()
    if InCombatLockdown() then
        QUI_GFCC.pendingRefresh = true
        return
    end
    for frame in pairs(registeredFrames) do
        ReassertFrameClickRouting(frame)
    end
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

QUI_GFCC._test = {
    GetOrCreateProxy             = GetOrCreateProxy,
    ProxyName                    = ProxyName,
    WriteFrameRouting            = WriteFrameRouting,
    TeardownFrameRouting         = TeardownFrameRouting,
    ReassertFrameClickRouting    = ReassertFrameClickRouting,
    ApplyKeyboardAttrsToProxy    = ApplyKeyboardAttrsToProxy,
    GetButtonDirections          = GetButtonDirections,
    UseActionOnKeyDown           = UseActionOnKeyDown,
    BuildPlainMouseoverCastMacro = BuildPlainMouseoverCastMacro,
}

function QUI_GFCC:Initialize()
    MigrateProfileClickCastToChar()

    local db = GetDB()
    if not db or not db.clickCast or not db.clickCast.enabled then return end

    if IsAddOnLoaded and IsAddOnLoaded("Clique") then
        if not db.clickCast.forceOverClique then
            return
        end
    end

    if isEnabled then
        self:RefreshBindings()
        return
    end

    ResolveBindings()
    UpdateHeaderKeyAttributes()
    ApplyGlobalKeyboardBindings()
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

    for _, headerKey in ipairs({"party", "raid", "self"}) do
        RegisterHeaderChildren(GF.headers[headerKey])
    end

    if GF.raidGroupHeaders then
        for _, header in ipairs(GF.raidGroupHeaders) do
            RegisterHeaderChildren(header)
        end
    end

    RegisterHeaderChildren(GF.spotlightHeader)

    ReassertAllFrameClickRouting()
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
        local settingKey = unitKey:match("^boss%d$") and "boss" or unitKey
        if ufSettings[settingKey] then
            SetupFrameClickCast(frame)
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

    for frame in pairs(registeredFrames) do
        ClearFrameClickCast(frame)
    end
    wipe(registeredFrames)

    if not enabled then
        wipe(activeBindings)
        wipe(keyboardBindings)
        wipe(globalKeyBindings)
        UpdateHeaderKeyAttributes()
        ClearHeaderOverrideBindings()
        ClearGlobalKeyboardBindings()
        isEnabled = false
        return
    end

    isEnabled = true
    ResolveBindings()
    UpdateHeaderKeyAttributes()
    ApplyGlobalKeyboardBindings()
    self:RegisterAllFrames()
    self:RegisterUnitFrames()
end

function QUI_GFCC:IsEnabled()
    return isEnabled
end

function QUI_GFCC:GetEditableBindings()
    local db = GetDB()
    if not db or not db.clickCast then return {} end
    local cc = db.clickCast

    if cc.perSpec then
        local specID = GetCurrentSpecID()
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

local function GetEditableBindingSetID(cc)
    if cc.perSpec then
        local specID = GetCurrentSpecID()
        if specID then
            if cc.perLoadout then
                local configID = GetStableLoadoutID()
                if configID then
                    return "loadout:" .. specID .. ":" .. configID
                end
            end
            return "spec:" .. specID
        end
    end

    return "shared"
end

local function GetBindingSetByID(cc, setID)
    if setID == "shared" then
        return cc.bindings
    end

    local specID = type(setID) == "string" and setID:match("^spec:(%d+)$")
    if specID then
        specID = tonumber(specID)
        return cc.specBindings and cc.specBindings[specID]
    end

    local loadoutSpecID, configID
    if type(setID) == "string" then
        loadoutSpecID, configID = setID:match("^loadout:(%d+):(%d+)$")
    end
    if loadoutSpecID and configID then
        loadoutSpecID = tonumber(loadoutSpecID)
        configID = tonumber(configID)
        local specLoadouts = cc.loadoutBindings and cc.loadoutBindings[loadoutSpecID]
        return specLoadouts and specLoadouts[configID]
    end

    return nil
end

local function SortedNumericKeys(source)
    local keys = {}
    if type(source) ~= "table" then return keys end

    for key in pairs(source) do
        if type(key) == "number" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    return keys
end

function QUI_GFCC:GetEditableBindingSetID()
    local db = GetDB()
    local cc = db and db.clickCast
    return cc and GetEditableBindingSetID(cc) or nil
end

function QUI_GFCC:GetBindingSetSources()
    local db = GetDB()
    local cc = db and db.clickCast
    if not cc then return {} end

    local activeID = GetEditableBindingSetID(cc)
    local sources = {}
    local function AddSource(id, scope, bindings, specID, configID)
        if type(bindings) ~= "table" or #bindings == 0 then return end
        sources[#sources + 1] = {
            id = id,
            scope = scope,
            specID = specID,
            configID = configID,
            count = #bindings,
            isActive = id == activeID,
        }
    end

    AddSource("shared", "shared", cc.bindings)

    for _, specID in ipairs(SortedNumericKeys(cc.specBindings)) do
        AddSource("spec:" .. specID, "spec", cc.specBindings[specID], specID)
    end

    for _, specID in ipairs(SortedNumericKeys(cc.loadoutBindings)) do
        local loadouts = cc.loadoutBindings[specID]
        for _, configID in ipairs(SortedNumericKeys(loadouts)) do
            AddSource("loadout:" .. specID .. ":" .. configID,
                "loadout", loadouts[configID], specID, configID)
        end
    end

    return sources
end

function QUI_GFCC:CopyBindingsFrom(sourceID)
    local db = GetDB()
    local cc = db and db.clickCast
    if not cc then return false, "Click-cast settings unavailable" end

    local source = GetBindingSetByID(cc, sourceID)
    if type(source) ~= "table" then return false, "Binding set not found" end

    local target = self:GetEditableBindings()
    if source == target then return false, "Cannot copy a binding set onto itself" end

    local copied = DeepCopy(source)
    wipe(target)
    for index, binding in ipairs(copied) do
        target[index] = binding
    end

    if not InCombatLockdown() then
        self:RefreshBindings()
    else
        self.pendingRefresh = true
    end
    return true, #target
end

function QUI_GFCC:AddBinding(binding)
    if not binding then return false, "No binding specified" end
    if not binding.button and not binding.key then return false, "No button or key specified" end

    local bindings = self:GetEditableBindings()
    local mod = binding.modifiers or ""

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

    MigrateBindingsToRootSpells(cc.bindings)

    if cc.specBindings then
        for _, specTable in pairs(cc.specBindings) do
            MigrateBindingsToRootSpells(specTable)
        end
    end

    if cc.loadoutBindings then
        for _, specTable in pairs(cc.loadoutBindings) do
            for _, loadoutTable in pairs(specTable) do
                MigrateBindingsToRootSpells(loadoutTable)
            end
        end
    end

    cc.rootSpellMigrationDone = true
end

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

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")

local loadoutDebounceTimer = nil
local rosterDebounceTimer = nil

local STARTUP_REFRESH_INTERVAL = 1.0
local STARTUP_REFRESH_MAX_ATTEMPTS = 12
local startupRefreshAttempts = 0

function HasConfiguredBindings()
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

IsUnresolvedButConfigured = function()
    local db = GetDB()
    if not db or not db.clickCast or not db.clickCast.enabled then return false end
    return #activeBindings == 0 and #keyboardBindings == 0 and #globalKeyBindings == 0
        and HasConfiguredBindings()
end

local function RunStartupRefresh()
    if InCombatLockdown() then
        QUI_GFCC.pendingRefresh = true
        return
    end

    startupRefreshAttempts = startupRefreshAttempts + 1
    QUI_GFCC:RefreshBindings()

    if startupRefreshAttempts < STARTUP_REFRESH_MAX_ATTEMPTS and IsUnresolvedButConfigured() then
        C_Timer.After(STARTUP_REFRESH_INTERVAL, RunStartupRefresh)
    end
end

eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
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

        MigrateProfileClickCastToChar()

        RunRootSpellMigration()

        if not isEnabled then
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
        C_Timer.After(0.5, function()
            if not InCombatLockdown() then
                QUI_GFCC:RefreshBindings()
            else
                QUI_GFCC.pendingRefresh = true
            end
        end)
    elseif event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
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
        local db = GetDB()
        if not db or not db.clickCast or not db.clickCast.perLoadout then return end

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
        if rosterDebounceTimer then rosterDebounceTimer:Cancel() end
        rosterDebounceTimer = C_Timer.NewTimer(0.3, function()
            rosterDebounceTimer = nil
            if not InCombatLockdown() then
                QUI_GFCC:RegisterAllFrames()
            else
                QUI_GFCC.pendingRefresh = true
            end
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if QUI_GFCC.pendingRefresh then
            QUI_GFCC.pendingRefresh = false
            QUI_GFCC:RefreshBindings()
        end
    end
end)
