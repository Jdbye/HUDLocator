local configMod = require("HUDLocator.config")
local utils = require("HUDLocator.utils")
local logger = require("HUDLocator.logger")

local M = {}
M.hasLoggedRelics = false

function M.Scan(playerPos, maxDistSq)
    local newRelics = {}
    local relics = {}
    local status, res = pcall(function() return FindAllOf("PalLevelObjectRelic") end)
    if status and res then
        relics = res
    end
    for _, relic in ipairs(relics) do
        if utils.IsActorValidForScan(relic) then
            pcall(function()
                local ueRelicPos = relic:K2_GetActorLocation()
                if ueRelicPos then
                    local within, distSq, px, py, pz = utils.IsWithinDistanceSq(ueRelicPos, playerPos, maxDistSq)
                    -- Defer expensive C++ reflection check until after spatial distance check
                    if within and not utils.IsRelicPicked(relic) then
                        local name = nil
                        local statusType, relicType = pcall(function() return relic:GetRelicType() end)
                        if not statusType or not relicType then
                            statusType, relicType = pcall(function() return relic.RelicType end)
                        end
                        local resolvedType = (statusType and relicType) and relicType or 0
                        local trans = utils.GetTranslatedRelicName(resolvedType)
                        if trans then
                            name = trans
                        else
                            name = configMod.GetTranslation("Relic", "Relic")
                        end
                        local distStr = math.floor(math.sqrt(distSq) / 100.0) .. "m"
                        table.insert(newRelics, { Actor = relic, X = px, Y = py, Z = pz, Name = name, DistStr = distStr, BracketDistStr = "[" .. distStr .. "]" })
                    end
                end
            end)
        end
    end
    if not M.hasLoggedRelics and #newRelics > 0 then
        M.hasLoggedRelics = true
        logger.log("Relic Scan (Initial detection): Found " .. tostring(#newRelics) .. " relics.")
    end
    return newRelics
end

return M
