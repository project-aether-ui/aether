--!strict
--[[
	Stories that are WRONG on purpose (ms-53 P3).

	Every check in `host/Checks.luau` needs a subject that violates it, or the
	check is a thing nobody has seen fail. These are that subject -- one story per
	rule, each isolating exactly one -- and `verify_frame_checks` requires each to
	be caught and requires the clean one beside it not to be.

	They are stories rather than a fixture table so they are also VISIBLE: run
	`--browse` and you can look at what a caught violation actually looks like,
	which is the difference between a rule and a rule someone believes.

	NOT SHIPPED ANYWHERE. `<pkg>/stories/` never reaches a DataModel, and these in
	particular would be embarrassing if it did.
]]

local Aether = require("../src")

local host = Aether.Host.detect()
local V = host.Vocabulary

--- The palette is the real one from ShopUI's call-to-action, because the contrast
--- story should reproduce a defect this repo actually has rather than an invented
--- worst case: white on #38BDF8 measures 2.14:1 against WCAG AA's 4.5.
local SKY = V.Color3.fromRGB(56, 189, 248)
local SLATE = V.Color3.fromRGB(15, 23, 42)
local WHITE = V.Color3.fromRGB(255, 255, 255)
local BLUE = V.Color3.fromRGB(0, 0, 255)

local function box(name: string, w: number, h: number, fill: any, children: { any }): any
	return host.create("Frame")({
		Name = name,
		Size = V.UDim2.fromOffset(w, h),
		Position = V.UDim2.fromOffset(40, 40),
		BackgroundColor3 = fill,
		BackgroundTransparency = 0,
		table.unpack(children),
	})
end

local function label(text: string, w: number, h: number, colour: any, size: number): any
	return host.create("TextLabel")({
		Name = "Subject",
		Size = V.UDim2.fromOffset(w, h),
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		TextColor3 = colour,
	})
end

return {
	Title = "Aether/Checks/Violations",
	--- EVERY STORY HERE BREAKS A RULE ON PURPOSE, so `aether-cli check` skips the
	--- file unless a story is named with `--story`. `verify_frame_checks` names
	--- each one, which is how the rules are proven to bite without making the
	--- command red on every ordinary run.
	Fixture = true,
	Stories = {
		--- THE CONTROL. Everything the others violate, satisfied -- so a checker
		--- that simply flags everything is caught by the same suite that proves
		--- the others fail.
		{
			Name = "Clean",
			Build = function()
				return box("CleanBox", 420, 60, SLATE, { label("Readable", 400, 40, WHITE, 18) })
			end,
		},
		--- Wider than its box by a wide margin, so no measurement slack can
		--- swallow it.
		{
			Name = "Overflowing text",
			Build = function()
				return box("OverflowBox", 420, 60, SLATE, {
					label("This sentence is far too long to fit inside the box it was given", 90, 40, WHITE, 18),
				})
			end,
		},
		--- Fits horizontally; the LINE is taller than the box.
		{
			Name = "Vertically clipped text",
			Build = function()
				return box("VerticalBox", 420, 60, SLATE, { label("Tall", 400, 6, WHITE, 28) })
			end,
		},
		--- White on sky blue: the ShopUI call-to-action, isolated.
		--- WHERE THE FORMULA MATTERS, and this story exists because the gate
		--- could not tell that it did.
		---
		--- `Checks` uses WCAG relative luminance, whose per-channel weights are
		--- wildly uneven -- blue contributes 0.0722 against green's 0.7152 --
		--- because human vision is. Poisoning that to a naive `(r+g+b)/3` left
		--- `verify_frame_checks` GREEN: white on sky blue fails under BOTH
		--- formulas, so no existing case could see the difference.
		---
		--- Blue on white separates them. WCAG measures 8.59:1 and passes; a naive
		--- average measures 2.74:1 and reports a violation that is not there. So
		--- this story must stay SILENT, and it goes red the moment the weights are
		--- replaced by an average -- which is the only way the curve's correctness
		--- is actually asserted rather than merely commented.
		{
			Name = "Blue on white, legible",
			Build = function()
				return box("WeightsBox", 420, 60, WHITE, { label("Readable", 400, 40, BLUE, 18) })
			end,
		},
		--- ALLOWED, and the allowance is the point of the story. A subject that
		--- breaks a rule on purpose says so here, beside the thing it excuses --
		--- and `verify_frame_checks` asserts that this exact story is caught
		--- WITHOUT the allowance and silent WITH it, so the mechanism is proven
		--- rather than trusted.
		{
			Name = "Low contrast, allowed",
			Allow = { "contrast" },
			Build = function()
				return box("AllowedBox", 420, 60, SKY, { label("CLAIM ITEM", 400, 40, WHITE, 18) })
			end,
		},
		{
			Name = "Low contrast text",
			Build = function()
				return box("ContrastBox", 420, 60, SKY, { label("CLAIM ITEM", 400, 40, WHITE, 18) })
			end,
		},
		--- FITS IN ENGLISH AND NOT IN GERMAN. The check only fires under
		--- `--expand`, so this story is what separates "the localisation mode
		--- works" from "the overflow check works".
		{
			Name = "Fits in English only",
			Build = function()
				return box("LocaleBox", 420, 60, SLATE, { label("Settings", 74, 40, WHITE, 18) })
			end,
		},
	},
}
