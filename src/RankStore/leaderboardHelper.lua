-- Helper module for managing a leaderboard.
-- Assumes that you always know the score of the user you are updating because
-- binarySearch can be used to make table updates, which are O(log n).
local leaderboardHelper = {}

export type entry = {
    id: string,
    score: number
}

export type leaderboard = {entry}

local function binarySearch(bucket, score)
    local left, right = 1, #bucket
    while left <= right do
        local mid = math.floor((left + right) / 2)
        if bucket[mid].score == score then
            return mid
        elseif bucket[mid].score < score then
            right = mid - 1
        else
            left = mid + 1
        end
    end
    return left
end

function leaderboardHelper.GetRank(leaderboard: leaderboard, id: string, score: number): number
    if not leaderboard or #leaderboard == 0 then
        return nil
    end

    local pos = binarySearch(leaderboard, score)

    local upper = pos
    while upper >= 1 and leaderboard[upper] and leaderboard[upper].score == score do
        if leaderboard[upper].id == id then
            return upper
        end
        upper = upper - 1
    end
    
    local lower = pos + 1
    while lower <= #leaderboard and leaderboard[lower] and leaderboard[lower].score == score do
        if leaderboard[lower].id == id then
            return lower
        end
        lower = lower + 1
    end
    
    return nil
end

function leaderboardHelper.GetInsertPos(leaderboard: leaderboard, score: number): number
    return binarySearch(leaderboard, score)
end

function leaderboardHelper.Remove(leaderboard: leaderboard, id: string, score: number): number
    local rank = leaderboardHelper.GetRank(leaderboard, id, score)
    if rank ~= -1 then
        table.remove(leaderboard, rank)
    end
    return rank
end

-- 1. Find and remove id with prevScore from the leaderboard
-- 2. Insert id with newScore into the leaderboard
function leaderboardHelper.Update(leaderboard: leaderboard, id: string, prevScore: number?, newScore: number): (number, number)
    local prevRank = nil
    if prevScore then
        prevRank = leaderboardHelper.Remove(leaderboard, id, prevScore)
    end
    local newRank = leaderboardHelper.GetInsertPos(leaderboard, newScore)
    table.insert(leaderboard, newRank, {id = id, score = newScore})
    
    return prevRank, newRank
end

return leaderboardHelper