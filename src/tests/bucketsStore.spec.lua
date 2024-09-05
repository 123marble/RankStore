local Util = require(game.ServerScriptService.Tests.util)
local HttpService = game:GetService("HttpService")

return function()
    local RankStore = require(game.ServerScriptService.RankStore)
    local rankStore
    local bucketsStore
    local numBuckets = 4
    local maxBucketsSize = 90
    beforeEach(function()
        local extensions = Util.GetExpectationExtensions()

        local pass = true

        -- Buckets are fetched in parallel so the order of buckets is not guaranteed.
        -- Checks that the contents of the buckets are as expected.
        extensions.bucketsEqual = function(actualBuckets, expectedBuckets)
            for _, expectedBucket in expectedBuckets do
                local found = false
                for _, actualBucket in actualBuckets do
                    if Util.DeepEqual(expectedBucket, actualBucket) then
                        found = true
                    end
                end
                if not found then
                    pass = false
                end
            end
            return {
                pass = pass,
                message = ("Expected %s to be bucketsEqual but got %s"):format(HttpService:JSONEncode(actualBuckets), HttpService:JSONEncode(expectedBuckets))
            }
        end
        expect.extend(extensions)

        rankStore = RankStore.GetRankStore("UnitTestsBucketStore_3", numBuckets, maxBucketsSize, -1, false, "table", "base91")
        
        bucketsStore = rankStore._bucketsStore
        
        rankStore:ClearAsync()
        local meta = bucketsStore._metadataStore:GetAsync(false)
        meta.numBuckets = numBuckets
        bucketsStore._metadataStore:SetAsync(meta)
    end)

    afterEach(function()
        local meta = bucketsStore._metadataStore:GetAsync(false)
        meta.numBuckets = numBuckets
        bucketsStore._metadataStore:SetAsync(meta)
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

        it("TestGetBuckets", function()
            bucketsStore:SetScoreBatchAsync(
                {1, 2, 3, 4, 5},
                {nil, nil, nil, nil, nil},
                {200, 300, 100, 400, 500}
            )
            local leaderboards = bucketsStore:GetBucketsAsync()

            expect(#leaderboards).to.be.equal(4)

            local expected = {
                {
                    {id = 4, score = 400},
                },
                {
                    {id = 3, score = 100},
                },
                {
                    {id = 2, score = 300},
                },
                {
                    {id = 5, score = 500},
                    {id = 1, score = 200}
                    
                }
            }

            expect(leaderboards).to.be.bucketsEqual(expected)
        end)

        it("TestBucketFull", function()
            bucketsStore:SetScoreBatchAsync(
                {4, 8, 12, 16, 20, 24, 28, 32, 36, 40}, -- ids are all multiples of 5 so they all go to the same bucket
                {nil, nil, nil, nil, nil, nil, nil, nil, nil, nil},
                {200, 300, 100, 400, 500, 600, 700, 800, 900, 1000}
            )

            expect(function() bucketsStore:SetScoreAsync(44, nil, 1100) end).to.throw()
        end)

        it("TestIncrementNumBuckets", function()
            bucketsStore:SetScoreBatchAsync(
                {1, 2, 3, 4, 5}, -- ids will be split across buckets
                {nil, nil, nil, nil, nil},
                {200, 300, 100, 400, 500}
            )
            bucketsStore:UpdateNumBucketsAsync(5)

            local leaderboards = bucketsStore:GetBucketsAsync()

            expect(leaderboards).to.be.bucketsEqual({
                {
                    {id = 5, score = 500},
                },
                {
                    {id = 4, score = 400},
                },
                {
                    {id = 3, score = 100},
                },
                {
                    {id = 2, score = 300},
                },
                {
                    {id = 1, score = 200},
                }
            })
        end)

        it("TestIncrementNumBuckets Partial Failure", function()
            bucketsStore:SetScoreBatchAsync(
                {1, 2, 3, 4, 5}, -- ids will be split across buckets
                {nil, nil, nil, nil, nil},
                {200, 300, 100, 400, 500}
            )
            local copyAllData = bucketsStore._CopyAllData
            bucketsStore._CopyAllData = function() error("Simulated error") end

            expect(function() bucketsStore:UpdateNumBucketsAsync(5) end).to.throw()

            -- expect all of our data to still exist.
            expect(bucketsStore:GetTopScoresAsync(10)).to.be.deepEqual({
                {id = 5, score = 500},
                {id = 4, score = 400},
                {id = 2, score = 300},
                {id = 1, score = 200},
                {id = 3, score = 100},
            })

            local leaderboards = bucketsStore:GetBucketsAsync()
            expect(#leaderboards).to.be.equal(4)

            -- Now unpatch the function and check that updating num buckets is successful.
            bucketsStore._CopyAllData = copyAllData

            bucketsStore:UpdateNumBucketsAsync(5)

            leaderboards = bucketsStore:GetBucketsAsync()
            expect(#leaderboards).to.be.equal(5)

            expect(leaderboards).to.be.bucketsEqual({
                {
                    {id = 5, score = 500},
                },
                {
                    {id = 4, score = 400},
                },
                {
                    {id = 2, score = 300},
                },
                {
                    {id = 1, score = 200},
                },
                {
                    {id = 3, score = 100},
                }
            })
            
        end)
    end)
end