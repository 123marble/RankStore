-- This module can compress a number into a series of utf-8 characters to reduce the bytes needed to represent a number.
-- For example, the number 1234567890 (10 utf-8 characters) can be represented instead as 2 utf-8 characters as follows:
--  1. Split the string every 6 characters. The largest code in utf-8 is 1,112,064 (7 characters), so we use 6 characters to represent a number up to 999,999 safely.
--  2. Convert each 6 digit number to the equivalent utf-8 character using utf8.char https://www.lua.org/manual/5.3/manual.html#6.4.2
--  3. Concatenate the utf-8 characters together to form the compressed number.

-- Understand that the number of bytes for one utf-8 character is between 1 and 4. The number of bytes used increases by 1 at 127, 2047, and 65535 code values.
-- This is useful for Roblox Datastores, which use utf-8 strings to store data. 
-- The data limits for Roblox Datastores per key are 4,194,304 bytes https://create.roblox.com/docs/cloud-services/data-stores#data-limits
local Utf8Compress = {}

local INVALID_CODE_POINTS_START = 55296 
local NUM_INVALID_CODE_POINTS = 2048

local MAX_UTF8_LEN = 6
function Utf8Compress.Compress(num : number, encodingLength : number) : string

	local strNum = string.format("%0".. MAX_UTF8_LEN*encodingLength .. "d", num)
	if #strNum > encodingLength*MAX_UTF8_LEN then
		error("The number " .. strNum .. " is too large to represent with " .. tostring(encodingLength) .. " utf-8 characters")
	end
	
	local utf8Str = ""
	for i = 1, encodingLength do
        local subNum = tonumber(strNum:sub((i-1)*MAX_UTF8_LEN + 1, i*MAX_UTF8_LEN))
        
        if subNum >= INVALID_CODE_POINTS_START then -- For the benefit of utf-16, utf-8 considers the surrogate pair range used in utf-16
                                                    -- invalid code points, so these need to be avoided. https://en.wikipedia.org/wiki/UTF-8#Invalid_sequences_and_error_handling
            subNum = subNum + NUM_INVALID_CODE_POINTS
        end
		utf8Str = utf8Str .. utf8.char(subNum)
	end 
	return utf8Str
end

function Utf8Compress.Decompress(utf8Str : string) : number
	local strNum = ""
	for _, code in utf8.codes(utf8Str) do
        if code >= INVALID_CODE_POINTS_START then
            code = code - NUM_INVALID_CODE_POINTS
        end
		strNum = strNum .. string.format("%0"..MAX_UTF8_LEN.."d", code)
	end
	return tonumber(strNum)
end

return Utf8Compress