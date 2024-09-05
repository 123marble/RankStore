local CachedDataStore = {}
CachedDataStore.__index = CachedDataStore

local TimedCache = require(script.Parent.timedCache)

local dsGetOptions = Instance.new("DataStoreGetOptions")
dsGetOptions.UseCache = false -- disable roblox caching so that it doesn't interfere with our caching

function CachedDataStore.New(datastore : DataStore, expireTime : number?, compressor : (() -> ())?, decompressor : (() -> ())?)
    local self = setmetatable({}, {__index = CachedDataStore})
    self._datastore = datastore
    self._expireTime = expireTime
    self._compressor = compressor or function(v) return v end
    self._decompressor = decompressor or function(v) return v end

    self._cache = TimedCache.New()
    return self
end

function CachedDataStore:_CreateTimedCache(key : string)
    self._cache:Set(key, function()
        return self._decompressor(self._datastore:GetAsync(key, dsGetOptions))
    end, self._expireTime)
end

function CachedDataStore:GetAsync(key : string, useCache : boolean?)
    useCache = useCache == nil and true or useCache
    if not self._cache:IsSet(key) then
        self:_CreateTimedCache(key)
    end
    if not useCache then
        self._cache:Clear(key)
    end
    local v, cacheWasUsed = self._cache:Get(key)
    return v, cacheWasUsed
end

function CachedDataStore:UpdateAsync(key : string, callback : (any) -> any, useCache : boolean?)
    useCache = useCache == nil and true or useCache
    local result
    local cacheWasUsed = false
    if not self._cache:IsSet(key) then
        self:_CreateTimedCache(key)
    end
    if self._cache:IsExpired(key) or not useCache then
        local decompressed
        result = self._datastore:UpdateAsync(key, function(v)
            decompressed = callback(self._decompressor(v), false)
            return self._compressor(decompressed)
        end)
        result = decompressed
    else 
        -- TODO: is there a synchronisation issue here if the cache expires after the check above?
        result = callback(self._cache:Get(key), true)
        cacheWasUsed = true
    end
    self._cache:SetDirect(key, result)
    return result, cacheWasUsed
end

function CachedDataStore:SetAsync(key : string, value : any)
    if not self._cache:IsSet(key) then
        self:_CreateTimedCache(key)
    end
    self._datastore:SetAsync(key, self._compressor(value))
    self._cache:SetDirect(key, value)
end

function CachedDataStore:ClearCache(key : string?)
    if key then
        self._cache:Clear(key)
    else
        self._cache = TimedCache.New()
    end
end

export type typedef = typeof(CachedDataStore)

return CachedDataStore