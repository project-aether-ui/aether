--!strict
--[[
	Alignment moves a run that is longer than its panel, on either axis, with
	and without UIPadding and Padding.

	Three children of 100 in a 200 wide panel overflow by 100. Left starts the
	run at the left edge, Center centres it so that half the overflow lies past
	each edge, and Right ends it at the right edge. With UIPadding 8 on each
	side and a Padding of 6 the run is 312 in a content box of 184, and the
	same rule applies inside the padding. Three children of 30 in a 60 tall
	panel do the same vertically.

	Every row sits at x 0, so each x below is the child's offset from its
	row's left edge, as the engine printed it. The columns sit at y 200, so a
	vertical child's y is 200 plus the printed offset.
]]

local function kids(prefix: string, w: number, h: number)
	return {
		{ class = "Frame", name = prefix .. "1", props = { LayoutOrder = 1, Size = { "UDim2", 0, w, 0, h } } },
		{ class = "Frame", name = prefix .. "2", props = { LayoutOrder = 2, Size = { "UDim2", 0, w, 0, h } } },
		{ class = "Frame", name = prefix .. "3", props = { LayoutOrder = 3, Size = { "UDim2", 0, w, 0, h } } },
	}
end

local function row(name: string, y: number, align: string, padded: boolean)
	local children = kids(name, 100, 20)
	table.insert(children, {
		class = "UIListLayout",
		name = name .. "Layout",
		props = {
			FillDirection = { "Enum", "FillDirection", "Horizontal" },
			SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
			HorizontalAlignment = { "Enum", "HorizontalAlignment", align },
			Padding = { "UDim", 0, if padded then 6 else 0 },
		},
	})
	if padded then
		table.insert(children, {
			class = "UIPadding",
			name = name .. "Padding",
			props = {
				PaddingLeft = { "UDim", 0, 8 },
				PaddingRight = { "UDim", 0, 8 },
			},
		})
	end
	return {
		class = "Frame",
		name = name,
		props = {
			Position = { "UDim2", 0, 0, 0, y },
			Size = { "UDim2", 0, 200, 0, 20 },
		},
		children = children,
	}
end

local function column(name: string, x: number, align: string)
	local children = kids(name, 40, 30)
	table.insert(children, {
		class = "UIListLayout",
		name = name .. "Layout",
		props = {
			FillDirection = { "Enum", "FillDirection", "Vertical" },
			SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
			VerticalAlignment = { "Enum", "VerticalAlignment", align },
		},
	})
	return {
		class = "Frame",
		name = name,
		props = {
			Position = { "UDim2", 0, x, 0, 200 },
			Size = { "UDim2", 0, 40, 0, 60 },
		},
		children = children,
	}
end

--- One child's rectangle: horizontal children are 100 by 20 on their row,
--- vertical ones 40 by 30 in their column.
local function across(name: string, x: number, y: number)
	return { name = name, x = x, y = y, w = 100, h = 20 }
end

local function down(name: string, x: number, y: number)
	return { name = name, x = x, y = y, w = 40, h = 30 }
end

return {
	name = "UIListLayout alignment moves an overflowing run on both axes",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIListLayout.MainAxisAlignment" },
	note = "From a command-bar measurement on 2026-10-02: each child's offset from its panel's edge, "
		.. "read from AbsolutePosition, with every panel at the origin. Horizontal: Left 0 100 200, "
		.. "Center -50 50 150, Right -100 0 100; padded Left 8 114 220, Center -56 50 156, Right "
		.. "-120 -14 92. Vertical: Top 0 30 60, Center -15 15 45, Bottom -30 0 30.",
	surface = { width = 400, height = 300 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			row("OverflowLeft", 0, "Left", false),
			row("OverflowCenter", 30, "Center", false),
			row("OverflowRight", 60, "Right", false),
			row("PaddedLeft", 90, "Left", true),
			row("PaddedCenter", 120, "Center", true),
			row("PaddedRight", 150, "Right", true),
			column("VerticalTop", 250, "Top"),
			column("VerticalCenter", 300, "Center"),
			column("VerticalBottom", 350, "Bottom"),
		},
	},

	expect = {
		across("OverflowLeft1", 0, 0),
		across("OverflowLeft2", 100, 0),
		across("OverflowLeft3", 200, 0),
		across("OverflowCenter1", -50, 30),
		across("OverflowCenter2", 50, 30),
		across("OverflowCenter3", 150, 30),
		across("OverflowRight1", -100, 60),
		across("OverflowRight2", 0, 60),
		across("OverflowRight3", 100, 60),

		across("PaddedLeft1", 8, 90),
		across("PaddedLeft2", 114, 90),
		across("PaddedLeft3", 220, 90),
		across("PaddedCenter1", -56, 120),
		across("PaddedCenter2", 50, 120),
		across("PaddedCenter3", 156, 120),
		across("PaddedRight1", -120, 150),
		across("PaddedRight2", -14, 150),
		across("PaddedRight3", 92, 150),

		down("VerticalTop1", 250, 200),
		down("VerticalTop2", 250, 230),
		down("VerticalTop3", 250, 260),
		down("VerticalCenter1", 300, 185),
		down("VerticalCenter2", 300, 215),
		down("VerticalCenter3", 300, 245),
		down("VerticalBottom1", 350, 170),
		down("VerticalBottom2", 350, 200),
		down("VerticalBottom3", 350, 230),
	},
}
