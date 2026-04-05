Config = {}

-- Cooldown mellem heists (i minutter)
Config.HeistCooldown = 120

-- Maksimalt antal spillere i et heist
Config.MaxPlayers = 4

-- Penge reward per spiller
Config.MoneyReward = 1000000

-- Tilfældig penge reward per spiller (bruges hvis min/max er sat)
Config.MoneyRewardMin = 750000
Config.MoneyRewardMax = 1500000

-- Items der gives til hver spiller efter heist (ud over penge)
-- Sæt til {} for ingen items
Config.ItemRewards = {
    { item = 'weapon_pistol', count = 3 },
    { item = 'ammo', count = 150 },
    { item = 'drivingplan', count = 2 },
    -- { item = 'black_money', count = 50 },
    -- { item = 'diamond', count = 2 },
}

-- Krav for at starte heistet + forbrug under heistet
Config.RequiredTools = {
    c4Item = 'bomb_c4',
    c4Count = 3,
    hackItem = 'hackingdevice',
    hackCount = 2,
}

-- NPC der starter heistet
Config.HeistNPC = {
    model = 's_m_y_marine_03',
    coords = vector4(783.24, -3324.83, 6.45, 233.25),
}

-- Koordinat man sejler til for at entre ubåden
Config.SubmarineEntryBoat = vector3(-3177.3184, 1736.0859, 1.0)

-- Kosatka police-adgang
Config.PoliceJobName = 'police'
Config.Kosatka = {
    model = 'kosatka',
    coords = vector4(-3459.9321, 1729.9727, -6.2735, 326.9452),
}
Config.PoliceSubAccessTarget = vector4(-3443.3381, 1755.5065, 5.4862, 166.3525)

-- Doomsday bunker flow (før ubåden)
Config.BunkerEntranceOutside = vector4(-2229.5520, 2399.0674, 12.0643, 2.6281)
Config.BunkerEntranceInside = vector4(415.7448, 4844.3237, -58.9997, 91.7386)
Config.BunkerComputer = vector4(320.2443, 4874.9028, -62.5994, 27.4135)

-- Stealth/guard behaviour
Config.Stealth = {
    sightRange = 16.0,
    instantSpotRange = 8.0,
    alertOnUnsilencedShot = true,
    showGuardBlips = true,
}

-- Interior minimap support (IPL/interiors)
-- Hvis navnet ikke matcher interior-radaren, justér name/x/y/floor i config.
Config.InteriorMinimap = {
    bunker = {
        name = 'V_FakeGun',
        x = 415.7448,
        y = 4844.3237,
        floor = 0,
        zoom = 220,
    },
    submarine = {
        name = 'V_Ship',
        x = 1563.4291,
        y = 370.2016,
        floor = 0,
        zoom = 220,
    },
}

-- Militær NPC'er i bunkeren
Config.BunkerGuards = {
    { model = 's_m_y_marine_03', coords = vector4(395.8489, 4839.9492, -58.9996, 277.0400) },
    { model = 's_m_y_marine_03', coords = vector4(385.3514, 4845.4487, -62.5995, 264.0044) },
    { model = 's_m_y_marine_03', coords = vector4(335.6367, 4855.8906, -62.5995, 261.6974) },
    { model = 's_m_y_marine_03', coords = vector4(330.1851, 4869.8257, -62.5994, 234.5826) },
    { model = 's_m_y_marine_03', coords = vector4(342.2498, 4857.8623, -58.9999, 240.1601) },
    { model = 's_m_y_marine_03', coords = vector4(343.9935, 4831.8838, -58.9990, 272.5530) },
    { model = 's_m_y_marine_03', coords = vector4(352.3137, 4874.7402, -60.7936, 145.7088) },
    { model = 's_m_y_marine_03', coords = vector4(337.1437, 4867.9604, -58.9995, 206.7338) },
    { model = 's_m_y_marine_03', coords = vector4(324.4442, 4869.4648, -58.9994, 244.9887) },
    { model = 's_m_y_marine_03', coords = vector4(323.2265, 4868.2129, -62.5994, 237.7803) },
}

-- Koordinat hvor spillere spawner inde i ubåden
Config.SubmarineInterior = vector4(1563.4291, 370.2016, -49.6853, 357.0493)

-- Koordinat hvor man spawner når man forlader ubåden
Config.SubmarineExit = vector4(-3177.3184, 1736.0859, 1.0752, 277.9604)

-- Koordinat hvor man detonerer C4
Config.DetonationPoint = vector4(-1911.6111, 2071.2251, 140.3891, 8.7129)

-- Vagter inde i ubåden
Config.Guards = {
    { model = 's_m_y_marine_03', coords = vector4(1559.4088, 382.4711, -49.6855, 183.6133) },
    { model = 's_m_y_marine_03', coords = vector4(1558.8817, 393.8036, -49.6880, 176.8976) },
    { model = 's_m_y_marine_03', coords = vector4(1558.2352, 402.6921, -49.6550, 241.9517) },
    { model = 's_m_y_marine_03', coords = vector4(1561.5520, 398.6219, -56.0869, 15.1516) },
    { model = 's_m_y_marine_03', coords = vector4(1562.0784, 374.9052, -56.0885, 45.4562) },
    { model = 's_m_y_marine_03', coords = vector4(1565.0133, 420.7662, -54.1763, 163.9076) },
    { model = 's_m_y_marine_03', coords = vector4(1560.9188, 437.8850, -52.8711, 121.0305) },
}

-- Steder man skal placere C4
Config.C4Locations = {
    { coords = vector4(1557.9614, 432.2556, -53.2406, 100.3057), label = 'Placer C4 #1' },
    { coords = vector4(1560.9360, 382.0673, -49.6854, 204.7927), label = 'Placer C4 #2' },
    { coords = vector4(1560.7505, 429.1789, -56.1011, 348.9804), label = 'Placer C4 #3' },
    { coords = vector4(1557.7853, 382.3413, -53.2843, 83.8344), label = 'Hack Computer', action = 'hack' },
}

-- Guard weapon
Config.GuardWeapon = 'WEAPON_COMBATMG'

-- Discord Webhook URL til heist logs (lad stå tom for at deaktivere)
Config.DiscordWebhook = ''

-- Optional separat webhook til security logs (tom = brug DiscordWebhook)
Config.SecurityWebhook = ''

-- Anti-cheat
Config.AntiCheat = {
    LogSecurity = true,
    RateLimitMs = {
        startHeist = 1500,
        playerArrivedAtBunker = 1500,
        bunkerHackComplete = 1200,
        playerExitBunker = 1200,
        playerArrivedAtSub = 1500,
        c4Placed = 1000,
        exitSubmarine = 1200,
        detonate = 2000,
    },
    MaxDistance = {
        bunkerEntry = 60.0,
        bunkerComputer = 25.0,
        bunkerExit = 30.0,
        subEntry = 60.0,
        c4Placement = 20.0,
        subExit = 30.0,
        detonation = 40.0,
    }
}

-- Blip for detonation point
Config.DetonationBlip = {
    sprite = 436,
    colour = 1,
    scale = 0.8,
    label = 'Detoner C4',
}
