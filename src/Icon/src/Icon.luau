local isScript = typeof(script) == "Instance"
--- ms-51 M19: Aether's own headless host, not testkit's VideShim and not the
--- two-function stub that stood behind it — that stub's `create` returned the
--- props table unchanged, which is indistinguishable from working until
--- something reads the result.
---
--- Reachable by a fixed path only because this module is now required BY NAME
--- rather than as a folder; see init.luau beside it for why that mattered.
local Vide = if isScript
	--- ms-51 M19: TWO hops, not one. As `init.luau` this module WAS the folder,
	--- so `script.Parent` was the package root; as a named child module it is
	--- `src`, and roblox_packages sits beside that. verify_require_paths caught
	--- the difference the moment the file was renamed — the same way it caught
	--- flux_motion's when that code moved out of an init.
	then require(script.Parent.Parent.roblox_packages.vide)
	else require("../../host/Headless").new()

local IconManager = {}

export type FontIconDef = { Type: "Font", Font: Font, Glyph: string, IsLigature: boolean? }
export type ImageIconDef = { Type: "Image", Image: string }
export type SpritesheetIconDef = { Type: "Spritesheet", Image: string, Offset: Vector2, Size: Vector2 }
export type EmojiIconDef = { Type: "Emoji", Text: string }

export type IconDefinition = FontIconDef | ImageIconDef | SpritesheetIconDef | EmojiIconDef

export type IconPack = {
	GetIcon: (name: string) -> IconDefinition?
}

local Packs: { [string]: IconPack } = {}
local DefaultPackName: string? = nil

-- Registry API
function IconManager.RegisterPack(name: string, pack: IconPack, isDefault: boolean?)
	Packs[name] = pack
	if isDefault or DefaultPackName == nil then
		DefaultPackName = name
	end
end

function IconManager.GetPack(name: string?): IconPack?
	local targetName = name or DefaultPackName
	if not targetName then return nil end
	return Packs[targetName]
end

-- Component API
export type StrokeProps = {
	Color: (Vide.Source<Color3> | Color3)?,
	Thickness: (Vide.Source<number> | number)?,
	Transparency: (Vide.Source<number> | number)?,
	LineJoinMode: (Vide.Source<Enum.LineJoinMode> | Enum.LineJoinMode)?,
}

export type DropShadowProps = {
	Color: (Vide.Source<Color3> | Color3)?,
	Transparency: (Vide.Source<number> | number)?,
	Offset: (Vide.Source<Vector2> | Vector2)?,
}

export type IconProps = {
	Name: Vide.Source<string> | string,
	Pack: (Vide.Source<string | IconPack> | string | IconPack)?,
	Size: (Vide.Source<UDim2> | UDim2)?,
	Color: (Vide.Source<Color3> | Color3)?,
	LayoutOrder: (Vide.Source<number> | number)?,
	AnchorPoint: (Vide.Source<Vector2> | Vector2)?,
	Position: (Vide.Source<UDim2> | UDim2)?,
	Filled: (Vide.Source<boolean> | boolean)?,
	Stroke: StrokeProps?,
	DropShadow: DropShadowProps?,
	DropShadows: { DropShadowProps }?,
	Padding: (Vide.Source<number | UDim> | number | UDim)?,
	ZIndex: (Vide.Source<number> | number)?,
	Rotation: (Vide.Source<number> | number)?,
}

