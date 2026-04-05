local myHeistId = nil
local isLeader = false
local insideSubmarine = false
local c4PlacedLocally = {}
local allC4Done = false
local guardPeds = {}
local guardBlips = {}
local heistNpcPed = nil
local detonationBlip = nil
local c4Props = {}
local heistState = 'none' -- none, waiting, bunker_travel, bunker, active, inside, escaped
local activeZones = {} -- Track ox_target zone IDs for cleanup
local isPlacingC4 = false
local lesterPed = nil
local savedOutfit = {}
local bunkerHackDone = false
local guardsAlerted = false
local guardMonitorToken = 0
local activeInteriorMinimap = nil
local kosatkaVeh = nil
local policeSubAccess = false
local submarineExitZoneCreated = false
local policeAccessZoneId = nil
local isPoliceCached = false
local setInteriorMinimap
local clearInteriorMinimap
local restoreOutfit

-- ========================
-- LESTER PHONE CALLS
-- ========================
local function lesterCall(message, duration)
    duration = duration or 5000
    lib.notify({
        id = 'lester_call',
        title = 'Lester',
        description = message,
        type = 'info',
        icon = 'phone',
        duration = duration,
    })
end

local function exitSubmarineLocal(skipHeistFlow)
    local wasPoliceSubAccess = policeSubAccess
    insideSubmarine = false
    heistState = 'escaped'
    clearInteriorMinimap()
    policeSubAccess = false

    DoScreenFadeOut(1000)
    Wait(1500)

    cleanupSubmarine()

    local exitCoords = Config.SubmarineExit
    if skipHeistFlow and wasPoliceSubAccess and Config.PoliceSubAccessTarget then
        exitCoords = Config.PoliceSubAccessTarget
    end
    local playerPed = cache.ped

    SetEntityCoords(playerPed, exitCoords.x, exitCoords.y, exitCoords.z, false, false, false, true)
    SetEntityHeading(playerPed, exitCoords.w)

    Wait(500)
    DoScreenFadeIn(1000)

    if not skipHeistFlow then
        restoreOutfit(cache.ped)
        lesterCall('Du er ude! Godt. Kør hen til mig - jeg venter ved detonationspunktet. Vi sprænger lortet sammen.', 8000)

        local detCoords = Config.DetonationPoint
        detonationBlip = AddBlipForCoord(detCoords.x, detCoords.y, detCoords.z)
        SetBlipSprite(detonationBlip, Config.DetonationBlip.sprite)
        SetBlipDisplay(detonationBlip, 4)
        SetBlipScale(detonationBlip, Config.DetonationBlip.scale)
        SetBlipColour(detonationBlip, Config.DetonationBlip.colour)
        SetBlipRoute(detonationBlip, true)
        SetBlipRouteColour(detonationBlip, Config.DetonationBlip.colour)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(Config.DetonationBlip.label)
        EndTextCommandSetBlipName(detonationBlip)

        setupDetonationZone()
    else
        lib.notify({ type = 'info', description = 'Du forlod ubåden.' })
    end
end

local function spawnKosatka()
    local cfg = Config.Kosatka
    if not cfg or not cfg.coords then return end

    if kosatkaVeh and DoesEntityExist(kosatkaVeh) then
        return
    end

    local model = joaat(cfg.model or 'kosatka')
    RequestModel(model)
    local timeout = 0
    while not HasModelLoaded(model) and timeout < 200 do
        Wait(50)
        timeout = timeout + 1
    end

    if not HasModelLoaded(model) then
        print('[Mach1ne_Subrobbery] FEJL: Kunne ikke loade Kosatka model.')
        return
    end

    local c = cfg.coords
    kosatkaVeh = CreateVehicle(model, c.x, c.y, c.z, c.w, false, false)
    if not kosatkaVeh or kosatkaVeh == 0 then
        print('[Mach1ne_Subrobbery] FEJL: Kunne ikke oprette Kosatka.')
        return
    end

    SetEntityAsMissionEntity(kosatkaVeh, true, true)
    SetEntityInvincible(kosatkaVeh, true)
    SetVehicleCanBeVisiblyDamaged(kosatkaVeh, false)
    SetVehicleEngineOn(kosatkaVeh, false, true, true)
    SetVehicleUndriveable(kosatkaVeh, true)
    SetVehicleDoorsLocked(kosatkaVeh, 2)
    SetVehicleDoorsLockedForAllPlayers(kosatkaVeh, true)
    FreezeEntityPosition(kosatkaVeh, true)
end

local function enterSubmarineAsPolice()
    local playerPed = cache.ped
    local subCoords = Config.SubmarineInterior

    policeSubAccess = true
    insideSubmarine = true
    heistState = 'inside'
    setInteriorMinimap('submarine')
    setupExitPoint()

    DoScreenFadeOut(700)
    Wait(850)
    SetEntityCoords(playerPed, subCoords.x, subCoords.y, subCoords.z, false, false, false, true)
    SetEntityHeading(playerPed, subCoords.w)
    Wait(350)
    DoScreenFadeIn(700)
    lib.notify({ type = 'success', description = 'Police-adgang: Du er gået ind i ubåden.' })
