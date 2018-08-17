package.path = package.path .. ";data/scripts/lib/?.lua"

require("utility")
require("stringutility")
require ("tooltipmaker")

local playerTotalCrewBar;
local selfTotalCrewBar;

local playerCrewIcons = {}
local playerCrewBars = {}
local playerCrewButtons = {}
local playerCrewTextBoxes = {}
local selfCrewIcons = {}
local selfCrewBars = {}
local selfCrewButtons = {}
local selfCrewTextBoxes = {}

local playerCrewTextBoxByIndex = {}
local selfCrewTextBoxByIndex = {}

local playerTransferAllCrewButton = {}
local selfTransferAllCrewButton = {}

local playerTotalCargoBar;
local selfTotalCargoBar;

local playerCargoIcons = {}
local playerCargoBars = {}
local playerCargoButtons = {}
local playerCargoTextBoxes = {}
local selfCargoIcons = {}
local selfCargoBars = {}
local selfCargoButtons = {}
local selfCargoTextBoxes = {}

--local playerCargoName = {} --MOD: TransferCargoTweaks
local playerCargoTextBoxByIndex = {}
--local selfCargoName = {} --MOD: TransferCargoTweaks
local selfCargoTextBoxByIndex = {}

local playerTransferAllCargoButton = {}
local selfTransferAllCargoButton = {}

local playerFighterLabels = {}
local selfFighterLabels = {}
local playerFighterSelections = {}
local selfFighterSelections = {}
local isPlayerShipBySelection = {}
local squadIndexBySelection = {}

local playerTransferAllFightersButton = {}
local selfTransferAllFightersButton = {}

local crewmenByButton = {}
local crewmenByTextBox = {}
local cargosByButton = {}
local cargosByTextBox = {}

local textboxIndexByButton = {}

--MOD: TransferCargoTweaks
package.path = package.path .. ";mods/TransferCargoTweaks/?.lua"
local status, utf8 = pcall(require, "scripts/lib/utf8")
if not status then
    print("[TCTweaks][ERROR]: Couldn't load utf8 library")
end
local status, TCTweaksConfig = pcall(require, 'config/TCTweaksConfig')
if not status then
    print("[TCTweaks][ERROR]: Couldn't load config, using default settings")
    TCTweaksConfig = { CargoRowsAmount = 100 }
end

-- register mod for localization
if i18n then i18n.registerMod("TransferCargoTweaks") end

local favoritesFile = {} -- file with all stations of the server
local stationFavorites = { {}, {} } -- current station only

local crewProfessionIds = {1, 2, 3, 4, 5, 8, 9, 10, 11}
-- crew workforce labels
local playerCrewWorkforceLabels = {}
local selfCrewWorkforceLabels = {}

-- crew overlay names
local playerCrewLabels = {}
local selfCrewLabels = {}

local playerToggleSearchBtn
local selfToggleSearchBtn

local playerCargoSearchBox
local selfCargoSearchBox

-- goods overlay names
local playerCargoLabels = {}
local selfCargoLabels = {}

local playerToggleFavoritesBtn
local selfToggleFavoritesBtn

local playerFavoriteButtons = {}
local playerTrashButtons = {}
local selfFavoriteButtons = {}
local selfTrashButtons = {}

-- cargo list saved between the updates (to eliminate the need of calling C function every search)
local playerCargoList = {}
local selfCargoList = {}

local cargoLowerCache = {} -- because non-native utf8.lower is 32 times slower than string.lower

-- to utf8.lower query string only when it was changed
local playerPrevQuery = {}
local selfPrevQuery = {}

-- goods indexes in saved cargo lists by name
local playerGoodIndexesByName
local selfGoodIndexesByName

-- goods names sorted
local playerGoodNames
local selfGoodNames

-- currently displayed goods localized names by index of row
local playerGoodSearchNames = {}
local selfGoodSearchNames = {}

-- how many goods were displayed in the previous update/search (performance)
local playerCargoPrevCount = 0
local selfCargoPrevCount = 0

-- we want to keep textbox values for goods even if their rows are currently hidden (because of search)
local playerAmountByIndex = {}
local selfAmountByIndex = {}

local playerFavoritesEnabled = TCTweaksConfig.ToggleFavoritesByDefault
local selfFavoritesEnabled = TCTweaksConfig.ToggleFavoritesByDefault

local playerLastHoveredRow
local selfLastHoveredRow

local tabbedWindow
local cargoTabIndex

local function playerSortGoodsFavorites(a, b)
    local afav = stationFavorites[1][a] or 1
    local bfav = stationFavorites[1][b] or 1
    return afav > bfav or (afav == bfav and utf8.compare(a, b, true))
end

local function selfSortGoodsFavorites(a, b)
    local afav = stationFavorites[2][a] or 1
    local bfav = stationFavorites[2][b] or 1
    return afav > bfav or (afav == bfav and utf8.compare(a, b, true))
end

local function playerSortGoods()
    if not playerFavoritesEnabled then
        table.sort(playerGoodNames, utf8.comparesensitive)
    else
        table.sort(playerGoodNames, playerSortGoodsFavorites)
    end
    TransferCrewGoods.playerCargoSearch()
end

local function selfSortGoods()
    if not selfFavoritesEnabled then
        table.sort(selfGoodNames, utf8.comparesensitive)
    else
        table.sort(selfGoodNames, selfSortGoodsFavorites)
    end
    TransferCrewGoods.selfCargoSearch()
end

local function serialze(o)
    if type(o) == 'table' then
        local s = '{'
        for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. '['..k..']=' .. serialze(v) .. ','
        end
        return s .. '}'
    else
        return type(o) == "string" and '"'..o:gsub("([\"\\])", "\\%1")..'"' or tostring(o)
    end
end

local function loadFavorites()
    local seed = GameSettings().seed
    local file, err = io.open("TransferCargoTweaks_"..seed..".lua", "r")
    if err then return nil, err end
    local result = loadstring(file:read("*a"))
    if not result then
        file:close()
        return nil, 1
    end
    result = result()
    file:close()
    return result
end

local function saveFavorites(tbl)
    local seed = GameSettings().seed
    local file, err = io.open("TransferCargoTweaks_"..seed..".lua", "wb")
    if err then return false, err end
    file:write("return "..serialze(tbl))
    file:close()
    return true
end
--MOD

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace TransferCrewGoods
TransferCrewGoods = {}

-- if this function returns false, the script will not be listed in the interaction window,
-- even though its UI may be registered
function TransferCrewGoods.interactionPossible(playerIndex, option)

    local player = Player()
    local ship = Entity()
    local other = player.craft

    if ship.index == other.index then
        return false
    end

    -- interaction with drones does not work
    if ship.isDrone or other.isDrone then
        return false
    end

    local shipFaction = Faction()
    if not shipFaction then return false end

    if shipFaction.isPlayer then
        if shipFaction.index ~= playerIndex then
            return false
        end
    elseif shipFaction.isAlliance then
        if player.allianceIndex ~= shipFaction.index then
            return false
        end
    else
        return false
    end

    return true, ""
end

--function initialize()
--
--end

-- create all required UI elements for the client side
function TransferCrewGoods.initUI()

    local res = getResolution()
    local size = vec2(850, 635)

    local menu = ScriptUI()
    local window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5));
    menu:registerWindow(window, "Transfer Crew/Cargo/Fighters"%_t);

    window.caption = "Transfer Crew, Cargo and Fighters"%_t
    window.showCloseButton = 1
    window.moveable = 1

    tabbedWindow = window:createTabbedWindow(Rect(vec2(10, 10), size - 10)) --local tabbedWindow = window:createTabbedWindow(Rect(vec2(10, 10), size - 10)) --MOD: TransferCargoTweaks
    local crewTab = tabbedWindow:createTab("Crew"%_t, "data/textures/icons/backup.png", "Exchange crew"%_t)

    local vSplit = UIVerticalSplitter(Rect(crewTab.size), 10, 0, 0.5)

