local Azimuth = include("azimuthlib-basic")

local UTF8 -- Client includes
local tct_isWindowShown, tct_favoritesFile, tct_stationFavorites, tct_playerCargoList, tct_selfCargoList, tct_cargoLowerCache, tct_playerPrevQuery, tct_selfPrevQuery, tct_playerGoodIndexesByName, tct_selfGoodIndexesByName, tct_playerGoodNames, tct_selfGoodNames, tct_playerGoodSearchNames, tct_selfGoodSearchNames, tct_playerCargoPrevCount, tct_selfCargoPrevCount, tct_playerAmountByIndex, tct_selfAmountByIndex, tct_playerFavoritesEnabled, tct_selfFavoritesEnabled, tct_playerLastHoveredRow, tct_selfLastHoveredRow, tct_playerCargoRows, tct_selfCargoRows -- Client
local tct_tabbedWindow, tct_helpLabel, tct_crewTabIndex, tct_cargoTabIndex, tct_fightersTabIndex, tct_playerCrewWorkforceLabels, tct_selfCrewWorkforceLabels, tct_playerCrewLabels, tct_selfCrewLabels, tct_playerToggleSearchBtn, tct_selfToggleSearchBtn, tct_playerCargoSearchBox, tct_selfCargoSearchBox, tct_playerCargoLabels, tct_selfCargoLabels, tct_playerToggleFavoritesBtn, tct_selfToggleFavoritesBtn, tct_playerFavoriteButtons, tct_playerTrashButtons, tct_selfFavoriteButtons, tct_selfTrashButtons, tct_leftCargoLister, tct_rightCargoLister, tct_leftCargoFrame, tct_rightCargoFrame -- Client UI
local tct_playerSortGoodsFavorites, tct_selfSortGoodsFavorites, tct_playerSortGoods, tct_selfSortGoods, tct_getGoodColor, tct_createPlayerCargoRow, tct_createSelfCargoRow -- Client local functions
local TCTConfig -- Client/Server


if onClient() then


UTF8 = include("azimuthlib-utf8")

local configOptions = {
  _version = { default = "1.7", comment = "Config version. Don't touch" },
  EnableFavorites = { default = true, comment = "Enable favorites/trash system." },
  ToggleFavoritesByDefault = { default = true, comment = "If favorites system is enabled, it will be turned on by default when you open transfer window." },
  EnableCrewWorkforcePreview = { default = true, comment = "Show current an minimal crew workforce in crew transfer tab." }
}
local isModified
TCTConfig, isModified = Azimuth.loadConfig("TransferCargoTweaks", configOptions)
-- update config
if TCTConfig._version == "1.6" then
    TCTConfig._version = "1.7"
    isModified = true
    TCTConfig.CargoRowsAmount = nil
end
if isModified then
    Azimuth.saveConfig("TransferCargoTweaks", TCTConfig, configOptions)
end

tct_cargoLowerCache = {} -- because non-native UTF8.lower is 32 times slower than string.lower
-- to UTF8.lower query string only when it was changed
tct_playerPrevQuery = {}
tct_selfPrevQuery = {}
-- how many goods were displayed in the previous update/search (performance)
tct_playerCargoPrevCount = 0
tct_selfCargoPrevCount = 0
-- we want to keep textbox values for goods even if their rows are currently hidden (because of search)
tct_playerAmountByIndex = {}
tct_selfAmountByIndex = {}
-- amount of created cargo rows
tct_playerCargoRows = 0
tct_selfCargoRows = 0
-- favorites enabled status
tct_playerFavoritesEnabled = TCTConfig.EnableFavorites and TCTConfig.ToggleFavoritesByDefault
tct_selfFavoritesEnabled = TCTConfig.EnableFavorites and TCTConfig.ToggleFavoritesByDefault

-- LOCAL FUNCTIONS --

tct_playerSortGoodsFavorites = function(a, b)
    -- and here is where performance will probably die
    local goodA = tct_playerCargoList[tct_playerGoodIndexesByName[a]].good
    local goodNameA = goodA.name
    if goodA.suspicious then
        goodNameA = goodNameA .. ".1"
    end
    if goodA.stolen then
        goodNameA = goodNameA .. ".2"
    end
    local goodB = tct_playerCargoList[tct_playerGoodIndexesByName[b]].good
    local goodNameB = goodB.name
    if goodB.suspicious then
        goodNameB = goodNameB .. ".1"
    end
    if goodB.stolen then
        goodNameB = goodNameB .. ".2"
    end
    
    local afav = tct_stationFavorites[1][goodNameA] or 1
    local bfav = tct_stationFavorites[1][goodNameB] or 1
    return afav > bfav or (afav == bfav and UTF8.compare(a, b, true))
end

tct_selfSortGoodsFavorites = function(a, b)
    -- and here is where performance will probably die
    local goodA = tct_selfCargoList[tct_selfGoodIndexesByName[a]].good
    local goodNameA = goodA.name
    if goodA.suspicious then
        goodNameA = goodNameA .. ".1"
    end
    if goodA.stolen then
        goodNameA = goodNameA .. ".2"
    end
    local goodB = tct_selfCargoList[tct_selfGoodIndexesByName[b]].good
    local goodNameB = goodB.name
    if goodB.suspicious then
        goodNameB = goodNameB .. ".1"
    end
    if goodB.stolen then
        goodNameB = goodNameB .. ".2"
    end

    local afav = tct_stationFavorites[2][goodNameA] or 1
    local bfav = tct_stationFavorites[2][goodNameB] or 1
    return afav > bfav or (afav == bfav and UTF8.compare(a, b, true))
end

tct_playerSortGoods = function()
    if not tct_playerFavoritesEnabled then
        table.sort(tct_playerGoodNames, UTF8.comparesensitive)
    else
        table.sort(tct_playerGoodNames, tct_playerSortGoodsFavorites)
    end
    TransferCrewGoods.tct_playerCargoSearch()
end

tct_selfSortGoods = function()
    if not tct_selfFavoritesEnabled then
        table.sort(tct_selfGoodNames, UTF8.comparesensitive)
    else
        table.sort(tct_selfGoodNames, tct_selfSortGoodsFavorites)
    end
    TransferCrewGoods.tct_selfCargoSearch()
end

tct_getGoodColor = function(good)
    if good.illegal then
        return ColorRGB(1, 0, 0)
    end
    if good.dangerous then
        return ColorRGB(1, 1, 0)
    end
    if good.stolen then
        return ColorRGB(0.6, 0, 0.6)
    end
    if good.suspicious then
        return ColorRGB(0, 0.7, 0.82)
    end
    return ColorRGB(1, 1, 1)
end

tct_createPlayerCargoRow = function()
    tct_playerCargoRows = tct_playerCargoRows + 1
    local i = tct_playerCargoRows

    local iconRect = Rect(tct_leftCargoLister.inner.topLeft - vec2(30, 0), tct_leftCargoLister.inner.topLeft + vec2(-5, 25))
    local rect = tct_leftCargoLister:placeCenter(vec2(tct_leftCargoLister.inner.width, 25))
    local vsplit, vsplit2
    if TCTConfig.EnableFavorites then
        vsplit = UIVerticalSplitter(rect, 10, 0, 0.87)
        vsplit2 = UIVerticalSplitter(vsplit.left, 10, 0, 0.77)
    else
        vsplit = UIVerticalSplitter(rect, 10, 0, 0.85)
        vsplit2 = UIVerticalSplitter(vsplit.left, 10, 0, 0.75)
    end

    local icon = tct_leftCargoFrame:createPicture(iconRect, "")
    icon.isIcon = 1
    local button = tct_leftCargoFrame:createButton(vsplit.right, ">>", "onPlayerTransferCargoPressed")
    local bar
    if TCTConfig.EnableFavorites then
        bar = tct_leftCargoFrame:createStatisticsBar(Rect(vsplit2.left.lower + vec2(15, 0), vsplit2.left.upper), ColorInt(0x808080))
    else
        bar = tct_leftCargoFrame:createStatisticsBar(vsplit2.left, ColorInt(0x808080))
    end
    local box = tct_leftCargoFrame:createTextBox(vsplit2.right, "onPlayerTransferCargoTextEntered")
    button.textSize = 16
    box.allowedCharacters = "0123456789"
    box.clearOnClick = true

    playerCargoIcons[i] = icon
    playerCargoButtons[i] = button
    playerCargoBars[i] = bar
    playerCargoTextBoxes[i] = box

    local overlayName

    if TCTConfig.EnableFavorites then
        local favoriteBtn = tct_leftCargoFrame:createPicture(Rect(vsplit2.left.topLeft + vec2(0, 2), vsplit2.left.topLeft + vec2(10, 12)), '')
        favoriteBtn.flipped = true
        favoriteBtn.picture = "data/textures/icons/transfercargotweaks/empty.png"
        tct_playerFavoriteButtons[i] = favoriteBtn
        favoriteBtn.visible = false

        local trashBtn = tct_leftCargoFrame:createPicture(Rect(vsplit2.left.topLeft + vec2(0, 18), vsplit2.left.topLeft + vec2(10, 28)), '')
        trashBtn.flipped = true
        trashBtn.picture = "data/textures/icons/transfercargotweaks/empty.png"
        tct_playerTrashButtons[i] = trashBtn
        trashBtn.visible = false

        overlayName = tct_leftCargoFrame:createLabel(Rect(vsplit2.left.lower + vec2(15, 6), vsplit2.left.upper), "", 10)
    else
        overlayName = tct_leftCargoFrame:createLabel(Rect(vsplit2.left.lower + vec2(0, 6), vsplit2.left.upper), "", 10)
    end

    overlayName.centered = true
    overlayName.wordBreak = false
    tct_playerCargoLabels[i] = { elem = overlayName }

    icon.visible = false
    button.visible = false
    bar.visible = false
    box.visible = false
    overlayName.visible = false
    cargosByButton[button.index] = i
    cargosByTextBox[box.index] = i
    textboxIndexByButton[button.index] = box.index
