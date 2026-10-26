local ADDON_NAME = "QUI"
local ROOT = "."
-- ONE cache, in English. Its strings are ns.L keys, and the runtime localizes
-- them at apply time (GUI:PrepareSearchEntry in QUI_Options/framework.lua).
-- This used to take a locale argument and emit ten translated copies; every
-- non-enUS client then parsed a 3.2 MB copy on the LOGIN path, because those
-- copies shipped inside the per-locale translation addons that had to load
-- synchronously during login. Those addons are gone too — the overlays are
-- core/locale/<loc>.lua now.
local OUTPUT_PATH = "QUI_Options/search_cache.lua"

-- Hard-stop the old habit: `lua tools/generate_search_cache.lua deDE` used to
-- emit QUI_OptionsSearch_deDE/search_cache.lua. It now silently regenerates
-- the English cache, which looks like a no-op and hides the mistake.
if arg and arg[1] then
    io.stderr:write(([[
generate_search_cache.lua takes no arguments (got %q).

There is one cache, in English, at %s. Its strings are ns.L keys and
QUI_Options localizes them at apply time (GUI:PrepareSearchEntry), so
per-locale caches no longer exist — one in a QUI_OptionsSearch_<loc> folder
would be parsed on the LOGIN path of every non-enUS client.

Run without arguments, or `bash tools/i18n/gen_all_caches.sh` for the full
enUS.lua + cache + overlay-TOC pass.
]]):format(tostring(arg[1]), OUTPUT_PATH))
    os.exit(1)
end
_G.unpack = _G.unpack or table.unpack
_G.tinsert = table.insert
_G.UISpecialFrames = {}
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

