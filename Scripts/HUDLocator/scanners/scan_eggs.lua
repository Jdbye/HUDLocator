local configMod = require("HUDLocator.config")
local utils = require("HUDLocator.utils")
local logger = require("HUDLocator.logger")

local M = {}
M.hasLoggedEggs = false

function M.Scan(playerPos, maxDistSq, eggFilter)
    local newEggs = {}
    local eggs = {}
    local status, res = pcall(function() return FindAllOf("PalMapObjectPalEgg") end)
    if status and res then
        eggs = res
    end
    for _, egg in ipairs(eggs) do
        if utils.IsActorValidForScan(egg) then
            pcall(function()
                local ueEggPos = egg:K2_GetActorLocation()
                if ueEggPos then
                    local within, distSq, px, py, pz = utils.IsWithinDistanceSq(ueEggPos, playerPos, maxDistSq)
                    -- Defer expensive C++ reflection check until after spatial distance check
                    if within and not utils.IsEggPicked(egg) then
                        local sizeStr = ""
                        local statusScale, scale = pcall(function() return egg.Scale end)
                        
                        if statusScale and type(scale) == "number" then
                            if scale >= 1.9 then sizeStr = "Huge"
                            elseif scale >= 1.05 then sizeStr = "Large"
                            end
                        end

                        local shouldAdd = true
                        if eggFilter == "HugeOnly" and sizeStr ~= "Huge" then
                            shouldAdd = false
                        elseif eggFilter == "Large+" and sizeStr == "" then
                            shouldAdd = false
                        end

                        if shouldAdd then
                            local name = nil
                            local useSizePrefix = true
                            local statusModel, model = pcall(function() return egg.MapObjectModel end)
                            if statusModel and model and model:IsValid() then
                                local concrete = model.ConcreteModel
                                if concrete and concrete:IsValid() then
                                    local visualIdStatus, visualId = pcall(function() return concrete:GetVisualStaticItemId() end)
                                    if not visualIdStatus or not visualId then
                                        visualIdStatus, visualId = pcall(function() return concrete.VisualStaticItemId end)
                                    end
                                    if visualIdStatus and visualId and visualId:ToString() ~= "None" then
                                        local itemIdStr = visualId:ToString()
                                        local trans = utils.GetTranslatedItemName(itemIdStr)
                                        if trans then
                                            name = trans
                                            useSizePrefix = false
                                        end
                                    end
                                end
                                
                                if not name then
                                    local dataIdStatus, dataId = pcall(function() return model.MapObjectMasterDataId end)
                                    if dataIdStatus and dataId then
                                        local trans = utils.GetTranslatedMapObjectName(dataId)
                                        if trans then name = trans end
                                    end
                                end
                            end
                            
                            if not name then
                                name = configMod.GetTranslation("Egg", "Egg")
                            end
                            
                            local transSize = ""
                            if useSizePrefix and sizeStr ~= "" then
                                transSize = configMod.GetTranslation(sizeStr, sizeStr) .. " "
                            end
                            
                            local distStr = math.floor(math.sqrt(distSq) / 100.0) .. "m"
                            table.insert(newEggs, { Actor = egg, X = px, Y = py, Z = pz, SizePrefix = transSize, Name = name, FullName = transSize .. name, DistStr = distStr, BracketDistStr = "[" .. distStr .. "]" })
                        end
                    end
                end
            end)
        end
    end
    
    if not M.hasLoggedEggs and #newEggs > 0 then
        M.hasLoggedEggs = true
        logger.log("Egg Scan (Initial detection): Found " .. tostring(#newEggs) .. " eggs.")
    end
    
    return newEggs
end

return M
