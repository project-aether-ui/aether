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
local createCheckbox = require("./core/createCheckbox").createCheckbox
local createRadioGroup = require("./core/createRadioGroup").createRadioGroup
local createTabs = require("./core/createTabs").createTabs
local createContextMenu = require("./core/createContextMenu").createContextMenu

local LayerManager = require("./LayerManager")
local Text = require("./Text")
local InputSink = require("./InputSink")
local InputScope = require("./InputScope")
local PointerRouter = require("./PointerRouter")
local SelectionRouter = require("./SelectionRouter")
local Pressable = require("./primitives/Pressable")
local Checkbox = require("./primitives/Checkbox")
local Tabs = require("./primitives/Tabs")
local RadioGroup = require("./primitives/RadioGroup")
local ScreenStack = require("./ScreenStack")
local TransitionOrchestrator = require("./TransitionOrchestrator")
local useHover = require("./useHover")
local ScreenCoords = require("./ScreenCoords")
local For = require("./For")
local ScopeContext = require("./ScopeContext")
local ScopedSurface = require("./ScopedSurface")
local TextInput = require("./TextInput")
local TextInputManager = require("./TextInputManager")
local FloatingMath = require("./core/FloatingMath")
local useFloating = require("./useFloating")
local Presence = require("./core/Presence")
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
local Motion = require("./core/Motion")
--- The cursor seam (ms-51 M19). Exported so the package that OWNS the cursor
--- can register itself, which is what replaced Aether depending on it.
local Cursor = require("./core/Cursor")
local Host = require("./host/Host")
local TooltipMachine = require("./core/TooltipMachine")
local VirtualWindow = require("./core/VirtualWindow")

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
--- THE LAYER 1 MACHINES A CONSUMER CAN REACH.
---
--- `TooltipMachine` and `VirtualWindow` were added under `src/core/` by milestone
--- 7 and listed nowhere: not here, not at the top level. Two modules shipped that
--- no consumer could require, found when a demo tried to use one.
local Core = {
	createPressable = createPressable,
	createCheckbox = createCheckbox,
	createRadioGroup = createRadioGroup,
	createTabs = createTabs,
	createContextMenu = createContextMenu,
	ScrollController = ScrollController,
	TooltipMachine = TooltipMachine,
	VirtualWindow = VirtualWindow,
}

-- Domain 1: Reactive Runtime & Control Flow
local Runtime = {
	For = For,
	KeyedList = For,
	--- MOVED HERE FROM `Primitives`. `VirtualList` owns no interaction state
	--- of its own -- its windowing arithmetic already lives in
	--- `core/VirtualWindow` and the sibling `spektr/virtual` package, both
	--- framework-free and headless-testable on their own, and what stays in
	--- this file is only instance pooling, mounting and positioning over
	--- whichever supplies the numbers. That is a rendering-economy tool, the
	--- same job `For` already does, not a Checkbox-shaped interaction
	--- primitive.
	VirtualList = VirtualList,
}

-- Domain 2: Arbitration & Interaction Engines
local Engine = {
	PointerRouter = PointerRouter,
	SelectionRouter = SelectionRouter,
	--- NO `Pressable` HERE ANY MORE (milestone 54 sprint 4). This used to be
	--- `PointerRouter.Pressable`, the router's raw registration function,
	--- sharing a name with `Aether.Pressable` (the Primitive) and disambiguated
	--- only by which of the five internal layers a consumer happened to pull
	--- from -- exactly the confusion this sprint's own collapse exists to
	--- remove. A grep across this repository and every known consumer found
	--- no call site actually reaching it through `Engine.Pressable`; the raw
	--- function is still reachable, unambiguously, as `PointerRouter.Pressable`
	--- directly.
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
	Checkbox = Checkbox,
	Tabs = Tabs,
	RadioGroup = RadioGroup,
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
	--- NO `createX` SHORTCUTS HERE ANY MORE (milestone 54 sprint 4). Every one
	--- of the five machines this milestone covers had three names a consumer
	--- could reach it by: `Aether.createCheckbox` (this shortcut), `Aether.Core
	--- .createCheckbox` (the same function, namespaced), and `Aether.Checkbox`
	--- (the Primitive) -- organized by which internal layer implemented it
	--- rather than by what a consumer was building. One name survives at the
	--- top level per widget, the Primitive, since that is the one built for a
	--- consumer to reach for directly; `Aether.Core.createCheckbox` and its
	--- neighbours are still there for whoever is building a bespoke widget
	--- straight on top of Layer 1, just not duplicated up here beside it.
	SelectionModel = SelectionModel,
	TreeController = TreeController,
	ScrollController = ScrollController,
	For = For,
	KeyedList = For,
	ScopedSurface = ScopedSurface,
	SurfaceFrame = ScopedSurface,
	Pressable = Pressable,
	PressableFrame = Pressable,
	Checkbox = Checkbox,
	Tabs = Tabs,
	RadioGroup = RadioGroup,
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
	SelectionRouter = SelectionRouter,
	--- NOTE (ms-51 M14, resolved milestone 54 sprint 4): top-level `Pressable`
	--- is the PRIMITIVE, above. The router's low-level registration function of
	--- the same name used to be exported here too and, being declared later,
	--- silently won the key -- fixed at the time by moving it to `Engine
	--- .Pressable` instead, which only renamed the collision rather than
	--- removing it (`Aether.Pressable` the Primitive and `Aether.Engine
	--- .Pressable` the raw function still shared a word, one layer over). It is
	--- reachable as `Aether.PointerRouter.Pressable` now, unambiguously.
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
