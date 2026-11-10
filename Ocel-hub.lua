-- language: Luau, file: Ocel-hub.lua, runtime: Roblox Mobile / PC Executors
-- *AimSpeed нормализован по dt (1.0 = мгновенный лок), добавлен ESP на FPV-дроны*

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Полная очистка предыдущего запуска (UI, бинды, Drawing)
if _G.OcelHubCleanup then
    pcall(_G.OcelHubCleanup)
end
pcall(function() RunService:UnbindFromRenderStep("OcelAimbot") end)

local uiParent = (gethui and gethui()) or CoreGui
pcall(function()
    local old = uiParent:FindFirstChild("OcelHub_UI")
    if old then old:Destroy() end
end)

-- Клиентский реестр команд Lost Front
local LostFrontRegistry = nil
pcall(function()
    local loaderMod = ReplicatedStorage:FindFirstChild("lIIIlIIllIIlllIIIlllllIIlIIIIIlllIIIlIlllIllllIlIIIllIlIIIIl")
    if loaderMod then
        local loader = require(loaderMod)
        if loader and loader.import then
            LostFrontRegistry = loader.import("llIlIIlIllIlllIlIIlIlIIlllIIIlllIlIllllIIllIlllIlllIlIllIlII")
        end
    end
end)

local Config = {
    MenuOpen = true,
    -- ESP
    BoxESP = true,
    SkeletonESP = true,
    FPVESP = true,
    ESPVisibleColor = true,
    TeamCheck = true,
    -- Aimbot
    Aimbot = false,
    VisibleCheck = true,
    LineToTarget = true,
    ShowFOV = true,
    TargetPart = "Head", -- "Head" | "UpperTorso"
    AimFOV = 120,
    AimSpeed = 0.85,
}

local Palette = {
    Bg = Color3.fromRGB(10, 10, 10),
    Card = Color3.fromRGB(18, 18, 18),
    Stroke = Color3.fromRGB(45, 45, 45),
    White = Color3.fromRGB(255, 255, 255),
    Muted = Color3.fromRGB(140, 140, 140),
    Dim = Color3.fromRGB(95, 95, 95),
    Black = Color3.fromRGB(0, 0, 0),
}

local Connections = {}

local function newLine(thickness, color, zIndex)
    local line = Drawing.new("Line")
    line.Visible = false
    line.Thickness = thickness or 1.5
    line.Color = color or Palette.White
    line.Transparency = 1
    line.ZIndex = zIndex or 2
    return line
end

local function newSquare(thickness, color, zIndex)
    local sq = Drawing.new("Square")
    sq.Visible = false
    sq.Filled = false
    sq.Thickness = thickness or 1.5
    sq.Color = color or Palette.White
    sq.Transparency = 1
    sq.ZIndex = zIndex or 2
    return sq
end

local function newCircle(thickness, color, numSides, zIndex)
    local c = Drawing.new("Circle")
    c.Visible = false
    c.Filled = false
    c.Thickness = thickness or 1.5
    c.Color = color or Palette.White
    c.NumSides = numSides or 48
    c.Transparency = 1
    c.ZIndex = zIndex or 2
    return c
end

local function newText(size, color, zIndex)
    local t = Drawing.new("Text")
    t.Visible = false
    t.Size = size or 13
    t.Color = color or Palette.White
    t.Center = true
    t.Outline = true
    t.OutlineColor = Palette.Black
    t.Font = 2
    t.Transparency = 1
    t.ZIndex = zIndex or 3
    return t
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function isVisible(targetModel, targetPart)
    if not targetModel or not targetPart or not Camera then return false end
    local origin = Camera.CFrame.Position
    local targetPos = targetPart.Position
    local ignoreList = {}
    if LocalPlayer.Character then table.insert(ignoreList, LocalPlayer.Character) end
    if Camera then table.insert(ignoreList, Camera) end
    local ignoreFolder = workspace:FindFirstChild("ignore")
    if ignoreFolder then table.insert(ignoreList, ignoreFolder) end

    for _ = 1, 4 do
        rayParams.FilterDescendantsInstances = ignoreList
        local dir = targetPos - origin
        local result = workspace:Raycast(origin, dir, rayParams)
        if not result then
            return true
        end
        local hit = result.Instance
        if hit:IsDescendantOf(targetModel) then
            return true
        end
        if (not hit.CanCollide) or hit.Transparency >= 0.85 then
            table.insert(ignoreList, hit)
            origin = result.Position + dir.Unit * 0.05
        else
            return false
        end
    end
    return false
end

