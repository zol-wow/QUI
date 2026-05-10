--[[
    QUI Options V2 — Related Settings Footer

    Renders a compact "Related:" row at the bottom of a tile's page frame.
    Each entry navigates to another tile/sub-page on click.
]]

local ADDON_NAME, ns = ...
local QUI = QUI
local GUI = QUI.GUI
local C = GUI.Colors

-- body     : parent frame (the tile's _pageFrame)
-- related  : array of { label, tileId, subPageIndex (optional), scrollToLabel (optional) }
-- frame    : the V2 MainFrame (for GUI:FindV2TileByID lookup)
function ns.QUI_RenderRelatedFooter(body, related, frame)
    if not body or not related or #related == 0 then return end

    local container = CreateFrame("Frame", nil, body)
    container:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 20, 10)
    container:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -20, 10)
    container:SetHeight(22)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", container, "LEFT", 0, 0)
    label:SetText("Related:")
    label:SetTextColor(0.6, 0.6, 0.65, 1)

    local x = label:GetStringWidth() + 8
    for _, entry in ipairs(related) do
        local btn = CreateFrame("Button", nil, container)
        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("LEFT", btn, "LEFT", 0, 0)
        txt:SetText("[ " .. entry.label .. " ]")
        txt:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
        btn.text = txt
        local w = txt:GetStringWidth() + 4
        btn:SetSize(w, 20)
        btn:SetPoint("LEFT", container, "LEFT", x, 0)
        btn:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1, 1) end)
        btn:SetScript("OnLeave", function(self) self.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
        btn:SetScript("OnClick", function()
            local _, idx = GUI:FindV2TileByID(frame, entry.tileId)
            if idx then
                GUI:SelectFeatureTile(frame, idx, {
                    subPageIndex = entry.subPageIndex,
                    scrollToLabel = entry.scrollToLabel,
                    pulse = entry.scrollToLabel and true or false,
                })
            end
        end)
        x = x + w + 12
    end
end
