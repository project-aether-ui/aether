--!strict
--[[
	One checkbox, one radio group, one tab bar -- built end to end with
	Aether's own Primitives, no fake Router/Selection double anywhere in
	this file. Milestone 54 sprint 6.

	`Aether.Checkbox`, `Aether.RadioGroup` and `Aether.Tabs` all default
	their own Router/Selection to the real singletons (milestone 54 sprint
	2's own ambient `RouterContext`), so nothing here ever names
	`PointerRouter` or `SelectionRouter` -- the exact gap this milestone's
	own vision doc opened with: every real interaction call site in this
	repository, before this file, was either prose in a doc comment or
	wired to a fake double for a test.

	THE FRAMEWORK COMES FROM THIS REPOSITORY'S OWN `src/` AND `roblox_packages/`,
	by relative require, the same way `examples/counter`'s own desktop entry
	reaches `roblox_packages/vide` -- this example lives inside the framework
	it demonstrates rather than installing it as a dependency.
]]

local Aether = require("../../src/api")
local vide = require("../../roblox_packages/vide")
local create = vide.create
local source = vide.source

local WIDTH, HEIGHT = 300, 400

local root = desktop.Widget({ width = WIDTH, height = HEIGHT, anchor = "center" })

local INK = Color3.fromRGB(233, 239, 249)
local MUTED_TEXT = Color3.fromRGB(146, 162, 188)
local PANEL = Color3.fromRGB(18, 20, 26)
local ACCENT = Color3.fromRGB(96, 170, 255)
local UNCHECKED = Color3.fromRGB(46, 51, 64)
local INACTIVE = Color3.fromRGB(26, 29, 38)

--- EVERYTHING BELOW BUILDS INSIDE ONE `vide.root`, the same reason
--- `examples/counter`'s own desktop entry opens one: a reactive property
--- function (`BackgroundColor3 = function() ... end`, below) needs a stable
--- scope to register into the moment `create` applies it, and nothing here
--- is called from inside one otherwise.
vide.root(function()
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 1, 0)
	body.BackgroundColor3 = PANEL
	body.BorderSizePixel = 0
	body.Parent = root

	local function sectionLabel(text: string, y: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = "SectionLabel"
		label.Position = UDim2.new(0, 16, 0, y)
		label.Size = UDim2.new(1, -32, 0, 18)
		label.BackgroundTransparency = 1
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = MUTED_TEXT
		label.TextSize = 12
		label.Text = text
		label.Parent = body
		return label
	end

	----------------------------------------------------------------------
	-- CHECKBOX -- self-rendering, so `Aether.Checkbox` builds its own
	-- Frame. `OnCheckedChanged` is the only seam this file needs to draw
	-- a checkmark: the machine's own `Checked` state never leaves the
	-- Primitive, on purpose, the same way `Checkbox.luau`'s own header
	-- explains a Primitive supplies the tree and nothing else.
	----------------------------------------------------------------------

	sectionLabel("CHECKBOX", 12)

	local checked = source(false)

	local checkboxRow = Instance.new("Frame")
	checkboxRow.Name = "CheckboxRow"
	checkboxRow.Position = UDim2.new(0, 16, 0, 34)
	checkboxRow.Size = UDim2.new(1, -32, 0, 24)
	checkboxRow.BackgroundTransparency = 1
	checkboxRow.Parent = body

	Aether.Checkbox({
		Parent = checkboxRow,
		Name = "Checkbox",
		Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 0,
		BackgroundColor3 = function()
			return if checked() then ACCENT else UNCHECKED
		end,
		OnCheckedChanged = function(value: boolean)
			checked(value)
		end,

		create("TextLabel")({
			Name = "Mark",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = function()
				return if checked() then "x" else ""
			end,
			TextColor3 = Color3.fromRGB(10, 12, 16),
			TextSize = 14,
		}),
	})

	local checkboxLabel = Instance.new("TextLabel")
	checkboxLabel.Name = "Label"
	checkboxLabel.Position = UDim2.new(0, 28, 0, 0)
	checkboxLabel.Size = UDim2.new(1, -28, 1, 0)
	checkboxLabel.BackgroundTransparency = 1
	checkboxLabel.TextXAlignment = Enum.TextXAlignment.Left
	checkboxLabel.TextColor3 = INK
	checkboxLabel.TextSize = 14
	checkboxLabel.Text = "Send notifications"
	checkboxLabel.Parent = checkboxRow

	----------------------------------------------------------------------
	-- RADIO GROUP -- a factory, not a self-renderer (`Tabs.luau`'s own
	-- header explains why: a caller lays its options out however it
	-- likes). Each option's own `IsSelected` source IS exposed, unlike
	-- Checkbox's `Checked`, so the fill below reads it directly rather
	-- than tracking a shadow copy.
	----------------------------------------------------------------------

	sectionLabel("RADIO GROUP", 74)

	local sizes = { "small", "medium", "large" }
	local sizeGroup = Aether.RadioGroup({
		Options = sizes,
		InitialValue = "medium",
	})

	for i, size in ipairs(sizes) do
		local option = sizeGroup.GetOption(size)
		create("TextButton")(option.GetRootProps({
			Parent = body,
			Name = `Size{size}`,
			Position = UDim2.new(0, 16 + (i - 1) * 92, 0, 96),
			Size = UDim2.fromOffset(84, 28),
			BackgroundTransparency = 0,
			BackgroundColor3 = function()
				return if option.IsSelected() then ACCENT else INACTIVE
			end,
			TextColor3 = INK,
			TextSize = 13,
			Text = size,
		}))
	end

	----------------------------------------------------------------------
	-- TAB BAR -- the exact shape Dew's own `dashboard/dashboard.luau`
	-- migrated onto in milestone 54 sprint 1, reused here as the
	-- canonical example rather than reconstructed from doc-comment prose.
	----------------------------------------------------------------------

	sectionLabel("TAB BAR", 146)

	local TAB_WIDTH = 88
	local tabNames = { "profile", "billing", "team" }
	local tabs = Aether.Tabs({
		Tabs = tabNames,
		InitialActive = "profile",
	})

	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.Position = UDim2.new(0, 16, 0, 168)
	tabBar.Size = UDim2.new(1, -32, 0, 32)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = body

	for i, name in ipairs(tabNames) do
		create("TextButton")(tabs.GetTab(name).GetRootProps({
			Parent = tabBar,
			Name = `Tab{name}`,
			Position = UDim2.new(0, (i - 1) * TAB_WIDTH, 0, 0),
			Size = UDim2.fromOffset(TAB_WIDTH - 4, 28),
			BackgroundTransparency = 0,
			BackgroundColor3 = function()
				return if tabs.GetTab(name).IsActive() then ACCENT else INACTIVE
			end,
			TextColor3 = INK,
			TextSize = 13,
			Text = name,
		}))
	end

	--- `GetRootProps` ALREADY SETS `Visible` TO THE PANEL'S OWN
	--- `IsVisible` source (see `createTabs.luau`'s own `getPanel`), so
	--- `create` wires the reactive property up on its own -- nothing here
	--- has to read it back out.
	for _, name in ipairs(tabNames) do
		create("TextLabel")(tabs.GetPanel(name).GetRootProps({
			Parent = body,
			Position = UDim2.new(0, 16, 0, 208),
			Size = UDim2.new(1, -32, 0, 24),
			BackgroundTransparency = 1,
			TextColor3 = MUTED_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 13,
			Text = `{name} panel`,
		}))
	end
end)
