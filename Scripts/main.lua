-- Palworld HUDLocator Mod (Merged & Modularized)
-- Built for Palworld v1.0
-- Uses UE4SS Lua Scripting API

local configMod = require("HUDLocator.config")
local utils = require("HUDLocator.utils")
local tracker = require("HUDLocator.tracker")
local beams = require("HUDLocator.beams")
local renderer = require("HUDLocator.renderer")
local popup = require("HUDLocator.popup")
local menu = require("HUDLocator.menu")
local boundary = require("HUDLocator.boundary_tool")
local pmoIntegration = require("HUDLocator.pmo_integration")

local CONFIG = configMod.CONFIG
local DebugPrint = configMod.DebugPrint

DebugPrint("Initializing Mod...")

-- Initialize Mod Options Framework Integration
pcall(pmoIntegration.Init)

-- Pre-allocated static FKey wrappers for edit mode to avoid per-frame GC spikes
local KeyLeft = { KeyName = FName("Left") }
local KeyRight = { KeyName = FName("Right") }
local KeyUp = { KeyName = FName("Up") }
local KeyDown = { KeyName = FName("Down") }

local KeyEquals = { KeyName = FName("Equals") }
local KeyAdd = { KeyName = FName("Add") }
local KeyRightBracket = { KeyName = FName("RightBracket") }
local KeyLeftBracket = { KeyName = FName("LeftBracket") }
local KeyBackslash = { KeyName = FName("Backslash") }

local KeyHyphen = { KeyName = FName("Hyphen") }
local KeySubtract = { KeyName = FName("Subtract") }
local KeySlash = { KeyName = FName("Slash") }
local KeyPeriod = { KeyName = FName("Period") }

local holdFrames = 0
local lastInputCheckTime = 0
local cachedDx = 0
local cachedDy = 0
local cachedDScale = 0
local cachedIsAnyHeld = false

local function UpdateEditCoordinates(sx, sy, dx, dy, dScale, moveAmount, scaleAmount)
    local screenW = (type(sx) == "number" and sx > 0) and sx or 1920.0
    local screenH = (type(sy) == "number" and sy > 0) and sy or 1080.0

    local scale = (CONFIG.Completionist and CONFIG.Completionist.HUDScale) or 1.0
    local cardW = 340.0 * scale
    local cardH = 148.0 * scale

    local maxScrollX = math.max(1.0, screenW - cardW)
    local maxScrollY = math.max(1.0, screenH - cardH)

    if CONFIG.Completionist.HUDX == nil then
        local defaultX = screenW - cardW - (30.0 * scale)
        CONFIG.Completionist.HUDX = tonumber(string.format("%.1f", (defaultX / maxScrollX) * 100.0))
    end
    if CONFIG.Completionist.HUDY == nil then
        local defaultY = 40.0 * scale
        CONFIG.Completionist.HUDY = tonumber(string.format("%.1f", (defaultY / maxScrollY) * 100.0))
    end

    local pctDx = (dx * moveAmount) / maxScrollX * 100.0
    local pctDy = (dy * moveAmount) / maxScrollY * 100.0

    CONFIG.Completionist.HUDX = math.max(0.0, math.min(100.0, CONFIG.Completionist.HUDX + pctDx))
    CONFIG.Completionist.HUDY = math.max(0.0, math.min(100.0, CONFIG.Completionist.HUDY + pctDy))

    CONFIG.Completionist.HUDX = tonumber(string.format("%.1f", CONFIG.Completionist.HUDX))
    CONFIG.Completionist.HUDY = tonumber(string.format("%.1f", CONFIG.Completionist.HUDY))
    CONFIG.Completionist.HUDAnchor = "Custom"

    if dScale ~= 0 then
        local currentScale = CONFIG.Completionist.HUDScale or 1.0
        local newScale = math.max(0.5, math.min(2.0, currentScale + (dScale * scaleAmount)))
        CONFIG.Completionist.HUDScale = tonumber(string.format("%.2f", newScale))
    end
end

