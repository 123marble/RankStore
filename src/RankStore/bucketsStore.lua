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

function BucketsStore:_UpdateBucketBatchAsync(bucketKey : string, ids : {number}, prevScores : {number}, newScores : {number})
    local prevRanks, newRanks = {}, {}
    local success, result = pcall(function()
        return self._datastore:UpdateAsync(bucketKey, function(leaderboard : {LeaderboardHelper.entry})
            leaderboard = leaderboard or {}

            for i, id in ipairs(ids) do
                local prevRank, newRank = LeaderboardHelper.Update(leaderboard, id, prevScores[i], newScores[i])
                table.insert(prevRanks, prevRank)
                table.insert(newRanks, newRank)
            end

            return leaderboard
        end)
    end)

    if not success then
        error("Failed to update bucket: " .. tostring(result))
    end

    return prevRanks, newRanks
end

function BucketsStore:_GroupByBucketKey(ids : {number}, prevScores : {number?}, newScores : {number}) : {[string] : {{number}}}
    local idToBucket = {}
    for i, id in ipairs(ids) do
        local bucketKey = self:_GetBucketKeyForId(id)
        if not idToBucket[bucketKey] then
            idToBucket[bucketKey] = {}
            idToBucket[bucketKey][1] = {}
            idToBucket[bucketKey][2] = {}
            idToBucket[bucketKey][3] = {}
        end

        local prevScore = prevScores[i]
        local newScore = newScores[i]

        table.insert(idToBucket[bucketKey][1], id)
        table.insert(idToBucket[bucketKey][2], prevScore)
        table.insert(idToBucket[bucketKey][3], newScore)
    end
    return idToBucket
end

function BucketsStore:SetScoreBatchAsync(ids : {number}, prevScores : {number?}, newScores : number) : ({number}, {number})
    local groupedIds = self:_GroupByBucketKey(ids, prevScores, newScores)
    local primaryBucketPrevRanks, primaryBucketNewRanks = {}, {}
    for bucketKey, v in pairs(groupedIds) do
        local ids, prevScores, newScores = table.unpack(v)

        local bucketPrevRanks, bucketNewRanks = self:_UpdateBucketBatchAsync(bucketKey, ids, prevScores, newScores)
        for i = 1, #bucketNewRanks do
            primaryBucketPrevRanks[#primaryBucketNewRanks+1] = bucketPrevRanks[i]
            primaryBucketNewRanks[#primaryBucketNewRanks+1] = bucketNewRanks[i]
        end
    end
    
    local prevRanks, newRanks = primaryBucketPrevRanks, primaryBucketNewRanks
    local otherBucketPrevRanksSummed, otherBucketNewRanksSummed = self:_FindRankChangeBatchAsync(ids, prevScores, newScores, false)
    for i = 1, #otherBucketNewRanksSummed do
        if prevRanks[i] then
            prevRanks[i] += otherBucketPrevRanksSummed[i]
        end
        newRanks[i] += otherBucketNewRanksSummed[i]
    end

    return prevRanks, newRanks
end

function BucketsStore:SetScoreAsync(id : number, prevScore : number?, newScore : number) : (number, number)
    local prevRanks, newRanks = self:SetScoreBatchAsync({id}, {prevScore}, {newScore})
    return prevRanks[1], newRanks[1]
end

-- Intended to be used in combination with _MapGetBucketsAsync
local function _SumBucket(bucketsStore, bucketKey, leaderboard, ...)
    local ids, scores, ranks, includePrimary = table.unpack({...})
    
    for i, id in ipairs(ids) do
        if not scores[i] then
            ranks[i] = nil
            continue
        end

        local bucketRank = 0
        if bucketsStore:_GetBucketKeyForId(id) == bucketKey then
            if includePrimary then
                bucketRank = LeaderboardHelper.GetRank(leaderboard, id, scores[i])
            end
        else
            bucketRank = LeaderboardHelper.GetInsertPos(leaderboard, scores[i]) - 1
        end

        ranks[i] += bucketRank
    end
end

-- Intended to be used in combination with _MapGetBucketsAsync
local function _SumBucketChange(bucketsStore, bucketKey, leaderboard, ...)
    local ids, prevScores, newScores, prevRanks, newRanks, includePrimary = table.unpack({...})

    _SumBucket(bucketsStore, bucketKey, leaderboard, ids, prevScores, prevRanks, includePrimary)
    _SumBucket(bucketsStore, bucketKey, leaderboard, ids, newScores, newRanks, includePrimary)
end

function BucketsStore:_FindRankChangeBatchAsync(ids : {number}, prevScores : {number?}, newScores : {number}, includePrimary : boolean) : ({number}, {number})
    local prevRanks = {}
    local newRanks = {}
    for i = 1, #ids do
        prevRanks[i] = 0
        newRanks[i] = 0
    end

    self:_MapGetBucketsAsync(_SumBucketChange, nil, false, ids, prevScores, newScores, prevRanks, newRanks, includePrimary)

    return prevRanks, newRanks
end

function BucketsStore:FindRankBatchAsync(ids : {number}, scores : {number}) : {number}
    local ranks = {}
    for i = 1, #ids do
        ranks[i] = 0
    end
    local includePrimary = true
    self:_MapGetBucketsAsync(_SumBucket, nil, true, ids, scores, ranks, includePrimary)
    return ranks
end

function BucketsStore:FindRankAsync(id : number, score : number) : {number}
    local ranks = self:FindRankBatchAsync({id}, {score})
    return ranks[1]
end


function BucketsStore:GetTopScoresAsync(limit : number) : {entry}
    local leaderboards = {}

    self:_MapGetBucketsAsync(function(_, _, leaderboard)
        if #leaderboard > 0 then
            table.insert(leaderboards, leaderboard)
        end
    end, nil, true)

    local topScores = Util.Merge(leaderboards, false, function(entry) return entry.score end, limit)
    return topScores
end

function BucketsStore:_MapGetBucketsAsync(func : (bucketsStore : {}, bucketKey : string, leaderboard : {entry}, any...) -> any, ignoreKeys : {string}?, parallel : boolean?, ...)
    parallel = parallel or false

    local function runMap(bucketKey, ...)
        local leaderboard = self:_GetBucketAsync(bucketKey)
        func(self, bucketKey, leaderboard, ...)
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