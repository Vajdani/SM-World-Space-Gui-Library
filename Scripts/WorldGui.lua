local vec3 = sm.vec3.new
local quat_zero = sm.quat.identity()
local baseWidgetScale = sm.vec3.one() * 0.25
local guiScaleMultiplier = 0.25 * 0.01
local guiScaleMultiplier_half = guiScaleMultiplier * 0.5

---@param gui WorldGuiInterface
---@param widgetName string
local function CalculateZIndex(gui, widgetName)
    local widget = gui.widgets[widgetName]
    local index = 0
    while (widget.parent ~= nil) do
        index = index + 1
        widget = gui.widgets[widget.parent]
    end

    return index
end

---@param gui WorldGuiInterface
---@param widgetName string
---@param customTrans? WorldGuiTransform
local function CalculateTransform(gui, widgetName, customTrans)
    local widget = gui.widgets[widgetName]
    local transform = shallowcopy(customTrans or widget.transform)
    while (widget.parent ~= nil) do
        local parent = widget.parent
        local parentTransform = gui.widgets[parent].transform
        local parentRot = parentTransform.rotation

        local newPos = (parentRot * vec3(transform.pos_x, 0, transform.pos_y) + vec3(parentTransform.pos_x, 0, parentTransform.pos_y))
        transform.pos_x = newPos.x
        transform.pos_y = newPos.z

        transform.rotation = parentRot * transform.rotation

        widget = gui.widgets[parent]
    end

    return transform
end

local function OnUnHoverButton(self)
    local button = self.hoverWidget:getUserData().button
    local widget = self.widgets[button]
    if widget.data.isPressed then
        WorldGui.OnInteract(self.id, button, false)
    end

    widget.effect:setParameter("color", sm.color.new(WorldGui.skins[widget.skin].colour))
    self.hoverWidget = nil

    sm.tool.forceTool(nil)
end



WorldGui = {}
WorldGui.activeLayouts = {}
WorldGui.skins = {
    TransparentBG = {
        uuid = "5f41af56-df4c-4837-9b3c-10781335757f",
        colour = "#e4f8ff"
    },
    Red = {
        uuid = "027bd4ec-b16d-47d2-8756-e18dc2af3eb6",
        colour = "#820a0a",
        hoverColour = "#aa0a0a",
        pressColour = "ff0a0a"
    },
    Orange = {
        uuid = "027bd4ec-b16d-47d2-8756-e18dc2af3eb6",
        colour = "#df7f00",
        hoverColour = "#ff8f00",
        pressColour = "ffaf00"
    },
    Blue = {
        uuid = "027bd4ec-b16d-47d2-8756-e18dc2af3eb6",
        colour = "#0000ff"
    },
    White = {
        uuid = "027bd4ec-b16d-47d2-8756-e18dc2af3eb6",
        colour = "#ffffff"
    },
    Black = {
        uuid = "027bd4ec-b16d-47d2-8756-e18dc2af3eb6",
        colour = "#000000"
    }
}

--https://math.stackexchange.com/a/1905794
---@param A Vec3 The point
---@param B Vec3 First point of the line
---@param C Vec3 Second point of the line
---@return Vec3
local function DistanceToPointFromLine(A, B, C)
    local d = (C - B):normalize()
    local v = A - B
    local t = v:dot(d)
    local P = B + d * t

    local dir = A - P--; dir.z = 0
    return dir
end

