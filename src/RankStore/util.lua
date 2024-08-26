local Util = {}

export type tableAccessor =  {
    Get: (leaderboard: string, index: number) -> any,
    Update: (leaderboard: string, oldIndex: number, newIndex: number, entry: any) -> string,
    Insert: (leaderboard: string, index: number, entry: any) -> string,
    Remove: (leaderboard: string, index: number) -> string,
    Length: (leaderboard: string) -> number
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
function Util.Merge(tables : {{}}, accessor : tableAccessor, ascending : boolean, getKey : boolean, limit : number?) : {}
    local result = {}
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
        
        table.insert(result, accessor.Get(tables[bestIndex], indices[bestIndex]))
        indices[bestIndex] = indices[bestIndex] + 1
        
        if limit and #result >= limit then
            limitReached = true
        end
    end
    
    return result
end

return Util