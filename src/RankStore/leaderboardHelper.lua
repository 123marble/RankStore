local leaderboardHelper = {}

export type entry = {
    id : string,
    score : number
}

export type leaderboard = {entry}

local function binarySearch(bucket, score)
    local left, right = 1, #bucket / 6  -- Each entry is 6 bytes
    while left <= right do
        local mid = math.floor((left + right) / 2)
        local _, midScore = string.unpack(">I3I3", bucket, (mid - 1) * 6 + 1)
        if midScore < score then
            right = mid - 1
        else
            left = mid + 1
        end
    end
    return left
end

function leaderboardHelper.GetRank(leaderboard, id, score)

end

function leaderboardHelper.GetInsertPos(leaderboard, score)

end

function leaderboardHelper.Remove(leaderboard, id, score)

end
-- 1. Find and remove prevScore and id from the leaderboard
-- 2. Insert newScore and id into the leaderboard
function leaderboardHelper.Update(leaderboard, id : string, prevScore : number?, newScore : number)
    local prevRank = leaderboardHelper.Remove(leaderboard, id, prevScore)
    local newRank = leaderboardHelper.GetInsertPos(leaderboard, newScore)
    table.insert(leaderboard, newRank, {id = id, score = newScore})
    
    return prevRank, newRank
end

return leaderboardHelper