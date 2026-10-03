--!strict
--!tier math
--[=[
	A masked TextInput, mounted on a real host and driven through a live session.

	The engine offers developers no masking (`TextBox.TextInputType` is closed
	to developer scripts), so TextInput draws the bullets itself. What is
	asserted here is what a password field gets wrong when it is only half
	masked: the label, the caret and the click mapping all have to agree on the
	bullets, and the proxy that holds the real text must not paint it.
]=]
local T = require("@testkit")
local Aether = require("../../src/api")
local Deps = require("../../src/Deps")
local Live = require("../../src/host/Live")
local TextInput = require("../../src/TextInput")
local TextInputManager = require("../../src/TextInputManager")

local BULLET = "\u{2022}"
local TEXT_SIZE = 14

local host = Aether.Host.detect()
local V = host.Vocabulary or {
	UDim2 = UDim2,
}

--- The same measurement TextInput uses, so the caret can be checked against
--- the width of the string it should be standing after.
local function width(text: string): number
	if text == "" then
		return 0
	end
	local textService = Deps.Host.Services.TextService
	if textService then
		return textService:GetTextSize(text, TEXT_SIZE, Enum.Font.SourceSans, Vector2.new(10000, 10000)).X
	end
	local w = Deps.Host.Text.Measure(text, TEXT_SIZE, nil)
	return w
end

--- Where a caret drawn after `text` lands. A UDim offset is an integer, so
--- the expected width goes through the same conversion the caret's does.
local function caretAfter(text: string): number
	return V.UDim2.new(0, width(text), 0, 0).X.Offset
end

local function bullets(n: number): string
	return string.rep(BULLET, n)
end

type Mounted = {
	Field: any,
	Session: any,
	Label: () -> any,
	Caret: () -> any,
	Click: (x: number) -> (),
}

--- Mounts one field at y = 400 in a 400 x 500 session and hands `body` what
--- it needs to drive it. Focus is always released afterwards, so one test's
--- field cannot receive the next test's keys.
local function withField(props: { [string]: any }, body: (Mounted) -> ())
	local destroy = host.root(function()
		TextInputManager.Blur(false)

		props.Size = V.UDim2.new(0, 200, 0, 32)
		props.TextSize = TEXT_SIZE
		local field = TextInput(props :: any)

		local screen = host.create("ScreenGui")({ Name = "MaskedScreen", Enabled = true })
		local holder = host.create("Frame")({
			Name = "MaskedHolder",
			Parent = screen,
			Position = V.UDim2.new(0, 0, 0, 400),
			Size = V.UDim2.new(0, 200, 0, 32),
			BackgroundTransparency = 1,
			field,
		})

		local session = Live.Session(host, holder, Aether.PointerRouter, 400, 500)
		session.Step(1 / 60)

		local function label()
			return field:FindFirstChild("DisplayLabel")
		end

		body({
			Field = field,
			Session = session,
			Label = label,
			Caret = function()
				return field:FindFirstChild("VirtualCaret")
			end,
			--- A click `x` pixels right of where the label's text starts.
			Click = function(x: number)
				local at = label().AbsolutePosition.X + x
				session.Pointer("down", at, 416)
				session.Pointer("up", at, 416)
				session.Step(1 / 60)
			end,
		})
	end)
	TextInputManager.Blur(false)
	destroy()
end

local function testMaskedDisplayString()
	withField({ Value = "hunter2", Masked = true }, function(m)
		local shown = m.Label().Text
		assert(shown == bullets(7), `a masked field should show seven bullets, got "{shown}"`)
	end)
end

