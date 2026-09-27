--!strict
--[[
	Aether's headless machines, one demo per widget, controlled and
	uncontrolled side by side wherever the machine actually supports both --
	the same shape ark-ui's and zag.js's own demo sites use to show a widget
	off: one page, one section per component, no fake Router/Selection
	double anywhere in it.

	`Aether.Checkbox`, `Aether.RadioGroup`, `Aether.Tabs` and `Aether.ContextMenu`
	all default their own Router/Selection to the real singletons (milestone
	54 sprint 2's own ambient `RouterContext`), so nothing here ever names
	`PointerRouter` or `SelectionRouter`.

	CONTROLLED MEANS WHAT IT MEANS IN ark-ui/zag.js: a getter handed to the
	machine instead of a plain value. The machine reads it, never writes it,
	and a click or a keystroke calls the machine's own `On*Changed` WITHOUT
	moving what the machine reports -- the caller's own state is what
	actually has to move, the same way a controlled `<input>` never checks
	itself. `Checkbox`/`RadioGroup`/`Tabs` grew this dual mode alongside this
	example, because there was nothing controlled to demonstrate before it.
	`ContextMenu`'s own Primitive was already controlled-only (`IsOpen` is a
	required getter, not an optional one), so it gets one demo, not two.
	`Pressable` has no persisted value at all -- press/hover/activate are
	events, not state -- so it gets one demo too.

	THE FRAMEWORK COMES FROM THIS REPOSITORY'S OWN `src/` AND `roblox_packages/`,
	by relative require, the same way `examples/counter`'s own desktop entry
	reaches `roblox_packages/vide` -- this example lives inside the framework
	it demonstrates rather than installing it as a dependency.
]]

local Aether = require("../../src/api")
local vide = require("../../roblox_packages/vide")
local create = vide.create
local source = vide.source

local WIDTH, HEIGHT = 360, 760

local root = desktop.Widget({ width = WIDTH, height = HEIGHT, anchor = "center" })

local INK = Color3.fromRGB(233, 239, 249)
local MUTED_TEXT = Color3.fromRGB(146, 162, 188)
local PANEL = Color3.fromRGB(18, 20, 26)
local ACCENT = Color3.fromRGB(96, 170, 255)
local UNCHECKED = Color3.fromRGB(46, 51, 64)
local INACTIVE = Color3.fromRGB(26, 29, 38)
local PRESSED_COLOR = Color3.fromRGB(255, 176, 96)

