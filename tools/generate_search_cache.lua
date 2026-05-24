local ADDON_NAME = "QUI"
local ROOT = "."
local OUTPUT_PATH = "QUI_Options/search_cache.lua"
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

-- QUI_Options/options.xml lives in a sibling LoD addon. Local option UI
-- scripts live under QUI_Options in this repo; references to the main addon
-- use "..\QUI\..." and are stripped to repo-relative paths for headless runs.
local function collect_qui_options_scripts(out, seen)
    local xml_path = normalize_path("QUI_Options/options.xml")
    if seen[xml_path] then
        return
    end
    seen[xml_path] = true

    local probe = io.open(xml_path, "r")
    if not probe then
        return
    end
    probe:close()

    local emitted = {}
    for _, existing in ipairs(out) do
        emitted[existing] = true
    end

    for _, line in ipairs(read_lines(xml_path)) do
        local script_path = line:match('<Script file="([^"]+)"')
        if script_path then
            local normalized = normalize_path(script_path)
            local repo_path = normalized:match("^%.%./QUI/(.+)$")
            if repo_path then
                repo_path = normalize_path(repo_path)
            else
                repo_path = normalize_path(join_path(xml_path, normalized))
            end
            if not emitted[repo_path] then
                emitted[repo_path] = true
                out[#out + 1] = repo_path
            end
        end
    end
end

local function should_load_script(path)
    path = normalize_path(path)

    if path == "init.lua" or path == OUTPUT_PATH then
        return false
    end
    if path:match("^libs/") or path:match("^importstrings/") then
        return false
    end
    if path == "QUI_Options/blizzard_options.lua" then
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

    if path == "modules/layout/layoutmode_utils.lua" then
        return true
    end
    if path:match("^modules/.+/settings/") then
        return true
    end

    if path:match("^QUI_Options/") then
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

local function is_icon_only_button_label(text)
    if type(text) ~= "string" or text == "" then
        return true
    end
    if #text <= 2 and not text:match("[%w]") then
        return true
    end
    return false
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
local script_xml_seen = {}
collect_scripts_from_xml("load.xml", scripts, script_xml_seen)
collect_qui_options_scripts(scripts, script_xml_seen)

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

-- Tile registration deferred until after install_search_capture_overrides()
-- (see end of file) so the alias-emit wrapper actually intercepts the
-- RegisterFeatureTile / AddFeatureTile calls those tiles make.

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

local function emit_alias_entries(aliases, tile_id, sub_page_index, feature_id)
    if type(aliases) ~= "table" then
        return
    end
    for _, alias in ipairs(aliases) do
        if type(alias) == "string" and alias ~= "" then
            GUI:RegisterStaticNavigationEntry({
                navType = "alias",
                label = alias,
                tileId = tile_id,
                subPageIndex = sub_page_index,
                featureId = feature_id,
                keywords = { alias },
            })
        end
    end
end

local function emit_tile_search_aliases(tile_config)
    if type(tile_config) ~= "table" then
        return
    end

    -- Top-level aliases (for single-page tiles like welcome that have no subPages array).
    emit_alias_entries(tile_config.searchAliases, tile_config.id, nil, tile_config.featureId)

    if type(tile_config.subPages) == "table" then
        for sub_page_index, sub_page in ipairs(tile_config.subPages) do
            if type(sub_page) == "table" then
                emit_alias_entries(sub_page.searchAliases, tile_config.id, sub_page_index, sub_page.featureId)
            end
        end
    end
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
        surfaceTabKey = context.surfaceTabKey,
        surfaceUnitKey = context.surfaceUnitKey,
        widgetDescriptor = entry.widgetDescriptor,
        keywords = entry.keywords,
        description = entry.description,
        relatedTo = entry.relatedTo,
    })
end

local function create_captured_widget_stub(kind)
    local stub = create_stub_node(kind or "Frame", nil, false)

    if kind == "toggle" or kind == "toggle_inverted" or kind == "checkbox" or kind == "checkbox_inverted" then
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

