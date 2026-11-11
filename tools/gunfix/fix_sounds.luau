-- GUNFIX 9 Nov 2026: sounds the experience is not allowed to load ("User is not authorized to access Asset").
-- The AWP's three handling sounds take the AK's (which load); the unused death and footstep sounds that can never
-- load are removed. Applied in Multiplayer, campaign and Zombies. Run from the Command Bar or execute_luau (Edit).
local A = game.ReplicatedStorage.SPH_Assets
local swap = {
	["131162205463581"] = { Move1 = "rbxassetid://152206206", ClipPouch = "rbxassetid://4681162356" },
	["124419147113939"] = { Move2 = "rbxassetid://152206246" },
}
local dead = { ["104745788691591"] = true, ["2977012439"] = true, ["13593294325"] = true, ["5546573724"] = true }
local out = {}
for _, s in A:GetDescendants() do
	if s:IsA("Sound") then
		local id = s.SoundId:match("%d+")
		if id and swap[id] and swap[id][s.Name] then
			s.SoundId = swap[id][s.Name]
			table.insert(out, "swapped " .. s:GetFullName())
		elseif id and dead[id] then
			table.insert(out, "removed " .. s:GetFullName())
			s:Destroy()
		end
	end
end
return table.concat(out, "\n")