WorldGui.widgetTypeCallbacks = {
    slider = {
        ---@param gui WorldGuiInterface
        ---@param name string
        ---@param data WorldGuiWidget
        create = function(gui, name, data, widgetData, position, rotation)
            widgetData.sliderFraction = widgetData.sliderFraction or 1
            widgetData.isFlipped = widgetData.isFlipped or false
            widgetData.callbacks = { { obj = widgetData, callback = "OnClick" } }
            widgetData.isPressed = false
            widgetData.isInteractable = true
            widgetData.trigger = sm.areaTrigger.createBox(
                vec3(data.transform.scale_x, 1, data.transform.scale_y) * guiScaleMultiplier_half,
                position, rotation, 0,
                {
                    button = name,
                    guiId = gui.id
                }
            )

            function widgetData:OnClick(widgetName, state, player)
                self.player = state and player or nil
            end
        end,
        update = function(gui, name, data, scale, result)
            local widgetData = data.data
            if widgetData.player and result.type == "areaTrigger" then
                local transform = data.transform
                local maxRange = widgetData.maxRange
                local pos_x = transform.pos_x + (widgetData.isFlipped and maxRange or -maxRange) * 0.5
                local up = CalculateTransform(gui, name, { pos_x = pos_x, pos_y = transform.pos_y + transform.scale_y * 0.5, scale_x = 0, scale_y = 0, rotation = transform.rotation })
                local down = CalculateTransform(gui, name, { pos_x = pos_x, pos_y = transform.pos_y - transform.scale_y * 0.5, scale_x = 0, scale_y = 0, rotation = transform.rotation })
                local realPos_up = gui.position + gui.rotation * vec3(up.pos_x, data.zIndex, up.pos_y) * guiScaleMultiplier * scale
                local realPos_down = gui.position + gui.rotation * vec3(down.pos_x, data.zIndex, down.pos_y) * guiScaleMultiplier * scale
                local distance = DistanceToPointFromLine(result.pointWorld, realPos_up, realPos_down)

                widgetData.sliderFraction = sm.util.clamp(distance:length() * 400 / maxRange * (1 / scale), 0, 1)
            end
        end,
        recalculateTransform = function(gui, name, data, position, rotation, scale, effect, transform)
            local widgetData = data.data
            local width = sm.util.lerp(0, widgetData.maxRange, widgetData.sliderFraction)
            local newTransform = CalculateTransform(
                gui, name, { pos_x = transform.pos_x + (widgetData.isFlipped and (-width + widgetData.maxRange) or (width - widgetData.maxRange)) * 0.5,
                pos_y = transform.pos_y, scale_x = width, scale_y = transform.scale_y, rotation = transform.rotation }
            )

            transform.scale_x = width

            effect:setPosition(position + rotation * vec3(newTransform.pos_x, data.zIndex, newTransform.pos_y) * guiScaleMultiplier * scale)
            effect:setRotation(rotation * newTransform.rotation)
            effect:setScale(baseWidgetScale * vec3(width, 1, transform.scale_y) * 0.01 * scale)

            local trigger = widgetData.trigger --[[@as AreaTrigger]]
            local triggerTransform = CalculateTransform(gui, name, { pos_x = transform.pos_x, pos_y = transform.pos_y, scale_x = width, scale_y = transform.scale_y, rotation = transform.rotation })
            trigger:setWorldPosition(position + rotation * vec3(triggerTransform.pos_x, data.zIndex, triggerTransform.pos_y) * guiScaleMultiplier * scale)
            trigger:setWorldRotation(rotation * triggerTransform.rotation)
            trigger:setSize(baseWidgetScale * vec3(widgetData.maxRange, 1, transform.scale_y) * 0.01 * 0.5 * scale)
        end,
        ---@param gui WorldGuiInterface
        ---@param name string
        ---@param data WorldGuiWidget
        destroy = function(gui, name, data)
            sm.areaTrigger.destroy(data.data.trigger)
        end,
        ---@param gui WorldGuiInterface
        ---@param name string
        ---@param data WorldGuiWidget
        interactionText = function(gui, name, data)
            return "Adjust slider"
        end
    },
    button = {
        ---@param gui WorldGuiInterface
        ---@param name string
        ---@param data WorldGuiWidget
        create = function(gui, name, data, widgetData, position, rotation)
            widgetData.callbacks = {}
            widgetData.isPressed = false
            widgetData.isInteractable = true
            widgetData.trigger = sm.areaTrigger.createBox(
                vec3(data.transform.scale_x, 1, data.transform.scale_y) * guiScaleMultiplier_half,
                position, rotation, 0,
                {
                    button = name,
                    guiId = gui.id
                }
            )
        end,
        ---@param gui WorldGuiInterface
        ---@param name string
        ---@param data WorldGuiWidget
        update = function(gui, name, data, scale)
            local trigger = data.data.trigger --[[@as AreaTrigger]]
            trigger:setWorldPosition(gui.position + gui.rotation * vec3(data.transform.pos_x, data.zIndex, data.transform.pos_y) * guiScaleMultiplier * scale)
            trigger:setWorldRotation(gui.rotation * data.transform.rotation)
            trigger:setSize(vec3(data.transform.scale_x, 1, data.transform.scale_y) * guiScaleMultiplier_half * scale)
        end,
        ---@param gui WorldGuiInterface
        ---@param name string
        ---@param data WorldGuiWidget
        destroy = function(gui, name, data)
            sm.areaTrigger.destroy(data.data.trigger)
        end,
        ---@param gui WorldGuiInterface
        ---@param name string
        ---@param data WorldGuiWidget
        interactionText = function(gui, name, data)
            return "Press button"
        end
    }
}

---@class WorldGuiLayoutWidget
---@field skin string
---@field widgetType? string
---@field widgetData? table
---@field transform WorldGuiTransform
---@field parent? string

---@alias WorldGuiLayout { [string]: WorldGuiLayoutWidget }



