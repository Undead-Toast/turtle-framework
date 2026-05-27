package.path = package.path .. ";/?.lua;/?/init.lua"

local Turtle   = require("turtle.Turtle")
local Tunneler = require("turtle.types.Tunneler")

-- Per-turtle config, inline for now.
-- Could later be loaded from disk for editing without code changes, e.g.:
--   local File = require("helpers.File")
--   local config = textutils.unserialize(File.read("/data/config.txt"))
local config = {
    HOME_COORDS  = {-70, 69, 111},
    HOME_HEADING = "S",
    NAME         = "toast",
    TYPE         = "tunneler",
}

Turtle.run(config, Tunneler.run)