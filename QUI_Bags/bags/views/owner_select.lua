local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local UIKit = ns.UIKit
local Helpers = ns.Helpers

local OwnerSelect = {}
Bags.OwnerSelect = OwnerSelect

function OwnerSelect.BuildOwnerList(keys, currentKey)
    local list = {}
    local seen = false
    for _, key in ipairs(keys or {}) do
        if key == currentKey then
            seen = true
            list[#list + 1] = { key = key, label = key .. " " .. ns.L["(current)"] }
        else
            list[#list + 1] = { key = key, label = key }
        end
    end
    if currentKey and not seen then
        table.insert(list, 1, { key = currentKey, label = currentKey .. " " .. ns.L["(current)"] })
    end
    return list
end

function OwnerSelect.Attach(win, opts)
    local btn = Bags.Chassis.CreatePanelButton(win._header, true)
    btn:SetPoint("LEFT", win._title, "RIGHT", 8, 0)
    UIKit.CreateBorderLines(btn)
    btn:Hide()

    btn:SetScript("OnClick", function(self)
        if not MenuUtil or not MenuUtil.CreateContextMenu then return end
        MenuUtil.CreateContextMenu(self, function(_, root)
            if opts.title then root:CreateTitle(opts.title) end
            for _, owner in ipairs(opts.listOwners()) do
                local key = owner.key
                root:CreateRadio(owner.label,
                    function() return key == opts.current() end,
                    function() opts.onSelect(key) end)
            end
        end)
    end)
    if opts.tooltip then
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(opts.tooltip)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    function btn:Update()
        if #opts.listOwners() < 2 then
            self:Hide()
            return
        end
        self._label:SetText(opts.current() or ns.L["Select"])
        self:SetSize(math.max(40, math.ceil(self._label:GetStringWidth()) + 14), 18)
        local sr, sg, sb = Helpers.GetSkinColors()
        UIKit.UpdateBorderLines(self, 1, sr, sg, sb, 0.35)
        self:Show()
    end

    return btn
end
