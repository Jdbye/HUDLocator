-- Scanners Facade Module for HUDLocator
local scanPlayers = require("HUDLocator.scanners.scan_players")
local scanRelics = require("HUDLocator.scanners.scan_relics")
local scanChests = require("HUDLocator.scanners.scan_chests")
local scanEggs = require("HUDLocator.scanners.scan_eggs")
local scanCaves = require("HUDLocator.scanners.scan_caves")
local scanLoot = require("HUDLocator.scanners.scan_loot")
local scanNotes = require("HUDLocator.scanners.scan_notes")
local scanPals = require("HUDLocator.scanners.scan_pals")
local scanFastTravel = require("HUDLocator.scanners.scan_fasttravel")
local scanHacks = require("HUDLocator.scanners.scan_hacks")
local scanBounties = require("HUDLocator.scanners.scan_bounties")

local M = {}

function M.ScanPlayers(localPlayerState, localPlayerPawn, localPlayerPos)
    return scanPlayers.Scan(localPlayerState, localPlayerPawn, localPlayerPos)
end

function M.ScanRelics(playerPos, maxDistSq)
    return scanRelics.Scan(playerPos, maxDistSq)
end

function M.ScanChests(playerPos, maxDistSq)
    return scanChests.Scan(playerPos, maxDistSq)
end

function M.ScanEggs(playerPos, maxDistSq, eggFilter, debug)
    return scanEggs.Scan(playerPos, maxDistSq, eggFilter)
end

function M.ScanCaves(playerPos, maxDistSq)
    return scanCaves.Scan(playerPos, maxDistSq)
end

function M.ScanLoot(playerPos, maxDistSq, lootConfig)
    return scanLoot.Scan(playerPos, maxDistSq, lootConfig)
end

function M.ScanFastTravel(playerPos, maxDistSq)
    return scanFastTravel.Scan(playerPos, maxDistSq)
end

function M.ScanHacks(playerPos, maxDistSq)
    return scanHacks.Scan(playerPos, maxDistSq)
end

function M.ScanBounties(playerPos, maxDistSq)
    return scanBounties.Scan(playerPos, maxDistSq)
end

function M.ScanNotes(playerPos, maxDistSq)
    return scanNotes.Scan(playerPos, maxDistSq)
end

function M.ScanPals(playerPos, maxDistSq, palConfig)
    return scanPals.Scan(playerPos, maxDistSq, palConfig)
end

return M
