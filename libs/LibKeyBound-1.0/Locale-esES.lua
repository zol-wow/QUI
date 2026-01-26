--[[
	LibKeyBound-1.0 localization file
		Spanish by StiviS
--]]

if (GetLocale() ~= "esES") then
	return
end

local REVISION = 90000 + tonumber(("$Revision: 92 $"):match("%d+"))
if (LibKeyBoundLocale10 and REVISION <= LibKeyBoundLocale10.REVISION) then
	return
end

LibKeyBoundLocale10 = {
	REVISION = REVISION;
	Enabled = 'Modo Atajos activado';
	Disabled = 'Modo Atajos desactivado';
	ClearTip = format('Pulsa %s para limpiar todos los atajos', GetBindingText('ESCAPE', 'KEY_'));
	NoKeysBoundTip = 'No existen atajos';
	ClearedBindings = 'Eliminados todos los atajos de %s';
	BoundKey = 'Establecer %s a %s';
	UnboundKey = 'Quitado atajo %s de %s';
	CannotBindInCombat = 'No se pueden atajar teclas en combate';
	CombatBindingsEnabled = 'Saliendo de combate, modo de Atajos de Teclado activado';
	CombatBindingsDisabled = 'Entrando en combate, modo de Atajos de Teclado desactivado';
	BindingsHelp = "Sitúese en un botón, entonces pulse una tecla para establecer su atajo.  Para limpiar el Atajo del botón actual, pulse %s.";

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
	["End"] = "Fin",
	["Home"] = "Ini",
	["Insert"] = "Ins",
	["Mouse Wheel Down"] = "AW",
	["Mouse Wheel Up"] = "RW",
	["Num Lock"] = "NL",
	["Page Down"] = "AP",
	["Page Up"] = "RP",
	["Scroll Lock"] = "SL",
	["Spacebar"] = "Sp",
	["Tab"] = "Tb",

	["Down Arrow"] = "Ar",
	["Left Arrow"] = "Ab",
	["Right Arrow"] = "Iz",
	["Up Arrow"] = "De",
}
setmetatable(LibKeyBoundLocale10, {__index = LibKeyBoundBaseLocale10})
