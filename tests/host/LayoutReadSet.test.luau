--!strict
--!tier math
--[=[
	What does the layout solver actually look at? (ms-52 M15.1)

	WHY THIS EXISTS BEFORE THE CACHE IT SERVES
	M15 caches solved layout and reuses it while its inputs are unchanged. A cache
	is exactly as correct as the set of things it watches, and a MISSING entry is
	silent: that node keeps last frame's rectangle, the frame stays internally
	consistent, and every pixel check still passes -- they compare the painter
	against the frame it was GIVEN, not against the frame it should have been
	given. `--audit` cannot see it either, because the node IS delivered and IS
	visible.

	It surfaces much later as the ms-43 M20 stale-geometry bug: the router
	arbitrating against last frame's rectangle, so what can be CLICKED and what can
	be SEEN disagree. That is a horrible thing to debug and a cheap thing to
	prevent.

	So this records what a real solve touches and requires `Layout.Inputs` to cover
	it. The gate MAINTAINS ITSELF -- a future solver that reads a new property
	fails here rather than quietly holing the cache's assumptions.

	THE TRAP IT IS BUILT AROUND
	Not every read goes through `Scene.Raw`. `ClassOf` reads a class name, `Clips`
	a `ClipsDescendants`, `Children` the child list AND its order, `ZIndex` a
	ZIndex. Grepping for `Raw` shows none of them, which makes them precisely the
	entries most likely to be left out of a hand-written list. The recorder wraps
	the whole Scene, not one function.
]=]
local T = require("@testkit")
local Aether = require("../../src/api")
local Layout = require("../../src/host/Layout")

--- A scene wrapper that records every access and forwards it unchanged.
---
--- Wrapping every function rather than naming the ones expected: a recorder that
--- only watched the accessors someone remembered would report exactly the set
--- someone remembered.
local function recording(scene: any)
	local props: { [string]: boolean } = {}
	local used: { [string]: boolean } = {}
	local proxy: any = {}
	for key, value in pairs(scene) do
		if type(value) == "function" then
			proxy[key] = function(...)
				used[key] = true
				if key == "Raw" then
					local _, prop = ...
					if type(prop) == "string" then
						props[prop] = true
					end
				end
				return value(...)
			end
		else
			proxy[key] = value
		end
	end
	return proxy, props, used
end

local function declared(list: { string }): { [string]: boolean }
	local set = {}
	for _, name in ipairs(list) do
		set[name] = true
	end
	return set
end

--- A tree with enough shape to exercise the solver's branches: padding, a list
--- layout, a scroller, automatic sizing, text, a scale and clipping. A flat tree
--- would report a much smaller read set and pass while proving very little.
local function buildScene(): (any, any)
	local host = Aether.Host.Headless.new()
	local V = host.Vocabulary
	local create = host.create

	local rows = {}
	for i = 1, 3 do
		rows[i] = create("TextLabel")({
			Name = `Row{i}`,
			Text = `row {i}`,
			TextSize = 14,
			AutomaticSize = V.Enum.AutomaticSize.XY,
			AnchorPoint = V.Vector2.new(0, 0),
			LayoutOrder = i,
			ZIndex = i,
		})
	end

	local root = create("Frame")({
		Name = "Root",
		Size = V.UDim2.fromScale(1, 1),
		create("Frame")({
			Name = "Padded",
			Size = V.UDim2.fromScale(1, 1),
			ClipsDescendants = true,
			create("UIPadding")({
				PaddingLeft = V.UDim.new(0, 8),
				PaddingTop = V.UDim.new(0, 8),
				PaddingRight = V.UDim.new(0, 8),
				PaddingBottom = V.UDim.new(0, 8),
			}),
			create("UIListLayout")({
				Padding = V.UDim.new(0, 4),
				FillDirection = V.Enum.FillDirection.Vertical,
			}),
			create("ScrollingFrame")({
				Name = "Scroller",
				Size = V.UDim2.new(1, 0, 0, 200),
				CanvasPosition = V.Vector2.new(0, 20),
				LayoutOrder = 1,
				rows[1], rows[2], rows[3],
			}),
			create("Frame")({
				Name = "Scaled",
				Size = V.UDim2.fromOffset(100, 100),
				Visible = true,
				LayoutOrder = 2,
				create("UIScale")({ Scale = 1.5 }),
			}),
		}),
	})

	return host, root