-- The main addon lists its Lua files directly in QUI.toc (flat TOC loading).
-- Comment lines (#) and directives (##) are skipped; the rare .xml entry
-- (frame templates) is walked for any <Script> tags it may carry.
local function collect_scripts_from_toc(toc_path, out, seen)
    for _, line in ipairs(read_lines(toc_path)) do
        line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local entry = join_path(toc_path, line)
            if entry:lower():match("%.lua$") then
                out[#out + 1] = entry
            elseif entry:lower():match("%.xml$") then
                collect_scripts_from_xml(entry, out, seen)
            end
        end
    end
end

-- QUI_Options lists its files directly in QUI_Options.toc (flat TOC loading).
-- Local option UI scripts live under QUI_Options in this repo; references to
-- the main addon use "..\QUI\..." and are stripped to repo-relative paths for
-- headless runs. bootstrap.lua is namespace wiring only and was never part of
-- the old options.xml manifest; it is skipped so the collected script set
-- stays identical.
local function collect_qui_options_scripts(out, seen)
    local toc_path = normalize_path("QUI_Options/QUI_Options.toc")
    if seen[toc_path] then
        return
    end
    seen[toc_path] = true

    local probe = io.open(toc_path, "r")
    if not probe then
        return
    end
    probe:close()

    local emitted = {}
    for _, existing in ipairs(out) do
        emitted[existing] = true
    end

    for _, line in ipairs(read_lines(toc_path)) do
        line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 1) ~= "#" and line:lower():match("%.lua$") then
            local normalized = normalize_path(line)
            local repo_path = normalized:match("^%.%./QUI/(.+)$")
            if repo_path then
                repo_path = normalize_path(repo_path)
            else
                repo_path = normalized:match("^%.%./(.+)$")
                if repo_path then
                    repo_path = normalize_path(repo_path)
                else
                    repo_path = normalize_path(join_path(toc_path, normalized))
                end
            end
            if repo_path ~= "QUI_Options/bootstrap.lua" and not emitted[repo_path] then
                emitted[repo_path] = true
                out[#out + 1] = repo_path
            end
        end
    end
end

local function should_load_script(path)
    path = normalize_path(path)

    if path == "QUI_ActionBars/actionbars/actionbars_env.lua"
        or path == "QUI_ActionBars/actionbars/actionbars.lua"
        or path == "QUI_ActionBars/actionbars/actionbars_helpers.lua"
        or path == "QUI_ActionBars/actionbars/actionbars_per_bar_builders.lua" then
        return true
    end

    if path == "QUI_CDM/cdm/cdm_shared.lua"
        or path == "modules/qol/sound_mute_catalog.lua"
        or path == "modules/qol/blizzard_mover.lua"
        or path == "modules/qol/blizzard_mover_frames.lua"
        or path == "QUI_Chat/chat/button_bar.lua"
        or path == "QUI_Chat/chat/tab_manager.lua"
        or path == "QUI_Chat/chat/tab_filters.lua"
        or path == "QUI_Reminders/spell_reminders/model.lua" or path == "QUI_Reminders/spell_reminders/catalog.lua" then
        return true
    end

    if path == "init.lua" or path == OUTPUT_PATH then
        return false
    end
    if path:match("^libs/") or path:match("^importstrings/") then
        return false
    end

    if path == "core/utils.lua"
        or path == "core/profile_io.lua"
        or path == "core/theme.lua"
        or path == "core/infobar_shared.lua"
        or path == "core/settings_layout_shared.lua"
        or path == "core/border_registry.lua"
        or path == "core/defaults.lua"
        or path == "core/scaling.lua"
        or path == "core/uikit.lua"
        or path == "core/settings_builders.lua"
        or path == "core/diagnostics_console.lua"
        or path == "core/addon_manifest.lua"
        or path:match("^core/settings/") then
        return true
    end

    if path == "modules/layout/layoutmode_utils.lua" then
        return true
    end
    if path:match("^modules/.+/settings/") then
        return true
    end

    if path:match("^QUI_.+/settings/") then
        if path:match("^QUI_GroupFrames/groupframes/settings/") then
            return true
        end
        if path:match("^QUI_UnitFrames/unitframes/settings/") then
            return true
        end
        if path:match("^QUI_Nameplates/nameplates/settings/") then
            return true
        end
        if path:match("^QUI_Chat/chat/settings/") then
            return true
        end
        if path:match("^QUI_Bags/bags/settings/") then
            return true
        end
        if path:match("^QUI_ResourceBars/resourcebars/settings/") then
            return true
        end
        if path == "QUI_DamageMeter/damage_meter/settings/damage_meter_content.lua" then
            return true
        end
        if path == "QUI_CDM/cdm/settings/containers_page.lua"
            or path == "QUI_CDM/cdm/settings/composer_preview_driver.lua"
            or path == "QUI_CDM/cdm/settings/composer.lua" then
            return true
        end
        if path:match("^QUI_ActionBars/actionbars/settings/") then
            return true
        end
        if path:match("^QUI_Reminders/.+/settings/") then
            return true
        end
        return false
    end

    if path:match("^QUI_Options/") then
        return true
    end

    return false
end

local function make_auto_table()
    return setmetatable({}, {
        __index = function(t, k)
            if type(k) == "number" then
                return nil
            end
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
            if key == "RegisterSection" then return nil end
            if key == "GetFontString" then
                return function(frame)
                    frame._fontString = frame._fontString or create_region(frame, "FontString")
                    return frame._fontString
                end
            end
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
    -- The harvest always runs in English: the emitted strings must be the ns.L
    -- keys that QUI_Options localizes at apply time.
    return "enUS"
end
-- WoW-style positional string.format (e.g. "%2$s %1$s", "%1$d / %2$d"). Stock
-- Lua 5.1 rejects "%n$" specifiers but WoW's format supports them and QUI
-- localization relies on them. This shim reorders args for positional
-- specifiers then delegates to native format; non-positional strings pass
-- through unchanged. Also covers ("..."):format(...) via the string table.
do
    local rawformat = string.format
    local function posformat(fmt, ...)
        if type(fmt) == "string" and fmt:find("%%%d+%$") then
            local args = { ... }
            local res = fmt:gsub("%%(%d+)%$([%-%+ #0]*%d*%.?%d*[diouxXeEfgGqcs])",
                function(idx, conv)
                    return rawformat("%" .. conv, args[tonumber(idx)])
                end)
            return (res:gsub("%%%%", "%%"))
        end
        return rawformat(fmt, ...)
    end
    string.format = posformat
    _G.format = posformat
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
    GetCVarBool = function(cvar)
        return _G.GetCVarBool(cvar)
    end,
    GetCVar = function(cvar)
        return _G.GetCVar(cvar)
    end,
    SetCVar = function(cvar, value)
        return _G.SetCVar(cvar, value)
    end,
}
_G.CVarCallbackRegistry = {
    GetCVarValueBool = function(_, cvar) return _G.GetCVarBool(cvar) end,
}
_G.C_NamePlateManager = {
    SetNamePlateSimplified = function() end,
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

-- Published so page builds can skip work that's meaningless under the
-- harvest — e.g. live preview-mock rendering, whose math reads numeric DB
-- leaves that make_auto_table() vivifies as TABLES (math.max(0, table)
-- errors, and the failed build knocks the page's labels out of the cache).
_G.QUI_SEARCH_HARVEST = true

local profile_db = make_auto_table()
profile_db.damageMeter.native.windows[1] = {}
profile_db.general.showOptionTooltips = true
profile_db.quiGroupFrames = {
    testMode = {},
    party = {
        auras = {
            enabled = true,
            elements = {},
        },
    },
    raid = {
        auras = {
            enabled = true,
            elements = {},
        },
    },
}

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
                Source = {},
            },
        },
    },
    -- Palette comes from core/theme.lua (loaded by should_load_script before
    -- framework.lua); theme.lua fills QUI.GUI.Colors when it is absent.
    GUI = {},
    QUICore = {
        db = {
            profile = profile_db,
            GetProfiles = function()
                return { "Default", "Source" }
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
ns.QUI = _G.QUI
ns.QUI.Chat = {
    _internals = { GetSettings = function() return profile_db.chat end },
    _afterRefresh = {},
}

-- i18n: resolve L["..."] in content files against the enUS base so the emitted
-- strings are exactly the ns.L KEYS the runtime resolver looks up. Do not add a
-- translation overlay here — a translated cache cannot be localized again, and
-- the whole point of the single-cache design is that translation happens at
-- apply time from the overlay the client already loaded.
do
    -- enUS.lua ships an ordered KEY ARRAY (ns.LocaleData.keys) since the ten
    -- overlays went positional. It used to ship a keyed identity table, and
    -- resolving against an identity table returns the key itself -- so the
    -- identity fallback below is exactly what that lookup always produced,
    -- with no table to load. Emitting the KEY is the requirement here; see the
    -- comment above and tests/unit/search_cache_locale_consistency_test.lua.
    ns.L = setmetatable({}, { __index = function(_, key) return key end })
end

local function build_lsm_options(kind, fallback)
    local list = {}
    local lsm = ns.LSM
    if lsm and type(lsm.List) == "function" then
        for _, name in ipairs(lsm:List(kind) or {}) do
            list[#list + 1] = { value = name, text = name }
        end
    end
    if #list == 0 and fallback then
        list[1] = fallback
    end
    return list
end

ns.QUI_Options = {
    PADDING = 15,
    GetDB = function()
        return profile_db
    end,
    GetTextureList = function()
        return build_lsm_options("statusbar", { value = "Solid", text = "Solid" })
    end,
    GetFontList = function()
        return build_lsm_options("font", { value = "Friz Quadrata TT", text = "Friz Quadrata TT" })
    end,
    GetSoundList = function()
        return build_lsm_options("sound", { value = "None", text = "None" })
    end,
    CreateScrollableContent = function(parent)
        local scroll = create_stub_node("ScrollFrame", parent, false)
        local content = create_stub_node("Frame", scroll, false)
        content._hasContent = false
        scroll.SetScrollChild = function(self, child) self._scrollChild = child end
        scroll:SetScrollChild(content)
        return scroll, content
    end,
    CreateWrappedLabel = function(parent, text)
        local label = create_stub_node("FontString", parent, true)
        label:SetText(text or "")
        return label
    end,
    CreateLinkItem = function(parent, label)
        local item = create_stub_node("Button", parent, false)
        item._text = label or ""
        return item
    end,
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
    GetEditableBindingSetID = function()
        return nil
    end,
    GetBindingSetSources = function()
        return {}
    end,
    CopyBindingsFrom = function()
        return false
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

-- Headless stub for AddonLoader: module_addons_content.lua calls
-- IsModuleAddonEnabled (isEnabled) and SetModuleAddonEnabled (setEnabled)
-- only at runtime; the registration loop only needs the namespace to exist.
ns.AddonLoader = {
    IsModuleAddonEnabled  = function() return true end,
    IsModuleLoaded        = function() return false end,
    SetModuleAddonEnabled = function() return "reload" end,
}

ns.SpellReminders = { Store = function() return profile_db.spellReminders end }

local function load_script(path, script_ns)
    local chunk, load_err = loadfile(path)
    if not chunk then
        return false, load_err
    end

    return xpcall(function()
        return chunk(ADDON_NAME, script_ns or ns)
    end, debug.traceback)
end

local scripts = {}
local script_xml_seen = {}
collect_scripts_from_toc("QUI.toc", scripts, script_xml_seen)
collect_scripts_from_toc("QUI_Reminders/QUI_Reminders.toc", scripts, script_xml_seen)
collect_scripts_from_toc("QUI_ActionBars/QUI_ActionBars.toc", scripts, script_xml_seen)
collect_scripts_from_toc("QUI_CDM/QUI_CDM.toc", scripts, script_xml_seen)
collect_scripts_from_toc("QUI_Chat/QUI_Chat.toc", scripts, script_xml_seen)
collect_qui_options_scripts(scripts, script_xml_seen)

local failures = {}
local loaded_count = 0

do
    local swing_ns = setmetatable({
        Client = { isForever = true },
        WhenLoggedIn = function() end,
        Registry = { Register = function() end },
    }, { __index = ns })
    local path = "modules/skinning/gameplay/swing_timers.lua"
    local ok, err = load_script(path, swing_ns)
    if ok then
        ns.SwingTimers = swing_ns.SwingTimers
    else
        failures[#failures + 1] = { path = path, error = err }
    end
end

-- groupframes_aura_model.lua is now a compatibility shim: `local E =
-- ns.AuraElements` captured at file scope, delegating every constructor to the
-- shared core model (core/aura_elements.lua). That core file is part of
-- QUI.toc and would normally load via the main scripts loop below, but the
-- shim (pre-loaded next) needs ns.AuraElements populated BEFORE it runs, so
-- pull it in here first. Pure Lua / no dependencies, safe to load standalone;
-- the main loop loading it again later is harmless (a fresh idempotent table
-- assignment — this file's shim already captured its own reference).
-- QUI_Options/shared.lua (GetFontList, CVar helpers) calls ns.SafeCall at
-- harvest time. That guard lives in QUI.toc (core/safecall.lua), which
-- should_load_script() does not pull into the main loop, so pre-load it
-- here or every page whose build() touches those helpers errors out of the
-- harvest. Pure Lua (issecretvalue/geterrorhandler resolved defensively),
-- safe to load standalone.
do
    local safecall_path = "core/safecall.lua"
    local probe = io.open(safecall_path, "r")
    if probe then
        probe:close()
        local ok, err = load_script(safecall_path)
        if not ok then
            failures[#failures + 1] = { path = safecall_path, error = err }
        end
    end
end

do
    local core_model_path = "core/aura_elements.lua"
    local probe = io.open(core_model_path, "r")
    if probe then
        probe:close()
        local ok, err = load_script(core_model_path)
        if not ok then
            failures[#failures + 1] = { path = core_model_path, error = err }
        end
    end
end

do
    local aura_displays_path = "modules/trackers/aura_displays.lua"
    local probe = io.open(aura_displays_path, "r")
    if probe then
        probe:close()
        local ok, err = load_script(aura_displays_path)
        if not ok then
            failures[#failures + 1] = { path = aura_displays_path, error = err }
        end
    end
end

-- The unified-auras editor captures `local Model = ns.QUI_GroupFramesAuraModel`
-- at file scope, and the auras element-list capture below needs the model's
-- element constructors. That model lives in the QUI_GroupFrames runtime TOC, not
-- the options TOC the harvest walks, so pre-load it into ns before the editor
-- file runs (otherwise its Model upvalue is nil and RenderAuras early-returns).
do
    local model_path = "QUI_GroupFrames/groupframes/groupframes_aura_model.lua"
    local probe = io.open(model_path, "r")
    if probe then
        probe:close()
        local ok, err = load_script(model_path)
        if not ok then
            failures[#failures + 1] = { path = model_path, error = err }
        end
    end
end

-- Nameplates' shared-element aura editor mount (nameplates_schema.lua,
-- RenderAuraRowsSection) captures `local NP = ns.QUI_Nameplates` and
-- passes NP.DefaultNameplateBucket (plate_auras.lua) as AurasEditor.RenderAuras's
-- defaultBucketFn, seeding the SAME store the runtime uses. Both files live in
-- QUI_Nameplates's runtime TOC, not the options TOC the harvest walks, so
-- pre-load them here, in dependency order: shared.lua creates ns.QUI_Nameplates
-- first (plate_auras.lua opens with `if not NP then return end` and is a
-- silent no-op otherwise). Without this the schema's NP upvalue is nil and
-- the aura editor mount is skipped, leaving those rows unsearchable.
do
    local shared_path = "QUI_Nameplates/nameplates/shared.lua"
    local probe = io.open(shared_path, "r")
    if probe then
        probe:close()
        local ok, err = load_script(shared_path)
        if not ok then
            failures[#failures + 1] = { path = shared_path, error = err }
        end
    end
end

do
    local plate_type_path = "QUI_Nameplates/nameplates/plate_type.lua"
    local probe = io.open(plate_type_path, "r")
    if probe then
        probe:close()
        local ok, err = load_script(plate_type_path)
        if not ok then
            failures[#failures + 1] = { path = plate_type_path, error = err }
        end
    end
end

do
    local plate_auras_path = "QUI_Nameplates/nameplates/plate_auras.lua"
    local probe = io.open(plate_auras_path, "r")
    if probe then
        probe:close()
        local ok, err = load_script(plate_auras_path)
        if not ok then
            failures[#failures + 1] = { path = plate_auras_path, error = err }
        end
    end
end

-- The setup-wizard page (core/settings/content/auras_wizard_page.lua) captures
-- `local W = ns.QUI_AuraWizard` at file scope, and its build() calls W.WizardSteps
-- / W.RoleDefaults / W.CommitTrackedHoTs etc. during the harvest. That module
-- lives in QUI.toc (core/aura_wizard.lua), which should_load_script() does not
-- pull into the main loop, so pre-load it here -- AFTER core/aura_elements.lua
-- (loaded above), which it depends on via `local E = ns.AuraElements`. Without
-- this the page's W upvalue is nil and the wizard page build errors, leaving
-- only its nav entry (SetSearchContext) searchable and none of its labels.
do
    local wizard_path = "core/aura_wizard.lua"
    local probe = io.open(wizard_path, "r")
    if probe then
        probe:close()
        local ok, err = load_script(wizard_path)
        if not ok then
            failures[#failures + 1] = { path = wizard_path, error = err }
        end
    end
end

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

local function build_capture_navigation_label(nav_type, info, context_label)
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
    if context_label and context_label ~= "" then
        parts[#parts + 1] = context_label
    end
    if section_label and section_label ~= "" then
        parts[#parts + 1] = section_label
    end

    return #parts > 0 and table.concat(parts, " > ") or nil
end

local function build_capture_navigation_keywords(info, context_label)
    local tab_label, subtab_label, section_label = build_capture_route_labels(info)
    local keywords = {}
    if tab_label and tab_label ~= "" then
        keywords[#keywords + 1] = tab_label
    end
    if subtab_label and subtab_label ~= "" then
        keywords[#keywords + 1] = subtab_label
    end
    if context_label and context_label ~= "" then
        keywords[#keywords + 1] = context_label
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

local capturing_navigation_only
local capturing_context_label

local function resolve_surface_type_key(widget_descriptor, context)
    return type(widget_descriptor) == "table" and widget_descriptor.dbPath and context.surfaceTypeKey or nil
end

local function register_capture_setting_entry(entry)
    if capturing_navigation_only then return nil end
    local context = GUI._searchContext or {}
    if type(entry) ~= "table" or type(entry.label) ~= "string" or entry.label == "" then
        return nil
    end

    local surfaceTypeKey = resolve_surface_type_key(entry.widgetDescriptor, context)
    local contextLabel = capturing_context_label
    if context.surfaceTypeKey and not surfaceTypeKey then contextLabel = nil end
    return GUI:RegisterStaticSettingEntry({
        label = entry.label,
        contextLabel = contextLabel,
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
        surfaceTypeKey = surfaceTypeKey,
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
    if type(widget) ~= "table" or type(label) ~= "string" or label == "" then return end
    if rawget(widget, "_quiSearchCaptureExcluded") then return end
    local entry = rawget(widget, "_quiSearchCaptureEntry")
    if type(entry) ~= "table" then
        -- Composite rows own real form controls plus action buttons. Inherit the
        -- row label for the controls; action buttons keep their own captions.
        for _, child in ipairs({ widget:GetChildren() }) do register_widget_row_capture(child, label) end
        return
    end
    if entry.widgetType == "action_button" or widget._quiSearchCaptureRegisteredLabel == label then return end
    entry = copy_capture_entry(entry)
    entry.label = label
    widget._widgetLabel = label
    widget._quiSearchCaptureRegisteredLabel = label
    return register_capture_setting_entry(entry)
end

local function create_captured_search_widget(kind, parent, label, dbKey, dbTable, extra, registryInfo)
    local entry = {
        label = label,
        widgetType = kind,
        widgetDescriptor = GUI:BuildSearchWidgetDescriptor(kind, dbKey, dbTable, extra),
        keywords = registryInfo and registryInfo.keywords or nil,
        description = registryInfo and registryInfo.description or nil,
        relatedTo = registryInfo and registryInfo.relatedTo or nil,
    }

    local excluded = type(registryInfo) == "table" and registryInfo.searchable == false
    if not excluded then register_capture_setting_entry(entry) end

    local stub = create_captured_widget_stub(kind)
    stub:SetParent(parent)
    stub._quiSearchCaptureEntry = not excluded and entry or nil
    stub._quiSearchCaptureExcluded = excluded
    stub._widgetLabel = label
    return stub
end

local function install_search_capture_overrides()
    GUI.RegisterSearchNavigation = function(self, navType, info)
        if capturing_navigation_only then return nil end
        if type(info) ~= "table" then
            return nil
        end

        -- moduleToggle entries are emitted only by the generator (the runtime
        -- RegisterNavigationItem handles tab/subtab/section only). They carry an
        -- author-supplied label and keywords (the feature's display name, caption,
        -- and group) that are NOT derivable from route info — their tileId/
        -- subPageIndex alone yield a useless "global > Page 3" with no feature
        -- name, which makes the feature toggle impossible to find via search.
        -- Honor the caller's label/keywords for these; derive them for the
        -- breadcrumb-based tab/subtab/section entries as before.
        local isModuleToggle = navType == "moduleToggle"

        local label
        if isModuleToggle and type(info.label) == "string" and info.label ~= "" then
            label = info.label
        else
            label = build_capture_navigation_label(navType, info, capturing_context_label)
        end
        if type(label) ~= "string" or label == "" then
            return nil
        end

        local keywords
        if isModuleToggle and type(info.keywords) == "table" then
            keywords = {}
            for _, keyword in ipairs(info.keywords) do
                if type(keyword) == "string" and keyword ~= "" then
                    keywords[#keywords + 1] = keyword
                end
            end
        end
        if not keywords or #keywords == 0 then
            keywords = build_capture_navigation_keywords(info, capturing_context_label)
        end

        return self:RegisterStaticNavigationEntry({
            navType = navType,
            label = label,
            contextLabel = capturing_context_label,
            tabIndex = info.tabIndex,
            tabName = info.tabName,
            subTabIndex = info.subTabIndex,
            subTabName = info.subTabName,
            sectionName = info.sectionName,
            tileId = info.tileId,
            subPageIndex = info.subPageIndex,
            featureId = info.featureId,
            providerKey = info.providerKey or (capturing_context_label and self._searchContext.providerKey),
            category = info.category,
            surfaceTabKey = info.surfaceTabKey,
            surfaceUnitKey = info.surfaceUnitKey,
            surfaceTypeKey = info.surfaceTypeKey,
            keywords = keywords,
        })
    end

    GUI.RegisterSearchSettingWidget = function(self, entry)
        return register_capture_setting_entry(entry)
    end

    GUI.CreateFormToggle = function(self, parent, label, dbKey, dbTable, onChange, registryInfo)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("toggle", parent, label, dbKey, dbTable, nil, registryInfo)
    end

    GUI.CreateFormToggleInverted = function(self, parent, label, dbKey, dbTable, onChange, registryInfo)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("toggle_inverted", parent, label, dbKey, dbTable, nil, registryInfo)
    end

    GUI.CreateFormEditBox = function(self, parent, label, dbKey, dbTable, onChange, options, registryInfo)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("editbox", parent, label, dbKey, dbTable, {
            options = options or {},
        }, registryInfo)
    end

    GUI.CreateFormSlider = function(self, parent, label, min, max, step, dbKey, dbTable, onChange, options, registryInfo)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("slider", parent, label, dbKey, dbTable, {
            min = min,
            max = max,
            step = step,
            options = options or {},
        }, registryInfo)
    end

    GUI.CreateFormDropdown = function(self, parent, label, options, dbKey, dbTable, onChange, registryInfo, opts)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("dropdown", parent, label, dbKey, dbTable, {
            options = options,
            dropdownOptions = opts or {},
        }, registryInfo)
    end

    GUI.CreateFormColorPicker = function(self, parent, label, dbKey, dbTable, onChange, options, registryInfo)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("colorpicker", parent, label, dbKey, dbTable, {
            options = options or {},
        }, registryInfo)
    end

    GUI.CreateFormCheckbox = function(self, parent, label, dbKey, dbTable, _onChange, registryInfo)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("checkbox", parent, label, dbKey, dbTable, nil, registryInfo)
    end

    GUI.CreateFormCheckboxInverted = function(self, parent, label, dbKey, dbTable, _onChange, registryInfo)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("checkbox_inverted", parent, label, dbKey, dbTable, nil, registryInfo)
    end

    GUI.CreateCheckbox = function(self, parent, label, dbKey, dbTable, _onChange, description)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("checkbox", parent, label, dbKey, dbTable, nil, { description = description })
    end

    GUI.CreateCheckboxCentered = function(self, parent, label, dbKey, dbTable, _onChange, description)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("checkbox", parent, label, dbKey, dbTable, nil, { description = description })
    end

    GUI.CreateCheckboxInverted = function(self, parent, label, dbKey, dbTable, _onChange, description)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("checkbox_inverted", parent, label, dbKey, dbTable, nil, { description = description })
    end

    GUI.CreateAccentCheckbox = function(self, parent, options)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        local opts = type(options) == "table" and options or {}
        return create_captured_search_widget("checkbox", parent, opts.label, opts.dbKey, opts.dbTable, nil, { description = opts.description })
    end

    GUI.CreateSlider = function(self, parent, label, min, max, step, dbKey, dbTable, _onChange, options)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        local opts = type(options) == "table" and options or {}
        return create_captured_search_widget("slider", parent, label, dbKey, dbTable, {
            min = min, max = max, step = step, options = opts,
        }, { description = opts.description })
    end

    GUI.CreateDropdown = function(self, parent, label, options, dbKey, dbTable, _onChange, description)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("dropdown", parent, label, dbKey, dbTable, {
            options = options,
        }, { description = description })
    end

    GUI.CreateDropdownFullWidth = function(self, parent, label, options, dbKey, dbTable, _onChange, description)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("dropdown", parent, label, dbKey, dbTable, {
            options = options,
        }, { description = description })
    end

    GUI.CreateColorPicker = function(self, parent, label, dbKey, dbTable, _onChange, description)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("colorpicker", parent, label, dbKey, dbTable, nil, { description = description })
    end

    GUI.CreateColorPickerCentered = function(self, parent, label, dbKey, dbTable, _onChange, description)
        if parent and parent._hasContent ~= nil then parent._hasContent = true end
        return create_captured_search_widget("colorpicker", parent, label, dbKey, dbTable, nil, { description = description })
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
        options_api.BuildSettingRow = function(parent, labelText, widget, desc, opts)
            register_widget_row_capture(widget, labelText)
            return original_build_setting_row(parent, labelText, widget, desc, opts)
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

    local hosted = {}
    for destination in registry:IterateDestinations() do
        local feature = registry:GetFeature(destination.featureId)
        if feature then
            queue[#queue + 1] = { featureId = feature.id, feature = feature, destination = destination }
            hosted[feature.id] = true
        end
    end
    -- Keep standalone provider/layout features searchable through their default
    -- route. Registered tile homes always take precedence over that fallback.
    for featureId, feature in registry:IterateFeatures() do
        if type(feature) == "table" and not hosted[featureId] and not feature.noSearch then
            queue[#queue + 1] = { featureId = featureId, feature = feature }
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

local function build_feature_search_context(feature, destinationContext)
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

    for key, value in pairs(destinationContext or {}) do context[key] = value end

    return context
end

local function create_timer_stub()
    return {
        Cancel = function() end,
    }
end

-- Capture lightweight navigation while the offline harvester renders pages.
-- Runtime menus consume this catalog without constructing settings controls.
local navigation_catalog = {}
local capturing_navigation_feature
local capturing_navigation_descriptor
local function NavigationRecord()
    local featureId = capturing_navigation_feature or (GUI._searchContext and GUI._searchContext.featureId)
    if not featureId then return end
    local record = navigation_catalog[featureId]
    if not record then
        record = { sections = {}, tabs = {} }
        navigation_catalog[featureId] = record
    end
    return record
end
local function CaptureNavigationSection(text)
    local record = NavigationRecord()
    if record and type(text) == "string" and text ~= "" then
        local sections = record.sections
        local tabKey = GUI._searchContext and GUI._searchContext.surfaceTabKey
        if not tabKey and capturing_navigation_descriptor and capturing_navigation_descriptor.getActiveTab then
            tabKey = capturing_navigation_descriptor.getActiveTab()
        end
        for _, tab in ipairs(record.tabs) do
            if tab.key == tabKey then sections = tab.sections; break end
        end
        local section
        for _, existing in ipairs(sections) do if existing.id == text then section = existing; break end end
        if not section then
            section = { id = text, label = text, contexts = {} }
            sections[#sections + 1] = section
        end
        local context = GUI._searchContext or {}
        local providerKey = context.providerKey
        if context.featureId == "cooldownManagerContainersPage" then
            providerKey = ns.QUI_CooldownManagerSettingsModel.GetNavigationContext(providerKey).providerKey
        end
        local found = false
        for _, existing in ipairs(section.contexts) do
            if existing.providerKey == providerKey and existing.surfaceUnitKey == context.surfaceUnitKey
                and existing.surfaceTypeKey == context.surfaceTypeKey then
                found = true
                break
            end
        end
        if not found then
            local order
            if context.featureId == "cooldownManagerContainersPage" then
                order = 1
                for _, other in ipairs(sections) do
                    for _, variant in ipairs(other.contexts) do
                        if variant.providerKey == providerKey and variant.surfaceUnitKey == context.surfaceUnitKey
                            and variant.surfaceTypeKey == context.surfaceTypeKey then
                            order = math.max(order, (variant.order or 0) + 1)
                        end
                    end
                end
            end
            section.contexts[#section.contexts + 1] = {
                providerKey = providerKey,
                surfaceUnitKey = context.surfaceUnitKey,
                surfaceTypeKey = context.surfaceTypeKey,
                order = order,
            }
        end
    end
end
local original_accent_label = ns.QUI_Options.CreateAccentDotLabel
ns.QUI_Options.CreateAccentDotLabel = function(parent, text, offset, skip)
    if not skip then
        local featureId = GUI._searchContext and GUI._searchContext.featureId
        if featureId == "minimap" or featureId == "datatextPanel" then
            GUI:SetSearchSection(text)
        end
        CaptureNavigationSection(text)
    end
    return original_accent_label(parent, text, offset, skip)
end
local original_surface_pages = GUI.RegisterTileSurfacePages
GUI.RegisterTileSurfacePages = function(self, body, descriptor)
    local record = NavigationRecord()
    if record and type(descriptor.getTabs) == "function" then
        capturing_navigation_descriptor = descriptor
        for _, tab in ipairs(descriptor.getTabs() or {}) do
            if type(tab.key) == "string" and type(tab.label) == "string" then
                local found = false
                for _, existing in ipairs(record.tabs) do if existing.key == tab.key then found = true; break end end
                if not found then
                    record.tabs[#record.tabs + 1] = { key = tab.key, label = tab.label, sections = {} }
                end
            end
        end
        return true
    end
    return original_surface_pages(self, body, descriptor)
end

local function capture_search_feature(feature, providerKey, contextLabel, destination, bindingContext)
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
    local context = build_feature_search_context(feature, destination and destination.searchContext)
    for key, value in pairs(bindingContext or {}) do context[key] = value end
    context.providerKey = providerKey or context.providerKey
    -- Dedicated bar pages retain their registered provider identity for module
    -- toggle routing and refresh. Extra & Zone hosts two providers together.
    if not context.providerKey and feature.id:match("^actionBars")
        and feature.lookupKeys and #feature.lookupKeys == 1 then
        context.providerKey = feature.lookupKeys[1]
    end
    local renderContext = {}
    for key, value in pairs(context) do renderContext[key] = value end
    if feature.model then renderContext.subTabName = nil end
    local host = create_stub_node("Frame", nil, false)
    host:SetSize(760, 1)
    host.RegisterSection = function(_, _, label) CaptureNavigationSection(label) end

    if C_Timer then
        C_Timer.After = function()
            return create_timer_stub()
        end
        C_Timer.NewTimer = function()
            return create_timer_stub()
        end
    end

    GUI:ClearSearchContext()
    capturing_navigation_feature = feature.id
    capturing_context_label = contextLabel
    local ok, err = xpcall(function()
        GUI:SetSearchContext(context)
        if context.sectionName then
            GUI:SetSearchSection(context.sectionName)
        end
        local options = {
            surface = "tile", width = 760, tileLayout = true,
            includePosition = true, providerKey = context.providerKey,
        }
        for key, value in pairs(destination and destination.renderOptions or {}) do options[key] = value end
        settings.SearchRoute.With(renderContext, function()
            renderer:RenderFeature(feature, host, options)
        end)
        local descriptor = capturing_navigation_descriptor
        if descriptor and type(descriptor.selectTab) == "function" then
            for _, tab in ipairs(descriptor.getTabs() or {}) do
                GUI:SetSearchContext(context)
                settings.SearchRoute.With(renderContext, function() descriptor.selectTab(tab.key) end)
            end
        end
        GUI:ClearSearchContext()
    end, debug.traceback)
    capturing_navigation_feature = nil
    capturing_navigation_descriptor = nil
    capturing_context_label = nil
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

local capture_model_search_tabs

local function capture_all_search_features()
    local settings = ns.Settings
    local renderer = settings and settings.Renderer
    local registry = settings and settings.Registry
    if not renderer or type(renderer.RenderFeature) ~= "function"
        or not registry or type(registry.IterateFeatures) ~= "function" then
        return false
    end

    for _, step in ipairs(build_search_capture_queue()) do
        if step and step.feature then
            local feature = step.feature
            if type(feature.model) == "function" or type(feature.model) == "table" then
                capture_model_search_tabs(feature, step.destination and step.destination.searchContext)
                capture_search_feature(feature, nil, nil, step.destination)
            elseif type(feature.getSearchContexts) == "function" then
                local previous = feature.getNavigationContext and feature.getNavigationContext()
                for _, variant in ipairs(feature.getSearchContexts()) do
                    capturing_navigation_only = true
                    assert(feature.searchNavigate(variant.searchContext), "unsupported feature context: " .. feature.id)
                    capturing_navigation_only = nil
                    capture_search_feature(feature, variant.searchContext.providerKey, variant.label, step.destination, variant.searchContext)
                end
                if previous then
                    capturing_navigation_only = true
                    feature.searchNavigate(previous)
                    capturing_navigation_only = nil
                end
            else
                capture_search_feature(feature, nil, nil, step.destination)
            end
        end
    end

    return #capture_errors == 0
end

local function capture_model_search_tab(feature, destinationContext, variant)
    local settings = ns.Settings
    local context = build_feature_search_context(feature, variant.searchContext)
    -- The outer host owns the route, including dual-home/stack destinations.
    for key, value in pairs(destinationContext or {}) do context[key] = value end
    context.subTabName = variant.tab.label
    local host = create_stub_node("Frame", nil, false)
    host:SetSize(760, 1)
    host.RegisterSection = function(_, _, label) CaptureNavigationSection(label) end

    GUI:ClearSearchContext()
    capturing_navigation_feature = feature.id
    capturing_context_label = variant.label
    GUI:SetSearchContext(context)
    local record = NavigationRecord()
    local found
    for _, tab in ipairs(record.tabs) do
        if tab.key == variant.tab.key then found = true; break end
    end
    if not found then
        record.tabs[#record.tabs + 1] = { key = variant.tab.key, label = variant.tab.label, sections = {} }
    end
    local ok, err = xpcall(function()
        settings.SearchRoute.With(context, function()
            variant.tab.render(host, variant.state)
        end)
    end, debug.traceback)
    capturing_navigation_feature = nil
    capturing_navigation_descriptor = nil
    capturing_context_label = nil
    GUI:ClearSearchContext()
    if not ok then
        capture_errors[#capture_errors + 1] = {
            featureId = feature.id,
            providerKey = table.concat({ context.providerKey or context.surfaceUnitKey
                or context.surfaceTypeKey or "", variant.tab.key }, ":"),
            error = err,
        }
    end
    return ok
end

capture_model_search_tabs = function(feature, destinationContext)
    local model = type(feature.model) == "function" and feature.model() or feature.model
    for _, variant in ipairs(ns.Settings.ModelKit.EnumerateSearchTabs(model)) do
        capture_model_search_tab(feature, destinationContext, variant)
    end
    return #capture_errors == 0
end

local function capture_custom_cdm_navigation()
    local containers = profile_db.ncdm.containers
    local key = "__navigation_sample"
    local previous = rawget(containers, key)
    local registry = ns.Settings.Registry
    local feature = registry:GetFeature("cooldownManagerContainersPage")
    local model = feature.model()
    local destinationContext
    for destination in registry:IterateDestinations() do
        if destination.featureId == feature.id then
            destinationContext = destination.searchContext
            break
        end
    end
    capturing_navigation_only = true
    -- These are conditional editor fixtures, not a duplicate destination list.
    for _, kind in ipairs({ "cooldown", "customBar", "aura", "auraBar" }) do
        for _, shape in ipairs({ "icon", "bar" }) do
            local base = kind == "aura" and "buff" or (kind == "auraBar" and "trackedBar" or "essential")
            local db = ns.Helpers.DeepCopy(ns.defaults.profile.ncdm[base])
            db.containerType, db.shape, db.builtIn = kind, shape, false
            containers[key] = db
            for _, variant in ipairs(ns.Settings.ModelKit.EnumerateSearchTabs(model)) do
                if variant.state.activeContainer == key then
                    capture_model_search_tab(feature, destinationContext, variant)
                end
            end
        end
    end
    containers[key] = previous
    capturing_navigation_only = nil
end

-- The per-element aura config controls (Aura Type, Filter Mode, classifications,
-- whitelist, blacklist, duration text, Display Type, the bar.* fields, per-spell
-- Only Mine, etc.) render inside the unified-auras editor only for the element
-- that is currently EXPANDED, and the editor opens collapsed by default -- so the
-- normal RenderAurasTab harvest (which renders once with no selection) never sees
-- those labels. Here we drive AurasEditor.RenderAuras directly, once per element
-- variant, each time with a single-element bucket and forceSelectedIndex = 1 so
-- the element renders expanded. The variant matrix covers every conditional
-- branch (each filterMode, each tracked displayType, multi-spell per-spell rows).
-- Expanded-content fixtures describe inner editor state; their outer routes
-- come from the same registrations as normal page capture.
local function fixture_search_contexts(bindingsByFeature)
    local contexts = {}
    local registry = ns.Settings.Registry
    for destination in registry:IterateDestinations() do
        local binding = bindingsByFeature[destination.featureId]
        if binding then
            local feature = registry:GetFeature(destination.featureId)
            local context = build_feature_search_context(feature, destination.searchContext)
            for key, value in pairs(binding) do context[key] = value end
            if feature.model and context.surfaceTabKey then
                local model = type(feature.model) == "function" and feature.model() or feature.model
                local tab = ns.Settings.ModelKit.GetTabDefinition(model, context.surfaceTabKey)
                if tab then context.subTabName = tab.label end
            end
            contexts[#contexts + 1] = context
        end
    end
    return contexts
end

-- Observe capabilities and routes supplied by every mounted editor. New hosts
-- automatically participate; host-specific copies of the editor matrix drift.
local function aura_capability_identity(value)
    if type(value) ~= "table" then return type(value) == "function" and "function" or tostring(value) end
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do parts[#parts + 1] = tostring(key) .. "=" .. aura_capability_identity(value[key]) end
    return table.concat(parts, ";")
end
local aura_editor_hosts = {}
local render_aura_editor = ns.QUI_AuraElementsEditor.RenderAuras
ns.QUI_AuraElementsEditor.RenderAuras = function(host, db, specID, changed, options)
    if not capturing_navigation_only then
        local context = copy_capture_entry(GUI._searchContext or {})
        local caps = options and options.capabilities
        local parts = {}
        for _, field in ipairs({"tileId", "subPageIndex", "featureId", "providerKey", "surfaceTabKey", "surfaceUnitKey", "surfaceTypeKey"}) do
            parts[#parts + 1] = tostring(context[field] or "")
        end
        parts[#parts + 1] = aura_capability_identity(caps)
        aura_editor_hosts[table.concat(parts, "|")] = {context = context, capabilities = caps}
    end
    return render_aura_editor(host, db, specID, changed, options)
end

local function capture_expanded_aura_editors()
    local E = ns.AuraElements
    local keys = {}
    for key in pairs(aura_editor_hosts) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local sample = aura_editor_hosts[key]
        local caps, variants = sample.capabilities, {}
        if not caps or not caps.elementTypes or caps.elementTypes.filterStrip then
            for _, auraType in ipairs({"HELPFUL", "HARMFUL"}) do
                for _, mode in ipairs({"off", "flags", "classify", "whitelist"}) do
                    local element = E.NewFilterStripElement(auraType)
                    element.filterMode = mode
                    element.casterName = {showRealmName = false, useClassColors = true, fontSize = 10,
                        anchor = "BOTTOM", offsetX = 0, offsetY = 1, color = {1, 1, 1, 1}}
                    element.pandemicGlow = {style = "steady", color = {1, 0.85, 0.2, 1}}
                    variants[#variants + 1] = element
                end
            end
        end
        if not caps or not caps.elementTypes or caps.elementTypes.tracked then
            for _, shape in ipairs({"icon", "square", "bar", "healthTint"}) do
                if not caps or not caps.trackedDisplayTypes or caps.trackedDisplayTypes[shape] then
                    variants[#variants + 1] = E.NewTrackedElement({12345, 67890}, shape)
                end
            end
        end
        if not caps or not caps.elementTypes or caps.elementTypes.missingRaidBuff then
            for _, automatic in ipairs({true, false}) do
                local element = E.NewMissingRaidBuffElement()
                element.classDetection = automatic
                variants[#variants + 1] = element
            end
        end
        for _, element in ipairs(variants) do
            local host = create_stub_node("Frame", nil, false)
            host:SetSize(760, 1)
            GUI:ClearSearchContext()
            GUI:SetSearchContext(sample.context)
            local ok, err = xpcall(function()
                ns.Settings.SearchRoute.With(sample.context, function()
                    render_aura_editor(host, {enabled = true, elements = {["*"] = {element}}}, "*", function() end,
                        {forceSelectedIndex = 1, capabilities = caps})
                end)
            end, debug.traceback)
            GUI:ClearSearchContext()
            if not ok then
                capture_errors[#capture_errors + 1] = {featureId = sample.context.featureId, providerKey = key, error = err}
            end
        end
    end
    return #capture_errors == 0
end

local function capture_aura_displays_elements()
    local AurasEditor = ns.QUI_AuraElementsEditor
    local E = ns.AuraElements
    local AD = ns.QUI_AuraDisplays
    local Page = ns.QUI_AuraDisplaysOptions
    if type(AurasEditor) ~= "table"
        or type(AurasEditor.RenderAuras) ~= "function"
        or type(E) ~= "table"
        or type(E.NewFilterStripElement) ~= "function"
        or type(E.NewTrackedElement) ~= "function"
        or type(AD) ~= "table"
        or type(AD.DefaultBucket) ~= "function"
        or type(ns.QUI_AuraDisplayPickers) ~= "table" then
        return true
    end

    local contexts = fixture_search_contexts({ aurasDisplaysPage = { providerKey = "detail" } })
    local function render(providerKey, fn)
        for _, context in ipairs(contexts) do
        local host = create_stub_node("Frame", nil, false)
        host:SetSize(760, 1)

        GUI:ClearSearchContext()
        local ok, err = xpcall(function()
            GUI:SetSearchContext(context)
            ns.Settings.SearchRoute.With(context, fn, host)
            GUI:ClearSearchContext()
        end, debug.traceback)
        GUI:ClearSearchContext()

        if not ok then
            capture_errors[#capture_errors + 1] = {
                featureId = "aurasDisplaysPage",
                providerKey = providerKey,
                error = err,
            }
        end
        end
    end

    if type(Page) == "table" and type(Page._BuildGeneralTab) == "function"
        and type(Page._BuildLoadTab) == "function"
        and type(Page._BuildAlertsTab) == "function" then
        for _, unit in ipairs({ "player", "target" }) do
            local display = {
                id = "d1",
                name = "Display",
                enabled = true,
                unitMode = "token",
                unit = unit,
                load = { classes = {}, specs = {}, roles = {}, encounters = {} },
                auras = {},
            }
            render("general:" .. unit, function(host)
                Page._BuildGeneralTab(host, nil, display)
            end)
            render("load:" .. unit, function(host)
                Page._BuildLoadTab(host, nil, display)
            end)
            render("auras:" .. unit, function(host)
                Page._BuildAurasTab(host, nil, display)
            end)
            local tracked = E.NewTrackedElement({ 12345 }, "icon")
            display.auras = { enabled = true, elements = { ["*"] = { tracked } } }
            render("alerts:" .. unit, function(host)
                Page._BuildAlertsTab(host, nil, display)
            end)
        end

    end
    if type(Page) == "table" and type(Page._BuildGroupTab) == "function"
        and type(AD.GetGroup) == "function" then
        local searchGroup = AD.GetGroup("Search Group", true)
        if searchGroup then searchGroup._quiTransientOptionsProxy = true end
        render("group", function(host)
            Page._BuildGroupTab(host, nil, "Search Group")
        end)
    end


    return #capture_errors == 0
end

-- Traverse the registered datatext choices so the provider itself exposes
-- conditional Spec/Time/Alts/Currencies settings. Keep callback-only controls
-- unbound, and restore the generator profile and registry after harvesting.
local function capture_chat_tab_variants()
    local feature = ns.Settings.Registry:GetFeature("chatFrame1")
    local chat = profile_db.chat
    local previous = rawget(chat, "defaultTabPerSpec")
    for destination in ns.Settings.Registry:IterateDestinations() do
        if destination.featureId == feature.id then
            for _, perSpec in ipairs({false, true}) do
                chat.defaultTabPerSpec = perSpec
                capture_search_feature(feature, nil, nil, destination)
            end
        end
    end
    chat.defaultTabPerSpec = previous
end

local function capture_datatext_variants()
    local registry = ns.Settings.Registry
    local feature = registry:GetFeature("datatextPanel")
    local destination
    for registered in registry:IterateDestinations() do
        if registered.featureId == feature.id then destination = registered; break end
    end
    assert(destination, "Datatext tile destination must be registered before capture")
    local datatext = profile_db.datatext
    local selection = ns.QUI_DatatextPanelSelection
    local previousSlots = datatext.slots
    local previousPanel = selection.getActivePanel(profile_db)
    local previousRegistry = ns.Addon.Datatexts
    local ok, err = xpcall(function()
        assert(loadfile("modules/datatexts/datatexts.lua"))(ADDON_NAME, ns)
        assert(loadfile("modules/datatexts/providers_extra.lua"))(ADDON_NAME, ns)
        selection.setActivePanel("datatextPanel", profile_db)
        local definitions = ns.Addon.Datatexts:GetAll()
        for first = 1, #definitions, 3 do
            datatext.slots = {}
            for index = first, math.min(first + 2, #definitions) do
                datatext.slots[index - first + 1] = definitions[index].id
            end
            capture_search_feature(feature, nil, nil, destination)
        end
    end, debug.traceback)
    datatext.slots = previousSlots
    selection.setActivePanel(previousPanel, profile_db)
    ns.Addon.Datatexts = previousRegistry
    if not ok then
        capture_errors[#capture_errors + 1] = { featureId = "datatextPanel", error = err }
    end
end

local function capture_spell_reminder_fixture()
    if not ns.SpellReminderOptions then return end
    for _, context in ipairs(fixture_search_contexts({ spellRemindersPage = {} })) do
        GUI:SetSearchContext(context)
        local host = create_stub_node("Frame", nil, false)
        host:SetSize(760, 1)
        ns.Settings.SearchRoute.With(context, function()
            if ns.SpellReminderOptions.GetTabs then
                GUI:RegisterTileSurfacePages(host, {
                    getTabs = function() return ns.SpellReminderOptions.GetTabs({ pi = true }) end,
                })
            end
            ns.SpellReminderOptions.CaptureSearch(host)
        end)
        capturing_navigation_descriptor = nil
        GUI:ClearSearchContext()
    end
end


install_search_capture_overrides()
GUI:ResetStaticSearchIndex()
ns.QUI_Options.RegisterAllFeatureTiles(frame)
capture_all_search_features()
do
    local originalClient = ns.Client
    ns.Client = { isForever = true }
    capture_search_feature(ns.Settings.Registry:GetFeature("skinningPage"))
    ns.Client = originalClient
end
capture_custom_cdm_navigation()
capture_aura_displays_elements()
capture_expanded_aura_editors()
capture_datatext_variants()
capture_chat_tab_variants()

-- The reminder editor starts empty, so render its configurable tabs against
-- a transient PI preset to index them before a player creates a reminder.
capture_spell_reminder_fixture()


collect_feature_keywords()

local function clear_non_plain_arrays_before_route_seed()
    local function plain_array(list)
        if type(list) ~= "table" or getmetatable(list) ~= nil then return {} end
        return list
    end

    local function is_scalar(value)
        local value_type = type(value)
        return value == nil
            or value_type == "string"
            or value_type == "number"
            or value_type == "boolean"
    end

    local function filter_registry_entries(list)
        local filtered = {}
        for _, entry in ipairs(list) do
            if type(entry) == "table"
                and getmetatable(entry) == nil
                and type(entry.label) == "string"
                and is_scalar(entry.navType)
                and is_scalar(entry.tabIndex)
                and is_scalar(entry.subTabIndex)
                and is_scalar(entry.tileId)
                and is_scalar(entry.subPageIndex)
                and is_scalar(entry.tabName)
                and is_scalar(entry.subTabName)
                and is_scalar(entry.sectionName)
                and is_scalar(entry.featureId)
                and is_scalar(entry.providerKey)
                and is_scalar(entry.category)
                and is_scalar(entry.surfaceTabKey)
                and is_scalar(entry.surfaceUnitKey)
                and is_scalar(entry.surfaceTypeKey) then
                filtered[#filtered + 1] = entry
            end
        end
        return filtered
    end

    if type(GUI.StaticSettingsRegistry) ~= "table" or getmetatable(GUI.StaticSettingsRegistry) ~= nil then
        GUI.StaticSettingsRegistry = {}
    end
    if type(GUI.StaticNavigationRegistry) ~= "table" or getmetatable(GUI.StaticNavigationRegistry) ~= nil then
        GUI.StaticNavigationRegistry = {}
    end
    GUI.StaticSettingsRegistry = filter_registry_entries(plain_array(GUI.StaticSettingsRegistry))
    GUI.StaticNavigationRegistry = filter_registry_entries(plain_array(GUI.StaticNavigationRegistry))

    if type(frame._tiles) ~= "table" or getmetatable(frame._tiles) ~= nil then
        frame._tiles = {}
        return
    end
    frame._tiles = plain_array(frame._tiles)
    local filtered_tiles = {}
    for _, tile in ipairs(frame._tiles) do
        local config = tile and tile.config
        if type(tile) == "table"
            and type(tile.id) == "string"
            and type(config) == "table"
            and getmetatable(config) == nil
            and type(config.name) == "string" then
            if type(config.subPages) == "table"
                and getmetatable(config.subPages) ~= nil then
                config.subPages = nil
            elseif type(config.subPages) == "table" then
                local sub_pages = {}
                for _, sub_page in ipairs(plain_array(config.subPages)) do
                    if type(sub_page) == "table"
                        and getmetatable(sub_page) == nil
                        and type(sub_page.name) == "string" then
                        sub_pages[#sub_pages + 1] = sub_page
                    end
                end
                config.subPages = sub_pages
            end
            filtered_tiles[#filtered_tiles + 1] = tile
        end
    end
    frame._tiles = filtered_tiles
end

clear_non_plain_arrays_before_route_seed()

if type(GUI.SeedStaticSearchRoutesFromTiles) == "function" then
    GUI:SeedStaticSearchRoutesFromTiles(frame)
end

local swing_route = ns.Settings.Registry:GetFeature("swingTimersPage").nav
for _, entry in ipairs(GUI.StaticNavigationRegistry) do
    if entry.tileId == swing_route.tileId and entry.subPageIndex == swing_route.subPageIndex then
        entry.featureId = entry.featureId or "swingTimersPage"
    end
end

-- Phase 1+ Modules Control Center: emit moduleToggle navigation entries
-- for features that declare moduleEntry. These power the [Module] badge +
-- inline pill rendering in the global search dropdown (see Task 9).
local function find_module_enabled_route(featureId)
    local wantPath = "profile." .. featureId
    local fallbackTile, fallbackSubPage
    for _, row in ipairs(GUI.StaticSettingsRegistry or {}) do
        if row.providerKey == featureId
            and type(row.tileId) == "string"
            and row.tileId ~= "" then
            local descriptor = row.widgetDescriptor
            if type(descriptor) == "table"
                and descriptor.dbPath == wantPath
                and descriptor.dbKey == "enabled" then
                return row.tileId, row.subPageIndex
            end
            if not fallbackTile then
                fallbackTile, fallbackSubPage = row.tileId, row.subPageIndex
            end
        end
    end
    return fallbackTile, fallbackSubPage
end

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
            local tileId = "global"
            local subPageIndex = 3    -- Modules sub-page index in General tile's
                                      -- subPages array. See options/tiles/global.lua
                                      -- — order is profiles, pinnedGlobals, modules,
                                      -- importExport, thirdParty, clickCast.
            local hiddenOk, hiddenFromToggles = pcall(entry.hidden)
            if type(entry.hidden) == "function" and hiddenOk and hiddenFromToggles then
                local routeTile, routeSubPage = find_module_enabled_route(featureId)
                if routeTile then
                    tileId = routeTile
                    subPageIndex = routeSubPage
                end
            end
            GUI:RegisterSearchNavigation("moduleToggle", {
                label = label,
                featureId = featureId,
                tileId = tileId,
                subPageIndex = subPageIndex,
                keywords = { label, caption, group, "module" },
            })
            emitted = emitted + 1
        end
    end
    return emitted
end

local emitted_module_entries = emit_module_toggle_entries()

local function copy_table(source, seen, depth)
    if type(source) ~= "table" then
        return source
    end
    depth = depth or 0
    if depth > 5 then
        return nil
    end
    if getmetatable(source) ~= nil then
        return nil
    end
    seen = seen or {}
    if seen[source] then
        return nil
    end
    seen[source] = true
    local copy = {}
    local copied = 0
    for key, value in pairs(source) do
        copied = copied + 1
        if copied > 200 then
            break
        end
        copy[key] = copy_table(value, seen, depth + 1)
    end
    seen[source] = nil
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
        entry.surfaceTypeKey or "",
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

local previousFrame = GUI.MainFrame
GUI.MainFrame = frame
for _, entries in ipairs({ settings_entries, navigation_entries }) do
    for _, entry in ipairs(entries) do
        local route = GUI:ResolveV2SectionNavigation(entry.tabIndex, entry.sectionName, entry.tileId)
        if route then
            entry.tileId = route.tileId
            entry.subPageIndex = route.subPageIndex
            local tile = GUI:FindV2TileByID(frame, route.tileId)
            entry.subTabName = tile.config.subPages[route.subPageIndex].name
        end
    end
end
GUI.MainFrame = previousFrame

-- Records are emitted POSITIONALLY under a per-group schema header, and the
-- whole payload ships as a long-bracket string. The keyed, indented table this
-- replaced was 3,179,748 bytes of which ~69% was `["field"] = ` scaffolding,
-- indentation and newlines repeated once per record; and every byte of it was
-- compiled by the Lua parser whether or not anyone opened the search box.
--
-- Underscore-prefixed keys (_normLabel, _rawKeywords, …) are dropped by
-- pack_emit at every level. GUI:PrepareSearchEntry attaches them as the
-- registry is populated, so the headless harvest sees them too — but they are
-- computed from the ENGLISH strings and the runtime recomputes them after
-- localizing, so serializing them would ship values that are wrong for every
-- non-enUS client.
local pack_emit = assert(loadfile("tools/lib/pack_emit.lua"),
    "tools/lib/pack_emit.lua not found (run from the repository root)")()

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

local settings_schema   = pack_emit.derive_schema(settings_entries)
local navigation_schema = pack_emit.derive_schema(navigation_entries)

local packed = table.concat({
    "{settings=", pack_emit.rows(settings_entries, settings_schema),
    ",navigation=", pack_emit.rows(navigation_entries, navigation_schema),
    ",version=1}",
})

pack_emit.assert_long_bracket_safe(packed, "]==]")

-- Two things about the emitted file that used to be explained in comments
-- INSIDE it. The addon tree is kept comment-free (tools/strip_comments.sh), and
-- a generator that emits comments makes its output permanently "stale" against
-- that, so the explanations live here instead:
--
--   * ns.QUI_SearchCacheSchema — records are POSITIONAL: row[i] is the field
--     named schema[i]. An absent field is `false`, not a hole, so every row has
--     the schema's arity; a trailing nil would truncate the array and shift
--     every later read.
--   * ns.QUI_SearchCachePacked — a long-bracket STRING, so loading the file
--     lexes ONE token. QUI_Options/framework.lua compiles it on first search
--     via ns.Unpack.
--
-- Only the "do not edit by hand" banner is still emitted: it is what stops an
-- agent hand-editing generated output that the next regen silently eats.
local output = table.concat({
    "-- Generated by tools/generate_search_cache.lua; do not edit by hand.",
    "local ADDON_NAME, ns = ...",
    "",
    "ns.QUI_OptionsNavigationCatalog = " .. pack_emit.quote(navigation_catalog),
    "",
    "ns.QUI_SearchCacheSchema = {",
    "    settings = " .. pack_emit.schema(settings_schema) .. ",",
    "    navigation = " .. pack_emit.schema(navigation_schema) .. ",",
    "}",
    "",
    "ns.QUI_SearchCachePacked = [==[",
    packed,
    "]==]",
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
