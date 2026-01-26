--[[
	KeyBound localization file
		Russian by ?
--]]

if (GetLocale() ~= "ruRU") then
	return
end

local REVISION = 90000 + tonumber(("$Revision: 92 $"):match("%d+"))
if (LibKeyBoundLocale10 and REVISION <= LibKeyBoundLocale10.REVISION) then
	return
end

LibKeyBoundLocale10 = {
	REVISION = REVISION;
	Enabled = 'Режим назначения клавиш включен';
	Disabled = 'Режим назначения клавиш отключен';
	ClearTip = format('Нажмите %s для сброса всех назначений', GetBindingText('ESCAPE', 'KEY_'));
	NoKeysBoundTip = 'Нет текущих назначений';
	ClearedBindings = 'Удалить все назначения с %s';
	BoundKey = 'Установить %s на %s';
	UnboundKey = 'Снять назначение %s с %s';
	CannotBindInCombat = 'Невозможно назначить клавишу в бою';
	CombatBindingsEnabled = 'Выход из боя, режим назначения клавиш включен';
	CombatBindingsDisabled = 'Начало боя, режим назначения клавиш отключен';
	BindingsHelp = "Зависните над кнопкой, и тогда нажмите клавишу для установки назначения.  Для очистки текущих назначений клавиш, нажмите %s.";

	-- This is the short display version you see on the Button
	["Alt"] = "A",
	["Ctrl"] = "C",
	["Shift"] = "S",
	["NumPad"] = "Ц",

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
	["Mouse Wheel Down"] = "КМВХ",
	["Mouse Wheel Up"] = "КМВЗ",
	["Num Lock"] = "NL",
	["Page Down"] = "PD",
	["Page Up"] = "PU",
	["Scroll Lock"] = "SL",
	["Spacebar"] = "Прбл",
	["Tab"] = "Tb",

	["Down Arrow"] = "Dn",
	["Left Arrow"] = "Lf",
	["Right Arrow"] = "Rt",
	["Up Arrow"] = "Up",
}
setmetatable(LibKeyBoundLocale10, {__index = LibKeyBoundBaseLocale10})
