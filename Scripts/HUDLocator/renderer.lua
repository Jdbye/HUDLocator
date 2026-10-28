local configMod = require("HUDLocator.config")
local popup = require("HUDLocator.popup")
local menu = require("HUDLocator.menu")
local utils = require("HUDLocator.utils")
local completion = require("HUDLocator.completion")
local beams = require("HUDLocator.beams")
local CONFIG = configMod.CONFIG

local M = {}

-- Pre-allocated static table buffers to prevent GC allocations during ReceiveDrawHUD frame ticks
local playerPosBuffer = { X = 0.0, Y = 0.0, Z = 0.0 }
local textWorldPosBuffer = { X = 0.0, Y = 0.0, Z = 0.0 }

-- CanvasPanel_WorkerSimpleInfo stays at visibility 4 outside a base, and
-- GetInsideBaseCampModel returns a nameless wrapper every call. The widgets
-- that actually fold away are the camp-name / worker-info children.
local cachedCanvas = nil
local cachedCanvasAddress = nil
local cachedWidgets = {}
local baseHudPoll = 0
local cachedHudCanvas = nil
local gameHudPoll = 0
local gameHudHidden = false
local boundHudAddress = nil

local function IsLive(obj)
    if type(obj) ~= "userdata" then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and (valid == true or valid == 1)
end

local function FullName(obj)
    local name = ""
    if obj == nil then return "" end
    pcall(function() name = obj:GetFullName() end)
    return name or ""
end

local function IsDefaultObject(obj)
    return string.find(FullName(obj), "Default__", 1, true) ~= nil
end

local function InViewport(obj)
    local shown = false
    local ok = pcall(function() shown = obj:IsInViewport() end)
    return ok and (shown == true or shown == 1)
end

local function ObjectAddress(obj)
    if type(obj) ~= "userdata" then return nil end
    local ok, addr = pcall(function() return obj:GetAddress() end)
    if ok and type(addr) == "number" and addr ~= 0 then return addr end
    return nil
end

local function OwningPlayerAddress(obj)
    if type(obj) ~= "userdata" then return nil end
    local pc = nil
    pcall(function() pc = obj:GetOwningPlayer() end)
    if type(pc) ~= "userdata" then
        pcall(function() pc = obj:GetOwningPlayerController() end)
    end
    if type(pc) ~= "userdata" then
        pcall(function() pc = obj.PlayerOwner end)
    end
    return ObjectAddress(pc)
end

local function WorldAddress(obj)
    if type(obj) ~= "userdata" then return nil end
    local world = nil
    pcall(function() world = obj:GetWorld() end)
    return ObjectAddress(world)
end

-- A widget left over from the previous load can still pass IsValid after
-- returning to the menu. Only trust one owned by this HUD's player and world.
local function BelongsToSession(widget, hud)
    if not IsLive(widget) or type(hud) ~= "userdata" then return false end
    local hudPc = OwningPlayerAddress(hud)
    local widgetPc = OwningPlayerAddress(widget)
    if hudPc and widgetPc then return hudPc == widgetPc end
    if hudPc and not widgetPc then return false end
    local hudWorld = WorldAddress(hud)
    local widgetWorld = WorldAddress(widget)
    if hudWorld and widgetWorld then return hudWorld == widgetWorld end
    return InViewport(widget)
end

local function ClearWidgetCache()
    cachedCanvas = nil
    cachedCanvasAddress = nil
    cachedWidgets = {}
    cachedHudCanvas = nil
    gameHudHidden = false
    gameHudPoll = 0
end

local function NoteHud(hud)
    local addr = ObjectAddress(hud)
    if addr == nil then return end
    if boundHudAddress ~= nil and addr ~= boundHudAddress then
        ClearWidgetCache()
    end
    boundHudAddress = addr
end

local function Unwrap(value)
    if type(value) ~= "userdata" then return value end
    local label = nil
    local okLabel = pcall(function() label = tostring(value) end)
    if okLabel and type(label) == "string" and string.find(label, "RemoteUnrealParam", 1, true) then
        local inner = nil
        local ok = pcall(function() inner = value:get() end)
        if ok and inner ~= nil then return inner end
    end
    return value
end

local function WidgetName(widget)
    local name = nil
    local ok = pcall(function() name = widget:GetName() end)
    if not ok or name == nil then return "" end
    if type(name) == "string" then return name end
    local text = ""
    pcall(function() text = name:ToString() end)
    if text == "" then text = tostring(name) end
    return text or ""
end

local function UsableWidget(widget)
    widget = Unwrap(widget)
    if type(widget) ~= "userdata" then return nil end
    if IsLive(widget) then return widget end
    local vis = nil
    local ok = pcall(function() vis = widget:GetVisibility() end)
    if ok and vis ~= nil then return widget end
    return nil
end

-- GetName() is not the blueprint variable name, so the cache has to be keyed
-- by the property we asked for. Otherwise every lookup stays missing.
local function Keep(name, widget)
    if cachedWidgets[name] ~= nil then return true end
    local usable = UsableWidget(widget)
    if not usable then return false end
    cachedWidgets[name] = usable
    return true
end

local function TakeProperty(widget, name)
    if type(widget) ~= "userdata" then return end
    local child = nil
    local ok = pcall(function() child = widget[name] end)
    if ok and Keep(name, child) then return end
    pcall(function() child = widget:GetWidgetFromName(name) end)
    Keep(name, child)
end

local function WalkWidgets(widget, depth)
    widget = Unwrap(widget)
    if depth > 6 or not UsableWidget(widget) then return end
    local count = 0
    local ok = pcall(function() count = widget:GetChildrenCount() end)
    if not ok or type(count) ~= "number" or count <= 0 then return end
    if count > 30 then count = 30 end
    for i = 0, count - 1 do
        local child = nil
        pcall(function() child = widget:GetChildAt(i) end)
        local usable = UsableWidget(child)
        if usable then
            local childName = WidgetName(usable)
            if childName ~= "" then
                for _, wanted in ipairs({
                    "WBP_IngameMenu_Task_Simple",
                    "CanvasPanel_WorkerSimpleInfo",
                    "CanvasPanel_WorkerInfo",
                    "Text_BaseCampName",
                    "HorizontalBox_Border_Top",
                    "HorizontalBox_Border_Bottom",
                    "HorizontalBox_WorkMode",
                    "VerticalBox",
                    "VerticalBox_All",
                }) do
                    if cachedWidgets[wanted] == nil and string.find(childName, wanted, 1, true) then
                        cachedWidgets[wanted] = usable
                    end
                end
            end
            WalkWidgets(usable, depth + 1)
        end
    end
end

local function QuestCanvasFromHud(hud)
    if type(hud) ~= "userdata" then return nil end
    local found = nil
    local function Walk(widget, depth)
        if found or depth > 4 then return end
        widget = Unwrap(widget)
        if not UsableWidget(widget) then return end
        local quest = nil
        pcall(function() quest = widget.WBP_QuestAndBaseCampInfoCanvas end)
        quest = UsableWidget(quest)
        if quest and not IsDefaultObject(quest) then
            found = quest
            return
        end
        local count = 0
        pcall(function() count = widget:GetChildrenCount() end)
        if type(count) ~= "number" or count <= 0 then return end
        if count > 40 then count = 40 end
        for i = 0, count - 1 do
            local child = nil
            pcall(function() child = widget:GetChildAt(i) end)
            Walk(child, depth + 1)
            if found then return end
        end
    end
    pcall(function()
        local layout = hud.HUDLayout
        if not layout or not layout:IsValid() then return end
        Walk(layout.HUDCanvas or layout, 0)
    end)
    return found
