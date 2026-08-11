local ADDON_NAME, ns = ...
local E = ns.AuraElements
local Model = setmetatable({}, { __index = E })
ns.QUI_GroupFramesAuraModel = Model

function Model.DefaultStripBucket(frameType)
    return {
        {
            id = "debuffs", enabled = true, mode = "filterStrip", auraType = "HARMFUL",
            anchor = "BOTTOMRIGHT", growDirection = "LEFT", spacing = 2,
            offsetX = -2, offsetY = -18, iconSize = 16, maxIcons = 3,
            hideSwipe = false, reverseSwipe = false,
            swipeStyle = "radial",
            duration = { show = true, fontSize = 9, anchor = "BOTTOM", offsetX = 0, offsetY = -6, color = { 1, 1, 1, 1 } },
            stack = { show = true, fontSize = 9, anchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 1, color = { 1, 1, 1, 1 } },
            filterMode = "off", filterFlags = {},
            classifications = { raid = true, crowdControl = true },
            whitelist = {}, blacklist = {},
            sortRule = "INDEX", sortReverse = false, rightClickCancel = true,
        },
        {
            id = "buffs", enabled = false, mode = "filterStrip", auraType = "HELPFUL",
            anchor = "TOPLEFT", growDirection = "RIGHT", spacing = 2,
            offsetX = 2, offsetY = 16, iconSize = 14, maxIcons = 0,
            hideSwipe = false, reverseSwipe = false,
            swipeStyle = "radial",
            duration = { show = true, fontSize = 9, anchor = "BOTTOM", offsetX = 0, offsetY = -6, color = { 1, 1, 1, 1 } },
            stack = { show = true, fontSize = 9, anchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 1, color = { 1, 1, 1, 1 } },
            filterMode = "off", filterFlags = {}, onlyMine = false, hidePermanent = false,
            classifications = { raid = false, raidInCombat = false, cancelable = false, notCancelable = false, bigDefensive = false, externalDefensive = false },
            whitelist = {}, blacklist = {},
            sortRule = "INDEX", sortReverse = false, rightClickCancel = true,
        },
        {
            id = "defensives", enabled = (frameType == "party"), mode = "filterStrip", auraType = "HELPFUL",
            anchor = "BOTTOMRIGHT", growDirection = "LEFT", spacing = 0,
            offsetX = 0, offsetY = 4, iconSize = 15, maxIcons = 3,
            hideSwipe = false, reverseSwipe = true,
            swipeStyle = "radial",
            duration = { show = true, fontSize = 9, anchor = "BOTTOM", offsetX = 0, offsetY = -6, color = { 1, 1, 1, 1 } },
            stack = { show = true, fontSize = 9, anchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 1, color = { 1, 1, 1, 1 } },
            filterMode = "classify", filterFlags = {},
            classifications = { bigDefensive = true, externalDefensive = true },
            borderColor = { 0, 0.8, 0, 1 },
            whitelist = {}, blacklist = {},
            sortRule = "INDEX", sortReverse = false, rightClickCancel = false,
        },
    }
end

function Model.EnsureSeeded(auras, defaultBucketFnOrFrameType)
    local a = defaultBucketFnOrFrameType
    if type(a) == "function" then
        return E.EnsureSeeded(auras, a)
    end
    return E.EnsureSeeded(auras, function() return Model.DefaultStripBucket(a) end)
end

function Model.PopulateElementMatches(element, cache, out)
    local matches = out or {}
    if out then
        for k in pairs(matches) do matches[k] = nil end
    end
    if element.mode == "tracked" and cache then
        for _, sid in ipairs(element.spells or {}) do
            local data = (cache.buffsBySpellID and cache.buffsBySpellID[sid])
                      or (cache.debuffsBySpellID and cache.debuffsBySpellID[sid])
            if data then matches[sid] = data end
        end
    end
    return matches
end

return Model
