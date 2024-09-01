local Shared = {}
local DataStoreService = game:GetService("DataStoreService")

Shared.RANK_STORE_PREFIX = "RankStore_"

Shared.ID_BYTES = 5
Shared.SCORE_BYTES = 4
Shared.RECORD_BYTES = Shared.ID_BYTES + Shared.SCORE_BYTES

function Shared.GetDataStore(name : string)
    return DataStoreService:GetDataStore(Shared.RANK_STORE_PREFIX .. name) -- As per the 'Best Practices' section, we use one datastore to store all data
                                                                            -- for one RankStore https://create.roblox.com/docs/cloud-services/data-stores#create-fewer-data-stores
end

return Shared