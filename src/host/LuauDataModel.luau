--!strict
--[[
	Aether · host/LuauDataModel — Layer 2.5 resolver for "no engine at all".

	WHAT THIS IS, AND WHAT IT IS NOT. Renamed from `Headless.luau` on 2026-09-04,
	for two reasons. The first is that "headless" already means something else in
	this framework — a headless PRIMITIVE is behaviour without styling, which is
	most of what `src/primitives/` is, and the collision was ours. The second
	matters more.

	**THIS IS jsdom, NOT A BROWSER.** It is a test double for a DataModel. You
	would not call a JavaScript app running under jsdom a browser experience, and
	nothing here is a description of how a DataModel is supposed to behave.

	    IMPLEMENTATIONS OF THE STANDARD   Roblox (C++)      Dew (Rust)
	    THIS                              a test double, and downstream of both

	**ITS SHAPE FOLLOWS THE APPLICATION HOSTS, NEVER THE REVERSE.** If this file
	and a real host disagree, this file is wrong by definition. Do not read it to
	learn what a DataModel does, do not implement against it, and do not cite it in
	a conformance case as evidence of anything — the suite already encodes this,
	which is why `provenance = "reference"` means *recorded from the Luau
	implementation, regression only: says we have not changed, not that we are
	right*. Only the engine promotes a case.

	It archives out of this repository to `OSS/luau-datamodel/` under ADR-002 and
	Dew's roadmap step N. It is deliberately not anybody's priority.

	This is a HOST, not a shim. It supplies exactly the seven modules vide cannot
	load outside Roblox — `create`, `apply`, `defaults`, `mount`, `cleanup`,
	`changed`, `lib` — over mock instances, and takes the other sixteen (the
	entire reactive core) from the real installed vide via `VideCore`. See
	VideCore.luau for the measured split and why it lands exactly here.

	WHAT THAT CHANGES versus testkit's VideShim, which this replaces:

	    VideShim                        LuauDataModel
	    ------------------------------  ------------------------------------
	    effect runs ONCE, no tracking   effect IS vide's effect: tracks + re-runs
	    derive re-evaluates on read     derive IS vide's derive: memoised
	    create returns the props table  create returns a mock instance
	    no scopes                       real vide scopes, per-instance teardown

	The first two are why a suite written against the shim could not observe a
	re-render. Aether's own TreeView suite documents having to route around it.

	COMPATIBILITY WITH SUITES WRITTEN AGAINST THE SHIM. The shim's `create`
	returned the props table, so existing suites read properties by name off the
	result, read children by array index, and check `_ClassName`. A mock instance
	here keeps ALL THREE of those shapes: properties are raw fields, children live
	in the array part so `ipairs`/`[1]`/`#` work, and both `ClassName` and
	`_ClassName` answer. That is deliberate — the point is to raise fidelity
	without rewriting every suite in the monorepo.

	WHERE IT IS STILL LESS THAN AN ENGINE, stated here rather than discovered:
	  * No layout and no rendering. `AbsolutePosition`/`AbsoluteSize` are whatever
	    a test sets (see `SetBounds`); nothing computes them.
	  * `spring` settles immediately — it returns the target. There is no clock
	    headlessly. The SETTINGS HANDLE is real, because ms-43 M46 depends on
	    seeding a spring's position.
	  * No RBXScriptSignals, so a function-valued property is ALWAYS a reactive
	    binding here. In-engine, vide would route it to `:Connect` when the
	    property is an event.
]]

local VideCore = require("./VideCore")

local Headless = {}

export type Bounds = { X: number, Y: number, Width: number, Height: number }

--- Class ancestry, child -> parent. Only what hit-testing and layout code
--- actually asks `IsA` about; unknown classes answer only to their own name and
--- to "Instance".
local ANCESTRY: { [string]: string } = {
	Frame = "GuiObject",
	ScrollingFrame = "GuiObject",
	CanvasGroup = "GuiObject",
	TextLabel = "GuiObject",
	TextButton = "GuiObject",
	TextBox = "GuiObject",
	ImageLabel = "GuiObject",
	ImageButton = "GuiObject",
	VideoFrame = "GuiObject",
	ViewportFrame = "GuiObject",
	GuiObject = "GuiBase2d",
	GuiBase2d = "Instance",

	ScreenGui = "LayerCollector",
	SurfaceGui = "LayerCollector",
	BillboardGui = "LayerCollector",
	LayerCollector = "GuiBase2d",

	UIListLayout = "UILayout",
	UIGridLayout = "UILayout",
	UIPageLayout = "UILayout",
	UITableLayout = "UILayout",
	UILayout = "UIComponent",
	UIPadding = "UIComponent",
	UICorner = "UIComponent",
	UIStroke = "UIComponent",
	UIGradient = "UIComponent",
	UIScale = "UIComponent",
	UIAspectRatioConstraint = "UIConstraint",
	UISizeConstraint = "UIConstraint",
	UITextSizeConstraint = "UIConstraint",
	UIConstraint = "UIComponent",
	UIComponent = "Instance",
}

