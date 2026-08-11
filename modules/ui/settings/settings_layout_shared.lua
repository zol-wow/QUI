local _, ns = ...

local SettingsLayout = {}
ns.QUI_ModulesSettingsLayout = SettingsLayout

local HEADER_GAP = 26
local SECTION_GAP = 14

SettingsLayout.NINE_POINT_OPTIONS = ns.QUI_SettingsLayoutShared.BuildNinePointAnchorOptions()

function SettingsLayout.MakeLayout(content, startY)
    return ns.QUI_SettingsLayoutShared.MakeLayout(content, nil, startY)
end

function SettingsLayout.Row(parent, label, widget, desc)
    return ns.QUI_Options.BuildSettingRow(parent, label, widget, desc)
end

function SettingsLayout.PairCells(card, cells)
    local i = 1
    while i <= #cells do
        local left = cells[i]
        local right = cells[i + 1]
        if right then
            card.AddRow(left, right)
            i = i + 2
        else
            card.AddRow(left)
            i = i + 1
        end
    end
end
