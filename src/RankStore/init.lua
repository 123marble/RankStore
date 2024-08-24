local IdentityStore = require(script.Parent.RankStore.identityStore)
local BucketsStore = require(script.Parent.RankStore.bucketsStore)
local MetadataStore = require(script.Parent.RankStore.metadataStore)
local Shared = require(script.Parent.RankStore.shared)

local RankStore = {}
RankStore.__index = RankStore

-- Compression functions
-- local function encodeEntry(userId, score)
--     return string.pack(">I3I3", userId, score)
-- end

export type entry = {
    id: string,
    rank : number,
    score: number
}

export type setResult = {
    prevRank : number,
    prevScore : number,
    newRank : number,
    newScore : number
}

function RankStore.GetRankStore(name : string, numBuckets : number, maxBucketSize : number)
    local self = setmetatable({}, RankStore)
    self._name = name
    self._datastore = Shared.GetDataStore(name)

    self._metadataStore = MetadataStore.GetMetadataStore(name, numBuckets, maxBucketSize)
    self._bucketsStore = BucketsStore.GetBucketsStore(name, self._metadataStore)
    self._identityStore = IdentityStore.GetIdentityStore(name, self._metadataStore)
    
    return self
end

-- 2 UpdateAsync requests
function RankStore:SetScoreAsync(id : number, score : number)
    local identityEntry = self._identityStore:Update(id, score)

    local prevRank, newRank = self._bucketsStore:SetScoreAsync(id, identityEntry.prevScore, score)

    return {prevRank = prevRank, prevScore = identityEntry.prevScore, newRank = newRank, newScore = score}
end

-- 1. Get the score from the identity store
-- 2. Get the rank from the relevant bucket store using leaderboardHelper. If the identity is not found then this is a sign that there was a write failure
--      during the second datastore update in SetScoreAsync. This should be corrected by intserting the score into the leaderboard in the bucket.
-- 3. Get the rank placement in the other buckets
-- 4. Sum the ranks to get the final rank.
-- numBuckets + 1 GetAsync requests
function RankStore:GetEntryAsync(id : number) : entry
    local identityEntry = self._identityStore:Get(id)

    if not identityEntry then
        warn("Attempted to get entry for non-existent id:", tostring(id))
        return nil
    end

    local rank = self._bucketsStore:FindRankAsync(id, identityEntry.currentScore)
    if not rank then  -- This is a consistency violation between the identity store and the leaderboard store
                        -- This should be corrected by inserting the score into the leaderboard in the bucket.
        local _, newRank = self._bucketsStore:SetScoreAsync(id, identityEntry.prevScore, identityEntry.currentScore)

        -- If the above failed because prevScore couldn't be found then this means that the identity store write
        -- succeeded multiple times but the bucketsStore write failed multiple times. This is likely a rare occurrence but
        -- the issue of not having transaction atomicity in SetScoreAsync is showing here. In this case, we
        -- can iterate sequentially through all entries in the bucket to find a remove the player's previous
        -- score
        -- TODO: Implement the above.
        rank = newRank
    end
    
    return {id = id, rank = rank, score = identityEntry.currentScore}
end

function RankStore:GetTopScoresAsync(limit : number)
    return self._bucketsStore:GetTopScoresAsync(limit)
end

function RankStore:ClearAsync()
    local prevMetadata = self._metadataStore:GetAsync()
    local newMetadata = {numBuckets = prevMetadata.numBuckets, line = prevMetadata.line + 1}
    self._metadataStore:SetAsync(newMetadata)
end

return RankStore