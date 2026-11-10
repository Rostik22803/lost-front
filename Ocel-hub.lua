-- language: Luau, file: Ocel-hub.lua, runtime: Roblox Mobile / PC Executors
-- *Lost Front: Silent Aim (FastCast Hook), Improved Aimbot, 12 Expandable Chams (Enemy/Hands/Weapon), Bullet Tracer, NoRecoil/NoSpread, ESP*

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Полная очистка предыдущего запуска
if _G.OcelHubCleanup then
    pcall(_G.OcelHubCleanup)
end
pcall(function() RunService:UnbindFromRenderStep("OcelAimbot") end)

local uiParent = (gethui and gethui()) or CoreGui
pcall(function()
    local old = uiParent:FindFirstChild("OcelHub_UI")
    if old then old:Destroy() end
end)

-- Импорт клиентских модулей Lost Front
local GameModules = {
    Registry = nil,
    Shake = nil,
    Projectile = nil,
    Stats = nil,
    Items = nil,
    FastCast = nil,
    ActiveCast = nil,
}

pcall(function()
    local loaderMod = ReplicatedStorage:FindFirstChild("lIIIlIIllIIlllIIIlllllIIlIIIIIlllIIIlIlllIllllIlIIIllIlIIIIl")
    if not loaderMod then return end
    local loader = require(loaderMod)
    if not (loader and loader.import) then return end

    local function safeImport(name)
        local ok, res = pcall(loader.import, name)
        return ok and res or nil
    end

    GameModules.Registry   = safeImport("llIlIIlIllIlllIlIIlIlIIlllIIIlllIlIllllIIllIlllIlllIlIllIlII")
    GameModules.Shake      = safeImport("IIIllIIllllIlllllIllllIlIIIlIlIIIIIlIIIlIIlIIllIIlIIlIlIIlll")
    GameModules.Projectile = safeImport("lIIIlllIIlIllIlllllIIllllIlllIlIlIIlIllIllllIIlIllIlllllIllI")
    GameModules.Stats      = safeImport("IIIIIlIlllIIIlIlIIllIIIIlIllIlllllIlIllllIlIlllIIlIIlIIlIlII")
    GameModules.Items      = safeImport("IIIlllIIIIIIlllllIlllIlIIlIIIlllIIIllIIlIlIIIlIlllllIIlllllI")
    GameModules.FastCast   = safeImport("IlIllIllIIIIllllIllllIlIIlIIIIIIIIllIlIlIlllIIllIllIllIIllIl")
    GameModules.ActiveCast = safeImport("lIlIIlIIIlllIIIlIlIIlIIIlIlIIllIllIIlIIIIlllIIIIlIIlIIIllllI")
end)

local ChamStyleList = {
    "Water Flow",
    "Glossy Flow",
    "Wireframe",
    "Lava Flow",
    "Toxic Pulse",
    "Galaxy Flow",
    "Gold Chrome",
    "Dark Chrome",
    "Neon Glow",
    "Ghost Glass",
    "RGB Flow",
    "Monochrome",
}

local Config = {
    MenuOpen = true,
    -- ESP
    BoxESP = true,
    SkeletonESP = true,
    FPVESP = true,
    ESPVisibleColor = true,
    TeamCheck = true,
    -- Aimbot & Combat
    Aimbot = false,
    SilentAim = false,
    Prediction = true,
    VisibleCheck = true,
    LineToTarget = true,
    ShowFOV = true,
    NoRecoil = false,
    NoSpread = false,
    BulletTracer = true,
    TargetPart = "Head", -- "Head" | "UpperTorso" | "Nearest"
    AimFOV = 120,
    AimSpeed = 0.90,
    -- Chams
    EnemyChams = false,
    EnemyChamStyle = "Water Flow",
    HandsChams = true,
    HandsChamStyle = "Water Flow",
    WeaponChams = true,
    WeaponChamStyle = "Glossy Flow",
}

local Palette = {
    Bg = Color3.fromRGB(10, 10, 10),
    Card = Color3.fromRGB(18, 18, 18),
    SubCard = Color3.fromRGB(14, 14, 14),
    Stroke = Color3.fromRGB(45, 45, 45),
    White = Color3.fromRGB(255, 255, 255),
    Muted = Color3.fromRGB(140, 140, 140),
    Dim = Color3.fromRGB(95, 95, 95),
    Black = Color3.fromRGB(0, 0, 0),
}

local Connections = {}
local ActiveBallistics = {
    Speed = 2500,
    Gravity = workspace.Gravity / 8,
}

-- =========================================================================
-- Drawing & Raycast (общие утилиты)
-- =========================================================================
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

