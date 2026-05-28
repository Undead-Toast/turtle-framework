local File = require("helpers.File")
local Log = require("helpers.Log")

-- MoveLog is a paged, run-length-encoded record of the turtle's moves. Moves are
-- buffered in memory and flushed to disk pages once the buffer fills; each page
-- is named "<page>-<runHash>.txt". Navigation owns movement and position --
-- MoveLog only records the trail and helps replay it (see Navigation:retrace).

-- config
local FLUSH_DIR = "/data/flush/movelog/"
local MOVE_LIMIT_BEFORE_FLUSH = 200

-- colinear opposites, used to cancel direct back-and-forth as moves are recorded
local INVERSE_HEADING = {
    N = "S", S = "N",
    E = "W", W = "E",
    U = "D", D = "U",
}

local MoveLog = {
    runHash = nil,
    moves = {},
    pages = {},
    paused = false, -- when true, recordMove is a no-op (used while retracing)
}

function MoveLog.generateNextFlushFile()
    local flushDir = File.ensureDir(FLUSH_DIR)
    if not flushDir then Log:fatal("Could not find or create flush directory.") end

    return (#MoveLog.pages + 1) .. "-" .. MoveLog.runHash .. ".txt"
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

-- remove flush pages left over from previous runs (any file not tagged with
-- the current runHash); leaves the live run's pages untouched
function MoveLog:clearStaleFlushFiles()
    -- guard: without a runHash we can't tell ours from theirs, so don't delete
    if not self.runHash then return false, "no runHash to compare against" end
    if not fs.exists(FLUSH_DIR) or not fs.isDir(FLUSH_DIR) then return true, 0 end

    local removed = 0
    for _, name in ipairs(fs.list(FLUSH_DIR)) do
        local path = FLUSH_DIR .. name

        -- only our flush pages: skip dirs, non-.txt, and current-run files
        if not fs.isDir(path)
            and name:sub(-4) == ".txt"
            and not string.find(name, self.runHash, 1, true)
        then
            local ok, err = File.delete(path)
            if ok then
                removed = removed + 1
            else
                Log:warn("NAV: Failed to clear stale flush file " .. path .. " (" .. tostring(err) .. ")")
            end
        end
    end

    Log:debug("NAV: Cleared " .. removed .. " stale flush file(s).")
    return true, removed
end

-- parse a flush page name "<page>-<hash>.txt" into (pageNum, hash); nil if it
-- doesn't match the flush naming scheme
local function parseFlushName(name)
    local pageNum, hash = name:match("^(%d+)%-(.+)%.txt$")
    if not pageNum then return nil end
    return tonumber(pageNum), hash
end

-- adopt up to `depth` most-recent prior runs into the current run: rename their
-- pages under the new runHash (in chronological order) and register them in
-- self.pages. Non-destructive: returns true, staleFiles -- the paths of older,
-- un-adopted pages, left for the caller to dispose of.
function MoveLog:rehashFlushFiles(depth)
    if not self.runHash then return false, "no runHash to rehash into" end
    if not fs.exists(FLUSH_DIR) or not fs.isDir(FLUSH_DIR) then return true, {} end

    depth = depth or 1

    -- group prior pages by their embedded run hash, tracking each run's newest mtime
    local runs = {}
    for _, name in ipairs(fs.list(FLUSH_DIR)) do
        local path = FLUSH_DIR .. name
        local pageNum, hash = parseFlushName(name)
        if pageNum and not fs.isDir(path) then
            local run = runs[hash]
            if not run then
                run = { mtime = 0, files = {} }
                runs[hash] = run
            end
            run.files[#run.files + 1] = { pageNum = pageNum, name = name }

            local attr = fs.attributes(path)
            local mtime = attr and attr.modified or 0
            if mtime > run.mtime then run.mtime = mtime end
        end
    end

    -- order runs newest-first
    local ordered = {}
    for _, run in pairs(runs) do ordered[#ordered + 1] = run end
    table.sort(ordered, function(a, b) return a.mtime > b.mtime end)

    -- split into the adopted window (newest `depth`) and the stale remainder
    local adopted, stale = {}, {}
    for i, run in ipairs(ordered) do
        if i <= depth then
            adopted[#adopted + 1] = run
        else
            for _, f in ipairs(run.files) do
                stale[#stale + 1] = FLUSH_DIR .. f.name
            end
        end
    end

    -- fold adopted runs forward oldest-first, pages ascending within each run,
    -- so the rehashed sequence preserves chronological move order
    table.sort(adopted, function(a, b) return a.mtime < b.mtime end)
    for _, run in ipairs(adopted) do
        table.sort(run.files, function(a, b) return a.pageNum < b.pageNum end)
        for _, f in ipairs(run.files) do
            local newName = (#self.pages + 1) .. "-" .. self.runHash .. ".txt"
            local from = FLUSH_DIR .. f.name

            if pcall(fs.move, from, FLUSH_DIR .. newName) then
                self.pages[#self.pages + 1] = newName
            else
                Log:warn("NAV: Failed to rehash flush file " .. from)
            end
        end
    end

    Log:debug("NAV: Rehashed " .. #self.pages .. " page(s) from " .. #adopted
        .. " run(s); " .. #stale .. " stale page(s) left.")
    return true, stale
end

-- full resume cleanup: adopt the newest `depth` runs, then delete every older
-- page. Returns true, adoptedPageCount, deletedCount.
function MoveLog:restoreFlushFiles(depth)
    local ok, stale = self:rehashFlushFiles(depth)
    if not ok then return false, stale end -- stale carries the error message here

    local deleted = 0
    for _, path in ipairs(stale) do
        local dok, err = File.delete(path)
        if dok then
            deleted = deleted + 1
        else
            Log:warn("NAV: Failed to delete stale flush file " .. path .. " (" .. tostring(err) .. ")")
        end
    end

    Log:debug("NAV: Restored " .. #self.pages .. " page(s); deleted " .. deleted .. " stale file(s).")
    return true, #self.pages, deleted
end

-- init assigns this run a fresh runHash and prepares the flush directory.
-- opts:
--   flush  true to resume: adopt the previous run's pages into this run and
--          seed the last page back into memory. false/absent for a fresh start,
--          which deletes stale pages left by earlier runs.
--   depth  (resume only) how many most-recent prior runs to fold forward;
--          defaults to 1. Older runs are deleted. Ignored when flush is falsy.
-- returns true.
function MoveLog:init(opts)
    opts = opts or {}
    self.runHash = File.generateRandomFileId() -- random hash kinda for the most part

    if opts.flush then
        -- resume: adopt the newest `depth` prior run(s) into this run (renamed
        -- to runHash), and delete anything older
        self:restoreFlushFiles(opts.depth)

        -- seed the last page back into memory so new moves continue filling it
        -- rather than starting a fragmented page. If that page happened to be
        -- full it self-corrects: the next recordMove just flushes it straight
        -- back out.
        self:hydrateTail()
    else
        -- fresh start: clear any leftover pages from previous runs
        self:clearStaleFlushFiles()
    end

    return true
end

function MoveLog:recordMove(dir)
    -- paused while retracing so the reverse trip doesn't re-log the trail
    if self.paused then return true end

    -- check flush
    if #self.moves >= MOVE_LIMIT_BEFORE_FLUSH then
        self:flush()
    end

    local moves = self.moves

    -- consolidate against the last recorded run (in-memory only)
    if #moves >= 1 then
        local lastMove = moves[#moves]
        local lastDir = lastMove.direction

        if dir == lastDir then
            -- same direction: extend the run
            lastMove.count = lastMove.count + 1
            return true
        elseif dir == INVERSE_HEADING[lastDir] then
            -- colinear reversal: cancel against the run instead of appending, so
            -- direct back-and-forth (and branch in/out) never enters the trail.
            -- Drop the entry when it cancels out entirely.
            lastMove.count = lastMove.count - 1
            if lastMove.count <= 0 then moves[#moves] = nil end
            return true
        end
    end

    moves[#moves + 1] = {direction = dir, count = 1}

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

-- the inverse of flush: when the in-memory buffer is empty but flushed pages
-- remain, pull the newest page back into self.moves and delete it from disk, so
-- the retrace tail logic only ever has to touch self.moves
function MoveLog:hydrateTail()
    if #self.moves > 0 or #self.pages == 0 then return end

    local pageName = self.pages[#self.pages]
    local path = FLUSH_DIR .. pageName
    local content = File.readLines(path)
    if not content then Log:fatal("NAV: Failed to read flush file " .. path) end

    -- pages are written oldest -> newest, so restore that same order into moves
    local moves = {}
    for i = 1, #content do
        local move = textutils.unserialize(content[i])
        if move then moves[#moves + 1] = move end
    end

    self.moves = moves
    self.pages[#self.pages] = nil
    File.delete(path)
end

-- ---- retrace tail API ----------------------------------------------------
-- Small surface Navigation:retrace drives so it never touches the log's
-- internal arrays or pages directly.

-- stop / resume recording (recordMove is a no-op while paused)
function MoveLog:pause() self.paused = true end
function MoveLog:resume() self.paused = false end

-- newest unconsumed segment {direction, count}, hydrating a flushed page when
-- the in-memory buffer is empty. Returns nil when the log is fully empty.
function MoveLog:peekTail()
    self:hydrateTail()
    if #self.moves == 0 then return nil end
    return self.moves[#self.moves]
end

-- trim `units` unit-steps off the newest segment, dropping the entry at zero
function MoveLog:trimTail(units)
    if #self.moves == 0 then return end
    local entry = self.moves[#self.moves]
    entry.count = entry.count - units
    if entry.count <= 0 then self.moves[#self.moves] = nil end
end

-- flush whatever is still buffered in memory so a clean shutdown doesn't lose
-- the tail. The in-memory buffer is otherwise volatile until the next flush, so
-- this also closes the window opened by hydrateTail seeding on resume.
function MoveLog:shutdown()
    return self:flush()
end

return MoveLog
