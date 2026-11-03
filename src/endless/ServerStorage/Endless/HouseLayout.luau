-- The huge house the Endless reference is played in: Blackwood Manor, four levels (cellar, ground,
-- upper, attic), nineteen rooms in fifteen zones. HouseBuilder turns this table into parts at the start of every
-- run. Check a change with `python tools/endless_house.py` (it validates the layout and draws each
-- level to docs/endless/house-*.png) before you sync.
--
-- Plans: one string per row, north (z = 0) at the top, west (x = 0) on the left. Each character is a
-- cell House.Cell studs square (Config.House). A letter or digit is the room on that cell; "." is no
-- room. Every level uses the same grid, so a cell is the same spot of ground on every level.
-- Walls come by themselves: wherever two neighbouring cells are different rooms (or a room and
-- nothing), there is a wall. Openings are cut into those walls:
--   Doors   {Level, At = {x, z}, Side, Cost}: bought with points; opening one joins its two zones.
--   Arches  {Level, At, Side}: always open; rooms joined by arches are one zone.
--   Windows {Level, At, Side}: boarded windows on outside walls, where zombies come in. Windows on
--           an upper level need open ground under them on every level below (zombies climb the
--           wall).
--   Hatches {Level, At}: a broken hole in the floor of that cell; zombies claw up through it.
-- Side is the side of cell At the opening is on: "N" (toward z - 1), "S", "W" (toward x - 1) or "E".
-- Stairs {Level, At, Rise, Length, Gate, Cost}: a ramp on Level from cell At (its low end) running
--   Length cells toward Rise and climbing one level. The cells above it on Level + 1 have no floor
--   (railings round the hole) and the next cell past the top is where you step off. Gate = "Bottom"
--   or "Top" puts a door you buy across that end; no Gate means the stair is always open.
-- Spots {Kind, Level, At, Side}: places for the run's furniture, standing in cell At against the wall
--   on Side. Every run draws where things go from these, so the house plays different each time:
--   Box (the weapon randomizer: one spot is used, it moves between them), Perk (one per perk),
--   Wall (a gun drawn on the wall; Weapon = fixed gun, else drawn from Config.WallBuys.Pool),
--   Altar (gun ascension; one is used), Power (the power switch; one is used).
-- Rooms {Name, Style, Start}: Style picks colours and furniture (Config.House.Styles). Players
-- spawn in the Start room, whose zone is open from the start.

