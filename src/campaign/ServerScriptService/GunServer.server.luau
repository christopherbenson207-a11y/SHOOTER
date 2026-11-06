-- Server authority for guns: the loadout and which gun is out, ammo per gun, reloads, fire
-- rate and hit validation. The client raycasts for instant feedback and reports what each
-- bullet or pellet hit; this script checks every report is physically plausible before
-- any damage, then hands each mob its hits from the shot in one go (MobReactions.Hit).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MobReactions = require(ServerStorage.Modules.MobReactions)
local WorldDamage = require(ServerStorage.Modules.WorldDamage)
-- WAR soldiers (this place has them): a hit soldier learns where the shot came from, so it and its
-- squad turn on the shooter (Soldier:CallOut) instead of the foe nearest itself.
local soldierModule = ServerStorage.Modules:FindFirstChild("Soldier")
local Soldier = nil
if soldierModule then
	local ok, mod = pcall(require, soldierModule)
	Soldier = if ok then mod else nil
	if not ok then
		warn("GunServer: Soldier: " .. tostring(mod))
	end
end
-- Heard by the Beacon (BeaconServer): every shot, and every bullet that stops in a part.
local Gunshot = ServerStorage.Events.Gunshot
local WorldShot = ServerStorage.Events.WorldShot
local Remotes = ReplicatedStorage.Remotes
-- FRONTLINE (workspace attribute Front, Shared.Front): players of the other side and its bots are targets too.
local PlayerHealth = require(ServerStorage.Modules.PlayerHealth)

local Validation = GameConfig.Validation
-- While down only this gun can be out (PlayerHealth); while being eaten, none.
local DOWNED_GUN = GameConfig.Player.Downed.Gun
local INFINITE_RESERVE = GameConfig.Debug.InfiniteReserve

-- Third-person guns and camos (4 Nov 2026, from the zombies GunServer). The gun in your hands (Assets.WorldGuns) sits
-- under the character's "WorldGun" model: welded to an invisible GunRoot held in front of the chest by GunJoint, with
-- RightGrip, LeftGrip and Muzzle attachments that WorldGunArms (client) bends everyone's arms to. In the player's camo
-- (Shared.Camo, from the Camos attribute that Profile publishes).
local WORLD_GUNS = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("WorldGuns")
-- Pack guns (5 Nov 2026): R15 conversions of the BZ1 Tactical Combat pack guns (Assets.PackGuns, retextured). A pack
-- gun hangs from the RightHand on a Motor6D whose Part1 is named as in the pack clips (Handle / RootPart), so the
-- pack animations (Shared.PackAnims, played by WorldGunArms) move the arms, the gun and its bolt, mag and slide.
-- No arm IK for these; GunRoot rides on the gun so its Muzzle stays at the barrel. Guns without a pack model keep
-- the chest hold and IK below.
local PACK_GUNS = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("PackGuns")
local HOLDS = {
	Rifle = CFrame.new(0.3, -0.1, -0.8),
	Pistol = CFrame.new(0.1, 0.15, -1.45),
}
local Camo = nil
do
	local m = ReplicatedStorage.Shared:FindFirstChild("Camo")
	if m then
		local ok, mod = pcall(require, m)
		Camo = if ok and type(mod) == "table" and mod.Apply then mod else nil
	end
end
-- Scopes and attachments (Shared.Attachments): the gun's numbers per player (MagSize, reload, falloff) and the
-- attachment models welded onto the world gun, under the camo.
local Attachments = require(ReplicatedStorage.Shared:WaitForChild("Attachments"))

local function worldHolder(character)
	local torso = character:FindFirstChild("UpperTorso")
	if not torso then
		return nil
	end
	local holder = character:FindFirstChild("WorldGun")
	if holder and holder:FindFirstChild("GunRoot") then
		local joint = holder.GunRoot:FindFirstChild("GunJoint")
		if joint and joint.Part0 ~= torso then
			joint.Part0 = torso -- the avatar loader swapped the torso
		end
		return holder
	end
	holder = Instance.new("Model")
	holder.Name = "WorldGun"
	local root = Instance.new("Part")
	root.Name = "GunRoot"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.CastShadow = false
	root.CFrame = torso.CFrame * HOLDS.Rifle
	for _, name in { "RightGrip", "LeftGrip", "Muzzle" } do
		local a = Instance.new("Attachment")
		a.Name = name
		a.Parent = root
	end
	root.Parent = holder
	holder.PrimaryPart = root
	local joint = Instance.new("Motor6D")
	joint.Name = "GunJoint"
	joint.Part0 = torso
	joint.Part1 = root
	joint.C0 = HOLDS.Rifle
	joint.Parent = root
	holder.Parent = character
	return holder
