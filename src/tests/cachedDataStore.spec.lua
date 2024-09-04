local Util = require(game.ServerScriptService.Tests.util)
local DatastoreService = game:GetService("DataStoreService")

return function()
    local CachedDataStore = require(game.ServerScriptService.RankStore.cachedDataStore)
    
    local cachedDataStore
    local dataStore
    beforeEach(function()
        expect.extend(Util.GetExpectationExtensions())
        dataStore = DatastoreService:GetDataStore("UnitTestsCachedDataStore")
        cachedDataStore = CachedDataStore.New(dataStore)
        return cachedDataStore
    end)

    afterEach(function()
        print("test completed...")
    end)

    describe("CacheTests", function()
        it("TestCachedDataStoreSet", function()
            cachedDataStore:SetAsync("key", "value")
            expect(cachedDataStore:GetAsync("key")).to.be.equal("value")
        end)

        it("TestCachedDataStoreUpdateCached", function()
            cachedDataStore:UpdateAsync("key", function(_)
                return "value"
            end, true)

            dataStore:UpdateAsync("key", function(_)
                return "newValue"
            end)

            expect(cachedDataStore:GetAsync("key", true)).to.be.equal("value")
        end)

        it("TestCachedDataStoreUpdateNoCache", function()
            cachedDataStore:UpdateAsync("key", function(_)
                return "value"
            end, false)

            dataStore:UpdateAsync("key", function(_)
                return "newValue"
            end)

            expect(cachedDataStore:GetAsync("key", false)).to.be.equal("newValue")
        end)
    end)
end