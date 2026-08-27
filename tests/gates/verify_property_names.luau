--!strict
--[[
	verify_property_names — every property assigned in a `create "Class" { … }`
	block must exist on that class.

	WHY (ms-43 M64)
	This is the one class of defect in the UI packages that no test can reach. A
	headless stand-in is a plain table: it accepts any property name you write,
	including ones the engine has never heard of. So:

	    sf.VerticalScrollBarImageTransparency = 1

	passed every suite, and threw on every real mount. It had been there long
	enough to be invisible, and only surfaced when ms-43 M35 gave the PrismStudio
	debugger a working scrollbar and that effect ran for the first time.

	Roblox's reflection database is the authority — but lune ships a SNAPSHOT of it, and
	the engine moves. Where the snapshot lags, `reflection_overlay.luau` carries properties
	the LIVE ENGINE confirmed, each pinned by a test in `tests/engine/reflection`. Adding a
	row there requires engine evidence, never judgement. See that file for what this cost:
	ms-43 M64's "16 real defects" were false positives, and they cost two packages their
	coverage for a whole milestone.

	TWO THINGS IT CANNOT TELL US, both handled below rather than papered over:

	  * `Properties` holds a class's OWN properties only, so the Superclass chain
	    has to be walked. `Frame` declares exactly one property; `Visible` lives on
	    `GuiObject`.
	  * EVENTS ARE NOT IN THE DATABASE. `TextButton.Activated` and
	    `Frame.MouseEnter` are both absent, and vide accepts them as keys. There is
	    no authority to check them against, so they are allow-listed by name — a
	    real compromise, and the list is short and stable enough to be worth it.
]]

local fs = require("@lune/fs")
local rbx = require("@lune/roblox")

local db = (rbx :: any).getReflectionDatabase()
--- Engine-confirmed properties the bundled snapshot lacks. ADDITIVE ONLY: a name in
--- neither the database nor this table still fails, so the overlay cannot mask a real
--- typo — it can only stop the gate lying about a property that exists.
local OVERLAY: { [string]: { [string]: boolean } } = require("./reflection_overlay")

local failures = 0
local function fail(msg: string)
	failures += 1
	print("FAIL  " .. msg)
end

local NL = string.char(10)

--- Every property on a class, including inherited ones.
local propertyCache: { [string]: { [string]: boolean }? } = {}
local function propertiesOf(className: string): { [string]: boolean }?
	local cached = propertyCache[className]
	if cached then
		return cached
	end

	local ok, cls = pcall(function()
		return db:GetClass(className)
	end)
	if not ok or not cls then
		return nil
	end

	local out: { [string]: boolean } = {}
	local cursor: any = cls
	while cursor do
		for name in pairs(cursor.Properties) do
			out[name] = true
		end
		local super = cursor.Superclass
		if not super or super == "" or super == "<<<ROOT>>>" then
			break
		end
		local okSuper, parent = pcall(function()
			return db:GetClass(super)
		end)
		cursor = if okSuper then parent else nil
	end

	-- Fold in anything the engine has that the snapshot does not.
	local extra = OVERLAY[className]
	if extra then
		for name in pairs(extra) do
			out[name] = true
		end
	end

	propertyCache[className] = out
	return out
end

--- Keys vide accepts that are not properties.
---
--- Events first: the reflection database does not carry them, so this list is the
--- only authority available. Anything here is trusted, so keep it to names that
--- genuinely exist — an entry with a typo in it defeats the whole gate.
local ALLOWED: { [string]: boolean } = {}
for _, name in ipairs({
	-- GuiObject / GuiButton events
	"Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up",
	"MouseButton2Click", "MouseEnter", "MouseLeave", "MouseMoved",
	"MouseWheelForward", "MouseWheelBackward",
	"InputBegan", "InputChanged", "InputEnded",
	"SelectionGained", "SelectionLost", "TouchTap",
	-- TextBox
	"Focused", "FocusLost", "ReturnPressedFromOnScreenKeyboard",
	-- Instance events
	"AncestryChanged", "ChildAdded", "ChildRemoved", "Destroying", "Changed",
	-- vide's own keys
	"children",
}) do
	ALLOWED[name] = true
end

local SRC_ROOTS = {
	"src",
	"packages",
	"hosts",
}

--- EMPTY, and the history is worth keeping (ms-44).
---
--- Both Studio packages used to sit here. ms-43 M64 skipped them after this gate reported
--- "16 real defects" — `UICorner` blocks setting TopLeftRadius / TopRightRadius /
--- BottomLeftRadius / BottomRightRadius, "none of which exist". All four DO exist; the
--- bundled snapshot simply lagged the engine (see reflection_overlay.luau). The code was
--- correct, and the skip cost an entire layer its coverage for a milestone.
---
--- The lesson for anyone tempted to add an entry here: a skip added because a gate is
--- FAILING is only correct if the failure is real. Verify first — the engine tier can
--- answer in seconds now — because a wrong skip is silent and permanent.
local SKIPPED: { [string]: boolean } = {}

local checkedBlocks = 0

