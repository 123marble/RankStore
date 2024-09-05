local Util = require(game.ServerScriptService.Tests.util)

return function()
    local Leaderboard = require(game.ServerScriptService.RankStore.leaderboard)
    
    local leaderboard
    beforeEach(function()
        expect.extend(Util.GetExpectationExtensions())
    end)

    afterEach(function()
        print("test completed...")
    end)
    
    local config = {{name = "table", leaderboard = Leaderboard.New(nil, "table")}, {name = "string", leaderboard = Leaderboard.New(nil, "string")}}

    for _, config in ipairs(config) do
        leaderboard = config.leaderboard
        describe("Test Leaderboard " .. tostring(config.name) .. " data structure", function()
            it("TestLeaderboardHelperNew", function()
                expect(leaderboard).to.be.a("table")
            end)

            it("TestLeaderboardHelperInsert", function()
                local prevRank, newRank
                leaderboard:GenerateEmpty()
                prevRank, newRank = leaderboard:Update(1, nil, 100)
                expect(prevRank).to.be.equal(nil)
                expect(leaderboard:GetAll()).to.be.deepEqual({{id = 1, score = 100}})
            end)

            it("TestLeaderboardHelperInsertAfter", function()
                local prevRank, newRank
                leaderboard:GenerateEmpty()
                leaderboard:Update(1, nil, 100)
                prevRank, newRank = leaderboard:Update(2, nil, 200)
                expect(prevRank).to.be.equal(nil)
                expect(newRank).to.be.equal(1)

                expect(leaderboard:GetAll()).to.be.deepEqual({{id = 2, score = 200}, {id = 1, score = 100}})
            end)

            it("TestLeaderboardHelperInsertBefore", function()
                local prevRank, newRank
                leaderboard:GenerateEmpty()
                _, _= leaderboard:Update(1, nil, 100)
                prevRank, newRank = leaderboard:Update(2, nil, 50)
                expect(prevRank).to.be.equal(nil)
                expect(newRank).to.be.equal(2)

                expect(leaderboard:GetAll()).to.be.deepEqual({{id = 1, score = 100}, {id = 2, score = 50}})
            end)
            
            it("TestLeaderboardHelperInsertMiddle", function()
                local prevRank, newRank
                leaderboard:GenerateEmpty()
                _, _= leaderboard:Update(1, nil, 100)
                _, _= leaderboard:Update(2, nil, 200)
                prevRank, newRank = leaderboard:Update(3, nil, 150)
                expect(prevRank).to.be.equal(nil)
                expect(newRank).to.be.equal(2)
                expect(leaderboard:GetAll()).to.be.deepEqual({{id = 2, score = 200}, {id = 3, score = 150}, {id = 1, score = 100}})
            end)

            it("TestLeaderboardHelperUpdate", function()
                local prevRank, newRank
                leaderboard:GenerateEmpty()
                _, _= leaderboard:Update(1, nil, 100)
                prevRank, newRank = leaderboard:Update(1, 100, 200)
                expect(prevRank).to.be.equal(1)
                expect(newRank).to.be.equal(1)
            end)


            it("TestLeaderboardHelperUpdateOvertake", function()
                local prevRank, newRank
                leaderboard:GenerateEmpty()
                _, _= leaderboard:Update(1, nil, 100)
                _, _= leaderboard:Update(2, nil, 200)
                prevRank, newRank = leaderboard:Update(1, 100, 300)
                expect(prevRank).to.be.equal(2)
                expect(newRank).to.be.equal(1)
                expect(leaderboard:GetAll()).to.be.deepEqual({{id = 1, score = 300}, {id = 2, score = 200}})
            end)

            it("TestLeaderboardHelperUpdateUndertake", function()
                local prevRank, newRank
                leaderboard:GenerateEmpty()
                _, _= leaderboard:Update(1, nil, 200)
                _, _= leaderboard:Update(2, nil, 100)
                prevRank, newRank = leaderboard:Update(1, 200, 50)
                expect(prevRank).to.be.equal(1)
                expect(newRank).to.be.equal(2)
                expect(leaderboard:GetAll()).to.be.deepEqual({{id = 2, score = 100}, {id = 1, score = 50}})
            end)
            
            it("TestLeaderboardHelperUpdateMiddle", function()
                local prevRank, newRank
                leaderboard:GenerateEmpty()
                _, _= leaderboard:Update(1, nil, 100)
                _, _= leaderboard:Update(2, nil, 200)
                _, _= leaderboard:Update(3, nil, 300)
                prevRank, newRank = leaderboard:Update(2, 200, 500)
                expect(prevRank).to.be.equal(2)
                expect(newRank).to.be.equal(1)
                expect(leaderboard:GetAll()).to.be.deepEqual({{id = 2, score = 500}, {id = 3, score = 300}, {id = 1, score = 100}})
            end)

            it("TestLeaderboardHelperUpdate prevScore mismatch throws error", function()
                leaderboard:GenerateEmpty()
                expect(function()
                    _, _= leaderboard:Update(1, 200, 100)
                end).to.throw()

                leaderboard:GenerateEmpty()
                _, _= leaderboard:Update(1, nil, 100)
                expect(function()
                    _, _= leaderboard:Update(1, 200, 50)
                end).to.throw()
            end)

            it("TestCompressRecord", function()
                local expectedId = 3
                local expectedScore = 150

                local actual = Leaderboard._CompressRecord(expectedId, expectedScore)

                local expected = "AAAAD" .. "AAB7"
                expect(actual).to.be.equal(expected)

                local actualId, actualScore = Leaderboard._DecompressRecord(actual)
                expect({actualId, actualScore}).to.be.deepEqual({expectedId, expectedScore})
            end)
        end)
    end
end