-- qb-npcrobbery | client.lua

local QBCore = exports['qb-core']:GetCoreObject()

-- ===== Config fallbacks (override via config.lua if present) =====
local SURRENDER_RANGE = Config.SurrenderRange or 15.0
local REQUIRE_GUN     = (Config.RequireGun ~= false)
local ROB_DIST        = Config.RobDistance or 2.0
local ROB_TIME        = Config.RobTime or 4500
local TIMEOUT_MS      = Config.SurrenderTimeout or 120000
local PED_CD_MS       = Config.PedCooldown or 900000
local BLOCK_VEHICLE   = (Config.BlockIfInVehicle ~= false)
local AGGRO_CHANCE    = 0.50 -- 50% attack with a weapon, 50% surrender

local KNIVES = Config.Knives or { `WEAPON_KNIFE`, `WEAPON_SWITCHBLADE`, `WEAPON_BOTTLE` }
local GUNS   = Config.Guns   or { `WEAPON_PISTOL`, `WEAPON_COMBATPISTOL`, `WEAPON_SNSPISTOL` }

-- ===== State =====
local surrendered, robbed, cooldown, expiry, hostile = {}, {}, {}, {}, {}
local currentJob = "unemployed"

-- ===== Relationships (hostiles hate player) =====
AddRelationshipGroup('NPC_ROBBER')
SetRelationshipBetweenGroups(5, `NPC_ROBBER`, `PLAYER`)
SetRelationshipBetweenGroups(5, `PLAYER`, `NPC_ROBBER`)

-- ===== Job tracking (only unemployed can rob) =====
local function refreshJob()
    local d = QBCore.Functions.GetPlayerData()
    currentJob = (d and d.job and d.job.name) or currentJob or "unemployed"
end
AddEventHandler('QBCore:Client:OnPlayerLoaded', refreshJob)
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job) currentJob = job and job.name or currentJob end)
CreateThread(function() while not LocalPlayer.state.isLoggedIn do Wait(200) end; refreshJob() end)
local function IsRobberAllowed() return currentJob == "unemployed" end

-- ===== Helpers =====
local function IsValidTarget(ped)
    if not DoesEntityExist(ped) then return false end
    if IsPedAPlayer(ped) then return false end
    if IsEntityDead(ped) then return false end
    if not IsPedHuman(ped) then return false end
    if BLOCK_VEHICLE and IsPedInAnyVehicle(ped, false) then return false end
    local model = GetEntityModel(ped)
    if Config.BlockedModels then for _, h in ipairs(Config.BlockedModels) do if model == h then return false end end end
    local now = GetGameTimer()
    if cooldown[model] and now < cooldown[model] then return false end
    return true
end

local function cleanupPed(ped)
    if not DoesEntityExist(ped) then return end
    exports['qb-target']:RemoveTargetEntity(ped)
    FreezeEntityPosition(ped, false)
    ClearPedTasksImmediately(ped)
    SetBlockingOfNonTemporaryEvents(ped, false)
    surrendered[ped], hostile[ped], expiry[ped] = nil, nil, nil
end

local function addTargetForPed(ped)
    exports['qb-target']:RemoveTargetEntity(ped)
    exports['qb-target']:AddTargetEntity(ped, {
        options = {{
            icon = 'fas fa-sack-dollar',
            label = 'Rob',
            action = function(ent)
                if not IsRobberAllowed() then QBCore.Functions.Notify('Not allowed in this job', 'error', 2000); return end
                local p = type(ent) == 'number' and ent or (ent and ent.entity) or ped
                if not DoesEntityExist(p) or hostile[p] or robbed[p] or not surrendered[p] then return end
                if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(p)) > (ROB_DIST + 0.2) then
                    QBCore.Functions.Notify('Too far', 'error', 2000); return
                end
                local dict = 'amb@prop_human_bum_bin@base'
                RequestAnimDict(dict); while not HasAnimDictLoaded(dict) do Wait(0) end
                TaskPlayAnim(PlayerPedId(), dict, 'base', 2.0, 2.0, ROB_TIME, 1, 0.0, false, false, false)
                QBCore.Functions.Progressbar('rob_npc', 'Searching...', ROB_TIME, false, true,
                    { disableMovement = true, disableCarMovement = true, disableCombat = true }, {}, {}, {},
                    function()
                        ClearPedTasks(PlayerPedId())
                        local netId = NetworkGetNetworkIdFromEntity(p) or 0
                        local pc = GetEntityCoords(p)
                        TriggerServerEvent('npcrobbery:rob', netId, pc.x, pc.y, pc.z) -- send coords + optional netId
                    end,
                    function()
                        ClearPedTasks(PlayerPedId())
                        QBCore.Functions.Notify('Cancelled', 'error', 2000)
                    end
                )
            end,
            canInteract = function(ent, dist)
                if not IsRobberAllowed() then return false end
                local e = type(ent) == 'number' and ent or (ent and ent.entity)
                return e and DoesEntityExist(e) and surrendered[e] and not hostile[e] and not robbed[e] and dist <= ROB_DIST
            end
        }},
        distance = ROB_DIST
    })
