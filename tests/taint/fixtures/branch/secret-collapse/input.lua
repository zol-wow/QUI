local x = C_Spell.GetSpellCharges(1)
if issecretvalue(x) then
    return true
end
return x
