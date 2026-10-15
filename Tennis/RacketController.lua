-- [[ SERVICES ]] --
local Framework = require(game:GetService("ReplicatedStorage").Packets.Framework.Packages.Client)
local TrajectoryMath = require(game.ReplicatedStorage.Shared.Modules.TrajectoryMath)
local ActionManager = require(game.ReplicatedStorage.ActionManager.ActionManager)
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- [[ VARIABLES ]] --
local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Events = ReplicatedStorage.Shared.Events
local Camera = workspace.CurrentCamera
local isMobile = false
local DEBUGController = nil

if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled then
    isMobile = true
end

local Client = {
    Name = "ToolController";
    Racket = nil;
    RacketExtentsSize = nil;
    Caster = nil;
    CurrentArm = "Right";
}

local hitDebounce = false
local Maid = Framework.Maid.new()
local CollisionCaster = require(ReplicatedStorage.Shared.Modules.Collision)
local InputController

local PlayContext = ReplicatedStorage:WaitForChild("InputActionSystem"):WaitForChild("PlayContext")
local ConfirmHitAction = PlayContext:WaitForChild("ConfirmHit")

local offsets = {
    [0]  = "f32", [4]  = "f32", [8]  = "f32", [12] = "f32", [16] = "f32", [20] = "f32",
    [24] = {"string",6}, [31] = "f32", [35] = "i8", [37] = "u8", [39] = {"string",12},
    [51] = "f32", [56] = {"string",8}, [64] = "i8", [66] = "i8",
    [67] = "i8", 
    [68] = "i8",  
}

-- [[ PRIVATE FUNCTIONS ]] --
local function findRacketInModel(Object: Model) 
    for i, Tool in pairs(Object:GetChildren()) do
        if Tool:IsA("Tool") or Tool:IsA("Model") then return Tool end
    end
end

local function handleRacketCollisionGroup(Racket: Model) 
    for _, V in Racket:GetDescendants() do
        if V:IsA("BasePart") then
            V.CollisionGroup = "Racket"
            V.Anchored = false
        end
    end
end