local function isEnemy(player)
    if player == LocalPlayer then return false end
    if not Config.TeamCheck then return true end

    if LocalPlayer.Team and player.Team and player.Team == LocalPlayer.Team then
        return false
    end

    local myChar = LocalPlayer.Character
    local theirChar = player.Character
    if myChar and theirChar and myChar.Parent and theirChar.Parent == myChar.Parent and myChar.Parent ~= workspace then
        return false
    end

    local teamHl = ReplicatedStorage:FindFirstChild("teamHighlight")
    if teamHl and teamHl:IsA("Highlight") and teamHl.Adornee and theirChar and theirChar:IsDescendantOf(teamHl.Adornee) then
        return false
    end

    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    local nametags = pGui and pGui:FindFirstChild("nametags")
    if nametags and nametags:FindFirstChild(player.Name) then
        return false
    end

    if LostFrontRegistry and LostFrontRegistry.players and LostFrontRegistry.players[player] and LostFrontRegistry.isFriendly then
        local ok, friendly = pcall(LostFrontRegistry.isFriendly, player)
        if ok and friendly then
            return false
        end
    end

    return true
end

local function getJointPoint(part, yFactor)
    return (part.CFrame * CFrame.new(0, part.Size.Y * yFactor, 0)).Position
end

local function getSkeletonSegments(char)
    local segments = {}
    local head = char:FindFirstChild("Head")
    if not head then return segments end

    local upperTorso = char:FindFirstChild("UpperTorso")
    local lowerTorso = char:FindFirstChild("LowerTorso")

    if upperTorso and lowerTorso then
        local neck = getJointPoint(upperTorso, 0.42)
        local chest = upperTorso.Position
        local pelvis = getJointPoint(lowerTorso, -0.38)
        table.insert(segments, { head.Position, neck })
        table.insert(segments, { neck, chest })
        table.insert(segments, { chest, pelvis })

        local lUA = char:FindFirstChild("LeftUpperArm")
        local lLA = char:FindFirstChild("LeftLowerArm")
        local lH  = char:FindFirstChild("LeftHand")
        if lUA then
            local sh = getJointPoint(lUA, 0.4)
            local el = getJointPoint(lUA, -0.4)
            table.insert(segments, { neck, sh })
            table.insert(segments, { sh, el })
            if lLA then
                local wr = getJointPoint(lLA, -0.4)
                table.insert(segments, { el, wr })
                if lH then table.insert(segments, { wr, getJointPoint(lH, -0.35) }) end
            end
        end

        local rUA = char:FindFirstChild("RightUpperArm")
        local rLA = char:FindFirstChild("RightLowerArm")
        local rH  = char:FindFirstChild("RightHand")
        if rUA then
            local sh = getJointPoint(rUA, 0.4)
            local el = getJointPoint(rUA, -0.4)
            table.insert(segments, { neck, sh })
            table.insert(segments, { sh, el })
            if rLA then
                local wr = getJointPoint(rLA, -0.4)
                table.insert(segments, { el, wr })
                if rH then table.insert(segments, { wr, getJointPoint(rH, -0.35) }) end
            end
        end

        local lUL = char:FindFirstChild("LeftUpperLeg")
        local lLL = char:FindFirstChild("LeftLowerLeg")
        local lF  = char:FindFirstChild("LeftFoot")
        if lUL then
            local hip = getJointPoint(lUL, 0.4)
            local knee = getJointPoint(lUL, -0.42)
            table.insert(segments, { pelvis, hip })
            table.insert(segments, { hip, knee })
            if lLL then
                local ankle = getJointPoint(lLL, -0.42)
                table.insert(segments, { knee, ankle })
                if lF then table.insert(segments, { ankle, getJointPoint(lF, -0.3) }) end
            end
        end

        local rUL = char:FindFirstChild("RightUpperLeg")
        local rLL = char:FindFirstChild("RightLowerLeg")
        local rF  = char:FindFirstChild("RightFoot")
        if rUL then
            local hip = getJointPoint(rUL, 0.4)
            local knee = getJointPoint(rUL, -0.42)
            table.insert(segments, { pelvis, hip })
            table.insert(segments, { hip, knee })
            if rLL then
                local ankle = getJointPoint(rLL, -0.42)
                table.insert(segments, { knee, ankle })
                if rF then table.insert(segments, { ankle, getJointPoint(rF, -0.3) }) end
            end
        end
    else
        local torso = char:FindFirstChild("Torso")
        if torso then
            local neck = getJointPoint(torso, 0.45)
            local pelvis = getJointPoint(torso, -0.45)
            table.insert(segments, { head.Position, neck })
            table.insert(segments, { neck, pelvis })

            local lArm = char:FindFirstChild("Left Arm")
            if lArm then
                local sh = getJointPoint(lArm, 0.4)
                local el = lArm.Position
                local wr = getJointPoint(lArm, -0.45)
                table.insert(segments, { neck, sh })
                table.insert(segments, { sh, el })
                table.insert(segments, { el, wr })
            end

            local rArm = char:FindFirstChild("Right Arm")
            if rArm then
                local sh = getJointPoint(rArm, 0.4)
                local el = rArm.Position
                local wr = getJointPoint(rArm, -0.45)
                table.insert(segments, { neck, sh })
                table.insert(segments, { sh, el })
                table.insert(segments, { el, wr })
            end

            local lLeg = char:FindFirstChild("Left Leg")
            if lLeg then
                local hip = getJointPoint(lLeg, 0.42)
                local knee = lLeg.Position
                local foot = getJointPoint(lLeg, -0.45)
                table.insert(segments, { pelvis, hip })
                table.insert(segments, { hip, knee })
                table.insert(segments, { knee, foot })
            end

            local rLeg = char:FindFirstChild("Right Leg")
            if rLeg then
                local hip = getJointPoint(rLeg, 0.42)
                local knee = rLeg.Position
                local foot = getJointPoint(rLeg, -0.45)
                table.insert(segments, { pelvis, hip })
                table.insert(segments, { hip, knee })
                table.insert(segments, { knee, foot })
            end
        end
    end

    return segments
