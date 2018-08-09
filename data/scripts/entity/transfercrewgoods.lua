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

--MOD: TransferCargoTweaks
package.path = package.path .. ";mods/TransferCargoTweaks/?.lua"
local utf8 = require "scripts/lib/utf8"
local TransferCargoTweaksConfig = require "config/config"

local playerCargoSearchBox
local selfCargoSearchBox

local cargoLowercaseCache = {} -- cache lowercased names
local playerPrevQuery = {}
local selfPrevQuery = {}
-- goods indexes in saved cargo lists by name
local playerGoodIndexesByName
local selfGoodIndexesByName
-- goods names sorted
local playerGoodNames
local selfGoodNames

-- currently displayed good localized names by index of row
local playerGoodSearchNames = {}
local selfGoodSearchNames = {}

local playerCargoOverlayNames = {}
local selfCargoOverlayNames = {}

-- cargo list saved between the updates
local playerCargoList = {}
local selfCargoList = {}

-- how many goods were displayed in the previous update/search
local playerCargoPrevCount = 0
local selfCargoPrevCount = 0

-- we want to keep textbox values for goods even if their rows are currently hidden
local playerAmountByIndex = {}
local selfAmountByIndex = {}

local playerToggleSearchBtn
local selfToggleSearchBtn
--MOD

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

    local tabbedWindow = window:createTabbedWindow(Rect(vec2(10, 10), size - 10))
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

    local leftFrame = crewTab:createScrollFrame(vSplit.left)
    local rightFrame = crewTab:createScrollFrame(vSplit.right)

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
        playerCrewIcons[#playerCrewIcons+1] = icon --table.insert(playerCrewIcons, icon)
        playerCrewButtons[#playerCrewButtons+1] = button --table.insert(playerCrewButtons, button)
        playerCrewBars[#playerCrewBars+1] = bar --table.insert(playerCrewBars, bar)
        playerCrewTextBoxes[#playerCrewTextBoxes+1] = box --table.insert(playerCrewTextBoxes, box)
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
        selfCrewIcons[#selfCrewIcons+1] = icon  --table.insert(selfCrewIcons, icon)
        selfCrewButtons[#selfCrewButtons+1] = button --table.insert(selfCrewButtons, button)
        selfCrewBars[#selfCrewBars+1] = bar --table.insert(selfCrewBars, bar)
        selfCrewTextBoxes[#selfCrewTextBoxes+1] = box --table.insert(selfCrewTextBoxes, box)
        --MOD
        crewmenByButton[button.index] = i
        crewmenByTextBox[box.index] = i
        textboxIndexByButton[button.index] = box.index
    end

    local cargoTab = tabbedWindow:createTab("Cargo"%_t, "data/textures/icons/trade.png", "Exchange cargo"%_t)

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

    playerTransferAllCargoButton = leftFrame:createButton(Rect(), "Transfer All >>", "onPlayerTransferAllCargoPressed")
    leftLister:placeElementCenter(playerTransferAllCargoButton)

    selfTransferAllCargoButton = rightFrame:createButton(Rect(), "<< Transfer All", "onSelfTransferAllCargoPressed")
    rightLister:placeElementCenter(selfTransferAllCargoButton)

    playerTotalCargoBar = leftFrame:createNumbersBar(Rect())
    leftLister:placeElementCenter(playerTotalCargoBar)

    selfTotalCargoBar = rightFrame:createNumbersBar(Rect())
    rightLister:placeElementCenter(selfTotalCargoBar)
    
    --MOD: TransferCargoTweaks
    playerToggleSearchBtn = leftFrame:createButton(Rect(10, 10, 35, playerTransferAllCargoButton.height+10), "", "onPlayerToggleCargoSearchPressed")
    playerToggleSearchBtn.icon = "mods/TransferCargoTweaks/textures/icons/search.png"
    
    selfToggleSearchBtn = rightFrame:createButton(Rect(rightFrame.width-55, 10, rightFrame.width-30, selfTransferAllCargoButton.height+10), "", "onSelfToggleCargoSearchPressed")
    selfToggleSearchBtn.icon = "mods/TransferCargoTweaks/textures/icons/search.png"
    
    playerCargoSearchBox = leftFrame:createTextBox(Rect(42, playerTransferAllCargoButton.height+22, playerTotalCargoBar.width+38, playerTransferAllCargoButton.height+playerTotalCargoBar.height+18), "playerCargoSearch")
    playerCargoSearchBox.backgroundText = "Search"%_t
    playerCargoSearchBox.visible = false
    
    selfCargoSearchBox = rightFrame:createTextBox(Rect(12, selfTransferAllCargoButton.height+22, rightFrame.width-62, selfTransferAllCargoButton.height+selfTotalCargoBar.height+18), "selfCargoSearch")
    selfCargoSearchBox.backgroundText = "Search"%_t
    selfCargoSearchBox.visible = false

    for i = 1, TransferCargoTweaksConfig.CargoRowsAmount do --for i = 1, 100 do
    --MOD

        local iconRect = Rect(leftLister.inner.topLeft - vec2(30, 0), leftLister.inner.topLeft + vec2(0, 30))
        local rect = leftLister:placeCenter(vec2(leftLister.inner.width, 25))
        local vsplit = UIVerticalSplitter(rect, 10, 0, 0.85)
        local vsplit2 = UIVerticalSplitter(vsplit.left, 10, 0, 0.75)

        local icon = leftFrame:createPicture(iconRect, "")
        icon.isIcon = 1
        local button = leftFrame:createButton(vsplit.right, ">>", "onPlayerTransferCargoPressed")
        local bar = leftFrame:createStatisticsBar(vsplit2.left, ColorInt(0x808080))
        local box = leftFrame:createTextBox(vsplit2.right, "onPlayerTransferCargoTextEntered")
        button.textSize = 16
        box.allowedCharacters = "0123456789"

        --MOD: TransferCargoTweaks
        playerCargoIcons[#playerCargoIcons+1] = icon --table.insert(playerCargoIcons, icon)
        playerCargoButtons[#playerCargoButtons+1] = button --table.insert(playerCargoButtons, button)
        playerCargoBars[#playerCargoBars+1] = bar --table.insert(playerCargoBars, bar)
        playerCargoTextBoxes[#playerCargoTextBoxes+1] = box --table.insert(playerCargoTextBoxes, box)
        --table.insert(playerCargoName, "")
        
        local overlayName = leftFrame:createLabel(Rect(vsplit2.left.topLeft + vec2(0, 6), vsplit2.left.bottomRight), "", 10)
        overlayName.centered = true
        overlayName.wordBreak = false
        playerCargoOverlayNames[#playerCargoOverlayNames+1] = { elem = overlayName }
        
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
        local vsplit = UIVerticalSplitter(rect, 10, 0, 0.15)
        local vsplit2 = UIVerticalSplitter(vsplit.right, 10, 0, 0.25)

        local icon = rightFrame:createPicture(iconRect, "")
        icon.isIcon = 1
        local button = rightFrame:createButton(vsplit.left, "<<", "onSelfTransferCargoPressed")
        local bar = rightFrame:createStatisticsBar(vsplit2.right, ColorInt(0x808080))
        local box = rightFrame:createTextBox(vsplit2.left, "onSelfTransferCargoTextEntered")
        button.textSize = 16
        box.allowedCharacters = "0123456789"

        --MOD: TransferCargoTweaks
        local overlayName = rightFrame:createLabel(Rect(vsplit2.right.topLeft + vec2(0, 6), vsplit2.right.bottomRight), "", 10)
        overlayName.centered = true
        overlayName.wordBreak = false
        selfCargoOverlayNames[#selfCargoOverlayNames+1] = { elem = overlayName }
        
        selfCargoIcons[#selfCargoIcons+1] = icon --table.insert(selfCargoIcons, icon)
        selfCargoButtons[#selfCargoButtons+1] = button --table.insert(selfCargoButtons, button)
        selfCargoBars[#selfCargoBars+1] = bar --table.insert(selfCargoBars, bar)
        selfCargoTextBoxes[#selfCargoTextBoxes+1] = box --table.insert(selfCargoTextBoxes, box)
        --table.insert(selfCargoName, "")
        
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
        --MOD: TransferCargoTweaks
        playerFighterLabels[#playerFighterLabels+1] = label --table.insert(playerFighterLabels, label)
        --MOD

        local rect = leftLister:placeCenter(vec2(leftLister.inner.width, 35))
        rect.upper = vec2(rect.lower.x + 376, rect.upper.y)
        local selection = fightersTab:createSelection(rect, 12)
        selection.dropIntoEnabled = true
        selection.dragFromEnabled = true
        selection.entriesSelectable = false
        selection.onReceivedFunction = "onFighterReceived"
        selection.onClickedFunction = "onFighterClicked"
        selection.padding = 4

        --MOD: TransferCargoTweaks
        playerFighterSelections[#playerFighterSelections+1] = selection --table.insert(playerFighterSelections, selection)
        --MOD
        isPlayerShipBySelection[selection.index] = true
        squadIndexBySelection[selection.index] = i - 1

        -- right side (self)
        local rect = rightLister:placeCenter(vec2(rightLister.inner.width, 18))
        local label = fightersTab:createLabel(rect, "", 16)
        --MOD: TransferCargoTweaks
        selfFighterLabels[#selfFighterLabels+1] = label --table.insert(selfFighterLabels, label)
        --MOD

        local rect = rightLister:placeCenter(vec2(rightLister.inner.width, 35))
        rect.upper = vec2(rect.lower.x + 376, rect.upper.y)
        local selection = fightersTab:createSelection(rect, 12)
        selection.dropIntoEnabled = true
        selection.dragFromEnabled = true
        selection.entriesSelectable = false
        selection.onReceivedFunction = "onFighterReceived"
        selection.onClickedFunction = "onFighterClicked"
        selection.padding = 4

        --MOD: TransferCargoTweaks
        selfFighterSelections[#selfFighterSelections+1] = selection --table.insert(selfFighterSelections, selection)
        --MOD
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

    local sortedMembers = {}
    for crewman, num in pairs(crew:getMembers()) do
        table.insert(sortedMembers, {crewman = crewman, num = num})
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
    for i = 1, #playerCrewIcons do playerCrewIcons[i].visible = false end --for _, icon in pairs(playerCrewIcons) do icon.visible = false end
    for i = 1, #selfCrewIcons do selfCrewIcons[i].visible = false end --for _, icon in pairs(selfCrewIcons) do icon.visible = false end
    for i = 1, #playerCrewBars do playerCrewBars[i].visible = false end --for _, bar in pairs(playerCrewBars) do bar.visible = false end
    for i = 1, #selfCrewBars do selfCrewBars[i].visible = false end --for _, bar in pairs(selfCrewBars) do bar.visible = false end
    for i = 1, #playerCrewButtons do playerCrewButtons[i].visible = false end --for _, button in pairs(playerCrewButtons) do button.visible = false end
    for i = 1, #selfCrewButtons do selfCrewButtons[i].visible = false end --for _, button in pairs(selfCrewButtons) do button.visible = false end
    for i = 1, #playerCrewTextBoxes do playerCrewTextBoxes[i].visible = false end --for _, box in pairs(playerCrewTextBoxes) do box.visible = false end
    for i = 1, #selfCrewTextBoxes do selfCrewTextBoxes[i].visible = false end --for _, box in pairs(selfCrewTextBoxes) do box.visible = false end
    --MOD

    -- restore textbox values
    local amountByIndex = {}
    for crewIndex, index in pairs(playerCrewTextBoxByIndex) do
        --MOD: TransferCargoTweaks
        amountByIndex[crewIndex] = playerCrewTextBoxes[index].text --table.insert(amountByIndex, crewIndex, playerCrewTextBoxes[index].text)
        --MOD
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

        i = i + 1
    end

    -- restore textbox values
    local amountByIndex = {}
    for crewIndex, index in pairs(selfCrewTextBoxByIndex) do
        --MOD: TransferCargoTweaks
        amountByIndex[crewIndex] = selfCrewTextBoxes[index].text --table.insert(amountByIndex, crewIndex, selfCrewTextBoxes[index].text)
        --MOD
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
        --MOD: TransferCargoTweaks
        selfCrewTextBoxByIndex[index] = i --table.insert(selfCrewTextBoxByIndex, index, i)
        --MOD

        local box = selfCrewTextBoxes[i]
        box.visible = true
        box.text = amount

        i = i + 1
    end




    -- update cargo info
    playerTotalCargoBar:clear()
    selfTotalCargoBar:clear()

    playerTotalCargoBar:setRange(0, playerShip.maxCargoSpace)
    selfTotalCargoBar:setRange(0, ship.maxCargoSpace)
    
    --MOD: TransferCargoTweaks
    -- removed lines from 498 to 509
    --MOD
    
    --MOD: TransferCargoTweaks
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
    table.sort(playerGoodNames, utf8.comparesensitive)

    for i = 1, (ship.numCargos or 0) do
        local good, amount = ship:getCargo(i - 1)
        selfCargoList[i] = { good = good, amount = amount }
        selfGoodNames[i] = good.displayName
        selfGoodIndexesByName[good.displayName] = i
        
        selfTotalCargoBar:addEntry(amount * good.size, amount .. " " .. (amount > 1 and good.displayPlural or good.displayName), ColorInt(0xff808080))
    end
    table.sort(selfGoodNames, utf8.comparesensitive)
    
    TransferCrewGoods.playerCargoSearch()
    TransferCrewGoods.selfCargoSearch()
    
    -- removed lines from 511 to 586
    --MOD

    -- update fighter info
    --MOD: TransferCargoTweaks
    for i = 1, #playerFighterLabels do playerFighterLabels[i].visible = false end --for _, label in pairs(playerFighterLabels) do label:hide() end
    for i = 1, #selfFighterLabels do selfFighterLabels[i].visible = false end --for _, label in pairs(selfFighterLabels) do label:hide() end
    for i = 1, #playerFighterSelections do playerFighterSelections[i].visible = false end --for _, selection in pairs(playerFighterSelections) do selection:hide() end
    for i = 1, #selfFighterSelections do selfFighterSelections[i].visible = false end --for _, selection in pairs(selfFighterSelections) do selection:hide() end
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
    --local good, maxAmount = sender:getCargo(cargoIndex - 1)
    local maxAmount = playerCargoList[playerGoodIndexesByName[playerGoodSearchNames[cargoIndex]]].amount or 0
    --MOD

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
    if sender:getNearestDistance(receiver) > 20 then
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
    if sender:getNearestDistance(receiver) > 20 then
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
    if sender:getNearestDistance(receiver) > 2 then
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
    if sender:getNearestDistance(receiver) > 2 then
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

    if Entity(sender).factionIndex ~= callingPlayer and Entity(sender).factionIndex ~= player.allianceIndex then
        player:sendChatMessage("Server"%_t, 1, "You don't own this craft."%_t)
        return
    end

    -- check distance
    if Entity(sender):getNearestDistance(Entity(receiver)) > 2 then
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

    if Entity(sender).factionIndex ~= callingPlayer and Entity(sender).factionIndex ~= player.allianceIndex then
        player:sendChatMessage("Server"%_t, 1, "You don't own this craft."%_t)
        return
    end

    -- check distance
    if Entity(sender):getNearestDistance(Entity(receiver)) > 2 then
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

    if not activeSelection then return end

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
end

--MOD: TransferCargoTweaks
function TransferCrewGoods.onPlayerToggleCargoSearchPressed(button)
    playerCargoSearchBox.visible = not playerCargoSearchBox.visible
end

function TransferCrewGoods.onSelfToggleCargoSearchPressed(button)
    selfCargoSearchBox.visible = not selfCargoSearchBox.visible
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
        if rowNumber == TransferCargoTweaksConfig.CargoRowsAmount then break end

        -- save/retrieve lowercase good names
        local nameLowercase
        local displayName = playerGoodNames[i]
        if not cargoLowercaseCache[nameLowercase] then
            cargoLowercaseCache[displayName] = utf8.lower(displayName)
        end
        nameLowercase = cargoLowercaseCache[displayName]
        
        if query == "" or utf8.find(nameLowercase, query, 1, true) then
            rowNumber = rowNumber + 1
        
            local bar = playerCargoBars[rowNumber]
            local overlayName = playerCargoOverlayNames[rowNumber]
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
            if good.stolen then nameWithStatus = nameWithStatus .. ".stolen" end
            if good.suspicious then nameWithStatus = nameWithStatus .. ".suspicious" end
            local boxAmount = TransferCrewGoods.clampNumberString(playerAmountByIndex[nameWithStatus] or "1", amount)
            playerCargoTextBoxByIndex[nameWithStatus] = rowNumber
            playerCargoTextBoxes[rowNumber].text = boxAmount
            
            local displayName = amount > 1 and good.displayPlural or good.displayName
            -- adjust overlay name vertically (because we don't have built-in way to do this)
            if utf8.len(displayName) > 29 then
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
    
    -- hide only rows that were shown in prev search but not in current
    for i = rowNumber+1, playerCargoPrevCount do
        playerCargoIcons[i].visible = false
        playerCargoBars[i].visible = false
        playerCargoButtons[i].visible = false
        playerCargoTextBoxes[i].visible = false
        playerCargoOverlayNames[i].elem.visible = false
    end
    
    -- show only rows that were not shown in prev search but will be in current
    for i = playerCargoPrevCount+1, rowNumber do
        playerCargoIcons[i].visible = true
        playerCargoBars[i].visible = true
        playerCargoButtons[i].visible = true
        playerCargoTextBoxes[i].visible = true
        playerCargoOverlayNames[i].elem.visible = true
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
        if rowNumber == TransferCargoTweaksConfig.CargoRowsAmount then break end
        
        local nameLowercase
        local displayName = selfGoodNames[i]
        if not cargoLowercaseCache[nameLowercase] then
            cargoLowercaseCache[displayName] = utf8.lower(displayName)
        end
        nameLowercase = cargoLowercaseCache[displayName]
        
        if query == "" or utf8.find(utf8.lower(nameLowercase), query, 1, true) then
            rowNumber = rowNumber + 1
        
            local bar = selfCargoBars[rowNumber]
            local overlayName = selfCargoOverlayNames[rowNumber]
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
            if good.stolen then nameWithStatus = nameWithStatus .. ".stolen" end
            if good.suspicious then nameWithStatus = nameWithStatus .. ".suspicious" end
            local boxAmount = TransferCrewGoods.clampNumberString(selfAmountByIndex[nameWithStatus] or "1", amount)
            selfCargoTextBoxByIndex[nameWithStatus] = rowNumber
            selfCargoTextBoxes[rowNumber].text = boxAmount
            
            local displayName = amount > 1 and good.displayPlural or good.displayName
            if utf8.len(displayName) > 29 then
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
    
    -- hide
    for i = rowNumber+1, selfCargoPrevCount do
        selfCargoIcons[i].visible = false
        selfCargoBars[i].visible = false
        selfCargoButtons[i].visible = false
        selfCargoTextBoxes[i].visible = false
        selfCargoOverlayNames[i].elem.visible = false
    end
    
    -- show
    for i = selfCargoPrevCount+1, rowNumber do
        selfCargoIcons[i].visible = true
        selfCargoBars[i].visible = true
        selfCargoButtons[i].visible = true
        selfCargoTextBoxes[i].visible = true
        selfCargoOverlayNames[i].elem.visible = true
    end
    
    selfCargoPrevCount = rowNumber
end
--MOD