-- GUNFIX 11 Nov c: the Medkit gets its own hotbar tile and key (owner: "make it into inventory"). The count stays the
-- player attribute "Medkits" (ServerStorage.Modules.Bandages); the tile is a copy of the last authored hotbar button,
-- named "Medkit", with the GunSystem medkit mesh as its icon. Run in Multiplayer, campaign and Zombies (Edit).
local MARK = "GUNFIX 11 Nov c"
local RS, SP, SS = game.ReplicatedStorage, game.StarterPlayer, game.ServerStorage
local function rep(s, old, new, count)
	local n = 0
	local out = s:gsub(old:gsub("%p", "%%%0"), function() n += 1 return new end)
	if n ~= (count or 1) then error("hits " .. n .. " for " .. old) end
	return out
end
local jobs = {}
jobs[1] = { SS.Modules.Bandages, function(s)
	s = rep(s, 'character:SetAttribute("HealTime", applyTime)', 'character:SetAttribute("HealTime", applyTime)\n\tcharacter:SetAttribute("HealItem", if med then "Medkit" else "Bandage") -- ' .. MARK)
	s = rep(s, 'character:SetAttribute("HealTime", nil)', 'character:SetAttribute("HealTime", nil)\n\tcharacter:SetAttribute("HealItem", nil)')
	return s
end }
jobs[2] = { SP.StarterPlayerScripts.Hotbar, function(s)
	s = rep(s, '\tif wantsMedkit() then Remotes.Bandage:FireServer("Medkit") return end\n', "")
	s = rep(s, ' .. medText(item) else ""', ' else ""')
	s = rep(s, 'if button:IsA("GuiButton") then', 'if button:IsA("GuiButton") and button.Name ~= "Medkit" then')
	s = rep(s, 'local done = character and character:GetAttribute("BandageDone")', 'local done = character and character:GetAttribute("HealItem") ~= "Medkit" and character:GetAttribute("BandageDone") or nil')
	return s .. [==[

-- GUNFIX 11 Nov c: the Medkit tile (HUD.Hotbar.Medkit, a copy of the bandage tile). Its count is the player
-- attribute "Medkits"; its key is the Controls action "Medkit". Using one is Remotes.Bandage:FireServer("Medkit").
do
	local tile = nil
	local function useMedkit()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local hurt = humanoid and (humanoid.Health < humanoid.MaxHealth or (character:GetAttribute("Trauma") or 0) > 0)
		if medkits() <= 0 or not hurt or character:GetAttribute("Bandaging") or character:GetAttribute("Downed") then
			if tile then
				flash({ Stroke = tile:FindFirstChildOfClass("UIStroke") })
			end
			return
		end
		Remotes.Bandage:FireServer("Medkit")
	end
	local function redraw()
		if not tile or not tile.Parent then
			return
		end
		local n = medkits()
		tile.Count.Text = if n > 0 then "x" .. n else ""
		tile.BackgroundTransparency = if n > 0 then IDLE_BACK else EMPTY_BACK
		tile.Icon.Visible = n > 0
		local keyLabel = tile:FindFirstChild("Key")
		if keyLabel then
			local key = Controls.Short("Medkit", Controls.ActiveDevice())
			keyLabel.Text = key
			keyLabel.Visible = player:GetAttribute("TouchHud") ~= true and key ~= ""
		end
	end
	local function bindTile(hud)
		local bar = hud:WaitForChild("Hotbar")
		tile = bar:WaitForChild("Medkit", 5)
		if not tile then
			return
		end
		tile:WaitForChild("Icon")
		task.defer(showModel, tile.Icon, Assets.Icons:FindFirstChild("Medkit"), nil)
		tile.Activated:Connect(useMedkit)
		redraw()
	end
	player:GetAttributeChangedSignal("Medkits"):Connect(redraw)
	player:GetAttributeChangedSignal("TouchHud"):Connect(redraw)
	Controls.Changed:Connect(redraw)
	Platform.Changed:Connect(redraw)
	Controls.Bind("Medkit", "Medkit", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and not Controls.Listening then
			useMedkit()
		end
		return Enum.ContextActionResult.Sink
	end)
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "HUD" then
			bindTile(child)
		end
	end)
	if playerGui:FindFirstChild("HUD") then
		task.spawn(bindTile, playerGui.HUD)
	end
	RunService.RenderStepped:Connect(function()
		if not tile or not tile.Parent then
			return
		end
		local character = player.Character
		local healing = character and character:GetAttribute("HealItem") == "Medkit"
		local done = healing and character:GetAttribute("BandageDone")
		local k = 0
		if done then
			k = math.clamp(1 - (done - workspace:GetServerTimeNow()) / (character:GetAttribute("HealTime") or 3.3), 0, 1)
		end
		tile.Fill.Size = UDim2.fromScale(1, k)
		tile.Accent.Visible = healing == true
	end)
end
]==]
end }
jobs[3] = { RS.Shared.Controls, function(s)
	return rep(s, '{ Name = "Bandage", Label = "Bandage", Kb = { K.H }, Pad = { K.DPadDown } },', '{ Name = "Bandage", Label = "Bandage", Kb = { K.H }, Pad = { K.DPadDown } },\n\t-- ' .. MARK .. ': the Medkit tile of the hotbar.\n\t{ Name = "Medkit", Label = "Medkit", Kb = { K.M }, Pad = {} },')
end }
local out, ready = {}, {}
for i, job in jobs do
	local src = job[1].Source
	if src:find(MARK, 1, true) then
		table.insert(out, job[1].Name .. ": already")
	else
		local ok, new = pcall(job[2], src)
		if not ok then return "FAILED " .. job[1].Name .. ": " .. tostring(new) end
		local fn, err = loadstring(new)
		if not fn then return "COMPILE ERROR " .. job[1].Name .. ": " .. tostring(err) end
		ready[i] = { job[1], new }
	end
end
for _, r in ready do
	game:GetService("ScriptEditorService"):UpdateSourceAsync(r[1], function() return r[2] end)
	table.insert(out, r[1].Name .. " -> " .. #r[1].Source)
end
-- the icon model and the authored tile
local icons = RS.Assets.Icons
if not icons:FindFirstChild("Medkit") then
	local ok, mesh = pcall(function()
		return game:GetService("InsertService"):CreateMeshPartAsync("rbxassetid://504966484", Enum.CollisionFidelity.Box, Enum.RenderFidelity.Automatic)
	end)
	if ok and mesh then
		mesh.Name = "Handle"
		mesh.TextureID = "rbxassetid://504966509"
		mesh.Size = Vector3.new(1.814, 0.866, 1.281)
		mesh.Anchored = true
		local model = Instance.new("Model")
		model.Name = "Medkit"
		mesh.Parent = model
		model.PrimaryPart = mesh
		model:SetAttribute("Kind", "Medkit")
		model.Parent = icons
		table.insert(out, "icon made")
	else
		table.insert(out, "ICON FAILED: " .. tostring(mesh))
	end
end
local bar = game.StarterGui.HUD.Hotbar
if not bar:FindFirstChild("Medkit") then
	local last = nil
	for _, b in bar:GetChildren() do
		if b:IsA("GuiButton") and (not last or b.LayoutOrder > last.LayoutOrder) then last = b end
	end
	local tile = last:Clone()
	tile.Name = "Medkit"
	tile.LayoutOrder = last.LayoutOrder + 1
	tile.Icon:ClearAllChildren()
	tile.Count.Text = ""
	tile.Parent = bar
	table.insert(out, "tile made from " .. last.Name .. " (order " .. tile.LayoutOrder .. ")")
end
return table.concat(out, "\n")