end

local bodyPartsSet = {
    Head = true, Torso = true, UpperTorso = true, LowerTorso = true,
    ["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
    LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
    RightUpperArm = true, RightLowerArm = true, RightHand = true,
    LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
    RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}

local function computeBoxFromParts(model, filterSet)
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyVisible = false

    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") and (not filterSet or filterSet[part.Name]) then
            local cf = part.CFrame
            local half = part.Size * 0.5
            for sx = -1, 1, 2 do
                for sy = -1, 1, 2 do
                    for sz = -1, 1, 2 do
                        local corner = (cf * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position
                        local screenPos, onScreen = Camera:WorldToViewportPoint(corner)
                        if screenPos.Z > 0 then
                            if onScreen then anyVisible = true end
                            if screenPos.X < minX then minX = screenPos.X end
                            if screenPos.Y < minY then minY = screenPos.Y end
                            if screenPos.X > maxX then maxX = screenPos.X end
                            if screenPos.Y > maxY then maxY = screenPos.Y end
                        end
                    end
                end
            end
        end
    end

    if not anyVisible or minX == math.huge then
        return nil
    end
    return minX, minY, maxX - minX, maxY - minY
end

-- Кэш ESP игроков
local MAX_BONES = 18
local ESPCache = {}

local function createPlayerESP(player)
    if ESPCache[player] then return end
    local data = {
        BoxOutline = newSquare(3, Palette.Black, 1),
        Box = newSquare(1.4, Palette.White, 2),
        HeadCircleOutline = newCircle(3, Palette.Black, 20, 1),
        HeadCircle = newCircle(1.3, Palette.White, 20, 2),
        BoneOutlines = {},
        Bones = {},
    }
    for i = 1, MAX_BONES do
        data.BoneOutlines[i] = newLine(3, Palette.Black, 1)
        data.Bones[i] = newLine(1.3, Palette.White, 2)
    end
    ESPCache[player] = data
end

local function hidePlayerESP(data)
    data.BoxOutline.Visible = false
    data.Box.Visible = false
    data.HeadCircleOutline.Visible = false
    data.HeadCircle.Visible = false
    for i = 1, MAX_BONES do
        data.BoneOutlines[i].Visible = false
        data.Bones[i].Visible = false
    end
end

local function removePlayerESP(player)
    local data = ESPCache[player]
    if not data then return end
    data.BoxOutline:Remove()
    data.Box:Remove()
    data.HeadCircleOutline:Remove()
    data.HeadCircle:Remove()
    for i = 1, MAX_BONES do
        data.BoneOutlines[i]:Remove()
        data.Bones[i]:Remove()
    end
    ESPCache[player] = nil
end

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then createPlayerESP(p) end
end
table.insert(Connections, Players.PlayerAdded:Connect(createPlayerESP))
table.insert(Connections, Players.PlayerRemoving:Connect(removePlayerESP))

-- Кэш ESP FPV-дронов (Lost Front: тег "drone" и папка IllllII_iiii)
local DroneCache = {}

local function trackDrone(drone)
    if DroneCache[drone] or not drone:IsA("Model") then return end
    DroneCache[drone] = {
        BoxOutline = newSquare(3, Palette.Black, 1),
        Box = newSquare(1.4, Palette.White, 2),
        Label = newText(13, Palette.White, 3),
    }
end

local function hideDroneESP(data)
    data.BoxOutline.Visible = false
    data.Box.Visible = false
    data.Label.Visible = false
end

local function untrackDrone(drone)
    local data = DroneCache[drone]
    if not data then return end
    data.BoxOutline:Remove()
    data.Box:Remove()
    data.Label:Remove()
    DroneCache[drone] = nil
end

for _, inst in ipairs(CollectionService:GetTagged("drone")) do
    trackDrone(inst)
end
local droneFolder = workspace:FindFirstChild("IllllII_iiii")
if droneFolder then
    for _, inst in ipairs(droneFolder:GetDescendants()) do
        if inst:HasTag("drone") then trackDrone(inst) end
    end
    table.insert(Connections, droneFolder.DescendantAdded:Connect(function(inst)
        if inst:HasTag("drone") then trackDrone(inst) end
    end))
end
table.insert(Connections, CollectionService:GetInstanceAddedSignal("drone"):Connect(trackDrone))
table.insert(Connections, CollectionService:GetInstanceRemovedSignal("drone"):Connect(untrackDrone))

local FOVCircleOutline = newCircle(2.5, Palette.Black, 64, 3)
local FOVCircle = newCircle(1.2, Palette.White, 64, 4)
local TargetLineOutline = newLine(3, Palette.Black, 3)
local TargetLine = newLine(1.4, Palette.White, 4)

-- =========================================================================
-- Ocel-hub UI
-- =========================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "OcelHub_UI"
ScreenGui.IgnoreGuiInset = true
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = uiParent

local isDraggingSlider = false

local function makeDraggable(dragHandle, moveTarget)
    local dragging = false
    local dragStart, startPos

    dragHandle.InputBegan:Connect(function(input)
        if isDraggingSlider then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = moveTarget.Position
        end
    end)

    table.insert(Connections, UserInputService.InputChanged:Connect(function(input)
        if not dragging or isDraggingSlider then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            moveTarget.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))

    table.insert(Connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

local TogglePill = Instance.new("TextButton")
TogglePill.Name = "OcelPill"
TogglePill.Size = UDim2.fromOffset(74, 30)
TogglePill.Position = UDim2.new(0, 16, 0, 56)
TogglePill.BackgroundColor3 = Palette.Bg
TogglePill.Text = "OCEL"
TogglePill.TextColor3 = Palette.White
TogglePill.Font = Enum.Font.GothamBold
TogglePill.TextSize = 12
TogglePill.AutoButtonColor = false
TogglePill.Parent = ScreenGui

Instance.new("UICorner", TogglePill).CornerRadius = UDim.new(0, 8)
local pillStroke = Instance.new("UIStroke", TogglePill)
pillStroke.Color = Palette.White
pillStroke.Thickness = 1.2
makeDraggable(TogglePill, TogglePill)

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.fromOffset(252, 324)
MainFrame.Position = UDim2.new(0.5, -126, 0.5, -162)
MainFrame.BackgroundColor3 = Palette.Bg
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Parent = ScreenGui

Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)
local mainStroke = Instance.new("UIStroke", MainFrame)
mainStroke.Color = Palette.Stroke
mainStroke.Thickness = 1.2

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 38)
Header.BackgroundTransparency = 1
Header.Parent = MainFrame
makeDraggable(Header, MainFrame)

local TitleDot = Instance.new("Frame")
TitleDot.Size = UDim2.fromOffset(7, 7)
TitleDot.Position = UDim2.new(0, 14, 0.5, -3)
TitleDot.BackgroundColor3 = Palette.White
TitleDot.BorderSizePixel = 0
TitleDot.Parent = Header
Instance.new("UICorner", TitleDot).CornerRadius = UDim.new(1, 0)

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -60, 1, 0)
TitleLabel.Position = UDim2.new(0, 28, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "OCEL-HUB"
TitleLabel.TextColor3 = Palette.White
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 13
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = Header

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.fromOffset(26, 26)
CloseBtn.Position = UDim2.new(1, -34, 0.5, -13)
CloseBtn.BackgroundColor3 = Palette.Card
CloseBtn.Text = "—"
CloseBtn.TextColor3 = Palette.Muted
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 12
CloseBtn.AutoButtonColor = false
CloseBtn.Parent = Header
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

local Divider = Instance.new("Frame")
Divider.Size = UDim2.new(1, -24, 0, 1)
Divider.Position = UDim2.new(0, 12, 0, 38)
Divider.BackgroundColor3 = Palette.Stroke
Divider.BorderSizePixel = 0
Divider.Parent = MainFrame

local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, -24, 0, 28)
TabBar.Position = UDim2.new(0, 12, 0, 46)
TabBar.BackgroundColor3 = Palette.Card
TabBar.BorderSizePixel = 0
TabBar.Parent = MainFrame
Instance.new("UICorner", TabBar).CornerRadius = UDim.new(0, 7)

