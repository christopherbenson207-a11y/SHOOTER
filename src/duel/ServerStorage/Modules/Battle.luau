-- WAR's battle (horror-shooter/war/BATTLE-PLAN.md): HOUND against the Lamplighters, Size soldiers a
-- side. Numbers: GameConfig.War.Battle. The soldiers' own brains are Modules.Soldier.
--   HOUND: Size slots. A player holds a slot, or a bot does ("Ally": callsign, rig and fireteam by
--   slot). A player joining takes the calmest bot's slot and its place (Claim); a player leaving
--   gives the slot back to a bot where they stood (Release). A fallen bot comes back at the spawn
--   (the step's checkpoint) after BotRespawn seconds, unless the story has stopped reinforcements
--   (SetReinforce); HoundLoss takes one bot out for the story (the squad cut down at the LZ).
--   HOUND's orders: HoundAttack (three fireteams: the centre lane and LaneWidth studs out to either
--   side, closing on the objective) or HoundHold (cover round a point, facing where the enemy
--   comes from).
--   Lamplighters: at most Size on the field. EnemyDefend puts one on every post (a post's Kind
--   attribute picks the soldier), fills the field from the rear and keeps a reserve (pool) that
--   walks in from the rear as they fall. EnemyAttack queues soldiers that push at a point (the hold
--   waves). A new one appears at least SpawnClear studs from HOUND and out of every player's sight
--   when it can. RetireEnemies sends the survivors back; each vanishes once no player sees it.
-- workspace EnemyLeft: Lamplighters on the field plus those still to come.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Soldier = require(script.Parent.Soldier)
local CoverMap = require(script.Parent.CoverMap)

local B = GameConfig.War.Battle
local LANES = { 0, -1, 1 } -- fireteam 1 up the middle, 2 left, 3 right

local Battle = {}
Battle.OnContact = nil -- function(soldier): a HOUND bot has the enemy in sight

local on = false
local gen = 0
local houndRespawn = true
local slots = {} -- [i] = { Index, Callsign, Rig, Gun, Team, Player, Bot, DownAt }
local hound = { Spawn = CFrame.new(), Plan = nil }
local foe = { Field = {}, Queue = {}, Pool = 0, Posts = {}, Rear = {}, From = nil, Due = nil, Filling = false }
local retiring = {} -- [soldier] = os.clock() it was sent back

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function between(range)
	return range.Min + math.random() * (range.Max - range.Min)
end

local function inMatch()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("InMatch") then
			table.insert(list, p)
		end
	end
	return list
end

-- Sight and distance -------------------------------------------------------------------------------

-- Where everyone on HOUND is: the players in the match and the bots.
local function houndPoints()
	local list = {}
	for _, p in inMatch() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root then
			table.insert(list, root.Position)
		end
	end
	for _, s in Soldier.All("Ally") do
		table.insert(list, s.Root.Position)
	end
	return list
end

-- True if any player in the match has a clear line from their head to pos.
local function seenByPlayer(pos)
	local ignore, heads = {}, {}
	for _, name in { "Squad", "Hostiles", "Fx" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, p in inMatch() do
		local c = p.Character
		local head = c and c:FindFirstChild("Head")
		if head then
			table.insert(heads, head.Position)
			table.insert(ignore, c)
		end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	rp.RespectCanCollide = true
	for _, h in heads do
		if (h - pos).Magnitude < 300 and not workspace:Raycast(h, pos - h, rp) then
			return true
		end
	end
	return false
end

-- Of spots (parts), one at least SpawnClear studs from HOUND and out of every player's sight (in a
-- shuffled order), else the one farthest from HOUND.
local function pickSpot(spots)
	if #spots == 0 then
		return nil
	end
	local points = houndPoints()
	local order = table.clone(spots)
	for i = #order, 2, -1 do
		local j = math.random(i)
		order[i], order[j] = order[j], order[i]
	end
	local best, bestD = nil, -1
	for _, spot in order do
		local at = spot.Position + Vector3.new(0, 3, 0)
		local near = math.huge
		for _, q in points do
			near = math.min(near, (q - at).Magnitude)
		end
		if near >= B.SpawnClear and not seenByPlayer(at) then
			return spot
		end
		if near > bestD then
			best, bestD = spot, near
		end
	end
	return best
