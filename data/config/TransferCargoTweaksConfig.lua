local config = {}
config.author = 'Rinart73'
config.name = 'Transfer Cargo Tweaks'
config.version = {
    major = 1, minor = 5, patch = 0, -- 0.22
}
config.version.string = config.version.major..'.'..config.version.minor..'.'..config.version.patch


-- CLIENT SETTINGS --
-- Default = 100. Increase to 140 if you have all default goods in your cargo. Increase even more if you have variations (stolen, suspicious).
config.CargoRowsAmount = 100
-- Enable favorites/trash system. Will save favorites data on disk (default = true).
config.EnableFavorites = true
-- If favorites system is enabled, should it be toggled on by default? (default = true).
config.ToggleFavoritesByDefault = true
-- Show current an minimal crew workforce in Crew Transfer Tab (default = true).
config.EnableCrewWorkforcePreview = true

-- SERVER SETTINGS
-- Allows to specify max distance for transferring fighters, cargo and crew.
-- default = 20
config.FightersMaxTransferDistance = 20
-- default = 20
config.CargoMaxTransferDistance = 20
-- default = 20
config.CrewMaxTransferDistance = 20
-- If enabled, when a ship transfers goods from/to a station, server will check if the ship is docked instead of checking the distance (usually this will allow to transfer from a higher distance) (default = true).
config.CheckIfDocked = true


return config