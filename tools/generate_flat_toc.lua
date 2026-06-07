-- generate_flat_toc.lua
-- One-shot converter used for the XML→TOC loading migration: flattens the
-- load.xml <Include>/<Script file> tree into an ordered, TOC-style file list
-- so the client loads every Lua file directly from the TOC instead of through
-- the XML include chain. Kept as the record of how QUI.toc's file list was
-- derived; it cannot run again once the manifest XMLs are deleted.
--
-- Usage:   lua tools/generate_flat_toc.lua   (requires load.xml to exist)
-- Output:  tools/flat_toc/QUI.toc
--
-- Semantics preserved:
--   * Exact load order of every .lua file.
--   * XML files containing anything beyond <Script>/<Include> (frame/template
--     definitions) are NOT expanded — they are emitted as TOC lines verbatim,
--     which the client supports.
--   * Each flattened manifest becomes a "# == path ==" section comment so the
--     TOC stays navigable.

local ROOT = arg and arg[0] and arg[0]:match("^(.*)/tools/[^/]+$") or "."

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function normalize(path)
    path = path:gsub("\\", "/")
    -- collapse any dir/../ segments
    while true do
        local collapsed = path:gsub("[^/]+/%.%./", "")
        if collapsed == path then break end
        path = collapsed
    end
    return path
end

local function dirOf(path)
    return path:match("^(.*)/[^/]*$") or ""
end

-- True when the XML document contains only <Ui>, <Script>, <Include> elements
-- (i.e. it is purely a load manifest and can be flattened away).
local function isManifestOnly(content)
    for tag in content:gmatch("<%s*([%a_][%w_]*)") do
        if tag ~= "Ui" and tag ~= "Script" and tag ~= "Include" then
            return false, tag
        end
    end
    return true
end

local out = {}        -- ordered TOC lines (addon-root-relative, backslashes)
local missing = {}    -- referenced files not found on disk (case or typo)
local keptXml = {}    -- xml files emitted as-is (frame definitions inside)
local seen = {}       -- duplicate guard

local function emit(relPath)
    if seen[relPath] then
        io.write(("WARN duplicate file skipped: %s\n"):format(relPath))
        return
    end
    seen[relPath] = true
    out[#out + 1] = relPath:gsub("/", "\\")
end

local function walkXml(relPath)
    local full = ROOT .. "/" .. relPath
    local content = readFile(full)
    if not content then
        missing[#missing + 1] = relPath
        return
    end

    -- strip comments so commented-out includes are not loaded
    content = content:gsub("<!%-%-.-%-%->", "")

    local baseDir = dirOf(relPath)
    -- scan element-by-element in document order
    for tag, attrs in content:gmatch("<%s*(%a+)([^>]*)>") do
        local file = attrs:match('file%s*=%s*"([^"]+)"')
        if file then
            local ref = normalize((baseDir ~= "" and (baseDir .. "/") or "") .. normalize(file))
            if tag == "Script" then
                if not readFile(ROOT .. "/" .. ref) then
                    missing[#missing + 1] = ref
                end
                emit(ref)
            elseif tag == "Include" then
                if ref:lower():match("%.xml$") then
                    local sub = readFile(ROOT .. "/" .. ref)
                    if not sub then
                        missing[#missing + 1] = ref
                    else
                        local manifestOnly, badTag = isManifestOnly(sub:gsub("<!%-%-.-%-%->", ""))
                        if manifestOnly then
                            -- Section header so the flat TOC stays navigable.
                            out[#out + 1] = ""
                            out[#out + 1] = "# == " .. ref .. " =="
                            walkXml(ref)
                        else
                            keptXml[#keptXml + 1] = { path = ref, tag = badTag }
                            emit(ref)
                        end
                    end
                else
                    emit(ref)
                end
            end
        end
    end
end

-- Build the flat list from the same entry point the real TOC uses.
walkXml("load.xml")

-- Reproduce the original TOC header verbatim, swap the body.
local tocContent = readFile(ROOT .. "/QUI.toc")
if not tocContent then
    io.write("ERROR: QUI.toc not found at repo root\n")
    os.exit(1)
end
local header = {}
for line in (tocContent:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
    if line:match("^##") or line == "" then
        header[#header + 1] = line
    else
        break -- first file entry: header is done
    end
end
-- trim trailing blank header lines
while header[#header] == "" do header[#header] = nil end

os.execute(("mkdir -p %q"):format(ROOT .. "/tools/flat_toc"))
local outPath = ROOT .. "/tools/flat_toc/QUI.toc"
local f = assert(io.open(outPath, "wb"))
f:write(table.concat(header, "\n"), "\n")
f:write("\n# File list converted from the old load.xml include tree\n")
f:write("# (tools/generate_flat_toc.lua). Order is load-bearing.\n")
f:write(table.concat(out, "\n"), "\n")
f:close()

io.write(("flat TOC written: %s\n"):format(outPath))
io.write(("  entries: %d\n"):format(#out))
if #keptXml > 0 then
    io.write(("  xml kept as TOC lines (contain <%s> etc.):\n"):format(keptXml[1].tag))
    for _, k in ipairs(keptXml) do
        io.write(("    %s (<%s>)\n"):format(k.path, k.tag))
    end
end
if #missing > 0 then
    io.write("  MISSING on disk (check case!):\n")
    for _, m in ipairs(missing) do
        io.write(("    %s\n"):format(m))
    end
    os.exit(1)
end
