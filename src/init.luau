--!strict
-- Aether Headless UI Framework
-- Decoupled into 5-Layer Universal Architecture:
-- 1. Controllers (Pure State Machines)
-- 2. Core (Headless Interaction Protocols)
-- 3. Engine (Arbitration & IO)
-- 4. Primitives (Host-Resolved Structural Skeletons)
-- 5. Runtime (Reactive Control Flow)

local isScript = typeof(script) == "Instance"

local function loadSubmodule(instanceChild: any, relativePath: string): any
	if isScript and instanceChild then
		return require(instanceChild)
	end
	local ok, res = pcall(require, "./" .. relativePath)
	if ok then return res end
	local ok2, res2 = pcall(require, "./src/" .. relativePath)
	if ok2 then return res2 end
	return {}
end

local Icon = if isScript
	then require(script.Icon.src.Icon)
	else (function()
		local ok, res = pcall(require, "./Icon/src/Icon")
		if ok then return res end
		local ok2, res2 = pcall(require, "./src/Icon/src/Icon")
		if ok2 then return res2 end
		return {}
	end)()

local SelectionModel = loadSubmodule(if isScript and script:FindFirstChild("controllers") then script.controllers:FindFirstChild("SelectionModel") else nil, "controllers/SelectionModel")
local TreeController = loadSubmodule(if isScript and script:FindFirstChild("controllers") then script.controllers:FindFirstChild("TreeController") else nil, "controllers/TreeController")
local createPressableModule = loadSubmodule(if isScript and script:FindFirstChild("core") then script.core:FindFirstChild("createPressable") else nil, "core/createPressable")
local createPressable = if createPressableModule then createPressableModule.createPressable else nil

