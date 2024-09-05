local RankStore = require(game.ServerScriptService.RankStore)
local DataStoreService = game:GetService("DataStoreService")

local rankStore = RankStore.GetRankStore("TestLeaderboard_20", 4, 1000, -1, true)

function printDatastoreBudget()
    local updateBudget = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
    local getBudget = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)

    print("UpdateAsync:", tostring(updateBudget), "GetAsync:", tostring(getBudget))
end

-- rankStore:ClearAsync()
-- --rankStore._metadataStore:SetAsync({line = 21, numBuckets = 4})
-- print(rankStore:GetTopScoresAsync(10))

-- print(rankStore:SetScoreAsync(1, 25))
-- print(rankStore:SetScoreAsync(2, 50))
-- print(rankStore:SetScoreAsync(3, 20))
-- print(rankStore:SetScoreAsync(4, 75))
-- print(rankStore:SetScoreAsync(5, 45))
-- print(rankStore:SetScoreAsync(1, 65))

-- print(rankStore:GetTopScoresAsync(10))

-- print(rankStore:GetEntryAsync(3))


local count = 1
function writeBatch(rankStore, numRecords)

    local ids = {}
    local prevScores = {}
    local newScores = {}

    for i = 1, numRecords do
        table.insert(ids, count)
        table.insert(prevScores, nil)
        table.insert(newScores, math.random(1,10000000))
        count += 1
    end
    local start = os.clock()
    rankStore._bucketsStore:SetScoreBatchNoResultAsync(ids, prevScores, newScores)
    print("Time taken to set scores for", #ids, "ids:", os.clock() - start)
end

local numBuckets = 10
local maxBucketsSize = 4000000
local rankStore = RankStore.GetRankStore("TestLeaderboard_10", numBuckets, maxBucketsSize, 3, false)
rankStore:ClearAsync()

local maxRecordsPerBuckets = math.floor(maxBucketsSize/9)
print(maxRecordsPerBuckets)

writeBatch(rankStore, maxRecordsPerBuckets)
wait(1)
writeBatch(rankStore, maxRecordsPerBuckets)
wait(1)
writeBatch(rankStore, maxRecordsPerBuckets)
wait(1)
writeBatch(rankStore, maxRecordsPerBuckets)
wait(1)
writeBatch(rankStore, maxRecordsPerBuckets)
wait(1)
writeBatch(rankStore, maxRecordsPerBuckets)
wait(1)
writeBatch(rankStore, maxRecordsPerBuckets)
wait(1)
writeBatch(rankStore, maxRecordsPerBuckets)
wait(1)
writeBatch(rankStore, maxRecordsPerBuckets)


-- for i = 4, 100 do
--     for j = 1, 1000 do
--         local start = os.clock()
        
--         local success, result = pcall(function() 
--             return rankStore:SetScoreAsync((i-1)*1000+j, math.random(1,10000000))
--         end)
--         if not success then
--             warn(tostring(result))
--         end
        
--         print(result)
--         print("Time taken to set score for id", (i-1)*1000+j, ":", os.clock() - start)
--         printDatastoreBudget()
--         print("====")
--         task.wait(0.5)
--     end
--     -- local _, result = pcall(function()
--     --     return rankStore:GetTopScoresAsync(10000)
--     -- end)
--     -- print(result)
-- end