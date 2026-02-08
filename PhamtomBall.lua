-- > CONFIG VISUAL DA ÁREA
local AREA_THICKNESS = 0.5
local OUTER_TRANSPARENCY = 0.18
local INNER_TRANSPARENCY = 0.9
local AREA_COLOR = Color3.fromRGB(255, 255, 255)

-- > SERVIÇOS
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

-- > ESTADO LOCAL E PERSISTÊNCIA
local LocalPlayer = Players.LocalPlayer
local lastTarget = nil
local ballProcessed = false
local lastProcessReset = 0 
local smoothedPing = 0.05
local lastVisualUpdate = 0
local ManualSpamActive = false -- --> intenção: Controle de spam manual do usuário

-- > GERENCIAMENTO DE ESTADO DE CLASH
local ClashState = {
    Active = false,
    LastActivationTime = 0,
    DecayTime = 0.6,
    MinDistance = 40,
    CriticalDistance = 25,
    IsBursting = false
}

-- > CACHE DE OBJETOS
-- --> intenção: Evitar chamadas repetitivas ao motor do jogo e garantir persistência pós-morte
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
if LocalPlayer.Character then setupCharacter(LocalPlayer.Character) end

-- > ESTRUTURA DE DATA E CONFIGS
local BallSync = { RealPosition = Vector3.new(0,0,0), Speed = 0, TargetID = -999 }
local Config = {
    activationDistanceOffset = 7,
    enableAuraLogic = true,
    enableAuraVisual = true,
    manualPingOffset = 0.045,
    clashSpamThreshold = 0.98, 
    clashBurstRate = 70,
    processResetInterval = 0.5,
    guiVisible = true
}

-- > REMOTOS (VALIDAÇÃO DE EXISTÊNCIA)
-- --> intenção: Evitar erros de "nil index" se o servidor demorar a carregar os remotos
local TS_Folder = ReplicatedStorage:WaitForChild("TS", 10)
local NetRemotes = TS_Folder and TS_Folder:WaitForChild("GeneratedNetworkRemotes", 10)
local parryRemote = NetRemotes and NetRemotes:FindFirstChild("RE_4.6848415795802784e+76")
local ballSyncRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BallSyncData")

-- > MOTOR DE SPAM
local function performClashSpam()
    if ClashState.IsBursting or not parryRemote or not Cache.RootPart then return end

    ClashState.IsBursting = true
    task.spawn(function() -- --> intenção: Usar spawn para não bloquear a thread principal
        for i = 1, Config.clashBurstRate do
            if not ClashState.Active and not ManualSpamActive then break end
            parryRemote:FireServer(
                2.933813859058389e+76,
                Cache.RootPart.CFrame,
                Cache.Ball and Cache.Ball.CFrame or Cache.RootPart.CFrame
            )
            task.wait() -- --> intenção: Pequeno delay para evitar kick por rate limit de pacotes
        end
        ClashState.IsBursting = false
    end)
end

-- > CRIAÇÃO DA UI FLUTUANTE
local FloatingGui = Instance.new("ScreenGui")
FloatingGui.Name = "ManualSpamGui"
FloatingGui.ResetOnSpawn = false
-- Tenta colocar no CoreGui, se falhar (permissão), vai para PlayerGui
local success, err = pcall(function() FloatingGui.Parent = CoreGui end)
if not success then FloatingGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 150, 0, 100)
MainFrame.Position = UDim2.new(0.5, -75, 0.5, -50)
MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Visible = false 
MainFrame.Parent = FloatingGui

local Header = Instance.new("TextLabel")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 30)
Header.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
Header.Text = "PARRY SPAM"
Header.TextColor3 = Color3.fromRGB(255, 255, 255)
Header.Font = Enum.Font.GothamBold
Header.TextSize = 14
Header.Parent = MainFrame

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Name = "ToggleBtn"
ToggleBtn.Size = UDim2.new(0.8, 0, 0, 40)
ToggleBtn.Position = UDim2.new(0.1, 0, 0.45, 0)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
ToggleBtn.Text = "OFF"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 16
ToggleBtn.Parent = MainFrame

-- > LÓGICA DE ARRASTAR
local dragging, dragInput, dragStart, startPos
Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- > LÓGICA DO BOTÃO TOGGLE
local function updateBtnVisual(active)
    ToggleBtn.Text = active and "ON" or "OFF"
    ToggleBtn.BackgroundColor3 = active and Color3.fromRGB(50, 200, 50) or Color3.fromRGB(200, 50, 50)
end

ToggleBtn.MouseButton1Click:Connect(function()
    ManualSpamActive = not ManualSpamActive
    updateBtnVisual(ManualSpamActive)
end)