end

tct_createSelfCargoRow = function()
    tct_selfCargoRows = tct_selfCargoRows + 1
    local i = tct_selfCargoRows

    local iconRect = Rect(tct_rightCargoLister.inner.topRight - vec2(-5, 0), tct_rightCargoLister.inner.topRight + vec2(30, 25))
    local rect = tct_rightCargoLister:placeCenter(vec2(tct_rightCargoLister.inner.width, 25))
    local vsplit, vsplit2
    if TCTConfig.EnableFavorites then
        vsplit = UIVerticalSplitter(rect, 10, 0, 0.13)
        vsplit2 = UIVerticalSplitter(vsplit.right, 10, 0, 0.23)
    else
        vsplit = UIVerticalSplitter(rect, 10, 0, 0.15)
        vsplit2 = UIVerticalSplitter(vsplit.right, 10, 0, 0.25)
    end

    local icon = tct_rightCargoFrame:createPicture(iconRect, "")
    icon.isIcon = 1
    local button = tct_rightCargoFrame:createButton(vsplit.left, "<<", "onSelfTransferCargoPressed")
    local bar
    if TCTConfig.EnableFavorites then
        bar = tct_rightCargoFrame:createStatisticsBar(Rect(vsplit2.right.lower, vsplit2.right.upper - vec2(15, 0)), ColorInt(0x808080))
    else
        bar = tct_rightCargoFrame:createStatisticsBar(vsplit2.right, ColorInt(0x808080))
    end
    local box = tct_rightCargoFrame:createTextBox(vsplit2.left, "onSelfTransferCargoTextEntered")
    button.textSize = 16
    box.allowedCharacters = "0123456789"
    box.clearOnClick = true

    selfCargoIcons[i] = icon
    selfCargoButtons[i] = button
    selfCargoBars[i] = bar
    selfCargoTextBoxes[i] = box

    local overlayName

    if TCTConfig.EnableFavorites then
        local favoriteBtn = tct_rightCargoFrame:createPicture(Rect(vsplit2.right.topRight + vec2(-10, 2), vsplit2.right.topRight + vec2(0, 12)), '')
        favoriteBtn.flipped = true
        favoriteBtn.picture = "data/textures/icons/transfercargotweaks/empty.png"
        tct_selfFavoriteButtons[i] = favoriteBtn
        favoriteBtn.visible = false

        local trashBtn = tct_rightCargoFrame:createPicture(Rect(vsplit2.right.topRight + vec2(-10, 18), vsplit2.right.topRight + vec2(0, 28)), '')
        trashBtn.flipped = true
        trashBtn.picture = "data/textures/icons/transfercargotweaks/empty.png"
        tct_selfTrashButtons[i] = trashBtn
        trashBtn.visible = false

        overlayName = tct_rightCargoFrame:createLabel(Rect(vsplit2.right.lower + vec2(0, 6), vsplit2.right.upper - vec2(15, 0)), "", 10)
    else
        overlayName = tct_rightCargoFrame:createLabel(Rect(vsplit2.right.lower + vec2(0, 6), vsplit2.right.upper), "", 10)
    end

    overlayName.centered = true
    overlayName.wordBreak = false
    tct_selfCargoLabels[i] = { elem = overlayName }

    icon.visible = false
    button.visible = false
    bar.visible = false
    box.visible = false
    overlayName.visible = false

    cargosByButton[button.index] = i
    cargosByTextBox[box.index] = i
    textboxIndexByButton[button.index] = box.index
end

-- PREDEFINED --