end

-- Shows gunName (nil: none) in the character's hands.
local function showWorldGun(player, gunName)
	local character = player.Character
	if not (WORLD_GUNS and character) then
		return
	end
	local holder = worldHolder(character)
	if not holder then
		return
	end
	local root = holder.GunRoot
	local old = holder:FindFirstChild("Gun")
	if old then
		old:Destroy()
	end
	local packSource = gunName and PACK_GUNS and PACK_GUNS:FindFirstChild(gunName)
	local hand = character:FindFirstChild("RightHand")
	if not (packSource and packSource.PrimaryPart and hand) then
		packSource = nil
	end
	local source = packSource or (gunName and WORLD_GUNS:FindFirstChild(gunName))
	local gun = source and GameConfig.Guns[gunName]
	holder:SetAttribute("Gun", if gun then gunName else nil)
	holder:SetAttribute("Pack", if gun and packSource then true else nil)
	if not gun then
		return
	end
	local model = source:Clone()
	model.Name = "Gun"
	local gunRoot = model:FindFirstChild("Root") or model.PrimaryPart
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.CastShadow = d.Size.Magnitude > 0.3
		end
	end
	-- Pack guns carry attachments only once they have their own mount set (MountSet attribute, Shared.Attachments).
	if not packSource or model:GetAttribute("MountSet") then
		Attachments.Dress(model, gunName, player, "World", true)
	elseif Camo and Camo.ForPlayer then
		pcall(Camo.Apply, model, gunName, Camo.ForPlayer(player, gunName))
	end
	if packSource then
		-- The pack's hand joint (HandC0/HandC1 attributes, from the R15 conversion). Part1 keeps the pack's part
		-- name, which is the pose name the clips key.
		local motor = Instance.new("Motor6D")
		motor.Name = "PackGrip"
		motor.Part0 = hand
		motor.Part1 = gunRoot
		motor.C0 = model:GetAttribute("HandC0") or CFrame.identity
		motor.C1 = model:GetAttribute("HandC1") or CFrame.identity
		motor.Parent = gunRoot
		model:PivotTo(hand.CFrame * motor.C0 * motor.C1:Inverse() * gunRoot.CFrame:ToObjectSpace(model:GetPivot()))
		root.GunJoint.Part0 = gunRoot
		root.GunJoint.C0 = CFrame.identity
		-- The Muzzle attachment may sit on the barrel part rather than the handle; measure it in handle space.
		local muzzle = model:FindFirstChild("Muzzle", true)
		local muzzleCF = if muzzle and muzzle:IsA("Attachment")
			then gunRoot.CFrame:ToObjectSpace(muzzle.WorldCFrame)
			else CFrame.identity
		for _, name in { "RightGrip", "LeftGrip", "Muzzle" } do
			local a = root:FindFirstChild(name)
			if a then
				a.CFrame = if name == "Muzzle" then muzzleCF else CFrame.identity
			end
		end
		model.Parent = holder
		return
	end
	local grip = gunRoot:FindFirstChild("Grip")
	local gripCF = if grip then grip.CFrame else CFrame.identity
	model:PivotTo(root.CFrame * gripCF:Inverse() * gunRoot.CFrame:ToObjectSpace(model:GetPivot()))
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = gunRoot
	weld.C0 = gripCF:Inverse()
	weld.Parent = gunRoot
	local function mark(name, from)
		local a = root:FindFirstChild(name)
		if a then
			a.CFrame = if from then gripCF:Inverse() * from.CFrame else CFrame.identity
		end
	end
	mark("RightGrip", grip)
	mark("LeftGrip", gunRoot:FindFirstChild("LeftGrip"))
	mark("Muzzle", gunRoot:FindFirstChild("Muzzle"))
	local hold = gun.Hold or (if gunName == "Pistol" then "Pistol" else "Rifle")
	root.GunJoint.C0 = HOLDS[hold] or HOLDS.Rifle
	model.Parent = holder
