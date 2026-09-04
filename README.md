# Rank Store

RankStore is a scalable, persistent leaderboard library for Roblox. It supports setting player scores, looking up global ranks, and retrieving the top players efficiently at scale.

Roblox's [`OrderedDataStore`](https://create.roblox.com/docs/reference/engine/classes/OrderedDataStore) works well for reading the highest or lowest scores, but [`GetSortedAsync`](https://create.roblox.com/docs/reference/engine/classes/OrderedDataStore#GetSortedAsync) returns at most 100 entries per page. Finding an arbitrary player's rank requires reading every preceding page. On a leaderboard with hundreds of thousands of entries, those sequential reads exceed Roblox's [DataStore request limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits#access-limits), preventing the operation from completing within the available request budget.

RankStore solves this by maintaining a ranked index distributed across multiple DataStore keys. It can locate an individual player's global rank without reading every player above them and provides one API for all manner of rank queries including:

- Add a player or update their score
- Track a player's previous and new rank after a score update
- Look up an individual player's score and global rank
- Retrieve the leading entries in rank order
- Rank scores in ascending or descending order

RankStore applies several optimisations to stay within Roblox DataStore limits:

- Uses binary search or AVL trees for efficient score insertion and rank lookup
- Reads independent buckets in parallel to reduce query time
- Compresses entries to reduce storage requirements and network transfer
- Batches buffered score updates to reduce DataStore writes

Buffered changes are immediately visible on the server that made them but may take time to appear on other servers.

# Usage
Add `rankstore = "123marble-rbx/rankstore@1.0.0"` to your wally.toml.

