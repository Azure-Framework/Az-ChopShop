-- client.lua
local activeJob = nil
local jobBlip = nil
local vehicleBlip = nil
local spawnedVehicle = nil
local pedEntity = nil
local pedModelHash = nil
local playerHasNuiOpen = false
local pedBlip = nil -- blip representing the NPC for allowed players

-- helper to show chat
local function chat(msg)
    TriggerEvent('chat:addMessage', { args = { '^2AI JOB', msg } })
end

-- create the ped at ped coords from config
Citizen.CreateThread(function()
    local pedModel = GetHashKey(Config.Ped.model)
    pedModelHash = pedModel
    RequestModel(pedModel)
    while not HasModelLoaded(pedModel) do
        Wait(10)
    end
    pedEntity = CreatePed(4, pedModel, Config.Ped.coords.x, Config.Ped.coords.y, Config.Ped.coords.z - 1.0, Config.Ped.heading, false, true)
    SetEntityAsMissionEntity(pedEntity, true, true)
    FreezeEntityPosition(pedEntity, true)
    SetBlockingOfNonTemporaryEvents(pedEntity, true)
    SetEntityInvincible(pedEntity, true)

    -- after ped is spawned client-side, ask server if this player is allowed to see the ped blip
    TriggerServerEvent('ai_vehicle_jobs:checkAllowed')
end)

-- DrawText3D util
function DrawText3D(x,y,z, text)
    local onScreen,_x,_y=World3dToScreen2d(x,y,z)
    local px,py,pz=table.unpack(GetGameplayCamCoords())
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextCentre(true)
    SetTextEntry("STRING")
    SetTextColour(255,255,255,215)
    AddTextComponentString(text)
    EndTextCommandDisplayText(_x,_y)
end

-- interaction helper (E) - simply ask server, server will validate
Citizen.CreateThread(function()
    while true do
        Wait(0)
        local ped = pedEntity
        if ped and DoesEntityExist(ped) then
            local coords = GetEntityCoords(PlayerPedId())
            local d = #(coords - Config.Ped.coords)
            if d < 2.5 then
                DrawText3D(Config.Ped.coords.x, Config.Ped.coords.y, Config.Ped.coords.z + 1.0, "[E] Talk")
                if IsControlJustReleased(0, 38) then -- E
                    -- ask server to give a job (server validates police etc)
                    TriggerServerEvent('ai_vehicle_jobs:requestJob')
                end
            end
        end
    end
end)

