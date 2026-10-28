local configMod = require("HUDLocator.config")
local utils = require("HUDLocator.utils")
local logger = require("HUDLocator.logger")

local M = {}
M.hasLogged = false

local CLASSES = {
    "BP_LevelObject_TowerFastTravelPoint_C",
    "BP_LevelObject_UnlockMapPoint_C",
    "PalLevelObjectUnlockableFastTravelPoint",
}

local function IsUnlocked(actor)
    local unlocked = nil
    local ok = pcall(function() unlocked = actor:IsUnlocked() end)
    if ok and (unlocked == true or unlocked == 1) then return true end
    if ok and (unlocked == false or unlocked == 0) then return false end
    pcall(function() unlocked = actor.bUnlocked end)
    if unlocked == true or unlocked == 1 then return true end
    if unlocked == false or unlocked == 0 then return false end
    return true
end

function M.Scan(playerPos, maxDistSq)
    local found = {}
    local seen = {}
    for _, className in ipairs(CLASSES) do
        local status, actors = pcall(function() return FindAllOf(className) end)
        if status and actors then
            for _, actor in ipairs(actors) do
                local key = nil
                pcall(function() key = actor:GetFullName() end)
                if key and not seen[key] and not string.find(key, "Default__", 1, true) then
                    seen[key] = true
                    if utils.IsActorValidForScan(actor) and not IsUnlocked(actor) then
                        pcall(function()
                            local pos = actor:K2_GetActorLocation()
                            if not pos then return end
                            local within, distSq, px, py, pz = utils.IsWithinDistanceSq(pos, playerPos, maxDistSq)
                            if not within then return end
                            local distStr = math.floor(math.sqrt(distSq) / 100.0) .. "m"
                            table.insert(found, {
                                Actor = actor,
                                X = px, Y = py, Z = pz,
                                Name = configMod.GetTranslation("FastTravel", "Fast Travel"),
                                DistStr = distStr,
                                BracketDistStr = "[" .. distStr .. "]",
                            })
                        end)
                    end
                end
            end
        end
    end

    if not M.hasLogged and #found > 0 then
        M.hasLogged = true
        logger.log("Fast travel scan: found " .. tostring(#found) .. " unactivated points.")
    end
    return found
end

return M
