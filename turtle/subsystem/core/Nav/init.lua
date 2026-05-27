local State = require("helpers.State")
local Log = require("helpers.Log")
local MoveLog = require("turtle.Nav.MoveLog")
local Fuel = require("turtle.Fuel")

local Nav = {
    HEADINGS = {"N", "E", "S", "W"},
    VALID_HEADINGS = {
        ["N"]=true,
        ["E"]=true,
        ["S"]=true,
        ["W"]=true,
        ["U"]=true,
        ["D"]=true,
    },
    ROTATION_VALUES = {
        ["N"] = 1,
        ["E"] = 2,
        ["S"] = 3,
        ["W"] = 4
    },
    maxDistance = 0,
    distanceBeforeRefill = 0,
    refillIncrements = 0,
    home = {
        coords = {0,0,0},
        heading = nil,
    },
    state = {
        coords = {0,0,0},
        heading = nil,
    }
}

local INVERSE_HEADING = {
    N = "S", S = "N",
    E = "W", W = "E",
    U = "D", D = "U",
}

local RETRACE_RETRY_LIMIT = 3
local RETRACE_RETRY_DELAY = 1.0

local STATE_FILE = "nav"

function Nav:validateState(data)
    if type(data) ~= "table" then return false, "state is not a table" end
    if type(data.coords) ~= "table" then return false, "coords is not a table" end
    if #data.coords ~= 3 then return false, "coords must have exactly 3 elements" end

    for i = 1, 3 do
        if type(data.coords[i]) ~= "number" then
            return false, "coords[" .. i .. "] is not a number"
        end
    end

    if type(data.heading) ~= "string" then return false, "heading is not a string" end

    if not self.ROTATION_VALUES[data.heading] then
        return false, "heading '" .. tostring(data.heading) .. "' is not a valid cardinal"
    end

    return true
end

function Nav:requestFuel()
    if self.distanceBeforeRefill <= 0 then
        Log:info("NAV: Requested refuel.")
        local refueled = Fuel.refuelMax()
        if refueled == 0 then
            Log:warn("NAV: No units refueled, requesting at next increment.")
            self.distanceBeforeRefill = self.refillIncrements
            return nil
        end

        self.maxDistance = Fuel.calculateMaxDistance()
        self.refillIncrements = math.floor(self.maxDistance / 4)
        self.distanceBeforeRefill = self.refillIncrements

        Log:info("NAV: Max distance: " .. self.maxDistance .. ", Next refuel: " .. self.refillIncrements)
        return refueled
    end
end

function Nav:init(coords, heading)
    Log:startup("NAV: Starting nav initializion.")

    Log:startup("NAV: Cleaning old movelog files...")
    local cleanOk = MoveLog.clearOldMoveLog()
    if not cleanOk then Log:error("NAV: Failed to delete old movelog files.") end

    local init = false

    if State.exists(STATE_FILE) then
        local state = State.load(STATE_FILE)
        local valid, err = self:validateState(state)
        if valid then
            self.state = state

            Log:startup("NAV: Initialized with state.")
            init = true
        else
            Log:warn("NAV: Invalid state, initializing with defaults.")
        end
    end

    if not init then
        if not coords or not heading then return nil end
        if type(coords) ~= "table" then return nil end
        if #coords ~= 3 then print("3") return nil end
        if not self.ROTATION_VALUES[heading] then return nil end

        -- Init
        self.state.coords = coords
        self.state.heading = heading

        State.save(STATE_FILE, self.state)
        Log:startup("NAV: Initialized with defaults, state reset.")
        init = true
    end

    self.home.coords = coords
    self.home.heading = heading

    local refuel = Nav:requestFuel()
    if not refuel then
        self.maxDistance = Fuel.calculateMaxDistance()
        self.refillIncrements = math.floor(self.maxDistance / 4)
        self.distanceBeforeRefill = self.refillIncrements
    end

    local initMoveLogPayload = {
        x = self.state.coords[1],
        y = self.state.coords[2],
        z = self.state.coords[3],
        h = self.state.heading,
    }
    local ok, file = MoveLog:init(initMoveLogPayload)

    if ok then
        Log:startup("NAV: Nav init successful.")
        return true, file
    else
        Log:fatal("Nav: Failed to init MoveLog.")
    end
end

