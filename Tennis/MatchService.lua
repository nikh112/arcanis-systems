local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Framework = require(ReplicatedStorage.Packets.Framework.Packages.Server)
local Zone = require(ReplicatedStorage.Shared.Modules.FastZone)
local Maid = require(ReplicatedStorage.Shared.Library.Maid)
local BotModule = require(game.ServerScriptService.Server.Services.CourtService.BotPlayer)

local MatchService = {
	Name = "MatchService";
	Signal = {
		ActivateCourtBarriers = "RemoteEvent";
		DeActivateCourtBarriers = "RemoteEvent";
		ChangeServeBarrierStatus = "RemoteEvent";
		SwitchAnim = "RemoteEvent";
		updateUIScore = "RemoteEvent";
		disableMatchUI = "RemoteEvent";
		endMatchUI = "RemoteEvent";
		MatchCutscene = "RemoteEvent";
		TweenCamera = "RemoteEvent";
		HighlightZones = "RemoteEvent";
		MatchStatusNotification = "RemoteEvent";
		SpawnBot = "RemoteEvent";
	};

	MatchStatuses = {};
	Maids = {};
	MatchThreads = {};
}

-- [[ ANCHOR HELPERS ]] --

local function anchorCharacter(character, state)
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.Anchored = state end

	local realPlayer = character and game.Players:GetPlayerFromCharacter(character)
	if realPlayer and hrp then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if state then
				humanoid.AutoRotate = false
			else
				hrp.CFrame = hrp.CFrame
				task.defer(function()
					if humanoid and humanoid.Parent then
						humanoid.AutoRotate = true
					end
				end)
			end
		end
	end
end

local function teleportAnchored(character, targetCFrame)
	anchorCharacter(character, true)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = targetCFrame
	else
		character:PivotTo(targetCFrame)
	end
end

local function lerpCharacterTo(character, targetCFrame, duration, onComplete)
	anchorCharacter(character, true)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local startCFrame = hrp.CFrame
	local startTime = os.clock()

	local lockedY = startCFrame.Position.Y

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local walkAnimTrack = nil

	if animator then
		local walkAnim = Instance.new("Animation")
		if humanoid.RigType == Enum.HumanoidRigType.R15 then
			walkAnim.AnimationId = "rbxassetid://913376220" -- Standard R15 Walk
		else
			walkAnim.AnimationId = "rbxassetid://180426354" -- Standard R6 Walk
		end

		walkAnimTrack = animator:LoadAnimation(walkAnim)
		walkAnimTrack.Priority = Enum.AnimationPriority.Action4 
		walkAnimTrack.Looped = true 
		walkAnimTrack:Play()
	end

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not character or not character.Parent or not hrp or not hrp.Parent then
			if walkAnimTrack then walkAnimTrack:Stop() end
			conn:Disconnect()
			return
		end
		local alpha = math.clamp((os.clock() - startTime) / duration, 0, 1)

		local lerped = startCFrame:Lerp(targetCFrame, alpha)

		local _, yRot, _ = lerped:ToOrientation()

		local flatCFrame = CFrame.new(lerped.Position.X, lockedY, lerped.Position.Z) * CFrame.Angles(0, yRot, 0)
		hrp.CFrame = flatCFrame

		if walkAnimTrack and not walkAnimTrack.IsPlaying then
			walkAnimTrack:Play()
		end

		if alpha >= 1 then
			conn:Disconnect()
			local finalYRot = select(2, targetCFrame:ToOrientation())
			hrp.CFrame = CFrame.new(targetCFrame.Position.X, lockedY, targetCFrame.Position.Z) * CFrame.Angles(0, finalYRot, 0)

			if walkAnimTrack then walkAnimTrack:Stop() end
			if onComplete then onComplete() end
		end
	end)
	return conn
end

-- [[ LOCAL UTILITY FUNCTIONS ]] --

local function deepCopy(original)
	local copy = {}
	for k, v in pairs(original) do
		copy[k] = (type(v) == "table") and deepCopy(v) or v
	end
	return copy
end

local function findPlayersSide(dict, key)
	local copy = deepCopy(dict)
	if not key then return end
	local userId = typeof(key) ~= "table" and (typeof(key) == "Instance" and key:IsA("Player") and key.UserId or key) or key.UserId
	local plrs = {}
	local plr
	for i, v in pairs(copy) do
		if tonumber(i) == tonumber(userId) then
			plr = v
			table.insert(plrs, v)
		end
	end
	if #plrs == 1 then return plr elseif #plrs > 1 then return plrs end
end

local function findPlayerWithSide(dict, key)
	local copy = deepCopy(dict)
	local plrs = {}
	local plr
	for i, v in pairs(copy) do
		if v == key then
			plr = i
			table.insert(plrs, i)
		end
	end
	if #plrs == 1 then return plr elseif #plrs > 1 then return plrs end
end

local function findindictkey(dict, key)
	for _, p in pairs(dict) do
		if tonumber(p) == key then return true end
	end
end

local function getBestPingPlayer(players)
	local bestPlayer, lowestPing = nil, math.huge
	for plr in pairs(players) do
		local ping = plr:GetNetworkPing()
		if ping < lowestPing then
			lowestPing = ping
			bestPlayer = plr
		end
	end
	return bestPlayer
end

