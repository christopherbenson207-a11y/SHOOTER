-- Records each player's current input type (sent by the client's Platform module, which reads PreferredInput)
-- as the "InputMode" attribute, so server systems and analytics can split by platform.
-- Duel pass (5 Nov 2026): GunServer gives touch players a little extra hit tolerance (GameConfig.Validation.Pvp.Touch)
-- from this attribute, so a switch is only taken at most once every SWITCH_GAP seconds (a held-back switch still
-- lands when the gap is up) and InputModeSince keeps the server time it last changed. GunServer only trusts a mode
-- that has held for a few seconds, so flipping to Touch right before a shot buys nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VALID = { KeyboardAndMouse = true, Touch = true, Gamepad = true }
local SWITCH_GAP = 2

local lastSwitch = {} -- [player] = os.clock() of the last change
local pending = {} -- [player] = the mode waiting for the gap to pass

local function apply(player, mode)
	pending[player] = nil
	if player.Parent ~= Players or player:GetAttribute("InputMode") == mode then
		return
	end
	lastSwitch[player] = os.clock()
	player:SetAttribute("InputMode", mode)
	player:SetAttribute("InputModeSince", workspace:GetServerTimeNow())
end

ReplicatedStorage.Remotes.SetInputMode.OnServerEvent:Connect(function(player, mode)
	if typeof(mode) ~= "string" or not VALID[mode] then
		return
	end
	local wait = SWITCH_GAP - (os.clock() - (lastSwitch[player] or -math.huge))
	if wait <= 0 then
		apply(player, mode)
		return
	end
	local queued = pending[player] ~= nil
	pending[player] = mode
	if not queued then
		task.delay(wait, function()
			local m = pending[player]
			if m then
				apply(player, m)
			end
		end)
	end
end)

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("InputMode", "KeyboardAndMouse")
	player:SetAttribute("InputModeSince", workspace:GetServerTimeNow())
end)

Players.PlayerRemoving:Connect(function(player)
	lastSwitch[player] = nil
	pending[player] = nil
end)
