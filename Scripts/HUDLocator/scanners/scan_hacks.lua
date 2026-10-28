local configMod = require("HUDLocator.config")
local utils = require("HUDLocator.utils")
local logger = require("HUDLocator.logger")

local M = {}
M.hasLogged = false

local function IsPicked(actor)
    local picked = nil
    pcall(function() picked = actor.bPickedInClient end)
    return picked == true or picked == 1
end

local function RewardName(actor)
    local rowName = nil
    pcall(function()
        local row = actor.ItemPickupRowName
        if row then
            rowName = row.Key or row
        end
    end)
    if rowName then
        local translated = utils.GetTranslatedItemName(rowName)
        if translated and translated ~= "" and translated ~= "None" then
            local raw = ""
            pcall(function()
                raw = type(rowName) == "string" and rowName or rowName:ToString()
            end)
            if translated ~= raw then
                return translated
            end
        end
    end
    return configMod.GetTranslation("Hack", "Hack")
end

function M.Scan(playerPos, maxDistSq)
    local found = {}
    local status, actors = pcall(function() return FindAllOf("BP_LevelObject_ItemPickupTower_C") end)
    if not status or not actors then
        status, actors = pcall(function() return FindAllOf("PalLevelObjectItemPickup") end)
    end
    if not status or not actors then return found end

    local seen = {}
    for _, actor in ipairs(actors) do
        local key = nil
        pcall(function() key = actor:GetFullName() end)
        if key and not seen[key] and not string.find(key, "Default__", 1, true) then
            if not string.find(key, "ItemPickupTower", 1, true) then
                -- The base pickup class also covers non-tower prizes.
            else
                seen[key] = true
                if utils.IsActorValidForScan(actor) and not IsPicked(actor) then
                    pcall(function()
                        local pos = actor:K2_GetActorLocation()
                        if not pos then return end
                        local within, distSq, px, py, pz = utils.IsWithinDistanceSq(pos, playerPos, maxDistSq)
                        if not within then return end
                        local distStr = math.floor(math.sqrt(distSq) / 100.0) .. "m"
                        table.insert(found, {
                            Actor = actor,
                            X = px, Y = py, Z = pz,
                            Name = RewardName(actor),
                            DistStr = distStr,
                            BracketDistStr = "[" .. distStr .. "]",
                        })
                    end)
                end
            end
        end
    end

    if not M.hasLogged and #found > 0 then
        M.hasLogged = true
        logger.log("Hack tower scan: found " .. tostring(#found) .. " uncollected prizes.")
    end
    return found
end

return M
