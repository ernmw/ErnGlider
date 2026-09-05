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
local MOD_NAME = require("scripts.ErnGlider.ns")
local core = require("openmw.core")
local pself = require("openmw.self")
local camera = require('openmw.camera')
local util = require('openmw.util')
local async = require("openmw.async")
local types = require('openmw.types')
local input = require('openmw.input')
local controls = require('openmw.interfaces').Controls
local nearby = require('openmw.nearby')
local animation = require('openmw.animation')
local interfaces = require("openmw.interfaces")
local settings = require("scripts.ErnGlider.settings")

local function warn360()
    local storage = require('openmw.storage')
    -- This is a setting group in the OMW camera script.
    -- The individual setting we're interested in is 'move360'
    local thirdPersonGroup = "SettingsOMWCameraThirdPerson"
    local move360Enabled = storage.playerSection(thirdPersonGroup):get("move360")
    if move360Enabled then
        local localization = core.l10n(MOD_NAME)
        local ui = require('openmw.ui')
        ui.showMessage(localization("move360Warning"))
    end
end
warn360()

input.registerTriggerHandler("Jump", async:callback(
    function()
        -- go back to normal movement?
        local handled = false
        if interfaces.ErnGliderGlider.isApplied() then
            interfaces.ErnGliderGlider.remove()
            handled = true
        elseif interfaces.ErnGliderSurf.isApplied() then
            interfaces.ErnGliderSurf.jump()
            handled = true
        end
        if handled then
            return
        end

        if not settings.main.enableJumpControl then
            return
        end

        -- apply special movement
        if animation.isPlaying(pself, "jump") then
            if pself.controls.movement > settings.main.deadzone then
                -- no forward movement action on purpose.
                -- people like bunny hopping.
            elseif pself.controls.movement < -1 * settings.main.deadzone then
                if settings.surf.enable then
                    interfaces.ErnGliderSurf.apply()
                end
            else
                if settings.glider.enable then
                    interfaces.ErnGliderGlider.apply()
                end
            end
        end
    end
))

return {}
