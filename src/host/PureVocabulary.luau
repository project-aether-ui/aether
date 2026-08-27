--!strict
--[[
	Aether · host/PureVocabulary — the value vocabulary, in Luau alone (ms-52 M6).

	WHY THIS EXISTS
	`Headless.luau` took the whole vocabulary from `@lune/roblox`, and its own
	comment anticipated this file: "A future non-Roblox host implements the same
	eleven names. They are not really Roblox types: UDim2 is {scale, offset} per
	axis and Color3 is three floats."

	That was correct, and until a third runtime existed nobody had to act on it.
	Running Aether under zune resolved every relative require in the tree and
	stopped on exactly one line — `require("@lune/roblox")` — which made the gap
	concrete: the framework's claim that a component names no engine type was true
	of the components and false of the host serving them. The vocabulary was not
	an abstraction, it was one runtime's types borrowed.

	WHAT THIS IS NOT: a Roblox emulation. These carry the fields the framework
	reads and the arithmetic it performs, and nothing else. Where Lune's real
	types are available they are still preferred — they are the engine's own
	semantics and every existing suite is calibrated against them. This is the
	fallback that makes a runtime without them possible at all.

	THE ONE THING WORTH BEING CAREFUL ABOUT: `tostring`. Layout asks
	`tostring(FillDirection):find("Horizontal")`, so an enum that stringifies as
	"table: 0x..." silently lays every list out vertically. The enums below
	stringify as `Enum.Category.Member`, which is what Roblox does and what that
	code already depends on.
]]

local V = {}

--- UDim ------------------------------------------------------------------

local UDimMT = {}
UDimMT.__kind = "UDim"
UDimMT.__index = UDimMT
UDimMT.__tostring = function(self): string
	return `{self.Scale}, {self.Offset}`
end
UDimMT.__eq = function(a, b): boolean
	return a.Scale == b.Scale and a.Offset == b.Offset
end
UDimMT.__add = function(a, b)
	return V.UDim.new(a.Scale + b.Scale, a.Offset + b.Offset)
end
UDimMT.__sub = function(a, b)
	return V.UDim.new(a.Scale - b.Scale, a.Offset - b.Offset)
end

V.UDim = {}
function V.UDim.new(scale: number?, offset: number?): any
	return setmetatable({ Scale = scale or 0, Offset = offset or 0 }, UDimMT)
end

--- UDim2 -----------------------------------------------------------------

local UDim2MT = {}
UDim2MT.__kind = "UDim2"
UDim2MT.__index = UDim2MT
UDim2MT.__tostring = function(self): string
	return `{self.X.Scale}, {self.X.Offset}, {self.Y.Scale}, {self.Y.Offset}`
end
UDim2MT.__eq = function(a, b): boolean
	return a.X == b.X and a.Y == b.Y
end
UDim2MT.__add = function(a, b)
	return V.UDim2.new(
		a.X.Scale + b.X.Scale,
		a.X.Offset + b.X.Offset,
		a.Y.Scale + b.Y.Scale,
		a.Y.Offset + b.Y.Offset
	)
end
UDim2MT.__sub = function(a, b)
	return V.UDim2.new(
		a.X.Scale - b.X.Scale,
		a.X.Offset - b.X.Offset,
		a.Y.Scale - b.Y.Scale,
		a.Y.Offset - b.Y.Offset
	)
end

V.UDim2 = {}
function V.UDim2.new(xs: any, xo: number?, ys: number?, yo: number?): any
	--- Roblox accepts both `UDim2.new(xs, xo, ys, yo)` and `UDim2.new(udimX, udimY)`.
	if type(xs) == "table" then
		return setmetatable({ X = xs, Y = xo }, UDim2MT)
	end
	return setmetatable({
		X = V.UDim.new(xs or 0, xo or 0),
		Y = V.UDim.new(ys or 0, yo or 0),
	}, UDim2MT)
end
function V.UDim2.fromScale(x: number?, y: number?): any
	return V.UDim2.new(x or 0, 0, y or 0, 0)