local function makeTabBtn(text, xScale)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.5, -4, 1, -4)
    btn.Position = UDim2.new(xScale, 2, 0, 2)
    btn.BackgroundColor3 = Palette.White
    btn.Text = text
    btn.TextColor3 = Palette.Black
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.AutoButtonColor = false
    btn.Parent = TabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
    return btn
end

local TabESPBtn = makeTabBtn("VISUAL", 0)
local TabAIMBtn = makeTabBtn("AIMBOT", 0.5)

local function createContainer()
    local frame = Instance.new("ScrollingFrame")
    frame.Size = UDim2.new(1, -24, 1, -88)
    frame.Position = UDim2.new(0, 12, 0, 82)
    frame.BackgroundTransparency = 1
    frame.ScrollBarThickness = 2
    frame.ScrollBarImageColor3 = Palette.Stroke
    frame.CanvasSize = UDim2.new(0, 0, 0, 0)
    frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    frame.BorderSizePixel = 0
    frame.Parent = MainFrame

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = frame
    return frame
end

local PageESP = createContainer()
local PageAIM = createContainer()

local function setActiveTab(tabName)
    local isESP = (tabName == "ESP")
    PageESP.Visible = isESP
    PageAIM.Visible = not isESP

    TabESPBtn.BackgroundTransparency = isESP and 0 or 1
    TabESPBtn.TextColor3 = isESP and Palette.Black or Palette.Muted

    TabAIMBtn.BackgroundTransparency = isESP and 1 or 0
    TabAIMBtn.TextColor3 = isESP and Palette.Muted or Palette.Black
