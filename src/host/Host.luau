--!strict
--[[
	Aether · Host — Layer 2.5, the platform adapter boundary.

	The architecture (D-aether_framework_taxonomy_and_package_migration) puts a
	resolver layer between the headless protocols and the concrete target:

	    Layer 2    Aether.Core        abstract behaviour, no Instance anywhere
	    Layer 2.5  Aether.Host.*      <- HERE: binds abstract geometry to a target
	    Layer 3    Flux               motion
	    Layer 4    StudioUI, kits     visual expression

	A Host answers two things, and it is worth being precise about which is which
	because only the second is novel:

	  1. THE VIDE SURFACE. `create`, `cleanup`, `mount`, `spring` and the reactive
	     core. On Roblox these are vide's own. Off-engine, sixteen of the
	     twenty-three vide modules still load unmodified — the reactive core is
	     pure Luau — and the Host supplies the seven that do not. VideCore.luau
	     carries the measurement and the reason the split lands exactly there.

	  2. THE GEOMETRY CONTRACT. `Resolve(target) -> GeometrySource`, turning a
	     concrete target into { GetBounds, GetZIndex, IsVisible }. This is the
	     coupling that currently stops Layer 2 algorithms from running off-engine:
	     they read `AbsolutePosition` off a GuiObject directly.

	SELECTION IS BY CAPABILITY, never by configuration. `Host.detect()` returns
	the DataModel host when the environment supplies a DataModel this framework can
	drive, and the Luau test double otherwise. There is no flag to force the wrong
	one, because every bug in this area has been a path that silently took the
	wrong branch.

	IT USED TO SELECT BY VENDOR -- `typeof(game) == "Instance"` -- and
	DataModel.luau carries the argument for why that changed on 2026-09-04. The
	short version is ADR-001's: there are two implementations of the standard,
	Roblox in C++ and Dew in Rust, and a framework that runs on any conforming host
	should not decide by looking for the name of one of them.
]]

--- NOT `host/init.luau`. Lune resolves a DIRECTORY require by loading init.luau
--- but resolving that file's own relative requires from the CALLER's directory,
--- so `./DataModel` looked for a sibling of whoever required the folder. As a named
--- file this is required by path and its siblings resolve normally.
local DataModelHost = require("./DataModel")
local LuauDataModelHost = require("./LuauDataModel")
local VideCore = require("./VideCore")

export type Bounds = { X: number, Y: number, Width: number, Height: number }

--- What Layer 2 is allowed to know about a thing's place on screen.
export type GeometrySource = {
	GetBounds: () -> Bounds,
	GetZIndex: () -> number,
	IsVisible: () -> boolean,
}

--- Frames and time. The whole temporal surface, deliberately four members.
export type Clock = {
	Name: string,
	--- Subscribe to frames. Returns an unsubscribe.
	OnFrame: (fn: (dt: number) -> ()) -> () -> (),
	--- Seconds. Wall-clock in-engine, accumulated simulated time headlessly.
	Now: () -> number,
	--- Advance one frame BY HAND. A no-op in-engine, where the Heartbeat already
	--- drives them and stepping would run each frame twice.
	Step: (dt: number) -> (),
}

--- The value vocabulary — coordinates, colours, sequences, enums.
---
--- es9: a single interface regardless of host. These are NOT deeply Roblox types
--- — UDim2 is {scale, offset} per axis, Color3 is three floats — so a non-Roblox
--- host implements the same names rather than translating away from them. The
--- Roblox host hands back the engine's own globals; the headless host hands back
--- Lune's real implementations, so arithmetic is identical in both.
export type Vocabulary = {
	UDim: any,
	UDim2: any,
	Vector2: any,
	Color3: any,
	Rect: any,
	NumberSequence: any,
	NumberSequenceKeypoint: any,
	ColorSequence: any,
	ColorSequenceKeypoint: any,
	Font: any,
	Enum: any,
}

