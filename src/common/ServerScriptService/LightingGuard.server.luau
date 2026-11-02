-- If the place was saved with the Studio editing light on (ServerStorage._DevTools.EditLight),
-- put the night back before anyone sees it.
require(game:GetService("ServerStorage")._DevTools.EditLight).Restore()