end

local function setupPoliceSubAccessTarget()
    if policeAccessZoneId then
        return
    end

    local c = Config.PoliceSubAccessTarget
    if not c then return end

    policeAccessZoneId = exports.ox_target:addSphereZone({
        coords = vector3(c.x, c.y, c.z),
        radius = 2.0,
        options = {
            {
                name = 'police_enter_kosatka_sub',
                icon = 'fas fa-submarine',
                label = 'Gå ind i Ubåd (Politi)',
                distance = 2.5,
                canInteract = function()
                    return isPoliceCached and not insideSubmarine
                end,
                onSelect = function()
                    if insideSubmarine then return end
                    local isPolice = lib.callback.await('mach1ne_sub:server:isPolice', false)
                    if not isPolice then
                        lib.notify({ type = 'error', description = 'Kun politiet kan bruge denne adgang.' })
                        return
                    end

                    enterSubmarineAsPolice()
                end,
            },
        },
    })
end

setInteriorMinimap = function(interiorKey)
    local m = Config.InteriorMinimap and Config.InteriorMinimap[interiorKey]
    activeInteriorMinimap = m
end

clearInteriorMinimap = function()
    activeInteriorMinimap = nil
end

local function alertAllGuards()
    if guardsAlerted then return end

    guardsAlerted = true
    local guardGroup = joaat('HATES_PLAYER')
    SetRelationshipBetweenGroups(5, guardGroup, joaat('PLAYER'))
    SetRelationshipBetweenGroups(5, joaat('PLAYER'), guardGroup)

    for _, ped in pairs(guardPeds) do
        if DoesEntityExist(ped) and not IsEntityDead(ped) then
            SetPedAlertness(ped, 3)
            SetPedSeeingRange(ped, 100.0)
            SetPedHearingRange(ped, 100.0)
            TaskCombatHatedTargetsAroundPed(ped, 100.0, 0)
        end
    end
end

-- ========================
-- DYKKERDRAGT
-- ========================
local function saveCurrentOutfit(ped)
    savedOutfit = {}
    for i = 0, 11 do
        savedOutfit[i] = {
            drawable = GetPedDrawableVariation(ped, i),
            texture = GetPedTextureVariation(ped, i),
        }
    end
end

local function applyWetsuit(ped)
    -- Dykkerdragt components (standard GTA wetsuit)
    SetPedComponentVariation(ped, 3, 2, 0, 2)   -- Torso
    SetPedComponentVariation(ped, 4, 94, 0, 2)  -- Legs
    SetPedComponentVariation(ped, 6, 67, 0, 2)  -- Shoes
    SetPedComponentVariation(ped, 8, 151, 0, 2) -- Undershirt
    SetPedComponentVariation(ped, 11, 243, 0, 2) -- Top
end

restoreOutfit = function(ped)
    for i, data in pairs(savedOutfit) do
        SetPedComponentVariation(ped, i, data.drawable, data.texture, 2)
    end
    savedOutfit = {}
end

-- ========================
-- NPC SPAWN
-- ========================
local npcTargetOptions = {
    {
        name = 'sub_heist_start',
        icon = 'fas fa-anchor',
        label = 'Start Ubåds Røveri',
        distance = 2.5,
        canInteract = function()
            return myHeistId == nil
        end,
        onSelect = function()
            openHeistMenu()
        end,
    },
    {
        name = 'sub_heist_manage',
        icon = 'fas fa-users',
        label = 'Administrer Heist',
        distance = 2.5,
        canInteract = function()
            return myHeistId ~= nil and isLeader and heistState == 'waiting'
        end,
        onSelect = function()
            openManageMenu()
        end,
    },
}

local function createHeistPed()
    local coords = Config.HeistNPC.coords

    -- Prøv primær model, fallback til anden hvis den fejler
    local models = { Config.HeistNPC.model, 'a_m_m_business_01', 'cs_bankman' }
    local model

    for _, modelName in ipairs(models) do
        local hash = joaat(modelName)
        RequestModel(hash)
        local timeout = 0
        while not HasModelLoaded(hash) and timeout < 100 do
            Wait(50)
            timeout = timeout + 1
        end
        if HasModelLoaded(hash) then
            model = hash
            print(('[Mach1ne_Subrobbery] NPC model loaded: %s'):format(modelName))
            break
        end
        print(('[Mach1ne_Subrobbery] Model fejlede: %s, prøver næste...'):format(modelName))
    end

    if not model then
        print('[Mach1ne_Subrobbery] KRITISK FEJL: Ingen NPC model kunne loades!')
        return nil
    end

    local ped = CreatePed(0, model, coords.x, coords.y, coords.z, coords.w, false, false)

    if not ped or ped == 0 then
        print('[Mach1ne_Subrobbery] FEJL: Kunne ikke oprette NPC ped')
        return nil
    end

    SetEntityAsMissionEntity(ped, true, true)
    SetEntityHeading(ped, coords.w)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    FreezeEntityPosition(ped, true)

    -- Vent et øjeblik før idle-task, så ped ikke ender i A-pose
    CreateThread(function()
        Wait(300)
        if DoesEntityExist(ped) then
            ClearPedTasksImmediately(ped)
            TaskStartScenarioAtPosition(ped, 'WORLD_HUMAN_STAND_IMPATIENT', coords.x, coords.y, coords.z, coords.w, 0, true, false)
            SetEntityHeading(ped, coords.w)
        end
    end)

    exports.ox_target:addLocalEntity(ped, npcTargetOptions)

    return ped
