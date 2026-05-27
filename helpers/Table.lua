local Log = require("helpers.Log")
local Table = {}

function Table.clone(input)
    if type(input) ~= "table" then Log:error("Input is not a table.") return nil end
    local copy = {}

    for k, v in pairs(input) do
        if type(v) == "table" then
            copy[k] = Table.clone(v)
        else
            copy[k] = v
        end
    end

    return copy
end

function Table.contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

function Table.nameContainsAny(name, needles)
    for _, needle in ipairs(needles) do
        if name:find(needle, 1, true) then
            return true
        end
    end
    return false
end

return Table