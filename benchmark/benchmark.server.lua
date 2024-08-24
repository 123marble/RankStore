local RankStore = require(game.ServerScriptService.RankStore)
local DataStoreService = game:GetService("DataStoreService")

local rankStore = RankStore.GetRankStore("TestLeaderboard_1", 4)

function printDatastoreBudget()
    local updateBudget = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
    local getBudget = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)

    print("UpdateAsync:", tostring(updateBudget), "GetAsync:", tostring(getBudget))
end

rankStore:ClearAsync()
--rankStore._metadataStore:SetAsync({line = 21, numBuckets = 4})
print(rankStore:GetTopScoresAsync(10))

print(rankStore:SetScoreAsync(1, 25))
print(rankStore:SetScoreAsync(2, 50))
print(rankStore:SetScoreAsync(3, 20))
print(rankStore:SetScoreAsync(4, 75))
print(rankStore:SetScoreAsync(5, 45))
print(rankStore:SetScoreAsync(1, 65))

print(rankStore:GetTopScoresAsync(10))

print(rankStore:GetEntryAsync(3))
    
-- for i = 1, 100 do
--     for j = 1, 1000 do
--         local start = os.clock()
        
--         local result = rankStore:SetScoreAsync(i*1000+j, math.random(1,10000000)/1000)
        
--         print(result)
--         print("Time taken to set score for id", i*1000+j, ":", os.clock() - start)
--         printDatastoreBudget()
--         print("====")
--         task.wait(0.5)
--     end
--     -- local _, result = pcall(function()
--     --     return rankStore:GetTopScoresAsync(10000)
--     -- end)
--     -- print(result)
    
-- end