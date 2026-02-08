local Tekscripts = loadstring(game:HttpGet("https://raw.githubusercontent.com/TekScripts/TekUix/refs/heads/main/src/main.lua"))()
local gui = Tekscripts.new({ Name = "Tkst | Phantom V2.2", FloatText = "abrir", startTab = "mainTab", Transparent = true })

gui:Notify({
   Title = "beta version",
   Desc = "Esta versão é experimental. Reporte bugs se necessário."
})

local AREA_THICKNESS = 0.5
local OUTER_TRANSPARENCY = 0.18
local INNER_TRANSPARENCY = 0.9
local AREA_COLOR = Color3.fromRGB(255, 255, 255)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer
local lastTarget = nil
local ballProcessed = false
local lastProcessReset = 0 
local smoothedPing = 0.05
local lastVisualUpdate = 0

local ClashState = {
    Active = false,
    LastActivationTime = 0,
    DecayTime = 0.6,
    MinDistance = 35,
    CriticalDistance = 14,
    IsBursting = false
}

local Cache = {
    Character = nil,
    RootPart = nil,
    Ball = nil
}

local function setupCharacter(character)
    if not character then return end
    Cache.Character = character
    Cache.RootPart = character:WaitForChild("HumanoidRootPart", 10)
    ballProcessed = false
end

LocalPlayer.CharacterAdded:Connect(setupCharacter)
setupCharacter(LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait())

local BallSync = {
    RealPosition = Vector3.new(0,0,0),
    Speed = 0,
    TargetID = -999
}

local Config = {
    activationDistanceOffset = 6,
    enableAuraLogic = true,
    enableAuraVisual = true,
    manualPingOffset = 0.045,
    clashSpamThreshold = 0.98, 
    clashBurstRate = 40,
    processResetInterval = 0.4 
}

local TS_Folder = ReplicatedStorage:WaitForChild("TS", 10)
local NetRemotes = TS_Folder and TS_Folder:WaitForChild("GeneratedNetworkRemotes", 10)
local parryRemote = NetRemotes and NetRemotes:FindFirstChild("RE_4.6848415795802784e+76")
local ballSyncRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BallSyncData")

local function performClashSpam()
    if ClashState.IsBursting or not parryRemote or not Cache.RootPart then return end
    
    ClashState.IsBursting = true
    task.defer(function()
        for i = 1, Config.clashBurstRate do
            if not ClashState.Active then break end
            parryRemote:FireServer(2.933813859058389e+76, Cache.RootPart.CFrame, Cache.Ball and Cache.Ball.CFrame)
            if i % 6 == 0 then task.wait() end 
        end
        ClashState.IsBursting = false
    end)
end