--    crewTab:createFrame(vSplit.left);
--    crewTab:createFrame(vSplit.right);

    -- have to use "left" twice here since the coordinates are relative and the UI would be displaced to the right otherwise
    local leftLister = UIVerticalLister(vSplit.left, 10, 10)
    local rightLister = UIVerticalLister(vSplit.left, 10, 10)

    leftLister.marginRight = 30
    rightLister.marginRight = 30

    -- margin for the icon
    leftLister.marginLeft = 40
    rightLister.marginRight = 60

    --MOD: TransferCargoTweaks
    --local leftFrame = crewTab:createScrollFrame(vSplit.left)
    --local rightFrame = crewTab:createScrollFrame(vSplit.right)
    local leftFrame, rightFrame
    if not TCTweaksConfig.EnableCrewWorkforcePreview then
        leftFrame = crewTab:createScrollFrame(vSplit.left)
        rightFrame = crewTab:createScrollFrame(vSplit.right)
    else
        leftFrame = crewTab:createScrollFrame(Rect(vSplit.left.lower + vec2(0, 90), vSplit.left.upper))
        rightFrame = crewTab:createScrollFrame(Rect(vSplit.right.lower + vec2(0, 90), vSplit.right.upper))

        -- create ui to show how many workforce both ships have and need
        local leftForceHSplitter = UIHorizontalMultiSplitter(Rect(vSplit.left.lower + vec2(10, 0), vSplit.left.lower + vec2(vSplit.left.width - 20, 80)), 10, 0, 2)
        local rightForceHSplitter = UIHorizontalMultiSplitter(Rect(vSplit.right.lower + vec2(10, 0), vSplit.right.lower + vec2(vSplit.right.width - 10, 80)), 10, 0, 2)
        local i = 1
        for j = 0, 2 do
            local leftForceVSplitter = UIVerticalMultiSplitter(leftForceHSplitter:partition(j), 10, 0, 2)
            local rightForceVSplitter = UIVerticalMultiSplitter(rightForceHSplitter:partition(j), 10, 0, 2)
            for k = 0, 2 do
                local leftPartition = leftForceVSplitter:partition(k)
                local rightPartition = rightForceVSplitter:partition(k)
                local leftIcon = crewTab:createPicture(Rect(leftPartition.lower, leftPartition.lower + vec2(20, 20)), CrewProfession(crewProfessionIds[i]).icon)
                leftIcon.isIcon = 1
                local rightIcon = crewTab:createPicture(Rect(rightPartition.lower, rightPartition.lower + vec2(20, 20)), CrewProfession(crewProfessionIds[i]).icon)
                rightIcon.isIcon = 1
                
                playerCrewWorkforceLabels[crewProfessionIds[i]] = crewTab:createLabel(Rect(leftPartition.lower + vec2(30, 2), leftPartition.upper), "0/0", 12)
                selfCrewWorkforceLabels[crewProfessionIds[i]] = crewTab:createLabel(Rect(rightPartition.lower + vec2(30, 2), rightPartition.upper), "0/0", 12)
                i = i + 1
            end
        end
    end
    --MOD

    playerTransferAllCrewButton = leftFrame:createButton(Rect(), "Transfer All >>", "onPlayerTransferAllCrewPressed")
    leftLister:placeElementCenter(playerTransferAllCrewButton)

    selfTransferAllCrewButton = rightFrame:createButton(Rect(), "<< Transfer All", "onSelfTransferAllCrewPressed")
    rightLister:placeElementCenter(selfTransferAllCrewButton)

    playerTotalCrewBar = leftFrame:createNumbersBar(Rect())
    leftLister:placeElementCenter(playerTotalCrewBar)

    selfTotalCrewBar = rightFrame:createNumbersBar(Rect())
    rightLister:placeElementCenter(selfTotalCrewBar)

    for i = 1, CrewProfessionType.Number * 4 do

        local iconRect = Rect(leftLister.inner.topLeft - vec2(30, 0), leftLister.inner.topLeft + vec2(0, 30))
        local rect = leftLister:placeCenter(vec2(leftLister.inner.width, 25))
        local vsplit = UIVerticalSplitter(rect, 10, 0, 0.85)
        local vsplit2 = UIVerticalSplitter(vsplit.left, 10, 0, 0.75)

        local icon = leftFrame:createPicture(iconRect, "")
        icon.isIcon = 1
        local button = leftFrame:createButton(vsplit.right, ">>", "onPlayerTransferCrewPressed")
        local bar = leftFrame:createStatisticsBar(vsplit2.left, ColorRGB(1, 1, 1))
        local box = leftFrame:createTextBox(vsplit2.right, "onPlayerTransferCrewTextEntered")
        button.textSize = 16
        box.allowedCharacters = "0123456789"
        box.text = "1"

        --MOD: TransferCargoTweaks
        local overlayName = leftFrame:createLabel(Rect(vsplit2.left.lower + vec2(0, 6), vsplit2.left.upper), "", 10)
        overlayName.centered = true
        overlayName.wordBreak = false
        playerCrewLabels[i] = overlayName

        playerCrewIcons[i] = icon --table.insert(playerCrewIcons, icon)
        playerCrewButtons[i] = button --table.insert(playerCrewButtons, button)
        playerCrewBars[i] = bar --table.insert(playerCrewBars, bar)
        playerCrewTextBoxes[i] = box --table.insert(playerCrewTextBoxes, box)
        --MOD
        crewmenByButton[button.index] = i
        crewmenByTextBox[box.index] = i
        textboxIndexByButton[button.index] = box.index


        local iconRect = Rect(rightLister.inner.topRight, rightLister.inner.topRight + vec2(30, 30))
        local rect = rightLister:placeCenter(vec2(rightLister.inner.width, 25))
        local vsplit = UIVerticalSplitter(rect, 10, 0, 0.15)
        local vsplit2 = UIVerticalSplitter(vsplit.right, 10, 0, 0.25)

        local icon = rightFrame:createPicture(iconRect, "")
        icon.isIcon = 1
        local button = rightFrame:createButton(vsplit.left, "<<", "onSelfTransferCrewPressed")
        local bar = rightFrame:createStatisticsBar(vsplit2.right, ColorRGB(1, 1, 1))
        local box = rightFrame:createTextBox(vsplit2.left, "onSelfTransferCrewTextEntered")
        button.textSize = 16
        box.allowedCharacters = "0123456789"
        box.text = "1"

        --MOD: TransferCargoTweaks
        local overlayName = rightFrame:createLabel(Rect(vsplit2.right.lower + vec2(0, 6), vsplit2.right.upper), "", 10)
        overlayName.centered = true
        overlayName.wordBreak = false
        selfCrewLabels[i] = overlayName

        selfCrewIcons[i] = icon --table.insert(selfCrewIcons, icon)
        selfCrewButtons[i] = button --table.insert(selfCrewButtons, button)
        selfCrewBars[i] = bar --table.insert(selfCrewBars, bar)
        selfCrewTextBoxes[i] = box --table.insert(selfCrewTextBoxes, box)
        --MOD
        crewmenByButton[button.index] = i
        crewmenByTextBox[box.index] = i
        textboxIndexByButton[button.index] = box.index
    end

    local cargoTab = tabbedWindow:createTab("Cargo"%_t, "data/textures/icons/trade.png", "Exchange cargo"%_t)
    cargoTabIndex = cargoTab.index --MOD: TransferCargoTweaks

    -- have to use "left" twice here since the coordinates are relative and the UI would be displaced to the right otherwise
    local leftLister = UIVerticalLister(vSplit.left, 10, 10)
    local rightLister = UIVerticalLister(vSplit.left, 10, 10)

    leftLister.marginRight = 30
    rightLister.marginRight = 30

    -- margin for the icon
    leftLister.marginLeft = 40
    rightLister.marginRight = 60

    local leftFrame = cargoTab:createScrollFrame(vSplit.left)
    local rightFrame = cargoTab:createScrollFrame(vSplit.right)
    
    --MOD: TransferCargoTweaks
    --playerTransferAllCargoButton = leftFrame:createButton(Rect(), "Transfer All >>", "onPlayerTransferAllCargoPressed")
    --leftLister:placeElementCenter(playerTransferAllCargoButton)
    --selfTransferAllCargoButton = rightFrame:createButton(Rect(), "<< Transfer All", "onSelfTransferAllCargoPressed")
    --rightLister:placeElementCenter(selfTransferAllCargoButton)

    if TCTweaksConfig.EnableFavorites then
        playerTransferAllCargoButton = leftFrame:createButton(Rect(0, 10, leftFrame.width - 110, 45), "Transfer All >>", "onPlayerTransferAllCargoPressed")
        selfTransferAllCargoButton = rightFrame:createButton(Rect(0, 10, rightFrame.width - 110, 45), "<< Transfer All", "onSelfTransferAllCargoPressed")
    else
        playerTransferAllCargoButton = leftFrame:createButton(Rect(0, 10, leftFrame.width - 75, 45), "Transfer All >>", "onPlayerTransferAllCargoPressed")
        selfTransferAllCargoButton = rightFrame:createButton(Rect(0, 10, rightFrame.width - 75, 45), "<< Transfer All", "onSelfTransferAllCargoPressed")
    end
    leftLister:placeElementRight(playerTransferAllCargoButton)
    rightLister:placeElementLeft(selfTransferAllCargoButton)

    playerTotalCargoBar = leftFrame:createNumbersBar(Rect(0, 0, leftFrame.width - 40, 25)) --playerTotalCargoBar = leftFrame:createNumbersBar(Rect())
    leftLister:placeElementRight(playerTotalCargoBar) --leftLister:placeElementCenter(playerTotalCargoBar)

    selfTotalCargoBar = rightFrame:createNumbersBar(Rect(0, 0, rightFrame.width - 40, 25)) --selfTotalCargoBar = rightFrame:createNumbersBar(Rect())
    rightLister:placeElementLeft(selfTotalCargoBar) --rightLister:placeElementCenter(selfTotalCargoBar)

    playerToggleSearchBtn = leftFrame:createButton(Rect(10, 10, 40, 45), "", "onPlayerToggleCargoSearchPressed")
    playerToggleSearchBtn.icon = "mods/TransferCargoTweaks/textures/icons/search.png"
    selfToggleSearchBtn = rightFrame:createButton(Rect(rightFrame.width-60, 10, rightFrame.width-30, 45), "", "onSelfToggleCargoSearchPressed")
    selfToggleSearchBtn.icon = "mods/TransferCargoTweaks/textures/icons/search.png"

    playerCargoSearchBox = leftFrame:createTextBox(Rect(12, playerTransferAllCargoButton.height+22, leftFrame.width-33, playerTransferAllCargoButton.height+selfTotalCargoBar.height+18), "playerCargoSearch")
    playerCargoSearchBox.backgroundText = "Search"%_t
    playerCargoSearchBox.visible = false
    selfCargoSearchBox = rightFrame:createTextBox(Rect(12, selfTransferAllCargoButton.height+22, rightFrame.width-33, selfTransferAllCargoButton.height+selfTotalCargoBar.height+18), "selfCargoSearch")
    selfCargoSearchBox.backgroundText = "Search"%_t
    selfCargoSearchBox.visible = false

    if TCTweaksConfig.EnableFavorites then
        playerToggleFavoritesBtn = leftFrame:createButton(Rect(45, 10, 75, 45), "", "onPlayerToggleFavoritesPressed")
        selfToggleFavoritesBtn = rightFrame:createButton(Rect(rightFrame.width-95, 10, rightFrame.width-65, 45), "", "onSelfToggleFavoritesPressed")
        if TCTweaksConfig.ToggleFavoritesByDefault then
            playerToggleFavoritesBtn.icon = "mods/TransferCargoTweaks/textures/icons/favorites-enabled.png"
            selfToggleFavoritesBtn.icon = "mods/TransferCargoTweaks/textures/icons/favorites-enabled.png"
        else
            playerToggleFavoritesBtn.icon = "mods/TransferCargoTweaks/textures/icons/favorites.png"
            selfToggleFavoritesBtn.icon = "mods/TransferCargoTweaks/textures/icons/favorites.png"
        end
    end
    --MOD

    for i = 1, TCTweaksConfig.CargoRowsAmount do --for i = 1, 100 do --MOD: TransferCargoTweaks

        local iconRect = Rect(leftLister.inner.topLeft - vec2(30, 0), leftLister.inner.topLeft + vec2(0, 30))
        local rect = leftLister:placeCenter(vec2(leftLister.inner.width, 25))
        --MOD: TransferCargoTweaks
        --local vsplit = UIVerticalSplitter(rect, 10, 0, 0.85)
        --local vsplit2 = UIVerticalSplitter(vsplit.left, 10, 0, 0.75)
        local vsplit, vsplit2
        if TCTweaksConfig.EnableFavorites then
            vsplit = UIVerticalSplitter(rect, 10, 0, 0.87)
            vsplit2 = UIVerticalSplitter(vsplit.left, 10, 0, 0.77)
        else
            vsplit = UIVerticalSplitter(rect, 10, 0, 0.85)
            vsplit2 = UIVerticalSplitter(vsplit.left, 10, 0, 0.75)
        end
        --MOD

        local icon = leftFrame:createPicture(iconRect, "")
        icon.isIcon = 1
        local button = leftFrame:createButton(vsplit.right, ">>", "onPlayerTransferCargoPressed")
        --MOD: TransferCargoTweaks
        --local bar = leftFrame:createStatisticsBar(vsplit2.left, ColorInt(0xa0a0a0))
        local bar
        if TCTweaksConfig.EnableFavorites then
            bar = leftFrame:createStatisticsBar(Rect(vsplit2.left.lower + vec2(20, 0), vsplit2.left.upper), ColorInt(0x808080))
        else
            bar = leftFrame:createStatisticsBar(vsplit2.left, ColorInt(0x808080))
        end
        --MOD
        local box = leftFrame:createTextBox(vsplit2.right, "onPlayerTransferCargoTextEntered")
        button.textSize = 16
        box.allowedCharacters = "0123456789"

        --MOD: TransferCargoTweaks
        playerCargoIcons[i] = icon --table.insert(playerCargoIcons, icon)
        playerCargoButtons[i] = button --table.insert(playerCargoButtons, button)
        playerCargoBars[i] = bar --table.insert(playerCargoBars, bar)
        playerCargoTextBoxes[i] = box --table.insert(playerCargoTextBoxes, box)
        --table.insert(playerCargoName, "")

        local overlayName

        if TCTweaksConfig.EnableFavorites then
            local favoriteBtn = leftFrame:createPicture(Rect(vsplit2.left.topLeft + vec2(5, 2), vsplit2.left.topLeft + vec2(15, 12)), '')
            favoriteBtn.flipped = true
            favoriteBtn.picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
            playerFavoriteButtons[i] = favoriteBtn
            favoriteBtn.visible = false
            
            local trashBtn = leftFrame:createPicture(Rect(vsplit2.left.topLeft + vec2(5, 18), vsplit2.left.topLeft + vec2(15, 28)), '')
            trashBtn.flipped = true
            trashBtn.picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
            playerTrashButtons[i] = trashBtn
            trashBtn.visible = false

            overlayName = leftFrame:createLabel(Rect(vsplit2.left.lower + vec2(20, 6), vsplit2.left.upper), "", 10)
        else
            overlayName = leftFrame:createLabel(Rect(vsplit2.left.lower + vec2(0, 6), vsplit2.left.upper), "", 10)
        end

        overlayName.centered = true
        overlayName.wordBreak = false
        playerCargoLabels[i] = { elem = overlayName }

        icon.visible = false
        button.visible = false
        bar.visible = false
        box.visible = false
        overlayName.visible = false
        --MOD
        cargosByButton[button.index] = i
        cargosByTextBox[box.index] = i
        textboxIndexByButton[button.index] = box.index


        local iconRect = Rect(rightLister.inner.topRight, rightLister.inner.topRight + vec2(30, 30))
        local rect = rightLister:placeCenter(vec2(rightLister.inner.width, 25))
        --MOD: TransferCargoTweaks
        --local vsplit = UIVerticalSplitter(rect, 10, 0, 0.15)
        --local vsplit2 = UIVerticalSplitter(vsplit.right, 10, 0, 0.25)
        local vsplit, vsplit2
        if TCTweaksConfig.EnableFavorites then
            vsplit = UIVerticalSplitter(rect, 10, 0, 0.13)
            vsplit2 = UIVerticalSplitter(vsplit.right, 10, 0, 0.23)
        else
            vsplit = UIVerticalSplitter(rect, 10, 0, 0.15)
            vsplit2 = UIVerticalSplitter(vsplit.right, 10, 0, 0.25)
        end
        --MOD

        local icon = rightFrame:createPicture(iconRect, "")
        icon.isIcon = 1
        local button = rightFrame:createButton(vsplit.left, "<<", "onSelfTransferCargoPressed")
        --MOD: TransferCargoTweaks
        --local bar = rightFrame:createStatisticsBar(vsplit2.right, ColorInt(0xa0a0a0))
        local bar
        if TCTweaksConfig.EnableFavorites then
            bar = rightFrame:createStatisticsBar(Rect(vsplit2.right.lower, vsplit2.right.upper - vec2(20, 0)), ColorInt(0x808080))
        else
            bar = rightFrame:createStatisticsBar(vsplit2.right, ColorInt(0x808080))
        end
        --MOD
        local box = rightFrame:createTextBox(vsplit2.left, "onSelfTransferCargoTextEntered")
        button.textSize = 16
        box.allowedCharacters = "0123456789"

        --MOD: TransferCargoTweaks
        selfCargoIcons[i] = icon --table.insert(selfCargoIcons, icon)
        selfCargoButtons[i] = button --table.insert(selfCargoButtons, button)
        selfCargoBars[i] = bar --table.insert(selfCargoBars, bar)
        selfCargoTextBoxes[i] = box --table.insert(selfCargoTextBoxes, box)
        --table.insert(selfCargoName, "")

        local overlayName

        if TCTweaksConfig.EnableFavorites then
            local favoriteBtn = rightFrame:createPicture(Rect(vsplit2.right.topRight + vec2(-15, 2), vsplit2.right.topRight + vec2(-5, 12)), '')
            favoriteBtn.flipped = true
            favoriteBtn.picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
            selfFavoriteButtons[i] = favoriteBtn
            favoriteBtn.visible = false

            local trashBtn = rightFrame:createPicture(Rect(vsplit2.right.topRight + vec2(-15, 18), vsplit2.right.topRight + vec2(-5, 28)), '')
            trashBtn.flipped = true
            trashBtn.picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
            selfTrashButtons[i] = trashBtn
            trashBtn.visible = false
            
            overlayName = rightFrame:createLabel(Rect(vsplit2.right.lower + vec2(0, 6), vsplit2.right.upper - vec2(20, 0)), "", 10)
        else
            overlayName = rightFrame:createLabel(Rect(vsplit2.right.lower + vec2(0, 6), vsplit2.right.upper), "", 10)
        end
        
        overlayName.centered = true
        overlayName.wordBreak = false
        selfCargoLabels[i] = { elem = overlayName }
        
        icon.visible = false
        button.visible = false
        bar.visible = false
        box.visible = false
        overlayName.visible = false
        --MOD
        
        cargosByButton[button.index] = i
        cargosByTextBox[box.index] = i
        textboxIndexByButton[button.index] = box.index
    end

    -- create fighters tab
    local fightersTab = tabbedWindow:createTab("Fighters"%_t, "data/textures/icons/fighter.png", "Exchange fighters"%_t)

    local leftLister = UIVerticalLister(vSplit.left, 0, 0)
    local rightLister = UIVerticalLister(vSplit.right, 0, 0)

    leftLister.marginLeft = 5
    rightLister.marginLeft = 5

    playerTransferAllFightersButton = fightersTab:createButton(Rect(), "Transfer All >>", "onPlayerTransferAllFightersPressed")
    leftLister:placeElementCenter(playerTransferAllFightersButton)

    selfTransferAllFightersButton = fightersTab:createButton(Rect(), "<< Transfer All", "onSelfTransferAllFightersPressed")
    rightLister:placeElementCenter(selfTransferAllFightersButton)

    for i = 1, 10 do
        -- left side (player)
        local rect = leftLister:placeCenter(vec2(leftLister.inner.width, 18))
        local label = fightersTab:createLabel(rect, "", 16)
        playerFighterLabels[i] = label --table.insert(playerFighterLabels, label) --MOD: TransferCargoTweaks

        local rect = leftLister:placeCenter(vec2(leftLister.inner.width, 35))
        rect.upper = vec2(rect.lower.x + 376, rect.upper.y)
        local selection = fightersTab:createSelection(rect, 12)
        selection.dropIntoEnabled = true
        selection.dragFromEnabled = true
        selection.entriesSelectable = false
        selection.onReceivedFunction = "onFighterReceived"
        selection.onClickedFunction = "onFighterClicked"
        selection.padding = 4

        playerFighterSelections[i] = selection --table.insert(playerFighterSelections, selection) --MOD: TransferCargoTweaks
        isPlayerShipBySelection[selection.index] = true
        squadIndexBySelection[selection.index] = i - 1

        -- right side (self)
        local rect = rightLister:placeCenter(vec2(rightLister.inner.width, 18))
        local label = fightersTab:createLabel(rect, "", 16)
        selfFighterLabels[i] = label --table.insert(selfFighterLabels, label) --MOD: TransferCargoTweaks

        local rect = rightLister:placeCenter(vec2(rightLister.inner.width, 35))
        rect.upper = vec2(rect.lower.x + 376, rect.upper.y)
        local selection = fightersTab:createSelection(rect, 12)
        selection.dropIntoEnabled = true
        selection.dragFromEnabled = true
        selection.entriesSelectable = false
        selection.onReceivedFunction = "onFighterReceived"
        selection.onClickedFunction = "onFighterClicked"
        selection.padding = 4

        selfFighterSelections[i] = selection --table.insert(selfFighterSelections, selection) --MOD: TransferCargoTweaks
        isPlayerShipBySelection[selection.index] = false
        squadIndexBySelection[selection.index] = i - 1
    end
