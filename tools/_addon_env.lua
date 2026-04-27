--[[
  _addon_env.lua

  Shared headless environment for QUI Lua tooling. Stubs the WoW globals
  the bundled libs and addon files reach for at module-load time, then
  loads the libs and a slice of core/ in dependency order.

  Public API:
    local env = dofile("tools/_addon_env.lua")
    env.LoadLibs()                        -- bundled libs (LibStub, AceDB, etc.)
    local ns = env.LoadCore()             -- QUI core slice; returns shared ns
    env.ApplySeed(seedTable)              -- _G.QUI_DB := deep-copy of seedTable
    local h = env.BuildHarness()          -- fresh AceDB on current _G.QUI_DB;
                                          -- returns { db, QUI, QUICore, ns, defaults }
    local h = env.LoadHarness(seedTable)  -- ApplySeed + BuildHarness combo

  Path-independent: resolves bundled libs relative to its own location.
]]

local M = {}

local function ScriptDir()
    local p = (arg and arg[0]) or ""
    p = p:gsub("\\", "/")
    local dir = p:match("(.*/)")
    if dir == nil or dir == "" then return "./" end
    return dir
end

-- Repo root is one directory up from tools/_addon_env.lua. When invoked as
-- `lua -e ...` (no script file), arg[0] is nil — fall back to "./" so the
-- documented "run from repo root" workflow resolves libs/ correctly.
local REPO_ROOT = (arg and arg[0]) and (ScriptDir() .. "../") or "./"
M.REPO_ROOT = REPO_ROOT

----------------------------------------------------------------------------
-- WoW string globals
----------------------------------------------------------------------------
strmatch = string.match
strfind  = string.find
strsub   = string.sub
strlower = string.lower
strupper = string.upper
strrep   = string.rep
strtrim  = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strjoin  = function(sep, ...)
    local n = select("#", ...)
    local out = {}
    for i = 1, n do out[i] = tostring(select(i, ...)) end
    return table.concat(out, sep)
end
tinsert  = table.insert
tremove  = table.remove
tconcat  = table.concat
wipe     = function(t) for k in pairs(t) do t[k] = nil end return t end
geterrorhandler = function() return print end

----------------------------------------------------------------------------
-- WoW API stubs (constants — just have to satisfy module-init reads)
----------------------------------------------------------------------------
function CreateFrame(_)
    return {
        RegisterEvent     = function() end,
        UnregisterEvent   = function() end,
        SetScript         = function() end,
        IsEventRegistered = function() return false end,
    }
end

function GetRealmName()      return "TestRealm"           end
function UnitName()          return "TestChar"            end
function UnitClass()         return nil, "MAGE"           end
function UnitRace()          return nil, "Human"          end
function UnitFactionGroup()  return "Alliance"            end
function GetLocale()         return "enUS"                end
function GetCurrentRegion()  return 1                      end

-- Combat-secret APIs (12.0+) — stub to "not secret"
_G.issecretvalue   = function() return false end
_G.canaccesstable  = function() return true end

-- C_AddOns / similar tables — just empty so init.lua-style lookups don't error
_G.C_AddOns = _G.C_AddOns or { GetAddOnMetadata = function() return nil end }

----------------------------------------------------------------------------
-- Library loading (AceDB needs LibStub + CallbackHandler in scope)
----------------------------------------------------------------------------
local LIBS_LOADED = false

local function LoadLibs()
    if LIBS_LOADED then return end
    local libsRoot = REPO_ROOT .. "libs"

    dofile(libsRoot .. "/LibStub/LibStub.lua")
    dofile(libsRoot .. "/CallbackHandler-1.0/CallbackHandler-1.0.lua")
    dofile(libsRoot .. "/AceDB-3.0/AceDB-3.0.lua")
    dofile(libsRoot .. "/AceSerializer-3.0.lua")
    dofile(libsRoot .. "/LibDeflate/LibDeflate.lua")

    LIBS_LOADED = true
end

M.LoadLibs = LoadLibs

