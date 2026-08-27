--!strict
--!tier math
local TreeController = require("../../src/controllers/TreeController")
local T = require("@testkit")

type SampleNode = {
	Id: string,
	Name: string,
	Children: { SampleNode }?,
}

local function testTreeExpansion()
	local controller = TreeController.new({ InitialExpanded = { "root" } })
	assert(controller.IsExpanded("root"), "root starts expanded")
	assert(not controller.IsExpanded("child-1"), "child-1 starts collapsed")
	assert(controller.GetExpandedCount() == 1, "count is 1")

	controller.Expand("child-1")
	assert(controller.IsExpanded("child-1"), "child-1 expanded")
	assert(controller.GetExpandedCount() == 2, "count is 2")

	controller.Toggle("child-1")
	assert(not controller.IsExpanded("child-1"), "child-1 toggled off")

	controller.ExpandPath({ "folder-a", "folder-b", "folder-c" })
	assert(controller.IsExpanded("folder-a"), "folder-a expanded")
	assert(controller.IsExpanded("folder-b"), "folder-b expanded")
	assert(controller.IsExpanded("folder-c"), "folder-c expanded")

	controller.CollapseAll()
	assert(controller.GetExpandedCount() == 0, "all collapsed")
end

local function testTreeFlattening()
	local controller = TreeController.new()

	local tree: { SampleNode } = {
		{
			Id = "A",
			Name = "Root A",
			Children = {
				{
					Id = "A1",
					Name = "Child A1",
					Children = {
						{ Id = "A1a", Name = "Leaf A1a" },
					},
				},
				{ Id = "A2", Name = "Leaf A2" },
			},
		},
		{
			Id = "B",
			Name = "Root B",
			Children = {
				{ Id = "B1", Name = "Leaf B1" },
			},
		},
	}

	local getId = function(n: SampleNode) return n.Id end
	local getChildren = function(n: SampleNode) return n.Children end

	-- 1. All collapsed: should only return Root A and Root B
	local flat1 = controller.Flatten(tree, getId, getChildren)
	assert(#flat1 == 2, `expected 2 root items, got {#flat1}`)
	assert(flat1[1].Id == "A" and flat1[1].Depth == 0 and not flat1[1].IsExpanded and flat1[1].HasChildren, "Root A structure")
	assert(flat1[2].Id == "B" and flat1[2].Depth == 0, "Root B structure")

	-- 2. Expand A: should return Root A, Child A1, Leaf A2, Root B
	controller.Expand("A")
	local flat2 = controller.Flatten(tree, getId, getChildren)
	assert(#flat2 == 4, `expected 4 items after expanding A, got {#flat2}`)
	assert(flat2[1].Id == "A" and flat2[1].IsExpanded, "A is expanded")
	assert(flat2[2].Id == "A1" and flat2[2].Depth == 1 and flat2[2].HasChildren and not flat2[2].IsExpanded, "A1 at depth 1")
	assert(flat2[3].Id == "A2" and flat2[3].Depth == 1 and not flat2[3].HasChildren, "A2 at depth 1")
	assert(flat2[4].Id == "B" and flat2[4].Depth == 0, "B at depth 0")

	-- 3. Expand A1: should return Root A, Child A1, Leaf A1a, Leaf A2, Root B
	controller.Expand("A1")
	local flat3 = controller.Flatten(tree, getId, getChildren)
	assert(#flat3 == 5, `expected 5 items after expanding A1, got {#flat3}`)
	assert(flat3[3].Id == "A1a" and flat3[3].Depth == 2, "A1a at depth 2")
end

T.test("tree expansion state", testTreeExpansion, "math")
T.test("tree flattening to virtual list", testTreeFlattening, "math")

return T.run("TreeController")
