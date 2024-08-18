-- Helper module for managing a leaderboard.
-- Assumes that you always know the score of the user you are updating because
-- binarySearch can be used to make table updates, which are O(log n).
local leaderboardHelper = {}

export type entry = {
    id : string,
    score : number
}

export type leaderboard = {entry}

local function binarySearch(bucket, score)

end

function leaderboardHelper.GetRank(leaderboard : leaderboard, id : number, score : number) : number

end

function leaderboardHelper.GetInsertPos(leaderboard : leaderboard, score : number) : number

end

function leaderboardHelper.Remove(leaderboard : leaderboard, id : number, score : number) : number

end
-- 1. Find and remove prevScore and id from the leaderboard
-- 2. Insert newScore and id into the leaderboard
function leaderboardHelper.Update(leaderboard : leaderboard, id : string, prevScore : number?, newScore : number) : (number, number)
    local prevRank = leaderboardHelper.Remove(leaderboard, id, prevScore)
    local newRank = leaderboardHelper.GetInsertPos(leaderboard, newScore)
    table.insert(leaderboard, newRank, {id = id, score = newScore})
    
    return prevRank, newRank
end

return leaderboardHelper