local eventBindings =
{
	["Harvestable"     ] = sm.event.sendToHarvestable,
	["ScriptableObject"] = sm.event.sendToScriptableObject,
	["Character"       ] = sm.event.sendToCharacter,
	["Tool"            ] = sm.event.sendToTool,
	["Interactable"	   ] = sm.event.sendToInteractable,
	["Unit"			   ] = sm.event.sendToUnit,
	["Player"		   ] = sm.event.sendToPlayer,
	["World"		   ] = sm.event.sendToWorld
}

function WorldGui.OnInteract(guiId, widgetName, state, player)
    ---@type WorldGuiWidget
    local widget = WorldGui.activeLayouts[guiId].widgets[widgetName]
    if state == widget.data.isPressed then return end

    widget.data.isPressed = state
    if state then
        widget.effect:setParameter("color", sm.color.new(WorldGui.skins[widget.skin].pressColour))
    else
        widget.effect:setParameter("color", sm.color.new(WorldGui.skins[widget.skin].hoverColour))
    end

    for k, callbackData in pairs(widget.data.callbacks) do
        local obj = callbackData.obj
        local eventFunction = eventBindings[type(obj)]
        if eventFunction then
            eventFunction(obj, callbackData.callback, { widget = widgetName, state = state, player })
        else
            callbackData.obj[callbackData.callback](callbackData.obj, widgetName, state, player)
        end
    end
end


---@class WorldGuiTransform
---@field pos_x number
---@field pos_y number
---@field scale_x number
---@field scale_y number
---@field rotation Quat

---@class WorldGuiWidget
---@field effect Effect
---@field skin string
---@field type string
---@field data table
---@field transform WorldGuiTransform
---@field parent? string
---@field zIndex number

---@class WorldGuiInterface
---@field id number
---@field widgets { [string]: WorldGuiWidget }
---@field position Vec3
---@field rotation Quat
---@field hoverWidget AreaTrigger?
---@field open function
---@field close function
---@field destroy function
---@field recalculateTransform function
---@field setPosition function
---@field setRotation function
---@field setWidgetPosition function
---@field setWidgetRotation function
---@field update function
---@field bindButtonCallback function
---@field getWidget function
---@field setSliderFraction function
---@field getSliderFraction function

