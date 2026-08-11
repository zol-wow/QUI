local ADDON_NAME, ns = ...

function ns.Unpack(packed, chunkname)
    local chunk, err = loadstring("return " .. packed, chunkname)
    if not chunk then
        error(("ns.Unpack: %s: %s"):format(tostring(chunkname), tostring(err)), 0)
    end
    local result = chunk()
    if type(result) ~= "table" then
        error(("ns.Unpack: %s: payload did not evaluate to a table (got %s)")
            :format(tostring(chunkname), type(result)), 0)
    end
    return result
end
