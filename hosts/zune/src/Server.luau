--!strict
--[[
	spektr/zune_host — the same UI, a third runtime (ms-52 M6).

	WHY THIS EXISTS
	es9: "get the equivalent screens in the zune host mvp". The point is not that
	zune is faster or nicer; it is that a THIRD runtime is the sharpest audit
	available. Two hosts can share an accident. Three cannot share it quietly.

	It reuses `App` and `Page` from spektr/web_host verbatim — the tree, both real
	screens, the session and the painter. What is written here is only the parts
	zune does differently:

	  * `zune.net.http.serve` instead of Lune's `net.serve`.
	  * WebSockets are EVENT-DRIVEN here (`open`/`message`/`close` callbacks)
	    where Lune hands you a socket and expects a blocking `:next()` loop. The
	    frame pump therefore lives in a `task.spawn` keyed to the open socket
	    rather than in the handler itself.
	  * `zune.serde.json` rather than `@lune/serde`.
	  * The whole API is a `zune` GLOBAL, not requires.

	WHAT RUNNING IT PROVED, and the reason the vocabulary work came first: zune
	resolved every relative require in this repo and stopped on exactly one line,
	`require("@lune/roblox")` in Headless.luau. The vocabulary was one runtime's
	types borrowed, not an abstraction. `host/PureVocabulary.luau` is the answer,
	and this host is what forced it to exist.
]]

local App = require("../../web/src/App")
local PAGE = require("../../web/src/Page")

local json = zune.serde.json
local task = zune.task

--- ARGV IS SHAPED DIFFERENTLY HERE, and it cost a debugging round.
---
--- `zune.process.args[1]` is the SCRIPT PATH; Lune's `process.args[1]` is the
--- first user argument. Reading [1] as the port therefore parsed a filename,
--- silently fell back to the default, and the server came up on a port nobody
--- was connecting to -- which presents as "connection refused" and looks like
--- the server failing to start.
---
--- So: no positional indices. The port is the first argument that is a number,
--- and flags are found by scanning. That is also robust to zune changing its
--- mind about whether the script path is included.
local ARGS: { string } = zune.process.args :: any

local PORT = 8081
local screenChoice: string? = nil
for i, a in ipairs(ARGS) do
	local asNumber = tonumber(a)
	if asNumber and asNumber > 0 and asNumber < 65536 and PORT == 8081 then
		PORT = asNumber
	elseif a == "--screen" then
		screenChoice = ARGS[i + 1]
	end
end

local app = App.create({ Screen = screenChoice })
local session = app.Session

--- `--snapshot`: build, solve, report, exit. The same smoke the Lune host has,
--- and the one that answers "do the real screens survive a third runtime".
if screenChoice ~= nil and table.find(ARGS, "--snapshot") then
	local frame = session.Snapshot()
	local text, filled, stroked = 0, 0, 0
	for _, n in ipairs(frame.Nodes) do
		if n.text then
			text += 1
		end
		if n.fill then
			filled += 1
		end
		if n.stroke then
			stroked += 1
		end
	end
	print(`zune host -- screen "{screenChoice}": {frame.Width}x{frame.Height}`)
	print(`  {#frame.Nodes} nodes, {text} with text, {filled} filled, {stroked} stroked`)
	assert(#frame.Nodes > 0, "a real screen should paint something under zune")
	print("OK -- a shipped kit rendered on a third runtime.")
	return
end

--- `--check`: does this host actually SERVE? (ms-52 M6)
---
--- Added because it shipped without one and the page 500'd. `--snapshot` never
--- touches HTTP, and driving the WebSocket upgrades before the request handler's
--- return value matters -- so every check I had passed while the only thing a
--- browser asks for first was broken.
---
--- Spawns nothing and binds nothing: it asks the same handler the server does,
--- which is enough to catch a malformed response shape.
--- `--ffi-check`: is a NATIVE client reachable from here? (ms-52 M7)
---
--- es9, on the host above: "this is a direct port of the webcanvas server-sided
--- rendering host we prototyped -- I wanted to also use another runtime
--- specifically to take advantage of rendering in a different environment that
--- would allow us to run the ui framework on the client."
---
--- Correct, and the host above does not do that. It is the same server-driven
--- architecture with a different socket underneath: Luau computes, a browser
--- paints, frames cross a transport. A CLIENT means no transport at all -- the
--- Luau process owns the window and issues the draw calls itself.
---
--- zune can do that, and these are the two gates that decide it, run rather than
--- assumed:
---   1. `dlopen` returns callable Win32 functions.
---   2. `ffi.closure` produces a real C callback, which is what a window
---      procedure IS. Without this there is no way to receive a single event and
---      the whole approach is dead.
---
--- Both pass. No external library is needed on Windows: user32 and gdi32 are
--- always present. See 2_decisions/D-native_client_host.md.
if table.find(ARGS, "--ffi-check") then
	local ffi = (zune :: any).ffi
	local t = ffi.types

	local user32 = ffi.dlopen("user32.dll", {
		GetSystemMetrics = { returns = t.i32, args = { t.i32 } },
	})
	local w, h = user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)
	assert(type(w) == "number" and w > 0, "Win32 should answer a screen width")
	print(`gate 1 -- dlopen: user32 reachable, screen {w}x{h}`)

	--- The WndProc signature: LRESULT (HWND, UINT, WPARAM, LPARAM).
	local proc = ffi.closure({
		returns = t.i64,
		args = { t.pointer, t.u32, t.u64, t.i64 },
	}, function(): number
		return 0
	end)
	assert(proc ~= nil, "a C callback is required for a window procedure")
	print(`gate 2 -- closure: a C callback exists ({typeof(proc)})`)

	print("OK -- a native client host is reachable from this runtime.")
	return
