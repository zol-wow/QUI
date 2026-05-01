local ADDON_NAME = "QUI"
local ROOT = "."
local OUTPUT_PATH = "options/search_cache.lua"
_G.unpack = _G.unpack or table.unpack
local unpack = _G.unpack

local function normalize_path(path)
    path = tostring(path or ""):gsub("\\", "/")
    path = path:gsub("/+", "/")
    path = path:gsub("^%./", "")
    return path
end

local function join_path(base, relative)
    base = normalize_path(base)
    relative = normalize_path(relative)
    if relative:match("^%a:/") or relative:match("^/") then
        return relative
    end
    local dir = base:match("^(.*)/[^/]+$") or ""
    if dir == "" then
        return relative
    end
    return normalize_path(dir .. "/" .. relative)
end

local function dirname(path)
    return normalize_path(path):match("^(.*)/[^/]+$") or ""
end

local function read_lines(path)
    local lines = {}
    local handle = assert(io.open(path, "r"))
    for line in handle:lines() do
        lines[#lines + 1] = line
    end
    handle:close()
    return lines
end

local function collect_scripts_from_xml(xml_path, out, seen)
    xml_path = normalize_path(xml_path)
    if seen[xml_path] then
        return
    end
    seen[xml_path] = true

    for _, line in ipairs(read_lines(xml_path)) do
        local include_path = line:match('<Include file="([^"]+)"')
        if include_path then
            collect_scripts_from_xml(join_path(xml_path, include_path), out, seen)
        end

        local script_path = line:match('<Script file="([^"]+)"')
        if script_path then
            out[#out + 1] = normalize_path(join_path(xml_path, script_path))
        end
    end
end

local function should_load_script(path)
    path = normalize_path(path)

    if path == "init.lua" or path == OUTPUT_PATH then
        return false
    end
    if path:match("^libs/") or path:match("^skinning/") or path:match("^importstrings/") then
        return false
    end
    if path == "options/blizzard_options.lua" then
        return false
    end

    if path == "core/utils.lua"
        or path == "core/defaults.lua"
        or path == "core/scaling.lua"
        or path == "core/uikit.lua"
        or path == "core/settings_builders.lua"
        or path == "core/diagnostics_console.lua"
        or path:match("^core/settings/") then
        return true
    end

    if path == "modules/utility/layoutmode_utils.lua" then
        return true
    end
    if path:match("^modules/.+/settings/") then
        return true
    end

    if path:match("^options/") then
        return true
    end

    return false
end

local function make_auto_table()
    return setmetatable({}, {
        __index = function(t, k)
            local value = make_auto_table()
            rawset(t, k, value)
            return value
        end,
    })
end

local function is_stub_method_key(key)
    if type(key) ~= "string" or key == "" then
        return false
    end

    local prefixes = {
        "Set",
        "Get",
        "Create",
        "Is",
        "Has",
        "Can",
        "Enable",
        "Disable",
        "Register",
        "Unregister",
        "Hook",
        "Clear",
        "Start",
        "Stop",
        "Play",
        "Pause",
        "Resume",
        "Update",
        "Refresh",
        "Show",
        "Hide",
        "Add",
        "Remove",
        "Lock",
        "Unlock",
        "Select",
        "Deselect",
        "Toggle",
    }

    for _, prefix in ipairs(prefixes) do
        if key:sub(1, #prefix) == prefix then
            return true
        end
    end

    return key:match("^On[A-Z]") ~= nil
end

local function remove_child(parent, bucket, child)
    if type(parent) ~= "table" or type(parent[bucket]) ~= "table" then
        return
    end

    for index, existing in ipairs(parent[bucket]) do
        if existing == child then
            table.remove(parent[bucket], index)
            return
        end
    end
end

local function attach_child(parent, bucket, child)
    if type(parent) ~= "table" then
        return
    end

    parent[bucket] = parent[bucket] or {}
    parent[bucket][#parent[bucket] + 1] = child
end

local function create_stub_node(kind, parent, is_region)
    local node = {
        _captureKind = kind or "Frame",
        _captureParent = nil,
        _children = {},
        _regions = {},
        _height = 24,
        _width = 160,
        _shown = true,
        _text = "",
        _value = 0,
        _checked = false,
        _points = {},
        _frameLevel = 0,
        _frameStrata = "MEDIUM",
        _scale = 1,
        _alpha = 1,
        _enabled = true,
        _isRegion = is_region == true,
    }

    local function noop() end
    local function set_parent(self, new_parent)
        local old_parent = rawget(self, "_captureParent")
        if old_parent == new_parent then
            return
        end
        if old_parent then
            remove_child(old_parent, "_children", self)
            remove_child(old_parent, "_regions", self)
        end
        self._captureParent = new_parent
        if new_parent then
            attach_child(new_parent, self._isRegion and "_regions" or "_children", self)
        end
    end

    local function create_region(self, region_kind)
        return create_stub_node(region_kind, self, true)
    end

    local function create_animation_group()
        local group = create_stub_node("AnimationGroup", nil, true)
        group._animations = {}
        group.CreateAnimation = function(self, animation_kind)
            local animation = create_stub_node(animation_kind or "Animation", nil, true)
            self._animations[#self._animations + 1] = animation
            return animation
        end
        group.Play = noop
        group.Stop = noop
        group.Finish = noop
        return group
    end

    set_parent(node, parent)

    return setmetatable(node, {
        __index = function(self, key)
            if key == "GetChildren" then
                return function(frame) return unpack(frame._children or {}) end
            end
            if key == "GetNumChildren" then
                return function(frame) return #(frame._children or {}) end
            end
            if key == "GetRegions" then
                return function(frame) return unpack(frame._regions or {}) end
            end
            if key == "GetNumRegions" then
                return function(frame) return #(frame._regions or {}) end
            end
            if key == "SetParent" then
                return set_parent
            end
            if key == "GetParent" then
                return function(frame) return frame._captureParent end
            end
            if key == "SetHeight" then
                return function(frame, value) frame._height = value or frame._height end
            end
            if key == "SetWidth" then
                return function(frame, value) frame._width = value or frame._width end
            end
            if key == "SetSize" then
                return function(frame, width, height)
                    frame._width = width or frame._width
                    frame._height = height or frame._height
                end
            end
            if key == "GetHeight" then
                return function(frame) return frame._height or 24 end
            end
            if key == "GetWidth" then
                return function(frame) return frame._width or 160 end
            end
            if key == "GetSize" then
                return function(frame) return frame._width or 160, frame._height or 24 end
            end
            if key == "SetScale" then
                return function(frame, value) frame._scale = value or frame._scale end
            end
            if key == "GetScale" or key == "GetEffectiveScale" then
                return function(frame) return frame._scale or 1 end
            end
            if key == "SetAlpha" then
                return function(frame, value) frame._alpha = value or frame._alpha end
            end
            if key == "GetAlpha" then
                return function(frame) return frame._alpha or 1 end
            end
            if key == "Show" then
                return function(frame) frame._shown = true end
            end
            if key == "Hide" then
                return function(frame) frame._shown = false end
            end
            if key == "SetShown" then
                return function(frame, shown) frame._shown = shown ~= false end
            end
            if key == "IsShown" or key == "IsVisible" then
                return function(frame) return frame._shown ~= false end
            end
            if key == "SetEnabled" then
                return function(frame, enabled) frame._enabled = enabled ~= false end
            end
            if key == "IsEnabled" then
                return function(frame) return frame._enabled ~= false end
            end
            if key == "SetFrameLevel" then
                return function(frame, level) frame._frameLevel = level or frame._frameLevel end
            end
            if key == "GetFrameLevel" then
                return function(frame) return frame._frameLevel or 0 end
            end
            if key == "SetFrameStrata" then
                return function(frame, strata) frame._frameStrata = strata or frame._frameStrata end
            end
            if key == "GetFrameStrata" then
                return function(frame) return frame._frameStrata or "MEDIUM" end
            end
            if key == "SetText" then
                return function(frame, value) frame._text = value or "" end
            end
            if key == "SetFormattedText" then
                return function(frame, fmt, ...)
                    local ok, value = pcall(string.format, fmt or "", ...)
                    frame._text = ok and value or (fmt or "")
                end
            end
            if key == "GetText" then
                return function(frame) return frame._text or "" end
            end
            if key == "GetStringWidth" then
                return function(frame) return #(frame._text or "") * 6 end
            end
            if key == "GetStringHeight" then
                return function() return 14 end
            end
            if key == "SetValue" then
                return function(frame, value)
                    if type(frame) ~= "table" then
                        return
                    end
                    frame._value = value
                end
            end
            if key == "GetValue" then
                return function(frame)
                    if type(frame) ~= "table" then
                        return 0
                    end
                    return frame._value or 0
                end
            end
            if key == "SetChecked" then
                return function(frame, value)
                    if type(frame) ~= "table" then
                        return
                    end
                    frame._checked = value and true or false
                end
            end
            if key == "GetChecked" then
                return function(frame)
                    if type(frame) ~= "table" then
                        return false
                    end
                    return frame._checked and true or false
                end
            end
            if key == "ClearAllPoints" then
                return function(frame) frame._points = {} end
            end
            if key == "SetPoint" then
                return function(frame, ...)
                    frame._points = frame._points or {}
                    frame._points[#frame._points + 1] = { ... }
                end
            end
            if key == "GetPoint" then
                return function(frame, index)
                    local point = (frame._points or {})[index or 1]
                    if not point then
                        return nil
                    end
                    return unpack(point)
                end
            end
            if key == "GetNumPoints" then
                return function(frame) return #(frame._points or {}) end
            end
            if key == "GetTop" or key == "GetBottom" or key == "GetLeft" or key == "GetRight" then
                return function() return 0 end
            end
            if key == "GetCenter" then
                return function() return 0, 0 end
            end
            if key == "SetScrollChild" then
                return function(frame, child) frame._scrollChild = child end
            end
            if key == "GetScrollChild" then
                return function(frame) return frame._scrollChild end
            end
            if key == "CreateAnimationGroup" then
                return create_animation_group
            end
            if type(key) == "string" and key:sub(1, 6) == "Create" then
                return function(frame)
                    return create_region(frame, key)
                end
            end
            if key == "HookScript" or key == "SetScript" or key == "RegisterEvent"
                or key == "UnregisterEvent" or key == "RegisterForClicks"
                or key == "RegisterForDrag" or key == "EnableMouse"
                or key == "EnableMouseWheel" or key == "EnableKeyboard"
                or key == "SetPropagateKeyboardInput" or key == "SetMovable"
                or key == "SetResizable" or key == "SetClampedToScreen"
                or key == "SetToplevel" or key == "SetHitRectInsets"
                or key == "SetJustifyH" or key == "SetJustifyV"
                or key == "SetWordWrap" or key == "SetNonSpaceWrap"
                or key == "SetAutoFocus" or key == "SetFont"
                or key == "SetTextInsets" or key == "SetMinMaxValues"
                or key == "SetValueStep" or key == "SetObeyStepOnDrag"
                or key == "SetOrientation" or key == "SetNormalFontObject"
                or key == "SetHighlightFontObject" or key == "SetDisabledFontObject"
                or key == "SetNormalTexture" or key == "SetPushedTexture"
                or key == "SetHighlightTexture" or key == "SetDisabledTexture"
                or key == "SetBackdrop" or key == "SetBackdropColor"
                or key == "SetBackdropBorderColor" or key == "SetColorTexture"
                or key == "SetTexture" or key == "SetAtlas" or key == "SetTexCoord"
                or key == "SetVertexColor" or key == "SetDesaturated"
                or key == "SetBlendMode" or key == "SetDrawLayer"
                or key == "SetMask" or key == "AddMaskTexture"
                or key == "SetClipsChildren" or key == "SetAllPoints"
                or key == "SetStatusBarTexture" or key == "SetStatusBarColor"
                or key == "SetHorizontalScroll" or key == "SetVerticalScroll"
                or key == "SetInsertMode" or key == "HighlightText"
                or key == "ClearFocus" or key == "SetFocus" or key == "Raise"
                or key == "StartMoving" or key == "StopMovingOrSizing"
                or key == "LockHighlight" or key == "UnlockHighlight"
                or key == "UpdateVisual" or key == "EnableDrawLayer" then
                return noop
            end
            if key == "GetObjectType" then
                return function(frame) return frame._captureKind or "Frame" end
            end
            if key == "GetName" then
                return function() return nil end
            end
            if is_stub_method_key(key) then
                return noop
            end
            return nil
        end,
    })
end

local scheduled_timers = {}

local function queue_timer(delay, callback)
    local timer = {
        delay = tonumber(delay) or 0,
        callback = callback,
        cancelled = false,
    }

    function timer:Cancel()
        self.cancelled = true
    end

    scheduled_timers[#scheduled_timers + 1] = timer
    return timer
end

local function flush_timers(max_passes)
    local passes = 0
    while #scheduled_timers > 0 and passes < (max_passes or 128) do
        passes = passes + 1
        local pending = scheduled_timers
        scheduled_timers = {}
        table.sort(pending, function(a, b)
            return (a.delay or 0) < (b.delay or 0)
        end)

        for _, timer in ipairs(pending) do
            if not timer.cancelled and type(timer.callback) == "function" then
                local ok, err = xpcall(timer.callback, debug.traceback)
                if not ok then
                    io.stderr:write("timer error: " .. tostring(err) .. "\n")
                end
            end
        end
    end
end

_G.CreateFrame = function(frame_type, _, parent)
    return create_stub_node(frame_type or "Frame", parent, false)
end

_G.UIParent = create_stub_node("UIParent", nil, false)
_G.GameTooltip = create_stub_node("GameTooltip", nil, true)
_G.ColorPickerFrame = create_stub_node("ColorPickerFrame", nil, false)
_G.CooldownViewerSettings = create_stub_node("CooldownViewerSettings", nil, false)
_G.EditModeManagerFrame = create_stub_node("EditModeManagerFrame", nil, false)
_G.GetPhysicalScreenSize = function()
    return 1920, 1080
end
_G.GetFramerate = function()
    return 144
end
_G.GetLocale = function()
    return "enUS"
end
_G.GetRealmName = function()
    return "Offline"
end
_G.GetBuildInfo = function()
    return "12.0.0", "12345", "Apr 1 2026", 120000
end
_G.GetCurrentRegion = function()
    return 1
end
_G.GetTime = function()
    return os.time()
end
_G.GetTimePreciseSec = function()
    return os.clock()
end
_G.UnitClass = function()
    return "Warrior", "WARRIOR"
end
_G.UnitClassBase = function()
    return "WARRIOR"
end
_G.UnitRace = function()
    return "Human", "Human", 1
end
_G.UnitLevel = function()
    return 80
end
_G.UnitName = function()
    return "Offline", "OfflineRealm"
end
_G.GetSpecialization = function()
    return 1
end
_G.GetNumSpecializations = function()
    return 1
end
_G.GetSpecializationInfo = function()
    return 1, "Arms", "", "", "DAMAGER"
end
_G.GetShapeshiftForm = function()
    return 0
end
_G.InCombatLockdown = function()
    return false
end
_G.issecurevariable = function()
    return true
end
_G.issecure = function()
    return true
end
_G.issecurecmd = function()
    return true
end
_G.issecurefunc = function()
    return true
end
_G.issecretvalue = function()
    return false
end
_G.canaccesstable = function()
    return true
end
_G.hooksecurefunc = function()
    return nil
end
_G.ShowUIPanel = function(frame)
    if frame and frame.Show then
        frame:Show()
    end
end
_G.HideUIPanel = function(frame)
    if frame and frame.Hide then
        frame:Hide()
    end
end
_G.PanelTemplates_SetNumTabs = function() end
_G.PanelTemplates_UpdateTabs = function() end
_G.SetPortraitToTexture = function() end
_G.GetCursorPosition = function()
    return 0, 0
end
_G.GetCurrentKeyBoardFocus = function()
    return nil
end
_G.IsControlKeyDown = function()
    return false
end
_G.GetMouseFocus = function()
    return nil
end
_G.GetCursorInfo = function()
    return nil
end
_G.ClearCursor = function() end
_G.PlaySound = function() end
_G.PlaySoundFile = function() end
_G.SetCVar = function() end
_G.GetCVar = function()
    return "0"
end
_G.GetCVarBool = function()
    return false
end
_G.C_CVar = {
    GetCVar = function(cvar)
        return _G.GetCVar(cvar)
    end,
    SetCVar = function(cvar, value)
        return _G.SetCVar(cvar, value)
    end,
}
_G.ReloadUI = function() end
_G.date = _G.date or os.date
_G.wipe = _G.wipe or function(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end
_G.tContains = _G.tContains or function(tbl, needle)
    for _, value in ipairs(tbl or {}) do
        if value == needle then
            return true
        end
    end
    return false
end
_G.geterrorhandler = function()
    return function(err)
        io.stderr:write(tostring(err) .. "\n")
    end
end
_G.SetFont = function(font_string, size)
    if font_string and font_string.SetFont then
        font_string:SetFont("Fonts\\FRIZQT__.TTF", size or 12, "")
    end
end
_G.NUM_CHAT_WINDOWS = 10
_G.GetChatWindowInfo = function(index)
    if type(index) ~= "number" then
        return nil
    end
    if index == 1 then
        return "General"
    end
    return "Chat " .. tostring(index)
end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.GetBindingKey = function()
    return nil
end
_G.SetBinding = function()
    return true
end
_G.SaveBindings = function()
    return true
end
_G.GetCurrentBindingSet = function()
    return 1
end

_G.C_Timer = {
    After = function(delay, callback)
        return queue_timer(delay, callback)
    end,
    NewTimer = function(delay, callback)
        return queue_timer(delay, callback)
    end,
}

local profile_db = make_auto_table()
profile_db.general.showOptionTooltips = true

_G.QUI = {
    db = {
        profile = profile_db,
        char = make_auto_table(),
        global = make_auto_table(),
        GetProfiles = function(self)
            local names = {}
            local profiles = self and self.sv and self.sv.profiles or {}
            for name in pairs(profiles) do
                names[#names + 1] = name
            end
            table.sort(names)
            return names
        end,
        GetCurrentProfile = function()
            return "Default"
        end,
        sv = {
            profiles = {
                Default = {},
            },
        },
    },
    GUI = {},
    QUICore = {
        db = {
            profile = profile_db,
            GetProfiles = function()
                return { "Default" }
            end,
            GetCurrentProfile = function()
                return "Default"
            end,
        },
        GetPixelSize = function()
            return 1
        end,
        Pixels = function(_, value)
            return value
        end,
    },
}

local shared_media = {
    statusbar = {
        Solid = "Interface\\Buttons\\WHITE8x8",
    },
    font = {
        ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
    },
    sound = {
        None = "None",
    },
}

local libs = {
    ["LibSharedMedia-3.0"] = {
        HashTable = function(_, kind)
            return shared_media[kind] or {}
        end,
        List = function(_, kind)
            local list = {}
            for name in pairs(shared_media[kind] or {}) do
                list[#list + 1] = name
            end
            table.sort(list)
            return list
        end,
        Fetch = function(_, kind, name)
            return (shared_media[kind] or {})[name]
        end,
        Register = function(_, kind, name, path)
            shared_media[kind] = shared_media[kind] or {}
            shared_media[kind][name] = path
        end,
    },
}

_G.LibStub = function(name, silent)
    local lib = libs[name]
    if lib then
        return lib
    end
    if silent then
        return nil
    end
    return {}
end

local ns = {
    Addon = _G.QUI.QUICore,
    Helpers = {},
    Settings = {},
    UIKit = {},
    LSM = libs["LibSharedMedia-3.0"],
}

ns.QUI_GroupFrameClickCast = {
    GetButtonNames = function()
        return {
            LeftButton = "Left Click",
            RightButton = "Right Click",
            MiddleButton = "Middle Click",
        }
    end,
    GetModifierLabels = function()
        return {
            ALT = "Alt",
            CTRL = "Ctrl",
            SHIFT = "Shift",
        }
    end,
    GetEditableBindings = function()
        return {}
    end,
    AddBinding = function()
        return true
    end,
    RemoveBinding = function() end,
    RefreshBindings = function() end,
}

ns.QUI_LayoutMode_Settings = {
    RegisterSharedProvider = function(_, key, provider)
        local providers = ns.Settings and ns.Settings.Providers
        if providers and type(providers.Register) == "function" then
            providers:Register(key, provider)
        end
    end,
}

local function load_script(path)
    local chunk, load_err = loadfile(path)
    if not chunk then
        return false, load_err
    end

    return xpcall(function()
        return chunk(ADDON_NAME, ns)
    end, debug.traceback)
end

local scripts = {}
collect_scripts_from_xml("load.xml", scripts, {})

local failures = {}
local loaded_count = 0
for _, path in ipairs(scripts) do
    path = normalize_path(path)
    if should_load_script(path) then
        local ok, err = load_script(path)
        if not ok then
            failures[#failures + 1] = {
                path = path,
                error = err,
            }
        else
            loaded_count = loaded_count + 1
        end
    end
end

flush_timers()

if #failures > 0 then
    io.stderr:write(("failed to load %d script(s):\n"):format(#failures))
    for _, failure in ipairs(failures) do
        io.stderr:write(("  %s\n%s\n"):format(failure.path, tostring(failure.error)))
    end
    os.exit(1)
end

local GUI = _G.QUI.GUI
if not GUI then
    io.stderr:write("GUI not initialized.\n")
    os.exit(1)
end

local frame = create_stub_node("Frame", nil, false)
frame.sidebar = create_stub_node("Frame", frame, false)
frame.contentArea = create_stub_node("Frame", frame, false)
frame.footerBar = create_stub_node("Frame", frame, false)
frame._tiles = {}
frame._topTiles = {}
frame._bottomTiles = {}

if type(GUI.AddFeatureTile) == "function" then
    GUI:AddFeatureTile(frame, {
        id = "welcome",
        icon = "*",
        name = "Welcome",
    })
end

local tile_order = {
    "QUI_GlobalTile",
    "QUI_UnitFramesTile",
    "QUI_GroupFramesTile",
    "QUI_ActionBarsTile",
    "QUI_CooldownManagerTile",
    "QUI_ResourceBarsTile",
    "QUI_MinimapTile",
    "QUI_AppearanceTile",
    "QUI_ChatTooltipsTile",
    "QUI_GameplayTile",
    "QUI_QoLTile",
    "QUI_HelpTile",
}

for _, key in ipairs(tile_order) do
    local tile = ns[key]
    if tile and type(tile.Register) == "function" then
        local ok, err = xpcall(function()
            tile.Register(frame)
        end, debug.traceback)
        if not ok then
            io.stderr:write(("tile registration failed for %s\n%s\n"):format(key, tostring(err)))
            os.exit(1)
        end
    end
end

local capture_errors = {}

local function build_capture_route_labels(info)
    if type(info) ~= "table" then
        return nil, nil, nil
    end

    local tab_label = info.tabName
    if (type(tab_label) ~= "string" or tab_label == "")
        and type(info.tileId) == "string" and info.tileId ~= "" then
        tab_label = info.tileId
    end

    local subtab_label = info.subTabName
    if (type(subtab_label) ~= "string" or subtab_label == "")
        and info.subPageIndex ~= nil then
        subtab_label = "Page " .. tostring(info.subPageIndex)
    end

    local section_label = info.sectionName
    if type(section_label) ~= "string" or section_label == "" then
        section_label = nil
    end

    return tab_label, subtab_label, section_label
end

local function build_capture_navigation_label(nav_type, info)
    local tab_label, subtab_label, section_label = build_capture_route_labels(info)
    if nav_type == "tab" then
        return tab_label or section_label
    end

    local parts = {}
    if tab_label and tab_label ~= "" then
        parts[#parts + 1] = tab_label
    end

    if nav_type == "subtab" then
        if subtab_label and subtab_label ~= "" then
            parts[#parts + 1] = subtab_label
        end
        return #parts > 0 and table.concat(parts, " > ") or nil
    end

    if subtab_label and subtab_label ~= "" then
        parts[#parts + 1] = subtab_label
    end
    if section_label and section_label ~= "" then
        parts[#parts + 1] = section_label
    end

    return #parts > 0 and table.concat(parts, " > ") or nil
end

local function build_capture_navigation_keywords(info)
    local tab_label, subtab_label, section_label = build_capture_route_labels(info)
    local keywords = {}
    if tab_label and tab_label ~= "" then
        keywords[#keywords + 1] = tab_label
    end
    if subtab_label and subtab_label ~= "" then
        keywords[#keywords + 1] = subtab_label
    end
    if section_label and section_label ~= "" then
        keywords[#keywords + 1] = section_label
    end
    return keywords
end

local function register_capture_setting_entry(entry)
    local context = GUI._searchContext or {}
    if type(entry) ~= "table" or type(entry.label) ~= "string" or entry.label == "" then
        return nil
    end

    return GUI:RegisterStaticSettingEntry({
        label = entry.label,
        widgetType = entry.widgetType,
        tabIndex = context.tabIndex,
        tabName = context.tabName,
        subTabIndex = context.subTabIndex,
        subTabName = context.subTabName,
        sectionName = context.sectionName,
        tileId = context.tileId,
        subPageIndex = context.subPageIndex,
        featureId = context.featureId,
        providerKey = context.providerKey,
        category = context.category,
        widgetDescriptor = entry.widgetDescriptor,
        keywords = entry.keywords,
        description = entry.description,
        relatedTo = entry.relatedTo,
    })
end

local function create_captured_widget_stub(kind)
    local stub = create_stub_node(kind or "Frame", nil, false)

    if kind == "toggle" or kind == "toggle_inverted" then
        stub.track = create_stub_node("Frame", stub, false)
        stub.knob = create_stub_node("Texture", stub, true)
    elseif kind == "dropdown" then
        stub.button = create_stub_node("Button", stub, false)
        stub._children[1] = stub.button
    elseif kind == "editbox" then
        stub.field = create_stub_node("Frame", stub, false)
        stub.editBox = create_stub_node("EditBox", stub.field, false)
    elseif kind == "slider" then
        stub.slider = create_stub_node("Slider", stub, false)
        stub.editBox = create_stub_node("EditBox", stub, false)
        stub.trackFill = create_stub_node("Texture", stub.slider, true)
        stub.thumbFrame = create_stub_node("Texture", stub.slider, true)
        stub.trackContainer = stub.slider
    elseif kind == "colorpicker" then
        stub.swatch = create_stub_node("Texture", stub, true)
    end

    return stub
end

local function create_captured_search_widget(kind, label, dbKey, dbTable, extra, registryInfo)
    register_capture_setting_entry({
        label = label,
        widgetType = kind,
        widgetDescriptor = GUI:BuildSearchWidgetDescriptor(kind, dbKey, dbTable, extra),
        keywords = registryInfo and registryInfo.keywords or nil,
        description = registryInfo and registryInfo.description or nil,
        relatedTo = registryInfo and registryInfo.relatedTo or nil,
    })
    return create_captured_widget_stub(kind)
end

local function install_search_capture_overrides()
    GUI.RegisterSearchNavigation = function(self, navType, info)
        if type(info) ~= "table" then
            return nil
        end

        local label = build_capture_navigation_label(navType, info)
        if type(label) ~= "string" or label == "" then
            return nil
        end

        return self:RegisterStaticNavigationEntry({
            navType = navType,
            label = label,
            tabIndex = info.tabIndex,
            tabName = info.tabName,
            subTabIndex = info.subTabIndex,
            subTabName = info.subTabName,
            sectionName = info.sectionName,
            tileId = info.tileId,
            subPageIndex = info.subPageIndex,
            featureId = info.featureId,
            keywords = build_capture_navigation_keywords(info),
        })
    end

    GUI.RegisterSearchSettingWidget = function(self, entry)
        return register_capture_setting_entry(entry)
    end

    GUI.CreateFormToggle = function(self, parent, label, dbKey, dbTable, onChange, registryInfo)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("toggle", label, dbKey, dbTable, nil, registryInfo)
    end

    GUI.CreateFormToggleInverted = function(self, parent, label, dbKey, dbTable, onChange, registryInfo)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("toggle_inverted", label, dbKey, dbTable, nil, registryInfo)
    end

    GUI.CreateFormEditBox = function(self, parent, label, dbKey, dbTable, onChange, options, registryInfo)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("editbox", label, dbKey, dbTable, {
            options = options or {},
        }, registryInfo)
    end

    GUI.CreateFormSlider = function(self, parent, label, min, max, step, dbKey, dbTable, onChange, options, registryInfo)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("slider", label, dbKey, dbTable, {
            min = min,
            max = max,
            step = step,
            options = options or {},
        }, registryInfo)
    end

    GUI.CreateFormDropdown = function(self, parent, label, options, dbKey, dbTable, onChange, registryInfo, opts)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("dropdown", label, dbKey, dbTable, {
            options = options,
            dropdownOptions = opts or {},
        }, registryInfo)
    end

    GUI.CreateFormColorPicker = function(self, parent, label, dbKey, dbTable, onChange, options, registryInfo)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("colorpicker", label, dbKey, dbTable, {
            options = options or {},
        }, registryInfo)
    end
end

local function build_search_capture_queue()
    local queue = {}
    local settings = ns.Settings
    local registry = settings and settings.Registry
    if not registry or type(registry.IterateFeatures) ~= "function" then
        return queue
    end

    for featureId, feature in registry:IterateFeatures() do
        if type(feature) == "table" then
            queue[#queue + 1] = {
                featureId = featureId,
                feature = feature,
            }
        end
    end

    return queue
end

local function build_feature_search_context(feature)
    if type(feature) ~= "table" then
        return {}
    end

    local context = {}
    local search_context = type(feature.searchContext) == "table" and feature.searchContext or nil
    if search_context then
        context.tabIndex = search_context.tabIndex
        context.tabName = search_context.tabName
        context.subTabIndex = search_context.subTabIndex
        context.subTabName = search_context.subTabName
        context.sectionName = search_context.sectionName
    end

    local settings = ns.Settings
    local nav = settings and settings.Nav
    local route = nav and type(nav.GetRoute) == "function" and nav:GetRoute(feature) or feature.nav
    if type(route) == "table" then
        context.tileId = route.tileId
        context.subPageIndex = route.subPageIndex
    end

    context.featureId = feature.id
    context.providerKey = feature.providerKey
    context.category = feature.category

    return context
end

local function create_timer_stub()
    return {
        Cancel = function() end,
    }
end

local function capture_search_feature(feature)
    if type(feature) ~= "table" then
        return false
    end

    local settings = ns.Settings
    local renderer = settings and settings.Renderer
    if not renderer or type(renderer.RenderFeature) ~= "function" then
        return false
    end

    local original_after = C_Timer and C_Timer.After or nil
    local original_new_timer = C_Timer and C_Timer.NewTimer or nil
    local context = build_feature_search_context(feature)
    local host = create_stub_node("Frame", nil, false)
    host:SetSize(760, 1)

    if C_Timer then
        C_Timer.After = function()
            return create_timer_stub()
        end
        C_Timer.NewTimer = function()
            return create_timer_stub()
        end
    end

    GUI:ClearSearchContext()
    local ok, err = xpcall(function()
        GUI:SetSearchContext(context)
        if context.sectionName then
            GUI:SetSearchSection(context.sectionName)
        end
        renderer:RenderFeature(feature, host, {
            surface = "tile",
            width = 760,
            tileLayout = true,
            includePosition = true,
            providerKey = feature.providerKey,
        })
        GUI:ClearSearchContext()
    end, debug.traceback)
    GUI:ClearSearchContext()

    if C_Timer then
        C_Timer.After = original_after
        C_Timer.NewTimer = original_new_timer
    end

    if not ok then
        capture_errors[#capture_errors + 1] = {
            featureId = feature.id,
            providerKey = feature.providerKey,
            error = err,
        }
        return false
    end

    return true
end

local function capture_all_search_features()
    local settings = ns.Settings
    local renderer = settings and settings.Renderer
    local registry = settings and settings.Registry
    if not renderer or type(renderer.RenderFeature) ~= "function"
        or not registry or type(registry.IterateFeatures) ~= "function" then
        return false
    end

    GUI:ResetStaticSearchIndex()

    for _, step in ipairs(build_search_capture_queue()) do
        if step and step.feature then
            capture_search_feature(step.feature)
        end
    end

    return #capture_errors == 0
end

install_search_capture_overrides()
capture_all_search_features()

if type(GUI.SeedStaticSearchRoutesFromTiles) == "function" then
    GUI:SeedStaticSearchRoutesFromTiles(frame)
end

-- Phase 1+ Modules Control Center: emit moduleToggle navigation entries
-- for features that declare moduleEntry. These power the [Module] badge +
-- inline pill rendering in the global search dropdown (see Task 9).
local function emit_module_toggle_entries()
    local settings = ns.Settings
    local registry = settings and settings.Registry
    if not registry or type(registry.IterateFeatures) ~= "function" then
        return 0
    end

    local emitted = 0
    for featureId, feature in registry:IterateFeatures() do
        local entry = type(feature) == "table" and feature.moduleEntry
        if type(entry) == "table" and not feature.noSearch then
            local label = entry.label or feature.name or featureId
            local caption = entry.caption or ""
            local group = entry.group or "Modules"
            GUI:RegisterSearchNavigation("moduleToggle", {
                label = label,
                featureId = featureId,
                tileId = "global",
                subPageIndex = 3,    -- Modules sub-page index in General tile's
                                      -- subPages array. See options/tiles/global.lua
                                      -- — order is profiles, pinnedGlobals, modules,
                                      -- importExport, thirdParty, clickCast.
                keywords = { label, caption, group, "module" },
            })
            emitted = emitted + 1
        end
    end
    return emitted
end

local emitted_module_entries = emit_module_toggle_entries()

local function copy_table(source)
    if type(source) ~= "table" then
        return source
    end
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = copy_table(value)
    end
    return copy
end

local function entry_sort_key(entry)
    return table.concat({
        entry.tileId or "",
        tostring(entry.subPageIndex or 0),
        entry.sectionName or "",
        entry.label or "",
        entry.navType or "",
        entry.featureId or "",
        entry.providerKey or "",
    }, "\31")
end

local settings_entries = {}
for index, entry in ipairs(GUI.StaticSettingsRegistry or {}) do
    settings_entries[index] = copy_table(entry)
end
table.sort(settings_entries, function(a, b)
    return entry_sort_key(a) < entry_sort_key(b)
end)

local navigation_entries = {}
for index, entry in ipairs(GUI.StaticNavigationRegistry or {}) do
    navigation_entries[index] = copy_table(entry)
end
table.sort(navigation_entries, function(a, b)
    return entry_sort_key(a) < entry_sort_key(b)
end)

local function is_array(value)
    if type(value) ~= "table" then
        return false
    end

    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false
        end
        count = count + 1
    end

    return count == #value
end

local function sorted_keys(tbl)
    local keys = {}
    for key in pairs(tbl) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then
            return ta < tb
        end
        if ta == "number" or ta == "string" then
            return a < b
        end
        return tostring(a) < tostring(b)
    end)
    return keys
end

local function serialize(value, indent)
    indent = indent or ""
    local value_type = type(value)
    if value_type == "string" then
        return string.format("%q", value)
    end
    if value_type == "number" or value_type == "boolean" then
        return tostring(value)
    end
    if value_type == "nil" then
        return "nil"
    end
    if value_type ~= "table" then
        return "nil"
    end

    local next_indent = indent .. "    "
    local parts = { "{" }

    if is_array(value) then
        for index = 1, #value do
            parts[#parts + 1] = next_indent .. serialize(value[index], next_indent) .. ","
        end
    else
        for _, key in ipairs(sorted_keys(value)) do
            parts[#parts + 1] = next_indent
                .. "["
                .. serialize(key, next_indent)
                .. "] = "
                .. serialize(value[key], next_indent)
                .. ","
        end
    end

    parts[#parts + 1] = indent .. "}"
    return table.concat(parts, "\n")
end

local cache = {
    version = 1,
    settings = settings_entries,
    navigation = navigation_entries,
}

if #capture_errors > 0 then
    io.stderr:write(("search capture reported %d error(s):\n"):format(#capture_errors))
    for _, item in ipairs(capture_errors) do
        io.stderr:write(("  [%s] %s\n"):format(
            tostring(item.featureId or item.providerKey or "?"),
            tostring(item.error)
        ))
    end
    os.exit(1)
end

if #settings_entries == 0 or #navigation_entries == 0 then
    io.stderr:write("generated search cache is unexpectedly empty.\n")
    os.exit(1)
end

local output = table.concat({
    "local ADDON_NAME, ns = ...",
    "",
    "ns.QUI_SearchCache = " .. serialize(cache),
    "",
    "local GUI = QUI and QUI.GUI",
    "if GUI and type(GUI.ApplyGeneratedSearchCache) == \"function\" then",
    "    GUI:ApplyGeneratedSearchCache(ns.QUI_SearchCache)",
    "end",
    "",
}, "\n")

local handle = assert(io.open(OUTPUT_PATH, "w"))
handle:write(output)
handle:close()

print(("Loaded %d script(s). Generated %d settings entries and %d navigation entries (%d module toggles) into %s."):format(
    loaded_count,
    #settings_entries,
    #navigation_entries,
    emitted_module_entries,
    OUTPUT_PATH
))
