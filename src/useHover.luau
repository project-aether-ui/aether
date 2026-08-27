--!strict
--[[
	useHover: hover state for surfaces that are NOT controls.

	WHY (ms-43 M29)
	`Pressable` already answers hover correctly, but only for things that claim a
	click. A great deal of UI reacts to hover without being a button — cards,
	rows, carousels, scrollbar tracks, anything that lifts or brightens — and
	every one of those sites in this repo had hand-rolled the same two lines:

	    MouseEnter = function() isHovered(true) end,
	    MouseLeave = function() isHovered(false) end,

	which is wrong in four ways the author cannot see until someone plays the UI:

	  1. MouseEnter/MouseLeave fire on POINTER movement only. Content that scrolls
	     or animates under a stationary cursor never updates — a card slides out
	     from under the mouse and stays lit until you twitch it.
	  2. MouseLeave also fires when the pointer merely crosses onto a CHILD, so a
	     card with a label in it flickers.
	  3. They ignore anything drawn OVER the element. A topbar above a menu still
	     let the cards under it light up (M28).
	  4. They ignore CLIPPING. A card scrolled out of a ScrollingFrame still lit
	     up when you hovered the empty space where it would have been (M28).

	Every one of those was a real bug found by playtest, three of them twice, in
	different files, because the two-line idiom is easy to reach for and looks
	obviously correct. So the idiom gets a name, and the name does the right
	thing.

	NOT A Pressable. Binding one of these does NOT register the surface with the
	router and does NOT set Active: a display card must not sink input away from
	the world, and must not occlude the controls beneath it (M17). It only asks,
	each frame, whether the pointer reaches it — which is the question
	PointerRouter.IsPointerOver answers, honouring cover and clipping.
]]

local isRoblox = typeof(game) == "Instance"

local Deps = require("./Deps")
local PointerRouter = require("./PointerRouter")
local InputScope = require("./InputScope")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local Enum =
	Deps.Vocabulary.Enum

local source = Deps.source
local scopedCleanup = Deps.cleanup

local RunService = if isRoblox then (game :: any):GetService("RunService") else nil

export type HoverOptions = {
	--- Fired on transitions only, never repeated while the state holds.
	OnHoverChanged: ((hovered: boolean) -> ())?,
	--- Poll each frame so hover follows GEOMETRY rather than pointer movement.
	--- Default true, which is the whole point of this module; false restores
	--- movement-driven semantics for the rare surface that wants them (a drag
	--- handle whose highlight should not flicker as content moves beneath it).
	---
	--- Note that false opts out of POLLING, not of correctness: the movement path
	--- still resolves through IsPointerOver, so cover and clipping are honoured
	--- either way.
	LiveHover: boolean?,
	--- Reactive. A disabled surface reports not-hovered and fires no transitions.
	Disabled: (() -> boolean)?,
}

export type HoverHandle = {
	IsHovered: () -> boolean,
	--- Vide.action target. Returns an unbind function; disposal is also handled
	--- by Destroy and by the enclosing reactive scope.
	Bind: (rbx: GuiObject?) -> () -> (),
	Destroy: () -> (),
}

local function useHover(options: HoverOptions?): HoverHandle
	local opts = options or {}
	local isHovered = source(false)
	local connections: { any } = {}
	local destroyed = false

	local function setHovered(next: boolean)
		if isHovered() == next then return end
		isHovered(next)
		if opts.OnHoverChanged then
			opts.OnHoverChanged(next)
		end
	end

	local function evaluate(rbx: GuiObject)
		if destroyed then return end
		if opts.Disabled and opts.Disabled() then
			setHovered(false)
			return
		end
		local x, y = InputScope.GetPointerPosition()
		-- A negative reading means "no pointer" (touch released, or headless).
		if x < 0 then
			setHovered(false)
			return
		end
		setHovered(PointerRouter.IsPointerOver(rbx, x, y))
	end

	--- Releases both real RBXScriptConnections and the frame-bus unsubscribe,
	--- which is wrapped to present the same `Disconnect` shape.
	local function disconnectAll()
		for _, conn in ipairs(connections) do
			pcall(function() conn:Disconnect() end)
		end
		table.clear(connections)
	end

	local handle: HoverHandle
	handle = {
		IsHovered = isHovered,

		Bind = function(rbx: GuiObject?): () -> ()
			if not rbx then return function() end end
			-- Deliberately no `Active = true` and no router registration. See the
			-- header: a display surface neither sinks input nor occludes controls.

			if RunService then
				if opts.LiveHover ~= false then
					-- ms-43 M32: the router's ONE frame loop, not a Heartbeat per
					-- element. Fifty cards used to mean fifty connections; they now
					-- share one, and because observers run after the router's own
					-- hover pass they hit its resolve memo — fifty rect tests and a
					-- single resolve for the frame.
					table.insert(connections, {
						Disconnect = PointerRouter.OnFrame(function()
							if not rbx.Parent then return end
							evaluate(rbx)
						end),
					})
				else
					local UserInputService = (game :: any):GetService("UserInputService")
					table.insert(connections, UserInputService.InputChanged:Connect(function(input: any)
						if input.UserInputType == Enum.UserInputType.MouseMovement
							or input.UserInputType == Enum.UserInputType.Touch then
							if not rbx.Parent then return end
							evaluate(rbx)
						end
					end))
				end
			end

			return function()
				disconnectAll()
				setHovered(false)
			end
		end,

		Destroy = function()
			if destroyed then return end
			destroyed = true
			disconnectAll()
			setHovered(false)
		end,
	}

	scopedCleanup(handle.Destroy)
	return handle
end

return useHover
