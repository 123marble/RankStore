# Rank Store
RankStore is a reliable and scalable system for managing persistent leaderboards using ROBLOX DataStores. RankStore provides a ranking of leaderboard identities based on a score. 

- 🔍 Employs Binary Search or Binary Trees for optimal insertion and retrieval of entries
- 🦥 Lazy saving of leaderboard data to mitigate DataStore limits
- 🚀 Compresses data to a higher base to minimise storage size
- 🛡️ Ensures high data integrity through atomic updates or calling recovery methods in the event of consistency errors
- ⭐ Stores data across multiple keys to be scalable to thousands of identities

This module aims to overcome the current limitation of ROBLOX's Ordered Datastore which does not allow retrieval of specific ranks. At present, Ordered Datastores can only read 100 records per page and the entries must be read in sequence, which is impractical for large leaderboards with many thousands of entries.

# Limitations
- Some use cases will not be suitable for this module. While RankStore has been designed with efficiency in mind, it has to operate within the [limits of ROBLOX Datastores](https://create.roblox.com/docs/cloud-services/data-stores#server-limits), which cannot be changed. The general approach of RankStore is to trade-off real-time leaderboard accuracy for performance by periodically saving changes to the persistent DataStore. See the [Performance Section](#performance) to gauge whether RankStore is suitable for your use case.
- The entry ID and score must be 5 byte and 4 byte **integers** respectively. These strict integer sizes allow the leaderboard to be compressed to a higher base.

# Usage
Add `` to your wally.toml or grab the model here.

```lua
local RankStore = require(game.ServerScriptService.RankStore)
local rankStore = RankStore.GetRankStore("MyRankStore")

rankStore:SetScoreAsync(1, 25) -- pass in user id, score
rankStore:SetScoreAsync(2, 50)
rankStore:SetScoreAsync(3, 20)
rankStore:SetScoreAsync(4, 75)

print(rankStore:GetTopScoresAsync(10))

print(rankStore:GetEntryAsync(3))
-- {
--     ["id"] = 3,
--     ["rank"] = 4,
--     ["score"] = 20
-- }  
```
Full API is available on [123marble.github.io/RankStore/api/RankStore](https://123marble.github.io/RankStore/api/RankStore).

# Performance

| Method                | Algorithm Time Complexity | Network Time Complexity | Datastore Requests       |
|-----------------------|---------------------------|-------------------------|--------------------------|
| GetRankStore          | O(1)                      | O(1)                    | 1 GetAsync               |
| SetScoreAsync         | O(log n)                  | O(n)                    | 2 UpdateAsync<br /> N-1 GetAsync |
| GetEntryAsync         | O(log n)                  | O(n)                    | N GetAsync               |
| GetTopScoresAsync (k) | O(k)                      | O(n)                    | N GetAsync               |
| RemoveEntryAsync            |                     |                 |            |
| ClearAsync            | O(1)                      | O(1)                    | 1 SetAsync               |

**N=num buckets, n=total entries**

**NB: This table applies to only the optimal 'avl' tree `dataStructure`.**

**NB: A DataStore GetAsync or UpdateAsync request retrieves the entire leaderboard over the network so the actual time complexity for any leaderboard operations is O(n). For this reason, it is important that the `lazySaveTime` parameter is set appropriately to only periodically save the leaderboard to the DataStore. This allows more operations to be performed in-memory meaning they are bounded by only the algorithm time complexity, which is very fast. Understand that Lazy Saving means that the leaderboard on a given server will be out of sync with the leaderboard on other servers, but will at least be correct for any changes made within the server.**

**NB: The N GetAsync requests are made in parallel if the `parallel` parameter is set to true.**


## DataStore Limits

### Data Limits
Each entry requires only 9 characters for storage. The current storage limit for DataStore is 4,194,304 characters per key which means that approximately a maximum of 450k entries are storable in 1 key. The `maxBucketsSize` parameter allows you to set the maximum number of characters per key.

The `numBuckets` parameter allows you to set the number of keys that the leaderboard is shared over. This means that the maximum number of entries storable in your RankStore is `(numBuckets*maxBucketsSize) / 9`.


### Request and Throughput Limits
Setting the `lazySaveTime` parameter appropriately is crucuial for avoiding the request and throughput limits of the DataStore.



# Contribute
## How do I run the unit tests?
Testing requires Wally, Rojo, and Roblox Studio.
1. Install packages with `wally install`
1. Sync `rojo` with `default.project.json`
3. Run the Roblox Studio place
4. Check output window for test status
