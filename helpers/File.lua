-- Small wrapper for fs module, allows for easier logging and utils
local File = {}

function File.ensureDir(path)
    local dir = fs.getDir(path)
    if dir == "" or fs.exists(dir) then return true end

    local ok = pcall(fs.makeDir, dir)
    if not ok then return false, "could not create directory " .. dir end
    return true
end

function File.generateRandomFileId()
    local time = os.date("%H_%M", math.floor(os.epoch("local") / 1000))
    return string.format("%s-%x", time, math.random(0, 0xFFFF))
end

function File.write(path, data, newLine, append)
    local ok, err = File.ensureDir(path)
    if not ok then return false, err end

    local file = nil
    if append then
        file = fs.open(path, "a")
    else
        file = fs.open(path, "w")
        if not file then return false, "could not open " .. path .. " for writing" end
    end


    if newLine then
        file.writeLine(data)
    else
        file.write(data)
    end
    
    file.close()
    return true
end

function File.append(path, data)
    local ok, err = File.ensureDir(path)
    if not ok then return false, err end

    local file = fs.open(path, "a")
    if not file then return false, "could not open " .. path .. " for appending" end

    file.writeLine(data)
    file.close()
    return true
end

function File.read(path)
    if not fs.exists(path) then return nil end

    local file = fs.open(path, "r")
    if not file then return nil, "could not open " .. path .. " for reading" end

    local contents = file.readAll()
    file.close()
    return contents
end

function File.readLines(path)
    if not fs.exists(path) then return nil end

    local file = fs.open(path, "r")
    if not file then return nil, "could not open " .. path .. " for reading" end

    local lines = {}
    local line = file.readLine()
    while line do
        lines[#lines + 1] = line
        line = file.readLine()
    end
    file.close()
    return lines
end

function File.exists(path)
    return fs.exists(path)
end

function File.delete(path)
    if not fs.exists(path) then return true end

    local ok = pcall(fs.delete, path)
    if not ok then return false, "could not delete " .. path end
    return true
end

function File.getSize(path)
    if not fs.exists(path) then return nil end
    return fs.getSize(path)
end

return File
