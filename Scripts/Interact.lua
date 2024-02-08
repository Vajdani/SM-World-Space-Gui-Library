---@class Interact : ToolClass
Interact = class()

function Interact:client_onCreate()
    sm.worldgui_interact = self.tool
end

function Interact:client_onEquippedUpdate(lmb, rmb, f)
    if lmb == 1 then
        self:cl_tryUpdateButton(true)
    elseif lmb == 3 then
        self:cl_tryUpdateButton(false)
    end

    return true, true
end

function Interact:cl_tryUpdateButton(state)
    local camPos = sm.camera.getDefaultPosition()
    local dir = sm.localPlayer.getDirection()
    local hit, result = sm.physics.raycast(camPos, camPos + dir * 7.5, nil, sm.physics.filter.areaTrigger)
    if result.type == "areaTrigger" then
        local trigger = result:getAreaTrigger()
        if sm.exists(trigger) then
            local userdata = trigger:getUserData()
            if userdata and userdata.button then
                sm.worldgui.OnInteract(userdata.guiId, userdata.button, state, sm.localPlayer.getPlayer())
            end
        end
    end
end