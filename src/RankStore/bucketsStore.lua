local BucketsStore = {}
BucketsStore.__index = BucketsStore

local Shared = require(script.Parent.shared)
local LeaderboardHelper = require(script.Parent.leaderboardHelper)
local Util = require(script.Parent.util)
local MetadataStore = require(script.Parent.metadataStore)

local READ_THROUGHPUT_LIMIT_BYTES = 25*1024*1024
local WRITE_THROUGHPUT_LIMIT_BYTES = 4*1024*1024

export type entry = LeaderboardHelper.entry

type bucketsConfig = {
    numBuckets : number,
    maxBucketSize : number,
    line : number,
    version : number
}

local BucketsOperator = {}
BucketsOperator.__index = BucketsOperator

function BucketsOperator.New(name : string, config : bucketsConfig, parallel : boolean?)
    local self = setmetatable({}, BucketsOperator)

    self._config = config
    self._datastore = Shared.GetDataStore(name)
    self._parallel = parallel == nil and true or parallel
    self._leaderboardHelper = LeaderboardHelper.New()
    self._leaderboardHelper:SetAccessor(LeaderboardHelper.compressedLeaderboardAccessor)

    return self
end

function BucketsOperator:SetScoreBatchWithResultAsync(ids : {number}, prevScores : {number?}, newScores : number) : ({number}, {number})
    local ids, prevScores, newScores, primaryBucketPrevRanks, primaryBucketNewRanks = self:SetScoreBatchAsync(ids, prevScores, newScores)
    
    local prevRanks, newRanks = self:_GetSetScoreBatchResult(
        ids,
        prevScores,
        newScores,
        primaryBucketPrevRanks,
        primaryBucketNewRanks
    )

    return prevRanks, newRanks
end

function BucketsOperator:SetScoreBatchAsync(ids : {number}, prevScores : {number?}, newScores : {number})
    local groupedIds = self:_GroupByBucketKey(ids, prevScores, newScores)
    local primaryBucketIds, primaryBucketPrevRanks, primaryBucketNewRanks, primaryBucketPrevScores, primaryBucketNewScores = {}, {}, {}, {}, {}
    for bucketKey, v in pairs(groupedIds) do
        local bucketIds, bucketPrevScores, bucketNewScores = table.unpack(v)

        local bucketPrevRanks, bucketNewRanks = self:_UpdateBucketBatchAsync(bucketKey, bucketIds, bucketPrevScores, bucketNewScores)
        
        for i = 1, #bucketNewRanks do
            local newIndex = #primaryBucketNewRanks+1
            primaryBucketIds[newIndex] = bucketIds[i]
            primaryBucketPrevRanks[newIndex] = bucketPrevRanks[i]
            primaryBucketNewRanks[newIndex] = bucketNewRanks[i]
            primaryBucketPrevScores[newIndex] = bucketPrevScores[i]
            primaryBucketNewScores[newIndex] = bucketNewScores[i]
        end
    end
    return primaryBucketIds, primaryBucketPrevScores, primaryBucketNewScores, primaryBucketPrevRanks, primaryBucketNewRanks
end

function BucketsOperator:_GetBucketsRaw() : {{entry}}
    local leaderboards = {}

    self:_MapGetBucketsAsync(function(_, _, leaderboard)
        if #leaderboard > 0 then
            table.insert(leaderboards, leaderboard)
        end
    end, nil, false) -- TODO: Doesn't work in parallel because it needs to actually yield to wait for the data to be fetched

    return leaderboards
end

function BucketsOperator:GetBuckets() : {{entry}}
    local leaderboards = self:_GetBucketsRaw()
    local result = {}
    for _, leaderboard in ipairs(leaderboards) do
        table.insert(result, self._leaderboardHelper:GetAll(leaderboard))
    end
    return result
end

function BucketsOperator:GetTopScoresAsync(limit : number) : {entry}
    local leaderboards = self:_GetBucketsRaw()

    local topScores = Util.Merge(leaderboards, self._leaderboardHelper._accessor, false, function(entry) return entry.score end, limit)
    return topScores
