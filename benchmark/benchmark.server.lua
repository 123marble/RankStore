local RankStore = require(game.ServerScriptService.RankStore)
local Leaderboard = require(game.ServerScriptService.RankStore.leaderboard)

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

local rankStoreName = "TestLeaderboard_13"
local numBuckets = 10
local maxBucketsSize = 2000000
local lazySaveTime = 30

local maxRecordsPerBuckets = math.floor(maxBucketsSize/Leaderboard.RECORD_SIZE)
local dataStructures = {"avl", "table", "string"}

-- Benchmark Test 1: The time taken to set scores for a batch of records for different data structures.
-- String: O(N*2), table: O(log N), avl: O(log N)
for _, dataStructure in ipairs(dataStructures) do
    if dataStructure == "string" then -- don't benchmark string. String concatenations copy the entire string in memory so
                                        -- it becomes O(N^2) for batch inserts.
        continue
    end
    local rankStore = RankStore.GetRankStore(rankStoreName, numBuckets, maxBucketsSize, lazySaveTime, true, dataStructure, "base91")
    rankStore:ClearAsync()
    local start = os.clock()
    for i = 1, numBuckets - 1 do
        writeBatch(rankStore, maxRecordsPerBuckets)
        task.wait()
    end
    print("Write Batch Result: dataStructure=", dataStructure, "time taken=", os.clock() - start)
end
task.wait(30) -- wait for the lazy save to flush.

-- Benchmark Test 2: avl vs table vs string for the time taken to add a single score to the RankStore
-- Uncached: avl: O(N), table: O(N), string: O(N)
-- Cached: avl: O(log N), table: O(log N), string: O(N)
for _, dataStructure in ipairs(dataStructures) do
    local rankStore = RankStore.GetRankStore(rankStoreName, numBuckets, maxBucketsSize, lazySaveTime, true, dataStructure, "base91")
    local start = os.clock()
    rankStore._bucketsStore:SetScoreAsync(1, nil, 5000)
    print("Write Single Result: dataStructure=", dataStructure, "time taken=", os.clock() - start)
    start = os.clock()
    rankStore._bucketsStore:SetScoreAsync(1, 5000, 1000)
    print("Write Single Result: dataStructure=", dataStructure, "time taken=", os.clock() - start)
end

task.wait(30) -- wait for the lazy save to flush.

-- Benchmark Test 3: avl vs table vs string for the time taken to retrieve the top N entries from the RankStore
-- Uncached: avl: O(N), table: O(N), string: O(N) - String is the fastest here because the data stored in the 
--      datastore can be used directly without any decoding. In contrast, the other two data structures must
--      first decode the base91 string into an avl tree/lua table which is slow.
-- Cached: avl: O(1000), table: O(1000), string: O(1000) - All data structures perform the same because the data is cached in memory.                           
for _, dataStructure in ipairs(dataStructures) do
    local rankStore = RankStore.GetRankStore(rankStoreName, numBuckets, maxBucketsSize, lazySaveTime, true, dataStructure, "base91")
    local start = os.clock()
    rankStore._bucketsStore:GetTopScoresAsync(1000)
    print("Read Top N Result: dataStructure=", dataStructure, "time taken=", os.clock() - start)
    start = os.clock()
    print(rankStore._bucketsStore:GetTopScoresAsync(5))
    print("Read Top N Result: dataStructure=", dataStructure, "time taken=", os.clock() - start)
end