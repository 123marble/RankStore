-- Helper module for managing a leaderboard.
-- Assumes that you always know the score of the user you are updating because
-- binarySearch can be used to make table updates, which are O(log n).
local Leaderboard = {}
Leaderboard.__index = Leaderboard

local Utf8Compress = require(script.Parent.utf8Compress)
local Util = require(script.Parent.util)

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
    local id = Utf8Compress.DecompressInt(utf8Sub(utf8, 1, ID_ENCODE_LENGTH), ID_ENCODE_LENGTH)
    local score = Utf8Compress.DecompressInt(utf8Sub(utf8, ID_ENCODE_LENGTH + 1, ID_ENCODE_LENGTH + SCORE_ENCODE_LENGTH), SCORE_ENCODE_LENGTH)
    return id, score
end

function utf8Sub(str: string, i : number, j : number?) 
    if j then
        return string.sub(str, utf8.offset(str, i), utf8.offset(str, j+1)-1)
    else 
        return string.sub(str, utf8.offset(str, i))
    end
end

Leaderboard.compressedLeaderboardAccessor = {
    New = function()
        return ""
    end,
    Get = function(leaderboard : string, index : number)
        if index < 1 or index > utf8.len(leaderboard) / RECORD_SIZE then
            return nil
        end
        local startIndex = (index - 1) * RECORD_SIZE + 1
        local endIndex = startIndex + RECORD_SIZE - 1
        local id, score = Leaderboard._DecompressRecord(utf8Sub(leaderboard, startIndex, endIndex))
        return {id = id, score = score}
    end,
    Update = function(leaderboard : string, oldIndex : number, newIndex : number, entry : entry)
        local packedEntry = Leaderboard._CompressRecord(entry.id, entry.score)
        if oldIndex < newIndex then
            return utf8Sub(leaderboard, 1, (oldIndex-1)*RECORD_SIZE) ..
                utf8Sub(leaderboard, oldIndex*RECORD_SIZE + 1, newIndex*RECORD_SIZE) ..
                packedEntry ..
                utf8Sub(leaderboard, newIndex*RECORD_SIZE + 1)
        elseif oldIndex > newIndex then
            return utf8Sub(leaderboard, 1, (newIndex-1)*RECORD_SIZE) ..
                packedEntry ..
                utf8Sub(leaderboard, (newIndex-1)*RECORD_SIZE + 1, (oldIndex-1)*RECORD_SIZE) ..
                utf8Sub(leaderboard, oldIndex*RECORD_SIZE + 1)
        else
            return utf8Sub(leaderboard, 1, (newIndex-1)*RECORD_SIZE) ..
                packedEntry ..
                utf8Sub(leaderboard, newIndex*RECORD_SIZE + 1)
        end
    end,
    Insert = function(leaderboard : string, index : number, entry : entry)
        local packedEntry = Leaderboard._CompressRecord(entry.id, entry.score)
        
        local val = utf8Sub(leaderboard, 1, (index-1)*RECORD_SIZE) .. 
            packedEntry .. 
            utf8Sub(leaderboard, (index-1)*RECORD_SIZE + 1)

        return val
    end,
    Remove = function(leaderboard : string, index : number)
        return utf8Sub(leaderboard, 1, (index-1)*RECORD_SIZE) .. 
            utf8Sub(leaderboard, index*RECORD_SIZE + 1)
    end,
    Length = function(leaderboard : string)
        return utf8.len(leaderboard) / RECORD_SIZE
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

export type dataStructure = "table" | "string"

-- Creates a new leaderboard. The data must be compatible with the accessor.
-- I.e. if using a compressed accessor, the data must be a string. Or, if using a default accessor, the data must be a table.
-- @param data -- The data to initialize the leaderboard with
-- @param accessor -- The accessor to use for the leaderboard
function Leaderboard.New(data : any?, dataStructure : dataStructure)
    local self = setmetatable({}, Leaderboard)

    self:_ConfigureDataStructure(dataStructure)
    if data then
        self._data = data        
    end
    return self
end

function Leaderboard.NewFromMerge(leaderboards : {typedef}, dataStructure : dataStructure, limit : number?)
    local self = setmetatable({}, Leaderboard)

    self:_ConfigureDataStructure(dataStructure)
    
    local data = {self._data}
    for _, leaderboard in ipairs(leaderboards) do
        table.insert(data, leaderboard._data)
    end
    self._data = Util.Merge(data, self._accessor, false, function(entry) return entry.score end, limit) -- all leaderboards must use the same data structure and accessor.
    return self
end

function Leaderboard:_ConfigureDataStructure(dataStructure : dataStructure)
    self._dataStructure = dataStructure
    if dataStructure == "table" then
        self._accessor = Leaderboard.defaultLeaderboardAccessor
    elseif dataStructure == "string" then
        self._accessor = Leaderboard.compressedLeaderboardAccessor
    else
        error("Invalid data structure")
    end
    self:GenerateEmpty()
end

function Leaderboard:GetRaw()
    return self._data
end

function Leaderboard:Length(): number
    return self._accessor.Length(self._data)
end

function Leaderboard:GenerateEmpty()
    self._data = self._accessor.New()
end

function Leaderboard:BinarySearch(score)
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

function Leaderboard:GetIndex(index : number): entry
    return self._accessor.Get(self._data, index)
end

function Leaderboard:GetAll(): {entry}
    local result = {}
    for i = 1, self._accessor.Length(self._data) do
        table.insert(result, self._accessor.Get(self._data, i))
    end
    return result
end

function Leaderboard:GetRank(id: string, score: number): number
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

function Leaderboard:GetInsertPos(score: number): number
    return self:BinarySearch(score)
end

function Leaderboard:Remove(id: string, score: number): number
    local rank = self:GetRank(id, score)
    if rank ~= -1 then
        self._data = self._accessor.Remove(self._data, rank)
    end
    return rank
end

function Leaderboard:Update(id: string, prevScore: number?, newScore: number): (number, number)
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
        end
    elseif compression == "none" then
        self._compress = function(data) return data end
        self._decompress = function(s) return s end
    else
        error("Invalid compression type", compression)
    end
    if not self._compress or not self._decompress then
        error("Compression type not implemented the leaderboard data structure.")
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

export type typedef = typeof(Leaderboard.New())

return Leaderboard