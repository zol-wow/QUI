---------------------------------------------------------------------------
-- INTERACTION FRAMES SKINNING
--
-- Skins the everyday NPC-interaction and player-storage frames:
--   - BankFrame        (PortraitFrameTemplate)
--   - MerchantFrame    (ButtonFrameTemplate)
--   - MailFrame        (ButtonFrameTemplate, LOD via Blizzard_MailFrame)
--   - GuildBankFrame   (BasicFrameTemplate,  LOD via Blizzard_GuildBankUI)
--
-- All four lean on SkinBase.SkinButtonFrameTemplate for the standard
-- chrome strip + backdrop + close-button styling. Frame-specific sub-
-- elements (bag slot grids, tab strips, message lists) are deliberately
-- left alone in this initial pass — those land in follow-up commits if
-- they need per-element treatment.
---------------------------------------------------------------------------

local addonName, ns = ...
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

---------------------------------------------------------------------------
-- Generic refresh: re-apply current skin colors to a previously-skinned
-- frame's QUI backdrop. Used by all four refreshers below.
---------------------------------------------------------------------------
local function RefreshBackdropColors(frame)
    if not frame then return end
    local bd = SkinBase.GetBackdrop(frame)
    if not bd then return end
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()
    bd:SetBackdropColor(bgr, bgg, bgb, bga)
    bd:SetBackdropBorderColor(sr, sg, sb, sa)
end

-- Collect tabs by global-name pattern: prefix .. "Tab" .. 1..count.
-- Common pattern for legacy PanelTabButtonTemplate frames.
local function CollectNumberedTabs(prefix, count)
    local tabs = {}
    for i = 1, count do
        local tab = _G[prefix .. "Tab" .. i]
        if tab then tabs[#tabs + 1] = tab end
    end
    return tabs
end

---------------------------------------------------------------------------
-- BankFrame
---------------------------------------------------------------------------
local function SkinBank()
    if not IsSettingEnabled("skinBank") then return end
    local frame = _G.BankFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    SkinBase.SkinFrameText(frame, { recurse = true })
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

---------------------------------------------------------------------------
-- MerchantFrame
---------------------------------------------------------------------------
local function SkinMerchant()
    if not IsSettingEnabled("skinMerchant") then return end
    local frame = _G.MerchantFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    -- MerchantFrameTab1 (Items), MerchantFrameTab2 (Buyback)
    SkinBase.SkinTabGroup(CollectNumberedTabs("MerchantFrame", 2), frame)
    SkinBase.SkinFrameText(frame, { recurse = true })
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

---------------------------------------------------------------------------
-- MailFrame (LOD: Blizzard_MailFrame)
---------------------------------------------------------------------------
local function SkinMail()
    if not IsSettingEnabled("skinMail") then return end
    local frame = _G.MailFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    -- MailFrameTab1 (Inbox), MailFrameTab2 (Send Mail)
    SkinBase.SkinTabGroup(CollectNumberedTabs("MailFrame", 2), frame)
    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.MarkSkinned(frame)
end

local function RefreshMail() RefreshBackdropColors(_G.MailFrame) end
_G.QUI_RefreshMailColors = RefreshMail
if ns.Registry then
    ns.Registry:Register("skinMail", {
        refresh = RefreshMail,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

---------------------------------------------------------------------------
-- GuildBankFrame (LOD: Blizzard_GuildBankUI)
---------------------------------------------------------------------------
local function SkinGuildBank()
    if not IsSettingEnabled("skinGuildBank") then return end
    local frame = _G.GuildBankFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    SkinBase.SkinFrameText(frame, { recurse = true })
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

---------------------------------------------------------------------------
-- INITIALIZATION
-- Bank and Merchant ship in Blizzard_UIPanels_Game (always loaded);
-- OnAddOnLoaded short-circuits the already-loaded case so this works for
-- both LOD and always-loaded addons.
---------------------------------------------------------------------------
SkinBase.OnAddOnLoaded("Blizzard_UIPanels_Game", function()
    SkinBank()
    SkinMerchant()
end, 0.1)

SkinBase.OnAddOnLoaded("Blizzard_MailFrame",   SkinMail,      0.1)
SkinBase.OnAddOnLoaded("Blizzard_GuildBankUI", SkinGuildBank, 0.1)
