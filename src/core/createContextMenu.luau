--!strict
--[[
	Aether · core/createContextMenu -- is the menu open, which row is focused,
	and what closes it?

	Layer 1. No reactive library, no engine types, no hit-testing of its own.

	THE SAME SHAPE AS `createPressable`, deliberately (ADR-013). A machine hands
	back the table a binding spreads, so the binding is the tree and nothing
	else:

	    local machine = createContextMenu({ Items = props.Items, Source = ... })
	    return ScopedSurface(machine.GetSurfaceProps({ ... }))
	    ...
	    return Pressable(machine.GetItemProps(key, { ...how the row draws... }))

	WHAT IT OWNS is the four things the primitives gate named: open, closed,
	which item is focused, and dismissal. A row hovers, so a row is focused; a
	row activates, so the menu closes and the row's own handler runs, in that
	order -- a handler that opens a second menu would otherwise be closed by the
	first one's own dismissal.

	WHAT IT DOES NOT OWN is colour. A focused row is darker than an unfocused
	one, and the value that expresses that is a host type this layer may not name
	-- `verify_core_has_no_framework` fails a build over `Color3`. So the machine
	answers `IsItemFocused`, the binding derives its fill from it, and the whole
	question of who decides a colour at all is the styling sprint's.

	OPEN CAN BE OWNED HERE OR BY THE CALLER. A menu summoned by a right-click
	sits inside something that already knows where the click was, and that
	something usually keeps the open flag next to the anchor it captured. So
	`IsOpen` is a port: hand one over and this reads it, hand nothing over and
	this keeps its own. Either way `Open`, `Close` and `Dismiss` are the verbs,
	and a controlled caller hears about them through `OnOpenChanged`.
]]

--- Read with no arguments, write with one. `vide.source` is exactly this, which
--- is why the binding passes it straight in.
export type Source<T> = ((T) -> T) & (() -> T)

export type SourceFactory = <T>(initial: T) -> Source<T>

export type Item = {
	Id: string,
	Label: string,
	Icon: string?,
	Disabled: boolean?,
	OnActivated: (() -> ())?,
}

export type Options = {
	Source: SourceFactory?,

	--- The rows, as a list or as something that answers with one. A menu built
	--- over a live selection changes between one opening and the next.
	Items: ({ Item } | () -> { Item })?,

	--- CONTROLLED, if supplied: the caller owns the flag and this reads it.
	IsOpen: (() -> boolean)?,
	InitiallyOpen: boolean?,

	OnOpenChanged: ((open: boolean) -> ())?,
	--- Called whenever the menu stops being open, by dismissal or by activation.
	--- The spelling a controlled caller already uses.
	OnClose: (() -> ())?,
	OnItemActivated: ((item: Item) -> ())?,
	OnFocusChanged: ((id: string?) -> ())?,
}

export type ContextMenu = {
	IsOpen: () -> boolean,
	FocusedId: Source<string?>,
	Items: () -> { Item },

	Open: () -> (),
	Close: () -> (),
	Toggle: () -> (),
	--- Closed by something outside it: a click elsewhere, a surface dismissing.
	Dismiss: () -> (),

	FocusItem: (id: string?) -> (),
	FocusNext: () -> (),
	FocusPrevious: () -> (),
	IsItemFocused: (id: string) -> boolean,
	ActivateItem: (id: string) -> (),

	GetSurfaceProps: (overrides: { [any]: any }?) -> { [any]: any },
	GetItemProps: (id: string, overrides: { [any]: any }?) -> { [any]: any },
	Destroy: () -> (),
}

--- Options that belong to this machine and must not reach the element.
---
--- A DENY LIST RATHER THAN AN ALLOW LIST, for `createPressable`'s reason: the
--- list of things a host can draw is longer than the list of things this
--- decides, and an allow list drops every property nobody thought of.
local MACHINE_OPTIONS: { [string]: true } = {
	Source = true,
	Items = true,
	IsOpen = true,
	InitiallyOpen = true,
	OnOpenChanged = true,
	OnClose = true,
	OnItemActivated = true,
	OnFocusChanged = true,
}

--- The fallback `Source`, for a caller with no reactive library -- a test, or a
--- host that has not got one yet. Reads and writes with the shape vide uses,
--- and notifies nobody, which is all a machine needs to stay correct.
local function plainSource<T>(initial: T): Source<T>
	local value = initial
	return (
		function(...): T
			if select("#", ...) > 0 then
				value = (select(1, ...) :: any) :: T
			end
			return value
		end :: any
	) :: Source<T>
end

local function merge(defaults: { [any]: any }, overrides: { [any]: any }?): { [any]: any }
	if not overrides then
		return defaults
	end
	for key, value in pairs(overrides) do
		--- Numbered entries are children and actions the caller wrote, and they
		--- keep their order by being appended rather than assigned.
		if type(key) == "number" then
			if value ~= nil then
				table.insert(defaults, value)
			end
		elseif MACHINE_OPTIONS[key :: any] or value == nil then
			continue
		else
			defaults[key] = value
		end
	end
	return defaults