--- One bullet per CODEPOINT. "pä$s" is five bytes and four characters; a mask
--- built from `#text` would show five.
local function testOneBulletPerCodepoint()
	local value = "p\u{00E4}$s"
	assert(#value == 5, "the fixture is five bytes")
	withField({ Value = value, Masked = true }, function(m)
		local shown = m.Label().Text
		assert(shown == bullets(4), `"pä$s" should show four bullets, got "{shown}" ({#shown} bytes)`)
	end)
end

--- The caret stands after the BULLETS, not after where the real glyphs would
--- have ended. "WWi" is chosen because it measures nothing like three bullets,
--- so the assertion cannot pass by coincidence.
local function testCaretMeasuresTheMaskedPrefix()
	assert(caretAfter(bullets(3)) ~= caretAfter("WWi"), "the fixture must measure differently masked and unmasked")
	withField({ Value = "WWi", Masked = true }, function(m)
		m.Click(190)
		assert(TextInputManager.GetActiveField() ~= nil, "clicking the field should focus it")
		local caret = TextInputManager.GetSelection()
		assert(caret == 4, `a click past the end puts the caret last, got {caret}`)
		local x = m.Caret().Position.X.Offset
		assert(x == caretAfter(bullets(3)), `the caret should sit after three bullets ({caretAfter(bullets(3))}), got {x}`)

		m.Session.Key("Left")
		m.Session.Step(1 / 60)
		local x2 = m.Caret().Position.X.Offset
		assert(x2 == caretAfter(bullets(2)), `after Left it should sit after two bullets ({caretAfter(bullets(2))}), got {x2}`)

		--- CLICK MAPPING follows the bullets too: a click just past the second
		--- bullet lands between the second and third characters.
		local b = width(bullets(1))
		m.Click(2 * b + b / 4)
		local mapped = TextInputManager.GetSelection()
		assert(mapped == 3, `a click just past the second bullet should map to 3, got {mapped}`)
	end)
end

local function testPlaceholderIsNotMasked()
	withField({ Value = "", PlaceholderText = "Password", Masked = true }, function(m)
		local shown = m.Label().Text
		assert(shown == "Password", `the placeholder is never masked, got "{shown}"`)
	end)
end

--- A "show password" toggle flips the mask while the field is focused and
--- holding typed text, and the real text keeps flowing out through OnChanged.
local function testTogglingMaskedLive()
	local masked = Deps.vide.source(true)
	local changed: string? = nil
	withField({
		Value = "ab",
		Masked = masked,
		OnChanged = function(next: string)
			changed = next
		end,
	}, function(m)
		m.Click(190)
		m.Session.Key("c")
		m.Session.Step(1 / 60)
		assert(changed == "abc", `OnChanged carries the real text, got "{tostring(changed)}"`)
		assert(m.Label().Text == bullets(3), `masked, the label shows bullets, got "{m.Label().Text}"`)
		assert(m.Caret().Position.X.Offset == caretAfter(bullets(3)), "masked, the caret follows the bullets")

		masked(false)
		m.Session.Step(1 / 60)
		assert(m.Label().Text == "abc", `unmasked, the label shows the text, got "{m.Label().Text}"`)
		assert(m.Caret().Position.X.Offset == caretAfter("abc"), "unmasked, the caret follows the text")

		masked(true)
		m.Session.Step(1 / 60)
		assert(m.Label().Text == bullets(3), `masked again, the label shows bullets, got "{m.Label().Text}"`)
	end)
end

--- Aether has no clipboard path, and a masked field must not grow one: copy
--- and cut chords go unconsumed and cut removes nothing.
local function testCopyAndCutDoNotTakeTheText()
	local changed: string? = nil
	withField({
		Value = "secret",
		Masked = true,
		OnChanged = function(next: string)
			changed = next
		end,
	}, function(m)
		m.Click(190)
		m.Session.Step(1 / 60)
		--- Focusing loads the text into the proxy, which reports it once.
		changed = nil
		m.Session.Key("a", { Ctrl = true })
		assert(m.Session.Key("c", { Ctrl = true }) == false, "copy is not consumed by a masked field")
		assert(m.Session.Key("x", { Ctrl = true }) == false, "cut is not consumed by a masked field")
		assert(m.Session.Key("Copy") == false and m.Session.Key("Cut") == false, "nor are named copy and cut keys")
		m.Session.Step(1 / 60)
		assert(changed == nil, `cut must not edit the text, got "{tostring(changed)}"`)
		assert(m.Label().Text == bullets(6), "and the field still shows six bullets")
	end)
end

--- THE PROXY HOLDS THE REAL TEXT, so it is the one place a masked field could
--- still leak it to the screen. It must be invisible and fully transparent.
local function testProxyNeverPaints()
	withField({ Value = "hunter2", Masked = true }, function(m)
		m.Click(190)
		local proxy = TextInputManager._Proxy()
		assert(proxy ~= nil, "focusing a field creates the proxy")
		assert(proxy.Text == "hunter2", `the proxy holds the real text, got "{tostring(proxy.Text)}"`)
		assert(proxy.Visible == false, "the proxy must not be visible")
		assert(proxy.TextTransparency == 1, "the proxy's text must be fully transparent")
		assert(proxy.BackgroundTransparency == 1, "and so must its background")
		--- Hidden must not mean deaf: on Dew the native keystrokes reach the
		--- proxy only while it holds focus.
		assert(proxy:IsFocused() == true, "a hidden proxy still holds keyboard focus")
	end)
end

T.test("a masked field shows one bullet per character", testMaskedDisplayString, "math")
T.test("a masked field counts codepoints, not bytes", testOneBulletPerCodepoint, "math")
T.test("caret and click mapping measure the masked string", testCaretMeasuresTheMaskedPrefix, "math")
T.test("the placeholder is never masked", testPlaceholderIsNotMasked, "math")
T.test("Masked can be toggled live while focused", testTogglingMaskedLive, "math")
T.test("copy and cut do not take a masked field's text", testCopyAndCutDoNotTakeTheText, "math")
T.test("the proxy holding the real text never paints", testProxyNeverPaints, "math")

return T.run("TextInputMasked")
