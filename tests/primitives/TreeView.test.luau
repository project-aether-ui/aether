--!strict
--!tier math
--[=[
	TreeView — exercises the primitive itself, not TreeController underneath it.

	Every assertion here runs through TreeView's virtualized path (the one
	DebuggerUI uses): Roots -> TreeController.Flatten -> VirtualList -> RenderNode.
	Reading the row list back out of RenderNode is what proves the flattened
	stream actually reached the list, and reading GetContentSize() off the
	ScrollController proves the index was sized from it.

	Live Expand()/Collapse() IS covered, as of ms-51 M14. It could not be before:
	VirtualList tracks props.Items inside a vide `effect`, and testkit's VideShim
	ran effects ONCE with no dependency tracking, so a post-construction expansion
	could not propagate and asserting on it would only have confirmed the shim.
	Aether.Host.Headless runs vide's real effect, so the re-render is now
	observable headlessly and is asserted directly.
]=]
local T = require("@testkit")
local ScrollController = require("../../src/controllers/ScrollController")
local TreeView = require("../../src/primitives/TreeView")

local ESTIMATE = 20

local function build(props: any): (any, { any }, any)
	local rendered = {}
	local seenController = nil
	local scroll = ScrollController.new({ Orientation = "Vertical", ViewportSize = 300 })

	local view = TreeView({
		ScrollController = scroll,
		Estimate = ESTIMATE,
		Overscan = 1,
		Roots = props.Roots,
		InitialExpanded = props.InitialExpanded,
		RenderNode = function(node, controller)
			seenController = controller
			table.insert(rendered, node)
			return { Destroy = function() end }
		end,
	} :: any)

	return view, rendered, { Scroll = scroll, Controller = function() return seenController end }
end

local ROOTS = {
	{ Id = "f1", Children = { { Id = "c1" }, { Id = "c2", Children = { { Id = "g1" } } } } },
	{ Id = "f2", Children = { { Id = "c3" } } },
}

local function testCollapsedRendersRootsOnly()
	local view, rendered, ctx = build({ Roots = ROOTS })

	assert(view ~= nil, "TreeView constructed")
	assert(#rendered == 2, `collapsed tree renders 2 roots, got {#rendered}`)
	assert(rendered[1].Id == "f1" and rendered[2].Id == "f2", "roots render in order")

	-- Default GetChildren derives from the `Children` key with no accessor supplied.
	assert(rendered[1].HasChildren == true, "f1 reports children via default accessor")
	assert(rendered[1].IsExpanded == false, "f1 starts collapsed")
	assert(rendered[1].Depth == 0 and rendered[2].Depth == 0, "roots sit at depth 0")

	-- The list was sized from the flattened stream, not from the raw root table.
	assert(ctx.Scroll.GetContentSize() == 2 * ESTIMATE,
		`content sized to 2 rows, got {ctx.Scroll.GetContentSize()}`)

	-- RenderNode receives the live controller so nodes can drive their own disclosure.
	local controller = ctx.Controller()
	assert(controller ~= nil and type(controller.Toggle) == "function",
		"RenderNode is handed the tree controller")
	assert(controller.IsExpanded("f1") == false, "controller agrees f1 is collapsed")
end

local function testInitialExpandedFlattensNestedDepths()
	local _, rendered, ctx = build({ Roots = ROOTS, InitialExpanded = { "f1", "c2" } })

	assert(#rendered == 5, `two expanded branches render 5 rows, got {#rendered}`)

	local order = {}
	for i, node in ipairs(rendered) do
		order[i] = `{node.Id}@{node.Depth}`
	end
	local actual = table.concat(order, ",")
	assert(actual == "f1@0,c1@1,c2@1,g1@2,f2@0",
		`depth-first traversal with indent depths, got {actual}`)

	assert(rendered[3].IsExpanded == true, "c2 is expanded")
	assert(rendered[4].HasChildren == false, "leaf g1 reports no children")
	assert(rendered[5].Depth == 0, "f2 returns to depth 0 after the nested branch")

	assert(ctx.Scroll.GetContentSize() == 5 * ESTIMATE,
		`content sized to 5 rows, got {ctx.Scroll.GetContentSize()}`)
end

--- The case the shim made impossible. Expansion happens AFTER construction, so
--- nothing here is pre-flattened: the rows can only appear if TreeView's
--- controller subscription re-flattened and VirtualList's effect re-ran on the
--- new stream.
local function testLiveExpandRerenders()
	local _, rendered, ctx = build({ Roots = ROOTS })
	local controller = ctx.Controller()

	assert(#rendered == 2, `2 rows before expanding, got {#rendered}`)
	assert(ctx.Scroll.GetContentSize() == 2 * ESTIMATE, "content sized to 2 rows")

	controller.Expand("f1")

	assert(#rendered == 4, `f1's two children render on expand, got {#rendered}`)
	assert(rendered[3].Id == "c1" and rendered[4].Id == "c2", "the new rows are f1's children")
	assert(rendered[3].Depth == 1, "children render at depth 1")
	assert(ctx.Scroll.GetContentSize() == 4 * ESTIMATE,
		`content re-sized to 4 rows, got {ctx.Scroll.GetContentSize()}`)

	controller.Collapse("f1")
	assert(ctx.Scroll.GetContentSize() == 2 * ESTIMATE,
		`content re-sized back to 2 rows on collapse, got {ctx.Scroll.GetContentSize()}`)
end

T.test("tree view renders only root rows while collapsed", testCollapsedRendersRootsOnly, "math")
T.test("tree view re-renders on live Expand and Collapse", testLiveExpandRerenders, "math")
T.test("tree view flattens nested depths from InitialExpanded", testInitialExpandedFlattensNestedDepths, "math")

return T.run("TreeView")
