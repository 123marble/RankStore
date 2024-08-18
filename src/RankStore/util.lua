local Util = {}

-- Generic merge function for a collection of sorted tables
-- @param tables: An array of sorted tables to merge
-- @param ascending: Boolean, true for ascending order, false for descending
-- @param getKey: Function to get the comparison key from each element
-- @param limit: Optional, maximum number of elements to return
-- @return: A new table with merged and sorted elements
function Util.Merge(tables, ascending, getKey, limit)
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
            if indices[i] <= #tables[i] then
                local currentValue = getKey(tables[i][indices[i]])
                if bestValue == nil or compare(currentValue, bestValue) then
                    bestIndex = i
                    bestValue = currentValue
                end
            end
        end
        
        if bestIndex == nil then
            break
        end
        
        table.insert(result, tables[bestIndex][indices[bestIndex]])
        indices[bestIndex] = indices[bestIndex] + 1
        
        if limit and #result >= limit then
            limitReached = true
        end
    end
    
    return result
end

return Util