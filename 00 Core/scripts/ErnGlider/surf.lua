--[[
ErnGlider for OpenMW.
Copyright (C) 2026 Erin Pentecost

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
]]
local MOD_NAME               = require("scripts.ErnGlider.ns")
local core                   = require("openmw.core")
local pself                  = require("openmw.self")
local camera                 = require('openmw.camera')
local util                   = require('openmw.util')
local aux_util               = require('openmw_aux.util')
local async                  = require("openmw.async")
local types                  = require('openmw.types')
local input                  = require('openmw.input')
local controls               = require('openmw.interfaces').Controls
local nearby                 = require('openmw.nearby')
local localization           = core.l10n(MOD_NAME)
local animation              = require('openmw.animation')
local interfaces             = require("openmw.interfaces")
local ringbuffer             = require("scripts.ErnGlider.ringbuffer")
local chimtricky             = require("scripts.ErnGlider.ui.chimtricky")
local toasts                 = require("scripts.ErnGlider.ui.toasts")
local settings               = require("scripts.ErnGlider.settings")
local blur                   = require("scripts.ErnGlider.blurshader")
local chimgates              = require("scripts.ErnGlider.chimgates")
-- All animation-group control lives here. `animation` above is kept only for
-- the shield prop (addVfx/removeVfx) and the landing poof.
local Anim                   = require("scripts.ErnGlider.surfAnim")
local ui                     = require('openmw.ui')

-- initial momentum when starting surf
local startMomentum          = 0.2
-- downward slope bonus factor
local slopeDownMomentumRatio = 0.5
-- upward slope penalty factor
local slopeUpMomentumRatio   = 0.6
-- friction per second to decay momentum by
local friction               = 0.05
-- radian threshold per second to start drifting
local driftTurnThreshold     = 0.3
-- how much yaw change contributes to side movement drift
local driftFactor            = 1.1
-- decay drift momentum by this amount per second
local driftDecay             = 0.7
-- clamp drift to this magnitude
local maxDrift               = 0.8
-- penalize momentum by this factor if drifting
local driftPenalty           = 0.005
-- if momentum drops below this, we quit surfing
local kickoutMinimumMomentum = 0.15
-- prevent surfing when fatigue is at this level.
local minFatigue             = 1
-- influence which drops don't cause damage
local safeDropHeightFactor   = 13

local pointsPerSlideSecond   = 2
local pointsPerJump          = 1
local pointsPerAirTimeSecond = 8
local maxSpeedPointsModifier = 50

local persist                = {
    applied = false,
    appliedDuration = 0,
    maxMomentumThisRun = startMomentum,
    momentum = startMomentum,
    driftMomentum = 0,
    originalForwardInput = 0,
    activeShield = nil,
    activeShieldRecord = {
        instance = nil,
        weight = 0,
        model = "",
        health = 0,
        weightFactor = 0.5,
    },
    landed = false,
    lastFootPos = nil,
    currentFootPos = nil,
    slope = 0,
    sideMovement = 0,
    startHeightOnCurrentJump = 0,
    maxHeightOnCurrentJump = 0,
    airTimeDurationOnCurrentJump = 0,
    points = {
        slidePoints = 0,
        airPoints = 0,
        jumps = 0,
        maxSpeed = 0,
    },
    gatePositions = {},
    touchedGates = {}
}

local blurShader             = blur.NewBlurShader()

local fatigueStat            = pself.type.stats.dynamic.fatigue(pself)
local surfSpell              = "eg_surf_1"

local function getSoundFilePath(file)
    return "sound\\" .. MOD_NAME .. "\\" .. file
end

local sounds         = {
    wind = getSoundFilePath("wind.mp3"),
    breath_in = getSoundFilePath("breath_in.mp3"),
    gravel_road = getSoundFilePath("gravel_road.mp3"),
    hit_wall = "Sound\\Fx\\body hit.wav",
    jump_start = "Sound\\ErnGlider\\light_smack.ogg",
    unequip = "Sound\\Fx\\FOOT\\land_lt.wav",
    landing_soft = getSoundFilePath("landing soft.wav"),
    landing_hard = getSoundFilePath("landing hard.wav")
}

