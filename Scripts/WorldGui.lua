dofile "$SURVIVAL_DATA/Scripts/util.lua"

local vec3 = sm.vec3.new
local quat_zero = sm.quat.identity()
local baseWidgetScale = sm.vec3.one() * 0.25
local guiScaleMultiplier = 0.25 * 0.01
local guiScaleMultiplier_half = guiScaleMultiplier * 0.5

local DEBUG_HITBOX = false

---@param hierarchy table
---@param widgets WorldGuiLayout
local function AssembleHierarchy(hierarchy, widgets)
    for name, data in pairs(widgets) do
        hierarchy[name] = {}

        if data.children then
            AssembleHierarchy(hierarchy[name], data.children)
        end
    end
end

local function AddWidgetToHierarchy(hierarchy, widgetName, parent)
    if not parent then
        hierarchy[widgetName] = {}
        return
    end

    for name, children in pairs(hierarchy) do
        if name == parent then
            children[widgetName] = {}
        else
            AddWidgetToHierarchy(children, widgetName, parent)
        end
    end
end

---@param gui WorldGuiInterface
local function CalculateZIndexes(gui, widgets, zIndex)
    zIndex = (zIndex or -1) + 1
    for name, children in pairs(widgets) do
        gui.widgets[name].zIndex = zIndex
        CalculateZIndexes(gui, children, zIndex)
    end
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

    effect:setPosition(gui.position + gui.rotation * vec3(pos_x_new, transform.pos_z + widget.zIndex, pos_y_new) * guiScaleMultiplier * gui.scale)
    effect:setRotation(gui.rotation * rotation_new)
    effect:setScale(baseWidgetScale * vec3(transform.scale_x, transform.scale_z, transform.scale_y) * 0.01 * gui.scale)

    for child, childChildren in pairs(children) do
        RenderWidget(gui, child, childChildren, pos_x_new, pos_y_new, rotation_new)
    end
end



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