function Nav:recalcCoords(heading, units)
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

    -- Save movelog
    local moveLogPayload = {
        move = heading,
        x = Nav.state.coords[1],
        y = Nav.state.coords[2],
        z = Nav.state.coords[3],
        h = Nav.state.heading,
    }
    MoveLog:save(moveLogPayload)

    self.maxDistance = self.maxDistance - 1
    if self.distanceBeforeRefill <= 0 then
        Log:info("NAV: Requested refuel.")
        local refueled = Fuel.refuelMax()
        if refueled == 0 then
            Log:warn("NAV: Refuel attempt failed, requesting at next increment.")
        end
        Log:info("NAV: Refuel request successful, refueled " .. refueled .. " units.")
        self.maxDistance = Fuel.calculateMaxDistance()
    end

    -- Save state
    State.save(STATE_FILE, self.state)

    Log:debug("NAV: Move to " .. coords[1] .. "," .. coords[2] .. "," .. coords[3] .. " : " .. heading)
    return true
end

function Nav:rotateToHeading(targetHeading)
    if targetHeading == "D" or targetHeading == "U" then return nil end
    if not targetHeading then return nil end

    local cHeadingValue = self.ROTATION_VALUES[self.state.heading]
    local tHeadingValue = self.ROTATION_VALUES[targetHeading]

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
        MoveLog:save({rotated = targetHeading})

        self.state.heading = targetHeading
        State.save(STATE_FILE, self.state)
        Log:debug("NAV: Rotated to heading: " .. targetHeading)
    end

    return rotated
end

function Nav:rotateLeft()
    -- Need to get current cardinal
    local heading = self.state.heading
    local headingValue = self.ROTATION_VALUES[heading]
    local leftHeadingValue = ((headingValue - 2) % 4) + 1

    return self:rotateToHeading(self.HEADINGS[leftHeadingValue])
end

function Nav:rotateRight()
    local heading = self.state.heading
    local headingValue = self.ROTATION_VALUES[heading]
    local rightHeadingValue = (headingValue % 4) + 1

    return self:rotateToHeading(self.HEADINGS[rightHeadingValue])
end

function Nav:spinLeft()
    for _ = 1, 4 do
        self:rotateLeft()
    end
end

function Nav:spinRight()
    for _ = 1, 4 do
        self:rotateRight()
    end
end

-- Returns: nil on invalid input; false, n on partial failure; true, n on success
function Nav:moveBy(heading, units)
    -- Bad inputs
    if not heading or not units then return nil end
    if not self.VALID_HEADINGS[heading] then return nil end
    if type(units) ~= "number" then return nil end
    if units < 0 then return nil end

    local unitsMoved = 0;
    local moveFn = turtle.forward
    if heading == "U" then moveFn = turtle.up
    elseif heading == "D" then moveFn = turtle.down
    else
        local rotated = self:rotateToHeading(heading)
        if not rotated then return false, 0 end
    end

    for i = 1, units do
        if self.maxDistance <= 0 then
            Log:warn("Max distance from home, returning...")
            self:returnHome()
            break
        else
            if moveFn() then
                self:recalcCoords(heading, 1)
                unitsMoved = i
                self.maxDistance = self.maxDistance - 1
            else
                return false, unitsMoved
            end
        end

    end

    return true, unitsMoved
end

function Nav:moveTo(coords)
    print("TODO")
end

function Nav:returnHome()
    -- 1. PLAN
    local entries = MoveLog:readAll()
    local inverses = {}
    for i = #entries, 1, -1 do
        local entry = entries[i]
        if entry.retrace then
            break
        elseif entry.move then
            inverses[#inverses + 1] = INVERSE_HEADING[entry.move]
        end
        -- rotated entries and the init-position entry fall through (skip)
    end

    Log:info("NAV: Retrace plan: " .. #inverses .. " inverse moves.")

    MoveLog:save({retrace = true})
    MoveLog.suppress = true

    for i, dir in ipairs(inverses) do
        local attempt = 0
        local ok = false
        while not ok do
            ok = self:moveBy(dir, 1)
            if not ok then
                attempt = attempt + 1
                if attempt >= RETRACE_RETRY_LIMIT then
                    MoveLog.suppress = false
                    Log:error("NAV: Retrace bailed on step " .. i .. "/" .. #inverses .. " (" .. dir .. ")")
                    return false, {
                        remaining = #inverses - i + 1,
                        lastCoords = self.state.coords,
                        reason = "blocked",
                    }
                end
                Log:debug("NAV: Retrace blocked on " .. dir .. ", retry " .. attempt)
                sleep(RETRACE_RETRY_DELAY)
            end
        end
    end

    MoveLog.suppress = false
    self:rotateToHeading(self.home.heading)

    Log:info("NAV: returnHome complete.")
    return true
end

return Nav
