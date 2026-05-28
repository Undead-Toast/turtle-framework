package.path = package.path .. ";/?.lua;/?/init.lua"

local Turtle   = require("turtle.Turtle")
local TestAgent = require("turtle.agents.Test")
local config   = require("config.turtle")

Turtle.run(config, TestAgent.run)