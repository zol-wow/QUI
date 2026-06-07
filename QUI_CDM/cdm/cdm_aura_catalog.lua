local _, ns = ...

---------------------------------------------------------------------------
-- CDM Aura Catalog
--
-- Pure helpers for catalog-provided aura links. CDMSpellData owns entry
-- assembly; this module owns ability->aura display remaps and linked aura
-- ID attachment rules derived from the Blizzard catalog maps.
---------------------------------------------------------------------------

local CDMAuraCatalog = {}
ns.CDMAuraCatalog = CDMAuraCatalog

local ipairs = ipairs
local select = select
local type = type

local issecretvalue = issecretvalue or function() return false end

local function IsUsableID(id)
    if type(id) ~= "number" then return false end
    if issecretvalue(id) then return false end
    return id > 0
end

function CDMAuraCatalog.HasDirectAuraChild(mirror, spellID)
    if not (mirror and mirror.GetDirectCooldownIDForViewer and IsUsableID(spellID)) then
        return false
    end
    return mirror.GetDirectCooldownIDForViewer(spellID, "buff")
        or mirror.GetDirectCooldownIDForViewer(spellID, "trackedBar")
end

function CDMAuraCatalog.ResolveEntryAuraDisplay(entryID, abilityToAuraSpellID, mirror)
    if not IsUsableID(entryID) then
        return entryID, false
    end

    local mappedID = abilityToAuraSpellID and abilityToAuraSpellID[entryID]
    if IsUsableID(mappedID)
        and not CDMAuraCatalog.HasDirectAuraChild(mirror, entryID) then
        return mappedID, true
    end

    return entryID, false
end

function CDMAuraCatalog.AttachLinkedAuraIDs(resolved, auraIDsForSpell, getAuraIDsForSpell, ...)
    if not resolved then return end

    local out, seen
    local function appendForSpellID(spellID)
        if not IsUsableID(spellID) then return end

        local ids
        if type(getAuraIDsForSpell) == "function" then
            ids = getAuraIDsForSpell(spellID)
        elseif auraIDsForSpell then
            ids = auraIDsForSpell[spellID]
        end
        if type(ids) ~= "table" then return end

        if not out then
            out = {}
            seen = {}
        end
        for _, auraID in ipairs(ids) do
            if IsUsableID(auraID) and not seen[auraID] then
                seen[auraID] = true
                out[#out + 1] = auraID
            end
        end
    end

    for i = 1, select("#", ...) do
        appendForSpellID(select(i, ...))
    end

    if out and #out > 0 then
        resolved.linkedSpellIDs = out
    end
end