function TransferCrewGoods.initUI() -- overridden
    local res = getResolution()
    local size = vec2(850, 635)

    local menu = ScriptUI()
    local window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
    menu:registerWindow(window, "Transfer Crew/Cargo/Fighters"%_t)
    window.caption = "Transfer Crew, Cargo and Fighters"%_t
    window.showCloseButton = 1
    window.moveable = 1

    tct_helpLabel = window:createLabel(Rect(size.x - 65, -29, size.x - 40, -10), "?", 15)
    tct_helpLabel.layer = 2
    tct_helpLabel.tooltip = "In the crew and cargo tabs you can use hotkeys to move\ncertain amounts of items. Simply hold one of the\nfollowing key combinations and click '>>':\nCtrl = 5\nShift = 10\nAlt = 50\nCtrl + Shift = 100\nCtrl + Alt = 250\nShift + Alt = 500\nCtrl + Shift + Alt = 1000"%_t

    tct_tabbedWindow = window:createTabbedWindow(Rect(vec2(10, 10), size - 10))
    tct_tabbedWindow.onSelectedFunction = "tct_onTabbedWindowSelected"
    local crewTab = tct_tabbedWindow:createTab("Crew"%_t, "data/textures/icons/crew.png", "Exchange crew"%_t)
    tct_crewTabIndex = crewTab.index

    local vSplit = UIVerticalSplitter(Rect(crewTab.size), 10, 0, 0.5)

    -- have to use "left" twice here since the coordinates are relative and the UI would be displaced to the right otherwise
    local leftLister = UIVerticalLister(vSplit.left, 10, 10)
    local rightLister = UIVerticalLister(vSplit.left, 10, 10)

    leftLister.marginRight = 30
    rightLister.marginRight = 30

    -- margin for the icon
    leftLister.marginLeft = 35
    rightLister.marginRight = 60

    local leftFrame, rightFrame
    if not TCTConfig.EnableCrewWorkforcePreview then
        leftFrame = crewTab:createScrollFrame(vSplit.left)
        rightFrame = crewTab:createScrollFrame(vSplit.right)
    else
        leftFrame = crewTab:createScrollFrame(Rect(vSplit.left.lower + vec2(0, 90), vSplit.left.upper))
        rightFrame = crewTab:createScrollFrame(Rect(vSplit.right.lower + vec2(0, 90), vSplit.right.upper))

        -- create ui to show how many workforce both ships have and need
        tct_playerCrewWorkforceLabels = {}
        tct_selfCrewWorkforceLabels = {}
        local leftForceHSplitter = UIHorizontalMultiSplitter(Rect(vSplit.left.lower + vec2(10, 0), vSplit.left.lower + vec2(vSplit.left.width - 20, 80)), 10, 0, 2)
        local rightForceHSplitter = UIHorizontalMultiSplitter(Rect(vSplit.right.lower + vec2(10, 0), vSplit.right.lower + vec2(vSplit.right.width - 10, 80)), 10, 0, 2)
        local i = 1
        local profIcon, leftForceVSplitter, rightForceVSplitter, leftPartition, rightPartition, leftIcon, rightIcon
        for j = 0, 2 do
            leftForceVSplitter = UIVerticalMultiSplitter(leftForceHSplitter:partition(j), 8, 0, 3)
            rightForceVSplitter = UIVerticalMultiSplitter(rightForceHSplitter:partition(j), 8, 0, 3)
            for k = 0, 3 do
                if i < 12 then
                    profIcon = CrewProfession(i).icon
                    leftPartition = leftForceVSplitter:partition(k)
                    rightPartition = rightForceVSplitter:partition(k)
                    leftIcon = crewTab:createPicture(Rect(leftPartition.lower, leftPartition.lower + vec2(20, 20)), profIcon)
                    leftIcon.isIcon = 1
                    rightIcon = crewTab:createPicture(Rect(rightPartition.lower, rightPartition.lower + vec2(20, 20)), profIcon)
                    rightIcon.isIcon = 1

                    tct_playerCrewWorkforceLabels[i] = crewTab:createLabel(Rect(leftPartition.lower + vec2(28, 2), leftPartition.upper), "0/0", 11)
                    tct_selfCrewWorkforceLabels[i] = crewTab:createLabel(Rect(rightPartition.lower + vec2(28, 2), rightPartition.upper), "0/0", 11)
                    i = i + 1
                end
            end
        end
    end

    playerTransferAllCrewButton = leftFrame:createButton(Rect(), "Transfer All >>"%_t, "onPlayerTransferAllCrewPressed")
    leftLister:placeElementCenter(playerTransferAllCrewButton)

    selfTransferAllCrewButton = rightFrame:createButton(Rect(), "<< Transfer All"%_t, "onSelfTransferAllCrewPressed")
    rightLister:placeElementCenter(selfTransferAllCrewButton)

    playerTotalCrewBar = leftFrame:createNumbersBar(Rect())
    leftLister:placeElementCenter(playerTotalCrewBar)

    selfTotalCrewBar = rightFrame:createNumbersBar(Rect())
    rightLister:placeElementCenter(selfTotalCrewBar)

    tct_playerCrewLabels = {}
    tct_selfCrewLabels = {}
    for i = 1, CrewProfessionType.Number * 4 do
        local iconRect = Rect(leftLister.inner.topLeft - vec2(30, 0), leftLister.inner.topLeft + vec2(-5, 25))
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
        box.clearOnClick = true

        local overlayName = leftFrame:createLabel(Rect(vsplit2.left.lower + vec2(0, 6), vsplit2.left.upper), "", 10)
        overlayName.centered = true
        overlayName.wordBreak = false
        tct_playerCrewLabels[i] = overlayName

        playerCrewIcons[i] = icon
        playerCrewButtons[i] = button
        playerCrewBars[i] = bar
        playerCrewTextBoxes[i] = box
        crewmenByButton[button.index] = i
        crewmenByTextBox[box.index] = i
        textboxIndexByButton[button.index] = box.index


        local iconRect = Rect(rightLister.inner.topRight - vec2(-5, 0), rightLister.inner.topRight + vec2(30, 25))
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
        box.clearOnClick = true

        local overlayName = rightFrame:createLabel(Rect(vsplit2.right.lower + vec2(0, 6), vsplit2.right.upper), "", 10)
        overlayName.centered = true
        overlayName.wordBreak = false
        tct_selfCrewLabels[i] = overlayName

        selfCrewIcons[i] = icon
        selfCrewButtons[i] = button
        selfCrewBars[i] = bar
        selfCrewTextBoxes[i] = box
        crewmenByButton[button.index] = i
        crewmenByTextBox[box.index] = i
        textboxIndexByButton[button.index] = box.index
    end

    local cargoTab = tct_tabbedWindow:createTab("Cargo"%_t, "data/textures/icons/trade.png", "Exchange cargo"%_t)
    tct_cargoTabIndex = cargoTab.index

    -- have to use "left" twice here since the coordinates are relative and the UI would be displaced to the right otherwise
    tct_leftCargoLister = UIVerticalLister(vSplit.left, 10, 10)
    tct_rightCargoLister = UIVerticalLister(vSplit.left, 10, 10)

    tct_leftCargoLister.marginRight = 30
    tct_rightCargoLister.marginRight = 30

    -- margin for the icon
    tct_leftCargoLister.marginLeft = 35
    tct_rightCargoLister.marginRight = 60

    tct_leftCargoFrame = cargoTab:createScrollFrame(vSplit.left)
    tct_rightCargoFrame = cargoTab:createScrollFrame(vSplit.right)

    if TCTConfig.EnableFavorites then
        playerTransferAllCargoButton = tct_leftCargoFrame:createButton(Rect(0, 10, tct_leftCargoFrame.width - 110, 45), "/* Goods */Transfer All >>"%_t, "onPlayerTransferAllCargoPressed")
        selfTransferAllCargoButton = tct_rightCargoFrame:createButton(Rect(0, 10, tct_rightCargoFrame.width - 110, 45), "/* Goods */<< Transfer All"%_t, "onSelfTransferAllCargoPressed")
    else
        playerTransferAllCargoButton = tct_leftCargoFrame:createButton(Rect(0, 10, tct_leftCargoFrame.width - 75, 45), "/* Goods */Transfer All >>"%_t, "onPlayerTransferAllCargoPressed")
        selfTransferAllCargoButton = tct_rightCargoFrame:createButton(Rect(0, 10, tct_rightCargoFrame.width - 75, 45), "/* Goods */<< Transfer All"%_t, "onSelfTransferAllCargoPressed")
    end
    tct_leftCargoLister:placeElementRight(playerTransferAllCargoButton)
    tct_rightCargoLister:placeElementLeft(selfTransferAllCargoButton)

    playerTotalCargoBar = tct_leftCargoFrame:createNumbersBar(Rect(0, 0, tct_leftCargoFrame.width - 40, 25))
    tct_leftCargoLister:placeElementRight(playerTotalCargoBar)

    selfTotalCargoBar = tct_rightCargoFrame:createNumbersBar(Rect(0, 0, tct_rightCargoFrame.width - 40, 25))
    tct_rightCargoLister:placeElementLeft(selfTotalCargoBar)

    tct_playerToggleSearchBtn = tct_leftCargoFrame:createButton(Rect(10, 10, 40, 45), "", "tct_onPlayerToggleCargoSearchPressed")
    tct_playerToggleSearchBtn.icon = "data/textures/icons/transfercargotweaks/search.png"
    tct_selfToggleSearchBtn = tct_rightCargoFrame:createButton(Rect(tct_rightCargoFrame.width-60, 10, tct_rightCargoFrame.width-30, 45), "", "tct_onSelfToggleCargoSearchPressed")
    tct_selfToggleSearchBtn.icon = "data/textures/icons/transfercargotweaks/search.png"

    tct_playerCargoSearchBox = tct_leftCargoFrame:createTextBox(Rect(12, playerTransferAllCargoButton.height+22, tct_leftCargoFrame.width-33, playerTransferAllCargoButton.height+selfTotalCargoBar.height+18), "tct_playerCargoSearch")
    tct_playerCargoSearchBox.backgroundText = "Search"%_t
    tct_playerCargoSearchBox.visible = false
    tct_selfCargoSearchBox = tct_rightCargoFrame:createTextBox(Rect(12, selfTransferAllCargoButton.height+22, tct_rightCargoFrame.width-33, selfTransferAllCargoButton.height+selfTotalCargoBar.height+18), "tct_selfCargoSearch")
    tct_selfCargoSearchBox.backgroundText = "Search"%_t
    tct_selfCargoSearchBox.visible = false

    if TCTConfig.EnableFavorites then
        tct_playerToggleFavoritesBtn = tct_leftCargoFrame:createButton(Rect(45, 10, 75, 45), "", "tct_onPlayerToggleFavoritesPressed")
        tct_selfToggleFavoritesBtn = tct_rightCargoFrame:createButton(Rect(tct_rightCargoFrame.width-95, 10, tct_rightCargoFrame.width-65, 45), "", "tct_onSelfToggleFavoritesPressed")
        if TCTConfig.ToggleFavoritesByDefault then
            tct_playerToggleFavoritesBtn.icon = "data/textures/icons/transfercargotweaks/favorites-enabled.png"
            tct_selfToggleFavoritesBtn.icon = "data/textures/icons/transfercargotweaks/favorites-enabled.png"
        else
            tct_playerToggleFavoritesBtn.icon = "data/textures/icons/transfercargotweaks/favorites.png"
            tct_selfToggleFavoritesBtn.icon = "data/textures/icons/transfercargotweaks/favorites.png"
        end
    end

    tct_playerCargoLabels = {}
    tct_selfCargoLabels = {}
    tct_playerFavoriteButtons = {}
    tct_playerTrashButtons = {}
    tct_selfFavoriteButtons = {}
    tct_selfTrashButtons = {}

    -- create fighters tab
    local fightersTab = tct_tabbedWindow:createTab("Fighters"%_t, "data/textures/icons/fighter.png", "Exchange fighters"%_t)
    tct_fightersTabIndex = fightersTab.index

    local leftLister = UIVerticalLister(vSplit.left, 0, 0)
    local rightLister = UIVerticalLister(vSplit.right, 0, 0)

    leftLister.marginLeft = 5
    rightLister.marginLeft = 5

    playerTransferAllFightersButton = fightersTab:createButton(Rect(), "Transfer All >>"%_t, "onPlayerTransferAllFightersPressed")
    leftLister:placeElementCenter(playerTransferAllFightersButton)

    selfTransferAllFightersButton = fightersTab:createButton(Rect(), "<< Transfer All"%_t, "onSelfTransferAllFightersPressed")
    rightLister:placeElementCenter(selfTransferAllFightersButton)

    for i = 1, 10 do
        -- left side (player)
        local rect = leftLister:placeCenter(vec2(leftLister.inner.width, 18))
        local label = fightersTab:createLabel(rect, "", 16)
        playerFighterLabels[i] = label

        local rect = leftLister:placeCenter(vec2(leftLister.inner.width, 35))
        rect.upper = vec2(rect.lower.x + 376, rect.upper.y)
        local selection = fightersTab:createSelection(rect, 12)
        selection.dropIntoEnabled = true
        selection.dragFromEnabled = true
        selection.entriesSelectable = false
        selection.onReceivedFunction = "onFighterReceived"
        selection.onClickedFunction = "onFighterClicked"
        selection.padding = 4

        playerFighterSelections[i] = selection
        isPlayerShipBySelection[selection.index] = true
        squadIndexBySelection[selection.index] = i - 1

        -- right side (self)
        local rect = rightLister:placeCenter(vec2(rightLister.inner.width, 18))
        local label = fightersTab:createLabel(rect, "", 16)
        selfFighterLabels[i] = label

        local rect = rightLister:placeCenter(vec2(rightLister.inner.width, 35))
        rect.upper = vec2(rect.lower.x + 376, rect.upper.y)
        local selection = fightersTab:createSelection(rect, 12)
        selection.dropIntoEnabled = true
        selection.dragFromEnabled = true
        selection.entriesSelectable = false
        selection.onReceivedFunction = "onFighterReceived"
        selection.onClickedFunction = "onFighterClicked"
        selection.padding = 4

        selfFighterSelections[i] = selection
        isPlayerShipBySelection[selection.index] = false
        squadIndexBySelection[selection.index] = i - 1
    end
end

function TransferCrewGoods.onShowWindow() -- overridden
    tct_isWindowShown = true

    local player = Player()
    local ship = Entity()
    local other = player.craft

    ship:registerCallback("onCrewChanged", "onCrewChanged")
    other:registerCallback("onCrewChanged", "onCrewChanged")
    
    if TCTConfig.EnableFavorites then -- load favorites
        tct_favoritesFile = Azimuth.loadConfig("TransferCargoTweaks", { _version = TCTConfig._version }, true, true)
        local favorites = tct_favoritesFile[Entity().index.string] or { {}, {} }
        if not favorites[1] then favorites[1] = {} end
        if not favorites[2] then favorites[2] = {} end
        tct_stationFavorites = favorites
    end

    TransferCrewGoods.updateData()
end

function TransferCrewGoods.onCloseWindow() -- overridden
    local player = Player()
    local ship = Entity()
    local other = player.craft

    ship:unregisterCallback("onCrewChanged", "onCrewChanged")
    other:unregisterCallback("onCrewChanged", "onCrewChanged")

    if TCTConfig.EnableFavorites then -- save favorites
        local favorites = { {}, {} }
        local playerFavCount = 0
        local selfFavCount = 0
        for k, v in pairs(tct_stationFavorites[1]) do
            playerFavCount = playerFavCount + 1
            favorites[1][k] = v
        end
        for k, v in pairs(tct_stationFavorites[2]) do
            selfFavCount = selfFavCount + 1
            favorites[2][k] = v
        end
        if playerFavCount == 0 and selfFavCount == 0 then
            favorites = nil
        else
            if playerFavCount == 0 then favorites[1] = nil end
            if selfFavCount == 0 then favorites[2] = nil end
        end
        tct_favoritesFile[Entity().index.string] = favorites
        Azimuth.saveConfig("TransferCargoTweaks", tct_favoritesFile, nil, true, true, true)
        tct_favoritesFile = nil
        tct_stationFavorites = { {}, {} }
    end

    tct_isWindowShown = false
