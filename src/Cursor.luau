--!strict
--[[
	Aether · Cursor — the seam a cursor owner registers itself into.

	WHY A SEAM (ms-51 M19)
	PointerRouter's own comment states the division exactly:

	    "Cursor is ours to CHOOSE because nothing here is a GuiButton, but not
	     ours to WRITE: CoreInput.Mouse owns UserInputService.MouseIcon through a
	     priority stack that caches and restores the player's default, so a second
	     direct writer would fight it."

	That division is right and is not what changed. What changed is the DIRECTION.
	Aether declared spektr/coreinput so it could reach `Mouse.PushCursor` — and
	that edge was the last thing keeping VideShim alive, because it meant
	spektr/mouse could never depend on Aether for a real headless vide without
	closing a cycle.

	So the same shape as `Aether.Motion`: Aether names the CAPABILITY it needs,
	and whoever owns it registers. Aether decides which cursor a surface wants;
	the registered provider decides how a cursor is written and keeps its priority
	stack. Nothing about the arbitration moved.

	UNREGISTERED, `Push` IS A NO-OP that returns nil. A host with no cursor owner —
	headless, or an application that never installed one — simply has no cursor,
	which is the right answer rather than an error. Same promise spektr/button
	makes about motion.

	NEVER CLOBBER. `SetProvider` refuses to replace one an application already
	installed, matching every other seam in the repo (ms-43 M29).
]]

local Cursor = {}

--- What a cursor owner must be able to do.
---
--- `PushCursor` returns a POP function, because the stack is the whole point: a
--- router that pushes on hover has to be able to withdraw exactly its own entry
--- when the pointer leaves, without disturbing anyone else's.
---
--- `GetCursorToken` resolves a SEMANTIC name ("Pointer", "Text") through the
--- active cursor pack. Optional: a provider with no pack concept can omit it and
--- the name is used as-is.
export type CursorProvider = {
	PushCursor: (payload: any, priority: number?) -> (() -> ())?,
	GetCursorToken: ((name: any) -> { Image: any?, Node: any?, Priority: number? })?,
}

local provider: CursorProvider? = nil
local providerOwner: string? = nil

--- Register the authority that WRITES the cursor. Returns whether it took.
function Cursor.SetProvider(next: CursorProvider?, owner: string?): boolean
	if next ~= nil and provider ~= nil then
		return false
	end
	provider = next
	providerOwner = if next ~= nil then owner else nil
	return true
end

function Cursor.GetProvider(): CursorProvider?
	return provider
end

function Cursor.HasProvider(): boolean
	return provider ~= nil
end

--- Who registered it, for diagnostics. nil when unregistered.
function Cursor.ProviderOwner(): string?
	return providerOwner
end

--- Resolve a semantic name through the active pack, if there is one.
---
--- A pack may render either way per token: an asset id on the hardware cursor, or
--- a node the owner mounts and tracks. Both are carried; the caller picks.
function Cursor.Resolve(name: any): { Image: any?, Node: any?, Priority: number? }
	local p = provider
	if p and p.GetCursorToken then
		local ok, token = pcall(p.GetCursorToken, name)
		if ok and type(token) == "table" then
			return token
		end
	end
	return { Image = name }
end

--- Ask for `name` to be the cursor. Returns a pop function, or nil when nothing
--- was pushed — no provider, or a token that resolved to nothing.
function Cursor.Push(name: any, defaultPriority: number?): (() -> ())?
	local p = provider
	if not p or not p.PushCursor then
		return nil
	end

	local token = Cursor.Resolve(name)
	--- Node wins when both are present: a pack that supplies one is asking to
	--- render the cursor itself rather than hand the hardware an image.
	local payload: any = token.Node or token.Image
	if payload == nil then
		return nil
	end

	local ok, pop = pcall(p.PushCursor, payload, token.Priority or defaultPriority)
	if ok and type(pop) == "function" then
		return pop
	end
	return nil
end

--- Testing seam: forget the registration so a suite can install its own.
function Cursor._reset()
	provider = nil
	providerOwner = nil
end

return Cursor
