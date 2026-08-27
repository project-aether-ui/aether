--!strict
--[[
	verify_use_before_declaration — a local function must not reference a local
	declared BELOW it.

	WHY (ms-43 M74)
	In Luau this is not a timing problem, it is a SCOPING one. Given:

	    local function measureMounted()
	        clampOffset()          -- resolves as a GLOBAL, because...
	    end
	    local function clampOffset() end   -- ...this local does not exist yet

	`clampOffset` inside the body binds to a global that is nil forever. Moving
	the call later does not help; only moving the declaration earlier does.

	This is the single most repeated defect of ms-43 — EIGHT occurrences:
	fallbackHover/source (M35), trackSpan/absoluteSize (M41), the frame loop and
	scrollActive (M43), axisOf (M55), trackTransparency/showTrack (M60),
	FluxMotion (M65), frameSource/viewport (M69), clampOffset/measureMounted
	(M73). Six reached Studio. Two were caught by suites.

	AND IT IS EXACTLY THE CLASS TESTS ARE WORST AT. The body only throws when it
	RUNS, so any branch a headless suite cannot reach hides one indefinitely. M73
	landed in the measurement path — the one path documented as unreachable
	headlessly — and threw on every frame of the first playtest. Eight times is
	not a discipline problem any more, it is a missing gate.

	DELIBERATELY CONSERVATIVE. Flags only a CALL — `name(` — to a name declared
	later at the same or an outer indentation. It will not catch a bare reference
	or a name captured into a table, and that is the right trade: a gate people
	silence for false positives protects nothing. Every historical case above is
	a call, which is what made this shape worth encoding.
]]

local fs = require("@lune/fs")

local failures = 0
local function fail(msg: string)
	failures += 1
	print("FAIL  " .. msg)
end

local NL = string.char(10)

local SKIP_DIRS: { [string]: boolean } = {
	roblox_packages = true,
	[".pesde"] = true,
	[".artifacts"] = true,
	lune_packages = true,
}

--- Luau keywords and globals that may legitimately follow a call site.
local IGNORE: { [string]: boolean } = {}
for _, name in ipairs({
	"if", "then", "else", "elseif", "end", "for", "while", "do", "return", "local",
	"function", "and", "or", "not", "in", "repeat", "until", "break", "continue",
	"true", "false", "nil", "type", "export",
	"print", "error", "assert", "pcall", "xpcall", "require", "select", "typeof",
	"tostring", "tonumber", "pairs", "ipairs", "next", "setmetatable", "getmetatable",
	"rawget", "rawset", "unpack", "warn", "task", "math", "table", "string", "os",
	"game", "script", "workspace", "Instance", "Vector2", "Vector3", "UDim", "UDim2",
	"Color3", "Enum", "CFrame", "Random", "tick", "time", "delay", "spawn",
}) do
	IGNORE[name] = true
end

local function indentOf(line: string): number
	local ws = string.match(line, "^[\t ]*") or ""
	return #ws
end

local checked = 0

local function checkFile(path: string, rawBody: string)
	-- Drop a leading --[[ ]] header first. Its lines do not start with `--`, so a
	-- line-based stripper walks straight through them — and this file's own
	-- header contains an EXAMPLE of the defect, which the widened roots duly
	-- reported as a real finding. Second time this exact mistake appeared
	-- tonight, after the window_topbar suite.
	local headerEnd = string.find(rawBody, "]]", 1, true)
	local body = if headerEnd and string.find(string.sub(rawBody, 1, headerEnd), "--[[", 1, true)
		then string.sub(rawBody, headerEnd + 2)
		else rawBody

	local lines: { string } = {}
	-- Offset, so reported line numbers still point at the real file.
	local skipped = 0
	if body ~= rawBody then
		for _ in string.gmatch(string.sub(rawBody, 1, headerEnd), NL) do
			skipped += 1
		end
		for _ = 1, skipped do
			table.insert(lines, "")
		end
	end
	for line in string.gmatch(body .. NL, "(.-)" .. NL) do
		table.insert(lines, line)
	end

	--- name -> the line it is first declared on, plus its indentation.
	local declLine: { [string]: number } = {}
	local declIndent: { [string]: number } = {}

	for i, raw in ipairs(lines) do
		local line = string.gsub(raw, "%-%-.*$", "")
		local name = string.match(line, "^%s*local%s+function%s+([%w_]+)")
			or string.match(line, "^%s*local%s+([%w_]+)%s*[:=]")
		if name and not declLine[name] then
			declLine[name] = i
			declIndent[name] = indentOf(raw)
		end
	end

	for i, raw in ipairs(lines) do
		local line = string.gsub(raw, "%-%-.*$", "")
		local fnName = string.match(line, "^%s*local%s+function%s+([%w_]+)")
		if not fnName then
			continue
		end

		checked += 1
		local fnIndent = indentOf(raw)

		-- A ONE-LINE definition closes on its own line.
		--
		-- Without this the body was taken to run until the next lone `end`, which
		-- for a run of one-line declarations swept in every sibling below and
		-- reported all of them — 55 false positives on the first run, every one
		-- from UIMounter's block of `local function closeX() ... end`. A gate that
		-- cries wolf gets silenced, which would have been worse than no gate.
		if string.match(line, "%send%s*$") then
			continue
		end

		-- Body runs to the `end` at the same indentation.
		local stop = #lines
		for j = i + 1, #lines do
			local candidate = string.gsub(lines[j], "%-%-.*$", "")
			if string.match(candidate, "^%s*end%s*$") and indentOf(lines[j]) == fnIndent then
				stop = j
				break
			end
		end

		local reported: { [string]: boolean } = {}
		for j = i + 1, stop - 1 do
			local src = string.gsub(lines[j], "%-%-.*$", "")
			-- Strip string literals, so a name inside text is not a call.
			src = string.gsub(src, '"[^"]*"', '""')
			src = string.gsub(src, "'[^']*'", "''")

			for called in string.gmatch(src, "([%w_]+)%s*%(") do
				if IGNORE[called] or reported[called] then
					continue
				end
				-- A method or field call is qualified; only bare names bind to a
				-- local or a global.
				if string.find(src, "[%.:]%s*" .. called .. "%s*%(") then
					continue
				end
				local d = declLine[called]
				if d and d > i and (declIndent[called] or 0) <= fnIndent then
					reported[called] = true
					fail(
						`{path}:{j}: '{fnName}' calls '{called}', declared later at line {d} `
							.. `— inside the body that binds to a nil GLOBAL, not the local`
					)
				end
			end
		end
	end
end

local function walk(dir: string)
	for _, entry in ipairs(fs.readDir(dir)) do
		if SKIP_DIRS[entry] then
			continue
		end
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			walk(path)
		elseif string.sub(entry, -5) == ".luau" then
			checkFile(path, fs.readFile(path))
		end
	end
end

print("=== VERIFY: no local function references a local declared below it ===")
-- tests/ and scripts/ included (ms-43 M87). The gates are code too, and this
-- exact defect happened IN one: verify_property_names grew a helper below the
-- function that called it, and nothing caught it because the roots stopped at
-- pkgs and examples. A gate that does not check the gates has an obvious hole.
for _, root in ipairs({ "src", "packages", "hosts", "tests" }) do
	if fs.isDir(root) then
		walk(root)
	end
end

print("")
if failures > 0 then
	print(`VERIFY USE-BEFORE-DECLARATION: FAILED ({failures} problem(s))`)
	local process = require("@lune/process")
	process.exit(1)
else
	print(`VERIFY USE-BEFORE-DECLARATION: PASS ({checked} local functions)`)
end
return true
