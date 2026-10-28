local configMod = require("HUDLocator.config")
local utils = require("HUDLocator.utils")
local logger = require("HUDLocator.logger")

local M = {}
M.hasLoggedChests = false

local function ParseGradeNumFromString(str)
    if not str then return nil end
    local text = tostring(str)
    local g = text:match("Grade0*(%d+)") or text:match("Grade(%d+)") or text:match("Tier(%d+)")
    if g then
        return tonumber(g)
    end
    return nil
end

local function GetChestGradeNumber(chest, concrete)
    if concrete and concrete:IsValid() then
        local status, grade = pcall(function() return concrete:GetTreasureGradeType() end)
        if not status or grade == nil then
            status, grade = pcall(function() return concrete.TreasureGradeType end)
        end
        if status and grade ~= nil then
            if type(grade) == "number" then
                return grade + 1
            elseif type(grade) == "string" or type(grade) == "userdata" then
                local num = ParseGradeNumFromString(tostring(grade))
                if num then return num end
            end
        end
        local concreteName = nil
        pcall(function() concreteName = concrete:GetName() end)
        if concreteName then
            local num = ParseGradeNumFromString(concreteName)
            if num then return num end
        end
    end

    local visualChildName = nil
    pcall(function()
        if chest.VisualActor and chest.VisualActor.ChildActor then
            visualChildName = chest.VisualActor.ChildActor:GetName()
        end
    end)
    if visualChildName then
        local num = ParseGradeNumFromString(visualChildName)
        if num then return num end
    end

    local modelClassName = nil
    pcall(function()
        if chest.ConcreteModelClass then
            modelClassName = chest.ConcreteModelClass:GetName()
        end
    end)
    if modelClassName then
        local num = ParseGradeNumFromString(modelClassName)
        if num then return num end
    end

    return nil
end

local function IsChestGradeAllowed(gradeNum, gradeFilter)
    if not gradeFilter or gradeFilter == "All" then
        return true
    elseif gradeFilter == "None" then
        return false
    end

    if not gradeNum then
        return false
    end

    if gradeFilter == "Grade2+" then
        return gradeNum >= 2
    elseif gradeFilter == "Grade3+" then
        return gradeNum >= 3
    elseif gradeFilter == "Grade4+" then
        return gradeNum >= 4
    elseif gradeFilter == "Grade5+" then
        return gradeNum >= 5
    elseif gradeFilter == "Grade6Only" then
        return gradeNum >= 6
    end

    return true
end

function M.Scan(playerPos, maxDistSq)
    local newChests = {}
    local chests = {}
    local status, res = pcall(function() return FindAllOf("PalMapObjectTreasureBox") end)
    if status and res then
        chests = res
    end
    for _, chest in ipairs(chests) do
        if utils.IsActorValidForScan(chest) then
            pcall(function()
                local ueChestPos = chest:K2_GetActorLocation()
                if ueChestPos then
                    local within, distSq, px, py, pz = utils.IsWithinDistanceSq(ueChestPos, playerPos, maxDistSq)
                    -- Defer expensive C++ reflection check until after spatial distance check
                    if within and not utils.IsChestOpened(chest) then
                        local name = configMod.GetTranslation("Chest", "Chest")
                        local isJunk = false
                        local gradeVal = nil
                        local statusModel, model = pcall(function() return chest.MapObjectModel end)
                        if statusModel and model and model:IsValid() then
                            local concrete = model.ConcreteModel
                            gradeVal = GetChestGradeNumber(chest, concrete)

                            local dataIdStatus, dataId = pcall(function() return model.MapObjectMasterDataId end)
                            if dataIdStatus and dataId then
                                local idStr = dataId:ToString()
                                if idStr == "TreasureBox" and gradeVal then
                                    idStr = "TreasureBox_Grade" .. tostring(gradeVal)
                                end

                                if string.find(idStr, "RequiredLongHold") or string.find(idStr, "Search") then
                                    isJunk = true
                                end
                                local trans = utils.GetTranslatedMapObjectName(idStr)
                                if trans then
                                    if isJunk then
                                        trans = string.gsub(trans, "%s*%b()", "")
                                    end
                                    name = trans
                                end

                                if not isJunk and gradeVal then
                                    local gradeKey = "Grade_" .. tostring(gradeVal)
                                    local gradeLabel = configMod.GetTranslation(gradeKey, "G" .. tostring(gradeVal))
                                    name = name .. " (" .. gradeLabel .. ")"
                                end
                            end
                        end

                        local filter = configMod.CONFIG.Chests.Filter or "Both"
                        local gradeFilter = configMod.CONFIG.Chests.GradeFilter or "All"
                        local shouldAdd = true
                        if filter == "Chests" and isJunk then
                            shouldAdd = false
                        elseif filter == "Junk" and not isJunk then
                            shouldAdd = false
                        end

                        if shouldAdd and not isJunk then
                            if not IsChestGradeAllowed(gradeVal, gradeFilter) then
                                shouldAdd = false
                            end
                        end

                        if shouldAdd then
                            local distStr = math.floor(math.sqrt(distSq) / 100.0) .. "m"
                            table.insert(newChests, { Actor = chest, X = px, Y = py, Z = pz, Name = name, DistStr = distStr, BracketDistStr = "[" .. distStr .. "]" })
                        end
                    end
                end
            end)
        end
    end

    if not M.hasLoggedChests and #newChests > 0 then
        M.hasLoggedChests = true
        logger.log("Chest Scan (Initial detection): Found " .. tostring(#newChests) .. " chests.")
    end

    return newChests
end

return M
