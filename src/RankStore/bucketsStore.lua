local BucketsStore = {}
BucketsStore.__index = BucketsStore

local Shared = require(script.Parent.shared)
local LeaderboardHelper = require(script.Parent.leaderboardHelper)
local Util = require(script.Parent.util)
local MetadataStore = require(script.Parent.metadataStore)

export type entry = LeaderboardHelper.entry

function BucketsStore.GetBucketsStore(name : string, metadataStore : MetadataStore.typedef)
    local self = setmetatable({}, BucketsStore)

    self._datastore = Shared.GetDataStore(name)
    self._metadataStore = metadataStore

    return self
end

function BucketsStore:SetScoreAsync(id : number, prevScore : number?, newScore : number) : (number, number)
    local bucketKey = self:_GetBucketKeyForId(id)
    local prevRank, newRank
    local success, result = pcall(function()
        return self._datastore:UpdateAsync(bucketKey, function(leaderboard : {LeaderboardHelper.entry})
            leaderboard = leaderboard or {}

            prevRank, newRank = LeaderboardHelper.Update(leaderboard, id, prevScore, newScore)
            return leaderboard
        end)
    end)

    if not success then
        error("Failed to set score: " .. tostring(result))
    end

    local bucketKeys = self:_GetAllBucketKeys({bucketKey})
    local scores = {newScore}
    if prevScore then
        table.insert(scores, prevScore)
    end
    local rankSums = self:_GetSummedRanksOverBuckets(bucketKeys, scores)
    newRank += rankSums[1]
    if prevScore then
        prevRank += rankSums[2]
    end

    return prevRank, newRank
end

function BucketsStore:FindRank(id : number, score : number) : number
    local bucketKey = self:_GetBucketKeyForId(id)
    local leaderboard = self:_GetBucketAsync(bucketKey)
    local rank = LeaderboardHelper.GetRank(leaderboard, id, score)

    if not rank then
        return nil
    end

    local bucketKeys = self:_GetAllBucketKeys({bucketKey})
    local rankSums = self:_GetSummedRanksOverBuckets(bucketKeys, {score})
    rank += rankSums[1]

    return rank
end

function BucketsStore:GetTopScoresAsync(limit : number) : {entry}
    local leaderboards = {}

    -- TODO: Fetch buckets in parallel.
    local bucketKeys = self:_GetAllBucketKeys()
    for _, bucketKey in ipairs(bucketKeys) do
        local leaderboard = self:_GetBucketAsync(bucketKey)
        if #leaderboard > 0 then
            table.insert(leaderboards, leaderboard)
        end
    end
 
    local topScores = Util.Merge(leaderboards, false, function(entry) return entry.score end, limit)
    return topScores
end

function BucketsStore:_GetSummedRanksOverBuckets(bucketKeys : {string}, scores : {number}) : number
    local ranks = {}
    for i = 1, #scores do
        ranks[i] = 0
    end
    for _, bucketKey in ipairs(bucketKeys) do
        local leaderboard = self:_GetBucketAsync(bucketKey)
        for i, score in ipairs(scores) do
            local bucketRank = LeaderboardHelper.GetInsertPos(leaderboard, score) - 1
            ranks[i] += bucketRank
        end
    end
    return ranks
end

function BucketsStore:_GetBucketKeyAsync(index)
    local bucketKey = "bucket_line_" .. self._metadataStore:GetAsync().line .. "_index_" .. index
    
    return bucketKey
end

function BucketsStore:_getRandomBucketIndexAsync(uniqueId : number)
    return uniqueId % self._metadataStore:GetAsync().numBuckets + 1
end

function BucketsStore:_GetBucketAsync(bucketKey : number) : {entry}
    local success, result = pcall(function()
        return self._datastore:GetAsync(bucketKey)
    end)

    if not success then
        error("Failed to get bucket: " .. tostring(result))
    end

    if not result then
        return {}
    end

    return result
end



-- If the metadataCache is expired then this function will yield.
function BucketsStore:_GetBucketKeyForId(uniqueId : number)
    local bucketIndex = self:_getRandomBucketIndexAsync(uniqueId)
    local bucketKey = self:_GetBucketKeyAsync(bucketIndex)
    return bucketKey
end

function BucketsStore:_GetAllBucketKeys(ignoreKeys : {number}?)
    local ignoreKeys = ignoreKeys or {}
    local bucketKeys = {}
    
    for i = 1, self._metadataStore:GetAsync().numBuckets do
        local key = self:_GetBucketKeyAsync(i)
        if not table.find(ignoreKeys, key) then
            table.insert(bucketKeys, key)
        end
        
    end
    
    return bucketKeys
end


return BucketsStore