local shieldBone     = "Bip01 Shieldsurf" --Bip01 Shieldsurf

local chimGateSpells = {
    "eg_surf_chim1",
    "eg_surf_chim2",
    "eg_surf_chim3",
    "eg_surf_chim4",
}

local function getBestInventoryShield()
    local best, bestCondition = nil, 0
    for _, item in ipairs(types.Actor.inventory(pself):getAll(types.Armor)) do
        if types.Armor.records[item.recordId].type == types.Armor.TYPE.Shield then
            local condition = types.Item.itemData(item).condition
            if condition and condition > 0 and condition > bestCondition and item:isValid() then
                best, bestCondition = item, condition
            end
        end
    end
    return best
end

local function getShield()
    if persist.activeShield then
        return persist.activeShield
    end

    local shield
    local leftHand = pself.type.getEquipment(pself, types.Actor.EQUIPMENT_SLOT.CarriedLeft)
    if leftHand and types.Armor.objectIsInstance(leftHand)
        and types.Armor.records[leftHand.recordId].type == types.Armor.TYPE.Shield then
        shield = leftHand
    elseif settings.surf.onlyUseEquippedShield ~= true then
        shield = getBestInventoryShield()
    end

    if not shield then
        persist.activeShield = nil
        persist.activeShieldRecord = nil
        return nil
    end

    local record = types.Armor.records[shield.recordId]
    persist.activeShield = shield
    persist.activeShieldRecord = {
        weight = record.weight,
        weightFactor = util.clamp(util.remap(record.weight, 5, 50, 0, 1), 0, 1),
        model = record.model,
        health = record.health,
    }
    return shield
end

local function applyVFX()
    if camera.getMode() ~= camera.MODE.FirstPerson then
        local shieldModel = persist.activeShieldRecord.model
        animation.addVfx(pself, shieldModel,
            { loop = true, boneName = shieldBone, vfxId = "surf", useAmbientLight = false })
    end
end

local function applySurfSpell()
    pself.type.activeSpells(pself):add({
        id = surfSpell,
        effects = { 0, 1, 2, 3 },
        ignoreResistances = true,
        ignoreSpellAbsorption = true,
        ignoreReflect = true
    })
end

local forward = util.vector3(0.0, 1.0, 0.0)

local function touchingWall()
    local pselfCenter = pself:getBoundingBox().center
    local facing = pself.rotation:apply(forward):normalize() * 70

    local castResult = nearby.castRay(pselfCenter, pselfCenter + util.vector3(facing.x, facing.y, 0), {
        collisionType = nearby.COLLISION_TYPE.AnyPhysical,
        ignore = pself
    })

    return castResult
end

local function spawnCHIMGates()
    if persist.applied and settings.surf.chimTricky then
        persist.touchedGates = {}
        core.sendGlobalEvent(MOD_NAME .. 'onSurfStart', {
            player = pself.object,
            positions = persist.gatePositions,
        })
    end
end

local function onInit(initData)
    if initData ~= nil then
        persist = initData
    end
end
local function onLoad(data)
    -- The engine may still hold a looping surf group the fresh module has no
    -- record of; release them all. Anim.update() replays if we're mid-run.
    Anim.forceReset()
    if data ~= nil then
        persist = data
    end
    if data.sideMovement == nil then
        data.sideMovement = 0
    end
    if persist.driftMomentum == nil then
        persist.driftMomentum = 0
    end
    if persist.airTimeDurationOnCurrentJump == nil then
        persist.airTimeDurationOnCurrentJump = 0
    end
    if persist.gatePositions == nil then
        persist.touchedGates = {}
        persist.gatePositions = {}
    end
    spawnCHIMGates()
end
local function onSave()
    return persist
end

local function getRecord(obj)
    return obj.type.record(obj)
end

