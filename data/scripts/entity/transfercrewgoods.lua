local Azimuth = include("azimuthlib-basic")
local AzimuthUTF8 = include("azimuthlib-utf8")

local TransferCargoTweaksConfig, transferCargoTweaks_configOptions, transferCargoTweaks_isModified
if onClient() then -- different configs for client/server
    transferCargoTweaks_configOptions = {
      _version = { default = "1.6", comment = "Config version. Don't touch" },
      CargoRowsAmount = { default = 100, min = 10, max = 300, comment = "Increase if you have a lot of goods in your cargo storage." },
      EnableFavorites = { default = true, comment = "Enable favorites/trash system." },
      ToggleFavoritesByDefault = { default = true, comment = "If favorites system is enabled, it will be turned on by default when you open transfer window." },
      EnableCrewWorkforcePreview = { default = true, comment = "Show current an minimal crew workforce in crew transfer tab." }
    }
else
    transferCargoTweaks_configOptions = {
      _version = { default = "1.1", comment = "Config version. Don't touch" },
      FightersMaxTransferDistance = { default = 20, min = 2, max = 20000, comment = "Specify max distance for transferring fighters." },
      CargoMaxTransferDistance = { default = 20, min = 2, max = 20000, comment = "Specify max distance for transferring cargo." },
      CrewMaxTransferDistance = { default = 20, min = 2, max = 20000, comment = "Specify max distance for transferring crew." },
      CheckIfDocked = { default = true, comment = "If enabled, in ship <-> station transfer game will just check if ship is docked instead of checking distance." },
      RequireAlliancePrivileges = { default = true, comment = "If enabled, taking/adding goods, fighters and crew to/from alliance ships/stations will require 'Manage Ships' and 'Manage Stations' alliance privileges." }
    }
end
TransferCargoTweaksConfig, transferCargoTweaks_isModified = Azimuth.loadConfig("TransferCargoTweaks", transferCargoTweaks_configOptions)
if transferCargoTweaks_isModified then
    Azimuth.saveConfig("TransferCargoTweaks", TransferCargoTweaksConfig, transferCargoTweaks_configOptions)
end


local transferCargoTweaks_gameVersion = GameVersion()
local transferCargoTweaks_post0_26_1 = false
if transferCargoTweaks_gameVersion.minor > 26 or (transferCargoTweaks_gameVersion.minor == 26 and transferCargoTweaks_gameVersion.patch >= 1) then
    transferCargoTweaks_post0_26_1 = true
end

local favoritesFile = {} -- file with all stations of the server
local stationFavorites = { {}, {} } -- current station only

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

local cargoLowerCache = {} -- because non-native AzimuthUTF8.lower is 32 times slower than string.lower

-- to AzimuthUTF8.lower query string only when it was changed
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

local playerFavoritesEnabled = TransferCargoTweaksConfig.EnableFavorites and TransferCargoTweaksConfig.ToggleFavoritesByDefault
local selfFavoritesEnabled = TransferCargoTweaksConfig.EnableFavorites and TransferCargoTweaksConfig.ToggleFavoritesByDefault

local playerLastHoveredRow
local selfLastHoveredRow

local tabbedWindow
local cargoTabIndex


local function playerSortGoodsFavorites(a, b)
    -- and here is where performance will probably die
    local goodNameA = playerCargoList[playerGoodIndexesByName[a]].good.name
    local goodNameB = playerCargoList[playerGoodIndexesByName[b]].good.name
    
    local afav = stationFavorites[1][goodNameA] or 1
    local bfav = stationFavorites[1][goodNameB] or 1
    return afav > bfav or (afav == bfav and AzimuthUTF8.compare(a, b, true))
end

local function selfSortGoodsFavorites(a, b)
    -- and here is where performance will probably die
    local goodNameA = selfCargoList[selfGoodIndexesByName[a]].good.name
    local goodNameB = selfCargoList[selfGoodIndexesByName[b]].good.name

    local afav = stationFavorites[2][goodNameA] or 1
    local bfav = stationFavorites[2][goodNameB] or 1
    return afav > bfav or (afav == bfav and AzimuthUTF8.compare(a, b, true))
end

local function playerSortGoods()
    if not playerFavoritesEnabled then
        table.sort(playerGoodNames, AzimuthUTF8.comparesensitive)
    else
        table.sort(playerGoodNames, playerSortGoodsFavorites)
    end
    TransferCrewGoods.playerCargoSearch()
end

local function selfSortGoods()
    if not selfFavoritesEnabled then
        table.sort(selfGoodNames, AzimuthUTF8.comparesensitive)
    else
        table.sort(selfGoodNames, selfSortGoodsFavorites)
    end
    TransferCrewGoods.selfCargoSearch()
end

-- OVERRIDDEN FUNCTIONS