local function isVisibleFrom(originPos, targetModel, targetPart)
    if not targetModel or not targetPart then return false end
    local targetPos = targetPart.Position
    local ignoreList = {}
    if LocalPlayer.Character then table.insert(ignoreList, LocalPlayer.Character) end
    if Camera then table.insert(ignoreList, Camera) end
    local ignoreFolder = workspace:FindFirstChild("ignore")
    if ignoreFolder then table.insert(ignoreList, ignoreFolder) end

    local origin = originPos
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

local function isVisible(targetModel, targetPart)
    if not Camera then return false end
    return isVisibleFrom(Camera.CFrame.Position, targetModel, targetPart)
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

    local reg = GameModules.Registry
    if reg and reg.players and reg.players[player] and reg.isFriendly then
        local ok, friendly = pcall(reg.isFriendly, player)
        if ok and friendly then
            return false
        end
    end

    return true
end

-- =========================================================================
-- Кэш ESP игроков и таргетинг (Sticky + Nearest + 2-Pass Prediction)
-- =========================================================================
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

local function resolveTargetPartForChar(char, screenCenter, checkOrigin)
    if Config.TargetPart == "Nearest" then
        local candidates = {
            char:FindFirstChild("Head"),
            char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"),
        }
        local bestPart, bestDist = nil, math.huge
        for _, part in ipairs(candidates) do
            if part then
                local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen and pos.Z > 0 then
                    local d = (Vector2.new(pos.X, pos.Y) - screenCenter).Magnitude
                    if d < bestDist and (not Config.VisibleCheck or isVisibleFrom(checkOrigin, char, part)) then
                        bestDist = d
                        bestPart = part
                    end
                end
            end
        end
        return bestPart
    end

    local preferred = char:FindFirstChild(Config.TargetPart)
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("Head")
        or char:FindFirstChild("HumanoidRootPart")
    if preferred and Config.VisibleCheck and not isVisibleFrom(checkOrigin, char, preferred) then
        return nil
    end
    return preferred
end

local LockedPlayer = nil

local function findBestTarget(screenCenter, originOverride, useSticky)
    local checkOrigin = originOverride or (Camera and Camera.CFrame.Position)
    if not checkOrigin then return nil, nil, math.huge end

    if useSticky and LockedPlayer and ESPCache[LockedPlayer] then
        local char = LockedPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if char and hum and hum.Health > 0 and root and isEnemy(LockedPlayer) then
            local part = resolveTargetPartForChar(char, screenCenter, checkOrigin)
            if part then
                local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen and pos.Z > 0 then
                    local dist = (Vector2.new(pos.X, pos.Y) - screenCenter).Magnitude
                    if dist <= Config.AimFOV * 1.35 then
                        return part, root, dist
                    end
                end
            end
        end
        LockedPlayer = nil
    end

    local bestPlayer, bestPart, bestRoot = nil, nil, nil
    local bestScreenDist = Config.AimFOV

    for player in pairs(ESPCache) do
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if char and hum and hum.Health > 0 and root and isEnemy(player) then
            local aimPart = resolveTargetPartForChar(char, screenCenter, checkOrigin)
            if aimPart then
                local pos, onScreen = Camera:WorldToViewportPoint(aimPart.Position)
                if onScreen and pos.Z > 0 then
                    local dist = (Vector2.new(pos.X, pos.Y) - screenCenter).Magnitude
                    if dist < bestScreenDist then
                        bestScreenDist = dist
                        bestPlayer = player
                        bestPart = aimPart
                        bestRoot = root
                    end
                end
            end
        end
    end

    if useSticky then
        LockedPlayer = bestPlayer
    end
    return bestPart, bestRoot, bestScreenDist
end

local function getPredictedAimPos(originPos, aimPart, rootPart, speedOverride, gravOverride)
    local rawPos = aimPart.Position
    if not Config.Prediction then return rawPos end

    local speed = (speedOverride and speedOverride > 0) and speedOverride or (ActiveBallistics.Speed > 0 and ActiveBallistics.Speed or 2500)
    local grav = gravOverride or ActiveBallistics.Gravity or (workspace.Gravity / 8)

    local vel = (rootPart and rootPart.AssemblyLinearVelocity) or aimPart.AssemblyLinearVelocity or Vector3.zero
    if vel.Magnitude < 0.6 then
        vel = Vector3.zero
    end

    -- 2-проходная итерация времени полёта для точного упреждения на дальней дистанции
    local t1 = math.clamp((rawPos - originPos).Magnitude / speed, 0, 1.5)
    local p1 = rawPos + vel * t1 + Vector3.new(0, 0.5 * grav * t1 * t1, 0)
    local t2 = math.clamp((p1 - originPos).Magnitude / speed, 0, 1.5)
    return rawPos + vel * t2 + Vector3.new(0, 0.5 * grav * t2 * t2, 0)
end

-- =========================================================================
-- Bullet Tracer (3D Beam)
-- =========================================================================
local tracerRayParams = RaycastParams.new()
tracerRayParams.FilterType = Enum.RaycastFilterType.Exclude
tracerRayParams.IgnoreWater = true

