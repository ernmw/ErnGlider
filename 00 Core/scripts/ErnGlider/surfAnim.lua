---@omw-context player
--[[
    surfAnim.lua
    Animation controller for ErnGlider's shield surf.

]]--

local I         = require('openmw.interfaces')
local animation = require('openmw.animation')
local input     = require('openmw.input')
local self      = require('openmw.self')

local data      = require('scripts.ErnGlider.surfAnim_shared')

local Anim = {}

-- ==============================================
-- CONFIGURATION (data lives in surfAnim_shared.lua)
-- ==============================================
local GROUP   = data.GROUP
local STANCES = data.STANCES
local TUNING  = data.TUNING
local LAYER   = data.buildLayerProfiles(animation)

local OWNED_GROUPS = { [GROUP.DROPIN] = true }
local AIR_GROUPS = {}
for _, s in pairs(STANCES) do
    for _, field in ipairs({ "base", "left", "right", "air", "airArms" }) do
        if s[field] then OWNED_GROUPS[s[field]] = true end
    end
    AIR_GROUPS[s.air] = true
end

-- ==============================================
-- STANCE SELECTION
-- ==============================================
local function selectStance(ctx)
    if input.isShiftPressed() then
        return "modifier"
    end
    return "default"
end

-- ==============================================
-- INTERNAL STATE
-- ==============================================
local active     = false
local stanceName = "default"
local poseTime   = 0      
local airTime    = 0      


local slot = { BODY = nil, ONESHOT = nil, ARMS = nil }

-- ==============================================
-- TEXT KEY RESOLUTION
-- ==============================================
local keyCache = {}

local function resolveKeys(group)
    local cached = keyCache[group]
    if cached ~= nil then return cached end

    local result
    if animation.hasGroup and not animation.hasGroup(self, group) then
        result = false
    elseif not animation.getTextKeyTime then
        result = true
    else
        result = false
        for _, pair in ipairs(data.KEY_CANDIDATES) do
            local t = animation.getTextKeyTime(self, group .. ": " .. pair.start)
            if t and t >= 0 then
                result = pair
                break
            end
        end
    end

    if result == false then
        print(("[ErnGlider][surfAnim] '%s' missing or has no usable text keys - skipped"):format(group))
    end
    keyCache[group] = result
    return result
end

-- ==============================================
-- LOW-LEVEL HELPERS
-- ==============================================
local function play(layerName, group)
    local keys = resolveKeys(group)
    if keys == false then return false end

    local profile = LAYER[layerName]
    local looping = profile.looping
    I.AnimationController.playBlendedAnimation(group, {
        startKey    = type(keys) == "table" and keys.start or nil,
        stopKey     = type(keys) == "table" and keys.stop or nil,
        priority    = profile.priority,
        blendMask   = profile.blendMask,
        speed       = TUNING.speed[group] or 1,
        loops       = 0,
        forceLoop   = looping or nil,
        autoDisable = not looping,
    })
    return true
end

local function setSlot(layerName, group)
    local outgoing = slot[layerName]
    if outgoing == group then return end

    slot[layerName] = group
    if group and not play(layerName, group) then
        slot[layerName] = nil
    end
    if outgoing then
        animation.cancel(self, outgoing)
    end
end

local function clearSlots()
    local body, oneshot, arms = slot.BODY, slot.ONESHOT, slot.ARMS
    slot.BODY, slot.ONESHOT, slot.ARMS = nil, nil, nil
    if body    then animation.cancel(self, body)    end
    if oneshot then animation.cancel(self, oneshot) end
    if arms    then animation.cancel(self, arms)    end
end

local function reconcile()
    for name, group in pairs(slot) do
        if group and not animation.isPlaying(self, group) then
            slot[name] = nil
        end
    end
end

local function suppressLocomotion()
    for _, group in ipairs(data.SUPPRESS_GROUPS) do
        animation.cancel(self, group)
    end
end

-- ==============================================
-- PUBLIC API
-- ==============================================

-- Called from applySurf() once canApply() has passed.
function Anim.start()
    clearSlots()
    active     = true
    stanceName = "default"
    poseTime   = 0
    airTime    = 0   -- surf starts mid-jump, so the first landing drops in
