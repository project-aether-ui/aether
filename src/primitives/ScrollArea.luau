--!strict
--[=[
	ScrollArea — Headless Scroll Container Primitive
	Part of Aether.Primitives (Layer 2).

	Coordinates Viewport, Content Frame, ScrollController, and Scrollbar
	with full InputScope and InputSink coordination.
]=]

local isRoblox = typeof(game) == "Instance"
local isScriptInstance = typeof(script) == "Instance"

local function loadSibling(name: string): any
	if isScriptInstance then
		local parent = (script :: any).Parent
		if parent and parent:FindFirstChild(name) then
			return require(parent[name])
		end
		local root = parent and parent.Parent
		if root and root:FindFirstChild(name) then
			return require(root[name])
		end
		if root and root:FindFirstChild("src") and root.src:FindFirstChild(name) then
			return require(root.src[name])
		end
		if root and root:FindFirstChild("src") and root.src:FindFirstChild("controllers") and root.src.controllers:FindFirstChild(name) then
			return require(root.src.controllers[name])
		end
	end
	local ok, res = pcall(require, "./" .. name)
	if ok then return res end
	local ok2, res2 = pcall(require, "../" .. name)
	if ok2 then return res2 end
	local ok3, res3 = pcall(require, "../../src/" .. name)
	if ok3 then return res3 end
	local ok4, res4 = pcall(require, "../controllers/" .. name)
	if ok4 then return res4 end
	return {}
end

local Deps = loadSibling("Deps")
local ScrollController = loadSibling("ScrollController")
local Scrollbar = loadSibling("Scrollbar")
local InputScope = loadSibling("InputScope")
local PointerRouter = loadSibling("PointerRouter")
local HitTest = loadSibling("HitTest")

local UserInputService = if isRoblox and typeof(game) == "Instance" and game:GetService("UserInputService")
	then game:GetService("UserInputService")
	else nil

--- ms-51 M16: the motion SEAM, not Flux. Aether is a genuine consumer of
--- springs, so this edge could not be reversed like the component seams —
--- it was made OPTIONAL instead. Unregistered, Smooth hands the target
--- straight back and the value steps. See Motion.luau.
local Motion = loadSibling("Motion")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local UDim2, UDim, Vector2, Enum =
	Deps.Vocabulary.UDim2, Deps.Vocabulary.UDim, Deps.Vocabulary.Vector2, Deps.Vocabulary.Enum

local create = Deps.create
local source = Deps.source
--- A monotonic revision counter, not a value this scope should react to. See
--- Deps.peek: reading it plainly inside the subscriber made the running effect
--- depend on a source the very next expression writes.
local peek = Deps.peek
local action = Deps.action
local cleanup = Deps.cleanup

export type ScrollMotionConfig = {
	Period: number?,
	DampingRatio: number?,
	SmoothScroll: boolean?,
	SmoothThumb: boolean?,
	HoverEffect: boolean?,
}

export type ScrollAreaProps = {
	Name: string?,
	Scope: any?,
	Size: any?,
	Position: any?,
	AnchorPoint: any?,
	CanvasSize: any?,
	ContentHeight: ((() -> number) | number)?,
	Controller: any?,
	Layout: ("List" | "None")?,
	StepSize: number?,
	SpringPeriod: number?,
	SpringDamping: number?,
	SmoothMotion: boolean?,
	Motion: ScrollMotionConfig?,
	ShowVerticalBar: ((() -> boolean) | boolean)?,
	AutoHide: ((() -> boolean) | boolean)?,
	OnScrolled: ((offset: any) -> ())?,
	Content: any?,
	Children: any?,
	Visible: ((() -> boolean) | boolean)?,
	LayoutOrder: ((() -> number) | number)?,
	ZIndex: number?,
	Debug: boolean?,
	[any]: any,
}

local function resolve<T>(v: ((() -> T) | T)?): T?
	if type(v) == "function" then
		return (v :: any)()
	end
	return v :: any
end

local function udim2New(xs: number, xo: number, ys: number, yo: number): any
	if isRoblox and typeof(UDim2) == "table" and UDim2.new then
		return UDim2.new(xs, xo, ys, yo)
	end
	return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } }
