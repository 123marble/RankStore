local DataStoreService = game:GetService("DataStoreService")

local TimedCache = require(script.Parent.RankStore.timedCache)
local LeaderboardHelper = require(script.Parent.RankStore.leaderboardHelper)
local Util = require(script.Parent.RankStore.util)

local RankStore = {}
RankStore.__index = RankStore

local BUCKET_METADATA_TTL_SECS = 60*60

type metadata = {
    numBuckets : number,
    maxBucketSize : number,
    line : number
}

type identityEntry = {
    score : number
}

-- Compression functions
-- local function encodeEntry(userId, score)
--     return string.pack(">I3I3", userId, score)
-- end

function RankStore.GetRankStore(name : string, numBuckets : number, maxBucketSize : number)
    local self = setmetatable({}, RankStore)
    self._bucketStore = DataStoreService:GetDataStore(name .. "_BucketStore")

    self._metadataInitialised = false
    self._bucketStoreMetadataKey = "metadata"

    self:_InitBucketStoreMetadataAsync(numBuckets, maxBucketSize)
    self._metadataCache = TimedCache.New(
        function()
            return self:_GetBucketStoreMetadataAsync() 
        end, 
        BUCKET_METADATA_TTL_SECS
    ) :: TimedCache.TimedCache<metadata>  -- Note that using a timed cache means that changes to the metadata on other servers will not take effect until the cache expires.
    return self
end

-- 2 GetAsync requests
function RankStore:SetScoreAsync(uniqueId, score)
    local identityKey = self:_GetIdentityStoreKey(uniqueId)
    local prevScore
    local success, result = pcall(function()
        return self._bucketStore:UpdateAsync(identityKey, function(identity : identityEntry)
            identity = identity or {}
            prevScore = identity.score
            identity.score = score
            return identity
        end)
    end)

    if not success then
        error("Failed to set score: " .. tostring(result))
    end

    local bucketKey = self:_GetBucketKeyForId(uniqueId)

    local prevRank, newRank
    local success, result = pcall(function()
        return self._bucketStore:UpdateAsync(bucketKey, function(leaderboard)
            leaderboard = leaderboard or {}

            prevRank, newRank = LeaderboardHelper.Update(leaderboard, uniqueId, prevScore, score)
            return leaderboard
        end)
    end)

    if not success then
        error("Failed to set score: " .. tostring(result))
    end

    -- TODO: This code is shared with GetEntryAsync. Consider refactoring.
    local bucketKeys = self:_GetAllBucketKeys({bucketKey})
    for _, bucketKey in ipairs(bucketKeys) do
        local leaderboard = self:_GetBucketAsync(bucketKey)
        local bucketRank = LeaderboardHelper.GetInsertPos(leaderboard, score) - 1
        if prevRank then
            prevRank += bucketRank
        end
        newRank += bucketRank
    end

    return {prevRank = prevRank, prevScore = prevScore, newRank = newRank, newScore = score}
end

-- 1. Get the score from the identity store
-- 2. Get the rank from the relevant bucket store using leaderboardHelper. If the identity is not found then this is a sign that there was a write failure
--      during the second datastore update in SetScoreAsync. This should be corrected by intserting the score into the leaderboard in the bucket.
-- 3. Get the rank placement in the other buckets
-- 4. Sum the ranks to get the final rank.
-- numBuckets + 1 GetAsync requests
function RankStore:GetEntryAsync(uniqueId : number)
    local identityKey = self:_GetIdentityStoreKey(uniqueId)
    local success, result = pcall(function()
        return self._bucketStore:GetAsync(identityKey) :: identityEntry
    end)

    if not success then
        error("Failed to get identity entry: " .. tostring(result))
    end

    local identityEntry = result
    local score = identityEntry.score

    local bucketKey = self:_GetBucketKeyForId(uniqueId)
    local leaderboard = self:_GetBucketAsync(bucketKey)
    local rank = LeaderboardHelper.GetRank(leaderboard, uniqueId, score)

    if not rank then
        -- TODO: This is a consistency violation between the identity store and the leaderboard store
        -- This should be corrected by inserting the score into the leaderboard in the bucket.
    end

    local bucketKeys = self:_GetAllBucketKeys({bucketKey})
    for _, bucketKey in ipairs(bucketKeys) do
        local leaderboard = self:_GetBucketAsync(bucketKey)
        local bucketRank = LeaderboardHelper.GetInsertPos(leaderboard, score) - 1
        rank += bucketRank
    end
    return {rank = rank, score = score}