end

local function spawnHeistNPC()
    local coords = Config.HeistNPC.coords

  

    heistNpcPed = createHeistPed()

    -- Overvågningstråd: genskab NPC hvis den forsvinder
    CreateThread(function()
        while true do
            Wait(2000)
            if heistNpcPed and DoesEntityExist(heistNpcPed) then
                -- NPC eksisterer stadig, hold den frozen + sørg for normal idle anim
                local currentHeading = Config.HeistNPC.coords.w
                SetEntityHeading(heistNpcPed, currentHeading)
                FreezeEntityPosition(heistNpcPed, true)
                if not IsPedUsingAnyScenario(heistNpcPed) then
                    ClearPedTasksImmediately(heistNpcPed)
                    local c = Config.HeistNPC.coords
                    TaskStartScenarioAtPosition(heistNpcPed, 'WORLD_HUMAN_STAND_IMPATIENT', c.x, c.y, c.z, currentHeading, 0, true, false)
                    SetEntityHeading(heistNpcPed, currentHeading)
                end
            else
                -- NPC er væk, genskab
                heistNpcPed = createHeistPed()
            end
        end
    end)
end

-- ========================
-- MENUER
-- ========================
function openHeistMenu()
    local canStart, reason = lib.callback.await('mach1ne_sub:server:canStartHeist', false)

    if not canStart then
        lib.notify({ type = 'error', description = reason })
        return
    end

    local alert = lib.alertDialog({
        header = 'Ubåds Røveri',
        content = 'Vil du starte et nyt ubåds røveri? Du kan invitere spillere bagefter.',
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Start Heist',
            cancel = 'Annuller',
        },
    })

    if alert == 'confirm' then
        TriggerServerEvent('mach1ne_sub:server:createHeist')
    end
end

function openManageMenu()
    local options = {
        {
            title = 'Inviter Spiller',
            description = 'Inviter en spiller via deres server ID',
            icon = 'user-plus',
            onSelect = function()
                local input = lib.inputDialog('Inviter Spiller', {
                    { type = 'number', label = 'Server ID', description = 'Indtast spillerens server ID', required = true },
                })
                if input then
                    TriggerServerEvent('mach1ne_sub:server:invitePlayer', input[1])
                end
            end,
        },
        {
            title = 'Start Heist',
            description = 'Start heistet og sejl ud til ubåden',
            icon = 'play',
            onSelect = function()
                TriggerServerEvent('mach1ne_sub:server:startHeist')
            end,
        },
    }

    lib.registerContext({
        id = 'sub_heist_manage',
        title = 'Administrer Heist',
        options = options,
    })

    lib.showContext('sub_heist_manage')
end

-- ========================
-- HEIST EVENTS
-- ========================
RegisterNetEvent('mach1ne_sub:client:heistCreated', function(heistId)
    myHeistId = heistId
    isLeader = true
    heistState = 'waiting'
    lib.notify({ type = 'success', description = 'Heist oprettet! Brug NPC\'en til at invitere spillere og starte.' })
end)

RegisterNetEvent('mach1ne_sub:client:joinedHeist', function(heistId)
    myHeistId = heistId
    isLeader = false
    heistState = 'waiting'
end)

-- Modtag invitation
RegisterNetEvent('mach1ne_sub:client:receiveInvite', function(inviterId, heistId)
    local alert = lib.alertDialog({
        header = 'Heist Invitation',
        content = ('Spiller %d inviterer dig til et Ubåds Røveri. Vil du deltage?'):format(inviterId),
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Accepter',
            cancel = 'Afvis',
        },
    })

    if alert == 'confirm' then
        TriggerServerEvent('mach1ne_sub:server:acceptInvite', heistId)
    else
        TriggerServerEvent('mach1ne_sub:server:declineInvite', heistId, inviterId)
    end
end)

-- ========================
-- BUNKER FASE
-- ========================
RegisterNetEvent('mach1ne_sub:client:heistGoToBunker', function()
    heistState = 'bunker_travel'
    bunkerHackDone = false
    allC4Done = false
    c4PlacedLocally = {}

    local bunkerOut = Config.BunkerEntranceOutside
    local blip = AddBlipForCoord(bunkerOut.x, bunkerOut.y, bunkerOut.z)
    SetBlipSprite(blip, 356)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.95)
    SetBlipColour(blip, 5)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Doomsday Bunker')
    EndTextCommandSetBlipName(blip)

    lesterCall('Kør til Doomsday bunkeren. Når hele holdet er fremme, går I ind sammen.', 8000)

    CreateThread(function()
        while heistState == 'bunker_travel' do
            local playerCoords = GetEntityCoords(cache.ped)
            local dist = #(playerCoords - vector3(bunkerOut.x, bunkerOut.y, bunkerOut.z))

            if dist < 55.0 then
                if DoesBlipExist(blip) then
                    RemoveBlip(blip)
                end
                TriggerServerEvent('mach1ne_sub:server:playerArrivedAtBunker')
                lib.notify({ type = 'info', description = 'Ankommet ved bunker indgangen. Venter på resten af holdet...' })
                break
            end

            Wait(1000)
        end

        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end)