return {
	Name = "Blackwood Manor",
	Width = 16,
	Depth = 14,
	Levels = {
		[-1] = {
			"................",
			"................",
			"...........XXXXX",
			"...........XXXXX",
			"...........XXXXX",
			"...........WWWWW",
			"...........WWWWW",
			"...........WWWWW",
			"...........WWWWW",
			"...........WWWWW",
			"................",
			"................",
			"................",
			"................",
		},
		[0] = {
			"..CCCCCCCCCCCC..",
			"..CCCCCCCCCCCC..",
			"BBBBBGGGGGGKKKKK",
			"BBBBBGGGGGGKKKKK",
			"BBBBBGGGGGGKKKKK",
			"BBBBBGGGGGGKKKKK",
			"BBBBBGGGGGGPPPPP",
			"LLLLLhhhhhhPPPPP",
			"LLLLLFFFFFFDDDDD",
			"LLLLLFFFFFFDDDDD",
			"LLLLLFFFFFFDDDDD",
			"LLLLLFFFFFFDDDDD",
			".....FFFFFF.....",
			"................",
		},
		[1] = {
			"................",
			"................",
			"MMMMMSSSSSSNNNNN",
			"MMMMMSSSSSSNNNNN",
			"MMMMMSSSSSSNNNNN",
			"MMMMMSSSSSSNNNNN",
			"MMMMMuuuuuuNNNNN",
			"RRRRRuuuuuuTTTTT",
			"RRRRRUUUUUUTTTTT",
			"RRRRRUUUUUUTTTTT",
			"RRRRRUUUUUUTTTTT",
			"RRRRRUUUUUUTTTTT",
			"................",
			"................",
		},
		[2] = {
			"................",
			"................",
			".....AAAAAA.....",
			".....AAAAAA.....",
			".....AAAAAA.....",
			".....AAAAAA.....",
			".....AAAAAA.....",
			"................",
			"................",
			"................",
			"................",
			"................",
			"................",
			"................",
		},
	},

	Rooms = {
		F = { Name = "Foyer", Style = "Foyer", Start = true },
		h = { Name = "Back Hall", Style = "Hall" },
		L = { Name = "Living Room", Style = "Living" },
		D = { Name = "Dining Room", Style = "Dining" },
		B = { Name = "Library", Style = "Library" },
		G = { Name = "Great Hall", Style = "GreatHall" },
		K = { Name = "Kitchen", Style = "Kitchen" },
		P = { Name = "Pantry", Style = "Pantry" },
		C = { Name = "Conservatory", Style = "Conservatory" },
		W = { Name = "Wine Cellar", Style = "Cellar" },
		X = { Name = "Boiler Room", Style = "Boiler" },
		U = { Name = "Gallery", Style = "Foyer" },
		u = { Name = "Upper Hall", Style = "Hall" },
		R = { Name = "Guest Room", Style = "Bedroom" },
		T = { Name = "Trophy Room", Style = "Trophy" },
		M = { Name = "Master Bedroom", Style = "Bedroom" },
		N = { Name = "Nursery", Style = "Nursery" },
		S = { Name = "Study", Style = "Study" },
		A = { Name = "Attic", Style = "Attic" },
	},

	Stairs = {
		-- The grand stair, up the east side of the foyer to the gallery.
		{ Level = 0, At = { 10, 11 }, Rise = "N", Length = 3, Gate = "Bottom", Cost = 1000 },
		-- Down from the pantry into the wine cellar; the gate is at the top, in the pantry.
		{ Level = -1, At = { 12, 6 }, Rise = "E", Length = 3, Gate = "Top", Cost = 1250 },
		-- Up from the upper hall into the attic.
		{ Level = 1, At = { 6, 6 }, Rise = "E", Length = 3, Gate = "Bottom", Cost = 1500 },
	},

	Doors = {
		{ Level = 0, At = { 5, 9 }, Side = "W", Cost = 750 }, -- foyer -> living room
		{ Level = 0, At = { 10, 8 }, Side = "E", Cost = 750 }, -- foyer -> dining room
		{ Level = 0, At = { 7, 7 }, Side = "N", Cost = 1250 }, -- back hall -> great hall
		{ Level = 0, At = { 2, 7 }, Side = "N", Cost = 1000 }, -- living room -> library
		{ Level = 0, At = { 13, 8 }, Side = "N", Cost = 1000 }, -- dining room -> pantry
		{ Level = 0, At = { 4, 4 }, Side = "E", Cost = 1250 }, -- library -> great hall
		{ Level = 0, At = { 11, 4 }, Side = "W", Cost = 1250 }, -- kitchen -> great hall
		{ Level = 0, At = { 7, 2 }, Side = "N", Cost = 1500 }, -- great hall -> conservatory
		{ Level = 0, At = { 3, 2 }, Side = "N", Cost = 1250 }, -- library -> conservatory
		{ Level = 0, At = { 12, 2 }, Side = "N", Cost = 1250 }, -- kitchen -> conservatory
		{ Level = 1, At = { 5, 10 }, Side = "W", Cost = 1000 }, -- gallery -> guest room
		{ Level = 1, At = { 10, 8 }, Side = "E", Cost = 1000 }, -- gallery -> trophy room
		{ Level = 1, At = { 5, 6 }, Side = "W", Cost = 1250 }, -- upper hall -> master bedroom
		{ Level = 1, At = { 10, 6 }, Side = "E", Cost = 1250 }, -- upper hall -> nursery
		{ Level = 1, At = { 9, 6 }, Side = "N", Cost = 1000 }, -- upper hall -> study
		{ Level = 1, At = { 2, 7 }, Side = "N", Cost = 750 }, -- guest room -> master bedroom
		{ Level = 1, At = { 13, 7 }, Side = "N", Cost = 750 }, -- trophy room -> nursery
	},

	Arches = {
		{ Level = 0, At = { 6, 8 }, Side = "N" }, -- foyer <-> back hall
		{ Level = 0, At = { 9, 8 }, Side = "N" }, -- foyer <-> back hall
		{ Level = 0, At = { 11, 6 }, Side = "N" }, -- pantry <-> kitchen
		{ Level = -1, At = { 13, 5 }, Side = "N" }, -- wine cellar <-> boiler room
		{ Level = 1, At = { 6, 8 }, Side = "N" }, -- gallery <-> upper hall
		{ Level = 1, At = { 8, 8 }, Side = "N" }, -- gallery <-> upper hall
	},

	Windows = {
		{ Level = 0, At = { 6, 12 }, Side = "S" }, -- foyer
		{ Level = 0, At = { 9, 12 }, Side = "S" }, -- foyer
		{ Level = 0, At = { 5, 12 }, Side = "W" }, -- foyer
		{ Level = 0, At = { 0, 8 }, Side = "W" }, -- living room
		{ Level = 0, At = { 0, 10 }, Side = "W" }, -- living room
		{ Level = 0, At = { 2, 11 }, Side = "S" }, -- living room
		{ Level = 0, At = { 15, 9 }, Side = "E" }, -- dining room
		{ Level = 0, At = { 15, 11 }, Side = "E" }, -- dining room
		{ Level = 0, At = { 13, 11 }, Side = "S" }, -- dining room
		{ Level = 0, At = { 0, 3 }, Side = "W" }, -- library
		{ Level = 0, At = { 0, 5 }, Side = "W" }, -- library
		{ Level = 0, At = { 15, 3 }, Side = "E" }, -- kitchen
		{ Level = 0, At = { 15, 5 }, Side = "E" }, -- kitchen
		{ Level = 0, At = { 15, 7 }, Side = "E" }, -- pantry
		{ Level = 0, At = { 4, 0 }, Side = "N" }, -- conservatory
		{ Level = 0, At = { 7, 0 }, Side = "N" }, -- conservatory
		{ Level = 0, At = { 10, 0 }, Side = "N" }, -- conservatory
		{ Level = 0, At = { 2, 1 }, Side = "W" }, -- conservatory
		{ Level = 0, At = { 13, 1 }, Side = "E" }, -- conservatory
		{ Level = 1, At = { 0, 4 }, Side = "W" }, -- master bedroom
		{ Level = 1, At = { 0, 9 }, Side = "W" }, -- guest room
		{ Level = 1, At = { 3, 11 }, Side = "S" }, -- guest room
		{ Level = 1, At = { 15, 8 }, Side = "E" }, -- trophy room
		{ Level = 1, At = { 12, 11 }, Side = "S" }, -- trophy room
		{ Level = 1, At = { 15, 4 }, Side = "E" }, -- nursery
	},

	Hatches = {
		{ Level = 0, At = { 7, 4 } }, -- great hall
		{ Level = 0, At = { 9, 3 } }, -- great hall
		{ Level = -1, At = { 14, 8 } }, -- wine cellar
		{ Level = -1, At = { 12, 3 } }, -- boiler room
		{ Level = 1, At = { 7, 3 } }, -- study
		{ Level = 1, At = { 7, 10 } }, -- gallery
		{ Level = 2, At = { 7, 3 } }, -- attic
	},

	Spots = {
		{ Kind = "Box", Level = 0, At = { 1, 7 }, Side = "N" }, -- living room
		{ Kind = "Box", Level = 0, At = { 8, 2 }, Side = "N" }, -- great hall
		{ Kind = "Box", Level = 0, At = { 9, 1 }, Side = "S" }, -- conservatory
		{ Kind = "Box", Level = 1, At = { 1, 2 }, Side = "N" }, -- master bedroom
		{ Kind = "Box", Level = -1, At = { 11, 9 }, Side = "W" }, -- wine cellar
		{ Kind = "Box", Level = 1, At = { 15, 10 }, Side = "E" }, -- trophy room

		{ Kind = "Perk", Level = 0, At = { 0, 2 }, Side = "W" }, -- library
		{ Kind = "Perk", Level = 0, At = { 15, 2 }, Side = "E" }, -- kitchen
		{ Kind = "Perk", Level = 0, At = { 11, 11 }, Side = "W" }, -- dining room
		{ Kind = "Perk", Level = 0, At = { 10, 6 }, Side = "E" }, -- great hall
		{ Kind = "Perk", Level = 1, At = { 5, 11 }, Side = "W" }, -- gallery
		{ Kind = "Perk", Level = 1, At = { 15, 6 }, Side = "E" }, -- nursery
		{ Kind = "Perk", Level = 1, At = { 0, 11 }, Side = "W" }, -- guest room
		{ Kind = "Perk", Level = -1, At = { 15, 2 }, Side = "E" }, -- boiler room

		{ Kind = "Wall", Level = 0, At = { 5, 10 }, Side = "W", Weapon = "Carbine" }, -- foyer
		{ Kind = "Wall", Level = 0, At = { 7, 12 }, Side = "S", Weapon = "BoltRifle" }, -- foyer
		{ Kind = "Wall", Level = 0, At = { 0, 9 }, Side = "W" }, -- living room
		{ Kind = "Wall", Level = 0, At = { 15, 10 }, Side = "E" }, -- dining room
		{ Kind = "Wall", Level = 0, At = { 4, 6 }, Side = "E" }, -- library
		{ Kind = "Wall", Level = 0, At = { 11, 3 }, Side = "W" }, -- kitchen
		{ Kind = "Wall", Level = 0, At = { 5, 3 }, Side = "W" }, -- great hall
		{ Kind = "Wall", Level = 0, At = { 13, 0 }, Side = "N" }, -- conservatory
		{ Kind = "Wall", Level = 1, At = { 8, 11 }, Side = "S" }, -- gallery
		{ Kind = "Wall", Level = 1, At = { 4, 3 }, Side = "E" }, -- master bedroom
		{ Kind = "Wall", Level = 1, At = { 10, 3 }, Side = "E" }, -- study
		{ Kind = "Wall", Level = -1, At = { 15, 8 }, Side = "E" }, -- wine cellar

		{ Kind = "Altar", Level = 2, At = { 10, 4 }, Side = "E" }, -- attic
		{ Kind = "Altar", Level = 0, At = { 2, 0 }, Side = "N" }, -- conservatory
		{ Kind = "Altar", Level = -1, At = { 11, 2 }, Side = "W" }, -- boiler room

		{ Kind = "Power", Level = -1, At = { 13, 2 }, Side = "N" }, -- boiler room
		{ Kind = "Power", Level = -1, At = { 15, 5 }, Side = "E" }, -- wine cellar
	},
}
