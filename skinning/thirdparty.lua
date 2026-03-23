---------------------------------------------------------------------------
-- QUI Third-Party Frame Cleanup
-- Suppresses white backdrops and visible NineSlice borders on frames
-- that QUI's per-frame skinning modules don't cover (typically from
-- other loaded addons). Runs a delayed scan after login and re-scans
-- when new addons load.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase

local issecretvalue = issecretvalue

-- Weak-keyed set of frames we've already processed
local processed = setmetatable({}, { __mode = "k" })
local initialized = false

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function IsEnabled()
    local db = QUI.db and QUI.db.profile
    return db and db.general and db.general.skinThirdParty ~= false
end

--- Prefix set for O(1) lookup instead of pattern matches.
--- Keys are known Blizzard/QUI frame name prefixes.
local KNOWN_PREFIXES = {}
for _, prefix in ipairs({
    "QUI", "Quazii", "Blizzard_", "GameTooltip", "ItemRef", "Interface",
    "Minimap", "PlayerFrame", "TargetFrame", "ChatFrame", "Character",
    "Professions", "AuctionHouse", "LFG", "PVE", "PVP", "EditMode", "DropDown",
    "Loot", "Group", "Merchant", "Mail", "Gossip", "Quest", "Friends",
    "World", "Encounter", "Collections", "Spell", "Talent", "Inspect",
    "Trade", "Addon", "Ready", "Queue", "Flyout", "Objective", "Scenario",
    "Settings", "Help", "Garrison", "Achievement", "Calendar", "Craft",
    "Wardrobe", "Azerite", "Scrapping", "Community", "Club", "Cinematic",
    "NamePlate", "Tooltip", "Recap", "Arena", "Battlefield", "Honor",
    "Barber", "Generic", "Channel", "Color", "Macro", "KeyBinding",
    "Movie", "Splash", "Taxi", "Trainer", "Petition", "Guild", "Tabard",
    "Bank", "Void", "Item", "Socket", "Transmogrify", "Obliterum",
}) do
    KNOWN_PREFIXES[prefix] = true
end

