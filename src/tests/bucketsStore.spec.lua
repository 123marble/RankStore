local Util = require(game.ServerScriptService.Tests.util)

return function()
    local RankStore = require(game.ServerScriptService.RankStore)
    local rankStore
    local bucketsStore
    beforeEach(function()
        expect.extend(Util.GetExpectationExtensions())
        local numBuckets = 4
        local maxBucketsSize = 90
        rankStore = RankStore.GetRankStore("UnitTestsRankStore_3", numBuckets, maxBucketsSize)
        bucketsStore = rankStore._bucketsStore
        rankStore:ClearAsync()
    end)

    afterEach(function()
        print("test completed...")
    end)
    
    describe("TestSetScore", function()
        it("TestSetScoreNew", function()
            local prevRank, newRank = bucketsStore:SetScoreAsync(1, nil, 200)
            expect(prevRank).to.be.equal(nil)
            expect(newRank).to.be.equal(1)
        end)

        it("TestSetScoreUpdate", function()
            bucketsStore:SetScoreAsync(1, nil, 200)
            local prevRank, newRank = bucketsStore:SetScoreAsync(1, 200, 300)
            expect(prevRank).to.be.equal(1)
            expect(newRank).to.be.equal(1)
        end)

        -- Should throw an error if the previous score is not found.
        it("TestSetScoreUpdatePrevScoreMismatch", function()
            bucketsStore:SetScoreAsync(1, nil, 200)
            expect(function()
                bucketsStore:SetScoreAsync(1, 500, 100)
            end).to.throw()
        end)

        it("TestBatchInsertsAndUpdates", function()
            bucketsStore:SetScoreBatchAsync(
                {1,2,3,4,5},
                {nil, nil, nil, nil, nil},
                {200,300,100,400,500}
            )

            expect(bucketsStore:GetTopScoresAsync(10)).to.be.deepEqual({
                {id = 5, score = 500},
                {id = 4, score = 400},
                {id = 2, score = 300},
                {id = 1, score = 200},
                {id = 3, score = 100},
            })

            bucketsStore:SetScoreBatchAsync(
                {6,3,4,7,5}, -- 6, 7 are inserts and 3, 4, 5 are updates
                {nil, 100, 400, nil, 500},
                {250, 150, 450, 350, 550}
            )

            expect(bucketsStore:GetTopScoresAsync(10)).to.be.deepEqual({
                {id = 5, score = 550},
                {id = 4, score = 450},
                {id = 7, score = 350},
                {id = 2, score = 300},
                {id = 6, score = 250},
                {id = 1, score = 200},
                {id = 3, score = 150},
            })
        end)

        itFOCUS("TestBucketFull", function()
            bucketsStore:SetScoreBatchAsync(
                {4, 8, 12, 16, 20, 24, 28, 32, 36, 40}, -- ids are all multiples of 5 so they all go to the same bucket
                {nil, nil, nil, nil, nil, nil, nil, nil, nil, nil},
                {200, 300, 100, 400, 500, 600, 700, 800, 900, 1000}
            )

            expect(function() bucketsStore:SetScoreAsync(44, nil, 1100) end).to.throw()
        end)
    end)
end