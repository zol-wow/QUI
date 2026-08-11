-- luacheck: read globals GuildBankFrame CloseGuildBankFrame
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local GuildTakeover = {}
Bags.GuildTakeover = GuildTakeover

local LOD_ADDON = "Blizzard_GuildBankUI"

local suppressed = false
local pending = false
local live = false
local closing = false
local capturedScripts = nil
local capturedParent = nil
local hiddenHolder = nil

local SCRIPT_NAMES = { "OnEvent", "OnShow", "OnHide" }

local GUILD_OPENER = { GetName = function() return "QUI_GuildBankWindow" end }

function GuildTakeover.IsLive()
    return live
end

function GuildTakeover.Init()
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(LOD_ADDON))
        or (IsAddOnLoaded and IsAddOnLoaded(LOD_ADDON))
    if loaded then
        GuildTakeover.SuppressNow()
    end
    if not suppressed then
        pending = true
    end
end

function GuildTakeover.OnAddonLoaded(name)
    if name ~= LOD_ADDON or not pending then return end
    pending = false
    GuildTakeover.SuppressNow()
end

function GuildTakeover.SuppressNow()
    if suppressed then return end
    local guildBankFrame = GuildBankFrame
    if not guildBankFrame then return end
    suppressed = true

    capturedScripts = {}
    for _, name in ipairs(SCRIPT_NAMES) do
        capturedScripts[name] = guildBankFrame:GetScript(name)
        guildBankFrame:SetScript(name, nil)
    end
    guildBankFrame:Hide()

    if not hiddenHolder then
        hiddenHolder = Bags.TakeoverShared.MakeHiddenHolder()
    end
    capturedParent = guildBankFrame:GetParent()
    guildBankFrame:SetParent(hiddenHolder)
end

function GuildTakeover.OnOpened()
    if live then return end
    live = true
    Bags.GuildWindow.ShowLive()
    Bags.Takeover.OpenForFrame(GUILD_OPENER)
end

function GuildTakeover.OnClosed()
    if not live then return end
    closing = false
    live = false
    Bags.GuildWindow.OnBankClosed()
    Bags.Takeover.CloseForFrame(GUILD_OPENER)
end

function GuildTakeover.UserClosedWindow()
    if not live or closing then return end
    closing = true
    CloseGuildBankFrame()
end

function GuildTakeover.Revert()
    pending = false
    if not suppressed then return end
    suppressed = false

    if live and not closing then
        CloseGuildBankFrame()
    end

    local guildBankFrame = GuildBankFrame
    if guildBankFrame then
        guildBankFrame:Hide()
        if capturedScripts then
            for _, name in ipairs(SCRIPT_NAMES) do
                guildBankFrame:SetScript(name, capturedScripts[name])
            end
        end
        if capturedParent then
            guildBankFrame:SetParent(capturedParent)
        end
    end
    capturedScripts = nil
    capturedParent = nil
    live = false
    closing = false
end
