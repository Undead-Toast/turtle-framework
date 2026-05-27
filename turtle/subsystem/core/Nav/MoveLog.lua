local File = require("helpers.File")
local Log = require("helpers.Log")

local MOVELOG_PATH = "/data/state/movelog/"
local init = false

local MoveLog = {
    suppress = false,
    logDir = nil,
    pageState = {
        page = 0,
        currentPagePath = nil,
        writes = 0
    },
}

local function pathFor(name)
    if MoveLog.logDir then
        return MOVELOG_PATH .. MoveLog.logDir .. "/" .. name .. ".txt"
    else
        Log:fatal("MOVELOG: Init didn't run or failed.")
    end
end

function MoveLog:newPage()
    local pageState = self.pageState
    pageState.page = pageState.page + 1
    pageState.currentPagePath = pathFor(pageState.page)
    pageState.writes = 0
end

function MoveLog:save(data)
    if self.suppress then return end
    if not init then Log:error("MOVELOG: Init didn't run or failed.") end

    if self.pageState.writes >= 1000 then
        self:newPage()
    end

    local payload = textutils.serialize(data, {compact = true})
    local path = self.pageState.currentPagePath
    File.write(path, payload, true, true)
    self.pageState.writes = self.pageState.writes + 1
end

function MoveLog:readAll()
    if not init then
        Log:error("MOVELOG: readAll called before init.")
        return {}
    end

    local entries = {}
    for page = 1, self.pageState.page do
        local lines = File.readLines(pathFor(page))
        if lines then
            for _, line in ipairs(lines) do
                local entry = textutils.unserialize(line)
                if entry then
                    entries[#entries + 1] = entry
                else
                    Log:warn("MOVELOG: failed to unserialize line in page " .. page)
                end
            end
        end
    end
    return entries
end

-- not used but may in future
function MoveLog.exists(name)
    local size = File.getSize(pathFor(name))
    return size ~= nil and size > 0
end

function MoveLog.clearOldMoveLog()
    if not File.exists(MOVELOG_PATH) then return true, 0 end

    local currentDir = MoveLog.logDir
    local items = fs.list(MOVELOG_PATH)
    local deleted = 0

    for _, name in ipairs(items) do
        local path = MOVELOG_PATH .. name
        if fs.isDir(path) and name ~= currentDir then
            local ok = File.delete(path)
            if ok then deleted = deleted + 1 end
        end
    end

    return true, deleted
end

function MoveLog:init(data)
    Log:startup("MOVELOG: Starting MoveLog init.")
    -- Init
    local pageState = self.pageState

    self.logDir = File.generateRandomFileId()
    File.ensureDir(MOVELOG_PATH .. self.logDir)

    pageState.page = 1
    pageState.currentPagePath = pathFor(pageState.page)

    local payload = textutils.serialize(data, {compact = true})
    local path = pageState.currentPagePath
    File.write(path, payload, true, true)
    pageState.writes = pageState.writes + 1

    init = true
    Log:startup("MOVELOG: Init complete.")
    return true
end

return MoveLog
