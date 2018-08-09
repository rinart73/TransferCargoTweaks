local config = {}
config.author = 'Rinart73'
config.name = 'Transfer Cargo Tweaks'
config.homepage = "https://www.avorion.net/forum/index.php/topic,4263.msg22604.html"
config.version = {
    major = 1, minor = 1, patch = 0, -- 0.17.1+
    string = function() return config.version.major..'.'..config.version.minor..'.'..config.version.patch end
}

config.CargoRowsAmount = 100 -- increase to 140 if you have all default goods in your cargo

return config