function TransferCrewGoods.initUI()

    local res = getResolution()
    local size = vec2(850, 635)

    local menu = ScriptUI()
    local window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5));
    menu:registerWindow(window, "Transfer Crew/Cargo/Fighters"%_t);

    window.caption = "Transfer Crew, Cargo and Fighters"%_t
    window.showCloseButton = 1
    window.moveable = 1

    tabbedWindow = window:createTabbedWindow(Rect(vec2(10, 10), size - 10))
    local crewTab = tabbedWindow:createTab("Crew"%_t, "data/textures/icons/crew.png", "Exchange crew"%_t)

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
    if not TransferCargoTweaksConfig.EnableCrewWorkforcePreview then
        leftFrame = crewTab:createScrollFrame(vSplit.left)
        rightFrame = crewTab:createScrollFrame(vSplit.right)
    else
        leftFrame = crewTab:createScrollFrame(Rect(vSplit.left.lower + vec2(0, 90), vSplit.left.upper))
        rightFrame = crewTab:createScrollFrame(Rect(vSplit.right.lower + vec2(0, 90), vSplit.right.upper))

        -- create ui to show how many workforce both ships have and need
        local leftForceHSplitter = UIHorizontalMultiSplitter(Rect(vSplit.left.lower + vec2(10, 0), vSplit.left.lower + vec2(vSplit.left.width - 20, 80)), 10, 0, 2)
        local rightForceHSplitter = UIHorizontalMultiSplitter(Rect(vSplit.right.lower + vec2(10, 0), vSplit.right.lower + vec2(vSplit.right.width - 10, 80)), 10, 0, 2)
        local i = 1
        local profIcon, leftForceVSplitter, rightForceVSplitter, leftPartition, rightPartition, leftIcon, rightIcon
        for j = 0, 2 do
            leftForceVSplitter = UIVerticalMultiSplitter(leftForceHSplitter:partition(j), 10, 0, 3)
            rightForceVSplitter = UIVerticalMultiSplitter(rightForceHSplitter:partition(j), 10, 0, 3)
            for k = 0, 3 do
                if i < 12 then
                    profIcon = CrewProfession(i).icon
                    leftPartition = leftForceVSplitter:partition(k)
                    rightPartition = rightForceVSplitter:partition(k)
                    leftIcon = crewTab:createPicture(Rect(leftPartition.lower, leftPartition.lower + vec2(20, 20)), profIcon)
                    leftIcon.isIcon = 1
                    rightIcon = crewTab:createPicture(Rect(rightPartition.lower, rightPartition.lower + vec2(20, 20)), profIcon)
                    rightIcon.isIcon = 1

                    playerCrewWorkforceLabels[i] = crewTab:createLabel(Rect(leftPartition.lower + vec2(30, 2), leftPartition.upper), "0/0", 11)
                    selfCrewWorkforceLabels[i] = crewTab:createLabel(Rect(rightPartition.lower + vec2(30, 2), rightPartition.upper), "0/0", 11)
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
        playerCrewLabels[i] = overlayName

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
        selfCrewLabels[i] = overlayName

        selfCrewIcons[i] = icon
        selfCrewButtons[i] = button
        selfCrewBars[i] = bar
        selfCrewTextBoxes[i] = box
        crewmenByButton[button.index] = i
        crewmenByTextBox[box.index] = i
        textboxIndexByButton[button.index] = box.index
    end

    local cargoTab = tabbedWindow:createTab("Cargo"%_t, "data/textures/icons/trade.png", "Exchange cargo"%_t)
    cargoTabIndex = cargoTab.index

    -- have to use "left" twice here since the coordinates are relative and the UI would be displaced to the right otherwise
    local leftLister = UIVerticalLister(vSplit.left, 10, 10)
    local rightLister = UIVerticalLister(vSplit.left, 10, 10)

    leftLister.marginRight = 30
    rightLister.marginRight = 30

    -- margin for the icon
    leftLister.marginLeft = 35
    rightLister.marginRight = 60

    local leftFrame = cargoTab:createScrollFrame(vSplit.left)
    local rightFrame = cargoTab:createScrollFrame(vSplit.right)

    if TransferCargoTweaksConfig.EnableFavorites then
        playerTransferAllCargoButton = leftFrame:createButton(Rect(0, 10, leftFrame.width - 110, 45), "/* Goods */Transfer All >>"%_t, "onPlayerTransferAllCargoPressed")
        selfTransferAllCargoButton = rightFrame:createButton(Rect(0, 10, rightFrame.width - 110, 45), "/* Goods */<< Transfer All"%_t, "onSelfTransferAllCargoPressed")
    else
        playerTransferAllCargoButton = leftFrame:createButton(Rect(0, 10, leftFrame.width - 75, 45), "/* Goods */Transfer All >>"%_t, "onPlayerTransferAllCargoPressed")
        selfTransferAllCargoButton = rightFrame:createButton(Rect(0, 10, rightFrame.width - 75, 45), "/* Goods */<< Transfer All"%_t, "onSelfTransferAllCargoPressed")
    end
    leftLister:placeElementRight(playerTransferAllCargoButton)
    rightLister:placeElementLeft(selfTransferAllCargoButton)

    playerTotalCargoBar = leftFrame:createNumbersBar(Rect(0, 0, leftFrame.width - 40, 25))
    leftLister:placeElementRight(playerTotalCargoBar)

    selfTotalCargoBar = rightFrame:createNumbersBar(Rect(0, 0, rightFrame.width - 40, 25))
    rightLister:placeElementLeft(selfTotalCargoBar)

    playerToggleSearchBtn = leftFrame:createButton(Rect(10, 10, 40, 45), "", "onPlayerToggleCargoSearchPressed")
    playerToggleSearchBtn.icon = "data/textures/icons/transfercargotweaks/search.png"
    selfToggleSearchBtn = rightFrame:createButton(Rect(rightFrame.width-60, 10, rightFrame.width-30, 45), "", "onSelfToggleCargoSearchPressed")
    selfToggleSearchBtn.icon = "data/textures/icons/transfercargotweaks/search.png"

    playerCargoSearchBox = leftFrame:createTextBox(Rect(12, playerTransferAllCargoButton.height+22, leftFrame.width-33, playerTransferAllCargoButton.height+selfTotalCargoBar.height+18), "playerCargoSearch")
    playerCargoSearchBox.backgroundText = "Search"%_t
    playerCargoSearchBox.visible = false
    selfCargoSearchBox = rightFrame:createTextBox(Rect(12, selfTransferAllCargoButton.height+22, rightFrame.width-33, selfTransferAllCargoButton.height+selfTotalCargoBar.height+18), "selfCargoSearch")
    selfCargoSearchBox.backgroundText = "Search"%_t
    selfCargoSearchBox.visible = false

    if TransferCargoTweaksConfig.EnableFavorites then
        playerToggleFavoritesBtn = leftFrame:createButton(Rect(45, 10, 75, 45), "", "onPlayerToggleFavoritesPressed")
        selfToggleFavoritesBtn = rightFrame:createButton(Rect(rightFrame.width-95, 10, rightFrame.width-65, 45), "", "onSelfToggleFavoritesPressed")
        if TransferCargoTweaksConfig.ToggleFavoritesByDefault then
            playerToggleFavoritesBtn.icon = "data/textures/icons/transfercargotweaks/favorites-enabled.png"
            selfToggleFavoritesBtn.icon = "data/textures/icons/transfercargotweaks/favorites-enabled.png"
        else
            playerToggleFavoritesBtn.icon = "data/textures/icons/transfercargotweaks/favorites.png"
            selfToggleFavoritesBtn.icon = "data/textures/icons/transfercargotweaks/favorites.png"
        end
    end

    for i = 1, TransferCargoTweaksConfig.CargoRowsAmount do

        local iconRect = Rect(leftLister.inner.topLeft - vec2(30, 0), leftLister.inner.topLeft + vec2(-5, 25))
        local rect = leftLister:placeCenter(vec2(leftLister.inner.width, 25))
        local vsplit, vsplit2
        if TransferCargoTweaksConfig.EnableFavorites then
            vsplit = UIVerticalSplitter(rect, 10, 0, 0.87)
            vsplit2 = UIVerticalSplitter(vsplit.left, 10, 0, 0.77)
        else
            vsplit = UIVerticalSplitter(rect, 10, 0, 0.85)
            vsplit2 = UIVerticalSplitter(vsplit.left, 10, 0, 0.75)
        end

        local icon = leftFrame:createPicture(iconRect, "")
        icon.isIcon = 1
        local button = leftFrame:createButton(vsplit.right, ">>", "onPlayerTransferCargoPressed")
        local bar
        if TransferCargoTweaksConfig.EnableFavorites then
            bar = leftFrame:createStatisticsBar(Rect(vsplit2.left.lower + vec2(15, 0), vsplit2.left.upper), ColorInt(0x808080))
        else
            bar = leftFrame:createStatisticsBar(vsplit2.left, ColorInt(0x808080))
        end
        local box = leftFrame:createTextBox(vsplit2.right, "onPlayerTransferCargoTextEntered")
        button.textSize = 16
        box.allowedCharacters = "0123456789"
        box.clearOnClick = true

        playerCargoIcons[i] = icon
        playerCargoButtons[i] = button
        playerCargoBars[i] = bar
        playerCargoTextBoxes[i] = box

        local overlayName

        if TransferCargoTweaksConfig.EnableFavorites then
            local favoriteBtn = leftFrame:createPicture(Rect(vsplit2.left.topLeft + vec2(0, 2), vsplit2.left.topLeft + vec2(10, 12)), '')
            favoriteBtn.flipped = true
            favoriteBtn.picture = "data/textures/icons/transfercargotweaks/empty.png"
            playerFavoriteButtons[i] = favoriteBtn
            favoriteBtn.visible = false

            local trashBtn = leftFrame:createPicture(Rect(vsplit2.left.topLeft + vec2(0, 18), vsplit2.left.topLeft + vec2(10, 28)), '')
            trashBtn.flipped = true
            trashBtn.picture = "data/textures/icons/transfercargotweaks/empty.png"
            playerTrashButtons[i] = trashBtn
            trashBtn.visible = false

            overlayName = leftFrame:createLabel(Rect(vsplit2.left.lower + vec2(15, 6), vsplit2.left.upper), "", 10)
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
        cargosByButton[button.index] = i
        cargosByTextBox[box.index] = i
        textboxIndexByButton[button.index] = box.index


        local iconRect = Rect(rightLister.inner.topRight - vec2(-5, 0), rightLister.inner.topRight + vec2(30, 25))
        local rect = rightLister:placeCenter(vec2(rightLister.inner.width, 25))
        local vsplit, vsplit2
        if TransferCargoTweaksConfig.EnableFavorites then
            vsplit = UIVerticalSplitter(rect, 10, 0, 0.13)
            vsplit2 = UIVerticalSplitter(vsplit.right, 10, 0, 0.23)
        else
            vsplit = UIVerticalSplitter(rect, 10, 0, 0.15)
            vsplit2 = UIVerticalSplitter(vsplit.right, 10, 0, 0.25)
        end

        local icon = rightFrame:createPicture(iconRect, "")
        icon.isIcon = 1
        local button = rightFrame:createButton(vsplit.left, "<<", "onSelfTransferCargoPressed")
        local bar
        if TransferCargoTweaksConfig.EnableFavorites then
            bar = rightFrame:createStatisticsBar(Rect(vsplit2.right.lower, vsplit2.right.upper - vec2(15, 0)), ColorInt(0x808080))
        else
            bar = rightFrame:createStatisticsBar(vsplit2.right, ColorInt(0x808080))
        end
        local box = rightFrame:createTextBox(vsplit2.left, "onSelfTransferCargoTextEntered")
        button.textSize = 16
        box.allowedCharacters = "0123456789"
        box.clearOnClick = true

        selfCargoIcons[i] = icon
        selfCargoButtons[i] = button
        selfCargoBars[i] = bar
        selfCargoTextBoxes[i] = box

        local overlayName

        if TransferCargoTweaksConfig.EnableFavorites then
            local favoriteBtn = rightFrame:createPicture(Rect(vsplit2.right.topRight + vec2(-10, 2), vsplit2.right.topRight + vec2(0, 12)), '')
            favoriteBtn.flipped = true
            favoriteBtn.picture = "data/textures/icons/transfercargotweaks/empty.png"
            selfFavoriteButtons[i] = favoriteBtn
            favoriteBtn.visible = false

            local trashBtn = rightFrame:createPicture(Rect(vsplit2.right.topRight + vec2(-10, 18), vsplit2.right.topRight + vec2(0, 28)), '')
            trashBtn.flipped = true
            trashBtn.picture = "data/textures/icons/transfercargotweaks/empty.png"
            selfTrashButtons[i] = trashBtn
            trashBtn.visible = false

            overlayName = rightFrame:createLabel(Rect(vsplit2.right.lower + vec2(0, 6), vsplit2.right.upper - vec2(15, 0)), "", 10)
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

