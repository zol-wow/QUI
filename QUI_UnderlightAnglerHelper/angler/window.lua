-- QUI_UnderlightAnglerHelper/angler/window.lua -- the helper window.
--
-- One QUI-skinned window, QUI_UnderlightAnglerWindow, with three views: the
-- acquisition checklist, the artifact trait tree, and tips for repeating the
-- unlock on an alt. It is built on first open and listens to the client only
-- while it is shown.
--
-- It lives in one of two places. Free-standing, it is a movable window in the
-- middle of the screen. Embedded, it is a child of Blizzard's artifact window
-- and covers it, so opening the Underlight Angler shows the tree in place.
-- Whoever has the artifact open is past the checklist, so embedded it is left
-- out.
local ADDON_NAME, ns = ...

local Helpers = ns.Helpers
local UIKit = ns.UIKit
local Angler = ns.UnderlightAngler

local Window = {}
Angler.Window = Window

local FRAME_NAME = "QUI_UnderlightAnglerWindow"
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\"
local BUY_POPUP = "QUI_UNDERLIGHT_ANGLER_BUY"
local FALLBACK_ICON = 134400

local HEADER_H, PAD = 32, 10
-- The tree art is drawn for a body of exactly this size; trait positions are
-- fractions of the padded box inside it.
local BODY_W, BODY_H = 980, 605
local TREE_X, TREE_Y, TREE_W, TREE_H = 65, 18, 850, 525
local NODE_SIZE, RING_SIZE, GLOW_SIZE = 42, 48, 54
local MAP_W, MAP_H, MAP_TEX_BOTTOM = 500, 377, 773 / 1024
local REFRESH_DELAY = 0.1
-- A purchased rank is not readable straight away; the tree is repainted until
-- it is, or this many times.
local PURCHASE_SYNC_TRIES = 25
-- Above everything Blizzard's artifact window draws in the same strata, and
-- below the DIALOG strata the purchase confirmation appears in.
local EMBED_STRATA, EMBED_LEVEL = "HIGH", 5000
local HOST_TABS = { "PerksTabButton", "AppearancesTabButton" }

local ROUTE_COLORS = {
    [1] = { 1, 0.08, 0.03, 0.92 },
    [2] = { 1, 0.86, 0.05, 0.92 },
}
local LINK_IDLE = { 0.38, 0.45, 0.50, 0.72 }
local LINK_DONE = { 0.28, 0.72, 0.82, 0.72 }
local RANK_MAXED = { 1, 0.82, 0.15 }
local RANK_OPEN = { 0.3, 0.95, 1 }
local RANK_LOCKED = { 0.75, 0.75, 0.75 }
local RING_MAXED = { 1, 0.72, 0.08 }
local RING_OPEN = { 0.12, 0.85, 1 }
local RING_LOCKED = { 0.38, 0.38, 0.38 }

local STATUS_ICONS = {
    done    = "Interface\\RaidFrame\\ReadyCheck-Ready",
    todo    = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    unknown = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}

local EVENTS = {
    "ACHIEVEMENT_EARNED", "ARTIFACT_CLOSE", "ARTIFACT_UPDATE", "ARTIFACT_XP_UPDATE", "BAG_UPDATE_DELAYED",
    "QUEST_LOG_UPDATE", "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_SHOW",
}

local VIEW_ORDER = { "checklist", "tree", "tips" }

local win
local host
local views = {}
local tabs = {}
local activeView = "checklist"
local refreshQueued = false

local function Print(message)
    print("|cff60A5FAQUI:|r " .. message)
end

local function Font()
    return Helpers.GetGeneralFont() or STANDARD_TEXT_FONT, Helpers.GetGeneralFontOutline() or "OUTLINE"
end

local function Text(parent, size)
    local path, outline = Font()
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Helpers.ApplyFontWithFallback(fs, path, size, outline)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    return fs
end

local function Color(name, fallback)
    local gui = _G.QUI and _G.QUI.GUI
    local c = (gui and gui.Colors and gui.Colors[name]) or fallback
    return c[1], c[2], c[3], c[4] or 1
end

local function AccentHex()
    local r, g, b = UIKit.GetAccentColor()
    return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

