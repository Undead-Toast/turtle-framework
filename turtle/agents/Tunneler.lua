local Log = require("helpers.Log")
local Nav = require("turtle.Nav")
local Inspect = require("turtle.Inspect")
local Table = require("helpers.Table")
local Inventory = require("turtle.Inventory")

local Tunneler = {}

local SHOVEL_LIST = {"dirt", "gravel"}
local GRAVITY_BLOCKS = {"sand", "gravel"}

-- DEPRECATED, MOVE THE TOOL LOGIC TO Dig.lua

function Tunneler.useTool(direction, requestedTool)
    local hand = nil
    if Inventory.leftEquip then
        local tool = Inventory.leftEquip.name
        if tool:find(requestedTool, 1, true) then
            hand = "left"
        end
    end

    if Inventory.rightEquip then
        local tool = Inventory.rightEquip.name
        if tool:find(requestedTool, 1, true) then
            hand = "right"
        end
    end

    -- TODO: Check inventory for shovel
    if not hand then Log:fatal("No " .. requestedTool .. " found.") end

    if direction == "U" then
        return turtle.digUp(hand)
    elseif direction == "D" then
        return turtle.digDown(hand)
    else
        return turtle.dig(hand)
    end
end

function Tunneler.toolForBlock(block)
    if Table.nameContainsAny(block.name, SHOVEL_LIST) then
        return "shovel"
    else
        return "pickaxe"
    end
end

function Tunneler.checkForGravityBlock(direction)
    local ok, block = Inspect:inspect(direction)
    if ok and Table.nameContainsAny(block.name, GRAVITY_BLOCKS) then
        return ok
    end
    return nil
end

function Tunneler.digOnce(direction, tool)
    Tunneler.useTool(direction, tool)
end

function Tunneler.digUntilClear(direction, tool)
    while true do
        if Tunneler.checkForGravityBlock() then
            Tunneler.digOnce(direction, tool)
            sleep(1)
        else
            break
        end
    end

    return true
end

function Tunneler.dig(direction)
    local ok, block = Inspect:inspect(direction)
    if not ok then return nil end

    local tool = Tunneler.toolForBlock(block)
    if tool == "shovel" and Tunneler.checkForGravityBlock() then
        return Tunneler.digUntilClear(direction, tool)
    elseif tool == "shovel" then
        return Tunneler.digOnce(direction, tool)
    elseif tool == "pickaxe" then
        return Tunneler.digOnce(direction, tool)
    else
        return nil
    end
end

function Tunneler.moveTo(coords, heading)
    -- Find coord diff
    local currentCoords = Nav.state.coords
    local requestedCoords = coords

    local coordDiff = {
        x = currentCoords[]
    }
end

function Tunneler.tunnel(direction, length, height)
    for _ = 1, length do
        Tunneler.dig(direction)
        Nav:moveBy(direction, 1)
    end
end

function Tunneler.run()
    Log:info("TUNNELER: Starting mission.")

    Tunneler.tunnel("D", 10)
    Tunneler.tunnel("S", 10)

    Log:info("TUNNELER: Returning home.")
    Nav:returnHome()
end

return Tunneler
