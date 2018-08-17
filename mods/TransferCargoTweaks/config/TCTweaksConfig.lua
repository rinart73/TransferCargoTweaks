local config = {}
config.author = 'Rinart73'
config.name = 'Transfer Cargo Tweaks'
config.homepage = "https://www.avorion.net/forum/index.php/topic,4263.msg22604.html"
config.version = {
    major = 1, minor = 3, patch = 0, -- 0.17.1 - 0.18.2
}
config.version.string = config.version.major..'.'..config.version.minor..'.'..config.version.patch


-- CLIENT SETTINGS --
-- Increase to 140 if you have all default goods in your cargo. Increase even more if you have variations (stolen, suspicious)
config.CargoRowsAmount = 100
-- Enable favorites/trash system. Will save favorites data on disk
config.EnableFavorites = true
-- If favorites system is enabled, should it be toggled on by default?
config.ToggleFavoritesByDefault = true
-- Show current an minimal crew workforce in Crew Transfer Tab
config.EnableCrewWorkforcePreview = true

-- SERVER SETTINGS
-- Allows to specify max distance for transferring fighters, cargo and crew
-- default = 2
config.FightersMaxTransferDistance = 2
-- default = 2
config.CargoMaxTransferDistance = 2
-- default = 20
config.CrewMaxTransferDistance = 20
-- If enabled, when a ship transfers goods from/to a station, server will check if the ship is docked instead of checking the distance (usually this will allow to transfer from a higher distance)
config.CheckIfDocked = true


return config