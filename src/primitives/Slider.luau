--!strict
--[=[
	Slider — Headless Track & Thumb Primitive
	Part of Aether.Primitives (Layer 2).

	COMPOSES `core/createSlider` DIRECTLY, the same relationship
	`Checkbox.luau`/`RadioGroup.luau` already have with their own machines:
	`createSlider` decides what is true (the clamped/stepped `Value`, the
	drag-driven `Start`/`Stop` pipeline behind `GetThumbProps()`) and this
	file supplies the four things Layer 1 cannot have -- the router, vide's
	`source`/`action`/`create`, and a REAL instance pair (track, thumb) --
	the same split `Scrollbar.luau` already proved out for its own track and
	thumb.

	`Scrollbar.luau` IS THE STRUCTURAL PRECEDENT, not `Checkbox.luau` --
	a slider's track + thumb is a drag surface, not a self-contained toggle,
	so the thumb here binds through `PointerRouter.Pressable` directly
	(`thumbPressable.Bind`, `OnPressed`/`OnReleased` wired straight to
	`GetThumbProps()`'s own hooks) exactly the way `Scrollbar.luau`'s own
	`thumbPressable` does, rather than through `createPressable`'s
	spreadable `GetRootProps()` shape `Checkbox.luau` uses.

	TRACK LENGTH IS MEASURED FROM THE REAL TRACK INSTANCE, not declared as a
	number that could drift the moment layout changes it -- the same
	discipline `ScrollArea.luau`'s own "SOLVE, THEN WRITE THE ANSWER BACK
	ONTO THE TREE" comment names. Layer 1 (`createSlider`) has no engine
	types at all, so it cannot measure its own track; `Options.TrackLength`
	is a getter this file supplies, resolved from whichever host is
	running:

	  - ROBLOX: `AbsoluteSize`, refreshed on `GetPropertyChangedSignal`
	    (task.defer once, then the changed signal), the identical shape
	    `Scrollbar.luau`'s own track measurement already uses.
	  - OFF-ENGINE (Dew): `AbsoluteSize` changes with no change signal to
	    subscribe to -- `ScrollArea.luau`'s own `viewportFrame` binding
	    found this exact gap first ("the off-engine equivalent of
	    `AbsoluteSize` changing is the LAYOUT SOLVER writing new bounds --
	    which happens once a frame and has no change signal"). Polled every
	    frame off `PointerRouter.OnFrame`, reading `Deps.Host.Scene.Bounds`
	    -- the same solved rectangle hit-testing itself reads, so a track
	    and its own hit area cannot drift apart the way measuring some
	    other way would risk.

	NO CLAMPING OR STEPPING HERE. `createSlider` already owns the range;
	this file only ever reads `Value()` back (already clamped and stepped)
	to place the thumb, and only ever calls `GetThumbProps()`'s own
	`OnPressed`/`OnReleased` -- it does not recompute a value from a raw
	drag delta itself. See `createSlider.luau`'s own doc comment and this
	milestone's own "Traps" section for why re-deriving that here would be
	a regression, not a convenience.
]=]

local Deps = require("../Deps")
local isRoblox = Deps.Host.Environment == "Roblox"
local RouterContext = require("../RouterContext")
local ScopeContext = require("../ScopeContext")
local PointerRouter = require("../PointerRouter")
local createSlider = require("../core/createSlider").createSlider

local vide = Deps.vide
local create = vide.create
local source = vide.source
local action = vide.action
local cleanup = vide.cleanup
local useScope = ScopeContext.useScope
local useRouter = RouterContext.useRouter

export type SliderProps = {
	--- Overridable the same way `Scope` is; omit to use whatever is ambient.
	Router: any?,

	--- PointerRouter semantics, the same as `Scrollbar`'s own thumb.
	Scope: any?,
	Layer: string?,
	Priority: number?,

	--- createSlider semantics -- see that module's own doc comment for the
	--- full controlled/uncontrolled shape.
	Axis: ("Vertical" | "Horizontal")?,
	Min: number?,
	Max: number?,
	Step: number?,
	--- A plain number (or nothing) is UNCONTROLLED; a getter is
	--- CONTROLLED -- the identical split `Checkbox`'s own `Checked` uses.
	Value: (number | (() -> number))?,
	InitialValue: number?,
	OnChange: ((value: number) -> ())?,
	OnDragStart: (() -> ())?,
	OnDragEnd: (() -> ())?,

	--- Geometry. `TrackLength` overrides the real measured track length
	--- when given (a fixed pixel number, or a getter); otherwise this file
	--- measures its own track instance, the same way `Scrollbar.luau`'s
	--- own `TrackLength` prop can override its own measurement.
	Width: ((() -> number) | number)?,
	TrackLength: ((() -> number) | number)?,
	ThumbSize: ((() -> number) | number)?,
	Padding: ((() -> number) | number)?,

	TrackColor: any?,
	ThumbColor: any?,
	ThumbHoverColor: any?,
	CornerRadius: any?,

	--- GuiObject Frame properties, on the TRACK (the outer instance this
	--- Primitive returns).
	Name: string?,
	Size: (UDim2 | () -> UDim2)?,
	Position: (UDim2 | () -> UDim2)?,
	AnchorPoint: (Vector2 | () -> Vector2)?,
	LayoutOrder: (number | () -> number)?,
	ZIndex: (number | () -> number)?,
	Visible: (boolean | () -> boolean)?,

	[any]: any,
}

local function resolve<T>(v: ((() -> T) | T)?): T?
	if type(v) == "function" then
		return (v :: any)()
	end
	return v :: any
end

local function color3FromRGB(r: number, g: number, b: number): any
	if typeof(Color3) == "table" and Color3.fromRGB then
		return Color3.fromRGB(r, g, b)
	end
	return { R = r / 255, G = g / 255, B = b / 255 }
end

local function udim2New(xs: number, xo: number, ys: number, yo: number): any
	if typeof(UDim2) == "table" and UDim2.new then
		return UDim2.new(xs, xo, ys, yo)
	end
	return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } }
