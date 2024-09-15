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

function SequentialLeaderboard.New(data : string | {}, dataStructure : "table" | "string")
    local self = setmetatable({}, SequentialLeaderboard)
    
    if dataStructure == "table" then
        self._accessor = Leaderboard.defaultLeaderboardAccessor
    elseif dataStructure == "string" then
        self._accessor = Leaderboard.compressedLeaderboardAccessor
    else
        error("Invalid data structure for SequentialLeaderboard")
    end
    
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

function SequentialLeaderboard:Iterator()
    local index = 0
    
    return function()
        index = index + 1
        return self:GetIndex(index)
        
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
    return self._accessor.Get(self._data, index)
end

function SequentialLeaderboard:GetAll(): {entry}
    local result = {}
    for i = 1, self._accessor.Length(self._data) do
        table.insert(result, self._accessor.Get(self._data, i))
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
            return upper
        end
        upper = upper - 1
    end
    
    local lower = pos + 1
    local lowerValue = self._accessor.Get(self._data, lower)
    while lower <= self._accessor.Length(self._data) and lowerValue and lowerValue.score == score do
        if lowerValue.id == id then
            return lower
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

function TreeLeaderboard.New(data : AVL.typedef?)
    local self = setmetatable({}, TreeLeaderboard)
    
    self._avl = data or AVL.New()
    self._descending = true

    return self
end

function TreeLeaderboard:GetRaw()
    return self._avl
end

function TreeLeaderboard:Iterator() : () -> entry?
    local iter = self._avl:Iterator(self._descending)
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
    local node = self._avl:GetIndex(index, self._descending)
    return {id = node.Extra, score = node.Value}
end

function TreeLeaderboard:GetAll(): {entry}
    local result = {}
    for node in self._avl:Iterator(self._descending) do
        table.insert(result, {id = node.Extra, score = node.Value})
    end
    return result
end

function TreeLeaderboard:GetRank(id: string, score: number): number
    local _, rank = self._avl:Get(score, id)
    return rank
end

function TreeLeaderboard:GetInsertPos(score: number): number
    local pos = self._avl:GetInsertRank(score)
    if self._descending then
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
    if self._descending then
        prevRank = prevRank and self._avl:GetSize() - prevRank + 1 or nil
        newRank = self._avl:GetSize() - newRank + 1
    end
    return prevRank, newRank
end

function Leaderboard.New(data : any?, dataStructure : dataStructure)
    local self = setmetatable({}, Leaderboard)
    
    if dataStructure == "table" or dataStructure == "string" then
        self._implementation = SequentialLeaderboard.New(data, dataStructure)
    elseif dataStructure == "avl" then
        self._implementation = TreeLeaderboard.New(data)
    else
        error("Invalid data structure")
    end
    
    return self
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

function Leaderboard:Iterator() : () -> entry?
    return self._implementation:Iterator()
end

local base91Compressor = function(data : any) : string
    if not data then
        return
    end
    local t =  {}
    for i = 1,#data do
        t[i] = Leaderboard._CompressRecord(data[i].id, data[i].score)
        
    end
    return table.concat(t, "")
end

local base91Decompressor = function(v : string) : typedef
    if not v then
        return
    end
    local t = {}
    for i = 1, #v, Leaderboard.RECORD_SIZE do
        local id, score = Leaderboard._DecompressRecord(string.sub(v, i, i+Leaderboard.RECORD_SIZE-1))
        table.insert(t, {id = id, score = score})
    end
    return t
end

local avlBase91Compressor = function(data : AVL.typedef) : string
    if not data then
        return
    end
    local t = {}
    for node in data:Iterator() do
        table.insert(t, Leaderboard._CompressRecord(node.Value, node.Extra))
    end
    return table.concat(t, "")
end

local avlBase91Decompressor = function(v : string) : AVL.typedef
    if not v then
        return AVL.New()
    end
    local t = {}
    for i = 1, #v, Leaderboard.RECORD_SIZE do
        local id, score = Leaderboard._DecompressRecord(string.sub(v, i, i+Leaderboard.RECORD_SIZE-1))
        table.insert(t, {id, score})
    end

    local avl = AVL.FromOrderedArray(t)
    return avl
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
            self._decompress = base91Decompressor
        elseif dataStructure == "string" then -- string is always stored in base 91 so no need to compress.
            self._compress = function(data) return data end
            self._decompress = function(s) return s end
        elseif dataStructure == "avl" then
            self._compress = avlBase91Compressor
            self._decompress = avlBase91Decompressor
        end
    elseif compression == "none" then
        self._compress = function(data) return data end
        self._decompress = function(s) return s end
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
    
    return self._compress(leaderboard:GetRaw())
end

function LeaderboardCompressor:Decompress(s : string) : typedef
    if not s then
        return Leaderboard.New(nil, self._dataStructure)
    end
    local data = self._decompress(s)
    return Leaderboard.New(data, self._dataStructure)
end

function Leaderboard.GetMergedLeaderboards(leaderboards, limit) : {entry} 
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
        local iterator = leaderboards[i]:Iterator()
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
        local maxScore = nil
        local maxIndex = nil
        for i = 1, numLeaderboards do
            local entry = currentEntries[i]
            if entry then
                if not maxScore or entry.score > maxScore then
                    maxScore = entry.score
                    maxIndex = i
                elseif entry.score == maxScore then
                    -- Tie-breaker based on id if scores are equal
                    if entry.id < currentEntries[maxIndex].id then
                        maxIndex = i
                    end
                end
            end
        end

        if not maxIndex then
            break
        end

        table.insert(result, currentEntries[maxIndex])
        count = count + 1

        local nextEntry = iterators[maxIndex]()
        if nextEntry then
            currentEntries[maxIndex] = nextEntry
        else
            currentEntries[maxIndex] = nil
            activeIterators = activeIterators - 1
        end
    end

    return result
end

export type typedef = typeof(Leaderboard.New())

return Leaderboard