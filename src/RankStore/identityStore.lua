local IdentityStore = {}
IdentityStore.__index = IdentityStore

local Shared = require(script.Parent.shared)
local MetadataStore = require(script.Parent.metadataStore)

export type identityEntry = {
    prevScore : number,
    currentScore : number
}

function IdentityStore.GetIdentityStore(name : string, metadataStore : MetadataStore.typedef)
    local self = setmetatable({}, IdentityStore)
    self._datastore = Shared.GetDataStore(name)
    self._metadataStore = metadataStore
    return self
end

function IdentityStore:Update(id : number, score : number) : identityEntry
    local identityKey = self:_GetKey(id)
    local success, result = pcall(function()
        return self._datastore:UpdateAsync(identityKey, function(identity : identityEntry)
            identity = identity or {}
            identity.prevScore = identity.currentScore
            identity.currentScore = score
            return identity
        end)
    end)

    if not success then
        error("Failed to update identity store: " .. tostring(result))
    end
    return result
end

function IdentityStore:_GetKey(id : number)
    return "identity_" .. tostring(id) .. "_line_" .. self._metadataStore:GetAsync().line
end

function IdentityStore:Get(id : number) : identityEntry
    local identityKey = self:_GetKey(id)
    local success, result = pcall(function()
        return self._datastore:GetAsync(identityKey)
    end)

    if not success then
        error("Failed to get identity store: " .. tostring(result))
    end

    return result
end

return IdentityStore