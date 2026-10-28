local configMod = require("HUDLocator.config")
local utils = require("HUDLocator.utils")
local logger = require("HUDLocator.logger")

local M = {}
M.hasLoggedNotes = false

function M.Scan(playerPos, maxDistSq)
    local newNotes = {}
    local notes = {}
    local status, res = pcall(function() return FindAllOf("PalLevelObjectNote") end)
    if status and res then
        notes = res
    end
    for _, note in ipairs(notes) do
        if utils.IsActorValidForScan(note) then
            pcall(function()
                local ueNotePos = note:K2_GetActorLocation()
                if ueNotePos then
                    local within, distSq, px, py, pz = utils.IsWithinDistanceSq(ueNotePos, playerPos, maxDistSq)
                    -- Defer expensive C++ reflection check until after spatial distance check
                    if within and not utils.IsNotePicked(note) then
                        local name = nil
                        local statusName, noteKey = pcall(function() return note.NoteRowName.Key end)
                        if statusName and noteKey then
                            local trans = utils.GetTranslatedNoteName(noteKey)
                            if trans then
                                name = trans
                            else
                                name = configMod.GetTranslation("Note", "Journal")
                            end
                        else
                            name = configMod.GetTranslation("Note", "Journal")
                        end
                        local distStr = math.floor(math.sqrt(distSq) / 100.0) .. "m"
                        table.insert(newNotes, { Actor = note, X = px, Y = py, Z = pz, Name = name, DistStr = distStr, BracketDistStr = "[" .. distStr .. "]" })
                    end
                end
            end)
        end
    end
    
    if not M.hasLoggedNotes and #newNotes > 0 then
        M.hasLoggedNotes = true
        logger.log("Note Scan (Initial detection): Found " .. tostring(#newNotes) .. " journals.")
    end
    return newNotes
end

return M
