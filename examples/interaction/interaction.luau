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

	THIS PACKAGE INSTALLS ITS OWN FRAMEWORK, the same rule every installable
	Dew applet that consumes Aether follows (Dew's own ADR-008, and every
	`examples/aether/*` applet there carries its own `pesde.toml`). This
	example used to reach across the repo instead, with a bare relative
	`require("../../src/api")` -- which resolved correctly only because
	`dew run examples/interaction` runs the file IN PLACE, inside a real
	aether checkout where `../../src` genuinely exists. `dew install
	examples/interaction` copies THIS DIRECTORY ALONE into
	`%LOCALAPPDATA%\Dew\Applets\interaction`, where that same `../../src`
	resolves to a path that was never copied -- confirmed live, `dew start`
	against the installed copy failed with "could not resolve child
	component 'src'" while `dew run` against the repo could never reproduce
	it, because the two were never running the same file against the same
	directory shape. `pesde.toml` now declares `aether` as a workspace
	member (this package already lives inside aether's own repository, so a
	path dependency reaches it directly rather than pinning a git commit the
	way an external consumer would), and `pesde install` vendors a real,
	non-symlinked copy under `roblox_packages/` -- self-contained, and
	correct wherever this directory is copied to.
]]

local Aether = require("./roblox_packages/aether")
local vide = require("./roblox_packages/vide")
local create = vide.create
local source = vide.source
local action = vide.action
local cleanup = vide.cleanup

