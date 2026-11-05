--!strict
-- ServerStorage.Modules.CrashIntro  (INTRO stream, war/intro/CrashIntro.lua)
-- CrashIntro.Play(players, start?) plays the plane-crash cutscene on each listed client and
-- yields until every one of them fires Remotes.CrashIntro:FireServer("Done"), leaves, or 30 s pass.
-- Sets player attributes: InCutscene (true while it runs) and SeenIntro (true once done).
-- The character is NOT frozen here; the caller does that.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CrashIntro = {}

local TIMEOUT = 30
local COMMANDER = "HALE"

local function getRemote(): RemoteEvent
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end
	local r = remotes:FindFirstChild("CrashIntro")
	if r and r:IsA("RemoteEvent") then
		return r
	end
	local ev = Instance.new("RemoteEvent")
	ev.Name = "CrashIntro"
	ev.Parent = remotes
	return ev
end

local function startCFrame(): CFrame
	local map = workspace:FindFirstChild("Map")
	local war = map and map:FindFirstChild("War")
	local start = war and war:FindFirstChild("Start")
	if start and start:IsA("BasePart") then
		return start.CFrame
	end
	return CFrame.new(-4, 102.5, 292)
end

function CrashIntro.Play(players: { Player }, start: CFrame?)
	local remote = getRemote()
	local startCF = start or startCFrame()

	local pending: { [Player]: boolean } = {}
	local count = 0
	-- Squad: the user id in each seat, so every client seats the real squad in the cabin (4 Nov 2026).
	local squad: { number } = {}
	for i, p in players do
		squad[i] = if typeof(p) == "Instance" and p:IsA("Player") then p.UserId else 0
	end
	for i, p in players do
		if typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players and not pending[p] then
			pending[p] = true
			count += 1
			p:SetAttribute("InCutscene", true)
			remote:FireClient(p, { Start = startCF, Seat = i, Commander = COMMANDER, Squad = squad })
		end
	end
	if count == 0 then
		return
	end

	local thread = coroutine.running()
	local finished = false
	local conns: { RBXScriptConnection } = {}

	local function finish()
		if finished then
			return
		end
		finished = true
		for _, c in conns do
			c:Disconnect()
		end
		for p in pending do
			if p.Parent == Players then
				p:SetAttribute("InCutscene", false)
			end
		end
		table.clear(pending)
		task.spawn(thread)
	end

	local function release(p: Player, done: boolean)
		if not pending[p] then
			return
		end
		pending[p] = nil
		count -= 1
		if p.Parent == Players then
			p:SetAttribute("InCutscene", false)
			if done then
				p:SetAttribute("SeenIntro", true)
			end
		end
		if count <= 0 then
			finish()
		end
	end

	table.insert(conns, remote.OnServerEvent:Connect(function(p: Player, msg: any)
		if msg == "Done" then
			release(p, true)
		end
	end))
	table.insert(conns, Players.PlayerRemoving:Connect(function(p: Player)
		release(p, false)
	end))
	task.delay(TIMEOUT, finish)

	coroutine.yield()
end

return CrashIntro
