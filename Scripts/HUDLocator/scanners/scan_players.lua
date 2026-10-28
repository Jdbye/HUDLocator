local logger = require("HUDLocator.logger")

local M = {}
M.hasLoggedPlayers = false

-- UE4SS hands back a new wrapper per lookup, so == does not identify the local player.
local function SameObject(a, b)
    if not a or not b then return false end
    if a == b then return true end
    local okA, addrA = pcall(function() return a:GetAddress() end)
    local okB, addrB = pcall(function() return b:GetAddress() end)
    if okA and okB and addrA and addrB and addrA == addrB then return true end
    return false
end

local function GetStatePawn(state)
    local pawn = nil
    pcall(function()
        if state.PawnPrivate and state.PawnPrivate:IsValid() then
            pawn = state.PawnPrivate
        elseif state.GetPawn then
            local p = state:GetPawn()
            if p and p:IsValid() then pawn = p end
        end
    end)
    return pawn
end

local function GetStateName(state)
    local nameStr = nil
    pcall(function()
        local namePrivate = state.PlayerNamePrivate
        if namePrivate then nameStr = namePrivate:ToString() end
    end)
    if nameStr == "" then return nil end
    return nameStr
end

function M.Scan(localPlayerState, localPlayerPawn, localPlayerPos)
    local newPlayers = {}
    local seen = {}
    local localName = GetStateName(localPlayerState)

    if localPlayerState and localPlayerState:IsValid() then
        local playerStates = {}
        local status, res = pcall(function() return FindAllOf("PalPlayerState") end)
        if status and res then
            playerStates = res
        end

        for _, state in ipairs(playerStates) do
            if state:IsValid() and not SameObject(state, localPlayerState) then
                pcall(function()
                    local pawn = GetStatePawn(state)
                    if localPlayerPawn and SameObject(pawn, localPlayerPawn) then return end

                    local nameStr = GetStateName(state)
                    if localName and nameStr and nameStr == localName then return end

                    if nameStr and not seen[nameStr] then
                        local loc = state.CachedPlayerLocation
                        if loc then
                            local locX, locY, locZ = loc.X, loc.Y, loc.Z
                            if locX ~= 0.0 or locY ~= 0.0 or locZ ~= 0.0 then
                                -- Cached location can lag a scan tick behind the local pawn.
                                if localPlayerPos then
                                    local dx = locX - localPlayerPos.X
                                    local dy = locY - localPlayerPos.Y
                                    local dz = locZ - localPlayerPos.Z
                                    if (dx * dx + dy * dy + dz * dz) <= (500.0 * 500.0) then return end
                                end
                                seen[nameStr] = true
                                table.insert(newPlayers, {
                                    Name = nameStr,
                                    Actor = pawn,
                                    Pos = { X = locX, Y = locY, Z = locZ }
                                })
                            end
                        end
                    end
                end)
            end
        end
    end

    if not M.hasLoggedPlayers and #newPlayers > 0 then
        M.hasLoggedPlayers = true
        logger.log("Player Scan (Initial detection): Found " .. tostring(#newPlayers) .. " other players.")
    end

    return newPlayers
end

return M
