local BucketsStore = {}
BucketsStore.__index = BucketsStore

local Shared = require(script.Parent.shared)
local Leaderboard = require(script.Parent.leaderboard)
local MetadataStore = require(script.Parent.metadataStore)
local Buffer = require(script.Parent.buffer)
local CachedDataStore = require(script.Parent.cachedDataStore)
local Signal = require(game.ServerScriptService.Packages.goodsignal)

export type entry = Leaderboard.entry

type bucketsConfig = {
    numBuckets : number,
    maxBucketSize : number,
    line : number,
    version : number
}

export type compression = Leaderboard.compression
export type dataStructure = Leaderboard.dataStructure

local BucketsOperator = {}
BucketsOperator.__index = BucketsOperator

function BucketsOperator.New(
    datastore : CachedDataStore.typedef,
    config : bucketsConfig,
    parallel : boolean?,
    useCache : boolean?,
    dataStructure : dataStructure
)
    local self = setmetatable({}, BucketsOperator)

    self._config = config
    self._useCache = useCache == nil and true or useCache
    self._cacheUsedForWrite = false
    self._cacheUsedForRead = false
    self._datastore = datastore
    self._parallel = parallel == nil and true or parallel
    self._dataStructure = dataStructure

    return self
end

function BucketsOperator:WasCacheUsedForWrite() : boolean
    return self._cacheUsedForWrite
end

function BucketsOperator:WasCacheUsedForRead() : boolean
    return self._cacheUsedForRead
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
    self._cacheUsedForWrite = false

    for bucketKey, v in pairs(groupedIds) do
        
        local bucketIds, bucketPrevScores, bucketNewScores = table.unpack(v)

        local bucketPrevRanks, bucketNewRanks, _cacheUsedForWrite = self:_UpdateBucketBatchAsync(bucketKey, bucketIds, bucketPrevScores, bucketNewScores)
        self._cacheUsedForWrite = self._cacheUsedForWrite or _cacheUsedForWrite
        
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

function BucketsOperator:GetBucketsRaw() : {Leaderboard.typedef}
    local leaderboards = {}

    self:_MapGetBucketsAsync(function(_, _, leaderboard)
        if leaderboard:Length() > 0 then
            table.insert(leaderboards, leaderboard)
        end
    end, nil, self._parallel)

    return leaderboards
end

function BucketsOperator:GetTopScoresAsync(limit : number?) : Leaderboard.typedef
    local leaderboards = self:GetBucketsRaw()
    return Leaderboard.NewFromMerge(leaderboards, self._dataStructure, limit)
end

function BucketsOperator:GetBucketRawAsync(bucketKey : number) : Leaderboard.typedef
    local success, result, cacheUsedForRead = pcall(function()
        return self._datastore:GetAsync(bucketKey, self._useCache)
    end)

    if not success then
        error("Failed to get bucket: " .. tostring(result))
    end

    self._cacheUsedForRead = cacheUsedForRead
    local leaderboard = result
    return leaderboard
end

