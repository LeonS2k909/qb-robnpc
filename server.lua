local QBCore = exports['qb-core']:GetCoreObject()
local paid = {}  -- anti-double within short window

local function keyFor(netId, vx, vy, vz)
    if netId and netId ~= 0 then return ('net:%s'):format(netId) end
    if vx and vy and vz then
        return ('pos:%.1f,%.1f,%.1f'):format(vx, vy, vz) -- coarse grid key
    end
    return ('pos:none')
end

RegisterNetEvent('npcrobbery:rob', function(netId, vx, vy, vz)
    local src = source
    local P = QBCore.Functions.GetPlayer(src); if not P then return end
    if not P.PlayerData or not P.PlayerData.job or P.PlayerData.job.name ~= 'unemployed' then return end

    local k = keyFor(netId, vx, vy, vz)
    if paid[k] then return end

    -- distance check vs coords (no ped handle required)
    local ped = GetPlayerPed(src); if ped == 0 then return end
    local me = GetEntityCoords(ped)
    local target = vector3(tonumber(vx) or me.x, tonumber(vy) or me.y, tonumber(vz) or me.z)
    if #(me - target) > 3.5 then return end

    paid[k] = true
    SetTimeout(120000, function() paid[k] = nil end) -- 2 min reuse guard

    local amount = math.random(0, 1000)
    P.Functions.AddMoney('cash', amount)

    local newCash = 0; pcall(function() newCash = P.Functions.GetMoney('cash') end)
    TriggerClientEvent('npcrobbery:client:markRobbed', src, netId or 0, amount, newCash)
end)
