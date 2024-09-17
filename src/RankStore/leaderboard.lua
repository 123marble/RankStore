-- Helper module for managing a leaderboard.
-- Assumes that you always know the score of the user you are updating because
-- binarySearch can be used to make table updates, which are O(log n).
local Leaderboard = {}
Leaderboard.__index = Leaderboard

local Utf8Compress = require(script.Parent.utf8Compress)
local Util = require(script.Parent.util)
local AVL = require(script.Parent.avl)

export type entry = {
    id: string,
    score: number
}

export type leaderboardAccessor = {
    Get: (leaderboard: string, index: number) -> entry,
    Update: (leaderboard: string, oldIndex: number, newIndex: number, entry: entry) -> string,
    Insert: (leaderboard: string, index: number, entry: entry) -> string,
    Remove: (leaderboard: string, index: number) -> string,
    Length: (leaderboard: string) -> number
}

local ID_ENCODE_LENGTH = 5 -- userids are 10 characters long currently https://devforum.roblox.com/t/userids-are-going-over-32-bit-on-december-7th/903982
                            -- 5 bytes gives us 2^40 which gives leeway for the roblox playerbase to continue to grow.
local SCORE_ENCODE_LENGTH = 4
local RECORD_SIZE = ID_ENCODE_LENGTH + SCORE_ENCODE_LENGTH
Leaderboard.ID_ENCODE_LENGTH = ID_ENCODE_LENGTH
Leaderboard.SCORE_ENCODE_LENGTH = SCORE_ENCODE_LENGTH
Leaderboard.RECORD_SIZE = RECORD_SIZE

function Leaderboard._CompressRecord(id : number, score : number) : string
    return Utf8Compress.CompressInt(id, ID_ENCODE_LENGTH) .. Utf8Compress.CompressInt(score, SCORE_ENCODE_LENGTH)
end

function Leaderboard._DecompressRecord(utf8 : string) : string
    local id = Utf8Compress.DecompressInt(string.sub(utf8, 1, ID_ENCODE_LENGTH), ID_ENCODE_LENGTH)
    local score = Utf8Compress.DecompressInt(string.sub(utf8, ID_ENCODE_LENGTH + 1, ID_ENCODE_LENGTH + SCORE_ENCODE_LENGTH), SCORE_ENCODE_LENGTH)
    return id, score
end

Leaderboard.compressedLeaderboardAccessor = {
    New = function()
        return ""
    end,
    Get = function(leaderboard : string, index : number)
        if index < 1 or index > #leaderboard / RECORD_SIZE then
            return nil
        end
        local startIndex = (index - 1) * RECORD_SIZE + 1
        local endIndex = startIndex + RECORD_SIZE - 1
        local id, score = Leaderboard._DecompressRecord(string.sub(leaderboard, startIndex, endIndex))
        return {id = id, score = score}
    end,
    Update = function(leaderboard : string, oldIndex : number, newIndex : number, entry : entry)
        local packedEntry = Leaderboard._CompressRecord(entry.id, entry.score)
        if oldIndex < newIndex then
            return string.sub(leaderboard, 1, (oldIndex-1)*RECORD_SIZE) ..
                string.sub(leaderboard, oldIndex*RECORD_SIZE + 1, newIndex*RECORD_SIZE) ..
                packedEntry ..
                string.sub(leaderboard, newIndex*RECORD_SIZE + 1)
        elseif oldIndex > newIndex then
            return string.sub(leaderboard, 1, (newIndex-1)*RECORD_SIZE) ..
                packedEntry ..
                string.sub(leaderboard, (newIndex-1)*RECORD_SIZE + 1, (oldIndex-1)*RECORD_SIZE) ..
                string.sub(leaderboard, oldIndex*RECORD_SIZE + 1)
        else
            return string.sub(leaderboard, 1, (newIndex-1)*RECORD_SIZE) ..
                packedEntry ..
                string.sub(leaderboard, newIndex*RECORD_SIZE + 1)
        end
    end,
    Insert = function(leaderboard : string, index : number, entry : entry)
        local packedEntry = Leaderboard._CompressRecord(entry.id, entry.score)
        
        local val = string.sub(leaderboard, 1, (index-1)*RECORD_SIZE) .. 
            packedEntry .. 
            string.sub(leaderboard, (index-1)*RECORD_SIZE + 1)

        return val
    end,
    Remove = function(leaderboard : string, index : number)
        return string.sub(leaderboard, 1, (index-1)*RECORD_SIZE) .. 
            string.sub(leaderboard, index*RECORD_SIZE + 1)
    end,
    Length = function(leaderboard : string)
        return #leaderboard / RECORD_SIZE
    end
}