end


function TransferCrewGoods.getSortedCrewmen(entity)

    function compareCrewmen(pa, pb)
        local a = pa.crewman
        local b = pb.crewman

        if a.profession.value == b.profession.value then
            if a.specialist == b.specialist then
                return a.level < b.level
            else
                return (a.specialist and 1 or 0) < (b.specialist and 1 or 0)
            end
        else
            return a.profession.value < b.profession.value
        end
    end


    local sortedMembers = {}

    local crew = entity.crew
    if crew then
        for crewman, num in pairs(crew:getMembers()) do
            table.insert(sortedMembers, {crewman = crewman, num = num})
        end
    end

    table.sort(sortedMembers, compareCrewmen)

    return sortedMembers
end

function TransferCrewGoods.updateData()
    local playerShip = Player().craft
    local ship = Entity()

    -- update crew info
    playerTotalCrewBar:clear()
    selfTotalCrewBar:clear()

    playerTotalCrewBar:setRange(0, playerShip.maxCrewSize)
    selfTotalCrewBar:setRange(0, ship.maxCrewSize)

    --MOD: TransferCargoTweaks
    --[[for _, icon in pairs(playerCrewIcons) do icon.visible = false end
    for _, icon in pairs(selfCrewIcons) do icon.visible = false end
    for _, bar in pairs(playerCrewBars) do bar.visible = false end
    for _, bar in pairs(selfCrewBars) do bar.visible = false end
    for _, button in pairs(playerCrewButtons) do button.visible = false end
    for _, button in pairs(selfCrewButtons) do button.visible = false end
    for _, box in pairs(playerCrewTextBoxes) do box.visible = false end
    for _, box in pairs(selfCrewTextBoxes) do box.visible = false end]]
    for i = 1, #playerCrewIcons do
        playerCrewIcons[i].visible = false
        selfCrewIcons[i].visible = false
        playerCrewBars[i].visible = false
        selfCrewBars[i].visible = false
        playerCrewButtons[i].visible = false
        selfCrewButtons[i].visible = false
        playerCrewTextBoxes[i].visible = false
        selfCrewTextBoxes[i].visible = false
        playerCrewLabels[i].visible = false
        selfCrewLabels[i].visible = false
    end
    --MOD

    -- restore textbox values
    local amountByIndex = {}
    for crewIndex, index in pairs(playerCrewTextBoxByIndex) do
        table.insert(amountByIndex, crewIndex, playerCrewTextBoxes[index].text)
    end

    playerCrewTextBoxByIndex = {}

    local i = 1
    for _, p in pairs(TransferCrewGoods.getSortedCrewmen(playerShip)) do

        local crewman = p.crewman
        local num = p.num

        local caption
        if num == 1 then
            caption = num .. " " .. crewman.profession.name
        else
            caption = num .. " " .. crewman.profession.plural
        end

        playerTotalCrewBar:addEntry(num, caption, crewman.profession.color)

        local icon = playerCrewIcons[i]
        icon:show()
        icon.picture = crewman.profession.icon

        local singleBar = playerCrewBars[i]
        singleBar.visible = true
        singleBar:setRange(0, playerShip.maxCrewSize)
        singleBar.value = num
        singleBar.name = caption
        singleBar.color = crewman.profession.color

        local button = playerCrewButtons[i]
        button.visible = true

        -- restore textbox value
        local index = p.crewman.profession.value * 4
        if p.crewman.specialist then index = index + p.crewman.level end

        local amount = TransferCrewGoods.clampNumberString(amountByIndex[index] or "1", num)
        table.insert(playerCrewTextBoxByIndex, index, i)

        local box = playerCrewTextBoxes[i]
        box.visible = true
        box.text = amount

        --MOD: TransferCargoTweaks
        local overlayName
        if p.crewman.specialist then
            overlayName = string.format("%s Level %u"%_t, num == 1 and crewman.profession.name or crewman.profession.plural, p.crewman.level)
        else
            if num == 1 then
                overlayName = string.format("Untrained %s"%_t, crewman.profession.name)
            else
                overlayName = string.format("Untrained %s /* plural */"%_t, crewman.profession.plural)
            end
        end
        playerCrewLabels[i].caption = overlayName
        playerCrewLabels[i].visible = true
        --MOD

        i = i + 1
    end

    -- restore textbox values
    local amountByIndex = {}
    for crewIndex, index in pairs(selfCrewTextBoxByIndex) do
        table.insert(amountByIndex, crewIndex, selfCrewTextBoxes[index].text)
    end

    selfCrewTextBoxByIndex = {}

    local i = 1
    for _, p in pairs(TransferCrewGoods.getSortedCrewmen(Entity())) do

        local crewman = p.crewman
        local num = p.num

        local caption
        if num == 1 then
            caption = num .. " " .. crewman.profession.name
        else
            caption = num .. " " .. crewman.profession.plural
        end

        selfTotalCrewBar:addEntry(num, caption, crewman.profession.color)

        local icon = selfCrewIcons[i]
        icon:show()
        icon.picture = crewman.profession.icon

        local singleBar = selfCrewBars[i]
        singleBar.visible = true
        singleBar:setRange(0, ship.maxCrewSize)
        singleBar.value = num
        singleBar.name = caption
        singleBar.color = crewman.profession.color

        local button = selfCrewButtons[i]
        button.visible = true

        -- restore textbox value
        local index = p.crewman.profession.value * 4
        if p.crewman.specialist then index = index + p.crewman.level end

        local amount = TransferCrewGoods.clampNumberString(amountByIndex[index] or "1", num)
        table.insert(selfCrewTextBoxByIndex, index, i)

        local box = selfCrewTextBoxes[i]
        box.visible = true
        box.text = amount

        --MOD: TransferCargoTweaks
        local overlayName
        if p.crewman.specialist then
            overlayName = string.format("%s Level %u"%_t, num == 1 and crewman.profession.name or crewman.profession.plural, p.crewman.level)
        else
            if num == 1 then
                overlayName = string.format("Untrained %s"%_t, crewman.profession.name)
            else
                overlayName = string.format("Untrained %s /* plural */"%_t, crewman.profession.plural)
            end
        end
        selfCrewLabels[i].caption = overlayName
        selfCrewLabels[i].visible = true
        --MOD

        i = i + 1
    end

    --MOD: TransferCargoTweaks
    -- update workforce labels
    if TCTweaksConfig.EnableCrewWorkforcePreview then
        local playerMinWorkforce = {}
        for k,v in pairs(playerShip.minCrew:getWorkforce()) do
            playerMinWorkforce[k.value] = v
        end
        local playerWorkforce = {}
        for k,v in pairs(playerShip.crew:getWorkforce()) do
            playerWorkforce[k.value] = v
        end
        local selfMinWorkforce = {}
        for k,v in pairs(ship.minCrew:getWorkforce()) do
            selfMinWorkforce[k.value] = v
        end
        local selfWorkforce = {}
        for k,v in pairs(ship.crew:getWorkforce()) do
            selfWorkforce[k.value] = v
        end

        local profId
        for i = 1, #crewProfessionIds do
            profId = crewProfessionIds[i]
            -- player
            if not playerMinWorkforce[profId] then playerMinWorkforce[profId] = 0 end
            if not playerWorkforce[profId] then playerWorkforce[profId] = 0 end
            playerCrewWorkforceLabels[profId].caption = playerWorkforce[profId] .. "/" .. playerMinWorkforce[profId]
            playerCrewWorkforceLabels[profId].color = playerWorkforce[profId] < playerMinWorkforce[profId] and ColorInt(0xffff2626) or ColorInt(0xffe0e0e0)
            -- self
            if not selfMinWorkforce[profId] then selfMinWorkforce[profId] = 0 end
            if not selfWorkforce[profId] then selfWorkforce[profId] = 0 end
            selfCrewWorkforceLabels[profId].caption = selfWorkforce[profId] .. "/" .. selfMinWorkforce[profId]
            selfCrewWorkforceLabels[profId].color = selfWorkforce[profId] < selfMinWorkforce[profId] and ColorInt(0xffff2626) or ColorInt(0xffe0e0e0)
        end
    end
    --MOD

    -- update cargo info
    playerTotalCargoBar:clear()
    selfTotalCargoBar:clear()

    playerTotalCargoBar:setRange(0, playerShip.maxCargoSpace)
    selfTotalCargoBar:setRange(0, ship.maxCargoSpace)

    --MOD: TransferCargoTweaks
    -- removed lines from 498 to 509

    -- sort goods by localized name
    playerGoodNames = {}
    playerGoodIndexesByName = {}
    selfGoodNames = {}
    selfGoodIndexesByName = {}

    playerCargoList = {}
    selfCargoList = {}

    for i = 1, (playerShip.numCargos or 0) do
        local good, amount = playerShip:getCargo(i - 1)
        playerCargoList[i] = { good = good, amount = amount }
        playerGoodNames[i] = good.displayName
        playerGoodIndexesByName[good.displayName] = i
        
        playerTotalCargoBar:addEntry(amount * good.size, amount .. " " .. (amount > 1 and good.displayPlural or good.displayName), ColorInt(0xff808080))
    end

    for i = 1, (ship.numCargos or 0) do
        local good, amount = ship:getCargo(i - 1)
        selfCargoList[i] = { good = good, amount = amount }
        selfGoodNames[i] = good.displayName
        selfGoodIndexesByName[good.displayName] = i
        
        selfTotalCargoBar:addEntry(amount * good.size, amount .. " " .. (amount > 1 and good.displayPlural or good.displayName), ColorInt(0xff808080))
    end

    playerSortGoods()
    selfSortGoods()

    -- removed lines from 511 to 586
    --MOD

    -- update fighter info
    --MOD: TransferCargoTweaks
    --[[for _, label in pairs(playerFighterLabels) do label:hide() end
    for _, label in pairs(selfFighterLabels) do label:hide() end
    for _, selection in pairs(playerFighterSelections) do selection:hide() end
    for _, selection in pairs(selfFighterSelections) do selection:hide() end]]
    for i = 1, #playerFighterLabels do
        playerFighterLabels[i].visible = false
        selfFighterLabels[i].visible = false
        playerFighterSelections[i].visible = false
        selfFighterSelections[i].visible = false
    end
    --MOD

    -- left side (player)
    local hangar = Hangar(playerShip.index)
    if hangar then
        local squads = {hangar:getSquads()}

        for _, squad in pairs(squads) do
            local label = playerFighterLabels[squad + 1]
            label.caption = hangar:getSquadName(squad)
            label:show()

            local selection = playerFighterSelections[squad + 1]
            selection:show()
            selection:clear()
            for i = 0, hangar:getSquadFighters(squad) - 1 do
                local fighter = hangar:getFighter(squad, i)

                local item = SelectionItem()
                item.texture = "data/textures/icons/fighter.png"
                item.borderColor = fighter.rarity.color
                item.value0 = squad
                item.value1 = i

                selection:add(item, i)
            end

            for i = hangar:getSquadFighters(squad), 11 do
                selection:addEmpty(i)
            end
        end
    end

    -- right side (self)
    local hangar = Hangar(ship.index)
    if hangar then
        local squads = {hangar:getSquads()}

        for _, squad in pairs(squads) do
            local label = selfFighterLabels[squad + 1]
            label.caption = hangar:getSquadName(squad)
            label:show()

            local selection = selfFighterSelections[squad + 1]
            selection:show()
            selection:clear()
            for i = 0, hangar:getSquadFighters(squad) - 1 do
                local fighter = hangar:getFighter(squad, i)

                local item = SelectionItem()
                item.texture = "data/textures/icons/fighter.png"
                item.borderColor = fighter.rarity.color
                item.value0 = squad
                item.value1 = i

                selection:add(item, i)
            end

            for i = hangar:getSquadFighters(squad), 11 do
                selection:addEmpty(i)
            end
        end
    end