local function HandleEditModeHolding(SizeX, SizeY)
    if not configMod.EditModeActive then
        holdFrames = 0
        return
    end

    local now = os.clock()
    -- Throttle polling to 50Hz (20ms interval) to eliminate C++ reflection overhead
    if now - lastInputCheckTime >= 0.02 then
        lastInputCheckTime = now

        local pc = utils.PlayerController()
        if not pc or not pc:IsValid() then return end

        local dx = 0
        local dy = 0
        local dScale = 0
        local isAnyHeld = false

        local isLeft = pc:IsInputKeyDown(KeyLeft)
        local isRight = pc:IsInputKeyDown(KeyRight)
        local isUp = pc:IsInputKeyDown(KeyUp)
        local isDown = pc:IsInputKeyDown(KeyDown)

        local isPlus = pc:IsInputKeyDown(KeyEquals)
                    or pc:IsInputKeyDown(KeyAdd)
                    or pc:IsInputKeyDown(KeyRightBracket)
                    or pc:IsInputKeyDown(KeyLeftBracket)
                    or pc:IsInputKeyDown(KeyBackslash)

        local isMinus = pc:IsInputKeyDown(KeyHyphen)
                     or pc:IsInputKeyDown(KeySubtract)
                     or pc:IsInputKeyDown(KeySlash)
                     or pc:IsInputKeyDown(KeyPeriod)

        if isLeft then dx = dx - 1; isAnyHeld = true end
        if isRight then dx = dx + 1; isAnyHeld = true end
        if isUp then dy = dy - 1; isAnyHeld = true end
        if isDown then dy = dy + 1; isAnyHeld = true end

        if isPlus then dScale = dScale + 1; isAnyHeld = true end
        if isMinus then dScale = dScale - 1; isAnyHeld = true end

        cachedDx = dx
        cachedDy = dy
        cachedDScale = dScale
        cachedIsAnyHeld = isAnyHeld
    end

    if cachedIsAnyHeld then
        holdFrames = holdFrames + 1
    else
        holdFrames = 0
        return
    end

    local speedMultiplier = 1.0
    if holdFrames > 45 then
        speedMultiplier = 3.5
    elseif holdFrames > 12 then
        speedMultiplier = 2.0
    end

    local moveAmount = 2.0 * speedMultiplier
    local scaleAmount = 0.005 * speedMultiplier

    local sx = SizeX
    if type(sx) == "userdata" or type(sx) == "table" then pcall(function() sx = sx:get() end) end
    local sy = SizeY
    if type(sy) == "userdata" or type(sy) == "table" then pcall(function() sy = sy:get() end) end

    pcall(UpdateEditCoordinates, sx, sy, cachedDx, cachedDy, cachedDScale, moveAmount, scaleAmount)
end

-- Hook into HUD Draw frame tick (ReceiveDrawHUD)
local isHUDHooked = false
local hasLoggedDraw = false
local hasLoggedHookFailure = false

local function RegisterHUDHook()
    if isHUDHooked then return end
    
    local status = pcall(function()
        RegisterHook("/Game/Pal/Blueprint/UI/BP_PalHUD_InGame.BP_PalHUD_InGame_C:ReceiveDrawHUD", function(self, SizeX, SizeY)
            if not hasLoggedDraw then
                hasLoggedDraw = true
                local sx, sy = SizeX, SizeY
                pcall(function() if type(sx) == "userdata" or type(sx) == "table" then sx = sx:get() end end)
                pcall(function() if type(sy) == "userdata" or type(sy) == "table" then sy = sy:get() end end)
                DebugPrint("ReceiveDrawHUD hook successfully firing! Screen Size: " .. tostring(sx) .. "x" .. tostring(sy))
            end
            local hud = self:get()
            if not hud or not hud:IsValid() then return end
            pcall(function() utils.NotePlayerController(hud.PlayerOwner) end)
            
            -- Apply continuous holding checks in edit mode
            HandleEditModeHolding(SizeX, SizeY)
            
            renderer.draw(
                hud, 
                tracker.activePlayers, 
                tracker.activeRelics, 
                tracker.activeChests, 
                tracker.activeEggs,
                tracker.activeCaves,
                tracker.activeLoot,
                tracker.activeNotes,
                tracker.activePals,
                tracker.activeFastTravel,
                tracker.activeHacks,
                tracker.activeBounties,
                tracker.cachedLocalPlayer,
                SizeX, SizeY
            )
            local sx, sy = SizeX, SizeY
            pcall(function()
                if type(sx) == "userdata" or type(sx) == "table" then sx = sx:get() end
                if type(sy) == "userdata" or type(sy) == "table" then sy = sy:get() end
            end)
            boundary.Draw(hud, sx, sy)
        end)
    end)
    
    if status then
        isHUDHooked = true
        DebugPrint("HUD ReceiveDrawHUD hook successfully registered via UE4SS!")
    else
        if not hasLoggedHookFailure then
            DebugPrint("Failed to register ReceiveDrawHUD hook (class might not be loaded yet). Background timer will retry silently...")
            hasLoggedHookFailure = true
        end
    end
end

-- Try to hook immediately (handles mid-game mod reloading)
RegisterHUDHook()

-- Listen for new HUD objects to hook when loaded (handles startup / level load)
NotifyOnNewObject("/Game/Pal/Blueprint/UI/BP_PalHUD_InGame.BP_PalHUD_InGame_C", function(hudObj)
    RegisterHUDHook()
end)