end

-- FUNCTIONS --

function TransferCrewGoods.updateData() -- overridden
    local playerShip = Player().craft
    local ship = Entity()
    local currentTabIndex = tct_tabbedWindow:getActiveTab()
    currentTabIndex = currentTabIndex and currentTabIndex.index or -1

    if currentTabIndex == tct_crewTabIndex then -- update crew info

        playerTotalCrewBar:clear()
        selfTotalCrewBar:clear()

        playerTotalCrewBar:setRange(0, playerShip.maxCrewSize)
        selfTotalCrewBar:setRange(0, ship.maxCrewSize)

        for i = 1, #playerCrewIcons do
            playerCrewIcons[i].visible = false
            selfCrewIcons[i].visible = false
            playerCrewBars[i].visible = false
            selfCrewBars[i].visible = false
            playerCrewButtons[i].visible = false
            selfCrewButtons[i].visible = false
            playerCrewTextBoxes[i].visible = false
            selfCrewTextBoxes[i].visible = false
            tct_playerCrewLabels[i].visible = false
            tct_selfCrewLabels[i].visible = false
        end

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

            local caption = ""
            if not crewman.specialist then
                caption = "${profession} (untrained)"%_t % {profession = crewman.profession:name(num)}
            else
                caption = "${profession} (level ${level})"%_t % {profession = crewman.profession:name(num), level = crewman.level}
            end
            playerTotalCrewBar:addEntry(num, caption, crewman.profession.color)

            local icon = playerCrewIcons[i]
            icon:show()
            icon.picture = crewman.profession.icon
            icon.tooltip = crewman.profession:name()

            local singleBar = playerCrewBars[i]
            singleBar.visible = true
            singleBar:setRange(0, playerShip.maxCrewSize)
            singleBar.value = num
            if num < playerShip.maxCrewSize then
                singleBar.value = num
            else
                singleBar.value = playerShip.maxCrewSize
            end
            singleBar.name = caption
            singleBar.color = crewman.profession.color

            local button = playerCrewButtons[i]
            button.visible = true

            -- restore textbox value
            local box = playerCrewTextBoxes[i]
            if not box.isTypingActive then
                local index = p.crewman.profession.value * 4
                if p.crewman.specialist then index = index + p.crewman.level end
                local amount = TransferCrewGoods.clampNumberString(amountByIndex[index] or "1", num)
                table.insert(playerCrewTextBoxByIndex, index, i)

                box.visible = true
                if amount == "" then
                    box.text = "1"
                else
                    box.text = amount
                end
            end

            tct_playerCrewLabels[i].caption = caption
            tct_playerCrewLabels[i].visible = true

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

            local caption = ""
            if not crewman.specialist then
                caption = "${profession} (untrained)"%_t % {profession = crewman.profession:name(num)}
            else
                caption = "${profession} (level ${level})"%_t % {profession = crewman.profession:name(num), level = crewman.level}
            end
            selfTotalCrewBar:addEntry(num, caption, crewman.profession.color)

            local icon = selfCrewIcons[i]
            icon:show()
            icon.picture = crewman.profession.icon
            icon.tooltip = crewman.profession:name()

            local singleBar = selfCrewBars[i]
            singleBar.visible = true
            singleBar:setRange(0, ship.maxCrewSize)
            singleBar.value = num
            if num < ship.maxCrewSize then
                singleBar.value = num
            else
                singleBar.value = ship.maxCrewSize
            end
            singleBar.name = caption
            singleBar.color = crewman.profession.color

            local button = selfCrewButtons[i]
            button.visible = true

            -- restore textbox value
            local box = selfCrewTextBoxes[i]
            if not box.isTypingActive then
                local index = p.crewman.profession.value * 4
                if p.crewman.specialist then index = index + p.crewman.level end

                local amount = TransferCrewGoods.clampNumberString(amountByIndex[index] or "1", num)
                table.insert(selfCrewTextBoxByIndex, index, i)

                box.visible = true
                if amount == "" then
                    box.text = "1"
                else
                    box.text = amount
                end
            end

            tct_selfCrewLabels[i].caption = caption
            tct_selfCrewLabels[i].visible = true

            i = i + 1
        end

        -- update workforce labels
        if TCTConfig.EnableCrewWorkforcePreview then
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

            for i = 1, 11 do
                -- player
                if not playerMinWorkforce[i] then playerMinWorkforce[i] = 0 end
                if not playerWorkforce[i] then playerWorkforce[i] = 0 end
                tct_playerCrewWorkforceLabels[i].caption = playerWorkforce[i] .. "/" .. playerMinWorkforce[i]
                if playerWorkforce[i] < playerMinWorkforce[i] then
                    tct_playerCrewWorkforceLabels[i].color = ColorInt(0xffff2626)
                else
                    local mult = 1.0
                    if i == CrewProfessionType.Engine or i == CrewProfessionType.Repair then
                        mult = 1.3
                    end
                    if playerMinWorkforce[i] * mult + 2 < playerWorkforce[i] then -- too much crew
                        tct_playerCrewWorkforceLabels[i].color = ColorInt(0xff00b1d1)
                    else
                        tct_playerCrewWorkforceLabels[i].color = ColorInt(0xffe0e0e0)
                    end
                end
                -- self
                if not selfMinWorkforce[i] then selfMinWorkforce[i] = 0 end
                if not selfWorkforce[i] then selfWorkforce[i] = 0 end
                tct_selfCrewWorkforceLabels[i].caption = selfWorkforce[i] .. "/" .. selfMinWorkforce[i]
                if selfWorkforce[i] < selfMinWorkforce[i] then
                    tct_selfCrewWorkforceLabels[i].color = ColorInt(0xffff2626)
                else
                    local mult = 1.0
                    if i == CrewProfessionType.Engine or i == CrewProfessionType.Repair then
                        mult = 1.3
                    end
                    if selfMinWorkforce[i] * mult + 2 < selfWorkforce[i] then -- too much crew
                        tct_selfCrewWorkforceLabels[i].color = ColorInt(0xff00b1d1)
                    else
                        tct_selfCrewWorkforceLabels[i].color = ColorInt(0xffe0e0e0)
                    end
                end
            end
        end

    elseif currentTabIndex == tct_cargoTabIndex then -- update cargo info

        playerTotalCargoBar:clear()
        selfTotalCargoBar:clear()

        playerTotalCargoBar:setRange(0, playerShip.maxCargoSpace)
        selfTotalCargoBar:setRange(0, ship.maxCargoSpace)

        -- sort goods by localized name
        tct_playerGoodNames = {}
        tct_playerGoodIndexesByName = {}
        tct_selfGoodNames = {}
        tct_selfGoodIndexesByName = {}

        tct_playerCargoList = {}
        tct_selfCargoList = {}

        for i = 1, (playerShip.numCargos or 0) do
            local good, amount = playerShip:getCargo(i - 1)
            tct_playerCargoList[i] = { good = good, amount = amount }
            local displayName = good:displayName(1)
            tct_playerGoodNames[i] = displayName
            tct_playerGoodIndexesByName[displayName] = i

            local name = "${amount} ${good}"%_t % {amount = createMonetaryString(amount), good = good:displayName(amount)}
            playerTotalCargoBar:addEntry(amount * good.size, name, ColorInt(0xff808080))
        end

        for i = 1, (ship.numCargos or 0) do
            local good, amount = ship:getCargo(i - 1)
            tct_selfCargoList[i] = { good = good, amount = amount }
            local displayName = good:displayName(1)
            tct_selfGoodNames[i] = displayName
            tct_selfGoodIndexesByName[displayName] = i

            local name = "${amount} ${good}"%_t % {amount = createMonetaryString(amount), good = good:displayName(amount)}
            selfTotalCargoBar:addEntry(amount * good.size, name, ColorInt(0xff808080))
        end

        tct_playerSortGoods()
        tct_selfSortGoods()

    elseif currentTabIndex == tct_fightersTabIndex then -- update fighter info

        for i = 1, #playerFighterLabels do
            playerFighterLabels[i].visible = false
            selfFighterLabels[i].visible = false
            playerFighterSelections[i].visible = false
            selfFighterSelections[i].visible = false
        end

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
end

-- CALLBACKS --

