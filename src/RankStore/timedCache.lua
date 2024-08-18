--!strict
local TimedCache = {}
TimedCache.__index = TimedCache

export type TimedCache<T> = {
    New : (func: () -> T, ttl: number) -> TimedCache<T>,
    Get: (self: TimedCache<T>) -> T?,
    Clear: (self: TimedCache<T>) -> ()
}

function TimedCache.New<T>(func, ttl)
    local self = setmetatable({}, TimedCache)
    self.func = func
    self.expired = true
    self.ttl = ttl
    self.value = self:Get()


    
    return self
end

function TimedCache:Get()
    if self.expired then
        self.value = self.func()
        self.expired = false
        self.timer = task.delay(self.ttl, function()
            self.expired = true
        end)
    end
    return self.value
end

function TimedCache:Clear()
    task.cancel(self.timer)
    self.expired = true
    self.value = nil
end



return TimedCache