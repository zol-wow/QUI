-- tests/taint/parser/parser_test.lua
-- Smoke test: parse a trivial Lua snippet and verify we got an AST.

local Parser = dofile("tests/taint/parser/init.lua")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "") .. ": expected " .. tostring(expected) ..
              ", got " .. tostring(actual), 2)
    end
end

local source = [[
local x = 1
local y = x + 2
return y
]]
local ast, err = Parser.parse(source, "smoke")
assert(ast, "expected AST, got nil. err=" .. tostring(err))
assert(type(ast) == "table", "AST should be a table")
assert(ast.AstType == "Statlist", "root should be Statlist, got " .. tostring(ast.AstType))
-- Body has 3 real statements + 1 Eof sentinel appended by LuaMinify.
assert(#ast.Body == 4, "expected 4 body entries (3 stmts + Eof), got " .. #ast.Body)
assert(ast.Body[1].AstType == "LocalStatement",
    "stmt 1 should be LocalStatement, got " .. tostring(ast.Body[1].AstType))
assert(ast.Body[2].AstType == "LocalStatement",
    "stmt 2 should be LocalStatement, got " .. tostring(ast.Body[2].AstType))
assert(ast.Body[3].AstType == "ReturnStatement",
    "stmt 3 should be ReturnStatement, got " .. tostring(ast.Body[3].AstType))

local bad, badErr = Parser.parse("local = ", "bad")
assert_eq(bad, nil, "invalid source should return nil")
assert(badErr and #badErr > 0, "should have an error message")

-- Executable CLI scripts begin with a shebang line. Real Lua (luaL_loadfile)
-- skips a leading line starting with '#', so the parser must too — otherwise
-- the analyzer can't read its own tooling scripts.
local shebanged = "#!/usr/bin/env lua\nlocal x = 1\nreturn x\n"
local sast, serr = Parser.parse(shebanged, "shebang")
assert(sast, "shebang source should parse, got nil. err=" .. tostring(serr))
assert(sast.AstType == "Statlist",
    "shebang root should be Statlist, got " .. tostring(sast.AstType))
assert(sast.Body[1].AstType == "LocalStatement",
    "shebang stmt 1 should be LocalStatement, got " .. tostring(sast.Body[1].AstType))

-- Only the FIRST line is a shebang. A '#' mid-source is still a syntax error.
local notShebang, nsErr = Parser.parse("local x = 1\n#bad\n", "not-shebang")
assert_eq(notShebang, nil, "a '#' on a later line should still be a parse error")
assert(nsErr and #nsErr > 0, "later '#' should have an error message")

print("parser smoke test passed")
