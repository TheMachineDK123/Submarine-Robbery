local ESX = exports['es_extended']:getSharedObject()

-- Aktive heists: heistId = { leader = serverId, members = {serverId, ...}, c4Placed = {}, state = 'waiting'|'active'|'inside'|'escaped'|'completed' }
local ActiveHeists = {}
local PlayerHeist = {} -- serverId -> heistId
local HeistIdCounter = 0
local GlobalCooldown = 0
local EventThrottle = {}
local logHeist

math.randomseed(os.time())

local function formatMoney(value)
    return ESX.Math.GroupDigits(tonumber(value) or 0)
end

local function getRandomMoneyReward()
    local minReward = tonumber(Config.MoneyRewardMin)
    local maxReward = tonumber(Config.MoneyRewardMax)

    if minReward and maxReward and minReward > 0 and maxReward >= minReward then
        return math.random(minReward, maxReward)
    end

    return tonumber(Config.MoneyReward) or 0
end

local function parseItemRewardConfig(reward)
    local itemName = reward and reward.item or nil

    local defaultChance = tonumber(Config.ItemRewardDefaultChance) or 100
    local chance = tonumber(reward and reward.chance)
    if chance == nil then
        chance = defaultChance
    end
    chance = math.floor(math.max(0, math.min(100, chance)))

    local defaultMin = tonumber(Config.ItemRewardDefaultMin) or 1
    local defaultMax = tonumber(Config.ItemRewardDefaultMax) or defaultMin
    if defaultMax < defaultMin then
        defaultMin, defaultMax = defaultMax, defaultMin
    end

    local minCount = tonumber(reward and reward.minCount)
    local maxCount = tonumber(reward and reward.maxCount)

    -- Bagudkompatibilitet: brug count hvis min/max ikke er sat
    if minCount == nil and maxCount == nil then
        local legacyCount = tonumber(reward and reward.count)
        if legacyCount ~= nil then
            minCount = legacyCount
            maxCount = legacyCount
        end
    end

    minCount = math.floor(minCount or defaultMin)
    maxCount = math.floor(maxCount or defaultMax)

    if minCount < 0 then minCount = 0 end
    if maxCount < minCount then maxCount = minCount end

    return {
        item = itemName,
        chance = chance,
        minCount = minCount,
        maxCount = maxCount,
    }
end

local function rollItemRewardCount(reward)
    local cfg = parseItemRewardConfig(reward)

    if not cfg.item or cfg.item == '' then
        return 0, cfg
    end

    if cfg.maxCount <= 0 then
        return 0, cfg
    end

    if math.random(1, 100) > cfg.chance then
        return 0, cfg
    end

    local amount = cfg.minCount
    if cfg.maxCount > cfg.minCount then
        amount = math.random(cfg.minCount, cfg.maxCount)
    end

    return amount, cfg
end

local function finalizeHeistCompletion(heistId, options)
    options = options or {}

    local heist = ActiveHeists[heistId]
    if not heist then
        return false, 'Heistet blev ikke fundet.'
    end

    if heist.state == 'completed' then
        return false, 'Heistet er allerede fuldført.'
    end

    heist.state = 'completed'
    heist.heistId = heistId
    heist.completedAt = os.time()

    if not options.skipDetonationScene then
        for _, memberId in ipairs(heist.members) do
            TriggerClientEvent('mach1ne_sub:client:detonateScene', memberId, heistId)
        end
        Wait(8000) -- Vent på eksplosions-animation
    end

    local payoutData = {
        payouts = {},
        totalMoney = 0,
    }

    for _, memberId in ipairs(heist.members) do
        local xMember = ESX.GetPlayerFromId(memberId)
        if xMember then
            local moneyReward = getRandomMoneyReward()
            payoutData.totalMoney = payoutData.totalMoney + moneyReward

            xMember.addAccountMoney('money', moneyReward, 'Submarine Heist Reward')
            TriggerClientEvent('ox_lib:notify', memberId, { type = 'success', description = ('Du modtog $%s!'):format(formatMoney(moneyReward)) })

            table.insert(payoutData.payouts, {
                id = memberId,
                identifier = xMember.getIdentifier(),
                name = xMember.getName(),
                amount = moneyReward,
            })

            for _, reward in ipairs(Config.ItemRewards) do
                local amount, cfg = rollItemRewardCount(reward)
                if amount > 0 then
                    exports.ox_inventory:AddItem(memberId, cfg.item, amount)
                    TriggerClientEvent('ox_lib:notify', memberId, {
                        type = 'success',
                        description = ('Du modtog %dx %s!'):format(amount, cfg.item)
                    })
                end
            end
        end
    end

    logHeist(heist, payoutData)

    local cleanupDelay = tonumber(options.cleanupDelayMs)
    if cleanupDelay == nil then
        cleanupDelay = options.skipDetonationScene and 0 or 5000
    end
    if cleanupDelay > 0 then
        Wait(cleanupDelay)
    end

    for _, memberId in ipairs(heist.members) do
        PlayerHeist[memberId] = nil
        EventThrottle[memberId] = nil
        TriggerClientEvent('mach1ne_sub:client:heistCompleted', memberId)
    end

    ActiveHeists[heistId] = nil

    if not options.skipCooldown then
        GlobalCooldown = os.time() + (Config.HeistCooldown * 60)
    end

    return true, nil
