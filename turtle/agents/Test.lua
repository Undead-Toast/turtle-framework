local Log = require("helpers.Log")
local Navigation = require("turtle.subsystem.core.Navigation.init")

local Test = {}

local function backout()
    Navigation:returnHome({fallback = true})
end

function Test.run()
    -- FIRST RUN
    -- Log:info("TUNNELER: Starting mission.")

    -- Log:debug("Start at home.")
    -- Navigation:moveTo({-60, 71, 136}, {priority = {"Y"}, onBackout = backout})
    -- Navigation:moveTo({-87, 83, 155}, {priority = {"Y"}, onBackout = backout})

    -- Log:info("TUNNELER: Returning home.")
    -- Navigation:returnHome()
    -- Log:info("TUNNELER: Mission success.")

    -- SECOND RUN
    -- Log:info("TUNNELER: Starting mission.")
    -- Navigation:moveTo({-87, 83, 155}, {priority = {"Y"}, onBackout = backout})
    -- Log:info("TUNNELER: Mission success.")

    -- THIRD RUN
    Log:info("TUNNELER: Starting mission.")

    Log:debug("Start at home.")
    Navigation:moveTo({-70, 69, 130}, {priority = {"Y"}, onBackout = backout})
    Navigation:moveTo({-75, 69, 130}, {priority = {"Y"}, onBackout = backout})
    Navigation:moveTo({-70, 69, 130}, {priority = {"Y"}, onBackout = backout})
    Navigation:moveTo({-75, 69, 130}, {priority = {"Y"}, onBackout = backout})
    Navigation:moveTo({-70, 69, 130}, {priority = {"Y"}, onBackout = backout})
    Navigation:moveTo({-75, 69, 130}, {priority = {"Y"}, onBackout = backout})
    Navigation:moveTo({-70, 69, 130}, {priority = {"Y"}, onBackout = backout})
    Navigation:moveTo({-75, 69, 130}, {priority = {"Y"}, onBackout = backout})

    Log:info("TUNNELER: Returning home.")
    Navigation:returnHome()
    Log:info("TUNNELER: Mission success.")

end

return Test