local function PanelAlpha()
    local core = Helpers.GetCore and Helpers.GetCore()
    local profile = core and core.db and core.db.profile
    return (profile and profile.configPanelAlpha) or 0.97
end

local function FormatNumber(value)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(value) end
    return tostring(value)
end

---------------------------------------------------------------------------
-- Checklist
---------------------------------------------------------------------------

local function AdviceText(step, progress)
    if step == "achievement" then
        return ns.L["Complete Bigger Fish to Fry on this character. Fish Legion schools and use Arcane Lure to bring up the rare fish and lures."]
    elseif step == "skillUnknown" then
        return ns.L["Open the Legion Fishing page of your profession window, then press Refresh."]
    elseif step == "skill" then
        return ns.L["Raise Legion Fishing to 100. Current skill: %d/%d."]:format(
            progress.skill, progress.maxSkill or Angler.REQUIRED_SKILL)
    elseif step == "pearl" then
        return ns.L["Fish a Broken Isles fishing school with Arcane Lure active until you catch the Luminous Pearl, then follow its quest chain until the Underlight Angler is awarded."]
    elseif step == "khadgar" then
        return ns.L["Khadgar is inside The Violet Citadel. Go to the spot marked with the red circle on the map, not the yellow marker at the Chamber of the Guardian."]
    end
    return ns.L["Open the Underlight Angler artifact at the Luminous Pearl in the Dalaran fountain, then switch to the Artifact Tree tab."]
end

local function BuildChecklist(parent)
    local view = CreateFrame("Frame", nil, parent)

    view.heading = Text(view, 16)
    view.heading:SetPoint("TOPLEFT", 20, -16)
    view.heading:SetText(ns.L["Acquisition checklist"])

    view.rows = {}
    for i = 1, 4 do
        local row = CreateFrame("Frame", nil, view)
        row:SetSize(420, 22)
        row:SetPoint("TOPLEFT", 24, -56 - (i - 1) * 30)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT")
        row.label = Text(row, 14)
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.label:SetJustifyV("MIDDLE")
        view.rows[i] = row
    end

    view.nextHeading = Text(view, 13)
    view.nextHeading:SetPoint("TOPLEFT", 24, -192)

    view.advice = Text(view, 13)
    view.advice:SetPoint("TOPLEFT", 24, -214)
    view.advice:SetWidth(410)
    view.advice:SetSpacing(4)
    view.advice:SetWordWrap(true)

    local map = CreateFrame("Frame", nil, view)
    map:SetSize(MAP_W, MAP_H)
    map:SetPoint("TOPRIGHT", -20, -16)
    map.texture = map:CreateTexture(nil, "ARTWORK")
    map.texture:SetAllPoints()
    map.texture:SetTexture(MEDIA .. "VioletCitadelMap")
    map.texture:SetTexCoord(0, 1, 0, MAP_TEX_BOTTOM)
    UIKit.CreateBorderLines(map)
    map.caption = Text(view, 12)
    map.caption:SetPoint("TOPLEFT", map, "BOTTOMLEFT", 0, -8)
    map.caption:SetPoint("TOPRIGHT", map, "BOTTOMRIGHT", 0, -8)
    map.caption:SetWordWrap(true)
    map.caption:SetText(ns.L["Khadgar's location inside The Violet Citadel, Dalaran (Broken Isles)."])
    map:Hide()
    map.caption:Hide()
    view.map = map

    view.refresh = UIKit.CreateButton(view, {
        text = ns.L["Refresh"], width = 110, height = 24,
        onClick = function() view.Refresh() end,
    })
    view.refresh:SetPoint("BOTTOMLEFT", 20, 16)

    local function SetRow(index, state, label)
        local row = view.rows[index]
        row.icon:SetTexture(STATUS_ICONS[state])
        row.label:SetText(label)
        if state == "done" then
            row.label:SetTextColor(Color("text", { 1, 1, 1, 1 }))
        else
            row.label:SetTextColor(Color("textDim", { 1, 1, 1, 0.6 }))
        end
    end

    function view.Refresh()
        local progress = Angler.ReadProgress()
        local step = Angler.NextStep(progress)

        SetRow(1, progress.achievement and "done" or "todo",
            progress.achievementName or ns.L["Bigger Fish to Fry"])
        if progress.skill then
            SetRow(2, progress.skill >= Angler.REQUIRED_SKILL and "done" or "todo",
                ns.L["Legion Fishing %d/%d"]:format(progress.skill, progress.maxSkill or Angler.REQUIRED_SKILL))
        else
            SetRow(2, "unknown", ns.L["Legion Fishing (skill not available yet)"])
        end
        SetRow(3, progress.pearl and "done" or "todo", ns.L["Luminous Pearl questline"])
        SetRow(4, progress.rod and "done" or "todo", ns.L["Underlight Angler obtained"])

        view.nextHeading:SetText(AccentHex() .. (step == "ready" and ns.L["Ready"] or ns.L["Next step"]) .. "|r")
        view.advice:SetText(AdviceText(step, progress))
        view.advice:SetTextColor(Color("text", { 1, 1, 1, 1 }))

        local showMap = step == "khadgar"
        view.map:SetShown(showMap)
        view.map.caption:SetShown(showMap)
        view.map.caption:SetTextColor(Color("textDim", { 1, 1, 1, 0.6 }))
        UIKit.UpdateBorderLines(view.map, 1, Color("border", { 1, 1, 1, 0.06 }))
    end

    return view
