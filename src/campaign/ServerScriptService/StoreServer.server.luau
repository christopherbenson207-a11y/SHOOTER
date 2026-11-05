-- The store (GameConfig.Store, GameConfig.Classes; the menu's SHOP and CLASSES pages in
-- MenuClient). It runs in both places, the lobby and the campaign, so a purchase is granted
-- wherever Roblox delivers it.
-- Robux: each developer product is granted once (Profile receipts) and saved before Roblox is told
-- it went through (ProcessReceipt). The VIP pass is checked on join and when it is bought.
-- Scrip: classes are bought and picked through Remotes.Store.
--   Remotes.Store:InvokeServer("Class", name): picks a class you own; one you don't own is bought
--     with Scrip first (GameConfig.Classes.Price). Returns "Picked", "Bought", "Short" or "No".
--   Remotes.Store:InvokeServer("Offer"): true once, the first time the starter pack is due (after
--     the first escape, or the OfferDeaths-th death), so the menu opens on the SHOP.
-- Player attributes: Vip (the pass), and Profile's Scrip, Class, Owned and Tokens.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Profile = require(ServerStorage.Modules.Profile)

local STORE = GameConfig.Store
local CLASSES = GameConfig.Classes

local remote = ReplicatedStorage.Remotes:FindFirstChild("Store")
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = "Store"
	remote.Parent = ReplicatedStorage.Remotes
end

-- What each developer product gives (an id left at 0 sells nothing).
local grants = {}
if STORE.StarterPack.Product ~= 0 then
	grants[STORE.StarterPack.Product] = function(player)
		Profile.AddScrip(player, STORE.StarterPack.Scrip)
		Profile.Grant(player, "StarterPack")
	end
end
if STORE.Revive.Product ~= 0 then
	grants[STORE.Revive.Product] = function(player)
		Profile.Count(player, "Tokens", 1)
	end
end
for name, id in STORE.Classes do
	if id ~= 0 then
		grants[id] = function(player)
			Profile.Grant(player, name)
			Profile.SetClass(player, name)
		end
	end
end

-- 4 Nov 2026: the campaign never grants. Nothing here prompts a purchase, and this place has no Shared.Catalogue, so
-- it can't give a product's full contents; the lobby and zombies places grant with the full Shared.Catalogue. (This
-- place's Profile now uses the same session lock as theirs, so it no longer overwrites their saves.) A receipt that reaches this server (a purchase made
-- in another place that had not finished) is left for those places: Roblox calls ProcessReceipt again the next time
-- the player is in a server, so it is granted once, with the right contents, by the locked handler.
-- The old legacy grant table above is kept for reference only.
MarketplaceService.ProcessReceipt = function(_receipt)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- VIP ----------------------------------------------------------------------------------------------

-- Retries 1, 2, 4 s; an error never counts as "not owned".
local VIP_RETRY = { 1, 2, 4 }
local function checkVip(player)
	if STORE.Vip.Pass == 0 then
		return
	end
	for try = 1, #VIP_RETRY + 1 do
		if not player.Parent then
			return
		end
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, STORE.Vip.Pass)
		if ok then
			if owns and player.Parent then
				player:SetAttribute("Vip", true)
			end
			return
		end
		if try <= #VIP_RETRY then
			task.wait(VIP_RETRY[try])
		else
			warn("StoreServer: VIP pass check failed", player.Name, owns)
		end
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
	if bought and passId == STORE.Vip.Pass then
		player:SetAttribute("Vip", true)
	end
end)

-- Deaths in a match count toward the starter pack offer.
local function onPlayer(player)
	task.spawn(checkVip, player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Once(function()
				if player.Parent and player:GetAttribute("InMatch") then
					Profile.Count(player, "Deaths")
				end
			end)
		end
	end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end

-- Classes and the offer -----------------------------------------------------------------------------

remote.OnServerInvoke = function(player, action, name)
	if action == "Class" then
		if typeof(name) ~= "string" or not CLASSES.List[name] or player:GetAttribute("InMatch") then
			return "No"
		end
		if name ~= CLASSES.Default and not Profile.Owns(player, name) then
			if not Profile.SpendScrip(player, CLASSES.Price) then
				return "Short"
			end
			Profile.Grant(player, name)
			Profile.SetClass(player, name)
			return "Bought"
		end
		Profile.SetClass(player, name)
		return "Picked"
	elseif action == "Offer" then
		local pack = STORE.StarterPack
		if pack.Product == 0 or Profile.Owns(player, "StarterPack") or Profile.Flag(player, "StarterOffered") then
			return false
		end
		local data = Profile.Get(player)
		if not data.Escaped and (data.Deaths or 0) < pack.OfferDeaths then
			return false
		end
		return Profile.SetFlag(player, "StarterOffered")
	end
	return nil
end
