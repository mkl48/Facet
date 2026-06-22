-- Facet
-- _Drivers/init.luau
-- Plinko Labs
--
-- Reserved for swappable voxelization backends - DefineConfig.Drivers (see
-- _Classes/VoxelController/init.luau) already accepts a Drivers table, but nothing reads it yet.
-- Empty on purpose: there's only one driver (Voxelize.luau, wired directly into VoxelController)
-- today, so there's nothing to register here until a second one exists.

return {}
