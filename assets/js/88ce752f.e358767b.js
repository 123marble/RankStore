"use strict";(self.webpackChunkdocs=self.webpackChunkdocs||[]).push([[921],{61300:e=>{e.exports=JSON.parse('{"functions":[{"name":"GetRankStore","desc":"Creates or retrieves a Rank Store with the provided name.\\n                        Default is 60 seconds. -1 disables lazy saving but be advised that\\n                        this significantly increases the number of DataStore writes.\\nFor use cases requiring a mixture of read/write operations, `avl` is best because insertion into an AVL tree is O(log N). For read only use cases, `string` is best because only the\\nentries that are read are decompressed. In comparison to the other data structures, these will decompress the entire\\nleaderboard when fetching from the DataStore. Conversely, string is terrible for leaderboard insertions because each insertion copies the entire leaderboard in memory, which is O(N).","params":[{"name":"name","desc":"Name of the RankStore","lua_type":"string"},{"name":"numBuckets","desc":"The number of buckets to use","lua_type":"number?"},{"name":"maxBucketSize","desc":"Maximum number of entries in each bucket","lua_type":"number?"},{"name":"lazySaveTime","desc":"Time in seconds to wait before saving the data to the DataStore.","lua_type":"number?"},{"name":"parallel","desc":"Whether to save the data in parallel","lua_type":"boolean?"},{"name":"dataStructure","desc":"The data structure to use. \\"table\\", \\"string\\" or \\"avl\\". Default is \\"table\\".","lua_type":"dataStructure?"},{"name":"compression","desc":"The compression algorithm to use. \\"base91\\" or \\"none\\". Default is \\"base91\\".","lua_type":"compression?"},{"name":"ascending","desc":"Whether the leaderboard should be sorted in ascending order. Default is false (descending order).","lua_type":"boolean?\\n"}],"returns":[{"desc":"","lua_type":"RankStore"}],"function_type":"static","yields":true,"source":{"line":56,"path":"src/RankStore/init.lua"}},{"name":"SetScoreAsync","desc":"Sets the score for the given id.","params":[{"name":"id","desc":"The id of the entry. A number to uniquely identify the entry, typically a userId.","lua_type":"number"},{"name":"score","desc":"The score to set","lua_type":"number"}],"returns":[{"desc":"","lua_type":"setResult\\n"}],"function_type":"method","yields":true,"source":{"line":92,"path":"src/RankStore/init.lua"}},{"name":"GetEntryAsync","desc":"Gets the entry for the given id.","params":[{"name":"id","desc":"The id of the entry.","lua_type":"number"}],"returns":[{"desc":"","lua_type":"entry\\n"}],"function_type":"method","yields":true,"source":{"line":105,"path":"src/RankStore/init.lua"}},{"name":"GetTopScoresAsync","desc":"Gets the top n scores.","params":[{"name":"n","desc":"The number of scores to get","lua_type":"number"}],"returns":[{"desc":"","lua_type":"{entry}"}],"function_type":"method","yields":true,"source":{"line":135,"path":"src/RankStore/init.lua"}},{"name":"UpdateNumBucketsAsync","desc":"Increase the number of buckets used. This method can be used once the existing buckets are full to allow\\nfor more entries to be added.\\n:::info In order to minimise query time, the existing entires are distributed equally among the new buckets. This operation\\nreads your entire RankStore and writes it into the new buckets. This is a costly operation if you RankStore is large.:::","params":[{"name":"n","desc":"The number of buckets to update to. This should be greater than the current number of buckets.","lua_type":"number"}],"returns":[],"function_type":"method","yields":true,"source":{"line":151,"path":"src/RankStore/init.lua"}},{"name":"FlushBuffer","desc":"Manually flush the buffer to force a write to the DataStore. Use `lazySaveTime` to automatically flush the buffer at regular intervals.","params":[],"returns":[],"function_type":"method","source":{"line":158,"path":"src/RankStore/init.lua"}},{"name":"ClearAsync","desc":"Clears all entries in the RankStore.\\n\\nThis actually just increments the keys used in the underlying DataStore so no data is actually deleted. However there is \\nno support to rollback after calling this function at present.","params":[],"returns":[],"function_type":"method","yields":true,"source":{"line":169,"path":"src/RankStore/init.lua"}}],"properties":[],"types":[{"name":"entry","desc":"An array of strings, a number, or nil.","lua_type":"{id: string, rank: number, score: number}","source":{"line":19,"path":"src/RankStore/init.lua"}},{"name":"setResult","desc":"An array of strings, a number, or nil.","lua_type":"{prevRank: number, prevScore: number, newRank: number, newScore: number}","source":{"line":28,"path":"src/RankStore/init.lua"}}],"name":"RankStore","desc":"","source":{"line":8,"path":"src/RankStore/init.lua"}}')}}]);