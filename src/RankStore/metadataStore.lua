-- Manages retrieving/updating the metadata datastore for a RankStore.
local MetadataStore = {}
MetadataStore.__index = MetadataStore

local Shared = require(script.Parent.shared)
local TimedCache = require(script.Parent.timedCache)

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
    self._datastore = Shared.GetDataStore(name)

    self._metadataInitialised = false
    self._bucketStoreMetadataKey = "metadata"

    self:_Init(numBuckets, maxBucketSize)
    self._metadataCache = TimedCache.New(
        function()
            return self:_Retrieve() 
        end, 
        BUCKET_METADATA_TTL_SECS
    ) :: TimedCache.TimedCache<metadata>  -- Note that using a timed cache means that changes to the metadata on other servers will not take effect until the cache expires.

    return self
end

function MetadataStore:GetAsync(useCache : boolean) : metadata
    useCache = useCache == nil and true or useCache
    if not self._metadataInitialised then
        error("Metadata store not initialised, call GetMetadataStore first.")
    end

    if not useCache then
        self._metadataCache:Clear()
    end

    return self._metadataCache:Get()
end

function MetadataStore:SetAsync(metadata : metadata)
    local success, result = pcall(function()
        return self._datastore:SetAsync(self._bucketStoreMetadataKey, metadata)
    end)

    if not success then
        error("Failed to update bucket store metadata: " .. tostring(result))
    end

    self._metadataCache:SetOverride(metadata) -- Update the cache immediately
end


function MetadataStore:_Init(numBuckets : number, maxBucketSize : number) : metadata
    local success, result = pcall(function() 
        return self._datastore:UpdateAsync(self._bucketStoreMetadataKey, function(metadata)
            if metadata then
                if numBuckets ~= metadata.numBuckets then
                    error("Number of buckets does not match with existing number. Use RankStore.UpdateNumBuckets to update the number of buckets.")
                end

                for key, value in pairs(defaultMetadata) do -- Hit this usually when the metadata schema is changed, which allows existing RankStores to be updated.
                    if metadata[key] == nil then
                        metadata[key] = value
                    end
                end
            else
                metadata = defaultMetadata
            end
            return metadata
        end)
    end)

    if not success then
        error("Failed to init bucket store metadata: " .. tostring(result))
    end
    self._metadataInitialised = true

    local metadata = result
    return metadata
end

function MetadataStore:_Retrieve()
    local success, metadata = pcall(function()
        return self._datastore:GetAsync(self._bucketStoreMetadataKey)
    end)
    
    if not success then
        error("Failed to get bucket store metadata: " .. tostring(metadata))
    end
    
    return metadata
end

export type typedef = typeof(MetadataStore)

return MetadataStore