end

-- ========================
-- DISCORD WEBHOOK LOG
-- ========================
local function postWebhook(url, payload)
    if not url or url == '' then return end
    PerformHttpRequest(url, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

local function logSecurityEvent(title, color, fields)
    if not Config.AntiCheat or not Config.AntiCheat.LogSecurity then return end

    local securityUrl = Config.SecurityWebhook
    if not securityUrl or securityUrl == '' then
        securityUrl = Config.DiscordWebhook
    end

    if not securityUrl or securityUrl == '' then return end

    postWebhook(securityUrl, {
        username = 'Heist Security',
        embeds = {
            {
                title = title,
                color = color,
                fields = fields,
                footer = { text = 'Mach1ne Submarine Heist | Security' },
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
            }
        }
    })
end

local function markSecurityEvent(heist, src, action, reason)
    if heist then
        heist.securityEvents = (heist.securityEvents or 0) + 1
    end

    print(('[Mach1ne_Subrobbery] SECURITY: src=%d action=%s reason=%s'):format(src, action, reason))

    logSecurityEvent('🚨 Anti-Cheat Triggered', 15158332, {
        { name = 'Player', value = tostring(src), inline = true },
        { name = 'Action', value = action, inline = true },
        { name = 'Reason', value = reason, inline = false },
        { name = 'Heist ID', value = tostring(heist and heist.heistId or PlayerHeist[src] or 'N/A'), inline = true },
    })
end

local function checkRateLimit(src, key, fallbackMs)
    local anti = Config.AntiCheat or {}
    local map = anti.RateLimitMs or {}
    local cooldown = tonumber(map[key]) or fallbackMs or 1000

    EventThrottle[src] = EventThrottle[src] or {}
    local now = GetGameTimer()
    local allowedAt = EventThrottle[src][key] or 0

    if now < allowedAt then
        return false
    end

    EventThrottle[src][key] = now + cooldown
    return true
end

local function ensureMember(heist, src)
    for _, memberId in ipairs(heist.members) do
        if memberId == src then
            return true
        end
    end
    return false
end

local function isPolicePlayer(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then
        return false
    end

    local jobName = xPlayer.job and xPlayer.job.name
    local policeJob = Config.PoliceJobName or 'police'
    return tostring(jobName or ''):lower() == tostring(policeJob or 'police'):lower()
end

local function notifyPoliceSubmarineBreach(heist)
    for _, playerSrc in ipairs(GetPlayers()) do
        local targetId = tonumber(playerSrc)
        if targetId and isPolicePlayer(targetId) and not ensureMember(heist, targetId) then
            TriggerClientEvent('ox_lib:notify', targetId, {
                type = 'warning',
                title = 'Alarm',
                description = 'Et ubådsrøveri er i gang! Kriminelle er trængt ind i ubåden.',
            })
            TriggerClientEvent('mach1ne_sub:client:policeSubmarineAlert', targetId)
        end
    end
end

logHeist = function(heist, logData)
    if not Config.DiscordWebhook or Config.DiscordWebhook == '' then return end

    local memberLines = {}
    for _, memberId in ipairs(heist.members) do
        local xMember = ESX.GetPlayerFromId(memberId)
        if xMember then
            table.insert(memberLines, ('• **%s** (ID: %d | %s)'):format(xMember.getName(), memberId, xMember.getIdentifier()))
        end
    end

    local leaderX = ESX.GetPlayerFromId(heist.leader)
    local leaderName = leaderX and leaderX.getName() or 'Ukendt'
    local leaderIdentifier = leaderX and leaderX.getIdentifier() or 'Ukendt'

    local durationText = 'Ukendt'
    if heist.startedAt and heist.completedAt and heist.completedAt >= heist.startedAt then
        durationText = ('%d sekunder'):format(heist.completedAt - heist.startedAt)
    end

    local itemText = 'Ingen'
    if #Config.ItemRewards > 0 then
        local itemLines = {}
        for _, reward in ipairs(Config.ItemRewards) do
            local cfg = parseItemRewardConfig(reward)
            if cfg.item and cfg.item ~= '' then
                if cfg.minCount == cfg.maxCount then
                    table.insert(itemLines, ('%s%%: %dx %s'):format(cfg.chance, cfg.minCount, cfg.item))
                else
                    table.insert(itemLines, ('%s%%: %d-%dx %s'):format(cfg.chance, cfg.minCount, cfg.maxCount, cfg.item))
                end
            end
        end
        itemText = #itemLines > 0 and table.concat(itemLines, ', ') or 'Ingen'
    end

    local payoutLines = {}
    local totalMoney = logData and logData.totalMoney or 0
    if logData and logData.payouts then
        for _, payout in ipairs(logData.payouts) do
            table.insert(payoutLines, ('• %s: $%s'):format(payout.name, formatMoney(payout.amount)))
        end
    end

    local minReward = tonumber(Config.MoneyRewardMin) or 0
    local maxReward = tonumber(Config.MoneyRewardMax) or 0
    local rewardRange = ('$%s - $%s'):format(formatMoney(minReward), formatMoney(maxReward))

    local embed = {
        {
            title = '🔱 Ubåds Røveri Gennemført',
            color = 3066993,
            fields = {
                { name = '🆔 Heist ID', value = tostring(heist.heistId or 'N/A'), inline = true },
                { name = '⏱️ Varighed', value = durationText, inline = true },
                { name = '�️ Security events', value = tostring(heist.securityEvents or 0), inline = true },
                { name = '� Leder', value = ('**%s**\nID: %d | %s'):format(leaderName, heist.leader, leaderIdentifier), inline = false },
                { name = ('👥 Medlemmer (%d)'):format(#heist.members), value = table.concat(memberLines, '\n'), inline = false },
                { name = '💰 Reward range', value = rewardRange, inline = true },
                { name = '💵 Udbetalt total', value = ('$%s'):format(formatMoney(totalMoney)), inline = true },
                { name = '📦 Item Reward', value = itemText, inline = true },
                { name = '💳 Udbetalinger', value = #payoutLines > 0 and table.concat(payoutLines, '\n') or 'Ingen', inline = false },
            },
            footer = { text = 'Mach1ne Submarine Heist' },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        }
    }

    postWebhook(Config.DiscordWebhook, {
        username = 'Heist Logger',
        embeds = embed,
    })

    print(('[Mach1ne_Subrobbery] Heist logget til Discord v2: Leder=%s, Members=%d, Total=$%s'):format(leaderName, #heist.members, formatMoney(totalMoney)))
end

-- ========================
-- ANTI-EXPLOIT: Koordinat validering
-- ========================
local function getPlayerCoords(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function isNearCoord(playerCoords, targetCoords, maxDist)
    if not playerCoords then return false end
    maxDist = maxDist or 15.0
    local dx = playerCoords.x - targetCoords.x
    local dy = playerCoords.y - targetCoords.y
    local dz = playerCoords.z - targetCoords.z
    return (dx * dx + dy * dy + dz * dz) < (maxDist * maxDist)
end

local function getItemCount(src, itemName)
    if not itemName or itemName == '' then return 0 end

    local result = exports.ox_inventory:Search(src, 'count', itemName)
    if type(result) == 'number' then
        return result
    end

    if type(result) == 'table' then
        local total = 0
        for _, count in pairs(result) do
            total = total + (tonumber(count) or 0)
        end
        return total
    end

    return 0
end

local function hasRequiredStartTools(src)
    local req = Config.RequiredTools or {}
    local c4Item = req.c4Item or 'bomb_c4'
    local c4Needed = tonumber(req.c4Count) or 3
    local hackItem = req.hackItem or 'hackingdevice'
    local hackNeeded = tonumber(req.hackCount) or 1

    local c4Count = getItemCount(src, c4Item)
    if c4Count < c4Needed then
        return false, ('Du mangler %dx %s (du har %d).'):format(c4Needed, c4Item, c4Count)
    end

    local hackCount = getItemCount(src, hackItem)
    if hackCount < hackNeeded then
        return false, ('Du mangler %dx %s (du har %d).'):format(hackNeeded, hackItem, hackCount)
    end

    return true, nil
end

local function consumeHeistTool(src, toolType)
    local req = Config.RequiredTools or {}

    if toolType == 'c4' then
        local item = req.c4Item or 'bomb_c4'
        local removed = exports.ox_inventory:RemoveItem(src, item, 1)
        if not removed then
            return false, ('Du mangler %s.'):format(item)
        end
        return true, nil
    end

    if toolType == 'hack' then
        local item = req.hackItem or 'hackingdevice'
        local removed = exports.ox_inventory:RemoveItem(src, item, 1)
        if not removed then
            return false, ('Du mangler %s.'):format(item)
        end
        return true, nil
    end

    return false, 'Ugyldig tool type.'
end

-- Opret nyt heist
RegisterNetEvent('mach1ne_sub:server:createHeist', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    if PlayerHeist[src] then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Du er allerede i et heist!' })
        return
    end

    if os.time() < GlobalCooldown then
        local remaining = math.ceil((GlobalCooldown - os.time()) / 60)
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = ('Heist cooldown: %d minutter tilbage'):format(remaining) })
        return
    end

    HeistIdCounter = HeistIdCounter + 1
    local heistId = HeistIdCounter

    ActiveHeists[heistId] = {
        leader = src,
        members = { src },
        c4Placed = {},
        state = 'waiting',
        createdAt = os.time(),
        securityEvents = 0,
    }

    PlayerHeist[src] = heistId

    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = 'Heist oprettet! Inviter spillere eller start heistet.' })
    TriggerClientEvent('mach1ne_sub:client:heistCreated', src, heistId)
end)

-- Inviter spiller til heist
RegisterNetEvent('mach1ne_sub:server:invitePlayer', function(targetId)
    local src = source
    local heistId = PlayerHeist[src]

    if not heistId or not ActiveHeists[heistId] then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Du har ikke et aktivt heist!' })
        return
    end

    local heist = ActiveHeists[heistId]

    if heist.leader ~= src then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Kun lederen kan invitere spillere!' })
        return
    end

    if heist.state ~= 'waiting' then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Heistet er allerede startet!' })
        return
    end

    if #heist.members >= Config.MaxPlayers then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Heistet er fuldt!' })
        return
    end

    targetId = tonumber(targetId)
    if not targetId then return end

    local xTarget = ESX.GetPlayerFromId(targetId)
    if not xTarget then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Spiller ikke fundet!' })
        return
    end

    if PlayerHeist[targetId] then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Spilleren er allerede i et heist!' })
        return
    end

    -- Send invitation til target
    TriggerClientEvent('mach1ne_sub:client:receiveInvite', targetId, src, heistId)
    TriggerClientEvent('ox_lib:notify', src, { type = 'info', description = ('Invitation sendt til spiller %d'):format(targetId) })
end)

-- Accepter invitation
RegisterNetEvent('mach1ne_sub:server:acceptInvite', function(heistId)
    local src = source

    if PlayerHeist[src] then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Du er allerede i et heist!' })
        return
    end

    if not ActiveHeists[heistId] then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Heistet findes ikke længere!' })
        return
    end

    local heist = ActiveHeists[heistId]

    if heist.state ~= 'waiting' then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Heistet er allerede startet!' })
        return
    end

    if #heist.members >= Config.MaxPlayers then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Heistet er fuldt!' })
        return
    end

    table.insert(heist.members, src)
    PlayerHeist[src] = heistId

    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = 'Du har tilsluttet dig heistet!' })

    -- Underret alle members
    for _, memberId in ipairs(heist.members) do
        if memberId ~= src then
            TriggerClientEvent('ox_lib:notify', memberId, { type = 'info', description = ('Spiller %d har tilsluttet sig heistet!'):format(src) })
        end
    end

    TriggerClientEvent('mach1ne_sub:client:joinedHeist', src, heistId)
end)

-- Afvis invitation
RegisterNetEvent('mach1ne_sub:server:declineInvite', function(_, inviterId)
    local src = source
    if inviterId then
        TriggerClientEvent('ox_lib:notify', inviterId, { type = 'error', description = ('Spiller %d afviste invitationen.'):format(src) })
    end
end)

-- Start heistet (sejl ud)
RegisterNetEvent('mach1ne_sub:server:startHeist', function()
    local src = source
    local heistId = PlayerHeist[src]

    if not checkRateLimit(src, 'startHeist', 1500) then
        return
    end

    if not heistId or not ActiveHeists[heistId] then return end
    local heist = ActiveHeists[heistId]

    if heist.leader ~= src then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Kun lederen kan starte heistet!' })
        return
    end

    if heist.state ~= 'waiting' then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Heistet er allerede startet!' })
        return
    end

    local canStartWithTools, reason = hasRequiredStartTools(src)
    if not canStartWithTools then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = reason })
        return
    end

    heist.state = 'bunker_travel'
    heist.startedAt = os.time()
    heist.heistId = heistId
    heist.bunkerArrivedMembers = {}

    -- Underret alle members om at de skal køre til bunker-indgangen
    for _, memberId in ipairs(heist.members) do
        TriggerClientEvent('mach1ne_sub:client:heistGoToBunker', memberId, heistId)
    end
end)

