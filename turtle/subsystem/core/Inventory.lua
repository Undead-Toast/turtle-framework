local Log = require("helpers.Log")

local Inventory = {
    currentSlot = nil,
    leftEquip = nil,
    rightEquip = nil,
    inventory = {},
}

function Inventory.equipLeft()
end

function Inventory.equipRight()
end

function Inventory.getLeftEquip()
end

function Inventory.getRightEquip()
    
end

function Inventory.contains()

end

function Inventory.getNextFreeSlot()

end

function Inventory.consolidate()

end

function Inventory.select()
    
end

function Inventory.selectSlot()

end

function Inventory:init()
    self.leftEquip = turtle.getEquippedLeft()
    self.rightEquip = turtle.getEquippedRight()
    
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item then
            self.inventory[i] = item
        else
            self.inventory[i] = "_"
        end
        
    end

    turtle.select(1)
    self.currentSlot = 1
end

return Inventory