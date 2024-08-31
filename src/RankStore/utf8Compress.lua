-- This module compresses an integer from the usual Base 10 into a Base 91 string to reduce the number of bytes needed to store the integer.
-- For example, the integer 8108 which is comprised of 10 characters in Base 10 can be represented instead as 2 characters in Base 91.
-- Base91 was chosen because it is the maximum base where every character in the alphabet is encoded as 1 character in JSON. This maximises
-- the amount of data that can be stored in a single key in Roblox Datastore.
-- https://devforum.roblox.com/t/text-compression/163637/6?u=123marble

-- To understand the conversion please view the example below that converts 8000_10 to }9_91.
-- 10^3		10^2		10^1		10^0
-- 8		1			0			9
-- There are 8 1000s, 1 100s, 0 10s, and 9 1s
-- Now do the same again but use 91 as the base:

-- 91^1		91^0
-- 89		9
-- There are 89 91s (89 * 91 = 8099) and 9 1s (9 * 1 = 9).

-- Where 89 and 9 indicates the 89th and 9th character in the Base 91 alphabet respectively. 
-- In the Base91 alphabet used in this module, the 89th character is '}' and the 9th character is '9', resulting in the string '}9'.

-- This module is useful for use with Roblox Datastore which limit the size of data that can be stored per key.
-- The data limits for Roblox Datastores per key are 4,194,304 characters https://create.roblox.com/docs/cloud-services/data-stores#data-limits
local Utf8Compress = {}

local COMPRESSED_BASE = 91

local base91 = {To = nil, From = nil}
do
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&()*+,./:;<=>?@[]^_`{|}~'"

	local to = table.create(COMPRESSED_BASE)
	local from = {}
	for i = 1, COMPRESSED_BASE do
		local char = string.sub(alphabet, i, i)
		to[i] = char
		from[char] = i
	end

	base91.To = to
	base91.From = from
end

function Utf8Compress.CompressInt(num, max_bytes)
    local result = {}
    for i = 1, max_bytes do
        local remainder = num % COMPRESSED_BASE
        table.insert(result, 1, base91.To[remainder + 1])
        num = math.floor(num / COMPRESSED_BASE)
    end
    return table.concat(result)
end

function Utf8Compress.DecompressInt(str)
    local num = 0
    for i = 1, #str do
        local char = str:sub(i, i)
        num = num * COMPRESSED_BASE + base91.From[char]-1
    end
    return num
end

return Utf8Compress