local function spawnBulletTracer(weapon, customOrigin, customHitPos)
    if not Config.BulletTracer or not Camera then return end
    local terrain = workspace:FindFirstChildOfClass("Terrain") or workspace

    local origin = customOrigin
    if not origin and type(weapon) == "table" and typeof(weapon.instance) == "Instance" then
        local fp = weapon.instance:FindFirstChild("FirePoint", true)
        if fp then
            origin = fp:IsA("Attachment") and fp.WorldPosition or (fp:IsA("BasePart") and fp.Position or nil)
        end
    end
    if not origin then
        origin = (Camera.CFrame * CFrame.new(0.35, -0.25, -1.2)).Position
    end

    local hitPos = customHitPos
    if not hitPos then
        local ignoreList = {}
        if LocalPlayer.Character then table.insert(ignoreList, LocalPlayer.Character) end
        if Camera then table.insert(ignoreList, Camera) end
        local ignoreFolder = workspace:FindFirstChild("ignore")
        if ignoreFolder then table.insert(ignoreList, ignoreFolder) end

        tracerRayParams.FilterDescendantsInstances = ignoreList
        local camPos = Camera.CFrame.Position
        local dir = Camera.CFrame.LookVector * 1200
        local result = workspace:Raycast(camPos, dir, tracerRayParams)
        hitPos = result and result.Position or (camPos + dir)
    end

    local a0 = Instance.new("Attachment")
    a0.WorldPosition = origin
    a0.Parent = terrain

    local a1 = Instance.new("Attachment")
    a1.WorldPosition = hitPos
    a1.Parent = terrain

    local beam = Instance.new("Beam")
    beam.Attachment0 = a0
    beam.Attachment1 = a1
    beam.FaceCamera = true
    beam.LightEmission = 1
    beam.LightInfluence = 0
    beam.Width0 = 0.08
    beam.Width1 = 0.03
    beam.Segments = 1
    beam.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 215, 255)),
    })
    beam.Transparency = NumberSequence.new(0.05)
    beam.Parent = terrain

    task.spawn(function()
        local duration = 0.45
        local elapsed = 0
        while elapsed < duration and beam.Parent do
            local dt = RunService.Heartbeat:Wait()
            elapsed = elapsed + dt
            local alpha = math.clamp(elapsed / duration, 0, 1)
            beam.Transparency = NumberSequence.new(0.05 + 0.95 * alpha)
            beam.Width0 = 0.08 * (1 - alpha * 0.5)
        end
        pcall(function() beam:Destroy() end)
        pcall(function() a0:Destroy() end)
        pcall(function() a1:Destroy() end)
    end)
end

-- =========================================================================
-- No Recoil, No Spread & Silent Aim (FastCast / ActiveCast Hook)
-- =========================================================================
local RecoilKeys = {
    recoil_magnitude = 0,
    recoil_roughness = 0,
    recoil_recover_low = 0,
    recoil_recover_high = 0,
    recoil_rotation = Vector3.zero,
    kickback = 0,
    aimkickback = 0,
}

local SpreadKeys = {
    min_spread = 0,
    max_spread = 0,
    spread = 0,
}

local OrigStatValues = setmetatable({}, { __mode = "k" })

local function patchStatTable(tbl, keyMap, enable)
    if type(tbl) ~= "table" then return end
    local saved = OrigStatValues[tbl]
    for k, zeroVal in pairs(keyMap) do
        if rawget(tbl, k) ~= nil then
            if enable then
                if not saved then
                    saved = {}
                    OrigStatValues[tbl] = saved
                end
                if saved[k] == nil then
                    saved[k] = tbl[k]
                end
                tbl[k] = zeroVal
            elseif saved and saved[k] ~= nil then
                tbl[k] = saved[k]
            end
        end
    end
end

local function walkAndPatchItems(root, visited, depth)
    if type(root) ~= "table" or visited[root] or depth > 5 then return end
    visited[root] = true
    patchStatTable(root, RecoilKeys, Config.NoRecoil)
    patchStatTable(root, SpreadKeys, Config.NoSpread)
    for _, v in pairs(root) do
        if type(v) == "table" then
            walkAndPatchItems(v, visited, depth + 1)
        end
    end
end

local function applyWeaponMods()
    if GameModules.Items and GameModules.Items.items then
        walkAndPatchItems(GameModules.Items.items, {}, 0)
    end
    if getgc then
        local ok, gc = pcall(getgc, true)
        if ok and type(gc) == "table" then
            for _, obj in ipairs(gc) do
                if type(obj) == "table" and (rawget(obj, "recoil_magnitude") ~= nil or rawget(obj, "min_spread") ~= nil or rawget(obj, "head_damage") ~= nil) then
                    patchStatTable(obj, RecoilKeys, Config.NoRecoil)
                    patchStatTable(obj, SpreadKeys, Config.NoSpread)
                end
            end
        end
    end
