local RankStore = require(game.ServerScriptService.RankStore)

local rankStore = RankStore.GetRankStore("TestLeaderboard_1", 4)

rankStore:ClearAsync()

print(rankStore:GetTopScoresAsync(10))

print(rankStore:SetScoreAsync(1, 25))
print(rankStore:SetScoreAsync(2, 50))
print(rankStore:SetScoreAsync(3, 20))
print(rankStore:SetScoreAsync(4, 75))
print(rankStore:SetScoreAsync(5, 45))
print(rankStore:SetScoreAsync(1, 65))

print(rankStore:GetTopScoresAsync(10))

print(rankStore:GetEntryAsync(3))