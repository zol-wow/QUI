local addonName, ns = ...

local factionGroup = UnitFactionGroup("player")
local SIEGE_SPELL = factionGroup == "Horde" and 464256 or 445418
local MOTHERLODE_SPELL = factionGroup == "Horde" and 467555 or 467553

local NAME_TO_SHORT = {
    ["Pit of Saron"] = "PIT",

    ["Temple of the Jade Serpent"] = "TJS",
    ["Stormstout Brewery"] = "SSB",
    ["Shado-Pan Monastery"] = "SPM",
    ["Siege of Niuzao Temple"] = "SNT",
    ["Gate of the Setting Sun"] = "GOTSS",
    ["Mogu'shan Palace"] = "MSP",
    ["Scholomance"] = "SCHOLO",
    ["Scarlet Halls"] = "SH",
    ["Scarlet Monastery"] = "SM",

    ["Bloodmaul Slag Mines"] = "BSM",
    ["Auchindoun"] = "AUCH",
    ["Skyreach"] = "SKY",
    ["Shadowmoon Burial Grounds"] = "SBG",
    ["Grimrail Depot"] = "GD",
    ["Upper Blackrock Spire"] = "UBRS",
    ["The Everbloom"] = "EB",
    ["Iron Docks"] = "ID",

    ["Eye of Azshara"] = "EOA",
    ["Darkheart Thicket"] = "DT",
    ["Black Rook Hold"] = "BRH",
    ["Halls of Valor"] = "HOV",
    ["Neltharion's Lair"] = "NL",
    ["Vault of the Wardens"] = "VAULT",
    ["Maw of Souls"] = "MOS",
    ["The Arcway"] = "ARC",
    ["Court of Stars"] = "COS",
    ["Return to Karazhan: Lower"] = "LKARA",
    ["Return to Karazhan: Upper"] = "UKARA",
    ["Seat of the Triumvirate"] = "SEAT",

    ["Atal'Dazar"] = "AD",
    ["Freehold"] = "FH",
    ["The MOTHERLODE!!"] = "ML",
    ["Waycrest Manor"] = "WM",
    ["Kings' Rest"] = "KR",
    ["Temple of Sethraliss"] = "SETH",
    ["The Underrot"] = "UNDR",
    ["Shrine of the Storm"] = "SHRINE",
    ["Siege of Boralus"] = "SIEGE",
    ["Operation: Mechagon - Junkyard"] = "YARD",
    ["Operation: Mechagon - Workshop"] = "WORK",

    ["Mists of Tirna Scithe"] = "MISTS",
    ["The Necrotic Wake"] = "NW",
    ["De Other Side"] = "DOS",
    ["Halls of Atonement"] = "HOA",
    ["Plaguefall"] = "PF",
    ["Sanguine Depths"] = "SD",
    ["Spires of Ascension"] = "SOA",
    ["Theater of Pain"] = "TOP",
    ["Tazavesh: Streets of Wonder"] = "STRT",
    ["Tazavesh: So'leah's Gambit"] = "GMBT",

    ["Ruby Life Pools"] = "RLP",
    ["The Nokhud Offensive"] = "NO",
    ["The Azure Vault"] = "AV",
    ["Algeth'ar Academy"] = "AA",
    ["Uldaman: Legacy of Tyr"] = "ULD",
    ["Neltharus"] = "NELTH",
    ["Brackenhide Hollow"] = "BH",
    ["Halls of Infusion"] = "HOI",
    ["Dawn of the Infinite: Galakrond's Fall"] = "DOTI",
    ["Dawn of the Infinite: Murozond's Rise"] = "DOTI",

    ["Priory of the Sacred Flame"] = "PSF",
    ["The Rookery"] = "ROOK",
    ["The Stonevault"] = "SV",
    ["City of Threads"] = "COT",
    ["Ara-Kara, City of Echoes"] = "ARAK",
    ["Darkflame Cleft"] = "DFC",
    ["The Dawnbreaker"] = "DAWN",
    ["Cinderbrew Meadery"] = "BREW",
    ["Grim Batol"] = "GB",
    ["Operation: Floodgate"] = "FLOOD",
    ["Eco-Dome Al'dani"] = "EDA",

    ["Vortex Pinnacle"] = "VP",
    ["Throne of the Tides"] = "TOTT",

    ["Windrunner Spire"] = "WIND",
    ["Magister's Terrace"] = "MAGI",
    ["Magisters' Terrace"] = "MAGI",
    ["Nexus-Point Xenas"] = "XENAS",
    ["Maisara Caverns"] = "CAVNS",
    ["Murder Row"] = "MURDR",
    ["The Blinding Vale"] = "BLIND",
    ["Den of Nalorakk"] = "NALO",
    ["The Foraging"] = "FORAG",
    ["Voidscar Arena"] = "VSCAR",
    ["The Heart of Rage"] = "RAGE",
    ["Voidstorm"] = "VSTORM",
}