local function getStandOffset(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if humanoid.RigType == Enum.HumanoidRigType.R15 then
			return humanoid.HipHeight + 1 
		else
			return 3.0 
		end
	end
	return 3.0 
end

local function generateRandomID()
	local id = ""
	for _ = 1, 9 do id = id..math.random(0, 9) end
	return id
end

local function anchorModel(model, state)
	for _, part in pairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = not state
		end
	end
end

local function countEntries(dictionary)
	local count = 0
	for _ in pairs(dictionary) do count += 1 end
	return count
end

local function getCameraPositions(court)
	local positions, blocks = {}, {}
	for _, v in pairs(court:GetChildren()) do
		if v:IsA("BasePart") and v.Name:match("Position%d+") and not string.find(v.Name, "Walk") then
			table.insert(blocks, v)
		end
	end
	table.sort(blocks, function(a, b)
		return tonumber(a.Name:match("%d+")) < tonumber(b.Name:match("%d+"))
	end)
	for _, block in pairs(blocks) do
		table.insert(positions, {
			Cframe = block.CFrame,
			Duration = block:GetAttribute("Duration") or 0,
			WaitTime = block:GetAttribute("WaitTime") or 0,
		})
	end
	return positions
end

local function getRandomPositionInPart(part, index, playerCount)
	if playerCount == 1 then return part.CFrame end

	local spreadWidth = part.Size.X
	local offsetDistance = spreadWidth / (playerCount * 2)
	local offset = (index - 1 - (playerCount - 1) / 2) * offsetDistance

	local targetPosition = part.Position + (part.CFrame.RightVector * offset)
	local lookTarget = targetPosition + part.CFrame.LookVector
	return CFrame.lookAt(targetPosition, lookTarget)
end

local function movePlayers(playersTable, part, court, customCount, lookAtPart, onAllComplete)
	local count = 0
	local total = customCount ~= nil and customCount or countEntries(playersTable)
	local completed = 0

	local function markDone()
		completed += 1
		if onAllComplete and completed >= total then
			onAllComplete()
		end
	end

	for plr in pairs(playersTable) do
		count += 1
		if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
			local hrp = plr.Character.HumanoidRootPart
			local pos = getRandomPositionInPart(part, count, customCount ~= nil and customCount or countEntries(playersTable))

			local currentY = hrp.Position.Y
			local finalPos = CFrame.new(pos.Position.X, currentY, pos.Position.Z) * pos.Rotation

			local distance = (hrp.Position - finalPos.Position).Magnitude
			local walkSpeed = 12
			local duration = math.max(distance / walkSpeed, 0.5)

			lerpCharacterTo(plr.Character, finalPos, duration, function()
				if not plr.Character or not plr.Character:FindFirstChild("HumanoidRootPart") then
					markDone()
					return
				end
				local lookTarget = lookAtPart and lookAtPart.Position
					or (court and court:FindFirstChild("Net", true) and court:FindFirstChild("Net", true).Position)

				if lookTarget then
					local charPos = plr.Character.HumanoidRootPart.Position
					local flatLook = Vector3.new(lookTarget.X, charPos.Y, lookTarget.Z)
					plr.Character.HumanoidRootPart.CFrame = CFrame.lookAt(charPos, flatLook)
				end
				markDone()
			end)
		else
			markDone() 
		end
	end
end

local function getNearestBench(pos)
	local distance, benchToUse = math.huge, nil
	for _, bench in pairs(workspace:GetDescendants()) do
		if bench.Name == "BenchZone" then
			local d = (pos - bench.Position).Magnitude
			if d < distance then
				distance, benchToUse = d, bench
			end
		end
	end
	return benchToUse
end

-- [[ SIMPLE ACCESSORS ]] --

function MatchService:GetSideInformation(court)
	if not self.MatchStatuses[court] then return end
	return self.MatchStatuses[court]["playerSides"], self.MatchStatuses[court]["Side"]
end

function MatchService:getPlayerServingOnCourt(court)
	if not self.MatchStatuses[court] then return end
	local serving = self.MatchStatuses[court]["playerServing"]
	return serving and serving[1] and serving[1].UserId
end

function MatchService:isPositionInSide(court, numSide, pos, edit)
	local posToUse = pos
	local sideOneZone = self.MatchStatuses[court]["sideOneZone"]
	local sideTwoZone = self.MatchStatuses[court]["sideTwoZone"]
	local zoneToUse = numSide == 1 and sideOneZone or sideTwoZone

	if edit then
		posToUse = vector.create(pos.X, numSide == 1 and court["SideOneZone"].Position.Y or court["SideTwoZone"].Position.Y, pos.Z)
	end
	return zoneToUse:findPoint(posToUse)
end

function MatchService:getPlayerNamesInCourt(court)
	local playersSideOne = findPlayerWithSide(self.MatchStatuses[court]["playerScoreIndexes"], 1)
	local playersSideTwo = findPlayerWithSide(self.MatchStatuses[court]["playerScoreIndexes"], 2)
	local playerOneA = type(playersSideOne) == "table" and (game.Players:GetPlayerByUserId(playersSideOne[1]) or BotModule:GetPlayerByUserId(playersSideOne[1])) or (game.Players:GetPlayerByUserId(playersSideOne) or BotModule:GetPlayerByUserId(playersSideOne))
	local playerOneB = type(playersSideOne) == "table" and (game.Players:GetPlayerByUserId(playersSideOne[2]) or BotModule:GetPlayerByUserId(playersSideOne[2])) or ""
	local playerTwoA = type(playersSideTwo) == "table" and (game.Players:GetPlayerByUserId(playersSideTwo[1]) or BotModule:GetPlayerByUserId(playersSideTwo[1])) or (game.Players:GetPlayerByUserId(playersSideTwo) or BotModule:GetPlayerByUserId(playersSideTwo))
	local playerTwoB = type(playersSideTwo) == "table" and (game.Players:GetPlayerByUserId(playersSideTwo[2]) or BotModule:GetPlayerByUserId(playersSideTwo[2])) or ""

	playerOneA = playerOneA and playerOneA.Name or ""
	playerOneB = playerOneB and playerOneB.Name or ""
	playerTwoA = playerTwoA and playerTwoA.Name or ""
	playerTwoB = playerTwoB and playerTwoB.Name or ""

	return playerOneA, playerTwoA, playerOneB, playerTwoB
end

function MatchService:RetrieveActiveMatchesInTable()
	local tbl = {}
	for court, match in pairs(self.MatchStatuses) do
		if match["HasBot"] ~= true then
			tbl[court.Name] = {
				startTime = match.startTime;
				playersInMatch = match.playersInMatchUserIds;
				playerStats = match.playerStats;
				gameScore = match.gameScore;
				setScore = match.setScore;
				matchScore = match.matchScore;
				setsPlayed = match.setsPlayed;
				sets = match.sets;
				sides = match.playerSides;
				playerScoreIndexes = match.playerScoreIndexes;
				playerServing = match.playerServing;
				playerReceiving = match.playerReceiving;
			}
		end
	end
	return tbl
end

-- [[ LOGIC & MID-MATCH ACTIONS ]] --

function MatchService:switchCourtEnds(court)
	local status = self.MatchStatuses[court]
	if not status then return end
	for userId, side in pairs(status["playerSides"]) do
		status["playerSides"][userId] = (side == 1) and 2 or 1
	end
end

function MatchService:switchPlayersServing(court)
	local matchStatus = self.MatchStatuses[court]
	local ogServing, ogReceiving = matchStatus["playerServing"], matchStatus["playerReceiving"]

	if court:GetAttribute("CourtType") == "Doubles" then
		local team1, team2 = matchStatus["team1Players"], matchStatus["team2Players"]
		local servingIsTeam1 = (ogServing[1] == team1[1] or ogServing[1] == team1[2])

		local newServingTeam = servingIsTeam1 and team2 or team1
		local newServingIndexKey = servingIsTeam1 and "team2ServeIndex" or "team1ServeIndex"
		matchStatus[newServingIndexKey] = (matchStatus[newServingIndexKey] == 1) and 2 or 1
		local idx = matchStatus[newServingIndexKey]
		local otherIdx = (idx == 1) and 2 or 1

		matchStatus["playerServing"] = { newServingTeam[idx], newServingTeam[otherIdx] }

		local newReceivingTeam = servingIsTeam1 and team1 or team2
		matchStatus["playerReceiving"] = { newReceivingTeam[1], newReceivingTeam[2] }
	else
		matchStatus["playerServing"] = ogReceiving
		matchStatus["playerReceiving"] = ogServing
	end
	self.MatchStatuses[court]["receiverSideMap"] = {}
	self.MatchStatuses[court]["receiverSideMap"][self.MatchStatuses[court]["playerReceiving"][1]] = "One"
	if self.MatchStatuses[court]["playerReceiving"][2] then
		self.MatchStatuses[court]["receiverSideMap"][self.MatchStatuses[court]["playerReceiving"][2]] = "Two"
	end
end

function MatchService:ChangePlayersCanHitBallStatus(court, status)
	for id in pairs(self.MatchStatuses[court]["playerScoreIndexes"]) do
		local player = game.Players:GetPlayerByUserId(id) or BotModule:GetPlayerByUserId(id)
		if player then player:SetAttribute("CanHitBall", status) end
	end
end

function MatchService:SendMatchNotification(court, text, duration)
	for id in pairs(self.MatchStatuses[court]["playerScoreIndexes"]) do
		local player = game.Players:GetPlayerByUserId(id) or BotModule:GetPlayerByUserId(id)
		if player then
			self.Signal.MatchStatusNotification:Fire(player, text, duration)
		end
	end
end

function MatchService:WinPoint(court, winnerID)
	if not self.MatchStatuses[court] then return end
	self.MatchStatuses[court]["pointStatus"] = tonumber(winnerID)
	self:ChangePlayersCanHitBallStatus(court, false)
	task.delay(court:GetAttribute("BallDespawnTime"), function()
		self:destroyAllBalls(court)
		court:SetAttribute("BallDespawnTime", -1)
	end)
end

function MatchService:destroyAllBalls(court)
	local BallService = Framework.GetService("BallService")
	if not self.MatchStatuses[court] then return end
	for index in pairs(self.MatchStatuses[court]["playersInMatch"]) do
		BallService:deletePlayerBall(index)
	end
end

function MatchService:redetermineSides(court)
	local status = self.MatchStatuses[court]
	local sideOneZone, sideTwoZone = status["sideOneZone"], status["sideTwoZone"]

	for _, p in pairs(sideOneZone:getPlayers()) do
		if status["playerSides"][p.UserId] ~= nil then status["playerSides"][p.UserId] = 1 end
	end
	for _, p in pairs(sideTwoZone:getPlayers()) do
		if status["playerSides"][p.UserId] ~= nil then status["playerSides"][p.UserId] = 2 end
	end
	for _, part in pairs(sideOneZone:getParts()) do
		local plr = game.Players:FindFirstChild(part.Parent.Name)
		if plr and status["playerSides"][plr:GetAttribute("UserId")] ~= nil then
			status["playerSides"][plr:GetAttribute("UserId")] = 1
		end
	end
	for _, part in pairs(sideTwoZone:getParts()) do
		local plr = game.Players:FindFirstChild(part.Parent.Name)
		if plr and status["playerSides"][plr:GetAttribute("UserId")] ~= nil then
			status["playerSides"][plr:GetAttribute("UserId")] = 2
		end
	end
end

function MatchService:HighlightZonesForPlayers(court, playerSides, playerServing, servingSide)
	if not self.MatchStatuses[court] then return end
	for player in pairs(self.MatchStatuses[court]["playersInMatch"]) do
		self.Signal.HighlightZones:Fire(player, court, playerSides, playerServing, servingSide)
	end
end

function MatchService:LockKOTCCourt(court)
	local courtType = court:GetAttribute("CourtType")
	local q1 = court:FindFirstChild("QueueSideOne1", true)
	if courtType == "Singles" then
		q1:FindFirstChild("Queue").Enabled = false
	elseif courtType == "Doubles" then
		q1:FindFirstChild("Queue").Enabled = false
		court:FindFirstChild("QueueSideOne2", true):FindFirstChild("Queue").Enabled = false
	end
end

function MatchService:IncrementPlayerStats(plr, gameStats, usePlayer)
	if not usePlayer then
		for i in pairs(gameStats) do
			local player = game.Players:GetPlayerByUserId(i)
			if not player then return end
			if player:FindFirstChild("CourtObject") then
				local court = player.CourtObject.Value
				local currentStats = self.MatchStatuses[court]["playerStats"][player.UserId]
				for j, stat in pairs(gameStats[i]) do
					currentStats[j] += stat
				end
				self.MatchStatuses[court]["playerStats"][player.UserId] = currentStats
			end
		end
	else
		if plr:FindFirstChild("CourtObject") then
			local court = plr.CourtObject.Value
			local currentStats = self.MatchStatuses[court]["playerStats"][plr.UserId]
			for j, stat in pairs(gameStats[plr.UserId]) do
				currentStats[j] += stat
			end
			self.MatchStatuses[court]["playerStats"][plr.UserId] = currentStats
		end
	end
end

-- [[ SCORING ]] --

function MatchService:updateCourtVisualScore(court, gameScore, setScore, matchScore, dontUpdateUI, tiebreakScore)
	local ScoreService = Framework.GetService("ScoreService")
	local succ, err = pcall(function()
		if self.MatchStatuses[court] == nil then return end
		local sets = self.MatchStatuses[court]["sets"]
		if dontUpdateUI then return end

		local playersSideOne = findPlayerWithSide(self.MatchStatuses[court]["playerScoreIndexes"], 1)
		local playersSideTwo = findPlayerWithSide(self.MatchStatuses[court]["playerScoreIndexes"], 2)
		local playerServing = findPlayersSide(self.MatchStatuses[court]["playerScoreIndexes"], self.MatchStatuses[court]["playerServing"][1])
		local playerOneA = type(playersSideOne) == "table" and (game.Players:GetPlayerByUserId(playersSideOne[1]) or BotModule:GetPlayerByUserId(playersSideOne[1])) or (game.Players:GetPlayerByUserId(playersSideOne) or BotModule:GetPlayerByUserId(playersSideOne))
		local playerOneB = type(playersSideOne) == "table" and (game.Players:GetPlayerByUserId(playersSideOne[2]) or BotModule:GetPlayerByUserId(playersSideOne[2])) or nil
		local playerTwoA = type(playersSideTwo) == "table" and (game.Players:GetPlayerByUserId(playersSideTwo[1]) or BotModule:GetPlayerByUserId(playersSideTwo[1])) or (game.Players:GetPlayerByUserId(playersSideTwo) or BotModule:GetPlayerByUserId(playersSideTwo))
		local playerTwoB = type(playersSideTwo) == "table" and (game.Players:GetPlayerByUserId(playersSideTwo[2]) or BotModule:GetPlayerByUserId(playersSideTwo[2])) or nil
		local displayScore = tiebreakScore or gameScore

		local status = ""
		local function getTeamName(side)
			local playersSide = findPlayerWithSide(self.MatchStatuses[court]["playerScoreIndexes"], side)
			local pA = type(playersSide) == "table" and (game.Players:GetPlayerByUserId(playersSide[1]) or BotModule:GetPlayerByUserId(playersSide[1])) or (game.Players:GetPlayerByUserId(playersSide) or BotModule:GetPlayerByUserId(playersSide))
			local pB = type(playersSide) == "table" and (game.Players:GetPlayerByUserId(playersSide[2]) or BotModule:GetPlayerByUserId(playersSide[2])) or nil
			return pA.Name..(pB and ", "..pB.Name or "")
		end
		task.spawn(function()
			status = ScoreService:CalculateMatchStatus(court, gameScore, setScore, matchScore, tiebreakScore, playerServing, getTeamName)
		end)

		if playerOneA then self.Signal.updateUIScore:Fire(playerOneA, court, playerOneA, playerTwoA, setScore, displayScore, matchScore, sets, playerServing, playerOneB, playerTwoB, status) end
		if playerOneB then self.Signal.updateUIScore:Fire(playerOneB, court, playerOneA, playerTwoA, setScore, displayScore, matchScore, sets, playerServing, playerOneB, playerTwoB, status) end
		if playerTwoA then self.Signal.updateUIScore:Fire(playerTwoA, court, playerOneA, playerTwoA, setScore, displayScore, matchScore, sets, playerServing, playerOneB, playerTwoB, status) end
		if playerTwoB then self.Signal.updateUIScore:Fire(playerTwoB, court, playerOneA, playerTwoA, setScore, displayScore, matchScore, sets, playerServing, playerOneB, playerTwoB, status) end

		local scoreUI = court:FindFirstChild("Board", true)
		if not scoreUI then return end
		scoreUI.Enabled = true
		for _, previousmatchscore in pairs(scoreUI.Scores:GetChildren()) do
			if string.find(previousmatchscore.Name, "matchScore") and previousmatchscore.Name ~= "1_matchScore" then
				previousmatchscore:Destroy()
			elseif previousmatchscore.Name == "1_matchScore" then
				previousmatchscore.Visible = false
			end
		end
		scoreUI.Main.Plr1.Text = playerOneA.Name..(playerOneB and ", "..playerOneB.Name or "")
		scoreUI.Main.Plr2.Text = playerTwoA.Name..(playerTwoB and ", "..playerTwoB.Name or "")
		scoreUI.Scores["9_setScore"].Plr1.Text = setScore[1]
		scoreUI.Scores["9_setScore"].Plr2.Text = setScore[2]
		if sets then
			for i, set in pairs(sets) do
				local matchClone = scoreUI:FindFirstChild("1_matchScore", true):Clone()
				matchClone.Parent = scoreUI.Scores
				matchClone.Name = i.."_matchScore"
				matchClone.Visible = true
				matchClone.Plr1.Text = set[1]
				matchClone.Plr2.Text = set[2]
				if set[1] > set[2] then
					matchClone.Plr1.TextColor3 = Color3.fromRGB(255, 142, 12)
				elseif set[2] > set[1] then
					matchClone.Plr2.TextColor3 = Color3.fromRGB(255, 142, 12)
				end
			end
		end
		scoreUI.Scores.gameScore.Plr1.Text = tostring(displayScore[1])
		scoreUI.Scores.gameScore.Plr2.Text = tostring(displayScore[2])
		scoreUI.Main.Index1ServeIndicator.Visible = (playerServing == 1)
		scoreUI.Main.Index2ServeIndicator.Visible = (playerServing == 2)
	end)
	if not succ then warn("[MatchService] updateCourtVisualScore failed: ", err) end
end

function MatchService:handleScore(court, winnerID)
	if self.MatchStatuses[court] == nil or self.MatchStatuses[court]["breakMatch"] == true then return end
	local ScoreService = Framework.GetService("ScoreService")
	local BallTrackerService = Framework.GetService("BallTrackerService")
	local QuestsService = Framework.GetService("QuestsService")
	local SoundService = Framework.GetService("SoundService")
	local DataService = Framework.GetService("DataService")

	local adScoring = court:GetAttribute("AdScoring")
	local pointWinner = game.Players:GetPlayerByUserId(winnerID) or BotModule:GetPlayerByUserId(winnerID)
	local playerSide = findPlayersSide(self.MatchStatuses[court]["playerScoreIndexes"], pointWinner)
	local playerOneA, playerTwoA, playerOneB, playerTwoB = self:getPlayerNamesInCourt(court)

	for player, side in pairs(self.MatchStatuses[court]["playerScoreIndexes"]) do
		local plrInstance = game.Players:GetPlayerByUserId(player)
		if plrInstance then
			local settings = DataService:GetInfo(plrInstance, "Settings")
			local pointCheerSFX = settings and settings[12]
			if pointCheerSFX and pointCheerSFX.State == true and plrInstance.Character then
				SoundService:PlayPlayer(plrInstance, 7755719721, 0, plrInstance.Character.Head, 3, nil, 0.5)
			end
		end

		local addition = {
			[player] = {
				TotalPointsWon = 0, TotalPointsLost = 0,
				TotalSinglesMatchesWon = 0, TotalDoublesMatchesWon = 0,
				TotalSinglesMatchesLost = 0, TotalDoublesMatchesLost = 0,
				TotalHits = 0, TotalServes = 0, HitOut = 0, DiveOuts = 0,
				Aces = 0, Winners = 0, FirstServes = 0, SecondServes = 0, DoubleFaults = 0,
			}
		}

		if side == playerSide then
			addition[player]["TotalPointsWon"] += 1
			if plrInstance then
				QuestsService:UpdateQuest(plrInstance, "Main", 1, 1)
				QuestsService:UpdateQuest(plrInstance, "Main", 2, 1)
				QuestsService:UpdateQuest(plrInstance, "Main", 3, 1)
			end
		else
			addition[player]["TotalPointsLost"] += 1
		end

		if plrInstance then
			BallTrackerService:UpdatePlayerStats(plrInstance, addition, true)
		end
	end

	local status = self.MatchStatuses[court]
	local newGameScore, gameWonBySide = ScoreService:AwardPoint(status["gameScore"], playerSide, adScoring)
	status["gameScore"] = newGameScore

	if gameWonBySide then
		status["gameScore"] = { 0, 0 }
		status["setScore"][gameWonBySide] = status["setScore"][gameWonBySide] + 1
		local winnerNames = (gameWonBySide == 1) and (playerOneA..(playerOneB ~= "" and ", " or "")..playerOneB) or (playerTwoA..(playerTwoB ~= "" and ", " or "")..playerTwoB)
		self:SendMatchNotification(court, "GAME, "..winnerNames.."!", 3)

		-- Switch Ends on odd games
		local totalGamesInSet = status["setScore"][1] + status["setScore"][2]
		if totalGamesInSet % 2 ~= 0 then
			self:switchCourtEnds(court)
		end

		self:switchPlayersServing(court)
	end

	self:updateCourtVisualScore(court, status["gameScore"], status["setScore"], status["matchScore"])
end

-- [[ TELEPORTS ]] --

function MatchService:teleportPlayerToPosition(player, position)
	if typeof(player) == "number" then
		player = game.Players:GetPlayerByUserId(player) or BotModule:GetPlayerByUserId(player)
	end
	if player and player.Character then
		local targetCFrame = position:GetPivot()

		local hrpOffset = getStandOffset(player.Character)
		targetCFrame = CFrame.new(targetCFrame.Position + Vector3.new(0, (position.Size.Y / 2) + hrpOffset, 0)) * targetCFrame.Rotation

		if typeof(player) == "table" then
			player:SetStandardPosition(targetCFrame.Position)
		end

		teleportAnchored(player.Character, targetCFrame)

		anchorCharacter(player.Character, false)
		
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:MoveTo(targetCFrame.Position)
		end

		player:SetAttribute("TimeSinceLastTeleported", workspace:GetServerTimeNow())
		player:SetAttribute("CorrectOrientation", targetCFrame.Rotation)
	end
end

function MatchService:teleportSpectatorsOutOfCourt(court)
	local CourtRegistry = Framework.GetService("CourtRegistry")
	local plrs = CourtRegistry:GetSpectators(court)
	local specZonePart = court:FindFirstChild("SpectatorZone")
	if not specZonePart then return end

	for _, plr in pairs(plrs) do
		if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			and not findindictkey(self.MatchStatuses[court]["playerScoreIndexes"], plr.UserId) then
			self:teleportPlayerToPosition(plr, court:FindFirstChild("QueueSideOne1"))
		end
	end
end

function MatchService:teleportPlayersToCorrectPositions(court)
	if not self.MatchStatuses[court] then return end
	local status = self.MatchStatuses[court]
	local courtType = court:GetAttribute("CourtType")
	local side

	if status["tiebreakScore"] then
		local totalTiebreakPoints = status["tiebreakScore"][1] + status["tiebreakScore"][2]
		side = totalTiebreakPoints % 2 == 0 and "Deuce" or "Ad"
	else
		local totalPoints = (status["gameScore"][1] ~= "ADV." and status["gameScore"][2] ~= "ADV.")
			and status["gameScore"][1] + status["gameScore"][2] or 0

		if (status["gameScore"][1] == 40 and status["gameScore"][2] == 0)
			or (status["gameScore"][1] == 0 and status["gameScore"][2] == 40)
			or (status["gameScore"][1] == 40 and status["gameScore"][2] == 30)
			or (status["gameScore"][1] == 30 and status["gameScore"][2] == 40)
			or (status["gameScore"][1] == "ADV." or status["gameScore"][2] == "ADV.") then
			side = "Ad"
		elseif totalPoints % 2 == 0
			or (status["gameScore"][1] == 40 and status["gameScore"][2] == 15)
			or (status["gameScore"][1] == 15 and status["gameScore"][2] == 40) then
			side = "Deuce"
		else
			side = "Ad"
		end
	end

	local suffix = (side == "Deuce") and "One" or "Two"
	local altSuffix = (suffix == "One") and "Two" or "One"

	local server1 = status["playerServing"][1]
	local serverSideNum = status["playerSides"][server1.UserId]
	local receiverSideNum = (serverSideNum == 1) and 2 or 1

	local servePrefix = "Side" .. (serverSideNum == 1 and "One" or "Two") .. "Spawn"
	local recvPrefix = "Side" .. (receiverSideNum == 1 and "One" or "Two") .. "Spawn"

	if courtType == "Singles" then
		local receiver1 = status["playerReceiving"][1]
		self:teleportPlayerToPosition(server1, court:FindFirstChild(servePrefix..suffix))
		self:teleportPlayerToPosition(receiver1, court:FindFirstChild(recvPrefix..suffix))
	elseif courtType == "Doubles" then
		local server2 = status["playerServing"][2]
		local receiver1 = status["playerReceiving"][1]
		local receiver2 = status["playerReceiving"][2]

		self:teleportPlayerToPosition(server1, court:FindFirstChild(servePrefix..suffix))
		self:teleportPlayerToPosition(server2, court:FindFirstChild(servePrefix..altSuffix))
		local sideMap = status["receiverSideMap"]
		self:teleportPlayerToPosition(receiver1, court:FindFirstChild(recvPrefix..sideMap[receiver1]))
		self:teleportPlayerToPosition(receiver2, court:FindFirstChild(recvPrefix..sideMap[receiver2]))
	end
end

-- [[ PLAYER STATE / QUEUE ]] --

function MatchService:changePlayersInMatchStatus(court, status)
	local CourtRegistry = Framework.GetService("CourtRegistry")
	local QueueService = Framework.GetService("QueueService")

	for player in pairs(self.MatchStatuses[court]["playersInMatch"]) do
		player:SetAttribute("InMatch", status)
		CourtRegistry:SetBarrierRole(player, false, status, court)

		if status == false then
			self.Signal.disableMatchUI:Fire(player)
			QueueService:RemovePlayerFromQueue(player)
			player:SetAttribute("CanHitBall", true)
			if player.Parent == game.Players then
				local courtObj = player:FindFirstChild("CourtObject")
				if courtObj then courtObj:Destroy() end
			elseif typeof(player) == "table" then
				player:Destroy()
			end
			for _, otherCourt in pairs(workspace.Courts:GetChildren()) do
				self.Signal.DeActivateCourtBarriers:Fire(player, {}, otherCourt)
				self.Signal.ChangeServeBarrierStatus:Fire(player, otherCourt, false)
				self.Signal.SwitchAnim:Fire(player, "Normal", otherCourt)
			end
		else
			if player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					for _, overheadgui in pairs(hrp:GetChildren()) do
						if overheadgui.Name == "OverheadGui" then overheadgui:Destroy() end
					end
				end
			end
		end
	end
end

-- [[ MATCH CLEANUP ]] --

function MatchService:cleanupMatch(court, matchWinner)
	local CourtRegistry = Framework.GetService("CourtRegistry")
	local QueueService = Framework.GetService("QueueService")

	if self.MatchStatuses[court] then
		for userId in pairs(self.MatchStatuses[court]["playerScoreIndexes"]) do
			local plr = game.Players:GetPlayerByUserId(userId) or BotModule:GetPlayerByUserId(userId)
			if plr then
				plr:SetAttribute("CanHitBall", true)
			end
		end
	end

	court:SetAttribute("LastTimeMatchEnded", os.clock())
	court:SetAttribute("HasBot", false)
	court:SetAttribute("Active", false)
	CourtRegistry:SetCourtBarriersCollidable(court, false)
	CourtRegistry:SetCourtServeBarriersCollidable(court)

	local scoreUI = court:FindFirstChild("Board", true)
	if scoreUI then scoreUI.Enabled = false end
	local display = court:FindFirstChild("Display", true)
	if display then display.Enabled = true end

	self:changePlayersInMatchStatus(court, false)
	QueueService:ClearQueueBoards(court)

	if self.MatchStatuses[court] then
		for _, conn in pairs(self.MatchStatuses[court]["playerLeaveConnections"]) do
			conn:Disconnect()
		end
		if self.MatchStatuses[court]["sideOneZone"] then self.MatchStatuses[court]["sideOneZone"]:destroy() end
		if self.MatchStatuses[court]["sideTwoZone"] then self.MatchStatuses[court]["sideTwoZone"]:destroy() end
	end

	self.Signal.DeActivateCourtBarriers:FireAll({}, court)

	local succ, err = pcall(function()
		if self.Maids[court] then
			self.Maids[court]:DoCleaning()
			self.Maids[court]:Destroy()
		end
	end)
	if not succ then warn("[MatchService] Maid cleanup failed for "..court.Name..": ", err) end

	self.MatchStatuses[court] = nil
	self:updateCourtVisualScore(court, {0, 0}, {0, 0}, {0, 0}, true)
	self:StartCourtLoop(court)

	if court:GetAttribute("WinnersStayOn") == true and matchWinner then
		local winners = (type(matchWinner) == "table") and matchWinner or { matchWinner }
		local queueSpots = { court:FindFirstChild("QueueSideOne1", true), court:FindFirstChild("QueueSideOne2", true) }
		for i, winnerId in ipairs(winners) do
			local plr = game.Players:GetPlayerByUserId(winnerId)
			local spot = queueSpots[i]
			if plr and spot then
				QueueService:QueuePlayerAtQueue(spot, plr, court, true)
			end
		end
	end

	task.delay(0.25, function()
		if QueueService:AmountOfPlayersQueuedToCourt(court) == 0 and court:GetAttribute("Active") ~= true then
			if court:GetAttribute("OGCourtType") then court:SetAttribute("CourtType", court:GetAttribute("OGCourtType")) end
			if court:GetAttribute("OGBestTo") then court:SetAttribute("BestTo", court:GetAttribute("OGBestTo")) end
			if court:GetAttribute("OGMatchBestTo") then court:SetAttribute("MatchBestTo", court:GetAttribute("OGMatchBestTo")) end
		end
		CourtRegistry:handleCourtProperties(court)
		CourtRegistry:setupDisplay(court)
		QueueService:handleCourtQueue(court, true)
		CourtRegistry.Signal.RefreshCourtProperties:FireAll(court.Name)
	end)
end

-- [[ MIGRATING MATCHES ]] --

local function checkAllPlayersAreValid(playersDict, court)
	local plrs, plrsNeeded = {}, court:GetAttribute("CourtType") == "Singles" and 2 or 4
	for playerId, playerSide in playersDict do
		local plr = game.Players:GetPlayerByUserId(tonumber(playerId))
		if plr then
			plr:SetAttribute("HitPlayAuto", true)
			if plr:GetAttribute("InMatch") ~= true then
				plrs[plr] = playerSide
			end
		end
	end
	if countEntries(plrs) == plrsNeeded then return plrs end
end

local function tellPlayersMatchResuming(matches)
	for courtName, matchInfo in pairs(matches) do
		if workspace.Courts:FindFirstChild(courtName) then
			for playerId in matchInfo.playersInMatch do
				local plr = game.Players:GetPlayerByUserId(tonumber(playerId))
				if plr and plr:GetAttribute("InMatch") ~= true then
					plr:SetAttribute("WaitingForMatch", true)
				end
			end
		end
	end
end

function MatchService:HandleMigratingMatches(matches)
	tellPlayersMatchResuming(matches)
	task.delay(10, function()
		for courtName, matchInfo in pairs(matches) do
			local court = workspace.Courts:FindFirstChild(courtName)
			if court then
				local plrs = checkAllPlayersAreValid(matchInfo.playersInMatch, court)
				if plrs then
					self:HandleMatch(court, plrs, matchInfo)
				end
			end
		end
	end)
end

function MatchService:HandlePlayerJoining(player)
	task.spawn(function()
		task.wait(3)
		for _, court in pairs(workspace.Courts:GetChildren()) do
			if court:GetAttribute("Active") == true and self.MatchStatuses[court] then
				self.Signal.ActivateCourtBarriers:FireAll(self.MatchStatuses[court]["playerScoreIndexes"], court)
			end
		end
	end)
end

-- [[ COURT QUEUE -> MATCH LOOP ]] --

function MatchService:StartCourtLoop(court)
	local QueueService = Framework.GetService("QueueService")

	task.defer(function()
		local peopleNeeded = court:GetAttribute("CourtType") == "Singles" and 2 or 4
		repeat
			task.wait(10)
			peopleNeeded = court:GetAttribute("CourtType") == "Singles" and 2 or 4
		until QueueService:queueFilled(court, peopleNeeded) and self.MatchStatuses[court] == nil

		task.spawn(function()
			self:HandleMatch(court, QueueService:getQueuedPlayersBySide(court))
		end)
	end)

	task.defer(function()
		while task.wait(1) do
			if court:GetAttribute("LastTimeMatchStarted") and os.clock() - court:GetAttribute("LastTimeMatchStarted") < 5 then
				return
			end
			if court:GetAttribute("LastTimeMatchEnded") and os.clock() - court:GetAttribute("LastTimeMatchEnded") < 3 then
				return
			end

			local isCourtActive = true
			if self.MatchStatuses[court] then
				for _, player in pairs(self.MatchStatuses[court]["playersInMatch"]) do
					if not player or player:GetAttribute("InMatch") == false then
						isCourtActive = false
					end
				end
			end

			if not isCourtActive then
				self:cleanupMatch(court)
			end
		end
	end)
end

-- [[ HandleMatch ]] --

function MatchService:HandleMatch(court, players, prematchInfo)
	if players == nil or court:GetAttribute("Active") == true then return end

	local CourtRegistry = Framework.GetService("CourtRegistry")
	local QueueService = Framework.GetService("QueueService")
	local ScoreService = Framework.GetService("ScoreService")

	self.Maids[court] = Maid.new()
	local courtMaid = self.Maids[court]

	self.MatchThreads[court] = courtMaid:GiveTask(task.spawn(function()
		court:SetAttribute("Active", true)
		court:SetAttribute("LastTimeMatchStarted", os.clock())
		CourtRegistry:SetCourtBarriersCollidable(court, true)

		local BallService = Framework.GetService("BallService")
		local BallTrackerService = Framework.GetService("BallTrackerService")
		local embedService = Framework.GetService("EmbedService")
		local PlayerService = Framework.GetService("PlayerService")
		local TutorialService = Framework.GetService("TutorialService")

		local displayGui = court:FindFirstChild("Display", true)
		if displayGui then displayGui.Enabled = false end

		local plrTable = {}
		for index in pairs(players) do table.insert(plrTable, index) end

		local newPlayers = {}
		newPlayers[plrTable[1].UserId] = players[plrTable[1]]
		if plrTable[3] ~= nil then newPlayers[plrTable[3].UserId] = players[plrTable[3]] end
		newPlayers[plrTable[2].UserId] = players[plrTable[2]]
		if plrTable[4] ~= nil then newPlayers[plrTable[4].UserId] = players[plrTable[4]] end

		local playerServing1 = findPlayerWithSide(newPlayers, 1)
		local playerReceiving1 = findPlayerWithSide(newPlayers, 2)
		local playerServing, playerReceiving = {}, {}

		local function resolveList(sideVal, into)
			if typeof(sideVal) == "number" then
				local p = game.Players:GetPlayerByUserId(sideVal) or BotModule:GetPlayerByUserId(sideVal)
				if p then table.insert(into, p) end
			else
				for _, v in pairs(sideVal) do
					local p = game.Players:GetPlayerByUserId(v) or BotModule:GetPlayerByUserId(v)
					if p then table.insert(into, p) end
				end
			end
		end
		resolveList(playerServing1, playerServing)
		resolveList(playerReceiving1, playerReceiving)

		self.MatchStatuses[court] = {
			startTime = prematchInfo and prematchInfo.startTime or workspace:GetServerTimeNow();
			playersInMatchUserIds = {};
			playersInMatch = deepCopy(players);
			playerStats = prematchInfo and prematchInfo.playerStats or {};
			playerLeaveConnections = {};
			gameScore = prematchInfo and prematchInfo.gameScore or {0, 0};
			setScore = prematchInfo and prematchInfo.setScore or {0, 0};
			matchScore = prematchInfo and prematchInfo.matchScore or {0, 0};
			setsPlayed = prematchInfo and prematchInfo.setsPlayed or 0;
			sets = prematchInfo and prematchInfo.sets or {};
			playerScoreIndexes = prematchInfo and prematchInfo.playerScoreIndexes or deepCopy(newPlayers);
			playerServing = playerServing;
			playerReceiving = playerReceiving;
			playerSides = prematchInfo and prematchInfo.sides or deepCopy(newPlayers);
			serveStatus = 1;
			pointStatus = 0;
			sideOneZone = Zone.new(court:FindFirstChild("SideOneZone"));
			sideTwoZone = Zone.new(court:FindFirstChild("SideTwoZone"));
			matchThread = nil;
			team1Players = table.clone(playerServing);
			team2Players = table.clone(playerReceiving);
			team1ServeIndex = 1;
			team2ServeIndex = 2;
		}
		
		self.MatchStatuses[court]["receiverSideMap"] = {}
		self.MatchStatuses[court]["receiverSideMap"][self.MatchStatuses[court]["playerReceiving"][1]] = "One"
		if self.MatchStatuses[court]["playerReceiving"][2] then
			self.MatchStatuses[court]["receiverSideMap"][self.MatchStatuses[court]["playerReceiving"][2]] = "Two"
		end
		
		local matchWinner
		local TeamOneId, TeamTwoId = generateRandomID(), generateRandomID()

		for player in pairs(self.MatchStatuses[court]["playersInMatch"]) do
			player:SetAttribute("HitPlayAuto", true)
			if typeof(player) == "table" then
				court:SetAttribute("HasBot", true)
				self.MatchStatuses[court]["HasBot"] = true
			end
			local side = self.MatchStatuses[court]["playerSides"][player.UserId]
			local teamId = (side == 1) and TeamOneId or (side == 2) and TeamTwoId or nil
			if teamId then
				player:SetAttribute("TeamID", teamId)
			end

			self.MatchStatuses[court]["playersInMatchUserIds"][player.UserId] = players[player]
			if QueueService:IsPlayerQueued(player) then
				QueueService:unfreezePlayerAtQueue(player, QueueService:GetPlayerQueue(player), true)
			end

			local courtObjectValue = Instance.new("ObjectValue")
			courtObjectValue.Parent = (typeof(player) == "Instance") and player or game.Players[player.Name]
			courtObjectValue.Name = "CourtObject"
			courtObjectValue.Value = court

			self.MatchStatuses[court]["playerStats"][player.UserId] = {
				TotalPointsWon = 0, TotalPointsLost = 0,
				TotalSinglesMatchesWon = 0, TotalDoublesMatchesWon = 0,
				TotalSinglesMatchesLost = 0, TotalDoublesMatchesLost = 0,
				TotalHits = 0, TotalServes = 0, HitOut = 0, DiveOuts = 0,
				Aces = 0, Winners = 0, FirstServes = 0, SecondServes = 0, DoubleFaults = 0,
			}
		end

		QueueService:ClearQueueBoards(court)
		if court:GetAttribute("WinnersStayOn") == true then
			self:LockKOTCCourt(court)
		end

		self:changePlayersInMatchStatus(court, true)
		QueueService:refreshQueueList()
		self.Signal.ActivateCourtBarriers:FireAll(self.MatchStatuses[court]["playerScoreIndexes"], court)

		local breakMatch = false
		task.spawn(function()
			for plr in pairs(self.MatchStatuses[court]["playersInMatch"]) do
				BallService:deletePlayerBall(plr)
				self.Signal.MatchCutscene:Fire(plr, court, self.MatchStatuses[court]["playersInMatch"], true)

				if typeof(plr) == "Instance" and plr:IsA("Player") and plr.Character then
					anchorCharacter(plr.Character, true)
				end

				if plr.CharacterRemoving then
					if plr.Character then
						plr.Character:PivotTo(plr:GetAttribute("LastQueuePosition")) 
					end
					self.MatchStatuses[court]["playerLeaveConnections"][plr] = plr.CharacterRemoving:Connect(function()
						if typeof(plr) ~= "table" then
							BotModule:RemoveAllBotsForPlayer(plr.UserId)
						end
						QueueService:CheckAllQueuesForOccupancy()

						local playerSide = findPlayersSide(self.MatchStatuses[court]["playerScoreIndexes"], plr)
						if playerSide == 1 then
							matchWinner = findPlayerWithSide(self.MatchStatuses[court]["playerScoreIndexes"], 2)
						elseif playerSide == 2 then
							matchWinner = findPlayerWithSide(self.MatchStatuses[court]["playerScoreIndexes"], 1)
						end
						breakMatch = true
						self.MatchStatuses[court]["breakMatch"] = true
					end)
				end
			end
		end)

		local plrs = self.MatchStatuses[court]["playersInMatch"]
		
		local function resetCutscene(m)
			for plr in pairs(m) do
				if typeof(plr) == "Instance" and plr:IsA("Player") and plr.Character then
					anchorCharacter(plr.Character, false)
				end
			end
		end

		local function enablePlayerControls(m)
			for plr in pairs(m) do
				if typeof(plr) == "Instance" and plr:IsA("Player") then
					if plr.Character then
						local humanoid = plr.Character:FindFirstChild("Humanoid")
						if humanoid then
							humanoid.WalkSpeed = 16
						end
					end
					self.Signal.MatchCutscene:Fire(plr, court, self.MatchStatuses[court]["playersInMatch"], false)
				end
			end
		end

		self:teleportSpectatorsOutOfCourt(court)
		self:updateCourtVisualScore(court, self.MatchStatuses[court]["gameScore"], self.MatchStatuses[court]["setScore"], self.MatchStatuses[court]["matchScore"])
		local sideOneWalkDone, sideTwoWalkDone = true, true
		if not prematchInfo then
			local succ, err = pcall(function()
				local cameraPositions = getCameraPositions(court)
				for i, positionInfo in pairs(cameraPositions) do
					if breakMatch then task.delay(5, function() resetCutscene(plrs) enablePlayerControls(plrs) end) return end
					for plr in pairs(self.MatchStatuses[court]["playersInMatch"]) do
						self.Signal.TweenCamera:Fire(plr, positionInfo["Cframe"], positionInfo["Duration"])
					end
					if i == 1 then
						movePlayers(self.MatchStatuses[court]["playersInMatch"], court.WalkPosition1)
					elseif i == 3 then
						task.wait(1)
						local count = 0
						for plr in pairs(self.MatchStatuses[court]["playersInMatch"]) do
							if typeof(plr) ~= "table" then
								count += 1
								local racketBag = PlayerService:GetModel("RacketBag", plr.Character)
								PlayerService:Unweld("RacketBag", plr.Character)
								racketBag.Parent = workspace
								racketBag.Name = plr.Name.."_RACKETBAG"
								anchorModel(racketBag, false)
								local benchPart = getNearestBench(plr.Character.HumanoidRootPart.Position)
								racketBag:PivotTo(getRandomPositionInPart(benchPart, count, countEntries(self.MatchStatuses[court]["playersInMatch"])))
							end
						end
					elseif i == 4 then
						local sideOnePlayers, sideTwoPlayers = {}, {}
						for plr, x in pairs(self.MatchStatuses[court]["playersInMatch"]) do
							if findPlayersSide(self.MatchStatuses[court]["playerScoreIndexes"], plr.UserId) == 1 then
								sideOnePlayers[plr] = x
							else
								sideTwoPlayers[plr] = x
							end
						end

						sideOneWalkDone, sideTwoWalkDone = false, false

						local netPart = court:FindFirstChild("Net", true)
							or game:GetService("CollectionService"):GetTagged("Net")[1]
						if not netPart then
							warn("[MatchService] Could not resolve Net part for court "..court.Name.." — walk-side facing may be wrong.")
						end

						movePlayers(sideOnePlayers, court.WalkSide1, court, countEntries(self.MatchStatuses[court]["playersInMatch"]) / 2, netPart, function() sideOneWalkDone = true end)
						movePlayers(sideTwoPlayers, court.WalkSide2, court, countEntries(self.MatchStatuses[court]["playersInMatch"]) / 2, netPart, function() sideTwoWalkDone = true end)
						for plr in pairs(sideOnePlayers) do
							self.Signal.TweenCamera:Fire(plr, cameraPositions[4]["Cframe"], cameraPositions[4]["Duration"])
						end
						for plr in pairs(sideTwoPlayers) do
							self.Signal.TweenCamera:Fire(plr, cameraPositions[5]["Cframe"], cameraPositions[5]["Duration"])
						end
						break
					end
					task.wait(positionInfo["WaitTime"] + positionInfo["Duration"])
				end
			end)
			if not succ then warn("[MatchService] cutscene failed: ", err) end
		end

		local s0 = os.clock()
		repeat task.wait() until (sideOneWalkDone and sideTwoWalkDone) or os.clock() - s0 > 8 or breakMatch
		if breakMatch then
			resetCutscene(plrs)
			enablePlayerControls(plrs) 
			self:cleanupMatch(court, matchWinner)
			return
		end
		if not self.MatchStatuses[court] then return end
		resetCutscene(plrs)
		
		--self:teleportPlayersToCorrectPositions(court)
		--enablePlayerControls(plrs)
		local controlsGranted = false

		local function runServe(servingSide, singlesOrDoublesExtra)
			CourtRegistry:SetCourtServeBarriersCollidable(court)
			court:SetAttribute("BallDespawnTime", -1)

			local activeServer = self.MatchStatuses[court]["playerServing"][1]
			self.Signal.ChangeServeBarrierStatus:Fire(activeServer, court, true)
			CourtRegistry:SetBarrierRole(activeServer, true, true, court)

			local partner = self.MatchStatuses[court]["playerServing"][2]
			if partner then
				self.Signal.ChangeServeBarrierStatus:Fire(partner, court, false)
				CourtRegistry:SetBarrierRole(partner, false, true, court)
			end
			for _, receiver in ipairs(self.MatchStatuses[court]["playerReceiving"]) do
				self.Signal.ChangeServeBarrierStatus:Fire(receiver, court, false)
				CourtRegistry:SetBarrierRole(receiver, false, true, court)
			end

			self.Signal.SwitchAnim:Fire(self.MatchStatuses[court]["playerServing"][1], "Spike", court)
			for _, receiver in ipairs(self.MatchStatuses[court]["playerReceiving"]) do
				self.Signal.SwitchAnim:Fire(receiver, "Normal", court)
			end

			self:teleportPlayersToCorrectPositions(court)

			if not controlsGranted then
				controlsGranted = true
				enablePlayerControls(plrs)
			end

			self:destroyAllBalls(court)
			self:redetermineSides(court)
			self:HighlightZonesForPlayers(court, self.MatchStatuses[court]["playerSides"], self.MatchStatuses[court]["playerServing"][1], servingSide)
			TutorialService:HelpfulNotification(self.MatchStatuses[court]["playerServing"][1], "The ball is about to be served for you! Hold and charge spacebar, then release to spike it when its high!")
			self:ChangePlayersCanHitBallStatus(court, true)

			local s2 = os.clock()
			repeat task.wait() until os.clock() - s2 > 5 or breakMatch
			if breakMatch then return true end
			self:ChangePlayersCanHitBallStatus(court, true)

			local bestPingPlayer = getBestPingPlayer(self.MatchStatuses[court]["playersInMatch"]) or self.MatchStatuses[court]["playerServing"][1]
			BallService:NewBall(self.MatchStatuses[court]["playerServing"][1], court:GetAttribute("CourtSurface"), true)
			BallTrackerService:TrackBall(bestPingPlayer, court, self.MatchStatuses[court]["playerSides"], false, servingSide, self.MatchStatuses[court]["playerServing"][1])
			repeat task.wait() until self.MatchStatuses[court]["pointStatus"] ~= 0 or matchWinner ~= nil or breakMatch
			if breakMatch then return true end
			return false
		end

		local function runTiebreak()
			local playerOneA, playerTwoA, playerOneB, playerTwoB = self:getPlayerNamesInCourt(court)
			self:SendMatchNotification(court, "TIEBREAKER!", 3)

			local tiebreakScore = {0, 0}
			local tiebreakTarget = court:GetAttribute("Tiebreaker")

			local tiebreakFirstServer = deepCopy(self.MatchStatuses[court]["playerServing"])
			local tiebreakFirstReceiver = deepCopy(self.MatchStatuses[court]["playerReceiving"])

			while ScoreService:CheckTiebreakWon(tiebreakScore, tiebreakTarget) == nil and not breakMatch do
				local s3 = os.clock()
				repeat task.wait() until os.clock() - s3 > 3 or breakMatch
				if breakMatch then return end

				local totalTiebreakPoints = tiebreakScore[1] + tiebreakScore[2]
				self:updateCourtVisualScore(court, self.MatchStatuses[court]["gameScore"], self.MatchStatuses[court]["setScore"], self.MatchStatuses[court]["matchScore"], nil, tiebreakScore)
				self:redetermineSides(court)

				local side = totalTiebreakPoints % 2 == 0 and "Deuce" or "Ad"
				self.MatchStatuses[court]["Side"] = side
				self:teleportPlayersToCorrectPositions(court)

				local didBreak = runServe(side, nil)
				if didBreak then return end
				if not self.MatchStatuses[court] then return end

				local pointWinner = self.MatchStatuses[court]["pointStatus"]
				local winSide = findPlayersSide(self.MatchStatuses[court]["playerScoreIndexes"], pointWinner) == 1 and 1 or 2
				tiebreakScore = ScoreService:AwardTiebreakPoint(tiebreakScore, winSide)
				self.MatchStatuses[court]["tiebreakScore"] = tiebreakScore
				self.MatchStatuses[court]["pointStatus"] = 0
				self:updateCourtVisualScore(court, self.MatchStatuses[court]["gameScore"], self.MatchStatuses[court]["setScore"], self.MatchStatuses[court]["matchScore"], nil, tiebreakScore)
				self:redetermineSides(court)

				local newTotal = tiebreakScore[1] + tiebreakScore[2]

				if newTotal % 2 == 1 then
					self:switchPlayersServing(court)
				end

				if newTotal > 0 and newTotal % 6 == 0 then
					self:switchCourtEnds(court)
				end
			end
			if breakMatch then return end

			self.MatchStatuses[court]["tiebreakScore"] = nil
			local setScore = self.MatchStatuses[court]["setScore"]
			local winner = ScoreService:CheckTiebreakWon(tiebreakScore, tiebreakTarget)

			if winner == 1 then
				self.MatchStatuses[court]["matchScore"][1] += 1
				setScore[1] += 1
				self:SendMatchNotification(court, "GAME AND SET, "..playerOneA..(playerOneB ~= "" and ", " or "")..playerOneB.."!", 3)
			else
				self.MatchStatuses[court]["matchScore"][2] += 1
				setScore[2] += 1
				self:SendMatchNotification(court, "GAME AND SET, "..playerTwoA..(playerTwoB ~= "" and ", " or "")..playerTwoB.."!", 3)
			end

			self.MatchStatuses[court]["sets"][self.MatchStatuses[court]["setsPlayed"] + 1] = {setScore[1], setScore[2], tiebreakScore[1], tiebreakScore[2]}
			self.MatchStatuses[court]["setsPlayed"] += 1
			self.MatchStatuses[court]["setScore"] = {0, 0}
			self.MatchStatuses[court]["gameScore"] = {0, 0}

			self:switchCourtEnds(court)

			self.MatchStatuses[court]["playerServing"] = deepCopy(tiebreakFirstReceiver)
			self.MatchStatuses[court]["playerReceiving"] = deepCopy(tiebreakFirstServer)
		end

		local function set()
			repeat
				local s1 = os.clock()
				repeat task.wait() until os.clock() - s1 > 3 or breakMatch
				if breakMatch then return end
				self:updateCourtVisualScore(court, self.MatchStatuses[court]["gameScore"], self.MatchStatuses[court]["setScore"], self.MatchStatuses[court]["matchScore"])

				local totalPoints = (self.MatchStatuses[court]["gameScore"][1] ~= "ADV." and self.MatchStatuses[court]["gameScore"][2] ~= "ADV.")
					and self.MatchStatuses[court]["gameScore"][1] + self.MatchStatuses[court]["gameScore"][2] or 0
				local side
				if (self.MatchStatuses[court]["gameScore"][1] == 40 and self.MatchStatuses[court]["gameScore"][2] == 0)
					or (self.MatchStatuses[court]["gameScore"][1] == 0 and self.MatchStatuses[court]["gameScore"][2] == 40)
					or (self.MatchStatuses[court]["gameScore"][1] == 40 and self.MatchStatuses[court]["gameScore"][2] == 30)
					or (self.MatchStatuses[court]["gameScore"][1] == 30 and self.MatchStatuses[court]["gameScore"][2] == 40)
					or (self.MatchStatuses[court]["gameScore"][1] == "ADV." or self.MatchStatuses[court]["gameScore"][2] == "ADV.") then
					side = "Ad"
				elseif totalPoints % 2 == 0
					or (self.MatchStatuses[court]["gameScore"][1] == 40 and self.MatchStatuses[court]["gameScore"][2] == 15)
					or (self.MatchStatuses[court]["gameScore"][1] == 15 and self.MatchStatuses[court]["gameScore"][2] == 40) then
					side = "Deuce"
				else
					side = "Ad"
				end

				self.MatchStatuses[court]["Side"] = side
				self:teleportPlayersToCorrectPositions(court)

				local didBreak = runServe(side, nil)
				if didBreak then return end
				if not self.MatchStatuses[court] then return end

				if not matchWinner then
					self:handleScore(court, self.MatchStatuses[court]["pointStatus"])
				end
				self.MatchStatuses[court]["pointStatus"] = 0

				local setScore = self.MatchStatuses[court]["setScore"]
				local winBy2 = court:GetAttribute("WinBy2")
				local bestTo = court:GetAttribute("BestTo")
				local tiebreakThreshold = court:GetAttribute("Tiebreaker")

				local setState = ScoreService:EvaluateSetState(setScore, bestTo, winBy2, tiebreakThreshold)
				if setState then
					if setState.enterTiebreak then
						runTiebreak()
						return
					elseif setState.setWonBySide then
						local w = setState.setWonBySide
						self.MatchStatuses[court]["sets"][self.MatchStatuses[court]["setsPlayed"] + 1] = {setScore[1], setScore[2]}
						self.MatchStatuses[court]["setsPlayed"] += 1
						self.MatchStatuses[court]["setScore"] = {0, 0}
						self.MatchStatuses[court]["matchScore"][w] += 1
						self.MatchStatuses[court]["gameScore"] = {0, 0}

						local pOA, pTA, pOB, pTB = self:getPlayerNamesInCourt(court)
						local winnerNames = (w == 1) and (pOA..(pOB ~= "" and ", " or "")..pOB) or (pTA..(pTB ~= "" and ", " or "")..pTB)
						self:SendMatchNotification(court, "GAME AND SET, "..winnerNames.."!", 3)
						return
					end
				end

			until breakMatch
		end

		local matchEnded = false
		local bestToMatch = court:GetAttribute("MatchBestTo")
		local setsNeededToWin = math.ceil(bestToMatch / 2)

		repeat
			task.wait()
			if breakMatch then matchEnded = true break end

			set()

			local wonSide = ScoreService:EvaluateMatchState(self.MatchStatuses[court]["matchScore"], setsNeededToWin)
			if wonSide then
				matchEnded = true
				matchWinner = findPlayerWithSide(self.MatchStatuses[court]["playerScoreIndexes"], wonSide)
				local pOA, pTA, pOB, pTB = self:getPlayerNamesInCourt(court)
				local winnerNames = (wonSide == 1) and (pOA..(pOB ~= "" and ", " or "")..pOB) or (pTA..(pTB ~= "" and ", " or "")..pTB)
				self:SendMatchNotification(court, "GAME, SET, MATCH, "..winnerNames.."!", 3)
			end
		until matchEnded or matchWinner ~= nil or breakMatch

		local playersSideOne = findPlayerWithSide(self.MatchStatuses[court]["playerScoreIndexes"], 1)
		local playersSideTwo = findPlayerWithSide(self.MatchStatuses[court]["playerScoreIndexes"], 2)
		local playerOneA = type(playersSideOne) == "table" and (game.Players:GetPlayerByUserId(playersSideOne[1]) or BotModule:GetPlayerByUserId(playersSideOne[1])) or (game.Players:GetPlayerByUserId(playersSideOne) or BotModule:GetPlayerByUserId(playersSideOne))
		local playerOneB = type(playersSideOne) == "table" and (game.Players:GetPlayerByUserId(playersSideOne[2]) or BotModule:GetPlayerByUserId(playersSideOne[2])) or nil
		local playerTwoA = type(playersSideTwo) == "table" and (game.Players:GetPlayerByUserId(playersSideTwo[1]) or BotModule:GetPlayerByUserId(playersSideTwo[1])) or (game.Players:GetPlayerByUserId(playersSideTwo) or BotModule:GetPlayerByUserId(playersSideTwo))
		local playerTwoB = type(playersSideTwo) == "table" and (game.Players:GetPlayerByUserId(playersSideTwo[2]) or BotModule:GetPlayerByUserId(playersSideTwo[2])) or nil

		local function isPlayerInWinner(player, winner)
			if not player then return false end
			if type(winner) == "table" then
				return player == game.Players:GetPlayerByUserId(winner[1]) or player == game.Players:GetPlayerByUserId(winner[2])
			end
			return player == game.Players:GetPlayerByUserId(winner)
		end

		local function getMatchStats(player, isWinner)
			if isWinner then
				pcall(function()
					local QuestsService = Framework.GetService("QuestsService")
					QuestsService:UpdateQuest(player, "Main", 4, 1)
					QuestsService:UpdateQuest(player, "Main", 5, 1)
					QuestsService:UpdateQuest(player, "Main", 6, 1)
				end)
			end
			local longEnough = workspace:GetServerTimeNow() - self.MatchStatuses[court]["startTime"] > 120
			local noBot = court:GetAttribute("HasBot") == false
			local isSingles = court:GetAttribute("CourtType") == "Singles"
			local isDoubles = court:GetAttribute("CourtType") == "Doubles"
			return {
				[player.UserId] = {
					TotalPointsWon = 0, TotalPointsLost = 0,
					TotalSinglesMatchesWon = (noBot and longEnough and isWinner and isSingles) and 1 or 0,
					TotalDoublesMatchesWon = (noBot and longEnough and isWinner and isDoubles) and 1 or 0,
					TotalSinglesMatchesLost = (noBot and longEnough and not isWinner and isSingles) and 1 or 0,
					TotalDoublesMatchesLost = (noBot and longEnough and not isWinner and isDoubles) and 1 or 0,
					TotalHits = 0, TotalServes = 0, HitOut = 0, DiveOuts = 0,
					Aces = 0, Winners = 0, FirstServes = 0, SecondServes = 0, DoubleFaults = 0,
				}
			}
		end

		local BallTrackerServiceRef = Framework.GetService("BallTrackerService")
		if playerOneA then BallTrackerServiceRef:UpdatePlayerStats(playerOneA, getMatchStats(playerOneA, isPlayerInWinner(playerOneA, matchWinner)), true) end
		if playerOneB then BallTrackerServiceRef:UpdatePlayerStats(playerOneB, getMatchStats(playerOneB, isPlayerInWinner(playerOneB, matchWinner)), true) end
		if playerTwoA then BallTrackerServiceRef:UpdatePlayerStats(playerTwoA, getMatchStats(playerTwoA, isPlayerInWinner(playerTwoA, matchWinner)), true) end
		if playerTwoB then BallTrackerServiceRef:UpdatePlayerStats(playerTwoB, getMatchStats(playerTwoB, isPlayerInWinner(playerTwoB, matchWinner)), true) end

		local dataService = Framework.GetService("DataService")
		local giveRewards = workspace:GetServerTimeNow() - self.MatchStatuses[court]["startTime"] > 120

		for _, p in pairs({playerOneA, playerOneB, playerTwoA, playerTwoB}) do
			if p then
				local won = isPlayerInWinner(p, matchWinner)
				if giveRewards then
					dataService:MatchRewardBasedOnGames(p, findPlayersSide(self.MatchStatuses[court]["playerScoreIndexes"], p), self.MatchStatuses[court]["sets"], won, self.MatchStatuses[court]["playerStats"][p.UserId], court:GetAttribute("HasBot"))
				end
			end
		end

		local function getPlayerNameAsync(userId)
			local bot = BotModule:GetPlayerByUserId(userId)
			if bot then return bot.Name end
			local success, playerName = pcall(function()
				return game.Players:GetNameFromUserIdAsync(userId)
			end)
			return success and playerName or "Unknown Player"
		end

		local playerOneAName = type(playersSideOne) == "table" and getPlayerNameAsync(playersSideOne[1]) or getPlayerNameAsync(playersSideOne)
		local playerOneBName = type(playersSideOne) == "table" and playersSideOne[2] and getPlayerNameAsync(playersSideOne[2]) or "Unknown Player"
		local playerTwoAName = type(playersSideTwo) == "table" and getPlayerNameAsync(playersSideTwo[1]) or getPlayerNameAsync(playersSideTwo)
		local playerTwoBName = type(playersSideTwo) == "table" and playersSideTwo[2] and getPlayerNameAsync(playersSideTwo[2]) or "Unknown Player"

		self.Signal.endMatchUI:FireAll(playerOneAName, playerTwoAName, matchWinner, self.MatchStatuses[court]["playerScoreIndexes"], self.MatchStatuses[court]["sets"], playerOneBName, playerTwoBName, self.MatchStatuses[court]["playerStats"])

		embedService:RecordMatch(playerOneAName, playerTwoAName, matchWinner, self.MatchStatuses[court]["playerScoreIndexes"], self.MatchStatuses[court]["sets"], playerOneBName, playerTwoBName, self.MatchStatuses[court]["playerStats"], workspace:GetServerTimeNow() - self.MatchStatuses[court]["startTime"], self.MatchStatuses[court]["setScore"], court, breakMatch)

		self:cleanupMatch(court, matchWinner)
	end))
end

return MatchService