function TransferCrewGoods.renderUI() -- overridden
    local currentTabIndex = tct_tabbedWindow:getActiveTab()
    currentTabIndex = currentTabIndex and currentTabIndex.index or -1

    if currentTabIndex == tct_fightersTabIndex then -- render fighters stuff

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

        if activeSelection then
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
            return
        end

    elseif currentTabIndex == tct_cargoTabIndex then -- render cargo stuff

        if TCTConfig.EnableFavorites then

            local cargo, goodName, priority, btn, playerHoveredRow, selfHoveredRow
            -- change icon on hover, change item priority on icon click
            for i = 1, tct_playerCargoPrevCount do
                if playerCargoIcons[i].mouseOver
                  or playerCargoButtons[i].mouseOver
                  or playerCargoBars[i].mouseOver
                  or playerCargoTextBoxes[i].mouseOver
                  or tct_playerFavoriteButtons[i].mouseOver
                  or tct_playerTrashButtons[i].mouseOver then
                    cargo = tct_playerCargoList[tct_playerGoodIndexesByName[tct_playerGoodSearchNames[i]]]
                    goodName = cargo.good.name
                    if cargo.good.suspicious then
                        goodName = goodName .. ".1"
                    end
                    if cargo.good.stolen then
                        goodName = goodName .. ".2"
                    end
                    priority = tct_stationFavorites[1][goodName]
                    playerHoveredRow = i

                    if Mouse():mouseDown(3) then
                        if tct_playerFavoriteButtons[i].mouseOver then
                            if priority ~= 2 then
                                tct_stationFavorites[1][goodName] = 2
                                tct_playerFavoriteButtons[i].picture = "data/textures/icons/transfercargotweaks/star.png"
                                tct_playerTrashButtons[i].picture = "data/textures/icons/transfercargotweaks/empty.png"
                            else
                                tct_stationFavorites[1][goodName] = nil
                                tct_playerFavoriteButtons[i].picture = "data/textures/icons/transfercargotweaks/empty.png"
                            end
                            if tct_playerFavoritesEnabled then tct_playerSortGoods() end
                        elseif tct_playerTrashButtons[i].mouseOver then
                            if priority ~= 0 then
                                tct_stationFavorites[1][goodName] = 0
                                tct_playerFavoriteButtons[i].picture = "data/textures/icons/transfercargotweaks/empty.png"
                                tct_playerTrashButtons[i].picture = "data/textures/icons/transfercargotweaks/trash.png"
                            else
                                tct_stationFavorites[1][goodName] = nil
                                tct_playerTrashButtons[i].picture = "data/textures/icons/transfercargotweaks/empty.png"
                            end
                            if tct_playerFavoritesEnabled then tct_playerSortGoods() end
                        end
                    else -- just hover
                        if priority ~= 2 then
                            tct_playerFavoriteButtons[i].picture = "data/textures/icons/transfercargotweaks/star-hover.png"
                        end
                        if priority ~= 0 then
                            tct_playerTrashButtons[i].picture = "data/textures/icons/transfercargotweaks/trash-hover.png"
                        end
                    end
                    break
                end
            end
            for i = 1, tct_selfCargoPrevCount do
                if selfCargoIcons[i].mouseOver
                  or selfCargoButtons[i].mouseOver
                  or selfCargoBars[i].mouseOver
                  or selfCargoTextBoxes[i].mouseOver
                  or tct_selfFavoriteButtons[i].mouseOver
                  or tct_selfTrashButtons[i].mouseOver then
                    cargo = tct_selfCargoList[tct_selfGoodIndexesByName[tct_selfGoodSearchNames[i]]]
                    goodName = cargo.good.name
                    if cargo.good.suspicious then
                        goodName = goodName .. ".1"
                    end
                    if cargo.good.stolen then
                        goodName = goodName .. ".2"
                    end
                    priority = tct_stationFavorites[2][goodName]
                    selfHoveredRow = i

                    if Mouse():mouseDown(3) then
                        if tct_selfFavoriteButtons[i].mouseOver then
                            if priority ~= 2 then
                                tct_stationFavorites[2][goodName] = 2
                                tct_selfFavoriteButtons[i].picture = "data/textures/icons/transfercargotweaks/star.png"
                                tct_selfTrashButtons[i].picture = "data/textures/icons/transfercargotweaks/empty.png"
                            else
                                tct_stationFavorites[2][goodName] = nil
                                tct_selfFavoriteButtons[i].picture = "data/textures/icons/transfercargotweaks/empty.png"
                            end
                            if tct_selfFavoritesEnabled then tct_selfSortGoods() end
                        elseif tct_selfTrashButtons[i].mouseOver then
                            if priority ~= 0 then
                                tct_stationFavorites[2][goodName] = 0
                                tct_selfFavoriteButtons[i].picture = "data/textures/icons/transfercargotweaks/empty.png"
                                tct_selfTrashButtons[i].picture = "data/textures/icons/transfercargotweaks/trash.png"
                            else
                                tct_stationFavorites[2][goodName] = nil
                                tct_selfTrashButtons[i].picture = "data/textures/icons/transfercargotweaks/empty.png"
                            end
                            if tct_selfFavoritesEnabled then tct_selfSortGoods() end
                        end
                    else -- just hover
                        if priority ~= 2 then
                            tct_selfFavoriteButtons[i].picture = "data/textures/icons/transfercargotweaks/star-hover.png"
                        end
                        if priority ~= 0 then
                            tct_selfTrashButtons[i].picture = "data/textures/icons/transfercargotweaks/trash-hover.png"
                        end
                    end
                    break
                end
            end
            -- return icons to 'hidden' image, when mouse left them
            if tct_playerLastHoveredRow and tct_playerLastHoveredRow ~= playerHoveredRow and tct_playerLastHoveredRow <= #tct_playerGoodSearchNames then
                cargo = tct_playerCargoList[tct_playerGoodIndexesByName[tct_playerGoodSearchNames[tct_playerLastHoveredRow]]]
                local goodName = cargo.good.name
                if cargo.good.suspicious then
                    goodName = goodName .. ".1"
                end
                if cargo.good.stolen then
                    goodName = goodName .. ".2"
                end
                priority = tct_stationFavorites[1][goodName]
                if priority ~= 2 then
                    tct_playerFavoriteButtons[tct_playerLastHoveredRow].picture = "data/textures/icons/transfercargotweaks/empty.png"
                end
                if priority ~= 0 then
                    tct_playerTrashButtons[tct_playerLastHoveredRow].picture = "data/textures/icons/transfercargotweaks/empty.png"
                end
            end
            tct_playerLastHoveredRow = playerHoveredRow

            if tct_selfLastHoveredRow and tct_selfLastHoveredRow ~= selfHoveredRow and tct_selfLastHoveredRow <= #tct_selfGoodSearchNames then
                cargo = tct_selfCargoList[tct_selfGoodIndexesByName[tct_selfGoodSearchNames[tct_selfLastHoveredRow]]]
                local goodName = cargo.good.name
                if cargo.good.suspicious then
                    goodName = goodName .. ".1"
                end
                if cargo.good.stolen then
                    goodName = goodName .. ".2"
                end
                priority = tct_stationFavorites[2][goodName]
                if priority ~= 2 then
                    tct_selfFavoriteButtons[tct_selfLastHoveredRow].picture = "data/textures/icons/transfercargotweaks/empty.png"
                end
                if priority ~= 0 then
                    tct_selfTrashButtons[tct_selfLastHoveredRow].picture = "data/textures/icons/transfercargotweaks/empty.png"
                end
            end
            tct_selfLastHoveredRow = selfHoveredRow

        end

    end
end

function TransferCrewGoods.onPlayerTransferCrewPressed(button) -- overridden
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
    local keyboard = Keyboard()
    --[[ Ctrl = 5
    Shift = 10
    Alt = 50
    Ctrl+Shift = 100
    Ctrl+Alt = 250
    Shift+Alt = 500
    Ctrl+Shift+Alt = 1000 ]]
    local keyAmount = 1
    if keyboard:keyPressed(KeyboardKey.LControl) or keyboard:keyPressed(KeyboardKey.RControl) then
        keyAmount = 5
    end
    if keyboard:keyPressed(KeyboardKey.LShift) or keyboard:keyPressed(KeyboardKey.RShift) then
        keyAmount = (keyAmount == 5) and 100 or 10
    end
    if keyboard:keyPressed(KeyboardKey.LAlt) or keyboard:keyPressed(KeyboardKey.RAlt) then
        keyAmount = (keyAmount == 100) and 1000 or (keyAmount * 50)
    end
    if keyAmount > 1 then
        amount = keyAmount
    end
    if amount == 0 then return end

    invokeServerFunction("transferCrew", crewmanIndex, Player().craftIndex, false, amount)
end

function TransferCrewGoods.onSelfTransferCrewPressed(button) -- overridden
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
    local keyboard = Keyboard()
    local keyAmount = 1
    if keyboard:keyPressed(KeyboardKey.LControl) or keyboard:keyPressed(KeyboardKey.RControl) then
        keyAmount = 5
    end
    if keyboard:keyPressed(KeyboardKey.LShift) or keyboard:keyPressed(KeyboardKey.RShift) then
        keyAmount = (keyAmount == 5) and 100 or 10
    end
    if keyboard:keyPressed(KeyboardKey.LAlt) or keyboard:keyPressed(KeyboardKey.RAlt) then
        keyAmount = (keyAmount == 100) and 1000 or (keyAmount * 50)
    end
    if keyAmount > 1 then
        amount = keyAmount
    end
    if amount == 0 then return end

    invokeServerFunction("transferCrew", crewmanIndex, Player().craftIndex, true, amount)
end

function TransferCrewGoods.onPlayerTransferCargoTextEntered(textBox) -- overridden
    local enteredNumber = tonumber(textBox.text)
    if enteredNumber == nil then
        enteredNumber = 0
    end

    local newNumber = enteredNumber

    -- get available amount
    local cargoIndex = cargosByTextBox[textBox.index]
    if not cargoIndex then return end

    local sender = Entity(Player().craftIndex)
    local maxAmount = tct_playerCargoList[tct_playerGoodIndexesByName[tct_playerGoodSearchNames[cargoIndex]]].amount or 0

    if newNumber > maxAmount then
        newNumber = maxAmount
    end

    if newNumber ~= enteredNumber then
        textBox.text = newNumber
    end
end

function TransferCrewGoods.onSelfTransferCargoTextEntered(textBox) -- overridden
    local enteredNumber = tonumber(textBox.text)
    if enteredNumber == nil then
        enteredNumber = 0
    end

    local newNumber = enteredNumber

    -- get available amount
    local cargoIndex = cargosByTextBox[textBox.index]
    if not cargoIndex then return end

    local sender = Entity()
    local maxAmount = tct_selfCargoList[tct_selfGoodIndexesByName[tct_selfGoodSearchNames[cargoIndex]]].amount or 0

    if newNumber > maxAmount then
        newNumber = maxAmount
    end

    if newNumber ~= enteredNumber then
        textBox.text = newNumber
    end
end

