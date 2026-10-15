local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Marketplace = game:GetService("MarketplaceService")
local Workspace = game:GetService("Workspace")
local Maid = require(game.ReplicatedStorage.Shared.Library.Maid)
local Framework = require(game:GetService("ReplicatedStorage").Packets.Framework.Packages.Server)
local Zone = require(ReplicatedStorage.Shared.Modules.FastZone)
local Signal = require(game.ReplicatedStorage.FastCastRedux)
local Debris = game:GetService("Debris")
local HitboxV4 = require(game.ReplicatedStorage.Shared.RaycastHitboxV4)
local Init = require(game.ReplicatedStorage.Shared.Library.Init)
local highlights = {}
local BotModule = require(game.ServerScriptService.Server.Services.CourtService.BotPlayer)

local Service = {
	Name = "BallTrackerService",
	Signal = {
		TrackBall = "RemoteEvent",
		SecondServe = "RemoteEvent",
		PointWinner = "RemoteEvent",
		UpdateStats = "RemoteEvent",
		AdjustRallyStatsEventOne = "RemoteEvent",
		AdjustRallyStatsEventTwo = "RemoteEvent",
		UpdatedPlayerStats = "RemoteEvent",
	},

	trackDebounces = {},
	courtMaids = {},
	balls = {},
}