----------------------------------------------------------------------------
-- Addon file loading
--
-- QUI files use `local ADDON_NAME, ns = ...` to receive the addon name and
-- shared namespace from the WoW addon loader. We replicate that by calling
-- loadfile() and invoking the chunk with our own (name, ns) pair.
----------------------------------------------------------------------------

local function LoadAddonFile(relPath, addonName, ns)
    local fullPath = REPO_ROOT .. relPath
    local chunk, err = loadfile(fullPath)
    if not chunk then
        error("Failed to load " .. fullPath .. ": " .. tostring(err))
    end
    return chunk(addonName, ns)
end

M.LoadAddonFile = LoadAddonFile

local CORE_LOADED = false
local SHARED_NS

local function LoadCore()
    if CORE_LOADED then return SHARED_NS end
    LoadLibs()

    -- Fake _G.QUI before any core file loads — compatibility.lua attaches
    -- methods to it (function QUI:BackwardsCompat()), and migrations.lua
    -- exposes itself on it. DebugPrint is defined on the real AceAddon
    -- object in init.lua but not loaded here — stub it as a no-op so
    -- BackwardsCompat can call self:DebugPrint() without erroring.
    _G.QUI = _G.QUI or {}
    _G.QUI.DebugPrint = _G.QUI.DebugPrint or function() end

    SHARED_NS = {}
    SHARED_NS.Addon = {}  -- profile_io.lua does `local QUICore = ns.Addon`

    -- Load order matches modules.xml: utils first, then defaults, then
    -- migration / compat / io machinery.
    LoadAddonFile("core/utils.lua",         "QUI", SHARED_NS)
    LoadAddonFile("core/defaults.lua",      "QUI", SHARED_NS)
    LoadAddonFile("core/migrations.lua",    "QUI", SHARED_NS)
    LoadAddonFile("core/compatibility.lua", "QUI", SHARED_NS)
    LoadAddonFile("core/profile_io.lua",    "QUI", SHARED_NS)

    CORE_LOADED = true
    return SHARED_NS
end

M.LoadCore = LoadCore

----------------------------------------------------------------------------
-- Harness construction
----------------------------------------------------------------------------

local function ApplySeed(seedTable)
    -- Replace _G.QUI_DB / _G.QUIDB with deep clones of the seed.
    local function DeepCopy(v)
        if type(v) ~= "table" then return v end
        local copy = {}
        for k, vv in pairs(v) do copy[k] = DeepCopy(vv) end
        return copy
    end
    if seedTable and seedTable.QUI_DB then
        _G.QUI_DB = DeepCopy(seedTable.QUI_DB)
    else
        _G.QUI_DB = nil
    end
    if seedTable and seedTable.QUIDB then
        _G.QUIDB = DeepCopy(seedTable.QUIDB)
    else
        _G.QUIDB = nil
    end
end

M.ApplySeed = ApplySeed

local function BuildHarness(opts)
    opts = opts or {}
    local ns = LoadCore()
    local AceDB = LibStub("AceDB-3.0")

    -- core/defaults.lua sets ns.defaults (SHARED_NS.defaults); init.lua
    -- would merge that into QUI.defaults in WoW, but in the harness we use
    -- ns.defaults directly since we don't load init.lua.
    local defaults = ns.defaults
    if type(defaults) ~= "table" or type(defaults.profile) ~= "table" then
        error("Expected ns.defaults.profile to be a table after LoadCore — check core/defaults.lua")
    end

    local db = AceDB:New("QUI_DB", defaults, "Default")

    -- Make QUICore + QUI:BackwardsCompat() callable like in WoW.
    _G.QUI.db = db
    ns.Addon.db = db
    _G.QUI.QUICore = ns.Addon

    return {
        db = db,
        ns = ns,
        QUI = _G.QUI,
        QUICore = ns.Addon,
        defaults = defaults,
    }
end

M.BuildHarness = BuildHarness

local function LoadHarness(seedTable, opts)
    ApplySeed(seedTable)
    return BuildHarness(opts)
end

M.LoadHarness = LoadHarness

return M