end

function TransferCrewGoods.clampNumberString(string, max)
    if string == "" then return "" end

    local num = tonumber(string)
    if num > max then num = max end

    return tostring(num)
end

function TransferCrewGoods.onPlayerTransferAllCrewPressed(button)
    invokeServerFunction("transferAllCrew", Player().craftIndex, false)
end

function TransferCrewGoods.onSelfTransferAllCrewPressed(button)
    invokeServerFunction("transferAllCrew", Player().craftIndex, true)
end

function TransferCrewGoods.onPlayerTransferCrewPressed(button)
    -- transfer crew from player ship to self

    -- check which crew member type
    local crewmanIndex = crewmenByButton[button.index]
    if not crewmanIndex then return end

    -- get amount
    local textboxIndex = textboxIndexByButton[button.index]
    if not textboxIndex then return end

    local box = TextBox(textboxIndex)
    if not box then return end

    local amount = tonumber(box.text) or 0
    --MOD: TransferCargoTweaks
    local keyboard = Keyboard()
    if keyboard:keyPressed("left ctrl") or keyboard:keyPressed("right ctrl") then
        amount = 5
    elseif keyboard:keyPressed("left shift") or keyboard:keyPressed("right shift") then
        amount = 10
    elseif keyboard:keyPressed("left alt") or keyboard:keyPressed("right alt") then
        amount = 50
    end
    --MOD
    if amount == 0 then return end

    invokeServerFunction("transferCrew", crewmanIndex, Player().craftIndex, false, amount)