function findBallWithHighestIndex(playerName)
	local highestIndex = -1
	local highestBall = nil

	for _, ball in pairs(workspace.Balls:GetChildren()) do
		local ballName = ball.Name
		if string.sub(ballName, 1, #playerName) == playerName then
			if ball:GetAttribute("PracticeBall") ~= true then
				local indexPart = string.sub(ballName, #playerName + 1)
				local index = tonumber(indexPart)
				if index and index > highestIndex then
					highestIndex = index
					highestBall = ball
				end
			end
		end
	end
	for _, ball in pairs(workspace.EventBalls:GetChildren()) do
		local ballName = ball.Name
		if string.sub(ballName, 1, #playerName) == playerName then
			if ball:GetAttribute("PracticeBall") ~= true then
				local indexPart = string.sub(ballName, #playerName + 1)
				local index = tonumber(indexPart)
				if index and index > highestIndex then
					highestIndex = index
					highestBall = ball
				end
			end
		end
	end

	return highestBall
end

local function findPlayerWithSide(dict, key)
	local plrs = {}
	local plr

	for i, v in pairs(dict) do
		if v == key then
			plr = i
			table.insert(plrs, i)
		end
	end

	if #plrs == 1 then
		return plr
	elseif #plrs > 1 then
		return plrs
	end
end

local function findPlayersSide(dict, key)
	if not key then return end
	for i, v in pairs(dict) do
		if (tonumber(i)) == (typeof(key) ~= "table" and (key:IsA("Folder") and key:GetAttribute("UserId") or key.UserId) or key.UserId) then
			return v
		end
	end
end

local function findindictkey(dict, key)
	for _, p in pairs(dict) do
		if tonumber(p) == key then
			return true
		end
	end
end

function Service:UpdatePlayerStats(plr, gameStats, usePlayer)
	local dataService = Framework.GetService("DataService")
	local MatchService = Framework.GetService("MatchService")
	local success, err = pcall(function()
		MatchService:IncrementPlayerStats(plr, gameStats)
		if not usePlayer then
			for i, playerID in pairs(gameStats) do
				local player = game.Players:GetPlayerByUserId(i)
				local currentStats = dataService:GetInfo(player, "PlayerStats")
				self.Signal.UpdatedPlayerStats:Fire(player, playerID)
				for j, stat in pairs(playerID) do
					currentStats[j] += stat
				end
				dataService:SaveThingy(player, "PlayerStats", currentStats)
			end
		else
			local currentStats = dataService:GetInfo(plr, "PlayerStats")
			self.Signal.UpdatedPlayerStats:Fire(plr, gameStats[plr.UserId])
			for j, stat in pairs(gameStats[plr.UserId]) do
				currentStats[j] += stat
			end
			dataService:SaveThingy(plr, "PlayerStats", currentStats)
		end
	end)
end

function Service:InitializeCourtMaids()
	for i, court in pairs(workspace.Courts:GetChildren()) do
		self.courtMaids[court] = Maid.new()
	end
end

local filter = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

for _, descendant in ipairs(workspace:GetDescendants()) do
	if descendant:IsA("BasePart") then
		if descendant.Name == "Ground" then
			table.insert(filter, descendant)
		end
	end
end
rayParams.FilterDescendantsInstances = filter

function Service:ballMark(ballPos, court)
	if not ballPos then return end
	local p = ballPos
	local SoundService = Framework.GetService("SoundService")
	local randomID = math.random(0, 10000000)
	local ballMark = game.ReplicatedStorage.Shared.BallMark:Clone()
	ballMark.Parent = workspace
	ballMark.Position = p
	ballMark.CanCollide = false
	ballMark.Name = "BallMark_" .. tostring(randomID)
	--SoundService:Play(124542977612993, 1.5, ballMark)
	Debris:AddItem(ballMark, 10)

	local rayDirectionDown = vector.create(0, -500, 0)
	local rayResultDown = workspace:Raycast(p, rayDirectionDown, rayParams)

	if rayResultDown then
		ballMark.Position = rayResultDown.Position
	else
		local rayDirectionUp = vector.create(0, 500, 0)
		local rayResultUp = workspace:Raycast(p, rayDirectionUp, rayParams)

		if rayResultUp then
			ballMark.Position = rayResultUp.Position
		end
	end

	for _, particle in pairs(ballMark:GetChildren()) do
		task.spawn(function()
			if particle:IsA("ParticleEmitter") then
				particle.Enabled = true
				task.wait(ballMark:GetAttribute("Lifetime") or 0.3)
				particle.Enabled = false
			end
		end)
	end

	return ballMark
end

function Service:AdjustRallyStats(ball, stat, playerWhoHit, LastHitTime)
	local startTime = os.clock()
	while self.balls[ball] == nil and os.clock() - startTime < 1 do
		task.wait()
	end

	if self.balls[ball] == nil then return end

	if stat == "RallyHits" then
		if self.balls[ball]["numBounces"] == 0 and self.balls[ball]["RallyHits"] == 1 and workspace:GetServerTimeNow() - LastHitTime > 0.5 and playerWhoHit ~= self.balls[ball]["playerServing"] then
			self.balls[ball]["hitServeBeforeBounce"] = true
		end
		if ball then
			self.balls[ball]["RallyHits"] += 1
		end
		self.balls[ball]["numBounces"] = 0

		local hitUserId = playerWhoHit:IsA("Folder") and playerWhoHit:GetAttribute("UserId") or playerWhoHit.UserId

		self.balls[ball]["playerStats"][hitUserId]["TotalHits"] = (self.balls[ball]["playerStats"][hitUserId]["TotalHits"] or 0) + 1
		self.balls[ball]["Court"]:SetAttribute("RallyHits", self.balls[ball]["RallyHits"])
	end
end

function Service:GetActiveBallIdForCourt(court)
	for ballId, info in pairs(self.balls) do
		if info["Court"] == court then
			return ballId
		end
	end
	return nil
end

function Service:TrackBallMatch(PlayerWithBestPing, Court, playerSides, secondServe, servingSide, PlayerServing)
	local EffectsService = Framework.GetService("EffectsService")
	local PlayerService = Framework.GetService("PlayerService")
	local MatchService = Framework.GetService("MatchService")
	local playersBallTrackerMaid = self.courtMaids[Court]
	playersBallTrackerMaid:DoCleaning()

	playersBallTrackerMaid:GiveTask(task.spawn(function()
		local playerToUse = PlayerServing.Parent == game.Players and PlayerServing or PlayerServing.PlayerWhoSpawned

		local Ball = findBallWithHighestIndex(playerToUse.Name)

		local startTime = os.clock()
		while (Ball == nil or _G.ballSignals[Ball.Name] == nil) and os.clock() - startTime < 2 do
			task.wait()
			Ball = findBallWithHighestIndex(playerToUse.Name)
		end

		if Ball == nil or _G.ballSignals[Ball.Name] == nil then
			warn("NO BALL", Ball, _G.ballSignals)
			return
		end

		if self.balls[Ball.Name] ~= nil then warn("TABLE ALREADY ", Ball.Name, self.balls) return end

		local hasServed = false
		local pointActive = true
		local finalizedWinner
		local inBoundaryNameSideOne
		local inBoundaryNameSideTwo
		local lastZoneEntered
		local playerServingSide = findPlayersSide(playerSides, PlayerServing)
		local ballInfoTable = nil
		local serveBox = "Side" .. (playerServingSide == 1 and "Two" or "One") .. servingSide .. "ServeBoxZONE"
		local serveBoxName = "Side" .. (playerServingSide == 1 and "Two" or "One") .. servingSide .. "ServeBoxZONE"

		self.balls[Ball.Name] = {
			["RallyHits"] = 0,
			["numBounces"] = 0,
			["playerServing"] = PlayerServing,
			["lastBallBouncePosition"] = nil,
			["lastBallDebounce"] = os.clock(),
			["playerStats"] = {},
			["doubleHit"] = false,
			["Court"] = Court,
		}
		self.balls[Ball.Name]["fullBoundaryNameSideOne"] = Zone.fromRegion(Court:FindFirstChild("SideOneZone").CFrame, Court:FindFirstChild("SideOneZone").Size)
		self.balls[Ball.Name]["fullBoundaryNameSideTwo"] = Zone.fromRegion(Court:FindFirstChild("SideTwoZone").CFrame, Court:FindFirstChild("SideTwoZone").Size)
		ballInfoTable = self.balls[Ball.Name]

		for i, plr in pairs(game.Players:GetChildren()) do
			self.balls[Ball.Name]["playerStats"][plr:IsA("Folder") and plr:GetAttribute("UserId") or plr.UserId] = {
				["TotalPointsWon"] = 0,
				["TotalPointsLost"] = 0,
				["TotalSinglesMatchesWon"] = 0,
				["TotalDoublesMatchesWon"] = 0,
				["TotalSinglesMatchesLost"] = 0,
				["TotalDoublesMatchesLost"] = 0,
				["TotalHits"] = 0,
				["TotalServes"] = 0,
				["HitOut"] = 0,
				["DiveOuts"] = 0,
				["Aces"] = 0,
				["Winners"] = 0,
				["FirstServes"] = 0,
				["SecondServes"] = 0,
				["DoubleFaults"] = 0,
			}
		end

		if not self.balls[Ball.Name]["playerStats"][PlayerServing.UserId] then
			self.balls[Ball.Name]["playerStats"][PlayerServing.UserId] = {
				["TotalPointsWon"] = 0,
				["TotalPointsLost"] = 0,
				["TotalSinglesMatchesWon"] = 0,
				["TotalDoublesMatchesWon"] = 0,
				["TotalSinglesMatchesLost"] = 0,
				["TotalDoublesMatchesLost"] = 0,
				["TotalHits"] = 0,
				["TotalServes"] = 0,
				["HitOut"] = 0,
				["DiveOuts"] = 0,
				["Aces"] = 0,
				["Winners"] = 0,
				["FirstServes"] = 0,
				["SecondServes"] = 0,
				["DoubleFaults"] = 0,
			}
		end

		if not secondServe then
			self.balls[Ball.Name]["playerStats"][PlayerServing.UserId]["TotalServes"] = 1
		end

		local winner

		if Court:GetAttribute("CourtType") == "Singles" then
			inBoundaryNameSideOne = "SinglesSideOneZone"
			inBoundaryNameSideTwo = "SinglesSideTwoZone"
		elseif Court:GetAttribute("CourtType") == "Doubles" then
			inBoundaryNameSideOne = "DoublesSideOneZone"
			inBoundaryNameSideTwo = "DoublesSideTwoZone"
		end

		inBoundaryNameSideOne = Zone.new(Court:FindFirstChild(inBoundaryNameSideOne))
		inBoundaryNameSideTwo = Zone.new(Court:FindFirstChild(inBoundaryNameSideTwo))

		local CourtZone = Zone.new(Court:FindFirstChild("CourtZone"))
		local SideOneDeuceServeBoxZONE = Zone.new(Court:FindFirstChild("SideOneDeuceServeBox"))
		local SideOneAdServeBoxZONE = Zone.new(Court:FindFirstChild("SideOneAdServeBox"))
		local SideTwoDeuceServeBoxZONE = Zone.new(Court:FindFirstChild("SideTwoDeuceServeBox"))
		local SideTwoAdServeBoxZONE = Zone.new(Court:FindFirstChild("SideTwoAdServeBox"))

		local lastHitClock = os.clock()
		local deadBallClock
		local playerWhoLastHit
		local lastHit

		_G.ballSignals[Ball.Name]["lastHitChanged"]:Connect(function(newValue)
			local isDoubleHitWindow = os.clock() - lastHitClock <= 0.3 and (Court:GetAttribute("RallyHits") or 0) > 0 and lastHit ~= nil
			lastHitClock = os.clock()

			if not playerWhoLastHit then
				playerWhoLastHit = newValue
			elseif newValue == playerWhoLastHit and isDoubleHitWindow then
				if self.balls[Ball.Name] then
					self.balls[Ball.Name]["doubleHit"] = playerWhoLastHit
					ballInfoTable = self.balls[Ball.Name]
				end
			end

			playerWhoLastHit = newValue
			lastHit = game.Players:FindFirstChild(newValue)

			if newValue == PlayerServing.Name and not hasServed then
				hasServed = true

				local MatchServiceRef = Framework.GetService("MatchService")
				local CourtRegistryRef = Framework.GetService("CourtRegistry")
				MatchServiceRef.Signal.ChangeServeBarrierStatus:Fire(PlayerServing, Court, false)
				CourtRegistryRef:SetBarrierRole(PlayerServing, false, true, Court)
			end
		end)

		local barrierHit = false
		local netHit = false
		local hitOut = false
		local doubleBounce = false
		local ballPos = Ball.Position
		local hitDone = false
		local netHitDone = false
		local hasBounced = false
		local netTouchedOnServe = false

		if _G.ballSignals[Ball.Name]["hitGround"].Connect and _G.ballSignals[Ball.Name]["hitNet"].Connect and _G.ballSignals[Ball.Name]["hitBarrier"].Connect then
			_G.ballSignals[Ball.Name]["hitGround"]:Connect(function(hit, position)
				task.spawn(function()
					local success, err = pcall(function()
						if hitDone == false and pointActive and position then
							local tempLastHit = lastHit
							if hit.Name == "Ground" then
								hitDone = true
								deadBallClock = os.clock()
							end

							ballPos = position
							local tableToUse = self.balls[Ball.Name] or ballInfoTable
							if not tableToUse then return warn("TABLE NIL FOR BALL INFO") end
							local pservebox = serveBox
							if serveBox == "SideOneDeuceServeBoxZONE" then
								serveBox = SideOneDeuceServeBoxZONE
							elseif serveBox == "SideOneAdServeBoxZONE" then
								serveBox = SideOneAdServeBoxZONE
							elseif serveBox == "SideTwoDeuceServeBoxZONE" then
								serveBox = SideTwoDeuceServeBoxZONE
							elseif serveBox == "SideTwoAdServeBoxZONE" then
								serveBox = SideTwoAdServeBoxZONE
							end

							if self.balls[Ball.Name]["fullBoundaryNameSideOne"]:findPoint(position) then
								lastZoneEntered = 1
							end

							if self.balls[Ball.Name]["fullBoundaryNameSideTwo"]:findPoint(position) then
								lastZoneEntered = 2
							end

							local isInSideOne
							local isInSideTwo

							if tableToUse then
								if tableToUse["lastBallBouncePosition"] ~= nil then
									local succ, err2 = pcall(function()
										isInSideOne = inBoundaryNameSideOne:findPoint(tableToUse["lastBallBouncePosition"])
										isInSideTwo = inBoundaryNameSideTwo:findPoint(tableToUse["lastBallBouncePosition"])
									end)
								end
							end

							local lastZoneBounced

							if isInSideOne then
								lastZoneBounced = 1
							elseif isInSideTwo then
								lastZoneBounced = 2
							end

							local function updatePlayerStats(playerIds, statKey, increment)
								if typeof(playerIds) == "table" then
									for _, playerId in ipairs(playerIds) do
										tableToUse["playerStats"][tonumber(playerId)][statKey] = (tableToUse["playerStats"][tonumber(playerId)][statKey] or 0) + increment
									end
								else
									tableToUse["playerStats"][tonumber(playerIds)][statKey] = (tableToUse["playerStats"][tonumber(playerIds)][statKey] or 0) + increment
								end
							end

							if not hasServed or tableToUse["RallyHits"] < 1 then
								hitOut = true
								if not secondServe then
									self:SecondServe(PlayerServing, Court, playerSides, servingSide, PlayerServing)
									updatePlayerStats(PlayerServing.UserId, "SecondServes", 1)
									tableToUse["numBounces"] = 0
									pointActive = false
								else
									if not winner then
										local opponentSide = findPlayersSide(playerSides, PlayerServing) == 1 and 2 or 1
										winner = findPlayerWithSide(playerSides, opponentSide)
									end
								end
							else
								tableToUse["numBounces"] += 1
								if tableToUse["numBounces"] >= 2 then
									local timeSinceLastBounce = os.clock() - tableToUse["lastBallDebounce"]
									if timeSinceLastBounce > 0.3 then
										local ballMark = self:ballMark(position, Court, Ball)
										if not winner then
											local lastHitSide = findPlayersSide(playerSides, tempLastHit)
											local isWithinZoneBool = (lastHitSide == 1) and self.balls[Ball.Name]["fullBoundaryNameSideTwo"]:findPoint(position) or self.balls[Ball.Name]["fullBoundaryNameSideOne"]:findPoint(position)
											local opponentSide = lastHitSide == 1 and 2 or 1
											if not isWithinZoneBool then
												hitOut = true
												doubleBounce = true
												Court:SetAttribute("BallDespawnTime", 0)
												winner = findPlayerWithSide(playerSides, opponentSide)
												if typeof(winner) ~= "table" then
													if tempLastHit == game.Players:GetPlayerByUserId(winner) then
														updatePlayerStats(findPlayerWithSide(playerSides, opponentSide), "Winners", 1)
														if tableToUse["RallyHits"] <= 1 then
															updatePlayerStats(tempLastHit:IsA("Folder") and lastHit:GetAttribute("UserId") or lastHit.UserId, "Aces", 1)
														end
													end
												else
													if tempLastHit == game.Players:GetPlayerByUserId(winner[1]) then
														updatePlayerStats(findPlayerWithSide(playerSides, opponentSide), "Winners", 1)
														if tableToUse["RallyHits"] <= 1 then
															updatePlayerStats(tempLastHit:IsA("Folder") and lastHit:GetAttribute("UserId") or lastHit.UserId, "Aces", 1)
														end
													end
													if tempLastHit == game.Players:GetPlayerByUserId(winner[2]) then
														updatePlayerStats(findPlayerWithSide(playerSides, opponentSide), "Winners", 1)
														if tableToUse["RallyHits"] <= 1 then
															updatePlayerStats(tempLastHit:IsA("Folder") and lastHit:GetAttribute("UserId") or lastHit.UserId, "Aces", 1)
														end
													end
												end
											else
												winner = findPlayerWithSide(playerSides, lastHitSide)
												if typeof(winner) ~= "table" then
													if tempLastHit == game.Players:GetPlayerByUserId(winner) then
														updatePlayerStats(findPlayerWithSide(playerSides, lastHitSide), "Winners", 1)
														if tableToUse["RallyHits"] <= 1 then
															updatePlayerStats(tempLastHit:IsA("Folder") and lastHit:GetAttribute("UserId") or lastHit.UserId, "Aces", 1)
														end
													end
												else
													if tempLastHit == game.Players:GetPlayerByUserId(winner[1]) then
														updatePlayerStats(findPlayerWithSide(playerSides, lastHitSide), "Winners", 1)
														if tableToUse["RallyHits"] <= 1 then
															updatePlayerStats(tempLastHit:IsA("Folder") and lastHit:GetAttribute("UserId") or lastHit.UserId, "Aces", 1)
														end
													end
													if tempLastHit == game.Players:GetPlayerByUserId(winner[2]) then
														updatePlayerStats(findPlayerWithSide(playerSides, lastHitSide), "Winners", 1)
														if tableToUse["RallyHits"] <= 1 then
															updatePlayerStats(tempLastHit:IsA("Folder") and lastHit:GetAttribute("UserId") or lastHit.UserId, "Aces", 1)
														end
													end
												end
											end
										end
									end
								else
									local timeSinceLastBounce = os.clock() - tableToUse["lastBallDebounce"]
									if not winner and hasServed and timeSinceLastBounce > 0.3 then
										tableToUse["lastBallBouncePosition"] = ballPos
										tableToUse["lastBallDebounce"] = os.clock()
										local ballMark = self:ballMark(position, Court, Ball)
										local lastHitSide = findPlayersSide(playerSides, tempLastHit)
										local isWithinZoneBool
										local prevHasBounced = hasBounced
										hasBounced = true
										if prevHasBounced == false then
											isWithinZoneBool = serveBox:findPart(ballMark)
										else
											isWithinZoneBool = (lastHitSide == 1 and inBoundaryNameSideTwo or inBoundaryNameSideOne):findPart(ballMark)
										end

										-- [[ LET DETECTION ON SERVE ]]
										if netTouchedOnServe then
											netTouchedOnServe = false
											Ball:SetAttribute("NetTouchedOnServe", false)
											if isWithinZoneBool then
												local MatchServiceRef = Framework.GetService("MatchService")
												MatchServiceRef:SendMatchNotification(Court, "LET!", 2)
												self:Let(PlayerServing, Court, playerSides, servingSide, secondServe, PlayerServing)
												pointActive = false
												return
											end
										end

										if not isWithinZoneBool then
											local opponentSide = lastHitSide == 1 and 2 or 1
											if tableToUse["RallyHits"] > 1 then
												updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "HitOut", 1)
												local playerInst = game.Players:GetPlayerByUserId(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId) or BotModule:GetPlayerByUserId(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId)
												if playerInst and playerInst:GetAttribute("Diving") == true then
													updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "DiveOuts", 1)
												end
											end
											hitOut = true
											winner = findPlayerWithSide(playerSides, opponentSide)
											if typeof(winner) ~= "table" then
												if tempLastHit == game.Players:GetNameFromUserIdAsync(winner) then
													updatePlayerStats(findPlayerWithSide(playerSides, opponentSide), "Winners", 1)
													if tableToUse["RallyHits"] <= 1 then
														updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "Aces", 1)
													end
												end
											else
												if tempLastHit == game.Players:GetNameFromUserIdAsync(winner[1]) then
													updatePlayerStats(findPlayerWithSide(playerSides, opponentSide), "Winners", 1)
													if tableToUse["RallyHits"] <= 1 then
														updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "Aces", 1)
													end
												end
												if tempLastHit == game.Players:GetNameFromUserIdAsync(winner[2]) then
													updatePlayerStats(findPlayerWithSide(playerSides, opponentSide), "Winners", 1)
													if tableToUse["RallyHits"] <= 1 then
														updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "Aces", 1)
													end
												end
											end
										end
									end
								end
							end

							self.balls[Ball.Name] = tableToUse
							ballInfoTable = tableToUse
							hitDone = false
						end
					end)
					if not success then
						warn("Error in hitGround signal: " .. err)
						hitDone = false
						if not deadBallClock then
							deadBallClock = os.clock()
						end
					end
				end)
			end)

			_G.ballSignals[Ball.Name]["hitBarrier"]:Connect(function(hit, position)
				task.spawn(function()
					local success, err = pcall(function()
						if hitDone == false and pointActive and hit:IsDescendantOf(Court) then
							local tempLastHit = lastHit
							if hit.Name == "Barrier" then
								hitDone = true
							end

							ballPos = position
							local tableToUse = self.balls[Ball.Name] or ballInfoTable
							if not tableToUse then return warn("TABLE NIL FOR BALL INFO") end
							local pservebox = serveBox
							if serveBox == "SideOneDeuceServeBoxZONE" then
								serveBox = SideOneDeuceServeBoxZONE
							elseif serveBox == "SideOneAdServeBoxZONE" then
								serveBox = SideOneAdServeBoxZONE
							elseif serveBox == "SideTwoDeuceServeBoxZONE" then
								serveBox = SideTwoDeuceServeBoxZONE
							elseif serveBox == "SideTwoAdServeBoxZONE" then
								serveBox = SideTwoAdServeBoxZONE
							end

							if self.balls[Ball.Name]["fullBoundaryNameSideOne"]:findPoint(position) then
								lastZoneEntered = 1
							end

							if self.balls[Ball.Name]["fullBoundaryNameSideTwo"]:findPoint(position) then
								lastZoneEntered = 2
							end

							local isInSideOne
							local isInSideTwo

							if tableToUse then
								if tableToUse["lastBallBouncePosition"] ~= nil then
									local succ, err2 = pcall(function()
										isInSideOne = inBoundaryNameSideOne:findPoint(tableToUse["lastBallBouncePosition"])
										isInSideTwo = inBoundaryNameSideTwo:findPoint(tableToUse["lastBallBouncePosition"])
									end)
								end
							end

							local lastZoneBounced

							if isInSideOne then
								lastZoneBounced = 1
							elseif isInSideTwo then
								lastZoneBounced = 2
							end

							local function updatePlayerStats(playerIds, statKey, increment)
								if typeof(playerIds) == "table" then
									for _, playerId in ipairs(playerIds) do
										tableToUse["playerStats"][tonumber(playerId)][statKey] = (tableToUse["playerStats"][tonumber(playerId)][statKey] or 0) + increment
									end
								else
									tableToUse["playerStats"][tonumber(playerIds)][statKey] = (tableToUse["playerStats"][tonumber(playerIds)][statKey] or 0) + increment
								end
							end

							if hit.Name == "Barrier" and hit:IsDescendantOf(Court) then
								if not winner then
									barrierHit = true
									local lastHitSide = findPlayersSide(playerSides, tempLastHit)
									local lastBounceTime = (os.clock() - tableToUse["lastBallDebounce"])
									local lastHitTime = (os.clock() - lastHitClock)

									if lastHitSide == 1 and lastZoneEntered == 1 then
										winner = findPlayerWithSide(playerSides, 2)
										Court:SetAttribute("BallDespawnTime", 0)
										updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "HitOut", 1)
										local playerInst = game.Players:GetPlayerByUserId(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId) or BotModule:GetPlayerByUserId(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId)
										if playerInst and playerInst:GetAttribute("Diving") == true then
											updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "DiveOuts", 1)
										end
									elseif lastHitSide == 2 and lastZoneEntered == 2 then
										winner = findPlayerWithSide(playerSides, 1)
										Court:SetAttribute("BallDespawnTime", 0)
										updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "HitOut", 1)
										local playerInst = game.Players:GetPlayerByUserId(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId) or BotModule:GetPlayerByUserId(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId)
										if playerInst and playerInst:GetAttribute("Diving") == true then
											updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "DiveOuts", 1)
										end
									elseif lastHitSide == 1 and lastZoneEntered == 2 then
										if lastZoneBounced == 2 and (lastBounceTime < lastHitTime) then
											winner = findPlayerWithSide(playerSides, 1)
											Court:SetAttribute("BallDespawnTime", 0)
											updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "Winners", 1)
											if tableToUse["RallyHits"] <= 1 then
												updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "Aces", 1)
											end
										else
											winner = findPlayerWithSide(playerSides, 2)
											Court:SetAttribute("BallDespawnTime", 0)
											updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "Winners", 2)
											if tableToUse["RallyHits"] <= 1 then
												updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "Aces", 2)
											end
										end
									elseif lastHitSide == 2 and lastZoneEntered == 1 then
										if lastZoneBounced == 1 and (lastBounceTime < lastHitTime) then
											winner = findPlayerWithSide(playerSides, 2)
											Court:SetAttribute("BallDespawnTime", 0)
											updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "Winners", 2)
											if tableToUse["RallyHits"] <= 1 then
												updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "Aces", 2)
											end
										else
											winner = findPlayerWithSide(playerSides, 1)
											Court:SetAttribute("BallDespawnTime", 0)
											updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "Winners", 1)
											if tableToUse["RallyHits"] <= 1 then
												updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "Aces", 1)
											end
										end
									elseif lastZoneEntered == nil then
										if lastHitSide == 1 then
											winner = findPlayerWithSide(playerSides, 2)
											Court:SetAttribute("BallDespawnTime", 0)
											updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "HitOut", 1)
											local playerInst = game.Players:GetPlayerByUserId(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId) or BotModule:GetPlayerByUserId(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId)
											if playerInst and playerInst:GetAttribute("Diving") == true then
												updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "DiveOuts", 1)
											end
										elseif lastHitSide == 2 then
											winner = findPlayerWithSide(playerSides, 1)
											Court:SetAttribute("BallDespawnTime", 0)
											updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "HitOut", 1)
											local playerInst = game.Players:GetPlayerByUserId(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId) or BotModule:GetPlayerByUserId(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId)
											if playerInst and playerInst:GetAttribute("Diving") == true then
												updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "DiveOuts", 1)
											end
										end
									end
								end
							end

							self.balls[Ball.Name] = tableToUse
							ballInfoTable = tableToUse
							hitDone = false
						end
					end)
					if not success then
						warn("Error in hitBarrier signal: " .. err)
						hitDone = false
						if not deadBallClock then
							deadBallClock = os.clock()
						end
					end
				end)
			end)

			_G.ballSignals[Ball.Name]["hitNet"]:Connect(function(hit, position)
				task.spawn(function()
					local success, err = pcall(function()
						local shouldIgnoreNet = true
						local tableToUse = self.balls[Ball.Name] or ballInfoTable
						if not tableToUse then return warn("TABLE NIL FOR BALL INFO") end
						if tableToUse["RallyHits"] < 2 then
							shouldIgnoreNet = false
						end

						-- [[ LET ON SERVE: HOLD DECISION UNTIL BOUNCE ]]
						if hit.Name == "Net" and hit:IsDescendantOf(Court) and hasServed then
							if tableToUse["RallyHits"] <= 1 and not hasBounced then
								netTouchedOnServe = true
								Ball:SetAttribute("NetTouchedOnServe", true)
								return
							end
						end

						if netHitDone == false and pointActive and hit:IsDescendantOf(Court) and shouldIgnoreNet ~= true then
							local tempLastHit = lastHit
							if hit.Name == "Net" then
								netHitDone = true
							end

							ballPos = position
							local pservebox = serveBox
							if serveBox == "SideOneDeuceServeBoxZONE" then
								serveBox = SideOneDeuceServeBoxZONE
							elseif serveBox == "SideOneAdServeBoxZONE" then
								serveBox = SideOneAdServeBoxZONE
							elseif serveBox == "SideTwoDeuceServeBoxZONE" then
								serveBox = SideTwoDeuceServeBoxZONE
							elseif serveBox == "SideTwoAdServeBoxZONE" then
								serveBox = SideTwoAdServeBoxZONE
							end

							if self.balls[Ball.Name]["fullBoundaryNameSideOne"]:findPoint(position) then
								lastZoneEntered = 1
							end

							if self.balls[Ball.Name]["fullBoundaryNameSideTwo"]:findPoint(position) then
								lastZoneEntered = 2
							end

							local isInSideOne
							local isInSideTwo

							if tableToUse then
								if tableToUse["lastBallBouncePosition"] ~= nil then
									local succ, err2 = pcall(function()
										isInSideOne = inBoundaryNameSideOne:findPoint(tableToUse["lastBallBouncePosition"])
										isInSideTwo = inBoundaryNameSideTwo:findPoint(tableToUse["lastBallBouncePosition"])
									end)
								end
							end

							local lastZoneBounced

							if isInSideOne then
								lastZoneBounced = 1
							elseif isInSideTwo then
								lastZoneBounced = 2
							end

							local function updatePlayerStats(playerIds, statKey, increment)
								if typeof(playerIds) == "table" then
									for _, playerId in ipairs(playerIds) do
										tableToUse["playerStats"][tonumber(playerId)][statKey] = (tableToUse["playerStats"][tonumber(playerId)][statKey] or 0) + increment
									end
								else
									tableToUse["playerStats"][tonumber(playerIds)][statKey] = (tableToUse["playerStats"][tonumber(playerIds)][statKey] or 0) + increment
								end
							end

							if hit.Name == "Net" and hit:IsDescendantOf(Court) and hasServed then
								if tableToUse["RallyHits"] < 2 or shouldIgnoreNet == false then
									if not winner then
										netHit = true
										if tempLastHit then
											updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "HitOut", 1)
											local playerInst = game.Players:GetPlayerByUserId(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId) or BotModule:GetPlayerByUserId(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId)
											if playerInst and playerInst:GetAttribute("Diving") == true then
												updatePlayerStats(tempLastHit:IsA("Folder") and tempLastHit:GetAttribute("UserId") or tempLastHit.UserId, "DiveOuts", 1)
											end
										end
										local opponentSide = findPlayersSide(playerSides, tempLastHit) == 1 and 2 or 1
										winner = findPlayerWithSide(playerSides, opponentSide)
									end
								end
							end

							self.balls[Ball.Name] = tableToUse
							ballInfoTable = tableToUse
							netHitDone = false
						end
					end)
					if not success then
						warn("Error in hitNet signal: " .. err)
						netHitDone = false
						if not deadBallClock then
							deadBallClock = os.clock()
						end
					end
				end)
			end)
		end

		playersBallTrackerMaid:GiveTask(task.spawn(function()
			while pointActive do
				task.wait()
				local tempballInfoTable = self.balls[Ball.Name]

				local function updatePlayerStats(playerIds, statKey, increment)
					if typeof(playerIds) == "table" then
						for _, playerId in ipairs(playerIds) do
							self.balls[Ball.Name]["playerStats"][tonumber(playerId)][statKey] = (self.balls[Ball.Name]["playerStats"][tonumber(playerId)][statKey] or 0) + increment
						end
					else
						self.balls[Ball.Name]["playerStats"][tonumber(playerIds)][statKey] = (self.balls[Ball.Name]["playerStats"][tonumber(playerIds)][statKey] or 0) + increment
					end
				end

				if deadBallClock ~= nil then
					if os.clock() - deadBallClock > 10 then
						if not winner then
							deadBallClock = nil
							local ballMark = self:ballMark(ballPos, Court, Ball)
							hitOut = true
							local lastHitSide = findPlayersSide(playerSides, lastHit)
							local isWithinZoneBool = ballMark and ((lastHitSide == 1) and self.balls[Ball.Name]["fullBoundaryNameSideTwo"]:findPart(ballMark) or self.balls[Ball.Name]["fullBoundaryNameSideOne"]:findPart(ballMark)) or false
							local opponentSide = lastHitSide == 1 and 2 or 1
							Court:SetAttribute("BallDespawnTime", 0)

							if not isWithinZoneBool then
								winner = findPlayerWithSide(playerSides, opponentSide)
								if self.balls[Ball.Name]["playerStats"][tonumber(findPlayerWithSide(playerSides, lastHitSide))] ~= nil and self.balls[Ball.Name]["playerStats"][tonumber(findPlayerWithSide(playerSides, lastHitSide))]["TotalHits"] == 0 or 1 then
									updatePlayerStats(findPlayerWithSide(playerSides, opponentSide), "Winners", 1)
									if self.balls[Ball.Name]["RallyHits"] <= 1 then
										updatePlayerStats((lastHit:IsA("Folder") and lastHit:GetAttribute("UserId") or lastHit.UserId), "Aces", 1)
									end
								end
							else
								winner = findPlayerWithSide(playerSides, lastHitSide)
								if self.balls[Ball.Name]["playerStats"][tonumber(findPlayerWithSide(playerSides, lastHitSide))] ~= nil and self.balls[Ball.Name]["playerStats"][tonumber(findPlayerWithSide(playerSides, lastHitSide))]["TotalHits"] == 0 or 1 then
									updatePlayerStats(findPlayerWithSide(playerSides, lastHitSide), "Winners", 1)
									if self.balls[Ball.Name]["RallyHits"] <= 1 then
										updatePlayerStats((lastHit:IsA("Folder") and lastHit:GetAttribute("UserId") or lastHit.UserId), "Aces", 1)
									end
								end
							end
						end
					end
				end

				local bypassSecondServe = false
				if self.balls[Ball.Name] and not winner then
					if (lastHit and lastHit ~= "") and ((hasServed and not hasBounced) or (self.balls[Ball.Name]["doubleHit"] ~= false)) then
						if ((lastHit:IsA("Folder") and lastHit:GetAttribute("UserId") or lastHit.UserId) ~= PlayerServing.UserId) or (self.balls[Ball.Name]["doubleHit"] ~= false) and (Court:GetAttribute("RallyHits") > 1) then
							if self.balls[Ball.Name]["doubleHit"] then
								PlayerService.Signal.ActiveTipNotif:Fire(lastHit, "You cannot double hit the ball on your side!", 5)
							else
								PlayerService.Signal.ActiveTipNotif:Fire(lastHit, "Wait for the serve to bounce before hitting it!", 5)
							end
							ballPos = Ball.Position
							bypassSecondServe = true
							updatePlayerStats((lastHit:IsA("Folder") and lastHit:GetAttribute("UserId") or lastHit.UserId), "HitOut", 1)
							Court:SetAttribute("BallDespawnTime", 0)
							if findPlayersSide(playerSides, lastHit) == 1 then
								winner = findPlayerWithSide(playerSides, 2)
							elseif findPlayersSide(playerSides, lastHit) == 2 then
								winner = findPlayerWithSide(playerSides, 1)
							end
						end
					end
				end

				local finalBallInfoTable
				if winner then
					Court:SetAttribute("RallyHits", 0)
					finalBallInfoTable = Ball and self.balls[Ball.Name] or ballInfoTable
					if finalizedWinner == nil then
						finalizedWinner = winner
					end

					local finalizedServerID = PlayerServing.UserId
					local winnerName = type(finalizedWinner) == "table" and table.concat(finalizedWinner, " & ") or finalizedWinner

					local function getLosers(court, firstWinnerID, secondWinnerID)
						local losers = {}
						for i, plr in pairs(game.Players:GetPlayers()) do
							if plr:FindFirstChild("CourtObject") and plr:FindFirstChild("CourtObject").Value == court then
								local isFirstWinner = (firstWinnerID and plr.UserId == tonumber(firstWinnerID))
								local isSecondWinner = (secondWinnerID and plr.UserId == tonumber(secondWinnerID))
								if not isFirstWinner and not isSecondWinner then
									table.insert(losers, plr)
								end
							end
						end
						return losers
					end

					local winnerUserId = type(finalizedWinner) == "table" and finalizedWinner[1] or finalizedWinner
					local secondwinnerUserId = type(finalizedWinner) == "table" and finalizedWinner[2]
					local losers = getLosers(Court, winnerUserId, secondwinnerUserId)

					task.spawn(function()
						if netHit then
							EffectsService:NetEffect(ballPos, (lastHit or PlayerServing), tonumber(winnerUserId), tonumber(secondwinnerUserId), losers)
						end

						if hitOut then
							EffectsService:OutEffect(ballPos, (lastHit or PlayerServing), tonumber(winnerUserId), tonumber(secondwinnerUserId), losers, doubleBounce)
						end

						if barrierHit then
							EffectsService:BarrierEffect(ballPos, (lastHit or PlayerServing), tonumber(winnerUserId), tonumber(secondwinnerUserId), losers)
						end

						if winnerUserId then
							EffectsService:ShockwaveEffect(PlayerServing, ballPos, tonumber(winnerUserId), tonumber(secondwinnerUserId), losers)
						end
					end)

					if Court:GetAttribute("BallDespawnTime") == -1 then
						Court:SetAttribute("BallDespawnTime", 1.5)
					end

					if finalBallInfoTable["RallyHits"] > 1 or bypassSecondServe then
						if not secondServe then
							finalBallInfoTable["playerStats"][PlayerServing.UserId]["FirstServes"] = (finalBallInfoTable["playerStats"][PlayerServing.UserId]["FirstServes"] or 0) + 1
						end
						self:PointWinner(PlayerServing, winnerUserId, Court)
					elseif finalBallInfoTable["RallyHits"] <= 1 then
						local isSamePlayer = tonumber(finalizedWinner) == tonumber(finalizedServerID)
						local isSameTeam = type(finalizedWinner) == "table" and (findindictkey(finalizedWinner, finalizedServerID))
						if (not isSamePlayer and not isSameTeam) then
							if not secondServe then
								self:SecondServe(PlayerServing, Court, playerSides, servingSide, PlayerServing)
								finalBallInfoTable["playerStats"][PlayerServing.UserId]["SecondServes"] = (finalBallInfoTable["playerStats"][PlayerServing.UserId]["SecondServes"] or 0) + 1
								finalBallInfoTable["numBounces"] = 0
							else
								finalBallInfoTable["playerStats"][PlayerServing.UserId]["DoubleFaults"] = (finalBallInfoTable["playerStats"][PlayerServing.UserId]["DoubleFaults"] or 0) + 1
								self:PointWinner(PlayerServing, winnerUserId, Court)
							end
						else
							if not secondServe then
								finalBallInfoTable["playerStats"][PlayerServing.UserId]["FirstServes"] = (finalBallInfoTable["playerStats"][PlayerServing.UserId]["FirstServes"] or 0) + 1
							end
							self:PointWinner(PlayerServing, winnerUserId, Court)
						end
					end

					pointActive = false
				end

				if not pointActive then
					if finalBallInfoTable == nil then
						finalBallInfoTable = Ball and self.balls[Ball.Name] or ballInfoTable
					end
					self:UpdatePlayerStats(PlayerServing, finalBallInfoTable["playerStats"])
					inBoundaryNameSideOne:destroy()
					inBoundaryNameSideTwo:destroy()
					SideOneDeuceServeBoxZONE:destroy()
					SideOneAdServeBoxZONE:destroy()
					SideTwoDeuceServeBoxZONE:destroy()
					SideTwoAdServeBoxZONE:destroy()
					CourtZone:destroy()
					task.delay(1, function()
						if self.balls[Ball.Name] then
							self.balls[Ball.Name]["fullBoundaryNameSideOne"]:destroy()
							self.balls[Ball.Name]["fullBoundaryNameSideTwo"]:destroy()
						end
						self.balls[Ball.Name] = nil
					end)
				end
			end
		end))
	end))
