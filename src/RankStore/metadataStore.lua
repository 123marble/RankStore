-- Manages retrieving/updating the metadata datastore for a RankStore.
local MetadataStore = {}
MetadataStore.__index = MetadataStore

local Shared = require(script.Parent.shared)
local TimedCache = require(script.Parent.timedCache)
local CachedDataStore = require(script.Parent.cachedDataStore)

local BUCKET_METADATA_TTL_SECS = 60*60


type metadata = {
    numBuckets : number,
    maxBucketSize : number,
    line : number,
    version : number
}

local defaultMetadata = {
    numBuckets = 4,
    maxBucketSize = 4*1024*1024 - 50,
    line = 1,
    version = 1
}

function MetadataStore.GetMetadataStore(name : string, numBuckets : number, maxBucketSize : number)
    local self = setmetatable({}, MetadataStore)

     -- Note that using a timed cache means that changes to the metadata on other servers will not take effect until the cache expires.
    self._datastore = CachedDataStore.New(Shared.GetDataStore(name), BUCKET_METADATA_TTL_SECS)

    self._metadataInitialised = false
    self._bucketStoreMetadataKey = "metadata"

    self:_Init(numBuckets, maxBucketSize)
    return self
end

function MetadataStore:GetAsync(useCache : boolean?) : metadata
    useCache = useCache == nil and true or useCache
    if not self._metadataInitialised then
        error("Metadata store not initialised, call GetMetadataStore first.")
    end

    return self:_Retrieve(useCache)
end

function MetadataStore:SetAsync(metadata : metadata)
    local success, result = pcall(function()
        return self._datastore:SetAsync(self._bucketStoreMetadataKey, metadata)
    end)

    if not success then
        error("Failed to update bucket store metadata: " .. tostring(result))
    end
end


function MetadataStore:_Init(numBuckets : number, maxBucketSize : number) : metadata
    local success, result = pcall(function() 
        return self._datastore:UpdateAsync(self._bucketStoreMetadataKey, function(metadata)
            if metadata then
                if numBuckets ~= metadata.numBuckets then
                    error("Number of buckets does not match with existing number. Use RankStore.UpdateNumBuckets to update the number of buckets.")
                end
                if maxBucketSize ~= metadata.maxBucketSize then
                    error("Max bucket size does not match with existing number. Cannot change max bucket size after creation.")
                end

                for key, value in pairs(defaultMetadata) do -- Hit this usually when the metadata schema is changed, which allows existing RankStores to be updated.
                    if metadata[key] == nil then
                        metadata[key] = value
                    end
                end
            else
                metadata = defaultMetadata
                metadata.numBuckets = numBuckets or metadata.numBuckets
                metadata.maxBucketSize = maxBucketSize or metadata.maxBucketSize
            end
            return metadata
        end, false)
    end)

    if not success then
        error("Failed to init bucket store metadata: " .. tostring(result))
    end
    self._metadataInitialised = true

    local metadata = result
    return metadata
end

function MetadataStore:_Retrieve(useCache : boolean) : metadata
    local success, metadata = pcall(function()
        return self._datastore:GetAsync(self._bucketStoreMetadataKey, useCache)
    end)
    
    if not success then
        error("Failed to get bucket store metadata: " .. tostring(metadata))
    end
    
    return metadata
end

export type typedef = typeof(MetadataStore)

return MetadataStore