end

-- A standing place a few studs round a spot, on surveyed ground when there is some.
local function near(spot, spread)
	local at = spot.Position + Vector3.new((math.random() * 2 - 1) * spread, 0, (math.random() * 2 - 1) * spread)
	local g = CoverMap.Snap(at, spread + 1)
	return CFrame.new((g or spot.Position) + Vector3.new(0, 3, 0))
end

-- HOUND --------------------------------------------------------------------------------------------------

local function houndOrder(slot)
	local plan = hound.Plan
	if not plan then
		return { Mode = "Hold", Goal = hound.Spawn.Position, Radius = 16 }
	end
	if plan.Mode == "Attack" then
		local lane = LANES[(slot.Team - 1) % #LANES + 1] * B.LaneWidth
		local goal = plan.Goal + plan.Right * lane * 0.35
		return { Mode = "Attack", Goal = goal, Radius = plan.Radius, LaneA = plan.From + plan.Right * lane * 0.5, LaneB = goal, Facing = plan.Facing }
	end
	return { Mode = "Hold", Goal = plan.Goal, Radius = plan.Radius, Facing = plan.Facing }
end

-- Where slot's bot appears: a ring round the spawn, facing the objective.
local function spawnPoint(slot)
	local base = hound.Spawn.Position
	local a = slot.Index / B.Size * math.pi * 2
	local at = base + Vector3.new(math.cos(a) * 5, 0, math.sin(a) * 5)
	local g = CoverMap.Snap(at, 8)
	local pos = if g then g + Vector3.new(0, 3, 0) else at
	local look = if hound.Plan then flat(hound.Plan.Goal - pos) else Vector3.zero
	return if look.Magnitude > 1 then CFrame.lookAt(pos, pos + look) else CFrame.new(pos)
end

local function spawnBot(slot, cf)
	local s = Soldier.Spawn("Ally", cf, {
		Callsign = slot.Callsign,
		Rig = slot.Rig,
		Gun = slot.Gun,
		Slot = slot.Index,
		Team = slot.Team,
		Order = houndOrder(slot),
	})
	s.OnContact = function(soldier)
		if Battle.OnContact then
			Battle.OnContact(soldier)
		end
	end
	s.OnDied = function()
		if slot.Bot == s then
			slot.Bot = nil
			slot.DownAt = os.clock()
		end
	end
	slot.Bot, slot.DownAt = s, nil
	return s
end

local function orderBots()
	for _, slot in slots do
		if slot.Bot and slot.Bot.Alive then
			slot.Bot:SetOrder(houndOrder(slot))
		end
	end
end

-- The Lamplighters ----------------------------------------------------------------------------------

local function spawnEnemy(kind, cf, order)
	local s = Soldier.Spawn(kind, cf, { Order = order })
	foe.Field[s] = true
	s.OnDied = function()
		foe.Field[s] = nil
	end
	return s
end

local function fieldCount()
	local n = 0
	for s in foe.Field do
		if s.Alive then
			n += 1
		else
			foe.Field[s] = nil
		end
	end
	return n
end

-- A defender holds cover within DefendRadius of its post, facing HOUND's way in.
local function defendOrder(post)
	return { Mode = "Defend", Goal = post, Radius = B.DefendRadius, Facing = if foe.From then { foe.From } else nil }
end

-- An attacker pushes from where it starts to goal, a little off the straight line.
local function attackOrder(from, goal)
	local fwd = flat(goal - from)
	fwd = if fwd.Magnitude > 1 then fwd.Unit else Vector3.new(0, 0, -1)
	local right = fwd:Cross(Vector3.yAxis)
	local lane = (math.random() * 2 - 1) * B.LaneWidth * 0.6
	local g = goal + right * lane * 0.3
	return { Mode = "Attack", Goal = g, Radius = B.AttackRadius, LaneA = from + right * lane * 0.5, LaneB = g, Facing = { goal } }
end

-- The post with the fewest defenders sent to it (where a reinforcement goes).
local function thinnestPost()
	local best, bestN = nil, math.huge
	for _, spot in foe.Posts do
		local n = 0
		for s in foe.Field do
			if s.Alive and s.Order.Goal and flatDist(s.Order.Goal, spot.Position) < 2 then
				n += 1
			end
		end
		if n < bestN then
			best, bestN = spot, n
		end
	end
	return best
end

-- Tops the field up: queued attackers first (a third of a second apart), else one from the reserve
-- (quickly while the field first fills, then ReinforceDelay after each loss).
local function reinforce(now)
	if fieldCount() >= B.Size then
		foe.Filling, foe.Due = false, nil
		return
	end
	if #foe.Queue == 0 and foe.Pool <= 0 then
		return
	end
	if not foe.Due then
		foe.Due = now + (if foe.Filling or #foe.Queue > 0 then 0.35 else between(B.ReinforceDelay))
	end
	if now < foe.Due then
		return
	end
	foe.Due = nil
	local wave = table.remove(foe.Queue, 1)
	if wave then
		local spot = pickSpot(wave.Spots)
		if spot then
			local cf = near(spot, 3)
			spawnEnemy(wave.Kind, cf, attackOrder(cf.Position, wave.Goal))
		end
		return
	end
	local spot = pickSpot(if #foe.Rear > 0 then foe.Rear else foe.Posts)
	if not spot then
		foe.Pool = 0
		return
	end
	foe.Pool -= 1
	local post = thinnestPost()
	spawnEnemy("Lamplighter", near(spot, 3), defendOrder(if post then post.Position else spot.Position))
end

-- Survivors sent back vanish once no player can see them (or after 25 seconds).
local function retire(now)
	for s, at in retiring do
		if not s.Alive then
			retiring[s] = nil
		elseif now - at > 25 or (now - at > 2 and not seenByPlayer(s.Root.Position + Vector3.new(0, 1.5, 0))) then
			retiring[s] = nil
			s:Remove()
		end
	end
end

-- The loop ------------------------------------------------------------------------------------------

local function loop(mine)
	while on and gen == mine do
		local now = os.clock()
		for _, slot in slots do
			local p = slot.Player
			if p and (not p.Parent or not p:GetAttribute("InMatch")) then
				slot.Player = nil
				slot.DownAt = now - B.BotRespawn
			end
			if not slot.Player and not (slot.Bot and slot.Bot.Alive) then
				slot.Bot = nil
				slot.DownAt = slot.DownAt or now
				if houndRespawn and now - slot.DownAt >= B.BotRespawn then
					spawnBot(slot, spawnPoint(slot))
				end
			end
		end
		reinforce(now)
		retire(now)
		workspace:SetAttribute("EnemyLeft", Battle.EnemyLeft())
		task.wait(0.5)
	end
end

-- API -------------------------------------------------------------------------------------------------

-- Surveys cover round each point (Vector3s) out to Survey studs. Yields; call it at server start.
function Battle.Survey(points)
	for _, p in points do
		CoverMap.Survey(p, B.Survey)
	end
	return CoverMap.Count()
end

-- The battle begins with HOUND at spawnCF: the players in the match hold the last slots, bots the
-- rest.
function Battle.Start(spawnCF)
	Battle.Stop()
	on = true
	gen += 1
	houndRespawn = true
	hound.Spawn, hound.Plan = spawnCF, nil
	local per = math.ceil(B.Size / B.Teams)
	for i = 1, B.Size do
		slots[i] = {
			Index = i,
			Callsign = B.Callsigns[i] or ("HOUND " .. i),
			Rig = B.Rigs[(i - 1) % #B.Rigs + 1],
			Gun = "AK",
			Team = math.floor((i - 1) / per) + 1,
		}
	end
	for n, p in inMatch() do
		local slot = slots[B.Size - n + 1]
		if slot then
			slot.Player = p
		end
	end
	for _, slot in slots do
		if not slot.Player then
			spawnBot(slot, spawnPoint(slot))
		end
	end
	task.spawn(loop, gen)
end

function Battle.Stop()
	on = false
	gen += 1
	Soldier.Clear()
	table.clear(slots)
	table.clear(retiring)
	table.clear(foe.Field)
	table.clear(foe.Queue)
	foe.Pool, foe.Due, foe.Filling, foe.From = 0, nil, false, nil
	foe.Posts, foe.Rear = {}, {}
	hound.Plan = nil
	workspace:SetAttribute("EnemyLeft", nil)
end

-- Fallen HOUND bots come back (true, the default) or stay down (the story's last mission).
function Battle.SetReinforce(yes)
	houndRespawn = yes
end

-- Every empty bot slot filled at once at the spawn (a retry after a wipe), whatever SetReinforce says.
function Battle.Refill()
	if not on then
		return
	end
	for _, slot in slots do
		if not slot.Player and not (slot.Bot and slot.Bot.Alive) then
			spawnBot(slot, spawnPoint(slot))
		end
	end
end

-- HOUND's bots still standing.
function Battle.HoundBots()
	local list = {}
	for _, slot in slots do
		if slot.Bot and slot.Bot.Alive then
			table.insert(list, slot.Bot)
		end
	end
	return list
end

-- One HOUND bot falls (a random one still standing). Returns its callsign, or nil if none are left.
function Battle.HoundLoss()
	local bots = Battle.HoundBots()
	if #bots == 0 then
		return nil
	end
	local s = bots[math.random(#bots)]
	s:Hurt(s.Humanoid.Health + 1)
	return s.Callsign
end

-- Where HOUND's bots come back (the current checkpoint).
function Battle.SetSpawn(cf)
	hound.Spawn = cf
end

-- A player arriving: the calmest bot's slot (the highest slot first) and the CFrame it stood at,
-- or nil when that slot's bot is down (they start at the checkpoint). Also the callsign whose
-- place they took. Nothing for a player who already holds a slot.
function Battle.Claim(player)
	if not on then
		return nil
	end
	for _, slot in slots do
		if slot.Player == player then
			return nil
		end
	end
	local best, bestScore = nil, -math.huge
	for _, slot in slots do
		if not slot.Player then
			local bot = slot.Bot
			local score = slot.Index
			if bot and bot.Alive then
				score += if bot:Calm() then 200 else 100
			end
			if score > bestScore then
				best, bestScore = slot, score
			end
		end
	end
	if not best then
		return nil
	end
	best.Player = player
	local bot = best.Bot
	best.Bot, best.DownAt = nil, nil
	if bot and bot.Alive then
		local root = bot.Root
		local cf = CFrame.new(root.Position + Vector3.new(0, 1.5, 0)) * root.CFrame.Rotation
		bot:Remove()
		return cf, best.Callsign
	end
	return nil, best.Callsign
end

-- A player leaving: their slot goes back to a bot, standing at cf (else at the spawn, now).
function Battle.Release(player, cf)
	for _, slot in slots do
		if slot.Player == player then
			slot.Player = nil
			if on then
				if cf then
					spawnBot(slot, cf)
				else
					slot.DownAt = os.clock() - B.BotRespawn
				end
			end
			return
		end
	end
end

-- Every bot back at cf with a clean slate (the step starting again).
function Battle.Regroup(cf)
	hound.Spawn = cf
	for _, slot in slots do
		local s = slot.Bot
		if s and s.Alive then
			s.Model:PivotTo(spawnPoint(slot))
			s:Reset()
			s:SetOrder(houndOrder(slot))
		end
	end
end

-- HOUND's bots take goal: three fireteams in lanes from where the bots are now, within radius of
-- it when there.
function Battle.HoundAttack(goal, radius)
	local from = hound.Spawn.Position
	local sum, n = Vector3.zero, 0
	for _, s in Soldier.All("Ally") do
		sum += s.Root.Position
		n += 1
	end
	if n > 0 then
		from = sum / n
	end
	local fwd = flat(goal - from)
	fwd = if fwd.Magnitude > 1 then fwd.Unit else Vector3.new(0, 0, -1)
	hound.Plan = { Mode = "Attack", Goal = goal, Radius = radius, From = from, Right = fwd:Cross(Vector3.yAxis), Facing = { goal + fwd * 30 } }
	orderBots()
end

-- HOUND's bots hold cover within radius of point, facing the points in facing.
function Battle.HoundHold(point, radius, facing)
	hound.Plan = { Mode = "Hold", Goal = point, Radius = radius, Facing = facing }
	orderBots()
end

-- The Lamplighters hold posts (parts): one on each, the field filled from rear (parts; the posts
-- when empty) and pool more to come as they fall. from: where HOUND comes from (else where its
-- attack started, else its spawn).
function Battle.EnemyDefend(posts, rear, pool, from)
	foe.Posts, foe.Rear = posts, rear
	foe.From = from or (hound.Plan and hound.Plan.From) or hound.Spawn.Position
	foe.Pool = if #posts + #rear > 0 then pool else 0
	table.clear(foe.Queue)
	local n = fieldCount()
	for _, spot in posts do
		if n >= B.Size then
			foe.Pool += 1
		else
			spawnEnemy(spot:GetAttribute("Kind") or "Lamplighter", spot.CFrame + Vector3.new(0, 3, 0), defendOrder(spot.Position))
			n += 1
		end
	end
	foe.Filling, foe.Due = true, nil
end

-- count soldiers of kind (Lamplighter if nil) from spots (parts) push at goal, as the field allows.
function Battle.EnemyAttack(spots, count, goal, kind)
	for _ = 1, count do
		table.insert(foe.Queue, { Kind = kind or "Lamplighter", Spots = spots, Goal = goal })
	end
end

-- The step is won: the survivors fall back toward their rear and vanish out of sight.
function Battle.RetireEnemies()
	local now = os.clock()
	local back = foe.Rear[1] or foe.Posts[1]
	for s in foe.Field do
		if s.Alive then
			local pos = s.Root.Position
			local away = if foe.From then flat(pos - foe.From) else Vector3.zero
			local goal = if back then back.Position elseif away.Magnitude > 1 then pos + away.Unit * 60 else pos
			s:SetOrder({ Mode = "Retire", Goal = goal })
			retiring[s] = now
		end
	end
	table.clear(foe.Field)
	table.clear(foe.Queue)
	foe.Pool, foe.Due, foe.Filling = 0, nil, false
end

function Battle.ClearEnemies()
	Soldier.Clear("Enemy")
	table.clear(foe.Field)
	table.clear(foe.Queue)
	table.clear(retiring)
	foe.Pool, foe.Due, foe.Filling = 0, nil, false
end

-- The defence breaks (5 Nov 2026: its tank is gone): at most `most` of the reserve come straight at goal now,
-- the rest never come, and the ones on the field leave their posts and push too. The fight then ends at the
-- squad instead of trickling in one at a time from the far rear, which read as the mission being stuck.
function Battle.EnemyRush(goal, most)
	local n = math.min(foe.Pool, most or 4)
	local spots = if #foe.Rear > 0 then foe.Rear else foe.Posts
	foe.Pool = 0
	for _ = 1, n do
		table.insert(foe.Queue, { Kind = "Lamplighter", Spots = spots, Goal = goal })
	end
	for s in foe.Field do
		if s.Alive and s.Root then
			s:SetOrder(attackOrder(s.Root.Position, goal))
		end
	end
end

function Battle.EnemyAlive()
	return fieldCount()
end

function Battle.EnemyReserve()
	return foe.Pool + #foe.Queue
end

function Battle.EnemyLeft()
	return fieldCount() + foe.Pool + #foe.Queue
end

return Battle
