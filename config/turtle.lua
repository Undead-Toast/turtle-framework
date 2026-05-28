local turtle = {
    NAME         = "toast",
    AGENT_TYPE   = "tunneler", -- unused
}

local navigation = {
    HOME_COORDS  = {-70, 69, 111},
    HOME_HEADING = "S",
    MOVE_LOG = {
        FLUSH    = true
    },
}

local system = {
    LOG_LEVEL = "INFO"
}

local cleanup = {
    LOGS  = false
}

local config = {
    turtle = turtle,
    navigation = navigation,
    system = system,
    cleanup = cleanup
}

return config