end

-- ===== Behaviours =====
local function MakeHostile(ped, attacker)
    hostile[ped] = true
    surrendered[ped] = nil
    exports['qb-target']:RemoveTargetEntity(ped)

    FreezeEntityPosition(ped, false)
    ClearPedTasksImmediately(ped)

    SetPedRelationshipGroupHash(ped, `NPC_ROBBER`)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedConfigFlag(ped, 281, true)
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAttributes(ped, 5, true)
    SetPedCombatMovement(ped, 2)
    SetPedCombatRange(ped, 2)
    SetPedHearingRange(ped, 60.0)
    SetPedSeeingRange(ped, 60.0)
    SetPedAlertness(ped, 3)

    local useKnife = (math.random(1, 100) <= 50)
    local weap = useKnife and KNIVES[math.random(1, #KNIVES)] or GUNS[math.random(1, #GUNS)]
    RemoveAllPedWeapons(ped, true)
    GiveWeaponToPed(ped, weap, useKnife and 0 or 120, false, true)
    SetCurrentPedWeapon(ped, weap, true)
    SetPedDropsWeaponsWhenDead(ped, false)
    SetPedAccuracy(ped, useKnife and 15 or 45)

    TaskCombatPed(ped, attacker, 0, 16)
    SetPedKeepTask(ped, true)

    cooldown[GetEntityModel(ped)] = GetGameTimer() + PED_CD_MS
end

local function HandsUp(ped, holder)
    if surrendered[ped] or hostile[ped] then return end
    surrendered[ped] = true

    SetEntityAsMissionEntity(ped, true, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, false)
    RemoveAllPedWeapons(ped, true)

    FreezeEntityPosition(ped, true)
    TaskHandsUp(ped, -1, holder or 0, -1, true)

    addTargetForPed(ped)

    expiry[ped] = GetGameTimer() + TIMEOUT_MS
    CreateThread(function()
        local thisPed, endAt = ped, expiry[ped]
        while DoesEntityExist(thisPed) and not robbed[thisPed] and not hostile[thisPed] and expiry[thisPed] == endAt and GetGameTimer() < endAt do
            Wait(500)
        end
        if DoesEntityExist(thisPed) and not robbed[thisPed] and not hostile[thisPed] then
            exports['qb-target']:RemoveTargetEntity(thisPed)
            FreezeEntityPosition(thisPed, false)
            ClearPedTasksImmediately(thisPed)
            SetBlockingOfNonTemporaryEvents(thisPed, false)
            TaskSmartFleePed(thisPed, PlayerPedId(), 100.0, -1)
            SetPedKeepTask(thisPed, true)
            surrendered[thisPed], expiry[thisPed] = nil, nil
        end
    end)
end

-- ===== Aim detection (only unemployed triggers) =====
CreateThread(function()
    while true do
        local sleep = 400
        if IsRobberAllowed() then
            local me = PlayerPedId()
            if (not REQUIRE_GUN or IsPedArmed(me, 4)) and IsPlayerFreeAiming(PlayerId()) then
                local ok, ent = GetEntityPlayerIsFreeAimingAt(PlayerId())
                if ok and ent and IsEntityAPed(ent) and IsValidTarget(ent) then
                    if #(GetEntityCoords(me) - GetEntityCoords(ent)) <= SURRENDER_RANGE and HasEntityClearLosToEntity(me, ent, 17) then
                        sleep = 0
                        if not surrendered[ent] and not hostile[ent] then
                            if math.random() < AGGRO_CHANCE then
                                MakeHostile(ent, me)
                            else
                                HandsUp(ent, me)
                            end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- ===== Robbery complete -> release and flee =====
RegisterNetEvent('npcrobbery:client:markRobbed', function(netId, reward, newCash)
    local ped = NetworkGetEntityFromNetworkId(netId)
    if DoesEntityExist(ped) then
        robbed[ped], surrendered[ped], hostile[ped], expiry[ped] = true, nil, nil, nil
        exports['qb-target']:RemoveTargetEntity(ped)
        FreezeEntityPosition(ped, false)
        SetBlockingOfNonTemporaryEvents(ped, false)
        ClearPedTasksImmediately(ped)
        ResetPedMovementClipset(ped, 0.0)
        TaskReactAndFleePed(ped, PlayerPedId())
        SetPedKeepTask(ped, true)
        cooldown[GetEntityModel(ped)] = GetGameTimer() + PED_CD_MS
    end
    QBCore.Functions.Notify(('Took $%d | Cash: $%d'):format(tonumber(reward) or 0, tonumber(newCash) or 0), 'success', 3500)
end)

-- ===== Cleanup =====
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for ped in pairs(surrendered) do if DoesEntityExist(ped) then cleanupPed(ped) end end
    for ped in pairs(hostile)    do if DoesEntityExist(ped) then cleanupPed(ped) end end
end)