function BucketsOperator:_GetSetScoreBatchResult(
    ids : {number},
    prevScores : {number?},
    newScores : {number},
    primaryBucketPrevRanks : {number},
    primaryBucketNewRanks : {number}
) : ({number}, {number})
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
    local success, result, cacheWasUsed = pcall(function()
        return self._datastore:UpdateAsync(bucketKey, function(leaderboard : Leaderboard.typedef, isLocal)
            if leaderboard:Length() + #ids > math.floor(maxBucketSize/Leaderboard.RECORD_SIZE) then
                updateFailureReason = "Not enough space in bucket."
                return nil
            end
            
            for i, id in ipairs(ids) do
                local success, prevRank, newRank = pcall(function() return leaderboard:Update(id, prevScores[i], newScores[i]) end)
                if not success then
                    updateFailureReason = "Error occurred during UpdateAsync: " .. tostring(prevRank)
                    return nil
                end
                table.insert(newRanks, newRank)
                prevRanks[#newRanks] = prevRank
            end
            return leaderboard
        end, self._useCache)
    end)
    if not success or not result then
        error("Failed to update bucket " .. bucketKey .. ": " .. updateFailureReason)
    end

    return prevRanks, newRanks, cacheWasUsed
end

-- Intended to be used in combination with _MapGetBucketsAsync
local function _SumBucket(
    bucketsStore : {},
    bucketKey : string,
    leaderboard : Leaderboard.typedef,
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
                bucketRank = leaderboard:GetRank(id, scores[i])
            end
        else
            bucketRank = leaderboard:GetInsertPos(scores[i]) - 1
        end

        ranks[i] += bucketRank
    end
end

-- Intended to be used in combination with _MapGetBucketsAsync
local function _SumBucketChange(
    bucketsStore : {},
    bucketKey : string,
    leaderboard : Leaderboard.typedef, 
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

function BucketsOperator:_MapGetBucketsAsync(func : (bucketsStore : {}, bucketKey : string, leaderboard : Leaderboard.typedef, any...) -> any, ignoreKeys : {string}?, parallel : boolean?, ...)
    parallel = parallel or false
    local numCompleted = 0
    local completionSignal = Signal.new()

    local function runMap(bucketKey, ...)
        local leaderboard = self:GetBucketRawAsync(bucketKey)
        func(self, bucketKey, leaderboard, ...)
    end
    
    local bucketKeys = self:_GetAllBucketKeys(ignoreKeys)
    
    for _, bucketKey in ipairs(bucketKeys) do
        if parallel then
            task.spawn(function(...)
                runMap(bucketKey, ...)
                numCompleted += 1
                if numCompleted == #bucketKeys then
                    completionSignal:Fire()
                end
            end, ...)
        else
            runMap(bucketKey, ...)
        end
    end
    if parallel then
        if numCompleted < #bucketKeys then
            completionSignal:Wait()
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

local function FlushBuffer(bucketsStore, buf : {{number}})
    local ids, prevScores, newScores = {}, {}, {}
    for _, write in ipairs(buf) do
        local bufIds, bufPrevScores, bufNewScores = table.unpack(write)

        for i, id in ipairs(bufIds) do
            table.insert(ids, id)
            prevScores[#ids] = bufPrevScores[i]
            newScores[#ids] = bufNewScores[i]
        end
    end
    local bucketsOperator = BucketsOperator.New(bucketsStore._datastore, bucketsStore:_ConstructConfigFromMetadata(), true, false)
    bucketsOperator:SetScoreBatchAsync(ids, prevScores, newScores)
end

function BucketsStore.GetBucketsStore(
    name : string,
    metadataStore : MetadataStore.typedef,
    parallel : boolean,
    lazySaveTime : number,
    dataStructure : dataStructure,
    compression : compression
)
    local self = setmetatable({}, BucketsStore)

    self._name = name
    self._metadataStore = metadataStore
    self._parallel = parallel
    self._lazySaveTime = lazySaveTime
    if self._lazySaveTime == -1 then
        self._useCache = false
        self._lazySaveTime = nil
    else
        self._useCache = true
    end
    self._dataStructure = dataStructure
    self._compression = compression


    local compressor = function(leaderboard : Leaderboard.typedef) : string
        local c = Leaderboard.LeaderboardCompressor.New(self._dataStructure, self._compression)
        return c:Compress(leaderboard)
    end

    local decompressor = function(s : string) : Leaderboard.typedef -- we define this here becuse the cached data store will only decompress if
                                                                    -- the value was retrieved from the datastore and not the cache.
                                                                    -- It feels like compression could belong in the user defined UpdateAsync callback 
                                                                    -- but this would require the user to perform the smart decompression themselves.

        local c = Leaderboard.LeaderboardCompressor.New(self._dataStructure, self._compression)
        return c:Decompress(s)
    end
    
    self._datastore = CachedDataStore.New(Shared.GetDataStore(name), self._flushTime, compressor, decompressor)
    self._buf = Buffer.New(function(buf)
        FlushBuffer(self, buf)
    end, self._lazySaveTime)

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
    return BucketsOperator.New(self._datastore, self:_ConstructConfigFromMetadata(), self._parallel, self._useCache, self._dataStructure, self._compression)
end

function  BucketsStore:_CheckWriteBuffer(ids, prevScores, newScores, operator)
    if operator:WasCacheUsedForWrite() then
        self._buf:Write(ids, prevScores, newScores)
    end
end

function BucketsStore:FlushBuffer()
    self._buf:Flush()
end

function BucketsStore:SetScoreBatchAsync(ids : {number}, prevScores : {number?}, newScores : {number}) : ({number}, {number})
    local operator = self:_ConstructOperator()
    local prevRank, newRank = operator:SetScoreBatchWithResultAsync(ids, prevScores, newScores)
    self:_CheckWriteBuffer(ids, prevScores, newScores, operator)
    return prevRank, newRank
end

function BucketsStore:SetScoreBatchNoResultAsync(ids : {number}, prevScores : {number?}, newScores : {number})
    local operator = self:_ConstructOperator()
    operator:SetScoreBatchAsync(ids, prevScores, newScores)
    self:_CheckWriteBuffer(ids, prevScores, newScores, operator)
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
    return operator:GetTopScoresAsync(limit):GetAll()
end

function BucketsStore:GetBucketsAsync() : {{entry}}
    local operator = self:_ConstructOperator()
    local leaderboards = operator:GetBucketsRaw()
    local result = {}
    for _, leaderboard in ipairs(leaderboards) do
        table.insert(result, leaderboard:GetAll())
    end
    return result
end

function BucketsStore:_CopyAllData(sourceConfig : bucketsConfig, targetConfig : bucketsConfig)
    for i = 1, sourceConfig.numBuckets do
        local operator = BucketsOperator.New(self._datastore, sourceConfig)
        
        local leaderboard = operator:GetBucketRawAsync(operator:GetBucketKey(i))
        leaderboard = leaderboard:GetAll()

        local ids = {}
        local scores = {}
        for _, entry in ipairs(leaderboard) do
            table.insert(ids, entry.id)
            table.insert(scores, entry.score)
        end

        local operator = BucketsOperator.New(self._datastore, targetConfig)
        operator:SetScoreBatchAsync(ids, {}, scores)
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