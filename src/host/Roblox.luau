--!strict
--[[
	Aether · host/Roblox — Layer 2.5 resolver for the Roblox engine.

	The counterpart to Headless.luau. Where that one SUPPLIES the seven modules
	vide cannot load off-engine, this one simply hands back vide's own: in Roblox
	`game` is an Instance, so `create`, `cleanup`, `mount` and the rest resolve
	natively and there is nothing to substitute.

	So the interesting half of this file is not the vide surface — it is
	`Resolve`, the geometry contract.

	WHY `Resolve` MATTERS. Layer 2 (hit-testing, scope arbitration, floating
	placement) needs one question answered — "where is this thing, how deep is
	it, is it visible" — and today every call site asks the ENGINE directly, by
	reading `AbsolutePosition`/`AbsoluteSize` off a GuiObject. That is the single
	coupling that stops those algorithms from running anywhere else. `Resolve`
	turns a concrete host target into an abstract `GeometrySource`, so a Layer 2
	algorithm can be written against the contract instead of against Roblox.

	HitTest.luau already half-discovered this: its `cornerRadiusOf` guards the
	`FindFirstChildOfClass` call because "not every caller hands us a real
	Instance — the InputScope and PointerRouter suites pass minimal stand-ins with
	only the geometry fields". Those stand-ins ARE a GeometrySource, invented
	locally and unnamed. This gives them a name.

	NOT YET DONE, and the honest state of it: HitTest, PointerRouter, InputScope
	and useFloating still read the engine inline. Migrating them onto `Resolve`
	is the follow-on — this file establishes the contract and the Roblox
	implementation of it, it does not yet reroute those consumers.
]]

local Roblox = {}

export type Bounds = { X: number, Y: number, Width: number, Height: number }

export type GeometrySource = {
	GetBounds: () -> Bounds,
	GetZIndex: () -> number,
	IsVisible: () -> boolean,
}

--- Is this environment actually Roblox?
function Roblox.available(): boolean
	return typeof(game) == "Instance"
end