-- Spiller ankommet til bunker-indgangen
RegisterNetEvent('mach1ne_sub:server:playerArrivedAtBunker', function()
    local src = source
    local heistId = PlayerHeist[src]

    if not checkRateLimit(src, 'playerArrivedAtBunker', 1500) then
        return
    end

    if not heistId or not ActiveHeists[heistId] then return end
    local heist = ActiveHeists[heistId]

    if not ensureMember(heist, src) then
        markSecurityEvent(heist, src, 'playerArrivedAtBunker', 'Player is not a heist member')
        return
    end

    if heist.state ~= 'bunker_travel' then
        markSecurityEvent(heist, src, 'playerArrivedAtBunker', ('Invalid state: %s'):format(tostring(heist.state)))
        return
    end

    local anti = Config.AntiCheat or {}
    local maxDist = (anti.MaxDistance and anti.MaxDistance.bunkerEntry) or 60.0
    if not isNearCoord(getPlayerCoords(src), Config.BunkerEntranceOutside, maxDist) then
        markSecurityEvent(heist, src, 'playerArrivedAtBunker', 'Player too far from bunker entrance')
        return
    end

    heist.bunkerArrivedMembers = heist.bunkerArrivedMembers or {}
    heist.bunkerArrivedMembers[src] = true

    local allArrived = true
    for _, memberId in ipairs(heist.members) do
        if not heist.bunkerArrivedMembers[memberId] then
            allArrived = false
            break
        end
    end

    if allArrived then
        heist.state = 'bunker'
        for _, memberId in ipairs(heist.members) do
            TriggerClientEvent('mach1ne_sub:client:enterBunker', memberId, heistId)
        end
    else
        TriggerClientEvent('ox_lib:notify', src, { type = 'info', description = 'Ankommet til bunkeren. Venter på resten af holdet...' })
    end
end)

