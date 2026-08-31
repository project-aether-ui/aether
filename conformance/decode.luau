--!strict
--[[
	The value encoding, shared by every runner.

	A case writes `{ "UDim2", 1, 0, 1, 0 }` rather than a constructed value so the
	case is data — readable by a Luau runner, a Roblox runner, and eventually a
	Rust one.

	THIS FILE IS THE REASON THAT WORKS. `UDim2.new` is spelled identically in
	Roblox and against the pure vocabulary, so one decoder serves both and neither
	runner can drift from the other in how it reads a case. If they each had their
	own, a case could mean two different things.
]]

local decode = {}

function decode.value(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local kind = value[1]
	if kind == "UDim2" then
		return UDim2.new(value[2], value[3], value[4], value[5])
	elseif kind == "UDim" then
		return UDim.new(value[2], value[3])
	elseif kind == "Color3" then
		return Color3.new(value[2], value[3], value[4])
	elseif kind == "Vector2" then
		return Vector2.new(value[2], value[3])
	elseif kind == "Enum" then
		--- By NAME, not by number. Roblox's enum values are an implementation
		--- detail, and a case encoding them would assert something the standard
		--- does not say.
		local category = (Enum :: any)[value[2]]
		if not category then
			error(`conformance: no enum category '{value[2]}'`)
		end
		local member = category[value[3]]
		if not member then
			error(`conformance: {value[2]} has no member '{value[3]}'`)
		end
		return member
	end
	error(`conformance: unknown encoded type '{tostring(kind)}'`)
end

--- Properties for one node, decoded, with `Name` folded in.
function decode.props(node: any): { [string]: any }
	local props: { [string]: any } = {}
	for key, value in pairs(node.props or {}) do
		props[key] = decode.value(value)
	end
	if node.name then
		props.Name = node.name
	end
	return props
end

return decode