end

TabESPBtn.MouseButton1Click:Connect(function() setActiveTab("ESP") end)
TabAIMBtn.MouseButton1Click:Connect(function() setActiveTab("AIM") end)
setActiveTab("ESP")

local function addToggle(parent, labelText, configKey)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 34)
    btn.BackgroundColor3 = Palette.Card
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)

    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = Palette.Stroke
    stroke.Thickness = 1

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -56, 1, 0)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.TextColor3 = Palette.White
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = btn

    local switchBg = Instance.new("Frame")
    switchBg.Size = UDim2.fromOffset(34, 18)
    switchBg.Position = UDim2.new(1, -44, 0.5, -9)
    switchBg.BorderSizePixel = 0
    switchBg.Parent = btn
    Instance.new("UICorner", switchBg).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(12, 12)
    knob.BorderSizePixel = 0
    knob.Parent = switchBg
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local function refresh(instant)
        local on = Config[configKey]
        local bgCol = on and Palette.White or Color3.fromRGB(36, 36, 36)
        local knobCol = on and Palette.Black or Palette.Muted
        local knobPos = on and UDim2.new(1, -15, 0.5, -6) or UDim2.new(0, 3, 0.5, -6)
        if instant then
            switchBg.BackgroundColor3 = bgCol
            knob.BackgroundColor3 = knobCol
            knob.Position = knobPos
        else
            local ti = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            TweenService:Create(switchBg, ti, { BackgroundColor3 = bgCol }):Play()
            TweenService:Create(knob, ti, { BackgroundColor3 = knobCol, Position = knobPos }):Play()
        end
    end

    btn.MouseButton1Click:Connect(function()
        Config[configKey] = not Config[configKey]
        refresh(false)
    end)

    refresh(true)
end