function TransferCrewGoods.updateData()
    local playerShip = Player().craft
    local ship = Entity()

    -- update crew info
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
        playerCrewLabels[i].visible = false
        selfCrewLabels[i].visible = false
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

        playerCrewLabels[i].caption = caption
        playerCrewLabels[i].visible = true

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

        selfCrewLabels[i].caption = caption
        selfCrewLabels[i].visible = true

        i = i + 1
    end

    -- update workforce labels
    if TransferCargoTweaksConfig.EnableCrewWorkforcePreview then
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
            playerCrewWorkforceLabels[i].caption = playerWorkforce[i] .. "/" .. playerMinWorkforce[i]
            playerCrewWorkforceLabels[i].color = playerWorkforce[i] < playerMinWorkforce[i] and ColorInt(0xffff2626) or ColorInt(0xffe0e0e0)
            -- self
            if not selfMinWorkforce[i] then selfMinWorkforce[i] = 0 end
            if not selfWorkforce[i] then selfWorkforce[i] = 0 end
            selfCrewWorkforceLabels[i].caption = selfWorkforce[i] .. "/" .. selfMinWorkforce[i]
            selfCrewWorkforceLabels[i].color = selfWorkforce[i] < selfMinWorkforce[i] and ColorInt(0xffff2626) or ColorInt(0xffe0e0e0)
        end
    end

    -- update cargo info
    playerTotalCargoBar:clear()
    selfTotalCargoBar:clear()

    playerTotalCargoBar:setRange(0, playerShip.maxCargoSpace)
    selfTotalCargoBar:setRange(0, ship.maxCargoSpace)

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
        local displayName = good:displayName(1)
        playerGoodNames[i] = displayName
        playerGoodIndexesByName[displayName] = i

        local name = "${amount} ${good}"%_t % {amount = createMonetaryString(amount), good = good:displayName(amount)}
        playerTotalCargoBar:addEntry(amount * good.size, name, ColorInt(0xff808080))
    end

    for i = 1, (ship.numCargos or 0) do
        local good, amount = ship:getCargo(i - 1)
        selfCargoList[i] = { good = good, amount = amount }
        local displayName = good:displayName(1)
        selfGoodNames[i] = displayName
        selfGoodIndexesByName[displayName] = i

        local name = "${amount} ${good}"%_t % {amount = createMonetaryString(amount), good = good:displayName(amount)}
        selfTotalCargoBar:addEntry(amount * good.size, name, ColorInt(0xff808080))
    end

    playerSortGoods()
    selfSortGoods()

    -- update fighter info
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
    local keyboard = Keyboard()
    if keyboard:keyPressed(KeyboardKey.LControl) or keyboard:keyPressed(KeyboardKey.RControl) then
        amount = 5
    elseif keyboard:keyPressed(KeyboardKey.LShift) or keyboard:keyPressed(KeyboardKey.RShift) then
        amount = 10
    elseif keyboard:keyPressed(KeyboardKey.LAlt) or keyboard:keyPressed(KeyboardKey.RAlt) then
        amount = 50
    end
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
    local keyboard = Keyboard()
    if keyboard:keyPressed(KeyboardKey.LControl) or keyboard:keyPressed(KeyboardKey.RControl) then
        amount = 5
    elseif keyboard:keyPressed(KeyboardKey.LShift) or keyboard:keyPressed(KeyboardKey.RShift) then
        amount = 10
    elseif keyboard:keyPressed(KeyboardKey.LAlt) or keyboard:keyPressed(KeyboardKey.RAlt) then
        amount = 50
    end
    if amount == 0 then return end

    invokeServerFunction("transferCrew", crewmanIndex, Player().craftIndex, true, amount)
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
    local maxAmount = playerCargoList[playerGoodIndexesByName[playerGoodSearchNames[cargoIndex]]].amount or 0

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
    local maxAmount = selfCargoList[selfGoodIndexesByName[selfGoodSearchNames[cargoIndex]]].amount or 0

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
        player:sendChatMessage("", 1, "You don't own this craft."%_t)
        return
    end

    if TransferCargoTweaksConfig.RequireAlliancePrivileges then
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
    local transferDistance = TransferCargoTweaksConfig.CrewMaxTransferDistance
    if transferCargoTweaks_post0_26_1 then
        transferDistance = math.max(transferDistance, sender.transporterRange or 0, receiver.transporterRange or 0)
    end
    if TransferCargoTweaksConfig.CheckIfDocked and (sender.isStation or receiver.isStation) then
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
callable(TransferCrewGoods, "transferCrew")

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
        player:sendChatMessage("", 1, "You don't own this craft."%_t)
        return
    end

    if TransferCargoTweaksConfig.RequireAlliancePrivileges then
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
    local transferDistance = TransferCargoTweaksConfig.CrewMaxTransferDistance
    if transferCargoTweaks_post0_26_1 then
        transferDistance = math.max(transferDistance, sender.transporterRange or 0, receiver.transporterRange or 0)
    end
    if TransferCargoTweaksConfig.CheckIfDocked and (sender.isStation or receiver.isStation) then
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
callable(TransferCrewGoods, "transferAllCrew")

