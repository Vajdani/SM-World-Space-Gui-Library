dofile "$SURVIVAL_DATA/Scripts/util.lua"

local vec3 = sm.vec3.new
local quat_zero = sm.quat.identity()
local baseWidgetScale = sm.vec3.one() * 0.25
local guiScaleMultiplier = 0.25 * 0.01
local guiScaleMultiplier_half = guiScaleMultiplier * 0.5

local DEBUG_SLIDER_HITBOX = false

---@param gui WorldGuiInterface
---@param widgets { [string]: WorldGuiLayoutWidget }
---@param parent? string
local function CreateWidgets(gui, widgets, parent)
    for name, data in pairs(widgets) do
        local effect = sm.effect.createEffect("ShapeRenderable")
        local skinData = WorldGui.skins[data.skin]
        effect:setParameter("uuid", sm.uuid.new(skinData.uuid))
        effect:setParameter("color", sm.color.new(skinData.colour))

        gui.widgets[name] = {
            effect = effect,
            skin = data.skin,
            widgetType = data.widgetType,
            widgetData = data.widgetData or {},
            transform = data.transform,
            parent = parent,
            zIndex = 0,
        }

        if data.children then
            CreateWidgets(gui, data.children, name)
        end
    end
end

---@param hierarchy table
---@param widgets { [string]: WorldGuiLayoutWidget }
local function AssembleHierarchy(hierarchy, widgets)
    for name, data in pairs(widgets) do
        hierarchy[name] = {}

        if data.children then
            AssembleHierarchy(hierarchy[name], data.children)
        end
    end
end

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
---@param name string
---@param pos_x number
---@param pos_y number
---@param rotation Quat
---@return number, number, Quat
local function CalculateTransform(gui, name, pos_x, pos_y, rotation)
    pos_x = pos_x or 0
    pos_y = pos_y or 0
    rotation = rotation or quat_zero

    local widget = gui.widgets[name]
    local transform = widget.transform
    local newPos = (rotation * vec3(transform.pos_x, 0, transform.pos_y) + vec3(pos_x, 0, pos_y))

    return newPos.x, newPos.z, rotation * transform.rotation
end

---@param gui WorldGuiInterface
---@param name string
---@param children { [string]: string[] }
local function RenderWidget(gui, name, children, pos_x, pos_y, rotation)
    local widget = gui.widgets[name]

    local transform = widget.transform
    local effect = widget.effect
    local widgetTypeCallbacks = WorldGui.widgetTypeCallbacks[widget.widgetType] or {}

    local pos_x_new, pos_y_new, rotation_new
    if widgetTypeCallbacks.recalculateTransform then
        pos_x_new, pos_y_new, rotation_new = widgetTypeCallbacks.recalculateTransform(gui, name, widget, pos_x, pos_y, rotation, effect, transform)
    else
        pos_x_new, pos_y_new, rotation_new = CalculateTransform(gui, name, pos_x, pos_y, rotation)
    end

    effect:setPosition(gui.position + gui.rotation * vec3(pos_x_new, widget.zIndex, pos_y_new) * guiScaleMultiplier * gui.scale)
    effect:setRotation(gui.rotation * rotation_new)
    effect:setScale(baseWidgetScale * vec3(transform.scale_x, 1, transform.scale_y) * 0.01 * gui.scale)

    for child, childChildren in pairs(children) do
        RenderWidget(gui, child, childChildren, pos_x_new, pos_y_new, rotation_new)
    end
end

if WorldGui == nil then
    WorldGui = {}
    ---@type WorldGuiInterface[]
    WorldGui.activeLayouts = WorldGui.activeLayouts or {}
