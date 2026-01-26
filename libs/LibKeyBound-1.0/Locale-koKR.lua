--[[
	KeyBound localization file
		Korean by damjau
--]]

if (GetLocale() ~= "koKR") then
	return
end

local REVISION = 90000 + tonumber(("$Revision: 92 $"):match("%d+"))
if (LibKeyBoundLocale10 and REVISION <= LibKeyBoundLocale10.REVISION) then
	return
end

LibKeyBoundLocale10 = {
	REVISION = REVISION;
	Enabled = '단축키 설정 기능 사용 가능';
	Disabled = '단축키 설정 기능 사용 불가';
	ClearTip = format('%s키를 누르면 모든 단축키가 초기화됩니다', GetBindingText('ESCAPE', 'KEY_'));
	NoKeysBoundTip = '현재 단축키 없음';
	ClearedBindings = '%s의 모든 단축키가 초기화 되었습니다';
	BoundKey = '%2$s의 단축키로 %1$s|1을;를; 설정합니다.';
	UnboundKey = '%2$s에서 %1$s의 단축키가 삭제되었습니다';
	CannotBindInCombat = '전투 중에는 단축키를 지정할 수 없습니다';
	CombatBindingsEnabled = '전투 종료. 단축키 설정이 가능해집니다';
	CombatBindingsDisabled = '전투 시작. 단축키 설정이 불가능합니다';
	BindingsHelp = "버튼 위에 마우스를 올려 놓고 지정할 키를 누르세요.  버튼의 현재 단축키를 삭제하시려면 %s|1을;를; 누르세요.";

	-- This is the short display version you see on the Button
	["Alt"] = "A",
	["Ctrl"] = "C",
	["Shift"] = "S",
	["NumPad"] = "N",

	["Backspace"] = "BS",
	["Button1"] = "B1",
	["Button2"] = "B2",
	["Button3"] = "B3",
	["Button4"] = "B4",
	["Button5"] = "B5",
	["Button6"] = "B6",
	["Button7"] = "B7",
	["Button8"] = "B8",
	["Button9"] = "B9",
	["Button10"] = "B10",
	["Button11"] = "B11",
	["Button12"] = "B12",
	["Button13"] = "B13",
	["Button14"] = "B14",
	["Button15"] = "B15",
	["Button16"] = "B16",
	["Button17"] = "B17",
	["Button18"] = "B18",
	["Button19"] = "B19",
	["Button20"] = "B20",
	["Button21"] = "B21",
	["Button22"] = "B22",
	["Button23"] = "B23",
	["Button24"] = "B24",
	["Button25"] = "B25",
	["Button26"] = "B26",
	["Button27"] = "B27",
	["Button28"] = "B28",
	["Button29"] = "B29",
	["Button30"] = "B30",
	["Button31"] = "B31",
	["Capslock"] = "Cp",
	["Clear"] = "Cl",
	["Delete"] = "Del",
	["End"] = "En",
	["Home"] = "HM",
	["Insert"] = "Ins",
	["Mouse Wheel Down"] = "WD",
	["Mouse Wheel Up"] = "WU",
	["Num Lock"] = "NL",
	["Page Down"] = "PD",
	["Page Up"] = "PU",
	["Scroll Lock"] = "SL",
	["Spacebar"] = "Sp",
	["Tab"] = "Tb",

	["Down Arrow"] = "DA",
	["Left Arrow"] = "LA",
	["Right Arrow"] = "RA",
	["Up Arrow"] = "UA",
}
setmetatable(LibKeyBoundLocale10, {__index = LibKeyBoundBaseLocale10})