local LayerManager = loadSubmodule(if isScript then script:FindFirstChild("LayerManager") else nil, "LayerManager")
local Text = loadSubmodule(if isScript then script:FindFirstChild("Text") else nil, "Text")
local InputSink = loadSubmodule(if isScript then script:FindFirstChild("InputSink") else nil, "InputSink")
local InputScope = loadSubmodule(if isScript then script:FindFirstChild("InputScope") else nil, "InputScope")
local PointerRouter = loadSubmodule(if isScript then script:FindFirstChild("PointerRouter") else nil, "PointerRouter")
local Pressable = loadSubmodule(if isScript and script:FindFirstChild("primitives") then script.primitives:FindFirstChild("Pressable") else nil, "primitives/Pressable")
local ScreenStack = loadSubmodule(if isScript then script:FindFirstChild("ScreenStack") else nil, "ScreenStack")
local TransitionOrchestrator = loadSubmodule(if isScript then script:FindFirstChild("TransitionOrchestrator") else nil, "TransitionOrchestrator")
local useHover = loadSubmodule(if isScript then script:FindFirstChild("useHover") else nil, "useHover")
local ScreenCoords = loadSubmodule(if isScript then script:FindFirstChild("ScreenCoords") else nil, "ScreenCoords")
local For = loadSubmodule(if isScript then script:FindFirstChild("For") else nil, "For")
local ScopeContext = loadSubmodule(if isScript then script:FindFirstChild("ScopeContext") else nil, "ScopeContext")
local ScopedSurface = loadSubmodule(if isScript then script:FindFirstChild("ScopedSurface") else nil, "ScopedSurface")
local TextInput = loadSubmodule(if isScript then script:FindFirstChild("TextInput") else nil, "TextInput")
local TextInputManager = loadSubmodule(if isScript then script:FindFirstChild("TextInputManager") else nil, "TextInputManager")
local FloatingMath = loadSubmodule(if isScript then script:FindFirstChild("FloatingMath") else nil, "FloatingMath")
local useFloating = loadSubmodule(if isScript then script:FindFirstChild("useFloating") else nil, "useFloating")
local Presence = loadSubmodule(if isScript then script:FindFirstChild("Presence") else nil, "Presence")
local useDisclosure = loadSubmodule(if isScript then script:FindFirstChild("useDisclosure") else nil, "useDisclosure")
local useSelection = loadSubmodule(if isScript then script:FindFirstChild("useSelection") else nil, "useSelection")
local Stagger = loadSubmodule(if isScript then script:FindFirstChild("Stagger") else nil, "Stagger")
local Combobox = loadSubmodule(if isScript and script:FindFirstChild("primitives") then script.primitives:FindFirstChild("Combobox") else nil, "primitives/Combobox")
local ContextMenu = loadSubmodule(if isScript and script:FindFirstChild("primitives") then script.primitives:FindFirstChild("ContextMenu") else nil, "primitives/ContextMenu")
local Tooltip = loadSubmodule(if isScript and script:FindFirstChild("primitives") then script.primitives:FindFirstChild("Tooltip") else nil, "primitives/Tooltip")
local ScrollController = loadSubmodule(if isScript and script:FindFirstChild("controllers") then script.controllers:FindFirstChild("ScrollController") else nil, "controllers/ScrollController")
local ScrollArea = loadSubmodule(if isScript and script:FindFirstChild("primitives") then script.primitives:FindFirstChild("ScrollArea") else nil, "primitives/ScrollArea")
local PrimitiveScrollbar = loadSubmodule(if isScript and script:FindFirstChild("primitives") then script.primitives:FindFirstChild("Scrollbar") else nil, "primitives/Scrollbar")
local PrimitiveWindowTopbar = loadSubmodule(if isScript and script:FindFirstChild("primitives") then script.primitives:FindFirstChild("WindowTopbar") else nil, "primitives/WindowTopbar")
local ScrollingFrame = loadSubmodule(if isScript and script:FindFirstChild("primitives") then script.primitives:FindFirstChild("ScrollingFrame") else nil, "primitives/ScrollingFrame")
local VirtualList = loadSubmodule(if isScript and script:FindFirstChild("primitives") then script.primitives:FindFirstChild("VirtualList") else nil, "primitives/VirtualList")
local TreeView = loadSubmodule(if isScript and script:FindFirstChild("primitives") then script.primitives:FindFirstChild("TreeView") else nil, "primitives/TreeView")
--- Layer 2.5. Exported so packages ABOVE Aether can build on the same host —
--- notably so they can take real vide headlessly instead of a shim.
local Motion = loadSubmodule(if isScript then script:FindFirstChild("Motion") else nil, "Motion")
--- The cursor seam (ms-51 M19). Exported so the package that OWNS the cursor
--- can register itself, which is what replaced Aether depending on it.
local Cursor = loadSubmodule(if isScript then script:FindFirstChild("Cursor") else nil, "Cursor")
local Host = loadSubmodule(if isScript and script:FindFirstChild("host") then script.host:FindFirstChild("Host") else nil, "host/Host")

-- Layer 1: Pure Headless State Machines
local Controllers = {
	SelectionModel = SelectionModel,
	TreeController = TreeController,
	ScrollController = ScrollController,
}

-- Layer 2: Headless Interaction Protocols (Abstract IO)
local Core = {
	createPressable = createPressable,
	ScrollController = ScrollController,
}

-- Domain 1: Reactive Runtime & Control Flow
local Runtime = {
	For = For,
	KeyedList = For,
}

-- Domain 2: Arbitration & Interaction Engines
local Engine = {
	PointerRouter = PointerRouter,
	Pressable = if PointerRouter then PointerRouter.Pressable else nil,
	ScopeProvider = if ScopeContext then ScopeContext.ScopeProvider else nil,
	ScopeContext = if ScopeContext then ScopeContext.ScopeContext else nil,
	useScope = if ScopeContext then ScopeContext.useScope else nil,
	InputScope = InputScope,
	InputSink = InputSink,
	LayerManager = LayerManager,
	TextInputManager = TextInputManager,
	ScreenCoords = ScreenCoords,
	useHover = useHover,
	Presence = Presence,
	useDisclosure = useDisclosure,
	useSelection = useSelection,
	Stagger = Stagger,
	ScreenStack = ScreenStack,
	TransitionOrchestrator = TransitionOrchestrator,
	FloatingMath = FloatingMath,
	useFloating = useFloating,
}

