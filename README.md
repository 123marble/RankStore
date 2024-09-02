🚧 This library is still under construction...🚧
# Rank Store
RankStore is a reliable and scalable system for managing persistent leaderboards using ROBLOX DataStores. RankStore provides a ranking of leaderboard identities based on a score. 

- 🔍 Employs Binary Search for optimal insertion and retrieval of entries
- 🚀 Compresses data to a higher base to minimise storage size
- 🛡️ Ensures high data integrity by using atomic updates where possible or calling recovery methods in the event of consistency errors
- ⭐ Stores data across multiple keys to be scalable to thousands of identities

This module aims to overcome the commonly encountered limitation of the Ordered Datastore which does not allow retrieval of specific ranks. At present, Ordered Datastores can only read 100 records per page and the entries must be read in sequence, which is impractical for large leaderboards with thousands of entries.

# Limitations
- Some use cases will be too intensive for this module. While RankStore has been designed with efficiency in mind, it has to operate within the [limits of ROBLOX Datastores](https://create.roblox.com/docs/cloud-services/data-stores#server-limits), which cannot be changed. See the [Performance Section](#performance) to gauge whether RankStore is viable for your use case.
- The entry ID and score must be 5 byte and 4 byte **integers** respectively.

# Usage
Add `` to your wally.toml or grab the model here.

```lua
local RankStore = require(game.ServerScriptService.RankStore)
local rankStore = RankStore.GetRankStore("MyLeaderboard")

rankStore:SetScoreAsync(1, 25) -- pass in user id, score
rankStore:SetScoreAsync(2, 50)
rankStore:SetScoreAsync(3, 20)
rankStore:SetScoreAsync(4, 75)

print(rankStore:GetTopScoresAsync(10))

print(rankStore:GetEntryAsync(3))
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

**NB: A DataStore GetAsync or UpdateAsync request retrieves the entire value over the network so the actual time complexity for any leaderboard operations is O(n).**

**NB: The N GetAsync requests are always made in parallel.**

## Concurrency
- How DataStore handles concurrent requests is not documented.
- Number of Datastore keys is effectively the maximum number of maximum concurrent SetScoreAsync requests.

## DataStore Limits

### Data Limits
Each entry requires only 9 characters for storage. The current storage limit for DataStore is 4,194,304 characters per key which means that approximately a maximum of 450k entries are storable in 1 key.

### Server and Throughput Limits
There is a trade-off between number of keys and the maximum number of records per key. Choosing a higher number of keys will:
- Worsen the DataStore request budget because the number of GetAsync requests is linearly proportional to the number of keys.
- Improve the DataStore throughput budget because throughput limits are enforced per key.

Conversely, increasing the size of individual keys will improve the request budget but worsen the throughput budget.

# Contribute
## How do I run the unit tests?
Testing requires Wally, Rojo, and Roblox Studio.
1. Install packages with `wally install`
1. Sync `rojo` with `default.project.json`
3. Run the Roblox Studio place
4. Check output window for test status
