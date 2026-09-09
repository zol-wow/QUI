-- QUI_Reminders/reminders/settings/reminders_content.lua -- the Reminders page.
--
-- Loaded by QUI_Options, so it must work whether or not the QUI_Reminders
-- module is loaded: without it the page only says where to turn it on.
--
-- Three parts: the switches (general + callout), this spec's defensive
-- priority list, and the per-boss ability picker read from the Dungeon
-- Journal. The last two are dynamic lists that repaint in place; the page
-- height follows them.
local _, ns = ...

local QUI = _G.QUI
local GUI = QUI and QUI.GUI
local Shared = ns.QUI_Options
local Settings = ns.Settings
local Registry = Settings and Settings.Registry
local Schema = Settings and Settings.Schema
local RenderAdapters = Settings and Settings.RenderAdapters

local PAD = (Shared and Shared.PADDING) or 15
local ROW_H = 26
local ROW_GAP = 2
local SECTION_GAP = 14
local HEADER_H = 26
local SUBPAGE_INDEX = 9
local FALLBACK_ICON = 134400

local ROLE_COLORS = {
    Tank = { 0.94, 0.66, 0.19 },
    Healer = { 0.43, 0.82, 0.60 },
    Dps = { 1.0, 0.38, 0.38 },
}
local ROLE_LABELS = {
    Tank = ns.L["Tank"],
    Healer = ns.L["Healer"],
    Dps = ns.L["DPS"],
    Deadly = ns.L["Deadly"],
    Important = ns.L["Important"],
    Interruptible = ns.L["Interruptible"],
}

local function GetDB()
    local db = Shared and Shared.GetDB and Shared.GetDB()
    return db and db.reminders
end

local function Refresh()
    if _G.QUI_RefreshReminders then _G.QUI_RefreshReminders() end
end

local function MarkAbilitiesDirty()
    if ns.Reminders and ns.Reminders.MarkAbilitiesDirty then ns.Reminders.MarkAbilitiesDirty() end
end

local function Colors()
    return (GUI and GUI.Colors) or {}
end

local function SubTable(db, key)
    if type(db[key]) ~= "table" then db[key] = {} end
    return db[key]
end

local function MakeLayout(content)
    return ns.QUI_SettingsLayoutShared.MakeLayout(content)
end

local function row(parent, label, widget, desc)
    return Shared.BuildSettingRow(parent, label, widget, desc)
end

local function Label(parent, text, size, color)
    return GUI:CreateLabel(parent, text, size or 11, color or Colors().text)
end

local function Muted(parent, text)
    local lbl = Label(parent, text, 11, Colors().textMuted)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(true)
    return lbl
end

