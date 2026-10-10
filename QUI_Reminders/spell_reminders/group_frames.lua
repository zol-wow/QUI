local _, ns = ...
local M = ns.SpellReminderModel
local F = {}
ns.SpellReminderFrames = F

local function GroupToken(unit)
    unit = M.Plain(unit)
    if type(unit) ~= "string" then return nil end
    if unit == "player" or unit:match("^party%d+$") or unit:match("^raid%d+$") then return unit end
end

function F.Unit(frame)
    if not frame or not frame.GetObjectType then return nil end
    if frame.IsForbidden and frame:IsForbidden() then return nil end
    local unit = GroupToken(frame.displayedUnit) or GroupToken(frame.unit)
    if not unit and frame.GetAttribute then unit = GroupToken(frame:GetAttribute("unit")) end
    return unit
end

-- Only walk published addon frame collections and known headers. Never scan
-- the global frame list or install OnAttributeChanged handlers on secure cells.
function F.Collect()
    local result, seen = {}, {}
    local function Add(frame, unit)
        if not frame or seen[frame] or not frame.GetObjectType then return end
        if frame.IsForbidden and frame:IsForbidden() then return end
        seen[frame] = true
        unit = GroupToken(unit) or F.Unit(frame)
        if unit then result[#result + 1] = { frame = frame, unit = unit } end
    end
    local function Walk(root, depth)
        if not root or not root.GetChildren or (root.IsForbidden and root:IsForbidden()) then return end
        Add(root)
        if depth == 0 then return end
        for _, child in ipairs({ root:GetChildren() }) do
            Add(child)
            if depth > 1 then
                for _, grandchild in ipairs({ child:GetChildren() }) do Add(grandchild) end
            end
        end
    end
    local function Collection(list)
        if type(list) ~= "table" then return end
        for key, value in pairs(list) do
            if type(key) == "table" and key.GetObjectType then Add(key) end
            if type(value) == "table" and value.GetObjectType then Add(value) end
        end
    end
    local gf = ns.QUI_GroupFrames
    for unit, frames in pairs(gf and gf.unitFrameMap or {}) do
        for _, frame in ipairs(frames) do Add(frame, unit) end
    end
    Walk(_G.CompactRaidFrameContainer, 2)
    Walk(_G.CompactPartyFrame, 1)
    for i = 1, 40 do Add(_G["CompactRaidFrame" .. i]) end
    for group = 1, 8 do
        for member = 1, 5 do Add(_G["CompactRaidGroup" .. group .. "Member" .. member]) end
    end
    for _, name in ipairs({ "ElvUF_Party", "ElvUF_Raid1", "ElvUF_Raid2", "ElvUF_Raid3", "ElvUF_Raid40",
        "DandersFramesContainer", "DandersRaidFramesContainer", "DandersPartyGroupContainer",
        "ERFFlatHeader", "EllesmereRaidHeader", "EUIRaidHeader", "MRF_PartyHeader" }) do
        Walk(_G[name], 2)
    end
    local df = _G.DandersFrames
    if df then
        Walk(df.partyHeader, 1)
        Walk(df.raidCombinedHeader, 1)
        for _, header in pairs(df.raidSeparatedHeaders or {}) do Walk(header, 1) end
        Collection(df.FlatRaidFrames)
        if df.FlatRaidFrames then Walk(df.FlatRaidFrames.header, 1) end
        Collection(df.raidFrames)
        Collection(df.partyFrames)
    end
    local grid = _G.Grid2Frame
    if grid then Collection(grid.activatedFrames); Collection(grid.registeredFrames) end
    local modules = _G.EllesmereUI and _G.EllesmereUI._ModuleNS
    local erf = modules and modules.EllesmereUIRaidFrames
    if erf then Collection(erf._euiUnitButtons); Collection(erf._flatButtons) end
    local bf = _G.BuzzardFrames
    if bf then
        Collection(bf.registeredFrames); Collection(bf.activeFrames); Collection(bf.activatedFrames)
        for _, header in ipairs(bf.groupsUsed or {}) do Walk(header, 1) end
    end
    for i = 1, 8 do
        Walk(_G["ERFGroupHeader" .. i], 1)
        Walk(_G["BFLayoutHeader" .. i], 1)
        Walk(_G["MRF_RaidHeader" .. i], 1)
    end
    for i = 9, 24 do Walk(_G["BFLayoutHeader" .. i], 1) end
    local getter = _G.VUHDO_getUnitButtonsSafe or _G.VUHDO_getUnitButtons
    if type(getter) == "function" then
        for _, prefix in ipairs({ "party", "raid" }) do
            for i = 1, prefix == "raid" and 40 or 4 do
                local ok, buttons = pcall(getter, prefix .. i)
                if ok then Collection(buttons) end
            end
        end
    end
    return result
end

return F
