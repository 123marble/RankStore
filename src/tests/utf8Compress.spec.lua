local Util = require(game.ServerScriptService.Tests.util)

return function()
    local Utf8Compress = require(game.ServerScriptService.RankStore.utf8Compress)
    
    local ENCODING_LENGTH = 2
    beforeEach(function()
        expect.extend(Util.GetExpectationExtensions())
    end)

    afterEach(function()
        print("test completed...")
    end)
    
    it("TestCompressMin", function()
        local actual = Utf8Compress.Compress(20, ENCODING_LENGTH)
        
        expect(#actual).to.be.equal(2)

        local decompressed = Utf8Compress.Decompress(actual)
        expect(decompressed).to.be.equal(20)
    end)

    it("TestCompressMax", function()
        local actual = Utf8Compress.Compress(123456123456, ENCODING_LENGTH)
        
        expect(#actual).to.be.equal(8)

        local decompressed = Utf8Compress.Decompress(actual)
        expect(decompressed).to.be.equal(123456123456)
    end)

    it("TestCompressNewUserId", function() -- UserIds today are 10 chars long so let's verify how many characters we need to compress this.
                                                -- https://devforum.roblox.com/t/userids-are-going-over-32-bit-on-december-7th/903982
        local actual = Utf8Compress.Compress(1234567890, ENCODING_LENGTH)
        
        -- 1234567890 splits into 1234 and 567890. Which are 2 and 4 bytes respectively.
        expect(#actual).to.be.equal(6)

        local decompressed = Utf8Compress.Decompress(actual)
        expect(decompressed).to.be.equal(1234567890)
    end)
end