end

local function udimNew(scale: number, offset: number): any
	if typeof(UDim) == "table" and UDim.new then
		return UDim.new(scale, offset)
	end
	return { Scale = scale, Offset = offset }
end

local function Slider(props: SliderProps): any
	local axis = props.Axis or "Horizontal"
	local isVertical = axis == "Vertical"
	local isHovered = source(false)
	local trackSurface: GuiObject? = nil

	local min = props.Min or 0
	local max = props.Max or 100

	--- MEASURED, NOT DECLARED -- see this file's own header comment. `200`
	--- is only what a not-yet-mounted track answers before the first
	--- measurement lands, the same fallback shape `Scrollbar.luau`'s own
	--- `measuredTrackLength` uses.
	local measuredTrackLength = source(200)

	local function getWidth(): number
		local w = resolve(props.Width)
		return if type(w) == "number" then w else 20
	end

	local function getPadding(): number
		local p = resolve(props.Padding)
		return if type(p) == "number" then p else 2
	end

	local function resolveTrackLength(): number
		local fromProps = resolve(props.TrackLength)
		if fromProps and fromProps > 0 then
			return fromProps
		end
		return measuredTrackLength()
	end

	local function getThumbSize(): number
		return resolve(props.ThumbSize) or 18
	end

	local machine = createSlider({
		Router = if props.Router ~= nil then props.Router else useRouter(),
		Source = source,
		Axis = axis,
		Min = min,
		Max = max,
		Step = props.Step,
		--- CONTROLLED WHEN `Value` IS A FUNCTION, the identical split
		--- `createSlider.luau`'s own doc comment and `Checkbox.luau`'s own
		--- `Checked` already use.
		Value = if type(props.Value) == "function" then props.Value :: () -> number else nil,
		InitialValue = if type(props.Value) == "number" then props.Value :: number else props.InitialValue,
		TrackLength = resolveTrackLength,
		OnDragStart = props.OnDragStart,
		OnDragEnd = props.OnDragEnd,
		OnChange = props.OnChange,
	})

	cleanup(machine.Destroy)

	--- STATIC DATA (`Min`/`Max`/`Step`/`Value`) AND BEHAVIOUR HOOKS
	--- (`OnPressed`/`OnReleased`), read once -- `createSlider.luau`'s own
	--- doc comment is explicit these are plain records, not spreadable
	--- prop arrays, so there is nothing to re-fetch on every frame.
	local rootProps = machine.GetRootProps()
	local thumbProps = machine.GetThumbProps()

	--- THE THUMB'S OWN PIXEL OFFSET ALONG THE TRACK, from the machine's
	--- already-clamped-and-stepped `Value()` -- never re-derived from a
	--- drag delta here (that is `createSlider`'s own job, upstream of this
	--- read).
	local function thumbOffset(): number
		local len = resolveTrackLength()
		local thumbSize = getThumbSize()
		local usable = math.max(len - thumbSize, 0)
		local range = rootProps.Max - rootProps.Min
		if range <= 0 then
			return 0
		end
		local t = (rootProps.Value() - rootProps.Min) / range
		return t * usable
	end

	local trackColor = function(): any
		local c = resolve(props.TrackColor)
		return if c then c else color3FromRGB(20, 26, 40)
	end

	local thumbColor = function(): any
		local base = resolve(props.ThumbColor)
		local hover = resolve(props.ThumbHoverColor)
		if isHovered() and hover then
			return hover
		end
		return if base then base else color3FromRGB(120, 160, 230)
	end

	local cornerRadius = resolve(props.CornerRadius) or function()
		return udimNew(0, math.floor(getWidth() / 2))
	end

	local thumbPressable = PointerRouter.Pressable({
		Scope = if props.Scope ~= nil then props.Scope else useScope(),
		Layer = props.Layer,
		Priority = props.Priority,
		Cursor = "Grab",
		HitTestable = false,
		--- `(x, y)` ARRIVE FROM THE PRESS ITSELF -- `PointerRouter.Pressable`'s
		--- own `OnPressed(x, y)` already supplies real coordinates, matching
		--- `GetThumbProps().OnPressed`'s own signature exactly, so nothing
		--- here re-queries a pointer position by hand.
		OnPressed = thumbProps.OnPressed,
		OnReleased = thumbProps.OnReleased,
		OnHoverChanged = function(hovered: boolean)
			isHovered(hovered)
		end,
	})

	if cleanup then
		cleanup(thumbPressable.Destroy)
	end

	local thumb = create("Frame")({
		Name = "SliderThumb",
		Size = function()
			local size = getThumbSize()
			return if isVertical then udim2New(1, 0, 0, size) else udim2New(0, size, 1, 0)
		end,
		Position = function()
			local offset = thumbOffset()
			local pad = getPadding()
			return if isVertical then udim2New(0, 0, 0, offset + pad) else udim2New(0, offset + pad, 0, 0)
		end,
		BackgroundColor3 = thumbColor,
		BorderSizePixel = 0,
		ZIndex = 2,

		action(thumbPressable.Bind),

		create("UICorner")({
			CornerRadius = cornerRadius,
		}),
	})

	return create("Frame")({
		Name = props.Name or "Slider",
		--- FOUND LIVE: never forwarded before, so every consumer's own
		--- `Parent = ...` was silently accepted (the type's own `[any]: any`
		--- catch-all lets it through) and then silently DROPPED -- the
		--- returned track never got parented, which measured 0x0 and never
		--- painted. `Pressable.luau`'s own `create("Frame")(machine
		--- .GetRootProps(props))` forwards the WHOLE incoming table and so
		--- never had this gap; this file rebuilds a curated table by hand
		--- and had simply never named `Parent` on that list.
		Parent = props.Parent,
		Size = props.Size or function()
			local w = getWidth()
			return if isVertical then udim2New(0, w, 1, 0) else udim2New(1, 0, 0, w)
		end,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Visible = props.Visible,
		BackgroundColor3 = trackColor,
		BorderSizePixel = 0,

		action(function(rbx: GuiObject)
			trackSurface = rbx
			if isRoblox and rbx and typeof(rbx) == "Instance" and rbx:IsA("GuiObject") then
				local function updateTrack()
					if rbx.AbsoluteSize then
						local len = if isVertical then rbx.AbsoluteSize.Y else rbx.AbsoluteSize.X
						if len > 0 then
							measuredTrackLength(len)
						end
					end
				end
				task.defer(updateTrack)
				local conn = rbx:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateTrack)
				if cleanup then
					cleanup(function()
						conn:Disconnect()
					end)
				end
			elseif rbx then
				--- OFF-ENGINE (Dew): see this file's own header comment --
				--- polled on the frame the router already pumps, reading the
				--- same solved bounds hit-testing does, guarded on a change
				--- so a still screen costs one comparison.
				local Scene = Deps.Host.Scene
				local last = -1
				local unhook = PointerRouter.OnFrame(function()
					local _, _, w, h = Scene.Bounds(rbx)
					local len = if isVertical then h else w
					if len and len > 0 and len ~= last then
						last = len
						measuredTrackLength(len)
					end
				end)
				if cleanup then
					cleanup(unhook)
				end
			end
		end),

		create("UICorner")({
			CornerRadius = cornerRadius,
		}),

		thumb,
	})
end

return Slider
