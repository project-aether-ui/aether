--!strict
--[[
	The conformance runner, in the engine.

	Builds each case with `Instance.new`, lets Roblox lay it out, and reads
	`AbsolutePosition` and `AbsoluteSize` back. Whatever it prints IS the standard
	— this is the only runner whose output is evidence rather than opinion.

	It reads the SAME case files the off-engine runner does, through the same
	decoder. That is the whole reason cases are data: two implementations, one
	description, and no opportunity for a case to mean different things in
	different places.

	## Using it

	    rojo serve conformance/roblox/default.project.json

	Connect from Studio, run the place, and read Output. Cases that disagree print
	a paste-ready `expect` block; copy it into the case file and set
	`provenance = "roblox"`.

	**Only ever paste from THIS runner.** A `roblox` expectation recorded from
	anything else is a lie in the one place the suite cannot afford one.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local decode = require(script.Parent.decode)
local casesFolder = script.Parent.cases

local player = Players.LocalPlayer
local screen = Instance.new("ScreenGui")
screen.Name = "ConformanceHarness"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.Parent = player:WaitForChild("PlayerGui")

--- Build one node and its descendants.
---
--- Properties are applied BEFORE children are parented, and `Parent` is set
--- last. Roblox applies layout as things arrive, so parenting a child before its
--- parent is sized makes the child resolve against a size that is about to
--- change — measurable as a one-frame flicker, and as wrong numbers here.
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

--- Wait for the engine to settle.
---
--- Layout is NOT synchronous. `AbsolutePosition` and `AbsoluteSize` read zero
--- immediately after parenting, and a single frame is not always enough once
--- `AutomaticSize` is involved — a parent measuring children that are themselves
--- being measured can take several passes. Three frames is empirical and cheap;
--- if a case ever reports zeroes for something plainly visible, raise it before
--- suspecting the engine.
local function settle()
	for _ = 1, 3 do
		RunService.Heartbeat:Wait()
	end
end

local function round(n: number): number
	--- Two decimal places. Roblox returns floats and a case comparing them
	--- exactly would fail on noise that no implementation could match.
	return math.floor(n * 100 + 0.5) / 100
end

local results: { string } = {}
local agreed, disagreed = 0, 0

for _, module in ipairs(casesFolder:GetChildren()) do
	if not module:IsA("ModuleScript") then
		continue
	end

	local case = require(module) :: any

	--- A CONTAINER OF EXACTLY THE CASE'S SURFACE SIZE, so scale resolves against
	--- the same rectangle the off-engine runner solves against. A ScreenGui fills
	--- the viewport, which differs per machine and would make every scale case
	--- unreproducible.
	local surface = Instance.new("Frame")
	surface.Name = "Surface"
	surface.Size = UDim2.fromOffset(case.surface.width, case.surface.height)
	surface.Position = UDim2.fromOffset(0, 0)
	surface.BackgroundTransparency = 1
	surface.Parent = screen

	build(case.tree, surface)
	settle()

	local origin = surface.AbsolutePosition
	local byName: { [string]: GuiObject } = {}
	for _, descendant in ipairs(surface:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			byName[descendant.Name] = descendant
		end
	end

	local lines: { string } = {}
	local mismatch = false

	for _, expected in ipairs(case.expect) do
		local actual = byName[expected.name]
		if not actual then
			lines[#lines + 1] = `        -- '{expected.name}' not found`
			mismatch = true
			continue
		end

		local pos = actual.AbsolutePosition - origin
		local size = actual.AbsoluteSize
		local got = { x = round(pos.X), y = round(pos.Y), w = round(size.X), h = round(size.Y) }

		for _, field in ipairs({ "x", "y", "w", "h" }) do
			local want = expected[field]
			if want ~= nil and math.abs(want - got[field]) > 0.01 then
				mismatch = true
			end
		end

		lines[#lines + 1] =
			`\t\t{{ name = "{expected.name}", x = {got.x}, y = {got.y}, w = {got.w}, h = {got.h} }},`
	end

	if mismatch then
		disagreed += 1
		results[#results + 1] = `\nDISAGREES  {case.name}  [{case.provenance}]`
		results[#results + 1] = "\tengine says:\n\texpect = {"
		for _, line in ipairs(lines) do
			results[#results + 1] = line
		end
		results[#results + 1] = "\t},"
	else
		agreed += 1
		results[#results + 1] = `AGREES     {case.name}  [{case.provenance}]`
	end

	surface:Destroy()
end

print("")
for _, line in ipairs(results) do
	print(line)
end
print("")
print(`ENGINE CONFORMANCE: {agreed} agree, {disagreed} disagree`)
print("Paste a DISAGREES block into its case and set provenance = \"roblox\".")