end

function TransferCrewGoods.onSelfTransferCrewPressed(button)
    -- transfer crew from self ship to player ship

    -- check which crew member type
    local crewmanIndex = crewmenByButton[button.index]
    if not crewmanIndex then return end

    -- get amount
    local textboxIndex = textboxIndexByButton[button.index]
    if not textboxIndex then return end

    local box = TextBox(textboxIndex)
    if not box then return end

    local amount = tonumber(box.text) or 0
    --MOD: TransferCargoTweaks
    local keyboard = Keyboard()
    if keyboard:keyPressed("left ctrl") or keyboard:keyPressed("right ctrl") then
        amount = 5
    elseif keyboard:keyPressed("left shift") or keyboard:keyPressed("right shift") then
        amount = 10
    elseif keyboard:keyPressed("left alt") or keyboard:keyPressed("right alt") then
        amount = 50
    end
    --MOD
    if amount == 0 then return end

    invokeServerFunction("transferCrew", crewmanIndex, Player().craftIndex, true, amount)
end

-- textbox text changed callbacks
function TransferCrewGoods.onPlayerTransferCrewTextEntered(textBox)
    local enteredNumber = tonumber(textBox.text)
    if enteredNumber == nil then
        enteredNumber = 0
    end

    local newNumber = enteredNumber

    -- get available amount
    local crewmanIndex = crewmenByTextBox[textBox.index]
    if not crewmanIndex then return end

    local sender = Entity(Player().craftIndex)

    local sorted = TransferCrewGoods.getSortedCrewmen(sender)
    local p = sorted[crewmanIndex]
    if not p then return end

    local maxAmount = p.num
    if newNumber > maxAmount then
        newNumber = maxAmount
    end

    if newNumber ~= enteredNumber then
        textBox.text = newNumber
    end
end

function TransferCrewGoods.onSelfTransferCrewTextEntered(textBox)
    local enteredNumber = tonumber(textBox.text)
    if enteredNumber == nil then
        enteredNumber = 0
    end

    local newNumber = enteredNumber

    -- get available amount
    local crewmanIndex = crewmenByTextBox[textBox.index]
    if not crewmanIndex then return end

    local sender = Entity()

    local sorted = TransferCrewGoods.getSortedCrewmen(sender)
    local p = sorted[crewmanIndex]
    if not p then return end

    local maxAmount = p.num
    if newNumber > maxAmount then
        newNumber = maxAmount
    end

    if newNumber ~= enteredNumber then
        textBox.text = newNumber
    end
end

function TransferCrewGoods.onPlayerTransferCargoTextEntered(textBox)
    local enteredNumber = tonumber(textBox.text)
    if enteredNumber == nil then
        enteredNumber = 0
    end

    local newNumber = enteredNumber

    -- get available amount
    local cargoIndex = cargosByTextBox[textBox.index]
    if not cargoIndex then return end

    local sender = Entity(Player().craftIndex)
    --MOD: TransferCargoTweaks
    --local _, maxAmount = sender:getCargo(cargoIndex - 1)
    local maxAmount = playerCargoList[playerGoodIndexesByName[playerGoodSearchNames[cargoIndex]]].amount or 0
    --MOD

    maxAmount = maxAmount or 0

    if newNumber > maxAmount then
        newNumber = maxAmount
    end

    if newNumber ~= enteredNumber then
        textBox.text = newNumber
    end
end

function TransferCrewGoods.onSelfTransferCargoTextEntered(textBox)
    local enteredNumber = tonumber(textBox.text)
    if enteredNumber == nil then
        enteredNumber = 0
    end

    local newNumber = enteredNumber

    -- get available amount
    local cargoIndex = cargosByTextBox[textBox.index]
    if not cargoIndex then return end

    local sender = Entity()
    --MOD: TransferCargoTweaks
    --local good, maxAmount = sender:getCargo(cargoIndex - 1)
    local maxAmount = selfCargoList[selfGoodIndexesByName[selfGoodSearchNames[cargoIndex]]].amount or 0
    --MOD

    if newNumber > maxAmount then
        newNumber = maxAmount
    end

    if newNumber ~= enteredNumber then
        textBox.text = newNumber
    end
end

function TransferCrewGoods.transferCrew(crewmanIndex, otherIndex, selfToOther, amount)
    local sender
    local receiver

    if selfToOther then
        sender = Entity()
        receiver = Entity(otherIndex)
    else
        sender = Entity(otherIndex)
        receiver = Entity()
    end

    local player = Player(callingPlayer)
    if not player then return end

    if sender.factionIndex ~= callingPlayer and sender.factionIndex ~= player.allianceIndex then
        player:sendChatMessage("Server"%_t, 1, "You don't own this craft."%_t)
        return
    end

    -- check distance
    if TCTweaksConfig.CheckIfDocked and (sender.isStation or receiver.isStation) then
        if (sender.isStation and not sender:isDocked(receiver)) or (receiver.isStation and not receiver:isDocked(sender)) then
            player:sendChatMessage("Server"%_t, 1, "You must be docked to the station to transfer crew."%_t)
            return
        end
    elseif sender:getNearestDistance(receiver) > TCTweaksConfig.CrewMaxTransferDistance then
        player:sendChatMessage("Server"%_t, 1, "You're too far away."%_t)
        return
    end

    local sorted = TransferCrewGoods.getSortedCrewmen(sender)

    local p = sorted[crewmanIndex]
    if not p then
        print("bad crewman")
        return
    end

    local crewman = p.crewman

    -- make sure sending ship has enough members of this type
    if sender.crew:getNumMembers(crewman) < amount then
        print("not enough crew of this type")
        return
    end

    -- transfer
    sender:removeCrew(amount, crewman)
    receiver:addCrew(amount, crewman)
end

function TransferCrewGoods.transferAllCrew(otherIndex, selfToOther)
    local sender
    local receiver

    if selfToOther then
        sender = Entity()
        receiver = Entity(otherIndex)
    else
        sender = Entity(otherIndex)
        receiver = Entity()
    end

    local player = Player(callingPlayer)
    if not player then return end

    if sender.factionIndex ~= callingPlayer and sender.factionIndex ~= player.allianceIndex then
        player:sendChatMessage("Server"%_t, 1, "You don't own this craft."%_t)
        return
    end

    -- check distance
    if TCTweaksConfig.CheckIfDocked and (sender.isStation or receiver.isStation) then
        if (sender.isStation and not sender:isDocked(receiver)) or (receiver.isStation and not receiver:isDocked(sender)) then
            player:sendChatMessage("Server"%_t, 1, "You must be docked to the station to transfer crew."%_t)
            return
        end
    elseif sender:getNearestDistance(receiver) > TCTweaksConfig.CrewMaxTransferDistance then
        player:sendChatMessage("Server"%_t, 1, "You're too far away."%_t)
        return
    end

    local sorted = TransferCrewGoods.getSortedCrewmen(sender)
    for _, p in pairs(sorted) do
        -- transfer
        sender:removeCrew(p.num, p.crewman)
        receiver:addCrew(p.num, p.crewman)
    end
end

function TransferCrewGoods.onPlayerTransferAllCargoPressed(button)
    invokeServerFunction("transferAllCargo", Player().craftIndex, false)
end

function TransferCrewGoods.onSelfTransferAllCargoPressed(button)
    invokeServerFunction("transferAllCargo", Player().craftIndex, true)
end

function TransferCrewGoods.onPlayerTransferCargoPressed(button)
    -- transfer cargo from player ship to self

    -- check which cargo
    local cargo = cargosByButton[button.index]
    if cargo == nil then return end
    cargo = playerGoodIndexesByName[playerGoodSearchNames[cargo]] --MOD: TransferCargoTweaks

    -- get amount
    local textboxIndex = textboxIndexByButton[button.index]
    if not textboxIndex then return end

    local box = TextBox(textboxIndex)
    if not box then return end

    local amount = tonumber(box.text) or 0
    --MOD: TransferCargoTweaks
    local keyboard = Keyboard()
    if keyboard:keyPressed("left ctrl") or keyboard:keyPressed("right ctrl") then
        amount = 5
    elseif keyboard:keyPressed("left shift") or keyboard:keyPressed("right shift") then
        amount = 10
    elseif keyboard:keyPressed("left alt") or keyboard:keyPressed("right alt") then
        amount = 50
    end
    --MOD
    if amount == 0 then return end

    invokeServerFunction("transferCargo", cargo - 1, Player().craftIndex, false, amount)
end

