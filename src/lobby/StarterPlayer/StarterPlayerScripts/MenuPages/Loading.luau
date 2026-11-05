-- Loading page (FRONT-A, 4 Nov 2026): the mode art, name and line, the squad's names and a progress bar. Shown by
-- MenuClient for the last second of the countdown and in Studio's local deploy; the same fill runs on the teleport
-- screen (ReplicatedStorage.Assets.LoadingGui, cloned and filled by MenuClient before TeleportService:SetTeleportGui).
--   Page.Fill(frame, info, ui) info = {Mode, Chapter, Members = {{Name, Class}}}; works on any copy of the page frame
--   whose ScreenGui carries the Templates tree.
--   Page.Run(frame, ui, seconds) creeps the bar toward 90 % over the given time.
-- Elements: notes/SCREENS-A.md (Loading).

local Common = require(script.Parent:WaitForChild("TopBar"):WaitForChild("Common"))

local Page = { Name = "Loading", Camera = "Home" }

function Page.Fill(frame, info, ui)
	if not frame then
		return
	end
	info = info or {}
	local mode = info.Mode or "Outbreak"
	local m = Common.Info(mode)
	local art = frame:FindFirstChild("Art")
	if art and ui.Art(m.Wide) then
		ui.SetArt(art, m.Wide)
	end
	local line = m.Line
	if mode == "Campaign" then
		-- CHAPTER 1  ·  OPERATION LAST LIGHT (a run always starts at the chapter's first mission)
		local ch = tonumber(info.Chapter) or 1
		local chapter = Common.Chapters[ch]
		if chapter and chapter.Name then
			line = "CHAPTER " .. ch .. "  ·  " .. chapter.Name
		end
	end
	ui.Text(frame:FindFirstChild("ModeName"), m.Name)
	ui.Text(frame:FindFirstChild("Line"), line)
	local members = {}
	for _, mem in info.Members or {} do
		if type(mem) == "table" then
			table.insert(members, mem)
		end
	end
	local squad = frame:FindFirstChild("Squad")
	local header = frame:FindFirstChild("SquadHeader")
	if header then
		header.Visible = #members > 0
	end
	ui.Fill(squad, members, function(row, mem)
		local emblem = row:FindFirstChild("Emblem")
		local key = "Emblem/" .. tostring(mem.Class or "Rifleman")
		if emblem and ui.Art(key) then
			ui.SetArt(emblem, key)
		end
		ui.Text(row:FindFirstChild("Name"), string.upper(tostring(mem.Name or "")))
	end)
	ui.Bar(frame:FindFirstChild("Progress"), 0)
end

function Page.Run(frame, ui, seconds)
	local bar = frame and frame:FindFirstChild("Progress")
	if not bar then
		return
	end
	ui.Bar(bar, 0)
	ui.Bar(bar, 0.9, math.max(0.5, seconds or 6))
end

-- The squad as Loading wants it, from the Party state (or the local player alone).
function Page.Info(ctx, payload)
	local squad = Common.Squad(ctx)
	local members = {}
	for _, m in squad.Members do
		table.insert(members, { Name = m.Name, Class = m.Class })
	end
	payload = type(payload) == "table" and payload or {}
	return {
		Mode = payload.Mode or squad.Mode or Common.Recommended(ctx.player),
		Chapter = payload.Chapter or squad.Chapter,
		Members = members,
	}
end

function Page.Show(ctx, args)
	ctx.showChrome(false)
	local frame = ctx.frame("Loading")
	local info = Page.Info(ctx, args)
	Page.Fill(frame, info, ctx.ui)
	Page.Run(frame, ctx.ui, type(args) == "table" and args.Hold or 8)
end

return Page