function TransferCrewGoods.onPlayerTransferCargoPressed(button)
    -- transfer cargo from player ship to self

    -- check which cargo
    local cargo = cargosByButton[button.index]
    if cargo == nil then return end
    cargo = playerGoodIndexesByName[playerGoodSearchNames[cargo]]

    -- get amount
    local textboxIndex = textboxIndexByButton[button.index]
    if not textboxIndex then return end

    local box = TextBox(textboxIndex)
    if not box then return end

    local amount = tonumber(box.text) or 0
    local keyboard = Keyboard()
    if keyboard:keyPressed(KeyboardKey.LControl) or keyboard:keyPressed(KeyboardKey.RControl) then
        amount = 5
    elseif keyboard:keyPressed(KeyboardKey.LShift) or keyboard:keyPressed(KeyboardKey.RShift) then
        amount = 10
    elseif keyboard:keyPressed(KeyboardKey.LAlt) or keyboard:keyPressed(KeyboardKey.RAlt) then
        amount = 50
    end
    if amount == 0 then return end

    invokeServerFunction("transferCargo", cargo - 1, Player().craftIndex, false, amount)
end

function TransferCrewGoods.onSelfTransferCargoPressed(button)
    -- transfer cargo from self to player ship

    -- check which cargo
    local cargo = cargosByButton[button.index]
    if cargo == nil then return end
    cargo = selfGoodIndexesByName[selfGoodSearchNames[cargo]]

    -- get amount
    local textboxIndex = textboxIndexByButton[button.index]
    if not textboxIndex then return end

    local box = TextBox(textboxIndex)
    if not box then return end

    local amount = tonumber(box.text) or 0
    local keyboard = Keyboard()
    if keyboard:keyPressed(KeyboardKey.LControl) or keyboard:keyPressed(KeyboardKey.RControl) then
        amount = 5
    elseif keyboard:keyPressed(KeyboardKey.LShift) or keyboard:keyPressed(KeyboardKey.RShift) then
        amount = 10
    elseif keyboard:keyPressed(KeyboardKey.LAlt) or keyboard:keyPressed(KeyboardKey.RAlt) then
        amount = 50
    end
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
        player:sendChatMessage("", 1, "You don't own this craft."%_t)
        return
    end

    if TransferCargoTweaksConfig.RequireAlliancePrivileges then
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
    local transferDistance = TransferCargoTweaksConfig.CargoMaxTransferDistance
    if transferCargoTweaks_post0_26_1 then
        transferDistance = math.max(transferDistance, sender.transporterRange or 0, receiver.transporterRange or 0)
    end
    if TransferCargoTweaksConfig.CheckIfDocked and (sender.isStation or receiver.isStation) then
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
callable(TransferCrewGoods, "transferCargo")

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
        player:sendChatMessage("", 1, "You don't own this craft."%_t)
        return
    end

    if TransferCargoTweaksConfig.RequireAlliancePrivileges then
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
    local transferDistance = TransferCargoTweaksConfig.CargoMaxTransferDistance
    if transferCargoTweaks_post0_26_1 then
        transferDistance = math.max(transferDistance, sender.transporterRange or 0, receiver.transporterRange or 0)
    end
    if TransferCargoTweaksConfig.CheckIfDocked and (sender.isStation or receiver.isStation) then
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
callable(TransferCrewGoods, "transferAllCargo")