local function TriggerButtonCallback(callbacks, widgetName, player, state)
    for k, callbackData in pairs(callbacks) do
        local obj = callbackData.obj
        local eventFunction = eventBindings[type(obj)]
        if eventFunction then
            eventFunction(obj, callbackData.callback, { widget = widgetName, player = player, state = state })
        else
            callbackData.obj[callbackData.callback](callbackData.obj, widgetName, player, state)
        end
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
    TransparentBG_dark = {
        uuid = "5f41af56-df4c-4837-9b3c-10781335757f",
        colour = "#222222"
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
            widgetData.callbacks = { press = { { obj = widgetData, callback = "OnClick" } }, hover = {} }
            widgetData.isPressed = false
            widgetData.isInteractable = true
            widgetData.trigger = sm.areaTrigger.createBox(
                vec3(data.transform.scale_x, data.transform.scale_z, data.transform.scale_y) * guiScaleMultiplier_half,
                position, rotation, 0,
                {
                    button = name,
                    guiId = gui.id
                }
            )

            function widgetData:OnClick(widgetName, player, state)
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

            effect:setScale(baseWidgetScale * vec3(width, transform.scale_z, transform.scale_y) * 0.01 * scale)
            transform.scale_x = width

            local pos_x_new, pos_y_new, rotation_new = CalculateTransform(gui, name, pos_x, pos_y, rotation)

            ---@type AreaTrigger
            local trigger = widgetData.trigger
            trigger:setWorldPosition(gui.position + gui.rotation * vec3(pos_x_new, transform.pos_z + data.zIndex, pos_y_new) * guiScaleMultiplier * scale)
            trigger:setWorldRotation(gui.rotation * rotation_new)
            trigger:setSize(baseWidgetScale * vec3(widgetData.maxRange, transform.scale_z, transform.scale_y) * 0.01 * 0.5 * scale)

            if DEBUG_HITBOX then
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
            widgetData.callbacks = { press = {}, hover = {} }
            widgetData.isPressed = false
            widgetData.isInteractable = true
            widgetData.trigger = sm.areaTrigger.createBox(
                vec3(data.transform.scale_x, data.transform.scale_z, data.transform.scale_y) * guiScaleMultiplier_half,
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
            local transform = data.transform
            local trigger = data.widgetData.trigger --[[@as AreaTrigger]]
            trigger:setWorldPosition(gui.position + gui.rotation * vec3(transform.pos_x, transform.pos_z + data.zIndex, transform.pos_y) * guiScaleMultiplier * scale)
            trigger:setWorldRotation(gui.rotation * transform.rotation)
            trigger:setSize(vec3(transform.scale_x, transform.scale_z, transform.scale_y) * guiScaleMultiplier_half * scale)

            if DEBUG_HITBOX then
                if not data.vis then
                    local eff = sm.effect.createEffect("ShapeRenderable")
                    eff:setParameter("uuid", sm.uuid.new(WorldGui.skins.Black.uuid))
                    eff:setParameter("visualization", true)
                    eff:start()

                    data.vis = eff
                end

                data.vis:setPosition(trigger:getWorldPosition())
                data.vis:setRotation(trigger:getWorldRotation())
                data.vis:setScale(trigger:getSize() * 2)
            end
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

---@class WorldGuiTransform
---@field pos_x number
---@field pos_y number
---@field pos_z number
---@field scale_x number
---@field scale_y number
---@field scale_z number
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
---@field setWidgetScale function
---@field setWidgetZIndex function
---@field bindButtonPressCallback function
---@field bindButtonHoverCallback function
---@field getWidget function
---@field setSliderFraction function
---@field getSliderFraction function
---@field createWidget function

---@param gui WorldGuiInterface
---@param widgets WorldGuiLayout
---@param parent? string
function WorldGui.CreateWidgets(gui, widgets, parent)
    for name, data in pairs(widgets) do
        local effect = sm.effect.createEffect("ShapeRenderable")
        local skinData = type(data.skin) == "string" and WorldGui.skins[data.skin] or data.skin
        effect:setParameter("uuid", sm.uuid.new(skinData.uuid))
        effect:setParameter("color", sm.color.new(skinData.colour))

        local transform = data.transform
        transform.pos_x = transform.pos_x or 0
        transform.pos_z = transform.pos_z or 0
        transform.pos_y = transform.pos_y or 0
        transform.scale_x = transform.scale_x or 1
        transform.scale_z = transform.scale_z or 1
        transform.scale_y = transform.scale_y or 1

        gui.widgets[name] = {
            effect = effect,
            skin = data.skin,
            widgetType = data.widgetType,
            widgetData = data.widgetData or {},
            transform = transform,
            parent = parent,
            zIndex = 0,
        }

        if data.children then
            WorldGui.CreateWidgets(gui, data.children, name)
        end
    end
end

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
            if widget then
                widget.transform.pos_x = position.x
                widget.transform.pos_y = position.y
                widget.transform.pos_z = position.z
            else
                sm.log.warning(("No '%s' widget found in world interface!"):format(widgetName))
            end
        end,
        ---@param self WorldGuiInterface
        setWidgetRotation = function(self, widgetName, rotation)
            local widget = self.widgets[widgetName]
            if widget then
                widget.transform.rotation = rotation
            else
                sm.log.warning(("No '%s' widget found in world interface!"):format(widgetName))
            end
        end,
        ---@param self WorldGuiInterface
        setWidgetScale = function(self, widgetName, scale)
            local widget = self.widgets[widgetName]
            if widget then
                widget.transform.scale_x = scale.x
                widget.transform.scale_y = scale.y
                widget.transform.scale_z = scale.z
            else
                sm.log.warning(("No '%s' widget found in world interface!"):format(widgetName))
            end
        end,
        ---@param self WorldGuiInterface
        setWidgetZIndex = function(self, widgetName, index)
            local widget = self.widgets[widgetName]
            if widget then
                widget.zIndex = index
            else
                sm.log.warning(("No '%s' widget found in world interface!"):format(widgetName))
            end
        end,
        ---@param self WorldGuiInterface
        bindButtonPressCallback = function(self, widgetName, obj, callback)
            local widget = self.widgets[widgetName]
            if widget and widget.widgetType == "button" then
                table.insert(widget.widgetData.callbacks.press, { obj = obj, callback = callback })
            else
                sm.log.warning(("No '%s' button found in world interface!"):format(widgetName))
            end
        end,
        ---@param self WorldGuiInterface
        bindButtonHoverCallback = function(self, widgetName, obj, callback)
            local widget = self.widgets[widgetName]
            if widget and widget.widgetType == "button" then
                table.insert(widget.widgetData.callbacks.hover, { obj = obj, callback = callback })
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
        end,
        ---@param self WorldGuiInterface
        ---@param widgetName string
        createWidget = function(self, widgetName, data, parent)
            WorldGui.CreateWidgets(self, { [widgetName] = data }, parent)
            AddWidgetToHierarchy(self.hierarchy, widgetName, parent)
            CalculateZIndexes(self, self.hierarchy)

            local widget = self.widgets[widgetName]
            local widgetData = widget.widgetData
            local widgetTypeCallbacks = WorldGui.widgetTypeCallbacks[widget.widgetType] or {}
            if widgetTypeCallbacks.create then
                widgetTypeCallbacks.create(self, widgetName, widget, widgetData, position, rotation)
            end
        end
    }

    WorldGui.CreateWidgets(gui, layout)
    AssembleHierarchy(gui.hierarchy, layout)
    CalculateZIndexes(gui, gui.hierarchy)

    gui.id = #WorldGui.activeLayouts + 1

    for name, data in pairs(gui.widgets) do
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

function WorldGuiManager:client_onCreate()
    g_worldGuiManager = self
end

function WorldGuiManager:sv_OnButtonUpdate(args)
    self.network:sendToClients("cl_OnButtonUpdate", args)
end

function WorldGuiManager:cl_OnButtonUpdate(args)
    local guiId, widgetName, event, player, state = unpack(args)
    local gui = WorldGui.activeLayouts[guiId]
    local widget = gui.widgets[widgetName]

    if event == "hover" then
        TriggerButtonCallback(widget.widgetData.callbacks.hover, widgetName, player, state)
        widget.effect:setParameter("color", sm.color.new(state and WorldGui.skins[widget.skin].hoverColour or WorldGui.skins[widget.skin].colour))
    elseif event == "press" then
        TriggerButtonCallback(widget.widgetData.callbacks.press, widgetName, player, state)
        widget.widgetData.isPressed = state
        widget.effect:setParameter("color", state and sm.color.new(WorldGui.skins[widget.skin].pressColour) or sm.color.new(WorldGui.skins[widget.skin].hoverColour))
    elseif event == "holdUnhover" then
        TriggerButtonCallback(widget.widgetData.callbacks.press, widgetName, player, false)
        widget.widgetData.isPressed = false
        widget.effect:setParameter("color", sm.color.new(WorldGui.skins[widget.skin].colour))
    end
end

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
            local widgetData =  widget.widgetData
            if widgetData.isInteractable and not widgetData.isPressed then
                local text = "Interact"
                local widgetTypeCallbacks = WorldGui.widgetTypeCallbacks[widget.widgetType] or {}
                if widgetTypeCallbacks.interactionText then
                    text = widgetTypeCallbacks.interactionText(gui, userdata.button, widget)
                end
                sm.gui.setInteractionText("", sm.gui.getKeyBinding("Create", true), text)

                if not self.hoverWidget then
                    self.hoverWidget = trigger

                    self.network:sendToServer("sv_OnButtonUpdate", { userdata.guiId, userdata.button, "hover", sm.localPlayer.getPlayer(), true })
                    sm.tool.forceTool(sm.worldgui_interact)
                end
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
        local userdata = self.hoverWidget:getUserData()
        local gui = WorldGui.activeLayouts[userdata.guiId]
        local button = userdata.button
        local widget = gui.widgets[button]
        if widget.widgetData.isPressed then
            self.network:sendToServer("sv_OnButtonUpdate", { userdata.guiId, button, "holdUnhover", sm.localPlayer.getPlayer() })
        else
            self.network:sendToServer("sv_OnButtonUpdate", { userdata.guiId, button, "hover", sm.localPlayer.getPlayer(), false })
        end
    end

    self.hoverWidget = nil
    sm.tool.forceTool(nil)
end

function WorldGuiManager:OnInteract(args)
    local guiId, widgetName, player, state = unpack(args)

    ---@type WorldGuiWidget
    local widget = WorldGui.activeLayouts[guiId].widgets[widgetName]
    if state == widget.widgetData.isPressed then return end

    self.network:sendToServer("sv_OnButtonUpdate", { guiId, widgetName, "press", player, state })
end