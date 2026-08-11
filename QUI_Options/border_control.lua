local ADDON_NAME, ns = ...

local BorderControl = {}
ns.QUI_BorderControl = BorderControl

local function SourceOptions(includeInherit)
    local opts = {}
    if includeInherit ~= false then
        opts[#opts + 1] = { value = "inherit", text = ns.L["Inherit (global)"] }
    end
    opts[#opts + 1] = { value = "theme",  text = ns.L["Theme accent"] }
    opts[#opts + 1] = { value = "class",  text = ns.L["Class color"] }
    opts[#opts + 1] = { value = "custom", text = ns.L["Custom"] }
    return opts
end

function BorderControl.Attach(GUI, parent, dbTable, prefix, onChange, opts)
    opts = opts or {}

    local keys = ns.Helpers.GetBorderKeys(prefix or "")

    local defaultSource = (opts.includeInherit == false) and "theme" or "inherit"

    local picker

    local function syncEnabled()
        local cur = dbTable[keys.source] or defaultSource
        if picker and picker.SetEnabled then
            picker:SetEnabled(cur == "custom")
        end
    end

    local dropdownRegistryInfo = opts.sourceDescription
        and { description = opts.sourceDescription }
        or  { description = "Where this border gets its color: Theme (your theme accent), Class (the unit's class color), or Custom (the color picker)." }

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

    local pickerRegistryInfo = opts.colorDescription
        and { description = opts.colorDescription }
        or  { description = "Custom border color, used when Border Color Source is set to Custom." }

    local pickerOptions = opts.noAlpha and { noAlpha = true } or nil

    picker = GUI:CreateFormColorPicker(
        parent,
        nil,
        keys.color,
        dbTable,
        onChange,
        pickerOptions,
        pickerRegistryInfo
    )

    syncEnabled()

    return dropdown, picker
end
