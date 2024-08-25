--  ____             _     ____  _                 
-- |  _ \ __ _ _ __ | | __/ ___|| |_ ___  _ __ ___ 
-- | |_) / _` | '_ \| |/ /\___ \| __/ _ \| '__/ _ \
-- |  _ < (_| | | | |   <  ___) | || (_) | | |  __/
-- |_| \_\__,_|_| |_|_|\_\|____/ \__\___/|_|  \___|
--
--- @class RankStore
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

--- @type entry {id: string, rank: number, score: number}
--- @within RankStore
--- An array of strings, a number, or nil.
export type entry = {
    id: string,
    rank : number,
    score: number
}

--- @type setResult {prevRank: number, prevScore: number, newRank: number, newScore: number}
--- @within RankStore
--- An array of strings, a number, or nil.
export type setResult = {
    prevRank : number,
    prevScore : number,
    newRank : number,
    newScore : number
}

--[=[
Creates or retrieves a Rank Store with the provided name.
@param name -- Name of the RankStore
@param numBuckets -- The number of buckets to use
@param maxBucketSize -- Maximum number of entries in each bucket
@return RankStore
@yields
]=]
function RankStore.GetRankStore(name : string, numBuckets : number, maxBucketSize : number)
    local self = setmetatable({}, RankStore)
    self._name = name
    self._datastore = Shared.GetDataStore(name)

    self._metadataStore = MetadataStore.GetMetadataStore(name, numBuckets, maxBucketSize)
    self._bucketsStore = BucketsStore.GetBucketsStore(name, self._metadataStore)
    self._identityStore = IdentityStore.GetIdentityStore(name, self._metadataStore)
    
    return self
end

--[=[
Sets the score for the given id.
@param id -- The id of the entry. A number to uniquely identify the entry, typically a userId.
@param score -- The score to set
@yields
]=]
function RankStore:SetScoreAsync(id : number, score : number) : setResult
    local identityEntry = self._identityStore:Update(id, score)

    local prevRank, newRank = self._bucketsStore:SetScoreAsync(id, identityEntry.prevScore, score)

    return {prevRank = prevRank, prevScore = identityEntry.prevScore, newRank = newRank, newScore = score}
end

--[=[
Gets the entry for the given id.
@param id -- The id of the entry.
@yields
]=]
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

--[=[
Gets the top n scores.
@param n -- The number of scores to get
@return {entry}
@yields
]=]
function RankStore:GetTopScoresAsync(n : number) : {entry}
    return self._bucketsStore:GetTopScoresAsync(n)
end

--[=[
Clears all entries in the RankStore.

This actually just increments the keys used in the underlying DataStore so no data is actually deleted. However there is 
no support to rollback after calling this function at present.
@yields
]=]
function RankStore:ClearAsync()
    local prevMetadata = self._metadataStore:GetAsync()
    local newMetadata = {numBuckets = prevMetadata.numBuckets, line = prevMetadata.line + 1}
    self._metadataStore:SetAsync(newMetadata)
end

return RankStore