end

local function updateBallisticsFromStats(stats)
    if type(stats) ~= "table" then return end
    if type(stats.bullet_speed) == "number" and stats.bullet_speed > 0 then
        ActiveBallistics.Speed = stats.bullet_speed
    end
    if typeof(stats.bullet_gravity) == "Vector3" then
        ActiveBallistics.Gravity = math.abs(stats.bullet_gravity.Y)
    end
end

local IsLocalShooting = false
local LastSilentOrigin = nil
local LastSilentHitPos = nil

local function redirectCastForSilentAim(origin, direction, velocity, behavior)
    if not Config.SilentAim or not Camera or typeof(origin) ~= "Vector3" then
        return direction, velocity
    end
    local isMine = IsLocalShooting or ((origin - Camera.CFrame.Position).Magnitude < 12)
    if not isMine then
        return direction, velocity
    end

    local vpSize = Camera.ViewportSize
    local screenCenter = Vector2.new(vpSize.X * 0.5, vpSize.Y * 0.5)
    local targetPart, rootPart = findBestTarget(screenCenter, origin, false)
    if not targetPart then
        return direction, velocity
    end

    local speed = type(velocity) == "number" and velocity or (typeof(velocity) == "Vector3" and velocity.Magnitude or ActiveBallistics.Speed)
    local grav = (type(behavior) == "table" and typeof(behavior.Acceleration) == "Vector3") and math.abs(behavior.Acceleration.Y) or ActiveBallistics.Gravity
    local aimPos = getPredictedAimPos(origin, targetPart, rootPart, speed, grav)
    local newDir = (aimPos - origin).Unit

    LastSilentOrigin = origin
    LastSilentHitPos = aimPos

    if typeof(velocity) == "Vector3" then
        return newDir, newDir * velocity.Magnitude
    end
    return newDir, velocity
end

local OrigShakeNew    = GameModules.Shake and GameModules.Shake.new
local OrigGetStats    = GameModules.Stats and GameModules.Stats.getStatsForAttachments
local OrigProjNew     = GameModules.Projectile and GameModules.Projectile.new
local OrigFastCastFire = GameModules.FastCast and GameModules.FastCast.Fire
local OrigActiveCastNew = GameModules.ActiveCast and GameModules.ActiveCast.new

if GameModules.Shake and OrigShakeNew then
    GameModules.Shake.new = function(...)
        if Config.NoRecoil then return end
        return OrigShakeNew(...)
    end
end

if GameModules.Stats and OrigGetStats then
    GameModules.Stats.getStatsForAttachments = function(...)
        local stats, disp = OrigGetStats(...)
        if type(stats) == "table" then
            updateBallisticsFromStats(stats)
            if Config.NoRecoil then patchStatTable(stats, RecoilKeys, true) end
            if Config.NoSpread then patchStatTable(stats, SpreadKeys, true) end
        end
        return stats, disp
    end
end

if GameModules.FastCast and OrigFastCastFire then
    GameModules.FastCast.Fire = function(caster, origin, direction, velocity, behavior)
        local newDir, newVel = redirectCastForSilentAim(origin, direction, velocity, behavior)
        return OrigFastCastFire(caster, origin, newDir, newVel, behavior)
    end
end

if GameModules.ActiveCast and OrigActiveCastNew then
    GameModules.ActiveCast.new = function(caster, origin, direction, velocity, behavior)
        if not LastSilentHitPos then
            local newDir, newVel = redirectCastForSilentAim(origin, direction, velocity, behavior)
            direction, velocity = newDir, newVel
        end
        return OrigActiveCastNew(caster, origin, direction, velocity, behavior)
    end
end

if GameModules.Projectile and OrigProjNew then
    GameModules.Projectile.new = function(weapon, ...)
        if type(weapon) == "table" then
            updateBallisticsFromStats(weapon.stats)
        end

        IsLocalShooting = true
        LastSilentOrigin = nil
        LastSilentHitPos = nil

        local ok, res
        if Config.NoSpread and type(weapon) == "table" then
            if type(weapon.stats) == "table" then
                patchStatTable(weapon.stats, SpreadKeys, true)
            end
            local prevState = weapon.state
            weapon.state = "aim"
            ok, res = pcall(OrigProjNew, weapon, ...)
            weapon.state = prevState
        else
            ok, res = pcall(OrigProjNew, weapon, ...)
        end

        IsLocalShooting = false
        spawnBulletTracer(weapon, LastSilentOrigin, LastSilentHitPos)
        LastSilentOrigin = nil
        LastSilentHitPos = nil

        if ok then return res end
    end
end

-- =========================================================================
-- Система Chams (Враги, Руки, Оружие + 12 стилей)
-- =========================================================================
local OrigPartProps = {}
local OrigSurfaceApp = {}
local TrackedChamParts = {
    Enemy = {},
    Hands = {},
    Weapon = {},
}
local EnemyHighlights = {}

