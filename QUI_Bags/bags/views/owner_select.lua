---------------------------------------------------------------------------
-- Bags views: owner selector. Small header button (right of the window
-- title — the header's right side is already occupied by close/search/
-- sort) showing which owner's cache the window is rendering. Clicking it
-- opens a MenuUtil context menu (house idiom: damage_meter's config menu,
-- minimap datatext menus) with one radio per cached owner; the radio's
-- checked state tracks the VIEWED owner, the "(current)" label mark
-- identifies the logged-in one. Hidden while only one owner exists
-- (nothing to switch to).
-- Pure seam: BuildOwnerList (headless-tested) assembles the {key,label}
-- entries from store keys.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local UIKit = ns.UIKit
local Helpers = ns.Helpers

local OwnerSelect = {}
Bags.OwnerSelect = OwnerSelect

--- Pure: assemble the selector's owner entries from sorted store keys.
--- keys: array (Store.ListCharacters/ListGuilds output, already sorted);
--- currentKey: the logged-in owner's key (marked "(current)"), or nil when
--- there is no markable owner (unguilded, or the current guild was never
--- cached — selecting an uncached owner would render nothing, so callers
--- pass nil instead of such a key).
--- currentKey is PREPENDED when missing from keys: the selector is the only
--- way back to live mode, so the logged-in owner must stay selectable even
--- before its record lands in the store.
--- Returns an array of { key, label }.
function OwnerSelect.BuildOwnerList(keys, currentKey)
    local list = {}
    local seen = false
    for _, key in ipairs(keys or {}) do
        if key == currentKey then
            seen = true
            list[#list + 1] = { key = key, label = key .. " (current)" }
        else
            list[#list + 1] = { key = key, label = key }
        end
    end
    if currentKey and not seen then
        table.insert(list, 1, { key = currentKey, label = currentKey .. " (current)" })
    end
    return list
end

--- Attach a selector button to a chassis window's header.
--- opts: { listOwners() → array of {key,label}, current() → viewed key,
---         onSelect(key), title (menu title), tooltip (hover tooltip) }
--- Returns the button; the owner window calls :Update() from its Refresh
--- (same recolor-per-refresh contract as the Sort button / tab strip).
function OwnerSelect.Attach(win, opts)
    -- bank tab-button construction: dark bg + centered label + QUI border
    -- lines (recolored per Update); font set at creation like the footers
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

    --- Re-sync from the owner window's Refresh: label = the viewed owner's
    --- key (the "(current)" mark stays menu-only so the header stays
    --- compact); hidden when there's nothing to switch to; border tracks
    --- the skin like the tab strips.
    function btn:Update()
        if #opts.listOwners() < 2 then
            self:Hide()
            return
        end
        self._label:SetText(opts.current() or "Select")
        self:SetSize(math.max(40, math.ceil(self._label:GetStringWidth()) + 14), 18)
        local sr, sg, sb = Helpers.GetSkinColors()
        UIKit.UpdateBorderLines(self, 1, sr, sg, sb, 0.35)
        self:Show()
    end

    return btn
end
