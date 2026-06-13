---------------------------------------------------------------------------
-- Bags search: query compiler (PURE — no WoW APIs, fully headless-testable).
-- Compile(query) → matcher(details) → true | false | nil (nil = a field the
-- term needs isn't loaded yet; caller re-evaluates when item data arrives).
--
-- Grammar (left-assoc, no parens): or := and ('|' and)* ; and := not ((' '|'&') not)* ;
-- not := ['~'] term. Terms: name substring (default), quality names, class
-- keywords, equip-slot names, expansion names, numeric ilvl (<n >n =n a-b).
-- details record: { name, quality, classID, subClassID, equipLoc, ilvl,
--                   count, isBound, itemID, expacID }
--
-- Tradeoffs (deliberate, v1):
-- * Keywords SHADOW name substrings: "chest"/"bag"/"ring" match the slot,
--   never item names containing those words (future: prefix syntax like
--   "slot:chest" as the escape hatch).
-- * Keywords are enUS-only; name matching uses ASCII lower() (non-ASCII
--   case-insensitivity is not attempted).
-- * Boolean keywords extend via KEYWORDS; parameterized terms (stat:crit
--   etc.) extend MakeTermMatcher's grammar.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local Search = {}
Bags.Search = Search

-- tri-state combinators: nil = pending
local function triAnd(a, b)
    if a == false or b == false then return false end
    if a == nil or b == nil then return nil end
    return true
end
local function triOr(a, b)
    if a == true or b == true then return true end
    if a == nil or b == nil then return nil end
    return false
end
local function triNot(a)
    if a == nil then return nil end
    return not a
end

local QUALITY = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4,
                  legendary = 5, artifact = 6, heirloom = 7 }

local EXPANSION = { classic = 0, bc = 1, wotlk = 2, cata = 3, mop = 4, wod = 5,
                    legion = 6, bfa = 7, shadowlands = 8, dragonflight = 9,
                    tww = 10, midnight = 11 }

local SLOT = {
    head = "INVTYPE_HEAD", neck = "INVTYPE_NECK", shoulder = "INVTYPE_SHOULDER",
    back = "INVTYPE_CLOAK", cloak = "INVTYPE_CLOAK", chest = "INVTYPE_CHEST",
    wrist = "INVTYPE_WRIST", hands = "INVTYPE_HAND", waist = "INVTYPE_WAIST",
    legs = "INVTYPE_LEGS", feet = "INVTYPE_FEET", finger = "INVTYPE_FINGER",
    ring = "INVTYPE_FINGER", trinket = "INVTYPE_TRINKET", bag = "INVTYPE_BAG",
}

-- keyword → check(details) → tri-state. Add new keywords here (tier-2 later).
local KEYWORDS = {
    junk      = function(d) if d.quality == nil then return nil end return d.quality == 0 end,
    reagent   = function(d) if d.classID == nil then return nil end return d.classID == 7 or d.classID == 5 end,
    gear      = function(d) if d.classID == nil then return nil end return d.classID == 2 or d.classID == 4 end,
    quest     = function(d) if d.classID == nil then return nil end return d.classID == 12 end,
    pet       = function(d) if d.classID == nil then return nil end return d.classID == 17 end,
    -- isBound is non-nilable in ContainerItemInfo → never pending (the one
    -- keyword that deliberately skips the nil tri-state)
    soulbound = function(d) return d.isBound == true end,
    bound     = function(d) return d.isBound == true end,
}
KEYWORDS.equipment = KEYWORDS.gear
KEYWORDS.trash = KEYWORDS.junk

local function MakeTermMatcher(term)
    -- numeric: <n >n =n n-m  (ilvl)
    local op, num = term:match("^([<>=])(%d+)$")
    if op then
        num = tonumber(num)
        return function(d)
            if d.ilvl == nil then return nil end
            if op == "<" then return d.ilvl < num
            elseif op == ">" then return d.ilvl > num
            else return d.ilvl == num end
        end
    end
    local lo, hi = term:match("^(%d+)%-(%d+)$")
    if lo then
        lo, hi = tonumber(lo), tonumber(hi)
        return function(d)
            if d.ilvl == nil then return nil end
            return d.ilvl >= lo and d.ilvl <= hi
        end
    end
    if QUALITY[term] ~= nil then
        local q = QUALITY[term]
        return function(d)
            if d.quality == nil then return nil end
            return d.quality == q
        end
    end
    if EXPANSION[term] ~= nil then
        local e = EXPANSION[term]
        return function(d)
            if d.expacID == nil then return nil end
            return d.expacID == e
        end
    end
    if SLOT[term] then
        local slot = SLOT[term]
        return function(d)
            if d.equipLoc == nil then return nil end
            return d.equipLoc == slot
        end
    end
    -- exact keyword wins outright (deliberate filter, no name fallback)
    if KEYWORDS[term] then
        return KEYWORDS[term]
    end
    -- as-you-type: term that PREFIXES keyword name(s) fires those filters,
    -- UNION'd with plain name substring. Only adds highlights, never narrows,
    -- so partial typing ("reag" -> reagent) lights up incrementally.
    local prefixChecks
    for kw, fn in pairs(KEYWORDS) do
        if #term < #kw and kw:sub(1, #term) == term then
            prefixChecks = prefixChecks or {}
            local seen = false
            for i = 1, #prefixChecks do
                if prefixChecks[i] == fn then seen = true break end
            end
            if not seen then prefixChecks[#prefixChecks + 1] = fn end
        end
    end
    -- default: case-insensitive name substring (plain find, no patterns)
    local needle = term
    local nameCheck = function(d)
        if d.name == nil then return nil end
        return d.name:lower():find(needle, 1, true) ~= nil
    end
    if not prefixChecks then
        return nameCheck
    end
    return function(d)
        local r = nameCheck(d)
        for i = 1, #prefixChecks do
            r = triOr(r, prefixChecks[i](d))
            if r == true then return true end
        end
        return r
    end
end

local function CompileUncached(query)
    -- or-groups split on '|'; within a group, '&' and whitespace both AND
    local orMatchers = {}
    for orPart in (query .. "|"):gmatch("(.-)|") do
        local andMatchers = {}
        for token in orPart:gmatch("[^&%s]+") do
            local negate = false
            while token:sub(1, 1) == "~" do
                negate = not negate
                token = token:sub(2)
            end
            if token ~= "" then
                local m = MakeTermMatcher(token:lower())
                if negate then
                    local inner = m
                    m = function(d) return triNot(inner(d)) end
                end
                andMatchers[#andMatchers + 1] = m
            end
        end
        if #andMatchers > 0 then
            orMatchers[#orMatchers + 1] = andMatchers
        end
    end
    if #orMatchers == 0 then
        return function() return true end -- empty query matches everything
    end
    return function(d)
        local result = false
        for i = 1, #orMatchers do
            local group = orMatchers[i]
            local g = true
            for j = 1, #group do
                g = triAnd(g, group[j](d))
                if g == false then break end
            end
            result = triOr(result, g)
            if result == true then return true end
        end
        return result
    end
end

local cache = {} -- query string → matcher (session-bounded: queries are user-typed)

function Search.Compile(query)
    query = (query or ""):match("^%s*(.-)%s*$")
    local hit = cache[query]
    if hit then return hit end
    local m = CompileUncached(query)
    cache[query] = m
    return m
end