local function saveAndDisableSurfaceAppearances(part)
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("SurfaceAppearance") and not OrigSurfaceApp[child] then
            OrigSurfaceApp[child] = part
            child.Parent = nil
        end
    end
end

local function restorePartProps(part)
    local orig = OrigPartProps[part]
    if not orig then return end
    pcall(function()
        part.Material = orig.Material
        part.Color = orig.Color
        part.Transparency = orig.Transparency
        part.Reflectance = orig.Reflectance
        if orig.TextureID ~= nil and part:IsA("MeshPart") then
            part.TextureID = orig.TextureID
        end
    end)
    OrigPartProps[part] = nil
end

local function restoreSurfaceAppearancesFor(model)
    for sa, origParent in pairs(OrigSurfaceApp) do
        if origParent and origParent.Parent and (not model or origParent:IsDescendantOf(model)) then
            pcall(function() sa.Parent = origParent end)
            OrigSurfaceApp[sa] = nil
        elseif not origParent or not origParent.Parent then
            OrigSurfaceApp[sa] = nil
        end
    end
end

local function clearChamGroup(groupName)
    for part in pairs(TrackedChamParts[groupName]) do
        restorePartProps(part)
        TrackedChamParts[groupName][part] = nil
    end
    if groupName == "Enemy" then
        for char, hl in pairs(EnemyHighlights) do
            pcall(function() hl:Destroy() end)
            EnemyHighlights[char] = nil
        end
    end
end

local function getStyleProps(style, t, phase)
    local s = 0.5 + 0.5 * math.sin(t * 2.8 + (phase or 0))
    if style == "Water Flow" then
        return Enum.Material.ForceField, Color3.fromRGB(35, 145, 255):Lerp(Color3.fromRGB(165, 240, 255), s), 0.22, 0.2, ""
    elseif style == "Glossy Flow" then
        return Enum.Material.Glass, Color3.fromRGB(200, 220, 255):Lerp(Color3.fromRGB(255, 255, 255), s), 0.12, 0.85, ""
    elseif style == "Wireframe" then
        return Enum.Material.ForceField, Color3.fromRGB(235, 245, 255), 0.62, 0, "rbxassetid://446111271"
    elseif style == "Lava Flow" then
        return Enum.Material.ForceField, Color3.fromRGB(255, 55, 15):Lerp(Color3.fromRGB(255, 195, 50), s), 0.18, 0.1, ""
    elseif style == "Toxic Pulse" then
        return Enum.Material.ForceField, Color3.fromRGB(25, 210, 90):Lerp(Color3.fromRGB(170, 255, 70), s), 0.2, 0.15, ""
    elseif style == "Galaxy Flow" then
        return Enum.Material.ForceField, Color3.fromRGB(95, 45, 215):Lerp(Color3.fromRGB(230, 105, 255), s), 0.2, 0.2, ""
    elseif style == "Gold Chrome" then
        return Enum.Material.SmoothPlastic, Color3.fromRGB(255, 210, 95), 0, 0.95, ""
    elseif style == "Dark Chrome" then
        return Enum.Material.SmoothPlastic, Color3.fromRGB(28, 30, 36), 0, 0.95, ""
    elseif style == "Neon Glow" then
        return Enum.Material.Neon, Color3.fromRGB(245, 245, 255), 0.18, 0, ""
    elseif style == "Ghost Glass" then
        return Enum.Material.Glass, Color3.fromRGB(210, 225, 245), 0.52, 0.45, nil
    elseif style == "RGB Flow" then
        return Enum.Material.ForceField, Color3.fromHSV((t * 0.28 + (phase or 0) * 0.05) % 1, 0.78, 1), 0.2, 0.1, ""
    else -- "Monochrome"
        return Enum.Material.ForceField, Color3.fromRGB(145, 145, 145):Lerp(Color3.fromRGB(255, 255, 255), s), 0.18, 0.25, ""
    end
end

local function applyChamToPart(part, groupName, style, t, phase)
    if not part:IsA("BasePart") then return end
    if not OrigPartProps[part] then
        if part.Transparency >= 0.95 then return end
        OrigPartProps[part] = {
            Material = part.Material,
            Color = part.Color,
            Transparency = part.Transparency,
            Reflectance = part.Reflectance,
            TextureID = part:IsA("MeshPart") and part.TextureID or nil,
        }
    end
    saveAndDisableSurfaceAppearances(part)
    TrackedChamParts[groupName][part] = true

    local mat, col, trans, refl, tex = getStyleProps(style, t, phase)
    part.Material = mat
    part.Color = col
    part.Transparency = trans
    part.Reflectance = refl
    if part:IsA("MeshPart") and tex ~= nil then
        part.TextureID = tex
    end
end

