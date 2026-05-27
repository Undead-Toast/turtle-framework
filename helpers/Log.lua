local File = require("helpers.File")

local Log = {
    LOG_LEVEL_VALUES = {
        ["DEBUG"] = 1, 
        ["INFO"] = 2, 
        ["WARN"] = 3, 
        ["ERROR"] = 4,
        ["STARTUP"] = 5,
        ["SHUTDOWN"] = 6,
    },
    LOG_LEVELS = {
        "DEBUG", "INFO", "WARN", "ERROR", "STARTUP", "SHUTDOWN"
    },
    context = {
        runId = nil,
        pages = nil,
        logLevel = nil,
        errors = nil,
        warns = nil,
        info = nil,
    }
}

local LOGS_DIR = "/data/logs/"

function Log.parseToString(data)
    if type(data) == "table" then
        return textutils.serialize(data, {compact = true})
    elseif type(data) == "boolean" then
        if data then
            return "true"
        else
            return "false"
        end
    else
        return data
    end
end

function Log.writeToFile(dataString)
    local filePath = LOGS_DIR .. Log.context.runId .. ".txt"
    return File.append(filePath, dataString)
end

function Log.clearOldLogs()
    if not File.exists(LOGS_DIR) then return true, 0 end

    local currentFile = Log.context.runId and (Log.context.runId .. ".txt")
    local items = fs.list(LOGS_DIR)
    local deleted = 0

    for _, name in ipairs(items) do
        local path = LOGS_DIR .. name
        if not fs.isDir(path) and name ~= currentFile then
            local ok = File.delete(path)
            if ok then deleted = deleted + 1 end
        end
    end

    return true, deleted
end

-- Defaults to configured log level if invalid level
function Log:log(level, data)
    local logLevel = self.context.logLevel
    if type(level) == "string" and self.LOG_LEVEL_VALUES[level] then
        logLevel = self.LOG_LEVELS[self.LOG_LEVEL_VALUES[level]]
    end

    -- determine if print to console
    local configuredLevelValue = self.LOG_LEVEL_VALUES[self.context.logLevel]
    local requestedLevelValue = self.LOG_LEVEL_VALUES[logLevel]

    if requestedLevelValue >= configuredLevelValue then
        local dataString = Log.parseToString(data)
        local payload = logLevel .. ": " .. dataString

        Log.writeToFile(payload)
        print(payload)
    end
end

function Log:debug(data) self:log("DEBUG", data) end
function Log:info(data) self:log("INFO", data) end
function Log:warn(data) self:log("WARN", data) end
function Log:error(data) self:log("ERROR", data) end
function Log:startup(data) self:log("STARTUP", data) end
function Log:shutdown(data) self:log("SHUTDOWN", data) end

function Log:fatal(data)
    self:log("ERROR", data)
    error(Log.parseToString(data), 2)
end

function Log:init(level)
    math.randomseed(os.epoch("utc"))

    local levelOk = false;
    for i = 1, 4 do
        if self.LOG_LEVELS[i] == level then
            levelOk = true;
        end
    end

    local context = self.context

    if levelOk then
        context.logLevel = level
    else
        print("No log level defaulting to INFO")
        context.logLevel = self.LOG_LEVELS[2]
    end

    context.runId = "log-" .. File.generateRandomFileId()
    self:startup("Logger initialized with id " .. context.runId)
    context.pages = 1
    context.errors = 0
    context.warns = 0
    context.info = 0
    return true
end



return Log