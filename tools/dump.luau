-- Studio -> files. Run in the Command Bar (or execute_luau) of ONE place while
-- `python tools/syncback.py` is running. Set PLACE to "lobby", "campaign" or "zombies".
-- HttpEnabled is switched on only for the POST and restored straight after.
local PLACE = "lobby"

local HS = game:GetService("HttpService")
local roots = {
	game.ReplicatedStorage:FindFirstChild("Shared"),
	game.ServerScriptService,
	game.ServerStorage:FindFirstChild("Modules"),
	game.ServerStorage:FindFirstChild("_DevTools"),
	game.StarterPlayer:FindFirstChild("StarterPlayerScripts"),
	game.StarterPlayer:FindFirstChild("StarterCharacterScripts"),
}
local function rel(inst)
	local p, c = {}, inst
	while c and c ~= game do
		table.insert(p, 1, c.Name)
		c = c.Parent
	end
	return p
end
local entries, others = {}, {}
for _, root in ipairs(roots) do
	local list = root:GetDescendants()
	table.insert(list, 1, root)
	for _, d in ipairs(list) do
		if d:IsA("LuaSourceContainer") then
			local e = { path = rel(d), class = d.ClassName, source = d.Source }
			if d:IsA("BaseScript") then
				e.enabled = d.Enabled
				e.runContext = d.RunContext.Name
			end
			table.insert(entries, e)
		else
			table.insert(others, { path = rel(d), class = d.ClassName })
		end
	end
end
local body = HS:JSONEncode({ place = game.PlaceId, entries = entries, others = others })
local was = HS.HttpEnabled
HS.HttpEnabled = true
local ok, res = pcall(function()
	return HS:RequestAsync({
		Url = "http://127.0.0.1:34877/",
		Method = "POST",
		Headers = { ["X-Name"] = PLACE .. ".json" },
		Body = body,
	})
end)
HS.HttpEnabled = was
print(ok and ("synced " .. #entries .. " scripts as " .. PLACE) or ("sync failed: " .. tostring(res)))