local function findBallOwner(ballName)
    for _, plr in pairs(Players:GetPlayers()) do
        local rest = string.sub(ballName, #plr.Name + 1)
        if string.sub(ballName, 1, #plr.Name) == plr.Name and tonumber(rest) then
            return plr
        end
    end
    return nil
end

local function canPlayerHitBall(PlayerOne: Player, PlayerTwo: Player, PlayerOneCourtObject: ObjectValue, PlayerTwoCourtObject: ObjectValue, LastHit, Ball) 
    if PlayerOne:GetAttribute("TeamID") then
        if LastHit then
            if Players:FindFirstChild(LastHit) then
                if Players:FindFirstChild(LastHit):GetAttribute("TeamID") == PlayerOne:GetAttribute("TeamID") and (LastHit ~= PlayerOne.Name) then
                    return false, "TeamID"
                end
            end
        end
    end
    if PlayerOneCourtObject ~= nil then
        if PlayerTwoCourtObject == nil then return false,"PlayerTwoCourt" end
        if PlayerOneCourtObject.Value ~= PlayerTwoCourtObject.Value then return false,"PlayerOneCourt" end
    else
        if PlayerTwoCourtObject ~= nil then return false,"PlayerTwoCourtObjectIdk" end
    end
    if PlayerOne:GetAttribute("CanHitBall") == false then return false,"CanHitBall" end
end

local function createQuestData(Charge: number, isServe: boolean) 
    local questData = {
        ["ShotType"] = Player:GetAttribute("CurrentSwing"),
        ["Charge"] = Charge,
    }
    if questData.ShotType == "Spike" then
        if isServe then questData.ShotType = "Serve" end
    end
    return questData
end

local function getImpulseInformation(isSpike, isSliding, isDiving, isServing, ball, Spin, CameraMove) 
    local inputController = Framework.GetController("InputController")
    local topbarController = Framework.GetController("TopbarController")
    local ShotController = Framework.GetController("Bezier")
    local DataController = Framework.GetController("DataController")
    local TutorialController = Framework.GetController("TutorialController")

    local chargeToUse = inputController.LastReleasedCharge or 1
    local EasyServing = topbarController:GetState("Easy Serving")
    local EasyMobile = topbarController:GetState("Mobile Easy Hitting")
    local MouseAss = topbarController:GetState("Mouse Assistant")
    local logInTimes = DataController:GetInfo("LogInTimes")
    
    local MOBILE_MAX_CHARGE = 0.85

    local editedCharge = false
    if (EasyServing and isServing == true and Player:GetAttribute("Serving") == true and isSpike == true) or (isMobile) then 
        chargeToUse = MOBILE_MAX_CHARGE
    end
    if (logInTimes < 3 or (MouseAss and isServing)) and not isMobile then
        chargeToUse = 1
        editedCharge = true
    end
    if chargeToUse < 0.8 or editedCharge then
        if logInTimes < 3 or MouseAss then
            if isMobile then
                TutorialController:ActiveTip("You're hitting the ball without full power (green bar on bottom of your screen)! To hit full power, hold down on forehand or backhand button and move ur finger away more, to make the swipe longer! Red means more power!", 3)
            else
                TutorialController:ActiveTip("You're hitting the ball without full power (green bar on bottom of your screen)! Hold right or left click longer before releasing to build charge!", 3)
            end
        end
    end
    local FinalCharge = ((0.1 + math.pow(chargeToUse, 0.75)) * 1.1) / 2
    local FinalCameraCFrame = inputController.LastReleasedCameraCFrame or workspace.CurrentCamera.CFrame
    local PlayMode = inputController.ToUseOnHitPlayMode

    local Impulse, _, isServe = ShotController:CalculateImpulse(
        ball,
        FinalCameraCFrame,
        FinalCharge,
        Player,
        inputController.Side,
        Player.Character.HumanoidRootPart.CFrame,
        isSpike,
        isSliding,
        isDiving,
        PlayMode,
        game.Players.LocalPlayer:GetAttribute("CurrentSwing")
    )

    local QuestData = createQuestData(FinalCharge, isServe)

    return {
        ["Impulse"] = Impulse;
        ["isServe"] = isServe;
        ["QuestData"] = QuestData;
    }
end

local function determineTrajectoryStartPosition(ball: BasePart, ServeIndicatorFixedPosition: boolean, isServing: boolean) 
    local inMatch = Player:GetAttribute("InMatch")
    local previewStart = Player:GetAttribute("PreviewStart")
    local TutorialController = Framework.GetController("TutorialController")
    local topbarController = Framework.GetController("TopbarController")

    local startPos = ball.Position
    local servingChange = false
    local EasyServing = topbarController:GetState("Easy Serving")

    if ServeIndicatorFixedPosition == true and previewStart and inMatch == true  and isServing == true then
        if ((Player:GetAttribute("PreviewStart").Y-ball.Position.Y) < 5 or isMobile or EasyServing) and math.abs(Player:GetAttribute("PreviewStart").X-ball.Position.X) < 2.5 and math.abs(Player:GetAttribute("PreviewStart").Z-ball.Position.Z) < 2.5 then
            startPos = Player:GetAttribute("PreviewStart")
            servingChange = true
        end
    end
    if previewStart and inMatch == true  and isServing == true  then
        if (Player:GetAttribute("PreviewStart").Y-ball.Position.Y) > 3.5 and not servingChange  then
            TutorialController:ActiveTip("You're hitting your serve when the ball is too low. Hit it when its at its peak, above your head!", 5)
        end
        if math.abs(Player.Character.Head.Position.X-ball.Position.X) > 3 or math.abs(Player.Character.Head.Position.Z-ball.Position.Z) > 5 then
            TutorialController:ActiveTip("After the ball tosses up for you, don't move! You want to stand still until you've served the ball.", 5)
        end
    end
    if inMatch and game.Players.LocalPlayer:GetAttribute("CurrentSwing") == "Spike" and not isServing and not (game.Players.LocalPlayer:GetAttribute("Diving") == true or game.Players.LocalPlayer:GetAttribute("Sliding") == true) then
        if (Player.Character.Head.Position.Y-ball.Position.Y) > 1 then
            TutorialController:ActiveTip("Spike shots are meant for high balls! Use forehand/backhand for normal shots!", 5)
        end
    end

    return startPos, servingChange
end

local function getTrajectoryInformation(ImpulseInformation, ballOwner, ballName, startPos, Spin, CameraMove, hasBounced, PlayMode)
    local currentSwing = Player:GetAttribute("CurrentSwing")
    local finalVelocity, finalAcceleration = TrajectoryMath.Calculate(
        ImpulseInformation["Impulse"], Spin, CameraMove, ImpulseInformation["isServe"],
        hasBounced or false, 1, 0, PlayMode, currentSwing
    )
    return {
        Spin = Spin,
        Velocity = finalVelocity,
        Acceleration = finalAcceleration,
        HitType = currentSwing, 
    }
end

local function hitBallWithTrajectory(finalTrajectoryInformation, impulseInformation, trajectoryStartPosition, Spin, CameraMove, changedForServing, ball, isServing, hasBounced)
    local BallService = Framework.GetService("BallService")
    local inputController = Framework.GetController("InputController")

    local startTime = workspace:GetServerTimeNow()
    local ping = math.clamp(math.floor(Player:GetNetworkPing() * 2000), -128, 127)
    local timeDelay = Player:GetNetworkPing()
    local startPos = trajectoryStartPosition
    local PlayMode = inputController.ToUseOnHitPlayMode
    local LastReleasedSliceMagnitude = inputController.LastReleasedSliceMagnitude
    local HitType = finalTrajectoryInformation.HitType

    local function floorVec3(Vec)
        return vector.create(
            tonumber(string.format("%.2f",tostring(Vec.X))),
            tonumber(string.format("%.2f",tostring(Vec.Y))),
            tonumber(string.format("%.2f",tostring(Vec.Z)))
        )
    end

    task.defer(function()
        local Buff = buffer.create(70) 

        local Diving = if game.Players.LocalPlayer:GetAttribute("Diving") == true then 1 else 0
        local Sliding = if game.Players.LocalPlayer:GetAttribute("Sliding") == true then 1 else 0
        local Swing = HitType or ""; 
        local Magnitude = LastReleasedSliceMagnitude or 0

        buffer.writef32(Buff,0,startPos.X)
        buffer.writef32(Buff,4,startPos.Y)
        buffer.writef32(Buff,8,startPos.Z)

        local Impulse = floorVec3(impulseInformation["Impulse"])
        buffer.writef32(Buff,12,Impulse.X)
        buffer.writef32(Buff,16,Impulse.Y)
        buffer.writef32(Buff,20,Impulse.Z)

        buffer.writestring(Buff,24,Spin,#Spin)
        buffer.writef32(Buff,31,CameraMove)
        buffer.writei8(Buff,35,ping)
        buffer.writeu8(Buff,37,timeDelay)
        buffer.writestring(Buff,39,PlayMode,#PlayMode);
        buffer.writef32(Buff,51,Magnitude)
        buffer.writestring(Buff,56,Swing,#Swing)
        buffer.writei8(Buff,64,Diving)
        buffer.writei8(Buff,66,Sliding)
        buffer.writei8(Buff,67,isServing and 1 or 0) 
        buffer.writei8(Buff,68,hasBounced and 1 or 0)  

        BallService.ReplicateVelocity:Fire(ball.Name,Buff,impulseInformation["QuestData"])
        if Player:GetRankInGroup(17225134) > 2 then
            DEBUGController:DisplayBuffer(Buff,offsets)
        end
    end)

    if Player:GetAttribute("ForceServing") ~= true then
        Player:SetAttribute("Serving", false)
    end
end

local function handlePlayerStuffOnBallHit() 
    local playerController = Framework.GetController("PlayerController")
    local inputController = Framework.GetController("InputController")

    if Player:FindFirstChild("CourtObject") ~= nil then
        playerController:ChangeServeBarrierStatus(
            Player:FindFirstChild("CourtObject").Value,
            false
        )
    end

    task.delay(0.2, function()
        inputController:StopPreview()
        Client:NormalHitbox()
    end)
end

local function handleHitSounds(ballName: string, hitPart: BasePart) 
    local EffectsService = Framework.GetService("EffectsService")
    local SoundController = Framework.GetController("SoundController")
    local topbarController = Framework.GetController("TopbarController")

    local customEffectName = Client.Racket and Client.Racket:GetAttribute("HitEffect")
    local HitEffect = (customEffectName and ReplicatedStorage.Shared.Effects:FindFirstChild(customEffectName)) 
        or ReplicatedStorage.Shared.Effects:FindFirstChild("HitEffect")

    EffectsService.HitEffect:Fire(ballName)

    if not HitEffect then return end

    local hitSound = HitEffect:GetAttribute("Sound")
    local SoundStartAt = HitEffect:GetAttribute("SoundStartAt")
    local SoundSpeed = HitEffect:GetAttribute("SoundSpeed")
    local SoundVolume = HitEffect:GetAttribute("SoundVolume")
    local HitSFX = topbarController:GetState("Hit Ball SFX")

    if HitSFX and hitSound then  
        SoundController:PlayAndReplicateSound(hitSound, SoundStartAt or 0, hitPart, nil, SoundSpeed, SoundVolume)
    end
end

local function DisplayHit(HitPos)
    local Part = Instance.new("Part")
    Part.Size = vector.create(.2,.2,.2);
    Part.Position = HitPos
    Part.Color = Color3.fromRGB(math.random(60,255), math.random(60,255), math.random(60,255))
    Part.Material = Enum.Material.Neon
    Part.Shape = Enum.PartType.Ball;
    Part.Anchored = true
    Part.CanCollide = false;
    Part.CanQuery = false;
    Part.Parent = workspace
    return Part
end

local function isPointInBox(point, part, padding)
    padding = padding or 0
    local relative = part.CFrame:PointToObjectSpace(point)
    local halfSize = part.Size / 2 + Vector3.new(padding, padding, padding)
    return math.abs(relative.X) <= halfSize.X
        and math.abs(relative.Y) <= halfSize.Y
        and math.abs(relative.Z) <= halfSize.Z
end

local function HandleHit(Hit: BasePart, HitboxPart: BasePart) 
    task.spawn(function()
        if not Hit then return end   
        if DEBUGController:GetState("RacketHitLocation") then DisplayHit(Hit) end

        local inputController = Framework.GetController("InputController")
        local SoundController = Framework.GetController("SoundController")
        local playerController = Framework.GetController("PlayerController")
        local guiController = Framework.GetController("GUIController")
        local topbarController = Framework.GetController("TopbarController")

        local startTime = os.clock()
        repeat task.wait() until inputController.WasReleased == true or os.clock()-startTime > 0.6

        if not Hit.Parent then return end
        
        if not HitboxPart or not HitboxPart.Parent then return end
        if not isPointInBox(Hit.Position, HitboxPart, 0.35) then
            return
        end

        local Ball = Hit
        local ballName = Ball.Name

        if string.sub(ballName, 1, 6) == "Ghost_" then
            ballName = string.sub(ballName, 7)
        end

        local RealBall = workspace.Balls:FindFirstChild(ballName) or workspace.EventBalls:FindFirstChild(ballName)
        if not RealBall then return end
        Ball = RealBall
        local toBall = (Ball.Position - Player.Character.HumanoidRootPart.Position)
        
        if Ball:GetAttribute("NetTouchedOnServe") == true then return end
        local ballOwner = findBallOwner(ballName)

        local ServerTimeNow = workspace:GetServerTimeNow()
        local timeSinceSpawn = Ball:GetAttribute("SpawnTime") ~= nil and ServerTimeNow - Ball:GetAttribute("SpawnTime") or 0
        local timeSinceLastHit = Ball:GetAttribute("LastHitTime") ~= nil and ServerTimeNow - Ball:GetAttribute("LastHitTime") or 10000

        if not ballOwner then return end

        local localPlayerCourtObject =Player:FindFirstChild("CourtObject") 
        local ballOwnerCourtObject = ballOwner:FindFirstChild("CourtObject") 
        local lastHit = Ball:GetAttribute("LastHit")
        local isServing = Player:GetAttribute("Serving") == true or Player:GetAttribute("ForceServing") == true
        local isSpike = Player:GetAttribute("CurrentSwing") == "Spike" and true or false
        local isSliding = Player:GetAttribute("Sliding") == true or false
        local isDiving = Player:GetAttribute("Diving") == true or false
        local ServeIndicatorFixedPosition = topbarController:GetState("Serve Indicator Fixed Position") 
        local Spin = Player:GetAttribute("ServeSpin") or "Flat" 
        local CameraMove = inputController.LastReleasedCameraMove or Client:determineHowCameraCFrameMoved()
        local WasReleased = inputController.WasReleased
        local PlayMode = inputController.ToUseOnHitPlayMode

        local C1 = Framework.Assert(Ball:IsDescendantOf(workspace.Balls) or Ball:IsDescendantOf(workspace.EventBalls))
        local C2 = Framework.Assert(WasReleased == true)
        local C3 = Framework.Assert(hitDebounce == false)
        local C4 = Framework.Assert(timeSinceLastHit >= 0.1)
        local C5 = Framework.Assert(ballOwner ~= nil)
        local C6 = Framework.Assert(timeSinceSpawn >= 0.5)
        if C1 or C2 or C3 or C4 or C5 or C6 then return end

        local canHitBall, Msg = canPlayerHitBall(Player, ballOwner, localPlayerCourtObject, ballOwnerCourtObject, lastHit, Ball)
        if canHitBall == false then
            return
        end

        local impulseInformation = getImpulseInformation(isSpike, isSliding, isDiving, isServing, Ball, Spin, CameraMove) 
        if impulseInformation.Impulse.Magnitude <= 0 then return end

        hitDebounce = true
        task.delay(0.75, function()
            hitDebounce = false
        end)
        inputController:GamepadHitPulse()
        handlePlayerStuffOnBallHit()

        local predictedPos = Framework.GetController("BallController"):GetPredictedPosition(ballName)
        local trajectoryStartPosition, changedForServing = determineTrajectoryStartPosition(Ball, ServeIndicatorFixedPosition, isServing)
        if predictedPos and not isServing then
            if (predictedPos - Ball.Position).Magnitude < 15 then
                trajectoryStartPosition = predictedPos
            end
        end

        local hasBounced = Ball:GetAttribute("HasBounced") == true
        local finalTrajectoryInformation = getTrajectoryInformation(impulseInformation, ballOwner, ballName, trajectoryStartPosition, Spin, CameraMove, hasBounced, PlayMode)

        Framework.GetController("BallController"):PredictLocalTrajectory(
            Ball, trajectoryStartPosition, finalTrajectoryInformation.Velocity, finalTrajectoryInformation.Acceleration,
            nil, impulseInformation["Impulse"], CameraMove 
        )
        hitBallWithTrajectory(
            finalTrajectoryInformation, impulseInformation, trajectoryStartPosition,
            Spin, CameraMove, changedForServing, Ball,
            isServing, hasBounced 
        )
        handleHitSounds(ballName, Hit)

        guiController:HideSliceMagnitudeVisual()

        task.delay(0.75, function()
            hitDebounce = false
        end)
    end)
end

local function newHitboxes(Hitboxes: Folder) 
    Maid:Cleanup() 
    for i, hitbox in pairs(Hitboxes:GetChildren()) do
        Maid:AddTask(
            task.spawn(function()
                local Caster = CollisionCaster.newHitbox(hitbox)
                Caster.PARAMS.FilterDescendantsInstances = {game.Workspace.Balls, game.Workspace.EventBalls, workspace.CurrentCamera}
                Caster.OVERLAPPARAMS.FilterDescendantsInstances = {game.Workspace.Balls, game.Workspace.EventBalls, workspace.CurrentCamera}
                Client.Caster = Caster
                Caster:OnHit(function(Hit)
                    HandleHit(Hit, hitbox)
                end)
            end)
        )
    end
end

-- [[ PUBLIC FUNCTIONS ]] --
function Client:Start()
    local topbarController = Framework.GetController("TopbarController")
    local HitboxService = Framework.GetService("HitboxService")
    local InputController = Framework.GetController("InputController")
    DEBUGController = Framework.GetController("DEBUG")

    game.Workspace.Balls.ChildAdded:Connect(function(ball)
        if not ball:IsA("BasePart") then return end
        if string.sub(ball.Name, 1, #Player.Name) ~= Player.Name then return end
        Player:SetAttribute("ServeCamCFrame", Camera.CFrame)
    end)

    local function onCharacterAdded(char: Model)
        self:ListenForRacket(char)
        local hitboxes = char:WaitForChild("Hitboxes", 5)
        if hitboxes then
            newHitboxes(hitboxes)
            InputController.Hitbox = self.Caster
        end
    end

    local function handleSwitchInputsSettingChanged(newState: boolean)
        if self.CurrentArm == "Left" then
            if newState == true then
                Player:SetAttribute("ForehandInput", "Left")
                Player:SetAttribute("BackhandInput", "Right")
            else
                Player:SetAttribute("ForehandInput", "Right")
                Player:SetAttribute("BackhandInput", "Left")
            end
        else
            Player:SetAttribute("ForehandInput", "Right")
            Player:SetAttribute("BackhandInput", "Left")
        end
    end

    Player.CharacterAdded:Connect(onCharacterAdded)
    if Character then onCharacterAdded(Character) end

    topbarController:Connect("Switch Left Hand Inputs", function(newState: boolean)
        handleSwitchInputsSettingChanged(newState)
    end)

    HitboxService.HandleHitboxes:Connect(function()
        newHitboxes(Player.Character:FindFirstChild("Hitboxes"))
        InputController.Hitbox = self.Caster
    end)
end

function Client:ListenForRacket(Character: Model) 
    task.spawn(function()
        if not Character then return end

        local rightName = Character:GetAttribute("RigType") == "R15" and "RightHand" or "Right Arm"
        local leftName = Character:GetAttribute("RigType") == "R15" and "LeftHand" or "Left Arm"

        local Right = Character:WaitForChild(rightName, 10)
        local Left = Character:WaitForChild(leftName, 10)

        if not Right or not Left then 
            warn("[ToolController] Could not find player arms to attach racket listeners.")
            return 
        end

        local function handleRacketAdded(Racket: Instance, Arm: string)
            if Racket:IsA("Tool") or Racket:IsA("Model") then 
                self:NewRacket(Racket, Arm) 
            end
        end

        local RightLimbRacket = findRacketInModel(Right)
        local LeftLimbRacket = findRacketInModel(Left)

        if RightLimbRacket then self:NewRacket(RightLimbRacket, "Right") end
        if LeftLimbRacket then self:NewRacket(LeftLimbRacket, "Left") end

        Maid:AddTask(Right.ChildAdded:Connect(function(Racket) handleRacketAdded(Racket, "Right") end))
        Maid:AddTask(Left.ChildAdded:Connect(function(Racket) handleRacketAdded(Racket, "Left") end))
    end)
end

function Client:ServeHitbox() end
function Client:SpikeHitbox() end
function Client:NormalHitbox() end
function Client:SliceHitbox() end

function Client:determineHowCameraCFrameMoved()
    local hand = Framework.GetController("AnimationController").CurrentHand
    local pastCFrame = Player:GetAttribute("ServeCamCFrame")
    local currentCFrame = game.Workspace.CurrentCamera.CFrame
    if not pastCFrame then return 0 end

    local currentSwing = Player:GetAttribute("CurrentSwing")
    local isServingNow = Player:GetAttribute("Serving") == true
    local invert = (currentSwing == "Forehand") or (currentSwing == "Spike" and isServingNow)

    local pastDirection = pastCFrame.LookVector
    local currentDirection = currentCFrame.LookVector
    local dot = math.clamp(pastDirection:Dot(currentDirection), -1, 1)
    local angle = math.acos(dot)
    local crossProduct = pastDirection:Cross(currentDirection)
    local sign = math.sign(crossProduct.Y)
    local MAX_SWIPE_ANGLE = math.rad(35)

    local rightMovementMagnitude = sign * math.clamp(angle / MAX_SWIPE_ANGLE, 0, 1) * (invert and -1 or 1)

    if rightMovementMagnitude > 0 and hand == "Right" then
        rightMovementMagnitude = 0
    elseif rightMovementMagnitude < 0 and hand == "Left" then
        rightMovementMagnitude = 0
    end

    return rightMovementMagnitude
end

function Client:GetCurrentArm()
    return self.CurrentArm
end

function Client:NewRacket(Racket: Model, Arm: string)
    local EffectsService = Framework.GetService("EffectsService")
    local guiController = Framework.GetController("GUIController")
    local topbarController = Framework.GetController("TopbarController")
    local ShotController = Framework.GetController("Bezier")
    InputController = Framework.GetController("InputController")

    local SwitchInputs = topbarController:GetState("Switch Left Hand Inputs")
    handleRacketCollisionGroup(Racket)

    if Arm == "Left" then
        if SwitchInputs == true then
            Player:SetAttribute("ForehandInput", "Left")
            Player:SetAttribute("BackhandInput", "Right")
        else
            Player:SetAttribute("ForehandInput", "Right")
            Player:SetAttribute("BackhandInput", "Left")
        end
    else
        Player:SetAttribute("ForehandInput", "Right")
        Player:SetAttribute("BackhandInput", "Left")
    end

    self.Racket = Racket
    self.RacketExtentsSize = game.ReplicatedStorage.Shared.ItemStorage.Rackets.DefaultRacket:GetExtentsSize()
    Player:SetAttribute("RacketReach", self.RacketExtentsSize.Z)
    self.CurrentArm = Arm
end

-- [[ FRAMEWORK INIT ]] --
return Client