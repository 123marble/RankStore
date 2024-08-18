--!strict
local TimedCache = {}
TimedCache.__index = TimedCache

export type TimedCache<T> = {
    New : (func: () -> T, ttl: number) -> TimedCache<T>,
    Get: (self: TimedCache<T>) -> T?,
    Cancel: (self: TimedCache<T>) -> ()
}

function TimedCache.New<T>(func, ttl)
    local self = setmetatable({}, TimedCache)
    self.func = func
    self.value = self.func()
    self.expired = false
    
    self.timer = task.delay(ttl, function()
        self.expired = true
    end)
    
    return self
end


function TimedCache:Get()
    if self.expired then
        self.value = self.func()
    end
    return self.value
end

function TimedCache:Cancel(): ()
    if self.timer then
        task.cancel(self.timer)
        self.timer = nil
    end
end

return TimedCache