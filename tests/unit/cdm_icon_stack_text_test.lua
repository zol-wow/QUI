-- tests/unit/cdm_icon_stack_text_test.lua
-- Run: lua tests/unit/cdm_icon_stack_text_test.lua

local secretToken = { secret = true }
_G.issecretvalue = function(value)
    return value == secretToken
end

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_stack_text.lua")("QUI", ns)

local stackText = assert(ns.CDMIconStackText, "CDMIconStackText table was not exported")

assert(stackText.ValueIsPresent(secretToken) == true, "secret stack text should count as present")
assert(stackText.TextHasDisplay(secretToken) == true, "secret stack text should count as displayable")
assert(stackText.TextHasDisplay("") == false, "known empty text should not count as displayable")
assert(stackText.TextHasDisplay("3") == true, "non-empty text should count as displayable")
assert(stackText.ValueIsMissing(nil) == true, "nil stack text should count as missing")

local writes = {}
local icon = {
    StackText = {
        SetText = function(_, value)
            writes[#writes + 1] = { op = "set", value = value }
        end,
        Show = function()
            writes[#writes + 1] = { op = "show" }
        end,
        Hide = function()
            writes[#writes + 1] = { op = "hide" }
        end,
    },
}

local setOk, _, showOk = stackText.Show(icon, secretToken, "Applications")
assert(setOk == true, "show should report a successful text write")
assert(showOk == true, "show should report a successful show write")
assert(writes[1].op == "set" and writes[1].value == secretToken,
    "show should forward secret stack text unchanged")
assert(writes[2].op == "show", "show should show the stack text FontString")
assert(icon._stackTextSource == "Applications", "show should stamp the stack text source")

stackText.Clear(icon)
assert(writes[3].op == "set" and writes[3].value == "", "clear should write an empty string")
assert(writes[4].op == "hide", "clear should hide the stack text FontString")
assert(icon._stackTextSource == nil, "clear should remove the stack text source")

print("OK: cdm_icon_stack_text_test")
