-- Helper module for managing a leaderboard.
-- Assumes that you always know the score of the user you are updating because
-- binarySearch can be used to make table updates, which are O(log n).
local LeaderboardHelper = {}
LeaderboardHelper.__index = LeaderboardHelper

local Utf8Compress = require(script.Parent.utf8Compress)

export type entry = {
    id: string,
    score: number
}

export type leaderboardAccessor = {
    Get: (leaderboard: string, index: number) -> entry,
    Update: (leaderboard: string, oldIndex: number, newIndex: number, entry: entry) -> string,
    Insert: (leaderboard: string, index: number, entry: entry) -> string,
    Remove: (leaderboard: string, index: number) -> string,
    Length: (leaderboard: string) -> number
}


local ID_ENCODE_LENGTH = 5 -- userids are 10 characters long currently https://devforum.roblox.com/t/userids-are-going-over-32-bit-on-december-7th/903982
                            -- 5 bytes gives us 2^40 which gives leeway for the roblox playerbase to continue to grow.
local SCORE_ENCODE_LENGTH = 4
local RECORD_SIZE = ID_ENCODE_LENGTH + SCORE_ENCODE_LENGTH

function LeaderboardHelper._CompressRecord(id : number, score : number) : string
    return Utf8Compress.CompressInt(id, 5) .. Utf8Compress.CompressInt(score, 4)
end

function LeaderboardHelper._DecompressRecord(utf8 : string) : string
    local id = Utf8Compress.DecompressInt(utf8Sub(utf8, 1, ID_ENCODE_LENGTH), 5)
    local score = Utf8Compress.DecompressInt(utf8Sub(utf8, ID_ENCODE_LENGTH + 1, ID_ENCODE_LENGTH + SCORE_ENCODE_LENGTH), 4)
    return id, score
end

function utf8Sub(str: string, i : number, j : number?) 
    if j then
        return string.sub(str, utf8.offset(str, i), utf8.offset(str, j+1)-1)
    else 
        return string.sub(str, utf8.offset(str, i))
    end
end

LeaderboardHelper.compressedLeaderboardAccessor = {
    New = function()
        return ""
    end,
    Get = function(leaderboard : string, index : number)
        if index < 1 or index > utf8.len(leaderboard) / RECORD_SIZE then
            return nil
        end
        local startIndex = (index - 1) * RECORD_SIZE + 1
        local endIndex = startIndex + RECORD_SIZE - 1
        local id, score = LeaderboardHelper._DecompressRecord(utf8Sub(leaderboard, startIndex, endIndex))
        return {id = id, score = score}
    end,
    Update = function(leaderboard : string, oldIndex : number, newIndex : number, entry : entry)
        local packedEntry = LeaderboardHelper._CompressRecord(entry.id, entry.score)
        if oldIndex < newIndex then
            return utf8Sub(leaderboard, 1, (oldIndex-1)*RECORD_SIZE) ..
                utf8Sub(leaderboard, oldIndex*RECORD_SIZE + 1, newIndex*RECORD_SIZE) ..
                packedEntry ..
                utf8Sub(leaderboard, newIndex*RECORD_SIZE + 1)
        elseif oldIndex > newIndex then
            return utf8Sub(leaderboard, 1, (newIndex-1)*RECORD_SIZE) ..
                packedEntry ..
                utf8Sub(leaderboard, (newIndex-1)*RECORD_SIZE + 1, (oldIndex-1)*RECORD_SIZE) ..
                utf8Sub(leaderboard, oldIndex*RECORD_SIZE + 1)
        else
            return utf8Sub(leaderboard, 1, (newIndex-1)*RECORD_SIZE) ..
                packedEntry ..
                utf8Sub(leaderboard, newIndex*RECORD_SIZE + 1)
        end
    end,
    Insert = function(leaderboard : string, index : number, entry : entry)
        local packedEntry = LeaderboardHelper._CompressRecord(entry.id, entry.score)
        
        local val = utf8Sub(leaderboard, 1, (index-1)*RECORD_SIZE) .. 
            packedEntry .. 
            utf8Sub(leaderboard, (index-1)*RECORD_SIZE + 1)

        return val
    end,
    Remove = function(leaderboard : string, index : number)
        return utf8Sub(leaderboard, 1, (index-1)*RECORD_SIZE) .. 
            utf8Sub(leaderboard, index*RECORD_SIZE + 1)
    end,
    Length = function(leaderboard : string)
        return utf8.len(leaderboard) / RECORD_SIZE
    end
}

