local State = require("helpers.State")
local Fuel = require("turtle.Fuel")
local Log = require("helpers.Log")
local File = require("helpers.File")

-- TODOS
--  clearStaleFlush
--  rehashFlush
--  





-- config
local STATE_FILE = "navigation-state"
local FLUSH_DIR = "/data/flush/movelog/"

local MOVE_LIMIT_BEFORE_FLUSH = 200

-- constants
local CARDINALS = {"N", "E", "S", "W"}
local HEADINGS = {"N", "E", "S", "W", "U", "D"} -- might not use

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

-- helper
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

-- move log
local MoveLog = {
    runHash = nil,
    moves = {},
    pages = {},
}

function MoveLog.generateNextFlushFile()
    local flushDir = File.ensureDir(FLUSH_DIR)
    if not flushDir then Log:fatal("Could not find or create flush directory.") end

    return (#MoveLog.pages + 1) .. "-" .. MoveLog.runHash .. ".txt"
end

function MoveLog:init(opts)
    self.runHash = File.generateRandomFileId() -- random hash kinda for the most part
    if opts.flush then
        
    end
end

function MoveLog:flush()
    if #self.moves == 0 then return true end
    local flushFile = self.generateNextFlushFile()
    self.pages[#self.pages+1] = flushFile

    local filePath = FLUSH_DIR .. flushFile
    
    local file = fs.open(filePath, "a") -- using fs instead of File due to continuous write
    if not file then return false, "could not open " .. filePath .. " for appending" end

    -- move to disk
    local moves = self.moves
    for i = 1, #moves do
        local serialized = textutils.serialize(moves[i], {compact = true})
        file.writeLine(serialized)
    end

    file.close()
    -- flush
    self.moves = {}
    Log:debug("NAV: Flushed.")
    return true, flushFile
end

-- remove old runs
function MoveLog:clearStaleFlush()
end

-- rehash old run files into new
function MoveLog:rehashFlush()
end

function MoveLog:recordMove(dir)
    -- check flush
    if #self.moves >= MOVE_LIMIT_BEFORE_FLUSH then
        self:flush()
    end

    local moves = self.moves
    Log:debug(moves)

    -- if any moves prior, check direction
    if #moves >= 1 then
        local lastMove = moves[#moves]
        local lastDir = lastMove.direction
        if dir == lastDir then
            local lastVal = lastMove.count
            self.moves[#moves].count = lastVal + 1
            return true
        end
    end

    local payload = {direction = dir, count = 1}
    local index = #moves or 0
    self.moves[index + 1] = payload

    return true
end

function MoveLog:read(amount, opts)
    opts = opts or {}
    if not amount or amount <= 0 then return nil end

    local result = {}
    local count = 0

    -- in-memory first (newest)
    for i = #self.moves, 1, -1 do
        if count >= amount then break end
        count = count + 1
        result[count] = self.moves[i]
    end

    -- if we hit the cap or don't want flush, stop here
    if count >= amount or not opts.flush then
        if count == 0 then return nil end
        return result
    end

    -- pages from newest to oldest
    for i = #self.pages, 1, -1 do
        if count >= amount then break end

        local path = FLUSH_DIR .. self.pages[i]
        local content = File.readLines(path)
        if not content then
            Log:fatal("NAV: Failed to read flush file " .. path)
        end

        for j = #content, 1, -1 do
            if count >= amount then break end
            local move = textutils.unserialize(content[j])
            if move then
                count = count + 1
                result[count] = move
            end
        end
    end

    if count == 0 then return nil end
    return result
end

function MoveLog:readAll(opts)
    opts = opts or {}
    local result = {}
    local count = 0

    -- in-memory first (newest)
    for i = #self.moves, 1, -1 do
        count = count + 1
        result[count] = self.moves[i]
    end

    if not opts.flush or #self.pages == 0 then
        return result
    end

    -- pages from newest to oldest
    for i = #self.pages, 1, -1 do
        local path = FLUSH_DIR .. self.pages[i]
        local content = File.readLines(path)

        if not content then
            Log:fatal("NAV: Failed to read flush file " .. path)
        end

        if #content == 0 then
            Log:warn("NAV: Empty flush file.")
        end

        for j = #content, 1, -1 do
            local move = textutils.unserialize(content[j])
            if move then
                count = count + 1
                result[count] = move
            end
        end
    end

    return result
end

function MoveLog:shutdown()
end

-- navigation defaults
local function backout()
    Log:debug("Default backout, no-op.")
end

-- navigation
local Navigation = {
    initialized = false,
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

    -- if state, use it
    if State.exists(STATE_FILE) then
        local state = State.load(STATE_FILE)
        local valid, _ = validateNavigationState(state)
        if valid then
            self.state = state

            Log:startup("NAV: Initialized with state.")
        else
            Log:error("NAV: Invalid state, initializing with defaults.")
        end
    end

    -- else, re-init with defaults
    if not self.initialized then
        if not hCoords or not hHeading then return nil end
        if type(hCoords) ~= "table" then return nil end
        if #hCoords ~= 3 then print("3") return nil end
        if not ROTATION_VALUES[hHeading] then return nil end

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
    local includeFlush = opts.flush or false
    MoveLog:init({flush = includeFlush})

    -- init success
    self.init = true
end

function Navigation:recalculate(heading)
    local coords = self.state.coords

    if heading == "N" then
        coords[3] = coords[3] - 1
    elseif heading == "E" then
        coords[1] = coords[1] + 1
    elseif heading == "S" then
        coords[3] = coords[3] + 1
    elseif heading == "W" then
        coords[1] = coords[1] - 1
    elseif heading == "U" then
        coords[2] = coords[2] + 1
    elseif heading == "D" then
        coords[2] = coords[2] - 1
    else
        return false
    end

    State.save(STATE_FILE, self.state)

    Log:debug("NAV: Move to " .. coords[1] .. "," .. coords[2] .. "," .. coords[3] .. " : " .. heading)
    return true
end

-- movement
function Navigation:moveBy(direction, distance, backout)
    if not direction or not distance then return nil end
    if not VALID_HEADINGS[direction] then return nil end
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
            MoveLog:recordMove(direction)
            self:recalculate(direction)
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

    if cwDistance == 0 then return true end

    local rotated = false

    if cwDistance == 1 then
        rotated = turtle.turnRight()
    elseif cwDistance == 2 then
        rotated = turtle.turnLeft()
        if not rotated then
            Log:error("NAV: Failed to rotate")
            return false
        end
        -- persist intermediate heading so a failure on the second turn leaves state consistent
        self.state.heading = CARDINALS[((cHeadingValue - 2) % 4) + 1]
        State.save(STATE_FILE, self.state)
        rotated = turtle.turnLeft()
    elseif cwDistance == 3 then
        rotated = turtle.turnLeft()
    end

    if rotated then
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