function TransferCrewGoods.onPlayerTransferCargoPressed(button) -- overridden
    -- transfer cargo from player ship to self

    -- check which cargo
    local cargo = cargosByButton[button.index]
    if cargo == nil then return end
    cargo = tct_playerGoodIndexesByName[tct_playerGoodSearchNames[cargo]]

    -- get amount
    local textboxIndex = textboxIndexByButton[button.index]
    if not textboxIndex then return end

    local box = TextBox(textboxIndex)
    if not box then return end

    local amount = tonumber(box.text) or 0
    local keyboard = Keyboard()
    local keyAmount = 1
    if keyboard:keyPressed(KeyboardKey.LControl) or keyboard:keyPressed(KeyboardKey.RControl) then
        keyAmount = 5
    end
    if keyboard:keyPressed(KeyboardKey.LShift) or keyboard:keyPressed(KeyboardKey.RShift) then
        keyAmount = (keyAmount == 5) and 100 or 10
    end
    if keyboard:keyPressed(KeyboardKey.LAlt) or keyboard:keyPressed(KeyboardKey.RAlt) then
        keyAmount = (keyAmount == 100) and 1000 or (keyAmount * 50)
    end
    if keyAmount > 1 then
        amount = keyAmount
    end
    if amount == 0 then return end

    invokeServerFunction("transferCargo", cargo - 1, Player().craftIndex, false, amount)
end

function TransferCrewGoods.onSelfTransferCargoPressed(button) -- overridden
    -- transfer cargo from self to player ship

    -- check which cargo
    local cargo = cargosByButton[button.index]
    if cargo == nil then return end
    cargo = tct_selfGoodIndexesByName[tct_selfGoodSearchNames[cargo]]

    -- get amount
    local textboxIndex = textboxIndexByButton[button.index]
    if not textboxIndex then return end

    local box = TextBox(textboxIndex)
    if not box then return end

    local amount = tonumber(box.text) or 0
    local keyboard = Keyboard()
    local keyAmount = 1
    if keyboard:keyPressed(KeyboardKey.LControl) or keyboard:keyPressed(KeyboardKey.RControl) then
        keyAmount = 5
    end
    if keyboard:keyPressed(KeyboardKey.LShift) or keyboard:keyPressed(KeyboardKey.RShift) then
        keyAmount = (keyAmount == 5) and 100 or 10
    end
    if keyboard:keyPressed(KeyboardKey.LAlt) or keyboard:keyPressed(KeyboardKey.RAlt) then
        keyAmount = (keyAmount == 100) and 1000 or (keyAmount * 50)
    end
    if keyAmount > 1 then
        amount = keyAmount
    end
    if amount == 0 then return end

    invokeServerFunction("transferCargo", cargo - 1, Player().craftIndex, true, amount)
end

-- CUSTOM CALLBACKS --

function TransferCrewGoods.tct_onTabbedWindowSelected(tabbedWindowIndex, tabIndex) -- update data when switching tabs
    if not tct_isWindowShown then return end

    TransferCrewGoods.updateData()

    if tabIndex ~= tct_crewTabIndex and tabIndex ~= tct_cargoTabIndex then
        tct_helpLabel.visible = false
    else
        tct_helpLabel.visible = true
    end
end

function TransferCrewGoods.tct_onPlayerToggleCargoSearchPressed(button)
    tct_playerCargoSearchBox.visible = not tct_playerCargoSearchBox.visible
end

function TransferCrewGoods.tct_onPlayerToggleFavoritesPressed(button)
    tct_playerFavoritesEnabled = not tct_playerFavoritesEnabled
    if tct_playerFavoritesEnabled then
        button.icon = "data/textures/icons/transfercargotweaks/favorites-enabled.png"
    else
        button.icon = "data/textures/icons/transfercargotweaks/favorites.png"
    end
    tct_playerSortGoods()
end

function TransferCrewGoods.tct_onSelfToggleCargoSearchPressed(button)
    tct_selfCargoSearchBox.visible = not tct_selfCargoSearchBox.visible
end

function TransferCrewGoods.tct_onSelfToggleFavoritesPressed(button)
    tct_selfFavoritesEnabled = not tct_selfFavoritesEnabled
    if tct_selfFavoritesEnabled then
        button.icon = "data/textures/icons/transfercargotweaks/favorites-enabled.png"
    else
        button.icon = "data/textures/icons/transfercargotweaks/favorites.png"
    end
    tct_selfSortGoods()
end

