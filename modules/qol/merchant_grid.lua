local addonName, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("merchantGrid")

local BASE_W, BASE_H         = 336, 444
local ORIGIN_X, ORIGIN_Y     = 11, -69
local COL_STRIDE, ROW_STRIDE = 165, 52
local VANILLA_PER_PAGE       = 10
local XML_BUTTONS            = 12
local MIN_COLS, MAX_COLS     = 2, 4
local MIN_ROWS, MAX_ROWS     = 5, 8
local MAX_BUTTONS            = MAX_COLS * MAX_ROWS
local NEXT_PAGE_INSET        = 26
local BUYBACK_ANCHOR_X       = 30
local BUYBACK_ANCHOR_Y       = -53

local VANILLA_RELANCHORS = {
    { 2,  "MerchantItem1",  "TOPRIGHT",   12,   0 },
    { 4,  "MerchantItem3",  "TOPRIGHT",   12,   0 },
    { 6,  "MerchantItem5",  "TOPRIGHT",   12,   0 },
    { 8,  "MerchantItem7",  "TOPRIGHT",   12,   0 },
    { 10, "MerchantItem9",  "TOPRIGHT",   12,   0 },
    { 11, "MerchantItem9",  "BOTTOMLEFT",  0, -15 },
    { 12, "MerchantItem11", "TOPRIGHT",   12,   0 },
}

local MerchantGrid = {}
if _G.QUI then _G.QUI.MerchantGrid = MerchantGrid end

local buttonsBuilt        = false
local hookInstalled       = false
local pendingPanelUpdate  = false

local function ClampedConfig()
    local s = GetSettings()
    local enabled = (s and s.enabled == true) or false
    local cols = (s and s.columns) or MIN_COLS
    local rows = (s and s.rows) or MIN_ROWS
    if cols < MIN_COLS then cols = MIN_COLS elseif cols > MAX_COLS then cols = MAX_COLS end
    if rows < MIN_ROWS then rows = MIN_ROWS elseif rows > MAX_ROWS then rows = MAX_ROWS end
    return enabled, cols, rows
end

local function EnsureButtons()
    if buttonsBuilt then return end
    local frame = _G.MerchantFrame
    if not frame then return end
    for i = XML_BUTTONS + 1, MAX_BUTTONS do
        if not _G["MerchantItem" .. i] then
            CreateFrame("Frame", "MerchantItem" .. i, frame, "MerchantItemTemplate")
        end
    end
    buttonsBuilt = true
end

local function SafePanelUpdate()
    local frame = _G.MerchantFrame
    if not frame then return end
    if InCombatLockdown() then
        pendingPanelUpdate = true
        return
    end
    if _G.UpdateUIPanelPositions then
        _G.UpdateUIPanelPositions(frame)
    end
end

-- <<< QUI_TEST_EXTRACT buyback_anchor
local function BuybackRefIndex(cols, rows)
    return (rows - 1) * cols + 2
end

local function ApplyGrid(cols, rows)
    local frame = _G.MerchantFrame
    local n = cols * rows
    for i = 1, MAX_BUTTONS do
        local b = _G["MerchantItem" .. i]
        if b then
            if i <= n then
                local col = (i - 1) % cols
                local rowIdx = math.floor((i - 1) / cols)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", frame, "TOPLEFT",
                    ORIGIN_X + col * COL_STRIDE, ORIGIN_Y - rowIdx * ROW_STRIDE)
                b:Show()
            else
                b:Hide()
            end
        end
    end

    local w = BASE_W + (cols - MIN_COLS) * COL_STRIDE
    local h = BASE_H + (rows - MIN_ROWS) * ROW_STRIDE
    frame:SetSize(w, h)

    local nextBtn = _G.MerchantNextPageButton
    if nextBtn then
        nextBtn:ClearAllPoints()
        nextBtn:SetPoint("CENTER", frame, "BOTTOMLEFT", w - NEXT_PAGE_INSET, 96)
    end

    local buyback = _G.MerchantBuyBackItem
    local ref = _G["MerchantItem" .. BuybackRefIndex(cols, rows)]
    if buyback and ref then
        buyback:ClearAllPoints()
        buyback:SetPoint("TOPLEFT", ref, "BOTTOMLEFT", BUYBACK_ANCHOR_X, BUYBACK_ANCHOR_Y)
    end

    SafePanelUpdate()
end

local function RestoreVanilla()
    local frame = _G.MerchantFrame
    if not frame then return end
    for _, a in ipairs(VANILLA_RELANCHORS) do
        local b = _G["MerchantItem" .. a[1]]
        local rel = _G[a[2]]
        if b and rel then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", rel, a[3], a[4], a[5])
        end
    end
    for i = XML_BUTTONS + 1, MAX_BUTTONS do
        local b = _G["MerchantItem" .. i]
        if b then b:Hide() end
    end
    frame:SetSize(BASE_W, BASE_H)
    local nextBtn = _G.MerchantNextPageButton
    if nextBtn then
        nextBtn:ClearAllPoints()
        nextBtn:SetPoint("CENTER", frame, "BOTTOMLEFT", BASE_W - NEXT_PAGE_INSET, 96)
    end
    local buyback = _G.MerchantBuyBackItem
    local item10 = _G.MerchantItem10
    if buyback and item10 then
        buyback:ClearAllPoints()
        buyback:SetPoint("TOPLEFT", item10, "BOTTOMLEFT", BUYBACK_ANCHOR_X, BUYBACK_ANCHOR_Y)
    end
    SafePanelUpdate()
end
-- <<< QUI_TEST_EXTRACT buyback_anchor

local function OnMerchantUpdate()
    local frame = _G.MerchantFrame
    if not frame then return end
    local enabled, cols, rows = ClampedConfig()
    if enabled and frame.selectedTab == 1 then
        ApplyGrid(cols, rows)
    else
        RestoreVanilla()
    end
end

local function InstallHook()
    if hookInstalled then return end
    if type(_G.MerchantFrame_Update) ~= "function" then return end
    hooksecurefunc("MerchantFrame_Update", OnMerchantUpdate)
    hookInstalled = true
end

local function ApplyPageSize()
    local enabled, cols, rows = ClampedConfig()
    if enabled then
        EnsureButtons()
        _G.MERCHANT_ITEMS_PER_PAGE = cols * rows
    else
        _G.MERCHANT_ITEMS_PER_PAGE = VANILLA_PER_PAGE
    end
end

function MerchantGrid.Refresh()
    ApplyPageSize()
    if ClampedConfig() then InstallHook() end
    if _G.MerchantFrame and _G.MerchantFrame:IsShown()
        and type(_G.MerchantFrame_Update) == "function" then
        _G.MerchantFrame_Update()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        if ClampedConfig() then
            ApplyPageSize()
            InstallHook()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingPanelUpdate then
            pendingPanelUpdate = false
            SafePanelUpdate()
        end
    end
end)

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        if ClampedConfig() then
            ApplyPageSize()
            InstallHook()
        end
    end)
end

if ns.Registry then
    ns.Registry:Register("merchantGrid", {
        refresh = MerchantGrid.Refresh,
        priority = 30,
        group = "qol",
    })
end
