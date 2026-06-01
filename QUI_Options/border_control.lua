--[[
    QUI Options - Border Control
    Reusable composite widget: border source dropdown + custom color picker.
    Attach to any settings panel to get the standard border-color pair.
]]

local ADDON_NAME, ns = ...

local BorderControl = {}
ns.QUI_BorderControl = BorderControl

--- Build the source-options list for the dropdown.
--- @param includeInherit boolean|nil  Pass false to omit the Inherit entry.
--- @return table  Array of { value, text } entries.
local function SourceOptions(includeInherit)
    local opts = {}
    if includeInherit ~= false then
        opts[#opts + 1] = { value = "inherit", text = "Inherit (global)" }
    end
    opts[#opts + 1] = { value = "theme",  text = "Theme accent" }
    opts[#opts + 1] = { value = "class",  text = "Class color" }
    opts[#opts + 1] = { value = "custom", text = "Custom" }
    return opts
end

--- Attach a border source dropdown + custom color picker to a settings panel.
---
--- @param GUI       table   The QUI GUI framework object (has CreateFormDropdown, CreateFormColorPicker).
--- @param parent    frame   Parent frame (e.g. a section's .frame).
--- @param dbTable   table   The saved-variable sub-table that holds the keys.
--- @param prefix    string  Key prefix for GetBorderKeys (e.g. "" or "mm").
--- @param onChange  function|nil  Called after any change (for refresh callbacks).
--- @param opts      table|nil     Optional overrides:
---   .label             string   Label for the source dropdown  (default "Border Color Source")
---   .colorLabel        string   Label for the color picker     (default "Border Color")
---   .sourceDescription string   registryInfo.description for the dropdown
---   .colorDescription  string   registryInfo.description for the picker
---   .noAlpha           boolean  Pass noAlpha=true to the color-picker options
---   .includeInherit    boolean  false = omit the Inherit entry (default true)
---
--- @return table dropdownWidget
--- @return table pickerWidget
function BorderControl.Attach(GUI, parent, dbTable, prefix, onChange, opts)
    opts = opts or {}

    local keys = ns.Helpers.GetBorderKeys(prefix or "")

    -- Default source when none is stored: "theme" when Inherit is excluded,
    -- "inherit" otherwise — mirrors the pattern used in provider_panels.lua.
    local defaultSource = (opts.includeInherit == false) and "theme" or "inherit"

    local picker  -- forward-declared so the dropdown closure can reference it

    local function syncEnabled()
        local cur = dbTable[keys.source] or defaultSource
        if picker and picker.SetEnabled then
            picker:SetEnabled(cur == "custom")
        end
    end

    -- Source dropdown
    local dropdownRegistryInfo = opts.sourceDescription
        and { description = opts.sourceDescription }
        or  { description = "Where this border gets its color: Theme (your theme accent), Class (the unit's class color), or Custom (the color picker)." }

    -- Bare mode (label = nil): the caller wraps these widgets in BuildSettingRow,
    -- which supplies the label. Passing a label here puts the dropdown in
    -- labeled mode (control offset 180px right), which collapses to zero width
    -- inside a row's widget slot — making the control invisible.
    local dropdown = GUI:CreateFormDropdown(
        parent,
        nil,
        SourceOptions(opts.includeInherit),
        keys.source,
        dbTable,
        function(value)
            dbTable[keys.source] = value
            syncEnabled()
            if onChange then onChange() end
        end,
        dropdownRegistryInfo,
        nil
    )

    -- Custom color picker
    local pickerRegistryInfo = opts.colorDescription
        and { description = opts.colorDescription }
        or  { description = "Custom border color, used when Border Color Source is set to Custom." }

    local pickerOptions = opts.noAlpha and { noAlpha = true } or nil

    picker = GUI:CreateFormColorPicker(
        parent,
        nil,  -- bare mode: caller's BuildSettingRow supplies the label
        keys.color,
        dbTable,
        onChange,
        pickerOptions,
        pickerRegistryInfo
    )

    -- Set initial enabled state
    syncEnabled()

    return dropdown, picker
end
