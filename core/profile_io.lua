---------------------------------------------------------------------------
-- QUI Profile Import/Export
-- Handles serialization of profiles, tracker bars, and spell scanner data.
-- Extracted from core/main.lua for maintainability.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local QUICore = ns.Addon

local AceSerializer = LibStub("AceSerializer-3.0", true)
local LibDeflate    = LibStub("LibDeflate", true)

local MAX_IMPORT_DEPTH = 20
local MAX_IMPORT_NODES = 50000
local MAX_SCHEMA_ERRORS = 8
local MAX_DISPLAY_SCHEMA_ERRORS = 3

local function GetDisplayPath(path, rootLabel)
    if type(path) ~= "string" or path == "" then
        return "root"
    end
    local prefix = (rootLabel or "profile") .. "."
    if path:sub(1, #prefix) == prefix then
        path = path:sub(#prefix + 1)
    elseif path == (rootLabel or "profile") then
        return "root"
    end
    return path ~= "" and path or "root"
end

local function FormatTreeValidationError(issue, rootLabel)
    if type(issue) ~= "table" then
        return "Import failed validation. The string appears to be malformed."
    end

    if issue.kind == "unsupported_value_type" then
        local where = GetDisplayPath(issue.path, rootLabel)
        return ("Import rejected: unsupported value type '%s' at '%s'."):format(tostring(issue.valueType), where)
    end
    if issue.kind == "unsupported_key_type" then
        local where = GetDisplayPath(issue.path, rootLabel)
        return ("Import rejected: unsupported key type '%s' at '%s'."):format(tostring(issue.keyType), where)
    end
    if issue.kind == "depth_limit" then
        local where = GetDisplayPath(issue.path, rootLabel)
        return ("Import rejected: data is nested too deeply at '%s' (limit: %d)."):format(where, issue.limit or MAX_IMPORT_DEPTH)
    end
    if issue.kind == "node_limit" then
        return ("Import rejected: data payload is too large (limit: %d nodes)."):format(issue.limit or MAX_IMPORT_NODES)
    end

    return "Import failed validation. The string appears to be malformed."
end

local function FormatTypeMismatchErrors(errors, rootLabel)
    if type(errors) ~= "table" or #errors == 0 then
        return nil
    end

    local samples = {}
    local shown = math.min(#errors, MAX_DISPLAY_SCHEMA_ERRORS)
    for i = 1, shown do
        local err = errors[i]
        local where = GetDisplayPath(err.path, rootLabel)
        samples[#samples + 1] = ("%s (expected %s, got %s)"):format(where, err.expected, err.actual)
    end

    local summary = table.concat(samples, "; ")
    local remaining = #errors - shown
    if remaining > 0 then
        summary = summary .. ("; and %d more"):format(remaining)
    end

    return "Import rejected: incompatible setting types - " .. summary .. "."
end

-- Defensive import validation:
-- 1) Reject unsupported Lua value types in payload trees.
-- 2) Soft-check imported profile keys against AceDB defaults when available.
local function ValidateImportTree(value, label, state, depth)
    state = state or { visited = {}, nodes = 0 }
    depth = depth or 0

    local valueType = type(value)
    if valueType ~= "table" then
        if valueType == "function" or valueType == "thread" or valueType == "userdata" then
            return false, { kind = "unsupported_value_type", valueType = valueType, path = label or "root" }
        end
        return true
    end

    if state.visited[value] then
        return true
    end
    state.visited[value] = true

    if depth >= MAX_IMPORT_DEPTH then
        return false, { kind = "depth_limit", limit = MAX_IMPORT_DEPTH, path = label or "root" }
    end

    state.nodes = state.nodes + 1
    if state.nodes > MAX_IMPORT_NODES then
        return false, { kind = "node_limit", limit = MAX_IMPORT_NODES }
    end

    for k, v in pairs(value) do
        local keyType = type(k)
        if keyType ~= "string" and keyType ~= "number" and keyType ~= "boolean" then
            return false, { kind = "unsupported_key_type", keyType = keyType, path = label or "root" }
        end
        local childLabel = ("%s.%s"):format(label or "root", tostring(k))
        local ok, issue = ValidateImportTree(v, childLabel, state, depth + 1)
        if not ok then
            return false, issue
        end
    end

    return true
end

local function ValidateTableTypeShape(candidate, schema, path, errors, depth)
    if #errors >= MAX_SCHEMA_ERRORS then return end
    depth = depth or 0
    if depth > MAX_IMPORT_DEPTH then return end
    if type(candidate) ~= "table" or type(schema) ~= "table" then return end

    for key, schemaValue in pairs(schema) do
        if #errors >= MAX_SCHEMA_ERRORS then break end

        local candidateValue = candidate[key]
        if candidateValue ~= nil then
            local schemaType = type(schemaValue)
            local candidateType = type(candidateValue)
            local keyPath = ("%s.%s"):format(path or "profile", tostring(key))

            if schemaType ~= candidateType then
                table.insert(errors, { path = keyPath, expected = schemaType, actual = candidateType })
            elseif schemaType == "table" then
                ValidateTableTypeShape(candidateValue, schemaValue, keyPath, errors, depth + 1)
            end
        end
    end
end

local function ValidateProfilePayload(core, profileData)
    local ok, issue = ValidateImportTree(profileData, "profile")
    if not ok then
        return false, FormatTreeValidationError(issue, "profile")
    end

    local defaults = core and core.db and core.db.defaults and core.db.defaults.profile
    if type(defaults) ~= "table" then
        return true
    end

    local typeErrors = {}
    ValidateTableTypeShape(profileData, defaults, "profile", typeErrors, 0)
    if #typeErrors > 0 then
        return false, FormatTypeMismatchErrors(typeErrors, "profile")
    end

    return true
end

local function ValidateTrackerBarPayload(data, multi)
    local ok, issue = ValidateImportTree(data, "trackers")
    if not ok then
        return false, FormatTreeValidationError(issue, "trackers")
    end

    if multi then
        if type(data.bars) ~= "table" then
            return false, "Import rejected: tracker bars payload is missing a valid bars table."
        end
        for i, bar in ipairs(data.bars) do
            if type(bar) ~= "table" then
                return false, ("Import rejected: tracker bar #%d is invalid."):format(i)
            end
        end
    else
        if type(data.bar) ~= "table" then
            return false, "Import rejected: tracker bar payload is missing a valid bar table."
        end
    end

    if data.specEntries ~= nil and type(data.specEntries) ~= "table" then
        return false, "Import rejected: tracker spec entries must be a table."
    end

    return true
end

local function ValidateSpellScannerPayload(data)
    local ok, issue = ValidateImportTree(data, "spellScanner")
    if not ok then
        return false, FormatTreeValidationError(issue, "spellScanner")
    end

    if type(data) ~= "table" then
        return false, "Import rejected: spell scanner payload is not a table."
    end
    if data.spells ~= nil and type(data.spells) ~= "table" then
        return false, "Import rejected: spell scanner spells must be a table."
    end
    if data.items ~= nil and type(data.items) ~= "table" then
        return false, "Import rejected: spell scanner items must be a table."
    end
    return true
end

---=================================================================================
--- PROFILE IMPORT/EXPORT
---=================================================================================

function QUICore:ExportProfileToString()
    if not self.db or not self.db.profile then
        return "No profile loaded."
    end
    if not AceSerializer or not LibDeflate then
        return "Export requires AceSerializer-3.0 and LibDeflate."
    end

    local serialized = AceSerializer:Serialize(self.db.profile)
    if not serialized or type(serialized) ~= "string" then
        return "Failed to serialize profile."
    end

    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        return "Failed to compress profile."
    end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return "Failed to encode profile."
    end

    return "QUI1:" .. encoded
end

function QUICore:ImportProfileFromString(str)
    if not self.db or not self.db.profile then
        return false, "No profile loaded."
    end
    if not AceSerializer or not LibDeflate then
        return false, "Import requires AceSerializer-3.0 and LibDeflate."
    end
    if not str or str == "" then
        return false, "No data provided."
    end

    str = str:gsub("%s+", "")
    str = str:gsub("^QUI1:", "")  -- Strip QUI1 prefix
    str = str:gsub("^CDM1:", "")  -- Backwards compatibility

    local compressed = LibDeflate:DecodeForPrint(str)
    if not compressed then
        return false, "Could not decode string (maybe corrupted)."
    end

    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return false, "Could not decompress data."
    end

    local ok, t = AceSerializer:Deserialize(serialized)
    if not ok or type(t) ~= "table" then
        return false, "Could not deserialize profile."
    end

    local payloadValid, payloadErr = ValidateProfilePayload(self, t)
    if not payloadValid then
        return false, payloadErr or "Import failed profile validation."
    end

    local profile = self.db.profile

    for k in pairs(profile) do
        profile[k] = nil
    end
    for k, v in pairs(t) do
        profile[k] = v
    end

    if self.RefreshAll then
        self:RefreshAll()
    end

    return true
end

---=================================================================================
--- CUSTOM TRACKER BAR IMPORT/EXPORT
---=================================================================================

-- Generate a collision-safe unique tracker ID
local function GenerateUniqueTrackerID()
    local used = {}
    local bars = QUICore.db.profile.customTrackers and QUICore.db.profile.customTrackers.bars or {}
    for _, b in ipairs(bars) do
        if b.id then used[b.id] = true end
    end
    if QUICore.db.global and QUICore.db.global.specTrackerSpells then
        for id in pairs(QUICore.db.global.specTrackerSpells) do
            used[id] = true
        end
    end
    local id
    repeat
        id = "tracker" .. time() .. math.random(1000, 9999)
    until not used[id]
    return id
end

-- Export a single tracker bar (with its spec-specific entries if enabled)
function QUICore:ExportSingleTrackerBar(barIndex)
    if not self.db or not self.db.profile or not self.db.profile.customTrackers
        or not self.db.profile.customTrackers.bars then
        return nil, "No tracker data loaded."
    end
    if not AceSerializer or not LibDeflate then
        return nil, "Export requires AceSerializer-3.0 and LibDeflate."
    end

    local bar = self.db.profile.customTrackers.bars[barIndex]
    if not bar then
        return nil, "Bar not found."
    end

    -- Build export data including spec-specific entries if enabled
    local exportData = {
        bar = bar,
        specEntries = nil,
    }

    -- Include spec-specific entries if the bar uses them
    if bar.specSpecificSpells and bar.id and self.db.global and self.db.global.specTrackerSpells then
        exportData.specEntries = self.db.global.specTrackerSpells[bar.id]
    end

    local serialized = AceSerializer:Serialize(exportData)
    if not serialized or type(serialized) ~= "string" then
        return nil, "Failed to serialize bar."
    end

    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        return nil, "Failed to compress bar data."
    end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return nil, "Failed to encode bar data."
    end

    return "QCB1:" .. encoded
end

-- Export all tracker bars
function QUICore:ExportAllTrackerBars()
    if not self.db or not self.db.profile or not self.db.profile.customTrackers then
        return nil, "No tracker data loaded."
    end
    if not AceSerializer or not LibDeflate then
        return nil, "Export requires AceSerializer-3.0 and LibDeflate."
    end

    local bars = self.db.profile.customTrackers.bars
    if not bars or #bars == 0 then
        return nil, "No tracker bars to export."
    end

    local exportData = {
        bars = bars,
        specEntries = self.db.global and self.db.global.specTrackerSpells or nil,
    }

    local serialized = AceSerializer:Serialize(exportData)
    if not serialized or type(serialized) ~= "string" then
        return nil, "Failed to serialize bars."
    end

    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        return nil, "Failed to compress bar data."
    end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return nil, "Failed to encode bar data."
    end

    return "QCT1:" .. encoded
end

-- Import a single tracker bar (appends to existing bars)
function QUICore:ImportSingleTrackerBar(str)
    if not self.db or not self.db.profile then
        return false, "No profile loaded."
    end
    if not AceSerializer or not LibDeflate then
        return false, "Import requires AceSerializer-3.0 and LibDeflate."
    end
    if not str or str == "" then
        return false, "No data provided."
    end

    str = str:gsub("%s+", "")

    -- Check for correct prefix
    if not str:match("^QCB1:") then
        return false, "This doesn't appear to be a tracker bar export."
    end
    str = str:gsub("^QCB1:", "")

    local compressed = LibDeflate:DecodeForPrint(str)
    if not compressed then
        return false, "Could not decode string (maybe corrupted)."
    end

    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return false, "Could not decompress data."
    end

    local ok, data = AceSerializer:Deserialize(serialized)
    if not ok or type(data) ~= "table" or not data.bar then
        return false, "Could not deserialize bar data."
    end

    local payloadValid, payloadErr = ValidateTrackerBarPayload(data, false)
    if not payloadValid then
        return false, payloadErr or "Import failed bar validation."
    end

    -- Ensure customTrackers structure exists
    if not self.db.profile.customTrackers then
        self.db.profile.customTrackers = { bars = {} }
    end
    if not self.db.profile.customTrackers.bars then
        self.db.profile.customTrackers.bars = {}
    end

    -- Generate collision-safe unique ID for the imported bar
    local oldID = data.bar.id
    local newID = GenerateUniqueTrackerID()
    data.bar.id = newID

    -- Append bar to existing bars
    table.insert(self.db.profile.customTrackers.bars, data.bar)

    -- Copy spec-specific entries if present (with new ID)
    if data.specEntries then
        if not self.db.global then self.db.global = {} end
        if not self.db.global.specTrackerSpells then self.db.global.specTrackerSpells = {} end
        self.db.global.specTrackerSpells[newID] = data.specEntries
    end

    return true, "Bar imported successfully."
end

-- Import all tracker bars (replaceExisting: true = replace all, false = merge/append)
function QUICore:ImportAllTrackerBars(str, replaceExisting)
    if not self.db or not self.db.profile then
        return false, "No profile loaded."
    end
    if not AceSerializer or not LibDeflate then
        return false, "Import requires AceSerializer-3.0 and LibDeflate."
    end
    if not str or str == "" then
        return false, "No data provided."
    end

    str = str:gsub("%s+", "")

    -- Check for correct prefix
    if not str:match("^QCT1:") then
        return false, "This doesn't appear to be a tracker bars export."
    end
    str = str:gsub("^QCT1:", "")

    local compressed = LibDeflate:DecodeForPrint(str)
    if not compressed then
        return false, "Could not decode string (maybe corrupted)."
    end

    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return false, "Could not decompress data."
    end

    local ok, data = AceSerializer:Deserialize(serialized)
    if not ok or type(data) ~= "table" or not data.bars then
        return false, "Could not deserialize bars data."
    end

    local payloadValid, payloadErr = ValidateTrackerBarPayload(data, true)
    if not payloadValid then
        return false, payloadErr or "Import failed bars validation."
    end

    -- Ensure customTrackers structure exists
    if not self.db.profile.customTrackers then
        self.db.profile.customTrackers = { bars = {} }
    end

    if replaceExisting then
        -- Replace all bars
        self.db.profile.customTrackers.bars = data.bars

        -- Replace spec entries (or clear if none provided)
        if not self.db.global then self.db.global = {} end
        self.db.global.specTrackerSpells = data.specEntries or {}
    else
        -- Merge: append bars with new IDs
        if not self.db.profile.customTrackers.bars then
            self.db.profile.customTrackers.bars = {}
        end

        local idMapping = {}  -- old ID -> new ID

        for _, bar in ipairs(data.bars) do
            local oldID = bar.id
            local newID = GenerateUniqueTrackerID()
            bar.id = newID
            idMapping[oldID] = newID
            table.insert(self.db.profile.customTrackers.bars, bar)
        end

        -- Copy spec entries with new IDs
        if data.specEntries then
            if not self.db.global then self.db.global = {} end
            if not self.db.global.specTrackerSpells then self.db.global.specTrackerSpells = {} end

            for oldID, specData in pairs(data.specEntries) do
                local newID = idMapping[oldID]
                if newID then
                    self.db.global.specTrackerSpells[newID] = specData
                end
            end
        end
    end

    return true, "Tracker bars imported successfully."
end

---=================================================================================
--- SPELL SCANNER IMPORT/EXPORT
---=================================================================================

-- Export spell scanner learned data
function QUICore:ExportSpellScanner()
    if not self.db or not self.db.global or not self.db.global.spellScanner then
        return nil, "No spell scanner data to export."
    end
    if not AceSerializer or not LibDeflate then
        return nil, "Export requires AceSerializer-3.0 and LibDeflate."
    end

    local scannerData = self.db.global.spellScanner
    local spellCount = 0
    local itemCount = 0

    if scannerData.spells then
        for _ in pairs(scannerData.spells) do spellCount = spellCount + 1 end
    end
    if scannerData.items then
        for _ in pairs(scannerData.items) do itemCount = itemCount + 1 end
    end

    if spellCount == 0 and itemCount == 0 then
        return nil, "No learned spells or items to export."
    end

    local exportData = {
        spells = scannerData.spells,
        items = scannerData.items,
    }

    local serialized = AceSerializer:Serialize(exportData)
    if not serialized or type(serialized) ~= "string" then
        return nil, "Failed to serialize spell scanner data."
    end

    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        return nil, "Failed to compress spell scanner data."
    end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return nil, "Failed to encode spell scanner data."
    end

    return "QSS1:" .. encoded
end

-- Import spell scanner data (replaceExisting: true = replace all, false = merge)
function QUICore:ImportSpellScanner(str, replaceExisting)
    if not self.db then
        return false, "No database loaded."
    end
    if not AceSerializer or not LibDeflate then
        return false, "Import requires AceSerializer-3.0 and LibDeflate."
    end
    if not str or str == "" then
        return false, "No data provided."
    end

    str = str:gsub("%s+", "")

    -- Check for correct prefix
    if not str:match("^QSS1:") then
        return false, "This doesn't appear to be spell scanner data."
    end
    str = str:gsub("^QSS1:", "")

    local compressed = LibDeflate:DecodeForPrint(str)
    if not compressed then
        return false, "Could not decode string (maybe corrupted)."
    end

    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return false, "Could not decompress data."
    end

    local ok, data = AceSerializer:Deserialize(serialized)
    if not ok or type(data) ~= "table" then
        return false, "Could not deserialize spell scanner data."
    end

    local payloadValid, payloadErr = ValidateSpellScannerPayload(data)
    if not payloadValid then
        return false, payloadErr or "Import failed spell scanner validation."
    end

    -- Ensure global structure exists
    if not self.db.global then self.db.global = {} end
    if not self.db.global.spellScanner then
        self.db.global.spellScanner = { spells = {}, items = {}, autoScan = false }
    end

    if replaceExisting then
        -- Replace all learned data
        self.db.global.spellScanner.spells = data.spells or {}
        self.db.global.spellScanner.items = data.items or {}
    else
        -- Merge: add new entries without overwriting existing
        if data.spells then
            for spellID, spellData in pairs(data.spells) do
                if not self.db.global.spellScanner.spells[spellID] then
                    self.db.global.spellScanner.spells[spellID] = spellData
                end
            end
        end
        if data.items then
            for itemID, itemData in pairs(data.items) do
                if not self.db.global.spellScanner.items[itemID] then
                    self.db.global.spellScanner.items[itemID] = itemData
                end
            end
        end
    end

    return true, "Spell scanner data imported successfully."
end
