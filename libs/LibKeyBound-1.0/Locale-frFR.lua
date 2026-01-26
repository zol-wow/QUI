--[[
	LibKeyBound-1.0 localization file
		French by ?
--]]

if (GetLocale() ~= "frFR") then
	return
end

local REVISION = 90000 + tonumber(("$Revision: 92 $"):match("%d+"))
if (LibKeyBoundLocale10 and REVISION <= LibKeyBoundLocale10.REVISION) then
	return
end

LibKeyBoundLocale10 = {
	REVISION = REVISION;
	Enabled = "Mode Raccourcis activé";
	Disabled = "Mode Raccourcis désactivé";
	ClearTip = format("Appuyez sur %s pour effacer tous les raccourcis", GetBindingText("ESCAPE", "KEY_"));
	NoKeysBoundTip = "Aucun raccourci";
	ClearedBindings = "Suppression de tous les raccourcis de %s";
	BoundKey = "%s associé à %s";
	UnboundKey = "%s n'est plus associé à %s";
	CannotBindInCombat = "Impossible de faire des raccourcis en combat";
	CombatBindingsEnabled = "Sortie de combat, mode Raccourcis activé";
	CombatBindingsDisabled = "Entrée en combat, mode Raccourcis désactivé";
	BindingsHelp = "Survolez un bouton, puis appuyez sur une touche pour définir son raccourci.  Pour effacer le raccourci actuel d'un bouton, appuyez sur %s";

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

	["Down Arrow"] = "BA",
	["Left Arrow"] = "GA",
	["Right Arrow"] = "DA",
	["Up Arrow"] = "HA",
}
setmetatable(LibKeyBoundLocale10, {__index = LibKeyBoundBaseLocale10})