--- The GuiObject events component code actually connects to.
---
--- Needed because ACTIONS RUN here (real vide invokes them; VideShim never did),
--- and an action body's whole job is usually to bind to the element it is handed:
--- spektr/scrollbar's `attachTrack` does `ref.InputBegan:Connect(...)`. Without
--- these the action reached a nil event, which is a headless artifact rather than
--- a defect in the component.
---
--- INERT: nothing fires them, because there is no engine to. They exist so
--- construction completes and so a suite can assert that a component CONNECTED,
--- which is a different question from whether the handler ever runs.
local EVENTS: { [string]: boolean } = {
	InputBegan = true,
	InputChanged = true,
	InputEnded = true,
	MouseEnter = true,
	MouseLeave = true,
	MouseMoved = true,
	MouseWheelForward = true,
	MouseWheelBackward = true,
	Activated = true,
	MouseButton1Click = true,
	MouseButton1Down = true,
	MouseButton1Up = true,
	MouseButton2Click = true,
	TouchTap = true,
	SelectionGained = true,
	SelectionLost = true,
	AncestryChanged = true,
	ChildAdded = true,
	ChildRemoved = true,
	Destroying = true,
	Changed = true,
	FocusLost = true,
	Focused = true,
}

export type MockInstance = any

--- Per-instance bookkeeping, held OUTSIDE the instance.
---
--- It used to be a `__shadow` field on the table, and that was a real defect
--- rather than untidiness: suites walk these trees with `pairs`, the shadow holds
--- a `Parent` BACK-REFERENCE, and a recursive walk therefore recursed forever —
--- WindowTopbar's `findNamed` overflowed the stack on the first tree it was given.
---
--- Keeping it in a weak-keyed side table means a mock instance iterates as
--- exactly what it models: string properties and array children, nothing else.
--- That is also what the props tables these suites were written against looked
--- like, so the compatibility is not a coincidence — it is the point.
local SHADOWS: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any

local function isMock(v: any): boolean
	return type(v) == "table" and SHADOWS[v] ~= nil
end

Headless.isMockInstance = isMock

--- Every mock instance shares one metatable. Properties and children are RAW
--- fields on the instance itself (hash part and array part respectively), so the
--- common reads cost no metamethod and behave exactly like the props table that
--- suites were written against. The metatable carries only the methods and the
--- two fields we must intercept.
local InstanceMT = {}

local function shadow(self: any): any
	return SHADOWS[self]
end

InstanceMT.__index = function(self: any, key: any): any
	local sh = SHADOWS[self]
	local sv = sh[key]
	if sv ~= nil then
		return sv
	end
	if EVENTS[key] then
		local signal = sh.signals[key]
		if not signal then
			signal = {
				_listeners = {},
				Connect = function(self: any, fn: any)
					table.insert(self._listeners, fn)
					return {
						Connected = true,
						Disconnect = function(conn: any)
							conn.Connected = false
						end,
					}
				end,
				Once = function(self: any, fn: any)
					return self:Connect(fn)
				end,
				Wait = function() end,
				--- How many listeners a component attached. The one thing about an
				--- inert signal that is still worth asserting.
				_ListenerCount = function(self: any): number
					return #self._listeners
				end,
			}
			sh.signals[key] = signal
		end
		return signal
	end
	return InstanceMT.methods[key]
end

InstanceMT.__newindex = function(self: any, key: any, value: any)
	if key == "Parent" then
		local sh = SHADOWS[self]
		local old = sh.Parent
		if old ~= nil and isMock(old) then
			for i, child in ipairs(old) do
				if child == self then
					table.remove(old, i)
					break
				end
			end
		end
		sh.Parent = value
		if value ~= nil and isMock(value) then
			table.insert(value, self)
		end
		return
	end
	rawset(self, key, value)
end

InstanceMT.__tostring = function(self: any): string
	return `MockInstance<{rawget(self, "ClassName")}>`
end