function TransferCrewGoods.transferFighter(sender, squad, index, receiver, receiverSquad)
    if not onServer() then return end

    local player = Player(callingPlayer)
    if not player then return end

    local entityReceiver = Entity(receiver)

    local senderEntity = Entity(sender)
    if senderEntity.factionIndex ~= callingPlayer and senderEntity.factionIndex ~= player.allianceIndex then
        player:sendChatMessage("", 1, "You don't own this craft."%_t)
        return
    end

    if TransferCargoTweaksConfig.RequireAlliancePrivileges then
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
    local transferDistance = TransferCargoTweaksConfig.FightersMaxTransferDistance
    if transferCargoTweaks_post0_26_1 then
        transferDistance = math.max(transferDistance, senderEntity.transporterRange or 0, entityReceiver.transporterRange or 0)
    end
    if TransferCargoTweaksConfig.CheckIfDocked and (senderEntity.isStation or entityReceiver.isStation) then
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
callable(TransferCrewGoods, "transferFighter")

function TransferCrewGoods.transferAllFighters(sender, receiver)
    if not onServer() then return end

    local player = Player(callingPlayer)
    if not player then return end

    local entityReceiver = Entity(receiver)

    local senderEntity = Entity(sender)
    if senderEntity.factionIndex ~= callingPlayer and senderEntity.factionIndex ~= player.allianceIndex then
        player:sendChatMessage("", 1, "You don't own this craft."%_t)
        return
    end

    if TransferCargoTweaksConfig.RequireAlliancePrivileges then
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
    local transferDistance = TransferCargoTweaksConfig.FightersMaxTransferDistance
    if transferCargoTweaks_post0_26_1 then
        transferDistance = math.max(transferDistance, senderEntity.transporterRange or 0, entityReceiver.transporterRange or 0)
    end
    if TransferCargoTweaksConfig.CheckIfDocked and (senderEntity.isStation or entityReceiver.isStation) then
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
callable(TransferCrewGoods, "transferAllFighters")

