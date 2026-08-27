--!strict
--[[
	Aether · host/Svg — the SECOND host, and an instrument.

	WHY (ms-51 M21)
	es9, after the first Studio playtest: "there's a bit of a challenge in knowing
	what exactly within the UI I'm seeing in the roblox host is actually flowing
	from Aether, and what behaviours/presentations are still coming from other
	packages coupled directly to the roblox host and/or hand-rolled."

	A manual audit answers that once and rots immediately. A SECOND HOST answers it
	by construction and keeps answering it: whatever appears here reached the page
	through `Aether.Host.create` and the Scene contract, and whatever is missing
	did not. The instrument cannot flatter the architecture, because it can only
	draw what it was actually given.

	It also makes es9's own prediction testable rather than assumed — that themes
	and sound packs would NOT render here, because those token engines do not
	integrate with Aether yet. If a colour shows up, it came through `create`; if
	the whole tree is grey, the theme layer is resolving somewhere Aether cannot
	see.

	WHY SVG rather than a terminal or a native window: it needs no runtime beyond
	`fs.writeFile`, it is genuinely visual rather than an approximation of one, and
	it is TEXT — so two renders diff, and a visual regression is a line in a patch
	rather than a screenshot someone has to eyeball.

	WHAT IT DRAWS: rectangles with fill and transparency, corner radii from
	UICorner, clipping from ClipsDescendants, text content and colour, in the paint
	order HitTest.RendersAbove would arbitrate.

	WHAT IT DOES NOT: gradients, strokes and images. They are omissions, not
	approximations — a renderer that guessed would make the audit lie, which is the
	one thing this must never do. ms-52 M2 adds them.

	TEXT MEASUREMENT ARRIVED IN ms-52 M1, so `AutomaticSize` now resolves here and
	this note no longer excludes it.
]]

local Layout = require("./Layout")

local Svg = {}

export type RenderOptions = {
	Width: number?,
	Height: number?,
	--- Draw a labelled outline around every element, so an unfilled or
	--- zero-alpha node is still visible AS a node. This is what turns the output
	--- from a picture into an audit.
	Annotate: boolean?,
	Background: string?,
}

local function esc(s: string): string
	s = string.gsub(s, "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	s = string.gsub(s, '"', "&quot;")
	return s
end

local function round(n: number): string
	return string.format("%.2f", n)
end

--- A Color3 as an SVG hex string. nil when the node carries no colour, which is
--- itself information: it means nothing set one.
local function colorOf(c: any): string?
	if c == nil then
		return nil
	end
	local r = math.floor((c.R or 0) * 255 + 0.5)
	local g = math.floor((c.G or 0) * 255 + 0.5)
	local b = math.floor((c.B or 0) * 255 + 0.5)
	return string.format("#%02x%02x%02x", r, g, b)
end

--- The rendered corner radius, resolved the way HitTest resolves it: scale
--- against the SMALLER dimension, clamped to half of either.
local function cornerOf(Scene: any, node: any, w: number, h: number): number
	local scale, offset = Scene.RenderedCorner(node)
	if scale == nil and offset == nil then
		return 0
	end
	local resolved = (scale or 0) * math.min(w, h) + (offset or 0)
	return math.max(0, math.min(resolved, w / 2, h / 2))
end

--- Render a built tree to an SVG document.
function Svg.Render(host: any, root: any, options: RenderOptions?): string
	local opts = options or {}
	local width = opts.Width or 1280
	local height = opts.Height or 720
	local Scene = host.Scene

	--- `host` is passed so AutomaticSize resolves (ms-52 M1); without it a
	--- content-sized element renders as a zero rect.
	local solved = Layout.Solve(Scene, root, { X = 0, Y = 0, Width = width, Height = height }, host)

	local parts: { string } = {}
	local function emit(s: string)
		table.insert(parts, s)
	end

	emit(`<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">`)
	emit(`<rect width="100%" height="100%" fill="{opts.Background or "#12141a"}"/>`)

	local clipId = 0
	for _, item in ipairs(solved) do
		local node, rect = item.Node, item.Rect
		if rect.Width > 0 and rect.Height > 0 then
			local class = Scene.ClassOf(node) or "?"
			local name = Scene.Name(node) or class
			local fill = colorOf(Scene.Raw(node, "BackgroundColor3"))
			local transparency = Scene.Raw(node, "BackgroundTransparency") or 0
			local radius = cornerOf(Scene, node, rect.Width, rect.Height)

			local group = ""
			if item.Clip then
				clipId += 1
				local c = item.Clip
				emit(
					`<clipPath id="c{clipId}"><rect x="{round(c.X)}" y="{round(c.Y)}" `
						.. `width="{round(c.Width)}" height="{round(c.Height)}"/></clipPath>`
				)
				group = ` clip-path="url(#c{clipId})"`
			end
			emit(`<g{group}>`)

			--- An element with no colour, or fully transparent, still EXISTS. Drawn
			--- as an outline so the audit shows structure rather than only paint —
			--- an invisible container that reached the page is exactly the kind of
			--- thing this is for.
			if fill and transparency < 1 then
				emit(
					`<rect x="{round(rect.X)}" y="{round(rect.Y)}" width="{round(rect.Width)}" `
						.. `height="{round(rect.Height)}" rx="{round(radius)}" fill="{fill}" `
						.. `fill-opacity="{round(1 - transparency)}"/>`
				)
			elseif opts.Annotate ~= false then
				emit(
					`<rect x="{round(rect.X)}" y="{round(rect.Y)}" width="{round(rect.Width)}" `
						.. `height="{round(rect.Height)}" rx="{round(radius)}" fill="none" `
						.. `stroke="#2c3140" stroke-width="1" stroke-dasharray="3 3"/>`
				)
			end

			local text = Scene.Raw(node, "Text")
			if type(text) == "string" and text ~= "" then
				local tc = colorOf(Scene.Raw(node, "TextColor3")) or "#e6e8ee"
				local size = Scene.Raw(node, "TextSize") or 14
				emit(
					`<text x="{round(rect.X + 6)}" y="{round(rect.Y + rect.Height / 2 + size / 3)}" `
						.. `font-family="ui-sans-serif,system-ui,sans-serif" font-size="{size}" `
						.. `fill="{tc}">{esc(text)}</text>`
				)
			end

			if opts.Annotate ~= false then
				emit(
					`<text x="{round(rect.X + 3)}" y="{round(rect.Y + 10)}" font-family="ui-monospace,monospace" `
						.. `font-size="8" fill="#5b6474">{esc(name)}</text>`
				)
			end

			emit("</g>")
		end
	end

	emit("</svg>")
	return table.concat(parts, "\n")
end

--- Render and write. Returns the solved node count, so a caller can assert that
--- something was actually drawn rather than trusting a file exists.
function Svg.Write(host: any, root: any, path: string, options: RenderOptions?): number
	local fs = require("@lune/fs")
	local doc = Svg.Render(host, root, options)
	fs.writeFile(path, doc)
	local n = 0
	for _ in string.gmatch(doc, "<g") do
		n += 1
	end
	return n
end

return Svg
