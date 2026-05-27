local State = require("helpers.State")
local Fuel = require("turtle.Fuel")
local Log = require("helpers.Log")
local File = require("helpers.File")





-- config
local STATE_FILE = "navigation-state"
local FLUSH_DIR = "/data/flush/movelog"

local MOVE_LIMIT_BEFORE_FLUSH = 200

-- constants
local CARDINALS = {"N", "E", "S", "W"}
local HEADINGS = {"N", "E", "S", "W", "U", "D"}

local ROTATION_VALUES = {
    ["N"] = 1,
    ["E"] = 2,
    ["S"] = 3,
    ["W"] = 4,
}

local VALID_HEADINGS = {
    ["N"]=true,
    ["E"]=true,
    ["S"]=true,
    ["W"]=true,
    ["U"]=true,
    ["D"]=true,
}

local INVERSE_HEADING = {
    N = "S", S = "N",
    E = "W", W = "E",
    U = "D", D = "U",
}

-- move log
local MoveLog = {
    runHash = nil,
    moves = {},
    flush = {
        pages = nil,
    },
}

local function Coordinate(coords, heading)
    if type(coords) ~= "table" then return false, "coords is not a table" end
    if #coords ~= 3 then return false, "coords must have exactly 3 elements" end

    for i = 1, 3 do
        if type(coords[i]) ~= "number" then
            return false, "coords[" .. i .. "] is not a number"
        end
    end

    if not VALID_HEADINGS[heading] then return false, "Not a valid heading" end

    return {coords = coords, heading = heading}
end

function MoveLog.generateNextFlushFile()
    local flushDir = File.ensureDir(FLUSH_DIR)
    -- ensure flush dir
    -- generate file id - #pages + 1 .. self.runHash
    -- create file
    -- return filename
end

function MoveLog:init()
    self.runHash = File.generateRandomFileId() -- random hash kinda for the most part
end

function MoveLog:recordMove(dir)
    -- check move size
    -- if full
        -- generate next flush file
        -- add it to flush.pages
        -- 
end

function MoveLog:recordRotation(targetHeading)

end

function MoveLog:readAll()
end

function MoveLog:flush()
    -- generateNextFlushFile
    -- for each move:
        -- write move
        -- pop from array? or set moves to {}?
    
end

function MoveLog:clearFlush()
end

function MoveLog:rehashFlush()
end

function MoveLog:shutdown()
end

-- navigation defaults
local function backout()
    Log:debug("Default backout, no-op.")
end

-- navigation
local Navigation = {
    init = false,
    backout = backout,
    home = nil,
    state = nil,
}

local function validateNavigationState(data)
    -- coord checks
    if type(data) ~= "table" then return false, "state is not a table" end
    if type(data.coords) ~= "table" then return false, "coords is not a table" end
    if #data.coords ~= 3 then return false, "coords must have exactly 3 elements" end

    for i = 1, 3 do
        if type(data.coords[i]) ~= "number" then
            return false, "coords[" .. i .. "] is not a number"
        end
    end

    -- heading checks
    if type(data.heading) ~= "string" then return false, "heading is not a string" end

    if not ROTATION_VALUES[data.heading] then
        return false, "heading '" .. tostring(data.heading) .. "' is not a valid cardinal"
    end

    return true
end

function Navigation:init(hCoords, hHeading, opts)
    Log:startup("NAV: Starting nav initializion.")

    -- if state, use it. else, re-init with defaults
    if State.exists(STATE_FILE) then
        local state = State.load(STATE_FILE)
        local valid, err = validateNavigationState(state)
        if valid then
            self.state = state

            Log:startup("NAV: Initialized with state.")
        else
            Log:error("NAV: Invalid state, initializing with defaults.")
        end
    end

    if not self.init then
        if not hCoords or not hHeading then return nil end
        if type(hCoords) ~= "table" then return nil end
        if #hCoords ~= 3 then print("3") return nil end
        if not self.ROTATION_VALUES[hHeading] then return nil end

        -- Init
        self.state = Coordinate(hCoords, hHeading)

        State.save(STATE_FILE, self.state)
        Log:startup("NAV: Initialized with defaults, state reset.")
    end

    -- set backout
    if opts and opts.backout then self.backout = opts.backout end

    -- set home
    self.home = Coordinate(hCoords, hHeading)

    -- move log stuff
    MoveLog:init()

    -- init success
    self.init = true
end

function Navigation:recalculate(heading, units)
    local coords = self.state.coords

    if heading == "N" then
        coords[3] = coords[3] - units
    elseif heading == "E" then
        coords[1] = coords[1] + units
    elseif heading == "S" then
        coords[3] = coords[3] + units
    elseif heading == "W" then
        coords[1] = coords[1] - units
    elseif heading == "U" then
        coords[2] = coords[2] + units
    elseif heading == "D" then
        coords[2] = coords[2] - units
    else
        return false
    end

    -- Move Log

    -- Save state
    State.save(STATE_FILE, self.state)
    
    Log:debug("NAV: Move to " .. coords[1] .. "," .. coords[2] .. "," .. coords[3] .. " : " .. heading)
    return true
end

-- move
-- direction - N,E,S,W,U,D
-- units - distance
-- backout(optional) - what to do if cannot complete
function Navigation:moveBy(direction, distance, backout)
    if not direction or not distance then return nil end
    if not self.VALID_HEADINGS[direction] then return nil end
    if type(distance) ~= "number" then return nil end
    if distance < 0 then return nil end

    local unitsMoved = 0;
    local moveFn = turtle.forward
    if direction == "U" then moveFn = turtle.up
    elseif direction == "D" then moveFn = turtle.down
    else
        local rotated = self:rotateTo(direction)
        if not rotated then return false, 0 end
    end

    for i = 1, distance do
        if moveFn() then
            self:recalculate(direction, 1)
            unitsMoved = i
        else
            local handler = backout or self.backout
            handler(direction, unitsMoved)
            return false, unitsMoved
        end
    end

    return true, unitsMoved

end

function Navigation:moveTo(coords, endDirection, opts)
    Log:debug("TODO")
end

-- rotate
function Navigation:rotateTo(targetCardinal)
    if not targetCardinal then return nil end
    if targetCardinal == "D" or targetCardinal == "U" then return nil end

    local cHeadingValue = ROTATION_VALUES[self.state.heading]
    local tHeadingValue = ROTATION_VALUES[targetCardinal]

    local cwDistance = (tHeadingValue - cHeadingValue) % 4

    local rotated = false

    if cwDistance == 1 then
        rotated = turtle.turnRight()
    elseif cwDistance == 2 then
        rotated = turtle.turnLeft()
        if rotated then
            rotated = turtle.turnLeft()
        else
            print("Failed to rotate")
            return false
        end
    elseif cwDistance == 3 then
        rotated = turtle.turnLeft()
    else
        return true
    end

    if rotated then
        MoveLog:save({rotated = targetCardinal})

        self.state.heading = targetCardinal
        State.save(STATE_FILE, self.state)
        Log:debug("NAV: Rotated to heading: " .. targetCardinal)
    end

    return rotated
end

-- returns
function Navigation:retrace()
end

function Navigation:returnHome()
end

return Navigation