-- Domain 3: Headless Structural UI Primitives (Host-Resolved)
local Primitives = {
	ScopedSurface = ScopedSurface,
	SurfaceFrame = ScopedSurface,
	--- The atomic press/hover/activate primitive. `PressableFrame` is the former
	--- name, kept as an alias for Layer 4 consumers that still spell it that way.
	---
	--- There is deliberately NO `Button` here (ms-51 M14): a button is a visual
	--- affordance, and Layer 2 does not decide affordances. The presentational one
	--- is `spektr/button` in the components tier, which embeds this.
	Pressable = Pressable,
	PressableFrame = Pressable,
	WindowTopbar = PrimitiveWindowTopbar,
	TextInput = TextInput,
	TextInputFrame = TextInput,
	Combobox = Combobox,
	ContextMenu = ContextMenu,
	Tooltip = Tooltip,
	ScrollArea = ScrollArea,
	ScrollBar = PrimitiveScrollbar,
	Scrollbar = PrimitiveScrollbar,
	ScrollingFrame = ScrollingFrame,
	VirtualList = VirtualList,
	TreeView = TreeView,
	Text = Text,
}

-- Domain 4: Compound UI Assemblies
local Assemblies = {
	ScrollingFrame = ScrollingFrame,
}

return {
	-- Layer & Domain Namespaces
	Controllers = Controllers,
	Core = Core,
	Host = Host,
	Motion = Motion,
	Cursor = Cursor,
	Runtime = Runtime,
	Engine = Engine,
	Primitives = Primitives,
	Assemblies = Assemblies,

	-- Top-Level Ergonomic Shortcuts
	SelectionModel = SelectionModel,
	TreeController = TreeController,
	ScrollController = ScrollController,
	createPressable = createPressable,
	For = For,
	KeyedList = For,
	ScopedSurface = ScopedSurface,
	SurfaceFrame = ScopedSurface,
	Pressable = Pressable,
	PressableFrame = Pressable,
	TextInput = TextInput,
	TextInputFrame = TextInput,
	TextInputManager = TextInputManager,
	Combobox = Combobox,
	ContextMenu = ContextMenu,
	Tooltip = Tooltip,
	WindowTopbar = PrimitiveWindowTopbar,
	ScrollArea = ScrollArea,
	ScrollBar = PrimitiveScrollbar,
	Scrollbar = PrimitiveScrollbar,
	ScrollingFrame = ScrollingFrame,
	VirtualList = VirtualList,
	TreeView = TreeView,
	Styled = if PrimitiveScrollbar then PrimitiveScrollbar.Styled else nil,
	PointerRouter = PointerRouter,
	--- NOTE (ms-51 M14): top-level `Pressable` is the PRIMITIVE, above. The
	--- router's low-level registration function of the same name used to be
	--- exported here too and, being declared later, silently won the key. It is
	--- reachable as `Aether.PointerRouter.Pressable` and `Aether.Engine.Pressable`,
	--- which is how every call site in the monorepo already spells it.
	ScopeProvider = if ScopeContext then ScopeContext.ScopeProvider else nil,
	ScopeContext = if ScopeContext then ScopeContext.ScopeContext else nil,
	useScope = if ScopeContext then ScopeContext.useScope else nil,
	InputScope = InputScope,
	InputSink = InputSink,
	LayerManager = LayerManager,
	useHover = useHover,
	Text = Text,
	ScreenCoords = ScreenCoords,
	Presence = Presence,
	useDisclosure = useDisclosure,
	useSelection = useSelection,
	Stagger = Stagger,
	ScreenStack = ScreenStack,
	TransitionOrchestrator = TransitionOrchestrator,
	FloatingMath = FloatingMath,
	useFloating = useFloating,
	Icon = Icon,
}
