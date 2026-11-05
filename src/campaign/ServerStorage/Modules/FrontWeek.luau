-- "The Front" (FRONTLINE pass 5, Shared.Front.Week): a universe-wide count of sectors taken this week. Every server adds
-- its match's sectors once the match ends (UpdateAsync on key "Week<n>", Front.WeekOf), and reads the count back every
-- Refresh seconds into workspace FrontWeek / FrontWeekGoal (the lobby's FrontBoard does the same for its menu card).
-- When the count reaches Goal, every player in a FRONTLINE match that week is granted Week.Reward (Profile.Grant).
-- Studio uses Week.StudioStore, so tests never touch the live count; with Studio API access off it does nothing.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Front = require(ReplicatedStorage.Shared.Front)
local Profile = require(script.Parent.Profile)

local W = Front.Week

local FrontWeek = {}

local store = nil
local function getStore()
	if store == nil then
		local ok, s = pcall(DataStoreService.GetDataStore, DataStoreService, if RunService:IsStudio() then W.StudioStore else W.Store)
		store = if ok then s else false
	end
	return store or nil
end

local function key()
	return "Week" .. Front.WeekOf(os.time())
end

-- Adds n sectors to this week's count (yields; call it in its own thread).
function FrontWeek.Add(n)
	local s = getStore()
	if not s or n <= 0 then
		return
	end
	for attempt = 1, 3 do
		local ok, result = pcall(s.UpdateAsync, s, key(), function(old)
			return (tonumber(old) or 0) + n
		end)
		if ok then
			workspace:SetAttribute("FrontWeek", result)
			return
		end
		warn("FrontWeek: add failed (" .. tostring(result) .. ")")
		task.wait(2 ^ attempt)
	end
end

local function grant()
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("InMatch") and Profile.Holds and Profile.Holds(p) ~= false and not Profile.Owns(p, W.Reward) then
			Profile.Grant(p, W.Reward)
			ReplicatedStorage.Remotes.Match:FireClient(p, "Notice", "THE FRONT HELD: " .. W.RewardName .. " UNLOCKED")
		end
	end
end

function FrontWeek.Start()
	workspace:SetAttribute("FrontWeekGoal", W.Goal)
	task.spawn(function()
		while true do
			local s = getStore()
			if not s then
				return
			end
			local ok, value = pcall(s.GetAsync, s, key())
			if ok then
				workspace:SetAttribute("FrontWeek", tonumber(value) or 0)
			end
			if (workspace:GetAttribute("FrontWeek") or 0) >= W.Goal then
				grant()
			end
			task.wait(W.Refresh)
		end
	end)
end

return FrontWeek
