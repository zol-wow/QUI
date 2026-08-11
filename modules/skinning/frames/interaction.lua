local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local RefreshBackdropColors = SkinBase.RefreshFrameBackdropColors

local function SkinBank()
    if not IsSettingEnabled("skinBank") then return end
    local frame = _G.BankFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame, { depth = 6 })
    SkinBase.MarkSkinned(frame)
end

local function RefreshBank() RefreshBackdropColors(_G.BankFrame) end
_G.QUI_RefreshBankColors = RefreshBank
if ns.Registry then
    ns.Registry:Register("skinBank", {
        refresh = RefreshBank,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local function SkinMerchant()
    if not IsSettingEnabled("skinMerchant") then return end
    local frame = _G.MerchantFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame, { tabs = SkinBase.CollectNumberedTabs("MerchantFrame", 2) })
    if _G.MerchantPrevPageButton then SkinBase.SkinNextPrevButton(_G.MerchantPrevPageButton, "prev") end
    if _G.MerchantNextPageButton then SkinBase.SkinNextPrevButton(_G.MerchantNextPageButton, "next") end
    SkinBase.MarkSkinned(frame)
end

local function RefreshMerchant() RefreshBackdropColors(_G.MerchantFrame) end
_G.QUI_RefreshMerchantColors = RefreshMerchant
if ns.Registry then
    ns.Registry:Register("skinMerchant", {
        refresh = RefreshMerchant,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local GOSSIP_CODE_REMAP = { ["000000"] = "ffffff", ["414141"] = "7b8489" }

local function GossipReplaceCode(code)
    return "|cFF" .. (GOSSIP_CODE_REMAP[string.lower(code)] or code)
end

local function GossipForceTextColor(fontString, r, g, b)
    if r ~= 1 or g ~= 1 or b ~= 1 then
        fontString:SetTextColor(1, 1, 1)
    end
end

local function GossipStripText(button, text)
    if not text or text == "" then return end
    local startText = text
    local iconText, iconCount = string.gsub(text, ":32:32:0:0", ":32:32:0:0:64:64:5:59:5:59")
    if iconCount > 0 then text = iconText end
    local colorText, colorCount = string.gsub(text, "|c[fF][fF](%x%x%x%x%x%x)", GossipReplaceCode)
    if colorCount > 0 then text = colorText end
    if startText ~= text then button:SetFormattedText("%s", text, true) end
end

local function GossipStripFormatted(button, textFormat, text, skip)
    if skip or not text or text == "" then return end
    local colorText, colorCount = string.gsub(textFormat, "|c[fF][fF](%x%x%x%x%x%x)", GossipReplaceCode)
    if colorCount > 0 then button:SetFormattedText(colorText, text, true) end
end

local function GossipColorRow(row)
    if not row then return end
    local greetingText = row.GreetingText
    if greetingText and not SkinBase.GetFrameData(greetingText, "qGossipColored") then
        greetingText:SetTextColor(1, 1, 1)
        hooksecurefunc(greetingText, "SetTextColor", GossipForceTextColor)
        SkinBase.SetFrameData(greetingText, "qGossipColored", true)
    end
    local fs = row.GetFontString and row:GetFontString()
    if fs and not SkinBase.GetFrameData(fs, "qGossipColored") then
        fs:SetTextColor(1, 1, 1)
        hooksecurefunc(fs, "SetTextColor", GossipForceTextColor)
        GossipStripText(row, row.GetText and row:GetText())
        hooksecurefunc(row, "SetText", GossipStripText)
        if row.SetFormattedText then
            hooksecurefunc(row, "SetFormattedText", GossipStripFormatted)
        end
        SkinBase.SetFrameData(fs, "qGossipColored", true)
    end
end

local function SkinGossip()
    if not IsSettingEnabled("skinGossip") then return end
    local frame = _G.GossipFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame)
    local greeting = frame.GreetingPanel
    if greeting then
        if greeting.ScrollBar then SkinBase.SkinTrimScrollBar(greeting.ScrollBar) end
        if greeting.ScrollBox and SkinBase.HookScrollBoxRowFonts then
            SkinBase.HookScrollBoxRowFonts(greeting.ScrollBox, 3)
            if SkinBase.HookScrollBoxAcquired then
                SkinBase.HookScrollBoxAcquired(greeting.ScrollBox, GossipColorRow, { sync = true })
            end
        end
    end
    SkinBase.MarkSkinned(frame)
end

local function RefreshGossip() RefreshBackdropColors(_G.GossipFrame) end
if ns.Registry then
    ns.Registry:Register("skinGossip", {
        refresh = RefreshGossip,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local function SkinQuest()
    if not IsSettingEnabled("skinQuest") then return end
    local frame = _G.QuestFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame, { depth = 5 })
    SkinBase.MarkSkinned(frame)
end

local function RefreshQuest() RefreshBackdropColors(_G.QuestFrame) end
if ns.Registry then
    ns.Registry:Register("skinQuest", {
        refresh = RefreshQuest,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local function SkinGuildBank()
    if not IsSettingEnabled("skinGuildBank") then return end
    local frame = _G.GuildBankFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame, { tabs = SkinBase.CollectNumberedTabs("GuildBankFrame", 4) })
    SkinBase.MarkSkinned(frame)
end

local function RefreshGuildBank() RefreshBackdropColors(_G.GuildBankFrame) end
_G.QUI_RefreshGuildBankColors = RefreshGuildBank
if ns.Registry then
    ns.Registry:Register("skinGuildBank", {
        refresh = RefreshGuildBank,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local function SkinTrainer()
    if not IsSettingEnabled("skinTrainer") then return end
    local frame = _G.ClassTrainerFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame)
    SkinBase.MarkSkinned(frame)
end

local function RefreshTrainer() RefreshBackdropColors(_G.ClassTrainerFrame) end
if ns.Registry then
    ns.Registry:Register("skinTrainer", {
        refresh = RefreshTrainer,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local function SkinMacro()
    if not IsSettingEnabled("skinMacro") then return end
    local frame = _G.MacroFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame, { tabs = SkinBase.CollectNumberedTabs("MacroFrame", 2) })
    SkinBase.MarkSkinned(frame)
end

local function RefreshMacro() RefreshBackdropColors(_G.MacroFrame) end
if ns.Registry then
    ns.Registry:Register("skinMacro", {
        refresh = RefreshMacro,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_UIPanels_Game", function()
    SkinBank()
    SkinMerchant()
    SkinGossip()
    SkinQuest()
end, 0)

SkinBase.OnAddOnLoaded("Blizzard_GuildBankUI", SkinGuildBank, 0)
SkinBase.OnAddOnLoaded("Blizzard_TrainerUI", SkinTrainer, 0)
SkinBase.OnAddOnLoaded("Blizzard_MacroUI", SkinMacro, 0)
