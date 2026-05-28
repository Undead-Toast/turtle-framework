local State     = require("helpers.State")
local Log       = require("helpers.Log")
local MoveLog   = require("turtle.subsystem.core.Navigation.MoveLog")

-- TODOS
--  Port Fuel/refuel/maxDistance integration from deprecated Nav into moveBy
--  Refactor Nav -> Navigation in consumers (Tunneler, Inspect, Turtle, startup)
--  Testing
--  Cleanup

-- config
local STATE_FILE = "navigation-state"

-- constants
local CARDINALS = {"N", "E", "S", "W"}

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

-- moveTo config
local RETRY_SLEEP = 0.5 -- seconds to wait between transient retries
local DEFAULT_RETRY_COUNT = 2
local DEFAULT_OBSTACLE_LIMIT = 3
local DEFAULT_AXIS_ORDER = {"X", "Z", "Y"} -- horizontal first, vertical settle

local AXIS_INDEX = { X = 1, Y = 2, Z = 3 }
local AXIS_HEADINGS = {
    X = { pos = "E", neg = "W" },
    Y = { pos = "U", neg = "D" },
    Z = { pos = "S", neg = "N" },
}

local function NOOP() end

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

    -- copy coords so the record owns its own array. Otherwise state and home,
    -- both built from the same hCoords table, would alias -- and recalculate
    -- mutating state.coords would silently drag home.coords along with it.
    return {coords = {coords[1], coords[2], coords[3]}, heading = heading}
end

local function copyCoords(coords)
    return { coords[1], coords[2], coords[3] }
end