Leaderboard.defaultLeaderboardAccessor = {
    New = function()
        return {}
    end,
    Get = function(leaderboard : {entry}, index : number)
        return leaderboard[index]
    end,
    Update = function(leaderboard : {entry}, oldIndex : number, newIndex : number, entry : entry)
        table.remove(leaderboard, oldIndex)
        table.insert(leaderboard, newIndex, entry)
        return leaderboard
    end,
    Insert = function(leaderboard : {entry}, index : number, entry : entry)
        table.insert(leaderboard, index, entry)
        return leaderboard
    end,
    Remove = function(leaderboard : {entry}, index : number)
        table.remove(leaderboard, index)
        return leaderboard
    end,
    Length = function(leaderboard : {entry})
        return #leaderboard
    end
}

export type dataStructure = "table" | "string" | "avl"

local SequentialLeaderboard = {}
SequentialLeaderboard.__index = SequentialLeaderboard

function SequentialLeaderboard.New(data : string | {}, dataStructure : "table" | "string", ascending : boolean?)
    local self = setmetatable({}, SequentialLeaderboard)
    
    if dataStructure == "table" then
        self._accessor = Leaderboard.defaultLeaderboardAccessor
    elseif dataStructure == "string" then
        self._accessor = Leaderboard.compressedLeaderboardAccessor
    else
        error("Invalid data structure for SequentialLeaderboard")
    end
    
    self._ascending = ascending or false
    
    if data then
        self._data = data
    else
        self:GenerateEmpty()
    end
    
    return self
end

function SequentialLeaderboard:GetRaw()
    return self._data
end

function SequentialLeaderboard:Length(): number
    return self._accessor.Length(self._data)
end

function SequentialLeaderboard:Iterator(ascending : boolean?)
    ascending = (ascending == nil) and self._ascending or ascending
    local index = 0
    local length = self:Length()

    return function()
        index = index + 1
        local actualIndex = ascending and (length - index + 1) or index
        if actualIndex >= 1 and actualIndex <= length then
            return self:GetIndex(index)
        else
            return nil
        end
    end
end
 
function SequentialLeaderboard:GenerateEmpty()
    self._data = self._accessor.New()
end

function SequentialLeaderboard:BinarySearch(score)
    local left, right = 1, self._accessor.Length(self._data)
    while left <= right do
        local mid = math.floor((left + right) / 2)
        if self._accessor.Get(self._data, mid).score == score then
            return mid
        elseif self._accessor.Get(self._data, mid).score < score then
            right = mid - 1
        else
            left = mid + 1
        end
    end
    return left
end

function SequentialLeaderboard:GetIndex(index : number): entry
    local length = self:Length()
    local actualIndex = self._ascending and (length - index + 1) or index
    return self._accessor.Get(self._data, actualIndex)
end

function SequentialLeaderboard:GetAll(): {entry}
    local result = {}
    for entry in self:Iterator() do
        table.insert(result, entry)
    end
    return result
end

function SequentialLeaderboard:GetRank(id: string, score: number): number
    if not self._data or self._accessor.Length(self._data) == 0 then
        return nil
    end

    local pos = self:BinarySearch(score)

    local upper = pos
    local upperValue = self._accessor.Get(self._data, upper)
    while upper >= 1 and upperValue and upperValue.score == score do
        if upperValue.id == id then
            local rank = upper
            if self._ascending then
                rank = self:Length() - upper + 1
            end
            return rank
        end
        upper = upper - 1
    end
    
    local lower = pos + 1
    local lowerValue = self._accessor.Get(self._data, lower)
    while lower <= self._accessor.Length(self._data) and lowerValue and lowerValue.score == score do
        if lowerValue.id == id then
            local rank = lower
            if self._ascending then
                rank = self:Length() - lower + 1
            end
            return rank
        end
        lower = lower + 1
    end
    
    return nil
end

function SequentialLeaderboard:GetInsertPos(score: number): number
    return self:BinarySearch(score)
end

function SequentialLeaderboard:Remove(id: string, score: number): number
    local rank = self:GetRank(id, score)
    if rank ~= -1 then
        self._data = self._accessor.Remove(self._data, rank)
    end
    return rank
end

function SequentialLeaderboard:Update(id: string, prevScore: number?, newScore: number): (number, number)
    local prevRank = nil
    local newRank = self:GetInsertPos(newScore)
    local entry = {id = id, score = newScore}
    if prevScore then
        prevRank = self:GetRank(id, prevScore)
        if prevRank < newRank then
            newRank = newRank - 1
        end
        self._data = self._accessor.Update(self._data, prevRank, newRank, entry)
    else
        self._data = self._accessor.Insert(self._data, newRank, entry)
    end
    
    return prevRank, newRank
