--!strict
--[[
	Layout answers a rectangle cannot carry, for Studio's command bar.

	The engine runner reads AbsolutePosition and AbsoluteSize, so it cannot say
	what a property defaults to or what a layout reports about itself. This
	script prints both. It is NOT synced by the Rojo project and never runs on
	its own: paste the whole file into the command bar in Edit mode while
	`rojo serve conformance/roblox/default.project.json` is connected, because
	the read-backs build trees from the synced cases.

	Every line it prints is evidence to copy back by hand. Nothing here asserts.
]]

local StarterGui = game:GetService("StarterGui")
local harness = game:GetService("StarterPlayer").StarterPlayerScripts:FindFirstChild("Conformance")
assert(harness, "Conformance is not synced: connect Rojo to conformance/roblox/default.project.json first")
local decode = require(harness:WaitForChild("decode") :: ModuleScript) :: any
local cases = harness:WaitForChild("cases")

print(`-- layout defaults, Roblox {version()}`)

--- Defaults. SortOrder is the one that decides whether an unsorted list is
--- ordered by Name; the rest are cheap to read while the instances exist.
local defaults: { { string } } = {
	{ "UIListLayout", "SortOrder", "FillDirection", "Wraps", "HorizontalFlex", "VerticalFlex", "ItemLineAlignment" },
	{ "UIGridLayout", "SortOrder", "FillDirection", "CellSize", "CellPadding", "FillDirectionMaxCells", "StartCorner" },
	{ "UITableLayout", "SortOrder", "FillDirection" },
	{ "UIPageLayout", "SortOrder", "FillDirection" },
	{ "UIFlexItem", "FlexMode", "GrowRatio", "ShrinkRatio", "ItemLineAlignment" },
	{ "UISizeConstraint", "MinSize", "MaxSize" },
}
for _, row in ipairs(defaults) do
	local instance = Instance.new(row[1])
	for i = 2, #row do
		print(`default {row[1]}.{row[i]} = {tostring((instance :: any)[row[i]])}`)
	end
	instance:Destroy()
end

--- Read-backs, built from the same case files the engine runner uses, so the
--- tree is exactly the one whose rectangles it prints.
local function build(node: any, parent: Instance): Instance
	local instance = Instance.new(node.class)
	for key, value in pairs(decode.props(node)) do
		(instance :: any)[key] = value
	end
	for _, child in ipairs(node.children or {}) do
		build(child, instance)
	end
	instance.Parent = parent
	return instance
end

local readBacks = {
	"uilistlayout_wraps_horizontal",
	"uilistlayout_horizontal_flex_none",
	"uilistlayout_horizontal_flex_fill",
	"uilistlayout_horizontal_flex_space_around",
	"uilistlayout_horizontal_flex_space_between",
	"uilistlayout_horizontal_flex_space_evenly",
	"uigridlayout_defaults",
	"uigridlayout_fill_direction_max_cells",
}

local screen = Instance.new("ScreenGui")
screen.Name = "LayoutDefaults"
screen.IgnoreGuiInset = true
screen.Parent = StarterGui

for _, stem in ipairs(readBacks) do
	local module = cases:FindFirstChild(stem)
	if not module then
		print(`{stem}: case not found`)
		continue
	end
	local case = require(module :: ModuleScript) :: any
	local surface = Instance.new("Frame")
	surface.Size = UDim2.fromOffset(case.surface.width, case.surface.height)
	surface.BackgroundTransparency = 1
	surface.Parent = screen
	build(case.tree, surface)
	task.wait(0.2)

	for _, descendant in ipairs(surface:GetDescendants()) do
		if descendant:IsA("UIGridLayout") then
			print(
				`{stem}: AbsoluteContentSize = {descendant.AbsoluteContentSize}, `
					.. `AbsoluteCellSize = {descendant.AbsoluteCellSize}, `
					.. `AbsoluteCellCount = {descendant.AbsoluteCellCount}`
			)
		elseif descendant:IsA("UIListLayout") then
			print(`{stem}: AbsoluteContentSize = {descendant.AbsoluteContentSize}`)
		end
	end
	surface:Destroy()
end

screen:Destroy()
print("-- end of layout defaults")
