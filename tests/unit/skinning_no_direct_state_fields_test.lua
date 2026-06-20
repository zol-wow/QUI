-- tests/unit/skinning_no_direct_state_fields_test.lua
-- Run: lua tests/unit/skinning_no_direct_state_fields_test.lua
--
-- Blizzard-owned skinning surfaces must store QUI hook/style sentinels in the
-- shared SkinBase side tables. Direct frame/table fields are the exact pattern
-- core/uikit.lua replaced for Midnight taint hygiene.

local function ReadLines(path)
    local f = assert(io.open(path, "r"), "cannot open " .. path)
    local lines = {}
    for line in f:lines() do
        lines[#lines + 1] = line
    end
    f:close()
    return lines
end

local function FileList()
    local cmd = "find QUI_Skinning/skinning -type f -name '*.lua' | sort"
    local pipe = assert(io.popen(cmd, "r"))
    local files = {}
    for path in pipe:lines() do
        files[#files + 1] = path
    end
    pipe:close()
    return files
end

local failures = {}
for _, path in ipairs(FileList()) do
    for lineNo, line in ipairs(ReadLines(path)) do
        if line:find("%._qui[%w_]*")
            or line:find("%.__qui[%w_]*")
            or line:find("%.quiSkinned")
            or line:find("%.quiStyled")
            or line:find("%.quiBackdrop") then
            failures[#failures + 1] = string.format("%s:%d:%s", path, lineNo, line)
        end
    end
end

if #failures > 0 then
    error("direct QUI frame state fields must use SkinBase.SetFrameData/GetFrameData:\n"
        .. table.concat(failures, "\n"))
end

print("OK: skinning_no_direct_state_fields_test")
