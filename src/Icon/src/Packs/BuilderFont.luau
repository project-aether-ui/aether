local BuilderFontPack: any = {
	GetIcon = function(name: string)
		return {
			Type = "Font",
			Font = Font.new("rbxasset://LuaPackages/Packages/_Index/BuilderIcons/BuilderIcons/BuilderIcons.json"),
			Glyph = name,
			IsLigature = true,
		}
	end
}

return BuilderFontPack