--!strict
--[[
	spektr/zune_host · TextOrigin — where a run of text starts, given its box.

	ONE RULE, THREE PAINTERS (ms-52 M12). `Live.Frame` carries the alignment and
	every painter resolves it the same way; when it did not, all three invented
	the same `n.x + 10` inset and es9 saw it as "none of our external renderers
	centre the icons".

	SPLIT OUT OF `NativePainter` (ms-53 P2), which is where it lived for no reason
	other than being written there first. It is pure arithmetic over a display
	node -- no DC, no platform -- but requiring the GDI painter to reach it pulled
	`Win32` into every consumer, and that is what stopped `RasterPainter` (and
	therefore the headless CLI) from running anywhere but Windows.

	A shared rule belongs where every sharer can reach it. `verify_headless_is_portable`
	is what keeps that true from here on.
]]

local TextOrigin = {}

--- `leftalign` replays the invented inset: text pinned to the left edge plus ten
--- pixels regardless of what the frame asked for. Kept here with the rule it
--- sabotages so the poison and the code it poisons cannot drift apart.
local poison: string? = nil

function TextOrigin.SetPoison(name: string?)
	poison = name
end

function TextOrigin.Resolve(n: any, measuredWidth: number, lineHeight: number): (number, number)
	local x
	local align = if poison == "leftalign" then "left" else (n.textAlignX or "center")
	if align == "left" then
		x = if poison == "leftalign" then n.x + 10 else n.x
	elseif align == "right" then
		x = n.x + n.w - measuredWidth
	else
		x = n.x + (n.w - measuredWidth) / 2
	end

	local y
	local valign = n.textAlignY or "center"
	if valign == "top" then
		y = n.y
	elseif valign == "bottom" then
		y = n.y + n.h - lineHeight
	else
		y = n.y + (n.h - lineHeight) / 2
	end
	return x, y
end

return TextOrigin