local function updateAllChams(t)
    local vm = Camera and Camera:FindFirstChild("ViewModel")
    local weaponContainer = vm and vm:FindFirstChild("Model")

    if vm and (Config.HandsChams or Config.WeaponChams) then
        local idx = 0
        for _, desc in ipairs(vm:GetDescendants()) do
            if desc:IsA("BasePart") then
                idx = idx + 1
                local isWeapon = weaponContainer and desc:IsDescendantOf(weaponContainer)
                if isWeapon then
                    if Config.WeaponChams then
                        applyChamToPart(desc, "Weapon", Config.WeaponChamStyle, t, idx * 0.15)
                    elseif TrackedChamParts.Weapon[desc] then
                        restorePartProps(desc)
                        TrackedChamParts.Weapon[desc] = nil
                    end
                elseif desc.Name ~= "HRP" then
                    if Config.HandsChams then
                        applyChamToPart(desc, "Hands", Config.HandsChamStyle, t, idx * 0.2)
                    elseif TrackedChamParts.Hands[desc] then
                        restorePartProps(desc)
                        TrackedChamParts.Hands[desc] = nil
                    end
                end
            end
        end
    end

    if not Config.HandsChams then clearChamGroup("Hands") end
    if not Config.WeaponChams then clearChamGroup("Weapon") end

    for part in pairs(TrackedChamParts.Hands) do
        if not part.Parent or (vm and not part:IsDescendantOf(vm)) then
            restorePartProps(part)
            TrackedChamParts.Hands[part] = nil
        end
    end
    for part in pairs(TrackedChamParts.Weapon) do
        if not part.Parent or (weaponContainer and not part:IsDescendantOf(weaponContainer)) then
            restorePartProps(part)
            TrackedChamParts.Weapon[part] = nil
        end
    end
    if not Config.HandsChams and not Config.WeaponChams and vm then
        restoreSurfaceAppearancesFor(vm)
    end

    if not Config.EnemyChams then
        clearChamGroup("Enemy")
        restoreSurfaceAppearancesFor(nil)
    end
end

-- =========================================================================
-- Скелет и 2D-боксы + FPV Дроны
-- =========================================================================
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
-- Ocel-hub UI (3 таба + выдвижные списки)
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
MainFrame.Size = UDim2.fromOffset(258, 346)
MainFrame.Position = UDim2.new(0.5, -129, 0.5, -173)
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
    btn.Size = UDim2.new(1 / 3, -3, 1, -4)
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

local TabAIMBtn   = makeTabBtn("AIM", 0)
local TabESPBtn   = makeTabBtn("ESP", 1 / 3)
local TabCHAMSBtn = makeTabBtn("CHAMS", 2 / 3)

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

local PageAIM   = createContainer()
local PageESP   = createContainer()
local PageCHAMS = createContainer()

local TabMap = {
    AIM   = { btn = TabAIMBtn,   page = PageAIM },
    ESP   = { btn = TabESPBtn,   page = PageESP },
    CHAMS = { btn = TabCHAMSBtn, page = PageCHAMS },
}

local function setActiveTab(tabName)
    for name, entry in pairs(TabMap) do
        local active = (name == tabName)
        entry.page.Visible = active
        entry.btn.BackgroundTransparency = active and 0 or 1
        entry.btn.TextColor3 = active and Palette.Black or Palette.Muted
    end
end

TabAIMBtn.MouseButton1Click:Connect(function() setActiveTab("AIM") end)
TabESPBtn.MouseButton1Click:Connect(function() setActiveTab("ESP") end)
TabCHAMSBtn.MouseButton1Click:Connect(function() setActiveTab("CHAMS") end)
setActiveTab("AIM")

local function addToggle(parent, labelText, configKey, onChanged)
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
        if onChanged then onChanged(Config[configKey]) end
    end)

    refresh(true)
end

-- Выдвижной список (аккордеон) с плавной анимацией открытия
local OpenDropdowns = {}