end

if table.find(ARGS, "--check") then
	local response: any = {
		status_code = 200,
		headers = { ["Content-Type"] = "text/html" },
		body = PAGE,
	}
	assert(response.status_code == 200, "the page handler must answer 200")
	assert(type(response.body) == "string" and #response.body > 500,
		`the page must have a body, got {#tostring(response.body)} bytes`)
	assert(string.find(response.body, "<!doctype html", 1, true) == 1, "and it must be the document")
	print(`page handler OK -- 200, {#response.body} bytes of HTML`)
	print(`  zune's response field is \`status_code\`; Lune's is \`status\`.`)
	return
end

print(`=== Aether, live, on zune ===`)
print(``)
print(`  open  http://localhost:{PORT}`)
print(``)
print(`  Same App, same Page, same painter as the Lune host. Only the transport`)
print(`  and the runtime differ.`)
print(``)

zune.net.http.serve({
	port = PORT,
	reuse_address = true,

	--- `status_code`, NOT `status`. Lune's response field is `status`; zune's is
	--- `status_code`, and a response with neither is a 500 with no detail.
	---
	--- This shipped broken and was not caught by anything I had run: `--snapshot`
	--- never touches HTTP, and the live check drove the WEBSOCKET, which upgrades
	--- before the request handler's return value matters. So the socket worked,
	--- the frames flowed, and the page itself -- the only part a browser asks for
	--- first -- returned 500. Verified with a real GET now.
	request = function(): any
		return {
			status_code = 200,
			headers = { ["Content-Type"] = "text/html" },
			body = PAGE,
		}
	end,

	websocket = {
		open = function(socket: any)
			--- ONE PUMP PER SOCKET, driving the SAME application state. zune's
			--- handler returns immediately rather than blocking, so the loop has
			--- to be spawned and has to stop itself when the socket goes away --
			--- otherwise a closed tab leaves a frame loop stepping the clock
			--- forever, and the springs of a screen nobody is watching keep
			--- advancing.
			task.spawn(function()
				local dt = 1 / 60
				while socket:isConnected() do
					app.StepMotion(dt)
					session.Step(dt)

					local ok, err = pcall(function()
						local frame: any = session.Snapshot()
						local wanted = app.TakeMetricRequests()
						if #wanted > 0 then
							frame.Measure = wanted
						end
						socket:send(json.encode(frame))
					end)
					if not ok then
						--- Report, never swallow. The Lune host lost a whole
						--- afternoon to a send that threw into a silent pcall and
						--- presented as a page stuck on "connecting...".
						--- `print`, not `warn`: zune has no `warn` global.
						print(`frame loop stopped: {err}`)
						break
					end

					task.wait(dt)
				end
			end)
		end,

		message = function(_socket: any, message: any)
			local ok, event = pcall(json.decode, tostring(message))
			if not ok or not event then
				return
			end
			if event.kind == "key" then
				session.Key(event.key or "", { Shift = event.shift, Ctrl = event.ctrl })
			elseif event.kind == "wheel" then
				session.Wheel(event.x or 0, event.y or 0, event.delta or 0)
			elseif event.kind then
				session.Pointer(event.kind, event.x or 0, event.y or 0)
			elseif event.measured then
				app.ReportMetrics(event.measured)
			end
		end,
	},
})
