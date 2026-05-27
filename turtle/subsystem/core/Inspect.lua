local Nav = require("turtle.Nav")
local Log = require("helpers.Log")

local Inspect = {
    blocks = {
        ["N"] = nil,
        ["E"] = nil,
        ["S"] = nil,
        ["W"] = nil,
        ["U"] = nil,
        ["D"] = nil,
    }
}

function Inspect:inspect(direction)
    if direction == "U" then
        return Inspect:up()
    elseif direction == "D" then
        return Inspect:down()
    else
        Nav:rotateToHeading(direction)
        return Inspect:forward()
    end
end

function Inspect:forward()
    local ok, block = turtle.inspect()
    if ok then
        self.blocks[Nav.state.heading] = block
        Log:debug("INSPECT: Block: " .. block.name .. ", Heading: " .. Nav.state.heading)
    end

    return ok, block
end

function Inspect:right()
    Nav:rotateRight()
    return self:forward()
end

function Inspect:left()
    Nav:rotateLeft()
    return self:forward()
end

function Inspect:up()
    local ok, block = turtle.inspectUp()
    if ok then
        self.blocks["U"] = block
        Log:debug("INSPECT: Block: " .. block.name .. ", Heading: U")
    end
    return ok, block
end

function Inspect:down()
    local ok, block = turtle.inspectDown()
    if ok then
        self.blocks["D"] = block
        Log:debug("INSPECT: Block: " .. block.name .. ", Heading: D")
    end
    return ok, block
end

function Inspect:inspectAll()
    for i = 1, 4 do
        self:left()
    end
    self:up()
    self:down()
    return true, self.blocks
end

return Inspect