end

function RankStore:GetTopScoresAsync(limit)
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

function RankStore:ClearAsync()
    local prevMetadata = self._metadataCache:Get()
    local newMetadata = {numBuckets = prevMetadata.numBuckets, line = prevMetadata.line + 1}
    self:_SetBucketStoreMetadataAsync(newMetadata)
    self._metadataCache:Clear()
end


function RankStore:_SetBucketStoreMetadataAsync(metadata : metadata)
    local success, result = pcall(function()
        return self._bucketStore:SetAsync(self._bucketStoreMetadataKey, metadata)
    end)

    if not success then
        error("Failed to update bucket store metadata: " .. tostring(result))
    end
end

function RankStore:_InitBucketStoreMetadataAsync(numBuckets : number, maxBucketSize : number) : metadata
    local success, result = pcall(function() 
        return self._bucketStore:UpdateAsync(self._bucketStoreMetadataKey, function(metadata)
            if metadata then
                if numBuckets ~= metadata.numBuckets then
                    error("Number of buckets does not match. To add a new bucket, use AddBucketAsync.")
                end
            else
                metadata = {numBuckets = numBuckets, maxBucketSize = maxBucketSize, line = 1}
            end
            return metadata
        end)
    end)

    if not success then
        error("Failed to init bucket store metadata: " .. tostring(result))
    end
    self._metadataInitialised = true

    local metadata = result
    return metadata
end

function RankStore:_RetrieveBucketStoreMetadataAsync()
    local success, metadata = pcall(function()
        return self._bucketStore:GetAsync(self._bucketStoreMetadataKey)
    end)
    
    if not success then
        error("Failed to get bucket store metadata: " .. tostring(metadata))
    end
    
    return metadata
end

function RankStore:_GetBucketStoreMetadataAsync() : metadata
    if not self._metadataInitialised then
        return self:_InitBucketStoreMetadataAsync()
    else
        return self:_RetrieveBucketStoreMetadataAsync()
    end
end


function RankStore:_GetIdentityStoreKey(id : number)
    return "identity_" .. tostring(id) .. "_line_" .. self._metadataCache:Get().line
end


function RankStore:_GetBucketKeyAsync(index)
    local bucketKey = "bucket_line_" .. self._metadataCache:Get().line .. "_index_" .. index
    
    return bucketKey
end

function RankStore:_getRandomBucketIndexAsync(uniqueId : number)
    return uniqueId % self._metadataCache:Get().numBuckets + 1
end

-- If the metadataCache is expired then this function will yield.
function RankStore:_GetBucketKeyForId(uniqueId : number)
    local bucketIndex = self:_getRandomBucketIndexAsync(uniqueId)
    local bucketKey = self:_GetBucketKeyAsync(bucketIndex)
    return bucketKey
end

function RankStore:_GetAllBucketKeys(ignoreIndexes : {number}?)
    local ignoreIndexes = ignoreIndexes or {}
    local bucketKeys = {}
    
    for i = 1, self._metadataCache:Get().numBuckets do
        if not table.find(ignoreIndexes, i) then
            table.insert(bucketKeys, self:_GetBucketKeyAsync(i))
        end
    end
    
    return bucketKeys
end

function RankStore:_GetBucketAsync(bucketKey : number) : LeaderboardHelper.leaderboard
    local success, result = pcall(function()
        return self._bucketStore:GetAsync(bucketKey)
    end)

    if not success then
        error("Failed to get bucket: " .. tostring(result))
    end

    if not result then
        return {}
    end

    return result
end

return RankStore