end

local function QuestCanvasFromSearch(hud)
    local chosen = nil
    local fallback = nil
    pcall(function()
        local list = FindAllOf("WBP_QuestAndBaseCampInfoCanvas_C")
        if not list then return end
        for _, widget in ipairs(list) do
            if IsLive(widget) and not IsDefaultObject(widget) and BelongsToSession(widget, hud) then
                if InViewport(widget) then
                    chosen = widget
                    break
                end
                fallback = fallback or widget
            end
        end
    end)
    return chosen or fallback
end

local function RefreshBaseWidgets(hud)
    local live = QuestCanvasFromHud(hud)
    if not IsLive(live) then
        live = QuestCanvasFromSearch(hud)
    end
    if not IsLive(live) then
        cachedCanvas = nil
        cachedCanvasAddress = nil
        cachedWidgets = {}
        return
    end
    local liveAddress = ObjectAddress(live)
    if liveAddress ~= nil and liveAddress == cachedCanvasAddress
        and (cachedWidgets.Text_BaseCampName or cachedWidgets.CanvasPanel_WorkerInfo or cachedWidgets.VerticalBox or cachedWidgets.HorizontalBox_Border_Top) then
        return
    end
    cachedCanvas = live
    cachedCanvasAddress = liveAddress
    cachedWidgets = {}

    local root = nil
    pcall(function() root = cachedCanvas:GetRootWidget() end)
    WalkWidgets(root or cachedCanvas, 0)
    TakeProperty(cachedCanvas, "WBP_IngameMenu_Task_Simple")
    TakeProperty(cachedCanvas, "CanvasPanel_WorkerSimpleInfo")
    TakeProperty(cachedCanvas, "VerticalBox")
    TakeProperty(cachedCanvas, "HorizontalBox_Border_Top")
    TakeProperty(cachedCanvas, "HorizontalBox_Border_Bottom")
    local task = cachedWidgets.WBP_IngameMenu_Task_Simple
    WalkWidgets(task, 0)
    TakeProperty(task, "CanvasPanel_WorkerInfo")
    TakeProperty(task, "Text_BaseCampName")
    TakeProperty(task, "HorizontalBox_WorkMode")
    TakeProperty(task, "VerticalBox_All")
end

-- 1 = Collapsed, 2 = Hidden. A child can stay at 4 while a parent is collapsed.
local function VisibilityCode(widget)
    if not IsLive(widget) then return "missing" end
    local vis = nil
    local ok = pcall(function() vis = widget:GetVisibility() end)
    if not ok or vis == nil then return "err" end
    return tostring(vis)
end

local function CodeIsShown(code)
    local n = tonumber(code)
    if n == nil then return nil end
    return n ~= 1 and n ~= 2
end

local function ChainShown(widget)
    local current = widget
    for _ = 1, 12 do
        if not IsLive(current) then return false end
        local shown = CodeIsShown(VisibilityCode(current))
        if shown == false then return false end
        if shown == nil then return false end
        local parent = nil
        pcall(function() parent = current:GetParent() end)
        parent = Unwrap(parent)
        if not IsLive(parent) or parent == current then break end
        current = parent
    end
    return true
end

local function CampNameText(widget)
    if not IsLive(widget) then return "" end
    local value = nil
    local ok = pcall(function() value = widget:GetText() end)
    if not ok or value == nil then return "" end
    local text = ""
    pcall(function() text = value:ToString() end)
    if text == "" then text = tostring(value) end
    if text == "nil" or string.find(text, "RemoteUnrealParam", 1, true) then return "" end
    return text
end

local function BaseCampHudActive(hud)
    baseHudPoll = baseHudPoll + 1
    if baseHudPoll >= 20 or not IsLive(cachedCanvas) then
        baseHudPoll = 0
        RefreshBaseWidgets(hud)
    end
    if not IsLive(cachedCanvas) then return false end

    local worker = cachedWidgets.CanvasPanel_WorkerInfo
    local campText = cachedWidgets.Text_BaseCampName
    local border = cachedWidgets.HorizontalBox_Border_Top
    local vertical = cachedWidgets.VerticalBox
    local name = CampNameText(campText)

    -- The camp name and worker panel stay at visibility 4 outside a base.
    -- HorizontalBox_Border_Top is the piece that collapses (1) on the way out
    -- and comes back as HitTestInvisible (3) on the way in.
    local inside = false
    if IsLive(border) then
        inside = ChainShown(border)
    elseif IsLive(campText) then
        inside = ChainShown(campText) and name ~= ""
    elseif IsLive(worker) then
        inside = ChainShown(worker)
    elseif IsLive(vertical) then
        inside = ChainShown(vertical)
    end

    return inside
end

-- Cutscenes and loading screens collapse the in-game HUD layout. Follow that
-- The player UI root stays visible during cutscenes. The quest/base panel
-- inside it is what collapses.
local function LooksLikePlayerUi(widget)
    local name = WidgetName(widget)
    if name ~= "" and string.find(name, "WBP_PlayerUI", 1, true) then return true end
    return string.find(FullName(widget), "WBP_PlayerUI_C", 1, true) ~= nil
end

local function FindPlayerUi(hud)
    if type(hud) ~= "userdata" then return nil end
    local found = nil
    local function Walk(widget, depth)
        if found or depth > 4 then return end
        widget = Unwrap(widget)
        if not UsableWidget(widget) then return end
        if LooksLikePlayerUi(widget) then
            found = widget
            return
        end
        local count = 0
        pcall(function() count = widget:GetChildrenCount() end)
        if type(count) ~= "number" or count <= 0 then return end
        if count > 40 then count = 40 end
        for i = 0, count - 1 do
            local child = nil
            pcall(function() child = widget:GetChildAt(i) end)
            Walk(child, depth + 1)
            if found then return end
        end
    end
    pcall(function()
        local layout = hud.HUDLayout
        if not layout or not layout:IsValid() then return end
        Walk(layout.HUDCanvas or layout, 0)
    end)
    return found
end

local function OpacityHidden(widget)
    local opacity = nil
    local ok = pcall(function() opacity = widget:GetRenderOpacity() end)
    return ok and type(opacity) == "number" and opacity <= 0.02
end

local function OwnHidden(widget)
    if not IsLive(widget) then return false end
    local code = VisibilityCode(widget)
    if code == "1" or code == "2" then return true end
    return OpacityHidden(widget)
end

local function ChildWidget(widget, prop)
    local child = nil
    pcall(function() child = widget[prop] end)
    return Unwrap(child)
end

-- Visibility and opacity, including a parent that was collapsed or faded out.
local function EffectivelyHidden(widget)
    local current = widget
    for _ = 1, 12 do
        if not IsLive(current) then return false end
        if OwnHidden(current) then return true end
        local parent = nil
        pcall(function() parent = current:GetParent() end)
        parent = Unwrap(parent)
        if not IsLive(parent) or parent == current then break end
        current = parent
    end
    return false
end

local function CutscenePlaying(hud)
    local controller = nil
    pcall(function() controller = hud.PlayerOwner end)
    if not IsLive(controller) then return false end
    local comp = nil
    pcall(function() comp = controller.CutsceneComponent end)
    if not IsLive(comp) then return false end
    local ok, result = pcall(function() return comp:IsPlayingCutscene() end)
    return ok and (result == true or result == 1)