function TransferCrewGoods.onSelfTransferCargoPressed(button)
    -- transfer cargo from self to player ship

    -- check which cargo
    local cargo = cargosByButton[button.index]
    if cargo == nil then return end
    cargo = selfGoodIndexesByName[selfGoodSearchNames[cargo]] --MOD: TransferCargoTweaks

    -- get amount
    local textboxIndex = textboxIndexByButton[button.index]
    if not textboxIndex then return end

    local box = TextBox(textboxIndex)
    if not box then return end

    local amount = tonumber(box.text) or 0
    --MOD: TransferCargoTweaks
    local keyboard = Keyboard()
    if keyboard:keyPressed("left ctrl") or keyboard:keyPressed("right ctrl") then
        amount = 5
    elseif keyboard:keyPressed("left shift") or keyboard:keyPressed("right shift") then
        amount = 10
    elseif keyboard:keyPressed("left alt") or keyboard:keyPressed("right alt") then
        amount = 50
    end
    --MOD
    if amount == 0 then return end

    invokeServerFunction("transferCargo", cargo - 1, Player().craftIndex, true, amount)
end


function TransferCrewGoods.transferCargo(cargoIndex, otherIndex, selfToOther, amount)
    local sender
    local receiver

    if selfToOther then
        sender = Entity()
        receiver = Entity(otherIndex)
    else
        sender = Entity(otherIndex)
        receiver = Entity()
    end

    local player = Player(callingPlayer)
    if not player then return end

    if sender.factionIndex ~= callingPlayer and sender.factionIndex ~= player.allianceIndex then
        player:sendChatMessage("Server"%_t, 1, "You don't own this craft."%_t)
        return
    end

    -- check distance
    if TCTweaksConfig.CheckIfDocked and (sender.isStation or receiver.isStation) then
        if (sender.isStation and not sender:isDocked(receiver)) or (receiver.isStation and not receiver:isDocked(sender)) then
            player:sendChatMessage("Server"%_t, 1, "You must be docked to the station to transfer cargo."%_t)
            return
        end
    elseif sender:getNearestDistance(receiver) > TCTweaksConfig.CargoMaxTransferDistance then
        player:sendChatMessage("Server"%_t, 1, "You're too far away."%_t)
        return
    end

    -- get the cargo
    local good, availableAmount = sender:getCargo(cargoIndex)

    -- make sure sending ship has the cargo
    if not good or not availableAmount then return end
    amount = math.min(amount, availableAmount)

    -- make sure receiving ship has enough space
    if receiver.freeCargoSpace < good.size * amount then
        player:sendChatMessage("Server"%_t, 1, "Not enough space on the other craft."%_t)
        return
    end

    -- transfer
    sender:removeCargo(good, amount)
    receiver:addCargo(good, amount)

    invokeClientFunction(player, "updateData")
end

function TransferCrewGoods.transferAllCargo(otherIndex, selfToOther)
    local sender
    local receiver

    if selfToOther then
        sender = Entity()
        receiver = Entity(otherIndex)
    else
        sender = Entity(otherIndex)
        receiver = Entity()
    end

    local player = Player(callingPlayer)
    if not player then return end

    if sender.factionIndex ~= callingPlayer and sender.factionIndex ~= player.allianceIndex then
        player:sendChatMessage("Server"%_t, 1, "You don't own this craft."%_t)
        return
    end

    -- check distance
    if TCTweaksConfig.CheckIfDocked and (sender.isStation or receiver.isStation) then
        if (sender.isStation and not sender:isDocked(receiver)) or (receiver.isStation and not receiver:isDocked(sender)) then
            player:sendChatMessage("Server"%_t, 1, "You must be docked to the station to transfer cargo."%_t)
            return
        end
    elseif sender:getNearestDistance(receiver) > TCTweaksConfig.CargoMaxTransferDistance then
        player:sendChatMessage("Server"%_t, 1, "You're too far away."%_t)
        return
    end

    -- get the cargo
    local cargos = sender:getCargos()
    local cargoTransferred = false

    for good, amount in pairs(cargos) do
        -- make sure receiving ship has enough space
        if receiver.freeCargoSpace < good.size * amount then
            -- transfer as much as possible
            amount = math.floor(receiver.freeCargoSpace / good.size)

            if amount == 0 then
                player:sendChatMessage("Server"%_t, 1, "Not enough space on the other craft."%_t)
                break;
            end
        end

        -- transfer
        sender:removeCargo(good, amount)
        receiver:addCargo(good, amount)
        cargoTransferred = true
    end

    if cargoTransferred then
        invokeClientFunction(player, "updateData")
    end
end

function TransferCrewGoods.onPlayerTransferAllFightersPressed(button)
    invokeServerFunction("transferAllFighters", Player().craftIndex, Entity().index)
end

function TransferCrewGoods.onSelfTransferAllFightersPressed(button)
    invokeServerFunction("transferAllFighters", Entity().index, Player().craftIndex)
end

function TransferCrewGoods.onFighterReceived(selectionIndex, fkx, fky, item, fromIndex, toIndex, tkx, tky)
    if not item then return end

    local sender
    if isPlayerShipBySelection[fromIndex] then
        sender = Player().craftIndex
    else
        sender = Entity().index
    end

    local receiver
    if isPlayerShipBySelection[toIndex] then
        receiver = Player().craftIndex
    else
        receiver = Entity().index
    end

    local squad = item.value0
    local index = item.value1
    local receiverSquad = squadIndexBySelection[toIndex]

    if receiverSquad == squad and fromIndex == toIndex then return end

    invokeServerFunction("transferFighter", sender, squad, index, receiver, receiverSquad)
end

function TransferCrewGoods.onFighterClicked(selectionIndex, x, y, item, button)
    if button ~= 3 then return end
    if not item then return end

    local sender
    local receiver
    if isPlayerShipBySelection[selectionIndex] then
        sender = Player().craftIndex
        receiver = Entity().index
    else
        sender = Entity().index
        receiver = Player().craftIndex
    end

    local squad = item.value0
    local index = item.value1

    invokeServerFunction("transferFighter", sender, squad, index, receiver, squad)
end

function TransferCrewGoods.transferFighter(sender, squad, index, receiver, receiverSquad)
    if not onServer() then return end

    local player = Player(callingPlayer)
    if not player then return end
    
    local entitySender = Entity(sender)
    local entityReceiver = Entity(receiver)

    if entitySender.factionIndex ~= callingPlayer and entitySender.factionIndex ~= player.allianceIndex then
        player:sendChatMessage("Server"%_t, 1, "You don't own this craft."%_t)
        return
    end

    -- check distance
    if TCTweaksConfig.CheckIfDocked and (entitySender.isStation or entityReceiver.isStation) then
        if (entitySender.isStation and not entitySender:isDocked(entityReceiver)) or (entityReceiver.isStation and not entityReceiver:isDocked(entitySender)) then
            player:sendChatMessage("Server"%_t, 1, "You must be docked to the station to transfer fighters."%_t)
            return
        end
    elseif entitySender:getNearestDistance(entityReceiver) > TCTweaksConfig.FightersMaxTransferDistance then
        player:sendChatMessage("Server"%_t, 1, "You're too far away."%_t)
        return
    end

    local senderHangar = Hangar(sender)
    if not senderHangar then
        player:sendChatMessage("Server"%_t, 1, "Missing hangar."%_t)
        return
    end
    local receiverHangar = Hangar(receiver)
    if not receiverHangar then
        player:sendChatMessage("Server"%_t, 1, "Missing hangar."%_t)
        return
    end

    local fighter = senderHangar:getFighter(squad, index)
    if not fighter then
        return
    end

    if sender ~= receiver and receiverHangar.freeSpace < fighter.volume then
        player:sendChatMessage("Server"%_t, 1, "Not enough space in hangar."%_t)
        return
    end

    if receiverHangar:getSquadFreeSlots(receiverSquad) == 0 then
        receiverSquad = nil

        -- find other squad
        local receiverSquads = {receiverHangar:getSquads()}

        for _, newSquad in pairs(receiverSquads) do
            if receiverHangar:getSquadFreeSlots(newSquad) > 0 then
                receiverSquad = newSquad
                break
            end
        end

        if receiverSquad == nil then
            if #receiverSquads < receiverHangar.maxSquads then
                receiverSquad = receiverHangar:addSquad("New Squad"%_t)
            else
                player:sendChatMessage("Server"%_t, 1, "Not enough space in squad."%_t)
            end
        end

    end

    if receiverHangar:getSquadFreeSlots(receiverSquad) > 0 then
        senderHangar:removeFighter(index, squad)
        receiverHangar:addFighter(receiverSquad, fighter)
    end

    invokeClientFunction(player, "updateData")
end

function TransferCrewGoods.transferAllFighters(sender, receiver)
    if not onServer() then return end

    local player = Player(callingPlayer)
    if not player then return end

    local entitySender = Entity(sender)
    local entityReceiver = Entity(receiver)

    if entitySender.factionIndex ~= callingPlayer and entitySender.factionIndex ~= player.allianceIndex then
        player:sendChatMessage("Server"%_t, 1, "You don't own this craft."%_t)
        return
    end

    -- check distance
    if TCTweaksConfig.CheckIfDocked and (entitySender.isStation or entityReceiver.isStation) then
        if (entitySender.isStation and not entitySender:isDocked(entityReceiver)) or (entityReceiver.isStation and not entityReceiver:isDocked(entitySender)) then
            player:sendChatMessage("Server"%_t, 1, "You must be docked to the station to transfer fighters."%_t)
            return
        end
    elseif entitySender:getNearestDistance(entityReceiver) > TCTweaksConfig.FightersMaxTransferDistance then
        player:sendChatMessage("Server"%_t, 1, "You're too far away."%_t)
        return
    end

    local senderHangar = Hangar(sender)
    if not senderHangar then
        player:sendChatMessage("Server"%_t, 1, "Missing hangar."%_t)
        return
    end
    local receiverHangar = Hangar(receiver)
    if not receiverHangar then
        player:sendChatMessage("Server"%_t, 1, "Missing hangar."%_t)
        return
    end

    local senderSquads = {senderHangar:getSquads()}
    local receiverSquads = {receiverHangar:getSquads()}
    local missingSquads = {}

    for _, squad in pairs(senderSquads) do
        if senderHangar:getSquadFighters(squad) > 0 then
            local targetSquad

            for _, rSquad in pairs(receiverSquads) do
                if rSquad == squad then
                    targetSquad = rSquad
                    break
                end
            end

            if not targetSquad then
                targetSquad = receiverHangar:addSquad(senderHangar:getSquadName(squad))
            end

            for i = 0, senderHangar:getSquadFighters(squad) - 1 do
                -- check squad space
                if receiverHangar:getSquadFreeSlots(targetSquad) == 0 then
                    player:sendChatMessage("Server"%_t, 1, "Not enough space in squad."%_t)
                    break
                end

                local fighter = senderHangar:getFighter(squad, 0)
                if not fighter then
                    print("fighter is nil")
                    return
                end

                -- check hangar space
                if receiverHangar.freeSpace < fighter.volume then
                    player:sendChatMessage("Server"%_t, 1, "Not enough space in hangar."%_t)
                    return
                end

                -- transfer
                senderHangar:removeFighter(0, squad)
                receiverHangar:addFighter(targetSquad, fighter)
            end
        end
    end

    invokeClientFunction(player, "updateData")
