local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local ENTRY_IDS
local function EntryIndex()
    if ENTRY_IDS then return ENTRY_IDS end
    ENTRY_IDS = {}
    local cat = ns.SoundMuteCatalog
    if cat and cat.categories then
        for _, category in ipairs(cat.categories) do
            for _, entry in ipairs(category.entries) do
                ENTRY_IDS[entry.key] = entry.ids
            end
        end
    end
    return ENTRY_IDS
end

-- <<< QUI_TEST_EXTRACT mute_delta
local function ComputeMuteDelta(applied, want)
    local toUnmute, toMute = {}, {}
    for key in pairs(applied) do
        if not want[key] then toUnmute[#toUnmute + 1] = key end
    end
    for key in pairs(want) do
        if not applied[key] then toMute[#toMute + 1] = key end
    end
    return toUnmute, toMute
end
-- <<< QUI_TEST_EXTRACT mute_delta

local applied = {}

local function Apply()
    local index = EntryIndex()
    local s = GetSettings()
    local sm = s and s.soundMute
    local want = {}
    if sm and sm.enabled then
        for key in pairs(index) do
            if sm[key] then want[key] = true end
        end
    end

    local toUnmute, toMute = ComputeMuteDelta(applied, want)
    for _, key in ipairs(toUnmute) do
        local ids = index[key]
        if ids then
            for _, id in ipairs(ids) do UnmuteSoundFile(id) end
        end
        applied[key] = nil
    end
    for _, key in ipairs(toMute) do
        local ids = index[key]
        if ids then
            for _, id in ipairs(ids) do MuteSoundFile(id) end
        end
        applied[key] = true
    end
end

ns.RefreshSoundMute = Apply

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(Apply)
end
