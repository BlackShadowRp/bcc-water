local MaxCanteenDrinks = Config.maxCanteenDrinks
local SickPlayers = {}

local function getConfiguredCanteenItems()
    local items = {}
    local seen = {}

    local function addItem(itemName)
        if type(itemName) ~= 'string' or itemName == '' or seen[itemName] then
            return
        end

        seen[itemName] = true
        items[#items + 1] = itemName
    end

    if type(Config.canteens) == 'table' then
        for _, itemName in ipairs(Config.canteens) do
            addItem(itemName)
        end
    end

    addItem(Config.canteen)
    return items
end

local function addBottleType(types, seen, bottleType)
    if type(bottleType) ~= 'table' then
        return
    end

    local emptyBottle = bottleType.empty or bottleType.emptyBottle
    local cleanBottle = bottleType.clean or bottleType.cleanBottle
    local dirtyBottle = bottleType.dirty or bottleType.dirtyBottle
    if type(emptyBottle) ~= 'string' or emptyBottle == ''
        or type(cleanBottle) ~= 'string' or cleanBottle == ''
        or type(dirtyBottle) ~= 'string' or dirtyBottle == '' then
        return
    end

    local key = emptyBottle .. '|' .. cleanBottle .. '|' .. dirtyBottle
    if seen[key] then
        return
    end

    seen[key] = true
    types[#types + 1] = {
        empty = emptyBottle,
        clean = cleanBottle,
        dirty = dirtyBottle
    }
end

local function getConfiguredBottleTypes()
    local bottleTypes = {}
    local seen = {}

    if type(Config.bottleTypes) == 'table' then
        for _, bottleType in ipairs(Config.bottleTypes) do
            addBottleType(bottleTypes, seen, bottleType)
        end
    end

    addBottleType(bottleTypes, seen, {
        empty = Config.emptyBottle,
        clean = Config.cleanBottle,
        dirty = Config.dirtyBottle
    })

    return bottleTypes
end

local function getInventoryCount(src, itemName)
    local item = exports.vorp_inventory:getItem(src, itemName)
    return math.max(0, math.floor(tonumber(item and item.count) or 0))
end

local function buildBottleFillPlan(src, itemAmount)
    local remaining = math.max(1, math.floor(tonumber(itemAmount) or 1))
    local plan = {}

    for _, bottleType in ipairs(getConfiguredBottleTypes()) do
        local available = getInventoryCount(src, bottleType.empty)
        local amount = math.min(available, remaining)
        if amount > 0 then
            plan[#plan + 1] = {
                bottleType = bottleType,
                amount = amount
            }
            remaining = remaining - amount
        end

        if remaining <= 0 then
            return plan
        end
    end

    return nil
end

local function isConfiguredCanteenItem(itemName)
    for _, configuredItemName in ipairs(getConfiguredCanteenItems()) do
        if configuredItemName == itemName then
            return true
        end
    end

    return false
end

local function getCanteenUsage(itemName)
    local perItemUsage = Config.durability and Config.durability.canteens
    if type(perItemUsage) == 'table' and tonumber(perItemUsage[itemName]) then
        return tonumber(perItemUsage[itemName])
    end

    return tonumber(Config.durability and Config.durability.canteen) or 1
end

local function isCanteenFull(canteen)
    local meta = canteen and canteen.metadata
    return type(meta) == 'table' and tonumber(meta.drinksLeft) and tonumber(meta.drinksLeft) >= MaxCanteenDrinks
end

local function getInventoryItemById(src, itemId)
    local ok, item = pcall(function()
        return exports.vorp_inventory:getItemById(src, itemId)
    end)

    if ok then
        return item
    end

    DBG:Warning(string.format('getItemById failed for source=%d id=%s: %s', src, tostring(itemId), tostring(item)))
    return nil
end

local function findCanteen(src, preferredItemName, preferredItemId, requireFillable)
    preferredItemId = tonumber(preferredItemId)
    if preferredItemId and preferredItemId > 0 then
        local canteen = getInventoryItemById(src, preferredItemId)
        if canteen and isConfiguredCanteenItem(canteen.name) and (not requireFillable or not isCanteenFull(canteen)) then
            return canteen, canteen.name
        end
    end

    if preferredItemName and isConfiguredCanteenItem(preferredItemName) then
        local canteen = exports.vorp_inventory:getItem(src, preferredItemName)
        if canteen and (not requireFillable or not isCanteenFull(canteen)) then
            return canteen, preferredItemName
        end
    end

    local foundFullCanteen = false
    for _, itemName in ipairs(getConfiguredCanteenItems()) do
        local canteen = exports.vorp_inventory:getItem(src, itemName)
        if canteen then
            if not requireFillable or not isCanteenFull(canteen) then
                return canteen, itemName
            end
            foundFullCanteen = true
        end
    end

    if foundFullCanteen then
        return nil, nil, 'full'
    end

    return nil, nil, 'missing'
end

exports('IsSickByCharId', function(charid)
    charid = tonumber(charid) or 0
    if charid <= 0 then
        return false
    end
    return SickPlayers[charid] == true
end)

---@param src number
---@param canteenId number
---@param drinksLeft number
---@param durability number
local function updateCanteenMetadata(src, canteenId, drinksLeft, durability)
    local description = _U('canteenDesc') .. '<br>'
        .. _U('drinksLeft') .. ' : ' .. tostring(drinksLeft) .. '/' .. tostring(MaxCanteenDrinks) .. '<br>'
        .. _U('Durability') .. ' : ' .. tostring(durability) .. '%'
    exports.vorp_inventory:setItemMetadata(src, canteenId, {
        description = description,
        drinksLeft = drinksLeft,
        durability = durability
    })
    DBG:Info(string.format('Updated canteen metadata for source %d: Drinks Left = %d, Durability = %d%%', src, drinksLeft,
        durability))
end

-- Manage Filling a New or Empty Canteen
Core.Callback.Register('bcc-water:GetCanteenLevel', function(source, cb)
    local src = source
    local user = Core.getUser(src)
    -- Check if the user exists
    if not user then
        DBG:Error(string.format('User not found for source: %d', src))
        return cb(false)
    end
    local canteen, _, reason = findCanteen(src, nil, nil, true)
    -- Check if the canteen exists in the inventory
    if not canteen then
        Core.NotifyRightTip(src, reason == 'full' and _U('fullCanteen') or _U('needCanteen'), 4000)
        DBG:Warning(string.format('Fillable canteen not found for source: %d reason=%s', src, tostring(reason)))
        return cb(false)
    end
    local meta = canteen['metadata'] or {}
    local isNewCanteen = type(meta) ~= 'table' or next(meta) == nil
    -- Fill the canteen if it's new or not full
    if isNewCanteen then
        updateCanteenMetadata(src, canteen.id, MaxCanteenDrinks, 100)
        DBG:Info(string.format('Filled new canteen for source: %d', src))
    else
        local drinksLeft = meta.drinksLeft
        local durability = meta.durability
        if drinksLeft < MaxCanteenDrinks then
            updateCanteenMetadata(src, canteen.id, MaxCanteenDrinks, durability)
            DBG:Info(string.format('Refilled canteen for source: %d', src))
        else
            Core.NotifyRightTip(src, _U('fullCanteen'), 4000)
            DBG:Info(string.format('Canteen already full for source: %d', src))
            return cb(false)
        end
    end
    cb(true)
end)

-- Manage Drinking from Canteen
Core.Callback.Register('bcc-water:UpdateCanteen', function(source, cb, itemName, itemId)
    local src = source
    local user = Core.getUser(src)
    -- Check if the user exists
    if not user then
        DBG:Error(string.format('User not found for source: %d', src))
        return cb(false)
    end
    local canteen, canteenItemName = findCanteen(src, itemName, itemId, false)
    if not canteen then
        Core.NotifyRightTip(src, _U('needCanteen'), 4000)
        DBG:Warning(string.format('Canteen not found for source: %d item=%s id=%s', src, tostring(itemName), tostring(itemId)))
        return cb(false)
    end
    local meta = canteen['metadata'] or {}
    local drinksLeft = meta.drinksLeft
    local durability = meta.durability
    local canteenUsage = getCanteenUsage(canteenItemName)
    local newDurability = durability and durability - canteenUsage or 100
    -- Decrement drinks left and update durability
    if drinksLeft and drinksLeft > 0 then
        updateCanteenMetadata(src, canteen.id, drinksLeft - 1, newDurability)
        DBG:Info(string.format('Used canteen for source %d: Drinks Left = %d, New Durability = %d%%', src, drinksLeft - 1,
            newDurability))
        -- Remove the canteen if durability is too low
        if newDurability and newDurability < canteenUsage then
            exports.vorp_inventory:subItemById(src, canteen.id)
            Core.NotifyRightTip(src, _U('brokeCanteen'), 4000)
            DBG:Info(string.format('Canteen broke for source: %d', src))
        end
    else
        Core.NotifyRightTip(src, _U('emptyCanteen'), 4000)
        DBG:Info(string.format('Canteen empty for source: %d', src))
        return cb(false)
    end
    cb(true)
end)

RegisterNetEvent('bcc-water:UpdateSickness', function(isSick)
    local src = source
    local user = Core.getUser(src)
    -- Check if the user exists
    if not user then
        DBG:Error(string.format('User not found for source: %d', src))
        return
    end
    local character = user.getUsedCharacter
    local charid = character.charIdentifier
    DBG:Info(string.format('Updating sickness for character ID: %d', charid))
    SickPlayers[charid] = isSick and true or nil
    DBG:Info(string.format('Sickness status for character ID %d: %s', charid, tostring(isSick)))
end)

Core.Callback.Register('bcc-water:CheckSickness', function(source, cb)
    local src = source
    local user = Core.getUser(src)
    -- Check if the user exists
    if not user then
        DBG:Error(string.format('User not found for source: %d', src))
        return cb(false)
    end
    local character = user.getUsedCharacter
    local charid = character.charIdentifier
    if SickPlayers[charid] then
        DBG:Info(string.format('Sickness detected for character ID %d: %s', charid, tostring(SickPlayers[charid])))
        return cb(true)
    else
        DBG:Info(string.format('No sickness detected for character ID %d', charid))
        return cb(false)
    end
end)

-- Check if Player has an Item and Update Inventory
---@param itemType string
---@param itemAmount number
---@param pump boolean
Core.Callback.Register('bcc-water:GetItem', function(source, cb, itemType, itemAmount, pump)
    local src = source
    local user = Core.getUser(src)
    -- Check if the user exists
    if not user then
        DBG:Error(string.format('User not found for source: %d', src))
        return cb(false)
    end

    itemAmount = math.max(1, math.floor(tonumber(itemAmount) or 1))
    local sourceType = pump and 'pump' or 'wild'
    local wildDirty = not pump and Config.wild.dirtyItems

    if itemType == 'bottle' then
        local fillPlan = buildBottleFillPlan(src, itemAmount)
        if not fillPlan then
            Core.NotifyRightTip(src, _U('needBottle'), 4000)
            DBG:Warning(string.format('Source %d does not have enough configured empty bottles for amount: %d', src, itemAmount))
            return cb(false)
        end

        for _, entry in ipairs(fillPlan) do
            exports.vorp_inventory:subItem(src, entry.bottleType.empty, entry.amount)
        end

        for _, entry in ipairs(fillPlan) do
            local itemName = (pump or not wildDirty) and entry.bottleType.clean or entry.bottleType.dirty
            for i = 1, entry.amount do
                exports.vorp_inventory:addItem(src, itemName, 1, { source = sourceType })
                DBG:Info(string.format('Added bottle item to source %d: %s, Empty: %s, Pump: %s, WildDirty: %s', src, itemName, entry.bottleType.empty, tostring(pump), tostring(wildDirty)))
            end
        end

        return cb(true)
    end

    local item = exports.vorp_inventory:getItem(src, Config.emptyBucket)
    local bucketCount = tonumber(item and item.count) or 0
    if bucketCount < itemAmount then
        Core.NotifyRightTip(src, _U('needBucket'), 4000)
        DBG:Warning(string.format('Source %d does not have the required item: %s', src, Config.emptyBucket))
        return cb(false)
    end

    exports.vorp_inventory:subItem(src, Config.emptyBucket, itemAmount)
    local itemName = (pump or not wildDirty) and Config.cleanBucket or Config.dirtyBucket
    for i = 1, itemAmount do
        exports.vorp_inventory:addItem(src, itemName, 1, { source = sourceType })
        DBG:Info(string.format('Added item to source %d: %s, Pump: %s, WildDirty: %s', src, itemName, tostring(pump), tostring(wildDirty)))
    end
    cb(true)
end)

-- Register configured canteen items as usable items
for _, canteenItemName in ipairs(getConfiguredCanteenItems()) do
    exports.vorp_inventory:registerUsableItem(canteenItemName, function(data)
        local src = data.source
        local itemId = data.item and data.item.id
        exports.vorp_inventory:closeInventory(src)
        local canteen = itemId and getInventoryItemById(src, itemId) or exports.vorp_inventory:getItem(src, canteenItemName)
        if not canteen then
            Core.NotifyRightTip(src, _U('needCanteen'), 4000)
            DBG:Warning(string.format('Canteen not found during usable callback: source=%d item=%s id=%s', src, canteenItemName, tostring(itemId)))
            return
        end

        local meta = canteen['metadata'] or {}
        local durability = meta.durability
        local canteenUsage = getCanteenUsage(canteenItemName)
        -- Check if the canteen can be used
        if durability == nil or durability >= canteenUsage then
            TriggerClientEvent('bcc-water:UseCanteen', src, canteenItemName, itemId)
            DBG:Info(string.format('Canteen used by source: %d item=%s id=%s', src, canteenItemName, tostring(itemId)))
        else
            DBG:Warning(string.format('Canteen cannot be used by source: %d item=%s id=%s', src, canteenItemName, tostring(itemId)))
        end
    end)
end

local registeredBottleItems = {}

local function registerBottleUsableItem(itemName, emptyBottle, isDirty)
    if type(itemName) ~= 'string' or itemName == '' or registeredBottleItems[itemName] then
        return
    end

    registeredBottleItems[itemName] = true
    DBG:Info(string.format('Registering bottle as usable item: item=%s empty=%s dirty=%s', itemName, emptyBottle, tostring(isDirty)))
    exports.vorp_inventory:registerUsableItem(itemName, function(data)
        local src = data.source
        local itemId = data.item and data.item.id
        exports.vorp_inventory:closeInventory(src)

        if itemId then
            exports.vorp_inventory:subItemById(src, itemId)
        else
            exports.vorp_inventory:subItem(src, itemName, 1)
        end

        if exports.vorp_inventory:canCarryItem(src, emptyBottle, 1) then
            exports.vorp_inventory:addItem(src, emptyBottle, 1)
        end

        TriggerClientEvent('bcc-water:DrinkBottle', src, isDirty)
    end)
end

for _, bottleType in ipairs(getConfiguredBottleTypes()) do
    if Config.useable.cleanBottle then
        registerBottleUsableItem(bottleType.clean, bottleType.empty, false)
    end
    if Config.useable.dirtyBottle then
        registerBottleUsableItem(bottleType.dirty, bottleType.empty, true)
    end
end

if Config.useable.antidoteItem then
    DBG:Info('Registering antidote item as usable item')
    exports.vorp_inventory:registerUsableItem(Config.antidoteItem, function(data)
        local src = data.source
        exports.vorp_inventory:closeInventory(src)
        exports.vorp_inventory:subItem(src, Config.antidoteItem, 1)
        TriggerClientEvent('bcc-water:CureSickness', src)
    end)
end

-- Check if Player has a specific item
Core.Callback.Register('bcc-water:CheckItem', function(source, cb, itemName)
    local src = source
    local user = Core.getUser(src)
    if not user then
        DBG:Error(string.format('User not found for source: %d', src))
        return cb(false)
    end

    local item = exports.vorp_inventory:getItem(src, itemName)
    local hasItem = item and item.count > 0

    DBG:Info(string.format('CheckItem for source %d, item %s: %s', src, itemName, tostring(hasItem)))
    cb(hasItem)
end)

-- Remove a specific item from Player inventory
Core.Callback.Register('bcc-water:RemoveItem', function(source, cb, itemName, amount)
    local src = source
    local user = Core.getUser(src)
    if not user then
        DBG:Error(string.format('User not found for source: %d', src))
        return cb(false)
    end

    local item = exports.vorp_inventory:getItem(src, itemName)
    if not item or item.count < amount then
        DBG:Warning(string.format('Source %d does not have enough of item: %s (required: %d, has: %d)', src, itemName,
            amount, item and item.count or 0))
        return cb(false)
    end

    exports.vorp_inventory:subItem(src, itemName, amount)
    DBG:Info(string.format('Removed %d of item %s from source %d', amount, itemName, src))
    cb(true)
end)

-- Check if Player has any soap items from the table
Core.Callback.Register('bcc-water:CheckSoapItems', function(source, cb, soapItems)
    local src = source
    local user = Core.getUser(src)
    if not user then
        DBG:Error(string.format('User not found for source: %d', src))
        return cb(false, nil)
    end

    -- Check each soap item in the table
    for _, soapItem in ipairs(soapItems) do
        local item = exports.vorp_inventory:getItem(src, soapItem)
        if item and item.count > 0 then
            DBG:Info(string.format('CheckSoapItems for source %d, found soap: %s', src, soapItem))
            return cb(true, soapItem)
        end
    end

    DBG:Info(string.format('CheckSoapItems for source %d: no soap items found', src))
    cb(false, nil)
end)

-- Remove or update soap item with durability tracking
Core.Callback.Register('bcc-water:UseSoapItem', function(source, cb, soapItems, consumeSoap, maxUses)
    local src = source
    local user = Core.getUser(src)
    if not user then
        DBG:Error(string.format('User not found for source: %d', src))
        return cb(false, nil)
    end

    -- Find the first available soap item
    for _, soapItem in ipairs(soapItems) do
        local item = exports.vorp_inventory:getItem(src, soapItem)
        if item and item.count > 0 then
            if not consumeSoap then
                -- Soap is reusable, no removal or durability tracking
                DBG:Info(string.format('Used reusable soap item %s for source %d', soapItem, src))
                return cb(true, soapItem)
            end

            -- Get current uses from metadata
            local currentUses = 1
            if item.metadata and item.metadata.uses then
                currentUses = item.metadata.uses + 1
            end

            if currentUses >= maxUses then
                -- Remove the soap item as it's used up
                exports.vorp_inventory:subItem(src, soapItem, 1)
                DBG:Info(string.format('Soap item %s used up and removed from source %d after %d uses', soapItem, src, currentUses))
                return cb(true, soapItem)
            else
                -- Update metadata with current uses using setItemMetadata
                local metadata = item.metadata or {}
                metadata.uses = currentUses
                metadata.description = _U('soapDurability') .. ': ' .. tostring(currentUses) .. '/' .. tostring(maxUses)

                exports.vorp_inventory:setItemMetadata(src, item.id, metadata)

                DBG:Info(string.format('Updated soap item %s durability for source %d: %d/%d uses', soapItem, src, currentUses, maxUses))
                return cb(true, soapItem)
            end
        end
    end

    DBG:Warning(string.format('Source %d does not have any soap items from the table', src))
    cb(false, nil)
end)

BccUtils.Versioner.checkFile(GetCurrentResourceName(), 'https://github.com/BryceCanyonCounty/bcc-water')
