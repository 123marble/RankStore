local DataStoreService = game:GetService("DataStoreService")

local TimedCache = require(script.Parent.RankStore.timedCache)
local LeaderboardHelper = require(script.Parent.RankStore.leaderboardHelper)

local RankStore = {}
RankStore.__index = RankStore

local BUCKET_SIZE = 1000000
local BUCKET_METADATA_TTL_SECS = 60*60

math.randomseed()

type metadata = {
    numBuckets : number,
    line : number
}

type identityEntry = {
    score : number
}

-- Compression functions
local function encodeEntry(userId, score)
    return string.pack(">I3I3", userId, score)
end

local function decodeEntry(encodedEntry)
    local userId, score = string.unpack(">I3I3", encodedEntry)
    return {userId = userId, score = score}
end

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

function RankStore.GetRankStore(name : string, numBuckets : number)
    local self = setmetatable({}, RankStore)
    self._bucketStore = DataStoreService:GetDataStore(name .. "_BucketStore")

    self._metadataInitialised = false

    self.metadataCache = TimedCache.New(
        function()
            return self:_GetBucketStoreMetadataAsync()
        end, 
        BUCKET_METADATA_TTL_SECS
    ) :: TimedCache.TimedCache<metadata>  -- New buckets will not be picked up until the metadata cache expires.

    self._numBuckets = numBuckets
    return self
end

-- 2 GetAsync requests
function RankStore:SetScoreAsync(uniqueId, score)
    local identityKey = self:_GetIdentityStoreKey(uniqueId)
    local success, result = pcall(function()
        return self._bucketStore:UpdateAsync(identityKey, function(identity : identityEntry)
            identity = identity or {}
            local prevScore = identity.score
            identity.score = score
            return prevScore
        end)
    end)

    if not success then
        error("Failed to set score:", result)
    end

    local prevScore = result
    local bucketKey = self:_GetBucketKeyForId(uniqueId)

    local success, result, newRank = pcall(function()
        return self._bucketStore:UpdateAsync(bucketKey, function(leaderboard)
            leaderboard = leaderboard or {}

            local prevRank, newRank = LeaderboardHelper.Update(leaderboard, uniqueId, prevScore, score)
            return prevRank, newRank
        end)
    end)

    if not success then
        error("Failed to set score:", result)
    end
    local prevRank = result

    -- TODO: Need to return prevScore, prevRank, newScore, newRank
    return prevScore, prevRank, score, newRank
end

function RankStore:GetAllBucketsIteratorAsync(ignoreBucketKeys : {string?})
    local bucketKeys = self:_getAllBucketKeys()
    for _, bucketKey in ipairs(ignoreBucketKeys) do
        table.remove(bucketKeys, table.find(bucketKeys, bucketKey))
    end
    local index = 0
    local count = #bucketKeys

    return function()
        index = index + 1
        if index <= count then
            local bucketKey = bucketKeys[index]
            return bucketKey, self:_GetBucketAsync(bucketKey)
        end
    end
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
        error("Failed to get identity entry:", result)
    end

    local identityEntry = result
    local score = identityEntry.score

    local bucketKey = self:_GetBucketKeyForId(uniqueId)
    local leaderboard = self:_GetBucketAsync(bucketKey)
    local rank = LeaderboardHelper.GetRank(leaderboard, uniqueId, score)

    if not rank then
        -- TODO: This indicates a consistency violation between the identity store and the leaderboard store
        -- This should be corrected by inserting the score into the leaderboard in the bucket.
    end

    local rank = 0
    local score = 0
    for _, leaderboard in self:GetAllBucketsIteratorAsync(bucketKey) do
        local bucketRank = LeaderboardHelper.GetInsertPos(leaderboard, score)
        rank += bucketRank
    end
    return rank, score
end

function RankStore:GetTopScoresAsync(limit)
    local leaderboards = {}
    local indices = {}
    local topScores = {}

    -- Collect all leaderboards and initialize indices
    for _, leaderboard in self:GetAllBucketsIteratorAsync({}) do
        if #leaderboard > 0 then
            table.insert(leaderboards, leaderboard)
            table.insert(indices, 1)
        end
    end

    -- Merge top scores
    while #topScores < limit do
        local maxScore = -math.huge
        local maxIndex = nil

        -- Find the highest score among the current indices
        for i, leaderboard in ipairs(leaderboards) do
            if indices[i] <= #leaderboard and leaderboard[indices[i]].score > maxScore then
                maxScore = leaderboard[indices[i]].score
                maxIndex = i
            end
        end

        -- If we've exhausted all leaderboards, break
        if maxIndex == nil then
            break
        end

        -- Add the highest score to topScores and move to the next score in that leaderboard
        table.insert(topScores, leaderboards[maxIndex][indices[maxIndex]])
        indices[maxIndex] = indices[maxIndex] + 1
    end

    return topScores
end

function RankStore:_InitBucketStoreMetadataAsync()
    local success, result = pcall(
        function() 
            local metadata = self._bucketStore:UpdateAsync(self._bucketStoreMetadataKey, function(metadata)
                if metadata then
                if self._numBuckets ~= metadata.numBuckets then
                    error("Number of buckets does not match. To add a new bucket, use AddBucketAsync.")
                end
                else
                    metadata = {numBuckets = self._numBuckets, line = 1}
                end
                
                return metadata

            end)
            return metadata
        end
    )
    if not success then
        error("Failed to init bucket store metadata:", result)
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
        error("Failed to get bucket store metadata:", metadata)
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
    return "identity_" .. tostring(id)
end


function RankStore:_getBucketKeyAsync(index)
    local bucketKey = "line_" .. self.metadataCache:Get().line .. "_index_" .. index
    
    return bucketKey
end

function RankStore:_getRandomBucketIndexAsync(uniqueId : number)
    return uniqueId % self.metadataCache:Get().numBuckets + 1
end

-- If the metadataCache is expired then this function will yield.
function RankStore:_GetBucketKeyForId(uniqueId : number)
    local bucketIndex = self:_getRandomBucketIndexAsync(uniqueId)
    local bucketKey = self:_getBucketKeyAsync(bucketIndex)
    return bucketKey
end

function RankStore:_getAllBucketKeys()
    local bucketKeys = {}
    
    for i = 1, self._numBuckets do
        table.insert(bucketKeys, self:_getBucketKey(i))
    end
    
    return bucketKeys
end

function RankStore:_GetBucketAsync(bucketKey : number) : LeaderboardHelper.leaderboard
    local success, result = pcall(function()
        return self._bucketStore:GetAsync(bucketKey)
    end)

    if not success then
        error("Failed to get bucket:", tostring(result))
    end

    return result
end

return RankStore