end

---- this function gets called every time the window is shown on the client, ie. when a player presses F
function TransferCrewGoods.onShowWindow()
    local player = Player()
    local ship = Entity()
    local other = player.craft

    ship:registerCallback("onCrewChanged", "onCrewChanged")
    other:registerCallback("onCrewChanged", "onCrewChanged")

    --MOD: TransferCargoTweaks
    if TCTweaksConfig.EnableFavorites then -- load favorites
        favoritesFile, err = loadFavorites()
        if err == 1 then print("[TCTweaks][ERROR]: Settings file is corrupted") end
        if not favoritesFile then
            favoritesFile = { version = TCTweaksConfig.version.string }
        end
        local favorites = favoritesFile[Entity().index.string] or { {}, {} }
        if not favorites[1] then favorites[1] = {} end
        if not favorites[2] then favorites[2] = {} end
        -- convert latin names to localized to improve performance of future checks
        stationFavorites = { {}, {} }
        for k,v in pairs(favorites[1]) do
            stationFavorites[1][k%_t] = v
        end
        for k,v in pairs(favorites[2]) do
            stationFavorites[2][k%_t] = v
        end
    end
    --MOD

    TransferCrewGoods.updateData()
end
--
---- this function gets called every time the window is shown on the client, ie. when a player presses F
function TransferCrewGoods.onCloseWindow()
    local player = Player()
    local ship = Entity()
    local other = player.craft

    ship:unregisterCallback("onCrewChanged", "onCrewChanged")
    other:unregisterCallback("onCrewChanged", "onCrewChanged")

    --MOD: TransferCargoTweaks
    if TCTweaksConfig.EnableFavorites then -- save favorites
        local favorites = { {}, {} }
        local playerFavCount = 0
        local selfFavCount = 0
        for k,v in pairs(stationFavorites[1]) do
            playerFavCount = playerFavCount + 1
            favorites[1][playerCargoList[playerGoodIndexesByName[k]].good.name] = v
        end
        for k,v in pairs(stationFavorites[2]) do
            selfFavCount = selfFavCount + 1
            favorites[2][selfCargoList[selfGoodIndexesByName[k]].good.name] = v
        end
        if playerFavCount == 0 and selfFavCount == 0 then
            favorites = nil
        else
            if playerFavCount == 0 then favorites[1] = nil end
            if selfFavCount == 0 then favorites[2] = nil end
        end
        favoritesFile[Entity().index.string] = favorites
        local success, err = saveFavorites(favoritesFile)
        if err then
            print("[TCTweaks][ERROR]: Couldn't save settings file due to an error: "..err)
        end

        favoritesFile = nil
        stationFavorites = { {}, {} }
    end
    --MOD
end

function TransferCrewGoods.onCrewChanged()
    TransferCrewGoods.updateData()
end

-- this function will be executed every frame both on the server and the client
--function update(timeStep)
--end
--
---- this function will be executed every frame on the client only
--function updateClient(timeStep)
--end
--
---- this function will be executed every frame on the server only
--function updateServer(timeStep)
--end
--
---- this function will be executed every frame on the client only
---- use this for rendering additional elements to the target indicator of the object
--function renderUIIndicator(px, py, size)
--end
--
---- this function will be executed every frame on the client only
---- use this for rendering additional elements to the interaction menu of the target craft
function TransferCrewGoods.renderUI()
    local activeSelection
    for _, selection in pairs(playerFighterSelections) do
        if selection.mouseOver then
            activeSelection = selection
            break
        end
    end

    if not activeSelection then
        for _, selection in pairs(selfFighterSelections) do
            if selection.mouseOver then
                activeSelection = selection
                break
            end
        end
    end

    if activeSelection then --if not activeSelection then return end --MOD: TransferCargoTweaks

    local mousePos = Mouse().position
    local key = activeSelection:getMouseOveredKey()
    if key.y ~= 0 then return end
    if key.x < 0 then return end

    local entity
    if isPlayerShipBySelection[activeSelection.index] then
        entity = Player().craftIndex
    else
        entity = Entity().index
    end

    if not entity then return end

    local hangar = Hangar(entity)
    if not hangar then return end

    local fighter = hangar:getFighter(squadIndexBySelection[activeSelection.index], key.x)
    if not fighter then return end

    local renderer = TooltipRenderer(makeFighterTooltip(fighter))
    renderer:drawMouseTooltip(mousePos)
    --MOD: TransferCargoTweaks
    return
    end
    
    if not TCTweaksConfig.EnableFavorites then return end
    local currentTab = tabbedWindow:getActiveTab()
    if not currentTab or currentTab.index ~= cargoTabIndex then return end

    local goodName, priority, btn, playerHoveredRow, selfHoveredRow
    -- change icon on hover, change item priority on icon click
    for i = 1, playerCargoPrevCount do
        if playerCargoIcons[i].mouseOver
          or playerCargoButtons[i].mouseOver
          or playerCargoBars[i].mouseOver
          or playerCargoTextBoxes[i].mouseOver
          or playerFavoriteButtons[i].mouseOver
          or playerTrashButtons[i].mouseOver then
            goodName = playerGoodSearchNames[i]
            priority = stationFavorites[1][goodName]
            playerHoveredRow = i

            if Mouse():mouseDown(3) then
                if playerFavoriteButtons[i].mouseOver then
                    if priority ~= 2 then
                        stationFavorites[1][goodName] = 2
                        playerFavoriteButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/star.png"
                        playerTrashButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
                    else
                        stationFavorites[1][goodName] = nil
                        playerFavoriteButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
                    end
                    if playerFavoritesEnabled then playerSortGoods() end
                elseif playerTrashButtons[i].mouseOver then
                    if priority ~= 0 then
                        stationFavorites[1][goodName] = 0
                        playerFavoriteButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
                        playerTrashButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/trash.png"
                    else
                        stationFavorites[1][goodName] = nil
                        playerTrashButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
                    end
                    if playerFavoritesEnabled then playerSortGoods() end
                end
            else -- just hover
                if priority ~= 2 then
                    playerFavoriteButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/star-hover.png"
                end
                if priority ~= 0 then
                    playerTrashButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/trash-hover.png"
                end
            end
            break
        end
    end
    for i = 1, selfCargoPrevCount do
        if selfCargoIcons[i].mouseOver
          or selfCargoButtons[i].mouseOver
          or selfCargoBars[i].mouseOver
          or selfCargoTextBoxes[i].mouseOver
          or selfFavoriteButtons[i].mouseOver
          or selfTrashButtons[i].mouseOver then
            goodName = selfGoodSearchNames[i]
            priority = stationFavorites[2][goodName]
            selfHoveredRow = i
            
            if Mouse():mouseDown(3) then
                if selfFavoriteButtons[i].mouseOver then
                    if priority ~= 2 then
                        stationFavorites[2][goodName] = 2
                        selfFavoriteButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/star.png"
                        selfTrashButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
                    else
                        stationFavorites[2][goodName] = nil
                        selfFavoriteButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
                    end
                    if selfFavoritesEnabled then selfSortGoods() end
                elseif selfTrashButtons[i].mouseOver then
                    if priority ~= 0 then
                        stationFavorites[2][goodName] = 0
                        selfFavoriteButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
                        selfTrashButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/trash.png"
                    else
                        stationFavorites[2][goodName] = nil
                        selfTrashButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
                    end
                    if selfFavoritesEnabled then selfSortGoods() end
                end
            else -- just hover
                if priority ~= 2 then
                    selfFavoriteButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/star-hover.png"
                end
                if priority ~= 0 then
                    selfTrashButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/trash-hover.png"
                end
            end
            break
        end
    end
    -- return icons to 'hidden' image, when mouse left them
    if playerLastHoveredRow and playerLastHoveredRow ~= playerHoveredRow then
        priority = stationFavorites[1][playerGoodSearchNames[playerLastHoveredRow]]
        if priority ~= 2 then
            playerFavoriteButtons[playerLastHoveredRow].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
        end
        if priority ~= 0 then
            playerTrashButtons[playerLastHoveredRow].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
        end
    end
    playerLastHoveredRow = playerHoveredRow
    
    if selfLastHoveredRow and selfLastHoveredRow ~= selfHoveredRow then
        priority = stationFavorites[2][selfGoodSearchNames[selfLastHoveredRow]]
        if priority ~= 2 then
            selfFavoriteButtons[selfLastHoveredRow].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
        end
        if priority ~= 0 then
            selfTrashButtons[selfLastHoveredRow].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
        end
    end
    selfLastHoveredRow = selfHoveredRow
    --MOD
end

--MOD: TransferCargoTweaks
function TransferCrewGoods.onPlayerToggleCargoSearchPressed(button)
    playerCargoSearchBox.visible = not playerCargoSearchBox.visible
end

function TransferCrewGoods.onPlayerToggleFavoritesPressed(button)
    playerFavoritesEnabled = not playerFavoritesEnabled
    if playerFavoritesEnabled then
        button.icon = "mods/TransferCargoTweaks/textures/icons/favorites-enabled.png"
    else
        button.icon = "mods/TransferCargoTweaks/textures/icons/favorites.png"
    end
    playerSortGoods()
end

function TransferCrewGoods.onSelfToggleCargoSearchPressed(button)
    selfCargoSearchBox.visible = not selfCargoSearchBox.visible
end

function TransferCrewGoods.onSelfToggleFavoritesPressed(button)
    selfFavoritesEnabled = not selfFavoritesEnabled
    if selfFavoritesEnabled then
        button.icon = "mods/TransferCargoTweaks/textures/icons/favorites-enabled.png"
    else
        button.icon = "mods/TransferCargoTweaks/textures/icons/favorites.png"
    end
    selfSortGoods()
end