local function canApply()
    if types.Actor.getStance(pself) ~= types.Actor.STANCE.Nothing then
        settings.debugPrint("canApply surf: spell or weapon is readied")
        return false
    end
    if types.Actor.isSwimming(pself) then
        settings.debugPrint("canApply surf: swimming")
        return false
    end
    local levitateEffect = types.Actor.activeEffects(pself):getEffect(core.magic.EFFECT_TYPE.Levitate)
    if (levitateEffect ~= nil) and (levitateEffect.magnitude > 0) then
        settings.debugPrint("canApply surf: levitating")
        return false
    end
    if not types.Player.getControlSwitch(pself, types.Player.CONTROL_SWITCH.Controls) then
        settings.debugPrint("canApply surf: no control")
        return false
    end
    local shield = getShield()
    if not shield then
        settings.debugPrint("canApply surf: no shield")
        return false
    end
    if not shield:isValid() then
        settings.debugPrint("canApply surf: shield not valid")
        return false
    end
    if types.Item.itemData(shield).condition <= 0 then
        settings.debugPrint("canApply surf: shield broken")
        ui.showMessage(localization("shieldBroke", {
            shield = getRecord(shield).name
        }))
        return false
    end
    --[[
    --- maybe this was for summoned shields?
    if not types.Player.hasEquipped(pself, shield) then
        settings.debugPrint("canApply surf: shield not equipped")
        return false
    end
    ]]
    if fatigueStat.current <= minFatigue then
        settings.debugPrint("canApply surf: min fatigue")
        return false
    end
    return true
end

