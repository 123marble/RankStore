--!strict
local Cache = {}
Cache.__index = Cache

export type TimedCache<T> = {
    New : (func: () -> T, ttl: number) -> TimedCache<T>,
    Get: (self: TimedCache<T>) -> T?,
    Clear: (self: TimedCache<T>) -> ()
}

type entry = {
    func : () -> any,
    expired : boolean,
    ttl : number,
    value : any
}

function Cache.New<T>()
    local self = setmetatable({}, Cache)
    
    self._cache = {}
    return self
end

function Cache:IsSet(key)
    return self._cache[key] ~= nil
end

function Cache:_ConstructEntry(func, expired, ttl) : entry
    return {
        func = func,
        expired = expired,
        ttl = ttl,
        value = nil,
        timer = nil
    }
end

function Cache:_GetEntry(key)
    if not self._cache[key] then
        error("Cache entry not found")
    end
    return self._cache[key]
end

function Cache:Set(key, func, ttl)
    self:Clear(key)
    self._cache[key] = self:_ConstructEntry(func, true, ttl)
end

function Cache:SetDirect(key, value)
    self:Clear(key)
    local entry = self:_GetEntry(key)
    entry.value = value
    entry.expired = false
    self:_StartTimer(key)
end

function Cache:Get(key)
    local entry = self:_GetEntry(key)
    local usedCache = true
    if entry.expired then
        entry.value = entry.func()
        entry.expired = false

        self:_StartTimer(key)
        usedCache = false
    end
    return entry.value, usedCache
end

function Cache:Clear(key)
    if not self:IsSet(key) then
        return
    end
    local entry = self:_GetEntry(key)

    if entry.timer then
        task.cancel(entry.timer)
    end
    entry.expired = true
    entry.value = nil
end

function Cache:IsExpired(key)
    local entry = self:_GetEntry(key)
    return entry.expired
end

function Cache:_StartTimer(key)
    local entry = self:_GetEntry(key)
    if entry.ttl then
        entry.timer = task.delay(entry.ttl, function()
            entry.expired = true
        end)
    end
end

return Cache