end

-- player -> { Current = gun name, Guns = { [gun name] = gun state } }
local loadouts = {}

local function newState(gunName, player)
	local gun = Attachments.ConfigFor(player, gunName) or GameConfig.Guns[gunName]
	return {
		GunName = gunName,
		Gun = gun,
		Mag = gun.MagSize,
		Reserve = gun.Reserve,
		Reloading = false,
		ReloadToken = 0,
		LastShot = 0,
		RecentShots = {},
	}
end

local function current(player)
	local loadout = loadouts[player]
	return loadout and loadout.Guns[loadout.Current]
end

local function syncAmmo(player, state)
	Remotes.AmmoSync:FireClient(player, state.GunName, state.Mag, state.Reserve)
end

local function stopReload(state)
	state.Reloading = false
	state.ReloadToken += 1
end

local function isFiniteVector(v)
	return typeof(v) == "Vector3" and v == v and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

-- frontSide: the shooter's side in FRONTLINE (nil otherwise). Then the nearest model with a Humanoid is the target if it is
-- on the other side (a player's Side attribute, a bot's model Side), and nothing if it is on the shooter's own.
local function getEnemyModel(part, frontSide)
	local node = part
	while node and node ~= workspace do
		if node:IsA("Model") then
			if frontSide then
				if node:FindFirstChildOfClass("Humanoid") then
					local owner = Players:GetPlayerFromCharacter(node)
					local side = if owner then owner:GetAttribute("Side") or "Ally" else node:GetAttribute("Side")
					return if side and side ~= frontSide then node else nil
				end
			elseif CollectionService:HasTag(node, "Enemy") then
				return node
			end
		end
		node = node.Parent
	end
	return nil
end

local function losParams()
	local ignore = { workspace:FindFirstChild("Fx") }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	for _, enemy in CollectionService:GetTagged("Enemy") do
		table.insert(ignore, enemy)
	end
	if workspace:GetAttribute("Front") then
		for _, ally in CollectionService:GetTagged("Ally") do
			table.insert(ignore, ally)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	return params
end

-- Keeps a 1-second window of shot times to stop remote spam.
local function tooManyShots(state, now)
	local recent = state.RecentShots
	local i = 1
	while i <= #recent do
		if now - recent[i] > 1 then
			table.remove(recent, i)
		else
			i += 1
		end
	end
	if #recent >= Validation.MaxShotsPerSecond then
		return true
	end
	table.insert(recent, now)
	return false
end