function TransferCrewGoods.onShowWindow()
    local player = Player()
    local ship = Entity()
    local other = player.craft

    ship:registerCallback("onCrewChanged", "onCrewChanged")
    other:registerCallback("onCrewChanged", "onCrewChanged")
    
    if TransferCargoTweaksConfig.EnableFavorites then -- load favorites
        favoritesFile = Azimuth.loadConfig("TransferCargoTweaks", { _version = TransferCargoTweaksConfig._version }, true, true)
        local favorites = favoritesFile[Entity().index.string] or { {}, {} }
        if not favorites[1] then favorites[1] = {} end
        if not favorites[2] then favorites[2] = {} end
        stationFavorites = favorites
    end

    TransferCrewGoods.updateData()
end

function TransferCrewGoods.onCloseWindow()
    local player = Player()
    local ship = Entity()
    local other = player.craft

    ship:unregisterCallback("onCrewChanged", "onCrewChanged")
    other:unregisterCallback("onCrewChanged", "onCrewChanged")

    if TransferCargoTweaksConfig.EnableFavorites then -- save favorites
        local favorites = { {}, {} }
        local playerFavCount = 0
        local selfFavCount = 0
        for k, v in pairs(stationFavorites[1]) do
            playerFavCount = playerFavCount + 1
            favorites[1][k] = v
        end
        for k, v in pairs(stationFavorites[2]) do
            selfFavCount = selfFavCount + 1
            favorites[2][k] = v
        end
        if playerFavCount == 0 and selfFavCount == 0 then
            favorites = nil
        else
            if playerFavCount == 0 then favorites[1] = nil end
            if selfFavCount == 0 then favorites[2] = nil end
        end
        favoritesFile[Entity().index.string] = favorites
        Azimuth.saveConfig("TransferCargoTweaks", favoritesFile, nil, true, true)
        favoritesFile = nil
        stationFavorites = { {}, {} }
    end