--- Collect `Key =` assignments at the TOP level of a create block.
---
--- Brace-depth counted from the opening `{`, so nested `create` blocks and nested
--- tables are skipped — they are checked separately when the scan reaches them.
local function checkCreateBlocks(path: string, body: string)
	-- `(.-)NL` rather than `[^NL]*`: the star form matches an EMPTY string at
	-- every position, so it yields roughly two entries per line and every reported
	-- line number comes out doubled. Blank lines still have to be preserved, or
	-- the numbering drifts the other way.
	local lines: { string } = {}
	for line in string.gmatch(body .. NL, "(.-)" .. NL) do
		table.insert(lines, line)
	end

	for index, line in ipairs(lines) do
		-- `create "Frame" {` and `create("Frame")({` both appear in this codebase.
		local className = string.match(line, 'create%s*"([%w_]+)"%s*{')
			or string.match(line, 'create%s*%(%s*"([%w_]+)"%s*%)%s*%(%s*{')
		if not className then
			continue
		end

		local known = propertiesOf(className)
		if not known then
			-- Not a class the database knows. Silence rather than noise: this scan
			-- also sees local component factories that happen to share the shape.
			continue
		end

		checkedBlocks += 1

		-- Walk to the matching close brace, and STOP there.
		--
		-- The break used to be `cursor > index and depth <= 0`, which never fires
		-- for a one-line block like `create "UICorner" { CornerRadius = r },`:
		-- depth returns to 0 on the opening line, the loop keeps going, and the
		-- NEXT sibling's keys get attributed to UICorner. That produced 155
		-- confident reports of `UICorner has no property 'Text'`.
		local depth = 0
		local opened = false
		for cursor = index, #lines do
			local stripped = string.gsub(lines[cursor], "%-%-.*$", "")

			if opened and depth == 1 then
				local key = string.match(stripped, "^%s*([A-Z][%w_]*)%s*=")
				if key and not known[key] and not ALLOWED[key] then
					fail(`{path}:{cursor}: {className} has no property '{key}'`)
				end
			end

			-- Character by character, and stop the INSTANT depth returns to zero.
			--
			-- End-of-line was not enough: `} or IconManager.Icon {` closes this
			-- block and opens another on the same line, so depth is back to 1 by the
			-- end of it and the next component's keys were attributed to this class.
			-- That is what produced `TextLabel has no property 'Pack'`.
			local finished = false
			for char in string.gmatch(stripped, "[{}]") do
				depth += if char == "{" then 1 else -1
				if depth > 0 then
					opened = true
				elseif opened then
					finished = true
					break
				end
			end

			if finished then
				break
			end
		end
	end
end

--- GuiButton-only members, ASSIGNED anywhere in the UI surface (ms-43 M87).
---
--- WHY THIS IS A SEPARATE PASS. The scan above reads `create "Class" { … }`
--- blocks, so a property ASSIGNED onto an element — `element.Activated = fn` —
--- is entirely outside it. That is the gap the M85 defect went through: the
--- window topbar assigned `Activated` onto a Frame, which throws on every mount
--- and which nothing here could see.
---
--- The rule is only decidable because of another invariant: M17 forbids
--- GuiButton anywhere in the UI packages. If no GuiButton exists, then any
--- GuiButton-only member being assigned is assigned to something that does not
--- have it.
---
--- PROPERTIES ARE DERIVED from the database — GuiButton's own, minus
--- GuiObject's — so the list cannot go stale against the engine. EVENTS are
--- curated, because the database does not carry events at all, and `Activated`
--- is an event. That is the same compromise the block above documents, and it
--- is why the actual defect needed the curated half.
local guiButtonOnly: { [string]: boolean } = {}
do
	local guiObject = propertiesOf("GuiObject")
	local guiButton = propertiesOf("GuiButton")
	if guiObject and guiButton then
		for name in pairs(guiButton) do
			if not guiObject[name] then
				guiButtonOnly[name] = true
			end
		end
	end
	for _, name in ipairs({
		"Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up",
		"MouseButton2Click", "MouseButton2Down", "MouseButton2Up",
	}) do
		guiButtonOnly[name] = true
	end
end

local assignmentsChecked = 0

local function checkAssignments(path: string, body: string)
	local lines: { string } = {}
	for line in string.gmatch(body .. NL, "(.-)" .. NL) do
		table.insert(lines, line)
	end
	for i, raw in ipairs(lines) do
		local line = string.gsub(raw, "%-%-.*$", "")
		-- `thing.Member = ` or `(thing :: any).Member = `, but not `==`.
		local member = string.match(line, "[%w_%)]%s*%.%s*([A-Z][%w_]*)%s*=[^=]")
		if not member then
			continue
		end
		assignmentsChecked += 1
		if guiButtonOnly[member] then
			fail(
				`{path}:{i}: assigns GuiButton-only '{member}'. `
					.. `M17 forbids GuiButton in the UI packages, so the target cannot have it — `
					.. `bind through an injected press authority instead`
			)
		end
	end
end

local function walk(dir: string)
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. entry
		if entry == "roblox_packages" or entry == ".pesde" or SKIPPED[path] then
			continue
		end
		if fs.isDir(path) then
			walk(path)
		elseif string.sub(entry, -5) == ".luau" and not string.find(entry, ".test.", 1, true) then
			local contents = fs.readFile(path)
			checkCreateBlocks(path, contents)
			checkAssignments(path, contents)
		end
	end
end

print("=== VERIFY: property names against Roblox's reflection database ===")

for _, root in ipairs(SRC_ROOTS) do
	if fs.isDir(root) then
		walk(root)
	end
end

print("")
if failures > 0 then
	print(`VERIFY PROPERTY NAMES: FAILED ({failures} problem(s) across {checkedBlocks} create blocks)`)
	local process = require("@lune/process")
	process.exit(1)
else
	print(`VERIFY PROPERTY NAMES: PASS ({checkedBlocks} create blocks, {assignmentsChecked} assignments)`)
end
return true