end
function V.UDim2.fromOffset(x: number?, y: number?): any
	return V.UDim2.new(0, x or 0, 0, y or 0)
end

--- Vector2 ---------------------------------------------------------------

local Vector2MT = {}
Vector2MT.__kind = "Vector2"
Vector2MT.__index = function(self, key: string): any
	if key == "Magnitude" then
		return math.sqrt(rawget(self, "X") ^ 2 + rawget(self, "Y") ^ 2)
	elseif key == "Unit" then
		local m = math.sqrt(rawget(self, "X") ^ 2 + rawget(self, "Y") ^ 2)
		if m == 0 then
			return V.Vector2.new(0, 0)
		end
		return V.Vector2.new(rawget(self, "X") / m, rawget(self, "Y") / m)
	end
	return rawget(Vector2MT, key)
end
Vector2MT.__tostring = function(self): string
	return `{self.X}, {self.Y}`
end
Vector2MT.__eq = function(a, b): boolean
	return rawget(a, "X") == rawget(b, "X") and rawget(a, "Y") == rawget(b, "Y")
end
Vector2MT.__add = function(a, b)
	return V.Vector2.new(rawget(a, "X") + rawget(b, "X"), rawget(a, "Y") + rawget(b, "Y"))
end
Vector2MT.__sub = function(a, b)
	return V.Vector2.new(rawget(a, "X") - rawget(b, "X"), rawget(a, "Y") - rawget(b, "Y"))
end
Vector2MT.__mul = function(a, b)
	if type(b) == "number" then
		return V.Vector2.new(rawget(a, "X") * b, rawget(a, "Y") * b)
	end
	return V.Vector2.new(rawget(a, "X") * rawget(b, "X"), rawget(a, "Y") * rawget(b, "Y"))
end

V.Vector2 = {}
function V.Vector2.new(x: number?, y: number?): any
	return setmetatable({ X = x or 0, Y = y or 0 }, Vector2MT)
end
V.Vector2.zero = V.Vector2.new(0, 0)
V.Vector2.one = V.Vector2.new(1, 1)

--- Color3 ----------------------------------------------------------------

local Color3MT = {}
Color3MT.__kind = "Color3"
Color3MT.__index = Color3MT
--- `Lerp` is a METHOD on the real type, and spektr/scrollbar and the theme
--- pipeline both call it to derive hover and pressed shades.
function Color3MT.Lerp(self, other: any, alpha: number): any
	return V.Color3.new(
		self.R + (other.R - self.R) * alpha,
		self.G + (other.G - self.G) * alpha,
		self.B + (other.B - self.B) * alpha
	)
end
function Color3MT.ToHex(self): string
	return string.format(
		"%02X%02X%02X",
		math.floor(self.R * 255 + 0.5),
		math.floor(self.G * 255 + 0.5),
		math.floor(self.B * 255 + 0.5)
	)
end
Color3MT.__tostring = function(self): string
	return `{self.R}, {self.G}, {self.B}`
end
Color3MT.__eq = function(a, b): boolean
	return a.R == b.R and a.G == b.G and a.B == b.B
end

V.Color3 = {}
function V.Color3.new(r: number?, g: number?, b: number?): any
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3MT)
end
function V.Color3.fromRGB(r: number?, g: number?, b: number?): any
	return V.Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
--- `fromHex` accepts "#RGB", "#RRGGBB" and the same without the hash, which is
--- what the real type accepts and what spektr/scrollbar's defaults use.
function V.Color3.fromHex(hex: string): any
	local h = string.gsub(hex, "^#", "")
	if #h == 3 then
		h = string.gsub(h, "(%x)", "%1%1")
	end
	local r = tonumber(string.sub(h, 1, 2), 16) or 0
	local g = tonumber(string.sub(h, 3, 4), 16) or 0
	local b = tonumber(string.sub(h, 5, 6), 16) or 0
	return V.Color3.new(r / 255, g / 255, b / 255)