end

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

    if not TransferCargoTweaksConfig.EnableFavorites then return end
    local currentTab = tabbedWindow:getActiveTab()
    if not currentTab or currentTab.index ~= cargoTabIndex then return end

    local cargo, goodName, priority, btn, playerHoveredRow, selfHoveredRow
    -- change icon on hover, change item priority on icon click
    for i = 1, playerCargoPrevCount do
        if playerCargoIcons[i].mouseOver
          or playerCargoButtons[i].mouseOver
          or playerCargoBars[i].mouseOver
          or playerCargoTextBoxes[i].mouseOver
          or playerFavoriteButtons[i].mouseOver
          or playerTrashButtons[i].mouseOver then
            cargo = playerCargoList[playerGoodIndexesByName[playerGoodSearchNames[i]]]
            goodName = cargo.good.name
            priority = stationFavorites[1][goodName]
            playerHoveredRow = i

            if Mouse():mouseDown(3) then
                if playerFavoriteButtons[i].mouseOver then
                    if priority ~= 2 then
                        stationFavorites[1][goodName] = 2
                        playerFavoriteButtons[i].picture = "data/textures/icons/transfercargotweaks/star.png"
                        playerTrashButtons[i].picture = "data/textures/icons/transfercargotweaks/empty.png"
                    else
                        stationFavorites[1][goodName] = nil
                        playerFavoriteButtons[i].picture = "data/textures/icons/transfercargotweaks/empty.png"
                    end
                    if playerFavoritesEnabled then playerSortGoods() end
                elseif playerTrashButtons[i].mouseOver then
                    if priority ~= 0 then
                        stationFavorites[1][goodName] = 0
                        playerFavoriteButtons[i].picture = "data/textures/icons/transfercargotweaks/empty.png"
                        playerTrashButtons[i].picture = "data/textures/icons/transfercargotweaks/trash.png"
                    else
                        stationFavorites[1][goodName] = nil
                        playerTrashButtons[i].picture = "data/textures/icons/transfercargotweaks/empty.png"
                    end
                    if playerFavoritesEnabled then playerSortGoods() end
                end
            else -- just hover
                if priority ~= 2 then
                    playerFavoriteButtons[i].picture = "data/textures/icons/transfercargotweaks/star-hover.png"
                end
                if priority ~= 0 then
                    playerTrashButtons[i].picture = "data/textures/icons/transfercargotweaks/trash-hover.png"
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
            cargo = selfCargoList[selfGoodIndexesByName[selfGoodSearchNames[i]]]
            goodName = cargo.good.name
            priority = stationFavorites[2][goodName]
            selfHoveredRow = i

            if Mouse():mouseDown(3) then
                if selfFavoriteButtons[i].mouseOver then
                    if priority ~= 2 then
                        stationFavorites[2][goodName] = 2
                        selfFavoriteButtons[i].picture = "data/textures/icons/transfercargotweaks/star.png"
                        selfTrashButtons[i].picture = "data/textures/icons/transfercargotweaks/empty.png"
                    else
                        stationFavorites[2][goodName] = nil
                        selfFavoriteButtons[i].picture = "data/textures/icons/transfercargotweaks/empty.png"
                    end
                    if selfFavoritesEnabled then selfSortGoods() end
                elseif selfTrashButtons[i].mouseOver then
                    if priority ~= 0 then
                        stationFavorites[2][goodName] = 0
                        selfFavoriteButtons[i].picture = "data/textures/icons/transfercargotweaks/empty.png"
                        selfTrashButtons[i].picture = "data/textures/icons/transfercargotweaks/trash.png"
                    else
                        stationFavorites[2][goodName] = nil
                        selfTrashButtons[i].picture = "data/textures/icons/transfercargotweaks/empty.png"
                    end
                    if selfFavoritesEnabled then selfSortGoods() end
                end
            else -- just hover
                if priority ~= 2 then
                    selfFavoriteButtons[i].picture = "data/textures/icons/transfercargotweaks/star-hover.png"
                end
                if priority ~= 0 then
                    selfTrashButtons[i].picture = "data/textures/icons/transfercargotweaks/trash-hover.png"
                end
            end
            break
        end
    end
    -- return icons to 'hidden' image, when mouse left them
    if playerLastHoveredRow and playerLastHoveredRow ~= playerHoveredRow and playerLastHoveredRow <= #playerGoodSearchNames then
        cargo = playerCargoList[playerGoodIndexesByName[playerGoodSearchNames[playerLastHoveredRow]]]
        priority = stationFavorites[1][cargo.good.name]
        if priority ~= 2 then
            playerFavoriteButtons[playerLastHoveredRow].picture = "data/textures/icons/transfercargotweaks/empty.png"
        end
        if priority ~= 0 then
            playerTrashButtons[playerLastHoveredRow].picture = "data/textures/icons/transfercargotweaks/empty.png"
        end
    end
    playerLastHoveredRow = playerHoveredRow

    if selfLastHoveredRow and selfLastHoveredRow ~= selfHoveredRow and selfLastHoveredRow <= #selfGoodSearchNames then
        cargo = selfCargoList[selfGoodIndexesByName[selfGoodSearchNames[selfLastHoveredRow]]]
        priority = stationFavorites[2][cargo.good.name]
        if priority ~= 2 then
            selfFavoriteButtons[selfLastHoveredRow].picture = "data/textures/icons/transfercargotweaks/empty.png"
        end
        if priority ~= 0 then
            selfTrashButtons[selfLastHoveredRow].picture = "data/textures/icons/transfercargotweaks/empty.png"
        end
    end
    selfLastHoveredRow = selfHoveredRow
end

-- MOD FUNCTIONS

function TransferCrewGoods.onPlayerToggleCargoSearchPressed(button)
    playerCargoSearchBox.visible = not playerCargoSearchBox.visible
end

function TransferCrewGoods.onPlayerToggleFavoritesPressed(button)
    playerFavoritesEnabled = not playerFavoritesEnabled
    if playerFavoritesEnabled then
        button.icon = "data/textures/icons/transfercargotweaks/favorites-enabled.png"
    else
        button.icon = "data/textures/icons/transfercargotweaks/favorites.png"
    end
    playerSortGoods()
end

function TransferCrewGoods.onSelfToggleCargoSearchPressed(button)
    selfCargoSearchBox.visible = not selfCargoSearchBox.visible
end

function TransferCrewGoods.onSelfToggleFavoritesPressed(button)
    selfFavoritesEnabled = not selfFavoritesEnabled
    if selfFavoritesEnabled then
        button.icon = "data/textures/icons/transfercargotweaks/favorites-enabled.png"
    else
        button.icon = "data/textures/icons/transfercargotweaks/favorites.png"
    end
    selfSortGoods()
end