end

local TreeLeaderboard = {}
TreeLeaderboard.__index = TreeLeaderboard

function TreeLeaderboard.New(data : AVL.typedef?, ascending : boolean)
    local self = setmetatable({}, TreeLeaderboard)
    
    self._avl = data or AVL.New()
    self._ascending = ascending or false

    return self
end

function TreeLeaderboard:GetRaw()
    return self._avl
end

function TreeLeaderboard:Iterator(ascending : boolean?) : () -> entry?
    ascending = (ascending == nil) and self._ascending or ascending
    local iter = self._avl:Iterator(not ascending)
    return function()
        local node = iter()
        if node then
            return {id = node.Extra, score = node.Value}
        end
    end
end

function TreeLeaderboard:Length(): number
    return self._avl:GetSize()
end

function TreeLeaderboard:GenerateEmpty()
    self._avl = AVL.New()
end

function TreeLeaderboard:GetIndex(index : number): entry
    local size = self._avl:GetSize()
    local actualIndex = not self._ascending and (size - index + 1) or index
    local node = self._avl:GetIndex(actualIndex)
    return {id = node.Extra, score = node.Value}
end

function TreeLeaderboard:GetAll(): {entry}
    local result = {}
    for entry in self:Iterator() do
        table.insert(result, entry)
    end
    return result
end

function TreeLeaderboard:GetRank(id: string, score: number): number
    local _, rank = self._avl:Get(score, id)
    if not self._ascending then
        rank = self._avl:GetSize() - rank + 1
    end
    return rank
end

function TreeLeaderboard:GetInsertPos(score: number): number
    local pos = self._avl:GetInsertRank(score)
    if not self._ascending then
        pos = self._avl:GetSize() - pos + 2
    end
    return pos
end

function TreeLeaderboard:Remove(id: string, score: number): number
    return self._avl:Remove(score, id)
end

function TreeLeaderboard:Update(id: string, prevScore: number?, newScore: number): (number, number)
    local avlPrevRank
    if prevScore then
        local node, rank = self._avl:Remove(prevScore, id)
        if not node then
            error("Could not find previous score for id " .. id)
        end
        avlPrevRank = rank
    end
    local _, avlNewRank = self._avl:Insert(newScore, id)

    local prevRank, newRank = avlPrevRank, avlNewRank
    if not self._ascending then
        prevRank = prevRank and self._avl:GetSize() - prevRank + 1 or nil
        newRank = self._avl:GetSize() - newRank + 1
    end
    return prevRank, newRank
end

function Leaderboard.New(data : any?, dataStructure : dataStructure, ascending : boolean?)
    local self = setmetatable({}, Leaderboard)
    ascending = ascending or false
    if dataStructure == "table" or dataStructure == "string" then
        self._implementation = SequentialLeaderboard.New(data, dataStructure, ascending)
    elseif dataStructure == "avl" then
        self._implementation = TreeLeaderboard.New(data, ascending)
    else
        error("Invalid data structure")
    end
    
    return self
end

function Leaderboard:SetAscending(ascending : boolean)
    self._implementation._ascending = ascending
end

function Leaderboard:GetRaw()
    return self._implementation:GetRaw()
end

function Leaderboard:Length(): number
    return self._implementation:Length()
end

function Leaderboard:GenerateEmpty()
    self._implementation:GenerateEmpty()
end

function Leaderboard:GetIndex(index : number): entry
    return self._implementation:GetIndex(index)
end

function Leaderboard:GetAll(): {entry}
    return self._implementation:GetAll()
end

function Leaderboard:GetRank(id: string, score: number): number
    return self._implementation:GetRank(id, score)
end

function Leaderboard:GetInsertPos(score: number): number
    return self._implementation:GetInsertPos(score)
end

function Leaderboard:Remove(id: string, score: number): number
    return self._implementation:Remove(id, score)
end

function Leaderboard:Update(id: string, prevScore: number?, newScore: number): (number, number)
    return self._implementation:Update(id, prevScore, newScore)
end

function Leaderboard:Iterator(ascending : boolean?) : () -> entry?
    return self._implementation:Iterator(ascending)
end

local base91Compressor = function(leaderboard : typedef) : string
    if not leaderboard then
        return
    end
    local t =  {}
    for entry in leaderboard:Iterator(true) do -- Remember the approach taken is to iterate retrieval methods in reverse for descending leaderboards
                                                -- as opposed to changing the actual storage order, so we must always store in ascending order.
        table.insert(t, Leaderboard._CompressRecord(entry.id, entry.score))
    end
    return table.concat(t, "")
