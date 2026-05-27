local Log     = require("helpers.Log")
local Test    = require("helpers.TestUtils")
local Nav     = require("turtle.Nav")
local Inventory = require("turtle.Inventory")
local Inspect = require("turtle.Inspect")

local TEST_CLEANUP    = true
local LOG_CLEANUP     = true

local Turtle = {}

local function initSequence(config)
    Log:startup("Init sequence started.")
    Nav:init(config.HOME_COORDS, config.HOME_HEADING)
    Inventory:init()
    Log:startup("Init sequence completed.")
end

local function shutdown()
    Log:shutdown("Shutdown sequence started.")
    if TEST_CLEANUP then
        Log:shutdown("Cleaning old test files...")
        local cleanTestsOk, _ = Test.clearOldTestFiles()
        if not cleanTestsOk then Log:error("Failed to delete old test files.") end
    end

    if LOG_CLEANUP then
        Log:shutdown("Cleaning old log files...")
        local cleanLogsOk, _ = Log.clearOldLogs()
        if not cleanLogsOk then Log:error("Failed to delete old log files.") end
    end

    Log:shutdown("Shutdown sequence completed, exiting.")
end

local function errorHandler(err)
    return debug.traceback("MAIN: Crashed: " .. tostring(err), 2)
end

function Turtle.run(config, mainLoopFn)
    Log:init(Log.LOG_LEVELS[2])
    initSequence(config)

    local ok, err = xpcall(mainLoopFn, errorHandler)
    if not ok then Log:error(err) end

    shutdown()
end

return Turtle