-- handle server reply whether this player is allowed to see NPC blip
RegisterNetEvent('ai_vehicle_jobs:allowedStatus', function(allowed, jobName)
    -- allowed = boolean
    if allowed then
        -- create ped blip if not exist
        if not pedBlip or not DoesBlipExist(pedBlip) then
            pedBlip = AddBlipForCoord(Config.Ped.coords.x, Config.Ped.coords.y, Config.Ped.coords.z)
            SetBlipSprite(pedBlip, 280) -- ped/shop icon (change if you like)
            SetBlipAsShortRange(pedBlip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString("Vehicle Jobs (NPC)")
            EndTextCommandSetBlipName(pedBlip)
        end
    else
        -- remove ped blip if exists
        if pedBlip and DoesBlipExist(pedBlip) then
            RemoveBlip(pedBlip)
            pedBlip = nil
        end
        -- optional immediate feedback
        if jobName then
            chat("You cannot take AI vehicle jobs while on duty: " .. tostring(jobName))
        end
    end
end)

-- allow players to re-check allowed status (useful when switching on/off duty)
RegisterCommand('aijobrefresh', function()
    TriggerServerEvent('ai_vehicle_jobs:checkAllowed')
    chat("Refreshing job eligibility...")
end)

-- handle a job assigned by server: create blip and set waypoint to job loc
RegisterNetEvent('ai_vehicle_jobs:jobAssigned', function(jobId, loc, model)
    activeJob = jobId
    local x, y, z = loc[1], loc[2], loc[3]
    if jobBlip and DoesBlipExist(jobBlip) then RemoveBlip(jobBlip) end
    jobBlip = AddBlipForCoord(x, y, z)
    SetBlipSprite(jobBlip, 225)
    SetBlipColour(jobBlip, 1)
    SetBlipAsShortRange(jobBlip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Target Vehicle Location")
    EndTextCommandSetBlipName(jobBlip)
    SetBlipRoute(jobBlip, true)
    SetNewWaypoint(x, y)
    chat("Job #" .. tostring(jobId) .. " assigned: go to the waypoint to retrieve the " .. tostring(model) .. ".")
end)

-- server tells client vehicle spawned (server also sends a notification)
RegisterNetEvent('ai_vehicle_jobs:vehicleSpawnedNotify', function(jobId, vehicleCoords)
    if vehicleCoords then
        local x, y, z = vehicleCoords.x or vehicleCoords[1], vehicleCoords.y or vehicleCoords[2], vehicleCoords.z or vehicleCoords[3]
        if vehicleBlip and DoesBlipExist(vehicleBlip) then RemoveBlip(vehicleBlip) end
        vehicleBlip = AddBlipForCoord(x, y, z)
        SetBlipSprite(vehicleBlip, 225)
        SetBlipColour(vehicleBlip, 5)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Target Vehicle (spawned)")
        EndTextCommandSetBlipName(vehicleBlip)
        SetBlipRoute(vehicleBlip, true)
        SetNewWaypoint(x, y)
        chat("Target vehicle spawned — waypoint set to the vehicle.")
    else
        chat("Target vehicle spawned.")
    end
end)

-- generic notification from server
RegisterNetEvent('ai_vehicle_jobs:notify', function(msg)
    chat(msg)
end)

-- clear blips for a job
RegisterNetEvent('ai_vehicle_jobs:clearJobBlips', function(jobId)
    if jobBlip and DoesBlipExist(jobBlip) then
        SetBlipRoute(jobBlip, false)
        RemoveBlip(jobBlip)
        jobBlip = nil
    end
    if vehicleBlip and DoesBlipExist(vehicleBlip) then
        SetBlipRoute(vehicleBlip, false)
        RemoveBlip(vehicleBlip)
        vehicleBlip = nil
    end
    activeJob = nil
    spawnedVehicle = nil
end)

-- Spawn the target vehicle at the job location (client does this)
RegisterNetEvent('ai_vehicle_jobs:spawnTargetVehicle', function(jobId, loc, model)
    activeJob = jobId
    local x,y,z,h = loc[1], loc[2], loc[3], loc[4]
    local modelHash = GetHashKey(model)
    RequestModel(modelHash)
    local cnt = 0
    while not HasModelLoaded(modelHash) and cnt < 100 do
        Wait(10)
        cnt = cnt + 1
    end

    -- debug: print before creation
    print(("[ai_vehicle_jobs] Client spawning vehicle model=%s at %.3f, %.3f, %.3f"):format(tostring(model), x, y, z))

    local veh = CreateVehicle(modelHash, x, y, z, h, true, false)
    if not veh or veh == 0 then
        print("[ai_vehicle_jobs] Failed to create vehicle entity")
    end

    NetworkRegisterEntityAsNetworked(veh)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    SetVehicleNumberPlateText(veh, "JOB"..tostring(math.random(1000,9999)))
    spawnedVehicle = veh
    SetEntityAsMissionEntity(veh, true, true)

    -- create a blip for the spawned vehicle (client-side immediate)
    if vehicleBlip and DoesBlipExist(vehicleBlip) then RemoveBlip(vehicleBlip) end
    vehicleBlip = AddBlipForEntity(veh)
    SetBlipSprite(vehicleBlip, 225)
    SetBlipColour(vehicleBlip, 5)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Target Vehicle")
    EndTextCommandSetBlipName(vehicleBlip)
    SetBlipRoute(vehicleBlip, true)
    local vehCoords = GetEntityCoords(veh)
    SetNewWaypoint(vehCoords.x, vehCoords.y)

    -- notify server that vehicle spawned and give network id and exact coords so server can send back a notification/waypoint
    TriggerServerEvent('ai_vehicle_jobs:vehicleSpawned', jobId, netId, { x = vehCoords.x, y = vehCoords.y, z = vehCoords.z })
    chat("Target vehicle spawned. Route set.")
end)

-- ====== NEW: monitor player entering the job vehicle and auto-advance instructions ======
Citizen.CreateThread(function()
    while true do
        Wait(500) -- half-second tick is enough
        if activeJob and spawnedVehicle and DoesEntityExist(spawnedVehicle) then
            local playerPed = PlayerPedId()
            if IsPedInAnyVehicle(playerPed, false) then
                local veh = GetVehiclePedIsUsing(playerPed)
                if veh == spawnedVehicle then
                    -- player got in the job vehicle. Remove job blip (location) and set waypoint to NPC
                    if jobBlip and DoesBlipExist(jobBlip) then
                        SetBlipRoute(jobBlip, false)
                        RemoveBlip(jobBlip)
                        jobBlip = nil
                    end
                    -- ensure vehicle blip exists but route to NPC now
                    if vehicleBlip and DoesBlipExist(vehicleBlip) then
                        RemoveBlip(vehicleBlip) -- will recreate as coord later if needed
                        vehicleBlip = nil
                    end

                    -- set waypoint to NPC
                    SetNewWaypoint(Config.Ped.coords.x, Config.Ped.coords.y)
                    chat("You're in the job vehicle. Drive it back to the NPC and park close. Use /removeparts when next to the NPC to dismantle.")

                    -- quick one-time pause to avoid repeating spam
                    Wait(3000)
                end
            end
        end
    end
end)

-- ====== proximity hint to use /removeparts when vehicle is next to ped ======
Citizen.CreateThread(function()
    while true do
        Wait(500)
        if activeJob and spawnedVehicle and DoesEntityExist(spawnedVehicle) then
            local pedCoords = Config.Ped.coords
            local vehCoords = GetEntityCoords(spawnedVehicle)
            local dist = #(vehCoords - pedCoords)
            if dist <= Config.DismantleRange then
                -- show a small prompt in chat (could be replaced with a 3D text or help text)
                chat("Vehicle is at the NPC. Exit the vehicle (or stay in it) and run /removeparts to dismantle.")
                Wait(3000) -- avoid repeating too fast
            end
        end
    end
end)

-- Delete vehicle event (server requests deletion on specific client)
RegisterNetEvent('ai_vehicle_jobs:deleteVehicle', function(netId)
    local ent = NetworkGetEntityFromNetworkId(netId)
    if DoesEntityExist(ent) then
        SetEntityAsMissionEntity(ent, true, true)
        DeleteVehicle(ent)
    end
end)

-- Command to start dismantle (client) [unchanged: existing logic will call server for validation]
RegisterCommand('removeparts', function()
    local srcPed = PlayerPedId()
    local pos = GetEntityCoords(srcPed)
    if not activeJob then
        TriggerEvent('chat:addMessage', { args = { "^1SYSTEM", "You have no active job." } })
        return
    end
    local jobId = activeJob
    if #(pos - Config.Ped.coords) > Config.DismantleRange then
        TriggerEvent('chat:addMessage', { args = { "^1SYSTEM", "You must be near the job NPC to dismantle." } })
        return
    end

    local vehicle = nil
    if IsPedInAnyVehicle(srcPed, false) then
        vehicle = GetVehiclePedIsUsing(srcPed)
    else
        for _, v in ipairs(GetGamePool('CVehicle')) do
            if DoesEntityExist(v) then
                local d = #(GetEntityCoords(v) - pos)
                if d < 6.0 then
                    vehicle = v
                    break
                end
            end
        end
    end

    if not vehicle or not DoesEntityExist(vehicle) then
        TriggerEvent('chat:addMessage', { args = { "^1SYSTEM", "No vehicle found to dismantle." } })
        return
    end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    TriggerServerEvent('ai_vehicle_jobs:beginDismantle', jobId, netId, pos)
end)

-- Server tells client to start minigame -> open NUI
RegisterNetEvent('ai_vehicle_jobs:startMinigame', function(jobId)
    SetNuiFocus(true, true)
    playerHasNuiOpen = true
    SendNUIMessage({
        action = 'startMinigame',
        settings = {
            sequenceLength = Config.Minigame.sequenceLength,
            keyTimeLimit = Config.Minigame.keyTimeLimit
        }
    })
    activeJob = jobId
    chat("Minigame started — follow the sequence.")
end)

-- Cancel dismantle (server)
RegisterNetEvent('ai_vehicle_jobs:cancelDismantle', function(reason)
    if playerHasNuiOpen then
        SendNUIMessage({ action = 'close' })
        SetNuiFocus(false, false)
        playerHasNuiOpen = false
    end
    if reason then
        TriggerEvent('chat:addMessage', { args = { "^1SYSTEM", "Dismantle canceled: "..tostring(reason) } })
    end
end)

-- Police alert: create blip on police client
RegisterNetEvent('ai_vehicle_jobs:policeAlert', function(coords, callerName, duration)
    local blip = nil
    if coords then
        blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    else
        blip = AddBlipForCoord(Config.Ped.coords.x, Config.Ped.coords.y, Config.Ped.coords.z)
    end
    SetBlipSprite(blip, 162)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 1.2)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Possible Carjack: "..(callerName or "Unknown"))
    EndTextCommandSetBlipName(blip)
    TriggerEvent('chat:addMessage', { args = { "^1ALERT", "Possible carjacking reported nearby." } })
    Citizen.CreateThread(function()
        local t0 = GetGameTimer()
        while GetGameTimer() - t0 < ((duration or 120) * 1000) do
            Wait(1000)
        end
        if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)

-- Receive minigame result from NUI
RegisterNUICallback('minigameComplete', function(data, cb)
    local success = data.success
    local pos = data.pos
    local jobId = activeJob
    SetNuiFocus(false, false)
    playerHasNuiOpen = false
    TriggerServerEvent('ai_vehicle_jobs:minigameResult', jobId, success, pos)
    cb('ok')
end)

-- allow closing NUI with ESC (NUI sends a close post to resource)
RegisterNUICallback('close', function(data, cb)
    SetNuiFocus(false, false)
    playerHasNuiOpen = false
    cb('ok')
end)

-- debug command to show active job and nearby vehicle netId
RegisterCommand('debugjob', function()
    print("client activeJob:", activeJob)
    local veh = GetVehiclePedIsUsing(PlayerPedId())
    if not veh then
        local pos = GetEntityCoords(PlayerPedId())
        for _,v in ipairs(GetGamePool('CVehicle')) do
            if #(GetEntityCoords(v) - pos) < 6.0 then veh = v; break end
        end
    end
    if veh and DoesEntityExist(veh) then
        print("veh entity:", veh, "netId:", NetworkGetNetworkIdFromEntity(veh))
    else
        print("no nearby vehicle found")
    end
end)