end

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
        ---@param gui WorldGuiInterface
        ---@param name string
        ---@param data WorldGuiWidget
        ---@param result RaycastResult
        update = function(gui, name, data, result)
            local widgetData = data.widgetData
            if widgetData.player and result.type == "areaTrigger" then
                local localPos = result.pointWorld - widgetData.trigger:getWorldPosition()
                local scale = gui.scale
                widgetData.sliderFraction = sm.util.clamp((0.38 * scale + (widgetData.isFlipped and -localPos.x or localPos.x)) * 400 / widgetData.maxRange * (1 / scale), 0, 1)
            end
        end,
        ---@param gui WorldGuiInterface
        ---@param name string
        ---@param data WorldGuiWidget
        ---@param pos_x number
        ---@param pos_y number
        ---@param rotation Quat
        ---@param effect Effect
        ---@param transform WorldGuiTransform
        recalculateTransform = function(gui, name, data, pos_x, pos_y, rotation, effect, transform)
            local scale = gui.scale
            local widgetData = data.widgetData
            local width = sm.util.lerp(0, widgetData.maxRange, widgetData.sliderFraction)

            effect:setScale(baseWidgetScale * vec3(width, 1, transform.scale_y) * 0.01 * scale)
            transform.scale_x = width

            local pos_x_new, pos_y_new, rotation_new = CalculateTransform(gui, name, pos_x, pos_y, rotation)

            ---@type AreaTrigger
            local trigger = widgetData.trigger
            trigger:setWorldPosition(gui.position + gui.rotation * vec3(pos_x_new, data.zIndex, pos_y_new) * guiScaleMultiplier * scale)
            trigger:setWorldRotation(gui.rotation * rotation_new)
            trigger:setSize(baseWidgetScale * vec3(widgetData.maxRange, 1, transform.scale_y) * 0.01 * 0.5 * scale)

            if DEBUG_SLIDER_HITBOX then
                if not gui.vis then
                    local eff = sm.effect.createEffect("ShapeRenderable")
                    eff:setParameter("uuid", sm.uuid.new(WorldGui.skins.Black.uuid))
                    eff:setParameter("visualization", true)
                    eff:start()

                    gui.vis = eff
                end

                gui.vis:setPosition(trigger:getWorldPosition())
                gui.vis:setRotation(trigger:getWorldRotation())
                gui.vis:setScale(trigger:getSize() * 2)
            end

            local offset = rotation_new * vec3((widgetData.isFlipped and (-width + widgetData.maxRange) or (width - widgetData.maxRange)) * 0.5, 0, 0)
            return CalculateTransform(gui, name, pos_x + offset.x, pos_y + offset.z, rotation)
        end,
        ---@param gui WorldGuiInterface
        ---@param name string
        ---@param data WorldGuiWidget
        destroy = function(gui, name, data)
            sm.areaTrigger.destroy(data.widgetData.trigger)
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
        update = function(gui, name, data)
            local scale = gui.scale
            local trigger = data.widgetData.trigger --[[@as AreaTrigger]]
            trigger:setWorldPosition(gui.position + gui.rotation * vec3(data.transform.pos_x, data.zIndex, data.transform.pos_y) * guiScaleMultiplier * scale)
            trigger:setWorldRotation(gui.rotation * data.transform.rotation)
            trigger:setSize(vec3(data.transform.scale_x, 1, data.transform.scale_y) * guiScaleMultiplier_half * scale)
        end,
        ---@param gui WorldGuiInterface
        ---@param name string
        ---@param data WorldGuiWidget
        destroy = function(gui, name, data)
            sm.areaTrigger.destroy(data.widgetData.trigger)
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
---@field children? WorldGuiLayoutWidget

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
    if state == widget.widgetData.isPressed then return end

    widget.widgetData.isPressed = state
    if state then
        widget.effect:setParameter("color", sm.color.new(WorldGui.skins[widget.skin].pressColour))
    else
        widget.effect:setParameter("color", sm.color.new(WorldGui.skins[widget.skin].hoverColour))
    end

    for k, callbackData in pairs(widget.widgetData.callbacks) do
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
---@field widgetType string
---@field widgetData table
---@field transform WorldGuiTransform
---@field parent? string
---@field zIndex number

---@class WorldGuiInterface
---@field id number
---@field widgets { [string]: WorldGuiWidget }
---@field hierarchy { [string]: string[] }
---@field position Vec3
---@field rotation Quat
---@field scale number
---@field hoverWidget AreaTrigger?
---@field open function
---@field close function
---@field destroy function
---@field setPosition function
---@field setRotation function
---@field setScale function
---@field setWidgetPosition function
---@field setWidgetRotation function
---@field setWidgetZIndex function
---@field bindButtonCallback function
---@field getWidget function
---@field setSliderFraction function
---@field getSliderFraction function