-- Computer i bunker hacket: lås ubåd lokation op
RegisterNetEvent('mach1ne_sub:server:bunkerHackComplete', function()
    local src = source
    local heistId = PlayerHeist[src]

    if not checkRateLimit(src, 'bunkerHackComplete', 1200) then
        return
    end

    if not heistId or not ActiveHeists[heistId] then return end
    local heist = ActiveHeists[heistId]

    if not ensureMember(heist, src) then
        markSecurityEvent(heist, src, 'bunkerHackComplete', 'Player is not a heist member')
        return
    end

    if heist.state ~= 'bunker' then
        markSecurityEvent(heist, src, 'bunkerHackComplete', ('Invalid state: %s'):format(tostring(heist.state)))
        return
    end

    local anti = Config.AntiCheat or {}
    local maxDist = (anti.MaxDistance and anti.MaxDistance.bunkerComputer) or 25.0
    if not isNearCoord(getPlayerCoords(src), Config.BunkerComputer, maxDist) then
        markSecurityEvent(heist, src, 'bunkerHackComplete', 'Player too far from bunker computer')
        return
    end

    if heist.bunkerHackDone then
        return
    end

    heist.bunkerHackDone = true
    heist.bunkerExitReadyMembers = {}

    for _, memberId in ipairs(heist.members) do
        TriggerClientEvent('ox_lib:notify', memberId, {
            type = 'success',
            description = 'Computeren er hacket! Gå tilbage til bunker-indgangen og brug terminalen for at forlade bunkeren.'
        })
    end
end)

