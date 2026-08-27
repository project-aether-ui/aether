--!strict
--[[
	spektr/zune_host · Browser — the story picker, built in Aether (ms-53 P1).

	    zune run pkgs/ui/hosts/zune/src/Native.luau --raster --browse

	A sidebar of every discovered story; click one and it mounts beside the list.

	IT IS A STORY ITSELF, structurally. `Browser.Build` returns the same thing a
	story returns -- a thunk producing a root instance -- so it plugs into
	`App.create({ Story = ... })` with no new application API. The browser is an
	Aether application like any other, which is the point: the tool that shows the
	framework off is built out of it, and anything wrong with the framework shows
	up here first.

	SELECTION REBUILDS RATHER THAN SWAPPING REACTIVELY.

	`host.switch` exists and would swap the mounted story inside one tree. This
	rebuilds the whole app instead, through exactly the path a hot reload takes --
	and that is a deliberate trade, not laziness:

	  * The reload path is already proven: it destroys the old tree, rebuilds, and
	    `--reload-check` asserts across twenty cycles that the router's
	    registration count does not drift. A reactive swap would be a SECOND
	    teardown path with its own leak profile and no gate.
	  * A story is meant to be seen from a clean state. Swapping in place keeps
	    whatever the previous story left in shared singletons; a rebuild cannot.
	  * It costs a reload -- 30-150 ms -- which is below what a human reads as a
	    delay on a click.

	The one thing it gives up is preserving state across a selection, which is
	exactly what a story browser should NOT do.
]]

local Aether = require("../../../src")
local Button = require("../../../components/button/src/Button").Button

local Browser = {}

local SIDEBAR_W = 300
local ROW_H = 26
local HEADER_H = 22
local LIST_GAP = 2
local LIST_PAD = 8

--- How tall the list is, from the story count. Exported because the host sizes
--- its window from it and the gate asserts against it -- see the scrolling note
--- on `Browser.Build`.
function Browser.ListHeight(stories: { any }): number
	local headers, rows = 0, 0
	local lastTitle: string? = nil
	for _, st in ipairs(stories) do
		if st.Title ~= lastTitle then
			lastTitle = st.Title
			headers += 1
		end
		rows += 1
	end
	return headers * HEADER_H + rows * ROW_H + (headers + rows) * LIST_GAP + LIST_PAD * 2
end

export type Options = {
	Stories: { any },
	--- Id of the story currently mounted, or nil for none.
	Selected: string?,
	--- Called with a story id when a row is clicked. The host records it and
	--- rebuilds; nothing here mounts anything itself.
	OnSelect: (string) -> (),
}