---@param layout WorldGuiLayout
---@param position Vec3
---@param rotation Quat
---@return WorldGuiInterface
function WorldGui.createGui(layout, position, rotation, scale)
    ---@type WorldGuiInterface
    local gui = {
        id = 0,
        widgets = {},
        hierarchy = {},
        rotation = rotation,
        position = position,
        scale = scale or 1,
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

                local widgetTypeCallbacks = WorldGui.widgetTypeCallbacks[data.widgetType] or {}
                if widgetTypeCallbacks.destroy then
                    widgetTypeCallbacks.destroy(self, name, data)
                end
            end

            WorldGui.activeLayouts[self.id] = nil
        end,
        ---@param self WorldGuiInterface
        setPosition = function(self, position)
            self.position = position
        end,
        ---@param self WorldGuiInterface
        setRotation = function(self, rotation)
            self.rotation = rotation
        end,
        ---@param self WorldGuiInterface
        setScale = function(self, scale)
            self.scale = scale
        end,
        ---@param self WorldGuiInterface
        setWidgetPosition = function(self, widgetName, position)
            local widget = self.widgets[widgetName]
            widget.transform.pos_x = position.x
            widget.transform.pos_y = position.y
        end,
        ---@param self WorldGuiInterface
        setWidgetRotation = function(self, widgetName, rotation)
           local widget = self.widgets[widgetName]
           widget.transform.rotation = rotation
        end,
        ---@param self WorldGuiInterface
        setWidgetZIndex = function(self, widgetName, index)
            local widget = self.widgets[widgetName]
            if widget then
                widget.zIndex = index
            else
                sm.log.warning(("No '%s' button found in world interface!"):format(widgetName))
            end
        end,
        ---@param self WorldGuiInterface
        bindButtonCallback = function(self, widgetName, obj, callback)
            local widget = self.widgets[widgetName]
            if widget and widget.widgetType == "button" then
                table.insert(widget.widgetData.callbacks, { obj = obj, callback = callback })
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
            if widget and widget.widgetType == "slider" then
                widget.widgetData.sliderFraction = fraction
            else
                sm.log.warning(("No '%s' slider found in world interface!"):format(widgetName))
            end
        end,
        ---@param self WorldGuiInterface
        ---@param widgetName string
        ---@return number fraction
        getSliderFraction = function(self, widgetName)
            local widget = self.widgets[widgetName]
            if widget and widget.widgetType == "slider" then
                return widget.widgetData.sliderFraction
            end

            sm.log.warning(("No '%s' slider found in world interface!"):format(widgetName))
            return 0
        end
    }

    CreateWidgets(gui, layout)
    AssembleHierarchy(gui.hierarchy, layout)

    gui.id = #WorldGui.activeLayouts + 1

    for name, data in pairs(gui.widgets) do
        data.zIndex = CalculateZIndex(gui, name)

        local widgetData = data.widgetData
        local widgetTypeCallbacks = WorldGui.widgetTypeCallbacks[data.widgetType] or {}
        if widgetTypeCallbacks.create then
            widgetTypeCallbacks.create(gui, name, data, widgetData, position, rotation)
        end
    end

    table.insert(WorldGui.activeLayouts, gui)

    return gui
end



sm.worldgui = WorldGui



---@class WorldGuiManager : ToolClass
WorldGuiManager = class()

function WorldGuiManager:client_onUpdate()
    --sm.tool.forceTool(nil)

    if #WorldGui.activeLayouts == 0 then return end

    local camPos = sm.camera.getDefaultPosition()
    local hit, result = sm.physics.raycast(camPos, camPos + sm.localPlayer.getDirection() * 7.5, nil, sm.physics.filter.areaTrigger)
    if result.type == "areaTrigger" then
        local trigger = result:getAreaTrigger()
        if sm.exists(trigger) then
            if self.hoverWidget and self.hoverWidget ~= trigger then
                self:OnUnHoverButton()
            end

            local userdata = trigger:getUserData()
            local gui = WorldGui.activeLayouts[userdata.guiId]
            local widget = gui.widgets[userdata.button]

            local text = "Interact"
            local widgetTypeCallbacks = WorldGui.widgetTypeCallbacks[widget.widgetType] or {}
            if widgetTypeCallbacks.interactionText then
                text = widgetTypeCallbacks.interactionText(gui, userdata.button, widget)
            end
            sm.gui.setInteractionText("", sm.gui.getKeyBinding("Create", true), text)

            if not self.hoverWidget then
                self.hoverWidget = trigger
                widget.effect:setParameter("color", sm.color.new(WorldGui.skins[widget.skin].hoverColour))

                sm.tool.forceTool(sm.worldgui_interact)
            end
        end
    elseif self.hoverWidget then
        self:OnUnHoverButton()
    end

    for k, layout in pairs(WorldGui.activeLayouts) do
        for name, children in pairs(layout.hierarchy) do
            RenderWidget(layout, name, children)
        end

        for name, data in pairs(layout.widgets) do
            local widgetTypeCallbacks = WorldGui.widgetTypeCallbacks[data.widgetType] or {}
            if widgetTypeCallbacks.update then
                widgetTypeCallbacks.update(layout, name, data, result)
            end
        end
    end
end

function WorldGuiManager:OnUnHoverButton()
    if sm.exists(self.hoverWidget) then
        local gui = WorldGui.activeLayouts[self.hoverWidget:getUserData().guiId]
        local button = self.hoverWidget:getUserData().button
        local widget = gui.widgets[button]
        if widget.widgetData.isPressed then
            WorldGui.OnInteract(gui.id, button, false)
        end

        widget.effect:setParameter("color", sm.color.new(WorldGui.skins[widget.skin].colour))
    end

    self.hoverWidget = nil
    sm.tool.forceTool(nil)
end