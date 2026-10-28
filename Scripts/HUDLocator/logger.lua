local configMod = require("HUDLocator.config")

local M = {}

local logFile = "Mods/HUDLocator/hudlocator_debug.log"
local isInit = false

function M.log(msg)
    if not (configMod.CONFIG and ((configMod.CONFIG.Global and configMod.CONFIG.Global.Debug) or configMod.CONFIG.Debug)) then
        return
    end

    if not isInit then
        local f = io.open(logFile, "w")
        if f then
            f:write("[HUDLocator] Initialized Debug Log\n")
            f:close()
        end
        isInit = true
    end
    
    local f = io.open(logFile, "a")
    if f then
        f:write("[HUDLocator] " .. tostring(msg) .. "\n")
        f:close()
    end
end

return M
