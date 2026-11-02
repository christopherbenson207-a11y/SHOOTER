-- VIP (the game pass; StoreServer sets the player attribute Vip): a gold [VIP] before the name in
-- chat.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

TextChatService.OnIncomingMessage = function(message)
	local properties = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	local sender = source and Players:GetPlayerByUserId(source.UserId)
	if sender and sender:GetAttribute("Vip") then
		properties.PrefixText = "<font color=\"#FFB03C\">[VIP]</font> " .. message.PrefixText
	end
	return properties
end
