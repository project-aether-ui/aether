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
local agreed, disagreed, vacuous = 0, 0, 0

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
	local ratioLines: { string } = {}
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

		--- `string.format`, not interpolation. This line's whole job is to emit
		--- literal braces, and an interpolated string reads `{` as the start of an
		--- expression — "Double braces are not permitted within interpolated
		--- strings". Escaping them would compile and would make the one line whose
		--- output has to be copy-pasteable the hardest one in the file to read.
		lines[#lines + 1] = string.format(
			'\t\t{ name = "%s", x = %s, y = %s, w = %s, h = %s },',
			expected.name,
			tostring(got.x),
			tostring(got.y),
			tostring(got.w),
			tostring(got.h)
		)
	end

	--- RATIOS, which this runner did not understand until a case that asserted
	--- nothing else was reported as agreeing.
	---
	--- Text measurement is a host service, so a case about it compares two nodes
	--- rather than naming a width. The observed value is printed even when it is
	--- within tolerance, because otherwise nobody ever learns what the engine
	--- actually says and a loose tolerance stays loose forever.
	for _, r in ipairs(case.ratios or {}) do
		local of, to = byName[r.of], byName[r.to]
		if not of or not to then
			lines[#lines + 1] = string.format("        -- ratio needs %s and %s", r.of, r.to)
			mismatch = true
			continue
		end
		local function field(g: GuiObject, f: string): number
			local pos = g.AbsolutePosition - origin
			local size = g.AbsoluteSize
			if f == "w" then return size.X elseif f == "h" then return size.Y
			elseif f == "x" then return pos.X else return pos.Y end
		end
		local denominator = field(to, r.field)
		if denominator == 0 then
			lines[#lines + 1] = string.format("        -- ratio %s/%s: denominator is zero", r.of, r.to)
			mismatch = true
			continue
		end
		local actual = field(of, r.field) / denominator
		local verdict, bound
		if r.min then
			verdict = if actual >= r.min then "within" else "OUTSIDE"
			bound = string.format("at least %.3f", r.min)
		else
			local slack = r.tolerance or 0.02
			verdict = if math.abs(actual - r.expect) <= slack then "within" else "OUTSIDE"
			bound = string.format("expected %.3f +/- %.3f", r.expect, slack)
		end
		ratioLines[#ratioLines + 1] = string.format(
			"    %s.%s / %s.%s = %.4f  (%s, %s)",
			r.of, r.field, r.to, r.field, actual, bound, verdict
		)
		if verdict == "OUTSIDE" then
			mismatch = true
		end
	end

	--- A CASE THAT ASSERTS NOTHING CANNOT AGREE. Reporting one as agreeing is
	--- worse than reporting a failure, because it manufactures provenance: two
	--- text cases were promoted to `roblox` on the strength of exactly this
	--- before the runner understood ratios.
	if #case.expect == 0 and #(case.ratios or {}) == 0 then
		vacuous += 1
		results[#results + 1] = `VACUOUS    {case.name}  [{case.provenance}]  -- asserts nothing`
		surface:Destroy()
		continue
	end

	if mismatch then
		disagreed += 1
		results[#results + 1] = `\nDISAGREES  {case.name}  [{case.provenance}]`
		--- STAMP THE BUILD INTO THE PASTE. An expectation is only true of the
		--- Roblox that produced it, and Roblox ships continuously. Re-running this
		--- later against a newer build and getting a different number is not a bug
		--- in the suite — it is the suite doing the most valuable thing it can,
		--- which is noticing that the standard moved.
		results[#results + 1] = `\tengine says (Roblox {version()}):`
		results[#results + 1] = string.format('\tverifiedAgainst = "%s",', version())
		results[#results + 1] = "\texpect = {"
		for _, line in ipairs(lines) do
			results[#results + 1] = line
		end
		results[#results + 1] = "\t},"
	else
		agreed += 1
		results[#results + 1] = `AGREES     {case.name}  [{case.provenance}]`
	end

	--- Printed whether or not the case agreed. An agreeing ratio says "within
	--- tolerance", and the number is how the tolerance gets tightened later.
	for _, line in ipairs(ratioLines) do
		results[#results + 1] = line
	end

	surface:Destroy()
end

print("")
for _, line in ipairs(results) do
	print(line)
end
print("")
print(
	`ENGINE CONFORMANCE: {agreed} agree, {disagreed} disagree, {vacuous} vacuous`
		.. `  --  Roblox {version()}`
)
print("Paste a DISAGREES block into its case and set provenance = \"roblox\".")
