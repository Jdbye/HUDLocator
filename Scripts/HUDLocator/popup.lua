local utils = require("HUDLocator.utils")

local M = {}

local PopupText = ""
local PopupTimer = 0
local MaxTimer = 180 -- ~3 seconds at 60fps

local mapBase = nil
local mapSearch = 0
local card = nil
local cardText = nil
local cardSlot = nil
local cardHost = nil

local function Alive(widget)
    return widget and widget.IsValid and widget:IsValid()
end

local function Shown(widget)
    if not Alive(widget) then return false end
    local code = ""
    pcall(function() code = tostring(widget:GetVisibility()) end)
    if code == "1" or code == "2" then return false end
    if string.find(code, "Collapsed", 1, true) or string.find(code, "Hidden", 1, true) then
        return false
    end
    local full = ""
    pcall(function() full = widget:GetFullName() or "" end)
    if string.find(full, "Default__", 1, true) then return false end
    return true
end

local function Construct(classPath, outer)
    local class = nil
    pcall(function() class = StaticFindObject(classPath) end)
    if not Alive(class) or not Alive(outer) then return nil end
    local widget = nil
    pcall(function() widget = StaticConstructObject(class, outer) end)
    if not Alive(widget) then return nil end
    return widget
end

local function HideCard()
    if Alive(card) then
        pcall(function() card:SetVisibility(1) end)
    end
end

local function MapOnScreen(widget)
    if not Alive(widget) then return false end
    local full = ""
    pcall(function() full = widget:GetFullName() or "" end)
    if string.find(full, "Default__", 1, true) then return false end
    local open = false
    pcall(function()
        if widget:IsVisible() == true then open = true end
    end)
    if not open then
        pcall(function()
            if widget:IsInViewport() == true then open = true end
        end)
    end
    return open
end

local function FindMap()
    if MapOnScreen(mapBase) then return mapBase end
    mapBase = nil
    if mapSearch > 0 then
        mapSearch = mapSearch - 1
        return nil
    end
    mapSearch = 15
    local widgets = nil
    pcall(function() widgets = FindAllOf("WBP_Map_Base_C") end)
    if not widgets then return nil end
    for _, widget in ipairs(widgets) do
        if MapOnScreen(widget) then
            mapBase = widget
            return widget
        end
    end
    return nil
end

-- HUD canvas text is underneath the world map. A user widget added to the
-- viewport at a high Z order is drawn above it.
local function EnsureCard(owner)
    if Alive(card) and Alive(cardText) and cardSlot then return true end
    HideCard()
    card, cardText, cardSlot, cardHost = nil, nil, nil, nil
    if not Alive(owner) then return false end
    local library, widgetClass, world = nil, nil, nil
    pcall(function() library = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end)
    pcall(function() widgetClass = StaticFindObject("/Script/UMG.UserWidget") end)
    pcall(function() world = owner:GetWorld() end)
    if not Alive(library) or not Alive(widgetClass) or not Alive(world) then return false end
    local widget = nil
    pcall(function() widget = library:Create(world, widgetClass, owner) end)
    if not Alive(widget) then return false end
    local tree = nil
    pcall(function() tree = widget.WidgetTree end)
    if not Alive(tree) then return false end
    local canvas = Construct("/Script/UMG.CanvasPanel", widget)
    local border = Construct("/Script/UMG.Border", canvas or widget)
    local text = Construct("/Script/UMG.TextBlock", border or widget)
    if not canvas or not border or not text then return false end
    pcall(function() tree.RootWidget = canvas end)
    pcall(function() border:SetBrushColor({ R = 0.05, G = 0.07, B = 0.15, A = 0.92 }) end)
    pcall(function() border:SetPadding({ Left = 14, Top = 8, Right = 14, Bottom = 8 }) end)
    pcall(function() border:AddChild(text) end)
    pcall(function() text.Font.Size = 10 end)
    pcall(function() text:SetJustification(1) end)
    pcall(function() text:SetAutoWrapText(false) end)
    pcall(function() widget.bIsFocusable = false end)
    pcall(function() widget:SetVisibility(4) end)
    local slot = nil
    pcall(function() slot = canvas:AddChildToCanvas(border) end)
    if not slot then return false end
    -- A new canvas slot stretches to fill the viewport, which scales the
    -- text up and makes a pixel position miss the center. Pin it to one point.
    pcall(function() slot:SetMinimum({ X = 0.5, Y = 0.22 }) end)
    pcall(function() slot:SetMaximum({ X = 0.5, Y = 0.22 }) end)
    pcall(function() slot:SetAlignment({ X = 0.5, Y = 0.5 }) end)
    pcall(function() slot:SetPosition({ X = 0.0, Y = 0.0 }) end)
    pcall(function() slot:SetAutoSize(true) end)
    pcall(function() slot:SetZOrder(1) end)
    pcall(function() widget:AddToViewport(100000) end)
    card = widget
    cardText = text
    cardSlot = slot
    cardHost = owner
    return true
end