end

function V.Color3.fromHSV(h: number, s: number, v: number): any
	--- The standard conversion. Present because theme code uses it to derive
	--- hover and pressed shades from a base colour.
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local m = i % 6
	if m == 0 then
		return V.Color3.new(v, t, p)
	elseif m == 1 then
		return V.Color3.new(q, v, p)
	elseif m == 2 then
		return V.Color3.new(p, v, t)
	elseif m == 3 then
		return V.Color3.new(p, q, v)
	elseif m == 4 then
		return V.Color3.new(t, p, v)
	end
	return V.Color3.new(v, p, q)
end

--- Rect ------------------------------------------------------------------

V.Rect = {}
function V.Rect.new(minX: any, minY: any, maxX: number?, maxY: number?): any
	if type(minX) == "table" then
		return { Min = minX, Max = minY }
	end
	return {
		Min = V.Vector2.new(minX or 0, minY or 0),
		Max = V.Vector2.new(maxX or 0, maxY or 0),
	}
end

--- Sequences -------------------------------------------------------------

V.NumberSequenceKeypoint = {}
function V.NumberSequenceKeypoint.new(time: number, value: number, envelope: number?): any
	return { Time = time, Value = value, Envelope = envelope or 0 }
end

V.NumberSequence = {}
function V.NumberSequence.new(a: any, b: number?): any
	--- Roblox accepts a constant, a from/to pair, or a keypoint list.
	if type(a) == "table" then
		return { Keypoints = a }
	end
	if b ~= nil then
		return {
			Keypoints = {
				V.NumberSequenceKeypoint.new(0, a),
				V.NumberSequenceKeypoint.new(1, b),
			},
		}
	end
	return {
		Keypoints = {
			V.NumberSequenceKeypoint.new(0, a),
			V.NumberSequenceKeypoint.new(1, a),
		},
	}
end

V.ColorSequenceKeypoint = {}
function V.ColorSequenceKeypoint.new(time: number, value: any): any
	return { Time = time, Value = value }
end

V.ColorSequence = {}
function V.ColorSequence.new(a: any, b: any?): any
	if type(a) == "table" and (a :: any)[1] ~= nil then
		return { Keypoints = a }
	end
	if b ~= nil then
		return {
			Keypoints = {
				V.ColorSequenceKeypoint.new(0, a),
				V.ColorSequenceKeypoint.new(1, b),
			},
		}
	end
	return {
		Keypoints = {
			V.ColorSequenceKeypoint.new(0, a),
			V.ColorSequenceKeypoint.new(1, a),
		},
	}
end

--- Font ------------------------------------------------------------------

V.Font = {}
function V.Font.new(family: string, weight: any?, style: any?): any
	return { Family = family, Weight = weight, Style = style }
end

--- Enum ------------------------------------------------------------------

--- Enums that STRINGIFY, which is the part that matters.
---
--- Layout asks `tostring(FillDirection):find("Horizontal")`, so a member that
--- stringifies as "table: 0x..." silently lays every list out vertically. These
--- render as `Enum.Category.Member`, the way Roblox does and the way the code
--- reading them already assumes.
local EnumItemMT = {}
EnumItemMT.__index = EnumItemMT
EnumItemMT.__tostring = function(self): string
	return `Enum.{rawget(self, "_category")}.{rawget(self, "Name")}`
end

local function enum(category: string, members: { string }): any
	local out: any = {}
	for i, name in ipairs(members) do
		out[name] = setmetatable({
			Name = name,
			Value = i - 1,
			_category = category,
		}, EnumItemMT)
	end
	return out
end