-- Sorted unique prefix lengths for cascading sub() lookups
local PREFIX_LENGTHS
do
    local seen = {}
    PREFIX_LENGTHS = {}
    for prefix in pairs(KNOWN_PREFIXES) do
        local len = #prefix
        if not seen[len] then
            seen[len] = true
            PREFIX_LENGTHS[#PREFIX_LENGTHS + 1] = len
        end
    end
    table.sort(PREFIX_LENGTHS)
end

local strsub = string.sub

--- Returns true if the frame name matches a known Blizzard/QUI prefix
--- so we don't accidentally suppress intentional Blizzard NineSlices
--- that QUI simply hasn't skinned.
--- Uses cascading sub()+set-lookup: ~8 hash probes instead of 18 find() calls.
local function IsBlizzardOrQUIFrame(name)
    if type(name) ~= "string" then return false end
    for _, len in ipairs(PREFIX_LENGTHS) do
        if KNOWN_PREFIXES[strsub(name, 1, len)] then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Suppress a single frame's white backdrop / visible NineSlice
---------------------------------------------------------------------------

local suppressingBackdrop = false

local function SuppressFrame(f)
    local isS = issecretvalue

    -- White backdrop → darken
    if f.GetBackdropColor then
        local rok, r, g, b = pcall(f.GetBackdropColor, f)
        if rok and not isS(r) and r and r > 0.9 and g > 0.9 and b > 0.9 then
            local hok, h = pcall(f.GetHeight, f)
            if hok and not isS(h) and h and h > 10 then
                suppressingBackdrop = true
                pcall(f.SetBackdropColor, f, 0.05, 0.05, 0.05, 0.95)
                pcall(f.SetBackdropBorderColor, f, 0, 0, 0, 1)
                suppressingBackdrop = false
                processed[f] = true
            end
        end
    end

    -- Orphaned overlay: backdropInfo set with bgFile but backdropColor nil →
    -- CENTER piece renders with default white vertex color.
    -- Only flag when bgFile is present (border-only backdrops have no background to be white).
    if f.backdropInfo and f.backdropInfo.bgFile and not f.backdropColor and f.GetBackdropColor then
        local hok, h = pcall(f.GetHeight, f)
        if hok and not isS(h) and h and h > 10 then
            suppressingBackdrop = true
            pcall(f.SetBackdropColor, f, 0.05, 0.05, 0.05, 0.95)
            pcall(f.SetBackdropBorderColor, f, 0, 0, 0, 1)
            suppressingBackdrop = false
            processed[f] = true
        end
    end

    -- Visible NineSlice → hide
    if f.NineSlice then
        local aok, a = pcall(f.NineSlice.GetAlpha, f.NineSlice)
        if aok and not isS(a) and a and a > 0 then
            pcall(f.NineSlice.SetAlpha, f.NineSlice, 0)
            processed[f] = true
        end
    end
end

-- Weak-keyed cache for IsBlizzardOrQUIFrame results.
-- Frame names are immutable, so the result never changes per frame identity.
-- SkinBase.IsSkinned is checked live (it can change as QUI skins frames).
local _blizzFrameCache = setmetatable({}, { __mode = "k" })

--- Returns true if a frame should be left alone (Blizzard, QUI, or
--- already handled by a per-frame skinning module).
local function ShouldSkipFrame(f)
    if SkinBase.IsSkinned(f) then return true end
    -- Skip QUI-managed frames that have backup color fields (set by
    -- SkinBase.CreateBackdrop, ApplyFullBackdrop, tooltip overlays, etc.)
    if f._quiBgR then return true end
    -- Skip frames that have a QUI backdrop child (SkinBase.CreateBackdrop
    -- stores the child in a weak-keyed table keyed by parent frame)
    if SkinBase.GetBackdrop(f) then return true end
    local cached = _blizzFrameCache[f]
    if cached ~= nil then return cached end
    local result = IsBlizzardOrQUIFrame(f:GetName())
    _blizzFrameCache[f] = result
    return result
end

---------------------------------------------------------------------------
-- Core scan
---------------------------------------------------------------------------

local function ScanAndSuppress()
    if not IsEnabled() then return end

    local isS = issecretvalue
    local f = EnumerateFrames()
    while f do
        if not processed[f] and not ShouldSkipFrame(f) then
            local ok, vis = pcall(f.IsVisible, f)
            if ok and not isS(vis) then
                if vis then
                    -- Visible frame: full suppression (backdrop + NineSlice)
                    SuppressFrame(f)
                elseif f.GetBackdropColor then
                    -- Hidden frame with backdrop: pre-emptively fix white/orphaned
                    -- backdrops so they don't flash white when shown later
                    SuppressFrame(f)
                end
            end
        end
        f = EnumerateFrames(f)
    end
end

---------------------------------------------------------------------------
-- Real-time hook — catch white backdrops set after the initial scan
---------------------------------------------------------------------------

if BackdropTemplateMixin and BackdropTemplateMixin.SetBackdropColor then
    hooksecurefunc(BackdropTemplateMixin, "SetBackdropColor", function(self, r, g, b)
        if suppressingBackdrop then return end
        if not initialized or not IsEnabled() then return end
        -- Fast path: skip non-white colors immediately (most common case).
        -- Color check is 3 number comparisons vs ShouldSkipFrame's string matching.
        local isS = issecretvalue
        if isS(r) then return end
        if not r or r <= 0.9 or not g or g <= 0.9 or not b or b <= 0.9 then return end
        if processed[self] then
            -- Frame was already processed but just got its color reset —
            -- clear the processed flag so we re-evaluate.
            processed[self] = nil
        end
        if ShouldSkipFrame(self) then return end
        local hok, h = pcall(self.GetHeight, self)
        if hok and not isS(h) and h and h > 10 then
            suppressingBackdrop = true
            pcall(self.SetBackdropColor, self, 0.05, 0.05, 0.05, 0.95)
            pcall(self.SetBackdropBorderColor, self, 0, 0, 0, 1)
            suppressingBackdrop = false
            processed[self] = true
        end
    end)
end

---------------------------------------------------------------------------
-- Real-time hook — catch orphaned overlays (SetBackdrop without SetBackdropColor)
---------------------------------------------------------------------------

-- Weak-keyed pending set for frames that need deferred orphan check.
-- After SetBackdrop, backdropColor is always nil until SetBackdropColor runs.
-- We defer the check to give callers time to call SetBackdropColor.
local pendingOrphanCheck = setmetatable({}, { __mode = "k" })
local orphanTimerRunning = false

local function ProcessPendingOrphans()
    orphanTimerRunning = false
    local isS = issecretvalue
    for f in pairs(pendingOrphanCheck) do
        -- If backdropColor was set in the meantime, skip
        if f.backdropInfo and f.backdropInfo.bgFile and not f.backdropColor then
            if f._quiBgR then
                -- QUI frame with backup colors: recover
                suppressingBackdrop = true
                pcall(f.SetBackdropColor, f, f._quiBgR, f._quiBgG, f._quiBgB, f._quiBgA or 1)
                if f._quiBorderR then
                    pcall(f.SetBackdropBorderColor, f, f._quiBorderR, f._quiBorderG, f._quiBorderB, f._quiBorderA or 1)
                end
                suppressingBackdrop = false
                processed[f] = true
            elseif not ShouldSkipFrame(f) then
                local hok, h = pcall(f.GetHeight, f)
                if hok and not isS(h) and h and h > 10 then
                    suppressingBackdrop = true
                    pcall(f.SetBackdropColor, f, 0.05, 0.05, 0.05, 0.95)
                    pcall(f.SetBackdropBorderColor, f, 0, 0, 0, 1)
                    suppressingBackdrop = false
                    processed[f] = true
                end
            end
        end
    end
    wipe(pendingOrphanCheck)
end

if BackdropTemplateMixin and BackdropTemplateMixin.SetBackdrop then
    hooksecurefunc(BackdropTemplateMixin, "SetBackdrop", function(self, info)
        if suppressingBackdrop then return end
        if not initialized or not IsEnabled() then return end
        -- Only care about backdrops with a background file (border-only = no white bg)
        if not info or not info.bgFile then return end
        -- Frame state changed — clear processed flag so we re-evaluate
        if processed[self] then
            processed[self] = nil
        end
        -- Defer check to let callers finish SetBackdrop + SetBackdropColor sequence
        pendingOrphanCheck[self] = true
        if not orphanTimerRunning then
            orphanTimerRunning = true
            C_Timer.After(0.2, ProcessPendingOrphans)
        end
    end)
end

---------------------------------------------------------------------------
-- Refresh (called by registry on profile/theme change)
---------------------------------------------------------------------------

local function Refresh()
    -- Clear processed set so we re-evaluate everything
    wipe(processed)
    wipe(_blizzFrameCache)
    if IsEnabled() then
        C_Timer.After(0.1, ScanAndSuppress)
    end
end

_G.QUI_RefreshThirdPartySkinning = Refresh

---------------------------------------------------------------------------
-- Event handling
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Run after a delay so other addons and QUI skinning modules finish first
        C_Timer.After(1.5, function()
            initialized = true
            ScanAndSuppress()
        end)
    elseif event == "ADDON_LOADED" then
        -- Re-scan when a new addon loads (after initialization)
        if initialized and arg1 ~= ADDON_NAME then
            C_Timer.After(0.5, ScanAndSuppress)
        end
    end
end)

---------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------

if ns.Registry then
    ns.Registry:Register("skinThirdParty", {
        refresh = Refresh,
        priority = 99,  -- Run after all other skinning modules
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end