local function PresentOverlay(hud, alpha)
    if not (Alive(card) and Alive(cardText) and cardSlot) then
        if not EnsureCard(utils.PlayerController(hud)) then return false end
    end
    pcall(function() card:AddToViewport(100000) end)
    pcall(function() card:SetVisibility(4) end)
    pcall(function() cardSlot:SetMinimum({ X = 0.5, Y = 0.22 }) end)
    pcall(function() cardSlot:SetMaximum({ X = 0.5, Y = 0.22 }) end)
    pcall(function() cardSlot:SetAlignment({ X = 0.5, Y = 0.5 }) end)
    pcall(function() cardSlot:SetPosition({ X = 0.0, Y = 0.0 }) end)
    pcall(function() cardSlot:SetAutoSize(true) end)
    pcall(function() card:SetRenderOpacity(alpha) end)
    pcall(function() cardText:SetText(FText(PopupText)) end)
    pcall(function()
        cardText:SetColorAndOpacity({
            SpecifiedColor = { R = 0.0, G = 0.95, B = 1.0, A = alpha },
            ColorUseRule = 0,
        })
    end)
    return true
end

function M.Show(text, duration)
    PopupText = text
    PopupTimer = duration or MaxTimer
    mapSearch = 0
end

function M.Draw(hud, SizeX, SizeY)
    if PopupTimer > 0 then
        -- Color theme matching settings menu
        local R, G, B = 0.0, 0.95, 1.0
        local A = 1.0
        
        -- Fade out effect in the last 60 frames
        if PopupTimer < 60 then
            A = PopupTimer / 60.0
        end

        -- Unwrap UE4SS RemoteUnrealParams safely
        local sx = SizeX
        if type(sx) == "userdata" or type(sx) == "table" then
            local status, val = pcall(function() return sx:get() end)
            if status then sx = val end
        end
        local sy = SizeY
        if type(sy) == "userdata" or type(sy) == "table" then
            local status, val = pcall(function() return sy:get() end)
            if status then sy = val end
        end

        -- Use a default 1080p fallback if size is not provided or invalid
        local screenW = (type(sx) == "number" and sx > 0) and sx or 1920.0
        local screenH = (type(sy) == "number" and sy > 0) and sy or 1080.0
        
        local y = screenH / 4.0

        -- Parse lines (handling newlines)
        local lines = {}
        for line in string.gmatch(PopupText, "[^\r\n]+") do
            table.insert(lines, line)
        end
        if #lines == 0 then lines = { PopupText } end

        local font, scaleMult = utils.GetFontAndScale()
        local baseScale = 1.25
        local finalScale = baseScale * scaleMult
        
        local lineH = font and (26.0 * finalScale) or (20.0 * finalScale)
        local lineGap = 6.0 * scaleMult
        local padX = 25.0
        local padY = 15.0
        local bw = 2.0

        -- Calculate max line width
        local maxW = 0
        local widths = {}
        for i, line in ipairs(lines) do
            local w = utils.GetTextSize(hud, line, baseScale)
            if not w or w == 0 then
                w = utils.GetStringLength(line) * 9.5 * finalScale
            end
            widths[i] = w
            if w > maxW then
                maxW = w
            end
        end

        -- Box dimensions
        local contentH = #lines * lineH + (#lines - 1) * lineGap
        local boxW = maxW + padX * 2
        local boxH = contentH + padY * 2
        
        local boxX = screenW / 2.0 - boxW / 2.0
        local boxY = y - boxH / 2.0

        if PresentOverlay(hud, A) then
            PopupTimer = PopupTimer - 1
            return
        end

        -- Panel colors (Glassmorphism look matching menu.lua)
        local cardBg = { R = 0.05, G = 0.07, B = 0.15, A = 0.85 * A }
        local borderCol = { R = 0.0, G = 0.95, B = 1.0, A = 0.6 * A }
        local borderShadow = { R = 0.0, G = 0.0, B = 0.0, A = 0.9 * A }

        -- Draw shadow
        hud:DrawRect(borderShadow, boxX - bw, boxY - bw, boxW + bw * 2, boxH + bw * 2)
        -- Draw main card background
        hud:DrawRect(cardBg, boxX, boxY, boxW, boxH)
        -- Draw neon accent line at the top
        hud:DrawRect(borderCol, boxX, boxY, boxW, 2.5)

        -- Draw lines of text
        local currentY = boxY + padY
        for i, line in ipairs(lines) do
            local w = widths[i]
            local textX = boxX + (boxW / 2.0) - (w / 2.0)
            
            -- Title is neon cyan, secondary lines are off-white
            local textColor = { R = R, G = G, B = B, A = A }
            if i > 1 then
                textColor = { R = 0.9, G = 0.9, B = 0.95, A = A * 0.9 }
            end
            
            -- Drop shadow
            utils.DrawText(hud, line, { R = 0.0, G = 0.0, B = 0.0, A = A * 0.8 }, textX + 1.5, currentY + 1.5, baseScale, false)
            -- Main text
            utils.DrawText(hud, line, textColor, textX, currentY, baseScale, false)
            
            currentY = currentY + lineH + lineGap
        end

        PopupTimer = PopupTimer - 1
    else
        HideCard()
    end
end

return M
