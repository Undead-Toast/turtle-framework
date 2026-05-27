local File = require("helpers.File")


local TEST_DIR = "/data/test/"
local EXPORT_FORMAT = ".txt"

local TestUtils = {}
local Text = textutils

local thisRunFiles = {}

local function prettyTable(table)
    if not table then return nil end
    return Text.serialize(table)
end

function TestUtils.export(data)
    local data = data
    if type(data) == "table" then
        data = prettyTable(data)
    end

    local rand = File.generateRandomFileId()
    local file = "test-" .. rand .. EXPORT_FORMAT
    local fullPath = TEST_DIR .. file
    local export = File.write(fullPath, data)
    if not export then return false end

    thisRunFiles[fullPath] = true
    return true
end

function TestUtils.clearTestFiles()
    if not File.exists(TEST_DIR) then return true, 0 end

    local items = fs.list(TEST_DIR)
    local deleted = 0

    for _, name in ipairs(items) do
        local path = TEST_DIR .. name
        if not fs.isDir(path) then
            local ok = File.delete(path)
            if ok then deleted = deleted + 1 end
        end
    end

    return true, deleted
end

function TestUtils.clearOldTestFiles()
    if not File.exists(TEST_DIR) then return true, 0 end

    local items = fs.list(TEST_DIR)
    local deleted = 0

    for _, name in ipairs(items) do
        local path = TEST_DIR .. name
        if not fs.isDir(path) and not thisRunFiles[path] then
            local ok = File.delete(path)
            if ok then deleted = deleted + 1 end
        end
    end

    return true, deleted
end

return TestUtils