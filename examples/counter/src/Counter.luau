--!strict
--[[
	Counter — one component, three hosts.

	THIS FILE IS THE POINT OF THE EXAMPLE. Nothing in it knows whether it is
	running inside Roblox, inside the `aether` CLI, or inside Dew. It asks `Deps`
	for `create` and `source`, which are resolved for whatever environment loaded
	it, and it names Roblox's own property vocabulary — `UDim2`, `Color3`,
	`BackgroundColor3` — because off-engine those exist too, supplied by the host
	rather than by an engine.

	The two entry points beside it are the only files that differ per host, and
	both are under twenty lines. If this component ever needs a third branch to
	run somewhere, the framework has lost the property this example exists to
	demonstrate.

	THE REQUIRE DANCE AT THE TOP is the one unavoidable seam, and it is the same
	one Aether's own modules carry: Roblox resolves modules through the Instance
	tree and everything else resolves them by string. There is no spelling that
	satisfies both, so the branch is explicit rather than hidden behind a helper
	that would only move it.
]]

local isScriptInstance = typeof(script) == "Instance"

local Deps = require("@aether/Deps")

local create = Deps.create
local source = Deps.source

export type Props = {
	--- Starting value, so a caller can mount several at different counts and see
	--- that each carries its own state rather than sharing one.
	start: number?,
}

--- Returns the tree AND the transition, as two values.
---
--- The increment is NOT a key in the props table: `create` treats every key it
--- does not recognise as a property to assign, so `_increment = fn` would try to
--- set a property of that name on a Frame — which Roblox rejects at runtime and
--- `verify_property_names` rejects at commit time. Two return values keep the
--- props table honestly a props table.
return function(props: Props?)
	--- INSIDE THE FUNCTION, NOT AT MODULE SCOPE, and this is a portability rule
	--- rather than a style preference.
	---
	--- A module body runs when it is REQUIRED. On Roblox that is harmless because
	--- `Color3` is always a global; off-engine the host installs the vocabulary
	--- during startup, and a require that happens first therefore sees nil. The
	--- first draft of this file read `Color3.new` at module scope and failed with
	--- "attempt to index nil with 'new'" before the entry point had run a line.
	---
	--- The rule generalises: a shared component may NAME the value vocabulary
	--- freely, but must not EVALUATE it until it is called.
	local INK = Color3.new(0.93, 0.95, 0.99)
	local PANEL = Color3.new(0.07, 0.09, 0.15)
	local ACCENT = Color3.new(0.22, 0.74, 0.97)

	local count = source((props and props.start) or 0)

	--- REACTIVE, not computed once. `Text` is given a FUNCTION, so vide re-reads
	--- it when `count` changes — on Roblox by writing the property, off-engine by
	--- the same graph driving the next `Live.Frame`. The component does not know
	--- which, and that is the whole claim.
	local tree = create "Frame" {
		Name = "Counter",
		Size = UDim2.fromOffset(240, 96),
		Position = UDim2.fromOffset(0, 0),
		BackgroundColor3 = PANEL,

		create "TextLabel" {
			Name = "Title",
			Size = UDim2.fromOffset(200, 22),
			Position = UDim2.fromOffset(20, 14),
			BackgroundTransparency = 1,
			Text = "aether counter",
			TextColor3 = ACCENT,
			TextSize = 15,
		},

		create "TextLabel" {
			Name = "Value",
			Size = UDim2.fromOffset(200, 34),
			Position = UDim2.fromOffset(20, 44),
			BackgroundColor3 = ACCENT,
			Text = function()
				return `count: {count()}`
			end,
			TextColor3 = INK,
			TextSize = 20,
		},
	}

	--- Handed back so an entry point can drive it: the Roblox one from a
	--- Heartbeat or a button, the desktop one from its own frame loop. The
	--- component owns the STATE and exposes the transition; it does not own what
	--- CAUSES it, because that is the part that genuinely differs per host.
	local function increment()
		count(count() + 1)
	end

	return tree, increment
end
