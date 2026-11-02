-- STUB by CORE (2 Nov 2026). DATA replaces this module. Signatures are frozen in
-- horror-shooter/menu/CONTRACTS.md section 3; callers may rely on them before DATA lands.
local Progression = {}

function Progression.OpenLedger(_player, _mode, _variant) end

function Progression.Add(_player, _reason, _amount) end

function Progression.Event(_player, _event, _n) end

function Progression.EndMatch(_player, _result, _info)
	return nil
end

return Progression