function TransferCrewGoods.playerCargoSearch()
    local playerShip = Player().craft

    -- save/retrieve lowercase query because we don't want to recalculate it every update (not search)
    local query = playerCargoSearchBox.text
    if playerPrevQuery[1] ~= query then
        if playerPrevQuery[1] == '' then
            playerToggleSearchBtn.icon = "data/textures/icons/transfercargotweaks/search-text.png"
        elseif query == '' then
            playerToggleSearchBtn.icon = "data/textures/icons/transfercargotweaks/search.png"
        end
        playerPrevQuery[1] = query
        playerPrevQuery[2] = AzimuthUTF8.lower(query)
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
        if rowNumber == TransferCargoTweaksConfig.CargoRowsAmount then break end
        
        local cargo = playerCargoList[playerGoodIndexesByName[playerGoodNames[i]]]
        local good = cargo.good
        local amount = cargo.amount
        
        -- save/retrieve lowercase good names
        local nameLowercase
        local actualDisplayName = good:displayName(amount)
        if not cargoLowerCache[actualDisplayName] then
            cargoLowerCache[actualDisplayName] = AzimuthUTF8.lower(actualDisplayName)
        end
        nameLowercase = cargoLowerCache[actualDisplayName]

        if query == "" or AzimuthUTF8.find(nameLowercase, query, 1, true, true) then
            rowNumber = rowNumber + 1

            local bar = playerCargoBars[rowNumber]
            local overlayName = playerCargoLabels[rowNumber]
            local displayName = playerGoodNames[i]

            playerCargoIcons[rowNumber].picture = good.icon
            bar:setRange(0, playerMaxSpace)
            bar.value = amount * good.size
            local name = "${amount} ${good}"%_t % {amount = createMonetaryString(amount), good = actualDisplayName}
            bar.name = name

            playerGoodSearchNames[rowNumber] = displayName

            -- restore textbox value
            local box = playerCargoTextBoxes[rowNumber]
            if not box.isTypingActive then
                local nameWithStatus = good.name
                if good.suspicious then
                    nameWithStatus = nameWithStatus .. ".1"
                end
                if good.stolen then
                    nameWithStatus = nameWithStatus .. ".2"
                end
                local boxAmount = TransferCrewGoods.clampNumberString(playerAmountByIndex[nameWithStatus] or "1", amount)
                playerCargoTextBoxByIndex[nameWithStatus] = rowNumber
                box.text = boxAmount
                if boxAmount == "" then
                    box.text = "1"
                else
                    box.text = boxAmount
                end
            end

            -- favorites and trash icons/buttons
            if TransferCargoTweaksConfig.EnableFavorites then
                local priority = stationFavorites[1][good.name]
                if priority == 2 then
                    playerFavoriteButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/star.png"
                    playerTrashButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/empty.png"
                elseif priority == 0 then
                    playerFavoriteButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/empty.png"
                    playerTrashButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/trash.png"
                else
                    playerFavoriteButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/empty.png"
                    playerTrashButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/empty.png"
                end
            end

            -- cargo overlay name
            -- adjust overlay name vertically (because we don't have built-in way to do this)
            if AzimuthUTF8.len(name) > 28 then
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
        end
    end

    if TransferCargoTweaksConfig.EnableFavorites then
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
            selfToggleSearchBtn.icon = "data/textures/icons/transfercargotweaks/search-text.png"
        elseif query == '' then
            selfToggleSearchBtn.icon = "data/textures/icons/transfercargotweaks/search.png"
        end
        selfPrevQuery[1] = query
        selfPrevQuery[2] = AzimuthUTF8.lower(query)
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
        if rowNumber == TransferCargoTweaksConfig.CargoRowsAmount then break end

        local cargo = selfCargoList[selfGoodIndexesByName[selfGoodNames[i]]]
        local good = cargo.good
        local amount = cargo.amount
        
        local nameLowercase
        local actualDisplayName = good:displayName(amount)
        if not cargoLowerCache[actualDisplayName] then
            cargoLowerCache[actualDisplayName] = AzimuthUTF8.lower(actualDisplayName)
        end
        nameLowercase = cargoLowerCache[actualDisplayName]

        if query == "" or AzimuthUTF8.find(nameLowercase, query, 1, true, true) then
            rowNumber = rowNumber + 1

            local bar = selfCargoBars[rowNumber]
            local overlayName = selfCargoLabels[rowNumber]
            local displayName = selfGoodNames[i]

            selfCargoIcons[rowNumber].picture = good.icon
            bar:setRange(0, selfMaxSpace)
            bar.value = amount * good.size
            local name = "${amount} ${good}"%_t % {amount = createMonetaryString(amount), good = actualDisplayName}
            bar.name = name

            selfGoodSearchNames[rowNumber] = displayName

            -- restore textbox value
            local box = selfCargoTextBoxes[rowNumber]
            if not box.isTypingActive then
                local nameWithStatus = good.name
                if good.suspicious then
                    nameWithStatus = nameWithStatus .. ".1"
                end
                if good.stolen then
                    nameWithStatus = nameWithStatus .. ".2"
                end
                local boxAmount = TransferCrewGoods.clampNumberString(selfAmountByIndex[nameWithStatus] or "1", amount)
                selfCargoTextBoxByIndex[nameWithStatus] = rowNumber
                box.text = boxAmount
                if boxAmount == "" then
                    box.text = "1"
                else
                    box.text = boxAmount
                end
            end

            -- favorites and trash icons/buttons
            if TransferCargoTweaksConfig.EnableFavorites then
                local priority = stationFavorites[2][good.name]
                if priority == 2 then
                    selfFavoriteButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/star.png"
                    selfTrashButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/empty.png"
                elseif priority == 0 then
                    selfFavoriteButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/empty.png"
                    selfTrashButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/trash.png"
                else
                    selfFavoriteButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/empty.png"
                    selfTrashButtons[rowNumber].picture = "data/textures/icons/transfercargotweaks/empty.png"
                end
            end

            -- overlay cargo name
            if AzimuthUTF8.len(name) > 28 then
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
        end
    end

    if TransferCargoTweaksConfig.EnableFavorites then
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