local function calcPoints(wipeout)
    local total = persist.points.slidePoints +
        persist.points.airPoints +
        persist.points.jumps * pointsPerJump +
        (persist.points.maxSpeed * persist.points.maxSpeed) * maxSpeedPointsModifier +
        25 * ((#persist.touchedGates) ^ 2)

    if wipeout then
        total = total / 2
    end
    total = (math.ceil(total) * 100)
    --print("Surf points: " .. total)
    return total
end

local currentSpeed = ringbuffer.new(20)

local function removeSpells()
    local spellsToRemove = {
        [surfSpell] = true,
    }
    for _, spell in pairs(pself.type.activeSpells(pself)) do
        if spellsToRemove[spell.id] then
            pself.type.activeSpells(pself):remove(spell.activeSpellId)
        end
    end
end
local removeSpellsCallback = async:registerTimerCallback("removeSpellsCallback", removeSpells)

local function removeSurf(wipeout)
    if not persist.applied then
        return
    end
    print("Surf duration: " .. tostring(persist.appliedDuration))
    persist.applied = false
    persist.appliedDuration = 0
    persist.landed = false
    persist.activeShield = nil
    persist.activeShieldRecord = nil
    print("Removing surf...")
    -- reset movement
    persist.sideMovement = 0
    pself.controls.movement = 0
    -- todo: this will probably be bad
    pself.controls.run = false
    currentSpeed:reset()

    -- do this twice because it breaks sometimes
    removeSpells()
    async:newSimulationTimer(0.01, removeSpellsCallback)

    -- remove vfx
    animation.removeVfx(pself, "surf")
    -- remove sound
    core.sound.stopSoundFile3d(sounds.wind, pself)
    core.sound.stopSoundFile3d(sounds.gravel_road, pself)
    -- play ending sound
    core.sound.playSoundFile3d(sounds.unequip, pself, {
        volume = settings.main.volume,
        loop = false,
    })

    -- release every surf layer and play the exit jump
    Anim.stop()
    blurShader:setEnabled(false)

    calcPoints(wipeout)

    chimtricky.display(nil)

    core.sendGlobalEvent(MOD_NAME .. 'onSurfEnd', {
        player = pself.object,
    })
end

local function getFootPos()
    local box = pself:getBoundingBox()
    return box.center + util.vector3(0, 0, -box.halfSize.z)
end

local function applySurf()
    if not canApply() then
        return
    end

    persist.activeShield = nil
    persist.applied = true
    persist.momentum = startMomentum
    persist.maxMomentumThisRun = startMomentum
    persist.driftMomentum = 0
    persist.landed = false

    persist.lastFootPos = getFootPos()
    persist.currentFootPos = getFootPos()
    persist.slope = 0
    persist.startHeightOnCurrentJump = persist.lastFootPos.z
    persist.maxHeightOnCurrentJump = persist.lastFootPos.z
    persist.airTimeDurationOnCurrentJump = 0

    -- set up next run
    persist.points = {
        slidePoints = 0,
        airPoints = 0,
        jumps = 0,
        maxSpeed = 0,
    }

    print("Applying surf...")
    -- set movement on this frame
    pself.controls.movement = 1
    pself.controls.run = true
    pself.controls.sideMovement = 0
    -- apply sound
    core.sound.playSoundFile3d(sounds.wind, pself, {
        volume = settings.main.volume * 0.3,
        loop = true,
    })
    core.sound.playSoundFile3d(sounds.breath_in, pself, {
        volume = settings.main.volume,
    })

    if camera.getMode() ~= camera.MODE.Static then
        blurShader:setEnabled(true)
    end


    -- make more gates
    persist.gatePositions = chimgates.getAllGatePositions()
    settings.debugPrint("Spawned " .. tostring(#persist.gatePositions) .. " CHIM gates.")
    spawnCHIMGates()

    Anim.start()

    -- todo: unequip then re-equip shield?
    -- maybe just override the shield vfx for sheath mod somehow?
end

local function onHit(victimActor)
    -- victimActor is nil or a target actor that was run into.
    core.sound.playSoundFile3d(sounds.hit_wall, pself, {
        volume = settings.main.volume,
    })
    settings.debugPrint("hit something")
    removeSurf(true)
    Anim.playImpact(victimActor)

    if victimActor then
        victimActor:sendEvent(MOD_NAME .. 'onHitByGlider', {
            glider = pself,
            victim = victimActor,
        })
        if types.NPC.objectIsInstance(victimActor) then
            core.sendGlobalEvent(MOD_NAME .. 'onHitByGlider', {
                glider = pself,
                victim = victimActor,
            })
        end
    end
end

local function slideSound()
    if types.Actor.isOnGround(pself) then
        -- restart sound if not playing
        if not core.sound.isSoundFilePlaying(sounds.gravel_road, pself) then
            local vol = settings.main.volume * persist.momentum * .7
            --settings.debugPrint("gravel sound volume: " .. tostring(vol))
            core.sound.playSoundFile3d(sounds.gravel_road, pself, {
                volume = vol,
                loop = false,
            })
        end
    else
        -- ensure off if in air
        core.sound.stopSoundFile3d(sounds.gravel_road, pself)
    end
end

local function onJump()
    -- we're doing an intentional jump
    settings.debugPrint("intentional jump")
    if not types.Actor.isOnGround(pself) then
        removeSurf()
        return
    end
    persist.points.jumps = persist.points.jumps + 1
    core.sound.playSoundFile3d(sounds.jump_start, pself, {
        volume = settings.main.volume,
        loop = false,
    })
end

local function hitGate()
    for i, gatePos in pairs(persist.gatePositions) do
        if not persist.touchedGates[i] then
            if (pself.position - gatePos):length2() < 200 * 200 then
                persist.touchedGates[i] = true
                return i
            end
        end
    end
    return nil
end

local conditionDebt = 1
local rayCastDelay = 0

local function onUpdate(dt)
    if dt == 0 then return end
    if persist.applied then
        local newToasts = {}

        if not settings.surf.enable then
            removeSurf()
            return
        end
        if not canApply() then
            removeSurf()
            return
        end
        -- did we hit the ground too hard?
        if Anim.isKnockedDown() then
            settings.debugPrint("fell from too high!")
            removeSurf()
            -- Was missing: without it the rest of this frame ran with
            -- activeShieldRecord already nil'd by removeSurf().
            return
        end

        if persist.landed and (persist.momentum <= kickoutMinimumMomentum) then
            settings.debugPrint("out of momentum")
            removeSurf()
            return
        end

        local justLanded = false
        local justJumped = false
        local bigDrop = false
        if types.Actor.isOnGround(pself) then
            if not persist.landed then
                justLanded = true
            end
            persist.landed = true
            -- apply spell
            applySurfSpell()
        else
            if persist.landed then
                justJumped = true
            end
            persist.landed = false
        end

        if justJumped then
            persist.startHeightOnCurrentJump = getFootPos().z
            persist.maxHeightOnCurrentJump = persist.startHeightOnCurrentJump
            persist.airTimeDurationOnCurrentJump = 0
        end

        -- track landing
        if justLanded then
            persist.landed = true
            settings.debugPrint("Landed!")
            local rawDropHeight = persist.maxHeightOnCurrentJump - persist.currentFootPos.z
            local dropHeight = rawDropHeight / pself:getBoundingBox().halfSize.z
            local acrobatics = pself.type.stats.skills.acrobatics(pself).modified
            -- heavy shields have a shorter safe height
            local safeHeight = 1 + safeDropHeightFactor * util.clamp(util.remap(acrobatics, 0, 100, 0.5, 1) *
                (1 - persist.activeShieldRecord.weightFactor / 2), 0.5, 1)
            local toastColor = "positive"
            if dropHeight > 0 and dropHeight > safeHeight then
                -- damage is percentage based
                local damage = math.ceil(math.sqrt((dropHeight - safeHeight)) * settings.surf.fallCost)
                conditionDebt = conditionDebt + (damage * persist.activeShieldRecord.health / 100)
                settings.debugPrint("Big drop! Height: " ..
                    tostring(dropHeight) .. ", damage: " .. tostring(damage) .. ", safe: " .. tostring(safeHeight))
                -- play hard landing sound
                core.sound.playSoundFile3d(sounds.landing_hard, pself, {
                    volume = settings.main.volume,
                    loop = false,
                })
                toastColor = "negative"
                bigDrop = true
            else
                settings.debugPrint("Small drop of height " .. tostring(dropHeight))
                -- play softer landing sound
                core.sound.playSoundFile3d(sounds.landing_soft, pself, {
                    volume = settings.main.volume,
                    loop = false,
                })
            end
            if rawDropHeight > 70 * 3 then
                local dropToast = toasts.newTextToast(localization("dropToast",
                        { height = math.floor(rawDropHeight / 70) }),
                    toastColor)
                table.insert(newToasts, dropToast)
            end
            if persist.airTimeDurationOnCurrentJump > 1 then
                local airToast = toasts.newTextToast(localization("airToast",
                        { duration = string.format("%.1f", persist.airTimeDurationOnCurrentJump) }),
                    "positive")
                table.insert(newToasts, airToast)
            end
            animation.addVfx(pself, "meshes/ernglider/poof.nif",
                { loop = false, boneName = "Bip01 L Foot", vfxId = "poof", useAmbientLight = false })
        elseif not persist.landed then
            -- in air
            persist.maxHeightOnCurrentJump = math.max(persist.maxHeightOnCurrentJump, persist.currentFootPos.z)
            persist.airTimeDurationOnCurrentJump = persist.airTimeDurationOnCurrentJump + dt
        end

        -- update gravel sound
        slideSound()
        -- handle animations
        Anim.update({
            dt         = dt,
            onGround   = persist.landed,
            justLanded = justLanded,
            side       = pself.controls.sideMovement,
            deadzone   = settings.main.deadzone,
            bigDrop    = bigDrop,
            fastStance = persist.originalForwardInput > settings.main.deadzone
        })
        -- shield prop: the old animate() re-applied it on grounded frames only
        if persist.landed then
            applyVFX()
        end

        -- roll over foot positions
        persist.lastFootPos = persist.currentFootPos
        persist.currentFootPos = getFootPos()

        local footTravelVec = util.vector2(persist.currentFootPos.x - persist.lastFootPos.x,
            persist.currentFootPos.y - persist.lastFootPos.y)

        local facingVec3 = pself.rotation:apply(forward):normalize()
        local facingVec2 = util.vector2(facingVec3.x, facingVec3.y)
        local travelDot = 0
        local xyDist = footTravelVec:length()
        if xyDist > 0 then
            travelDot = facingVec2:dot(footTravelVec:normalize())
        end
        --[[print("facing (" .. string.format("%.2f", facingVec2.x) .. ", " .. string.format("%.2f", facingVec2.y) .. ")" ..
            "foot (" ..
            string.format("%.2f", footTravelVec.x) .. ", " .. string.format("%.2f", footTravelVec.y) .. ")" ..
            "dot (" .. string.format("%.2f", travelDot) .. ")")]]


        if (travelDot < 0 and types.Actor.isOnGround(pself)) or xyDist == 0 then
            -- we are moving backwards!
            -- keep slope neutral since we might be bouncing against a wall.
            -- friction or min speed kickout will eventually exit surf
            -- if we stay backwards
            --settings.debugPrint("Backwards!")
            currentSpeed:push(0)
            persist.slope = 0
        else
            -- game unit / second to km / hour factor is 0.05112
            currentSpeed:push((xyDist / dt) * 0.05112)
            persist.slope = travelDot * (persist.currentFootPos.z - persist.lastFootPos.z) / xyDist
        end

        -- only remove whole units of condition
        conditionDebt = conditionDebt + (settings.surf.conditionCost * dt)
        if conditionDebt > 1 then
            local whole = math.floor(conditionDebt)
            conditionDebt = math.max(0, conditionDebt - whole)
            core.sendGlobalEvent(MOD_NAME .. 'onDamageItem', {
                item = getShield(),
                amount = whole,
            })
        end
        -- do this check less frequently
        rayCastDelay = rayCastDelay + dt
        if rayCastDelay > 0.3 then
            --[[settings.debugPrint("momentum: " ..
                string.format("%.2f", persist.momentum) ..
                ", slope: " ..
                string.format("%.2f", persist.slope) .. ", side:" .. string.format("%.2f", persist.sideMovement))]]
            local touchResult = touchingWall()
            if touchResult.hit then
                local actor = nil
                if touchResult.hitObject and types.Actor.objectIsInstance(touchResult.hitObject) then
                    actor = touchResult.hitObject
                end
                onHit(actor)
                return
            end
        end
        -- track duration of surf
        persist.appliedDuration = persist.appliedDuration + dt

        -- speed-related stuff
        local avgSpeed = currentSpeed:getAverage()
        local blurStrength = util.remap(avgSpeed, 15, 200, 0, 1)
        blurShader:update(util.clamp(blurStrength * blurStrength, 0, 0.005))

        -- max speed toast
        if persist.momentum > persist.maxMomentumThisRun then
            persist.maxMomentumThisRun = persist.momentum
            if persist.maxMomentumThisRun >= 1 then
                local momentumToast = toasts.newTextToast(localization("momentumToast"),
                    "positive")
                table.insert(newToasts, momentumToast)
            end
        end

        -- check if we are close to CHIM gates
        if settings.surf.chimTricky then
            local gate = hitGate()
            if gate then
                settings.debugPrint("touched gate " .. tostring(gate))
                persist.momentum = math.max(persist.momentum, startMomentum)
                pself.type.activeSpells(pself):add({
                    id = chimGateSpells[gate],
                    effects = { 0 },
                    ignoreResistances = true,
                    ignoreSpellAbsorption = true,
                    ignoreReflect = true
                })
                local gateToast = toasts.newTextToast(localization("gate_" .. tostring(gate)),
                    "magic")
                table.insert(newToasts, gateToast)
            end
        end

        chimtricky.display({
            dt = dt,
            speed = avgSpeed,
            conditionRatio = types.Item.itemData(getShield()).condition / persist.activeShieldRecord.health,
            fatigueRatio = fatigueStat.current / fatigueStat.base,
            momentumRatio = util.remap(persist.momentum, kickoutMinimumMomentum, 1, 0, 1),
            points = calcPoints(false),
            newToasts = newToasts,
        })
    else
        -- not currently surfing
        conditionDebt = 1
    end
end

local function quadraticEaseOut(x)
    return 1 - (1 - x) * (1 - x)
end

local function sineEaseIn(x)
    return 1 - math.cos((x * math.pi) / 2)
end

local function slopeMomentumFactor(slope)
    slope = util.clamp(slope, -1, 1)
    -- heavy shields speed up and slow down slower.
    if slope > 0 then
        -- sine ease-in when going uphill
        return slopeUpMomentumRatio * sineEaseIn(slope) *
            util.clamp((1 - persist.activeShieldRecord.weightFactor / 2), 0.5, 1)
    else
        -- quadratic ease-out when going downhill
        return slopeDownMomentumRatio * quadraticEaseOut(slope) *
            util.clamp((1 - persist.activeShieldRecord.weightFactor / 4), 0.75, 1)
    end
end

local function onFrame(dt)
    if persist.applied then
        -- only adjust momenum while on ground
        if persist.landed then
            persist.momentum = util.clamp(persist.momentum - (friction + slopeMomentumFactor(persist.slope)) * dt,
                0,
                1)
            if persist.momentum > 1.5 * kickoutMinimumMomentum then
                persist.points.slidePoints = persist.points.slidePoints +
                    pointsPerSlideSecond * dt * persist.momentum * persist.momentum
            end
        else
            if persist.momentum > 1.2 * kickoutMinimumMomentum then
                persist.points.airPoints = persist.points.airPoints +
                    pointsPerAirTimeSecond * dt * persist.momentum * persist.momentum
            end
        end

        persist.originalForwardInput = pself.controls.movement

        -- Don't give direct control over strafing.
        -- If the camera swings too much, automatically mix in strafing.
        local startingYaw = pself.controls.yawChange
        if math.abs(startingYaw) < (driftTurnThreshold * dt) then
            startingYaw = 0
        elseif startingYaw < 0 then
            startingYaw = startingYaw + (driftTurnThreshold * dt)
        elseif startingYaw > 0 then
            startingYaw = startingYaw - (driftTurnThreshold * dt)
        end
        persist.driftMomentum = persist.driftMomentum + startingYaw * driftFactor
        if persist.driftMomentum > 0 then
            persist.driftMomentum = persist.driftMomentum - driftDecay * dt
            if persist.driftMomentum < 0 then
                persist.driftMomentum = 0
            end
        else
            persist.driftMomentum = persist.driftMomentum + driftDecay * dt
            if persist.driftMomentum > 0 then
                persist.driftMomentum = 0
            end
        end
        persist.driftMomentum = util.clamp(persist.driftMomentum, -maxDrift, maxDrift)

        -- penalize momentum if drifting
        -- lighter shields are penalized less
        persist.momentum = util.clamp(
            persist.momentum -
            math.abs(persist.driftMomentum) * util.clamp((1 - persist.activeShieldRecord.weightFactor / 2), 0.5, 1) *
            driftPenalty, 0, 1)

        persist.sideMovement = persist.driftMomentum

        local maxSpeedMod = util.remap(persist.activeShieldRecord.weightFactor, 0, 1, 0.92, 1)

        --settings.debugPrint("sidemovement: " .. tostring(persist.sideMovement))
        pself.controls.sideMovement = persist.sideMovement * maxSpeedMod
        pself.controls.movement = util.clamp(
            persist.momentum - math.abs(persist.sideMovement), 0, 1) * maxSpeedMod
        pself.controls.run = true
    end
end

return {
    interfaceName = MOD_NAME .. "Surf",
    interface = {
        version = 1,
        isApplied = function()
            return persist.applied
        end,
        remove = removeSurf,
        jump = onJump,
        apply = applySurf,
    },
    engineHandlers = {
        onInit = onInit,
        onLoad = onLoad,
        onSave = onSave,
        onUpdate = onUpdate,
        onFrame = onFrame
    }
}