end

local cachedBossSeq = nil
local bossSeqSearchAt = 0

local function BossSequenceIsCinematic(seq)
    if not IsLive(seq) then return false end
    local kind = nil
    pcall(function()
        if seq.GetCurrentSequenceType then
            kind = seq:GetCurrentSequenceType()
        else
            kind = seq.CurrentSequenceType
        end
    end)
    local n = tonumber(kind)
    if n == 3 or n == 5 then return true end
    local text = string.lower(tostring(kind or ""))
    if string.find(text, "opening", 1, true) or string.find(text, "ending", 1, true) then
        return true
    end
    local current = nil
    pcall(function() current = seq.CurrentSequence end)
    if not IsLive(current) then return false end
    local full = string.lower(FullName(current))
    return string.find(full, "sequence_opening", 1, true) ~= nil
        or string.find(full, "sequence_ending", 1, true) ~= nil
end

-- Opening and Ending are the tower cinematics. Combat keeps the HUD.
-- FindAllOf walks every live object, so a miss must not search again next frame.
local function BossCinematicPlaying()
    if not IsLive(cachedBossSeq) then
        local now = os.clock()
        if now >= bossSeqSearchAt then
            bossSeqSearchAt = now + 1.0
            pcall(function()
                local list = FindAllOf("PalBossBattleSequencer")
                if not list then return end
                local fallback = nil
                for _, seq in ipairs(list) do
                    if IsLive(seq) and not IsDefaultObject(seq) then
                        if BossSequenceIsCinematic(seq) then
                            cachedBossSeq = seq
                            break
                        end
                        fallback = fallback or seq
                    end
                end
                if not IsLive(cachedBossSeq) then cachedBossSeq = fallback end
            end)
        end
    end
    return BossSequenceIsCinematic(cachedBossSeq)
end

local gameplayHidden = false
local gameplayHiddenAt = 0

local function GameplayHudHidden(playerUi, hud)
    -- Widget reflection and the boss search are too expensive to run every draw.
    local now = os.clock()
    if now < gameplayHiddenAt then return gameplayHidden end
    gameplayHiddenAt = now + 0.25

    local hidden = false
    if OwnHidden(playerUi) then
        hidden = true
    else
        local root = ChildWidget(playerUi, "CanvasPanel_Root")
        if OwnHidden(root) then
            hidden = true
        elseif CutscenePlaying(hud) or BossCinematicPlaying() then
            hidden = true
        else
            -- The quest panel stays up through most of a tower intro and only
            -- collapses for the pose. The gauge and compass are the HUD that hides.
            local side = ChildWidget(playerUi, "WBP_PlayerSideInfo_Separated")
            local compass = ChildWidget(playerUi, "WBP_Ingame_Compass")
            if EffectivelyHidden(side) and EffectivelyHidden(compass) then
                hidden = true
            else
                local quest = ChildWidget(playerUi, "WBP_QuestAndBaseCampInfoCanvas")
                hidden = EffectivelyHidden(quest)
            end
        end
    end
    gameplayHidden = hidden
    return gameplayHidden
end

local function GameHudHidden(hud)
    gameHudPoll = gameHudPoll + 1
    if not IsLive(cachedHudCanvas) or gameHudPoll >= 30 then
        gameHudPoll = 0
        local live = FindPlayerUi(hud)
        if IsLive(live) then
            cachedHudCanvas = live
        end
    end
    if not IsLive(cachedHudCanvas) then
        gameHudHidden = false
        return false
    end
    gameHudHidden = GameplayHudHidden(cachedHudCanvas, hud)
end

-- Pre-allocated color tables for Progress Tracker Card and Edit Mode
local cardBgCol = { R = 0.05, G = 0.07, B = 0.15, A = 0.85 }
local cardBorderCol = { R = 0.0, G = 0.95, B = 1.0, A = 0.6 }
local cardStripCol = { R = 0.0, G = 0.95, B = 1.0, A = 0.6 }
local cardTitleCol = { R = 0.0, G = 0.95, B = 1.0, A = 1.0 }
local cardTextCol = { R = 0.9, G = 0.9, B = 0.95, A = 1.0 }
local cardPctCol = { R = 0.0, G = 0.96, B = 0.83, A = 1.0 }
local cardBarBgCol = { R = 0.15, G = 0.15, B = 0.25, A = 0.8 }
local cardBarFillCol = { R = 0.0, G = 0.96, B = 0.83, A = 0.9 }

local editBorderCol = { R = 0.0, G = 0.95, B = 1.0, A = 0.8 }
local editBgCol = { R = 0.0, G = 0.1, B = 0.2, A = 0.35 }
local bannerBgCol = { R = 0.02, G = 0.05, B = 0.12, A = 0.92 }
local editBannerTextCol1 = { R = 0.0, G = 1.0, B = 0.8, A = 1.0 }
local editBannerTextCol2 = { R = 0.9, G = 0.9, B = 0.95, A = 0.9 }

local modalBgCol = { R = 0.04, G = 0.06, B = 0.12, A = 0.92 }
local modalBorderCol = { R = 0.0, G = 0.95, B = 1.0, A = 0.8 }
local modalShadowCol = { R = 0.0, G = 0.0, B = 0.0, A = 0.95 }
local modalHeaderCol = { R = 0.0, G = 0.95, B = 1.0, A = 1.0 }
local modalSepCol = { R = 0.2, G = 0.25, B = 0.35, A = 0.5 }
local modalCurrBgCol = { R = 0.0, G = 0.3, B = 0.4, A = 0.35 }
local modalNormalBgCol = { R = 0.08, G = 0.1, B = 0.18, A = 0.6 }
local modalCurrBorderCol = { R = 0.0, G = 0.96, B = 0.83, A = 0.9 }
local modalNormalBorderCol = { R = 0.2, G = 0.2, B = 0.3, A = 0.4 }
local modalCurrTextCol = { R = 0.0, G = 0.96, B = 0.83, A = 1.0 }
local modalNormalTextCol = { R = 0.95, G = 0.95, B = 1.0, A = 1.0 }
local modalDetTextCol = { R = 0.8, G = 0.85, B = 0.9, A = 1.0 }

local cachedEditBanner1 = nil
local cachedEditBanner2 = nil

local drawnBoxCount = 0
local drawnBoxes = {}
for i = 1, 150 do
    drawnBoxes[i] = { x = 0.0, y = 0.0, w = 0.0, h = 0.0 }
end

