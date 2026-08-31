local fs = require("@lune/fs")
local luau = require("@lune/luau")
--[[
    Compiles every conformance file without running it.

    WHY THIS EXISTS: the engine runner cannot be executed outside Studio, so a
    syntax error in it is invisible here and surfaces as a line number pasted
    back from someone else's Output window. That happened once -- an interpolated
    string containing literal braces, which is legal-looking and is not legal --
    and once is the right number of times.

    `luau.compile` parses and codegens; it does not run. That is the whole check
    and it is enough for the failure mode it exists for.
]]
local files = {
    "conformance/roblox/src/run.client.luau",
    "conformance/run.luau",
    "conformance/decode.luau",
}

for _, entry in ipairs(fs.readDir("conformance/cases")) do
    if string.match(entry, "%.luau$") then
        table.insert(files, `conformance/cases/{entry}`)
    end
end
local bad = 0
for _, path in ipairs(files) do
    local source = fs.readFile(path)
    -- `load` compiles without running, which is exactly the check we want: the
    -- engine runner cannot be executed here (it needs game services), but its
    -- syntax can be proven before it is handed over again.
    -- `compile` parses and codegens without running, which is exactly the check
    -- wanted here: the engine runner cannot be EXECUTED outside Studio, but its
    -- syntax can be proven before it is handed over a second time.
    local ok, err = pcall(luau.compile, source)
    if ok then
        print(("ok    %s"):format(path))
    else
        bad += 1
        print(("FAIL  %s\n      %s"):format(path, tostring(err)))
    end
end
if bad > 0 then error("syntax errors", 0) end
