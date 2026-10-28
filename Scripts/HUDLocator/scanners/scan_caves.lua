local configMod = require("HUDLocator.config")
local utils = require("HUDLocator.utils")
local logger = require("HUDLocator.logger")

local M = {}

M.dungeonClasses = {
    "BP_DungeonFixedEntrance_C",
    "BP_DungeonFixedEntrance_forest_1_C",
    "BP_DungeonFixedEntrance_forest_2_C",
    "BP_DungeonFixedEntrance_forest_3_C",
    "BP_DungeonFixedEntrance_forest_4_C",
    "BP_DungeonFixedEntrance_forest_5_C",
    "BP_DungeonFixedEntrance_grass_1_C",
    "BP_DungeonFixedEntrance_grass_2_C",
    "BP_DungeonFixedEntrance_grass_3_C",
    "BP_DungeonFixedEntrance_grass_4_C",
    "BP_DungeonFixedEntrance_grass_5_C",
    "BP_DungeonFixedEntrance_grass_6_C",
    "BP_DungeonFixedEntrance_grass_7_C",
    "PalDungeonEntrance"
}
M.currentClassIndex = 1
M.tempCaves = {}
M.hasLoggedDungeons = false

function M.Scan(playerPos, maxDistSq)
    local cls = M.dungeonClasses[M.currentClassIndex]
    M.tempCaves[cls] = {}
    
    local caves = {}
    local status, res = pcall(function() return FindAllOf(cls) end)
    if status and res then
        caves = res
    end
    local successCount = 0
    local closestDistSq = math.huge

    for _, cave in ipairs(caves) do
        if utils.IsActorValidForScan(cave) then
            pcall(function()
                local ueCavePos = cave:K2_GetActorLocation()
                if ueCavePos then
                    successCount = successCount + 1

                    -- ⚡ Bolt Performance Optimization:
                    -- Optimize distance calculation by reading X first and short-circuiting
                    -- before reading Y and Z to avoid expensive C++ reflection on distant items.
                    local cx = ueCavePos.X
                    local dx = cx - playerPos.X
                    local dxSq = dx * dx

                    -- We can only short-circuit if dxSq ALONE is greater than maxDistSq AND
                    -- greater than closestDistSq (to preserve closest finding logic).
                    if dxSq <= maxDistSq or dxSq < closestDistSq then
                        local cy = ueCavePos.Y
                        local dy = cy - playerPos.Y
                        local dySq = dy * dy
                        local dxSq_dySq = dxSq + dySq

                        if dxSq_dySq <= maxDistSq or dxSq_dySq < closestDistSq then
                            local cz = ueCavePos.Z
                            local dz = cz - playerPos.Z
                            local distSq = dxSq_dySq + dz * dz

                            if distSq < closestDistSq then
                                closestDistSq = distSq
                            end

                            if distSq <= maxDistSq then
                                local level, state = utils.GetDungeonDetails(cave)
                            local dungeonName = nil
                            pcall(function()
                            local stageModel = cave.StageModel
                            if stageModel and stageModel:IsValid() then
                                local instanceModel = stageModel.InstanceModel
                                if instanceModel and instanceModel:IsValid() then
                                    local overrideId = instanceModel.OverrideDungeonNameTextId
                                    if overrideId then
                                        local trans = utils.GetTranslatedDungeonName(overrideId)
                                        if trans then dungeonName = trans end
                                    end
                                end
                            end
                        end)
                        if not dungeonName then
                            dungeonName = configMod.GetTranslation("Cave", "Cave")
                        end
                        local nameStr = dungeonName
                        if level then
                            local lv = configMod.GetTranslation("Cave_Lv", "Lv.")
                            local stateStr = state
                            if stateStr == "Open" then stateStr = configMod.GetTranslation("Cave_Open", "Open")
                            elseif stateStr == "Cleared" then stateStr = configMod.GetTranslation("Cave_Cleared", "Cleared")
                            end
                            nameStr = dungeonName .. " " .. lv .. level .. " (" .. stateStr .. ")"
                        else
                            local closed = configMod.GetTranslation("Cave_Closed", "(Closed)")
                                nameStr = dungeonName .. " " .. closed
                            end
                            local distStr = math.floor(math.sqrt(distSq) / 100.0) .. "m"
                            table.insert(M.tempCaves[cls], {
                                Actor = cave,
                                X = cx,
                                Y = cy,
                                Z = cz,
                                Level = level,
                                State = state,
                                Name = nameStr,
                                DistStr = distStr,
                                BracketDistStr = "[" .. distStr .. "]"
                            })
                            end
                        end -- End of dySq short-circuit block
                    end -- End of dxSq short-circuit block
                end
            end)
        end
    end

    M.currentClassIndex = M.currentClassIndex + 1
    if M.currentClassIndex > #M.dungeonClasses then
        M.currentClassIndex = 1
    end

    local merged = {}
    for _, classCaves in pairs(M.tempCaves) do
        for _, c in ipairs(classCaves) do
            table.insert(merged, c)
        end
    end

    if not M.hasLoggedDungeons and successCount > 0 then
        M.hasLoggedDungeons = true
        logger.log("Cave Scan (Initial detection): Found " .. tostring(successCount) .. " active caves for class " .. cls)
        if closestDistSq ~= math.huge then
            logger.log("Cave Scan (Initial detection): Closest is " .. tostring(math.sqrt(closestDistSq) / 100.0) .. " meters away.")
        end
    end
    
    return merged
end

return M