local function addDropdown(parent, labelText, configKey, options)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 34)
    holder.BackgroundColor3 = Palette.Card
    holder.ClipsDescendants = true
    holder.BorderSizePixel = 0
    holder.Parent = parent
    Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 7)

    local stroke = Instance.new("UIStroke", holder)
    stroke.Color = Palette.Stroke
    stroke.Thickness = 1

    local headerBtn = Instance.new("TextButton")
    headerBtn.Size = UDim2.new(1, 0, 0, 34)
    headerBtn.BackgroundTransparency = 1
    headerBtn.Text = ""
    headerBtn.AutoButtonColor = false
    headerBtn.Parent = holder

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.46, 0, 1, 0)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.TextColor3 = Palette.White
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = headerBtn

    local valLbl = Instance.new("TextLabel")
    valLbl.Size = UDim2.new(0.54, -12, 1, 0)
    valLbl.Position = UDim2.new(0.46, 0, 0, 0)
    valLbl.BackgroundTransparency = 1
    valLbl.Text = Config[configKey] .. "  ▾"
    valLbl.TextColor3 = Palette.Muted
    valLbl.Font = Enum.Font.GothamBold
    valLbl.TextSize = 11
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.Parent = headerBtn

    local listFrame = Instance.new("Frame")
    listFrame.Size = UDim2.new(1, -12, 0, #options * 26 + (#options - 1) * 4 + 6)
    listFrame.Position = UDim2.new(0, 6, 0, 36)
    listFrame.BackgroundTransparency = 1
    listFrame.Parent = holder

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 4)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Parent = listFrame

    local optionButtons = {}
    local expanded = false
    local expandedHeight = 38 + #options * 26 + (#options - 1) * 4 + 6

    local function refreshOptionVisuals()
        for opt, b in pairs(optionButtons) do
            local sel = (Config[configKey] == opt)
            b.BackgroundColor3 = sel and Palette.White or Palette.SubCard
            b.TextColor3 = sel and Palette.Black or Palette.Muted
        end
        valLbl.Text = Config[configKey] .. (expanded and "  ▴" or "  ▾")
    end

    local function setExpanded(state)
        expanded = state
        if expanded then
            for _, closeFn in ipairs(OpenDropdowns) do
                if closeFn ~= setExpanded then closeFn(false) end
            end
        end
        local targetH = expanded and expandedHeight or 34
        TweenService:Create(holder, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(1, 0, 0, targetH)
        }):Play()
        refreshOptionVisuals()
    end

    table.insert(OpenDropdowns, setExpanded)

    for i, opt in ipairs(options) do
        local optBtn = Instance.new("TextButton")
        optBtn.Size = UDim2.new(1, 0, 0, 26)
        optBtn.LayoutOrder = i
        optBtn.Text = opt
        optBtn.Font = Enum.Font.GothamBold
        optBtn.TextSize = 11
        optBtn.AutoButtonColor = false
        optBtn.Parent = listFrame
        Instance.new("UICorner", optBtn).CornerRadius = UDim.new(0, 5)

        optionButtons[opt] = optBtn
        optBtn.MouseButton1Click:Connect(function()
            Config[configKey] = opt
            setExpanded(false)
        end)
    end

    headerBtn.MouseButton1Click:Connect(function()
        setExpanded(not expanded)
    end)

    refreshOptionVisuals()
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

-- Вкладка AIM
addToggle(PageAIM, "Aimbot", "Aimbot")
addToggle(PageAIM, "Silent Aim", "SilentAim")
addToggle(PageAIM, "Prediction (Long)", "Prediction")
addToggle(PageAIM, "Visible Check", "VisibleCheck")
addToggle(PageAIM, "Line to Target", "LineToTarget")
addToggle(PageAIM, "Show FOV", "ShowFOV")
addToggle(PageAIM, "No Recoil", "NoRecoil", applyWeaponMods)
addToggle(PageAIM, "No Spread", "NoSpread", applyWeaponMods)
addToggle(PageAIM, "Bullet Tracer", "BulletTracer")
addDropdown(PageAIM, "Target Part", "TargetPart", { "Head", "UpperTorso", "Nearest" })
addSlider(PageAIM, "Aim FOV", "AimFOV", 30, 300, 0)
addSlider(PageAIM, "Aim Speed", "AimSpeed", 0.15, 1.00, 2)

-- Вкладка ESP
addToggle(PageESP, "Boxes", "BoxESP")
addToggle(PageESP, "Skeleton", "SkeletonESP")
addToggle(PageESP, "FPV Drones", "FPVESP")
addToggle(PageESP, "Visible Highlight", "ESPVisibleColor")
addToggle(PageESP, "Team Check", "TeamCheck")

-- Вкладка CHAMS (с выдвижными списками разновидностей)
addToggle(PageCHAMS, "Enemy Chams", "EnemyChams")
addDropdown(PageCHAMS, "Enemy Style", "EnemyChamStyle", ChamStyleList)
addToggle(PageCHAMS, "Hands Chams", "HandsChams")
addDropdown(PageCHAMS, "Hands Style", "HandsChamStyle", ChamStyleList)
addToggle(PageCHAMS, "Weapon Chams", "WeaponChams")
addDropdown(PageCHAMS, "Weapon Style", "WeaponChamStyle", ChamStyleList)

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
-- Цикл Aimbot (RenderPriority 199) + Цикл ESP/Chams (RenderStepped)
-- =========================================================================
local currentTargetPart = nil

