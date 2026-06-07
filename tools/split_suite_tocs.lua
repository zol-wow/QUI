-- tools/split_suite_tocs.lua
-- One-shot TOC splitter for the QUI multi-addon suite split.
--
-- Usage (write outputs):   lua tools/split_suite_tocs.lua --run
-- Usage (unit-test only):  local M = assert(loadfile("tools/split_suite_tocs.lua"))()
--
-- When run with --run:
--   Reads QUI.toc + QUI_Options/QUI_Options.toc + core/addon_manifest.lua,
--   writes all output under tools/suite_split/ WITHOUT modifying any live file.
--
-- When loaded without --run (loadfile(...)()):
--   Returns the module table M for unit testing. Writes nothing.
-- luacheck: globals arg

local M = {}

---------------------------------------------------------------------------
-- Root detection (same pattern as generate_flat_toc.lua)
---------------------------------------------------------------------------
local ROOT = arg and arg[0] and arg[0]:match("^(.*)/tools/[^/]+$") or "."

---------------------------------------------------------------------------
-- Filesystem helpers
---------------------------------------------------------------------------
local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function writeFile(path, content)
    local f = assert(io.open(path, "wb"),
        "cannot open for writing: " .. path)
    f:write(content)
    f:close()
end

local function mkdir(path)
    os.execute(("mkdir -p %q"):format(path))
end