end

local function testDeclaredInputsCoverASolve()
	local host, root = buildScene()
	local proxy, props, used = recording(host.Scene)
	Layout.Solve(proxy, root, { X = 0, Y = 0, Width = 800, Height = 600 }, host)

	local okProps = declared(Layout.Inputs.Properties)
	local okAccessors = declared(Layout.Inputs.Accessors)

	local missingProps = {}
	for name in pairs(props) do
		if not okProps[name] then
			table.insert(missingProps, name)
		end
	end
	local missingAccessors = {}
	for name in pairs(used) do
		if not okAccessors[name] then
			table.insert(missingAccessors, name)
		end
	end
	table.sort(missingProps)
	table.sort(missingAccessors)

	assert(#missingProps == 0,
		`the solver reads properties Layout.Inputs does not declare: {table.concat(missingProps, ", ")}`
			.. " -- a cache keyed on the declared set would serve stale rectangles for them")
	assert(#missingAccessors == 0,
		`the solver uses Scene accessors Layout.Inputs does not declare: {table.concat(missingAccessors, ", ")}`)

	--- NOT VACUOUS. If the recorder saw nothing, the two assertions above are
	--- trivially satisfied and this suite would pass against any declaration at
	--- all -- including an empty one.
	local propCount = 0
	for _ in pairs(props) do
		propCount += 1
	end
	assert(propCount >= 8,
		`the recorder observed only {propCount} properties; a solve of this tree reads far more,`
			.. " so the recording is not working and the check above proves nothing")
	assert(used.Raw and used.Children,
		"a solve must at least read properties and walk children; the recorder saw neither")
end

local function testTheGateCatchesAnUndeclaredRead()
	--- POISON. The check above says "nothing undeclared was read". That is a
	--- NEGATIVE statement, and a recorder that observed nothing satisfies it --
	--- the exact failure mode that let a black screen score 100% pixel parity
	--- earlier in this milestone.
	---
	--- So: read a property that is deliberately not in `Layout.Inputs`, through
	--- the same recorder, and require the comparison to notice.
	local host, root = buildScene()
	local proxy, props = recording(host.Scene)
	proxy.Raw(root, "BorderSizePixel")
	Layout.Solve(proxy, root, { X = 0, Y = 0, Width = 800, Height = 600 }, host)

	local okProps = declared(Layout.Inputs.Properties)
	assert(not okProps.BorderSizePixel,
		"BorderSizePixel was picked as a poison BECAUSE it is undeclared; declaring it breaks this test")
	local caught = false
	for name in pairs(props) do
		if not okProps[name] then
			caught = true
		end
	end
	assert(caught,
		"an undeclared read went unnoticed, so this gate cannot detect the thing it exists for")
end

local function testEveryDeclaredInputIsReal()
	--- THE OTHER DIRECTION. An over-broad declaration is not a correctness bug,
	--- but it is a slow one: M15.2 invalidates on every declared input, so a name
	--- nothing reads means a cache that drops entries for no reason.
	---
	--- Asserted loosely -- a property this fixture does not happen to exercise is
	--- not proof it is unused -- so this only catches names that are obviously
	--- not properties at all.
	for _, name in ipairs(Layout.Inputs.Properties) do
		assert(type(name) == "string" and #name > 0, "an input name must be a non-empty string")
		assert(string.match(name, "^%u") ~= nil,
			`layout input "{name}" is not a Roblox property name; the solver reads capitalised keys`)
	end
	for _, name in ipairs(Layout.Inputs.Accessors) do
		assert(type(name) == "string" and #name > 0, "an accessor name must be a non-empty string")
	end
end

T.test("Layout.Inputs covers every property and accessor a solve touches", testDeclaredInputsCoverASolve, "math")
T.test("the gate catches a read it does not declare", testTheGateCatchesAnUndeclaredRead, "math")
T.test("every declared input is a plausible name", testEveryDeclaredInputIsReal, "math")

return T.run("LayoutReadSet")
