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

    local scores = {newScore}
    -- TODO: Find a way to make the below code cleaner.
    if prevScore then
        table.insert(scores, prevScore)
        local rankSums = self:_GetSummedRanksOverBuckets({bucketKey}, scores)
        prevRank += rankSums[2]
        newRank += rankSums[1]
    else
        local rankSums = self:_GetSummedRanksOverBuckets({bucketKey}, scores)
        newRank += rankSums[1]
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

    local rankSums = self:_GetSummedRanksOverBuckets({bucketKey}, {score})
    rank += rankSums[1]

    return rank
end

function BucketsStore:GetTopScoresAsync(limit : number) : {entry}
    local leaderboards = {}

    self:_MapGetBucketsAsync(function(leaderboard)
        if #leaderboard > 0 then
            table.insert(leaderboards, leaderboard)
        end
    end, nil, true)

    local topScores = Util.Merge(leaderboards, false, function(entry) return entry.score end, limit)
    return topScores
end

function BucketsStore:_MapGetBucketsAsync(func : (leaderboard : {entry}) -> any, ignoreKeys : {string}, parallel : boolean?, ...)
    parallel = parallel or false

    local function runMap(bucketKey, ...)
        local leaderboard = self:_GetBucketAsync(bucketKey)
        func(leaderboard, ...)
    end
    
    local bucketKeys = self:_GetAllBucketKeys(ignoreKeys)
    
    for _, bucketKey in ipairs(bucketKeys) do
        if parallel then
            task.spawn(function(...)
                runMap(bucketKey, ...)
            end, ...)
        else
            runMap(bucketKey, ...)
        end
    end
end

function BucketsStore:_GetSummedRanksOverBuckets(ignoreKeys : {string}, scores : {number}) : number
    local ranks = {}
    for i = 1, #scores do
        ranks[i] = 0
    end

    local function sumBucket(leaderboard, ...)
        local scores, ranks = table.unpack({...})
        for i, score in ipairs(scores) do
            local bucketRank = LeaderboardHelper.GetInsertPos(leaderboard, score) - 1
            ranks[i] += bucketRank
        end
    end

    self:_MapGetBucketsAsync(sumBucket, ignoreKeys, true, scores, ranks)

    return ranks
end

function BucketsStore:_GetBucketKeyAsync(index)
    local bucketKey = "bucket_line_" .. self._metadataStore:GetAsync().line .. "_index_" .. index
    
    return bucketKey
end

function BucketsStore:_GetRandomBucketIndexAsync(uniqueId : number)
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

function BucketsStore:_GetBucketKeyForId(uniqueId : number)
    local bucketIndex = self:_GetRandomBucketIndexAsync(uniqueId)
    local bucketKey = self:_GetBucketKeyAsync(bucketIndex)
    return bucketKey
end

function BucketsStore:_GetAllBucketKeys(ignoreKeys : {string}?)
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