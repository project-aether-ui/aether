--!strict
--[=[
	Tooltip — Composite Headless Primitive (Hover-Dwell Floating Badge)
	Part of Aether.Primitives (Layer 2B Composite).
	
	Embeds:
	- Aether.Engine.useHover (pointer dwell detection)
	- Aether.Engine.useFloating (spatial auto-flip & boundary clamping)
	- Aether.Primitives.ScopedSurface (floating container)
]=]

local Deps = require("../Deps")
local useHover = require("../useHover")
local useFloating = require("../useFloating")
local ScopedSurface = require("../ScopedSurface")
local TooltipMachine = require("../core/TooltipMachine")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local UDim2, UDim, Color3, Enum =
	Deps.Vocabulary.UDim2, Deps.Vocabulary.UDim, Deps.Vocabulary.Color3, Deps.Vocabulary.Enum

local create = Deps.create
local source = Deps.source
local action = Deps.action

export type TooltipProps = {
	Anchor: (GuiObject | (() -> GuiObject?))?,
	Child: any?,
	Content: string | (() -> any),
	Placement: string?,
	Delay: number?,
	Offset: number?,
	RenderContent: ((text: string) -> any)?,
}

local function Tooltip(props: TooltipProps): any
	local isOpen = source(false)

	--- THE RULE LIVES IN `core/TooltipMachine`, and this is the binding half.
	--- Hover, wait, show; leave, hide, cancel anything pending -- none of that is
	--- about vide or about Roblox, and it used to be a `task.delay` thread closed
	--- over by an effect, which meant the only way to ask whether it was right
	--- was to mount a component.
	---
	--- What stays here is what a machine has no business owning: the scheduler it
	--- is handed, and mirroring its state into a source the tree can read.
	local machine = TooltipMachine.new({
		Delay = props.Delay,
		Schedule = function(seconds: number, fn: () -> ()): () -> ()
			local thread = task.delay(seconds, fn)
			return function()
				task.cancel(thread)
			end
		end,
	})

	machine.Subscribe(function()
		isOpen(machine.IsOpen())
	end)

	Deps.cleanup(function()
		machine.Destroy()
	end)

	local hoverHandle = useHover()
	local isHovered = hoverHandle.IsHovered
	local childRef = source(nil :: GuiObject?)

	if props.Anchor then
		if typeof(props.Anchor) == "function" then
			Deps.effect(function()
				local a = (props.Anchor :: any)()
				if a and typeof(a) == "Instance" and (a :: any):IsA("GuiObject") then
					hoverHandle.Bind(a)
				end
			end)
		elseif typeof(props.Anchor) == "Instance" and (props.Anchor :: any):IsA("GuiObject") then
			hoverHandle.Bind(props.Anchor :: any)
		end
	end

	--- The only thing the binding decides: hovering means Enter, and not hovering
	--- means Leave. Everything downstream of that is the machine's.
	Deps.effect(function()
		if isHovered() then
			machine.Enter()
		else
			machine.Leave()
		end
	end)

	local effectiveAnchor = function()
		if props.Anchor then
			return if typeof(props.Anchor) == "function" then (props.Anchor :: any)() else props.Anchor
		end
		return childRef()
	end

	local floating = useFloating({
		Anchor = effectiveAnchor,
		Placement = (props.Placement or "top") :: any,
		Offset = props.Offset or 6,
		AutoFlip = true,
		IsOpen = isOpen,
	})

	local renderBadge = function()
		if not isOpen() then return nil end

		return ScopedSurface {
			Name = "AetherTooltip",
			Layer = "Tooltips",
			Position = floating.Position,
			Size = UDim2.new(0, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = Color3.fromRGB(15, 20, 30),
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			ZIndex = 100,

			create "UICorner" { CornerRadius = UDim.new(0, 6) },
			create "UIStroke" { Color = Color3.fromRGB(60, 80, 120), Thickness = 1, Transparency = 0.3 },
			create "UIPadding" {
				PaddingTop = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 6),
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			},

			if typeof(props.Content) == "string" then
				if props.RenderContent then
					props.RenderContent(props.Content)
				else
					create "TextLabel" {
						BackgroundTransparency = 1,
						AutomaticSize = Enum.AutomaticSize.XY,
						Text = props.Content,
						TextColor3 = Color3.fromRGB(240, 240, 240),
						TextSize = 10,
						Font = Enum.Font.GothamMedium,
						ZIndex = 101,
					}
			elseif typeof(props.Content) == "function" then
				props.Content()
			else
				props.Content,
		}
	end

	if props.Child then
		return create "Frame" {
			Name = "TooltipContainer",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,

			action(function(node: GuiObject)
				if node then
					hoverHandle.Bind(node)
					childRef(node)
				end
			end),

			props.Child,
			renderBadge,
		}
	end

	return renderBadge
end

return Tooltip