function TransferCrewGoods.playerCargoSearch()
    local playerShip = Player().craft
    
    -- save/retrieve lowercase query because we don't want to recalculate it every update (not search)
    local query = playerCargoSearchBox.text
    if playerPrevQuery[1] ~= query then
        if playerPrevQuery[1] == '' then
            playerToggleSearchBtn.icon = "mods/TransferCargoTweaks/textures/icons/search-text.png"
        elseif query == '' then
            playerToggleSearchBtn.icon = "mods/TransferCargoTweaks/textures/icons/search.png"
        end
        playerPrevQuery[1] = query
        playerPrevQuery[2] = utf8.lower(query)
    end
    query = playerPrevQuery[2]
    
    -- save textbox numbers
    for cargoName, index in pairs(playerCargoTextBoxByIndex) do
        playerAmountByIndex[cargoName] = playerCargoTextBoxes[index].text
    end
    playerCargoTextBoxByIndex = {}

    local playerMaxSpace = playerShip.maxCargoSpace or 0
    
    playerGoodSearchNames = {} --list of good names that is currently shown

    local rowNumber = 0
    for i = 1, #playerGoodNames do
        if rowNumber == TCTweaksConfig.CargoRowsAmount then break end

        -- save/retrieve lowercase good names
        local nameLowercase
        local displayName = playerGoodNames[i]
        if not cargoLowerCache[nameLowercase] then
            cargoLowerCache[displayName] = utf8.lower(displayName)
        end
        nameLowercase = cargoLowerCache[displayName]
        
        if query == "" or utf8.find(nameLowercase, query, 1, true, true) then
            rowNumber = rowNumber + 1
        
            local bar = playerCargoBars[rowNumber]
            local overlayName = playerCargoLabels[rowNumber]
            local cargo = playerCargoList[playerGoodIndexesByName[playerGoodNames[i]]]
            local good = cargo.good
            local amount = cargo.amount
            
            playerCargoIcons[rowNumber].picture = good.icon
            bar:setRange(0, playerMaxSpace)
            bar.value = amount * good.size
            bar.name = amount .. " " .. (amount > 1 and good.displayPlural or good.displayName)
            
            playerGoodSearchNames[rowNumber] = displayName
            
            -- restore textbox value
            local nameWithStatus = good.name
            if good.suspicious then
                nameWithStatus = nameWithStatus .. ".1"
            elseif good.stolen then
                nameWithStatus = nameWithStatus .. ".2"
            end
            local boxAmount = TransferCrewGoods.clampNumberString(playerAmountByIndex[nameWithStatus] or "1", amount)
            playerCargoTextBoxByIndex[nameWithStatus] = rowNumber
            playerCargoTextBoxes[rowNumber].text = boxAmount
            
            -- favorites and trash icons/buttons
            if TCTweaksConfig.EnableFavorites then
                local priority = stationFavorites[1][displayName]
                if priority == 2 then
                    playerFavoriteButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/star.png"
                    playerTrashButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
                elseif priority == 0 then
                    playerFavoriteButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
                    playerTrashButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/trash.png"
                else
                    playerFavoriteButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
                    playerTrashButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
                end
            end
            
            -- cargo overlay name
            displayName = amount > 1 and good.displayPlural or good.displayName
            -- adjust overlay name vertically (because we don't have built-in way to do this)
            if utf8.len(displayName) > 28 then
                if not overlayName.reducedFont then
                    overlayName.reducedFont = true
                    overlayName.elem.fontSize = 8
                    overlayName.elem.rect = Rect(overlayName.elem.rect.topLeft + vec2(0, 3), overlayName.elem.rect.bottomRight)
                end
            elseif overlayName.reducedFont then
                overlayName.reducedFont = false
                overlayName.elem.fontSize = 10
                overlayName.elem.rect = Rect(overlayName.elem.rect.topLeft + vec2(0, -3), overlayName.elem.rect.bottomRight)
            end
            overlayName.elem.caption = displayName
        end
    end
    
    if TCTweaksConfig.EnableFavorites then
        -- hide only rows that were shown in prev search but not in current
        for i = rowNumber+1, playerCargoPrevCount do
            playerCargoIcons[i].visible = false
            playerCargoBars[i].visible = false
            playerCargoButtons[i].visible = false
            playerCargoTextBoxes[i].visible = false
            playerCargoLabels[i].elem.visible = false
            playerFavoriteButtons[i].visible = false
            playerTrashButtons[i].visible = false
        end
        -- show only rows that were not shown in prev search but will be in current
        for i = playerCargoPrevCount+1, rowNumber do
            playerCargoIcons[i].visible = true
            playerCargoBars[i].visible = true
            playerCargoButtons[i].visible = true
            playerCargoTextBoxes[i].visible = true
            playerCargoLabels[i].elem.visible = true
            playerFavoriteButtons[i].visible = true
            playerTrashButtons[i].visible = true
        end
    else
        for i = rowNumber+1, playerCargoPrevCount do
            playerCargoIcons[i].visible = false
            playerCargoBars[i].visible = false
            playerCargoButtons[i].visible = false
            playerCargoTextBoxes[i].visible = false
            playerCargoLabels[i].elem.visible = false
        end
        for i = playerCargoPrevCount+1, rowNumber do
            playerCargoIcons[i].visible = true
            playerCargoBars[i].visible = true
            playerCargoButtons[i].visible = true
            playerCargoTextBoxes[i].visible = true
            playerCargoLabels[i].elem.visible = true
        end
    end

    playerCargoPrevCount = rowNumber
end

function TransferCrewGoods.selfCargoSearch()
    local ship = Entity()
    
    local query = selfCargoSearchBox.text
    if selfPrevQuery[1] ~= query then
        if selfPrevQuery[1] == '' then
            selfToggleSearchBtn.icon = "mods/TransferCargoTweaks/textures/icons/search-text.png"
        elseif query == '' then
            selfToggleSearchBtn.icon = "mods/TransferCargoTweaks/textures/icons/search.png"
        end
        selfPrevQuery[1] = query
        selfPrevQuery[2] = utf8.lower(query)
    end
    query = selfPrevQuery[2]
    
    for cargoName, index in pairs(selfCargoTextBoxByIndex) do
        selfAmountByIndex[cargoName] = selfCargoTextBoxes[index].text
    end
    selfCargoTextBoxByIndex = {}
    
    local selfMaxSpace = ship.maxCargoSpace or 0

    selfGoodSearchNames = {}
    
    local rowNumber = 0
    for i = 1, #selfGoodNames do
        if rowNumber == TCTweaksConfig.CargoRowsAmount then break end
        
        local nameLowercase
        local displayName = selfGoodNames[i]
        if not cargoLowerCache[nameLowercase] then
            cargoLowerCache[displayName] = utf8.lower(displayName)
        end
        nameLowercase = cargoLowerCache[displayName]
        
        if query == "" or utf8.find(nameLowercase, query, 1, true, true) then
            rowNumber = rowNumber + 1
        
            local bar = selfCargoBars[rowNumber]
            local overlayName = selfCargoLabels[rowNumber]
            local cargo = selfCargoList[selfGoodIndexesByName[selfGoodNames[i]]]
            local good = cargo.good
            local amount = cargo.amount
            
            selfCargoIcons[rowNumber].picture = good.icon
            bar:setRange(0, selfMaxSpace)
            bar.value = amount * good.size
            bar.name = amount .. " " .. (amount > 1 and good.displayPlural or good.displayName)
            
            selfGoodSearchNames[rowNumber] = displayName

            -- restore textbox value
            local nameWithStatus = good.name
            if good.suspicious then
                nameWithStatus = nameWithStatus .. ".1"
            elseif good.stolen then
                nameWithStatus = nameWithStatus .. ".2"
            end
            local boxAmount = TransferCrewGoods.clampNumberString(selfAmountByIndex[nameWithStatus] or "1", amount)
            selfCargoTextBoxByIndex[nameWithStatus] = rowNumber
            selfCargoTextBoxes[rowNumber].text = boxAmount

            -- favorites and trash icons/buttons
            if TCTweaksConfig.EnableFavorites then
                local priority = stationFavorites[2][displayName]
                if priority == 2 then
                    selfFavoriteButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/star.png"
                    selfTrashButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
                elseif priority == 0 then
                    selfFavoriteButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
                    selfTrashButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/trash.png"
                else
                    selfFavoriteButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
                    selfTrashButtons[i].picture = "mods/TransferCargoTweaks/textures/icons/empty.png"
                end
            end

            -- overlay cargo name
            displayName = amount > 1 and good.displayPlural or good.displayName
            if utf8.len(displayName) > 28 then
                if not overlayName.reducedFont then
                    overlayName.reducedFont = true
                    overlayName.elem.fontSize = 8
                    overlayName.elem.rect = Rect(overlayName.elem.rect.topLeft + vec2(0, 3), overlayName.elem.rect.bottomRight)
                end
            elseif overlayName.reducedFont then
                overlayName.reducedFont = false
                overlayName.elem.fontSize = 10
                overlayName.elem.rect = Rect(overlayName.elem.rect.topLeft + vec2(0, -3), overlayName.elem.rect.bottomRight)
            end
            overlayName.elem.caption = displayName
        end
    end

    if TCTweaksConfig.EnableFavorites then
        -- hide
        for i = rowNumber+1, selfCargoPrevCount do
            selfCargoIcons[i].visible = false
            selfCargoBars[i].visible = false
            selfCargoButtons[i].visible = false
            selfCargoTextBoxes[i].visible = false
            selfCargoLabels[i].elem.visible = false
            selfFavoriteButtons[i].visible = false
            selfTrashButtons[i].visible = false
        end
        -- show
        for i = selfCargoPrevCount+1, rowNumber do
            selfCargoIcons[i].visible = true
            selfCargoBars[i].visible = true
            selfCargoButtons[i].visible = true
            selfCargoTextBoxes[i].visible = true
            selfCargoLabels[i].elem.visible = true
            selfFavoriteButtons[i].visible = true
            selfTrashButtons[i].visible = true
        end
    else
        for i = rowNumber+1, selfCargoPrevCount do
            selfCargoIcons[i].visible = false
            selfCargoBars[i].visible = false
            selfCargoButtons[i].visible = false
            selfCargoTextBoxes[i].visible = false
            selfCargoLabels[i].elem.visible = false
        end
        for i = selfCargoPrevCount+1, rowNumber do
            selfCargoIcons[i].visible = true
            selfCargoBars[i].visible = true
            selfCargoButtons[i].visible = true
            selfCargoTextBoxes[i].visible = true
            selfCargoLabels[i].elem.visible = true
        end
    end
    
    selfCargoPrevCount = rowNumber
end
--MOD