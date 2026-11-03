-- Small helpers the Endless server modules share.
--   Util.Signal(): Connect(fn) -> {Disconnect}, Fire(...), Clear()
--   Util.Maid(): Add(thing) (connection, thread, instance, function, or anything with Destroy/Disconnect),
--     Clean() (undoes everything added, newest first)
--   Util.Prompt(parent, action, object, hold, range): a ProximityPrompt set up the house way
--   Util.Shuffle(list), Util.Weighted(weights, skip), Util.Flat(v), Util.Now()

local Util = {}

function Util.Signal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		local h = { Fn = fn }
		table.insert(handlers, h)
		return {
			Disconnect = function()
				local i = table.find(handlers, h)
				if i then
					table.remove(handlers, i)
				end
			end,
		}
	end
	function signal:Fire(...)
		for _, h in table.clone(handlers) do
			task.spawn(h.Fn, ...)
		end
	end
	function signal:Clear()
		table.clear(handlers)
	end
	return signal
end

function Util.Maid()
	local items = {}
	local maid = {}
	function maid:Add(thing)
		table.insert(items, thing)
		return thing
	end
	function maid:Clean()
		for i = #items, 1, -1 do
			local thing = items[i]
			items[i] = nil
			local kind = typeof(thing)
			if kind == "RBXScriptConnection" then
				thing:Disconnect()
			elseif kind == "thread" then
				pcall(task.cancel, thing)
			elseif kind == "Instance" then
				thing:Destroy()
			elseif kind == "function" then
				local ok, err = pcall(thing)
				if not ok then
					warn("Endless cleanup:", err)
				end
			elseif kind == "table" then
				if thing.Destroy then
					thing:Destroy()
				elseif thing.Disconnect then
					thing:Disconnect()
				end
			end
		end
	end
	return maid
end

function Util.Prompt(parent: Instance, action: string, object: string, hold: number, range: number?)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = range or 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = parent
	return prompt
end

function Util.Shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- A key from {key = weight}, leaving out keys for which skip(key) is true. Nil if none is left.
function Util.Weighted(weights, skip)
	local total = 0
	for k, wgt in weights do
		if wgt > 0 and not (skip and skip(k)) then
			total += wgt
		end
	end
	if total <= 0 then
		return nil
	end
	local r = math.random() * total
	local last
	for k, wgt in weights do
		if wgt > 0 and not (skip and skip(k)) then
			r -= wgt
			last = k
			if r <= 0 then
				return k
			end
		end
	end
	return last
end

function Util.Flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Util.Now(): number
	return workspace:GetServerTimeNow()
end

return Util
