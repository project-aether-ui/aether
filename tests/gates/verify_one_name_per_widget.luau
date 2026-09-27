--!strict
--[[
	verify_one_name_per_widget — the collapse milestone 54 sprint 4 did stays
	done.

	WHY
	Before this sprint, a checkbox was reachable three ways: `Aether.createCheckbox`,
	`Aether.Core.createCheckbox`, and `Aether.Checkbox` (the Primitive) -- organized by
	which of the five internal layers implemented it rather than by what a consumer was
	building. The top-level `createX` shortcuts are gone now, and `Engine.Pressable` (the
	router's raw registration function, sharing a name with the `Pressable` Primitive) is
	gone with them. This sprint's own falsifiable success criterion is that `grep`-ing this
	repository for `Aether.Core.create` and `Aether.Engine.Pressable` finds nothing outside
	history -- this gate is that grep, run on every future commit instead of once by hand.

	CODE ONLY, THE SAME DISCIPLINE `SourceScan` EXISTS FOR. `src/primitives/ContextMenu
	.luau`'s own header comment says "Aether.Core.createContextMenu" in PROSE, describing
	what it embeds -- a real find there would be a false positive off `SourceScan
	.blankComments`'s own job, not a regression this gate exists to catch.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local SourceScan = require("./source_scan")

local SUBJECT = "src/"
local FORBIDDEN = {
	{ pattern = "Aether%.Core%.create", label = "Aether.Core.create" },
	{ pattern = "Aether%.Engine%.Pressable", label = "Aether.Engine.Pressable" },
}

type Finding = { file: string, line: number, label: string, text: string }

local function walk(dir: string, out: { string })
	for _, name in ipairs(fs.readDir(dir)) do
		local path = `{dir}{name}`
		if fs.isDir(path) then
			if name ~= "roblox_packages" and name ~= ".pesde" and name ~= "node_modules" then
				walk(`{path}/`, out)
			end
		elseif string.match(name, "%.luau$") then
			table.insert(out, path)
		end
	end
end

local files: { string } = {}
walk(SUBJECT, files)
table.sort(files)

local findings: { Finding } = {}
for _, path in ipairs(files) do
	local code = SourceScan.blankComments(SourceScan.blankStrings(fs.readFile(path)))
	local line = 0
	for text in string.gmatch(code .. "\n", "([^\n]*)\n") do
		line += 1
		for _, forbidden in ipairs(FORBIDDEN) do
			if string.find(text, forbidden.pattern) then
				table.insert(findings, { file = path, line = line, label = forbidden.label, text = text })
			end
		end
	end
end

print("")
print(`VERIFY ONE NAME PER WIDGET: scanned {#files} file(s) under {SUBJECT}`)

if #findings > 0 then
	print("")
	for _, finding in ipairs(findings) do
		print(`  {finding.file}:{finding.line}: found \`{finding.label}\` as code, not prose`)
	end
	print(`VERIFY ONE NAME PER WIDGET: FAILED ({#findings} problem(s))`)
	process.exit(1)
else
	print("VERIFY ONE NAME PER WIDGET: PASS (no live call site reaches either collapsed name)")
end