RunService:BindToRenderStep("OcelAimbot", Enum.RenderPriority.Camera.Value - 1, function(dt)
    Camera = workspace.CurrentCamera
    if not Camera then return end

    local vpSize = Camera.ViewportSize
    local screenCenter = Vector2.new(vpSize.X * 0.5, vpSize.Y * 0.5)

    local bestRoot, bestScreenDist
    if Config.Aimbot or Config.SilentAim or Config.LineToTarget then
        currentTargetPart, bestRoot, bestScreenDist = findBestTarget(screenCenter, Camera.CFrame.Position, true)
    else
        currentTargetPart = nil
        LockedPlayer = nil
    end

    if Config.Aimbot and currentTargetPart and Camera.CameraType ~= Enum.CameraType.Scriptable then
        local camPos = Camera.CFrame.Position
        local aimPos = getPredictedAimPos(camPos, currentTargetPart, bestRoot)
        local targetCF = CFrame.lookAt(camPos, aimPos)

        if Config.AimSpeed >= 0.98 or (bestScreenDist and bestScreenDist <= 14 and Config.AimSpeed >= 0.65) then
            Camera.CFrame = targetCF
        else
            local alpha = math.clamp(1 - (1 - Config.AimSpeed) ^ (math.max(dt, 1 / 240) * 60), 0, 1)
            Camera.CFrame = Camera.CFrame:Lerp(targetCF, alpha)
        end
    end
end)

local activeFolder = ReplicatedStorage:FindFirstChild("active")
local clientFolder = activeFolder and activeFolder:FindFirstChild("client")
local kickbackVal  = clientFolder and clientFolder:FindFirstChild("Kickback")

table.insert(Connections, RunService.RenderStepped:Connect(function()
    local now = tick()

    if Config.NoRecoil then
        if not kickbackVal then
            activeFolder = ReplicatedStorage:FindFirstChild("active")
            clientFolder = activeFolder and activeFolder:FindFirstChild("client")
            kickbackVal  = clientFolder and clientFolder:FindFirstChild("Kickback")
        end
        if kickbackVal then
            kickbackVal.Value = 0
        end
    end

    Camera = workspace.CurrentCamera
    if not Camera then return end

    updateAllChams(now)

    local vpSize = Camera.ViewportSize
    local screenCenter = Vector2.new(vpSize.X * 0.5, vpSize.Y * 0.5)
    local camPos = Camera.CFrame.Position

    local showFov = Config.ShowFOV and (Config.Aimbot or Config.SilentAim or Config.LineToTarget)
    FOVCircleOutline.Visible = showFov
    FOVCircle.Visible = showFov
    if showFov then
        FOVCircleOutline.Position = screenCenter
        FOVCircleOutline.Radius = Config.AimFOV
        FOVCircle.Position = screenCenter
        FOVCircle.Radius = Config.AimFOV
    end

    for player, data in pairs(ESPCache) do
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")

        if not char or not hum or hum.Health <= 0 or not root or not isEnemy(player) then
            hidePlayerESP(data)
            if EnemyHighlights[char] then
                pcall(function() EnemyHighlights[char]:Destroy() end)
                EnemyHighlights[char] = nil
            end
            continue
        end

        local aimPart = char:FindFirstChild(Config.TargetPart == "Nearest" and "Head" or Config.TargetPart)
            or char:FindFirstChild("Torso")
            or char:FindFirstChild("Head")
            or root

        local visible = isVisible(char, aimPart)
        local drawColor = (Config.ESPVisibleColor and not visible) and Palette.Dim or Palette.White

        if Config.EnemyChams then
            local idx = 0
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    idx = idx + 1
                    applyChamToPart(part, "Enemy", Config.EnemyChamStyle, now, idx * 0.12)
                end
            end

            local hl = EnemyHighlights[char]
            if not hl or not hl.Parent then
                hl = Instance.new("Highlight")
                hl.Name = "OcelEnemyCham"
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.Adornee = char
                hl.Parent = char
                EnemyHighlights[char] = hl
            end

            local _, styleCol = getStyleProps(Config.EnemyChamStyle, now, 0)
            local isWire = (Config.EnemyChamStyle == "Wireframe")
            hl.FillColor = visible and styleCol or Color3.fromRGB(160, 70, 70)
            hl.OutlineColor = visible and Palette.White or styleCol
            hl.FillTransparency = isWire and 0.9 or (visible and 0.65 or 0.72)
            hl.OutlineTransparency = 0
        elseif EnemyHighlights[char] then
            pcall(function() EnemyHighlights[char]:Destroy() end)
            EnemyHighlights[char] = nil
        end

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
    if GameModules.Shake and OrigShakeNew then GameModules.Shake.new = OrigShakeNew end
    if GameModules.Stats and OrigGetStats then GameModules.Stats.getStatsForAttachments = OrigGetStats end
    if GameModules.Projectile and OrigProjNew then GameModules.Projectile.new = OrigProjNew end
    if GameModules.FastCast and OrigFastCastFire then GameModules.FastCast.Fire = OrigFastCastFire end
    if GameModules.ActiveCast and OrigActiveCastNew then GameModules.ActiveCast.new = OrigActiveCastNew end
    clearChamGroup("Enemy")
    clearChamGroup("Hands")
    clearChamGroup("Weapon")
    restoreSurfaceAppearancesFor(nil)
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