LeaderboardHelper.defaultLeaderboardAccessor = {
    New = function()
        return {}
    end,
    Get = function(leaderboard : {entry}, index : number)
        return leaderboard[index]
    end,
    Update = function(leaderboard : {entry}, oldIndex : number, newIndex : number, entry : entry)
        if oldIndex < newIndex then
            table.insert(leaderboard, newIndex, entry)
            table.remove(leaderboard, oldIndex)
        else
            table.remove(leaderboard, oldIndex)
            table.insert(leaderboard, newIndex, entry)
        end
        return leaderboard
    end,
    Insert = function(leaderboard : {entry}, index : number, entry : entry)
        table.insert(leaderboard, index, entry)
        return leaderboard
    end,
    Remove = function(leaderboard : {entry}, index : number)
        table.remove(leaderboard, index)
        return leaderboard
    end,
    Length = function(leaderboard : {entry})
        return #leaderboard
    end
}
function LeaderboardHelper.New()
    local self = setmetatable({}, LeaderboardHelper)
    self._accessor = LeaderboardHelper.defaultLeaderboardAccessor
    return self
end

function LeaderboardHelper:GenerateEmpty()
    return self._accessor.New()
end

function LeaderboardHelper:SetAccessor(accessor: leaderboardAccessor)
    self._accessor = accessor
end


function LeaderboardHelper:BinarySearch(leaderboard, score)
    local left, right = 1, self._accessor.Length(leaderboard)
    while left <= right do
        local mid = math.floor((left + right) / 2)
        if self._accessor.Get(leaderboard, mid).score == score then
            return mid
        elseif self._accessor.Get(leaderboard, mid).score < score then
            right = mid - 1
        else
            left = mid + 1
        end
    end
    return left
end

function LeaderboardHelper:GetIndex(leaderboard: {entry}, index : number): entry
    return self._accessor.Get(leaderboard, index)
end

function LeaderboardHelper:GetAll(leaderboard: {entry}): {entry}
    local result = {}
    for i = 1, self._accessor.Length(leaderboard) do
        table.insert(result, self._accessor.Get(leaderboard, i))
    end
    return result
end

function LeaderboardHelper:GetRank(leaderboard: {entry}, id: string, score: number): number
    if not leaderboard or self._accessor.Length(leaderboard) == 0 then
        return nil
    end

    local pos = self:BinarySearch(leaderboard, score)

    local upper = pos
    local upperValue = self._accessor.Get(leaderboard, upper)
    while upper >= 1 and upperValue and upperValue.score == score do
        if upperValue.id == id then
            return upper
        end
        upper = upper - 1
    end
    
    local lower = pos + 1
    local lowerValue = self._accessor.Get(leaderboard, lower)
    while lower <= self._accessor.Length(leaderboard) and lowerValue and lowerValue.score == score do
        if lowerValue.id == id then
            return lower
        end
        lower = lower + 1
    end
    
    return nil
end

function LeaderboardHelper:GetInsertPos(leaderboard: {entry}, score: number): number
    return self:BinarySearch(leaderboard, score)
end

function LeaderboardHelper:Remove(leaderboard: {entry}, id: string, score: number): number
    local rank = self:GetRank(leaderboard, id, score)
    if rank ~= -1 then
        leaderboard = self._accessor.Remove(leaderboard, rank)
    end
    return leaderboard, rank
end

function LeaderboardHelper:Update(leaderboard: {entry}, id: string, prevScore: number?, newScore: number): (number, number)
    local prevRank = nil
    local newRank = self:GetInsertPos(leaderboard, newScore)
    local entry = {id = id, score = newScore}
    if prevScore then

        prevRank = self:GetRank(leaderboard, id, prevScore)
        if prevRank < newRank then
            newRank = newRank - 1
        end
        leaderboard = self._accessor.Update(leaderboard, prevRank, newRank, entry)
    else
        leaderboard = self._accessor.Insert(leaderboard, newRank, entry)
    end
    
    return leaderboard, prevRank, newRank
end

return LeaderboardHelper