-- Spiller klar til at forlade bunkeren via ox_target ved indgangen
RegisterNetEvent('mach1ne_sub:server:playerExitBunker', function()
    local src = source
    local heistId = PlayerHeist[src]

    if not checkRateLimit(src, 'playerExitBunker', 1200) then
        return
    end

    if not heistId or not ActiveHeists[heistId] then return end
    local heist = ActiveHeists[heistId]

    if not ensureMember(heist, src) then
        markSecurityEvent(heist, src, 'playerExitBunker', 'Player is not a heist member')
        return
    end

    if heist.state ~= 'bunker' or not heist.bunkerHackDone then
        markSecurityEvent(heist, src, 'playerExitBunker', ('Invalid state/hack status: state=%s, hacked=%s'):format(tostring(heist.state), tostring(heist.bunkerHackDone)))
        return
    end

    local anti = Config.AntiCheat or {}
    local maxDist = (anti.MaxDistance and anti.MaxDistance.bunkerExit) or 30.0
    if not isNearCoord(getPlayerCoords(src), Config.BunkerEntranceInside, maxDist) then
        markSecurityEvent(heist, src, 'playerExitBunker', 'Player too far from bunker exit point')
        return
    end

    heist.bunkerExitReadyMembers = heist.bunkerExitReadyMembers or {}
    heist.bunkerExitReadyMembers[src] = true

    local allReady = true
    for _, memberId in ipairs(heist.members) do
        if not heist.bunkerExitReadyMembers[memberId] then
            allReady = false
            break
        end
    end

    if not allReady then
        TriggerClientEvent('ox_lib:notify', src, { type = 'info', description = 'Du er klar til at forlade bunkeren. Venter på resten af holdet...' })
        return
    end

    heist.state = 'active'
    for _, memberId in ipairs(heist.members) do
        TriggerClientEvent('mach1ne_sub:client:exitBunkerCutscene', memberId)
        TriggerClientEvent('mach1ne_sub:client:heistStarted', memberId, heistId)
    end
end)

