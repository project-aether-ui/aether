--!strict
--[=[
	Tabs — a tab list and its panels, exactly one active at a time. Part of
	Aether.Primitives (Layer 2A).

	NAMED FOR THE BEHAVIOUR, THE SAME AS Checkbox. `core/createTabs` decides
	what is true and hands back `GetTab`/`GetPanel`; this file supplies the
	two routers, vide's `source`, and vide's `action` -- the four things the
	machine cannot have -- so a caller never has to name `PointerRouter` or
	`SelectionRouter` to get a tab bar working.

	NO SINGLE ELEMENT IS CREATED HERE, unlike `Checkbox.luau`. A tab list
	shares one model between two kinds of element (a tab, its panel) laid out
	however the caller likes -- side by side, panel below, tabs in a sidebar
	-- so this stays a factory, exactly the shape `createTabs` itself already
	has, and a caller builds its own elements from `GetTab(key).GetRootProps()`
	and `GetPanel(key).GetRootProps()`.

	`Source`/`Action` ARE OVERRIDABLE TOO, unlike `Checkbox.luau`'s own
	hard-wired pair, and this is not an inconsistency -- it is the same
	discrepancy this sprint's own live test against Dew's `dashboard.luau`
	surfaced. `Checkbox` composes entirely inside Aether's own render tree,
	so its `vide.source`/`vide.action` never leave Aether's own reactive
	graph. `Tabs` hands `Active`/`IsActive`/etc back to a caller that reads
	them from ITS OWN `effect`, and a host builds its own vide package
	rather than sharing Aether's vendored copy -- `dashboard.luau` does, and
	pinning `Source` to Aether's internal vide left `tabs.Active` changing
	correctly while the dashboard's own `effect` never re-ran, because a
	vide source only notifies the reactive graph that CREATED it. The fix is
	the override below, exactly the shape `dashboard.luau`'s own pre-Sprint-1
	code already used by handing its own `Source = source` to
	`Aether.Core.createTabs` directly.
]=]

local Deps = require("../Deps")
local PointerRouter = require("../PointerRouter")
local SelectionRouter = require("../SelectionRouter")

local coreTabs = require("../core/createTabs")
local createTabs = coreTabs.createTabs

local vide = Deps.vide

export type Options = {
	--- Overridable the same way `Checkbox`'s own `Scope` is -- default to the
	--- real singletons, but a caller that already has a fake double (or a
	--- second router) can still hand one over explicitly.
	Router: coreTabs.Router?,
	Selection: coreTabs.Selection?,
	--- Overridable for the same reason `Router`/`Selection` are: a host with
	--- its own vide package (Dew's `dashboard.luau`, for one) must be able to
	--- hand its own reactive graph over, since a source only notifies the
	--- graph that created it.
	Source: coreTabs.SourceFactory?,
	Action: coreTabs.ActionFactory?,

	Tabs: { any },
	InitialActive: any?,

	Disabled: (boolean | () -> boolean)?,
	Cursor: (string | () -> string)?,

	OnActiveChanged: ((active: any?) -> ())?,
}

local function Tabs(options: Options): coreTabs.Tabs
	return createTabs({
		Router = if options.Router ~= nil then options.Router else PointerRouter,
		Selection = if options.Selection ~= nil then options.Selection else SelectionRouter,
		Source = if options.Source ~= nil then options.Source else vide.source,
		Action = if options.Action ~= nil then options.Action else vide.action,

		Tabs = options.Tabs,
		InitialActive = options.InitialActive,
		Disabled = options.Disabled,
		Cursor = options.Cursor,
		OnActiveChanged = options.OnActiveChanged,
	})
end

return Tabs