end

local function vector2New(x: number, y: number): any
	if isRoblox and typeof(Vector2) == "table" and Vector2.new then
		return Vector2.new(x, y)
	end
	return { X = x, Y = y }
end

type ScrollOwner = {
	Scope: any?,
	Surface: () -> GuiObject?,
	IsHovered: () -> boolean,
	Scroll: (delta: number) -> (),
}

local scrollOwners: { ScrollOwner } = {}

local function depthOfInstance(inst: any): number
	local depth, cur = 0, inst
	while cur and typeof(cur) == "Instance" do
		depth += 1
		cur = cur.Parent
	end
	return depth
end

local function resolveWheelTarget(px: number, py: number): ScrollOwner?
	local best: ScrollOwner? = nil
	local bestDepth = -1
	local owningScope = InputScope.HitTest(px, py)

	for _, owner in ipairs(scrollOwners) do
		local scopeId = if type(owner.Scope) == "table" and owner.Scope.Id
			then owner.Scope.Id
			elseif type(owner.Scope) == "string"
			then owner.Scope
			else nil

		if owningScope and scopeId and scopeId ~= owningScope then
			continue
		end

		local surface = owner.Surface()
		if not surface or not surface.Parent then
			continue
		end

		local isOver = false
		if HitTest and HitTest.ContainsVisible then
			isOver = HitTest.ContainsVisible(surface, px, py)
		elseif isRoblox and surface.AbsolutePosition and surface.AbsoluteSize then
			local pos = surface.AbsolutePosition
			local sz = surface.AbsoluteSize
			isOver = px >= pos.X and px <= pos.X + sz.X and py >= pos.Y and py <= pos.Y + sz.Y
		end

		if not isOver and owner.IsHovered() then
			isOver = true
		end

		if isOver then
			local d = depthOfInstance(surface)
			if d > bestDepth then
				best, bestDepth = owner, d
			end
		end
	end
	return best
end

--- WHEEL INPUT, THROUGH THE ROUTER (ms-52 M3).
---
--- This was a private `UserInputService.InputChanged` behind
--- `if ... not UserInputService then return end`, which made wheel scrolling the
--- second interaction that only existed in Roblox -- the same shape as the
--- scrollbar thumb's drag, found the same way, by a real primitive that laid out
--- and hit-tested correctly off-engine and then would not respond.
---
--- What is NOT changing is the interesting part: `resolveWheelTarget` picks the
--- topmost scrollable under the pointer and was already fully portable. Only the
--- source of the event was engine-bound, which is precisely why the omission was
--- invisible from inside Roblox.
---
--- Still ONE listener for every ScrollArea on screen, as before; the router now
--- owns it, and normalises the sign so this code no longer encodes Roblox's
--- convention that wheel-up is a positive Z.
local wheelConnected = false
local function ensureWheelListener()
	if wheelConnected then
		return
	end
	wheelConnected = true

	PointerRouter.OnWheel(function(px: number, py: number, delta: number)
		local target = resolveWheelTarget(px, py)
		if target then
			target.Scroll(delta)
		end
	end)
end