-- resolve a caller priority list into a full, de-duplicated axis order;
-- any axis the caller omits is appended using DEFAULT_AXIS_ORDER
local function resolveAxisOrder(priority)
    local order, seen = {}, {}

    if type(priority) == "table" then
        for _, axis in ipairs(priority) do
            local a = type(axis) == "string" and string.upper(axis) or nil
            if a and AXIS_INDEX[a] and not seen[a] then
                order[#order + 1] = a
                seen[a] = true
            end
        end
    end

    for _, axis in ipairs(DEFAULT_AXIS_ORDER) do
        if not seen[axis] then
            order[#order + 1] = axis
            seen[axis] = true
        end
    end

    return order
end

-- build per-axis {heading, dist} legs from current to target coords,
-- skipping axes with no displacement
local function buildLegs(current, target, priority)
    local legs = {}

    for _, axis in ipairs(resolveAxisOrder(priority)) do
        local idx = AXIS_INDEX[axis]
        local delta = target[idx] - current[idx]
        if delta ~= 0 then
            local heading = AXIS_HEADINGS[axis][delta > 0 and "pos" or "neg"]
            legs[#legs + 1] = { heading = heading, dist = math.abs(delta) }
        end
    end

    return legs
end

-- navigation
local Navigation = {
    initialized = false,
    home = nil,
    state = nil,
}

-- Default backout: for now, just head home.
--
-- Defined as Navigation.backout (dot, not colon) because moveBy/moveTo call it
-- as a plain handler(direction, unitsMoved) without passing self. It reaches
-- returnHome through the Navigation upvalue; returnHome is defined lower in the
-- file, which is fine -- Lua resolves the name when this runs, not when it's
-- defined, and a backout can only fire after the module has fully loaded.
--
-- Override per-call via moveBy's onBackout arg or moveTo/init's opts.onBackout.
function Navigation.backout(direction, unitsMoved)
    Log:debug("NAV: Default backout -> returnHome.")
    return Navigation:returnHome()
end

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

-- init sets up navigation. hCoords/hHeading are the home position (a 3-element
-- {x,y,z} table and a cardinal heading) used both as the default starting state
-- when there's no saved state and as the target for returnHome.
-- opts:
--   onBackout  function(direction, unitsMoved); replaces the default backout
--              (which heads home) for the lifetime of this nav instance
--   flush      true to resume from a previous run's move log; false/absent to
--              start fresh and clear stale log pages. Forwarded to MoveLog:init.
-- returns nil on invalid input (missing/malformed hCoords/hHeading with no
-- usable saved state).
function Navigation:init(hCoords, hHeading, opts)
    opts = opts or {}
    Log:startup("NAV: Starting nav initializion.")

    -- if state, use it
    if State.exists(STATE_FILE) then
        local state = State.load(STATE_FILE)
        local valid, _ = validateNavigationState(state)
        if valid then
            self.state = state
            self.initialized = true
            Log:startup("NAV: Initialized with state.")
        else
            Log:error("NAV: Invalid state, initializing with defaults.")
        end
        
    end

    -- else, re-init with defaults
    if not self.initialized then
        if not hCoords or not hHeading then return nil end
        if type(hCoords) ~= "table" then return nil end
        if #hCoords ~= 3 then return nil end
        if not ROTATION_VALUES[hHeading] then return nil end

        -- Init
        self.state = Coordinate(hCoords, hHeading)

        State.save(STATE_FILE, self.state)
        Log:startup("NAV: Initialized with defaults, state reset.")
    end



    -- set backout
    if opts.onBackout then self.backout = opts.onBackout end

    -- set home
    self.home = Coordinate(hCoords, hHeading)

    Log:debug("NAV: HOME: " .. self.home.coords[1] .. "," .. self.home.coords[2] .. "," .. self.home.coords[3])

    -- move log stuff
    local includeFlush = opts.flush or false
    MoveLog:init({flush = includeFlush})

    -- init success
    self.initialized = true
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
function Navigation:moveBy(direction, distance, onBackout)
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
            local handler = onBackout or self.backout
            handler(direction, unitsMoved)
            return false, unitsMoved
        end
    end

    return true, unitsMoved
end


-- moveTo orchestrates moveBy across axes to reach an absolute target.
-- opts:
--   priority      ordered axis list ("X"/"Y"/"Z"); omitted axes appended X,Z,Y
--   onObstacle    function(ctx) -> truthy when resolved; ctx = {heading, remaining, coords, attempt}
--   onBackout     function(heading, remaining); overrides self.backout for this call
--   retryCount    transient retries per obstacle position (default 2)
--   obstacleLimit max onObstacle escalations per leg (default 3)
--   endDirection  optional final cardinal to rotateTo
-- returns true, {coords, heading} on success
--         false, {coords, blockedHeading, remaining} when backed out
--         nil on invalid input
--
-- FUTURES: sidestep opt -- default pathfinding before onObstacle escalation
function Navigation:moveTo(coords, opts)
    opts = opts or {}

    -- validate target
    if type(coords) ~= "table" or #coords ~= 3 then return nil end
    for i = 1, 3 do
        if type(coords[i]) ~= "number" then return nil end
    end

    -- endDirection, if given, must be a cardinal (rotateTo rejects U/D)
    local endDirection = opts.endDirection
    if endDirection ~= nil and not ROTATION_VALUES[endDirection] then return nil end

    local retryCount    = opts.retryCount    or DEFAULT_RETRY_COUNT
    local obstacleLimit = opts.obstacleLimit or DEFAULT_OBSTACLE_LIMIT
    local backout       = opts.onBackout     or self.backout
    local onObstacle    = opts.onObstacle

    -- back out, then report where and why we stopped
    local function blocked(heading, remaining)
        backout(heading, remaining)
        return false, {
            coords         = copyCoords(self.state.coords),
            blockedHeading = heading,
            remaining      = remaining,
        }
    end

    local legs = buildLegs(self.state.coords, coords, opts.priority)

    for _, leg in ipairs(legs) do
        local remaining     = leg.dist
        local retries       = 0
        local obstacleCalls = 0

        while remaining > 0 do
            -- suppress moveBy's own backout so we own the retry policy
            local ok, moved = self:moveBy(leg.heading, remaining, NOOP)
            remaining = remaining - (moved or 0)

            if ok then break end -- leg complete

            if moved and moved > 0 then retries = 0 end -- progress => new obstacle

            if retries < retryCount then
                retries = retries + 1
                sleep(RETRY_SLEEP)
            elseif obstacleCalls >= obstacleLimit then
                return blocked(leg.heading, remaining) -- escalation ceiling hit
            else
                obstacleCalls = obstacleCalls + 1
                local resolved = onObstacle and onObstacle({
                    heading   = leg.heading,
                    remaining = remaining,
                    coords    = copyCoords(self.state.coords),
                    attempt   = retries,
                })

                if resolved then
                    retries = 0 -- hook cleared it; resume moving
                else
                    return blocked(leg.heading, remaining)
                end
            end
        end
    end

    -- optional final rotation
    if endDirection and not self:rotateTo(endDirection) then
        return false, {
            coords         = copyCoords(self.state.coords),
            blockedHeading = endDirection,
            remaining      = 0,
        }
    end

    return true, {
        coords  = copyCoords(self.state.coords),
        heading = self.state.heading,
    }
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
-- retrace walks the MoveLog backwards, inverting each segment, and trims the
-- unwound steps off the tail of the log as it goes. `steps` caps how many
-- unit-steps to unwind (default: the whole log).
--
-- The trail is a path the turtle already traversed, so a blocked move is treated
-- as transient (a wandering mob, settling gravel): it retries opts.retryCount
-- times (default 2) with a short sleep before giving up. opts.onBackout passes
-- through to moveBy.
--
-- Returns true, unwound on success, or
-- false, {unwound, blockedHeading, remaining, reason} if a segment stays blocked.
function Navigation:retrace(steps, opts)
    opts = opts or {}
    if steps ~= nil and (type(steps) ~= "number" or steps < 0) then return nil end

    local retryCount = opts.retryCount or DEFAULT_RETRY_COUNT

    local remaining = steps -- nil means "until the log is empty"
    local unwound = 0
    local retries = 0

    MoveLog:pause() -- don't re-log the reverse trip

    while remaining == nil or remaining > 0 do
        local entry = MoveLog:peekTail() -- newest segment, hydrating a page if needed
        if not entry then break end -- trail exhausted

        local take = entry.count
        if remaining ~= nil and remaining < take then take = remaining end

        local inverse = INVERSE_HEADING[entry.direction]
        local ok, moved = self:moveBy(inverse, take, opts.onBackout)
        moved = moved or 0

        MoveLog:trimTail(moved) -- trim exactly what we actually moved
        unwound = unwound + moved
        if remaining ~= nil then remaining = remaining - moved end

        if ok then
            retries = 0
        else
            if moved > 0 then retries = 0 end -- progress => transient cleared, reset
            if retries < retryCount then
                retries = retries + 1
                sleep(RETRY_SLEEP) -- wait out a mob / settling gravel, then retry
            else
                MoveLog:resume()
                return false, {
                    unwound        = unwound,
                    blockedHeading = inverse,
                    remaining      = remaining,
                    reason         = "blocked",
                }
            end
        end
    end

    MoveLog:resume()
    return true, unwound
end

-- returnHome walks the turtle back to self.home along the recorded trail -- the
-- path it actually carved, and therefore the only path we *know* is clear. It
-- never travels blind (no moveTo straight-lining through unmined rock).
--
-- It retraces the whole log, then verifies it truly arrived: if the log ran out
-- before home (resumed shallow, or a prior retrace trimmed it), it stops and
-- reports rather than guessing. opts.retryCount tunes the transient-obstacle
-- retries on the way back.
--
-- opts.fallback (opt-in): if the safe trail fails -- blocked after retries, or
-- it runs out short of home -- fall back to moveToHome (the blind direct line)
-- as a last resort. Off by default, so the strict safe-only guarantee holds
-- unless a caller asks for it.
--
-- Returns true, {coords, heading} on arrival;
--         false, {reason, ...} if the trail fails and fallback is off/also fails.
--
-- NOTE: without fallback this only reaches home if the log holds an unbroken
-- trail back to it. v2 (see docs/plans) adds checkpointed per-segment path
-- optimization to prune wasted back-and-forth; for now the return replays the trail.
function Navigation:returnHome(opts)
    if not self.home then return nil end
    opts = opts or {}

    -- safe return: reverse the known trail. onBackout is forced to NOOP so a
    -- blocked move can't invoke the default backout (= returnHome) and recurse.
    local ok, result = self:retrace(nil, {
        onBackout  = NOOP,
        retryCount = opts.retryCount,
    })

    -- did the safe trail land us exactly home?
    local home, at = self.home.coords, self.state.coords
    local atHome = ok and at[1] == home[1] and at[2] == home[2] and at[3] == home[3]

    if atHome then
        self:rotateTo(self.home.heading) -- retrace restores position, not facing
        return true, {
            coords  = copyCoords(self.state.coords),
            heading = self.state.heading,
        }
    end

    -- safe path didn't get us home: blocked (result holds detail) or trail ran short
    local info = ok and { reason = "incomplete trail", coords = copyCoords(at) } or result

    -- opt-in blind fallback: try the direct moveTo line as a last resort
    if opts.fallback then
        Log:warn("NAV: returnHome trail failed (" .. tostring(info.reason) .. "), falling back to moveToHome.")
        return self:moveToHome(opts)
    end

    return false, info
end

-- moveToHome is the fast, blind counterpart to returnHome: it heads straight to
-- self.home via moveTo (net per-axis displacement), which collapses any
-- back-and-forth automatically but does NOT stay on the carved trail -- moveBy
-- can't dig, so a direct line through unmined rock will fail. Use it only when
-- the path home is known clear (open terrain) or the caller can clear it.
-- Prefer returnHome for the guaranteed-safe path.
--
-- opts pass straight through to moveTo (priority, onObstacle, retryCount, ...);
-- endDirection defaults to home's heading.
-- Returns moveTo's result: true, {coords, heading} / false, {...} / nil.
function Navigation:moveToHome(opts)
    if not self.home then return nil end

    opts = opts or {}
    if opts.endDirection == nil then opts.endDirection = self.home.heading end
    -- suppress backout: a blocked direct path shouldn't silently fall back into
    -- the default backout (returnHome). Let moveTo fail and report; the caller
    -- can choose to returnHome instead.
    if opts.onBackout == nil then opts.onBackout = NOOP end

    return self:moveTo(self.home.coords, opts)
end

function Navigation:shutdown()
    MoveLog:shutdown()
end

return Navigation