---@param layout WorldGuiLayout
---@param position Vec3
---@param rotation Quat
---@return WorldGuiInterface
function WorldGui.createGui(layout, position, rotation)
    ---@type WorldGuiInterface
    local gui = {
        id = 0,
        widgets = {},
        rotation = rotation,
        position = position,
        hoverWidget = nil,
        ---@param self WorldGuiInterface
        open = function(self)
            for name, data in pairs(self.widgets) do
                data.effect:start()
            end
        end,
        ---@param self WorldGuiInterface
        close = function(self)
            for name, data in pairs(self.widgets) do
                data.effect:stop()
            end
        end,
        ---@param self WorldGuiInterface
        destroy = function(self)
            for name, data in pairs(self.widgets) do
                data.effect:destroy()

                local widgetTypeCallbacks = WorldGui.widgetTypeCallbacks[data.type] or {}
                if widgetTypeCallbacks.destroy then
                    widgetTypeCallbacks.destroy(self, name, data)
                end
            end

            WorldGui.activeLayouts[self.id] = nil
        end,
        ---@param self WorldGuiInterface
        recalculateTransform = function(self, position, rotation, scale)
            scale = scale or 1
            for name, data in pairs(self.widgets) do
                local transform = data.transform
                local effect = data.effect
                local widgetTypeCallbacks = WorldGui.widgetTypeCallbacks[data.type] or {}
                if widgetTypeCallbacks.recalculateTransform then
                    widgetTypeCallbacks.recalculateTransform(self, name, data, position, rotation, scale, effect, transform)
                else
                    local newTransform = CalculateTransform(self, name)
                    effect:setPosition(position + rotation * vec3(newTransform.pos_x, data.zIndex, newTransform.pos_y) * guiScaleMultiplier * scale)
                    effect:setRotation(rotation * newTransform.rotation)
                    effect:setScale(baseWidgetScale * vec3(transform.scale_x, 1, transform.scale_y) * 0.01 * scale)
                end
            end

            self.position = position
            self.rotation = rotation
        end,
        ---@param self WorldGuiInterface
        setPosition = function(self, position)
            self.position = position
            self:recalculateTransform(position, self.rotation)
        end,
        ---@param self WorldGuiInterface
        setRotation = function(self, rotation)
            self.rotation = rotation
            self:recalculateTransform(self.position, rotation)
        end,
        ---@param self WorldGuiInterface
        setWidgetPosition = function(self, widgetName, position)
            local widget = self.widgets[widgetName]
            widget.transform.pos_x = position.x
            widget.transform.pos_y = position.y
            --widget.effect:setPosition(self.position + self.rotation * vec3(position.x, widget.parent and 0.1 or 0, position.y) * guiScaleMultiplier)
        end,
        ---@param self WorldGuiInterface
        setWidgetRotation = function(self, widgetName, rotation)
           local widget = self.widgets[widgetName]
           widget.transform.rotation = rotation
           --widget.effect:setRotation(self.rotation * rotation)
        end,
        ---@param self WorldGuiInterface
        update = function(self, position, rotation, scale)
            scale = scale or 1
            self:recalculateTransform(position or self.position, rotation or self.rotation, scale)

            local camPos = sm.camera.getDefaultPosition()
            local hit, result = sm.physics.raycast(camPos, camPos + sm.localPlayer.getDirection() * 7.5, nil, sm.physics.filter.areaTrigger)
            if result.type == "areaTrigger" then
                local trigger = result:getAreaTrigger()
                if sm.exists(trigger) then
                    if self.hoverWidget and self.hoverWidget ~= trigger then
                        OnUnHoverButton(self)
                    end

                    local userdata = trigger:getUserData()
                    if self.id == userdata.guiId then
                        local widget = self.widgets[userdata.button]

                        local text = "Interact"
                        local widgetTypeCallbacks = WorldGui.widgetTypeCallbacks[widget.type] or {}
                        if widgetTypeCallbacks.interactionText then
                            text = widgetTypeCallbacks.interactionText(self, userdata.button, widget)
                        end
                        sm.gui.setInteractionText("", sm.gui.getKeyBinding("Create", true), text)

                        if not self.hoverWidget then
                            self.hoverWidget = trigger
                            widget.effect:setParameter("color", sm.color.new(WorldGui.skins[widget.skin].hoverColour))

                            sm.tool.forceTool(sm.worldgui_interact)
                        end
                    end
                end
            elseif self.hoverWidget then
                OnUnHoverButton(self)
            end

            for name, data in pairs(self.widgets) do
                local widgetTypeCallbacks = WorldGui.widgetTypeCallbacks[data.type] or {}
                if widgetTypeCallbacks.update then
                    widgetTypeCallbacks.update(self, name, data, scale, result)
                end
            end
        end,
        ---@param self WorldGuiInterface
        bindButtonCallback = function(self, widgetName, obj, callback)
            local widget = self.widgets[widgetName]
            if widget and widget.type == "button" then
                table.insert(widget.data.callbacks, { obj = obj, callback = callback })
            else
                sm.log.warning(("No '%s' button found in world interface!"):format(widgetName))
            end
        end,
        ---@param self WorldGuiInterface
        ---@param widgetName string
        ---@return WorldGuiWidget
        getWidget = function(self, widgetName)
            return self.widgets[widgetName]
        end,
        ---@param self WorldGuiInterface
        ---@param widgetName string
        ---@param fraction number
        setSliderFraction = function(self, widgetName, fraction)
            local widget = self.widgets[widgetName]
            if widget and widget.type == "slider" then
                widget.data.sliderFraction = fraction
            else
                sm.log.warning(("No '%s' slider found in world interface!"):format(widgetName))
            end
        end,
        ---@param self WorldGuiInterface
        ---@param widgetName string
        ---@return number fraction
        getSliderFraction = function(self, widgetName)
            local widget = self.widgets[widgetName]
            if widget and widget.type == "slider" then
                return widget.data.sliderFraction
            end

            sm.log.warning(("No '%s' slider found in world interface!"):format(widgetName))
            return 0
        end
    }

    for name, data in pairs(layout) do
        local effect = sm.effect.createEffect("ShapeRenderable")
        local skinData = WorldGui.skins[data.skin]
        effect:setParameter("uuid", sm.uuid.new(skinData.uuid))
        effect:setParameter("color", sm.color.new(skinData.colour))

        gui.widgets[name] = {
            effect = effect,
            skin = data.skin,
            type = data.widgetType,
            data = data.widgetData or {},
            transform = data.transform,
            parent = data.parent,
            zIndex = 0,
        }
    end

    gui.id = #WorldGui.activeLayouts + 1

    for name, data in pairs(gui.widgets) do
        data.zIndex = CalculateZIndex(gui, name)

        local widgetData = data.data
        local widgetTypeCallbacks = WorldGui.widgetTypeCallbacks[data.type] or {}
        if widgetTypeCallbacks.create then
            widgetTypeCallbacks.create(gui, name, data, widgetData, position, rotation)
        end
    end

    gui:recalculateTransform(position, rotation)

    table.insert(WorldGui.activeLayouts, gui)

    return gui
end



sm.worldgui = WorldGui