-- Checks one reported hit along a ray. index is its place along the ray (2 = the second
-- mob a penetrating round went through). Returns the enemy, damage, head flag and distance.
local function checkHit(state, origin, dir, hit, index, params)
	if typeof(hit) ~= "table" then
		return nil
	end
	local hitPart, hitPos = hit.Part, hit.Pos
	if typeof(hitPart) ~= "Instance" or not hitPart:IsA("BasePart") or not hitPart:IsDescendantOf(workspace) then
		return nil
	end
	if not isFiniteVector(hitPos) then
		return nil
	end
	local enemy = getEnemyModel(hitPart, state.FrontSide)
	if not enemy then
		return nil
	end
	local humanoid = enemy:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	local gun = state.Gun
	local toHit = hitPos - origin
	local dist = toHit.Magnitude
	if dist > gun.Range + 2 then
		return nil
	end
	-- The reported hit must lie close to the reported ray.
	local along = toHit:Dot(dir)
	if along <= 0 then
		return nil
	end
	if (toHit - dir * along).Magnitude > Validation.MaxRayMiss then
		return nil
	end
	-- And close to the part it claims to have hit (with slack for movement and ping).
	if (hitPart.Position - hitPos).Magnitude > hitPart.Size.Magnitude / 2 + Validation.MaxPartOffset then
		return nil
	end
	-- No world geometry between the shooter and the hit (mobs don't block: rounds go through).
	local block = workspace:Raycast(origin, toHit, params)
	if block and (block.Position - origin).Magnitude < dist - 1.5 then
		return nil
	end

	local falloff = math.clamp((dist - gun.FalloffStart) / (gun.FalloffEnd - gun.FalloffStart), 0, 1)
	local multiplier = 1 - falloff * (1 - gun.FalloffMin)
	local isHead = hitPart.Name == "Head" or hitPart:GetAttribute("Limb") == "Head"
	if isHead then
		multiplier *= gun.HeadMultiplier * (state.RelicHead or 1)
	end
	if index > 1 and gun.Penetration then
		multiplier *= gun.Penetration.DamageKeep ^ (index - 1)
	end
	-- Endless relics (ServerStorage.Modules.Relics) on the player: Iron Rounds, Headhunter.
	multiplier *= state.RelicDamage or 1
	return enemy, math.floor(gun.Damage * multiplier + 0.5), isHead, dist
end

-- Checks the world part a bullet stopped in ({ Part, Pos }). Returns the part, the point
-- and the bullet's damage there, or nil.
local function checkWorldHit(state, origin, dir, hit, params)
	if typeof(hit) ~= "table" then
		return nil
	end
	local part, pos = hit.Part, hit.Pos
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) or getEnemyModel(part) then
		return nil
	end
	local model = part:FindFirstAncestorWhichIsA("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return nil
	end
	if not isFiniteVector(pos) then
		return nil
	end
	local gun = state.Gun
	local toHit = pos - origin
	local dist = toHit.Magnitude
	local along = toHit:Dot(dir)
	if dist > gun.Range + 2 or along <= 0 or (toHit - dir * along).Magnitude > Validation.MaxRayMiss then
		return nil
	end
	if (part.Position - pos).Magnitude > part.Size.Magnitude / 2 + Validation.MaxPartOffset then
		return nil
	end
	-- The first thing along the ray must be that part (or something right at the hit).
	local first = workspace:Raycast(origin, toHit + dir * 0.5, params)
	if not first or (first.Instance ~= part and (first.Position - pos).Magnitude > 1.5) then
		return nil
	end
	local falloff = math.clamp((dist - gun.FalloffStart) / (gun.FalloffEnd - gun.FalloffStart), 0, 1)
	return part, pos, gun.Damage * (1 - falloff * (1 - gun.FalloffMin))
end

-- shots: one entry per bullet or pellet: { Dir, End, Hits = { { Part, Pos }, ... }, World },
-- the hits in order along the ray, at most one per mob, and World = { Part, Pos } when the
-- bullet stopped in the world.
-- fwjelaa-ignore: remote-unvalidated-args (gunName must equal the server's own state.GunName)
Remotes.Fire.OnServerEvent:Connect(function(player, origin, gunName, shots)
	local state = current(player)
	if not state or gunName ~= state.GunName then
		return
	end
	if not isFiniteVector(origin) or typeof(shots) ~= "table" then
		return
	end
	local gun = state.Gun
	local count = #shots
	if count < 1 or count > (gun.Pellets or 1) then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	if not humanoid or humanoid.Health <= 0 or not head then
		return
	end
	if character:GetAttribute("Devoured") or character:GetAttribute("Bandaging")
		or (character:GetAttribute("Downed") and gunName ~= DOWNED_GUN) then
		return
	end
	-- A shot gives a hiding player away to zombies for a moment (MobAI reads FiredAt).
	local serverNow = workspace:GetServerTimeNow()
	if serverNow - (character:GetAttribute("FiredAt") or 0) > 0.5 then
		character:SetAttribute("FiredAt", serverNow)
	end

	local now = os.clock()
	if state.Reloading then
		-- Firing breaks off a shell-by-shell reload; a mag reload has to finish.
		if gun.ReloadStyle == "Shells" and state.Mag > 0 then
			stopReload(state)
		else
			syncAmmo(player, state)
			return
		end
	end
	if state.Mag <= 0 then
		syncAmmo(player, state)
		return
	end
	if now - state.LastShot < (60 / gun.RPM) * Validation.FireRateTolerance then
		return
	end
	if tooManyShots(state, now) then
		return
	end

	state.LastShot = now
	state.Mag -= 1

	if (origin - head.Position).Magnitude > Validation.MaxOriginOffset then
		return
	end
	Gunshot:Fire(player, origin)

	-- Every pellet leaves inside the gun's cone around the shot's mean direction.
	local dirs = {}
	local mean = Vector3.zero
	for i, shot in shots do
		if typeof(shot) ~= "table" or not isFiniteVector(shot.Dir) then
			return
		end
		local len = shot.Dir.Magnitude
		if len < 0.9 or len > 1.1 then
			return
		end
		dirs[i] = shot.Dir / len
		mean += dirs[i]
	end
	if mean.Magnitude < 0.5 then
		return
	end
	mean = mean.Unit
	local cone = math.rad((gun.PelletSpread or 0) + gun.Spread.Max + Validation.ConeSlack)
	for _, d in dirs do
		if math.acos(math.clamp(d:Dot(mean), -1, 1)) > cone then
			return
		end
	end

	local params = losParams()
	state.FrontSide = if workspace:GetAttribute("Front") then player:GetAttribute("Side") or "Ally" else nil
	state.RelicDamage = 1 + (player:GetAttribute("RelicDamage") or 0)
	state.RelicHead = 1 + (player:GetAttribute("RelicHead") or 0)
	local maxHits = if gun.Penetration then gun.Penetration.Count else 1
	local ends = {}
	local worldHits = {}
	local byEnemy = {}
	local order = {}
	for i, shot in shots do
		local dir = dirs[i]
		-- Clamp the reported end point to the gun's range for effects.
		local endPos = shot.End
		if not isFiniteVector(endPos) or (endPos - origin).Magnitude > gun.Range then
			endPos = origin + dir * gun.Range
		end
		ends[i] = endPos
		local part, pos, damage = checkWorldHit(state, origin, dir, shot.World, params)
		if part then
			table.insert(worldHits, { Part = part, Pos = pos, Dir = dir, Damage = damage, Radius = gun.BreakRadius })
		end
		if typeof(shot.Hits) == "table" then
			local seen = {}
			for index = 1, math.min(#shot.Hits, maxHits) do
				local hit = shot.Hits[index]
				local enemy, damage, isHead, dist = checkHit(state, origin, dir, hit, index, params)
				if enemy and not seen[enemy] then
					seen[enemy] = true
					local entry = byEnemy[enemy]
					if not entry then
						entry = { Hits = {}, Dist = dist, Dir = Vector3.zero }
						byEnemy[enemy] = entry
						table.insert(order, enemy)
					end
					table.insert(entry.Hits, { Part = hit.Part, Damage = damage, Pos = hit.Pos, IsHead = isHead })
					entry.Dir += dir
					entry.Dist = math.min(entry.Dist, dist)
				end
			end
		end
	end

	for _, other in Players:GetPlayers() do
		if other ~= player then
			Remotes.ShotFx:FireClient(other, player, ends, state.GunName)
		end
	end

	for _, w in worldHits do
		WorldDamage.Hit(w.Part, w.Pos, w.Dir, w.Damage, w.Radius)
		WorldShot:Fire(player, w.Part, w.Pos, w.Damage)
	end

	for _, enemy in order do
		local entry = byEnemy[enemy]
		local isHead = false
		for _, hit in entry.Hits do
			isHead = isHead or hit.IsHead
		end
		local soldier = Soldier and Soldier.FromModel(enemy)
		if soldier then
			soldier.HurtFrom = origin
		end
		if state.FrontSide then
			-- Kill credit (FrontServer reads it when the body falls).
			enemy:SetAttribute("LastHitBy", player.UserId)
			enemy:SetAttribute("LastHitAt", workspace:GetServerTimeNow())
			enemy:SetAttribute("LastHitHead", isHead)
		end
		local target = Players:GetPlayerFromCharacter(enemy)
		if state.FrontSide and (target or not CollectionService:HasTag(enemy, "Enemy")) then
			-- A player of the other side, or a HOUND bot hit by a Lamplighter: plain damage, no mob reactions.
			local total = 0
			for _, hit in entry.Hits do
				total += hit.Damage
			end
			local humanoid = enemy:FindFirstChildOfClass("Humanoid")
			if target then
				PlayerHealth.Damage(target, total, origin, "Bullet")
			elseif soldier then
				soldier:Hurt(total, origin)
			elseif humanoid then
				humanoid:TakeDamage(total)
			end
			Remotes.HitConfirm:FireClient(player, enemy, isHead, humanoid ~= nil and humanoid.Health <= 0, false)
			continue
		end
		local killed, severed = MobReactions.Hit(enemy, entry.Hits, {
			Player = player,
			Gun = gun,
			GunName = state.GunName,
			HitPos = entry.Hits[1].Pos,
			Dir = entry.Dir.Unit,
			Distance = entry.Dist,
			Share = #entry.Hits / count,
		})
		Remotes.HitConfirm:FireClient(player, enemy, isHead, killed, severed)
	end
end)

-- "Stop" ends a shell-by-shell reload early (the client fired or switched).
-- fwjelaa-ignore: remote-unvalidated-args (command is only ever compared to "Stop")
Remotes.Reload.OnServerEvent:Connect(function(player, command)
	local state = current(player)
	if not state then
		return
	end
	local gun = state.Gun
	if command == "Stop" then
		if state.Reloading then
			stopReload(state)
			syncAmmo(player, state)
		end
		return
	end
	if state.Reloading or state.Mag >= gun.MagSize or (state.Reserve <= 0 and not INFINITE_RESERVE) then
		syncAmmo(player, state)
		return
	end

	state.Reloading = true
	state.ReloadToken += 1
	local token = state.ReloadToken
	local function stillLoading()
		return loadouts[player] ~= nil and current(player) == state and state.ReloadToken == token
	end

	-- Other players see the reload on the body (WorldGunArms plays the pack clip at this length).
	local character = player.Character
	if character then
		local mark = if gun.ReloadStyle == "Shells"
			then "Shells"
			else "Mag:" .. (if state.Mag == 0 then gun.ReloadEmptyTime else gun.ReloadTime)
		character:SetAttribute("Reload", mark)
		task.spawn(function()
			while stillLoading() and state.Reloading and character.Parent do
				task.wait(0.1)
			end
			if character:GetAttribute("Reload") == mark then
				character:SetAttribute("Reload", nil)
			end
		end)
	end

	-- Timers run a little short of the client's so the server is never the one holding a shot back.
	if gun.ReloadStyle == "Shells" then
		local timing = gun.ShellReload
		task.spawn(function()
			task.wait(timing.StartTime * 0.85)
			while stillLoading() and state.Mag < gun.MagSize and (INFINITE_RESERVE or state.Reserve > 0) do
				task.wait(timing.ShellTime * 0.85)
				if not stillLoading() then
					return
				end
				state.Mag += 1
				if not INFINITE_RESERVE then
					state.Reserve -= 1
				end
			end
			if stillLoading() then
				state.Reloading = false
				syncAmmo(player, state)
			end
		end)
		return
	end

	local duration = (if state.Mag == 0 then gun.ReloadEmptyTime else gun.ReloadTime) * 0.85
	task.delay(duration, function()
		if not stillLoading() then
			return
		end
		local need = gun.MagSize - state.Mag
		local take = if INFINITE_RESERVE then need else math.min(need, state.Reserve)
		state.Mag += take
		if not INFINITE_RESERVE then
			state.Reserve -= take
		end
		state.Reloading = false
		syncAmmo(player, state)
	end)
end)

-- Switching guns drops any reload in progress on the old one.
-- Guns you carry are in your inventory (ServerStorage.Modules.Inventory, read here from the
-- "Inventory" attribute). The downed pistol works while you're down, carried or not.
local function carries(player, gunName)
	local inventory = player:GetAttribute("Inventory") or ""
	return string.find("|" .. inventory, "|" .. gunName .. ":", 1, true) ~= nil
end

Remotes.Equip.OnServerEvent:Connect(function(player, gunName)
	local loadout = loadouts[player]
	if not loadout or typeof(gunName) ~= "string" or not loadout.Guns[gunName] then
		return
	end
	local character = player.Character
	local downed = character and character:GetAttribute("Downed")
	if downed and gunName ~= DOWNED_GUN then
		return
	end
	if not downed and not carries(player, gunName) then
		return
	end
	local old = loadout.Guns[loadout.Current]
	if old and old.Reloading then
		stopReload(old)
		syncAmmo(player, old)
	end
	loadout.Current = gunName
	syncAmmo(player, loadout.Guns[gunName])
	showWorldGun(player, gunName)
end)

local function onCharacter(player)
	local loadout = { Current = GameConfig.Loadout[1], Guns = {} }
	for _, name in GameConfig.Loadout do
		loadout.Guns[name] = newState(name, player)
	end
	loadouts[player] = loadout
	for _, state in loadout.Guns do
		syncAmmo(player, state)
	end
	local character = player.Character
	if character and WORLD_GUNS then
		showWorldGun(player, if carries(player, loadout.Current) then loadout.Current else nil)
		-- The avatar loader can swap the body parts after spawn: put the gun back on the new torso.
		character.ChildAdded:Connect(function(child)
			if child.Name == "UpperTorso" and child:IsA("BasePart") then
				task.defer(function()
					if player.Character == character and loadouts[player] == loadout then
						showWorldGun(player, loadout.Current)
					end
				end)
			end
		end)
	end
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function()
		onCharacter(player)
	end)
	-- A new camo shows on the gun in your hands; a gun you no longer carry leaves your hands.
	player:GetAttributeChangedSignal("Camos"):Connect(function()
		local loadout = loadouts[player]
		if loadout then
			showWorldGun(player, loadout.Current)
		end
	end)
	-- New attachments (lobby picks, or the zombies Gunsmith's run-only ones): new numbers and a redressed gun.
	local function refreshAttachments()
		local loadout = loadouts[player]
		if not loadout then
			return
		end
		for name, state in loadout.Guns do
			state.Gun = Attachments.ConfigFor(player, name) or state.Gun
			if state.Mag > state.Gun.MagSize then
				state.Mag = state.Gun.MagSize
			end
			syncAmmo(player, state)
		end
		showWorldGun(player, loadout.Current)
	end
	player:GetAttributeChangedSignal("Attach"):Connect(refreshAttachments)
	player:GetAttributeChangedSignal("RunAttach"):Connect(refreshAttachments)
	player:GetAttributeChangedSignal("Inventory"):Connect(function()
		local loadout = loadouts[player]
		local character = player.Character
		if loadout and character and not character:GetAttribute("Downed") then
			showWorldGun(player, if carries(player, loadout.Current) then loadout.Current else nil)
		end
	end)
	if player.Character then
		onCharacter(player)
	end
end

-- Pickups (InteractServer) reach gun state through this: GunsApi:Invoke(action, player, ...).
--   "GiveAmmo", magazines?: refills the guns you carry, to their full Reserve or by that many
--     magazines. Returns the rounds that went in (0 = you were full, leave the can).
--   "GetAmmo", gun: that gun's mag and reserve (to drop it with them).
--   "SetAmmo", gun, mag, reserve: a gun just picked up.
--   "Equip", gun: puts it in your hands on the server (the client follows via its hotbar).
--   "Current": the gun in your hands.
local gunsApi = Instance.new("BindableFunction")
gunsApi.Name = "GunsApi"
gunsApi.OnInvoke = function(action, player, a, b, c)
	local loadout = loadouts[player]
	if not loadout then
		return nil
	end
	if action == "GiveAmmo" then
		local total = 0
		for name, state in loadout.Guns do
			if carries(player, name) then
				local room = state.Gun.Reserve - state.Reserve
				local add = if a then math.min(state.Gun.MagSize * a, room) else room
				if add > 0 then
					state.Reserve += add
					total += add
					syncAmmo(player, state)
				end
			end
		end
		return total
	elseif action == "GetAmmo" then
		local state = loadout.Guns[a]
		return state and state.Mag, state and state.Reserve
	elseif action == "SetAmmo" then
		local state = loadout.Guns[a]
		if state then
			stopReload(state)
			state.Mag = math.clamp(b or state.Gun.MagSize, 0, state.Gun.MagSize)
			state.Reserve = math.clamp(c or state.Gun.Reserve, 0, state.Gun.Reserve)
			syncAmmo(player, state)
		end
	elseif action == "Equip" then
		if loadout.Guns[a] then
			local old = loadout.Guns[loadout.Current]
			if old and old.Reloading then
				stopReload(old)
			end
			loadout.Current = a
			showWorldGun(player, a)
		end
	elseif action == "Current" then
		return loadout.Current
	end
	return nil
end
gunsApi.Parent = ServerStorage

Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerRemoving:Connect(function(player)
	loadouts[player] = nil
end)