function TransferCrewGoods.tct_playerCargoSearch()
    local playerShip = Player().craft

    -- save/retrieve lowercase query because we don't want to recalculate it every update (not search)
    local query = tct_playerCargoSearchBox.text
    if tct_playerPrevQuery[1] ~= query then
        if tct_playerPrevQuery[1] == '' then
            tct_playerToggleSearchBtn.icon = "data/textures/icons/transfercargotweaks/search-text.png"
        elseif query == '' then
            tct_playerToggleSearchBtn.icon = "data/textures/icons/transfercargotweaks/search.png"
        end
        tct_playerPrevQuery[1] = query
        tct_playerPrevQuery[2] = UTF8.lower(query)
    end
    query = tct_playerPrevQuery[2]

    -- save textbox numbers
    for cargoName, index in pairs(playerCargoTextBoxByIndex) do
        tct_playerAmountByIndex[cargoName] = playerCargoTextBoxes[index].text
    end
    playerCargoTextBoxByIndex = {}

    local playerMaxSpace = playerShip.maxCargoSpace or 0

    tct_playerGoodSearchNames = {} --list of good names that is currently shown

    local rowNumber = 0
    for i = 1, #tct_playerGoodNames do
        local cargo = tct_playerCargoList[tct_playerGoodIndexesByName[tct_playerGoodNames[i]]]
        local good = cargo.good
        local amount = cargo.amount
        
        -- save/retrieve lowercase good names
        local nameLowercase
        local actualDisplayName = good:displayName(amount)
        if not tct_cargoLowerCache[actualDisplayName] then
            tct_cargoLowerCache[actualDisplayName] = UTF8.lower(actualDisplayName)
        end
        nameLowercase = tct_cargoLowerCache[actualDisplayName]

        if query == "" or UTF8.find(nameLowercase, query, 1, true, true) then
            rowNumber = rowNumber + 1
            
            if rowNumber > tct_playerCargoRows then
                tct_createPlayerCargoRow()
            end

            local bar = playerCargoBars[rowNumber]
            local overlayName = tct_playerCargoLabels[rowNumber]
            local displayName = tct_playerGoodNames[i]

            playerCargoIcons[rowNumber].picture = good.icon
            bar:setRange(0, playerMaxSpace)
            bar.value = amount * good.size
            local name = "${amount} ${good}"%_t % {amount = createMonetaryString(amount), good = actualDisplayName}
            bar.name = name

            tct_playerGoodSearchNames[rowNumber] = displayName

            local nameWithStatus = good.name
            if good.suspicious then
                nameWithStatus = nameWithStatus .. ".1"
            end
            if good.stolen then
                nameWithStatus = nameWithStatus .. ".2"
            end

            -- restore textbox value
            local box = playerCargoTextBoxes[rowNumber]
            if not box.isTypingActive then
                local boxAmount = TransferCrewGoods.clampNumberString(tct_playerAmountByIndex[nameWithStatus] or "1", amount)
                playerCargoTextBoxByIndex[nameWithStatus] = rowNumber
                box.text = boxAmount
                if boxAmount == "" then
                    box.text = "1"
                else
                    box.text = boxAmount
                end
            end

            -- favorites and trash icons/buttons
            if TCTConfig.EnableFavorites then
                local priority = tct_stationFavorites[1][nameWithStatus]
                if priority == 2 then
                    tct_playerFavoriteButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/star.png"
                    tct_playerTrashButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/empty.png"
                elseif priority == 0 then
                    tct_playerFavoriteButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/empty.png"
                    tct_playerTrashButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/trash.png"
                else
                    tct_playerFavoriteButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/empty.png"
                    tct_playerTrashButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/empty.png"
                end
            end

            -- cargo overlay name
            -- adjust overlay name vertically (because we don't have built-in way to do this)
            if UTF8.len(name) > 28 then
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
            overlayName.elem.caption = name
            overlayName.elem.color = tct_getGoodColor(good)
        end
    end

    if TCTConfig.EnableFavorites then
        -- hide only rows that were shown in prev search but not in current
        for i = rowNumber+1, tct_playerCargoPrevCount do
            playerCargoIcons[i].visible = false
            playerCargoBars[i].visible = false
            playerCargoButtons[i].visible = false
            playerCargoTextBoxes[i].visible = false
            tct_playerCargoLabels[i].elem.visible = false
            tct_playerFavoriteButtons[i].visible = false
            tct_playerTrashButtons[i].visible = false
        end
        -- show only rows that were not shown in prev search but will be in current
        for i = tct_playerCargoPrevCount+1, rowNumber do
            playerCargoIcons[i].visible = true
            playerCargoBars[i].visible = true
            playerCargoButtons[i].visible = true
            playerCargoTextBoxes[i].visible = true
            tct_playerCargoLabels[i].elem.visible = true
            tct_playerFavoriteButtons[i].visible = true
            tct_playerTrashButtons[i].visible = true
        end
    else
        for i = rowNumber+1, tct_playerCargoPrevCount do
            playerCargoIcons[i].visible = false
            playerCargoBars[i].visible = false
            playerCargoButtons[i].visible = false
            playerCargoTextBoxes[i].visible = false
            tct_playerCargoLabels[i].elem.visible = false
        end
        for i = tct_playerCargoPrevCount+1, rowNumber do
            playerCargoIcons[i].visible = true
            playerCargoBars[i].visible = true
            playerCargoButtons[i].visible = true
            playerCargoTextBoxes[i].visible = true
            tct_playerCargoLabels[i].elem.visible = true
        end
    end

    tct_playerCargoPrevCount = rowNumber
end

function TransferCrewGoods.tct_selfCargoSearch()
    local ship = Entity()

    local query = tct_selfCargoSearchBox.text
    if tct_selfPrevQuery[1] ~= query then
        if tct_selfPrevQuery[1] == '' then
            tct_selfToggleSearchBtn.icon = "data/textures/icons/transfercargotweaks/search-text.png"
        elseif query == '' then
            tct_selfToggleSearchBtn.icon = "data/textures/icons/transfercargotweaks/search.png"
        end
        tct_selfPrevQuery[1] = query
        tct_selfPrevQuery[2] = UTF8.lower(query)
    end
    query = tct_selfPrevQuery[2]

    for cargoName, index in pairs(selfCargoTextBoxByIndex) do
        tct_selfAmountByIndex[cargoName] = selfCargoTextBoxes[index].text
    end
    selfCargoTextBoxByIndex = {}

    local selfMaxSpace = ship.maxCargoSpace or 0

    tct_selfGoodSearchNames = {}

    local rowNumber = 0
    for i = 1, #tct_selfGoodNames do
        local cargo = tct_selfCargoList[tct_selfGoodIndexesByName[tct_selfGoodNames[i]]]
        local good = cargo.good
        local amount = cargo.amount
        
        local nameLowercase
        local actualDisplayName = good:displayName(amount)
        if not tct_cargoLowerCache[actualDisplayName] then
            tct_cargoLowerCache[actualDisplayName] = UTF8.lower(actualDisplayName)
        end
        nameLowercase = tct_cargoLowerCache[actualDisplayName]

        if query == "" or UTF8.find(nameLowercase, query, 1, true, true) then
            rowNumber = rowNumber + 1

            if rowNumber > tct_selfCargoRows then
                tct_createSelfCargoRow()
            end

            local bar = selfCargoBars[rowNumber]
            local overlayName = tct_selfCargoLabels[rowNumber]
            local displayName = tct_selfGoodNames[i]

            selfCargoIcons[rowNumber].picture = good.icon
            bar:setRange(0, selfMaxSpace)
            bar.value = amount * good.size
            local name = "${amount} ${good}"%_t % {amount = createMonetaryString(amount), good = actualDisplayName}
            bar.name = name

            tct_selfGoodSearchNames[rowNumber] = displayName

            local nameWithStatus = good.name
            if good.suspicious then
                nameWithStatus = nameWithStatus .. ".1"
            end
            if good.stolen then
                nameWithStatus = nameWithStatus .. ".2"
            end

            -- restore textbox value
            local box = selfCargoTextBoxes[rowNumber]
            if not box.isTypingActive then
                local boxAmount = TransferCrewGoods.clampNumberString(tct_selfAmountByIndex[nameWithStatus] or "1", amount)
                selfCargoTextBoxByIndex[nameWithStatus] = rowNumber
                box.text = boxAmount
                if boxAmount == "" then
                    box.text = "1"
                else
                    box.text = boxAmount
                end
            end

            -- favorites and trash icons/buttons
            if TCTConfig.EnableFavorites then
                local priority = tct_stationFavorites[2][nameWithStatus]
                if priority == 2 then
                    tct_selfFavoriteButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/star.png"
                    tct_selfTrashButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/empty.png"
                elseif priority == 0 then
                    tct_selfFavoriteButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/empty.png"
                    tct_selfTrashButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/trash.png"
                else
                    tct_selfFavoriteButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/empty.png"
                    tct_selfTrashButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/empty.png"
                end
            end

            -- overlay cargo name
            if UTF8.len(name) > 28 then
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
            overlayName.elem.caption = name
            overlayName.elem.color = tct_getGoodColor(good)
        end
    end

    if TCTConfig.EnableFavorites then
        -- hide
        for i = rowNumber+1, tct_selfCargoPrevCount do
            selfCargoIcons[i].visible = false
            selfCargoBars[i].visible = false
            selfCargoButtons[i].visible = false
            selfCargoTextBoxes[i].visible = false
            tct_selfCargoLabels[i].elem.visible = false
            tct_selfFavoriteButtons[i].visible = false
            tct_selfTrashButtons[i].visible = false
        end
        -- show
        for i = tct_selfCargoPrevCount+1, rowNumber do
            selfCargoIcons[i].visible = true
            selfCargoBars[i].visible = true
            selfCargoButtons[i].visible = true
            selfCargoTextBoxes[i].visible = true
            tct_selfCargoLabels[i].elem.visible = true
            tct_selfFavoriteButtons[i].visible = true
            tct_selfTrashButtons[i].visible = true
        end
    else
        for i = rowNumber+1, tct_selfCargoPrevCount do
            selfCargoIcons[i].visible = false
            selfCargoBars[i].visible = false
            selfCargoButtons[i].visible = false
            selfCargoTextBoxes[i].visible = false
            tct_selfCargoLabels[i].elem.visible = false
        end
        for i = tct_selfCargoPrevCount+1, rowNumber do
            selfCargoIcons[i].visible = true
            selfCargoBars[i].visible = true
            selfCargoButtons[i].visible = true
            selfCargoTextBoxes[i].visible = true
            tct_selfCargoLabels[i].elem.visible = true
        end
    end

    tct_selfCargoPrevCount = rowNumber
end


else -- onServer


local configOptions = {
  _version = { default = "1.1", comment = "Config version. Don't touch" },
  FightersMaxTransferDistance = { default = 20, min = 2, max = 20000, comment = "Specify max distance for transferring fighters." },
  CargoMaxTransferDistance = { default = 20, min = 2, max = 20000, comment = "Specify max distance for transferring cargo." },
  CrewMaxTransferDistance = { default = 20, min = 2, max = 20000, comment = "Specify max distance for transferring crew." },
  CheckIfDocked = { default = true, comment = "If enabled, in ship <-> station transfer game will just check if ship is docked instead of checking distance." },
  RequireAlliancePrivileges = { default = true, comment = "If enabled, taking/adding goods, fighters and crew to/from alliance ships/stations will require 'Manage Ships' and 'Manage Stations' alliance privileges." }
}
local isModified
TCTConfig, isModified = Azimuth.loadConfig("TransferCargoTweaks", configOptions)
if isModified then
    Azimuth.saveConfig("TransferCargoTweaks", TCTConfig, configOptions)
end

-- CALLABLE --

function TransferCrewGoods.transferCrew(crewmanIndex, otherIndex, selfToOther, amount) -- overridden
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
        player:sendChatMessage("", 1, "You don't own this craft."%_t)
        return
    end

    if TCTConfig.RequireAlliancePrivileges then
        local requiredPrivileges = {}
        if (sender.allianceOwned and sender.isShip) or (receiver.allianceOwned and receiver.isShip) then
            requiredPrivileges[#requiredPrivileges+1] = AlliancePrivilege.ManageShips
        end
        if (sender.allianceOwned and sender.isStation) or (receiver.allianceOwned and receiver.isStation) then
            requiredPrivileges[#requiredPrivileges+1] = AlliancePrivilege.ManageStations
        end
        if #requiredPrivileges > 0 and not getInteractingFaction(callingPlayer, unpack(requiredPrivileges)) then
            return
        end
    end

    -- check distance
    local transferDistance = math.max(TCTConfig.CrewMaxTransferDistance, sender.transporterRange or 0, receiver.transporterRange or 0)
    if TCTConfig.CheckIfDocked and (sender.isStation or receiver.isStation) then
        if ((sender.isStation and not sender:isDocked(receiver)) or (receiver.isStation and not receiver:isDocked(sender)))
          and sender:getNearestDistance(receiver) > transferDistance then
            player:sendChatMessage("", 1, "You must be docked to the station to transfer crew."%_t)
            return
        end
    elseif sender:getNearestDistance(receiver) > transferDistance then
        player:sendChatMessage("", 1, "You're too far away."%_t)
        return
    end

    local sorted = TransferCrewGoods.getSortedCrewmen(sender)

    local p = sorted[crewmanIndex]
    if not p then
        eprint("bad crewman")
        return
    end

    local crewman = p.crewman

    -- make sure sending ship has enough members of this type
    amount = math.min(amount, sender.crew:getNumMembers(crewman))

    -- transfer
    sender:removeCrew(amount, crewman)
    receiver:addCrew(amount, crewman)
end

function TransferCrewGoods.transferAllCrew(otherIndex, selfToOther) -- overridden
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
        player:sendChatMessage("", 1, "You don't own this craft."%_t)
        return
    end

    if TCTConfig.RequireAlliancePrivileges then
        local requiredPrivileges = {}
        if (sender.allianceOwned and sender.isShip) or (receiver.allianceOwned and receiver.isShip) then
            requiredPrivileges[#requiredPrivileges+1] = AlliancePrivilege.ManageShips
        end
        if (sender.allianceOwned and sender.isStation) or (receiver.allianceOwned and receiver.isStation) then
            requiredPrivileges[#requiredPrivileges+1] = AlliancePrivilege.ManageStations
        end
        if #requiredPrivileges > 0 and not getInteractingFaction(callingPlayer, unpack(requiredPrivileges)) then
            return
        end
    end

    -- check distance
    local transferDistance = math.max(TCTConfig.CrewMaxTransferDistance, sender.transporterRange or 0, receiver.transporterRange or 0)
    if TCTConfig.CheckIfDocked and (sender.isStation or receiver.isStation) then
        if ((sender.isStation and not sender:isDocked(receiver)) or (receiver.isStation and not receiver:isDocked(sender)))
          and sender:getNearestDistance(receiver) > transferDistance then
            player:sendChatMessage("", 1, "You must be docked to the station to transfer crew."%_t)
            return
        end
    elseif sender:getNearestDistance(receiver) > transferDistance then
        player:sendChatMessage("", 1, "You're too far away."%_t)
        return
    end

    local sorted = TransferCrewGoods.getSortedCrewmen(sender)
    for _, p in pairs(sorted) do
        -- transfer
        sender:removeCrew(p.num, p.crewman)
        receiver:addCrew(p.num, p.crewman)
    end
end

function TransferCrewGoods.transferCargo(cargoIndex, otherIndex, selfToOther, amount) -- overridden
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
        player:sendChatMessage("", 1, "You don't own this craft."%_t)
        return
    end

    if TCTConfig.RequireAlliancePrivileges then
        local requiredPrivileges = {}
        if (sender.allianceOwned and sender.isShip) or (receiver.allianceOwned and receiver.isShip) then
            requiredPrivileges[#requiredPrivileges+1] = AlliancePrivilege.ManageShips
        end
        if (sender.allianceOwned and sender.isStation) or (receiver.allianceOwned and receiver.isStation) then
            requiredPrivileges[#requiredPrivileges+1] = AlliancePrivilege.ManageStations
        end
        if #requiredPrivileges > 0 and not getInteractingFaction(callingPlayer, unpack(requiredPrivileges)) then
            return
        end
    end

    -- check distance
    local transferDistance = math.max(TCTConfig.CargoMaxTransferDistance, sender.transporterRange or 0, receiver.transporterRange or 0)
    if TCTConfig.CheckIfDocked and (sender.isStation or receiver.isStation) then
        if ((sender.isStation and not sender:isDocked(receiver)) or (receiver.isStation and not receiver:isDocked(sender)))
          and sender:getNearestDistance(receiver) > transferDistance then
            player:sendChatMessage("", 1, "You must be docked to the station to transfer cargo."%_t)
            return
        end
    elseif sender:getNearestDistance(receiver) > transferDistance then
        player:sendChatMessage("", 1, "You're too far away."%_t)
        return
    end

    -- get the cargo
    local good, availableAmount = sender:getCargo(cargoIndex)

    -- make sure sending ship has the cargo
    if not good or not availableAmount then return end
    amount = math.min(amount, availableAmount)

    -- make sure receiving ship has enough space
    if receiver.freeCargoSpace < good.size * amount then
        player:sendChatMessage("", 1, "Not enough space on the other craft."%_t)
        return
    end

    -- transfer
    sender:removeCargo(good, amount)
    receiver:addCargo(good, amount)

    invokeClientFunction(player, "updateData")
end

function TransferCrewGoods.transferAllCargo(otherIndex, selfToOther) -- overridden
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
        player:sendChatMessage("", 1, "You don't own this craft."%_t)
        return
    end

    if TCTConfig.RequireAlliancePrivileges then
        local requiredPrivileges = {}
        if (sender.allianceOwned and sender.isShip) or (receiver.allianceOwned and receiver.isShip) then
            requiredPrivileges[#requiredPrivileges+1] = AlliancePrivilege.ManageShips
        end
        if (sender.allianceOwned and sender.isStation) or (receiver.allianceOwned and receiver.isStation) then
            requiredPrivileges[#requiredPrivileges+1] = AlliancePrivilege.ManageStations
        end
        if #requiredPrivileges > 0 and not getInteractingFaction(callingPlayer, unpack(requiredPrivileges)) then
            return
        end
    end

    -- check distance
    local transferDistance = math.max(TCTConfig.CargoMaxTransferDistance, sender.transporterRange or 0, receiver.transporterRange or 0)
    if TCTConfig.CheckIfDocked and (sender.isStation or receiver.isStation) then
        if ((sender.isStation and not sender:isDocked(receiver)) or (receiver.isStation and not receiver:isDocked(sender)))
          and sender:getNearestDistance(receiver) > transferDistance then
            player:sendChatMessage("", 1, "You must be docked to the station to transfer cargo."%_t)
            return
        end
    elseif sender:getNearestDistance(receiver) > transferDistance then
        player:sendChatMessage("", 1, "You're too far away."%_t)
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
                player:sendChatMessage("", 1, "Not enough space on the other craft."%_t)
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

function TransferCrewGoods.transferFighter(sender, squad, index, receiver, receiverSquad) -- overridden
    if not onServer() then return end

    local player = Player(callingPlayer)
    if not player then return end

    local entityReceiver = Entity(receiver)

    local senderEntity = Entity(sender)
    if senderEntity.factionIndex ~= callingPlayer and senderEntity.factionIndex ~= player.allianceIndex then
        player:sendChatMessage("", 1, "You don't own this craft."%_t)
        return
    end

    if TCTConfig.RequireAlliancePrivileges then
        local requiredPrivileges = {}
        if (senderEntity.allianceOwned and senderEntity.isShip) or (entityReceiver.allianceOwned and entityReceiver.isShip) then
            requiredPrivileges[#requiredPrivileges+1] = AlliancePrivilege.ManageShips
        end
        if (senderEntity.allianceOwned and senderEntity.isStation) or (entityReceiver.allianceOwned and entityReceiver.isStation) then
            requiredPrivileges[#requiredPrivileges+1] = AlliancePrivilege.ManageStations
        end
        if #requiredPrivileges > 0 and not getInteractingFaction(callingPlayer, unpack(requiredPrivileges)) then
            return
        end
    end

    -- check distance
    local transferDistance = math.max(TCTConfig.FightersMaxTransferDistance, senderEntity.transporterRange or 0, entityReceiver.transporterRange or 0)
    if TCTConfig.CheckIfDocked and (senderEntity.isStation or entityReceiver.isStation) then
        if ((senderEntity.isStation and not senderEntity:isDocked(entityReceiver)) or (entityReceiver.isStation and not entityReceiver:isDocked(senderEntity)))
          and senderEntity:getNearestDistance(entityReceiver) > transferDistance then
            player:sendChatMessage("", 1, "You must be docked to the station to transfer fighters."%_t)
            return
        end
    elseif senderEntity:getNearestDistance(entityReceiver) > transferDistance then
        player:sendChatMessage("", 1, "You're too far away."%_t)
        return
    end

    local senderHangar = Hangar(sender)
    if not senderHangar then
        player:sendChatMessage("", 1, "Missing hangar."%_t)
        return
    end
    local receiverHangar = Hangar(receiver)
    if not receiverHangar then
        player:sendChatMessage("", 1, "Missing hangar."%_t)
        return
    end

    local fighter = senderHangar:getFighter(squad, index)
    if not fighter then
        return
    end

    if sender ~= receiver and receiverHangar.freeSpace < fighter.volume then
        player:sendChatMessage("", 1, "Not enough space in hangar."%_t)
        return
    end

    if receiverHangar:getSquadFreeSlots(receiverSquad) == 0 then
        receiverSquad = nil

        -- find other squad
        local receiverSquads = {receiverHangar:getSquads()}

        for _, newSquad in pairs(receiverSquads) do
            if receiverHangar:fighterTypeMatchesSquad(fighter, newSquad) then
                if receiverHangar:getSquadFreeSlots(newSquad) > 0 then
                    receiverSquad = newSquad
                    break
                end
            end
        end

        if receiverSquad == nil then
            if #receiverSquads < receiverHangar.maxSquads then
                receiverSquad = receiverHangar:addSquad("New Squad"%_t)
            else
                player:sendChatMessage("", 1, "Not enough space in squad."%_t)
            end
        end

    end

    if receiverHangar:getSquadFreeSlots(receiverSquad) > 0 then
        if receiverHangar:fighterTypeMatchesSquad(fighter, receiverSquad) then
            senderHangar:removeFighter(index, squad)
            receiverHangar:addFighter(receiverSquad, fighter)
        else
            player:sendChatMessage("", 1, "The fighter type doesn't match the type of the squad."%_t)
        end
    end

    invokeClientFunction(player, "updateData")
end

function TransferCrewGoods.transferAllFighters(sender, receiver) -- overridden
    if not onServer() then return end

    local player = Player(callingPlayer)
    if not player then return end

    local entityReceiver = Entity(receiver)

    local senderEntity = Entity(sender)
    if senderEntity.factionIndex ~= callingPlayer and senderEntity.factionIndex ~= player.allianceIndex then
        player:sendChatMessage("", 1, "You don't own this craft."%_t)
        return
    end

    if TCTConfig.RequireAlliancePrivileges then
        local requiredPrivileges = {}
        if (senderEntity.allianceOwned and senderEntity.isShip) or (entityReceiver.allianceOwned and entityReceiver.isShip) then
            requiredPrivileges[#requiredPrivileges+1] = AlliancePrivilege.ManageShips
        end
        if (senderEntity.allianceOwned and senderEntity.isStation) or (entityReceiver.allianceOwned and entityReceiver.isStation) then
            requiredPrivileges[#requiredPrivileges+1] = AlliancePrivilege.ManageStations
        end
        if #requiredPrivileges > 0 and not getInteractingFaction(callingPlayer, unpack(requiredPrivileges)) then
            return
        end
    end

    -- check distance
    local transferDistance = math.max(TCTConfig.FightersMaxTransferDistance, senderEntity.transporterRange or 0, entityReceiver.transporterRange or 0)
    if TCTConfig.CheckIfDocked and (senderEntity.isStation or entityReceiver.isStation) then
        if ((senderEntity.isStation and not senderEntity:isDocked(entityReceiver)) or (entityReceiver.isStation and not entityReceiver:isDocked(senderEntity)))
          and senderEntity:getNearestDistance(entityReceiver) > transferDistance then
            player:sendChatMessage("", 1, "You must be docked to the station to transfer fighters."%_t)
            return
        end
    elseif senderEntity:getNearestDistance(entityReceiver) > transferDistance then
        player:sendChatMessage("", 1, "You're too far away."%_t)
        return
    end

    local senderHangar = Hangar(sender)
    if not senderHangar then
        player:sendChatMessage("", 1, "Missing hangar."%_t)
        return
    end
    local receiverHangar = Hangar(receiver)
    if not receiverHangar then
        player:sendChatMessage("", 1, "Missing hangar."%_t)
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

                local fighter = senderHangar:getFighter(squad, 0)
                if not fighter then
                    eprint("fighter is nil")
                    return
                end

                -- check squad type
                if not receiverHangar:fighterTypeMatchesSquad(fighter, targetSquad) then
                    player:sendChatMessage("", 1, "The fighter type doesn't match the type of the squad."%_t)
                    break
                end

                -- check squad space
                if receiverHangar:getSquadFreeSlots(targetSquad) == 0 then
                    player:sendChatMessage("", 1, "Not enough space in squad."%_t)
                    break
                end
                -- check hangar space
                if receiverHangar.freeSpace < fighter.volume then
                    player:sendChatMessage("", 1, "Not enough space in hangar."%_t)
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


end