--- Only the categories this framework and the kits actually read. A missing one
--- should be added when something needs it, not guessed at now: an enum member
--- that exists but is never read is indistinguishable from one that is wrong.
V.Enum = {
	AutomaticSize = enum("AutomaticSize", { "None", "X", "Y", "XY" }),
	FillDirection = enum("FillDirection", { "Horizontal", "Vertical" }),
	SortOrder = enum("SortOrder", { "Name", "Custom", "LayoutOrder" }),
	HorizontalAlignment = enum("HorizontalAlignment", { "Center", "Left", "Right" }),
	VerticalAlignment = enum("VerticalAlignment", { "Center", "Top", "Bottom" }),
	TextXAlignment = enum("TextXAlignment", { "Left", "Right", "Center" }),
	TextYAlignment = enum("TextYAlignment", { "Top", "Center", "Bottom" }),
	TextTruncate = enum("TextTruncate", { "None", "AtEnd" }),
	Font = enum("Font", {
		"Legacy", "Arial", "ArialBold", "SourceSans", "SourceSansBold",
		"Gotham", "GothamMedium", "GothamBold", "GothamBlack",
	}),
	UserInputType = enum("UserInputType", {
		"MouseButton1", "MouseButton2", "MouseButton3", "MouseWheel",
		"MouseMovement", "Touch", "Keyboard", "Focus",
	}),
	UserInputState = enum("UserInputState", { "Begin", "Change", "End", "Cancel" }),
	KeyCode = enum("KeyCode", { "Unknown", "Backspace", "Return", "Escape", "Left", "Right", "Home", "End", "Delete" }),
	ZIndexBehavior = enum("ZIndexBehavior", { "Global", "Sibling" }),
	ScrollBarInset = enum("ScrollBarInset", { "None", "ScrollBar", "Always" }),
	ApplyStrokeMode = enum("ApplyStrokeMode", { "Contextual", "Border" }),
	EasingStyle = enum("EasingStyle", { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Back", "Bounce", "Elastic" }),
	EasingDirection = enum("EasingDirection", { "In", "Out", "InOut" }),
}

--- WHAT KIND OF VALUE IS THIS? (ms-52 M6)
---
--- `typeof` cannot answer for these. Roblox's typeof reports real datatypes and
--- Lune's reports its own, but plain Luau returns "table" for anything with a
--- metatable -- and it does NOT honour a `__type` or `__typeof` metafield;
--- verified on zune rather than assumed.
---
--- So code that branches on `typeof(v) == "UDim2"` silently takes the wrong
--- branch on a runtime using this vocabulary. Two suites caught exactly that
--- ("thumb geometry evaluates to a UDim2", "SheenOffsetFor yields Vector2"), and
--- production code has the same exposure -- ScrollingFrame already hedges with
--- `typeof(sz) == "UDim2" or (type(sz) == "table" and sz.Y)`, which is somebody
--- having met this before without naming it.
---
--- `KindOf` is the name for it: the real `typeof` when it says something useful,
--- and the tag otherwise.
function V.KindOf(value: any): string
	local native = typeof(value)
	if native ~= "table" then
		return native
	end
	local mt = getmetatable(value)
	if type(mt) == "table" and (mt :: any).__kind then
		return (mt :: any).__kind
	end
	--- The sequence types are plain tables by design -- they carry Keypoints and
	--- nothing else -- so they are recognised structurally.
	if type(value) == "table" and (value :: any).Keypoints ~= nil then
		local first = (value :: any).Keypoints[1]
		if type(first) == "table" and type((first :: any).Value) == "number" then
			return "NumberSequence"
		end
		return "ColorSequence"
	end
	return "table"
end

--- The eleven names, as one table, in the shape `Headless.Vocabulary` expects.
function V.build(): any
	return {
		--- Answers what `typeof` cannot for pure values; see V.KindOf.
		KindOf = V.KindOf,
		UDim = V.UDim,
		UDim2 = V.UDim2,
		Vector2 = V.Vector2,
		Color3 = V.Color3,
		Rect = V.Rect,
		NumberSequence = V.NumberSequence,
		NumberSequenceKeypoint = V.NumberSequenceKeypoint,
		ColorSequence = V.ColorSequence,
		ColorSequenceKeypoint = V.ColorSequenceKeypoint,
		Font = V.Font,
		Enum = V.Enum,
	}
end

return V
