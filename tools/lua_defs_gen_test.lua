-- tools/lua_defs_gen_test.lua
-- Run: lua tools/lua_defs_gen_test.lua
--
-- Unit tests for the pure transform functions that turn a parsed Blizzard
-- APIDocumentation table into LuaLS meta-definition source.

local G = dofile("tools/lua_defs_gen.lua")

local function assert_eq(a, e, msg)
    if a ~= e then error((msg or "") .. ": expected " .. tostring(e) ..
        ", got " .. tostring(a), 2) end
end

-- mapType: WoW doc types → Lua types, unknown/complex → any
assert_eq(G.mapType("bool"), "boolean", "bool")
assert_eq(G.mapType("cstring"), "string", "cstring")
assert_eq(G.mapType("string"), "string", "string")
assert_eq(G.mapType("luaIndex"), "number", "luaIndex")
assert_eq(G.mapType("number"), "number", "number")
assert_eq(G.mapType("SpellBookSpellBank"), "any", "enum type → any")
assert_eq(G.mapType(nil), "any", "nil → any")

-- sanitizeName: Lua keywords and bad chars are made safe identifiers
assert_eq(G.sanitizeName("spellID"), "spellID", "plain")
assert_eq(G.sanitizeName("end"), "end_", "keyword end")
assert_eq(G.sanitizeName("function"), "function_", "keyword function")
assert_eq(G.sanitizeName("in"), "in_", "keyword in")

-- emitFunction (namespaced): tolerant signature with doc, optional params,
-- trailing vararg, and typed returns.
local fn = {
    Name = "FindBaseSpellByID",
    Documentation = { "Find base spell" },
    Arguments = { { Name = "spellID", Type = "number", Nilable = false } },
    Returns = { { Name = "baseSpellID", Type = "number", Nilable = true } },
}
local out = G.emitFunction(fn, "C_SpellBook")
assert(out:find("--- Find base spell", 1, true), "doc line missing:\n" .. out)
assert(out:find("---@param spellID? number", 1, true), "param line missing:\n" .. out)
assert(out:find("---@param ... any", 1, true), "vararg line missing:\n" .. out)
assert(out:find("---@return number baseSpellID", 1, true), "return line missing:\n" .. out)
assert(out:find("function C_SpellBook.FindBaseSpellByID(spellID, ...) end", 1, true),
    "def line missing:\n" .. out)

-- emitFunction (global, no namespace): bare global function
local g = G.emitFunction({
    Name = "UnitClass",
    Arguments = { { Name = "unit", Type = "string" } },
    Returns = { { Name = "className", Type = "cstring" } },
}, nil)
assert(g:find("function UnitClass(unit, ...) end", 1, true), "global def missing:\n" .. g)

-- emitFunction with no args still gets the trailing vararg
local z = G.emitFunction({ Name = "Foo" }, "C_Bar")
assert(z:find("function C_Bar.Foo(...) end", 1, true), "no-arg def missing:\n" .. z)

-- emitMethod: colon method on a widget class, same tolerant signature
local m = G.emitMethod({
    Name = "SetPoint",
    Arguments = { { Name = "point", Type = "string" }, { Name = "x", Type = "uiUnit" } },
}, "Region")
assert(m:find("---@param point? string", 1, true), "method param missing:\n" .. m)
assert(m:find("---@param x? number", 1, true), "method param2 missing:\n" .. m)
assert(m:find("---@param ... any", 1, true), "method vararg missing:\n" .. m)
assert(m:find("function Region:SetPoint(point, x, ...) end", 1, true), "method def missing:\n" .. m)

print("OK: lua_defs_gen_test")