-- Spiller ankommet til ubåden
RegisterNetEvent('mach1ne_sub:server:playerArrivedAtSub', function()
    local src = source
    local heistId = PlayerHeist[src]

    if not checkRateLimit(src, 'playerArrivedAtSub', 1500) then
        return
    end

    if not heistId or not ActiveHeists[heistId] then return end
    local heist = ActiveHeists[heistId]

    if not ensureMember(heist, src) then
        markSecurityEvent(heist, src, 'playerArrivedAtSub', 'Player is not a heist member')
        return
    end

    if heist.state ~= 'active' then
        markSecurityEvent(heist, src, 'playerArrivedAtSub', ('Invalid state: %s'):format(tostring(heist.state)))
        return
    end

    local anti = Config.AntiCheat or {}
    local maxDist = (anti.MaxDistance and anti.MaxDistance.subEntry) or 60.0
    if not isNearCoord(getPlayerCoords(src), Config.SubmarineEntryBoat, maxDist) then
        markSecurityEvent(heist, src, 'playerArrivedAtSub', 'Player too far from submarine entry point')
        return
    end

    if not heist.arrivedMembers then
        heist.arrivedMembers = {}
    end

    heist.arrivedMembers[src] = true

    -- Tjek om alle er ankommet
    local allArrived = true
    for _, memberId in ipairs(heist.members) do
        if not heist.arrivedMembers[memberId] then
            allArrived = false
            break
        end
    end

    if allArrived then
        heist.state = 'inside'
        -- Alle teleporteres ind i ubåden
        for _, memberId in ipairs(heist.members) do
            TriggerClientEvent('mach1ne_sub:client:enterSubmarine', memberId, heistId)
        end

        notifyPoliceSubmarineBreach(heist)
    else
        TriggerClientEvent('ox_lib:notify', src, { type = 'info', description = 'Venter på resten af holdet...' })
    end
end)

-- C4 placeret
RegisterNetEvent('mach1ne_sub:server:c4Placed', function(c4Index)
    local src = source
    local heistId = PlayerHeist[src]

    if not checkRateLimit(src, 'c4Placed', 1000) then
        return
    end

    if not heistId or not ActiveHeists[heistId] then return end
    local heist = ActiveHeists[heistId]

    if not ensureMember(heist, src) then
        markSecurityEvent(heist, src, 'c4Placed', 'Player is not a heist member')
        return
    end

    if heist.state ~= 'inside' then
        markSecurityEvent(heist, src, 'c4Placed', ('Invalid state: %s'):format(tostring(heist.state)))
        return
    end

    -- Valider c4Index
    c4Index = tonumber(c4Index)
    if not c4Index or c4Index < 1 or c4Index > #Config.C4Locations then
        markSecurityEvent(heist, src, 'c4Placed', ('Invalid c4 index: %s'):format(tostring(c4Index)))
        return
    end

    if heist.c4Placed[c4Index] then
        markSecurityEvent(heist, src, 'c4Placed', ('Duplicate c4 index: %d'):format(c4Index))
        return
    end

    -- Koordinat validering
    local playerCoords = getPlayerCoords(src)
    local c4Coords = Config.C4Locations[c4Index].coords
    local anti = Config.AntiCheat or {}
    local maxDist = (anti.MaxDistance and anti.MaxDistance.c4Placement) or 20.0
    if not isNearCoord(playerCoords, c4Coords, maxDist) then
        markSecurityEvent(heist, src, 'c4Placed', ('Too far from c4 point #%d'):format(c4Index))
        return
    end

    heist.c4Placed[c4Index] = true

    local totalPlaced = 0
    for _ in pairs(heist.c4Placed) do
        totalPlaced = totalPlaced + 1
    end

    -- Underret alle members
    for _, memberId in ipairs(heist.members) do
        TriggerClientEvent('mach1ne_sub:client:c4Update', memberId, c4Index, totalPlaced)
    end

    if totalPlaced >= #Config.C4Locations then
        -- Alle C4 placeret
        for _, memberId in ipairs(heist.members) do
            TriggerClientEvent('mach1ne_sub:client:allC4Placed', memberId)
            TriggerClientEvent('ox_lib:notify', memberId, { type = 'success', description = 'Alle C4 er placeret! Forlad ubåden!' })
        end
    end
end)

