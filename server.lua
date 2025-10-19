-- server.lua
local Jobs = {} -- active jobs keyed by jobId
local jobCounter = 0

local function isPoliceJob(jobName)
    if not jobName then return false end
    for _, j in ipairs(Config.PoliceJobs or {}) do
        if string.lower(jobName) == string.lower(j) then
            return true
        end
    end
    return false
end

-- helper: get online players (server IDs)
local function serverGetPlayers()
    local p = GetPlayers() or {}
    local players = {}
    for _, id in ipairs(p) do
        table.insert(players, tonumber(id))
    end
    return players
end

-- When a player requests a job
RegisterNetEvent('ai_vehicle_jobs:requestJob', function()
    local src = source
    local job = exports['Az-Framework']:getPlayerJob(src)
    if isPoliceJob(job) then
        TriggerClientEvent('ai_vehicle_jobs:notify', src, 'You cannot take AI vehicle jobs while on duty.')
        return
    end

    jobCounter = jobCounter + 1
    local jobId = jobCounter

    -- pick random location and model
    local loc = Config.JobLocations[math.random(1, #Config.JobLocations)]
    local model = Config.VehicleModels[math.random(1, #Config.VehicleModels)]

    Jobs[jobId] = {
        src = src,
        loc = loc, -- vector4
        model = model,
        created = os.time(),
        vehicleNetId = nil,
        vehicleCoords = nil
    }

    print(("[ai_vehicle_jobs] Job %d created for src=%s model=%s loc=%s"):format(jobId, tostring(src), tostring(model), tostring(json and json.encode and json.encode(loc) or tostring(loc))))

    -- send job assignment to the requesting client (includes coords & model)
    TriggerClientEvent('ai_vehicle_jobs:jobAssigned', src, jobId, loc, model)

    -- instruct the client to spawn the target vehicle (client-side spawning)
    TriggerClientEvent('ai_vehicle_jobs:spawnTargetVehicle', src, jobId, loc, model)

    TriggerClientEvent('ai_vehicle_jobs:notify', src, 'Job assigned — waypoint set to target vehicle location. Drive there and retrieve the vehicle.')
end)

-- client informs server that it has spawned the vehicle and returns network id and coords
RegisterNetEvent('ai_vehicle_jobs:vehicleSpawned', function(jobId, vehicleNetId, vehicleCoords)
    local src = source
    local job = Jobs[jobId]
    if not job then
        print(("ai_vehicle_jobs:vehicleSpawned - no job %s from src %s"):format(tostring(jobId), tostring(src)))
        return
    end

    job.vehicleNetId = vehicleNetId
    job.vehicleCoords = vehicleCoords -- expect table {x,y,z} or vector3-like

    -- notify the owner that vehicle spawned and the server will set a waypoint to the vehicle coords (via client)
    TriggerClientEvent('ai_vehicle_jobs:vehicleSpawnedNotify', src, jobId, vehicleCoords)

    -- extra: instruct player what to do next (helps if client messages were missed)
    TriggerClientEvent('ai_vehicle_jobs:notify', src, 'Vehicle spawned. Get in it and drive it back to the NPC. Park near the NPC and use /removeparts to dismantle.')

    print(("ai_vehicle_jobs:vehicleSpawned - job %s owner %s netId %s coords %s"):format(tostring(jobId), tostring(src), tostring(vehicleNetId), tostring(json and json.encode and json.encode(vehicleCoords or {}) or tostring(vehicleCoords))))
end)

-- Client requests to begin dismantle (server authoritative check)
RegisterNetEvent('ai_vehicle_jobs:beginDismantle', function(jobId, vehNetId, playerCoords)
    local src = source
    local job = Jobs[jobId]
    if not job then
        TriggerClientEvent('ai_vehicle_jobs:cancelDismantle', src, 'No job found.')
        return
    end

    -- only the job owner may dismantle
    if job.src ~= src then
        TriggerClientEvent('ai_vehicle_jobs:cancelDismantle', src, 'You are not the owner of this job.')
        return
    end

    -- ensure not police (re-check)
    local playerJob = exports['Az-Framework']:getPlayerJob(src)
    if isPoliceJob(playerJob) then
        TriggerClientEvent('ai_vehicle_jobs:cancelDismantle', src, 'Police cannot dismantle vehicles.')
        return
    end

    -- validate vehicle network id matches server record
    if not job.vehicleNetId or tostring(job.vehicleNetId) ~= tostring(vehNetId) then
        TriggerClientEvent('ai_vehicle_jobs:cancelDismantle', src, 'Vehicle mismatch.')
        return
    end

    -- instruct client to open NUI minigame/progress (server trusts client to run it, result reported back)
    TriggerClientEvent('ai_vehicle_jobs:startMinigame', src, jobId)
end)

-- client reports minigame result
RegisterNetEvent('ai_vehicle_jobs:minigameResult', function(jobId, success, pos)
    local src = source
    local job = Jobs[jobId]
    if not job then return end

    if success then
        -- payout player
        local payout = math.random(Config.MinPayout or 400, Config.MaxPayout or 1200)
        exports['Az-Framework']:addMoney(src, payout)
        TriggerClientEvent('ai_vehicle_jobs:notify', src, ('Dismantle complete — you received $%d'):format(payout))

        -- tell the client who spawned the vehicle to delete it
        if job.vehicleNetId and job.vehicleNetId ~= nil then
            if job.src then
                TriggerClientEvent('ai_vehicle_jobs:deleteVehicle', job.src, job.vehicleNetId)
            end
        end

        -- clear waypoints / blips for the player
        TriggerClientEvent('ai_vehicle_jobs:clearJobBlips', src, jobId)

        Jobs[jobId] = nil
    else
        -- failed: alert police with blip and notification
        local alertCoords = pos or (job.loc and { x = job.loc[1], y = job.loc[2], z = job.loc[3] } or nil)

        -- get player name for message (async callback)
        exports['Az-Framework']:GetPlayerCharacterName(src, function(err, name)
            local callerName = (not err and name) and name or "Unknown"
            for _, playerId in ipairs(serverGetPlayers()) do
                local policeJob = exports['Az-Framework']:getPlayerJob(playerId)
                if isPoliceJob(policeJob) then
                    TriggerClientEvent('ai_vehicle_jobs:policeAlert', playerId, alertCoords, callerName, Config.PoliceBlipDuration or 120)
                end
            end
            TriggerClientEvent('ai_vehicle_jobs:notify', src, 'Mini-game failed! Police have been alerted.')
        end)
        -- keep the job active (allow reattempt or cancel by admin)
    end
end)

-- Admin convenience to cancel job (server console only)
RegisterCommand('aijobcancel', function(src, args)
    if src == 0 then
        local id = tonumber(args[1])
        if id and Jobs[id] then
            Jobs[id] = nil
            print("Cancelled job", id)
        end
    end
end, true)

-- Export to check active job (server-side)
exports('GetActiveJobForPlayer', function(source)
    for id, j in pairs(Jobs) do
        if j.src == source then
            return id
        end
    end
    return nil
end)

-- respond to client asking whether their job is allowed to see the NPC blip
RegisterNetEvent('ai_vehicle_jobs:checkAllowed', function()
    local src = source
    local playerJob = exports['Az-Framework']:getPlayerJob(src)
    local allowed = not isPoliceJob(playerJob)
    -- reply to that single client with boolean allowed and the job name
    TriggerClientEvent('ai_vehicle_jobs:allowedStatus', src, allowed, playerJob)
end)