InstanceMT.methods = {
	Destroy = function(self: any)
		local sh = shadow(self)
		for _, destroy in ipairs(sh.scopes) do
			pcall(destroy)
		end
		table.clear(sh.scopes)
		for _, child in ipairs(table.clone(self)) do
			if isMock(child) then
				child:Destroy()
			end
		end
		self.Parent = nil
		sh.destroyed = true
	end,

	GetChildren = function(self: any): { any }
		return table.clone(self)
	end,

	GetDescendants = function(self: any): { any }
		local out = {}
		local function walk(node: any)
			for _, child in ipairs(node) do
				table.insert(out, child)
				if isMock(child) then
					walk(child)
				end
			end
		end
		walk(self)
		return out
	end,

	FindFirstChild = function(self: any, name: string): any?
		for _, child in ipairs(self) do
			if isMock(child) and rawget(child, "Name") == name then
				return child
			end
		end
		return nil
	end,

	FindFirstChildOfClass = function(self: any, class: string): any?
		for _, child in ipairs(self) do
			if isMock(child) and rawget(child, "ClassName") == class then
				return child
			end
		end
		return nil
	end,

	FindFirstAncestorOfClass = function(self: any, class: string): any?
		local cur = self.Parent
		while cur ~= nil and isMock(cur) do
			if rawget(cur, "ClassName") == class then
				return cur
			end
			cur = cur.Parent
		end
		return nil
	end,

	--- Walks ANCESTRY. An unknown class still answers to its own name and to
	--- "Instance", which keeps a stand-in usable without registering it here.
	IsA = function(self: any, query: string): boolean
		local cur: string? = rawget(self, "ClassName")
		while cur do
			if cur == query then
				return true
			end
			cur = ANCESTRY[cur]
		end
		return query == "Instance"
	end,

	GetAttribute = function(self: any, name: string): any
		return shadow(self).attributes[name]
	end,

	SetAttribute = function(self: any, name: string, value: any)
		shadow(self).attributes[name] = value
	end,

	GetAttributes = function(self: any): { [string]: any }
		return table.clone(shadow(self).attributes)
	end,

	--- Inert by design: there is no engine to fire it. Returning a connectable
	--- object rather than nil keeps component code that connects on construction
	--- from erroring headlessly.
	--- A REAL SIGNAL (ms-53 D8). This returned a stub whose `Connect` handed back
	--- an already-disconnected handle, so anything driven by property changes was
	--- silently inert off-engine while working perfectly in a place.
	---
	--- es9 found the consequence: the shop's scrollbar was invisible in the native
	--- window and drawn in Roblox. `spektr/scrollbar` syncs its viewport and canvas
	--- extents through `GetPropertyChangedSignal("AbsoluteSize")` and
	--- `("AbsoluteCanvasSize")`, so off-engine that sync ran exactly ONCE -- at
	--- build time, before any layout existed -- concluded the canvas (100) did not
	--- exceed the viewport (100), and hid the bar for the rest of the process.
	---
	--- A dead signal is worse than a missing one: `Subscribe` returns a disconnect
	--- function and the caller has every reason to believe it is connected.
	GetPropertyChangedSignal = function(self: any, property: string): any
		local sh = SHADOWS[self]
		if not sh then
			return {
				Connect = function()
					return { Disconnect = function() end, Connected = false }
				end,
				Once = function()
					return { Disconnect = function() end, Connected = false }
				end,
				Wait = function() end,
			}
		end
		sh.signals[property] = sh.signals[property] or {}
		local listeners = sh.signals[property]
		return {
			Connect = function(_selfSignal: any, fn: (() -> ())?)
				--- Both spellings: `sig:Connect(fn)` passes the signal as the first
				--- argument, `sig.Connect(fn)` does not.
				local callback = if type(_selfSignal) == "function" then _selfSignal else fn
				if type(callback) ~= "function" then
					return { Disconnect = function() end, Connected = false }
				end
				table.insert(listeners, callback)
				local connected = true
				return {
					Connected = true,
					Disconnect = function()
						if not connected then
							return
						end
						connected = false
						local i = table.find(listeners, callback)
						if i then
							table.remove(listeners, i)
						end
					end,
				}
			end,
			Once = function(_selfSignal: any, fn: (() -> ())?)
				local callback = if type(_selfSignal) == "function" then _selfSignal else fn
				if type(callback) ~= "function" then
					return { Disconnect = function() end, Connected = false }
				end
				local wrapper
				wrapper = function()
					local i = table.find(listeners, wrapper)
					if i then
						table.remove(listeners, i)
					end
					callback()
				end
				table.insert(listeners, wrapper)
				return {
					Connected = true,
					Disconnect = function()
						local i = table.find(listeners, wrapper)
						if i then
							table.remove(listeners, i)
						end
					end,
				}
			end,
			Wait = function() end,
		}
	end,

	Clone = function(self: any): any
		error("MockInstance:Clone is not implemented by Aether.Host.LuauDataModel", 2)
	end,
}