local TargetHistory = {}
local function updateClashDetection(newTargetID, currentBallPos)
    local now = tick()
    if newTargetID == lastTarget then return end
    
    lastTarget = newTargetID
    ballProcessed = false 

    if not Cache.RootPart then return end
    
    local dist = (Cache.RootPart.Position - currentBallPos).Magnitude

    if newTargetID == LocalPlayer.UserId and dist < ClashState.CriticalDistance then
        ClashState.Active = true
        ClashState.LastActivationTime = now
        return
    end

    table.insert(TargetHistory, 1, now)
    if #TargetHistory > 5 then table.remove(TargetHistory) end

    if #TargetHistory >= 3 then
        local totalGap = 0
        for i = 1, #TargetHistory - 1 do
            totalGap = totalGap + (TargetHistory[i] - TargetHistory[i+1])
        end
        local averageGap = totalGap / (#TargetHistory - 1)

        local speedFactor = math.clamp(BallSync.Speed / 150, 0, 0.2)
        local clashThreshold = 0.42 + speedFactor 

        if averageGap < clashThreshold and dist < ClashState.MinDistance then
            ClashState.Active = true
            ClashState.LastActivationTime = now
        else
            if dist > ClashState.MinDistance then
                ClashState.Active = false
            end
        end
    end
end

local function createAuraPart(name)
    local existing = Workspace:FindFirstChild(name)
    if existing then existing:Destroy() end
    
    local p = Instance.new("Part")
    p.Name = name; p.Shape = Enum.PartType.Ball; p.Material = Enum.Material.ForceField
    p.Color = AREA_COLOR; p.Anchored = true; p.CanCollide = false; p.CastShadow = false
    p.Transparency = 1; p.Parent = Workspace
    return p
end

local outer = createAuraPart("AuraOuter")
local inner = createAuraPart("AuraInner")

ballSyncRemote.OnClientEvent:Connect(function(data)
    if typeof(data) == "table" then
        BallSync.RealPosition = data.RealPosition or BallSync.RealPosition
        BallSync.Speed = typeof(data.Speed) == "number" and data.Speed or (data.Speed and data.Speed.Magnitude or 0)
        
        if data.TargetPlayerID then
            updateClashDetection(data.TargetPlayerID, BallSync.RealPosition)
            BallSync.TargetID = data.TargetPlayerID
        end
    end
end)

RunService.RenderStepped:Connect(function(dt)
    local now = tick()
    
    if not Cache.RootPart or not Cache.RootPart.Parent then 
        outer.Transparency = 1; inner.Transparency = 1
        return 
    end

    if not Cache.Ball or not Cache.Ball.Parent then
        Cache.Ball = Workspace:FindFirstChild("GameBall")
        return
    end
    
    local rawPing = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
    smoothedPing = (smoothedPing * 0.8) + (rawPing * 0.2)

    local ballPos = (BallSync.RealPosition ~= Vector3.zero) and BallSync.RealPosition or Cache.Ball.Position
    local relativeVel = (Cache.Ball.AssemblyLinearVelocity - Cache.RootPart.AssemblyLinearVelocity).Magnitude
    local effectiveSpeed = math.max(relativeVel, BallSync.Speed, 1)
    
    local distance = (Cache.RootPart.Position - ballPos).Magnitude
    local timeToReach = distance / effectiveSpeed

    if Config.enableAuraLogic and BallSync.TargetID == LocalPlayer.UserId then
        if ClashState.Active then
            if timeToReach <= Config.clashSpamThreshold then
                performClashSpam()
            end
        else
            local normalThreshold = math.clamp(0.12 + (smoothedPing * 1.05) + Config.manualPingOffset, 0.05, 0.55)
            if timeToReach <= normalThreshold and not ballProcessed then
                parryRemote:FireServer(2.933813859058389e+76, Cache.RootPart.CFrame, Cache.Ball.CFrame)
                ballProcessed = true
                lastProcessReset = now
            end
        end
    end

    if ballProcessed and (now - lastProcessReset) >= Config.processResetInterval then
        ballProcessed = false
    end
    if ClashState.Active and (now - ClashState.LastActivationTime) > ClashState.DecayTime then
        ClashState.Active = false
    end
    if #TargetHistory > 0 and (now - TargetHistory[1]) > 1.2 then
        table.clear(TargetHistory)
    end

    if Config.enableAuraVisual and (now - lastVisualUpdate) > 0.015 then
        lastVisualUpdate = now
        local visualSize = (math.max(BallSync.Speed, 45) * 0.22) + Config.activationDistanceOffset
        
        outer.CFrame = Cache.RootPart.CFrame
        inner.CFrame = Cache.RootPart.CFrame
        
        local targetColor = ClashState.Active and Color3.fromRGB(255, 40, 40) or AREA_COLOR
        outer.Color = outer.Color:Lerp(targetColor, 0.25)
        
        outer.Size = Vector3.new(visualSize * 2, visualSize * 2, visualSize * 2)
        inner.Size = Vector3.new((visualSize - 0.4) * 2, (visualSize - 0.4) * 2, (visualSize - 0.4) * 2)
        
        outer.Transparency = OUTER_TRANSPARENCY
        inner.Transparency = INNER_TRANSPARENCY
    elseif not Config.enableAuraVisual then
        outer.Transparency = 1; inner.Transparency = 1
    end
end)

local mainTab = gui:CreateTab({ Title = "Combat", Icon = "shield" })

gui:CreateToggle(mainTab, { Text = "Auto Parry", InitialValue = true, Callback = function(v) Config.enableAuraLogic = v end })
gui:CreateToggle(mainTab, { Text = "Aura Visual", InitialValue = true, Callback = function(v) Config.enableAuraVisual = v eneneneneneneennCCllaas
