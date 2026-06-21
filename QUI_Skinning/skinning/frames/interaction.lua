---------------------------------------------------------------------------
-- INTERACTION FRAMES SKINNING
--
-- Skins the everyday NPC-interaction and player-storage frames:
--   - BankFrame        (PortraitFrameTemplate)
--   - MerchantFrame    (ButtonFrameTemplate)
--   - GuildBankFrame   (BasicFrameTemplate,  LOD via Blizzard_GuildBankUI)
--
-- All three lean on SkinBase.SkinButtonFrameTemplate for the standard
-- chrome strip + backdrop + close-button styling. Frame-specific sub-
-- elements (bag slot grids, tab strips, message lists) get explicit coverage
-- where Blizzard owns them outside the root frame's descendant tree.
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
-- frame's QUI backdrop. Used by all three refreshers below.
---------------------------------------------------------------------------
local RefreshBackdropColors = SkinBase.RefreshFrameBackdropColors

---------------------------------------------------------------------------
-- BankFrame
---------------------------------------------------------------------------
local function SkinBank()
    if not IsSettingEnabled("skinBank") then return end
    local frame = _G.BankFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    SkinBase.SkinFrameText(frame, { recurse = true })
    -- Depth 6 to match SkinFrameText's reach: the tab-settings icon-selector
    -- popup's SelectedIconDescription sits at child-depth 5 and is re-fonted via
    -- SelectedIconDescription:SetFontObject(GameFontHighlightSmall) on icon-select;
    -- a shallower lock stops one level short and misses it.
    SkinBase.LockFrameTextObjects(frame, 6)
    -- Withdraw/Deposit/PurchaseTab are UIPanelButtons: engine swaps Highlight/
    -- Disabled font OBJECT on hover/disable with no setter call (LockFrameTextObjects
    -- above can't catch it). Drive the button font objects.
    SkinBase.ApplyButtonFontObjectsDeep(frame, 4)
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
    SkinBase.SkinTabGroup(SkinBase.CollectNumberedTabs("MerchantFrame", 2), frame)
    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.LockFrameTextObjects(frame, 4)
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
-- GuildBankFrame (LOD: Blizzard_GuildBankUI)
---------------------------------------------------------------------------
local function SkinGuildBank()
    if not IsSettingEnabled("skinGuildBank") then return end
    local frame = _G.GuildBankFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinButtonFrameTemplate(frame)
    -- Bottom PanelTabs (Items/Log/Money Log/Tab Info) re-show slice art + swap font
    -- via PanelTemplates_Select/DeselectTab on selection; SkinTabGroup installs the
    -- qTabArtClamped guard so the global PanelTemplates hooks re-clamp them.
    SkinBase.SkinTabGroup(SkinBase.CollectNumberedTabs("GuildBankFrame", 4), frame)
    SkinBase.SkinFrameText(frame, { recurse = true })
    SkinBase.LockFrameTextObjects(frame, 4)
    SkinBase.ApplyButtonFontObjectsDeep(frame, 4)
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
end, 0)

SkinBase.OnAddOnLoaded("Blizzard_GuildBankUI", SkinGuildBank, 0)