end

local tableBase91Decompressor = function(v : string) : typedef
    if not v then
        return
    end
    local t = {}
    for i = 1, #v, Leaderboard.RECORD_SIZE do
        local id, score = Leaderboard._DecompressRecord(string.sub(v, i, i+Leaderboard.RECORD_SIZE-1))
        table.insert(t, {id = id, score = score})
    end
    return Leaderboard.New(t, "table")
end

local stringBase91Decompressor = function(v : string) : typedef
    return Leaderboard.New(v, "string")
end

local avlBase91Decompressor = function(v : string) : AVL.typedef
    if not v then
        return AVL.New()
    end
    local t = {}
    for i = 1, #v, Leaderboard.RECORD_SIZE do
        local id, score = Leaderboard._DecompressRecord(string.sub(v, i, i+Leaderboard.RECORD_SIZE-1))
        table.insert(t, {score, id})
    end
    local avl = AVL.FromOrderedArray(t, true)
    return Leaderboard.New(avl, "avl")
end

export type compression = "base91" | "none"

local LeaderboardCompressor = {}
Leaderboard.LeaderboardCompressor = LeaderboardCompressor
LeaderboardCompressor.__index = LeaderboardCompressor

function LeaderboardCompressor.New(dataStructure : dataStructure, compression : compression)
    local self = setmetatable({}, LeaderboardCompressor)
    self._dataStructure = dataStructure
    self._compression = compression
    
    if compression == "base91" then
        if dataStructure == "table" then
            self._compress = base91Compressor
            self._decompress = tableBase91Decompressor
        elseif dataStructure == "string" then 
            self._compress = function(leaderboard) return leaderboard:GetRaw() end -- string is always stored in base 91 so no need to compress.
            self._decompress = stringBase91Decompressor
        elseif dataStructure == "avl" then
            self._compress = base91Compressor
            self._decompress = avlBase91Decompressor
        end
    elseif compression == "none" then
        self._compress = function(leaderboard) return leaderboard:GetRaw() end
        self._decompress = function(s) return Leaderboard.New(s, self._dataStructure) end
    else
        error("Invalid compression type", compression)
    end
    if not self._compress or not self._decompress then
        error("Compression type not implemented for the leaderboard data structure.")
    end
    return self
end

function LeaderboardCompressor:Compress(leaderboard : typedef) : string
    if not leaderboard then
        return
    end
    
    return self._compress(leaderboard)
end

function LeaderboardCompressor:Decompress(s : string) : typedef
    if not s then
        return Leaderboard.New(nil, self._dataStructure)
    end
    return self._decompress(s)
end

function Leaderboard.GetMergedLeaderboards(leaderboards, limit, ascending) : {entry} 
    -- TODO: The code structure could be improved by moving this method to leaderboard class.
    -- E.g. a Leaderboard.NewFromMerge(leaderboards, limit) : typedef method. The current issue is that
    -- there must be a method to efficiently instantiate the leaderboard from an ordered list of entries.
    -- This method currently circumvents this by simply returning type {entry}.
    local result = {}
    local numLeaderboards = #leaderboards
    local iterators = {}
    local currentEntries = {}
    local activeIterators = 0

    for i = 1, numLeaderboards do
        local iterator = leaderboards[i]:Iterator(ascending)
        iterators[i] = iterator
        local entry = iterator()
        if entry then
            currentEntries[i] = entry
            activeIterators = activeIterators + 1
        else
            currentEntries[i] = nil
        end
    end

    local count = 0
    limit = limit or math.huge  -- Use unlimited limit if not specified

    while activeIterators > 0 and count < limit do
        local bestScore = nil
        local bestIndex = nil
        for i = 1, numLeaderboards do
            local entry = currentEntries[i]
            if entry then
                if not bestScore or (ascending and entry.score < bestScore) or (not ascending and entry.score > bestScore) then
                    bestScore = entry.score
                    bestIndex = i
                elseif entry.score == bestScore then
                    -- Tie-breaker based on id if scores are equal
                    if (ascending and entry.id < currentEntries[bestIndex].id) or (not ascending and entry.id > currentEntries[bestIndex].id) then
                        bestIndex = i
                    end
                end
            end
        end

        if not bestIndex then
            break
        end

        table.insert(result, currentEntries[bestIndex])
        count = count + 1

        local nextEntry = iterators[bestIndex]()
        if nextEntry then
            currentEntries[bestIndex] = nextEntry
        else
            currentEntries[bestIndex] = nil
            activeIterators = activeIterators - 1
        end
    end

    return result
end

export type typedef = typeof(Leaderboard.New())

return Leaderboard