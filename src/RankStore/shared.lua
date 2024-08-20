local Shared = {}
local DataStoreService = game:GetService("DataStoreService")

Shared.RANK_STORE_PREFIX = "RankStore_"

function Shared.GetDataStore(name : string)
    return DataStoreService:GetDataStore(Shared.RANK_STORE_PREFIX .. name) -- As per the 'Best Practices' section, we use one datastore to store all data
                                                                            -- for one RankStore https://create.roblox.com/docs/cloud-services/data-stores#create-fewer-data-stores
end

return Shared