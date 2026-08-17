-- tests/unit/cdm_secure_linear_chain_test.lua
-- Run: lua tests/unit/cdm_secure_linear_chain_test.lua

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_containers.lua", "cdm_layout.lua")("QUI", ns)

local function Frame(name, width, height)
    local frame = {
        name = name,
        width = width,
        height = height,
        points = {},
    }

    function frame:ClearAllPoints()
        self.points = {}
    end

    function frame:SetPoint(...)
        self.points[#self.points + 1] = { ... }
    end

    function frame:GetLeft()
        if #self.points == 0 then return 0 end
        local point = self.points[1]
        assert(point[1] == "LEFT")
        local relative = point[2]
        local x = point[4] or 0
        return relative:GetLeft()
            + (point[3] == "RIGHT" and relative.width or 0)
            + x
    end

    return frame
end

local owner = Frame("owner", 0, 0)
local cooldownA = Frame("cooldown-a", 30, 30)
local inactiveAura = Frame("inactive-aura", 1, 1)
local cooldownB = Frame("cooldown-b", 30, 30)

local apply = assert(ns.CDMLayout.AnchorLinearChain,
    "CDMLayout.AnchorLinearChain must exist")

apply(owner, { cooldownA, inactiveAura, cooldownB }, {
    axis = "HORIZONTAL",
    grow = "RIGHT",
    spacing = 2,
    spacingAfter = { [inactiveAura] = -1 },
})

local a = cooldownA.points[1]
local aura = inactiveAura.points[1]
local b = cooldownB.points[1]

assert(a[1] == "LEFT" and a[2] == owner and a[3] == "LEFT"
    and a[4] == 0 and a[5] == 0,
    "first cooldown must start at the owner")
assert(aura[1] == "LEFT" and aura[2] == cooldownA and aura[3] == "RIGHT"
    and aura[4] == 2 and aura[5] == 0,
    "aura must follow the first cooldown")
assert(b[1] == "LEFT" and b[2] == inactiveAura and b[3] == "RIGHT"
    and b[4] == -1 and b[5] == 0,
    "second cooldown must follow the aura layout frame")
assert(cooldownB:GetLeft() == 32,
    "inactive 1x1 aura must collapse without an extra gap")
inactiveAura.width = 33
assert(cooldownB:GetLeft() == 64,
    "one active aura must preserve the visible row gap")
inactiveAura.width = 65
assert(cooldownB:GetLeft() == 96,
    "two active auras must preserve both visible row gaps")

print("OK: cdm_secure_linear_chain_test")