local function addCycle(parent, labelText, configKey, options)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 34)
    btn.BackgroundColor3 = Palette.Card
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)

    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = Palette.Stroke
    stroke.Thickness = 1

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.55, 0, 1, 0)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.TextColor3 = Palette.White
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = btn

    local val = Instance.new("TextLabel")
    val.Size = UDim2.new(0.45, -14, 1, 0)
    val.Position = UDim2.new(0.55, 0, 0, 0)
    val.BackgroundTransparency = 1
    val.Text = Config[configKey]
    val.TextColor3 = Palette.Muted
    val.Font = Enum.Font.GothamBold
    val.TextSize = 11
    val.TextXAlignment = Enum.TextXAlignment.Right
    val.Parent = btn

    local idx = table.find(options, Config[configKey]) or 1
    btn.MouseButton1Click:Connect(function()
        idx = (idx % #options) + 1
        Config[configKey] = options[idx]
        val.Text = Config[configKey]
    end)
end

local function addSlider(parent, labelText, configKey, minVal, maxVal, decimals)
    local box = Instance.new("Frame")
    box.Size = UDim2.new(1, 0, 0, 46)
    box.BackgroundColor3 = Palette.Card
    box.BorderSizePixel = 0
    box.Parent = parent
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 7)

    local stroke = Instance.new("UIStroke", box)
    stroke.Color = Palette.Stroke
    stroke.Thickness = 1

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.6, 0, 0, 22)
    lbl.Position = UDim2.new(0, 12, 0, 3)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.TextColor3 = Palette.White
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = box

    local valLbl = Instance.new("TextLabel")
    valLbl.Size = UDim2.new(0.4, -12, 0, 22)
    valLbl.Position = UDim2.new(0.6, 0, 0, 3)
    valLbl.BackgroundTransparency = 1
    valLbl.TextColor3 = Palette.Muted
    valLbl.Font = Enum.Font.GothamBold
    valLbl.TextSize = 11
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.Parent = box

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -24, 0, 6)
    track.Position = UDim2.new(0, 12, 0, 31)
    track.BackgroundColor3 = Color3.fromRGB(36, 36, 36)
    track.BorderSizePixel = 0
    track.Parent = box
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Palette.White
    fill.BorderSizePixel = 0
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local function updateFromRatio(ratio)
        ratio = math.clamp(ratio, 0, 1)
        local raw = minVal + (maxVal - minVal) * ratio
        local mult = 10 ^ (decimals or 0)
        local rounded = math.floor(raw * mult + 0.5) / mult
        Config[configKey] = rounded
        fill.Size = UDim2.new(ratio, 0, 1, 0)
        valLbl.Text = string.format("%." .. tostring(decimals or 0) .. "f", rounded)
    end

    local function updateFromInput(posX)
        local absPos = track.AbsolutePosition.X
        local absSize = track.AbsoluteSize.X
        if absSize > 0 then
            updateFromRatio((posX - absPos) / absSize)
        end
    end

    local sliding = false
    box.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            sliding = true
            isDraggingSlider = true
            updateFromInput(input.Position.X)
        end
    end)

    table.insert(Connections, UserInputService.InputChanged:Connect(function(input)
        if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input.Position.X)
        end
    end))

    table.insert(Connections, UserInputService.InputEnded:Connect(function(input)
        if sliding and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            sliding = false
            isDraggingSlider = false
        end
    end))

    updateFromRatio((Config[configKey] - minVal) / (maxVal - minVal))
end

addToggle(PageESP, "Boxes", "BoxESP")
addToggle(PageESP, "Skeleton", "SkeletonESP")
addToggle(PageESP, "FPV Drones", "FPVESP")
addToggle(PageESP, "Visible Highlight", "ESPVisibleColor")
addToggle(PageESP, "Team Check", "TeamCheck")

addToggle(PageAIM, "Aimbot", "Aimbot")
addToggle(PageAIM, "Visible Check", "VisibleCheck")
addToggle(PageAIM, "Line to Target", "LineToTarget")
addToggle(PageAIM, "Show FOV", "ShowFOV")
addCycle(PageAIM, "Target Part", "TargetPart", { "Head", "UpperTorso" })
addSlider(PageAIM, "Aim FOV", "AimFOV", 30, 300, 0)
addSlider(PageAIM, "Aim Speed", "AimSpeed", 0.15, 1.00, 2)

local function setMenuVisible(state)
    Config.MenuOpen = state
    MainFrame.Visible = state
end

TogglePill.MouseButton1Click:Connect(function()
    setMenuVisible(not Config.MenuOpen)
end)

CloseBtn.MouseButton1Click:Connect(function()
    setMenuVisible(false)
end)

table.insert(Connections, UserInputService.InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode == Enum.KeyCode.RightShift then
        setMenuVisible(not Config.MenuOpen)
    end
end))

-- =========================================================================
-- Поиск цели и наводка (до cameraRenderUpdate и camShake)
-- =========================================================================
local function findBestTarget(screenCenter)
    local bestPart = nil
    local bestDist = Config.AimFOV

    for player in pairs(ESPCache) do
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if char and hum and hum.Health > 0 and root and isEnemy(player) then
            local aimPart = char:FindFirstChild(Config.TargetPart)
                or char:FindFirstChild("Torso")
                or char:FindFirstChild("Head")
                or root
            if aimPart then
                local pos, onScreen = Camera:WorldToViewportPoint(aimPart.Position)
                if onScreen and pos.Z > 0 then
                    local dist = (Vector2.new(pos.X, pos.Y) - screenCenter).Magnitude
                    if dist < bestDist and (not Config.VisibleCheck or isVisible(char, aimPart)) then
                        bestDist = dist
                        bestPart = aimPart
                    end
                end
            end
        end
    end

    return bestPart
