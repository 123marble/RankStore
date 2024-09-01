local Util = require(game.ServerScriptService.Tests.util)

return function()
    local LeaderboardHelper = require(game.ServerScriptService.RankStore.leaderboardHelper)
    
    local leaderboardHelper
    beforeEach(function()
        expect.extend(Util.GetExpectationExtensions())
        leaderboardHelper = LeaderboardHelper.New()
        leaderboardHelper:SetAccessor(LeaderboardHelper.compressedLeaderboardAccessor)
        return leaderboardHelper
    end)

    afterEach(function()
        print("test completed...")
    end)
    
    it("TestLeaderboardHelperNew", function()
        expect(leaderboardHelper).to.be.a("table")
    end)

    it("TestLeaderboardHelperGenerateEmpty", function()
        local emptyLeaderboard = leaderboardHelper:GenerateEmpty()
        expect(emptyLeaderboard).to.be.equal("")
    end)

    it("TestLeaderboardHelperInsert", function()
        local prevRank, newRank
        local leaderboard = leaderboardHelper:GenerateEmpty()
        leaderboard, prevRank, newRank = leaderboardHelper:Update(leaderboard, 1, nil, 100)
        expect(prevRank).to.be.equal(nil)
        expect(leaderboardHelper:GetAll(leaderboard)).to.be.deepEqual({{id = 1, score = 100}})
    end)

    it("TestLeaderboardHelperInsertAfter", function()
        local prevRank, newRank
        local leaderboard = leaderboardHelper:GenerateEmpty()
        leaderboard, _, _ = leaderboardHelper:Update(leaderboard, 1, nil, 100)
        leaderboard, prevRank, newRank = leaderboardHelper:Update(leaderboard, 2, nil, 200)
        expect(prevRank).to.be.equal(nil)
        expect(newRank).to.be.equal(1)

        expect(leaderboardHelper:GetAll(leaderboard)).to.be.deepEqual({{id = 2, score = 200}, {id = 1, score = 100}})
    end)

    it("TestLeaderboardHelperInsertBefore", function()
        local prevRank, newRank
        local leaderboard = leaderboardHelper:GenerateEmpty()
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, nil, 100)
        leaderboard, prevRank, newRank = leaderboardHelper:Update(leaderboard, 2, nil, 50)
        expect(prevRank).to.be.equal(nil)
        expect(newRank).to.be.equal(2)

        expect(leaderboardHelper:GetAll(leaderboard)).to.be.deepEqual({{id = 1, score = 100}, {id = 2, score = 50}})
    end)
    
    it("TestLeaderboardHelperInsertMiddle", function()
        local prevRank, newRank
        local leaderboard = leaderboardHelper:GenerateEmpty()
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, nil, 100)
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 2, nil, 200)
        leaderboard, prevRank, newRank = leaderboardHelper:Update(leaderboard, 3, nil, 150)
        expect(prevRank).to.be.equal(nil)
        expect(newRank).to.be.equal(2)
        expect(leaderboardHelper:GetAll(leaderboard)).to.be.deepEqual({{id = 2, score = 200}, {id = 3, score = 150}, {id = 1, score = 100}})
    end)

    it("TestLeaderboardHelperUpdate", function()
        local prevRank, newRank
        local leaderboard = leaderboardHelper:GenerateEmpty()
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, nil, 100)
        leaderboard, prevRank, newRank = leaderboardHelper:Update(leaderboard, 1, 100, 200)
        expect(prevRank).to.be.equal(1)
        expect(newRank).to.be.equal(1)
    end)


    it("TestLeaderboardHelperUpdateOvertake", function()
        local prevRank, newRank
        local leaderboard = leaderboardHelper:GenerateEmpty()
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, nil, 100)
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 2, nil, 200)
        leaderboard, prevRank, newRank = leaderboardHelper:Update(leaderboard, 1, 100, 300)
        expect(prevRank).to.be.equal(2)
        expect(newRank).to.be.equal(1)
        expect(leaderboardHelper:GetAll(leaderboard)).to.be.deepEqual({{id = 1, score = 300}, {id = 2, score = 200}})
    end)

    it("TestLeaderboardHelperUpdateUndertake", function()
        local prevRank, newRank
        local leaderboard = leaderboardHelper:GenerateEmpty()
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, nil, 200)
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 2, nil, 100)
        leaderboard, prevRank, newRank = leaderboardHelper:Update(leaderboard, 1, 200, 50)
        expect(prevRank).to.be.equal(1)
        expect(newRank).to.be.equal(2)
        expect(leaderboardHelper:GetAll(leaderboard)).to.be.deepEqual({{id = 2, score = 100}, {id = 1, score = 50}})
    end)
    
    it("TestLeaderboardHelperUpdateMiddle", function()
        local prevRank, newRank
        local leaderboard = leaderboardHelper:GenerateEmpty()
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, nil, 100)
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 2, nil, 200)
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 3, nil, 300)
        leaderboard, prevRank, newRank = leaderboardHelper:Update(leaderboard, 2, 200, 500)
        expect(prevRank).to.be.equal(2)
        expect(newRank).to.be.equal(1)
        expect(leaderboardHelper:GetAll(leaderboard)).to.be.deepEqual({{id = 2, score = 500}, {id = 3, score = 300}, {id = 1, score = 100}})
    end)

    it("TestLeaderboardHelperUpdate prevScore mismatch throws error", function()
        local leaderboard = leaderboardHelper:GenerateEmpty()
        expect(function()
            leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, 200, 100)
        end).to.throw()

        local leaderboard = leaderboardHelper:GenerateEmpty()
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, nil, 100)
        expect(function()
            leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, 200, 50)
        end).to.throw()
    end)

    it("TestCompressRecord", function()
        local expectedId = 3
        local expectedScore = 150

        local actual = LeaderboardHelper._CompressRecord(expectedId, expectedScore)

        local expected = "AAAAD" .. "AAB7"
        expect(actual).to.be.equal(expected)

        local actualId, actualScore = LeaderboardHelper._DecompressRecord(actual)
        expect({actualId, actualScore}).to.be.deepEqual({expectedId, expectedScore})
    end)
end