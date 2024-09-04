local Buffer = {}
Buffer.__index = Buffer

function Buffer.New(flusher : ({any}), flushTimer : number?)
    local self = setmetatable({}, {__index = Buffer})
    self._flusher = flusher
    self._flushTimer = flushTimer
    self._timerCoroutine = nil
    self._buf = {}
    return self
end

function Buffer:_StartFlushTimer()
    if self._flushTimer then
        self._timerCoroutine = task.delay(self._flushTimer, function()
            self._timerCoroutine = nil
            self:Flush()
        end)
    end
end

function Buffer:Write(...)
    table.insert(self._buf, {...})
    if self._autoflush then
        self:Flush()
    end
    print("WRITTEN TO BUFFER")
    print(self._timerCoroutine)
    if not self._timerCoroutine then
        self:_StartFlushTimer()
    end
end

function Buffer:Flush()
    local buf = self._buf
    self._buf = {} -- Must be cleared before flushing so that writes that happen during the flush can be added to the buffer for the next flush.
    self._flusher(buf)
end

export type typedef = typeof(Buffer)

return Buffer