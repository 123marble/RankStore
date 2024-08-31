--- @class Util

local HttpService = game:GetService("HttpService")
local Util = {}

--[=[
@private
Function to compare two tables for deep equality.
@return boolean
Source: https://stackoverflow.com/a/25976660
A request for a TestEZ native implementation of this function is tracked here: https://github.com/Roblox/testez/issues/46
]=]
function Util.DeepEqual(table1 : {}, table2 : {})
    local avoid_loops = {}
    local function recurse(t1, t2)
       if type(t1) ~= type(t2) then return false end
       if type(t1) ~= "table" then return t1 == t2 end

       if avoid_loops[t1] then return avoid_loops[t1] == t2 end
       avoid_loops[t1] = t2
       local t2keys = {}
       local t2tablekeys = {}
       for k, _ in pairs(t2) do
          if type(k) == "table" then table.insert(t2tablekeys, k) end
          t2keys[k] = true
       end
       for k1, v1 in pairs(t1) do
          local v2 = t2[k1]
          if type(k1) == "table" then
             local ok = false
             for i, tk in ipairs(t2tablekeys) do
                if Util.DeepEqual(k1, tk) and recurse(v1, t2[tk]) then
                   table.remove(t2tablekeys, i)
                   t2keys[tk] = nil
                   ok = true
                   break
                end
             end
             if not ok then return false end
          else
             if v2 == nil then return false end
             t2keys[k1] = nil
             if not recurse(v1, v2) then return false end
          end
       end
       if next(t2keys) then return false end
       return true
    end
    return recurse(table1, table2)
 end

function Util.GetExpectationExtensions()
    return {
        deepEqual = function(receivedValue, expectedValue)
            local pass = Util.DeepEqual(receivedValue, expectedValue)
            return {
                pass = pass,
                message = ("Expected %s to be deep equal to %s"):format(HttpService:JSONEncode(receivedValue), HttpService:JSONEncode(expectedValue))
            }
        end,
        divisibleBy = function(receivedValue, expectedValue)
            local pass = receivedValue % expectedValue == 0
            if pass then
                return {
                    pass = true,
                    message = ("Expected %s to be divisible by %s"):format(receivedValue, expectedValue)
                }
            else
                return {
                    pass = false,
                    message = ("Expected %s not to be divisible by %s"):format(receivedValue, expectedValue)
                }
            end
        end
    }
end

return Util