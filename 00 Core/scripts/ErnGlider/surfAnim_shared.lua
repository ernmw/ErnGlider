---@omw-context runtime

-- ---------------------------------------------------------------------------
-- GROUP NAMES
-- ---------------------------------------------------------------------------

local GROUP = {
    -- xShieldSurfRedux1.kf
    GO        = "shieldgo",      -- ground loop, facing straight
    GO_LEFT   = "shieldgol",     -- ground loop,
    GO_RIGHT  = "shieldgor",     -- ground loop, 
    GO_STANCE = "shieldgos",     -- ground loop, modifier stance
    STANCE_L  = "shieldgosl",    -- carving left (full body)
    STANCE_R  = "shieldgosr",    -- carving right (full body)
    JUMP      = "shieldjump",    -- airborne loop; replaces vanilla jump
    DROPIN    = "shielddropin",  -- landing one-shot

    -- vanilla, arm-only overlays (as the original surf.lua used)
    ARMS_LEFT  = "sneakleft",
    ARMS_RIGHT = "sneakright",

    -- vanilla, used on exit / impact
    EXIT      = "jump",
    KNOCKDOWN = "knockdown",
}

-- Impact reactions when the surfer hits an actor. Picked at random.
local HIT_GROUPS = { "hit1", "hit2", "hit3", "hit4", "hit5" }

local SUPPRESS_GROUPS = { "runforward", "runleft", "runright" }

-- ---------------------------------------------------------------------------
-- TEXT KEY CANDIDATES
-- ---------------------------------------------------------------------------

local KEY_CANDIDATES = {
    { start = "loop start", stop = "loop stop" },
    { start = "start",      stop = "stop" },
}

-- ---------------------------------------------------------------------------
-- STANCES
-- ---------------------------------------------------------------------------
-- base    - BODY layer on the ground, not turning
-- left    - BODY (turnMode "body") or ARMS (turnMode "arms") while turning left
-- right   - as `left`
-- air     - BODY layer while airborne
-- airArms - optional ARMS layer while airborne (nil = none)
-- turnMode - "body": turning swaps the BODY loop
--            "arms": BODY stays on `base`, turning adds an ARMS overlay
-- movement - NOT read by the controller. Hook for surf.lua's onFrame to
--            vary handling per stance (see Anim.getStance()). Stub.

local STANCE_BY_NAME = {
    default = {
        base     = GROUP.GO,
        left     = GROUP.GO_LEFT,
        right    = GROUP.GO_RIGHT,
        air      = GROUP.JUMP,
        airArms  = nil,
        turnMode = "body",
        movement = { speedMod = 1.0, driftMod = 1.0 },
    },

    -- Shift held: shieldgos replaces shieldgo, turning is arm-only.
    modifier = {
        base     = GROUP.GO_STANCE,
        left     = GROUP.STANCE_L,
        right    = GROUP.STANCE_R,
        air      = GROUP.JUMP,
        airArms  = nil,
        turnMode = "body",
        movement = { speedMod = 1.0, driftMod = 1.0 },  -- STUB: e.g. 0.9 / 1.3
    },

    -- STUB -- = {
    --     base     = "shieldpop",
    --     left     = "shieldtuckl",
    --     right    = "shieldtuckr",
    --     air      = GROUP.JUMP,
    --     turnMode = "body",
    --     movement = { speedMod = 1.1, driftMod = 0.7 },
    -- },
}

local TURN_MODES = { body = true, arms = true }

local function validateStances(byName)
    for name, s in pairs(byName) do
        if type(s) ~= "table" then
            error(("[ErnGlider surfAnim] stance '%s' is %s, expected table"):format(name, type(s)))
        end
        for _, field in ipairs({ "base", "left", "right", "air" }) do
            if type(s[field]) ~= "string" then
                error(("[ErnGlider surfAnim] stance '%s' has no '%s' group"):format(name, field))
            end
            if s[field] ~= s[field]:lower() then
                error(("[ErnGlider surfAnim] stance '%s'.%s '%s' must be lowercase")
                    :format(name, field, s[field]))
            end
        end
        if not TURN_MODES[s.turnMode] then
            error(("[ErnGlider surfAnim] stance '%s' has unknown turnMode '%s'")
                :format(name, tostring(s.turnMode)))
        end
    end
    if not byName.default then
        error("[ErnGlider surfAnim] a 'default' stance is required")
    end
    return byName
end

local STANCES = validateStances(STANCE_BY_NAME)

-- ---------------------------------------------------------------------------
-- LAYER PROFILES
-- ---------------------------------------------------------------------------

---@param anim any the openmw.animation module, passed in so this file requires nothing
local function buildLayerProfiles(anim)
    local P, B = anim.PRIORITY, anim.BLEND_MASK
    return {
        BODY    = { priority = P.Hit,       blendMask = B.All,                    looping = true  },
        ONESHOT = { priority = P.Weapon,    blendMask = B.All,                    looping = false },
        ARMS    = { priority = P.Block,     blendMask = B.LeftArm + B.RightArm,   looping = true  },
        EXIT    = { priority = P.Jump,      blendMask = B.LowerBody,              looping = false },
        IMPACT  = { priority = P.Knockdown, blendMask = B.All,                    looping = false },
    }
end

-- ---------------------------------------------------------------------------
-- TUNING
-- ---------------------------------------------------------------------------

local TUNING = {
    -- Minimum seconds a ground BODY pose is held before switching to another,
    minPoseTime   = 0.5,
    -- Airborne time required before landing plays the drop-in. 0 = always.
    dropinMinAir  = 0.25,
    -- Airborne time before the ground loop gives way to shieldjump
    airGrace      = 0.1,
    -- Playback speed per group. Absent = 1.
    speed = {
        -- [GROUP.DROPIN] = 1.2,
    },
}

return {
    GROUP              = GROUP,
    HIT_GROUPS         = HIT_GROUPS,
    SUPPRESS_GROUPS    = SUPPRESS_GROUPS,
    KEY_CANDIDATES     = KEY_CANDIDATES,
    STANCES            = STANCES,
    buildLayerProfiles = buildLayerProfiles,
    TUNING             = TUNING,
}
