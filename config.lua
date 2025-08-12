Config = {}

-- Distance at which aiming forces surrender
Config.SurrenderRange = 15.0

-- Only when armed with a firearm
Config.RequireGun = true

-- Time before a surrendered ped is cleaned up if not robbed (ms)
Config.SurrenderTimeout = 120000

-- Robbing settings
Config.RobDistance = 2.0
Config.RobTime = 4500         -- ms to "search"
Config.MinCash = 75
Config.MaxCash = 350

-- Cooldown per ped after rob or timeout (ms)
Config.PedCooldown = 900000

-- Prevent robbing certain ped models (add hashes)
Config.BlockedModels = {
    -- GetHashKey('s_m_y_cop_01'),
    -- GetHashKey('s_f_y_cop_01'),
}

-- Prevent robbing if ped is in a vehicle
Config.BlockIfInVehicle = true