end

function BucketsOperator:GetBucketRawAsync(bucketKey : number) : {entry}
    local success, result = pcall(function()
        return self._datastore:GetAsync(bucketKey)
    end)

    if not success then
        error("Failed to get bucket: " .. tostring(result))
    end

    if not result then
        return self._leaderboardHelper:GenerateEmpty()
    end

    return result
end

function BucketsOperator:GetBucketAsync(bucketKey : string) : {entry}
    local leaderboard = self:GetBucketRawAsync(bucketKey)
    return self._leaderboardHelper:GetAll(leaderboard)
end


function BucketsOperator:_GetSetScoreBatchResult(ids, prevScores, newScores, primaryBucketPrevRanks, primaryBucketNewRanks)
    local otherBucketPrevRanksSummed, otherBucketNewRanksSummed = self:_FindRankChangeBatchAsync(ids, prevScores, newScores, false)
    local prevRanks, newRanks = primaryBucketPrevRanks, primaryBucketNewRanks
    for i = 1, #otherBucketNewRanksSummed do
        if prevRanks[i] then
            prevRanks[i] += otherBucketPrevRanksSummed[i]
        end
        newRanks[i] += otherBucketNewRanksSummed[i]
    end

    return prevRanks, newRanks
end

function BucketsOperator:_GroupByBucketKey(ids : {number}, prevScores : {number?}, newScores : {number}) : {[string] : {{number}}}
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

        local bucketGroupIds = idToBucket[bucketKey][1]
        local bucketGroupPrevScores = idToBucket[bucketKey][2]
        local bucketGroupNewScores = idToBucket[bucketKey][3]
        table.insert(bucketGroupIds, id)
        bucketGroupPrevScores[#bucketGroupIds] = prevScore -- using #bucketGroupIds in case prevScores has nils
        bucketGroupNewScores[#bucketGroupIds] = newScore
    end
    return idToBucket
end

function BucketsOperator:_UpdateBucketBatchAsync(bucketKey : string, ids : {number}, prevScores : {number}, newScores : {number})
    local maxBucketSize = self._config.maxBucketSize
    local updateFailureReason = ""
    local prevRanks, newRanks = {}, {}
    local _, result = pcall(function()
        return self._datastore:UpdateAsync(bucketKey, function(leaderboard : {LeaderboardHelper.entry})
            leaderboard = leaderboard or self._leaderboardHelper:GenerateEmpty()

            if #leaderboard + Shared.RECORD_BYTES*#ids > maxBucketSize then
                updateFailureReason = "Not enough space in bucket."
                return nil
            end
            
            for i, id in ipairs(ids) do
                local success, _leaderboard, prevRank, newRank = pcall(function() return self._leaderboardHelper:Update(leaderboard, id, prevScores[i], newScores[i]) end)
                if not success then
                    updateFailureReason = "Error occurred during UpdateAsync: " .. tostring(_leaderboard)
                    return nil
                end
                leaderboard = _leaderboard
                table.insert(newRanks, newRank)
                prevRanks[#newRanks] = prevRank
            end

            return leaderboard
        end)
    end)

    if not result then
        error("Failed to update bucket " .. bucketKey .. ": " .. updateFailureReason)
    end

    return prevRanks, newRanks
end

-- Intended to be used in combination with _MapGetBucketsAsync
local function _SumBucket(
    bucketsStore : {},
    bucketKey : string,
    leaderboard : {entry},
    ids : {number},
    scores : {number},
    ranks : {number},
    includePrimary : boolean
)
    for i, id in ipairs(ids) do
        if not scores[i] then
            ranks[i] = nil
            continue
        end

        local bucketRank = 0
        if bucketsStore:_GetBucketKeyForId(id) == bucketKey then
            if includePrimary then
                bucketRank = bucketsStore._leaderboardHelper:GetRank(leaderboard, id, scores[i])
            end
        else
            bucketRank = bucketsStore._leaderboardHelper:GetInsertPos(leaderboard, scores[i]) - 1
        end

        ranks[i] += bucketRank
    end
end

-- Intended to be used in combination with _MapGetBucketsAsync
local function _SumBucketChange(
    bucketsStore : {},
    bucketKey : string,
    leaderboard : {entry}, 
    ids : {number}, 
    prevScores : {number?}, 
    newScores : {number}, 
    prevRanks : {number}, 
    newRanks : {number}, 
    includePrimary : boolean
)
    _SumBucket(bucketsStore, bucketKey, leaderboard, ids, prevScores, prevRanks, includePrimary)
    _SumBucket(bucketsStore, bucketKey, leaderboard, ids, newScores, newRanks, includePrimary)
end

function BucketsOperator:FindRankBatchAsync(ids : {number}, scores : {number}) : {number}
    local ranks = {}
    for i = 1, #ids do
        ranks[i] = 0
    end
    local includePrimary = true
    self:_MapGetBucketsAsync(_SumBucket, nil, self._parallel, ids, scores, ranks, includePrimary)
    return ranks
end

function BucketsOperator:_FindRankChangeBatchAsync(ids : {number}, prevScores : {number?}, newScores : {number}, includePrimary : boolean) : ({number}, {number})
    local prevRanks = {}
    local newRanks = {}
    for i = 1, #ids do
        prevRanks[i] = 0
        newRanks[i] = 0
    end

    self:_MapGetBucketsAsync(_SumBucketChange, nil, self._parallel, ids, prevScores, newScores, prevRanks, newRanks, includePrimary)

    return prevRanks, newRanks
end

function BucketsOperator:_MapGetBucketsAsync(func : (bucketsStore : {}, bucketKey : string, leaderboard : {entry}, any...) -> any, ignoreKeys : {string}?, parallel : boolean?, ...)
    parallel = parallel or false

    local function runMap(bucketKey, ...)
        local leaderboard = self:GetBucketRawAsync(bucketKey)
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

function BucketsOperator:_GetBucketKey(line : number, bucketIndex : number, version : number) : string
    return "bucket_line_" .. line .. "_index_" .. bucketIndex .. "_version_" .. version
end

function BucketsOperator:GetBucketKey(index)
    return self:_GetBucketKey(self._config.line, index, self._config.version)
end

function BucketsOperator:_GetRandomBucketIndex(uniqueId : number)
    return uniqueId % self._config.numBuckets + 1
end

function BucketsOperator:_GetBucketKeyForId(uniqueId : number)
    local bucketIndex = self:_GetRandomBucketIndex(uniqueId)
    local bucketKey = self:GetBucketKey(bucketIndex)
    return bucketKey
end

function BucketsOperator:_GetAllBucketKeys(ignoreKeys : {string}?)
    local ignoreKeys = ignoreKeys or {}
    local bucketKeys = {}
    
    for i = 1, self._config.numBuckets do
        local key = self:GetBucketKey(i)
        if not table.find(ignoreKeys, key) then
            table.insert(bucketKeys, key)
        end
    end
    
    return bucketKeys
end

function BucketsStore.GetBucketsStore(name : string, metadataStore : MetadataStore.typedef, parallel : boolean?)
    local self = setmetatable({}, BucketsStore)

    self._name = name
    self._metadataStore = metadataStore
    self._parallel = parallel == nil and true or parallel
    
    return self
end

function BucketsStore:_ConstructConfigFromMetadata() : bucketsConfig
    local metadata = self._metadataStore:GetAsync()
    return {
        numBuckets = metadata.numBuckets,
        maxBucketSize = metadata.maxBucketSize,
        line = metadata.line,
        version = metadata.version
    }
end

function BucketsStore:_ConstructOperator()
    return BucketsOperator.New(self._name, self:_ConstructConfigFromMetadata())
end

function BucketsStore:SetScoreBatchAsync(ids : {number}, prevScores : {number?}, newScores : {number})
    local operator = self:_ConstructOperator()
    local prevRank, newRank = operator:SetScoreBatchWithResultAsync(ids, prevScores, newScores)
    return prevRank, newRank
end

function BucketsStore:SetScoreBatchNoResultAsync(ids : {number}, prevScores : {number?}, newScores : {number})
    local operator = self:_ConstructOperator()
    operator:SetScoreBatchAsync(ids, prevScores, newScores)
end

function BucketsStore:SetScoreAsync(id : number, prevScore : number?, newScore : number) : (number, number)
    local prevRanks, newRanks = self:SetScoreBatchAsync({id}, {prevScore}, {newScore})
    return prevRanks[1], newRanks[1]
end

function BucketsStore:FindRankBatchAsync(ids : {number}, scores : {number}) : {number}
    local operator = self:_ConstructOperator()
    return operator:FindRankBatchAsync(ids, scores)
end

function BucketsStore:FindRankAsync(id : number, score : number) : {number}
    local ranks = self:FindRankBatchAsync({id}, {score})
    return ranks[1]
end

function BucketsStore:GetTopScoresAsync(limit : number) : {entry}
    local operator = self:_ConstructOperator()
    return operator:GetTopScoresAsync(limit)
end

function BucketsStore:GetBucketsAsync() : {{entry}}
    local operator = self:_ConstructOperator()
    return operator:GetBuckets()
end

function BucketsStore:_CopyAllData(sourceConfig : bucketsConfig, targetConfig : bucketsConfig)
    for i = 1, sourceConfig.numBuckets do
        local operator = BucketsOperator.New(self._name, sourceConfig)
        
        local leaderboard = operator:GetBucketAsync(operator:GetBucketKey(i))

        local ids = {}
        local scores = {}
        for _, entry in ipairs(leaderboard) do
            table.insert(ids, entry.id)
            table.insert(scores, entry.score)
        end

        local operator = BucketsOperator.New(self._name, targetConfig)
        operator:SetScoreBatchAsync(ids, {}, scores)

        local extraBytes = 1000 -- Add some extra bytes to be safe
        local readDelay = 60/(READ_THROUGHPUT_LIMIT_BYTES/(#leaderboard+extraBytes)) -- We are copying a lot of data so we need to throttle the loop
                                                                        -- to not hit the throughput limits
        local writeDelay = 60/(WRITE_THROUGHPUT_LIMIT_BYTES/(#leaderboard+extraBytes))
        local delay = math.max(readDelay, writeDelay)
        task.wait(delay)
    end
end

-- Remember that each identity is assigned to a bucket so increasing the number
-- of buckets will require a copy of ALL the leaderboard data to new buckets.
function BucketsStore:UpdateNumBucketsAsync(numBuckets : number)
    local prevMetadata = self._metadataStore:GetAsync(false)

    local newLine
    if prevMetadata.stagedLine  then
        newLine = prevMetadata.stagedLine+1 -- we tried a copy before but it never finished so use the next line to avoid starting from corrupted data.
    else
        newLine = prevMetadata.line+1
    end
    local newMetadata = {numBuckets = prevMetadata.numBuckets, line = prevMetadata.line, stagedLine=newLine, maxBucketSize = prevMetadata.maxBucketSize, version = prevMetadata.version}
    self._metadataStore:SetAsync(newMetadata)

    local prevConfig = {
        numBuckets = prevMetadata.numBuckets,
        maxBucketSize = prevMetadata.maxBucketSize,
        line = prevMetadata.line,
        version = prevMetadata.version
    }
    local newConfig = {
        numBuckets = numBuckets,
        maxBucketSize = prevMetadata.maxBucketSize,
        line = newLine,
        version = prevMetadata.version
    }

    self:_CopyAllData(prevConfig, newConfig)

    newMetadata.line = newMetadata.stagedLine
    newMetadata.stagedLine = nil
    newMetadata.numBuckets = numBuckets
    self._metadataStore:SetAsync(newMetadata)
end

return BucketsStore