-- > LÓGICA DE DETECÇÃO DE CLASH
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
    if #TargetHistory > 4 then table.remove(TargetHistory) end
    if #TargetHistory >= 2 then
        local totalGap = 0
        for i = 1, #TargetHistory - 1 do totalGap = totalGap + (TargetHistory[i] - TargetHistory[i+1]) end
        local averageGap = totalGap / (#TargetHistory - 1)
        local speedFactor = math.clamp(BallSync.Speed / 80, 0, 0.2)
        local clashThreshold = 0.42 + speedFactor
        
        if averageGap < clashThreshold and dist < ClashState.MinDistance then
            ClashState.Active = true
            ClashState.LastActivationTime = now
        else
            if dist > ClashState.MinDistance then ClashState.Active = false end
        end
    end
end

-- > VISUAL (AURA)
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

-- > SYNC DATA
if ballSyncRemote then
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
end

-- > LOOP PRINCIPAL
RunService.RenderStepped:Connect(function(dt)
    local now = tick()
    
    local isAnySpamActive = (ClashState.Active or ManualSpamActive)
    if not dragging then updateBtnVisual(isAnySpamActive) end

    if not Cache.RootPart or not Cache.RootPart.Parent then 
        outer.Transparency = 1; inner.Transparency = 1
        return 
    end

    -- --> intenção: Cache dinâmico da bola para evitar lookups pesados no workspace
    if not Cache.Ball or not Cache.Ball.Parent then
        Cache.Ball = Workspace:FindFirstChild("GameBall") or Workspace:FindFirstChild("Ball")
    end
    
    local rawPing = 0.05
    pcall(function() rawPing = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000 end)
    smoothedPing = (smoothedPing * 0.8) + (rawPing * 0.2)

    local ballPos = (BallSync.RealPosition ~= Vector3.zero) and BallSync.RealPosition or (Cache.Ball and Cache.Ball.Position or Vector3.zero)
    if ballPos == Vector3.zero then return end

    local distance = (Cache.RootPart.Position - ballPos).Magnitude
    local effectiveSpeed = math.max(BallSync.Speed, 1)
    local timeToReach = distance / effectiveSpeed

    -- LÓGICA DE DEFESA
    if ManualSpamActive then
        performClashSpam()
    elseif Config.enableAuraLogic and BallSync.TargetID == LocalPlayer.UserId then
        if ClashState.Active then
            if timeToReach <= Config.clashSpamThreshold then
                performClashSpam()
            end
        elseif not ballProcessed then
            local normalThreshold = math.clamp(0.12 + (smoothedPing * 1.05) + Config.manualPingOffset, 0.05, 0.55)
            if timeToReach <= normalThreshold then
                if parryRemote then
                    parryRemote:FireServer(2.933813859058389e+76, Cache.RootPart.CFrame, ballPos)
                end
                ballProcessed = true
                lastProcessReset = now
            end
        end
    end

    -- Persistência de estado
    if ballProcessed and (now - lastProcessReset) >= Config.processResetInterval then ballProcessed = false end
    if ClashState.Active and (now - ClashState.LastActivationTime) > ClashState.DecayTime then ClashState.Active = false end

    -- ATUALIZAÇÃO VISUAL
    if Config.enableAuraVisual and (now - lastVisualUpdate) > 0.015 then
        lastVisualUpdate = now
        local visualSize = (math.max(BallSync.Speed, 45) * 0.22) + Config.activationDistanceOffset
        outer.CFrame = Cache.RootPart.CFrame
        inner.CFrame = Cache.RootPart.CFrame
        
        local targetColor = isAnySpamActive and Color3.fromRGB(255, 40, 40) or AREA_COLOR
        outer.Color = outer.Color:Lerp(targetColor, 0.2)
        
        outer.Size = Vector3.new(visualSize * 2, visualSize * 2, visualSize * 2)
        inner.Size = Vector3.new((visualSize - 0.4) * 2, (visualSize - 0.4) * 2, (visualSize - 0.4) * 2)
        outer.Transparency = OUTER_TRANSPARENCY
        inner.Transparency = INNER_TRANSPARENCY
    elseif not Config.enableAuraVisual then
        outer.Transparency = 1; inner.Transparency = 1
    end
end)

-- > UI INTEGRATION
local Tekscripts = loadstring(game:HttpGet("https://raw.githubusercontent.com/TekScripts/TekUix/refs/heads/main/src/main.lua"))()
local gui = Tekscripts.new({ Name = "Tkst | Phantom V2.2", FloatText = "abrir", startTab = "mainTab", Transparent = true })
local mainTab = gui:CreateTab({ Title = "Combat", Icon = "shield" })

gui:CreateToggle(mainTab, { 
    Text = "Show Manual Spam UI", 
    InitialValue = false, 
    Callback = function(v) 
        MainFrame.Visible = v 
    end 
})

gui:CreateToggle(mainTab, { Text = "Auto Parry Logic", InitialValue = true, Callback = function(v) Config.enableAuraLogic = v end })
gui:CreateToggle(mainTab, { Text = "Aura Visual", InitialValue = true, Callback = function(v) Config.enableAuraVisual = v end })
