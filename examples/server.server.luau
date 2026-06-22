--!nonstrict
-- Example server bootstrap (ServerScriptService). Defines an Absolute controller hosted on
-- a wall part and shatters it on a Box hitbox when a RemoteEvent fires.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Facet = require(ReplicatedStorage.Facet)
local Enums = Facet.Enums

local Wall = Facet.Define({
	Type = Enums.ControllerType.Absolute,
	VoxelSize = 2,
	Host = workspace:WaitForChild("Wall"),
})

local BlastEvent = Instance.new("RemoteEvent")
BlastEvent.Name = "Blast"
BlastEvent.Parent = ReplicatedStorage

BlastEvent.OnServerEvent:Connect(function(_player, impactCFrame: CFrame)
	Wall:Shatter({
		Hitbox = {
			Size = Vector3.new(4, 4, 4),
			CFrame = impactCFrame,
			HitboxType = Enums.HitboxType.Partial,
		},
		Effects = {
			[Enums.Effects.Explode] = { Radius = 12 },
		},
		Cleanup = Enums.Cleanup.Fade,
	}):Next(Enums.Event.NewVoxel):Then(function(result)
		print(`[Facet] produced {#result.Voxels.Partial} partial, {#result.Voxels.Extra} extra voxels`)
	end)
end)