end

local currentTargetPart = nil

RunService:BindToRenderStep("OcelAimbot", Enum.RenderPriority.Camera.Value - 1, function(dt)
    Camera = workspace.CurrentCamera
    if not Camera then return end

    local vpSize = Camera.ViewportSize
    local screenCenter = Vector2.new(vpSize.X * 0.5, vpSize.Y * 0.5)

    if Config.Aimbot or Config.LineToTarget then
        currentTargetPart = findBestTarget(screenCenter)
    else
        currentTargetPart = nil
    end

    if Config.Aimbot and currentTargetPart and Camera.CameraType ~= Enum.CameraType.Scriptable then
        local targetCF = CFrame.lookAt(Camera.CFrame.Position, currentTargetPart.Position)
        if Config.AimSpeed >= 0.98 then
            Camera.CFrame = targetCF
        else
            local alpha = math.clamp(1 - (1 - Config.AimSpeed) ^ (math.max(dt, 1 / 240) * 60), 0, 1)
            Camera.CFrame = Camera.CFrame:Lerp(targetCF, alpha)
        end
    end
end)

-- =========================================================================
-- Отрисовка ESP игроков, FPV-дронов, FOV и Line to Target
-- =========================================================================
table.insert(Connections, RunService.RenderStepped:Connect(function()
    Camera = workspace.CurrentCamera
    if not Camera then return end

    local vpSize = Camera.ViewportSize
    local screenCenter = Vector2.new(vpSize.X * 0.5, vpSize.Y * 0.5)
    local camPos = Camera.CFrame.Position

    local showFov = Config.ShowFOV and (Config.Aimbot or Config.LineToTarget)
    FOVCircleOutline.Visible = showFov
    FOVCircle.Visible = showFov
    if showFov then
        FOVCircleOutline.Position = screenCenter
        FOVCircleOutline.Radius = Config.AimFOV
        FOVCircle.Position = screenCenter
        FOVCircle.Radius = Config.AimFOV
    end

    -- Игроки
    for player, data in pairs(ESPCache) do
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")

        if not char or not hum or hum.Health <= 0 or not root or not isEnemy(player) then
            hidePlayerESP(data)
            continue
        end

        local aimPart = char:FindFirstChild(Config.TargetPart)
            or char:FindFirstChild("Torso")
            or char:FindFirstChild("Head")
            or root

        local visible = isVisible(char, aimPart)
        local drawColor = (Config.ESPVisibleColor and not visible) and Palette.Dim or Palette.White

        if Config.BoxESP then
            local bx, by, bw, bh = computeBoxFromParts(char, bodyPartsSet)
            if bx and bw > 2 and bh > 2 then
                local boxPos = Vector2.new(bx, by)
                local boxSize = Vector2.new(bw, bh)
                data.BoxOutline.Position = boxPos
                data.BoxOutline.Size = boxSize
                data.BoxOutline.Visible = true

                data.Box.Position = boxPos
                data.Box.Size = boxSize
                data.Box.Color = drawColor
                data.Box.Visible = true
            else
                data.BoxOutline.Visible = false
                data.Box.Visible = false
            end
        else
            data.BoxOutline.Visible = false
            data.Box.Visible = false
        end

        if Config.SkeletonESP then
            local segs = getSkeletonSegments(char)
            local used = 0

            for i = 1, #segs do
                if i > MAX_BONES then break end
                local pA, onA = Camera:WorldToViewportPoint(segs[i][1])
                local pB, onB = Camera:WorldToViewportPoint(segs[i][2])
                if pA.Z > 0 and pB.Z > 0 and (onA or onB) then
                    used = used + 1
                    local vA = Vector2.new(pA.X, pA.Y)
                    local vB = Vector2.new(pB.X, pB.Y)

                    data.BoneOutlines[used].From = vA
                    data.BoneOutlines[used].To = vB
                    data.BoneOutlines[used].Visible = true

                    data.Bones[used].From = vA
                    data.Bones[used].To = vB
                    data.Bones[used].Color = drawColor
                    data.Bones[used].Visible = true
                end
            end

            for i = used + 1, MAX_BONES do
                data.BoneOutlines[i].Visible = false
                data.Bones[i].Visible = false
            end

            local head = char:FindFirstChild("Head")
            if head then
                local hp, onH = Camera:WorldToViewportPoint(head.Position)
                local topP = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, head.Size.Y * 0.5, 0))
                if onH and hp.Z > 0 then
                    local radius = math.clamp(math.abs(hp.Y - topP.Y), 3, 28)
                    local hPos = Vector2.new(hp.X, hp.Y)
                    data.HeadCircleOutline.Position = hPos
                    data.HeadCircleOutline.Radius = radius
                    data.HeadCircleOutline.Visible = true

                    data.HeadCircle.Position = hPos
                    data.HeadCircle.Radius = radius
                    data.HeadCircle.Color = drawColor
                    data.HeadCircle.Visible = true
                else
                    data.HeadCircleOutline.Visible = false
                    data.HeadCircle.Visible = false
                end
            end
        else
            data.HeadCircleOutline.Visible = false
            data.HeadCircle.Visible = false
            for i = 1, MAX_BONES do
                data.BoneOutlines[i].Visible = false
                data.Bones[i].Visible = false
            end
        end
    end

    -- FPV-дроны
    for drone, data in pairs(DroneCache) do
        if not Config.FPVESP or not drone.Parent or not drone:IsDescendantOf(workspace) then
            hideDroneESP(data)
            continue
        end

        local ownerName = drone:GetAttribute("player")
        local owner = ownerName and Players:FindFirstChild(ownerName)
        if owner == LocalPlayer or (Config.TeamCheck and owner and not isEnemy(owner)) then
            hideDroneESP(data)
            continue
        end

        local refPart = drone.PrimaryPart or drone:FindFirstChildWhichIsA("BasePart", true)
        if not refPart then
            hideDroneESP(data)
            continue
        end

        local centerPos, onScreen = Camera:WorldToViewportPoint(refPart.Position)
        if not onScreen or centerPos.Z <= 0 then
            hideDroneESP(data)
            continue
        end

        local bx, by, bw, bh = computeBoxFromParts(drone, nil)
        if not bx then
            bx = centerPos.X - 8
            by = centerPos.Y - 8
            bw = 16
            bh = 16
        else
            local minSize = 14
            if bw < minSize then
                bx = bx - (minSize - bw) * 0.5
                bw = minSize
            end
            if bh < minSize then
                by = by - (minSize - bh) * 0.5
                bh = minSize
            end
        end

        local visible = isVisible(drone, refPart)
        local drawColor = (Config.ESPVisibleColor and not visible) and Palette.Dim or Palette.White
        local distMeters = math.floor((refPart.Position - camPos).Magnitude * 0.28 + 0.5)

        local boxPos = Vector2.new(bx, by)
        local boxSize = Vector2.new(bw, bh)
        data.BoxOutline.Position = boxPos
        data.BoxOutline.Size = boxSize
        data.BoxOutline.Visible = true

        data.Box.Position = boxPos
        data.Box.Size = boxSize
        data.Box.Color = drawColor
        data.Box.Visible = true

        data.Label.Text = string.format("[FPV] %dm", distMeters)
        data.Label.Position = Vector2.new(bx + bw * 0.5, by - 16)
        data.Label.Color = drawColor
        data.Label.Visible = true
    end

    -- Line to Target
    if Config.LineToTarget and currentTargetPart and currentTargetPart.Parent then
        local pos, onScreen = Camera:WorldToViewportPoint(currentTargetPart.Position)
        if onScreen and pos.Z > 0 then
            local targetPos2D = Vector2.new(pos.X, pos.Y)
            TargetLineOutline.From = screenCenter
            TargetLineOutline.To = targetPos2D
            TargetLineOutline.Visible = true

            TargetLine.From = screenCenter
            TargetLine.To = targetPos2D
            TargetLine.Visible = true
        else
            TargetLineOutline.Visible = false
            TargetLine.Visible = false
        end
    else
        TargetLineOutline.Visible = false
        TargetLine.Visible = false
    end
end))

_G.OcelHubCleanup = function()
    pcall(function() RunService:UnbindFromRenderStep("OcelAimbot") end)
    for _, conn in ipairs(Connections) do
        pcall(function() conn:Disconnect() end)
    end
    for p in pairs(ESPCache) do removePlayerESP(p) end
    for d in pairs(DroneCache) do untrackDrone(d) end
    pcall(function() FOVCircleOutline:Remove() end)
    pcall(function() FOVCircle:Remove() end)
    pcall(function() TargetLineOutline:Remove() end)
    pcall(function() TargetLine:Remove() end)
    pcall(function() ScreenGui:Destroy() end)
end
