local utils = require("HUDLocator.utils")
local logger = require("HUDLocator.logger")

local M = {}
M.hasLoggedLoot = false

local function GetItemDetails(actor)
    local name = nil
    local itemIdStr = nil
    
    local statusModel, model = pcall(function() return actor.MapObjectModel end)
    if statusModel and model then
        local isValid = false
        pcall(function() isValid = model:IsValid() end)
        if isValid then
            local concrete = nil
            pcall(function() concrete = model.ConcreteModel end)
            if concrete then
                local isConcreteValid = false
                pcall(function() isConcreteValid = concrete:IsValid() end)
                if isConcreteValid then
                    local itemId = nil
                    pcall(function() itemId = concrete.ItemId end)
                    if itemId then
                        local staticId = nil
                        pcall(function() staticId = itemId.StaticId end)
                        if staticId then
                            pcall(function() itemIdStr = staticId:ToString() end)
                        end
                    end
                    
                    if not itemIdStr then
                        local visualId = nil
                        local visualIdStatus = pcall(function() visualId = concrete:GetVisualStaticItemId() end)
                        if not visualIdStatus or not visualId then
                            pcall(function() visualId = concrete.VisualStaticItemId end)
                        end
                        if visualId then
                            pcall(function() itemIdStr = visualId:ToString() end)
                        end
                    end
                end
            end
        end
    end
    
    if not itemIdStr or itemIdStr == "" or itemIdStr == "None" then
        pcall(function()
            local model = actor.MapObjectModel
            if model then
                local direct = model.ItemId
                if direct and direct.StaticId then
                    itemIdStr = direct.StaticId:ToString()
                end
            end
        end)
    end

    if not itemIdStr or itemIdStr == "" or itemIdStr == "None" then
        pcall(function()
            local param = actor.PalMapObjectPickupItemParameter
            local drops = param and param.DropItems
            local first = drops and drops[1]
            local staticId = first and (first.StaticItemId and (first.StaticItemId.Key or first.StaticItemId) or first.StaticId)
            if staticId then
                if type(staticId) == "string" then
                    itemIdStr = staticId
                elseif staticId.ToString then
                    itemIdStr = staticId:ToString()
                end
            end
        end)
    end

    if itemIdStr and itemIdStr ~= "None" then
        name = utils.GetTranslatedItemName(itemIdStr)
        if not name or name == "" then
            name = itemIdStr
        end
    end
    
    return name, itemIdStr
end

local function Lower(value)
    return string.lower(tostring(value or ""))
end

local function Hit(hay, needle)
    if hay == "" or needle == "" then return false end
    return string.find(hay, needle, 1, true) ~= nil
end

local function IsSkillFruit(name, itemId, className)
    return Hit(name, "skill fruit") or Hit(name, "skillfruit") or Hit(itemId, "skillfruit")
        or Hit(itemId, "skill_fruit") or Hit(itemId, "skillunlock") or Hit(itemId, "skillcard")
        or Hit(className, "skillfruit")
end

local function IsLotus(name, itemId)
    return Hit(name, "lotus") or Hit(itemId, "lotus")
end

local function IsSphere(name, itemId)
    return Hit(name, "sphere") or Hit(itemId, "sphere") or Hit(itemId, "palsphere")
end

local function Wanted(mode, list, name, itemId, className)
    local n, id, class = Lower(name), Lower(itemId), Lower(className)
    if Hit(id, "palegg") or Hit(class, "palegg") or Hit(class, "relic") then return false end
    if mode == "All" then return true end
    if mode == "Skill Fruits/Lotus Only" then
        return IsSkillFruit(n, id, class) or IsLotus(n, id)
    end
    local rules = list
    if type(rules) ~= "table" or #rules == 0 then
        rules = { "SkillFruit", "Skill Fruit", "Lotus", "Sphere" }
    end
    for _, token in ipairs(rules) do
        local needle = Lower(token)
        if needle == "skillfruit" or needle == "skill fruit" then
            if IsSkillFruit(n, id, class) then return true end
        elseif needle == "lotus" then
            if IsLotus(n, id) then return true end
        elseif needle == "sphere" or needle == "palsphere" then
            if IsSphere(n, id) then return true end
        elseif Hit(n, needle) or Hit(id, needle) or Hit(class, needle) then
            return true
        end
    end
    return false
end

local function ClassNameOf(actor)
    local name = ""
    pcall(function()
        local classObj = actor:GetClass()
        if classObj and classObj.GetName then
            local raw = classObj:GetName()
            if type(raw) == "string" then
                name = raw
            elseif raw and raw.ToString then
                name = raw:ToString()
            end
        end
    end)
    return name
end

function M.Scan(playerPos, maxDistSq, lootConfig)
    lootConfig = lootConfig or {}
    local mode = lootConfig.FilterMode or "All"
    local list = lootConfig.TrackerLoot
    if type(lootConfig.Filters) == "table" and #lootConfig.Filters > 0 then
        list = lootConfig.Filters
    end
    local newLoot = {}
    local actors = {}
    local classes = {
        "BP_MapObject_TreasureBox_VisibleContent_SkillFruits_C",
        "BP_MapObject_TreasureBox_VisibleContent_C",
        "BP_MapObject_PickupItem_Base_C",
        "PalMapObjectDropItem",
    }
    if mode == "All" then
        table.insert(classes, "PalMapLevelObject")
    end
    for _, className in ipairs(classes) do
        local status, found = pcall(function() return FindAllOf(className) end)
        if status and found then
            for _, actor in ipairs(found) do
                table.insert(actors, actor)
            end
        end
    end
    
    local seen = {}
    local uniqueActors = {}
    for _, actor in ipairs(actors) do
        local key = nil
        pcall(function() key = actor:GetFullName() end)
        key = key or tostring(actor)
        if not seen[key] then
            seen[key] = true
            table.insert(uniqueActors, actor)
        end
    end
    
    for _, actor in ipairs(uniqueActors) do
        local hidden = false
        pcall(function() hidden = actor.bHidden end)
        if hidden ~= true and utils.IsActorValidForScan(actor) then
            pcall(function()
                local ueLootPos = actor:K2_GetActorLocation()
                if ueLootPos then
                    local within, distSq, px, py, pz = utils.IsWithinDistanceSq(ueLootPos, playerPos, maxDistSq)
                    if within then
                        local name, itemIdStr = GetItemDetails(actor)
                        local className = ClassNameOf(actor)
                        if (not name or name == "") and IsSkillFruit("", "", className) then
                            name = "Skill Fruit"
                        end
                        if name and name ~= "" and Wanted(mode, list, name, itemIdStr, className) then
                            local distStr = math.floor(math.sqrt(distSq) / 100.0) .. "m"
                            table.insert(newLoot, { Actor = actor, X = px, Y = py, Z = pz, Name = name, DistStr = distStr, BracketDistStr = "[" .. distStr .. "]" })
                        end
                    end
                end
            end)
        end
    end
    
    if not M.hasLoggedLoot and #newLoot > 0 then
        M.hasLoggedLoot = true
        logger.log("Loot Scan (Initial detection): Found " .. tostring(#newLoot) .. " loot items on ground.")
    end
    
    return newLoot
end

return M