local function lines(text)
    local result = {}
    for line in (text:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
        result[#result + 1] = line
    end
    -- trim trailing empty lines that arise from the trailing \n we added
    while result[#result] == "" do result[#result] = nil end
    return result
end

---------------------------------------------------------------------------
-- Pretty-name map for sub-addon titles
---------------------------------------------------------------------------
local TITLES = {
    QUI_ActionBars  = "Action Bars",
    QUI_CDM         = "Cooldown Manager",
    QUI_Chat        = "Chat",
    QUI_GroupFrames = "Group Frames",
    QUI_ResourceBars= "Resource Bars",
    QUI_UnitFrames  = "Unit Frames",
    QUI_Skinning    = "Skinning",
    QUI_Minimap     = "Minimap",
    QUI_QoL         = "Quality of Life",
    QUI_DamageMeter = "Damage Meter",
}

---------------------------------------------------------------------------
-- M.CORE_DIRS: module dirs that stay in the QUI core (never moved to sub-addons)
---------------------------------------------------------------------------
M.CORE_DIRS = { layout = true, ui = true, integrations = true }

---------------------------------------------------------------------------
-- M.BuildHeader(entry, interfaceLine[, versionLine]) → TOC header string (trailing \n)
-- versionLine defaults to "## Version: 4.0.0-beta26" when nil (keeps unit tests
-- that pass only 2 args working).
---------------------------------------------------------------------------
function M.BuildHeader(entry, interfaceLine, versionLine)
    versionLine = versionLine or "## Version: 4.0.0-beta26"
    local lines_out = {}
    local function add(s) lines_out[#lines_out + 1] = s end

    add(interfaceLine)
    add("## Title: |cFF30D1FFQUI|r " .. (TITLES[entry.folder] or entry.folder))
    add("## Notes: QUI module. Requires the QUI core addon.")
    add("## Author: Zol")
    add(versionLine)
    add("## Category: User Interface")
    add("## Group: QUI")
    add("## Dependencies: QUI")
    add("## IconTexture: Interface\\AddOns\\QUI\\assets\\QUI")
    if entry.class == "lod" then
        add("## LoadOnDemand: 1")
    end
    if entry.folder == "QUI_Chat" then
        add("## SavedVariablesPerCharacter: QUI_ChatHistory")
        add("## LoadSavedVariablesFirst: 1")
    end

    return table.concat(lines_out, "\n") .. "\n"
end

---------------------------------------------------------------------------
-- Build a lookup: dir (e.g. "cdm") → folder (e.g. "QUI_CDM")
-- Sources in manifest use forward-slash form "modules/cdm" so we strip prefix.
---------------------------------------------------------------------------
local function buildDirIndex(manifest)
    local idx = {}  -- idx["cdm"] = "QUI_CDM"
    for _, entry in ipairs(manifest) do
        for _, src in ipairs(entry.sources) do
            -- src is like "modules/cdm"
            local dir = src:match("^modules/(.+)$")
            if dir then
                idx[dir] = entry.folder
            end
        end
    end
    return idx
end

---------------------------------------------------------------------------
-- M.ClassifyLine(line, manifest) → folder name or nil
-- Matches backslash-form TOC lines like "modules\cdm\..."
---------------------------------------------------------------------------
function M.ClassifyLine(line, manifest)
    -- Only classify file lines starting with "modules\"
    local dir = line:match("^modules\\([^\\]+)\\")
    if not dir then return nil end
    local idx = buildDirIndex(manifest)
    return idx[dir]  -- nil if dir stays in core
end

---------------------------------------------------------------------------
-- M.RewriteForSubAddon(line) → strip leading "modules\" prefix
---------------------------------------------------------------------------
function M.RewriteForSubAddon(line)
    return (line:gsub("^modules\\", ""))
end

---------------------------------------------------------------------------
-- M.RewriteOptionsLine(line, manifest) → rewrite ..\QUI\modules\<dir>\ paths
-- Lines for dirs that move: ..\QUI\modules\<dir>\rest → ..\<Folder>\<dir>\rest
-- Lines for dirs staying in core (layout, ui, integrations) or non-modules: unchanged
---------------------------------------------------------------------------
function M.RewriteOptionsLine(line, manifest)
    -- Match ..\QUI\modules\<dir>\rest (backslash form)
    local dir, rest = line:match("^%.%.\\QUI\\modules\\([^\\]+)\\(.+)$")
    if not dir then return line end
    local idx = buildDirIndex(manifest)
    local folder = idx[dir]
    if not folder then
        -- dir stays in core (layout, ui, integrations, etc.) — leave unchanged
        return line
    end
    return "..\\" .. folder .. "\\" .. dir .. "\\" .. rest
end

---------------------------------------------------------------------------
-- Main run logic — only executed when --run is passed
---------------------------------------------------------------------------
local function run()
    -- Clear stale outputs before writing fresh ones
    os.execute('rm -rf "tools/suite_split"')

    -- Load manifest
    local manifest = assert(loadfile(ROOT .. "/core/addon_manifest.lua"))()

    -- Validate all manifest source dirs exist on disk
    local missing = {}
    for _, entry in ipairs(manifest) do
        for _, src in ipairs(entry.sources) do
            local path = ROOT .. "/" .. src
            local ok = os.execute(("test -d %q"):format(path))
            if ok ~= 0 and ok ~= true then
                missing[#missing + 1] = src
            end
        end
    end
    if #missing > 0 then
        for _, m in ipairs(missing) do
            io.write("ERROR: manifest source dir not found on disk: " .. m .. "\n")
        end
        os.exit(1)
    end

    -- Read live QUI.toc
    local tocText = assert(readFile(ROOT .. "/QUI.toc"),
        "ERROR: QUI.toc not found")
    local tocLines = lines(tocText)

    -- Extract the ## Interface: and ## Version: lines from QUI.toc
    local interfaceLine
    local versionLine
    for _, l in ipairs(tocLines) do
        if l:match("^## Interface:") then
            interfaceLine = l
        elseif l:match("^## Version:") then
            versionLine = l
        end
        if interfaceLine and versionLine then break end
    end
    assert(interfaceLine, "no ## Interface: line in QUI.toc")

    -- Read live QUI_Options.toc
    local optText = assert(readFile(ROOT .. "/QUI_Options/QUI_Options.toc"),
        "ERROR: QUI_Options/QUI_Options.toc not found")
    local optLines = lines(optText)

    -- Pre-count planned moves for validation BEFORE writing anything
    local mvCount = 0
    for _, entry in ipairs(manifest) do
        for _, src in ipairs(entry.sources) do
            if src:match("^modules/") then
                mvCount = mvCount + 1
            end
        end
    end
    if mvCount ~= 14 then
        io.write("ERROR: expected 14 git mv lines, got " .. mvCount
            .. "; update the manifest or this tool\n")
        os.exit(1)
    end

    -- Create output root
    mkdir(ROOT .. "/tools/suite_split")

    -----------------------------------------------------------------------
    -- Helpers used in the body-partition pass
    -----------------------------------------------------------------------
    local function isSectionComment(l)
        return l:match("^# == ") ~= nil
    end

    local function isFileLine(l)
        return l ~= "" and not l:match("^#") and not l:match("^%s*$")
    end

    -----------------------------------------------------------------------
    -- Split tocLines into header block and body lines.
    -- The header block ends just before the first file line.
    -- Body lines: everything from that file line onward.
    -----------------------------------------------------------------------
    local headerLines = {}
    local bodyLines   = {}
    local inBody = false
    for _, line in ipairs(tocLines) do
        if not inBody and isFileLine(line) then
            inBody = true
        end
        if inBody then
            bodyLines[#bodyLines + 1] = line
        else
            headerLines[#headerLines + 1] = line
        end
    end

    -----------------------------------------------------------------------
    -- Process header: remove QUI_ChatHistory from SavedVariablesPerCharacter
    -----------------------------------------------------------------------
    local newHeader = {}
    for _, line in ipairs(headerLines) do
        if line:match("^## SavedVariablesPerCharacter:") then
            local _, val = line:match("^(## SavedVariablesPerCharacter:)%s*(.+)$")
            if val then
                local tokens = {}
                for token in (val .. ","):gmatch("([^,]+),") do
                    local t = token:match("^%s*(.-)%s*$")
                    if t ~= "" and t ~= "QUI_ChatHistory" then
                        tokens[#tokens + 1] = t
                    end
                end
                if #tokens > 0 then
                    newHeader[#newHeader + 1] = "## SavedVariablesPerCharacter: "
                        .. table.concat(tokens, ", ")
                end
                -- else: only SV was QUI_ChatHistory → drop line entirely
            else
                newHeader[#newHeader + 1] = line
            end
        else
            newHeader[#newHeader + 1] = line
        end
    end

    -----------------------------------------------------------------------
    -- Classify every body line
    -- classified[i] = folder name if moved, nil if stays core
    -----------------------------------------------------------------------
    local classified = {}
    for i, line in ipairs(bodyLines) do
        if line:match("^modules\\") then
            classified[i] = M.ClassifyLine(line, manifest)
        end
    end

    -----------------------------------------------------------------------
    -- For each section-comment body line, pre-compute its "owner":
    --   the folder of the first file line that follows it (before the next
    --   section comment), or "core" if that file stays core, or "drop" if
    --   no file line follows before the next section comment / EOF.
    -----------------------------------------------------------------------
    local sectionOwner = {}
    for i, line in ipairs(bodyLines) do
        if isSectionComment(line) then
            local owner = "drop"
            for j = i + 1, #bodyLines do
                local jl = bodyLines[j]
                if isSectionComment(jl) then break end
                if isFileLine(jl) then
                    owner = classified[j] or "core"
                    break
                end
            end
            sectionOwner[i] = owner
        end
    end

    -----------------------------------------------------------------------
    -- Partition body lines into per-folder lists and coreBody
    -----------------------------------------------------------------------
    local folderFiles = {}
    for _, entry in ipairs(manifest) do
        folderFiles[entry.folder] = {}
    end
    local coreBody = {}

    for i, line in ipairs(bodyLines) do
        if isSectionComment(line) then
            local owner = sectionOwner[i]
            if owner == "drop" then
                -- skip
            elseif owner == "core" then
                coreBody[#coreBody + 1] = line
            else
                local fl = folderFiles[owner]
                if fl then fl[#fl + 1] = line end
            end
        elseif isFileLine(line) then
            local folder = classified[i]
            if folder then
                local fl = folderFiles[folder]
                if fl then fl[#fl + 1] = M.RewriteForSubAddon(line) end
            else
                coreBody[#coreBody + 1] = line
            end
        else
            -- empty line or plain non-section comment: stays in core body
            coreBody[#coreBody + 1] = line
        end
    end

    -----------------------------------------------------------------------
    -- Validate: every remaining modules\ line in coreBody must be
    -- layout / ui / integrations.
    -----------------------------------------------------------------------
    local coreDirs = M.CORE_DIRS
    local hasUnclassified = false
    for _, line in ipairs(coreBody) do
        if line:match("^modules\\") then
            local dir = line:match("^modules\\([^\\]+)\\")
            if not dir or not coreDirs[dir] then
                io.write("UNCLASSIFIED core line: " .. line .. "\n")
                hasUnclassified = true
            end
        end
    end
    if hasUnclassified then os.exit(1) end

    -----------------------------------------------------------------------
    -- Write tools/suite_split/QUI.toc
    -----------------------------------------------------------------------
    local coreOut = {}
    for _, l in ipairs(newHeader) do coreOut[#coreOut + 1] = l end
    for _, l in ipairs(coreBody)  do coreOut[#coreOut + 1] = l end
    writeFile(ROOT .. "/tools/suite_split/QUI.toc",
        table.concat(coreOut, "\n") .. "\n")

    -----------------------------------------------------------------------
    -- Build each sub-addon TOC
    -----------------------------------------------------------------------
    local folderCounts = {}
    for _, entry in ipairs(manifest) do
        local folder = entry.folder
        mkdir(ROOT .. "/tools/suite_split/" .. folder)

        local header = M.BuildHeader(entry, interfaceLine, versionLine)
        local fileLines = folderFiles[folder] or {}

        -- header ends with \n; strip trailing newline so join produces exactly one blank line
        local tocOut = { (header:gsub("\n$", "")) }
        tocOut[#tocOut + 1] = ""   -- blank line between header and file list
        tocOut[#tocOut + 1] = "bootstrap.lua"
        for _, fl in ipairs(fileLines) do
            tocOut[#tocOut + 1] = fl
        end

        writeFile(ROOT .. "/tools/suite_split/" .. folder .. "/" .. folder .. ".toc",
            table.concat(tocOut, "\n") .. "\n")

        -- Count actual file lines (not section comments, not empty, not bootstrap)
        local count = 0
        for _, fl in ipairs(fileLines) do
            if fl ~= "" and not fl:match("^#") then count = count + 1 end
        end
        folderCounts[folder] = count
    end

    -----------------------------------------------------------------------
    -- Build tools/suite_split/QUI_Options.toc
    -----------------------------------------------------------------------
    local newOptLines = {}
    for _, line in ipairs(optLines) do
        newOptLines[#newOptLines + 1] = M.RewriteOptionsLine(line, manifest)
    end
    writeFile(ROOT .. "/tools/suite_split/QUI_Options.toc",
        table.concat(newOptLines, "\n") .. "\n")

    -----------------------------------------------------------------------
    -- Build tools/suite_split/git_mv.sh
    -----------------------------------------------------------------------
    local sh = {
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        "",
        'cd "$(git rev-parse --show-toplevel)"',
        '[ -f QUI.toc ] || { echo "ERROR: run from the QUI repo root" >&2; exit 1; }',
        "",
        "# NOTE: this script is HALF the apply. The generated tools/suite_split/QUI.toc",
        "# and tools/suite_split/QUI_Options.toc must be copied over the live files",
        "# manually (plan Task 4).",
        "",
    }
    for _, entry in ipairs(manifest) do
        local folder = entry.folder
        sh[#sh + 1] = "mkdir -p " .. folder
        for _, src in ipairs(entry.sources) do
            -- src is "modules/cdm" → guarded git mv modules/cdm QUI_CDM/cdm
            local dir = src:match("^modules/(.+)$")
            local dest = folder .. "/" .. dir
            sh[#sh + 1] = "if [ -d " .. src .. " ]; then"
            sh[#sh + 1] = "  [ -e " .. dest .. " ] && { echo \"ERROR: " .. dest
                .. " exists\" >&2; exit 1; }"
            sh[#sh + 1] = "  git mv " .. src .. " " .. dest
            sh[#sh + 1] = "  echo \"moved: " .. src .. " -> " .. dest .. "\""
            sh[#sh + 1] = "else"
            sh[#sh + 1] = "  echo \"skip: " .. src .. " already moved\""
            sh[#sh + 1] = "fi"
        end
        sh[#sh + 1] = "cp tools/suite_split/" .. folder .. "/" .. folder
            .. ".toc " .. folder .. "/"
        sh[#sh + 1] = "cp core/templates/subaddon_bootstrap.lua "
            .. folder .. "/bootstrap.lua"
        sh[#sh + 1] = ""
    end

    writeFile(ROOT .. "/tools/suite_split/git_mv.sh",
        table.concat(sh, "\n") .. "\n")

    -----------------------------------------------------------------------
    -- Summary
    -----------------------------------------------------------------------
    io.write("tools/suite_split/ written.\n")
    io.write(string.format("  git mv commands: %d\n", mvCount))
    io.write("  Per-folder file counts:\n")
    for _, entry in ipairs(manifest) do
        io.write(string.format("    %-20s  %d files\n",
            entry.folder, folderCounts[entry.folder] or 0))
    end
    local coreFileCount = 0
    for _, line in ipairs(coreBody) do
        if line ~= "" and not line:match("^#") then
            coreFileCount = coreFileCount + 1
        end
    end
    io.write(string.format("    %-20s  %d files (core)\n", "QUI (core)", coreFileCount))
end

---------------------------------------------------------------------------
-- Entry point
---------------------------------------------------------------------------
local isRun = false
if arg then
    for _, a in ipairs(arg) do
        if a == "--run" then isRun = true end
    end
end

if isRun then
    run()
else
    return M
end