function Browser.Build(opts: Options): () -> any
	return function(): any
		local host = Aether.Host.detect()
		local V = host.Vocabulary

		local rows: { any } = {}
	--- Counted as the list is built, so the scroll extent is DERIVED rather than
	--- measured. `AutomaticCanvasSize` alone left the canvas at zero here, and a
	--- zero extent means the wheel scrolls nothing -- which looks exactly like a
	--- list that simply ends. The browser knows how tall its own list is; saying
	--- so is cheaper and more reliable than asking for it to be discovered.
		local headerCount, rowCount = 0, 0

		--- One header per title, then its stories. The list arrives already
		--- grouped and ordered from `Stories.Discover`, so this only has to notice
		--- when the title changes -- no sorting, no second pass, and the order on
		--- screen is the order everything else in the pipeline uses.
		local lastTitle: string? = nil
		local order = 0
		for _, st in ipairs(opts.Stories) do
			if st.Title ~= lastTitle then
				lastTitle = st.Title
				headerCount += 1
				order += 1
				table.insert(rows, host.create("TextLabel")({
					Name = `Header_{order}`,
					Size = V.UDim2.new(1, 0, 0, HEADER_H),
					LayoutOrder = order,
					BackgroundTransparency = 1,
					Text = st.Title,
					TextSize = 11,
					TextColor3 = V.Color3.fromRGB(120, 130, 150),
					TextXAlignment = "Left",
				}))
			end
			order += 1
			rowCount += 1

			--- CAPTURED PER ROW. `st` is the loop variable; a closure over it
			--- without this local would, in a language that reused the slot, hand
			--- every row the last story. Luau gives each iteration its own, but
			--- writing it down costs nothing and the failure it prevents -- every
			--- button opening the same story -- is one people actually ship.
			local id = st.Id
			local selected = opts.Selected == id

			table.insert(rows, Button({
				Name = `Row_{order}`,
				Content = { st.Name },
				--- EXPLICIT, because Button's `AutomaticSize.X` resolves to zero
				--- width off-engine -- the solver measures text but not children.
				--- Found by `--stories-check`; see the note in Button's stories.
				Size = V.UDim2.new(1, -8, 0, ROW_H),
				LayoutOrder = order,
				OnActivated = function()
					opts.OnSelect(id)
				end,
				--- The current row reads as chosen. Nothing else distinguishes
				--- them, and a browser where you cannot tell what you are looking
				--- at is a list, not a browser.
				TextColor3 = if selected
					then V.Color3.fromRGB(255, 255, 255)
					else V.Color3.fromRGB(170, 180, 200),
			}))
		end

		--- THE LIST SCROLLS, and the note that used to sit here was wrong.
		---
		--- P1 concluded "the wheel does not turn" after pressing every row and
		--- getting nothing from the last three, and after a wheel that moved
		--- nothing. The rows were genuinely below the fold; the wheel was
		--- genuinely not moving them. But it was only ever tried with a NEGATIVE
		--- delta at offset zero -- scrolling UP, at the top, which correctly does
		--- nothing. The conclusion was drawn from one direction of one test.
		---
		--- What was actually broken is narrower and was found in ms-53 D2: the
		--- viewport height is measured only in Roblox, so off-engine the controller
		--- clamped against a viewport nobody had measured and the list over-scrolled
		--- 220 px past its end. Fixed in `ScrollArea`.
		---
		--- Aether's own ScrollingFrame, not a hand-rolled one: it is the assembly
		--- this framework ships for exactly this, it brings the scrollbar and the
		--- wheel with it, and using anything else here would mean the tool that
		--- demonstrates the framework quietly declining to use it.
		local sidebar = host.create("Frame")({
			Name = "StorySidebar",
			Size = V.UDim2.new(0, SIDEBAR_W, 1, 0),
			BackgroundColor3 = V.Color3.fromRGB(18, 21, 28),
			BackgroundTransparency = 0,
			Aether.Assemblies.ScrollingFrame({
				Name = "StoryList",
				Size = V.UDim2.new(1, 0, 1, 0),
				StepSize = ROW_H + LIST_GAP,
				Layout = "List",
				--- NOT declared by hand. The formula that used to sit here
				--- over-counted by 72 px -- one gap too many and a bottom padding
				--- that does not exist -- and the list over-scrolled by exactly
				--- that. ms-53 D2 taught the ScrollArea to measure its own content
				--- off-engine, which is both more accurate and one less thing to
				--- keep in step with the layout.
				Children = rows,
			}),
		})

		--- The stage. The story's own root is parented here by the caller's thunk,
		--- so the story is laid out in a box that is not the whole window -- which
		--- is closer to how a component is used than a full-viewport mount, and
		--- catches a component that only looks right at 1280 wide.
		local stageChildren: { any } = {}
		if opts.Selected ~= nil then
			for _, st in ipairs(opts.Stories) do
				if st.Id == opts.Selected then
					local ok, built = pcall(st.Build)
					if ok then
						table.insert(stageChildren, built)
					else
						--- A BROKEN STORY MUST NOT TAKE THE BROWSER DOWN. It is the
						--- state a story is in while being written, and the same
						--- argument the reload path makes for surviving a syntax
						--- error applies here.
						table.insert(stageChildren, host.create("TextLabel")({
							Name = "StoryError",
							Size = V.UDim2.new(1, -40, 0, 80),
							Position = V.UDim2.fromOffset(20, 20),
							BackgroundTransparency = 1,
							Text = `{st.Id} failed to build:\n{tostring(built)}`,
							TextSize = 13,
							TextColor3 = V.Color3.fromRGB(240, 120, 120),
							TextXAlignment = "Left",
							TextYAlignment = "Top",
						}))
					end
					break
				end
			end
		end

		local stage = host.create("Frame")({
			Name = "StoryStage",
			Size = V.UDim2.new(1, -SIDEBAR_W, 1, 0),
			Position = V.UDim2.fromOffset(SIDEBAR_W, 0),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			table.unpack(stageChildren),
		})

		return host.create("Frame")({
			Name = "StoryBrowser",
			Size = V.UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			sidebar,
			stage,
		})
	end
end

return Browser