-- Start periodic background scan loop
local function StartPeriodicScan()
    local function loop()
        -- Robust hook retry to bypass NotifyOnNewObject bugs
        if not isHUDHooked then
            RegisterHUDHook()
        end
        
        local status, err = pcall(tracker.scan)
        if not status then
            print("[HUDLocator] ERROR in Scan loop: " .. tostring(err) .. "\n")
        end
        ExecuteWithDelay(CONFIG.Global.ScanIntervalMs, loop)
    end
    ExecuteWithDelay(CONFIG.Global.ScanIntervalMs, loop)
end

local function StartBeamFollow()
    local function loop()
        local status, err = pcall(beams.RefreshMobile)
        if not status then
            print("[HUDLocator] ERROR in beam follow: " .. tostring(err) .. "\n")
        end
        local ms = (CONFIG.Global and CONFIG.Global.BeamFollowIntervalMs) or 100
        if ms < 50 then ms = 50 end
        ExecuteWithDelay(ms, loop)
    end
    ExecuteWithDelay(100, loop)
end

-- Setup hotkeys

local function GetKey(keyStr, fallbackKey)
    if not keyStr then return fallbackKey end
    return Key[keyStr] or fallbackKey
end

local function ResolveModifier(modStr)
    if not modStr then return { ModifierKey.ALT } end
    local upper = string.upper(modStr)
    if upper == "ALT" then
        return { ModifierKey.ALT }
    elseif upper == "CTRL" or upper == "CONTROL" then
        return { ModifierKey.CTRL }
    elseif upper == "SHIFT" then
        return { ModifierKey.SHIFT }
    elseif upper == "NONE" or upper == "" then
        return {}
    else
        return { ModifierKey.ALT }
    end
end

local utilityModifier = ResolveModifier(CONFIG.Global.KeyBinds and CONFIG.Global.KeyBinds.Modifier or "ALT")

-- 5. HUD Config Menu Toggle (Alt + F6).
-- With the world map open, the same keys toggle the region boundary tool instead.
RegisterKeyBind(GetKey(CONFIG.Global.KeyBinds and CONFIG.Global.KeyBinds.ToggleMenu, Key.F6), utilityModifier, function()
    if boundary.TryToggle() then return end
    menu.Toggle()
end)

-- 6. HUD Edit Mode Toggle (Alt + F7)
RegisterKeyBind(GetKey(CONFIG.Global.KeyBinds and CONFIG.Global.KeyBinds.ToggleEditMode, Key.F7), utilityModifier, function()
    pcall(function()
        configMod.ToggleEditMode()
        if not configMod.EditModeActive then
            holdFrames = 0
        end
    end)
end)

-- 7. HUD Config Menu Navigation
RegisterKeyBind(GetKey(CONFIG.Global.KeyBinds and CONFIG.Global.KeyBinds.MenuUp, Key.UP_ARROW), {}, function()
    if menu.isOpen then menu.Navigate("up") end
end)

RegisterKeyBind(GetKey(CONFIG.Global.KeyBinds and CONFIG.Global.KeyBinds.MenuDown, Key.DOWN_ARROW), {}, function()
    if menu.isOpen then menu.Navigate("down") end
end)

RegisterKeyBind(GetKey(CONFIG.Global.KeyBinds and CONFIG.Global.KeyBinds.MenuLeft, Key.LEFT_ARROW), {}, function()
    if menu.isOpen then menu.Navigate("left") end
end)

RegisterKeyBind(GetKey(CONFIG.Global.KeyBinds and CONFIG.Global.KeyBinds.MenuRight, Key.RIGHT_ARROW), {}, function()
    if menu.isOpen then menu.Navigate("right") end
end)

-- 8. Alt+R: Reset HUD Coordinates in Edit Mode, or Reload Config outside Edit Mode
RegisterKeyBind(GetKey(CONFIG.Global.KeyBinds and CONFIG.Global.KeyBinds.ResetCoords, Key.R), utilityModifier, function()
    if menu.isOpen then return end

    if configMod.EditModeActive then
        pcall(function()
            CONFIG.Completionist.HUDX = nil
            CONFIG.Completionist.HUDY = nil
            CONFIG.Completionist.HUDScale = 1.0
            CONFIG.Completionist.HUDAnchor = "TopRight"
            popup.Show(configMod.GetTranslation("Popup_HUDReset", "HUD Position Reset to Default"), 120)
            configMod.DebugPrint("HUD coordinates and scale reset to default via modifier+R!")
        end)
    else
        local status, err = pcall(function()
            configMod.LoadConfig()
            tracker.SyncBeams()
        end)
        
        if status then
            print("[HUDLocator] Configuration reloaded successfully from central file." .. "\n")
            pcall(popup.Show, configMod.GetTranslation("Popup_HUDLoaded", "HUD Settings Reloaded"), 120)
        else
            print("[HUDLocator] ERROR: Failed to manually reload configuration: " .. tostring(err) .. "\n")
        end
    end
end)


-- Start scanning
StartPeriodicScan()
StartBeamFollow()

print("[HUDLocator] Mod Loaded Successfully!" .. "\n")

