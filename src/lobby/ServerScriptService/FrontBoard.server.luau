-- The lobby's view of "the Front" (FRONTLINE pass 5): this week's universe-wide count of sectors taken, read every
-- minute from the store the campaign place's Modules.FrontWeek writes, into workspace FrontWeek / FrontWeekGoal. The
-- FRONTLINE card's line (MenuPages/TopBar/Common) shows it. These names must match Shared.Front.Week in the campaign
-- place. Studio reads its own store, so tests never touch the live count.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local WEEK = { Goal = 2500, Store = "FrontWeek_v1", StudioStore = "FrontWeek_Studio_v1", Refresh = 60 }

local function weekOf(t)
	return math.floor((t - 345600) / 604800) -- Monday 00:00 UTC weeks, as Shared.Front.WeekOf
end

workspace:SetAttribute("FrontWeekGoal", WEEK.Goal)

local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, if RunService:IsStudio() then WEEK.StudioStore else WEEK.Store)
if not ok then
	return
end

while true do
	local got, value = pcall(store.GetAsync, store, "Week" .. weekOf(os.time()))
	if got then
		workspace:SetAttribute("FrontWeek", tonumber(value) or 0)
	end
	task.wait(WEEK.Refresh)
end
