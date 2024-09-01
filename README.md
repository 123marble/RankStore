# Rank Store

RankStore is a reliable and scalable system for managing persistent leaderboards using ROBLOX DataStores. RankStore provides a ranking of leaderboard identities based on a score. 

- 🔍 Employs Binary Search for optimal insertion and retrieval of entries
- 🚀 Compresses data to a higher base to minimise storage size
- 🛡️ Ensures high data integrity by using atomic updates where possible or calling recovery methods in the event of consistency errors
- ⭐ Stores data across multiple keys to be scalable to thousands of identities

This module aims to overcome the commonly encountered limitation of the Ordered Datastore which does not allow retrieval of specific ranks. At present, Ordered Datastores can only read 100 records per request and the entries must be read in sequence, which is impractical for large leaderboards with thousands of entries.

# Limitations
- Every read operation has to retrieve all leaderboard data over the network. This is because DataStore's GetAsync method can only read entire keys. Consider the [DataStore limits](https://create.roblox.com/docs/cloud-services/data-stores#limits) in conjunction with [RankStore's DataStore usage](#performance)
- Some use cases will be too intensive for this module. While the module has been designed with efficiency in mind, it has to operate within the limits of ROBLOX Datastores, which cannot be changed.
- The entry ID and score must be 5 byte and 4 byte integers respectively. An error is thrown if you attempt to save an invalid entry.

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


# Performance

| Method                | Algorithm Time Complexity | Network Time Complexity | Datastore Requests       |
|-----------------------|---------------------------|-------------------------|--------------------------|
| GetRankStore          | O(1)                      | O(1)                    | 1 GetAsync               |
| SetScoreAsync         | O(log n)                  | O(n)                    | 2 UpdateAsync N GetAsync |
| GetEntryAsync         | O(log n)                  | O(n)                    | N GetAsync               |
| GetTopScoresAsync (k) | O(k)                      | O(n)                    | N GetAsync               |
| ClearAsync            | O(1)                      | O(1)                    | 1 SetAsync               |

**N=num buckets, n=total entries**

**NB: A DataStore GetAsync or UpdateAsync request retrieves the entire value over the network so the actual time complexity for any leaderboard operations is O(n).**

## Concurrency
- How DataStore handles concurrent requests is [not documented]().
- The division of data across multiple buckets is likely beneficial for SetScoreAsync. Number of buckets is effectively the maximum number of supported concurrent requests.

## Data Limits
Each entry requires only 9 characters for storage. The current data limit for DataStore is 4,194,304 characters which means that approximately 450k entries are storable in 1 key.

Consider that there is a trade-off between increasing the number of keys and performance. Choosing a higher number of keys will:
- Use up data store limits faster because the number of GetAsync requests is linear to the number of buckets.
- Increase the number of SetScoreAsync calls that can be made in parallel because the requests are shared between the keys.
- Increase the maximum number of entries that can be stored.




# Contribute
## How do I run the unit tests?
Testing requires Rojo, and Roblox Studio.
1. Install packages with `wally install`
1. Sync `rojo` with `default.project.json`
3. Run the Roblox Studio place
4. Check output window for test status