end)

RegisterNetEvent('mach1ne_sub:client:enterBunker', function()
    heistState = 'bunker'
    setInteriorMinimap('bunker')
    bunkerHackDone = false
    c4PlacedLocally = {}
    allC4Done = false

    DoScreenFadeOut(1000)
    Wait(1500)

    local playerPed = cache.ped
    local bunkerIn = Config.BunkerEntranceInside
    SetEntityCoords(playerPed, bunkerIn.x, bunkerIn.y, bunkerIn.z, false, false, false, true)
    SetEntityHeading(playerPed, bunkerIn.w)

    Wait(500)
    DoScreenFadeIn(1000)
    Wait(800)

    FreezeEntityPosition(playerPed, false)

    lesterCall('I er inde i bunkeren. Ryd området og hack computeren for at få ubådens lokation.', 8000)

    spawnGuards(Config.BunkerGuards)
    setupBunkerHackTarget()
    setupBunkerExitTarget()
end)

RegisterNetEvent('mach1ne_sub:client:exitBunkerCutscene', function()
    local playerPed = cache.ped
    local bunkerOut = Config.BunkerEntranceOutside

    FreezeEntityPosition(playerPed, true)
    DoScreenFadeOut(1000)
    Wait(1200)

    cleanupSubmarine()

    SetEntityCoords(playerPed, bunkerOut.x, bunkerOut.y, bunkerOut.z, false, false, false, true)
    SetEntityHeading(playerPed, bunkerOut.w)
    clearInteriorMinimap()

    Wait(400)
    DoScreenFadeIn(1000)
    Wait(800)

    FreezeEntityPosition(playerPed, false)
end)

-- ========================
-- HEIST STARTET - SEJL TIL UBÅD
-- ========================
RegisterNetEvent('mach1ne_sub:client:heistStarted', function()
    heistState = 'active'
    allC4Done = false
    c4PlacedLocally = {}

    spawnKosatka()

    -- Sæt waypoint til ubådens lokation
    local subCoords = Config.SubmarineEntryBoat

    local blip = AddBlipForCoord(subCoords.x, subCoords.y, subCoords.z)
    SetBlipSprite(blip, 478)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 1.0)
    SetBlipColour(blip, 3)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, 3)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Ubåd Lokation')
    EndTextCommandSetBlipName(blip)

    lesterCall('Computeren gav os lokationen. Kør ud til ubåden, og vent på resten af holdet.', 8000)

    -- Vent på at spilleren ankommer
    CreateThread(function()
        while heistState == 'active' do
            local playerCoords = GetEntityCoords(cache.ped)
            local dist = #(playerCoords - subCoords)

            if dist < 50.0 then
                RemoveBlip(blip)
                TriggerServerEvent('mach1ne_sub:server:playerArrivedAtSub')
                lib.notify({ type = 'info', description = 'Ankommet! Venter på resten af holdet...' })
                break
            end

            Wait(1000)
        end
    end)
end)

-- ========================
-- ENTRE UBÅDEN
-- ========================
RegisterNetEvent('mach1ne_sub:client:enterSubmarine', function()
    heistState = 'inside'
    insideSubmarine = true
    policeSubAccess = false
    guardsAlerted = false
    setInteriorMinimap('submarine')

    -- Fade screen
    DoScreenFadeOut(1000)
    Wait(1500)

    -- Cutscene-lignende effekt
    local playerPed = cache.ped
    local subCoords = Config.SubmarineInterior

    SetEntityCoords(playerPed, subCoords.x, subCoords.y, subCoords.z, false, false, false, true)
    SetEntityHeading(playerPed, subCoords.w)
    FreezeEntityPosition(playerPed, true)

    Wait(500)

    DoScreenFadeIn(1000)
    Wait(1000)

    -- Gem outfit og skift til dykkerdragt
    saveCurrentOutfit(playerPed)
    applyWetsuit(playerPed)

    lesterCall('Du er inde. Ryd vagterne og placer C4 på de markerede steder.', 8000)

    FreezeEntityPosition(playerPed, false)

    -- Spawn guards og C4 targets
    spawnGuards(Config.Guards)
    setupC4Targets()
    setupExitPoint()
end)

