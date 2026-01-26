--[[
	LibKeyBound-1.0 localization file
		Deutch by Gamefaq
--]]

if (GetLocale() ~= "deDE") then
	return
end

local REVISION = 90000 + tonumber(("$Revision: 108 $"):match("%d+"))
if (LibKeyBoundLocale10 and REVISION <= LibKeyBoundLocale10.REVISION) then
	return
end


LibKeyBoundLocale10 = {
	REVISION = REVISION;



	BindingMode = "Tastenbelegungsmodus";
	Enabled = "Tastenbelegungsmodus aktiviert";
	Disabled = "Tastenbelegungsmodus deaktiviert";
	ClearTip = format("Drücke %s, um alle Tastenbelegungen zu löschen", GetBindingText("ESCAPE", "KEY_"));
	NoKeysBoundTip = "Keine Tasten zugewiesen";
	ClearedBindings = "Alle Belegungen von %s wurden entfernt";
	BoundKey = "%s wurde %s zugewiesen";
	UnboundKey = "%s wurde von %s entfernt";
	CannotBindInCombat = "Tasten können nicht im Kampf belegt werden";
	CombatBindingsEnabled = "Verlasse Kampf, Tastenbelegungsmodus aktiviert";
	CombatBindingsDisabled = "Beginne Kampf, Tastenbelegungsmodus deaktiviert";
	BindingsHelp = "Schwebe mit der Maus über eine Schaltfläche. Drücke dann eine Taste, um sie dieser Schaltfläche zuzuweisen. Um alle Tastenbelegungen der Schaltfläche wieder zu löschen, drücke %s.";

	-- This is the short display version you see on the Button
	["Alt"] = "A",
	["Ctrl"] = "S",
	["Shift"] = "U",
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