end

function Service:SecondServe(PlayerToServe, Court, PlayerSides, servingSide, PlayerServing)
	local MatchService = Framework.GetService("MatchService")
	local CourtRegistry = Framework.GetService("CourtRegistry")
	local BallService = Framework.GetService("BallService")
	task.spawn(function()
		MatchService.Signal.SwitchAnim:Fire(PlayerToServe, "Spike", Court)
		MatchService.Signal.ChangeServeBarrierStatus:Fire(PlayerToServe, Court, true)
		CourtRegistry:SetBarrierRole(PlayerToServe, true, true, Court)
		MatchService:destroyAllBalls(Court)
		MatchService:teleportPlayersToCorrectPositions(Court)
		MatchService:HighlightZonesForPlayers(Court, PlayerSides, PlayerServing, servingSide)
		Court:SetAttribute("RallyHits", 0)
		Court:SetAttribute("BallDespawnTime", -1)
		task.wait(5)
		Court:SetAttribute("RallyHits", 0)
		Court:SetAttribute("BallDespawnTime", -1)
		BallService:NewBall(PlayerToServe, Court:GetAttribute("CourtSurface"), true)
		self:TrackBallMatch(PlayerToServe, Court, PlayerSides, true, servingSide, PlayerServing)
	end)
end

function Service:Let(PlayerToServe, Court, PlayerSides, servingSide, secondServe, PlayerServing)
	local MatchService = Framework.GetService("MatchService")
	local CourtRegistry = Framework.GetService("CourtRegistry")
	local BallService = Framework.GetService("BallService")
	task.spawn(function()
		MatchService.Signal.SwitchAnim:Fire(PlayerToServe, "Spike", Court)
		MatchService.Signal.ChangeServeBarrierStatus:Fire(PlayerToServe, Court, true)
		CourtRegistry:SetBarrierRole(PlayerToServe, true, true, Court)
		MatchService:destroyAllBalls(Court)
		MatchService:teleportPlayersToCorrectPositions(Court)
		MatchService:HighlightZonesForPlayers(Court, PlayerSides, PlayerServing, servingSide)
		Court:SetAttribute("RallyHits", 0)
		Court:SetAttribute("BallDespawnTime", -1)
		task.wait(2.5)
		Court:SetAttribute("RallyHits", 0)
		Court:SetAttribute("BallDespawnTime", -1)
		BallService:NewBall(PlayerToServe, Court:GetAttribute("CourtSurface"), true)
		self:TrackBallMatch(PlayerToServe, Court, PlayerSides, secondServe, servingSide, PlayerServing)
	end)