--- Build the host. A fresh instance-space per call, so two suites in one process
--- cannot reach each other through it.
function Headless.new(): any
	local core = VideCore.load()
	if not core then
		error(
			"Aether.Host.LuauDataModel: no installed vide reachable. Run `pesde install` in "
				.. "the repository root, or add this version to VideCore.CANDIDATE_ROOTS.",
			2
		)
	end

	local _action, is_action = core.action()

	--- Is this an action, INCLUDING one a package could not build with vide's own
	--- constructor?
	---
	--- vide marks actions with a private metatable, so `is_action` only recognises
	--- actions made by the SAME vide instance. A rank-0 package like spektr/surface
	--- may not depend on anything that could hand it one, so its headless fallback
	--- emits the structure instead. Duck-typing it here is what lets such a package
	--- stay dependency-free without silently losing action semantics — the
	--- alternative is the array-part function being read as a reactive children
	--- binding and invoked with no arguments, which is exactly the defect this
	--- found in Surface.
	local function isActionLike(v: any): boolean
		if is_action(v) then
			return true
		end
		return type(v) == "table"
			and not isMock(v)
			and type(rawget(v, "callback")) == "function"
			and type(rawget(v, "priority")) == "number"
	end

	local function newInstance(className: string): MockInstance
		local inst = setmetatable({}, InstanceMT)
		rawset(inst, "ClassName", className)
		--- Both spellings answer. `_ClassName` is what the shim wrote and what
		--- five suites already assert against; dropping it would break them for
		--- no gain.
		rawset(inst, "_ClassName", className)
		rawset(inst, "Name", className)
		--- A ZERO RECTANGLE, not nil (ms-52 M5).
		---
		--- In Roblox every GuiObject always has an AbsolutePosition and an
		--- AbsoluteSize -- zero before the engine lays out, never absent. Here they
		--- appeared only once something called `SetBounds`, so any code that read
		--- geometry during CONSTRUCTION got nil and indexed it.
		---
		--- That is not a hypothetical: spektr/scrollbar reads `AbsoluteSize` in its
		--- property sync, which runs while the tree is being built, and a real
		--- ShopUI screen died there -- `attempt to index nil with 'Y'` -- long
		--- before it could be laid out. Matching the engine's guarantee is cheaper
		--- and more honest than teaching every consumer to guard.
		rawset(inst, "AbsolutePosition", { X = 0, Y = 0 })
		rawset(inst, "AbsoluteSize", { X = 0, Y = 0 })
		--- A ScrollingFrame additionally always carries a canvas. spektr/scrollbar
		--- reads `CanvasPosition` in the same construction-time sync, so leaving it
		--- absent moved the failure one line rather than fixing it.
		if className == "ScrollingFrame" then
			rawset(inst, "CanvasPosition", { X = 0, Y = 0 })
			rawset(inst, "AbsoluteCanvasSize", { X = 0, Y = 0 })
		end
		SHADOWS[inst] = {
			Parent = nil :: any,
			signals = {} :: { [string]: any },
			attributes = {} :: { [string]: any },
			scopes = {} :: { () -> () },
			destroyed = false,
		}
		return inst
	end

	--- vide's own dispatch, from apply.luau, with two host substitutions:
	---   * a CHILD is a mock instance (a table), where in-engine it is userdata;
	---   * a function-valued property is always a binding, never `:Connect`,
	---     because there are no signals here.
	--- Everything else — nested property tables applied to the SAME instance,
	--- actions deferred until after properties, `Parent` applied last — matches.
	local function processProperties(props: any, inst: MockInstance, cache: any)
		for key, value in props do
			if type(key) == "string" then
				if key == "Parent" then
					cache.parent = value
				elseif type(value) == "function" then
					if EVENTS[key] then
						--- vide routes a function-valued property to `:Connect` when
						--- the property is an event, and to an implicit effect
						--- otherwise. Mirrored — without this, `{ Activated = fn }`
						--- would be CALLED once with no arguments instead of
						--- connected, which is a silent behaviour change from the
						--- engine rather than a missing feature.
						local signal = (inst :: any)[key]
						signal:Connect(value)
					else
						table.insert(cache.bindings, function()
							core.effect(function()
								rawset(inst, key, value())
							end)
						end)
					end
				else
					rawset(inst, key, value)
				end
			elseif type(key) == "number" then
				if type(value) == "function" then
					--- Reactive children binding. vide re-parents the returned
					--- set on each run; here we append what it yields, which is
					--- enough to observe that it ran and what it produced.
					table.insert(cache.bindings, function()
						core.effect(function()
							local produced = value()
							if isMock(produced) then
								produced.Parent = inst
							elseif type(produced) == "table" then
								for _, child in ipairs(produced) do
									if isMock(child) then
										child.Parent = inst
									end
								end
							end
						end)
					end)
				elseif type(value) == "table" then
					if isActionLike(value) then
						table.insert(cache.actions, value)
					elseif isMock(value) then
						value.Parent = inst
					elseif rawget(value, "_ClassName") ~= nil then
						--- An ELEMENT built by some other package's stand-in `create`.
						---
						--- A rank-0 package may not depend on anything that could hand
						--- it this host, so spektr/surface keeps its own minimal
						--- `create` that returns the props table with `_ClassName`
						--- stamped on it. Under vide's rules a plain table in the array
						--- part is a NESTED PROPERTY TABLE applied to the same
						--- instance, so without this discriminator Surface's parts were
						--- flattened INTO their parent and vanished as children —
						--- scrollbar's Track and Thumb disappeared exactly that way.
						---
						--- `_ClassName` is a sound discriminator because a genuine
						--- nested property table never carries one: it is a marker only
						--- an element-producing shim writes.
						table.insert(inst, value)
					else
						processProperties(value, inst, cache)
					end
				end
			end
		end
	end

	local function apply(inst: MockInstance, props: any): MockInstance
		if not props then
			error("attempt to call a constructor returned by create() with no properties", 3)
		end

		local cache = { bindings = {}, actions = {}, parent = nil :: any }
		processProperties(props, inst, cache)

		--- ONE scope per instance, holding every implicit effect it owns.
		---
		--- Real vide binds these into the CALLER's scope. We cannot: suites here
		--- construct primitives outside any `root`, and vide's effect refuses to
		--- run outside a stable scope. Opening a scope per instance keeps the
		--- effects live after construction (verified: they re-run on write) and
		--- gives `Destroy` something exact to tear down.
		if #cache.bindings > 0 then
			local destroy = core.root(function()
				for _, bind in ipairs(cache.bindings) do
					bind()
				end
			end)
			table.insert(shadow(inst).scopes, destroy)
		end

		table.sort(cache.actions, function(a, b)
			return (a.priority or 0) < (b.priority or 0)
		end)
		for _, act in ipairs(cache.actions) do
			local callback = act.callback
			if type(callback) == "function" then
				callback(inst)
			end
		end

		if cache.parent ~= nil then
			if type(cache.parent) == "function" then
				local destroy = core.root(function()
					core.effect(function()
						inst.Parent = cache.parent()
					end)
				end)
				table.insert(shadow(inst).scopes, destroy)
			else
				inst.Parent = cache.parent
			end
		end

		return inst
	end

	local host: any = {}

	--- THE NAME THE FILE ALREADY HAS. It stayed "Headless" through the 2026-09-04
	--- rename, which renamed the module and its export and left the string behind
	--- -- and "Headless" means a primitive without styling everywhere else in this
	--- tree, which is the collision that rename existed to end.
	---
	--- IT IS ALSO EVIDENCE NOW. `Host.detect` chooses between this and the
	--- DataModel host, both draw the same widget correctly, and a suite asking
	--- which one ran reads `Name`. A name that does not match the module is a
	--- misleading answer to the one question this field is for.
	host.Name = "LuauDataModel"

	--- No environment supplied these; this host IS the environment. `Vocabulary`
	--- is Lune's, `Clock` is simulated, and `Text` is the bundled advance table.
	host.Environment = "Luau"

	-- ---- Layer 2: the reactive core, unmodified, straight from vide ----
	host.source = core.source
	host.derive = core.derive
	host.root = core.root
	host.batch = core.batch
	host.untrack = core.untrack
	host.read = core.read
	host.switch = core.switch
	host.show = core.show
	host.indexes = core.indexes
	host.values = core.values
	host.context = core.context
	host.action = _action

	--- vide's effect, with ONE accommodation: an effect created with no enclosing
	--- scope gets its own.
	---
	--- Real vide refuses — `assert_stable_scope` errors — and in-engine that is
	--- correct, because the app is always inside the scope `mount` opened. But
	--- suites here construct primitives bare, and Aether's own components create
	--- effects during construction (VirtualList binds props.Items that way). Under
	--- VideShim that worked because its effect just called the function; under
	--- real vide it errors, which would have meant rewriting every such suite to
	--- wrap in `root`.
	---
	--- So we ask `graph.get_scope()` — an exported query, not an error-message
	--- sniff — and open a scope only when there genuinely is none. The effect is
	--- fully live and tracking either way. Orphan scopes are retained on the host
	--- so they can be counted and torn down; `OrphanScopeCount()` exists so a
	--- suite can assert that a component it expected to be scope-clean is.
	local orphanScopes: { () -> () } = {}

	host.effect = function(fn: any, ...: any)
		if core.graph.get_scope() ~= nil then
			return core.effect(fn, ...)
		end
		local args = table.pack(...)
		local destroy = core.root(function()
			core.effect(fn, table.unpack(args, 1, args.n))
		end)
		table.insert(orphanScopes, destroy)
		return nil
	end

	--- How many effects were created with no enclosing scope. In-engine every one
	--- of these would have needed a real scope to exist in.
	host.OrphanScopeCount = function(): number
		return #orphanScopes
	end

	host.DestroyOrphanScopes = function()
		for _, destroy in ipairs(orphanScopes) do
			pcall(destroy)
		end
		table.clear(orphanScopes)
	end

	-- ---- Layer 2.5: what vide cannot load without an engine ----
	host.create = function(className: string)
		return function(props: any)
			return apply(newInstance(className), props)
		end
	end

	--- vide's cleanup REGISTERS a teardown against the current scope. It does not
	--- run it now.
	---
	--- Getting this wrong is not subtle: an earlier draft here called the task
	--- immediately, and `VirtualList` does `cleanup(unsub)` on its scroll
	--- subscription — so the list unsubscribed from its own controller during
	--- construction and never re-rendered on scroll. Under VideShim that was
	--- invisible, because its cleanup was `function() end`: registering nothing
	--- and running nothing look identical until something depends on the teardown
	--- actually being deferred.
	local orphanCleanups: { () -> () } = {}

	local function asTeardown(task: any): (() -> ())?
		if type(task) == "function" then
			return task
		elseif isMock(task) then
			return function()
				task:Destroy()
			end
		elseif type(task) == "table" then
			local d = (task :: any).destroy or (task :: any).Destroy or (task :: any).Disconnect
			if type(d) == "function" then
				return function()
					d(task)
				end
			end
		end
		return nil
	end

	host.cleanup = function(task: any)
		local teardown = asTeardown(task)
		if not teardown then
			return
		end
		local scope = core.graph.get_scope()
		if scope then
			core.graph.push_cleanup(scope, teardown)
		else
			--- No scope to own it. Held, never called: running it here would be
			--- the bug described above.
			table.insert(orphanCleanups, teardown)
		end
	end

	--- Teardowns registered with no enclosing scope. Held so a suite can run them
	--- deliberately; nothing runs them on its own.
	host.RunOrphanCleanups = function()
		for _, teardown in ipairs(orphanCleanups) do
			pcall(teardown)
		end
		table.clear(orphanCleanups)
	end

	host.OrphanCleanupCount = function(): number
		return #orphanCleanups
	end

	--- REAL SPRINGS, STEPPED BY THE HOST CLOCK (ms-52 M3).
	---
	--- This used to settle immediately, on the grounds that there was no clock.
	--- There is one now, and the consequence of the stand-in outliving its reason
	--- was worse than "no animation": Flux registers as Aether's spring authority
	--- on require, so `Motion.HasSpringDriver()` answered TRUE off-engine and
	--- every smoothed value snapped to its target on the frame it changed. Motion
	--- looked wired up and animated nothing, which is the failure mode a seam is
	--- supposed to make impossible.
	---
	--- vide's spring module is pure arithmetic over `graph`; only its FRAME
	--- SOURCE was ever Roblox-bound. `Clock.Step` drives it below.
	local core = VideCore.load()
	if core and core.spring then
		host.spring = core.spring
	else
		--- The installed vide has no usable spring module. Settle immediately
		--- rather than error, but keep the settings handle real: ms-43 M46
		--- depends on seeding a spring's position, and a test that cannot seed
		--- one passes while the component has silently lost that ability.
		host.spring = function(target: any): (any, any)
			local get = if type(target) == "function" then target else function()
				return target
			end
			local seeded: any = nil
			return get, function(settings: any)
				seeded = if settings then settings.position else nil
				return seeded
			end
		end
	end

	--- No engine to mount into. Parents into the given target when it is a mock,
	--- so a call site that mounts does not have to branch on environment.
	host.mount = function(component: () -> any, target: any?): any
		local result = component()
		if target ~= nil and isMock(result) then
			result.Parent = target
		end
		return result
	end

	host.changed = function(_property: string, _callback: any)
		return { priority = 0, callback = function() end }
	end

	--- THE vide THIS HOST RESOLVED, so `Deps.luau` can take it from whichever
	--- host `Host.detect()` chose rather than choosing one for itself.
	---
	--- THIS HOST IS ITS OWN vide, which is what makes it a test double and not a
	--- host: sixteen modules are the real ones, and the seven behind the engine
	--- gate are written above, over mock instances. A caller asking a host for its
	--- vide is asking "what did the framework end up building with", and here the
	--- honest answer is "these". Assembled by name rather than handing back
	--- `host` itself, so the answer stays the vide surface and does not quietly
	--- include `Scene`, `Resolve` and the rest.
	host.vide = {
		root = host.root,
		mount = host.mount,
		create = host.create,
		source = host.source,
		effect = host.effect,
		derive = host.derive,
		switch = host.switch,
		show = host.show,
		indexes = host.indexes,
		values = host.values,
		cleanup = host.cleanup,
		untrack = host.untrack,
		read = host.read,
		batch = host.batch,
		context = host.context,
		spring = host.spring,
		action = host.action,
		changed = host.changed,
	}

	-- ---- Host services ----

	--- TEXT METRICS (ms-52 M1). The bundled advance table by default; the web host
	--- registers a browser-backed cache over the top of it, which is what makes
	--- accuracy converge without layout ever awaiting.
	host.Text = require("./Text")

	host.Instance = { new = newInstance }

	--- THE CLOCK (ms-51 M16) — simulated, and deliberately so.
	---
	--- There is no engine to drive frames, so time here is whatever a suite says
	--- it is. That is a FEATURE rather than a limitation: motion asserted against
	--- a simulated clock is exact and repeatable, where the same assertion against
	--- a real Heartbeat is a race. `Step(dt)` advances every listener by exactly
	--- dt and `Now()` reports the accumulated total, so a spring's trajectory is
	--- reproducible frame for frame.
	local frameListeners: { (dt: number) -> () } = {}
	local simulatedNow = 0

	host.Clock = {
		Name = "Simulated",

		OnFrame = function(fn: (dt: number) -> ()): () -> ()
			table.insert(frameListeners, fn)
			return function()
				local i = table.find(frameListeners, fn)
				if i then
					table.remove(frameListeners, i)
				end
			end
		end,

		Now = function(): number
			return simulatedNow
		end,

		--- Advance one frame. Snapshots first: a listener may dispose itself, or a
		--- sibling, mid-frame.
		Step = function(dt: number)
			simulatedNow += dt
			--- Springs FIRST, before the frame listeners that read them. vide's
			--- own lib.luau steps them at the top of its Heartbeat handler for
			--- the same reason: a listener that samples a spring this frame
			--- should see this frame's value, not last frame's.
			if core and core.update_springs then
				core.update_springs(dt)
			end
			local batch = table.clone(frameListeners)
			for _, listener in ipairs(batch) do
				listener(dt)
			end
		end,

		--- How many listeners are subscribed. The one thing about a clock nothing
		--- is driving that is still worth asserting.
		_ListenerCount = function(): number
			return #frameListeners
		end,
	}

	--- THE VALUE VOCABULARY (ms-51 M16).
	---
	--- REAL implementations, not mocks. Lune ships working UDim2, Color3, Vector2,
	--- Enum and the sequence types, so headless arithmetic on them is the engine's
	--- arithmetic rather than an approximation of it — which matters, because a
	--- spring interpolating UDim2 is doing real work on these values and a
	--- stand-in that rounded differently would make motion tests lie.
	---
	--- A future non-Roblox host implements the same eleven names. They are not
	--- really Roblox types: UDim2 is {scale, offset} per axis and Color3 is three
	--- floats. Scale-plus-offset positioning is a good idea that happens to be
	--- spelled the way Roblox spells it.
	--- LUNE'S TYPES WHEN THEY EXIST, PURE LUAU WHEN THEY DO NOT (ms-52 M6).
	---
	--- Prefer the real ones: they are the engine's own semantics and every suite
	--- in this repo is calibrated against them. But `@lune/roblox` is a LUNE
	--- library, and this is supposed to be the host that does not care which
	--- runtime it is in. Under zune the require above was the single line that
	--- stopped Aether loading, after every relative require in the tree resolved.
	---
	--- pcall rather than a runtime check, because "is @lune/roblox available" has
	--- no answer other than trying it: the alias either resolves or it does not,
	--- and on zune it is a hard error at require time.
	local ok, lune = pcall(require, "@lune/roblox")
	if not ok or lune == nil then
		lune = require("./PureVocabulary").build()
	end

	host.Vocabulary = {
		UDim = (lune :: any).UDim,
		UDim2 = (lune :: any).UDim2,
		Vector2 = (lune :: any).Vector2,
		Color3 = (lune :: any).Color3,
		Rect = (lune :: any).Rect,
		NumberSequence = (lune :: any).NumberSequence,
		NumberSequenceKeypoint = (lune :: any).NumberSequenceKeypoint,
		ColorSequence = (lune :: any).ColorSequence,
		ColorSequenceKeypoint = (lune :: any).ColorSequenceKeypoint,
		Font = (lune :: any).Font,
		Enum = (lune :: any).Enum,
		--- WHAT KIND OF VALUE IS THIS, on any runtime (ms-52 M6).
		---
		--- With Lune's real datatypes `typeof` answers directly. With the pure
		--- vocabulary it cannot -- plain Luau returns "table" and ignores a
		--- `__type` metafield -- so the fallback carries its own tag. Consumers
		--- that branch on the kind of a value should ask HERE rather than calling
		--- `typeof`, or they take the wrong branch on a runtime without Lune.
		KindOf = (lune :: any).KindOf or function(value: any): string
			return typeof(value)
		end,
	}

	--- PUT THE VOCABULARY WHERE UNPORTED CODE ALREADY LOOKS FOR IT (ms-52 M5).
	---
	--- Aether's own packages name no engine type: they take UDim2, Color3 and the
	--- rest from `Host.Vocabulary`. Much of the repo has not been converted --
	--- `theme_core/SequenceUtil` reads a bare `NumberSequence`, and it is far from
	--- alone -- so those files simply error outside Roblox, which is why no kit
	--- depending on the token engine had ever rendered off-engine.
	---
	--- Converting every call site is a real piece of work and not this sprint's.
	--- Meanwhile every test suite in the repo hand-assigns these globals at the
	--- top of the file, one copy per file, drifting. This is that, once.
	---
	--- DELIBERATELY OPT-IN, and never called from library code. Writing globals is
	--- an APPLICATION's decision -- a host program or a suite -- because a library
	--- that silently installed them would make the unported call sites work and
	--- thereby hide exactly what this milestone exists to inventory. What is still
	--- reading bare globals stays visible: it only works because something chose
	--- to make it work.
	--- `_G`, NOT `getfenv(0)` (ms-52 M6).
	---
	--- This wrote to `getfenv(0)`, which under Lune is the shared global
	--- environment and under zune is the CALLING MODULE'S environment. So on zune
	--- the names appeared for whoever called this and for nobody else, and
	--- theme_core -- a different module -- still saw a nil `NumberSequenceKeypoint`
	--- and died on it. The symptom was a vocabulary that installed successfully
	--- and changed nothing, which is the same failure shape as the spring that
	--- registered and never animated.
	---
	--- `_G` is shared across modules in both runtimes; verified in each rather
	--- than assumed, because that is precisely the assumption that broke here.
	--- getfenv is written too, so a runtime where `_G` is NOT the global table
	--- still sees the names locally rather than not at all.
	host.InstallVocabulary = function()
		local targets: { any } = { _G }
		if getfenv then
			table.insert(targets, (getfenv :: any)(0))
		end
		for _, g in ipairs(targets) do
			for name, value in pairs(host.Vocabulary) do
				if value ~= nil and rawget(g, name) == nil then
					g[name] = value
				end
			end
		end
	end

	host.typeof = function(v: any): string
		if isMock(v) then
			return "Instance"
		end
		return type(v)
	end

	host.classOf = function(node: any): string?
		if type(node) == "table" then
			return rawget(node, "ClassName") or rawget(node, "_ClassName")
		end
		return nil
	end

	--- Give a node a rectangle. Nothing computes layout headlessly, so a suite
	--- that wants geometry states it — which is also what makes hit-testing
	--- assertions deterministic instead of dependent on a render pass.
	host.SetBounds = function(node: any, x: number, y: number, width: number, height: number)
		local pos = rawget(node, "AbsolutePosition")
		local size = rawget(node, "AbsoluteSize")
		local movedTo = not pos or pos.X ~= x or pos.Y ~= y
		local resized = not size or size.X ~= width or size.Y ~= height
		rawset(node, "AbsolutePosition", { X = x, Y = y })
		rawset(node, "AbsoluteSize", { X = width, Y = height })
		--- REPORTED, not just written (ms-53 D8). A host that changes geometry and
		--- tells nobody leaves every property-driven consumer reading whatever it
		--- saw at construction -- which is how the scrollbar decided, once and
		--- forever, that its content fit.
		if movedTo then
			host.FirePropertyChanged(node, "AbsolutePosition")
		end
		if resized then
			host.FirePropertyChanged(node, "AbsoluteSize")
		end
	end

	--- Notify anything listening for a property on this node. Public because the
	--- SOLVER lives in another module and is the other thing that measures.
	host.FirePropertyChanged = function(node: any, property: string)
		local sh = SHADOWS[node]
		if not sh then
			return
		end
		local listeners = sh.signals[property]
		if not listeners then
			return
		end
		--- Iterated over a COPY: a listener may disconnect itself, and several do.
		for _, fn in ipairs(table.clone(listeners)) do
			pcall(fn)
		end
	end

	--- THE SCENE CONTRACT (ms-51 M16 part 3) — the questions Layer 2 asks about a
	--- node, answered without an engine.
	---
	--- Stateless functions over a raw target, matching the Roblox host: hit-testing
	--- runs over every candidate on every pointer move, so a wrapper object per
	--- node would allocate a table per query. `Bounds` returns four numbers rather
	--- than a rectangle for the same reason.
	---
	--- Works over BOTH mock instances and the bare geometry stand-ins that Layer 2
	--- suites already pass — `{ AbsolutePosition = ..., AbsoluteSize = ... }`. Those
	--- stand-ins were an unnamed version of this contract all along.
	local function readVec(v: any, axis: string): number
		if v == nil then
			return 0
		end
		return (v :: any)[axis] or 0
	end

	--- Ask a target what it IS, honouring three ways of saying it.
	---
	--- Mock instances walk ANCESTRY. Stand-ins in the Layer 2 suites carry their
	--- own `IsA` closure — `IsA = function(_, class) return class == "GuiObject" end`
	--- — which is the oldest of the three and predates any of this. Elements from
	--- another package's `create` carry `_ClassName`. Consulting the closure FIRST
	--- matters: those stand-ins have no ClassName and no bounds of their own (a
	--- fake ScreenGui is exactly that), so any other order silently answers "no"
	--- and the render-order walk never finds the layer root.
	local function askIsA(target: any, class: string): boolean?
		local isA = (target :: any).IsA
		if type(isA) ~= "function" then
			return nil
		end
		local ok, result = pcall(isA, target, class)
		return if ok then result == true else nil
	end

	host.Scene = {
		Name = "Headless",

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
		--- Read straight off the node. `Layout.SetCanvasExtent` writes it there on
		--- every solve, which is the host reporting what it measured -- and it must
		--- be a plain read, because this is called from inside reactive getters and
		--- a `require` yields.
		CanvasExtent = function(target: any): (number, number)
			local canvas = rawget(target, "AbsoluteCanvasSize")
			if not canvas then
				return 0, 0
			end
			return readVec(canvas, "X"), readVec(canvas, "Y")
		end,

		Bounds = function(target: any): (number, number, number, number)
			local pos = rawget(target, "AbsolutePosition") or (target :: any).AbsolutePosition
			local size = rawget(target, "AbsoluteSize") or (target :: any).AbsoluteSize
			return readVec(pos, "X"), readVec(pos, "Y"), readVec(size, "X"), readVec(size, "Y")
		end,

		--- Raw property read, for a LAYOUT solver rather than a hit test.
		---
		--- `Bounds` answers "where is this" — which is what hit-testing needs and
		--- is meaningless before layout has run. `Raw` answers "what did the author
		--- ask for": the UDim2, the AnchorPoint, the padding. A solver needs the
		--- request; everything else needs the result.
		Raw = function(target: any, key: string): any
			return rawget(target, key)
		end,

		Children = function(target: any): { any }
			if isMock(target) then
				return target:GetChildren()
			end
			local out = {}
			for _, child in ipairs(target) do
				table.insert(out, child)
			end
			return out
		end,

		ClassOf = function(target: any): string?
			return rawget(target, "ClassName") or rawget(target, "_ClassName")
		end,

		Name = function(target: any): string?
			return rawget(target, "Name")
		end,

		ZIndex = function(target: any): number
			return rawget(target, "ZIndex") or 1
		end,

		IsVisible = function(target: any): boolean
			return rawget(target, "Visible") ~= false
		end,

		Parent = function(target: any): any
			if isMock(target) then
				return target.Parent
			end
			return rawget(target, "Parent")
		end,

		ChildIndex = function(target: any): number
			local parent = if isMock(target) then target.Parent else rawget(target, "Parent")
			if not parent or not isMock(parent) then
				return 0
			end
			for i, child in ipairs(parent) do
				if child == target then
					return i
				end
			end
			return 0
		end,

		--- Same rule as in-engine: ScrollingFrame and CanvasGroup clip whatever
		--- the flag says, because one bounds its canvas and the other renders its
		--- subtree to a texture.
		Clips = function(target: any): boolean
			if askIsA(target, "ScrollingFrame") or askIsA(target, "CanvasGroup") then
				return true
			end
			local class = rawget(target, "ClassName") or rawget(target, "_ClassName")
			if class == "ScrollingFrame" or class == "CanvasGroup" then
				return true
			end
			return rawget(target, "ClipsDescendants") == true
		end,

		IsLayerRoot = function(target: any): boolean
			local asked = askIsA(target, "LayerCollector")
			if asked ~= nil then
				return asked
			end
			local class = rawget(target, "ClassName") or rawget(target, "_ClassName")
			return class == "ScreenGui" or class == "SurfaceGui" or class == "BillboardGui"
		end,

		IsSurface = function(target: any): boolean
			local asked = askIsA(target, "GuiObject")
			if asked ~= nil then
				return asked
			end
			--- A stand-in carrying a rectangle IS a surface. Layer 2 suites have
			--- been passing these for years; the contract just names them now.
			return type(target) == "table" and rawget(target, "AbsolutePosition") ~= nil
		end,

		DisplayOrder = function(target: any): number
			return rawget(target, "DisplayOrder") or 0
		end,

		IsEnabled = function(target: any): boolean
			return rawget(target, "Enabled") ~= false
		end,

		Attribute = function(target: any, name: string): any
			if isMock(target) then
				return target:GetAttribute(name)
			end
			local get = (target :: any).GetAttribute
			if type(get) ~= "function" then
				return nil
			end
			local ok, value = pcall(get, target, name)
			return if ok then value else nil
		end,

		RenderedCorner = function(target: any): (number?, number?)
			local find = (target :: any).FindFirstChildOfClass
			if type(find) ~= "function" then
				return nil, nil
			end
			local ok, corner = pcall(find, target, "UICorner")
			if not ok or not corner then
				return nil, nil
			end
			local r = (corner :: any).CornerRadius
			if r == nil then
				return nil, nil
			end
			return r.Scale, r.Offset
		end,
	}

	--- The Layer 2.5 contract: an abstract rectangle for a concrete target.
	host.Resolve = function(node: any): any
		return {
			GetBounds = function(): Bounds
				local pos = rawget(node, "AbsolutePosition") or { X = 0, Y = 0 }
				local size = rawget(node, "AbsoluteSize") or { X = 0, Y = 0 }
				return { X = pos.X, Y = pos.Y, Width = size.X, Height = size.Y }
			end,
			GetZIndex = function(): number
				return rawget(node, "ZIndex") or 1
			end,
			IsVisible = function(): boolean
				return rawget(node, "Visible") ~= false
			end,
		}
	end

	return host
end

return Headless
