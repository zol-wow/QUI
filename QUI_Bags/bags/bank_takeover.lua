-- luacheck: read globals BankFrame
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local BankTakeover = {}
Bags.BankTakeover = BankTakeover

local suppressed = false
local live = false
local closing = false
local capturedScripts = nil
local capturedParent = nil
local hiddenHolder = nil

local SCRIPT_NAMES = { "OnEvent", "OnShow", "OnHide" }

local BANK_OPENER = { GetName = function() return "QUI_BankWindow" end }

function BankTakeover.IsLive()
    return live
end

local function UsesPlayerBags()
    return C_Bank.ShouldUsePlayerBagsInBank and C_Bank.ShouldUsePlayerBagsInBank()
end

function BankTakeover.Suppress()
    if UsesPlayerBags() then return end
    if suppressed then return end
    local bankFrame = BankFrame
    if not bankFrame then return end
    suppressed = true

    capturedScripts = {}
    for _, name in ipairs(SCRIPT_NAMES) do
        capturedScripts[name] = bankFrame:GetScript(name)
        bankFrame:SetScript(name, nil)
    end
    bankFrame:Hide()

    if not hiddenHolder then
        hiddenHolder = Bags.TakeoverShared.MakeHiddenHolder()
    end
    capturedParent = bankFrame:GetParent()
    bankFrame:SetParent(hiddenHolder)
end

function BankTakeover.OnBankOpened()
    if UsesPlayerBags() then return end
    live = true
    Bags.BankWindow.ShowLive()
    Bags.Takeover.OpenForFrame(BANK_OPENER)
end

function BankTakeover.OnBankClosed()
    if not live then return end
    closing = false
    live = false
    Bags.BankWindow.OnBankClosed()
    Bags.Takeover.CloseForFrame(BANK_OPENER)
end

function BankTakeover.UserClosedWindow()
    if not live or closing then return end
    closing = true
    C_Bank.CloseBankFrame()
end

function BankTakeover.Revert()
    if not suppressed then return end
    suppressed = false

    if live and not closing then
        C_Bank.CloseBankFrame()
    end

    local bankFrame = BankFrame
    if bankFrame then
        bankFrame:Hide()
        if capturedScripts then
            for _, name in ipairs(SCRIPT_NAMES) do
                bankFrame:SetScript(name, capturedScripts[name])
            end
        end
        if capturedParent then
            bankFrame:SetParent(capturedParent)
        end
    end
    capturedScripts = nil
    capturedParent = nil
    live = false
    closing = false
end
