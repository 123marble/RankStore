local DataStoreService = game:GetService("DataStoreService")

local TimedCache = require(script.Parent.RankStore.timedCache)

local RankStore = {}
RankStore.__index = RankStore

local BUCKET_SIZE = 1000000
local BUCKET_METADATA_TTL_SECS = 60*60

math.randomseed()

type metadata = {
    numBuckets : number,
    line : number
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

    self._bucketKeyPrefix = name .. "_Bucket_"
    self._numBuckets = numBuckets
    return self
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

function RankStore:_getBucketKeyAsync(index)
    local bucketKey = self._bucketKeyPrefix .. "_line_" .. self.metadataCache:Get().line .. "_index_" .. index
    
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

function RankStore:SetScoreAsync(uniqueId, score)
    local bucketKey = self:_GetBucketKeyForId(uniqueId)

    local success, result = pcall(function()
        return self._bucketStore:UpdateAsync(bucketKey, function(leaderboard)
            leaderboard = leaderboard or {}

            -- TODO: Need to find existing entry and remove if it exists.
            local insertIndex = binarySearch(leaderboard, score)

            table.insert(leaderboard, insertIndex, encodeEntry(uniqueId, score))
        end)
    end)

    if not success then
        error("Failed to set score:", result)
    end

    return result
end

function RankStore:_GetEntryInBucketAsync(scoreId : number, score : number, bucketKey : number)

    local success, result = pcall(function()
        return self._bucketStore:GetAsync(bucketKey)
    end)

    if not success then
        error("Failed to get rank in bucket:", result)
    end

    -- TODO: If the the score is found in the bucket then we need to check if the scoreId
    -- matches so that the rank is not offset.
    local rank = binarySearch(result, score)

    return rank
end

function RankStore:GetEntry(uniqueId : number)
    local bucketKey = self:_GetBucketKeyForId(uniqueId)

    local bucketKeys = self:_getAllBucketKeys()
    table.remove(bucketKeys, table.find(bucketKeys, bucketKey))

    local rank = 0
    local score = 0
    for i, bucketKey in ipairs(bucketKeys) do
        local success, result, bucketScore = pcall(function()
            return self:_GetEntryInBucketAsync(uniqueId, bucketKey)
        end)

        if not success then
            error("Failed to get score from bucket " .. tostring(i) .. ": " .. tostring(result))
        end

        local bucketRank = result

        rank += bucketRank
        score = bucketScore or score
    end
    return rank, score
end

function RankStore:SetScoreTemp(uniqueId, score)
    local success, metadata = pcall(function()
        return self._bucketMetadataStore:GetAsync("metadata") or {firstBucket = 1, currentBucket = 1}
    end)
    
    if not success then
        warn("Failed to get bucket metadata:", metadata)
        return
    end
    
    local currentBucketKey = self._bucketKeyPrefix .. metadata.currentBucket
    local success, currentBucket = pcall(function()
        return self._leaderboardStore:GetAsync(currentBucketKey) or ""
    end)
    
    if not success then
        warn("Failed to get current bucket:", currentBucket)
        return
    end
    
    -- Remove existing entry for this user, if any
    local newBucket = ""
    local i = 1
    while i <= #currentBucket do
        local entryUserId, entryScore = string.unpack(">I3I3", currentBucket, i)
        if entryUserId ~= userId then
            newBucket = newBucket .. string.sub(currentBucket, i, i + 5)
        end
        i = i + 6
    end
    currentBucket = newBucket
    
    -- Insert new score
    local insertIndex = binarySearch(currentBucket, score)
    local encodedEntry = encodeEntry(userId, score)
    currentBucket = currentBucket:sub(1, (insertIndex - 1) * 6) .. 
                    encodedEntry .. 
                    currentBucket:sub(insertIndex * 6 + 1)
    
    -- Check if bucket is full
    if #currentBucket > BUCKET_SIZE * 6 then
        metadata.currentBucket = metadata.currentBucket + 1
        currentBucketKey = self._bucketKeyPrefix .. metadata.currentBucket
        local overflowEntry = currentBucket:sub(-6)
        currentBucket = currentBucket:sub(1, -7)  -- Remove overflow entry
        
        -- Save overflow entry to new bucket
        pcall(function()
            self._leaderboardStore:SetAsync(currentBucketKey, overflowEntry)
        end)
    end
    
    -- Save updated bucket and metadata
    pcall(function()
        self._leaderboardStore:SetAsync(self._bucketKeyPrefix .. metadata.currentBucket, currentBucket)
        self._bucketMetadataStore:SetAsync("metadata", metadata)
    end)
end

function RankStore:findRank(userId, score)
    local success, metadata = pcall(function()
        return self._bucketMetadataStore:GetAsync("metadata")
    end)
    
    if not success or not metadata then
        warn("Failed to get bucket metadata:", metadata)
        return nil
    end
    
    local totalRank = 0
    
    for bucketIndex = metadata.firstBucket, metadata.currentBucket do
        local bucketKey = self._bucketKeyPrefix .. bucketIndex
        local success, bucket = pcall(function()
            return self._leaderboardStore:GetAsync(bucketKey)
        end)
        
        if not success or not bucket then
            warn("Failed to get bucket:", bucketKey)
            return nil
        end
        
        local insertIndex = binarySearch(bucket, score)
        totalRank = totalRank + insertIndex - 1
        
        -- If we find the user in this bucket, we can stop searching
        for i = insertIndex, #bucket / 6 do
            local entryUserId, entryScore = string.unpack(">I3I3", bucket, (i - 1) * 6 + 1)
            if entryUserId == userId then
                return totalRank + i
            end
        end
    end
    
    return nil  -- User not found
end

function RankStore:getTopScores(limit)
    local success, metadata = pcall(function()
        return self._bucketMetadataStore:GetAsync("metadata")
    end)
    
    if not success or not metadata then
        warn("Failed to get bucket metadata:", metadata)
        return {}
    end
    
    local topScores = {}
    local remaining = limit
    
    for bucketIndex = metadata.firstBucket, metadata.currentBucket do
        if remaining <= 0 then break end
        
        local bucketKey = self._bucketKeyPrefix .. bucketIndex
        local success, bucket = pcall(function()
            return self._leaderboardStore:GetAsync(bucketKey)
        end)
        
        if not success or not bucket then
            warn("Failed to get bucket:", bucketKey)
            return topScores
        end
        
        for i = 1, #bucket, 6 do
            if remaining <= 0 then break end
            local entry = decodeEntry(bucket:sub(i, i + 5))
            table.insert(topScores, entry)
            remaining = remaining - 1
        end
    end
    
    return topScores
end

return RankStore