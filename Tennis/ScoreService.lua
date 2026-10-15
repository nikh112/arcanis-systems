-- [[ SERVICES ]] --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BotModule = require(game.ServerScriptService.Server.Services.CourtService.BotPlayer)

-- [[ VARIABLES ]] --
local ScoreService = {
    Name = "ScoreService"
}

-- [[ PRIVATE FUNCTIONS ]] --
local function deepCopy(original)
    local copy = {}
    for k, v in pairs(original) do
        copy[k] = (type(v) == "table") and deepCopy(v) or v
    end
    return copy
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

-- [[ PUBLIC FUNCTIONS ]] --
function ScoreService:CalculateMatchStatus(court, gameScore, setScore, matchScore, tiebreakScore, playerServing, getTeamNameFunc)
    local bestTo = court:GetAttribute("BestTo") 
    local winBy2 = court:GetAttribute("WinBy2") 
    local matchBestTo = court:GetAttribute("MatchBestTo") 
    local setsNeededToWin = math.ceil(matchBestTo / 2) 
    local adScoring = court:GetAttribute("AdScoring") 
    local tiebreakThreshold = court:GetAttribute("Tiebreaker") or 0 
    local displayScore = tiebreakScore or gameScore 

    local function isOnePointAway(currentScore, opponentScore)
        local currentStr = tostring(currentScore)
        local opponentStr = tostring(opponentScore)
        if adScoring then
            return (currentStr == "40" and (opponentStr ~= "40" and opponentStr ~= "ADV.")) or currentStr == "ADV."
        else
            return currentStr == "40"
        end
    end

    local servingSide = playerServing 
    local receivingSide = servingSide == 1 and 2 or 1 
    local status = ""
    local setWinningSide = nil

    if tiebreakScore then
        local tiebreakTarget = tiebreakThreshold
        if tiebreakScore[1] >= tiebreakTarget - 1 and tiebreakScore[1] - tiebreakScore[2] >= 1 then
            setWinningSide = 1
        elseif tiebreakScore[2] >= tiebreakTarget - 1 and tiebreakScore[2] - tiebreakScore[1] >= 1 then
            setWinningSide = 2
        end
    else
        if winBy2 then
            if setScore[1] >= bestTo - 1 and setScore[1] - setScore[2] >= 1 and isOnePointAway(displayScore[1], displayScore[2]) then
                setWinningSide = 1
            elseif setScore[2] >= bestTo - 1 and setScore[2] - setScore[1] >= 1 and isOnePointAway(displayScore[2], displayScore[1]) then
                setWinningSide = 2
            end
        else
            if setScore[1] == bestTo - 1 and isOnePointAway(displayScore[1], displayScore[2]) then
                setWinningSide = 1
            elseif setScore[2] == bestTo - 1 and isOnePointAway(displayScore[2], displayScore[1]) then
                setWinningSide = 2
            end
        end
    end

    if setWinningSide then
        local wouldWinMatch = (matchScore[setWinningSide] + 1) >= setsNeededToWin
        status = (wouldWinMatch and "MATCH POINT " or "SET POINT ") .. getTeamNameFunc(setWinningSide)
    elseif not tiebreakScore then
        if isOnePointAway(displayScore[receivingSide], displayScore[servingSide]) then
            status = "BREAK POINT " .. getTeamNameFunc(receivingSide)
        elseif isOnePointAway(displayScore[servingSide], displayScore[receivingSide]) then
            status = "GAME POINT " .. getTeamNameFunc(servingSide)
        end
    end

    return status
end

function ScoreService:AwardPoint(gameScore, playerSide, adScoring)
    local newScore = deepCopy(gameScore)
    local gameWonBySide = nil

    if playerSide == 1 then
        if newScore[1] == 0 then newScore[1] = 15
        elseif newScore[1] == 15 then newScore[1] = 30
        elseif newScore[1] == 30 then newScore[1] = 40
        elseif newScore[1] == 40 then
            if adScoring and (newScore[2] == 40 or newScore[2] == "ADV.") then
                if newScore[2] == 40 then newScore[1] = "ADV." else newScore[2] = 40 end
            else
                gameWonBySide = 1
            end
        elseif newScore[1] == "ADV." then
            gameWonBySide = 1
        end
    elseif playerSide == 2 then
        if newScore[2] == 0 then newScore[2] = 15
        elseif newScore[2] == 15 then newScore[2] = 30
        elseif newScore[2] == 30 then newScore[2] = 40
        elseif newScore[2] == 40 then
            if adScoring and (newScore[1] == 40 or newScore[1] == "ADV.") then
                if newScore[1] == 40 then newScore[2] = "ADV." else newScore[1] = 40 end
            else
                gameWonBySide = 2
            end
        elseif newScore[2] == "ADV." then
            gameWonBySide = 2
        end
    end

    return newScore, gameWonBySide
end

function ScoreService:CheckTiebreakWon(tiebreakScore, target)
    if tiebreakScore[1] >= target and tiebreakScore[1] - tiebreakScore[2] >= 2 then return 1 end
    if tiebreakScore[2] >= target and tiebreakScore[2] - tiebreakScore[1] >= 2 then return 2 end
    return nil
end

function ScoreService:AwardTiebreakPoint(tiebreakScore, winSide)
    local newScore = deepCopy(tiebreakScore)
    newScore[winSide] += 1
    return newScore
end

function ScoreService:EvaluateSetState(setScore, bestTo, winBy2, tiebreakThreshold)
    if tiebreakThreshold and tiebreakThreshold > 0 and setScore[1] == bestTo and setScore[2] == bestTo then
        return { enterTiebreak = true }
    end
    if winBy2 then
        if setScore[1] >= bestTo and (setScore[1] - setScore[2] >= 2) then return { setWonBySide = 1 } end
        if setScore[2] >= bestTo and (setScore[2] - setScore[1] >= 2) then return { setWonBySide = 2 } end
    else
        if setScore[1] >= bestTo then return { setWonBySide = 1 } end
        if setScore[2] >= bestTo then return { setWonBySide = 2 } end
    end
    return nil
end

function ScoreService:EvaluateMatchState(matchScore, setsNeededToWin)
    if matchScore[1] >= setsNeededToWin then return 1 end
    if matchScore[2] >= setsNeededToWin then return 2 end
    return nil
end

-- [[ FRAMEWORK INIT ]] --
return ScoreService