vide.root(function()
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 1, 0)
	body.BackgroundColor3 = PANEL
	body.BorderSizePixel = 0
	body.Parent = root

	--- A RUNNING LAYOUT CURSOR, not hand-placed pixels per row -- the page
	--- grows by section, and a section's own height is however many rows it
	--- asked for rather than a number copied between sections that drift out
	--- of sync the next time one of them changes.
	local y = 0
	local function advance(amount: number): number
		local at = y
		y += amount
		return at
	end

	local function sectionTitle(text: string)
		local label = Instance.new("TextLabel")
		label.Name = "SectionTitle"
		label.Position = UDim2.new(0, 16, 0, advance(26))
		label.Size = UDim2.new(1, -32, 0, 18)
		label.BackgroundTransparency = 1
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = MUTED_TEXT
		label.TextSize = 12
		label.Font = Enum.Font.GothamBold
		label.Text = text
		label.Parent = body
	end

	local function rowLabel(text: string, atY: number)
		local label = Instance.new("TextLabel")
		label.Name = "RowLabel"
		label.Position = UDim2.new(0, 16, 0, atY)
		label.Size = UDim2.new(0, 96, 0, 24)
		label.BackgroundTransparency = 1
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = MUTED_TEXT
		label.TextSize = 12
		label.Text = text
		label.Parent = body
	end

	--- BUILT WITH `create`, NOT `Instance.new` -- unlike `sectionTitle`/
	--- `rowLabel`, this label's own `Text` is a REACTIVE FUNCTION, and only
	--- `create`'s own `implicit_effect.property` binds a function prop
	--- reactively. A raw `label.Text = getText` assignment (tried first, and
	--- the reason this file's own live test caught the exact same bug class
	--- `panel.Visible` already had) just sets `Text` to a Luau function
	--- value, which is not a string and errors the moment the host tries to
	--- draw it.
	local function statusLabel(getText: () -> string, atY: number, atX: number, width: number)
		create("TextLabel")({
			Name = "Status",
			Parent = body,
			Position = UDim2.new(0, atX, 0, atY),
			Size = UDim2.new(0, width, 0, 24),
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = MUTED_TEXT,
			TextSize = 12,
			Text = getText,
		})
	end

	----------------------------------------------------------------------
	-- PRESSABLE -- press/hover/activate are events, not state, so there is
	-- nothing controlled to demonstrate: one demo, matching the shape
	-- Dew's own `examples/aether/pressable` already uses.
	----------------------------------------------------------------------

	sectionTitle("PRESSABLE")

	local pressed = source(false)
	local presses = source(0)

	do
		local at = advance(40)
		Aether.Pressable({
			Parent = body,
			Name = "PressableDemo",
			Position = UDim2.new(0, 16, 0, at),
			Size = UDim2.fromOffset(140, 32),
			BackgroundTransparency = 0,
			BackgroundColor3 = function()
				return if pressed() then PRESSED_COLOR else ACCENT
			end,
			OnPressed = function()
				pressed(true)
			end,
			OnReleased = function()
				pressed(false)
			end,
			OnActivated = function()
				presses(presses() + 1)
			end,

			create("TextLabel")({
				Name = "Label",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				TextColor3 = Color3.fromRGB(10, 12, 16),
				TextSize = 13,
				Text = "Press me",
			}),
		})
		statusLabel(function()
			return `presses: {presses()}`
		end, at + 6, 168, 160)
	end

	----------------------------------------------------------------------
	-- CHECKBOX -- self-rendering, so `Aether.Checkbox` builds its own
	-- Frame. Uncontrolled owns `Checked` itself, starting from the value
	-- given; controlled reads a getter and never writes it, so the
	-- external state and the click callback are shown as two separate
	-- moving parts.
	----------------------------------------------------------------------

	sectionTitle("CHECKBOX")

	do
		local uncontrolledChecked = source(false)
		local at = advance(28)
		rowLabel("Uncontrolled", at)
		Aether.Checkbox({
			Parent = body,
			Name = "CheckboxUncontrolled",
			Position = UDim2.new(0, 120, 0, at + 2),
			Size = UDim2.fromOffset(20, 20),
			BackgroundTransparency = 0,
			BackgroundColor3 = function()
				return if uncontrolledChecked() then ACCENT else UNCHECKED
			end,
			OnCheckedChanged = function(value: boolean)
				uncontrolledChecked(value)
			end,
			create("TextLabel")({
				Name = "Mark",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = function()
					return if uncontrolledChecked() then "x" else ""
				end,
				TextColor3 = Color3.fromRGB(10, 12, 16),
				TextSize = 14,
			}),
		})
	end

	do
		--- CONTROLLED. `externalChecked` is the ONLY thing that decides what
		--- the checkbox shows -- `OnCheckedChanged` fires and this demo
		--- chooses to accept it by writing back into the same source, but a
		--- consumer that validated first and rejected the change would leave
		--- `externalChecked` untouched, and the checkbox would visibly stay
		--- exactly where it was. Uncontrolled above cannot do that: it always
		--- accepts.
		local externalChecked = source(true)
		local at = advance(32)
		rowLabel("Controlled", at)
		Aether.Checkbox({
			Parent = body,
			Name = "CheckboxControlled",
			Position = UDim2.new(0, 120, 0, at + 2),
			Size = UDim2.fromOffset(20, 20),
			BackgroundTransparency = 0,
			Checked = externalChecked,
			BackgroundColor3 = function()
				return if externalChecked() then ACCENT else UNCHECKED
			end,
			OnCheckedChanged = function(value: boolean)
				externalChecked(value)
			end,
			create("TextLabel")({
				Name = "Mark",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = function()
					return if externalChecked() then "x" else ""
				end,
				TextColor3 = Color3.fromRGB(10, 12, 16),
				TextSize = 14,
			}),
		})
		statusLabel(function()
			return `external: {tostring(externalChecked())}`
		end, at + 6, 152, 160)
	end

	----------------------------------------------------------------------
	-- RADIO GROUP -- a factory, not a self-renderer (`Tabs.luau`'s own
	-- header explains why: a caller lays its options out however it
	-- likes). Uncontrolled reads each option's own reactive `IsSelected`;
	-- controlled reads the SAME external getter for every option, since
	-- the group's own truth is one value shared by all of them.
	----------------------------------------------------------------------

	sectionTitle("RADIO GROUP")

	local sizes = { "small", "medium", "large" }

	do
		local at = advance(28)
		rowLabel("Uncontrolled", at)
		local group = Aether.RadioGroup({
			Options = sizes,
			InitialValue = "medium",
		})
		for i, size in ipairs(sizes) do
			local option = group.GetOption(size)
			create("TextButton")(option.GetRootProps({
				Parent = body,
				Name = `SizeUncontrolled{size}`,
				Position = UDim2.new(0, 120 + (i - 1) * 76, 0, at),
				Size = UDim2.fromOffset(70, 24),
				BackgroundTransparency = 0,
				BackgroundColor3 = function()
					return if option.IsSelected() then ACCENT else INACTIVE
				end,
				TextColor3 = INK,
				TextSize = 12,
				Text = size,
			}))
		end
	end

	do
		--- CONTROLLED. Every option's `IsSelected` reads the SAME
		--- `externalSize` getter (`option.IsSelected() == "large"`, not a
		--- source of its own), so the group can never disagree with itself
		--- the way three independently-mirrored copies could.
		local externalSize = source("large")
		local at = advance(32)
		rowLabel("Controlled", at)
		local group = Aether.RadioGroup({
			Options = sizes,
			Value = externalSize,
			OnValueChanged = function(value: any)
				externalSize(value)
			end,
		})
		for i, size in ipairs(sizes) do
			local option = group.GetOption(size)
			create("TextButton")(option.GetRootProps({
				Parent = body,
				Name = `SizeControlled{size}`,
				Position = UDim2.new(0, 120 + (i - 1) * 76, 0, at),
				Size = UDim2.fromOffset(70, 24),
				BackgroundTransparency = 0,
				BackgroundColor3 = function()
					return if option.IsSelected() then ACCENT else INACTIVE
				end,
				TextColor3 = INK,
				TextSize = 12,
				Text = size,
			}))
		end
		statusLabel(function()
			return `external: {externalSize()}`
		end, advance(20), 120, 200)
	end

	----------------------------------------------------------------------
	-- TAB BAR -- the exact factory shape Dew's own
	-- `dashboard/dashboard.luau` migrated onto. Uncontrolled reads each
	-- tab's own reactive `IsActive`/panel's `IsVisible`; controlled reads
	-- the same external getter for both, the same reason RadioGroup's own
	-- controlled demo shares one getter across every option.
	----------------------------------------------------------------------

	sectionTitle("TAB BAR")

	local TAB_WIDTH = 78
	local tabNames = { "profile", "billing", "team" }

	do
		local at = advance(28)
		rowLabel("Uncontrolled", at)
		local tabs = Aether.Tabs({
			Tabs = tabNames,
			InitialActive = "profile",
		})
		for i, name in ipairs(tabNames) do
			create("TextButton")(tabs.GetTab(name).GetRootProps({
				Parent = body,
				Name = `TabUncontrolled{name}`,
				Position = UDim2.new(0, 120 + (i - 1) * TAB_WIDTH, 0, at),
				Size = UDim2.fromOffset(TAB_WIDTH - 4, 24),
				BackgroundTransparency = 0,
				BackgroundColor3 = function()
					return if tabs.GetTab(name).IsActive() then ACCENT else INACTIVE
				end,
				TextColor3 = INK,
				TextSize = 11,
				Text = name,
			}))
		end
		local panelY = advance(24)
		for _, name in ipairs(tabNames) do
			create("TextLabel")(tabs.GetPanel(name).GetRootProps({
				Parent = body,
				Position = UDim2.new(0, 120, 0, panelY),
				Size = UDim2.new(0, 220, 0, 20),
				BackgroundTransparency = 1,
				TextColor3 = MUTED_TEXT,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = 12,
				Text = `{name} panel`,
			}))
		end
	end

	do
		--- CONTROLLED. Every tab's `IsActive` and every panel's `IsVisible`
		--- read the SAME `externalTab` getter.
		local externalTab = source("billing")
		local at = advance(32)
		rowLabel("Controlled", at)
		local tabs = Aether.Tabs({
			Tabs = tabNames,
			Active = externalTab,
			OnActiveChanged = function(value: any)
				externalTab(value)
			end,
		})
		for i, name in ipairs(tabNames) do
			create("TextButton")(tabs.GetTab(name).GetRootProps({
				Parent = body,
				Name = `TabControlled{name}`,
				Position = UDim2.new(0, 120 + (i - 1) * TAB_WIDTH, 0, at),
				Size = UDim2.fromOffset(TAB_WIDTH - 4, 24),
				BackgroundTransparency = 0,
				BackgroundColor3 = function()
					return if tabs.GetTab(name).IsActive() then ACCENT else INACTIVE
				end,
				TextColor3 = INK,
				TextSize = 11,
				Text = name,
			}))
		end
		local panelY = advance(24)
		for _, name in ipairs(tabNames) do
			create("TextLabel")(tabs.GetPanel(name).GetRootProps({
				Parent = body,
				Position = UDim2.new(0, 120, 0, panelY),
				Size = UDim2.new(0, 220, 0, 20),
				BackgroundTransparency = 1,
				TextColor3 = MUTED_TEXT,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = 12,
				Text = `{name} panel`,
			}))
		end
		statusLabel(function()
			return `external: {externalTab()}`
		end, advance(20), 120, 200)
	end

	----------------------------------------------------------------------
	-- CONTEXT MENU -- one demo, not two. `Aether.ContextMenu`'s own Props
	-- type makes `IsOpen` a REQUIRED getter, not an optional one -- the
	-- Primitive is controlled-only by design (a menu summoned by a click
	-- sits inside something that already captured the state), the same
	-- reason `createContextMenu`'s own doc comment gives. There is no
	-- uncontrolled mode here to demonstrate a second time.
	----------------------------------------------------------------------

	sectionTitle("CONTEXT MENU")

	do
		local isOpen = source(false)
		local anchor = source(Vector2.new(16, 0))
		local chosen = source(nil :: string?)

		local items = {}
		for _, label in ipairs({ "Cut", "Copy", "Paste" }) do
			table.insert(items, {
				Id = label,
				Label = label,
				OnActivated = function()
					chosen(label)
				end,
			})
		end

		local at = advance(32)
		Aether.Pressable({
			Parent = body,
			Name = "OpenMenuButton",
			Position = UDim2.new(0, 16, 0, at),
			Size = UDim2.fromOffset(120, 28),
			BackgroundTransparency = 0,
			BackgroundColor3 = ACCENT,
			OnActivated = function()
				anchor(Vector2.new(16, at + 32))
				isOpen(true)
			end,

			create("TextLabel")({
				Name = "Label",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				TextColor3 = Color3.fromRGB(10, 12, 16),
				TextSize = 13,
				Text = "Open menu",
			}),
		})
		statusLabel(function()
			return `chosen: {chosen() or "nothing"}`
		end, at + 4, 152, 160)

		advance(160)

		--- `ContextMenu.luau`'s OWN WRAPPER NEVER FORWARDS AN UNRECOGNISED
		--- PROP -- unlike `Checkbox.luau`, which spreads its whole `props`
		--- table into `create("Frame")(machine.GetRootProps(props))`,
		--- `ContextMenu.luau` builds its surface from a hand-picked table of
		--- exactly the keys it names (`IsOpen`, `OnClose`, `AnchorPosition`,
		--- `Position`, `Size`, `Items`, `RenderItem`) and nothing else, so a
		--- `Parent` prop handed in here is silently dropped -- the menu opens
		--- (`isOpen` genuinely flips true) and is never actually parented
		--- anywhere, which reads exactly like "nothing happened" from the
		--- caller's side. `.Parent` is set on the returned handle instead,
		--- the same way Dew's own working `examples/aether/contextmenu`
		--- nests the same call as a CHILD of another `create()` rather than
		--- naming `Parent` at all -- two different fixes for the one bug,
		--- found here rather than fixed in `ContextMenu.luau` itself.
		--- `Position`/`Size` also still need to be explicit: `useFloating`'s
		--- own computed position is never applied to the surface it returns,
		--- and `Width` is declared on `ContextMenuProps` but never read
		--- anywhere in the file -- two more latent bugs alongside the first,
		--- none of them introduced by this milestone's own sprints.
		local menu = Aether.ContextMenu({
			IsOpen = isOpen,
			OnClose = function()
				isOpen(false)
			end,
			AnchorPosition = anchor,
			Position = UDim2.fromOffset(16, at + 32),
			Size = UDim2.fromOffset(132, 0),
			Items = function()
				return items
			end,
		})
		menu.Parent = body
	end
end)
