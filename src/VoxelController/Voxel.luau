-- Facet
-- VoxelController/Voxel.luau
-- Plinko Labs
--
-- Wraps one produced BasePart with the extra behaviour Result.Voxels entries carry: a
-- Cleanup runner (Rebuild / Fade / Destroy / custom function) and, for Whole-kind voxels
-- (an untouched part isolated by the hitbox but never sliced), a follow-up :Shatter() that
-- only accepts Effects/Size - there's no hitbox left to detect against, the part IS the target.

local TweenService = game:GetService("TweenService")
local Enums = require(script.Parent.Parent.Enums)

export type Kind = "Whole" | "Partial" | "Extra"

export type ShatterSizeConfig = {
	Effects: { [string]: any }?,
	Size: number?,
}

export type Voxel = {
	Instance: BasePart,
	Kind: Kind,
	OriginalCFrame: CFrame,
	Cleanup: (self: Voxel, method: (Enums.Cleanup | ((Voxel) -> ())?)) -> (),
	Shatter: ((self: Voxel, config: ShatterSizeConfig?) -> any)?,
}

local Voxel = {}
Voxel.__index = Voxel

local function applyEffects(instance: BasePart, effects: { [string]: any }?, origin: Vector3?)
	if not effects then
		return
	end
	for key, value in effects do
		if key == Enums.Effects.Explode then
			local radius = (value :: any).Radius or 4
			local offset = instance.Position - (origin or instance.Position)
			local direction = if offset.Magnitude > 1e-3 then offset.Unit else Vector3.new(0, 1, 0)
			instance.AssemblyLinearVelocity = direction * radius
		elseif key == Enums.Effects.Anchored then
			instance.Anchored = value :: boolean
		elseif key == "Velocity" then
			instance.AssemblyLinearVelocity = value :: Vector3
		end
	end
end

function Voxel.new(instance: BasePart, kind: Kind, controller: any): Voxel
	local self = setmetatable({
		Instance = instance,
		Kind = kind,
		OriginalCFrame = instance.CFrame,
		_controller = controller,
	}, Voxel)

	if kind == Enums.HitboxType.Whole then
		function self:Shatter(config: ShatterSizeConfig?)
			config = config or {}
			if (config :: any).Hitbox then
				error("Voxel:Shatter() on a Whole voxel only accepts Effects/Size - there is no hitbox to detect against", 2)
			end
			return controller:Shatter(self.Instance, config)
		end
	end

	return (self :: any) :: Voxel
end

function Voxel:Cleanup(method)
	method = method or self._controller._cleanup
	if type(method) == "function" then
		method(self)
		return
	end

	if method == Enums.Cleanup.Destroy then
		self.Instance:Destroy()
	elseif method == Enums.Cleanup.Fade then
		local tween = TweenService:Create(self.Instance, TweenInfo.new(0.5), { Transparency = 1 })
		tween.Completed:Once(function()
			self.Instance:Destroy()
		end)
		tween:Play()
	elseif method == Enums.Cleanup.Rebuild then
		self.Instance.Anchored = true
		local tween = TweenService:Create(self.Instance, TweenInfo.new(0.6), { CFrame = self.OriginalCFrame })
		tween:Play()
	end
end

return { new = Voxel.new, applyEffects = applyEffects }