function IconManager.Icon(props: IconProps)
	local function resolve<T>(v: Vide.Source<T> | T): T
		return type(v) == "function" and (v :: any)() or v
	end

	local currentIconDef = Vide.derive(function()
		local packVal = resolve(props.Pack)
		local pack = nil
		if type(packVal) == "table" and type(packVal.GetIcon) == "function" then
			pack = packVal
		else
			pack = IconManager.GetPack(packVal :: string?)
		end
		if not pack then return nil end
		local name = resolve(props.Name)
		return pack.GetIcon(name)
	end)

	local currentIconType = Vide.derive(function()
		local def = currentIconDef()
		return def and def.Type or "None"
	end)

	-- We use a wrapper frame to allow swapping out TextLabel vs ImageLabel reactively
	return Vide.create("Frame")({
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Active = false,
		Interactable = false,
		
		Vide.changed("AbsoluteSize", function(size)
			-- Can be used if proportional scaling is needed
		end),

		Vide.show(function() return props.Padding ~= nil end, function()
			return Vide.create("UIPadding")({
				PaddingTop = function()
					local pad = resolve(props.Padding)
					return typeof(pad) == "number" and UDim.new(0, pad) or pad :: UDim
				end,
				PaddingBottom = function()
					local pad = resolve(props.Padding)
					return typeof(pad) == "number" and UDim.new(0, pad) or pad :: UDim
				end,
				PaddingLeft = function()
					local pad = resolve(props.Padding)
					return typeof(pad) == "number" and UDim.new(0, pad) or pad :: UDim
				end,
				PaddingRight = function()
					local pad = resolve(props.Padding)
					return typeof(pad) == "number" and UDim.new(0, pad) or pad :: UDim
				end,
			})
		end),
		
		-- Conditionally render TextLabel if it's a Font or Emoji pack
		Vide.show(function() return currentIconType() == "Font" or currentIconType() == "Emoji" end, function()
			local fontFaceSrc = function()
				local def = currentIconDef()
				if def and def.Type == "Font" then
					return (def :: FontIconDef).Font
				end
				return Font.new("")
			end
			
			local textSrc = function()
				local def = currentIconDef()
				if not def then return "" end
				
				if def.Type == "Emoji" then
					return (def :: EmojiIconDef).Text
				elseif def.Type == "Font" then
					local fontDef = def :: FontIconDef
					local text = fontDef.Glyph
					
					local filled = resolve(props.Filled)
					if filled then
						text = `<b>{text}</b>`
					end
					
					return text
				end
				return ""
			end

			return {
				-- Shadow Layers
				Vide.show(function() return props.DropShadow ~= nil or props.DropShadows ~= nil end, function()
					local shadows = {}
					local configs = props.DropShadows or { props.DropShadow }
					for i, shadowProps in ipairs(configs) do
						table.insert(shadows, Vide.create("TextLabel")({
							Name = "Shadow" .. i,
							BackgroundTransparency = 1,
							Size = UDim2.fromScale(1, 1),
							Position = function()
								local offset = shadowProps.Offset or Vector2.new(0, 1)
								return UDim2.fromOffset(offset.X, offset.Y)
							end,
							ZIndex = function()
								local baseZIndex = resolve(props.ZIndex) or 1
								return baseZIndex - 1
							end,
							Rotation = props.Rotation,
							TextScaled = true,
							TextColor3 = function() return shadowProps.Color or Color3.new(0, 0, 0) end,
							TextTransparency = function() return shadowProps.Transparency or 0.5 end,
							Active = false,
							Interactable = false,
							RichText = true,
							FontFace = fontFaceSrc,
							Text = textSrc,
						}))
					end
					return shadows
				end),
				
				-- Main Icon Layer
				Vide.create("TextLabel")({
					Name = "Icon",
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					ZIndex = props.ZIndex or 1,
					Rotation = props.Rotation,
					TextScaled = true,
					TextColor3 = props.Color or Color3.new(1, 1, 1),
					Active = false,
					Interactable = false,
					RichText = true,
					FontFace = fontFaceSrc,
					Text = textSrc,
					
					Vide.show(function() return props.Stroke ~= nil end, function()
						return Vide.create("UIStroke")({
							ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
							Color = props.Stroke and props.Stroke.Color or Color3.new(0, 0, 0),
							Thickness = props.Stroke and props.Stroke.Thickness or 1,
							Transparency = props.Stroke and props.Stroke.Transparency or 0,
							LineJoinMode = props.Stroke and props.Stroke.LineJoinMode or Enum.LineJoinMode.Round,
						})
					end)
				})
			}
		end),
		
		-- Conditionally render ImageLabel if it's an Image or Spritesheet pack
		Vide.show(function() return currentIconType() == "Image" or currentIconType() == "Spritesheet" end, function()
			local imageSrc = function()
				local def = currentIconDef()
				if def then
					if def.Type == "Image" then
						return (def :: ImageIconDef).Image
					elseif def.Type == "Spritesheet" then
						return (def :: SpritesheetIconDef).Image
					end
				end
				return ""
			end
			
			local imageRectOffsetSrc = function()
				local def = currentIconDef()
				if def and def.Type == "Spritesheet" then
					return (def :: SpritesheetIconDef).Offset
				end
				return Vector2.zero
			end
			
			local imageRectSizeSrc = function()
				local def = currentIconDef()
				if def and def.Type == "Spritesheet" then
					return (def :: SpritesheetIconDef).Size
				end
				return Vector2.zero
			end

			return {
				-- Shadow Layers
				Vide.show(function() return props.DropShadow ~= nil or props.DropShadows ~= nil end, function()
					local shadows = {}
					local configs = props.DropShadows or { props.DropShadow }
					for i, shadowProps in ipairs(configs) do
						table.insert(shadows, Vide.create("ImageLabel")({
							Name = "Shadow" .. i,
							BackgroundTransparency = 1,
							Size = UDim2.fromScale(1, 1),
							Position = function()
								local offset = shadowProps.Offset or Vector2.new(0, 1)
								return UDim2.fromOffset(offset.X, offset.Y)
							end,
							ZIndex = function()
								local baseZIndex = resolve(props.ZIndex) or 1
								return baseZIndex - 1
							end,
							Rotation = props.Rotation,
							ImageColor3 = function() return shadowProps.Color or Color3.new(0, 0, 0) end,
							ImageTransparency = function() return shadowProps.Transparency or 0.5 end,
							Active = false,
							Interactable = false,
							Image = imageSrc,
							ImageRectOffset = imageRectOffsetSrc,
							ImageRectSize = imageRectSizeSrc,
						}))
					end
					return shadows
				end),
				
				-- Main Icon Layer
				Vide.create("ImageLabel")({
					Name = "Icon",
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					ZIndex = props.ZIndex or 1,
					Rotation = props.Rotation,
					ImageColor3 = props.Color or Color3.new(1, 1, 1),
					Active = false,
					Interactable = false,
					Image = imageSrc,
					ImageRectOffset = imageRectOffsetSrc,
					ImageRectSize = imageRectSizeSrc,
					
					Vide.show(function() return props.Stroke ~= nil end, function()
						return Vide.create("UIStroke")({
							ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
							Color = props.Stroke and props.Stroke.Color or Color3.new(0, 0, 0),
							Thickness = props.Stroke and props.Stroke.Thickness or 1,
							Transparency = props.Stroke and props.Stroke.Transparency or 0,
							LineJoinMode = props.Stroke and props.Stroke.LineJoinMode or Enum.LineJoinMode.Round,
						})
					end)
				})
			}
		end)
	})
end

-- Preload standard packs
local BuilderFont = if isScript
	then require(script.Parent.Packs.BuilderFont)
	else (function()
		local ok, res = pcall(require, "./Packs/BuilderFont")
		if ok then return res end
		local ok2, res2 = pcall(require, "./src/Icon/src/Packs/BuilderFont")
		if ok2 then return res2 end
		return { GetIcon = function() return nil end }
	end)()
IconManager.RegisterPack("Builder", BuilderFont, true)

local EmojiPack: IconPack = {
	GetIcon = function(name: string)
		return {
			Type = "Emoji",
			Text = name,
		}
	end,
}
IconManager.RegisterPack("Emoji", EmojiPack)

return IconManager