end

-- Called once per onUpdate while surfing.
--   ctx.dt         frame time
--   ctx.onGround   types.Actor.isOnGround(pself)
--   ctx.justLanded true on the first grounded frame after being airborne
--   ctx.side       pself.controls.sideMovement (drift, -1..1)
--   ctx.deadzone   settings.main.deadzone
function Anim.update(ctx)
    if not active then return end
    local dt = ctx.dt or 0

    reconcile()
    suppressLocomotion()

    stanceName = selectStance(ctx)
    local stance = STANCES[stanceName] or STANCES.default

    -- ---- airborne ----------------------------------------------------------
    if not ctx.onGround then
        airTime = airTime + dt
        if airTime < TUNING.airGrace and slot.BODY and not AIR_GROUPS[slot.BODY] then
            return
        end
        if slot.BODY ~= stance.air then poseTime = 0 end
        setSlot("BODY", stance.air)
        setSlot("ARMS", stance.airArms)
        return
    end

    -- ---- landing -----------------------------------------------------------
    if ctx.justLanded and airTime >= TUNING.dropinMinAir then
        Anim.playDropIn()
    end
    airTime = 0

    -- ---- ground ------------------------------------------------------------
    local side, dz = ctx.side or 0, ctx.deadzone or 0.1
    local dir = (side <= -dz and "left") or (side >= dz and "right") or nil

    local bodyGroup, armGroup
    if stance.turnMode == "body" then
        bodyGroup = dir and stance[dir] or stance.base
    else
        bodyGroup = stance.base
        armGroup  = dir and stance[dir] or nil
    end
    if resolveKeys(bodyGroup) == false then
        bodyGroup = STANCES.default.base
    end

    poseTime = poseTime + dt
    if bodyGroup ~= slot.BODY then
        local current = slot.BODY
        local holding = current and not AIR_GROUPS[current]
                        and poseTime < TUNING.minPoseTime
        if not holding then
            setSlot("BODY", bodyGroup)
            poseTime = 0
        end
    end
    setSlot("ARMS", armGroup)
end

-- Landing one-shot. Public so surf.lua can also fire it on demand.
function Anim.playDropIn()
    if slot.ONESHOT then
        -- Restart cleanly rather than stacking a second copy.
        local outgoing = slot.ONESHOT
        slot.ONESHOT = nil
        animation.cancel(self, outgoing)
    end
    setSlot("ONESHOT", GROUP.DROPIN)
end

function Anim.stop()
    if not active then return end
    active = false
    clearSlots()

    local exit = LAYER.EXIT
    I.AnimationController.playBlendedAnimation(GROUP.EXIT, {
        priority    = exit.priority,
        blendMask   = exit.blendMask,
        autoDisable = true,
    })
end

function Anim.playImpact(hitActor)
    local group = GROUP.KNOCKDOWN
    if hitActor then
        group = data.HIT_GROUPS[math.random(#data.HIT_GROUPS)]
    end
    local impact = LAYER.IMPACT
    I.AnimationController.playBlendedAnimation(group, {
        priority    = impact.priority,
        blendMask   = impact.blendMask,
        autoDisable = true,
    })
end

function Anim.isKnockedDown()
    return animation.isPlaying(self, GROUP.KNOCKDOWN)
end

function Anim.isActive()
    return active
end

function Anim.getStance()
    return STANCES[stanceName] or STANCES.default, stanceName
end

function Anim.forceReset()
    active = false
    slot.BODY, slot.ONESHOT, slot.ARMS = nil, nil, nil
    for group in pairs(OWNED_GROUPS) do
        animation.cancel(self, group)
    end
end

function Anim.verifyGroups()
    for group in pairs(OWNED_GROUPS) do
        local keys = resolveKeys(group)
        local desc
        if keys == false then desc = "MISSING"
        elseif keys == true then desc = "present (keys not probed)"
        else desc = ("OK  %s / %s"):format(keys.start, keys.stop) end
        print(("[ErnGlider][surfAnim] %-14s %s"):format(group, desc))
    end
end

return Anim
