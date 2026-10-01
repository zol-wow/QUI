-- Run from the addon root with Lua 5.1.
local sent, popup = {}, nil
local secret = {}
local grouped, raided = true, true
IsInGroup = function() return grouped end
IsInRaid = function() return raided end
CreateFrame = function()
    return setmetatable({}, { __index = function() return function() end end })
end
CreateAbbreviateConfig = function(t) return t end
AbbreviateNumbers = function(n) return tostring(n) end
BreakUpLargeNumbers = function(n) return tostring(n) end
SlashCmdList = {}
C_ChatInfo = { SendChatMessage = function(...) sent[#sent + 1] = {...} end }
StaticPopup_Show = function(which, _, _, data)
    assert(which == 'GENERIC_INPUT_BOX')
    popup = data
end
Enum = { DamageMeterType = { DamageDone = 0, Dps = 1 },
    DamageMeterSessionType = { Overall = 0, Current = 1 } }
local appearance = { numberFormat = 'complete', showSecondaryValue = true }
QUI = { db = { profile = { damageMeter = { native = {
    windows = { {} }, appearance = { global = appearance, perWindow = {} },
} } } } }
local ns = { L = setmetatable({}, { __index = function(_, key) return key end }),
    Helpers = { IsSecretValue = function(v) return rawequal(v, secret) end } }
assert(loadfile('QUI_DamageMeter/damage_meter/damage_meter.lua'))('QUI', ns)
local Window = ns.QUI_DamageMeter.Window
local window = setmetatable({windowID = 1, damageMeterType = 1, sessionType = 1,
    sessionID = 7, sessionLabel = 'Boss', _renderSources = {
        {name = 'Alpha', rank = 1, totalAmount = 1000, amountPerSecond = 100},
        {name = 'Bravo', rank = 2, totalAmount = 500, amountPerSecond = 50},
    }}, {__index = Window})
local function node(label, callback)
    local n = { label = label, callback = callback, children = {} }
    function n:CreateButton(text, fn)
        local child = node(text, fn); self.children[text] = child; return child
    end
    n.CreateRadio = n.CreateButton
    n.CreateCheckbox = n.CreateButton
    function n:CreateTitle() end
    function n:CreateDivider() end
    function n:SetEnabled(value) self.enabled = value end
    return n
end
local menu
MenuUtil = { CreateContextMenu = function(_, fn) menu = node(); fn(nil, menu) end }
window._PopulateSessionMenu = function() end
window:_OpenConfigMenu()
local share = assert(menu.children['Share Results'], 'meter menu must offer sharing')
share.children.Party.callback()
assert(#sent == 3 and sent[1][1] == 'QUI - DPS - Boss')
assert(sent[2][1] == '1. Alpha - 100 (1000)' and sent[3][1] == '2. Bravo - 50 (500)')
for _, line in ipairs(sent) do assert(line[2] == 'PARTY') end
sent = {}; share.children.Raid.callback()
assert(#sent == 3 and sent[1][2] == 'RAID')
sent = {}; share.children.Whisper.callback()
assert(#sent == 0 and popup, 'whisper must request recipient first')
window._renderSources[1].amountPerSecond = 999
popup.callback('  Receiver-Realm  ')
assert(#sent == 3 and sent[2][1] == '1. Alpha - 100 (1000)', 'whisper must send snapshot')
assert(sent[1][2] == 'WHISPER' and sent[1][4] == 'Receiver-Realm')
sent = {}; popup.callback('   '); assert(#sent == 0)
grouped, raided = false, false
share.children.Party.callback(); share.children.Raid.callback(); assert(#sent == 0)
window:_OpenConfigMenu()
assert(menu.children['Share Results'].children.Party.enabled == false)
assert(menu.children['Share Results'].children.Raid.enabled == false)
grouped = true
window._renderSources[2].totalAmount = secret
share.children.Party.callback(); assert(#sent == 0, 'restricted data must not partially send')
window._renderSources = {}; share.children.Party.callback(); assert(#sent == 0)
window._renderSources = {{name='Solo',rank=1,totalAmount=500,amountPerSecond=50}}
window.damageMeterType = 0; window.sessionID = nil; window.sessionType = 0
appearance.showSecondaryValue = false
share.children.Party.callback()
assert(sent[1][1] == 'QUI - Damage Done - Overall' and sent[2][1] == '1. Solo - 500')
print('OK: damage meter sharing')