-- ========================
-- VAGTER
-- ========================
function spawnGuards(guardList)
    guardList = guardList or Config.Guards
    guardsAlerted = false
    guardMonitorToken = guardMonitorToken + 1
    local myGuardToken = guardMonitorToken

    local guardWeapons = {
        'WEAPON_COMBATPDW',
        'WEAPON_COMBATMG',
        'WEAPON_CARBINERIFLE',
        'WEAPON_PISTOL',
        'WEAPON_PUMPSHOTGUN',
    }

    local fallbackGuardModels = { 's_m_y_marine_03', 's_m_y_swat_01', 's_m_y_cop_01', 'a_m_m_business_01' }
    local loadedModelCache = {}

    local function loadGuardModel(modelName)
        if not modelName or modelName == '' then
            return nil
        end

        if loadedModelCache[modelName] then
            return loadedModelCache[modelName]
        end

        local hash = joaat(modelName)
        RequestModel(hash)
        local timeout = 0
        while not HasModelLoaded(hash) and timeout < 100 do
            Wait(50)
            timeout = timeout + 1
        end

        if HasModelLoaded(hash) then
            loadedModelCache[modelName] = hash
            return hash
        end

        return nil
    end

    -- Relationship group for guards (starter neutralt i stealth mode)
    local guardGroup = joaat('HATES_PLAYER')
    SetRelationshipBetweenGroups(0, guardGroup, joaat('PLAYER'))
    SetRelationshipBetweenGroups(0, joaat('PLAYER'), guardGroup)

    local stealth = Config.Stealth or {}
    local sightRange = tonumber(stealth.sightRange) or 16.0
    local instantSpotRange = tonumber(stealth.instantSpotRange) or 8.0
    local showGuardBlips = stealth.showGuardBlips ~= false
    local alertOnUnsilencedShot = stealth.alertOnUnsilencedShot ~= false

    for i, guard in ipairs(guardList) do
        local modelHash = loadGuardModel(guard.model)

        if not modelHash then
            for _, fallbackModel in ipairs(fallbackGuardModels) do
                modelHash = loadGuardModel(fallbackModel)
                if modelHash then
                    print(('[Mach1ne_Subrobbery] Guard fallback model loaded: %s'):format(fallbackModel))
                    break
                end
            end
        end

        if not modelHash then
            print(('[Mach1ne_Subrobbery] FEJL: Guard #%d model kunne ikke loades'):format(i))
        else
            local ped = CreatePed(4, modelHash, guard.coords.x, guard.coords.y, guard.coords.z - 1.0, guard.coords.w, false, false)

            if ped and ped ~= 0 then
                local weaponName = guardWeapons[((i - 1) % #guardWeapons) + 1] or Config.GuardWeapon
                local weaponHash = joaat(weaponName)

                SetEntityAsMissionEntity(ped, true, true)
                SetBlockingOfNonTemporaryEvents(ped, false)
                FreezeEntityPosition(ped, false)
                SetPedArmour(ped, 100)
                SetPedAccuracy(ped, 60)
                GiveWeaponToPed(ped, weaponHash, 9999, false, true)
                SetCurrentPedWeapon(ped, weaponHash, true)
                SetPedCombatAbility(ped, 2)
                SetPedCombatMovement(ped, 2)
                SetPedCombatRange(ped, 2)
                SetPedAlertness(ped, 0)
                SetPedFleeAttributes(ped, 0, false)
                SetPedRelationshipGroupHash(ped, guardGroup)
                SetEntityInvincible(ped, false)
                SetPedSeeingRange(ped, sightRange)
                SetPedHearingRange(ped, sightRange)
                SetPedCanRagdoll(ped, true)
                ClearPedTasksImmediately(ped)
                TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_GUARD_STAND', 0, true)
                guardPeds[i] = ped

                if showGuardBlips then
                    local blip = AddBlipForEntity(ped)
                    SetBlipSprite(blip, 303)
                    SetBlipColour(blip, 1)
                    SetBlipScale(blip, 0.65)
                    SetBlipAsShortRange(blip, false)
                    ShowHeadingIndicatorOnBlip(blip, true)
                    guardBlips[i] = blip
                end

                print(('[Mach1ne_Subrobbery] Guard #%d spawnet'):format(i))
            else
                print(('[Mach1ne_Subrobbery] FEJL: Guard #%d kunne ikke oprettes'):format(i))
            end
        end

        Wait(150)
    end

    -- Stealth monitor: guards opdager ved LOS/afstand eller usilenced shots
    CreateThread(function()
        while myGuardToken == guardMonitorToken and (insideSubmarine or heistState == 'bunker') do
            local playerPed = cache.ped
            if DoesEntityExist(playerPed) and not guardsAlerted then
                if alertOnUnsilencedShot and IsPedShooting(playerPed) and not IsPedCurrentWeaponSilenced(playerPed) then
                    alertAllGuards()
                else
                    local playerCoords = GetEntityCoords(playerPed)
                    for _, ped in pairs(guardPeds) do
                        if DoesEntityExist(ped) and not IsEntityDead(ped) then
                            local guardCoords = GetEntityCoords(ped)
                            local dist = #(playerCoords - guardCoords)
                            if dist <= instantSpotRange or (dist <= sightRange and HasEntityClearLosToEntity(ped, playerPed, 17)) then
                                alertAllGuards()
                                break
                            end
                        end
                    end
                end
            end

            for i, ped in pairs(guardPeds) do
                if DoesEntityExist(ped) and IsEntityDead(ped) then
                    TriggerServerEvent('mach1ne_sub:server:guardKilled', i)
                    if guardBlips[i] then
                        RemoveBlip(guardBlips[i])
                        guardBlips[i] = nil
                    end
                    guardPeds[i] = nil
                end
            end

            Wait(250)
        end
    end)
end

RegisterNetEvent('mach1ne_sub:client:syncGuardDeath', function(guardIndex)
    if guardPeds[guardIndex] and DoesEntityExist(guardPeds[guardIndex]) then
        if not IsEntityDead(guardPeds[guardIndex]) then
            SetEntityHealth(guardPeds[guardIndex], 0)
        end
    end

    if guardBlips[guardIndex] then
        RemoveBlip(guardBlips[guardIndex])
        guardBlips[guardIndex] = nil
    end
end)

-- ========================
-- C4 PLACERING
-- ========================
function setupBunkerHackTarget()
    local c = Config.BunkerComputer

    local zoneId = exports.ox_target:addSphereZone({
        coords = vector3(c.x, c.y, c.z),
        radius = 1.6,
        options = {
            {
                name = 'bunker_hack_computer',
                icon = 'fas fa-laptop-code',
                label = 'Hack Bunker Computer',
                distance = 2.0,
                canInteract = function()
                    return heistState == 'bunker' and not bunkerHackDone
                end,
                onSelect = function()
                    if bunkerHackDone or isPlacingC4 then return end

                    isPlacingC4 = true
                    local ok, reason = lib.callback.await('mach1ne_sub:server:useHeistTool', false, 'hack')
                    if not ok then
                        lib.notify({ type = 'error', description = reason or 'Du mangler hackingdevice.' })
                        isPlacingC4 = false
                        return
                    end

                    local success = exports['glitch-minigames']:StartFingerprintGame(
                        30000,
                        true,
                        true
                    )

                    if success then
                        bunkerHackDone = true
                        TriggerServerEvent('mach1ne_sub:server:bunkerHackComplete')
                        lib.notify({ type = 'success', description = 'Computeren er hacket! Gå tilbage til indgangen og brug terminalen for at forlade bunkeren.' })
                    else
                        lib.notify({ type = 'error', description = 'Hacket fejlede! Prøv igen.' })
                    end

                    isPlacingC4 = false
                end,
            },
        },
    })

    table.insert(activeZones, zoneId)
end

function setupBunkerExitTarget()
    local c = Config.BunkerEntranceInside

    local zoneId = exports.ox_target:addSphereZone({
        coords = vector3(c.x, c.y, c.z),
        radius = 2.0,
        options = {
            {
                name = 'bunker_exit_terminal',
                icon = 'fas fa-door-open',
                label = 'Forlad Bunker',
                distance = 2.5,
                canInteract = function()
                    return heistState == 'bunker' and bunkerHackDone
                end,
                onSelect = function()
                    TriggerServerEvent('mach1ne_sub:server:playerExitBunker')
                end,
            },
        },
    })

    table.insert(activeZones, zoneId)
end

function setupC4Targets()
    for i, c4 in ipairs(Config.C4Locations) do
        local coords = c4.coords

        -- Opret zone
        local zoneId = exports.ox_target:addSphereZone({
            coords = vector3(coords.x, coords.y, coords.z),
            radius = 1.0,
            options = {
                {
                    name = ('place_c4_%d'):format(i),
                    icon = 'fas fa-bomb',
                    label = c4.label,
                    distance = 2.0,
                    canInteract = function()
                        return insideSubmarine and not c4PlacedLocally[i] and not allC4Done
                    end,
                    onSelect = function()
                        placeC4(i, coords)
                    end,
                },
            },
        })
        table.insert(activeZones, zoneId)
    end
end

function placeC4(index, coords)
    if c4PlacedLocally[index] or isPlacingC4 then return end
    isPlacingC4 = true

    local c4Data = Config.C4Locations[index]
    local playerPed = cache.ped

    if c4Data and c4Data.action == 'hack' then
        local ok, reason = lib.callback.await('mach1ne_sub:server:useHeistTool', false, 'hack')
        if not ok then
            lib.notify({ type = 'error', description = reason or 'Du mangler hackingdevice.' })
            isPlacingC4 = false
            return
        end

        lib.notify({ type = 'info', description = 'Du skal hacke computeren...' })

        local success = exports['glitch-minigames']:StartFingerprintGame(
            30000,
            true,
            true
        )

        if not success then
            lib.notify({ type = 'error', description = 'Hacket fejlede! Prøv igen.' })
            isPlacingC4 = false
            return
        end

        c4PlacedLocally[index] = true
        TriggerServerEvent('mach1ne_sub:server:c4Placed', index)
        lib.notify({ type = 'success', description = 'Computeren er hacket!' })
        isPlacingC4 = false
        return
    end

    local ok, reason = lib.callback.await('mach1ne_sub:server:useHeistTool', false, 'c4')
    if not ok then
        lib.notify({ type = 'error', description = reason or 'Du mangler bomb_c4.' })
        isPlacingC4 = false
        return
    end

    -- Animationsdict (kun for bomber)
    lib.requestAnimDict('anim@heists@ornate_bank@grab_cash_heels')

    -- Placer C4 animation + progress bar
    if lib.progressBar({
        duration = 5000,
        label = 'Placerer C4...',
        useWhileDead = false,
        canCancel = false,
        disable = {
            car = true,
            move = true,
            combat = true,
        },
        anim = {
            dict = 'anim@heists@ornate_bank@grab_cash_heels',
            clip = 'grab',
        },
    }) then
        ClearPedTasks(playerPed)

        -- Spawn C4 prop
        local c4Model = joaat('w_ex_pe')
        RequestModel(c4Model)
        local t = 0
        while not HasModelLoaded(c4Model) and t < 100 do
            Wait(50)
            t = t + 1
        end

        if HasModelLoaded(c4Model) then
            local c4Prop = CreateObject(c4Model, coords.x, coords.y, coords.z - 0.5, false, false, false)
            PlaceObjectOnGroundProperly(c4Prop)
            FreezeEntityPosition(c4Prop, true)
            c4Props[index] = c4Prop
        end

        c4PlacedLocally[index] = true
        TriggerServerEvent('mach1ne_sub:server:c4Placed', index)
        lib.notify({ type = 'success', description = ('C4 #%d placeret!'):format(index) })
    end
    isPlacingC4 = false
end

RegisterNetEvent('mach1ne_sub:client:c4Update', function(c4Index, totalPlaced)
    c4PlacedLocally[c4Index] = true
    lib.notify({ type = 'info', description = ('C4 placeret: %d/%d'):format(totalPlaced, #Config.C4Locations) })
end)

RegisterNetEvent('mach1ne_sub:client:allC4Placed', function()
    allC4Done = true
    lesterCall('Perfekt! Alt er på plads. Kom ud af ubåden - HURTIGT!', 6000)
end)

RegisterNetEvent('mach1ne_sub:client:policeSubmarineAlert', function()
    local subEntry = Config.SubmarineEntryBoat
    if subEntry then
        SetNewWaypoint(subEntry.x, subEntry.y)
    end
end)

-- ========================
-- FORLAD UBÅD
-- ========================
function setupExitPoint()
    if submarineExitZoneCreated then
        return
    end

    local exitCoords = Config.SubmarineInterior

    local zoneId = exports.ox_target:addSphereZone({
        coords = vector3(exitCoords.x, exitCoords.y, exitCoords.z),
        radius = 2.0,
        options = {
            {
                name = 'exit_submarine',
                icon = 'fas fa-door-open',
                label = 'Forlad Ubåden',
                distance = 2.5,
                canInteract = function()
                    local hasHeist = myHeistId ~= nil
                    local canPoliceExit = policeSubAccess and isPoliceCached
                    return insideSubmarine and ((hasHeist and allC4Done) or (not hasHeist and canPoliceExit))
                end,
                onSelect = function()
                    local hasHeist = myHeistId ~= nil
                    local canPoliceExit = policeSubAccess and isPoliceCached

                    if hasHeist then
                        TriggerServerEvent('mach1ne_sub:server:exitSubmarine')
                        return
                    end

                    if canPoliceExit then
                        exitSubmarineLocal(true)
                    else
                        lib.notify({ type = 'error', description = 'Kun police med adgang kan bruge denne exit.' })
                    end
                end,
            },
        },
    })
    submarineExitZoneCreated = true
    table.insert(activeZones, zoneId)
end

RegisterNetEvent('mach1ne_sub:client:exitSubmarine', function()
    exitSubmarineLocal(false)
end)

-- ========================
-- DETONATION
-- ========================
function setupDetonationZone()
    local detCoords = Config.DetonationPoint
    local model = joaat('ig_lestercrest')

    RequestModel(model)
    local timeout = 0
    while not HasModelLoaded(model) and timeout < 100 do
        Wait(50)
        timeout = timeout + 1
    end

    if HasModelLoaded(model) then
        lesterPed = CreatePed(0, model, detCoords.x, detCoords.y, detCoords.z - 1.0, detCoords.w, false, false)
        SetEntityAsMissionEntity(lesterPed, true, true)
        SetEntityInvincible(lesterPed, true)
        SetBlockingOfNonTemporaryEvents(lesterPed, true)
        FreezeEntityPosition(lesterPed, true)
        SetPedKeepTask(lesterPed, true)
        SetPedDefaultComponentVariation(lesterPed)
        TaskStartScenarioInPlace(lesterPed, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)

        exports.ox_target:addLocalEntity(lesterPed, {
            {
                name = 'detonate_c4_lester',
                icon = 'fas fa-explosion',
                label = 'Detoner C4',
                distance = 2.5,
                canInteract = function()
                    return heistState == 'escaped' and allC4Done
                end,
                onSelect = function()
                    local alert = lib.alertDialog({
                        header = 'Lester - Detoner C4',
                        content = 'Lester: "Alt er klar. Skal jeg sprænge lortet?"',
                        centered = true,
                        cancel = true,
                        labels = {
                            confirm = 'DETONER!',
                            cancel = 'Vent lidt...',
                        },
                    })

                    if alert == 'confirm' then
                        TriggerServerEvent('mach1ne_sub:server:detonate')
                    end
                end,
            },
        })
    end
end

RegisterNetEvent('mach1ne_sub:client:detonateScene', function()
    -- Fjern blip
    if detonationBlip then
        RemoveBlip(detonationBlip)
        detonationBlip = nil
    end

    local playerPed = cache.ped

    -- Eksplosionsscene
    -- Kamera effekt
    local camCoords = GetEntityCoords(playerPed)
    local sceneCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(sceneCam, camCoords.x + 2.0, camCoords.y + 2.0, camCoords.z + 5.0)
    PointCamAtCoord(sceneCam, camCoords.x, camCoords.y, camCoords.z)
    SetCamActive(sceneCam, true)
    RenderScriptCams(true, true, 1000, true, false)

    FreezeEntityPosition(playerPed, true)

    Wait(1000)

    -- Spiller trykker på detonator animation
    lib.requestAnimDict('anim@heists@ornate_bank@hack')
    TaskPlayAnim(playerPed, 'anim@heists@ornate_bank@hack', 'hack_loop', 8.0, -8.0, 3000, 1, 0, false, false, false)

    Wait(2000)

    -- Massive eksplosioner rundt om spilleren (simulerer ubåden)
    local explosionCoords = {
        vector3(camCoords.x + 50.0, camCoords.y + 50.0, camCoords.z),
        vector3(camCoords.x - 30.0, camCoords.y + 40.0, camCoords.z),
        vector3(camCoords.x + 20.0, camCoords.y - 30.0, camCoords.z),
    }

    -- Skærm-rystelse
    ShakeGameplayCam('MEDIUM_EXPLOSION_SHAKE', 1.0)

    for _, expCoord in ipairs(explosionCoords) do
        AddExplosion(expCoord.x, expCoord.y, expCoord.z, 2, 50.0, true, false, 1.0, false)
        Wait(500)
    end

    -- Flash effekt
    AnimpostfxPlay('ExplosionJosh3', 0, false)

    Wait(3000)

    ClearPedTasks(playerPed)
    FreezeEntityPosition(playerPed, false)

    -- Tilbage til normal kamera
    RenderScriptCams(false, true, 1000, true, false)
    DestroyCam(sceneCam, true)

    lesterCall('BOOM! Ha! Det var noget af en eksplosion! Pengene er på vej til din konto.', 6000)
end)

-- ========================
-- HEIST COMPLETED
-- ========================
RegisterNetEvent('mach1ne_sub:client:heistCompleted', function()
    myHeistId = nil
    isLeader = false
    insideSubmarine = false
    bunkerHackDone = false
    allC4Done = false
    c4PlacedLocally = {}
    heistState = 'none'
    clearInteriorMinimap()

    if detonationBlip then
        RemoveBlip(detonationBlip)
        detonationBlip = nil
    end

    if lesterPed and DoesEntityExist(lesterPed) then
        DeleteEntity(lesterPed)
        lesterPed = nil
    end

    if kosatkaVeh and DoesEntityExist(kosatkaVeh) then
        DeleteEntity(kosatkaVeh)
        kosatkaVeh = nil
    end

    lib.notify({ type = 'success', description = 'Heistet er fuldført! Godt arbejde!' })
end)

-- ========================
-- CLEANUP
-- ========================
function cleanupSubmarine()
    guardMonitorToken = guardMonitorToken + 1

    for i, ped in pairs(guardPeds) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end
    guardPeds = {}
    submarineExitZoneCreated = false

    for i, blip in pairs(guardBlips) do
        if blip then
            RemoveBlip(blip)
        end
    end
    guardBlips = {}

    for i, prop in pairs(c4Props) do
        if DoesEntityExist(prop) then
            DeleteEntity(prop)
        end
    end
    c4Props = {}

    -- Fjern alle dynamiske ox_target zones
    for _, zoneId in ipairs(activeZones) do
        exports.ox_target:removeZone(zoneId)
    end
    activeZones = {}
end

-- ========================
-- RESOURCE CLEANUP
-- ========================
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    cleanupSubmarine()

    if heistNpcPed and DoesEntityExist(heistNpcPed) then
        DeleteEntity(heistNpcPed)
    end

    if lesterPed and DoesEntityExist(lesterPed) then
        DeleteEntity(lesterPed)
    end

    if detonationBlip then
        RemoveBlip(detonationBlip)
    end

    if kosatkaVeh and DoesEntityExist(kosatkaVeh) then
        DeleteEntity(kosatkaVeh)
    end

end)

-- ========================
-- INIT
-- ========================
CreateThread(function()
    spawnHeistNPC()
end)

CreateThread(function()
    while true do
        isPoliceCached = lib.callback.await('mach1ne_sub:server:isPolice', false) == true
        Wait(3000)
    end
end)

CreateThread(function()
    setupPoliceSubAccessTarget()
end)

CreateThread(function()
    while true do
        if activeInteriorMinimap then
            SetRadarAsInteriorThisFrame(joaat(activeInteriorMinimap.name), activeInteriorMinimap.x, activeInteriorMinimap.y, activeInteriorMinimap.floor or 0, activeInteriorMinimap.zoom or 220)
            Wait(0)
        else
            Wait(500)
        end
    end
end)