-- Render tracker label (either box style or simple text style)
local function DrawTrackerLabel(hud, worldPos, nameStr, distStr, style, screenW, screenH, subStr, nameColorOverride, bracketDistStr, subItems)
    textWorldPosBuffer.X = worldPos.X
    textWorldPosBuffer.Y = worldPos.Y
    textWorldPosBuffer.Z = worldPos.Z + style.TextOffsetZ
    local ueTextScreen = hud:Project(textWorldPosBuffer, false)
    
    -- Optimize: Read .Z first, and conditionally evaluate .X and .Y to avoid reflection overhead for off-screen items
    local textScreenZ = ueTextScreen.Z
    if textScreenZ <= 0.0 then return end

    local textScreenX = ueTextScreen.X
    local textScreenY = ueTextScreen.Y
    
    -- Screen Viewport Bounds Culling: Only render text for items visible on the screen
    local margin = 100.0
    local isVisibleOnScreen = (textScreenX >= -margin) and (textScreenX <= screenW + margin)
                          and (textScreenY >= -margin) and (textScreenY <= screenH + margin)
    
    if isVisibleOnScreen then
        local font, scaleMult = utils.GetFontAndScale()
        local fontScale = style.FontScale * scaleMult
        local smallFontScale = style.SmallFontScale * scaleMult
        local nameColor = nameColorOverride or style.NameColor
        
        local charW = style.FontCharW
        local lineH = style.FontLineH
        if font then
            charW = charW * 1.6
            lineH = lineH * 2.8
        end

        local useMultiColor = (style.UseRarityColors ~= false) and subItems and (#subItems > 0)
        local hasSub = (subStr and subStr ~= "") or useMultiColor
        local subH = hasSub and (lineH * smallFontScale) or 0
        local lineGap = font and 6.0 or 4.0

        local subW = 0
        local sepW = 0
        if useMultiColor then
            sepW = utils.GetTextSize(hud, ", ", style.SmallFontScale)
            if not sepW or sepW == 0 then sepW = 2 * charW * smallFontScale end
            for i = 1, #subItems do
                local item = subItems[i]
                local itemW = utils.GetTextSize(hud, item.name, style.SmallFontScale)
                if not itemW or itemW == 0 then itemW = utils.GetStringLength(item.name) * charW * smallFontScale end
                subW = subW + itemW
                if i < #subItems then
                    subW = subW + sepW
                end
            end
        elseif subStr and subStr ~= "" then
            subW = utils.GetTextSize(hud, subStr, style.SmallFontScale)
            if not subW or subW == 0 then
                subW = utils.GetStringLength(subStr) * charW * smallFontScale
            end
        end

        local nameW = utils.GetTextSize(hud, nameStr, style.FontScale)
        if not nameW or nameW == 0 then
            nameW = utils.GetStringLength(nameStr) * charW * fontScale
        end

        local distPartStr = bracketDistStr or (distStr and ("[" .. distStr .. "]") or "")
        local distW = 0
        if style.DrawBox then
            if distStr then
                distW = utils.GetTextSize(hud, distStr, style.SmallFontScale)
                if not distW or distW == 0 then distW = utils.GetStringLength(distStr) * charW * smallFontScale end
            end
        else
            if distPartStr ~= "" then
                distW = utils.GetTextSize(hud, distPartStr, style.SmallFontScale)
                if not distW or distW == 0 then distW = utils.GetStringLength(distPartStr) * charW * smallFontScale end
            end
        end

        local nameH  = lineH * fontScale
        local distH  = distStr and (lineH * smallFontScale) or 0
        local contentW = math.max(nameW, distW, subW)
        local contentH = nameH + (distStr and (lineGap + distH) or 0) + (subH > 0 and (lineGap + subH) or 0)

        local finalScreenY = textScreenY
        for i = 1, drawnBoxCount do
            local b = drawnBoxes[i]
            local dx = math.abs(textScreenX - b.x)
            local dy = math.abs(finalScreenY - b.y)
            if dx < (contentW + b.w) * 0.48 and dy < (contentH + b.h) * 0.55 then
                finalScreenY = b.y - (contentH + b.h) * 0.5 - 4.0
            end
        end

        if drawnBoxCount < 150 then
            drawnBoxCount = drawnBoxCount + 1
            local b = drawnBoxes[drawnBoxCount]
            b.x = textScreenX
            b.y = finalScreenY
            b.w = contentW
            b.h = contentH
        end

        if style.DrawBox then
            local bw     = style.BorderWidth
            local padX = style.BoxPadX
            local padY = style.BoxPadY
            if font then
                padX = padX + 4.0
                padY = padY + 2.0
            end
            
            local boxW = contentW + padX * 2
            local boxH = contentH + padY * 2
            
            local boxX = textScreenX - boxW * 0.5
            local boxY = finalScreenY - boxH * 0.5
 
            -- Draw border
            hud:DrawRect(style.BorderColor, boxX - bw, boxY - bw, boxW + bw * 2, boxH + bw * 2)
 
            -- Draw background fill box
            hud:DrawRect(style.BoxColor, boxX, boxY, boxW, boxH)
            
            local nameX = textScreenX - nameW * 0.5
            local nameY = boxY + padY
            
            utils.DrawText(hud, nameStr, nameColor, nameX, nameY, style.FontScale, false)
            
            local nextY = nameY + nameH + lineGap
            if useMultiColor then
                local curX = textScreenX - subW * 0.5
                for i = 1, #subItems do
                    local item = subItems[i]
                    local itemW = utils.GetTextSize(hud, item.name, style.SmallFontScale)
                    if not itemW or itemW == 0 then itemW = utils.GetStringLength(item.name) * charW * smallFontScale end
                    utils.DrawText(hud, item.name, item.color or nameColor, curX, nextY, style.SmallFontScale, false)
                    curX = curX + itemW
                    if i < #subItems then
                        utils.DrawText(hud, ", ", style.DistColor or style.BorderColor, curX, nextY, style.SmallFontScale, false)
                        curX = curX + sepW
                    end
                end
                nextY = nextY + subH + lineGap
            elseif subStr and subStr ~= "" then
                local subX = textScreenX - subW * 0.5
                utils.DrawText(hud, subStr, nameColor, subX, nextY, style.SmallFontScale, false)
                nextY = nextY + subH + lineGap
            end

            if distStr then
                local distX = textScreenX - distW * 0.5
                utils.DrawText(hud, distStr, style.DistColor, distX, nextY, style.SmallFontScale, false)
            end
        else
            -- Simple text format: Name \n SubText \n [Distance]
            local startX = textScreenX - nameW * 0.5
            local simpleY = finalScreenY - contentH * 0.5
            
            utils.DrawText(hud, nameStr, style.BorderColor, startX + 1.0, simpleY + 1.0, style.FontScale, false)
            utils.DrawText(hud, nameStr, nameColor, startX, simpleY, style.FontScale, false)
            
            local nextY = simpleY + nameH + lineGap
            if useMultiColor then
                local curX = textScreenX - subW * 0.5
                for i = 1, #subItems do
                    local item = subItems[i]
                    local itemW = utils.GetTextSize(hud, item.name, style.SmallFontScale)
                    if not itemW or itemW == 0 then itemW = utils.GetStringLength(item.name) * charW * smallFontScale end
                    utils.DrawText(hud, item.name, style.BorderColor, curX + 1.0, nextY + 1.0, style.SmallFontScale, false)
                    utils.DrawText(hud, item.name, item.color or nameColor, curX, nextY, style.SmallFontScale, false)
                    curX = curX + itemW
                    if i < #subItems then
                        utils.DrawText(hud, ", ", style.BorderColor, curX + 1.0, nextY + 1.0, style.SmallFontScale, false)
                        utils.DrawText(hud, ", ", style.DistColor or style.BorderColor, curX, nextY, style.SmallFontScale, false)
                        curX = curX + sepW
                    end
                end
                nextY = nextY + subH + lineGap
            elseif subStr and subStr ~= "" then
                local subX = textScreenX - subW * 0.5
                utils.DrawText(hud, subStr, style.BorderColor, subX + 1.0, nextY + 1.0, style.SmallFontScale, false)
                utils.DrawText(hud, subStr, nameColor, subX, nextY, style.SmallFontScale, false)
                nextY = nextY + subH + lineGap
            end

            if distStr then
                local distX = textScreenX - distW * 0.5
                utils.DrawText(hud, distPartStr, style.BorderColor, distX + 1.0, nextY + 1.0, style.SmallFontScale, false)
                utils.DrawText(hud, distPartStr, style.DistColor, distX, nextY, style.SmallFontScale, false)
            end
        end
    end
end

-- Main entry point for drawing
local function AlphaLine(stats, regionId)
    local label = regionId == "oilrigs" and "Bosses" or "Alphas"
    local text = string.format("%s: %d/%d", label, stats.alphas.defeated, stats.alphas.total)
    if regionId == "oilrigs" then return text end
    return string.format("%s   Bounties: %d/%d", text, stats.bounties.cleared, stats.bounties.total)
end

function M.draw(hud, activePlayers, activeRelics, activeChests, activeEggs, activeCaves, activeLoot, activeNotes, activePals, activeFastTravel, activeHacks, activeBounties, cachedLocalPlayer, SizeX, SizeY)
    NoteHud(hud)

    -- 1. Draw Settings Menu (always allowed, even if mod is disabled)
    menu.Draw(hud, SizeX, SizeY)
    
    -- 2. Draw Popups (always allowed)
    popup.Draw(hud, SizeX, SizeY)

    -- Unwrap screen dimensions safely
    local sx = SizeX
    if type(sx) == "userdata" or type(sx) == "table" then pcall(function() sx = sx:get() end) end
    local sy = SizeY
    if type(sy) == "userdata" or type(sy) == "table" then pcall(function() sy = sy:get() end) end

    local screenW = (type(sx) == "number" and sx > 0) and sx or 1920.0
    local screenH = (type(sy) == "number" and sy > 0) and sy or 1080.0

    -- Hide the card only when it would actually be drawn.
    local showCard = configMod.EditModeActive or (CONFIG.Completionist and CONFIG.Completionist.Enabled and CONFIG.Completionist.ShowHUDTracker)
    local hideOverlay = false
    if showCard and not configMod.EditModeActive then
        if CONFIG.Completionist and CONFIG.Completionist.HideInBase ~= false then
            hideOverlay = BaseCampHudActive(hud)
        end
        if not hideOverlay then
            hideOverlay = GameHudHidden(hud)
        end
    end

    -- 3. Draw Active Region Progress Tracker HUD Overlay (if enabled or edit mode active)
    if showCard and not hideOverlay then
        pcall(function()
            local activeRegName = completion.currentRegionName or "Grasslands & Central Isles"
            local activeRegId = completion.currentRegionId or "grasslands"
            local statsMap = completion.cachedRegionStats or {}
            local regStats = statsMap[activeRegId]

            local scale = (CONFIG.Completionist and CONFIG.Completionist.HUDScale) or 1.0
            scale = math.max(0.5, math.min(2.0, scale))

            local cardW = 340.0 * scale
            local cardH = 143.0 * scale

            local maxScrollX = math.max(1.0, screenW - cardW)
            local maxScrollY = math.max(1.0, screenH - cardH)

            local cardX, cardY
            if CONFIG.Completionist and CONFIG.Completionist.HUDX ~= nil then
                cardX = (CONFIG.Completionist.HUDX / 100.0) * maxScrollX
            else
                cardX = screenW - cardW - (30.0 * scale)
            end

            if CONFIG.Completionist and CONFIG.Completionist.HUDY ~= nil then
                cardY = (CONFIG.Completionist.HUDY / 100.0) * maxScrollY
            else
                cardY = 40.0 * scale
            end

            -- Clamp inside screen bounds
            cardX = math.max(0.0, math.min(screenW - cardW, cardX))
            cardY = math.max(0.0, math.min(screenH - cardH, cardY))

            -- Materialize percentage coordinates if Edit Mode is active
            if configMod.EditModeActive then
                if CONFIG.Completionist.HUDX == nil then
                    CONFIG.Completionist.HUDX = tonumber(string.format("%.1f", (cardX / maxScrollX) * 100.0))
                end
                if CONFIG.Completionist.HUDY == nil then
                    CONFIG.Completionist.HUDY = tonumber(string.format("%.1f", (cardY / maxScrollY) * 100.0))
                end
            end

            local compCfg = CONFIG.Completionist
            local boxCol = compCfg and compCfg.BoxColor
            local borderCol = compCfg and compCfg.BorderColor
            local stripCol = compCfg and compCfg.StripColor
            if boxCol then
                if boxCol.R ~= nil then cardBgCol.R = boxCol.R end
                if boxCol.G ~= nil then cardBgCol.G = boxCol.G end
                if boxCol.B ~= nil then cardBgCol.B = boxCol.B end
                if boxCol.A ~= nil then cardBgCol.A = boxCol.A end
            end
            if borderCol then
                if borderCol.R ~= nil then cardBorderCol.R = borderCol.R end
                if borderCol.G ~= nil then cardBorderCol.G = borderCol.G end
                if borderCol.B ~= nil then cardBorderCol.B = borderCol.B end
                if borderCol.A ~= nil then cardBorderCol.A = borderCol.A end
            end
            if stripCol then
                if stripCol.R ~= nil then cardStripCol.R = stripCol.R end
                if stripCol.G ~= nil then cardStripCol.G = stripCol.G end
                if stripCol.B ~= nil then cardStripCol.B = stripCol.B end
                if stripCol.A ~= nil then cardStripCol.A = stripCol.A end
            end

            local bw = ((compCfg and compCfg.BorderWidth) or 1.5) * scale
            if bw < 0 then bw = 0 end
            hud:DrawRect(cardBorderCol, cardX - bw, cardY - bw, cardW + bw * 2, cardH + bw * 2)
            hud:DrawRect(cardBgCol, cardX, cardY, cardW, cardH)
            hud:DrawRect(cardStripCol, cardX, cardY, cardW, 3.0 * scale)

            -- Header: Region Name & Progress. Percent is right-aligned to the card padding.
            local pct = regStats and regStats.percent or 0
            local pctStr = tostring(pct) .. "%"
            local pctScale = 1.0 * scale
            local pctW = utils.GetTextSize(hud, pctStr, pctScale)
            if not pctW or pctW <= 0 then
                local _, scaleMult = utils.GetFontAndScale()
                pctW = utils.GetStringLength(pctStr) * 8.4 * pctScale * (scaleMult or 1.0)
            end
            local pctX = cardX + cardW - (15.0 * scale) - pctW
            utils.DrawText(hud, "[>] " .. activeRegName, cardTitleCol, cardX + 15.0 * scale, cardY + 12.0 * scale, 1.0 * scale, false)
            utils.DrawText(hud, pctStr, cardPctCol, pctX, cardY + 12.0 * scale, pctScale, false)

            -- Progress Bar
            local barX = cardX + 15.0 * scale
            local barY = cardY + 38.0 * scale
            local barW = cardW - 30.0 * scale
            local barH = 6.0 * scale
            hud:DrawRect(cardBarBgCol, barX, barY, barW, barH)
            local fillW = math.max(0.0, math.min(barW, barW * (pct / 100.0)))
            if fillW > 0 then
                hud:DrawRect(cardBarFillCol, barX, barY, fillW, barH)
            end

            -- Stat Lines
            if regStats then
                local line1 = string.format("Fast Travel: %d/%d   Towers: %d/%d   Hacks: %d/%d",
                    regStats.fastTravels.unlocked, regStats.fastTravels.total,
                    regStats.towers.defeated, regStats.towers.total,
                    regStats.hacks and regStats.hacks.collected or 0,
                    regStats.hacks and regStats.hacks.total or 0)
                local line2 = string.format("Effigies: %d/%d   Journals: %d/%d",
                    regStats.effigies.collected, regStats.effigies.total,
                    regStats.journals and regStats.journals.collected or 0,
                    regStats.journals and regStats.journals.total or 0)
                local line3 = AlphaLine(regStats, activeRegId)

                utils.DrawText(hud, line1, cardTextCol, cardX + 15.0 * scale, cardY + 54.0 * scale, 0.9 * scale, false)
                utils.DrawText(hud, line2, cardTextCol, cardX + 15.0 * scale, cardY + 78.0 * scale, 0.9 * scale, false)
                utils.DrawText(hud, line3, cardTextCol, cardX + 15.0 * scale, cardY + 102.0 * scale, 0.9 * scale, false)
            end

            -- Draw Edit Mode Overlay if active
            if configMod.EditModeActive then
                local pad = 8.0 * scale
                local boxX = cardX - pad
                local boxY = cardY - pad
                local boxW = cardW + pad * 2.0
                local boxH = cardH + pad * 2.0

                hud:DrawRect(editBorderCol, boxX, boxY, boxW, boxH)
                hud:DrawRect(editBgCol, boxX + 1.5, boxY + 1.5, boxW - 3.0, boxH - 3.0)

                -- Instruction Banner
                if not cachedEditBanner1 then
                    local textLine1 = configMod.GetTranslation("EditModeActive", "EDIT MODE ACTIVE")
                    local rawEditKey = (CONFIG.Global.KeyBinds and CONFIG.Global.KeyBinds.ToggleEditMode) or "F7"
                    local rawResetKey = (CONFIG.Global.KeyBinds and CONFIG.Global.KeyBinds.ResetCoords) or "R"

                    local textLine2 = configMod.GetTranslation("EditModeInstructions", "ARROWS: MOVE | +/-: SCALE | ALT+R: RESET | ALT+F7: SAVE")
                    textLine2 = textLine2:gsub("ALT%+F7", "ALT+" .. rawEditKey)
                    textLine2 = textLine2:gsub("ALT%+R", "ALT+" .. rawResetKey)

                    cachedEditBanner1 = textLine1
                    cachedEditBanner2 = textLine2
                end

                local textLine1 = cachedEditBanner1
                local textLine2 = cachedEditBanner2

                local textScale1 = 0.65 * scale
                local textScale2 = 0.5 * scale

                local font, scaleMult = utils.GetFontAndScale()
                local textW1 = utils.GetTextSize(hud, textLine1, textScale1)
                if not textW1 or textW1 == 0 then
                    textW1 = utils.GetStringLength(textLine1) * 8.4 * textScale1 * scaleMult
                end

                local textW2 = utils.GetTextSize(hud, textLine2, textScale2)
                if not textW2 or textW2 == 0 then
                    textW2 = utils.GetStringLength(textLine2) * 8.4 * textScale2 * scaleMult
                end

                local bannerW = math.max(textW1, textW2) + 24.0 * scale
                local bannerH = 44.0 * scale
                local bannerX = cardX + (cardW / 2.0) - (bannerW / 2.0)
                
                local bannerY = (cardY > bannerH + 12.0 * scale) and (cardY - bannerH - 10.0 * scale) or (cardY + cardH + 10.0 * scale)

                hud:DrawRect(editBorderCol, bannerX, bannerY, bannerW, bannerH)
                hud:DrawRect(bannerBgCol, bannerX + 1.5, bannerY + 1.5, bannerW - 3.0, bannerH - 3.0)

                utils.DrawText(hud, textLine1, editBannerTextCol1, bannerX + (bannerW / 2.0) - (textW1 / 2.0), bannerY + 6.0 * scale, textScale1, false)
                utils.DrawText(hud, textLine2, editBannerTextCol2, bannerX + (bannerW / 2.0) - (textW2 / 2.0), bannerY + bannerH - 18.0 * scale, textScale2, false)
            else
                cachedEditBanner1 = nil
                cachedEditBanner2 = nil
            end
        end)
    end

    -- 4. Draw Full Completionist List Modal (if toggled open in menu)
    if menu.isCompletionistViewOpen then
        pcall(function()
            local modalW = 540.0
            local regionCount = #completion.Regions
            local gapY = 8.0
            local cardH = 121.0
            local rowStep = cardH + gapY
            local headerH = 68.0
            local visibleRows = math.min(5, math.max(1, regionCount))
            local maxBoxH = math.max(headerH + rowStep, screenH - 80.0)
            while visibleRows > 1 and headerH + visibleRows * rowStep > maxBoxH do
                visibleRows = visibleRows - 1
            end
            local maxScroll = math.max(0, regionCount - visibleRows)
            local scroll = math.max(0, math.min(maxScroll, menu.completionListScroll or 0))
            if menu.completionScrollPending then
                menu.completionScrollPending = false
                for i, reg in ipairs(completion.Regions) do
                    if reg.id == completion.currentRegionId then
                        scroll = math.max(0, math.min(maxScroll, i - 1))
                        break
                    end
                end
            end
            menu.completionListScroll = scroll
            menu.completionListPage = visibleRows

            local listH = visibleRows * rowStep - gapY
            local modalH = headerH + listH + 16.0
            local modalX = math.max(20.0, (screenW - modalW) / 2.0)
            local modalY = math.max(20.0, (screenH - modalH) / 2.0)

            hud:DrawRect(modalShadowCol, modalX - 2.0, modalY - 2.0, modalW + 4.0, modalH + 4.0)
            hud:DrawRect(modalBgCol, modalX, modalY, modalW, modalH)
            hud:DrawRect(modalBorderCol, modalX, modalY, modalW, 4.0)

            utils.DrawText(hud, "REGIONAL COMPLETIONIST LIST", modalHeaderCol, modalX + 20.0, modalY + 16.0, 1.0, false)
            local globPct = completion.globalSaveProgress and completion.globalSaveProgress.overallPercent or 0
            local globStr = "Global Save Progress: " .. globPct .. "%"
            local globScale = 0.9
            local globW = utils.GetTextSize(hud, globStr, globScale)
            if not globW or globW <= 0 then
                local _, scaleMult = utils.GetFontAndScale()
                globW = utils.GetStringLength(globStr) * 8.4 * globScale * (scaleMult or 1.0)
            end
            utils.DrawText(hud, globStr, { R = 0.0, G = 0.96, B = 0.83, A = 1.0 }, modalX + modalW - 28.0 - globW, modalY + 18.0, globScale, false)

            hud:DrawRect(modalSepCol, modalX + 20.0, modalY + 48.0, modalW - 40.0, 1.0)

            local startY = modalY + headerH
            local contentRight = modalW - 36.0
            local first = scroll + 1
            local last = math.min(regionCount, scroll + visibleRows)
            for idx = first, last do
                local reg = completion.Regions[idx]
                local rY = startY + (idx - first) * rowStep
                local stats = completion.cachedRegionStats and completion.cachedRegionStats[reg.id]
                local isCurr = (reg.id == completion.currentRegionId)

                local rBg = isCurr and modalCurrBgCol or modalNormalBgCol
                local rBorder = isCurr and modalCurrBorderCol or modalNormalBorderCol

                hud:DrawRect(rBg, modalX + 20.0, rY, contentRight - 20.0, cardH)
                hud:DrawRect(rBorder, modalX + 20.0, rY, 3.0, cardH)

                local titleStr = (reg.icon or "") .. " " .. reg.name
                if isCurr then titleStr = titleStr .. "  [CURRENT LOCATION]" end
                local tCol = isCurr and modalCurrTextCol or modalNormalTextCol
                utils.DrawText(hud, titleStr, tCol, modalX + 30.0, rY + 10.0, 1.0, false)

                local regPct = stats and stats.percent or 0
                local pctStr = tostring(regPct) .. "%"
                local pctW = utils.GetTextSize(hud, pctStr, 1.0)
                if not pctW or pctW <= 0 then
                    local _, scaleMult = utils.GetFontAndScale()
                    pctW = utils.GetStringLength(pctStr) * 8.4 * (scaleMult or 1.0)
                end
                utils.DrawText(hud, pctStr, { R = 0.0, G = 0.96, B = 0.83, A = 1.0 }, modalX + contentRight - 8.0 - pctW, rY + 10.0, 1.0, false)

                if stats then
                    local detStr = string.format("Fast Travel: %d/%d   Towers: %d/%d   Hacks: %d/%d",
                        stats.fastTravels.unlocked, stats.fastTravels.total,
                        stats.towers.defeated, stats.towers.total,
                        stats.hacks and stats.hacks.collected or 0,
                        stats.hacks and stats.hacks.total or 0)
                    local detStr2 = string.format("Effigies: %d/%d   Journals: %d/%d",
                        stats.effigies.collected, stats.effigies.total,
                        stats.journals and stats.journals.collected or 0,
                        stats.journals and stats.journals.total or 0)
                    local detStr3 = AlphaLine(stats, reg.id)

                    utils.DrawText(hud, detStr, modalDetTextCol, modalX + 30.0, rY + 40.0, 0.9, false)
                    utils.DrawText(hud, detStr2, modalDetTextCol, modalX + 30.0, rY + 64.0, 0.9, false)
                    utils.DrawText(hud, detStr3, modalDetTextCol, modalX + 30.0, rY + 88.0, 0.9, false)
                end
            end

            if regionCount > visibleRows then
                local trackX = modalX + modalW - 14.0
                local trackY = startY
                local trackH = listH
                local trackW = 6.0
                hud:DrawRect({ R = 0.15, G = 0.18, B = 0.24, A = 0.9 }, trackX, trackY, trackW, trackH)
                local thumbH = math.max(28.0, trackH * (visibleRows / regionCount))
                local travel = math.max(1.0, trackH - thumbH)
                local thumbY = trackY
                if maxScroll > 0 then
                    thumbY = trackY + (scroll / maxScroll) * travel
                end
                hud:DrawRect({ R = 0.0, G = 0.95, B = 1.0, A = 0.9 }, trackX, thumbY, trackW, thumbH)
            end
        end)
    end

    -- 5. Draw 3D World Markers
    if not CONFIG.Global.Enabled then return end

    drawnBoxCount = 0

    -- Early return if no active items exist to draw across all categories
    local totalActiveCount = #activePlayers + #activeRelics + #activeChests + #activeEggs + #activeCaves + #activeLoot + #activeNotes + (activePals and #activePals or 0) + (activeFastTravel and #activeFastTravel or 0) + (activeHacks and #activeHacks or 0) + (activeBounties and #activeBounties or 0)
    if totalActiveCount == 0 then return end
    
    if not cachedLocalPlayer or not cachedLocalPlayer:IsValid() then return end
    local uePlayerPos = cachedLocalPlayer:K2_GetActorLocation()
    if not uePlayerPos then return end
    playerPosBuffer.X = uePlayerPos.X
    playerPosBuffer.Y = uePlayerPos.Y
    playerPosBuffer.Z = uePlayerPos.Z

    -- 1. Draw Players (text only; beams are world-space Niagara effects synced by tracker)
    if configMod.ShouldShowText(CONFIG.Players) then
        local graceRadiusUEUnits = CONFIG.Players.GraceRadiusM * 100.0
        local graceRadiusSq = graceRadiusUEUnits * graceRadiusUEUnits
        for _, otherPlayer in ipairs(activePlayers) do
            local dx = otherPlayer.Pos.X - playerPosBuffer.X
            local dy = otherPlayer.Pos.Y - playerPosBuffer.Y
            local dz = otherPlayer.Pos.Z - playerPosBuffer.Z
            local distSq = dx*dx + dy*dy + dz*dz
            
            if distSq > graceRadiusSq then
                local labelStr = otherPlayer.LabelStr
                if not labelStr then
                    labelStr = "@ " .. otherPlayer.Name
                    otherPlayer.LabelStr = labelStr
                end

                if not otherPlayer.distSqUpper or distSq < otherPlayer.distSqLower or distSq >= otherPlayer.distSqUpper then
                    local dist = math.sqrt(distSq)
                    local distMeters = math.floor(dist / 100.0)

                    otherPlayer.distSqLower = (distMeters * 100.0) * (distMeters * 100.0)
                    otherPlayer.distSqUpper = ((distMeters + 1) * 100.0) * ((distMeters + 1) * 100.0)

                    if otherPlayer.lastDistMeters ~= distMeters then
                        otherPlayer.lastDistMeters = distMeters
                        local mStr = distMeters .. "m"
                        otherPlayer.cachedDistStr = mStr
                        otherPlayer.cachedBracketStr = "[" .. mStr .. "]"
                    end
                end

                DrawTrackerLabel(hud, otherPlayer.Pos, labelStr, otherPlayer.cachedDistStr, CONFIG.Players.Style, screenW, screenH, nil, nil, otherPlayer.cachedBracketStr)
            end
        end
    end

    -- 2. Draw Relics
    if configMod.ShouldShowText(CONFIG.Relics) then
        for _, pos in ipairs(activeRelics) do
            local name = pos.Name or "Relic"
            DrawTrackerLabel(hud, pos, name, pos.DistStr, CONFIG.Relics.Style, screenW, screenH, nil, nil, pos.BracketDistStr)
        end
    end

    -- 3. Draw Chests
    if configMod.ShouldShowText(CONFIG.Chests) then
        for _, pos in ipairs(activeChests) do
            local name = pos.Name or "Chest"
            DrawTrackerLabel(hud, pos, name, pos.DistStr, CONFIG.Chests.Style, screenW, screenH, nil, nil, pos.BracketDistStr)
        end
    end

    -- 4. Draw Eggs
    if CONFIG.Eggs.Filter ~= "None" and configMod.ShouldShowText(CONFIG.Eggs) then
        for _, pos in ipairs(activeEggs) do
            local name = pos.FullName or pos.Name or "Egg"
            DrawTrackerLabel(hud, pos, name, pos.DistStr, CONFIG.Eggs.Style, screenW, screenH, nil, nil, pos.BracketDistStr)
        end
    end

    -- 5. Draw Caves
    if configMod.ShouldShowText(CONFIG.Caves) then
        for _, pos in ipairs(activeCaves) do
            local name = pos.Name or "Cave"
            DrawTrackerLabel(hud, pos, name, pos.DistStr, CONFIG.Caves.Style, screenW, screenH, nil, nil, pos.BracketDistStr)
        end
    end

    if configMod.ShouldShowText(CONFIG.FastTravel) and activeFastTravel then
        for _, pos in ipairs(activeFastTravel) do
            DrawTrackerLabel(hud, pos, pos.Name or "Fast Travel", pos.DistStr, CONFIG.FastTravel.Style, screenW, screenH, nil, nil, pos.BracketDistStr)
        end
    end

    if configMod.ShouldShowText(CONFIG.Hacks) and activeHacks then
        for _, pos in ipairs(activeHacks) do
            DrawTrackerLabel(hud, pos, pos.Name or "Hack", pos.DistStr, CONFIG.Hacks.Style, screenW, screenH, nil, nil, pos.BracketDistStr)
        end
    end

    if CONFIG.Bounties and activeBounties then
        local showBountyText = configMod.ShouldShowText(CONFIG.Bounties)
        local showBountyBeam = configMod.ShouldShowBeam(CONFIG.Bounties)
        if showBountyText or showBountyBeam then
            for _, bounty in ipairs(activeBounties) do
                local drawPos = bounty
                local distStr = bounty.DistStr
                local bracketDistStr = bounty.BracketDistStr
                local actor = bounty.Actor
                if actor and actor:IsValid() then
                    local isDestroyed = false
                    local okD, resD = pcall(actor.IsActorBeingDestroyed, actor)
                    if okD then isDestroyed = resD end
                    local isHidden = false
                    if not isDestroyed then
                        local okH, resH = pcall(function() return actor.bHidden or (actor.IsHidden and actor:IsHidden()) end)
                        if okH and resH then isHidden = true end
                    end
                    if not isDestroyed and not isHidden then
                        local okLoc, liveLoc = pcall(actor.K2_GetActorLocation, actor)
                        if okLoc and liveLoc then
                            drawPos = liveLoc
                            if showBountyBeam then
                                beams.Follow("Bounties", bounty, liveLoc)
                            end
                            local dx = liveLoc.X - playerPosBuffer.X
                            local dy = liveLoc.Y - playerPosBuffer.Y
                            local dz = liveLoc.Z - playerPosBuffer.Z
                            local distSq = dx*dx + dy*dy + dz*dz
                            if not bounty.liveDistSqUpper or distSq < bounty.liveDistSqLower or distSq >= bounty.liveDistSqUpper then
                                local mInt = math.floor(math.sqrt(distSq) / 100.0)
                                bounty.liveDistSqLower = (mInt * 100.0) * (mInt * 100.0)
                                bounty.liveDistSqUpper = ((mInt + 1) * 100.0) * ((mInt + 1) * 100.0)
                                if bounty.lastLiveMeters ~= mInt then
                                    bounty.lastLiveMeters = mInt
                                    local mStr = mInt .. "m"
                                    bounty.cachedLiveDistStr = mStr
                                    bounty.cachedLiveBracketStr = "[" .. mStr .. "]"
                                end
                            end
                            distStr = bounty.cachedLiveDistStr
                            bracketDistStr = bounty.cachedLiveBracketStr
                        end
                    else
                        drawPos = nil
                    end
                end
                if showBountyText and drawPos then
                    DrawTrackerLabel(hud, drawPos, bounty.Name or "Bounty", distStr, CONFIG.Bounties.Style, screenW, screenH, nil, nil, bracketDistStr)
                end
            end
        end
    end

    -- 6. Draw Loot
    if configMod.ShouldShowText(CONFIG.Loot) then
        for _, pos in ipairs(activeLoot) do
            local name = pos.Name or "Loot"
            DrawTrackerLabel(hud, pos, name, pos.DistStr, CONFIG.Loot.Style, screenW, screenH, nil, nil, pos.BracketDistStr)
        end
    end

    -- 7. Draw Notes
    if configMod.ShouldShowText(CONFIG.Notes) then
        for _, pos in ipairs(activeNotes) do
            local name = pos.Name or "Note"
            DrawTrackerLabel(hud, pos, name, pos.DistStr, CONFIG.Notes.Style, screenW, screenH, nil, nil, pos.BracketDistStr)
        end
    end

    -- 8. Draw Pals
    if CONFIG.Pals and activePals and (configMod.ShouldShowText(CONFIG.Pals) or configMod.ShouldShowBeam(CONFIG.Pals)) then
        for _, pal in ipairs(activePals) do
            local drawPos = pal
            local distStr = pal.DistStr
            local bracketDistStr = pal.BracketDistStr

            local actor = pal.Actor
            if actor and actor:IsValid() then
                local isDestroyed = false
                local okD, resD = pcall(actor.IsActorBeingDestroyed, actor)
                if okD then isDestroyed = resD end

                local isHidden = false
                if not isDestroyed then
                    local okH, resH = pcall(function() return actor.bHidden or (actor.IsHidden and actor:IsHidden()) end)
                    if okH and resH then isHidden = true end
                end

                if not isDestroyed and not isHidden then
                    local okLoc, liveLoc = pcall(actor.K2_GetActorLocation, actor)
                    if okLoc and liveLoc then
                        drawPos = liveLoc
                        if configMod.ShouldShowBeam(CONFIG.Pals) then
                            beams.Follow("Pals", pal, liveLoc)
                        end
                        local dx = liveLoc.X - playerPosBuffer.X
                        local dy = liveLoc.Y - playerPosBuffer.Y
                        local dz = liveLoc.Z - playerPosBuffer.Z
                        local distSq = dx*dx + dy*dy + dz*dz
                        if not pal.liveDistSqUpper or distSq < pal.liveDistSqLower or distSq >= pal.liveDistSqUpper then
                            local mInt = math.floor(math.sqrt(distSq) / 100.0)

                            pal.liveDistSqLower = (mInt * 100.0) * (mInt * 100.0)
                            pal.liveDistSqUpper = ((mInt + 1) * 100.0) * ((mInt + 1) * 100.0)

                            if pal.lastLiveMeters ~= mInt then
                                pal.lastLiveMeters = mInt
                                local mStr = mInt .. "m"
                                pal.cachedLiveDistStr = mStr
                                pal.cachedLiveBracketStr = "[" .. mStr .. "]"
                            end
                        end

                        distStr = pal.cachedLiveDistStr
                        bracketDistStr = pal.cachedLiveBracketStr
                    end
                else
                    drawPos = nil
                end
            end

            if drawPos and configMod.ShouldShowText(CONFIG.Pals) then
                local colorOverride = nil
                if pal.IsMimog and CONFIG.Pals.Style and CONFIG.Pals.Style.MimogColor then
                    colorOverride = CONFIG.Pals.Style.MimogColor
                elseif pal.IsShiny and CONFIG.Pals.Style and CONFIG.Pals.Style.ShinyColor then
                    colorOverride = CONFIG.Pals.Style.ShinyColor
                elseif pal.IsBoss and CONFIG.Pals.Style and CONFIG.Pals.Style.BossColor then
                    colorOverride = CONFIG.Pals.Style.BossColor
                end

                local subStr = pal.PassivesStr
                DrawTrackerLabel(hud, drawPos, pal.Name, distStr, CONFIG.Pals.Style, screenW, screenH, subStr, colorOverride, bracketDistStr, pal.Passives)
            end
        end
    end
end

return M
