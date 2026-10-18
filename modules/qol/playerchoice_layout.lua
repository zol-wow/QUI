-- PlayerChoice's bottom-only widget layout skips clearing its horizontal row
-- pool. Recycled options can retain rows whose widgets have moved elsewhere;
-- those stale row anchors inflate the filler and grow the Codex on each open.
local function ReleaseStaleRows(container, widgets)
    local pool = container.horizontalRowContainerPool
    if not pool then return end

    local currentParents = {}
    for _, widget in ipairs(widgets) do
        currentParents[widget:GetParent()] = true
    end

    local staleRows = {}
    for row in pool:EnumerateActive() do
        if not currentParents[row] then
            staleRows[#staleRows + 1] = row
        end
    end
    if #staleRows == 0 then return end

    for _, row in ipairs(staleRows) do
        -- ResetChildWidgets would otherwise reparent widgets that are already
        -- owned by a different row (or back in the widget pool).
        row.childWidgets = {}
        pool:Release(row)
    end
    container:Layout()
end

local installed = false
local function Install()
    if installed or not _G.PlayerChoice_WidgetsLayout then return end
    installed = true
    hooksecurefunc("PlayerChoice_WidgetsLayout", ReleaseStaleRows)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, addon)
    if addon ~= "Blizzard_PlayerChoice" then return end
    Install()
    self:UnregisterEvent("ADDON_LOADED")
end)
Install()