end

local function createContextMenu(options: Options): ContextMenu
	local newSource: SourceFactory = options.Source or plainSource

	local openSource = newSource(options.InitiallyOpen == true)
	local focusedId: Source<string?> = newSource(nil :: string?)
	local controlled = options.IsOpen

	local function items(): { Item }
		local supplied = options.Items
		if supplied == nil then
			return {}
		end
		if type(supplied) == "function" then
			return (supplied :: () -> { Item })()
		end
		return supplied :: { Item }
	end

	local function isOpen(): boolean
		--- READ THROUGH, NOT COPIED. A controlled caller's flag can change
		--- without anything here being told, and a mirrored copy would be one
		--- frame behind on every open.
		if controlled then
			return controlled() == true
		end
		return openSource()
	end

	local function itemById(id: string): Item?
		for _, item in ipairs(items()) do
			if item.Id == id then
				return item
			end
		end
		return nil
	end

	local function focusItem(id: string?)
		if focusedId() == id then
			return
		end
		focusedId(id)
		if options.OnFocusChanged then
			options.OnFocusChanged(id)
		end
	end

	--- A CLOSED MENU FOCUSES NOTHING. Otherwise the next opening starts on
	--- whichever row the pointer happened to leave last time, which reads as the
	--- menu remembering a choice nobody made.
	local function setOpen(open: boolean)
		local was = isOpen()
		if not controlled then
			openSource(open)
		end
		if not open then
			focusItem(nil)
		end
		if was == open then
			return
		end
		if options.OnOpenChanged then
			options.OnOpenChanged(open)
		end
		if not open and options.OnClose then
			options.OnClose()
		end
	end

	local function open()
		setOpen(true)
	end

	local function close()
		setOpen(false)
	end

	local function toggle()
		setOpen(not isOpen())
	end

	--- Focus the next row that can take it, in `step`'s direction, skipping
	--- disabled ones and wrapping. A menu whose first row is disabled must still
	--- have somewhere to start.
	local function move(step: number)
		local list = items()
		if #list == 0 then
			return
		end

		local current = focusedId()
		local from = 0
		for index, item in ipairs(list) do
			if item.Id == current then
				from = index
				break
			end
		end
		if from == 0 then
			from = if step > 0 then 0 else 1
		end

		for offset = 1, #list do
			local index = (from - 1 + step * offset) % #list + 1
			local candidate = list[index]
			if not candidate.Disabled then
				focusItem(candidate.Id)
				return
			end
		end
	end

	--- ACTIVATION CLOSES FIRST AND CALLS SECOND, and the order is the whole of
	--- what this function decides. A row whose handler opens another menu would
	--- otherwise be shut by the dismissal of the one that invoked it.
	local function activateItem(id: string)
		local item = itemById(id)
		if not item or item.Disabled then
			return
		end
		close()
		if item.OnActivated then
			item.OnActivated()
		end
		if options.OnItemActivated then
			options.OnItemActivated(item)
		end
	end

	local function isItemFocused(id: string): boolean
		return focusedId() == id
	end

	local function getSurfaceProps(overrides: { [any]: any }?): { [any]: any }
		return merge({
			Name = "ContextMenu",
			Visible = isOpen,
			--- WHAT DISMISSAL IS, from this machine's side: the surface noticed
			--- something outside it and says so; the machine decides that this
			--- means closed.
			OnDismiss = close,
		}, overrides)
	end

	local function getItemProps(id: string, overrides: { [any]: any }?): { [any]: any }
		return merge({
			Name = `Item_{id}`,
			--- A GETTER, because the row's own disabled flag can change while the
			--- menu is open and whatever draws the row reads this whenever it
			--- likes.
			Disabled = function(): boolean
				local item = itemById(id)
				return item ~= nil and item.Disabled == true
			end,
			OnHoverChanged = function(hovered: boolean)
				if hovered then
					focusItem(id)
				elseif focusedId() == id then
					focusItem(nil)
				end
			end,
			OnActivated = function()
				activateItem(id)
			end,
		}, overrides)
	end

	local destroyed = false
	local function destroy()
		if destroyed then
			return
		end
		destroyed = true
		if not controlled then
			openSource(false)
		end
		focusedId(nil)
	end

	return {
		IsOpen = isOpen,
		FocusedId = focusedId,
		Items = items,

		Open = open,
		Close = close,
		Toggle = toggle,
		Dismiss = close,

		FocusItem = focusItem,
		FocusNext = function()
			move(1)
		end,
		FocusPrevious = function()
			move(-1)
		end,
		IsItemFocused = isItemFocused,
		ActivateItem = activateItem,

		GetSurfaceProps = getSurfaceProps,
		GetItemProps = getItemProps,
		Destroy = destroy,
	}
end

return {
	createContextMenu = createContextMenu,
}
