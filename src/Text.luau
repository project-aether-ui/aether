--!strict
local isRoblox = typeof(game) == "Instance"
--- ms-43 M119: the package's OWN tree, not the application's.
---
--- This read `ReplicatedStorage.roblox_packages`, which is whatever the HOST
--- installed rather than what this package declares. It worked only because the
--- demo installs everything, so the wrong tree happened to hold the right
--- answers — and it would have broken the moment this package shipped alone.
---
--- pesde generates `<package>/roblox_packages/<Dep>.luau` for every declared
--- dependency, and from a module inside `src/` that folder sits BESIDE src, one
--- hop further out. Two `.Parent` hops, not one.
---
--- It also makes this file TESTABLE: a ReplicatedStorage lookup at module scope
--- has no headless branch, so nothing here could ever run outside Roblox.
--- ms-51 M16: resolved here purely for the value vocabulary below.
local Deps = require("./Deps")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below is unchanged.
local UDim2, Color3, Enum =
	Deps.Vocabulary.UDim2, Deps.Vocabulary.Color3, Deps.Vocabulary.Enum

--- vide THROUGH Deps, which already resolved it.
---
--- This file used to find vide for itself: an Instance lookup for
--- `roblox_packages`, then a pcall fallback through `script.Parent.Parent`, then
--- a second pcall for the same thing at a path that had never existed. Twenty
--- lines to obtain `create`, which the module it was already requiring exports.
---
--- Both attempts were pcall'd, so when they failed they failed SILENTLY and
--- `create` was nil — a fault the require-path gate found and no test could,
--- because the headless branch never took either path.
local create = Deps.create

--- OPTIONAL, and not a declared dependency. A consumer that installs
--- `spektr/theme_core` gets scoped theming here; one that does not gets the
--- unthemed path. That is why this alone stays a pcall: the module's absence is
--- a supported configuration rather than a failure to report.
local ThemeCore: any
pcall(function()
	ThemeCore = require("../roblox_packages/ThemeCore")
end)



export type TextVariant = "Title" | "Header" | "Body" | "Muted"

export type TextProps = {
	Text: string | () -> string,
	Scope: string?,
	Variant: TextVariant?,
	PackageFallbackTheme: any?,

	Size: (UDim2 | () -> UDim2)?,
	Position: (UDim2 | () -> UDim2)?,
	AnchorPoint: (Vector2 | () -> Vector2)?,
	TextXAlignment: (Enum.TextXAlignment | () -> Enum.TextXAlignment)?,
	TextYAlignment: (Enum.TextYAlignment | () -> Enum.TextYAlignment)?,
	Visible: (boolean | () -> boolean)?,
}

local function Text(props: TextProps)
	if not create then return nil end

	local scopeTag = props.Scope or "Default"
	local useScopedTheme = ThemeCore and ThemeCore.useScopedTheme
	local getTheme = if useScopedTheme then useScopedTheme(scopeTag, props.PackageFallbackTheme) else function() return props.PackageFallbackTheme or {} end

	local variant = props.Variant or "Body"

	local function getTextColor(): Color3
		local t = getTheme()
		if t and t.Colors then
			if variant == "Muted" then return t.Colors.TextMuted or Color3.fromHex("#888888")
			elseif variant == "Title" or variant == "Header" then return t.Colors.TextSelected or t.Colors.Text or Color3.fromHex("#FFFFFF")
			else return t.Colors.Text or Color3.fromHex("#E0E0E0") end
		end
		return Color3.fromHex("#E0E0E0")
	end

	local function getTextSize(): number
		local t = getTheme()
		local baseSize = (t and t.Sizes and t.Sizes.TextSize) or 14
		if variant == "Title" then return baseSize + 6
		elseif variant == "Header" then return baseSize + 2
		else return baseSize end
	end

	local function getFont(): Enum.Font
		local t = getTheme()
		if t and t.Fonts and t.Fonts.Default then
			return t.Fonts.Default
		end
		return Enum.Font.SourceSans
	end

	return create "TextLabel" {
		Name = `Text_{variant}`,
		Text = props.Text,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left,
		TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center,
		Visible = props.Visible,
		BackgroundTransparency = 1,
		TextColor3 = getTextColor,
		TextSize = getTextSize,
		Font = getFont,
	}
end

return Text
