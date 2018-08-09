local config = {}
config.author = 'Rinart73'
config.name = 'Transfer Cargo Tweaks'
config.homepage = "https://www.avorion.net/forum/index.php/topic,4263.msg22604.html"
config.version = {
    major = 1, minor = 2, patch = 0, -- 0.17.1 - 0.18.2
}
config.version.string = config.version.major..'.'..config.version.minor..'.'..config.version.patch


-- Increase to 140 if you have all default goods in your cargo. Increase even more if you have variations (stolen, suspicious)
config.CargoRowsAmount = 100
-- Enable favorites/trash system. Will save favorites data on disk
config.EnableFavorites = true
-- If favorites system is enabled, should it be toggled on by default?
config.ToggleFavoritesByDefault = true
-- Show current an minimal crew workforce in Crew Transfer Tab
config.EnableCrewWorkforcePreview = true


return config