-- Spiller forlader ubåden
RegisterNetEvent('mach1ne_sub:server:exitSubmarine', function()
    local src = source
    local heistId = PlayerHeist[src]

    if not checkRateLimit(src, 'exitSubmarine', 1200) then
        return
    end

    if not heistId or not ActiveHeists[heistId] then return end
    local heist = ActiveHeists[heistId]

    if not ensureMember(heist, src) then
        markSecurityEvent(heist, src, 'exitSubmarine', 'Player is not a heist member')
        return
    end

    if heist.state ~= 'inside' then
        markSecurityEvent(heist, src, 'exitSubmarine', ('Invalid state: %s'):format(tostring(heist.state)))
        return
    end

    local totalPlaced = 0
    for _ in pairs(heist.c4Placed) do
        totalPlaced = totalPlaced + 1
    end

    if totalPlaced < #Config.C4Locations then
        markSecurityEvent(heist, src, 'exitSubmarine', 'Attempted to exit before all C4 points were completed')
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Du kan ikke forlade ubåden endnu.' })
        return
    end

    local anti = Config.AntiCheat or {}
    local maxDist = (anti.MaxDistance and anti.MaxDistance.subExit) or 30.0
    if not isNearCoord(getPlayerCoords(src), Config.SubmarineInterior, maxDist) then
        markSecurityEvent(heist, src, 'exitSubmarine', 'Player too far from submarine exit point')
        return
    end

    heist.state = 'escaped'

    -- Flyt hele holdet ud samtidig, så ingen bliver låst inde af state-check
    for _, memberId in ipairs(heist.members) do
        TriggerClientEvent('mach1ne_sub:client:exitSubmarine', memberId)
    end
end)

-- Spiller detonerer
RegisterNetEvent('mach1ne_sub:server:detonate', function()
    local src = source
    local heistId = PlayerHeist[src]

    if not checkRateLimit(src, 'detonate', 2000) then
        return
    end

    if not heistId or not ActiveHeists[heistId] then return end
    local heist = ActiveHeists[heistId]

    if not ensureMember(heist, src) then
        markSecurityEvent(heist, src, 'detonate', 'Player is not a heist member')
        return
    end

    if heist.state ~= 'escaped' then
        markSecurityEvent(heist, src, 'detonate', ('Invalid state: %s'):format(tostring(heist.state)))
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Du kan ikke detonere endnu.' })
        return
    end

    local anti = Config.AntiCheat or {}
    local maxDist = (anti.MaxDistance and anti.MaxDistance.detonation) or 40.0
    if not isNearCoord(getPlayerCoords(src), Config.DetonationPoint, maxDist) then
        markSecurityEvent(heist, src, 'detonate', 'Player too far from detonation point')
        return
    end

    if heist.state == 'completed' then return end

    -- Tjek at alle C4 er placeret
    local totalPlaced = 0
    for _ in pairs(heist.c4Placed) do
        totalPlaced = totalPlaced + 1
    end

    if totalPlaced < #Config.C4Locations then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Ikke alle C4 er placeret!' })
        return
    end

    finalizeHeistCompletion(heistId, {
        skipDetonationScene = false,
        skipCooldown = false,
    })
end)

RegisterCommand((Config.Debug and Config.Debug.ForceCompleteCommand) or 'sub_debug_complete', function(source, args)
    local debugCfg = Config.Debug or {}

    if not debugCfg.Enabled then
        if source ~= 0 then
            TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'Debug command er deaktiveret i config.' })
        else
            print('[Mach1ne_Subrobbery] Debug command er deaktiveret i config.')
        end
        return
    end

    if source ~= 0 and debugCfg.AdminOnly and not IsPlayerAceAllowed(source, 'mach1ne_sub.debug') then
        TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'Du har ikke adgang til debug command.' })
        return
    end

    local heistId
    if source == 0 then
        heistId = tonumber(args[1])
        if not heistId then
            print('[Mach1ne_Subrobbery] Brug: /' .. ((debugCfg.ForceCompleteCommand) or 'sub_debug_complete') .. ' <heistId>')
            return
        end
    else
        heistId = PlayerHeist[source]
        if not heistId or not ActiveHeists[heistId] then
            TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'Du er ikke i et aktivt heist.' })
            return
        end
    end

    local ok, reason = finalizeHeistCompletion(heistId, {
        skipDetonationScene = true,
        skipCooldown = true,
        cleanupDelayMs = 0,
    })

    if not ok then
        if source ~= 0 then
            TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = reason or 'Kunne ikke force-complete heistet.' })
        else
            print('[Mach1ne_Subrobbery] Debug force-complete fejlede: ' .. tostring(reason))
        end
        return
    end

    if source ~= 0 then
        TriggerClientEvent('ox_lib:notify', source, { type = 'success', description = 'Debug: Heist blev force-completed. Rewards er udbetalt.' })
    else
        print(('[Mach1ne_Subrobbery] Debug: Heist #%d force-completed.'):format(heistId))
    end