end

---------------------------------------------------------------------------
-- Artifact tree
---------------------------------------------------------------------------

local function TraitPosition(powerID)
    local trait = Angler.Traits[powerID]
    return TREE_X + trait.x * TREE_W, TREE_Y + trait.y * TREE_H
end

local function PowerInfo(powerID)
    if not Angler.IsArtifactOpen() then return nil end
    return C_ArtifactUI.GetPowerInfo(powerID)
end

local function SyncPurchasedRank(powerID, oldRank, tries)
    Window.QueueRefresh()
    if tries >= PURCHASE_SYNC_TRIES then return end
    local info = PowerInfo(powerID)
    if info and info.currentRank == oldRank then
        C_Timer.After(REFRESH_DELAY, function() SyncPurchasedRank(powerID, oldRank, tries + 1) end)
    end
end

local function EnsureBuyPopup()
    if StaticPopupDialogs[BUY_POPUP] then return end
    StaticPopupDialogs[BUY_POPUP] = {
        text = ns.L["Purchase %s for %s Artifact Power?"],
        button1 = _G.YES,
        button2 = _G.NO,
        OnAccept = function(_, powerID)
            if InCombatLockdown() or not Angler.IsArtifactOpen() then return end
            local before = C_ArtifactUI.GetPowerInfo(powerID)
            if C_ArtifactUI.AddPower(powerID) then
                Print(ns.L["Purchased %s."]:format(Angler.TraitName(powerID)))
                SyncPurchasedRank(powerID, before and before.currentRank, 1)
            else
                Print(ns.L["The game rejected the trait purchase."])
                Window.QueueRefresh()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

local function RequestPurchase(powerID)
    local name = Angler.TraitName(powerID)
    if InCombatLockdown() then
        Print(ns.L["Traits cannot be purchased in combat."])
        return
    end
    local info = PowerInfo(powerID)
    if not info then
        Print(ns.L["Open the Underlight Angler artifact at the Luminous Pearl first."])
        return
    end
    if info.currentRank >= info.maxRank then
        Print(ns.L["%s is already at its maximum rank."]:format(name))
        return
    end
    if info.prereqsMet == false then
        Print(ns.L["The prerequisites for %s are not met."]:format(name))
        return
    end
    EnsureBuyPopup()
    StaticPopup_Show(BUY_POPUP, name, FormatNumber(info.cost or 0), powerID)
end

local function ShowTraitTooltip(node)
    node.glow:SetAlpha(0.55)
    GameTooltip:SetOwner(node, "ANCHOR_RIGHT")
    GameTooltip:SetText(Angler.TraitName(node.powerID), 1, 0.82, 0)
    local info = PowerInfo(node.powerID)
    if info then
        GameTooltip:AddLine(ns.L["Rank: %d/%d"]:format(info.currentRank, info.maxRank), 1, 1, 1)
        if info.currentRank >= info.maxRank then
            GameTooltip:AddLine(ns.L["Maximum rank"], 1, 0.82, 0)
        else
            GameTooltip:AddLine(ns.L["Next rank: %s Artifact Power"]:format(FormatNumber(info.cost or 0)), 0.4, 0.85, 1)
            if info.prereqsMet == false then
                GameTooltip:AddLine(ns.L["Prerequisites not met"], 1, 0.33, 0.33)
            else
                GameTooltip:AddLine(ns.L["Click to purchase"], 0.2, 1, 0.4)
            end
        end
    else
        GameTooltip:AddLine(ns.L["Open the Underlight Angler artifact at the Luminous Pearl first."], 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function CreateTraitNode(view, powerID)
    local trait = Angler.Traits[powerID]
    local node = CreateFrame("Button", nil, view)
    node.powerID = powerID
    node:SetSize(NODE_SIZE, NODE_SIZE)
    node:SetPoint("CENTER", view, "BOTTOMLEFT", TraitPosition(powerID))

    node.ring = node:CreateTexture(nil, "BACKGROUND")
    node.ring:SetPoint("CENTER")
    node.ring:SetAtlas("Artifacts-PerkRing-Final")
    node.ring:SetSize(RING_SIZE, RING_SIZE)

    node.icon = node:CreateTexture(nil, "ARTWORK")
    node.icon:SetPoint("CENTER")
    node.icon:SetSize(NODE_SIZE, NODE_SIZE)
    local spell = C_Spell.GetSpellInfo(trait.spellID)
    node.icon:SetTexture(spell and spell.iconID or FALLBACK_ICON)
    node.icon:SetTexCoord(0.04, 0.96, 0.04, 0.96)
    node.mask = node:CreateMaskTexture()
    node.mask:SetAllPoints(node.icon)
    node.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    node.icon:AddMaskTexture(node.mask)

    node.rankBg = node:CreateTexture(nil, "OVERLAY")
    node.rankBg:SetColorTexture(0, 0, 0, 0.88)
    node.rankBg:SetSize(32, 16)
    node.rankBg:SetPoint("BOTTOM", 0, -6)
    node.rank = Text(node, 12)
    node.rank:SetDrawLayer("OVERLAY", 1)
    node.rank:SetPoint("CENTER", node.rankBg)

    node.glow = node:CreateTexture(nil, "OVERLAY")
    node.glow:SetPoint("CENTER")
    node.glow:SetAtlas("Artifacts-PerkRing-Final")
    node.glow:SetSize(GLOW_SIZE, GLOW_SIZE)
    node.glow:SetBlendMode("ADD")
    node.glow:SetAlpha(0)

    node:SetScript("OnClick", function(self) RequestPurchase(self.powerID) end)
    node:SetScript("OnEnter", ShowTraitTooltip)
    node:SetScript("OnLeave", function(self)
        self.glow:SetAlpha(0)
        GameTooltip:Hide()
    end)
    return node
end

local function CreateLink(view, link)
    local ax, ay = TraitPosition(link.from)
    local bx, by = TraitPosition(link.to)
    local dx, dy = bx - ax, by - ay
    local tex = view:CreateTexture(nil, "ARTWORK")
    tex:SetSize(math.sqrt(dx * dx + dy * dy), link.route > 0 and 5 or 3)
    tex:SetPoint("CENTER", view, "BOTTOMLEFT", (ax + bx) / 2, (ay + by) / 2)
    tex:SetRotation(math.atan2(dy, dx))
    local color = ROUTE_COLORS[link.route] or LINK_IDLE
    tex:SetColorTexture(color[1], color[2], color[3], color[4])
    return tex
end

local function CreateLegendEntry(view, route, label, anchor)
    local swatch = view:CreateTexture(nil, "OVERLAY")
    swatch:SetSize(22, 5)
    local color = ROUTE_COLORS[route]
    swatch:SetColorTexture(color[1], color[2], color[3], 1)
    if anchor then
        swatch:SetPoint("LEFT", anchor, "RIGHT", 18, 0)
    else
        swatch:SetPoint("BOTTOMLEFT", 16, 14)
    end
    local text = Text(view, 12)
    text:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    text:SetText(label)
    return text
end

local function BuildTree(parent)
    local view = CreateFrame("Frame", nil, parent)

    view.art = view:CreateTexture(nil, "BACKGROUND", nil, -8)
    view.art:SetAllPoints()
    view.art:SetTexture(MEDIA .. "AnglerBackground")
    view.art:SetAlpha(0.86)

    view.power = Text(view, 14)
    view.power:SetPoint("TOP", 0, -12)
    view.power:SetJustifyH("CENTER")

    view.links = {}
    for i, link in ipairs(Angler.Links) do
        view.links[i] = CreateLink(view, link)
    end
    view.nodes = {}
    for powerID in pairs(Angler.Traits) do
        view.nodes[powerID] = CreateTraitNode(view, powerID)
    end

    local first = CreateLegendEntry(view, 1, ns.L["Buy first: water walking and swim speed"])
    CreateLegendEntry(view, 2, ns.L["Buy second: reduced threat while fishing"], first)

    function view.Refresh()
        local open = Angler.IsArtifactOpen()
        local power = open and select(5, C_ArtifactUI.GetArtifactInfo())
        if type(power) == "number" then
            view.power:SetText(ns.L["Artifact Power: %s"]:format(FormatNumber(power)))
        else
            view.power:SetText(ns.L["Open the Underlight Angler artifact at the Luminous Pearl to see ranks and buy traits."])
        end

        local maxed = {}
        for powerID, node in pairs(view.nodes) do
            local info = open and C_ArtifactUI.GetPowerInfo(powerID)
            local rank = info and info.currentRank or 0
            local maxRank = info and info.maxRank or Angler.Traits[powerID].maxRank
            local ring, text
            if rank >= maxRank then
                ring, text = RING_MAXED, RANK_MAXED
                maxed[powerID] = true
            elseif info and info.prereqsMet ~= false then
                ring, text = RING_OPEN, RANK_OPEN
            else
                ring, text = RING_LOCKED, RANK_LOCKED
            end
            node.rank:SetText(rank .. "/" .. maxRank)
            node.rank:SetTextColor(text[1], text[2], text[3])
            node.ring:SetVertexColor(ring[1], ring[2], ring[3], 1)
            node.icon:SetDesaturated(ring == RING_LOCKED)
        end
        for i, link in ipairs(Angler.Links) do
            if link.route == 0 then
                local color = maxed[link.from] and LINK_DONE or LINK_IDLE
                view.links[i]:SetColorTexture(color[1], color[2], color[3], color[4])
            end
        end
    end

    return view
end

---------------------------------------------------------------------------
-- Tips
---------------------------------------------------------------------------

local function TipSections()
    return {
        { ns.L["1. Level Legion Fishing to 100"],
          ns.L["Fish in Dalaran until you reach 100 Legion Fishing; from 1 to 100 expect roughly 200 fish. Buy Arcane Lures with the Drowned Mana you collect along the way."] },
        { ns.L["2. Get the Luminous Pearl"],
          ns.L["At 100 Legion Fishing, find a nearby fishing school and use an Arcane Lure. Keep fishing schools until you catch the Luminous Pearl and can start its questline."] },
        { ns.L["3. Complete the Luminous Pearl questline"],
          ns.L["After Fishing Frenzy, continue the questline in Dalaran. Khadgar is inside The Violet Citadel, not at the yellow quest marker shown elsewhere on the map. If Brann Bronzebeard does not appear at the Luminous Pearl in the Dalaran fountain, try relogging."] },
        { ns.L["4. Farm Artifact Power efficiently"],
          ns.L["Instead of travelling around the Broken Isles, use Arcane Lures on Cursed Queenfish Schools in Azsuna. Fish until you get the brooch, use it to reveal Ghostly Queenfish Schools nearby, then fish those while the effect lasts. Keep fishing for another brooch to continue the cycle."] },
        { ns.L["5. Artifact Power targets"],
          ns.L["As a rough target from testing: about 2,650 Artifact Power for the water walking and swimming path, and around 6,000 if you also want reduced threat while fishing. Costs rise as more ranks are purchased."] },
        { ns.L["6. Traits unlocked but not working?"],
          ns.L["If water walking or swimming still does not work, speak to Mahra Treebender, the Profession Equipment Specialist, and make sure your fishing profession equipment is not hidden."] },
    }
end

local function BuildTips(parent)
    local view = CreateFrame("Frame", nil, parent)

    view.heading = Text(view, 16)
    view.heading:SetPoint("TOPLEFT", 20, -16)
    view.heading:SetText(ns.L["Tips for alts"])

    view.body = Text(view, 13)
    view.body:SetPoint("TOPLEFT", 24, -52)
    view.body:SetPoint("RIGHT", -24, 0)
    view.body:SetSpacing(4)
    view.body:SetWordWrap(true)

    function view.Refresh()
        local accent = AccentHex()
        local lines = {
            ns.L["Already unlocked the Underlight Angler on another character? These shortcuts make the next one faster."],
        }
        for _, section in ipairs(TipSections()) do
            lines[#lines + 1] = ""
            lines[#lines + 1] = accent .. section[1] .. "|r"
            lines[#lines + 1] = section[2]
        end
        view.body:SetText(table.concat(lines, "\n"))
        view.body:SetTextColor(Color("text", { 1, 1, 1, 1 }))
    end

    return view
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local VIEW_BUILDERS = { checklist = BuildChecklist, tree = BuildTree, tips = BuildTips }

local function ViewLabels()
    return {
        checklist = ns.L["Checklist"],
        tree = ns.L["Artifact Tree"],
        tips = ns.L["Tips"],
    }
end

local function Reskin()
    local r, g, b = Color("bg", { 0.051, 0.067, 0.09, 0.97 })
    win._bg:SetVertexColor(r, g, b, PanelAlpha())
    UIKit.UpdateBorderLines(win, 1, Color("border", { 1, 1, 1, 0.06 }))
    win._titleSep:SetColorTexture(Color("border", { 1, 1, 1, 0.06 }))
    win._bodyBg:SetColorTexture(Color("bgContent", { 1, 1, 1, 0.02 }))
    win._title:SetTextColor(Color("accentLight", { 0.431, 0.906, 0.718, 1 }))
    tabs.checklist:SetShown(not host)
    for id, tab in pairs(tabs) do
        tab:SetActive(id == activeView)
    end
end

local function SelectView(id)
    activeView = id
    for viewID, view in pairs(views) do
        view:SetShown(viewID == id)
    end
    for viewID, tab in pairs(tabs) do
        tab:SetActive(viewID == id)
    end
    views[id].Refresh()
end

-- Blizzard's own tab buttons hang below its window, outside the overlay. They
-- are faded, not hidden: Blizzard shows and hides them itself.
local function MuteHostTabs(muted)
    if not host then return end
    for _, key in ipairs(HOST_TABS) do
        local tab = host[key]
        if tab then
            tab:SetAlpha(muted and 0 or 1)
            tab:EnableMouse(not muted)
        end
    end
end

-- The content is laid out for one size, so the embedded window is scaled to
-- cover its host and is not stretched to it.
local function ApplyPlacement()
    win:SetParent(host or UIParent)
    win:ClearAllPoints()
    win:SetFrameStrata(EMBED_STRATA)
    if host then
        local scale = math.max(host:GetWidth() / win:GetWidth(), host:GetHeight() / win:GetHeight())
        win:SetScale(scale > 0 and scale or 1)
        win:SetPoint("CENTER", host, "CENTER")
        win:SetFrameLevel(EMBED_LEVEL)
    else
        win:SetScale(1)
        win:SetPoint("CENTER")
        win:SetFrameLevel(1)
    end
    win:SetToplevel(not host)
    win:SetClampedToScreen(not host)
    -- Escape closes the free-standing window itself. Embedded, it closes the
    -- host and the overlay goes with it.
    tDeleteItem(UISpecialFrames, FRAME_NAME)
    if not host then tinsert(UISpecialFrames, FRAME_NAME) end
end

local function Build()
    win = CreateFrame("Frame", FRAME_NAME, UIParent)
    win:SetSize(BODY_W + PAD * 2, HEADER_H + PAD + BODY_H + PAD)
    win:SetMovable(true)
    win:EnableMouse(true)
    ApplyPlacement()
    if win.SetDontSavePosition then win:SetDontSavePosition(true) end
    win:Hide()

    win._bg = win:CreateTexture(nil, "BACKGROUND")
    win._bg:SetAllPoints()
    win._bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    UIKit.DisablePixelSnap(win._bg)
    UIKit.CreateBorderLines(win)

    local header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_H)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if not host then win:StartMoving() end
    end)
    header:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)

    win._title = Text(header, 14)
    win._title:SetPoint("LEFT", 12, 0)
    win._title:SetText(ns.L["Underlight Angler"])

    win._close = UIKit.CreateCloseButton(header, {
        point = "RIGHT", x = -8, y = 0,
        -- Embedded, the overlay is the artifact window as far as the player
        -- can tell, so closing it closes both.
        onClick = function()
            if host then HideUIPanel(host) else win:Hide() end
        end,
    })

    local labels = ViewLabels()
    local fontPath = Font()
    local prev
    for i = #VIEW_ORDER, 1, -1 do
        local id = VIEW_ORDER[i]
        local tab = UIKit.CreateTabButton(header, {
            label = labels[id], height = 22, minWidth = 96,
            fontPath = fontPath, fontSize = 12,
            onClick = function() SelectView(id) end,
        })
        if prev then
            tab:SetPoint("RIGHT", prev, "LEFT", -4, 0)
        else
            tab:SetPoint("RIGHT", win._close, "LEFT", -12, 0)
        end
        tabs[id] = tab
        prev = tab
    end

    win._titleSep = win:CreateTexture(nil, "ARTWORK")
    win._titleSep:SetPoint("TOPLEFT", PAD, -HEADER_H)
    win._titleSep:SetPoint("TOPRIGHT", -PAD, -HEADER_H)
    win._titleSep:SetHeight(1)
    UIKit.DisablePixelSnap(win._titleSep)

    local body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", PAD, -(HEADER_H + PAD))
    body:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    body:SetClipsChildren(true)
    win._bodyBg = body:CreateTexture(nil, "BACKGROUND", nil, -8)
    win._bodyBg:SetAllPoints()
    UIKit.DisablePixelSnap(win._bodyBg)

    for _, id in ipairs(VIEW_ORDER) do
        local view = VIEW_BUILDERS[id](body)
        view:SetAllPoints(body)
        view:Hide()
        views[id] = view
    end

    win:SetScript("OnEvent", function() Window.QueueRefresh() end)
    win:SetScript("OnShow", function(self)
        for _, event in ipairs(EVENTS) do self:RegisterEvent(event) end
        MuteHostTabs(true)
    end)
    win:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        self:UnregisterAllEvents()
        StaticPopup_Hide(BUY_POPUP)
        MuteHostTabs(false)
    end)
end

-- Quest-log and bag events arrive in bursts; one repaint per burst is plenty.
function Window.QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(REFRESH_DELAY, function()
        refreshQueued = false
        if win and win:IsShown() then views[activeView].Refresh() end
    end)
end

-- Embeds the window in `frame`, or frees it again when `frame` is nil.
function Window.SetHost(frame)
    if frame == host then return end
    MuteHostTabs(false)
    host = frame
    if not win then return end
    win:StopMovingOrSizing()
    ApplyPlacement()
    tabs.checklist:SetShown(not host)
    if host and activeView == "checklist" then SelectView("tree") end
    if win:IsVisible() then MuteHostTabs(true) end
end

function Window.IsEmbedded()
    return host ~= nil
end

function Window.IsShown()
    return win and win:IsShown() or false
end

function Window.Hide()
    if win then win:Hide() end
end

function Window.Show(viewID)
    if not win then Build() end
    Reskin()
    win:Show()
    if not views[viewID] or (host and viewID == "checklist") then
        viewID = host and "tree" or "checklist"
    end
    SelectView(viewID)
end

function Window.Toggle(viewID)
    if Window.IsShown() then
        Window.Hide()
    else
        Window.Show(viewID)
    end
end

if ns.Registry then
    ns.Registry:Register("underlightAnglerSkin", {
        refresh = function()
            if win and win:IsShown() then
                Reskin()
                views[activeView].Refresh()
            end
        end,
        priority = 50,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end