local MAPID_TO_SPELL = {
    [556] = 1254555,

    [2] = 131204,
    [56] = 131205,
    [57] = 131206,
    [58] = 131228,
    [59] = 131225,
    [60] = 131222,
    [76] = 131232,
    [77] = 131231,
    [78] = 131229,

    [161] = 159895,
    [163] = 159897,
    [164] = 159898,
    [165] = 159899,
    [166] = 159900,
    [167] = 159902,
    [168] = 159901,
    [169] = 159896,

    [198] = 424163,
    [199] = 424153,
    [200] = 393764,
    [206] = 410078,
    [210] = 393766,
    [227] = 373262,
    [234] = 373262,
    [239] = 1254551,

    [244] = 424187,
    [245] = 410071,
    [247] = MOTHERLODE_SPELL,
    [248] = 424167,
    [249] = 1286831,
    [250] = 1286828,
    [251] = 410074,
    [353] = SIEGE_SPELL,
    [369] = 373274,
    [370] = 373274,

    [375] = 354464,
    [376] = 354462,
    [377] = 354468,
    [378] = 354465,
    [379] = 354463,
    [380] = 354469,
    [381] = 354466,
    [382] = 354467,
    [391] = 367416,
    [392] = 367416,

    [399] = 393256,
    [400] = 393262,
    [401] = 393279,
    [402] = 393273,
    [403] = 393222,
    [404] = 393276,
    [405] = 393267,
    [406] = 393283,
    [463] = 424197,
    [464] = 424197,

    [499] = 445444,
    [500] = 445443,
    [501] = 445269,
    [502] = 445416,
    [503] = 445417,
    [504] = 445441,
    [505] = 445414,
    [506] = 445440,
    [507] = 445424,
    [525] = 1216786,
    [542] = 1237215,

    [438] = 410080,
    [456] = 424142,

    [557] = 1254400,
    [558] = 1254572,
    [559] = 1254563,
    [560] = 1254559,
    [584] = 1286801,
    [585] = 1286804,
    [586] = 1286807,
    [587] = 1286809,
    [588] = 1286812,
    [15808] = 1254400,
    [15829] = 1254572,
    [16573] = 1254563,
    [16395] = 1254559,
}

local NAME_TO_SPELL = {
    ["Windrunner Spire"] = 1254400,
    ["Magister's Terrace"] = 1254572,
    ["Magisters' Terrace"] = 1254572,
    ["Nexus-Point Xenas"] = 1254563,
    ["Maisara Caverns"] = 1254559,
    ["The Blinding Vale"] = 1286801,
    ["Voidscar Arena"] = 1286804,
    ["Den of Nalorakk"] = 1286807,
    ["Murder Row"] = 1286809,
    ["Altar of Fangs"] = 1286812,
    ["Kings' Rest"] = 1286831,
    ["Temple of Sethraliss"] = 1286828,
    ["Skyreach"] = 159898,
    ["Pit of Saron"] = 1254555,
    ["Seat of the Triumvirate"] = 1254551,
    ["Algeth'ar Academy"] = 393273,
}

local function GetDungeonName(mapID)
    return mapID and C_ChallengeMode.GetMapUIInfo(mapID)
end

local function GetShortName(mapID)
    local name = GetDungeonName(mapID)
    if name then
        local short = NAME_TO_SHORT[name]
        if short then
            return short
        end
        local firstWord = name:match("^(%S+)")
        if firstWord and #firstWord <= 6 then
            return ns.Helpers.UpperUTF8(firstWord)
        end
        return ns.Helpers.UpperUTF8(ns.Helpers.TruncateUTF8(name, 4))
    end
    return "???"
end

local function GetTeleportSpellID(mapID)
    local name = GetDungeonName(mapID)
    return (name and NAME_TO_SPELL[name]) or MAPID_TO_SPELL[mapID]
end

local function GetDungeonData(mapID)
    local name = GetDungeonName(mapID)
    if name then
        return {
            short = NAME_TO_SHORT[name] or ns.Helpers.UpperUTF8(ns.Helpers.TruncateUTF8(name, 4)),
            spellID = GetTeleportSpellID(mapID)
        }
    end
    return nil
end

local function HasTeleport(mapID)
    return GetTeleportSpellID(mapID) ~= nil
end

local function GetKeyColor(level)
    if not level or level == 0 then return 0.7, 0.7, 0.7 end
    if level >= 12 then return 1, 0.5, 0 end
    if level >= 10 then return 0.64, 0.21, 0.93 end
    if level >= 7 then return 0, 0.44, 0.87 end
    if level >= 5 then return 0.12, 0.75, 0.26 end
    return 1, 1, 1
end

ns.DungeonData = {
    nameToShort = NAME_TO_SHORT,
    nameToSpell = NAME_TO_SPELL,
    mapIdToSpell = MAPID_TO_SPELL,
    GetShortName = GetShortName,
    GetTeleportSpellID = GetTeleportSpellID,
    GetDungeonData = GetDungeonData,
    HasTeleport = HasTeleport,
    GetKeyColor = GetKeyColor,
}

_G.QUI_DungeonData = ns.DungeonData
