local Util = require(game.ServerScriptService.Tests.util)

return function()
    local Utf8Compress = require(game.ServerScriptService.RankStore.utf8Compress)
    
    beforeEach(function()
        expect.extend(Util.GetExpectationExtensions())
    end)

    afterEach(function()
        print("test completed...")
    end)
    
    it("TestCompressInt8", function()
        local actual = Utf8Compress.CompressInt(20, 1)
        
        expect(#actual).to.be.equal(1)

        local decompressed = Utf8Compress.DecompressInt(actual)
        expect(decompressed).to.be.equal(20)
    end)

    it("TestCompressInt40", function()
        local actual = Utf8Compress.CompressInt(12345678901, 6)
        
        expect(#actual).to.be.equal(6)

        local decompressed = Utf8Compress.DecompressInt(actual)
        expect(decompressed).to.be.equal(12345678901)
    end)
end