local function ScrollArea(props: ScrollAreaProps): any
	ensureWheelListener()

	local verticalOffset = source(0)
	local horizontalOffset = source(0)
	local viewportHeight = source(200)
	local isHovered = source(false)
	local viewportSurface: GuiObject? = nil
	local rootSurface: GuiObject? = nil

	local initialViewportHeight = 200
	if props.Controller then
		local vp = props.Controller.GetViewportSize()
		if vp and vp > 0 then
			initialViewportHeight = vp
		end
	elseif props.Size then
		local sz = resolve(props.Size)
		if typeof(sz) == "UDim2" and sz.Y.Offset > 0 then
			initialViewportHeight = sz.Y.Offset
		elseif type(sz) == "table" and sz.Y and sz.Y.Offset and sz.Y.Offset > 0 then
			initialViewportHeight = sz.Y.Offset
		end
	end

	local initialContentHeight = 1000
	if props.Controller then
		local cs = props.Controller.GetContentSize()
		if cs and cs > 0 then
			initialContentHeight = cs
		end
	end
	local explicitH = resolve(props.ContentHeight)
	if explicitH and explicitH > 0 then
		initialContentHeight = explicitH
	elseif props.CanvasSize then
		local cs = resolve(props.CanvasSize)
		if typeof(cs) == "UDim2" and cs.Y.Offset > 0 then
			initialContentHeight = cs.Y.Offset
		elseif type(cs) == "table" and cs.Y and cs.Y.Offset and cs.Y.Offset > 0 then
			initialContentHeight = cs.Y.Offset
		end
	end

	local viewportHeight = source(initialViewportHeight)
	local contentHeight = source(initialContentHeight)

	local controller = props.Controller or ScrollController.new({
		ViewportSize = initialViewportHeight,
		ContentSize = initialContentHeight,
		StepSize = props.StepSize or 40,
	})

	local versionSignal = source(0)

	controller.Subscribe(function(newOffset)
		verticalOffset(newOffset)
		versionSignal(peek(versionSignal) + 1)
		if props.OnScrolled then
			props.OnScrolled(vector2New(horizontalOffset(), newOffset))
		end
	end)

	local children: { any } = {}
	for k, v in pairs(props) do
		if type(k) == "number" then
			table.insert(children, v)
		end
	end

	if props.Content then
		if typeof(props.Content) == "function" then
			local c = props.Content()
			if typeof(c) == "table" then
				for _, item in ipairs(c) do
					table.insert(children, item)
				end
			elseif c ~= nil then
				table.insert(children, c)
			end
		elseif typeof(props.Content) == "table" then
			for _, item in ipairs(props.Content) do
				table.insert(children, item)
			end
		elseif props.Content ~= nil then
			table.insert(children, props.Content)
		end
	end

	if props.Children then
		if typeof(props.Children) == "function" then
			local c = props.Children()
			if typeof(c) == "table" then
				for _, item in ipairs(c) do
					table.insert(children, item)
				end
			elseif c ~= nil then
				table.insert(children, c)
			end
		elseif typeof(props.Children) == "table" then
			for _, item in ipairs(props.Children) do
				table.insert(children, item)
			end
		elseif props.Children ~= nil then
			table.insert(children, props.Children)
		end
	end

	local isStationaryCanvas = if props.Virtualize ~= nil then (props.Virtualize == true or props.Virtualize ~= false) else (props.StaticCanvas == true)
	local hasExplicitCanvas = props.CanvasSize ~= nil or props.ContentHeight ~= nil
	local useListLayout = if isStationaryCanvas then false else (props.Layout == "List" or (props.Layout == nil and not hasExplicitCanvas))

	local autoSizeY = if isStationaryCanvas then nil elseif not hasExplicitCanvas and isRoblox and typeof(Enum) == "table" and Enum.AutomaticSize
		then Enum.AutomaticSize.Y
		else nil
	local fillDir = if isRoblox and typeof(Enum) == "table" and Enum.FillDirection then Enum.FillDirection.Vertical else nil
	local sortOrder = if isRoblox and typeof(Enum) == "table" and Enum.SortOrder then Enum.SortOrder.LayoutOrder else nil
	local padding = if isRoblox and typeof(UDim) == "table" and UDim.new then UDim.new(0, 4) else nil

	local motionConfig = props.Motion or {}
	local isDraggingThumb = source(false)
	local springPeriod = motionConfig.Period or props.SpringPeriod or 0.20
	local springDamping = motionConfig.DampingRatio or props.SpringDamping or 0.85
	local smoothScroll = if motionConfig.SmoothScroll ~= nil then motionConfig.SmoothScroll else (props.SmoothMotion ~= false)
	local smoothThumb = if motionConfig.SmoothThumb ~= nil then motionConfig.SmoothThumb else true

	local isSpringable = smoothScroll and springPeriod >= 0.02
	--- The spring's returned function is BOTH getter and setter: called with no
	--- arguments it reads, called with a number it sets the current position and
	--- zeroes the velocity. `Motion.Smooth` forwards it unchanged, so seeding
	--- needs no new API -- see the drag-end handler below for why it is needed.
	local smoothedVerticalOffset = if isSpringable
		then Motion.Smooth(verticalOffset, { Period = springPeriod, DampingRatio = springDamping })
		else verticalOffset

	local renderedVerticalOffset = function()
		if isDraggingThumb() or not smoothScroll or not isSpringable then
			return verticalOffset()
		end
		return smoothedVerticalOffset()
	end

	local contentContainer = create("Frame")({
		Name = "ScrollContent",
		Size = function()
			if isStationaryCanvas then
				return udim2New(1, 0, 1, 0)
			end
			if props.CanvasSize then
				return resolve(props.CanvasSize)
			end
			return if hasExplicitCanvas
				then udim2New(1, 0, 0, contentHeight())
				else udim2New(1, 0, 0, 0)
		end,
		Position = if isStationaryCanvas
			then udim2New(0, 0, 0, 0)
			else function()
				return udim2New(0, -horizontalOffset(), 0, -renderedVerticalOffset())
			end,
		AutomaticSize = autoSizeY,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		action(function(rbx: GuiObject)
			if isRoblox and rbx and typeof(rbx) == "Instance" and rbx:IsA("GuiObject") then
				local function updateContent()
					local h = 0
					local expH = resolve(props.ContentHeight)
					if expH and expH > 0 then
						h = expH
					elseif props.CanvasSize then
						local cs = resolve(props.CanvasSize)
						if typeof(cs) == "UDim2" and cs.Y.Offset > 0 then
							h = cs.Y.Offset
						elseif type(cs) == "table" and cs.Y and cs.Y.Offset and cs.Y.Offset > 0 then
							h = cs.Y.Offset
						end
					end

					if h <= 0 then
						-- Check for layout children first
						for _, child in ipairs(rbx:GetChildren()) do
							if child:IsA("UIListLayout") or child:IsA("UIGridLayout") then
								if child.AbsoluteContentSize and child.AbsoluteContentSize.Y > 0 then
									h = math.max(h, child.AbsoluteContentSize.Y)
								end
							end
						end
					end

					if h <= 0 and rbx.AbsoluteSize and rbx.AbsoluteSize.Y > 0 then
						h = rbx.AbsoluteSize.Y
					end

					-- If still 0, check child bounding box
					if h <= 0 then
						for _, child in ipairs(rbx:GetChildren()) do
							if child:IsA("GuiObject") and child.Visible then
								local bot = child.Position.Y.Offset + child.Size.Y.Offset
								if bot > h then
									h = bot
								end
							end
						end
					end

					if h > 0 then
						contentHeight(h)
						controller.SetDimensions(viewportHeight(), h)
					end
				end

				local layoutConns: { [Instance]: any } = {}
				local function trackChild(child: Instance)
					if child:IsA("UIListLayout") or child:IsA("UIGridLayout") then
						if not layoutConns[child] then
							layoutConns[child] = child:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateContent)
						end
						updateContent()
					elseif child:IsA("GuiObject") then
						child:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateContent)
						child:GetPropertyChangedSignal("Position"):Connect(updateContent)
					end
				end

				for _, child in ipairs(rbx:GetChildren()) do
					trackChild(child)
				end
				rbx.ChildAdded:Connect(trackChild)
				rbx.ChildRemoved:Connect(function(child)
					if layoutConns[child] then
						layoutConns[child]:Disconnect()
						layoutConns[child] = nil
					end
					task.defer(updateContent)
				end)

				task.defer(updateContent)
				rbx:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateContent)
			end
		end),
		if useListLayout then
			create("UIListLayout") {
				Padding = padding,
				FillDirection = fillDir,
				SortOrder = sortOrder,
			}
		else nil,
		table.unpack(children),
	})

	local viewportPressable = PointerRouter.Pressable({
		Scope = props.Scope,
		HitTestable = false,
		OnHoverChanged = function(hovered)
			isHovered(hovered)
		end,
	})

	if cleanup then
		cleanup(viewportPressable.Destroy)
	end

	local ownerRecord: ScrollOwner = {
		Scope = props.Scope,
		Surface = function()
			return viewportSurface or rootSurface
		end,
		IsHovered = function()
			return isHovered()
		end,
		Scroll = function(delta)
			controller.ScrollBy(delta * (props.StepSize or 40))
		end,
	}
	table.insert(scrollOwners, ownerRecord)

	if cleanup then
		cleanup(function()
			local idx = table.find(scrollOwners, ownerRecord)
			if idx then
				table.remove(scrollOwners, idx)
			end
		end)
	end

	local viewportFrame = create("Frame")({
		Name = "ScrollViewport",
		Size = udim2New(1, 0, 1, 0),
		Position = udim2New(0, 0, 0, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		BorderSizePixel = 0,
		action(viewportPressable.Bind),
		action(function(rbx: GuiObject)
			viewportSurface = rbx
			if isRoblox and rbx and typeof(rbx) == "Instance" and rbx:IsA("GuiObject") then
				local function updateVp()
					if rbx.AbsoluteSize then
						local h = rbx.AbsoluteSize.Y
						if h > 0 then
							viewportHeight(h)
							controller.SetDimensions(h, contentHeight())
						end
					end
				end
				task.defer(updateVp)
				rbx:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateVp)
			elseif rbx then
				--- OFF-ENGINE, THE VIEWPORT HAS TO BE ASKED FOR (ms-53 D2).
				---
				--- The branch above was the ONLY place this area learned how tall
				--- it is, and it is gated on Roblox. Off-engine `viewportHeight`
				--- kept its constructed default and `controller.SetDimensions` was
				--- never called at all -- so the controller clamped against a
				--- viewport nobody had measured, and the wheel moved nothing. That
				--- is the defect ms-52 recorded as "maxScroll reports 0 while the
				--- wheel moves content from 20 to -140": the area and its
				--- controller disagreeing because one of them was never told.
				---
				--- POLLED ON THE FRAME the router already pumps, because the
				--- off-engine equivalent of `AbsoluteSize` changing is the LAYOUT
				--- SOLVER writing new bounds -- which happens once a frame and has
				--- no change signal. `Scene.Bounds` is what the solver wrote, so
				--- this reads the same number hit-testing does; measuring it any
				--- other way is how a viewport and a hit area drift apart.
				---
				--- Guarded on a CHANGE, so a still screen costs one comparison.
				--- BOTH DIMENSIONS, because both were Roblox-only.
				---
				--- The content height is measured just above from
				--- `AbsoluteContentSize`, `GetChildren` and `IsA` -- all engine
				--- APIs -- so off-engine neither number ever arrived. A caller
				--- could supply `ContentHeight` by hand and the story browser did,
				--- over-declaring it by 72 px and over-scrolling by exactly that.
				---
				--- Measured from the SOLVED BOUNDS the layout wrote, which is the
				--- same source hit-testing reads. Measuring it any other way is how
				--- a viewport and a hit area drift apart.
				--- DISCONNECTED WITH THE TREE. `OnFrame` returns its own unhook and
				--- the router holds observers in a module-level table, so a tree
				--- that is destroyed without calling it leaves one behind on every
				--- rebuild -- which `--reload-check` caught on the first run after
				--- this was written, at 16 registrations before a reload and 17
				--- after.
				local Scene = Deps.Host.Scene
				local lastVp, lastContent = -1, -1
				local unhook = PointerRouter.OnFrame(function()
					local _, _, _, vh = Scene.Bounds(rbx)

					--- The canvas is the viewport's only real child, and the
					--- content extent is the bottom of what IT holds -- relative to
					--- the canvas top, because the canvas is what moves when the
					--- offset changes.
					local ch = 0
					for _, canvas in ipairs(Scene.Children(rbx)) do
						local _, cy = Scene.Bounds(canvas)
						for _, child in ipairs(Scene.Children(canvas)) do
							local _, ky, _, kh = Scene.Bounds(child)
							if kh and kh > 0 then
								ch = math.max(ch, (ky - cy) + kh)
							end
						end
					end

					local changed = false
					if vh and vh > 0 and vh ~= lastVp then
						lastVp = vh
						viewportHeight(vh)
						changed = true
					end
					--- Only when it can be measured. A canvas whose children have
					--- not been solved yet answers 0, and accepting that would
					--- clamp the extent to nothing on the first frame.
					if ch > 0 and ch ~= lastContent and not hasExplicitCanvas then
						lastContent = ch
						contentHeight(ch)
						changed = true
					end
					if changed then
						controller.SetDimensions(viewportHeight(), contentHeight())
					end
				end)
				if cleanup then
					cleanup(unhook)
				end
			end
		end),
		contentContainer,
	})

	local sbProps = props.ScrollbarProps or {}
	local rawSbWidth = props.ScrollBarWidth or sbProps.Width or 6
	local rawSbPadding = props.ScrollBarPadding or sbProps.Padding or 0

	local function getSbWidth(): number
		local w = resolve(rawSbWidth)
		return if type(w) == "number" then w else 6
	end

	local function getSbPadding(): number
		local p = resolve(rawSbPadding)
		return if type(p) == "number" then p else 0
	end

	local defaultPosition = function()
		local w = getSbWidth()
		return udim2New(1, -w - 2, 0, 2)
	end

	local defaultSize = function()
		local w = getSbWidth()
		return udim2New(0, w, 1, -4)
	end

	local showVerticalBar = if props.ShowVerticalBar ~= nil then props.ShowVerticalBar else true
	local verticalBar = if showVerticalBar then Scrollbar({
		Name = if props.Name then props.Name .. "_ScrollBar" else "ScrollBar",
		Scope = props.Scope,
		MaxScroll = function()
			if isStationaryCanvas and controller.GetMaxScroll then
				return controller.GetMaxScroll()
			end
			return math.max(0, contentHeight() - viewportHeight())
		end,
		ContentHeight = function()
			if isStationaryCanvas and controller.GetContentSize then
				return controller.GetContentSize()
			end
			return contentHeight()
		end,
		ViewportHeight = function()
			if isStationaryCanvas and controller.GetViewportSize then
				return controller.GetViewportSize()
			end
			return viewportHeight()
		end,
		Axis = "Vertical",
		Position = props.ScrollbarPosition or sbProps.Position or defaultPosition,
		Size = props.ScrollbarSize or sbProps.Size or defaultSize,
		Width = getSbWidth,
		Padding = getSbPadding,
		ThumbColor = props.ThumbColor or sbProps.ThumbColor,
		ThumbHoverColor = props.ThumbHoverColor or sbProps.ThumbHoverColor,
		TrackColor = props.TrackColor or sbProps.TrackColor,
		TrackTransparency = props.TrackTransparency or sbProps.TrackTransparency,
		ThumbTransparency = props.ThumbTransparency or sbProps.ThumbTransparency,
		CornerRadius = props.ScrollbarCornerRadius or sbProps.CornerRadius,
		Parts = props.ScrollbarParts or sbProps.Parts,
		Motion = props.Motion,
		HideWhenUnscrollable = props.HideWhenUnscrollable,
		AutoHide = props.AutoHide,
		TrackLength = function()
			local _ = versionSignal()
			local vp = if isStationaryCanvas and controller.GetViewportSize then controller.GetViewportSize() else viewportHeight()
			return math.max(vp - 4, 10)
		end,
		ThumbSize = function()
			local _ = versionSignal()
			local vp = if isStationaryCanvas and controller.GetViewportSize then controller.GetViewportSize() else viewportHeight()
			local trackLen = math.max(vp - 4, 10)
			return controller.GetThumbSize(trackLen)
		end,
		ThumbOffset = function()
			local _ = versionSignal()
			local currentOffset = if smoothThumb then renderedVerticalOffset() else verticalOffset()
			local vp = if isStationaryCanvas and controller.GetViewportSize then controller.GetViewportSize() else viewportHeight()
			local trackLen = math.max(vp - 4, 10)
			local thumbLen = controller.GetThumbSize(trackLen)
			local maxScr = if isStationaryCanvas and controller.GetMaxScroll then controller.GetMaxScroll() else math.max(0, contentHeight() - viewportHeight())
			local offset = ScrollController.computeThumbOffset(currentOffset, maxScr, trackLen, thumbLen)
			return offset
		end,
		OnDragStart = function()
			isDraggingThumb(true)
		end,
		OnDragEnd = function()
			--- SEED THE SPRING TO WHERE THE THUMB ACTUALLY IS (ms-52).
			---
			--- While the thumb is held, `renderedVerticalOffset` returns the RAW
			--- offset so the content tracks the finger exactly. The spring is
			--- meanwhile chasing that offset and lagging it by roughly its period.
			---
			--- The instant the drag ends, rendering switches to the spring -- which
			--- is still behind. So the content JUMPS BACKWARDS to where the spring
			--- had got to, then eases forward again. es9 noticed this as "the spring
			--- motion taking effect on the thumb just after a thumb drag had ended".
			---
			--- Seeding the spring to the raw offset makes the handover continuous:
			--- the value it reports at the moment of release is the value that was
			--- already on screen. Velocity is zeroed by the same call, which is
			--- correct here -- the finger has stopped, so the content should not
			--- carry momentum it never had.
			if isSpringable then
				(smoothedVerticalOffset :: any)(verticalOffset())
			end
			isDraggingThumb(false)
		end,
		OnThumbDrag = function(delta, initialThumbOffset)
			local vp = if isStationaryCanvas and controller.GetViewportSize then controller.GetViewportSize() else viewportHeight()
			local trackLen = math.max(vp - 4, 10)
			local thumbLen = controller.GetThumbSize(trackLen)
			local maxScr = if isStationaryCanvas and controller.GetMaxScroll then controller.GetMaxScroll() else math.max(0, contentHeight() - viewportHeight())
			if maxScr > 0 and trackLen > thumbLen then
				local targetThumbPos = initialThumbOffset + delta
				local targetScroll = ScrollController.computeScrollFromThumb(targetThumbPos, trackLen, thumbLen, maxScr)
				controller.ScrollTo(targetScroll)
			end
		end,
		OnTrackClick = function(clickPos)
			local vp = if isStationaryCanvas and controller.GetViewportSize then controller.GetViewportSize() else viewportHeight()
			local trackLen = math.max(vp - 4, 10)
			local thumbLen = controller.GetThumbSize(trackLen)
			local maxScr = if isStationaryCanvas and controller.GetMaxScroll then controller.GetMaxScroll() else math.max(0, contentHeight() - viewportHeight())
			if maxScr > 0 and trackLen > thumbLen then
				local targetThumbPos = clickPos - (thumbLen / 2)
				local targetScroll = ScrollController.computeScrollFromThumb(targetThumbPos, trackLen, thumbLen, maxScr)
				controller.ScrollTo(targetScroll)
			end
		end,
		Visible = function()
			local _ = versionSignal()
			local show = resolve(props.ShowVerticalBar)
			if show == false then return false end
			local maxScr = if isStationaryCanvas and controller.GetMaxScroll
				then controller.GetMaxScroll()
				else math.max(0, contentHeight() - viewportHeight())
			local hideWhenUnscrollable = resolve(props.HideWhenUnscrollable)
			if hideWhenUnscrollable ~= false then
				if maxScr <= 0 then
					return false
				end
			end
			local autoHide = resolve(props.AutoHide)
			if autoHide and not isHovered() and not isDraggingThumb() then return false end
			return true
		end,
		ZIndex = (props.ZIndex or 1) + 2,
	}) else nil

	return create("Frame")({
		Name = "ScrollArea",
		Size = props.Size or udim2New(1, 0, 1, 0),
		Position = props.Position or udim2New(0, 0, 0, 0),
		AnchorPoint = props.AnchorPoint,
		ZIndex = props.ZIndex or 1,
		Visible = props.Visible,
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		action(function(rbx: GuiObject)
			rootSurface = rbx
		end),
		viewportFrame,
		if showVerticalBar then verticalBar else nil,
	})
end

return ScrollArea
