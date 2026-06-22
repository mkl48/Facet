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
local ConfigModule = require(script.Parent.Parent.Config)
local Pool = require(script.Parent.Parent.Pool)

local Config = ConfigModule.Config

-- Destroy's instant; pooled parts go back to the Pool instead so a later Shatter can reuse the
-- instance rather than allocating a new one - only when Config.ObjectPooling is on and the
-- voxel is actually a plain Part (Pool only ever hands out Parts).
local function destroyOrRelease(instance: BasePart)
	if Config.ObjectPooling and instance:IsA("Part") then
		Pool.release(instance)
	else
		instance:Destroy()
	end
end

-- What bucket of Result.Voxels this voxel landed in: Whole (isolated but never sliced), Partial
-- (sliced debris - the only kind Cleanup ever runs against), or Extra (produced, outside the
-- hitbox, greedy-meshed, left alone unless you Cleanup it yourself).
export type Kind = "Whole" | "Partial" | "Extra"

--[=[
	@interface ShatterSizeConfig
	@within Voxel
	.Effects {[string]: any}? -- same shape as ShatterConfig.Effects.
	.Size number? -- overrides the controller's own sizing rule for just this re-shatter.
]=]
export type ShatterSizeConfig = {
	Effects: { [string]: any }?,
	Size: number?,
}

--[=[
	@class Voxel
	One produced part, wrapped with the behaviour every `Result.Voxels` entry carries. Every
	entry in `Result.Voxels.Whole/Partial/Extra` is one of these, not a bare `BasePart`.
]=]
export type Voxel = {
	Instance: BasePart,
	Kind: Kind,
	--[=[
		@within Voxel
		@prop OriginalCFrame CFrame
		The voxel's own `CFrame` the instant it was created, before any Effect moved it. `Rebuild`
		tweens back to this.
	]=]
	OriginalCFrame: CFrame,
	--[=[
		@within Voxel
		@prop OriginalPosition Vector3
		Shorthand for `OriginalCFrame.Position`.
	]=]
	OriginalPosition: Vector3,
	--[=[
		@within Voxel
		@prop OriginalOrientation Vector3
		Shorthand for `OriginalCFrame`'s Euler angles in degrees, the same shape `BasePart.Orientation` uses.
	]=]
	OriginalOrientation: Vector3,
	--[=[
		@within Voxel
		@prop Distance number?
		Straight-line distance from this voxel's `OriginalPosition` to the Shatter call's origin
		(the hitbox center, or the explicit point passed for indiscriminate destruction). `nil`
		for a no-hitbox Shatter, where there's no single origin to measure from.
	]=]
	Distance: number?,
	--[=[
		@within Voxel
		@method Cleanup
		Runs a Cleanup strategy against this one voxel directly - the same logic Shatter's own
		`Cleanup` config runs against every `Partial` voxel automatically. `duration` only
		applies to `Fade`/`Rebuild` (`Destroy` is instant).
	]=]
	Cleanup: (self: Voxel, method: (Enums.Cleanup | ((Voxel) -> ())?), duration: number?) -> (),
	--[=[
		@within Voxel
		@method Shatter
		Only present on `Whole` voxels (a part the hitbox isolated but never sliced). Re-shatters
		just this part - `config` only accepts `Effects`/`Size`, since there's no hitbox left to
		detect against; the part itself IS the target.
	]=]
	Shatter: ((self: Voxel, config: ShatterSizeConfig?) -> any)?,
}

local Voxel = {}
Voxel.__index = Voxel

-- Tweens `instance` toward zero size, then destroys/releases it - shared by Blackhole (which also
-- tweens CFrame) and Shrink (which doesn't move it).
local function shrinkAway(instance: BasePart, duration: number, extra: { [string]: any }?)
	local goal: { [string]: any } = { Size = Vector3.new(0.05, 0.05, 0.05) }
	if extra then
		for key, value in extra do
			goal[key] = value
		end
	end
	local tween = TweenService:Create(instance, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), goal)
	tween.Completed:Once(function()
		destroyOrRelease(instance)
	end)
	tween:Play()
end

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
		elseif key == Enums.Effects.Slice then
			local config = value :: { Normal: Vector3?, Speed: number? }
			local normal = (config.Normal or Vector3.new(0, 1, 0))
			normal = if normal.Magnitude > 1e-3 then normal.Unit else Vector3.new(0, 1, 0)
			local speed = config.Speed or 8
			local side = (instance.Position - (origin or instance.Position)):Dot(normal)
			instance.Anchored = false
			instance.AssemblyLinearVelocity = normal * speed * (if side >= 0 then 1 else -1)
		elseif key == Enums.Effects.Blackhole then
			local config = value :: { Position: Vector3?, Duration: number? }
			local target = config.Position or origin or instance.Position
			instance.Anchored = false
			instance.CanCollide = false
			shrinkAway(instance, config.Duration or 1, { CFrame = CFrame.new(target) })
		elseif key == Enums.Effects.Whitehole then
			local config = value :: { Position: Vector3?, Speed: number? }
			local center = config.Position or origin or instance.Position
			local offset = instance.Position - center
			local direction = if offset.Magnitude > 1e-3 then offset.Unit else Vector3.new(0, 1, 0)
			instance.Anchored = false
			instance.AssemblyLinearVelocity = direction * (config.Speed or 16)
		elseif key == Enums.Effects.Scatter then
			local config = value :: { Speed: number? }
			local speed = config.Speed or 10
			local random = Vector3.new((math.random() - 0.5) * 2, math.random(), (math.random() - 0.5) * 2)
			instance.Anchored = false
			instance.AssemblyLinearVelocity = (if random.Magnitude > 1e-3 then random.Unit else Vector3.new(0, 1, 0)) * speed
		elseif key == Enums.Effects.Shrink then
			local config = value :: { Duration: number? }
			shrinkAway(instance, config.Duration or 0.6)
		end
	end
end

function Voxel.new(instance: BasePart, kind: Kind, controller: any, origin: Vector3?): Voxel
	local cframe = instance.CFrame
	local rx, ry, rz = cframe:ToEulerAnglesXYZ()
	local self = setmetatable({
		Instance = instance,
		Kind = kind,
		OriginalCFrame = cframe,
		OriginalPosition = cframe.Position,
		OriginalOrientation = Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz)),
		Distance = if origin then (cframe.Position - origin).Magnitude else nil,
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

function Voxel:Cleanup(method, duration: number?)
	method = method or self._controller._cleanup
	if type(method) == "function" then
		method(self)
		return
	end

	if method == Enums.Cleanup.Destroy then
		destroyOrRelease(self.Instance)
	elseif method == Enums.Cleanup.Fade then
		local tween = TweenService:Create(self.Instance, TweenInfo.new(duration or 0.5), { Transparency = 1 })
		tween.Completed:Once(function()
			destroyOrRelease(self.Instance)
		end)
		tween:Play()
	elseif method == Enums.Cleanup.Rebuild then
		self.Instance.Anchored = true
		local tween = TweenService:Create(self.Instance, TweenInfo.new(duration or 0.6), { CFrame = self.OriginalCFrame })
		tween:Play()
	end
end

return { new = Voxel.new, applyEffects = applyEffects }
