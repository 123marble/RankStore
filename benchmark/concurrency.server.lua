local ds = game:GetService("DataStoreService"):GetDataStore("myDatastore")

ds:SetAsync("key", "This is some data")

local options = Instance.new("DataStoreGetOptions")
options.UseCache = false
while wait(1) do
	for _ = 1, 1 do
		for _ = 1, 10 do
			spawn(function()print(ds:GetAsync("key", options))end)
		end
	end
end