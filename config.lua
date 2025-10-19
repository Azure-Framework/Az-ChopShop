-- config.lua
Config = {}

-- Ped location where players accept jobs and bring vehicles back
Config.Ped = {
    model = "a_m_m_business_01",
    coords = vector3(-44.0, -1115.0, 26.44), -- change to where you want the NPC
    heading = 170.0
}

-- Vehicle spawn locations (targets to go steal)
Config.JobLocations = {
    vector4(392.443, -642.247, 28.500, 272.522),
    vector4(320.858, -1001.901, 29.301, 85.739),
    vector4(-532.155, -889.054, 24.913, 176.646),
    vector4(-811.747, -1318.079, 5.000, 167.123),
    -- add as many as you like
}

-- Allowed vehicle models for spawn (must be valid GTA model names)
Config.VehicleModels = { "baller", "dune", "buffalo", "felon" }

-- Money payout range (randomized)
Config.MinPayout = 400
Config.MaxPayout = 1200

-- Which jobs are considered police (these cannot take the job)
Config.PoliceJobs = { "lspd", "bcso", "sasp" }

-- How long police blip stays in seconds if alerted
Config.PoliceBlipDuration = 120

-- Distance from ped where dismantle can be used
Config.DismantleRange = 6.0

-- NUI settings
Config.NuiFocusWhileMinigame = true

-- Mini-game difficulty settings
Config.Minigame = {
  sequenceLength = 3, -- how many keys in the quick-time sequence
  keyTimeLimit = 2000, -- ms per key
  successChanceBonus = 0 -- reserved
}