local function copy_capture_entry(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local copy = {}
    for key, value in pairs(entry) do
        copy[key] = value
    end
    return copy
end

local function register_widget_row_capture(widget, label)
    if type(widget) ~= "table"
        or type(label) ~= "string"
        or label == ""
        or type(widget._quiSearchCaptureEntry) ~= "table" then
        return nil
    end

    if widget._quiSearchCaptureRegisteredLabel == label then
        return nil
    end

    local entry = copy_capture_entry(widget._quiSearchCaptureEntry)
    if not entry then
        return nil
    end

    entry.label = label
    widget._widgetLabel = label
    widget._quiSearchCaptureRegisteredLabel = label
    return register_capture_setting_entry(entry)
end

local function create_captured_search_widget(kind, label, dbKey, dbTable, extra, registryInfo)
    local entry = {
        label = label,
        widgetType = kind,
        widgetDescriptor = GUI:BuildSearchWidgetDescriptor(kind, dbKey, dbTable, extra),
        keywords = registryInfo and registryInfo.keywords or nil,
        description = registryInfo and registryInfo.description or nil,
        relatedTo = registryInfo and registryInfo.relatedTo or nil,
    }

    register_capture_setting_entry(entry)

    local stub = create_captured_widget_stub(kind)
    stub._quiSearchCaptureEntry = entry
    stub._widgetLabel = label
    return stub
end

local function register_manual_static_setting(context, label, widget_type, db_path, db_key, extra)
    if type(context) ~= "table" or type(label) ~= "string" or label == "" then
        return nil
    end

    local descriptor = nil
    if widget_type and db_path and db_key ~= nil then
        descriptor = {
            kind = widget_type,
            dbPath = db_path,
            dbKey = db_key,
            providerKey = context.providerKey,
        }
        if type(extra) == "table" then
            for key, value in pairs(extra) do
                descriptor[key] = value
            end
        end
    end

    return GUI:RegisterStaticSettingEntry({
        label = label,
        widgetType = widget_type,
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
        surfaceTabKey = context.surfaceTabKey,
        surfaceUnitKey = context.surfaceUnitKey,
        widgetDescriptor = descriptor,
        keywords = context.keywords,
    })
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
            providerKey = info.providerKey,
            category = info.category,
            surfaceTabKey = info.surfaceTabKey,
            surfaceUnitKey = info.surfaceUnitKey,
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

    GUI.CreateFormCheckbox = function(self, parent, label, dbKey, dbTable, _onChange, registryInfo)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("checkbox", label, dbKey, dbTable, nil, registryInfo)
    end

    GUI.CreateFormCheckboxInverted = function(self, parent, label, dbKey, dbTable, _onChange, registryInfo)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("checkbox_inverted", label, dbKey, dbTable, nil, registryInfo)
    end

    GUI.CreateCheckbox = function(self, parent, label, dbKey, dbTable, _onChange, description)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("checkbox", label, dbKey, dbTable, nil, { description = description })
    end

    GUI.CreateCheckboxCentered = function(self, parent, label, dbKey, dbTable, _onChange, description)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("checkbox", label, dbKey, dbTable, nil, { description = description })
    end

    GUI.CreateCheckboxInverted = function(self, parent, label, dbKey, dbTable, _onChange, description)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("checkbox_inverted", label, dbKey, dbTable, nil, { description = description })
    end

    GUI.CreateAccentCheckbox = function(self, parent, options)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        local opts = type(options) == "table" and options or {}
        return create_captured_search_widget("checkbox", opts.label, opts.dbKey, opts.dbTable, nil, { description = opts.description })
    end

    GUI.CreateSlider = function(self, parent, label, min, max, step, dbKey, dbTable, _onChange, options)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        local opts = type(options) == "table" and options or {}
        return create_captured_search_widget("slider", label, dbKey, dbTable, {
            min = min, max = max, step = step, options = opts,
        }, { description = opts.description })
    end

    GUI.CreateDropdown = function(self, parent, label, options, dbKey, dbTable, _onChange, description)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("dropdown", label, dbKey, dbTable, {
            options = options,
        }, { description = description })
    end

    GUI.CreateDropdownFullWidth = function(self, parent, label, options, dbKey, dbTable, _onChange, description)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("dropdown", label, dbKey, dbTable, {
            options = options,
        }, { description = description })
    end

    GUI.CreateColorPicker = function(self, parent, label, dbKey, dbTable, _onChange, description)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("colorpicker", label, dbKey, dbTable, nil, { description = description })
    end

    GUI.CreateColorPickerCentered = function(self, parent, label, dbKey, dbTable, _onChange, description)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("colorpicker", label, dbKey, dbTable, nil, { description = description })
    end

    GUI.CreateButton = function(self, parent, text, _width, _height, _onClick, variant)
        if is_icon_only_button_label(text) then
            return create_stub_node("Button", parent, false)
        end
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        local entry = {
            label = text,
            widgetType = "action_button",
            widgetDescriptor = { kind = "action_button", variant = variant },
        }
        register_capture_setting_entry(entry)
        local stub = create_stub_node("Button", parent, false)
        stub._quiSearchCaptureEntry = entry
        stub._widgetLabel = text
        return stub
    end

    local options_api = ns.QUI_Options
    if options_api and type(options_api.BuildSettingRow) == "function" then
        local original_build_setting_row = options_api.BuildSettingRow
        options_api.BuildSettingRow = function(parent, labelText, widget, desc)
            register_widget_row_capture(widget, labelText)
            return original_build_setting_row(parent, labelText, widget, desc)
        end
    end

    if options_api and type(options_api.RegisterFeatureTile) == "function" then
        local original_register_feature_tile = options_api.RegisterFeatureTile
        options_api.RegisterFeatureTile = function(tile_frame, tile_config)
            emit_tile_search_aliases(tile_config)
            return original_register_feature_tile(tile_frame, tile_config)
        end
    end

    -- Welcome tile (and any future top-level tile registered directly via
    -- AddFeatureTile rather than through Opts.RegisterFeatureTile) needs its
    -- own hook because the RegisterFeatureTile wrapper above never sees it.
    if type(GUI.AddFeatureTile) == "function" then
        local original_add_feature_tile = GUI.AddFeatureTile
        GUI.AddFeatureTile = function(self, tile_frame, tile_config)
            emit_tile_search_aliases(tile_config)
            return original_add_feature_tile(self, tile_frame, tile_config)
        end
    end

    local original_set_search_context = GUI.SetSearchContext
    if type(original_set_search_context) == "function" then
        GUI.SetSearchContext = function(self, context)
            -- Preserve featureId, providerKey, and category across partial context
            -- updates from imperative pages — these are the identity fields most
            -- often dropped by mid-build SetSearchContext calls. Other context
            -- fields (tab/section labels) are intentionally allowed to change.
            local preserved_featureId = self._searchContext and self._searchContext.featureId
            local preserved_providerKey = self._searchContext and self._searchContext.providerKey
            local preserved_category = self._searchContext and self._searchContext.category

            -- Call original to set the new context
            local result = original_set_search_context(self, context)

            -- Restore preserved fields if they weren't explicitly set in the new context
            if type(self._searchContext) == "table" then
                if preserved_featureId and not context.featureId then
                    self._searchContext.featureId = preserved_featureId
                end
                if preserved_providerKey and not context.providerKey then
                    self._searchContext.providerKey = preserved_providerKey
                end
                if preserved_category and not context.category then
                    self._searchContext.category = preserved_category
                end
            end
            return result
        end
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

local feature_keywords_by_id = {}

local function collect_feature_keywords()
    local settings = ns.Settings
    local registry = settings and settings.Registry
    if not registry or type(registry.IterateFeatures) ~= "function" then
        return
    end

    for featureId, feature in registry:IterateFeatures() do
        if type(feature) == "table" and type(feature.keywords) == "table" then
            feature_keywords_by_id[featureId] = feature.keywords
        end
    end
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

local CDM_SEARCH_CAPTURE_CONTAINERS = {
    "essential",
    "utility",
    "buff",
    "trackedBar",
}

local CDM_SEARCH_CAPTURE_TABS = {
    { key = "layout", label = "Appearance", method = "RenderLayoutTab" },
    { key = "effects", label = "Effects", method = "RenderEffectsTab" },
    { key = "keybinds", label = "Keybinds", method = "RenderKeybindsTab" },
}

local function capture_cdm_settings_tabs()
    local schema = ns.QUI_CooldownManagerSettingsSchema
    if type(schema) ~= "table" then
        return true
    end

    for _, container_key in ipairs(CDM_SEARCH_CAPTURE_CONTAINERS) do
        for _, tab in ipairs(CDM_SEARCH_CAPTURE_TABS) do
            local render = schema[tab.method]
            if type(render) == "function" then
                local host = create_stub_node("Frame", nil, false)
                host:SetSize(760, 1)

                GUI:ClearSearchContext()
                local ok, err = xpcall(function()
                    GUI:SetSearchContext({
                        tabIndex = 4,
                        tabName = "Cooldown Manager",
                        subTabIndex = 0,
                        subTabName = tab.label,
                        tileId = "cooldown_manager",
                        subPageIndex = 1,
                        featureId = "cooldownManagerContainersPage",
                        providerKey = container_key,
                        category = "cooldowns",
                        surfaceTabKey = tab.key,
                    })
                    render(host, container_key)
                    GUI:ClearSearchContext()
                end, debug.traceback)
                GUI:ClearSearchContext()

                if not ok then
                    capture_errors[#capture_errors + 1] = {
                        featureId = "cooldownManagerContainersPage",
                        providerKey = container_key .. ":" .. tab.key,
                        error = err,
                    }
                end
            end
        end
    end

    return #capture_errors == 0
end

local GROUP_FRAMES_SEARCH_CAPTURE_CONTEXTS = {
    { key = "party", providerKey = "partyFrames" },
    { key = "raid", providerKey = "raidFrames" },
}

local GROUP_FRAMES_SEARCH_CAPTURE_TABS = {
    { key = "general", label = "General", method = "RenderGeneralTab", subTabIndex = 1 },
    { key = "appearance", label = "Appearance", method = "RenderAppearanceTab", subTabIndex = 2 },
    { key = "layout", label = "Layout", method = "RenderLayoutTab", subTabIndex = 3 },
    { key = "dimensions", label = "Dimensions", method = "RenderDimensionsTab", subTabIndex = 4 },
    { key = "rangepet", label = "Range & Pet", method = "RenderRangePetTab", subTabIndex = 5 },
    { key = "spotlight", label = "Spotlight", method = "RenderSpotlightTab", subTabIndex = 6, raidOnly = true },
    { key = "health", label = "Health", method = "RenderHealthTab", subTabIndex = 7 },
    { key = "power", label = "Power", method = "RenderPowerTab", subTabIndex = 8 },
    { key = "name", label = "Name", method = "RenderNameTab", subTabIndex = 9 },
    { key = "buffs", label = "Buffs", method = "RenderBuffsTab", subTabIndex = 10 },
    { key = "debuffs", label = "Debuffs", method = "RenderDebuffsTab", subTabIndex = 11 },
    { key = "indicators", label = "Indicators", method = "RenderIndicatorsTab", subTabIndex = 12 },
    { key = "auraIndicators", label = "Aura Ind.", method = "RenderAuraIndicatorsTab", subTabIndex = 13 },
    { key = "pinnedAuras", label = "Pinned", method = "RenderPinnedAurasTab", subTabIndex = 14 },
    { key = "privateAuras", label = "Priv. Auras", method = "RenderPrivateAurasTab", subTabIndex = 15 },
    { key = "healer", label = "Healer", method = "RenderHealerTab", subTabIndex = 16 },
    { key = "defensive", label = "Defensive", method = "RenderDefensiveTab", subTabIndex = 17 },
}

local function capture_group_frames_settings_tabs()
    local schema = ns.QUI_GroupFramesSettingsSchema
    if type(schema) ~= "table" then
        return true
    end

    for _, group_context in ipairs(GROUP_FRAMES_SEARCH_CAPTURE_CONTEXTS) do
        for _, tab in ipairs(GROUP_FRAMES_SEARCH_CAPTURE_TABS) do
            local render = schema[tab.method]
            if type(render) == "function" and not (tab.raidOnly and group_context.key ~= "raid") then
                local host = create_stub_node("Frame", nil, false)
                host:SetSize(760, 1)

                GUI:ClearSearchContext()
                local ok, err = xpcall(function()
                    GUI:SetSearchContext({
                        tabIndex = 6,
                        tabName = "Group Frames",
                        subTabIndex = tab.subTabIndex,
                        subTabName = tab.label,
                        tileId = "group_frames",
                        subPageIndex = 2,
                        featureId = "groupFramesPage",
                        providerKey = group_context.providerKey,
                        category = "frames",
                        surfaceTabKey = tab.key,
                    })
                    render(host, group_context.key)
                    GUI:ClearSearchContext()
                end, debug.traceback)
                GUI:ClearSearchContext()

                if not ok then
                    capture_errors[#capture_errors + 1] = {
                        featureId = "groupFramesPage",
                        providerKey = group_context.providerKey .. ":" .. tab.key,
                        error = err,
                    }
                end
            end
        end
    end

    return #capture_errors == 0
end

local UNIT_FRAMES_SEARCH_CAPTURE_UNITS = {
    { key = "player", label = "Player" },
    { key = "target", label = "Target" },
    { key = "targettarget", label = "Target of Target" },
    { key = "pet", label = "Pet" },
    { key = "focus", label = "Focus" },
    { key = "boss", label = "Boss" },
}

local UNIT_FRAMES_SEARCH_CAPTURE_TABS = {
    { key = "frame", label = "Frame", method = "RenderFrameTab" },
    { key = "bars", label = "Bars", method = "RenderBarsTab" },
    { key = "castbar", label = "Castbar", method = "RenderCastbarTab" },
    { key = "text", label = "Text", method = "RenderTextTab" },
    { key = "icons", label = "Icons", method = "RenderIconsTab" },
    { key = "indicators", label = "Indicators", method = "RenderIndicatorsTab" },
    { key = "portrait", label = "Portrait", method = "RenderPortraitTab" },
    { key = "privateAuras", label = "Priv. Auras", method = "RenderPrivateAurasTab" },
}

local function capture_unit_frames_settings_tabs()
    local schema = ns.QUI_UnitFramesSettingsSchema
    if type(schema) ~= "table" then
        return true
    end

    for _, unit_context in ipairs(UNIT_FRAMES_SEARCH_CAPTURE_UNITS) do
        for _, tab in ipairs(UNIT_FRAMES_SEARCH_CAPTURE_TABS) do
            local render = schema[tab.method]
            if type(render) == "function" then
                local host = create_stub_node("Frame", nil, false)
                host:SetSize(760, 1)

                GUI:ClearSearchContext()
                local ok, err = xpcall(function()
                    GUI:SetSearchContext({
                        tabIndex = 5,
                        tabName = "Unit Frames",
                        subTabIndex = 0,
                        subTabName = tab.label,
                        tileId = "unit_frames",
                        subPageIndex = 1,
                        featureId = "unitFramesPage",
                        category = "frames",
                        surfaceTabKey = tab.key,
                        surfaceUnitKey = unit_context.key,
                    })
                    render(host, unit_context.key)
                    GUI:ClearSearchContext()
                end, debug.traceback)
                GUI:ClearSearchContext()

                if not ok then
                    capture_errors[#capture_errors + 1] = {
                        featureId = "unitFramesPage",
                        providerKey = unit_context.key .. ":" .. tab.key,
                        error = err,
                    }
                end
            end
        end
    end

    return #capture_errors == 0
end

local ACTION_BAR_ANCHOR_OPTIONS = {
    { value = "TOPLEFT", text = "Top Left" },
    { value = "TOP", text = "Top" },
    { value = "TOPRIGHT", text = "Top Right" },
    { value = "LEFT", text = "Left" },
    { value = "CENTER", text = "Center" },
    { value = "RIGHT", text = "Right" },
    { value = "BOTTOMLEFT", text = "Bottom Left" },
    { value = "BOTTOM", text = "Bottom" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
}

local ACTION_BAR_ORIENTATION_OPTIONS = {
    { value = "horizontal", text = "Horizontal" },
    { value = "vertical", text = "Vertical" },
}

local ACTION_BAR_FLYOUT_OPTIONS = {
    { value = "AUTO", text = "Auto" },
    { value = "UP", text = "Up" },
    { value = "DOWN", text = "Down" },
    { value = "LEFT", text = "Left" },
    { value = "RIGHT", text = "Right" },
}

local ACTION_BAR_PRESSED_OPTIONS = {
    { value = "off", text = "Off" },
    { value = "blizzard", text = "Default" },
    { value = "qui", text = "QUI" },
}

local ACTION_BAR_TOTEM_GROW_OPTIONS = {
    { value = "RIGHT", text = "Right" },
    { value = "LEFT", text = "Left" },
    { value = "UP", text = "Up" },
    { value = "DOWN", text = "Down" },
}

local ACTION_BAR_PER_BAR_CAPTURE_BARS = {
    { key = "bar1", label = "Bar 1", dbKey = "bar1", layout = true, skinnable = true, flyout = true, hidePageArrow = true },
    { key = "bar2", label = "Bar 2", dbKey = "bar2", layout = true, skinnable = true, flyout = true, toggleable = true },
    { key = "bar3", label = "Bar 3", dbKey = "bar3", layout = true, skinnable = true, flyout = true, toggleable = true },
    { key = "bar4", label = "Bar 4", dbKey = "bar4", layout = true, skinnable = true, flyout = true, toggleable = true },
    { key = "bar5", label = "Bar 5", dbKey = "bar5", layout = true, skinnable = true, flyout = true, toggleable = true },
    { key = "bar6", label = "Bar 6", dbKey = "bar6", layout = true, skinnable = true, flyout = true, toggleable = true },
    { key = "bar7", label = "Bar 7", dbKey = "bar7", layout = true, skinnable = true, flyout = true, toggleable = true },
    { key = "bar8", label = "Bar 8", dbKey = "bar8", layout = true, skinnable = true, flyout = true, toggleable = true },
    { key = "stanceBar", label = "Stance Bar", dbKey = "stance", layout = true, skinnable = true },
    { key = "petBar", label = "Pet Bar", dbKey = "pet", layout = true, skinnable = true },
    { key = "microMenu", label = "Micro Menu", dbKey = "microbar", layout = true, clickthrough = true },
    { key = "bagBar", label = "Bag Bar", dbKey = "bags", layout = true, clickthrough = true },
}

local function capture_action_bar_per_bar_setting(bar, section, label, widget_type, db_path, db_key, extra)
    register_manual_static_setting({
        tabIndex = 8,
        tabName = "Action Bars",
        subTabIndex = 3,
        subTabName = "Per-Bar",
        sectionName = bar.label .. " - " .. section,
        tileId = "action_bars",
        subPageIndex = 3,
        featureId = "actionBarsPerBar",
        providerKey = bar.key,
        category = "frames",
        keywords = { label, bar.label, section, "Action Bars", "Per-Bar" },
    }, label, widget_type, db_path, db_key, extra)
end

local function capture_action_bar_text_section(bar, bar_path, section, prefix, toggle_label)
    local lower_key = section:gsub("%s+", "")
    capture_action_bar_per_bar_setting(bar, section, toggle_label, "toggle", bar_path, prefix.show)
    capture_action_bar_per_bar_setting(bar, section, "Font Size", "slider", bar_path, prefix.fontSize, { min = 8, max = section == "Stack Count" and 20 or 18, step = 1 })
    capture_action_bar_per_bar_setting(bar, section, "Anchor", "dropdown", bar_path, prefix.anchor, { options = ACTION_BAR_ANCHOR_OPTIONS })
    capture_action_bar_per_bar_setting(bar, section, "X-Offset", "slider", bar_path, prefix.offsetX, { min = -20, max = 20, step = 1 })
    capture_action_bar_per_bar_setting(bar, section, "Y-Offset", "slider", bar_path, prefix.offsetY, { min = -20, max = 20, step = 1 })
    capture_action_bar_per_bar_setting(bar, section, "Color", "colorpicker", bar_path, prefix.color)
    return lower_key
end

local function capture_action_bar_per_bar_settings()
    for _, bar in ipairs(ACTION_BAR_PER_BAR_CAPTURE_BARS) do
        local bar_path = "profile.actionBars.bars." .. bar.dbKey
        local layout_path = bar_path .. ".ownedLayout"

        if bar.toggleable then
            capture_action_bar_per_bar_setting(bar, "Bar", "Enabled", "toggle", bar_path, "enabled")
        end
        if bar.hidePageArrow then
            capture_action_bar_per_bar_setting(bar, "Bar", "Hide Default Paging Arrow", "toggle", bar_path, "hidePageArrow")
        end
        if bar.clickthrough then
            capture_action_bar_per_bar_setting(bar, "Bar", "Clickthrough", "toggle", bar_path, "clickthrough")
        end

        if bar.layout then
            capture_action_bar_per_bar_setting(bar, "Layout", "Orientation", "dropdown", layout_path, "orientation", { options = ACTION_BAR_ORIENTATION_OPTIONS })
            capture_action_bar_per_bar_setting(bar, "Layout", "Buttons Per Row", "slider", layout_path, "columns", { min = 1, max = 12, step = 1 })
            capture_action_bar_per_bar_setting(bar, "Layout", "Visible Buttons", "slider", layout_path, "iconCount", { min = 1, max = 12, step = 1 })
            capture_action_bar_per_bar_setting(bar, "Layout", "Button Size", "slider", layout_path, "buttonSize", { min = 20, max = 64, step = 1 })
            capture_action_bar_per_bar_setting(bar, "Layout", "Button Spacing", "slider", layout_path, "buttonSpacing", { min = 0, max = 12, step = 1 })
            capture_action_bar_per_bar_setting(bar, "Layout", "Grow Upward", "toggle", layout_path, "growUp")
            capture_action_bar_per_bar_setting(bar, "Layout", "Grow Left", "toggle", layout_path, "growLeft")
            if bar.flyout then
                capture_action_bar_per_bar_setting(bar, "Layout", "Flyout Direction", "dropdown", layout_path, "flyoutDirection", { options = ACTION_BAR_FLYOUT_OPTIONS })
            end
        end

        if bar.skinnable then
            capture_action_bar_per_bar_setting(bar, "Visual", "Icon Crop", "slider", bar_path, "iconZoom", { min = 0.05, max = 0.15, step = 0.01 })
            capture_action_bar_per_bar_setting(bar, "Visual", "Show Backdrop", "toggle", bar_path, "showBackdrop")
            capture_action_bar_per_bar_setting(bar, "Visual", "Backdrop Opacity", "slider", bar_path, "backdropAlpha", { min = 0, max = 1, step = 0.05 })
            capture_action_bar_per_bar_setting(bar, "Visual", "Show Gloss", "toggle", bar_path, "showGloss")
            capture_action_bar_per_bar_setting(bar, "Visual", "Gloss Opacity", "slider", bar_path, "glossAlpha", { min = 0, max = 1, step = 0.05 })
            capture_action_bar_per_bar_setting(bar, "Visual", "Show Borders", "toggle", bar_path, "showBorders")
            capture_action_bar_per_bar_setting(bar, "Visual", "Pressed Effect", "dropdown", bar_path, "showFlash", { options = ACTION_BAR_PRESSED_OPTIONS })

            capture_action_bar_per_bar_setting(bar, "Keybind Text", "Show Keybinds", "toggle", bar_path, "showKeybinds")
            capture_action_bar_per_bar_setting(bar, "Keybind Text", "Hide Empty Keybinds", "toggle", bar_path, "hideEmptyKeybinds")
            capture_action_bar_text_section(bar, bar_path, "Keybind Text", {
                show = "showKeybinds",
                fontSize = "keybindFontSize",
                anchor = "keybindAnchor",
                offsetX = "keybindOffsetX",
                offsetY = "keybindOffsetY",
                color = "keybindColor",
            }, "Show Keybinds")

            capture_action_bar_text_section(bar, bar_path, "Macro Names", {
                show = "showMacroNames",
                fontSize = "macroNameFontSize",
                anchor = "macroNameAnchor",
                offsetX = "macroNameOffsetX",
                offsetY = "macroNameOffsetY",
                color = "macroNameColor",
            }, "Show Macro Names")

            capture_action_bar_text_section(bar, bar_path, "Stack Count", {
                show = "showCounts",
                fontSize = "countFontSize",
                anchor = "countAnchor",
                offsetX = "countOffsetX",
                offsetY = "countOffsetY",
                color = "countColor",
            }, "Show Counts")
        end
    end

    register_manual_static_setting({
        tabIndex = 8,
        tabName = "Action Bars",
        subTabIndex = 3,
        subTabName = "Per-Bar",
        sectionName = "Totem Bar - Layout",
        tileId = "action_bars",
        subPageIndex = 3,
        featureId = "actionBarsPerBar",
        providerKey = "totemBar",
        category = "frames",
        keywords = { "Grow Direction", "Totem Bar", "Action Bars", "Per-Bar" },
    }, "Grow Direction", "dropdown", "profile.totemBar", "growDirection", { options = ACTION_BAR_TOTEM_GROW_OPTIONS })
end

local MINIMAP_CORNER_OPTIONS = {
    { value = "TOPRIGHT", text = "Top Right" },
    { value = "TOPLEFT", text = "Top Left" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
    { value = "BOTTOMLEFT", text = "Bottom Left" },
}

local MINIMAP_DRAWER_ANCHOR_OPTIONS = {
    { value = "RIGHT", text = "Right" },
    { value = "LEFT", text = "Left" },
    { value = "TOP", text = "Top" },
    { value = "BOTTOM", text = "Bottom" },
    { value = "TOPLEFT", text = "Top Left" },
    { value = "TOPRIGHT", text = "Top Right" },
    { value = "BOTTOMLEFT", text = "Bottom Left" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
}

local MINIMAP_DRAWER_GROWTH_OPTIONS = {
    { value = "RIGHT", text = "Right" },
    { value = "LEFT", text = "Left" },
    { value = "DOWN", text = "Down" },
    { value = "UP", text = "Up" },
}

local MINIMAP_DRAWER_TOGGLE_ICON_OPTIONS = {
    { value = "hammer", text = "Hammer" },
    { value = "grid", text = "Grid Dots" },
}

local DATATEXT_SLOT_OPTIONS = {
    { value = "", text = "(empty)" },
    { value = "bags", text = "Bags" },
    { value = "coords", text = "Coordinates" },
    { value = "currencies", text = "Currencies" },
    { value = "durability", text = "Durability" },
    { value = "experience", text = "Experience" },
    { value = "fps", text = "FPS" },
    { value = "friends", text = "Friends" },
    { value = "gold", text = "Gold" },
    { value = "guild", text = "Guild" },
    { value = "latency", text = "Latency" },
    { value = "lootspec", text = "Loot Specialization" },
    { value = "mythickey", text = "Mythic+ Key" },
    { value = "playerspec", text = "Player Spec" },
    { value = "system", text = "System" },
    { value = "time", text = "Time" },
    { value = "volume", text = "Volume" },
}

local DATATEXT_SPEC_DISPLAY_OPTIONS = {
    { value = "icon", text = "Icon Only" },
    { value = "loadout", text = "Icon + Loadout" },
    { value = "full", text = "Full (Spec / Loadout)" },
}

local DATATEXT_TIME_FORMAT_OPTIONS = {
    { value = "local", text = "Local Time" },
    { value = "server", text = "Server Time" },
}

local DATATEXT_CLOCK_FORMAT_OPTIONS = {
    { value = true, text = "24-Hour Clock" },
    { value = false, text = "AM/PM" },
}

local function capture_minimap_setting(section, label, widget_type, db_path, db_key, extra)
    register_manual_static_setting({
        tabIndex = 9,
        tabName = "Minimap & Datatext",
        subTabIndex = 1,
        subTabName = "Minimap",
        sectionName = section,
        tileId = "minimap",
        subPageIndex = 1,
        featureId = "minimap",
        providerKey = "minimap",
        category = "ui",
        keywords = { label, section, "Minimap", "Minimap & Datatext" },
    }, label, widget_type, db_path, db_key, extra)
end

local function capture_datatext_setting(section, label, widget_type, db_path, db_key, extra)
    register_manual_static_setting({
        tabIndex = 9,
        tabName = "Minimap & Datatext",
        subTabIndex = 2,
        subTabName = "Datatext",
        sectionName = section,
        tileId = "minimap",
        subPageIndex = 2,
        featureId = "datatextPanel",
        providerKey = "datatextPanel",
        category = "ui",
        keywords = { label, section, "Datatext", "Data Text", "Data Ext", "Minimap & Datatext" },
    }, label, widget_type, db_path, db_key, extra)
end

local function capture_datatext_slot(slot_index, slot_label, slot_path)
    capture_datatext_setting("Slot Configuration", "Slot " .. slot_index .. " (" .. slot_label .. ")", "dropdown", "profile.datatext.slots", slot_index, { options = DATATEXT_SLOT_OPTIONS })
    capture_datatext_setting("Slot Configuration", "Slot " .. slot_index .. " Short Label", "toggle", slot_path, "shortLabel")
    capture_datatext_setting("Slot Configuration", "Slot " .. slot_index .. " No Label", "toggle", slot_path, "noLabel")
    capture_datatext_setting("Slot Configuration", "Slot " .. slot_index .. " X Offset", "slider", slot_path, "xOffset", { min = -50, max = 50, step = 1 })
    capture_datatext_setting("Slot Configuration", "Slot " .. slot_index .. " Y Offset", "slider", slot_path, "yOffset", { min = -20, max = 20, step = 1 })
end

local function capture_minimap_datatext_settings()
    capture_minimap_setting("General", "Map Dimensions", "slider", "profile.minimap", "size", { min = 120, max = 380, step = 1 })
    capture_minimap_setting("General", "Map Zoom Level", "slider", "profile.minimap", "zoomLevel", { min = 0, max = 5, step = 1 })
    capture_minimap_setting("General", "Middle-Click Menu", "toggle", "profile.minimap", "middleClickMenuEnabled")
    capture_minimap_setting("General", "Auto-Zoom After Idle", "toggle", "profile.minimap", "autoZoom")
    capture_minimap_setting("General", "Coord Update Interval (sec)", "slider", "profile.minimap", "coordUpdateInterval", { min = 1, max = 10, step = 1 })
    capture_minimap_setting("General", "Addon Button Corner Radius", "slider", "profile.minimap", "buttonRadius", { min = 0, max = 12, step = 1 })
    capture_minimap_setting("General", "Hide Addon Buttons Until Hover", "toggle", "profile.minimap", "hideAddonButtons")

    capture_minimap_setting("Border", "Border Size", "slider", "profile.minimap", "borderSize", { min = 1, max = 16, step = 1 })
    capture_minimap_setting("Border", "Border Color", "colorpicker", "profile.minimap", "borderColor")
    capture_minimap_setting("Border", "Class Color Border", "toggle", "profile.minimap", "useClassColorBorder")
    capture_minimap_setting("Border", "Accent Color Border", "toggle", "profile.minimap", "useAccentColorBorder")

    capture_minimap_setting("Hide Elements", "Hide Mail (reload after)", "toggle_inverted", "profile.minimap", "showMail")
    capture_minimap_setting("Hide Elements", "Hide Work Order Notification", "toggle_inverted", "profile.minimap", "showCraftingOrder")
    capture_minimap_setting("Hide Elements", "Hide Tracking", "toggle_inverted", "profile.minimap", "showTracking")
    capture_minimap_setting("Hide Elements", "Hide Difficulty", "toggle_inverted", "profile.minimap", "showDifficulty")
    capture_minimap_setting("Hide Elements", "Hide Garrison/Mission Report", "toggle_inverted", "profile.minimap", "showMissions")
    capture_minimap_setting("Hide Elements", "Hide Border (Top)", "toggle", "profile.uiHider", "hideMinimapBorder")
    capture_minimap_setting("Hide Elements", "Hide Clock Button", "toggle", "profile.uiHider", "hideTimeManager")
    capture_minimap_setting("Hide Elements", "Hide Calendar Button", "toggle", "profile.uiHider", "hideGameTime")
    capture_minimap_setting("Hide Elements", "Hide Zone Text (Native)", "toggle", "profile.uiHider", "hideMinimapZoneText")
    capture_minimap_setting("Hide Elements", "Hide Zoom Buttons", "toggle_inverted", "profile.minimap", "showZoomButtons")

    capture_minimap_setting("Zone Label", "Show Zone Label", "toggle", "profile.minimap", "showZoneText")
    capture_minimap_setting("Zone Label", "Horizontal Offset", "slider", "profile.minimap.zoneTextConfig", "offsetX", { min = -150, max = 150, step = 1 })
    capture_minimap_setting("Zone Label", "Vertical Offset", "slider", "profile.minimap.zoneTextConfig", "offsetY", { min = -150, max = 150, step = 1 })
    capture_minimap_setting("Zone Label", "Label Size", "slider", "profile.minimap.zoneTextConfig", "fontSize", { min = 8, max = 20, step = 1 })
    capture_minimap_setting("Zone Label", "Uppercase Text", "toggle", "profile.minimap.zoneTextConfig", "allCaps")
    capture_minimap_setting("Zone Label", "Use Class Color", "toggle", "profile.minimap.zoneTextConfig", "useClassColor")

    capture_minimap_setting("Dungeon Eye", "Enable Dungeon Eye", "toggle", "profile.minimap.dungeonEye", "enabled")
    capture_minimap_setting("Dungeon Eye", "Corner Position", "dropdown", "profile.minimap.dungeonEye", "corner", { options = MINIMAP_CORNER_OPTIONS })
    capture_minimap_setting("Dungeon Eye", "Icon Scale", "slider", "profile.minimap.dungeonEye", "scale", { min = 0.1, max = 2.0, step = 0.1 })
    capture_minimap_setting("Dungeon Eye", "X Offset", "slider", "profile.minimap.dungeonEye", "offsetX", { min = -30, max = 30, step = 1 })
    capture_minimap_setting("Dungeon Eye", "Y Offset", "slider", "profile.minimap.dungeonEye", "offsetY", { min = -30, max = 30, step = 1 })

    capture_minimap_setting("Great Vault", "Enable Great Vault Button", "toggle", "profile.minimap.greatVault", "enabled")
    capture_minimap_setting("Great Vault", "Fade When Not Hovered", "toggle", "profile.minimap.greatVault", "fadeWhenMouseOut")
    capture_minimap_setting("Great Vault", "Fade Opacity", "slider", "profile.minimap.greatVault", "fadeOpacity", { min = 0, max = 1, step = 0.05, options = { precision = 2 } })
    capture_minimap_setting("Great Vault", "Anchor", "dropdown", "profile.minimap.greatVault", "anchor", { options = ACTION_BAR_ANCHOR_OPTIONS })
    capture_minimap_setting("Great Vault", "Icon Scale", "slider", "profile.minimap.greatVault", "scale", { min = 0.5, max = 2.0, step = 0.1 })
    capture_minimap_setting("Great Vault", "X Offset", "slider", "profile.minimap.greatVault", "offsetX", { min = -200, max = 200, step = 1 })
    capture_minimap_setting("Great Vault", "Y Offset", "slider", "profile.minimap.greatVault", "offsetY", { min = -200, max = 200, step = 1 })

    capture_minimap_setting("Button Drawer", "Enable Button Drawer", "toggle", "profile.minimap.buttonDrawer", "enabled")
    capture_minimap_setting("Button Drawer", "Open on Mouseover", "toggle", "profile.minimap.buttonDrawer", "openOnMouseover")
    capture_minimap_setting("Button Drawer", "Anchor Side", "dropdown", "profile.minimap.buttonDrawer", "anchor", { options = MINIMAP_DRAWER_ANCHOR_OPTIONS })
    capture_minimap_setting("Button Drawer", "Drawer X Offset", "slider", "profile.minimap.buttonDrawer", "offsetX", { min = -200, max = 200, step = 1 })
    capture_minimap_setting("Button Drawer", "Drawer Y Offset", "slider", "profile.minimap.buttonDrawer", "offsetY", { min = -200, max = 200, step = 1 })
    capture_minimap_setting("Button Drawer", "Button X Offset", "slider", "profile.minimap.buttonDrawer", "toggleOffsetX", { min = -200, max = 200, step = 1 })
    capture_minimap_setting("Button Drawer", "Button Y Offset", "slider", "profile.minimap.buttonDrawer", "toggleOffsetY", { min = -200, max = 200, step = 1 })
    capture_minimap_setting("Button Drawer", "Toggle Size", "slider", "profile.minimap.buttonDrawer", "toggleSize", { min = 12, max = 40, step = 1 })
    capture_minimap_setting("Button Drawer", "Toggle Icon", "dropdown", "profile.minimap.buttonDrawer", "toggleIcon", { options = MINIMAP_DRAWER_TOGGLE_ICON_OPTIONS })
    capture_minimap_setting("Button Drawer", "Auto-Hide Delay (0=manual)", "slider", "profile.minimap.buttonDrawer", "autoHideDelay", { min = 0, max = 5, step = 0.5 })
    capture_minimap_setting("Button Drawer", "Button Size", "slider", "profile.minimap.buttonDrawer", "buttonSize", { min = 20, max = 40, step = 1 })
    capture_minimap_setting("Button Drawer", "Button Spacing", "slider", "profile.minimap.buttonDrawer", "buttonSpacing", { min = 0, max = 12, step = 1 })
    capture_minimap_setting("Button Drawer", "Inner Padding", "slider", "profile.minimap.buttonDrawer", "padding", { min = 0, max = 20, step = 1 })
    capture_minimap_setting("Button Drawer", "Columns", "slider", "profile.minimap.buttonDrawer", "columns", { min = 1, max = 6, step = 1 })
    capture_minimap_setting("Button Drawer", "Growth Direction", "dropdown", "profile.minimap.buttonDrawer", "growthDirection", { options = MINIMAP_DRAWER_GROWTH_OPTIONS })
    capture_minimap_setting("Button Drawer", "Center Growth", "toggle", "profile.minimap.buttonDrawer", "centerGrowth")
    capture_minimap_setting("Button Drawer", "Auto-Hide Toggle Button", "toggle", "profile.minimap.buttonDrawer", "autoHideToggle")

    capture_minimap_setting("Drawer Appearance", "Background Color", "colorpicker", "profile.minimap.buttonDrawer", "bgColor", { options = { noAlpha = true } })
    capture_minimap_setting("Drawer Appearance", "Background Opacity", "slider", "profile.minimap.buttonDrawer", "bgOpacity", { min = 0, max = 100, step = 1 })
    capture_minimap_setting("Drawer Appearance", "Border Size (0=hidden)", "slider", "profile.minimap.buttonDrawer", "borderSize", { min = 0, max = 8, step = 1 })
    capture_minimap_setting("Drawer Appearance", "Border Color", "colorpicker", "profile.minimap.buttonDrawer", "borderColor", { options = { noAlpha = true } })

    capture_datatext_setting("Panel Settings", "Enable Minimap Datatext", "toggle", "profile.datatext", "enabled")
    capture_datatext_setting("Panel Settings", "Force Single Line", "toggle", "profile.datatext", "forceSingleLine")
    capture_datatext_setting("Panel Settings", "Panel Height (Per Row)", "slider", "profile.datatext", "height", { min = 18, max = 50, step = 1 })
    capture_datatext_setting("Panel Settings", "Background Transparency", "slider", "profile.datatext", "bgOpacity", { min = 0, max = 100, step = 5 })
    capture_datatext_setting("Panel Settings", "Border Size (0=hidden)", "slider", "profile.datatext", "borderSize", { min = 0, max = 8, step = 1 })
    capture_datatext_setting("Panel Settings", "Border Color", "colorpicker", "profile.datatext", "borderColor")
    capture_datatext_setting("Panel Settings", "Vertical Offset", "slider", "profile.datatext", "offsetY", { min = -40, max = 40, step = 1 })
    capture_datatext_setting("Panel Settings", "Text Size", "slider", "profile.datatext", "fontSize", { min = 9, max = 18, step = 1 })

    capture_datatext_slot(1, "Left", "profile.datatext.slot1")
    capture_datatext_slot(2, "Center", "profile.datatext.slot2")
    capture_datatext_slot(3, "Right", "profile.datatext.slot3")

    capture_datatext_setting("Text Styling", "Use Class Color", "toggle", "profile.datatext", "useClassColor")
    capture_datatext_setting("Text Styling", "Custom Text Color", "colorpicker", "profile.datatext", "valueColor")

    capture_datatext_setting("Spec Display", "Spec Display Mode", "dropdown", "profile.datatext", "specDisplayMode", { options = DATATEXT_SPEC_DISPLAY_OPTIONS })
    capture_datatext_setting("Time Options", "Time Format", "dropdown", "profile.datatext", "timeFormat", { options = DATATEXT_TIME_FORMAT_OPTIONS })
    capture_datatext_setting("Time Options", "Clock Format", "dropdown", "profile.datatext", "use24Hour", { options = DATATEXT_CLOCK_FORMAT_OPTIONS })
    capture_datatext_setting("Time Options", "Lockout Refresh (minutes)", "slider", "profile.datatext", "lockoutCacheMinutes", { min = 1, max = 30, step = 1 })
end

install_search_capture_overrides()
capture_all_search_features()
capture_cdm_settings_tabs()
capture_group_frames_settings_tabs()
capture_unit_frames_settings_tabs()
capture_action_bar_per_bar_settings()
capture_minimap_datatext_settings()

-- Tile registration runs AFTER install_search_capture_overrides() so the
-- alias-emit wrappers actually intercept the RegisterFeatureTile /
-- AddFeatureTile calls, and AFTER capture_all_search_features() because
-- that function resets the navigation registry on entry — any alias
-- entries emitted before then would be wiped.

-- Welcome tile registration lives in QUI_Options/init.lua, which
-- should_load_script() excludes from the headless generator load. The
-- stub below mirrors init.lua's RegisterFeatureTile call and carries
-- the searchAliases this file owns for welcome. If you change init.lua's
-- welcome tile shape, update this stub too — and welcome aliases are
-- declared here, not in init.lua, since the runtime drops the field.
if ns.QUI_Options and type(ns.QUI_Options.RegisterFeatureTile) == "function" then
    ns.QUI_Options.RegisterFeatureTile(frame, {
        id = "welcome",
        icon = "*",
        name = "Welcome",
        subtitle = "Getting started · Tips · What's new",
        featureId = "welcomePage",
        noScroll = false,
        searchAliases = {
            "welcome",
            "getting started",
            "first time setup",
            "intro",
            "home",
        },
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

collect_feature_keywords()

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
        tostring(entry.tabIndex or 0),
        tostring(entry.subTabIndex or 0),
        entry.sectionName or "",
        entry.label or "",
        entry.navType or "",
        entry.featureId or "",
        entry.providerKey or "",
        entry.category or "",
        entry.surfaceTabKey or "",
        entry.surfaceUnitKey or "",
    }, "\31")
end

local function merge_unique(target, source)
    if type(source) ~= "table" then
        return target
    end
    target = target or {}
    local present = {}
    for _, value in ipairs(target) do
        if type(value) == "string" then
            present[value:lower()] = true
        end
    end
    for _, value in ipairs(source) do
        if type(value) == "string" and value ~= "" and not present[value:lower()] then
            target[#target + 1] = value
            present[value:lower()] = true
        end
    end
    return target
end

local function apply_feature_keywords(entries)
    if not entries then
        return
    end
    for _, entry in ipairs(entries) do
        local extra = feature_keywords_by_id[entry.featureId]
        if extra then
            entry.keywords = merge_unique(entry.keywords, extra)
        end
    end
end

local settings_entries = {}
for index, entry in ipairs(GUI.StaticSettingsRegistry or {}) do
    settings_entries[index] = copy_table(entry)
end
table.sort(settings_entries, function(a, b)
    return entry_sort_key(a) < entry_sort_key(b)
end)
apply_feature_keywords(settings_entries)

local navigation_entries = {}
for index, entry in ipairs(GUI.StaticNavigationRegistry or {}) do
    navigation_entries[index] = copy_table(entry)
end
table.sort(navigation_entries, function(a, b)
    return entry_sort_key(a) < entry_sort_key(b)
end)
apply_feature_keywords(navigation_entries)

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