--- Build the host. Errors off-engine rather than degrading, because a silent
--- degrade is how a Roblox-only path ends up "passing" in a Lune suite that was
--- never exercising it.
function Roblox.new(vide: any): any
	if not Roblox.available() then
		error("Aether.Host.Roblox requires the Roblox engine; use Aether.Host.Headless off-engine.", 2)
	end
	if type(vide) ~= "table" then
		error("Aether.Host.Roblox.new(vide) requires the vide module.", 2)
	end

	local host: any = {}

	host.Name = "Roblox"

	-- ---- Layers 2 and 2.5 both come straight from vide here ----
	host.source = vide.source
	host.derive = vide.derive
	host.effect = vide.effect
	host.root = vide.root
	host.batch = vide.batch
	host.untrack = vide.untrack
	host.read = vide.read
	host.switch = vide.switch
	host.show = vide.show
	host.indexes = vide.indexes
	host.values = vide.values
	host.context = vide.context
	host.action = vide.action
	host.create = vide.create
	host.cleanup = vide.cleanup
	host.spring = vide.spring
	host.mount = vide.mount
	host.changed = vide.changed

	-- ---- Host services ----

	--- TEXT METRICS from the engine itself (ms-52 M1).
	---
	--- `GetTextSize` is SYNCHRONOUS and exact, which is the whole reason the
	--- contract is shaped this way: layout runs inside a frame and cannot await.
	--- The bundled advance table in Text.luau is never consulted here.
	local TextService = game:GetService("TextService")
	local TextModule = require("./Text")

	TextModule.SetProvider(function(text: string, size: number, _font: string?): (number, number)
		--- A very large frame, because we are asking for the string's NATURAL size
		--- rather than how it wraps into a box. A caller that wants wrapping asks
		--- about a box it already has.
		local bounds = TextService:GetTextSize(text, size, Enum.Font.SourceSans, Vector2.new(1e6, 1e6))
		return bounds.X, bounds.Y
	end, "engine")

	host.Text = TextModule

	host.Instance = Instance

	--- A no-op: the engine already defines every one of these as a global, and
	--- overwriting them would be strictly worse than leaving them alone. Present
	--- so a host program can call it unconditionally (ms-52 M5).
	host.InstallVocabulary = function() end

	host.typeof = typeof

	--- THE CLOCK (ms-51 M16).
	---
	--- Motion needs "advance one frame", and that is the last purely temporal
	--- coupling in the stack: spektr/flux_motion held a single guarded
	--- `RunService.Heartbeat` connection and a `_StepForTest` beside it, so time
	--- was already isolated — it just was not owned by anything that could swap it.
	---
	--- ONE connection, made lazily. Subscribing costs nothing until something
	--- actually animates, and N hooks still share one Heartbeat rather than taking
	--- N connections, which is the property flux_motion existed to guarantee.
	local RunService = game:GetService("RunService")
	local frameListeners: { (dt: number) -> () } = {}
	local heartbeat: RBXScriptConnection? = nil

	host.Clock = {
		Name = "Heartbeat",

		OnFrame = function(fn: (dt: number) -> ()): () -> ()
			table.insert(frameListeners, fn)
			if not heartbeat then
				heartbeat = RunService.Heartbeat:Connect(function(dt: number)
					-- Snapshot: a listener may dispose itself, or a sibling,
					-- mid-frame.
					local batch = table.clone(frameListeners)
					for _, listener in ipairs(batch) do
						listener(dt)
					end
				end)
			end
			return function()
				local i = table.find(frameListeners, fn)
				if i then
					table.remove(frameListeners, i)
				end
			end
		end,

		Now = function(): number
			return os.clock()
		end,

		--- In-engine the Heartbeat drives frames; stepping by hand would run them
		--- TWICE. Present so callers need not branch on environment.
		Step = function(_dt: number) end,
	}

	--- THE VALUE VOCABULARY (ms-51 M16).
	---
	--- es9: these should have a single interface regardless of host. On Roblox
	--- that interface is satisfied by the engine's own globals — same objects,
	--- same identity, zero indirection cost. What the indirection buys is that
	--- nothing above Layer 2.5 has to NAME them.
	host.Vocabulary = {
		UDim = UDim,
		UDim2 = UDim2,
		Vector2 = Vector2,
		Color3 = Color3,
		Rect = Rect,
		NumberSequence = NumberSequence,
		NumberSequenceKeypoint = NumberSequenceKeypoint,
		ColorSequence = ColorSequence,
		ColorSequenceKeypoint = ColorSequenceKeypoint,
		Font = Font,
		Enum = Enum,
	}

	host.classOf = function(node: any): string?
		if typeof(node) == "Instance" then
			return node.ClassName
		end
		if type(node) == "table" then
			return (node :: any)._ClassName
		end
		return nil
	end

	--- Present for contract parity with Headless. In-engine the layout system
	--- owns these properties, so this can only move the element — which is what
	--- a caller asking to "set bounds" on a real Frame actually wants.
	host.SetBounds = function(target: GuiObject, x: number, y: number, width: number, height: number)
		target.Position = UDim2.fromOffset(x, y)
		target.Size = UDim2.fromOffset(width, height)
	end

	--- THE SCENE CONTRACT (ms-51 M16 part 3) — the questions Layer 2 asks about a
	--- node, answered without Layer 2 naming the engine.
	---
	--- STATELESS FUNCTIONS OVER A RAW TARGET, not a wrapper object per node. That
	--- is deliberate and it is a performance decision, not a style one: hit-testing
	--- runs over every candidate on every pointer move, and `Resolve`-style
	--- wrappers would allocate a table per node per query. A previous measurement
	--- in this repo took a hot tree walk from 121ns to 65ns per visit purely by
	--- removing a table per node — same shape, same cost. `Bounds` returns four
	--- numbers rather than a rectangle for the same reason.
	---
	--- TOLERANT OF STAND-INS. HitTest already notes that "not every caller hands us
	--- a real Instance — the InputScope and PointerRouter suites pass minimal
	--- stand-ins with only the geometry fields". Those stand-ins were an unnamed
	--- GeometrySource all along; every accessor here degrades to a sensible answer
	--- rather than erroring on one.
	local function isInstance(target: any): boolean
		return typeof(target) == "Instance"
	end

	host.Scene = {
		Name = "Roblox",

		--- THE SCROLLABLE EXTENT of a node's content (ms-53 D8).
		---
		--- `AbsoluteCanvasSize` is a Roblox property, so spektr/scrollbar read it
		--- directly and got `{0, 0}` in every headless host -- the mock sets it once
		--- at construction and nothing updates it, deliberately, because the HOST is
		--- supposed to report it rather than have application code write it and be
		--- believed. Nothing ever connected the reporting.
		---
		--- The visible consequence: `canvas.Y > viewport.Y` decides whether a
		--- scrollbar is shown at all, so the shop's bar -- track, thumb and steppers
		--- -- rendered in Roblox and was invisible in the native window. es9 found
		--- it and asked the right question: is this not owned by the Scrollbar
		--- component? It is. It was reading the engine instead of the host.
		CanvasExtent = function(target: any): (number, number)
			local canvas = (target :: any).AbsoluteCanvasSize
			if not canvas then
				return 0, 0
			end
			return canvas.X, canvas.Y
		end,

		Bounds = function(target: any): (number, number, number, number)
			local pos = target.AbsolutePosition
			local size = target.AbsoluteSize
			return pos.X, pos.Y, size.X, size.Y
		end,

		--- Raw property read, for a LAYOUT solver rather than a hit test. In-engine
		--- the layout system has already run, so this is mostly of use to a host
		--- that must solve it itself — but the contract is the same either way.
		Raw = function(target: any, key: string): any
			local ok, value = pcall(function()
				return (target :: any)[key]
			end)
			return if ok then value else nil
		end,

		Children = function(target: any): { any }
			if isInstance(target) then
				return target:GetChildren()
			end
			return {}
		end,

		ClassOf = function(target: any): string?
			if isInstance(target) then
				return target.ClassName
			end
			return (target :: any)._ClassName
		end,

		Name = function(target: any): string?
			return (target :: any).Name
		end,

		ZIndex = function(target: any): number
			return target.ZIndex or 1
		end,

		IsVisible = function(target: any): boolean
			return target.Visible ~= false
		end,

		Parent = function(target: any): any
			return target.Parent
		end,

		--- Declaration order within the parent. Under ZIndexBehavior.Sibling this
		--- is the tie-break when two siblings share a ZIndex.
		ChildIndex = function(target: any): number
			local parent = target.Parent
			if not parent or not isInstance(parent) then
				return 0
			end
			for i, child in ipairs(parent:GetChildren()) do
				if child == target then
					return i
				end
			end
			return 0
		end,

		--- Does this container clip what it contains?
		---
		--- ScrollingFrame and CanvasGroup clip regardless of the ClipsDescendants
		--- flag — a ScrollingFrame with it off still bounds its canvas, and a
		--- CanvasGroup renders its subtree to a texture the size of itself.
		Clips = function(target: any): boolean
			if isInstance(target) then
				if target:IsA("ScrollingFrame") or target:IsA("CanvasGroup") then
					return true
				end
			end
			return target.ClipsDescendants == true
		end,

		--- Is this the root of a render layer (a LayerCollector)?
		IsLayerRoot = function(target: any): boolean
			return isInstance(target) and target:IsA("LayerCollector")
		end,

		--- Is this a node Layer 2 should walk at all? Everything above a
		--- GuiObject chain is somebody else's tree.
		IsSurface = function(target: any): boolean
			if isInstance(target) then
				return target:IsA("GuiObject")
			end
			--- A stand-in with a rectangle IS a surface, which is the whole point
			--- of the contract.
			return type(target) == "table" and target.AbsolutePosition ~= nil
		end,

		DisplayOrder = function(target: any): number
			return target.DisplayOrder or 0
		end,

		IsEnabled = function(target: any): boolean
			return target.Enabled ~= false
		end,

		Attribute = function(target: any, name: string): any
			local get = (target :: any).GetAttribute
			if type(get) ~= "function" then
				return nil
			end
			local ok, value = pcall(get, target, name)
			return if ok then value else nil
		end,

		--- The RENDERED corner, as scale and offset. nil when the element draws
		--- square corners. Kept here rather than in Layer 2 because finding it
		--- means knowing about UICorner, which is an engine class; the clamping
		--- math on top of it stays in HitTest, which is where the rule lives.
		RenderedCorner = function(target: any): (number?, number?)
			local find = (target :: any).FindFirstChildOfClass
			if type(find) ~= "function" then
				return nil, nil
			end
			local ok, corner = pcall(find, target, "UICorner")
			if not ok or not corner then
				return nil, nil
			end
			local r = corner.CornerRadius
			return r.Scale, r.Offset
		end,
	}

	--- The Layer 2.5 contract: an abstract rectangle for a concrete GuiObject.
	---
	--- Reads live on every call rather than caching: `AbsolutePosition` changes
	--- whenever anything in the ancestor chain moves, and a cached rectangle is
	--- exactly the stale-geometry class that ms-43 M20 was about.
	host.Resolve = function(target: any): GeometrySource
		return {
			GetBounds = function(): Bounds
				local pos = target.AbsolutePosition
				local size = target.AbsoluteSize
				return { X = pos.X, Y = pos.Y, Width = size.X, Height = size.Y }
			end,
			GetZIndex = function(): number
				return target.ZIndex or 1
			end,
			IsVisible = function(): boolean
				return target.Visible ~= false
			end,
		}
	end

	return host
end

return Roblox
