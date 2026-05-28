-- tests/unit/cdm_icon_renderer_secret_stack_static_test.lua
-- Run: lua tests/unit/cdm_icon_renderer_secret_stack_static_test.lua

local path = "modules/cdm/cdm_icon_renderer.lua"
local handle = assert(io.open(path, "rb"))
local source = handle:read("*a")
handle:close()

assert(source:find("if issecretvalue and issecretvalue%(stackVal%) then%s*displayText = stackVal%s*elseif type%(stackVal%) == \"number\" then%s*if stackSource == \"ChargeCount\" or stackSource == \"spell%-charge%-count\" then%s*displayText = tostring%(stackVal%)"),
    "UpdateIconCooldown must guard secret stackVal before tostring/formatting the charge-count path")

assert(source:find("if issecretvalue and issecretvalue%(stackVal%) then%s*displayText = stackVal%s*elseif type%(stackVal%) == \"number\" then%s*displayText = C_StringUtil.TruncateWhenZero%(stackVal%)"),
    "UpdateIconCooldown must guard secret stackVal before formatting the harvested aura-stack path")

print("OK: cdm_icon_renderer_secret_stack_static_test")