end

function Service:PointWinner(PlayerServing, winnerUserId, Court)
	local MatchService = Framework.GetService("MatchService")
	MatchService:WinPoint(Court, winnerUserId)
end

function Service:Start()
	local CourtService = Framework.GetService("CourtService")
	local BallService = Framework.GetService("BallService")
	local dataService = Framework.GetService("DataService")
	self:InitializeCourtMaids()
end

local function getNearestCourt(pos)
	local nearestSpawn = nil
	local shortestDistance = math.huge
	for i, spawnPart in pairs(workspace.Courts:GetChildren()) do
		local distance = (spawnPart:GetPivot().Position - pos).Magnitude
		if distance < shortestDistance then
			shortestDistance = distance
			nearestSpawn = spawnPart
		end
	end

	for i, spawnPart in pairs(workspace.TutorialCourts:GetChildren()) do
		local distance = (spawnPart:GetPivot().Position - pos).Magnitude
		if distance < shortestDistance then
			shortestDistance = distance
			nearestSpawn = spawnPart
		end
	end

	return nearestSpawn
end

function Service:ListenForBall(BallName)
	task.delay(1, function()
		if not _G.ballSignals[BallName] then return end
		_G.ballSignals[BallName]["hitGround"]:Connect(function(hit, position, t, lastBounceTime)
			if lastBounceTime then
				if os.clock() - lastBounceTime > 1 then
					self:ballMark(position, getNearestCourt(position))
				end
			else
				self:ballMark(position, getNearestCourt(position))
			end
		end)
	end)
end

function Service:DetermineIfPositionIsIn(position, ballName)
	if not position then return false end
	if not self.balls[ballName] then return true end

	local sideOne = self.balls[ballName]["fullBoundaryNameSideOne"]
	local sideTwo = self.balls[ballName]["fullBoundaryNameSideTwo"]
	if not sideOne or not sideTwo then return false end

	local court = self.balls[ballName]["Court"]
	local adjustedPos = position
	if court and court:FindFirstChild("SideOneZone") then
		adjustedPos = vector.create(position.X, court.SideOneZone.Position.Y, position.Z)
	end

	local s = false
	if sideOne:findPoint(adjustedPos) or sideTwo:findPoint(adjustedPos) then
		s = true
	end
	return s
end

function Service:TrackBall(Player, Court, PlayerSides, SecondServe, ServingSide, PlayerServing)
	local CourtService = Framework.GetService("CourtService")
	self:TrackBallMatch(Player, Court, PlayerSides, SecondServe, ServingSide, PlayerServing)
end

return Service