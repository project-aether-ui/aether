--!strict
--!tier math
--[=[
	A TextInput's caret, mounted on a real host and driven through a live session.

	The field is built the way a styled form builds one: a face other than the
	host's default, and a UIPadding on the TextInput's own frame. The caret has
	to stand where the label drew the glyphs before it, and it has to blink on
	whichever clock the host drives.
]=]
local T = require("@testkit")
local Aether = require("../../src/api")
local Deps = require("../../src/Deps")
local Live = require("../../src/host/Live")
local TextInput = require("../../src/TextInput")
local TextInputManager = require("../../src/TextInputManager")

local PAD = 10

local host = Aether.Host.detect()
local V = host.Vocabulary or {
	UDim2 = UDim2,
	UDim = UDim,
}

--- Where a node starts: the engine's own geometry in Roblox, the rectangle
--- the live session solved elsewhere.
local function left(node: any): number
	local x = host.Scene.Bounds(node)
	return x
end

--- How wide the label drew its text. Its own `TextBounds` where the host
--- reports one; otherwise the host's measurer, asked in the face the label
--- itself names, which is the face the host draws it in.
local function drawnWidth(label: any): number
	local reported = label.TextBounds
	if reported and reported.X > 0 then
		return reported.X
	end
	local w = Deps.Host.Text.Measure(label.Text, label.TextSize, label.Font)
	return w
end

type Mounted = {
	Session: any,
	Label: any,
	Caret: any,
	Focus: () -> (),
}

local function withField(props: { [any]: any }, body: (Mounted) -> ())
	local destroy = host.root(function()
		TextInputManager.Blur(false)

		props.Size = V.UDim2.new(0, 200, 0, 32)
		props.ClipsDescendants = true
		table.insert(
			props,
			host.create("UIPadding")({
				PaddingLeft = V.UDim.new(0, PAD),
				PaddingRight = V.UDim.new(0, PAD),
			})
		)
		local field = TextInput(props :: any)

		local screen = host.create("ScreenGui")({ Name = "CaretScreen", Enabled = true })
		local holder = host.create("Frame")({
			Name = "CaretHolder",
			Parent = screen,
			Position = V.UDim2.new(0, 0, 0, 400),
			Size = V.UDim2.new(0, 200, 0, 32),
			BackgroundTransparency = 1,
			field,
		})

		local session = Live.Session(host, holder, Aether.PointerRouter, 400, 500)
		session.Step(1 / 60)

		local label = field:FindFirstChild("DisplayLabel")
		body({
			Session = session,
			Label = label,
			Caret = field:FindFirstChild("VirtualCaret"),
			--- A click past the end of the text, which puts the caret last.
			Focus = function()
				local at = left(label) + 170
				session.Pointer("down", at, 416)
				session.Pointer("up", at, 416)
				session.Step(1 / 60)
			end,
		})
	end)
	TextInputManager.Blur(false)
	destroy()
end

--- The caret after the last character stands at the right edge of what the
--- label drew. The UIPadding on the frame insets the label and the caret
--- alike, and Arimo is not the host's default face, so a caret measured in
--- any other face misses by a visible margin.
local function caretAtDrawnEnd(value: string, masked: boolean)
	withField({ Value = value, Masked = masked, Font = Enum.Font.Arimo, TextSize = 14 }, function(m)
		m.Focus()
		assert(TextInputManager.GetSelection() == #value + 1, "the click should put the caret last")
		local labelX = left(m.Label)
		local frameX = left(m.Label.Parent)
		assert(labelX == frameX + PAD, `the label starts inside the padding ({frameX + PAD}), got {labelX}`)
		local drawn = drawnWidth(m.Label)
		assert(drawn > 0, "the label drew something")
		local expected = labelX + drawn
		local x = left(m.Caret)
		assert(
			math.abs(x - expected) <= 1,
			`the caret should stand at the drawn end {expected} (label {labelX} + {drawn}), got {x}`
		)
	end)
end

local function testMaskedCaretFollowsTheBullets()
	caretAtDrawnEnd("hunter22", true)
	caretAtDrawnEnd("abc", true)
end

local function testPlainCaretFollowsTheText()
	caretAtDrawnEnd("Wide words", false)
end

--- Focused and left alone, the caret blinks: over two seconds of frames on
--- the host's clock it hides and comes back.
local function testCaretBlinks()
	withField({ Value = "abc", Font = Enum.Font.Arimo, TextSize = 14 }, function(m)
		m.Focus()
		assert(m.Caret.Visible == true, "a freshly focused caret is drawn")
		local hidden, shownAgain = false, false
		for _ = 1, 120 do
			m.Session.Step(1 / 60)
			if not m.Caret.Visible then
				hidden = true
			elseif hidden then
				shownAgain = true
			end
		end
		assert(hidden, "the caret never hid over two seconds of frames")
		assert(shownAgain, "the caret hid and never came back")

		--- A keystroke shows it again at once.
		while m.Caret.Visible do
			m.Session.Step(1 / 60)
		end
		m.Session.Key("d")
		m.Session.Step(1 / 60)
		assert(m.Caret.Visible == true, "a keystroke shows the caret again")
	end)
end

T.test("the masked caret stands after the drawn bullets", testMaskedCaretFollowsTheBullets, "math")
T.test("the caret stands after the drawn text", testPlainCaretFollowsTheText, "math")
T.test("a focused caret blinks on the host's clock", testCaretBlinks, "math")

return T.run("TextInputCaret")