```lua
local RankStore = require(game.ServerScriptService.RankStore)
local rankStore = RankStore.GetRankStore("MyRankStore")

rankStore:SetScoreAsync(1, 25) -- pass in user id, score
rankStore:SetScoreAsync(2, 50)
rankStore:SetScoreAsync(3, 20)
rankStore:SetScoreAsync(4, 75)

local topScores = rankStore:GetTopScoresAsync(10)
-- topScores:
-- {
--     { ["id"] = 4, ["rank"] = 1, ["score"] = 75 },
--     { ["id"] = 2, ["rank"] = 2, ["score"] = 50 },
--     { ["id"] = 1, ["rank"] = 3, ["score"] = 25 },
--     { ["id"] = 3, ["rank"] = 4, ["score"] = 20 }
-- }

local entry = rankStore:GetEntryAsync(3)
-- entry:
-- {
--     ["id"] = 3,
--     ["rank"] = 4,
--     ["score"] = 20
-- }

local updateResult = rankStore:SetScoreAsync(3, 100)
-- updateResult:
-- {
--     ["prevRank"] = 4,
--     ["prevScore"] = 20,
--     ["newRank"] = 1,
--     ["newScore"] = 100
-- }
```
Full API is available on [123marble.github.io/RankStore/api/RankStore](https://123marble.github.io/RankStore/api/RankStore).

# Performance

| Method | Cold local processing | Cached local processing | Data transferred on cache miss | DataStore requests on cache miss |
|--------|-----------------------|-------------------------|----------------------------------|----------------------------------|
| `GetRankStore` | O(1) | O(1) | O(1) | 1 `UpdateAsync` |
| `SetScoreAsync` | O(n) | O(N log m) | O(n) | 2 `UpdateAsync` + N-1 `GetAsync` |
| `GetEntryAsync` | O(n) | O(N log m) | O(n) | 1 identity `GetAsync` + N bucket `GetAsync` |
| `GetTopScoresAsync(k)` | O(n + kN) | O(kN) | O(n) | N `GetAsync` |
| `ClearAsync` | O(1) | O(1) | O(1) | 1 `SetAsync` |

**N = number of buckets; n = total number of entries; m = n/N, the average number of entries per bucket**

**Note: This table assumes evenly distributed entries and the default `"avl"` data structure with `"base91"` compression. On a cache miss, RankStore transfers and decompresses each complete bucket and rebuilds its AVL tree, making global-rank operations O(n). Once the bucket cache is populated, each AVL lookup is O(log m), but a global rank still requires a lookup across N buckets.**

**Note: Data transferred describes how the total payload grows, not request latency. Running bucket reads in parallel can reduce elapsed time, but does not reduce the number of requests or the total data transferred.**

# Tuning for Performance

`GetRankStore` exposes several configuration options for tuning the balance between cross-server consistency, request throughput, query latency, and storage requirements. The appropriate values depend on the size and update frequency of the leaderboard.

Start with the defaults: `lazySaveTime = 60`, `numBuckets = 5`, `maxBucketSize = 1,000,000`, `parallel = true`, `dataStructure = "avl"`, and `compression = "base91"`. Tune them only when a specific constraint appears:

```lua
local rankStore = RankStore.GetRankStore(
    "MyRankStore",
    5, -- numBuckets
    1_000_000, -- maxBucketSize
    60, -- lazySaveTime in seconds
    true, -- parallel
    "avl", -- dataStructure
    "base91", -- compression
    false -- ascending
)
```

With five buckets of 1,000,000 characters and nine characters per base-91-compressed entry, this configuration supports approximately 555,555 entries:

`floor(1,000,000 / 9) = 111,111 entries per bucket`

`111,111 * 5 = 555,555 entries in total`

| Symptom or requirement | Adjustment | Trade-off |
|------------------------|------------|-----------|
| Rank queries are slow | Ensure `parallel` is `true`, use `"avl"`, and avoid configuring more buckets than the required capacity needs. | Fewer buckets mean fewer requests, but reduce total capacity and increase the amount of data returned by each request. The number of buckets cannot currently be decreased after creation. |
| DataStore write limits are being reached | Increase `lazySaveTime` so that more score updates are combined into each write. | Other servers take longer to observe buffered changes. |
| DataStore read limits are being reached | Use the smallest practical `numBuckets`. | Each query reads fewer buckets, but each bucket contains more data and total capacity is lower. |
| Cross-server rankings are too stale | Decrease `lazySaveTime`; use `-1` only when every update must be written immediately. | More frequent writes reduce the available update throughput and can reach DataStore limits. |
| Buckets are approaching their storage limit | Use `"base91"` compression and increase `numBuckets`. | More buckets increase the number of requests needed by rank queries. |

The settings control the following behaviour:

| Option | Trade-off |
|--------|-----------|
| `lazySaveTime` | Controls how long score updates are buffered. A higher value batches more updates into fewer writes, increasing throughput at the cost of slower cross-server consistency. Setting it to `-1` disables buffering and substantially increases DataStore writes. |
| `numBuckets` | Controls how many DataStore keys contain the leaderboard. More buckets increase total capacity and reduce the amount of data in each bucket, but queries may require more DataStore requests. |
| `maxBucketSize` | Limits the number of characters stored in each bucket. Increase it to fit more entries per bucket or decrease it to reduce the data transferred by each request. |
| `parallel` | Runs independent bucket requests concurrently to reduce elapsed query time. This does not reduce the number of requests or total data transferred. |
| `dataStructure` | Selects the in-memory representation. Use `"avl"` for mixed read-and-write workloads and `"string"` for read-heavy workloads. |
| `compression` | Controls the serialized storage format. Use `"base91"` to reduce storage and network transfer, or `"none"` to retain the uncompressed representation. |

# Limitations

- RankStore's optimisations reduce DataStore usage but cannot bypass [Roblox DataStore limits](https://create.roblox.com/docs/cloud-services/data-stores#server-limits). Requirements such as extremely frequent rank queries or leaderboards containing hundreds of millions of entries may still exceed DataStore request, throughput, or storage limits even after tuning.
- Buffered writes trade immediate cross-server consistency for throughput. A server sees its own buffered changes, but other servers may temporarily return stale rankings.
- When using the default `"base91"` compression, entry IDs and scores must be non-negative integers. IDs may range from `0` to `6,240,321,450` (`91^5 - 1`), and scores from `0` to `68,574,960` (`91^4 - 1`). Their fixed-width representations use five and four characters respectively.

# Contribute

## Running the Unit Tests

Testing requires Wally, Rojo, and Roblox Studio.

1. Install packages with `wally install`
2. Sync Rojo with `default.project.json`
3. Run the Roblox Studio place
4. Check the Output window for the test status
