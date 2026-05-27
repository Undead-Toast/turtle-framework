local Log = require("helpers.Log")

local Fuel = {
    MAX_REFUEL = turtle.getFuelLimit(),
    fuelTypes = {
        ["minecraft:coal"] = 80,
        ["minecraft:charcoal"] = 80
    }
}

function Fuel.calculateMaxDistance()
    local fuelLevel = turtle.getFuelLevel()
    if  fuelLevel == 0 or fuelLevel == 1 then
        return 0
    else
        return math.floor(fuelLevel / 2)
    end
end

function Fuel.calculateMaxRefuel(item)
    if not Fuel.fuelTypes[item.name] then
        return nil
    end

    local perItemUnit = Fuel.fuelTypes[item.name]
    local availableUnits = Fuel.MAX_REFUEL - turtle.getFuelLevel()
    local maxItemRefuel = item.count * perItemUnit

    if maxItemRefuel <= availableUnits then
        return item.count
    else
        return math.floor(availableUnits / perItemUnit)
    end
end

function Fuel.selectNextRefuelItem()
    for i = 1, 16 do
        local sItem = turtle.getItemDetail(i)
        if sItem and Fuel.fuelTypes[sItem.name] then
            turtle.select(i)
            return sItem, i
        end
    end
    return nil
end

function Fuel.calculateAllItemFuelUnits()
    local total = 0;
    for i = 1, 16 do
        local sItem = turtle.getItemDetail(i)
        if sItem and Fuel.fuelTypes[sItem.name] then
            local perItemUnits = Fuel.fuelTypes[sItem.name]
            local stackTotal = sItem.count * perItemUnits
            total = total + stackTotal
        end
    end

    return total
end

function Fuel.refuel()
    Log:info("FUEL: Starting refuel.")
    local fuel = Fuel.selectNextRefuelItem()
    if not fuel then
        return nil
    end

    Log:info("FUEL: Refueling with " .. fuel.name)
    local refuelAmount = Fuel.calculateMaxRefuel(fuel)
    local perItemUnit = Fuel.fuelTypes[fuel.name]

    if not refuelAmount or refuelAmount == 0 then
        Log:error("FUEL: Cannot refuel, manual intervention required.")
        return nil
    end
    
    turtle.refuel(refuelAmount)

    local refilledUnits = refuelAmount * perItemUnit
    Log:info("FUEL: Refuel complete. Refueled " .. refilledUnits .. " units.")
    Log:info("FUEL: Fuel remaining: " .. turtle.getFuelLevel())
    return refilledUnits
end

function Fuel.refuelMax()
    Log:info("FUEL: Starting MAX refuel.")
    
    if not Fuel.selectNextRefuelItem() then
        Log:warn("FUEL: No fuel detected, skipping refuel.")
        return nil
    end

    local refilledUnits = 0

    while true do
        local fuel = Fuel.selectNextRefuelItem()

        if not fuel or Fuel.MAX_REFUEL == turtle.getFuelLevel() then
            break
        end

        local refuelAmount = Fuel.calculateMaxRefuel(fuel)
        local perItemUnit = Fuel.fuelTypes[fuel.name]

        if not refuelAmount or refuelAmount == 0 then
            Log:error("FUEL: Cannot refuel, manual intervention required.")
            return nil
        end
        
        turtle.refuel(refuelAmount)

        refilledUnits = refilledUnits + (refuelAmount * perItemUnit)
        sleep(0.3)
    end

    if refilledUnits ~= 0 then
        Log:info("FUEL: Refuel request successful, refueled " .. refilledUnits .. " units.")
    end
    
    Log:info("FUEL: Fuel remaining: " .. turtle.getFuelLevel())

    return refilledUnits 
end

return Fuel