--- What Layer 2 may ask about a node in the tree.
---
--- STATELESS, and that is a performance decision rather than a style one.
--- Hit-testing walks every candidate on every pointer move, so a wrapper object
--- per node would allocate a table per query — the exact shape a previous
--- measurement in this repo took from 121ns to 65ns per visit by removing.
--- `Bounds` returns four numbers rather than a rectangle for the same reason.
---
--- This is `GeometrySource` grown into what the algorithms actually need.
--- Measured against HitTest, PointerRouter, InputScope and useFloating, a
--- rectangle was nowhere near enough: 28 parent traversals, 23 visibility reads,
--- 13 ZIndex, 9 class queries, 9 DisplayOrder, 7 LayerCollector. Occlusion,
--- clipping and render order are questions about a TREE, so the contract has to
--- describe one.
export type Scene = {
	Name: string,
	Bounds: (target: any) -> (number, number, number, number),
	--- Layout inputs: what the AUTHOR asked for, as opposed to where the
	--- element ended up. A solver needs the request; a hit test needs the
	--- result.
	Raw: (target: any, key: string) -> any,
	Children: (target: any) -> { any },
	ClassOf: (target: any) -> string?,
	Name: (target: any) -> string?,
	ZIndex: (target: any) -> number,
	IsVisible: (target: any) -> boolean,
	Parent: (target: any) -> any,
	ChildIndex: (target: any) -> number,
	Clips: (target: any) -> boolean,
	IsLayerRoot: (target: any) -> boolean,
	IsSurface: (target: any) -> boolean,
	DisplayOrder: (target: any) -> number,
	IsEnabled: (target: any) -> boolean,
	Attribute: (target: any, name: string) -> any,
	RenderedCorner: (target: any) -> (number?, number?),
}

export type Host = {
	Name: string,
	--- WHICH ENVIRONMENT SUPPLIED THE HOST SERVICES, and not a second name for
	--- the host. `Name` says what is being driven -- "DataModel", or
	--- "LuauDataModel" for the test double -- and is the same on every
	--- environment providing one, which is the whole claim. This says where
	--- `Text` and `Clock` came from: "Roblox", "Dew", or "Luau".
	---
	--- IT EXISTS TO BE ASSERTED. Which branch `detect` took is invisible in a
	--- rendered tree -- both hosts draw the same widget correctly -- so a suite
	--- that wants to know has to be told by name rather than shown pixels.
	Environment: string,

	-- Reactive core (Layer 2)
	source: any,
	derive: any,
	effect: any,
	root: any,
	batch: any,
	untrack: any,
	read: any,
	action: any,

	-- Host-resolved construction (Layer 2.5)
	create: any,
	cleanup: any,
	spring: any,
	mount: any,

	-- Host services
	Scene: Scene,
	--- How wide is this string. Synchronous by contract: `Layout.Solve` runs
	--- inside a frame and cannot await, which is what rules out asking a display
	--- mid-solve however exact that would be. See D-text_metrics_provider.
	Text: {
		Measure: (text: string, size: number, font: string?) -> (number, number),
		MeasureDefault: (text: string, size: number, font: string?) -> (number, number),
		SetProvider: (provider: any, owner: string?) -> boolean,
		HasProvider: () -> boolean,
	},
	Clock: Clock,
	Vocabulary: Vocabulary,
	Instance: any,
	typeof: (any) -> string,
	classOf: (any) -> string?,
	SetBounds: (target: any, x: number, y: number, w: number, h: number) -> (),
	Resolve: (target: any) -> GeometrySource,
}

local Host = {}

Host.DataModel = DataModelHost
Host.LuauDataModel = LuauDataModelHost
Host.VideCore = VideCore

local detected: Host? = nil

--- The host for the environment we are actually in.
---
--- Memoised: both hosts are stateless per process apart from the vide handle,
--- and building a fresh one per call would hand two call sites different
--- `Instance.new` identities headlessly — which is the kind of split-brain that
--- makes a mock tree look correct and compare unequal.
function Host.detect(vide: any?): Host
	if detected then
		return detected
	end
	if DataModelHost.available() then
		detected = DataModelHost.new(vide) :: any
	else
		detected = LuauDataModelHost.new() :: any
	end
	return detected :: Host
end

--- Testing seam: drop the memoised host so a suite can build a clean tree.
function Host._reset()
	detected = nil
end

return Host