local WIDTH, HEIGHT = 360, 1380

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

		--- `Position`/`Size` STILL NEED TO BE EXPLICIT: `useFloating`'s own
		--- computed position is never applied to the surface it returns, and
		--- `Width` is declared on `ContextMenuProps` but never read anywhere
		--- in the file -- two latent bugs found alongside `Parent`'s own
		--- (now fixed in `ContextMenu.luau`), neither introduced by this
		--- milestone's own sprints.
		Aether.ContextMenu({
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
			Parent = body,
		})
	end

	----------------------------------------------------------------------
	-- TOOLTIP -- one demo, matching Pressable/ContextMenu's own shape.
	-- A tooltip has no persisted VALUE a caller could own or hand back --
	-- it is a dwell-timed presentation over hover, the same reason
	-- `TooltipMachine`'s own header describes it as "arms the delay" /
	-- "cancels it" rather than a value getter/setter pair. `Content` is
	-- the `Child` form's own binding, which carries no `typeof(x) ==
	-- "Instance"` guard (milestone 55 sprint 3's own regression suite
	-- exercises exactly this form for that reason, off-engine); the
	-- `Anchor` form used here works the same way live in Dew, verified
	-- with the same real hover this suite automated.
	----------------------------------------------------------------------

	sectionTitle("TOOLTIP")

	do
		local anchor: Frame? = nil
		local at = advance(40)
		Aether.Pressable({
			Parent = body,
			Name = "TooltipAnchor",
			Position = UDim2.new(0, 16, 0, at),
			Size = UDim2.fromOffset(140, 32),
			BackgroundTransparency = 0,
			BackgroundColor3 = ACCENT,

			action(function(ref)
				anchor = ref :: Frame
			end),

			create("TextLabel")({
				Name = "Label",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				TextColor3 = Color3.fromRGB(10, 12, 16),
				TextSize = 13,
				Text = "Hover me",
			}),
		})

		--- THE `Anchor` FORM RETURNS A BARE FUNCTION (a vide dynamic child,
		--- re-run on `isOpen`'s own transitions) RATHER THAN BUILDING
		--- ANYTHING ITSELF -- it has to be placed as an array child of a
		--- real `create()` call for vide to ever invoke it. A bare top-level
		--- call, tried first here, type-checked and ran without error and
		--- mounted nothing at all: the return value was simply discarded,
		--- which is exactly the "nothing appeared" shape the original Dew
		--- finding described, for a third, independent reason from the two
		--- milestone 55 sprint 3 already found.
		create("Frame")({
			Name = "TooltipHost",
			Parent = body,
			Size = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 1,

			Aether.Tooltip({
				Anchor = function()
					return anchor
				end,
				Content = "Rendered after a hover dwell, not on movement alone.",
				Delay = 0.4,
			}),
		})

		advance(4)
	end

	----------------------------------------------------------------------
	-- TREE VIEW -- one demo, uncontrolled only, and for a different
	-- reason than Pressable/ContextMenu/Tooltip above: `TreeController`
	-- has no controlled mode to demonstrate a second time. It exposes
	-- `InitialExpanded` and an `OnExpandedChanged` notification, but
	-- nothing shaped like `Checked`/`Value` -- a getter the controller
	-- reads instead of owning. Adding one is real ergonomics work in its
	-- own right (`createCheckbox`/`createRadioGroup`/`createTabs`-shaped),
	-- not a taxonomy correction, so it is not this milestone's to add.
	--
	-- `Virtualize = false` IS NOT USED HERE, and that is itself a finding:
	-- its own fallback branch calls `Deps.For`, and `Deps.luau`'s own
	-- export table has no `For` field at all (`For` lives on `Aether.For`,
	-- from `api.luau`, which `TreeView.luau` never requires) -- so that
	-- branch renders an empty `Frame` and nothing else, unconditionally.
	-- A real caller never hits it (`shouldVirtualize` defaults to `true`),
	-- which is exactly why nothing had found it before this demo did. Not
	-- this sprint's to fix; a `ScrollController` is what every real caller
	-- already needs to supply.
	----------------------------------------------------------------------

	sectionTitle("TREE VIEW")

	do
		rowLabel("Uncontrolled", advance(20))
		local treeY = advance(4)

		local roots = {
			{ Id = "src", Label = "src", Children = {
				{ Id = "api.luau", Label = "api.luau" },
				{ Id = "primitives", Label = "primitives", Children = {
					{ Id = "Tooltip.luau", Label = "Tooltip.luau" },
					{ Id = "TreeView.luau", Label = "TreeView.luau" },
				} },
			} },
			{ Id = "tests", Label = "tests" },
		}

		local ROW_HEIGHT = 22
		local VIEWPORT_HEIGHT = ROW_HEIGHT * 5
		local scroll = Aether.ScrollController.new({
			Orientation = "Vertical",
			ViewportSize = VIEWPORT_HEIGHT,
		})

		Aether.TreeView({
			Name = "TreeViewDemo",
			Parent = body,
			Position = UDim2.new(0, 16, 0, treeY),
			Size = UDim2.new(1, -32, 0, VIEWPORT_HEIGHT),
			Estimate = ROW_HEIGHT,
			ScrollController = scroll,
			Roots = roots,
			GetId = function(item: any)
				return item.Id
			end,
			GetChildren = function(item: any)
				return item.Children
			end,
			--- `expanded` IS ITS OWN `source`, SUBSCRIBED TO THE CONTROLLER,
			--- NOT A `Text` FUNCTION READING `controller.IsExpanded(node.Id)`
			--- DIRECTLY -- `TreeController.luau`'s own header is explicit
			--- that it holds no reactive library at all ("a binding decides
			--- what that means to a reactive graph"), so a plain read inside
			--- `Text`'s function has no `source` for vide to have subscribed
			--- to and never re-runs. `RenderNode` itself also runs once per
			--- key (`VirtualList`'s own reconciler keeps the built instance
			--- across a re-flatten), so `node.IsExpanded`, a snapshot from
			--- the moment this row first mounted, would be equally frozen.
			--- Confirmed live: clicking "src" swapped in its children but
			--- left its own ">" stuck until the label's own source, kept
			--- current by `controller.Subscribe`, replaced both reads.
			RenderNode = function(node, controller)
				local item = node.Node :: any
				local expanded = source(controller.IsExpanded(node.Id))
				cleanup(controller.Subscribe(function()
					expanded(controller.IsExpanded(node.Id))
				end))

				return Aether.Pressable({
					Name = `Row_{node.Id}`,
					Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
					BackgroundTransparency = 1,
					OnActivated = function()
						if node.HasChildren then
							controller.Toggle(node.Id)
						end
					end,

					create("TextLabel")({
						Name = "Label",
						Position = UDim2.new(0, node.Depth * 16, 0, 0),
						Size = UDim2.new(1, -node.Depth * 16, 1, 0),
						BackgroundTransparency = 1,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextColor3 = INK,
						TextSize = 12,
						Text = function()
							if not node.HasChildren then
								return `  {item.Label}`
							end
							return `{if expanded() then "v" else ">"} {item.Label}`
						end,
					}),
				})
			end,
		})

		advance(ROW_HEIGHT * 5 + 8)
	end

	----------------------------------------------------------------------
	-- TEXT INPUT -- one demo. `Value`/`OnChanged` is the whole surface:
	-- the field shows `localBuffer()` while focused and `Value()`
	-- whenever it is not, so an owner that writes `OnChanged` straight
	-- back into the same source (as here) gets the everyday "just types"
	-- behaviour, and an owner that filtered or rejected the change would
	-- see the field visibly hold its prior value the moment focus is
	-- lost -- the same controlled shape `Checkbox`'s own demo shows, just
	-- without a second, separate uncontrolled render to place beside it,
	-- since a text field with no external `Value` at all has nothing to
	-- redisplay once focus leaves it.
	--
	-- REAL KEYSTROKES DID NOT REACH THIS FIELD AT ALL UNDER DEW BEFORE THIS
	-- SPRINT, discovered building this exact section: `TextInputManager.luau`
	-- had a real (Roblox) editing path and a headless one (`HandleKey`), and
	-- Dew's own keyboard delivery -- new this milestone, mutating a native
	-- `TextBox` instance's `Text` directly -- matched neither. Fixed with a
	-- third `ensureProxy()` branch mirroring Roblox's hidden proxy `TextBox`
	-- without `PlayerGui` (`TextInputManager.luau`'s own header comment on
	-- `isDew` has the full account). Live-tested here: typing and Backspace
	-- both work. Dew's native `TextBox` has no cursor or selection concept
	-- of its own, though, so this field's click-to-place-caret and arrow-key
	-- navigation stay purely visual under Dew -- a real character always
	-- lands at the end regardless of where the caret is drawn, which is a
	-- limit of what Dew's own native `TextBox` can do today, not something
	-- fixed here.
	----------------------------------------------------------------------

	sectionTitle("TEXT INPUT")

	do
		local text = source("")
		local at = advance(32)
		Aether.TextInput({
			Parent = body,
			Name = "TextInputDemo",
			Position = UDim2.new(0, 16, 0, at),
			Size = UDim2.new(1, -32, 0, 28),
			BackgroundTransparency = 0,
			BackgroundColor3 = UNCHECKED,
			TextColor3 = INK,
			PlaceholderText = "Type here",
			PlaceholderColor3 = MUTED_TEXT,
			Value = text,
			OnChanged = function(value: string)
				text(value)
			end,
		})
		statusLabel(function()
			return `value: {text()}`
		end, advance(24), 16, 300)
	end

	----------------------------------------------------------------------
	-- SCROLL AREA -- not a parity demo, and the section itself says so.
	-- Neither `ark-ui` nor `zag.js` ships a scroll-area MACHINE to compare
	-- against: continuous drag offset and thumb position are a different
	-- shape than a discrete state machine, which is
	-- `.artifacts/project/decisions/primitive_layer_boundary.md`'s own
	-- reason `ScrollArea`/`Scrollbar` stay in `Primitives` at all. This
	-- section exists to show the primitive working, on its own terms, not
	-- to claim it against a peer that does not exist.
	--
	-- NO EXPLICIT `ContentHeight`/`CanvasSize` HERE, ON PURPOSE.
	-- `ScrollArea.luau`'s own auto-measurement (`AbsoluteContentSize` off a
	-- `UIListLayout`) is gated on `isRoblox` and skipped entirely under
	-- Dew -- what runs instead is its off-engine branch, polling
	-- `Deps.Host.Scene.Bounds` off the router's own frame pump. Leaving
	-- both props out is what lets that branch measure this section live,
	-- rather than this file declaring a number that drifts the next time a
	-- row's height changes.
	--
	----------------------------------------------------------------------

	sectionTitle("SCROLL AREA")

	do
		local at = advance(4)
		Aether.ScrollArea({
			Name = "ScrollAreaDemo",
			Parent = body,
			Position = UDim2.new(0, 16, 0, at),
			Size = UDim2.new(1, -32, 0, 160),
			Content = function()
				local rows = {}
				for i = 1, 12 do
					table.insert(rows, create("TextLabel")({
						Name = `Row{i}`,
						Size = UDim2.new(1, 0, 0, 28),
						BackgroundTransparency = 1,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextColor3 = INK,
						TextSize = 12,
						Text = `Row {i} of 12`,
					}))
				end
				return rows
			end,
		})

		advance(164)
	end
end)
