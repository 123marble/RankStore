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
        local leaderboard = leaderboardHelper:GenerateEmpty()
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, nil, 100)
        expect(leaderboardHelper:GetAll(leaderboard)).to.be.deepEqual({{id = 1, score = 100}})
    end)

    it("TestLeaderboardHelperInsertAfter", function()
        local leaderboard = leaderboardHelper:GenerateEmpty()
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, nil, 100)
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 2, nil, 200)
        expect(leaderboardHelper:GetAll(leaderboard)).to.be.deepEqual({{id = 2, score = 200}, {id = 1, score = 100}})
    end)

    it("TestLeaderboardHelperInsertBefore", function()
        local leaderboard = leaderboardHelper:GenerateEmpty()
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, nil, 100)
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 2, nil, 50)
        expect(leaderboardHelper:GetAll(leaderboard)).to.be.deepEqual({{id = 1, score = 100}, {id = 2, score = 50}})
    end)
    
    it("TestLeaderboardHelperInsertMiddle", function()
        local leaderboard = leaderboardHelper:GenerateEmpty()
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, nil, 100)
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 2, nil, 200)
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 3, nil, 150)
        expect(leaderboardHelper:GetAll(leaderboard)).to.be.deepEqual({{id = 2, score = 200}, {id = 3, score = 150}, {id = 1, score = 100}})
    end)

    it("TestLeaderboardHelperUpdateOvertake", function()
        local leaderboard = leaderboardHelper:GenerateEmpty()
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, nil, 100)
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 2, nil, 200)
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, 100, 300)
        expect(leaderboardHelper:GetAll(leaderboard)).to.be.deepEqual({{id = 1, score = 300}, {id = 2, score = 200}})
    end)

    it("TestLeaderboardHelperUpdateUndertake", function()
        local leaderboard = leaderboardHelper:GenerateEmpty()
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, nil, 200)
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 2, nil, 100)
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, 200, 50)
        expect(leaderboardHelper:GetAll(leaderboard)).to.be.deepEqual({{id = 2, score = 100}, {id = 1, score = 50}})
    end)
    
    it("TestLeaderboardHelperUpdateMiddle", function()
        local leaderboard = leaderboardHelper:GenerateEmpty()
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 1, nil, 100)
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 2, nil, 200)
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 3, nil, 300)
        leaderboard, _, _= leaderboardHelper:Update(leaderboard, 2, 200, 500)
        expect(leaderboardHelper:GetAll(leaderboard)).to.be.deepEqual({{id = 2, score = 500}, {id = 3, score = 300}, {id = 1, score = 100}})
    end)

    it("TestCompressRecord", function()
        local expectedId = 3
        local expectedScore = 150

        local actual = LeaderboardHelper._CompressRecord(expectedId, expectedScore)

        local expected = utf8.char(0) .. utf8.char(expectedId) .. utf8.char(0) .. utf8.char(expectedScore)
        expect(actual).to.be.equal(expected)

        local actualId, actualScore = LeaderboardHelper._DecompressRecord(actual)
        expect({actualId, actualScore}).to.be.deepEqual({expectedId, expectedScore})
    end)
end