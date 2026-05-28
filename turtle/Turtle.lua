local Log           = require("helpers.Log")
local Navigation    = require("turtle.subsystem.core.Navigation.init")

local Turtle = {
    name = nil,
    agentType = nil,
    logCleanup = nil,
}

local function initSequence(config)
    -- TODO: Validate config before use
    local turtleConfig = config.turtle
    local navigationConfig = config.navigation
    local cleanupConfig = config.cleanup

    Log:startup("CORE: Init sequence started.")
    
    Turtle.name = turtleConfig.NAME
    Turtle.agentType = turtleConfig.AGENT_TYPE

    Turtle.logCleanup = cleanupConfig.LOGS

    -- init nav
    Navigation:init(
        navigationConfig.HOME_COORDS,
        navigationConfig.HOME_HEADING,
        {flush = navigationConfig.MOVE_LOG.FLUSH}
    )
    Log:startup("CORE: Init sequence completed.")
end

local function shutdown()
    Log:shutdown("Shutdown sequence started.")

    -- persist the move log so the trail survives to the next run; this is what
    -- lets a later run's returnHome retrace a path recorded in an earlier run
    Navigation:shutdown()

    if Turtle.logCleanup then
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
    Log:init(config.system.LOG_LEVEL)
    initSequence(config)

    local ok, err = xpcall(mainLoopFn, errorHandler)
    if not ok then Log:error(err) end

    shutdown()
end

return Turtle
