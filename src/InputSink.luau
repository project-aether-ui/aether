--!strict
--[[
	InputSink: a rectangular region that swallows pointer input.

	SUPERSEDED BY InputScope (ms-43 M16), and kept because ShopMenu, SettingsMenu
	and TitleScreenMenuUI are built on it. New code should use InputScope, which
	understands ORDERING — this one does not, and cannot:

	  * it reports hover into a refcount, which answers "is the pointer over some
	    UI?" but never "which UI owns this click?";
	  * it has no depth, so two overlapping sinks cannot be resolved; and
	  * it cannot stop a click reaching a button on a menu underneath it.

	It remains correct for the single-modal case it was written for. Every
	instance also registers itself as a Block scope, so the arbiter accounts for
	it and a mixed InputSink/InputScope screen still resolves correctly.
]]
local isRoblox = typeof(game) == "Instance"

local Deps = require("./Deps")
local InputScope = require("./InputScope")
local PointerRouter = require("./PointerRouter")
--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local UDim2, Vector2, Color3 =
	Deps.Vocabulary.UDim2, Deps.Vocabulary.Vector2, Deps.Vocabulary.Color3

local vide = Deps.vide

local sinkSeq = 0

export type ValueOrGetter<T> = T | (() -> T)

export type InputSinkProps = {
	Size: ValueOrGetter<UDim2?>?,
	Position: ValueOrGetter<UDim2?>?,
	AnchorPoint: ValueOrGetter<Vector2?>?,
	ZIndex: ValueOrGetter<number?>?,
	Visible: ValueOrGetter<boolean?>?,

	Modal: boolean?,
	DimTransparency: number?,
	OnDismiss: (() -> ())?,

	children: any?,
}

local function resolve<T>(val: ValueOrGetter<T>?): T?
	if type(val) == "function" then
		return (val :: any)()
	end
	return val :: any
end

local function InputSink(props: InputSinkProps)
	if not vide then return nil end

	local isModal = props.Modal == true
	local dimTransparency = props.DimTransparency

	-- Register with the M16 arbiter so a screen that mixes InputSink and
	-- InputScope still resolves to one consistent ordering. The sink keeps
	-- rendering its own Frame and its own dismiss handling; this is purely so
	-- occlusion queries can see it.
	sinkSeq += 1
	local scope = InputScope.new({
		Id = `InputSink_{sinkSeq}`,
		Layer = "Windows",
		Policy = if isModal then "Modal" else "Block",
		Visible = function(): boolean
			local vis: any = props.Visible
			if type(vis) == "function" then
				local raw = vis()
				return if raw == nil then true else raw == true
			elseif vis ~= nil then
				return vis == true
			end
			return true
		end,
	})

	local isVisible = function(): boolean
		local vis: any = props.Visible
		if type(vis) == "function" then
			local rawVal = vis()
			return if rawVal == nil then true else (rawVal == true)
		elseif vis ~= nil then
			return vis == true
		end
		return true
	end

	local propTable: { [string]: any } = {
		Name = if isModal then "InputSink_Modal" else "InputSink",
		Size = function()
			if isModal then
				return UDim2.fromScale(1, 1)
			end
			return resolve(props.Size) or UDim2.fromScale(1, 1)
		end,
		Position = function()
			if isModal then
				return UDim2.fromScale(0, 0)
			end
			return resolve(props.Position) or UDim2.fromScale(0, 0)
		end,
		AnchorPoint = function() return resolve(props.AnchorPoint) or Vector2.zero end,
		ZIndex = function() return resolve(props.ZIndex) or 1 end,
		Visible = isVisible,
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = if dimTransparency then dimTransparency else 1,

		vide.action(function(node: Instance)
			--- NOT ENGINE-GATED ANY MORE (ms-53 D8). This read
			--- `if not isRoblox ... then return end`, so off-engine the scope was
			--- registered and then given NO SURFACES -- and a scope with no
			--- surfaces can never be hit, so arbitration silently did nothing in
			--- every headless host. The engine bound it and arbitrated for real.
			---
			--- That asymmetry hid the defect below for two milestones: every suite
			--- and both headless hosts took the branch where the sink does not
			--- exist, so es9's Studio session was the first thing ever to run it.
			if not node then
				return
			end
			local gui = node :: GuiObject

			--- BOUND TO THE SINK ITSELF, and the REGION it owns is worked out at
			--- query time by `InputScope.IsSurfaceInScope` (ms-53 D8).
			---
			--- Not to `gui.Parent`, which was the first fix and does not work:
			--- `vide.action` runs when the instance is CREATED, before it is
			--- parented, so the parent is nil exactly when this line reads it.
			scope.Bind(gui)

			-- ms-43 M31: the hover-refcount block that used to live here is GONE.
			--
			-- It maintained InputContextManager's "is the pointer over UI?" count
			-- via MouseEnter/MouseLeave, plus a checkEffectiveVisibility walk and a
			-- GetPropertyChangedSignal("Visible") subscription on every ancestor to
			-- correct the count when a menu was hidden without the pointer moving.
			-- Forty lines of bookkeeping, all of it answering a question that is
			-- now answered geometrically: InputContextManager.IsMouseOverUI defers
			-- to InputScope.IsMouseOverUI (M16), Aether registers that resolver
			-- itself (M29), and this sink is already in the scope registry two
			-- lines above. The refcount is the FALLBACK for when it is not.
			--
			-- It was also wrong in the ways MouseEnter/MouseLeave always are — it
			-- fired on crossing onto a child, and needed the ancestor-visibility
			-- machinery precisely because the events cannot see content that moves
			-- or hides under a stationary pointer.
			--
			-- Dismissal is a Pressable rather than gui.InputBegan for a sharper
			-- reason: this Frame is deliberately not Active (M17 — only controls
			-- sink), and input events on an inactive GuiObject are not a contract
			-- worth resting on. The router resolves the click geometrically, and
			-- Priority -1 puts the sink below every control inside the window it
			-- covers, so a button click never reads as a dismiss.
			local press = if props.OnDismiss
				then PointerRouter.Pressable({
					Scope = scope,
					Priority = -1,
					HitTestable = false,
					OnActivated = function()
						if isVisible() and props.OnDismiss then
							props.OnDismiss()
						end
					end,
				})
				else nil
			if press then
				press.Bind(gui)
			end

			return function()
				if press then
					press.Destroy()
				end
				scope.Destroy()
			end
		end),
	}

	table.insert(propTable, props.children)

	return vide.create("Frame")(propTable)
end

return InputSink
