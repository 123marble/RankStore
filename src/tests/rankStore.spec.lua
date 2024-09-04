
local Util = require(game.ServerScriptService.Tests.util)

return function()
    local RankStore = require(game.ServerScriptService.RankStore)
    local rankStore
    beforeEach(function()
        expect.extend(Util.GetExpectationExtensions())
        local numBuckets = 4
        local maxBucketsSize = 100
        rankStore = RankStore.GetRankStore("UnitTestsRankStore_5", numBuckets, maxBucketsSize, 5, false)
        rankStore:ClearAsync()
        return rankStore
    end)

    afterEach(function()
        print("test completed...")
    end)
    
    describe("GetRankStore", function()
        it("should return a table", function()
            expect(rankStore).to.be.a("table")
        end)
    end)

    it("TestGetEntryNotExist", function()
        expect(rankStore:GetEntryAsync(1)).to.be.equal(nil)
    end)

    it("TestGetEntryOne", function()
        expect(rankStore:SetScoreAsync(1, 200)).to.be.deepEqual({newRank = 1, newScore = 200})
        expect(rankStore:GetEntryAsync(1)).to.be.deepEqual({id = 1, rank = 1, score = 200})
    end)

    it("TestSetScoreUpdate", function()
        expect(rankStore:SetScoreAsync(1, 200)).to.be.deepEqual({newRank = 1, newScore = 200})
        expect(rankStore:SetScoreAsync(1, 300)).to.be.deepEqual({prevRank = 1, prevScore = 200, newRank = 1, newScore = 300})
    end)

    it("TestInsertionBetter", function()
        expect(rankStore:SetScoreAsync(1, 200)).to.be.deepEqual({newRank = 1, newScore = 200})
        expect(rankStore:SetScoreAsync(2, 300)).to.be.deepEqual({newRank = 1, newScore = 300})

        local expectedLeaderboard = {
            {id = 2, rank = 1, score = 300},
            {id = 1, rank = 2, score = 200}
        }
        expect(rankStore:GetTopScoresAsync(10)).to.be.deepEqual(expectedLeaderboard)
    end)

    it("TestInsertionWorse", function()
        expect(rankStore:SetScoreAsync(1, 200)).to.be.deepEqual({newRank = 1, newScore = 200})
        expect(rankStore:SetScoreAsync(2, 100)).to.be.deepEqual({newRank = 2, newScore = 100})

        local expectedLeaderboard = {
            {id = 1, rank = 1, score = 200},
            {id = 2, rank = 2, score = 100}
        }
        expect(rankStore:GetTopScoresAsync(10)).to.be.deepEqual(expectedLeaderboard)
    end)

    it("TestInsertionMiddle", function()
        expect(rankStore:SetScoreAsync(1, 200)).to.be.deepEqual({newRank = 1, newScore = 200})
        expect(rankStore:SetScoreAsync(2, 300)).to.be.deepEqual({newRank = 1, newScore = 300})
        expect(rankStore:SetScoreAsync(3, 250)).to.be.deepEqual({newRank = 2, newScore = 250})

        local expectedLeaderboard = {
            {id = 2, rank = 1, score = 300},
            {id = 3, rank = 2, score = 250},
            {id = 1, rank = 3, score = 200}
        }
        expect(rankStore:GetTopScoresAsync(10)).to.be.deepEqual(expectedLeaderboard)
    end)

    it("TestUpdateOvertake", function()
        expect(rankStore:SetScoreAsync(1, 200)).to.be.deepEqual({newRank = 1, newScore = 200})
        expect(rankStore:SetScoreAsync(2, 300)).to.be.deepEqual({newRank = 1, newScore = 300})
        expect(rankStore:SetScoreAsync(1, 400)).to.be.deepEqual({prevRank = 2, prevScore = 200, newRank = 1, newScore = 400})

        local expectedLeaderboard = {
            {id = 1, rank = 1, score = 400},
            {id = 2, rank = 2, score = 300}
        }
        expect(rankStore:GetTopScoresAsync(10)).to.be.deepEqual(expectedLeaderboard)
    end)

    it("TestUpdateUndertake", function()
        expect(rankStore:SetScoreAsync(1, 200)).to.be.deepEqual({newRank = 1, newScore = 200})
        expect(rankStore:SetScoreAsync(2, 100)).to.be.deepEqual({newRank = 2, newScore = 100})
        expect(rankStore:SetScoreAsync(1, 50)).to.be.deepEqual({prevRank = 1, prevScore = 200, newRank = 2, newScore = 50})

        local expectedLeaderboard = {
            {id = 2, rank = 1, score = 100},
            {id = 1, rank = 2, score = 50}
        }
        expect(rankStore:GetTopScoresAsync(10)).to.be.deepEqual(expectedLeaderboard)
    end)

    it("TestSetScoreBucketsStoreErrorMultiple", function()
 
    end)

    it("TestBucketSizeExceeded", function()

    end)
end