-------------------------------------------------------------------------------
-- Row list helper: pooled rows with icon, name, note, and up to three buttons
-------------------------------------------------------------------------------
local function NewList(parent)
    local list = { frame = CreateFrame("Frame", nil, parent), rows = {} }
    list.frame:SetHeight(1)

    local function AcquireRow(index)
        local r = list.rows[index]
        if r then return r end
        r = CreateFrame("Frame", nil, list.frame)
        r:SetHeight(ROW_H)
        r:SetPoint("LEFT", list.frame, "LEFT", 0, 0)
        r:SetPoint("RIGHT", list.frame, "RIGHT", 0, 0)
        if index % 2 == 0 then
            local bg = r:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.03)
        end
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(20, 20)
        r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.name = Label(r, "", 12)
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.name:SetJustifyH("LEFT")
        r.note = Label(r, "", 10, Colors().textMuted)
        r.note:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
        r.note:SetJustifyH("LEFT")
        r.buttons = {}
        -- The real spell tooltip is how you tell same-name abilities apart.
        -- Only the icon is a hover target, and the tooltip sits at the cursor.
        -- Painters set tooltipSpellID (a spell) or tooltipSlot (an equipped
        -- trinket) on the row; Paint clears both before every repaint.
        local hit = CreateFrame("Frame", nil, r)
        hit:SetAllPoints(r.icon)
        hit:EnableMouse(true)
        hit:SetScript("OnEnter", function()
            if not GameTooltip then return end
            local ok = false
            if r.tooltipSlot then
                GameTooltip:SetOwner(hit, "ANCHOR_CURSOR")
                ok = ns.SafeCall("best-effort-style", GameTooltip.SetInventoryItem, GameTooltip, "player", r.tooltipSlot)
            elseif r.tooltipSpellID then
                GameTooltip:SetOwner(hit, "ANCHOR_CURSOR")
                ok = ns.SafeCall("best-effort-style", GameTooltip.SetSpellByID, GameTooltip, r.tooltipSpellID)
            end
            if ok then GameTooltip:Show() else GameTooltip:Hide() end
        end)
        hit:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        r.iconHit = hit
        list.rows[index] = r
        return r
    end

    -- items: array; painter(rowFrame, item, index) fills the row.
    function list.Paint(items, painter)
        local y = 0
        for i = 1, #items do
            local r = AcquireRow(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", list.frame, "TOPLEFT", 0, -y)
            r:SetPoint("RIGHT", list.frame, "RIGHT", 0, 0)
            for _, b in ipairs(r.buttons) do b:Hide() end
            if r.check then r.check:Hide() end
            r.tooltipSpellID = nil
            r.tooltipSlot = nil
            r.icon:SetTexture(FALLBACK_ICON)
            r.name:SetText("")
            r.note:SetText("")
            r.name:SetTextColor(Colors().text[1] or 1, Colors().text[2] or 1, Colors().text[3] or 1, 1)
            painter(r, items[i], i)
            r:Show()
            y = y + ROW_H + ROW_GAP
        end
        for i = #items + 1, #list.rows do list.rows[i]:Hide() end
        list.frame:SetHeight(math.max(y, 1))
        return y
    end

    -- Buttons are laid right-to-left; slot 1 is the right-most.
    function list.Button(r, slot, text, onClick, variant)
        local b = r.buttons[slot]
        if not b then
            b = GUI:CreateButton(r, text, 24, 20, nil, variant)
            r.buttons[slot] = b
            if slot == 1 then
                b:SetPoint("RIGHT", r, "RIGHT", -4, 0)
            else
                b:SetPoint("RIGHT", r.buttons[slot - 1], "LEFT", -4, 0)
            end
        end
        if b.SetText then b:SetText(text) end
        if b.SetWidth then b:SetWidth(math.max(24, (#text * 7) + 12)) end
        b:SetScript("OnClick", onClick)
        b:Show()
        return b
    end

    function list.Check(r, checked, onChange)
        local c = r.check
        if not c then
            c = GUI:CreateAccentCheckbox(r, { size = 18, checked = checked, onChange = onChange })
            if not c then return nil end
            c:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            r.check = c
        else
            c.onChange = nil
            if c.SetChecked then c:SetChecked(checked, true) end
            c.onChange = onChange
        end
        c:Show()
        return c
    end

    return list
end

-- UIKit's accent checkbox reads options.onChange once at creation; keep a
-- per-row indirection so repaints can swap the handler.
local function CheckHandler(r)
    return function(val)
        if r.onCheck then r.onCheck(val) end
    end
end

-------------------------------------------------------------------------------
-- Static sections
-------------------------------------------------------------------------------
local function SourceOptions()
    local bus = ns.BossMods
    local function tag(source, text)
        if bus and bus.IsAvailable and bus.IsAvailable(source) then return text end
        return text .. " " .. ns.L["(not found)"]
    end
    return {
        { value = "auto", text = ns.L["Automatic"] },
        { value = "bigwigs", text = tag("bigwigs", "BigWigs") },
        { value = "dbm", text = tag("dbm", "DBM") },
        { value = "timeline", text = tag("timeline", ns.L["Blizzard Encounter Timeline"]) },
    }
end

local function BuildGeneral(L, db)
    L.headerAt(ns.L["General"])
    local s = L.sectionAt()
    local enableW = GUI:CreateFormCheckbox(s.frame, nil, "enabled", db, Refresh,
        { description = ns.L["Call out which defensive to press when a boss mod says an ability is coming."] })
    local sourceW = GUI:CreateFormDropdown(s.frame, nil, SourceOptions(), "source", db, Refresh,
        { description = ns.L["Which boss timer source drives the callouts. Automatic uses BigWigs, then DBM, then Blizzard's encounter timeline."] })
    s.AddRow(row(s.frame, ns.L["Enable Reminders"], enableW), row(s.frame, ns.L["Boss Mod Source"], sourceW))

    local dungeonsW = GUI:CreateFormCheckbox(s.frame, nil, "inDungeons", db, Refresh,
        { description = ns.L["Call out defensives in dungeons."] })
    local raidsW = GUI:CreateFormCheckbox(s.frame, nil, "inRaids", db, Refresh,
        { description = ns.L["Call out defensives in raids."] })
    s.AddRow(row(s.frame, ns.L["In Dungeons"], dungeonsW), row(s.frame, ns.L["In Raids"], raidsW))

    local elsewhereW = GUI:CreateFormCheckbox(s.frame, nil, "elsewhere", db, Refresh,
        { description = ns.L["Also call out defensives outside dungeons and raids, for world bosses and testing."] })
    local messagesW = GUI:CreateFormCheckbox(s.frame, nil, "fireOnMessages", db, Refresh,
        { description = ns.L["Also react to boss mod warning messages, for abilities that have no countdown bar."] })
    s.AddRow(row(s.frame, ns.L["Outside Instances"], elsewhereW), row(s.frame, ns.L["React To Messages"], messagesW))

    local leadW = GUI:CreateFormSlider(s.frame, nil, -5, 10, 0.5, "leadTime", db, Refresh,
        { description = ns.L["Seconds before the ability lands that the callout appears. A negative value calls the defensive that many seconds after it lands."] })
    local lingerW = GUI:CreateFormSlider(s.frame, nil, 1, 15, 0.5, "linger", db, Refresh,
        { description = ns.L["How long the callout stays on screen."] })
    s.AddRow(row(s.frame, ns.L["Warning Time"], leadW), row(s.frame, ns.L["Linger"], lingerW))

    local tankingW = GUI:CreateFormCheckbox(s.frame, nil, "onlyWhenTanking", db, Refresh,
        { description = ns.L["On a tank spec, only call out when the boss is on you. Healer and damage specs are never gated."] })
    local coveredW = GUI:CreateFormCheckbox(s.frame, nil, "skipWhenCovered", db, Refresh,
        { description = ns.L["Stay quiet when one of the listed defensives is already active on you."] })
    s.AddRow(row(s.frame, ns.L["Only When Tanking"], tankingW), row(s.frame, ns.L["Skip When Covered"], coveredW))

    local timelineW = GUI:CreateFormCheckbox(s.frame, nil, "timelineAllEvents", db, Refresh,
        { description = ns.L["Blizzard's encounter timeline keeps its ability names secret, so with that source every encounter countdown triggers a callout."] })
    s.AddRow(row(s.frame, ns.L["Timeline: Every Event"], timelineW))
    L.closeSection(s)
end

local function BuildCallout(L, db)
    local display = SubTable(db, "display")
    local sound = SubTable(db, "sound")
    local chat = SubTable(db, "chat")

    L.headerAt(ns.L["Callout"])
    local s = L.sectionAt()
    local showIconW = GUI:CreateFormCheckbox(s.frame, nil, "showIcon", display, Refresh,
        { description = ns.L["Show the defensive's icon."] })
    local iconSizeW = GUI:CreateFormSlider(s.frame, nil, 24, 128, 1, "iconSize", display, Refresh,
        { description = ns.L["Size of the callout icon in pixels."] })
    s.AddRow(row(s.frame, ns.L["Show Icon"], showIconW), row(s.frame, ns.L["Icon Size"], iconSizeW))

    local showTextW = GUI:CreateFormCheckbox(s.frame, nil, "showText", display, Refresh,
        { description = ns.L["Show the defensive's name next to the icon."] })
    local textSizeW = GUI:CreateFormSlider(s.frame, nil, 8, 40, 1, "textSize", display, Refresh,
        { description = ns.L["Font size of the callout text."] })
    s.AddRow(row(s.frame, ns.L["Show Text"], showTextW), row(s.frame, ns.L["Text Size"], textSizeW))

    local sideOptions = {
        { value = "BOTTOM", text = ns.L["Below"] },
        { value = "TOP", text = ns.L["Above"] },
        { value = "LEFT", text = ns.L["Left"] },
        { value = "RIGHT", text = ns.L["Right"] },
    }
    local sideW = GUI:CreateFormDropdown(s.frame, nil, sideOptions, "textSide", display, Refresh,
        { description = ns.L["Which side of the icon the text sits on."] })
    local glowW = GUI:CreateFormCheckbox(s.frame, nil, "glow", display, Refresh,
        { description = ns.L["Pulse a glow around the callout icon."] })
    s.AddRow(row(s.frame, ns.L["Text Position"], sideW), row(s.frame, ns.L["Icon Glow"], glowW))

    local cdmGlowW = GUI:CreateFormCheckbox(s.frame, nil, "cdmGlow", db, Refresh,
        { description = ns.L["Also glow the called defensive on the Cooldown Manager while the callout is up."] })
    s.AddRow(row(s.frame, ns.L["Cooldown Manager Glow"], cdmGlowW))
    L.closeSection(s)

    L.headerAt(ns.L["Sound & Chat"])
    local a = L.sectionAt()
    local modeOptions = {
        { value = "off", text = ns.L["Off"] },
        { value = "sound", text = ns.L["Sound"] },
        { value = "tts", text = ns.L["Text-to-Speech"] },
    }
    local modeW = GUI:CreateFormDropdown(a.frame, nil, modeOptions, "mode", sound, Refresh,
        { description = ns.L["Play a sound, speak the defensive's name, or stay silent."] })
    local soundW = GUI:CreateFormDropdown(a.frame, nil, Shared.GetSoundList(), "sound", sound, function()
        Refresh()
        if ns.Announce and ns.Announce.PlaySound then ns.Announce.PlaySound(sound.sound) end
    end, { description = ns.L["Sound to play when a defensive is called."] })
    a.AddRow(row(a.frame, ns.L["Audio"], modeW), row(a.frame, ns.L["Sound"], soundW))

    local ttsModeOptions = {
        { value = "name", text = ns.L["Defensive Name"] },
        { value = "custom", text = ns.L["Custom Phrase"] },
    }
    local ttsModeW = GUI:CreateFormDropdown(a.frame, nil, ttsModeOptions, "ttsMode", sound, Refresh,
        { description = ns.L["What text-to-speech says: the called defensive's name, or one phrase of your own."] })
    local ttsTextW = GUI:CreateFormEditBox(a.frame, nil, "ttsText", sound, function()
        Refresh()
        if sound.ttsMode == "custom" and ns.Announce and ns.Announce.Speak then ns.Announce.Speak(sound.ttsText) end
    end, { description = ns.L["Phrase spoken instead of the defensive's name, for example \"defensive\"."], width = 160 })
    a.AddRow(row(a.frame, ns.L["Spoken Text"], ttsModeW), row(a.frame, ns.L["Custom Phrase"], ttsTextW))

    local chatOnW = GUI:CreateFormCheckbox(a.frame, nil, "enabled", chat, Refresh,
        { description = ns.L["Post a chat line naming the ability and the defensive you are using."] })
    local channelOptions = {
        { value = "SAY", text = ns.L["Say"] },
        { value = "YELL", text = ns.L["Yell"] },
        { value = "PARTY", text = ns.L["Party"] },
        { value = "RAID", text = ns.L["Raid"] },
        { value = "INSTANCE_CHAT", text = ns.L["Instance"] },
    }
    local channelW = GUI:CreateFormDropdown(a.frame, nil, channelOptions, "channel", chat, Refresh,
        { description = ns.L["Chat channel for the announcement."] })
    a.AddRow(row(a.frame, ns.L["Announce In Chat"], chatOnW), row(a.frame, ns.L["Channel"], channelW))
    L.closeSection(a)

    local actions = CreateFrame("Frame", nil, L.content or nil)
    local previewBtn = GUI:CreateButton(actions, ns.L["Toggle Preview"], 140, 28, function()
        if _G.QUI_ToggleRemindersPreview then _G.QUI_ToggleRemindersPreview() end
    end)
    previewBtn:SetPoint("TOPLEFT", 0, -6)
    local testBtn = GUI:CreateButton(actions, ns.L["Test Callout"], 140, 28, function()
        if ns.Reminders and ns.Reminders.Test then ns.Reminders.Test() end
    end)
    testBtn:SetPoint("LEFT", previewBtn, "RIGHT", 8, 0)
    L.placeCustom(actions, 40)
end

-------------------------------------------------------------------------------
-- Priority list (this spec)
-------------------------------------------------------------------------------
local function SpecName()
    local specAPI = _G.C_SpecializationInfo
    local idx = specAPI and specAPI.GetSpecialization and specAPI.GetSpecialization()
    if idx and _G.GetSpecializationInfo then
        local _, name = _G.GetSpecializationInfo(idx)
        if type(name) == "string" then return name end
    end
    return ns.L["Current Spec"]
end

local function CurrentPriorityList(db, create)
    local D = ns.RemindersDefensives
    local specID = D and D.PlayerSpecID and D.PlayerSpecID()
    if not specID then return nil end
    local priorities = SubTable(db, "priorities")
    if type(priorities[specID]) ~= "table" then
        if not create then return {}, specID end
        priorities[specID] = {}
    end
    return priorities[specID], specID
end

local function InList(list, id)
    for i = 1, #list do
        if list[i] == id then return i end
    end
    return nil
end

local function BuildPrioritySection(content, db, onResize)
    local D = ns.RemindersDefensives
    local frame = CreateFrame("Frame", nil, content)
    local header = Shared.CreateAccentDotLabel(frame, ns.L["Defensive Priority"], 0)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    local hint = Muted(frame, ns.L["Top to bottom: the first defensive that is ready is the one called. Lists are saved per spec."])
    hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -HEADER_H - 4)
    hint:SetPoint("RIGHT", frame, "RIGHT", -4, 0)

    local specLabel = Label(frame, "", 12, Colors().accent)
    specLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -HEADER_H - 26)

    local chosen = NewList(frame)
    chosen.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -HEADER_H - 46)
    chosen.frame:SetPoint("RIGHT", frame, "RIGHT", 0, 0)

    local availLabel = Label(frame, ns.L["Available"], 12, Colors().accent)
    local avail = NewList(frame)
    avail.frame:SetPoint("RIGHT", frame, "RIGHT", 0, 0)

    local manual = CreateFrame("Frame", nil, frame)
    manual:SetHeight(30)
    manual:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    local manualState = { spellID = "" }
    local manualBox = GUI:CreateFormEditBox(manual, nil, "spellID", manualState, nil, { width = 120 })
    manualBox:SetPoint("LEFT", manual, "LEFT", 4, 0)
    local manualLabel = Muted(manual, ns.L["Add by spell ID"])
    manualLabel:SetPoint("LEFT", manualBox, "RIGHT", 8, 0)

    local Repaint

    local addBtn = GUI:CreateButton(manual, ns.L["Add"], 60, 22, function()
        local id = tonumber(manualState.spellID)
        if not id or id <= 0 then return end
        local list = CurrentPriorityList(db, true)
        if list and not InList(list, id) then
            list[#list + 1] = id
            Refresh()
            Repaint()
        end
    end, "primary")
    addBtn:SetPoint("LEFT", manualLabel, "RIGHT", 8, 0)

    local function BindTooltip(r, entry)
        if entry.kind == "item" and entry.slot then
            r.tooltipSlot = entry.slot
        elseif type(entry.spellID) == "number" then
            r.tooltipSpellID = entry.spellID
        end
    end

    local function PaintChosen(r, entry, index)
        local list = CurrentPriorityList(db, true)
        BindTooltip(r, entry)
        r.icon:SetTexture(entry.icon or FALLBACK_ICON)
        r.name:SetText(("%d. %s"):format(index, entry.name or "?"))
        if entry.known == false then
            r.note:SetText(ns.L["(not known on this spec)"])
        elseif entry.kind == "item" then
            r.note:SetText(ns.L["(trinket)"])
        end
        chosen.Button(r, 1, ns.L["Remove"], function()
            table.remove(list, index)
            Refresh()
            Repaint()
        end, "danger")
        chosen.Button(r, 2, "v", function()
            if index < #list then
                list[index], list[index + 1] = list[index + 1], list[index]
                Refresh()
                Repaint()
            end
        end)
        chosen.Button(r, 3, "^", function()
            if index > 1 then
                list[index], list[index - 1] = list[index - 1], list[index]
                Refresh()
                Repaint()
            end
        end)
    end

    local function PaintAvailable(r, entry)
        BindTooltip(r, entry)
        r.icon:SetTexture(entry.icon or FALLBACK_ICON)
        r.name:SetText(entry.name or "?")
        if entry.known == false then
            r.note:SetText(ns.L["(not known on this spec)"])
            r.name:SetTextColor(0.6, 0.6, 0.6, 1)
        elseif entry.kind == "item" then
            r.note:SetText(ns.L["(trinket)"])
        end
        avail.Button(r, 1, ns.L["Add"], function()
            local list = CurrentPriorityList(db, true)
            if list and not InList(list, entry.id) then
                list[#list + 1] = entry.id
                Refresh()
                Repaint()
            end
        end, "primary")
    end

    Repaint = function()
        specLabel:SetText(SpecName())
        local list = CurrentPriorityList(db, false) or {}
        local chosenItems = {}
        for i = 1, #list do
            local entry = D and D.Describe(list[i])
            if entry then
                chosenItems[#chosenItems + 1] = entry
            else
                chosenItems[#chosenItems + 1] = { id = list[i], name = tostring(list[i]), icon = FALLBACK_ICON, known = false }
            end
        end
        local chosenH = chosen.Paint(chosenItems, PaintChosen)
        if #chosenItems == 0 then chosenH = 8 end

        local availItems = {}
        if D then
            for _, entry in ipairs(D.SpecCandidates()) do
                if not InList(list, entry.id) then availItems[#availItems + 1] = entry end
            end
            for _, entry in ipairs(D.TrinketCandidates()) do
                if not InList(list, entry.id) then availItems[#availItems + 1] = entry end
            end
        end
        availLabel:ClearAllPoints()
        availLabel:SetPoint("TOPLEFT", chosen.frame, "BOTTOMLEFT", 4, -8)
        avail.frame:ClearAllPoints()
        avail.frame:SetPoint("TOPLEFT", availLabel, "BOTTOMLEFT", -4, -6)
        avail.frame:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        local availH = avail.Paint(availItems, PaintAvailable)
        if #availItems == 0 then availH = 8 end
        chosen.frame:SetHeight(math.max(chosenH, 8))
        avail.frame:SetHeight(math.max(availH, 8))

        manual:ClearAllPoints()
        manual:SetPoint("TOPLEFT", avail.frame, "BOTTOMLEFT", 0, -6)
        manual:SetPoint("RIGHT", frame, "RIGHT", 0, 0)

        local total = HEADER_H + 46 + chosenH + 8 + 18 + 6 + availH + 6 + 30 + 8
        frame:SetHeight(total)
        if onResize then onResize() end
    end

    frame.Repaint = Repaint
    Repaint()
    return frame
end

-------------------------------------------------------------------------------
-- Boss abilities
-------------------------------------------------------------------------------
local pickerState = { instance = nil, encounter = nil }

local function InstanceOptions(catalog)
    local options = {}
    for _, inst in ipairs(catalog.instances) do
        local prefix = inst.isRaid and ns.L["Raid"] or ns.L["Dungeon"]
        options[#options + 1] = { value = inst.id, text = ("%s: %s"):format(prefix, inst.name) }
    end
    return options
end

local function EncounterOptions(inst)
    local options = {}
    if inst then
        for _, enc in ipairs(inst.encounters) do
            options[#options + 1] = { value = enc.id, text = enc.name }
        end
    end
    return options
end

local function FindInstance(catalog, instanceID)
    for _, inst in ipairs(catalog.instances) do
        if inst.id == instanceID then return inst end
    end
    return nil
end

local function FindEncounter(inst, encounterID)
    if not inst then return nil end
    for _, enc in ipairs(inst.encounters) do
        if enc.id == encounterID then return enc end
    end
    return nil
end

local function FlagsText(flags)
    if type(flags) ~= "table" then return "" end
    local parts = {}
    for _, key in ipairs({ "Tank", "Healer", "Dps", "Deadly", "Important", "Interruptible" }) do
        if flags[key] then
            local color = ROLE_COLORS[key]
            local text = ROLE_LABELS[key] or key
            if color then
                text = ("|cff%02x%02x%02x%s|r"):format(color[1] * 255, color[2] * 255, color[3] * 255, text)
            end
            parts[#parts + 1] = text
        end
    end
    return table.concat(parts, " ")
end

local function SeenEntries(db)
    local core = _G.QUI
    local global = core and core.db and core.db.global
    local seen = global and global.reminders and global.reminders.seen
    local out = {}
    if type(seen) ~= "table" then return out end
    local J = ns.RemindersJournal
    for spellID, rec in pairs(seen) do
        local id = tonumber(spellID)
        if id and type(rec) == "table" and not (J and J.IsCached() and J.FindAbility(id)) then
            local name
            if _G.C_Spell and _G.C_Spell.GetSpellName then
                local ok, n = pcall(_G.C_Spell.GetSpellName, id)
                if ok and type(n) == "string" then name = n end
            end
            out[#out + 1] = {
                spellID = id,
                name = name or rec.text or ("#" .. id),
                icon = type(rec.icon) ~= "table" and rec.icon or nil,
                count = tonumber(rec.count) or 0,
            }
        end
    end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end

local function BuildBossSection(content, db, onResize)
    local frame = CreateFrame("Frame", nil, content)
    local header = Shared.CreateAccentDotLabel(frame, ns.L["Boss Abilities"], 0)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    local hint = Muted(frame, ns.L["Tick the abilities you want a defensive called for. Bosses and abilities come from your Dungeon Journal for the current season; abilities the boss mod has broadcast that the journal does not list appear at the bottom."])
    hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -HEADER_H - 4)
    hint:SetPoint("RIGHT", frame, "RIGHT", -4, 0)

    local picker = CreateFrame("Frame", nil, frame)
    picker:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -HEADER_H - 40)
    picker:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    picker:SetHeight(36)

    local list = NewList(frame)
    list.frame:SetPoint("TOPLEFT", picker, "BOTTOMLEFT", 0, -6)
    list.frame:SetPoint("RIGHT", frame, "RIGHT", 0, 0)

    local seenLabel = Label(frame, ns.L["Seen From Boss Mods"], 12, Colors().accent)
    local seen = NewList(frame)
    seen.frame:SetPoint("RIGHT", frame, "RIGHT", 0, 0)

    local status = Muted(frame, "")
    status:SetPoint("TOPLEFT", picker, "BOTTOMLEFT", 4, -6)
    status:SetPoint("RIGHT", frame, "RIGHT", -4, 0)

    local Repaint

    local function AbilityBucket(encounterID, create)
        local abilities = SubTable(db, "abilities")
        if type(abilities[encounterID]) ~= "table" then
            if not create then return {} end
            abilities[encounterID] = {}
        end
        return abilities[encounterID]
    end

    local function SetAbility(encounterID, spellID, on)
        local bucket = AbilityBucket(encounterID, true)
        bucket[spellID] = on and true or nil
        if next(bucket) == nil then SubTable(db, "abilities")[encounterID] = nil end
        MarkAbilitiesDirty()
    end

    local function PaintAbility(encounterID)
        return function(r, ability)
            r.tooltipSpellID = ability.spellID
            r.icon:SetTexture(ability.icon or FALLBACK_ICON)
            r.name:SetText(ability.name or ("#" .. ability.spellID))
            r.note:SetText(FlagsText(ability.flags))
            r.onCheck = function(val) SetAbility(encounterID, ability.spellID, val) end
            local bucket = AbilityBucket(encounterID, false)
            list.Check(r, bucket[ability.spellID] == true, CheckHandler(r))
        end
    end

    local function PaintSeen(r, entry)
        r.tooltipSpellID = entry.spellID
        r.icon:SetTexture(entry.icon or FALLBACK_ICON)
        r.name:SetText(entry.name)
        r.note:SetText(("x%d"):format(entry.count))
        r.onCheck = function(val) SetAbility("seen", entry.spellID, val) end
        local bucket = AbilityBucket("seen", false)
        seen.Check(r, bucket[entry.spellID] == true, CheckHandler(r))
    end

    local function RebuildPicker(catalog)
        GUI:TeardownFrameTree(picker)
        local inst = FindInstance(catalog, pickerState.instance) or catalog.instances[1]
        pickerState.instance = inst and inst.id or nil
        local enc = FindEncounter(inst, pickerState.encounter) or (inst and inst.encounters[1])
        pickerState.encounter = enc and enc.id or nil

        local instW = GUI:CreateFormDropdown(picker, nil, InstanceOptions(catalog), "instance", pickerState, function()
            pickerState.encounter = nil
            Repaint()
        end, nil, { searchable = true })
        instW:SetPoint("LEFT", picker, "LEFT", 4, 0)
        local encW = GUI:CreateFormDropdown(picker, nil, EncounterOptions(inst), "encounter", pickerState, function()
            Repaint()
        end, nil, { searchable = true })
        encW:SetPoint("LEFT", instW, "RIGHT", 12, 0)

        local D = ns.RemindersDefensives
        local role = D and D.PlayerRole and D.PlayerRole() or "DAMAGER"
        local roleFlag = (role == "TANK" and "Tank") or (role == "HEALER" and "Healer") or "Dps"
        local allBtn = GUI:CreateButton(picker, ns.L["Tick My Role"], 110, 22, function()
            if not enc then return end
            for _, ability in ipairs(enc.abilities) do
                if ability.flags and ability.flags[roleFlag] then SetAbility(enc.id, ability.spellID, true) end
            end
            Repaint()
        end)
        allBtn:SetPoint("LEFT", encW, "RIGHT", 12, 0)
        local clearBtn = GUI:CreateButton(picker, ns.L["Clear"], 70, 22, function()
            if not enc then return end
            SubTable(db, "abilities")[enc.id] = nil
            MarkAbilitiesDirty()
            Repaint()
        end)
        clearBtn:SetPoint("LEFT", allBtn, "RIGHT", 6, 0)
        return inst, enc
    end

    Repaint = function()
        local J = ns.RemindersJournal
        local catalog = J and J.Get and J.Get()
        local listH, seenH = 8, 8
        if not catalog or #catalog.instances == 0 then
            GUI:TeardownFrameTree(picker)
            status:SetText(ns.L["The Dungeon Journal has not answered yet. Close the journal if it is open and reopen this page."])
            list.Paint({}, function() end)
        else
            status:SetText("")
            local _, enc = RebuildPicker(catalog)
            local abilities = enc and enc.abilities or {}
            listH = list.Paint(abilities, PaintAbility(enc and enc.id or 0))
            if #abilities == 0 then
                status:SetText(ns.L["This boss lists no abilities in the journal."])
                listH = 20
            end
        end

        local seenItems = SeenEntries(db)
        seenLabel:ClearAllPoints()
        seenLabel:SetPoint("TOPLEFT", list.frame, "BOTTOMLEFT", 4, -8)
        seen.frame:ClearAllPoints()
        seen.frame:SetPoint("TOPLEFT", seenLabel, "BOTTOMLEFT", -4, -6)
        seen.frame:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        seenH = seen.Paint(seenItems, PaintSeen)
        seenLabel:SetShown(#seenItems > 0)
        if #seenItems == 0 then seenH = 0 end
        list.frame:SetHeight(math.max(listH, 8))

        local total = HEADER_H + 40 + 36 + 6 + listH + 8 + (seenH > 0 and (18 + 6 + seenH) or 0) + 12
        frame:SetHeight(total)
        if onResize then onResize() end
    end

    frame.Repaint = Repaint
    Repaint()
    return frame
end

-------------------------------------------------------------------------------
-- Page
-------------------------------------------------------------------------------
ns.QUI_RemindersOptions = ns.QUI_RemindersOptions or {}
local O = ns.QUI_RemindersOptions

function O.BuildRemindersContent(content)
    local db = GetDB()
    if not db then
        local noData = Label(content, ns.L["Reminders settings are not available. Please reload the UI."], 12, Colors().textMuted)
        noData:SetPoint("TOPLEFT", PAD, -20)
        content:SetHeight(80)
        return
    end

    local L = MakeLayout(content)
    L.content = content

    -- Settings are editable whether or not the module is loaded; only the
    -- runtime pieces (engine, journal reader, defensive catalog) need it.
    if not ns.Reminders then
        L.intro(ns.L["The Reminders module is not loaded. Turn it on under Module Addons, then come back here."])
    end

    L.intro(ns.L["When a boss mod says a boss ability is coming, QUI names the first defensive on your priority list that is ready to press. Pick the abilities per boss below."])
    BuildGeneral(L, db)
    BuildCallout(L, db)

    local baseY = L.getY()
    local prioFrame, bossFrame
    local function Relayout()
        local prioH = prioFrame and prioFrame:GetHeight() or 0
        local bossH = bossFrame and bossFrame:GetHeight() or 0
        content:SetHeight(math.abs(baseY) + prioH + SECTION_GAP + bossH + 24)
    end

    prioFrame = BuildPrioritySection(content, db, Relayout)
    prioFrame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, baseY)
    prioFrame:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)

    bossFrame = BuildBossSection(content, db, Relayout)
    bossFrame:SetPoint("TOPLEFT", prioFrame, "BOTTOMLEFT", 0, -SECTION_GAP)
    bossFrame:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)

    Relayout()
end

if Registry and Schema and RenderAdapters
    and type(Registry.RegisterFeature) == "function"
    and type(Schema.Feature) == "function"
    and type(Schema.Section) == "function" then
    Registry:RegisterFeature(Schema.Feature({
        id = "remindersPage",
        moverKey = "remindersCallout",
        lookupKeys = { "reminders", "remindersCallout" },
        category = "qol",
        nav = { tileId = "gameplay", subPageIndex = SUBPAGE_INDEX },
        sections = {
            Schema.Section({
                id = "settings",
                kind = "page",
                minHeight = 80,
                build = O.BuildRemindersContent,
            }),
        },
        render = {
            layout = function(host, options)
                return RenderAdapters.RenderLayoutRoute(host, options and options.providerKey or "remindersCallout")
            end,
        },
    }))
end