end, false)

-- Sync guard death
RegisterNetEvent('mach1ne_sub:server:guardKilled', function(guardIndex)
    local src = source
    local heistId = PlayerHeist[src]

    if not heistId or not ActiveHeists[heistId] then return end
    local heist = ActiveHeists[heistId]

    for _, memberId in ipairs(heist.members) do
        if memberId ~= src then
            TriggerClientEvent('mach1ne_sub:client:syncGuardDeath', memberId, guardIndex)
        end
    end
end)

-- Håndter spiller disconnect
AddEventHandler('playerDropped', function()
    local src = source
    local heistId = PlayerHeist[src]

    if not heistId or not ActiveHeists[heistId] then return end
    local heist = ActiveHeists[heistId]

    -- Fjern fra members
    for i, memberId in ipairs(heist.members) do
        if memberId == src then
            table.remove(heist.members, i)
            break
        end
    end

    PlayerHeist[src] = nil
    EventThrottle[src] = nil

    -- Hvis ingen members tilbage, afslut heist
    if #heist.members == 0 then
        ActiveHeists[heistId] = nil
        return
    end

    -- Hvis leader disconnected, giv ny leader
    if heist.leader == src then
        heist.leader = heist.members[1]
        TriggerClientEvent('ox_lib:notify', heist.leader, { type = 'info', description = 'Du er nu leder af heistet!' })
    end

    for _, memberId in ipairs(heist.members) do
        TriggerClientEvent('ox_lib:notify', memberId, { type = 'warning', description = ('Spiller %d har forladt heistet.'):format(src) })
    end
end)

-- Callback: hent heist info
lib.callback.register('mach1ne_sub:server:getHeistInfo', function(source)
    local src = source
    local heistId = PlayerHeist[src]

    if not heistId or not ActiveHeists[heistId] then
        return nil
    end

    local heist = ActiveHeists[heistId]
    return {
        heistId = heistId,
        leader = heist.leader,
        members = heist.members,
        state = heist.state,
        c4Placed = heist.c4Placed,
        isLeader = heist.leader == src,
    }
end)

-- Callback: tjek om heist er aktivt
lib.callback.register('mach1ne_sub:server:canStartHeist', function(source)
    local src = source
    if PlayerHeist[src] then
        return false, 'Du er allerede i et heist!'
    end
    if os.time() < GlobalCooldown then
        local remaining = math.ceil((GlobalCooldown - os.time()) / 60)
        return false, ('Cooldown: %d minutter'):format(remaining)
    end

    local canStartWithTools, reason = hasRequiredStartTools(src)
    if not canStartWithTools then
        return false, reason
    end

    return true, nil
end)

lib.callback.register('mach1ne_sub:server:isPolice', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        return false
    end

    local jobName = xPlayer.job and xPlayer.job.name
    local policeJob = Config.PoliceJobName or 'police'
    return tostring(jobName or ''):lower() == tostring(policeJob or 'police'):lower()
end)

lib.callback.register('mach1ne_sub:server:useHeistTool', function(source, toolType)
    local src = source
    local heistId = PlayerHeist[src]

    if not heistId or not ActiveHeists[heistId] then
        return false, 'Du er ikke i et aktivt heist.'
    end

    local heist = ActiveHeists[heistId]
    if not ensureMember(heist, src) then
        markSecurityEvent(heist, src, 'useHeistTool', 'Player is not a heist member')
        return false, 'Ikke gyldigt heist medlem.'
    end

    if toolType == 'hack' then
        if heist.state ~= 'inside' and heist.state ~= 'bunker' then
            return false, 'Du kan ikke hacke endnu.'
        end
    elseif toolType == 'c4' then
        if heist.state ~= 'inside' then
            return false, 'Du kan kun placere C4 inde i ubåden.'
        end
    else
        return false, 'Ugyldig tool type.'
    end

    return consumeHeistTool(src, toolType)
end)
