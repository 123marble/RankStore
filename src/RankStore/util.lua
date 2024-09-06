local Util = {}

export type tableAccessor =  {
    New : () -> any,
    Get: (leaderboard: any, index: number) -> any,
    Update: (leaderboard: any, oldIndex: number, newIndex: number, entry: any) -> string,
    Insert: (leaderboard: any, index: number, entry: any) -> string,
    Remove: (leaderboard: any, index: number) -> string,
    Length: (leaderboard: any) -> number
}

-- Generic merge for a collection of sorted tables
-- The merge part of the mergesort algorithm for efficient merging of already sorted tables.
-- @param tables: An array of sorted tables to merge
-- @param ascending: Boolean, true for ascending order, false for descending
-- @param getKey: Function to get the comparison key from each element
-- @param limit: Optional, maximum number of elements to return
-- @return: A new table with merged and sorted elements
-- todo: Using the accessor here feels awkward. Merge should be a completely generic operation but it's signature
-- is being dictated by the use of encoded leaderboards in leaderboardHelper.lua.
function Util.Merge(tables : {any}, accessor : tableAccessor, ascending : boolean, getKey : (any)->(any), limit : number?) : {}
    local result = accessor.New()
    local indices = {}
    local tablesToMerge = #tables
    local limitReached = false
    
    for i = 1, tablesToMerge do
        indices[i] = 1
    end
    
    local compare = ascending and
        function(a, b) return a < b end or
        function(a, b) return a > b end
    
    while not limitReached do
        local bestIndex = nil
        local bestValue = nil
        
        for i = 1, tablesToMerge do
            if indices[i] <= accessor.Length(tables[i]) then
                local currentValue = getKey(accessor.Get(tables[i], indices[i]))
                if bestValue == nil or compare(currentValue, bestValue) then
                    bestIndex = i
                    bestValue = currentValue
                end
            end
        end
        
        if bestIndex == nil then
            break
        end
        
        result = accessor.Insert(result, accessor.Length(result)+1, accessor.Get(tables[bestIndex], indices[bestIndex]))
        indices[bestIndex] = indices[bestIndex] + 1
        
        if limit and #result >= limit then
            limitReached = true
        end
    end
    
    return result
end

-- Method 3: Using a function to create an enum (more typesafe)
function Util.CreateEnum(values)
    local enum = {}
    for i, value in ipairs(values) do
        enum[value] = value
    end
    return setmetatable(enum, {
        __index = function(_, key)
            error(string.format("Invalid enum value: %s", tostring(key)), 2)
        end,
        __newindex = function()
            error(string.format("Cannot modify enum"), 2)
        end
    })
end

return Util