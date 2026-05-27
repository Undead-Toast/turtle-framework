local File = require("helpers.File")

local State = {
    STATE_PATH = "/data/state/"
}

local function pathFor(name)
    return State.STATE_PATH .. name .. ".txt"
end

function State.save(name, data)
    local payload = textutils.serialize(data)
    return File.write(pathFor(name), payload)
end

function State.load(name)
    local contents = File.read(pathFor(name))
    if not contents then return nil end

    local state = textutils.unserialize(contents)
    if not state then return nil, "parse failed" end

    return state
end

function State.exists(name)
    local size = File.getSize(pathFor(name))
    return size ~= nil and size > 0
end

function State.clear(name)
    return File.delete(pathFor(name))
end

return State
