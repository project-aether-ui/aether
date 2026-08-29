--!strict
-- Aether Headless UI Framework
-- Decoupled into 5-Layer Universal Architecture:
-- 1. Controllers (Pure State Machines)
-- 2. Core (Headless Interaction Protocols)
-- 3. Engine (Arbitration & IO)
-- 4. Primitives (Host-Resolved Structural Skeletons)
-- 5. Runtime (Reactive Control Flow)
--
-- PLAIN STRING REQUIRES, ONE SPELLING FOR EVERY HOST.
--
-- This file used to reach each submodule through a `loadSubmodule` helper that
-- took an Instance for Roblox and a path for everywhere else, then fell back
-- through two or three candidate paths with `pcall` when neither resolved. Two
-- dozen call sites, each naming the same module twice.
--
-- It bought nothing that require-by-string does not: Roblox resolves `./host/Host`
-- against this script's place in the DataModel, every other runtime resolves it
-- against this file's place on disk, and the Rojo tree mirrors the directory
-- tree, so the two agree by construction.
--
-- IT ALSO COST SOMETHING REAL. A `pcall(require, ...)` that fails returns nil and
-- says nothing, so a module renamed on disk became a nil export rather than an
-- error, and the first symptom was a nil index somewhere downstream. A missing
-- module is now a load error naming the module.

local Icon = require("./Icon/src/Icon")

local SelectionModel = require("./controllers/SelectionModel")
local TreeController = require("./controllers/TreeController")
local ScrollController = require("./controllers/ScrollController")
local createPressable = require("./core/createPressable").createPressable

local LayerManager = require("./LayerManager")
local Text = require("./Text")
local InputSink = require("./InputSink")
local InputScope = require("./InputScope")
local PointerRouter = require("./PointerRouter")
local Pressable = require("./primitives/Pressable")
local ScreenStack = require("./ScreenStack")
local TransitionOrchestrator = require("./TransitionOrchestrator")
local useHover = require("./useHover")
local ScreenCoords = require("./ScreenCoords")
local For = require("./For")
local ScopeContext = require("./ScopeContext")
local ScopedSurface = require("./ScopedSurface")
local TextInput = require("./TextInput")
local TextInputManager = require("./TextInputManager")
local FloatingMath = require("./FloatingMath")
local useFloating = require("./useFloating")
local Presence = require("./Presence")
local useDisclosure = require("./useDisclosure")
local useSelection = require("./useSelection")
local Stagger = require("./Stagger")
local Combobox = require("./primitives/Combobox")
local ContextMenu = require("./primitives/ContextMenu")
local Tooltip = require("./primitives/Tooltip")
local ScrollArea = require("./primitives/ScrollArea")
local PrimitiveScrollbar = require("./primitives/Scrollbar")
local PrimitiveWindowTopbar = require("./primitives/WindowTopbar")
local ScrollingFrame = require("./primitives/ScrollingFrame")
local VirtualList = require("./primitives/VirtualList")
local TreeView = require("./primitives/TreeView")

--- Layer 2.5. Exported so packages ABOVE Aether can build on the same host —
--- notably so they can take real vide headlessly instead of a shim.
local Motion = require("./Motion")
--- The cursor seam (ms-51 M19). Exported so the package that OWNS the cursor
--- can register itself, which is what replaced Aether depending on it.
local Cursor = require("./Cursor")
local Host = require("./host/Host")

--- THE REACTIVE SURFACE AND THE VALUE VOCABULARY, exported from the root.
---
--- These lived only in `Deps`, so every component author had to require a module
--- whose name says "the internal place this package resolves its own
--- dependencies" in order to obtain `create` and `source` — the two things they
--- reach for first. A public need served by a private-sounding door.
---
--- Re-exported rather than moved: `Deps` is still where the resolution happens
--- and still what the framework's own modules use. This is the front of it.
local Deps = require("./Deps")

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
	-- The reactive surface. One require gets an author everything they build with.
	create = Deps.create,
	source = Deps.source,
	derive = Deps.derive,
	effect = Deps.effect,
	read = Deps.read,
	batch = Deps.vide and Deps.vide.batch,
	untrack = Deps.untrack,
	spring = Deps.spring,
	cleanup = Deps.cleanup,
	peek = Deps.peek,

	--- UDim2, Color3, Vector2, Enum and the rest, from the HOST. On Roblox these
	--- are the engine's; off-engine they are the pure implementations. Named here
	--- so an author can bind them explicitly instead of relying on whatever the
	--- host installed as globals.
	Vocabulary = Deps.Vocabulary,

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
