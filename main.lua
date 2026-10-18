--[[
    K2 Duels
    FUNCTIONS = original M10RU Duels (all logic kept)
    GUI = K2 dark panel + circular quick buttons (1MB K2 look)
    Branding: K2 / discord.gg/k2scripts
]]
repeat task.wait() until game:IsLoaded()

-- ========================================================================
-- UNIVERSAL EXECUTOR COMPATIBILITY LAYER
-- ========================================================================
local function getSafeGuiParent()
    -- Reading CoreGui.Name does NOT prove we can parent a GUI there.
    -- Test the actual operation and prefer PlayerGui as the safe fallback.
    local function canParentGui(parent)
        if typeof(parent) ~= "Instance" then return false end
        local probe = Instance.new("ScreenGui")
        probe.Name = "K2GuiAccessProbe"
        probe.Enabled = false
        local ok = pcall(function() probe.Parent = parent end)
        pcall(function() probe:Destroy() end)
        return ok
    end

    if type(gethui) == "function" then
        local ok, parent = pcall(gethui)
        if ok and canParentGui(parent) then return parent end
    end

    local player = game:GetService("Players").LocalPlayer
    local playerGui = player and (
        player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
    )
    if canParentGui(playerGui) then return playerGui end

    local ok, coreGui = pcall(function() return game:GetService("CoreGui") end)
    if ok and canParentGui(coreGui) then return coreGui end

    error("[K2 Duels] No writable GUI parent. Run this on the Roblox client after joining a game.", 2)
end

local function protectGuiObject(gui)
    pcall(function()
        if syn and syn.protect_gui then
            syn.protect_gui(gui)
        elseif protectgui then
            protectgui(gui)
        end
    end)
end

-- File System Safe Wrappers
local function safeWriteFile(filename, content)
    if writefile then
        pcall(writefile, filename, content)
    end
end

local function safeReadFile(filename)
    if not (isfile and readfile) then return nil end
    local aliases = {
        ["k2_duels_config.json"] = "fluxhub_config.json",
        ["k2_duels_backup.json"] = "fluxhubPC.json",
        ["k2DuelsIntroSong"] = "fluxHubIntroSong",
    }
    local candidates = {filename}
    local legacy = aliases[filename] or (filename:match("^k2") and filename:gsub("^k2", "flux"))
    if legacy then table.insert(candidates, legacy) end
    for _, candidate in ipairs(candidates) do
        local existsOk, exists = pcall(isfile, candidate)
        if existsOk and exists then
            local readOk, result = pcall(readfile, candidate)
            if readOk and result then return result end
        end
    end
    return nil
end

local function safeIsFile(filename)
    if isfile then
        local ok, res = pcall(isfile, filename)
        return ok and res
    end
    return false
end

-- HTTP Request Safe Wrapper
local httpRequest = request or http_request or (syn and syn.request) or (http and http.request) or (fluxus and fluxus.request)
local function safeHttpGet(url)
    if game.HttpGet then
        local ok, res = pcall(function() return game:HttpGet(url) end)
        if ok and res then return res end
    end
    if httpRequest then
        local ok, res = pcall(function()
            local response = httpRequest({Url = url, Method = "GET"})
            return response and (response.Body or response.body)
        end)
        if ok and res then return res end
    end
    return nil
end

-- Proximity Prompt Trigger Wrapper
local function triggerPromptUniversal(prompt, holdDuration)
    if not prompt or not prompt:IsA("ProximityPrompt") then return end
    
    if type(fireproximityprompt) == "function" then
        local ok, result = pcall(fireproximityprompt, prompt, holdDuration or 0)
        if ok and result ~= false then return end
    end

    if type(getconnections) == "function" then
        local holdOk, holdConns = pcall(getconnections, prompt.PromptButtonHoldBegan)
        local trigOk, trigConns = pcall(getconnections, prompt.Triggered)
        holdConns = holdOk and type(holdConns) == "table" and holdConns or {}
        trigConns = trigOk and type(trigConns) == "table" and trigConns or {}
        if #holdConns > 0 or #trigConns > 0 then
            task.spawn(function()
                for _, c in ipairs(holdConns) do
                    if c.Function then pcall(c.Function) end
                end
                if holdDuration and holdDuration > 0 then
                    task.wait(holdDuration)
                end
                for _, c in ipairs(trigConns) do
                    if c.Function then pcall(c.Function) end
                end
            end)
            return
        end
    end

    pcall(function()
        prompt:InputHoldBegin()
        if holdDuration and holdDuration > 0 then
            task.wait(holdDuration)
        end
        prompt:InputHoldEnd()
    end)
end

-- Custom Asset Wrapper
local function safeGetAsset(filepath)
    if getsynasset then
        local ok, res = pcall(getsynasset, filepath)
        if ok and res then return res end
    end
    if getcustomasset then
        local ok, res = pcall(getcustomasset, filepath)
        if ok and res then return res end
    end
    return ""
end

-- Roblox image/decal formatter used by UI artwork asset IDs.
local function formatAssetId(assetId)
    local value = tostring(assetId or "")
    if value:match("^rbxthumb://") or value:match("^rbxassetid://") then return value end
    return "rbxassetid://" .. value
end

-- ========================================================================
-- SERVICES & LOCAL PLAYER
-- ========================================================================
local Players           = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Lighting         = game:GetService("Lighting")
local HttpService      = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")

if not RunService:IsClient() then
    warn("[K2 Duels] This script must run on the Roblox client, not the server.")
    return
end

local LP = Players.LocalPlayer

-- ========================================================================
-- K2 INTERNAL ANTI DROP (from 404 Anti Drop)
-- Always ON / no UI / no toggle / no keybind.
-- The anti-drop logic is kept inside this script and starts automatically.
-- ========================================================================
do
    -- This hook must filter the key BEFORE reading any Instance property.
    -- Reading LP.Character unconditionally from __index recursively re-enters
    -- __index and can close Roblox on Android (bug in the earlier patch).
    local mt
    if type(getrawmetatable) == "function" then
        local ok, value = pcall(getrawmetatable, game)
        if ok then mt = value end
    end
    if mt and type(newcclosure) == "function" and type(setreadonly) == "function"
        and type(checkcaller) == "function" then
        local oldIdx, oldNewIdx
        local writable = false
        local spoofedVelocity = Vector3.zero
        local ok, err = pcall(function()
            oldIdx, oldNewIdx = mt.__index, mt.__newindex
            if type(oldIdx) ~= "function" or type(oldNewIdx) ~= "function" then
                error("unsupported game metatable")
            end
            local indexHook = newcclosure(function(self, key)
                -- Non-velocity properties delegate immediately, without any
                -- LP.Character / self property access from the hook.
                if key == "AssemblyLinearVelocity" or key == "Velocity" then
                    if not checkcaller() and typeof(self) == "Instance"
                        and self:IsA("BasePart") and self.Name == "HumanoidRootPart" then
                        local character = LP and LP.Character
                        if character and self:IsDescendantOf(character) then
                            return spoofedVelocity
                        end
                    end
                end
                return oldIdx(self, key)
            end)
            local newIndexHook = newcclosure(function(self, key, value)
                if key == "AssemblyLinearVelocity" or key == "Velocity" then
                    if not checkcaller() and typeof(self) == "Instance"
                        and self:IsA("BasePart") and self.Name == "HumanoidRootPart" then
                        local character = LP and LP.Character
                        if character and self:IsDescendantOf(character) then
                            spoofedVelocity = value
                            return
                        end
                    end
                end
                return oldNewIdx(self, key, value)
            end)
            setreadonly(mt, false)
            writable = true
            mt.__index = indexHook
            mt.__newindex = newIndexHook
        end)
        if not ok and writable and oldIdx and oldNewIdx then
            pcall(function()
                mt.__index, mt.__newindex = oldIdx, oldNewIdx
            end)
        end
        if writable then pcall(setreadonly, mt, true) end
        if not ok then warn("[K2 Duels] Anti Drop hook unavailable: " .. tostring(err)) end
    else
        warn("[K2 Duels] Anti Drop executor functions unavailable; other features will load.")
    end
end

local Camera = workspace.CurrentCamera
do
    local deadline = os.clock() + 15
    while (not LP or not Camera) and os.clock() < deadline do
        task.wait(0.1)
        LP = Players.LocalPlayer
        Camera = workspace.CurrentCamera
    end
end
if not LP or not Camera then
    warn("[K2 Duels] LocalPlayer or CurrentCamera is unavailable. Wait for the game to load and try again.")
    return
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    if workspace.CurrentCamera then Camera = workspace.CurrentCamera end
end)

-- Helper to safely get character components
local function getCharData()
    local char = LP and LP.Character
    if not char then return nil, nil, nil end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local hrp  = char:FindFirstChild("HumanoidRootPart")
    return char, hum, hrp
end

-- ========================================================================
-- SHARED PURPLE THEME + INTERRUPTIBLE UI MOTION (visuals only, never physics)
-- ========================================================================

local DEFAULT_THEME = {
    background = Color3.fromRGB(14, 14, 18),
    panel = Color3.fromRGB(22, 22, 28),
    button = Color3.fromRGB(32, 32, 40),
    track = Color3.fromRGB(40, 40, 50),
    border = Color3.fromRGB(70, 70, 82),
    deep = Color3.fromRGB(55, 55, 65),
    accent = Color3.fromRGB(220, 220, 230),
    light = Color3.fromRGB(245, 245, 250),
    text = Color3.fromRGB(255, 255, 255),
    muted = Color3.fromRGB(160, 160, 175),
    dim = Color3.fromRGB(110, 110, 125),
    hover = Color3.fromRGB(45, 45, 55),
}

local UI = {
    alive = true, ready = false, cleanup = {}, root = nil,
    tweens = setmetatable({}, {__mode = "k"}),
    visibility = setmetatable({}, {__mode = "k"}),
    rows = setmetatable({}, {__mode = "k"}),
    theme = setmetatable({
        background = Color3.fromRGB(14, 14, 18),
        panel = Color3.fromRGB(22, 22, 28),
        button = Color3.fromRGB(32, 32, 40),
        track = Color3.fromRGB(40, 40, 50),
        border = Color3.fromRGB(70, 70, 82),
        deep = Color3.fromRGB(55, 55, 65),
        accent = Color3.fromRGB(220, 220, 230),
        light = Color3.fromRGB(245, 245, 250),
        text = Color3.fromRGB(255, 255, 255),
        muted = Color3.fromRGB(160, 160, 175),
        dim = Color3.fromRGB(110, 110, 125),
        hover = Color3.fromRGB(45, 45, 55),
    }, {__index = function(t, k) return DEFAULT_THEME[k] or Color3.fromRGB(220, 220, 230) end}),
}
do
    local runtimeEnvironment = _G
    if type(getgenv) == "function" then
        local ok, environment = pcall(getgenv)
        if ok and type(environment) == "table" then runtimeEnvironment = environment end
    end
    local runtimeKey = "__K2_DUELS_RUNTIME"
    local previous = runtimeEnvironment[runtimeKey] or runtimeEnvironment["__K2_GREY_RUNTIME"]
    if type(previous) == "table" and type(previous.destroy) == "function" then pcall(previous.destroy) end
    runtimeEnvironment[runtimeKey] = UI

    function UI.addCleanup(callback) table.insert(UI.cleanup, callback) end

    function UI.goal(object, property)
        local states = UI.tweens[object]
        local record = states and states[property]
        if record and record.tween then return record.goal end
        return object[property]
    end

    function UI.cancel(object, property)
        local states = UI.tweens[object]
        local record = states and states[property]
        if record then
            states[property] = nil
            if record.tween then pcall(function() record.tween:Cancel() end) end
        end
    end

    function UI.animate(object, goals, duration)
        if not UI.alive or not object then return end
        local states = UI.tweens[object]
        if not states then states = {}; UI.tweens[object] = states end
        for property, value in pairs(goals) do
            local current = states[property]
            -- Repeated refresh/Heartbeat calls must not restart the same tween.
            if current and current.goal == value and (current.tween or object[property] == value) then continue end
            UI.cancel(object, property)
            if not UI.ready or duration == 0 or object[property] == value then
                object[property] = value
                states[property] = {goal = value}
            else
                local tween = TweenService:Create(object,
                    TweenInfo.new(duration or 0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
                    {[property] = value})
                local record = {goal = value, tween = tween}
                states[property] = record
                tween.Completed:Connect(function()
                    if states[property] == record then record.tween = nil end
                end)
                tween:Play()
            end
        end
    end

    local function opacityTargets(object)
        if object:IsA("CanvasGroup") then return {{object = object, property = "GroupTransparency", value = 0}} end
        local targets = {}
        local objects = {object}
        for _, child in ipairs(object:GetDescendants()) do table.insert(objects, child) end
        for _, child in ipairs(objects) do
            if child:IsA("GuiObject") then
                table.insert(targets, {object = child, property = "BackgroundTransparency", value = child.BackgroundTransparency})
                if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
                    table.insert(targets, {object = child, property = "TextTransparency", value = child.TextTransparency})
                elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
                    table.insert(targets, {object = child, property = "ImageTransparency", value = child.ImageTransparency})
                end
            elseif child:IsA("UIStroke") then
                table.insert(targets, {object = child, property = "Transparency", value = child.Transparency})
            end
        end
        return targets
    end

    function UI.show(object, show, instant)
        if not UI.alive or not object then return end
        local state = UI.visibility[object]
        if state and state.wanted == show and not instant then return end
        if not state then
            state = {generation = 0, targets = opacityTargets(object)}
            UI.visibility[object] = state
        end
        state.wanted = show
        state.generation += 1
        local generation = state.generation
        local immediate = instant or not UI.ready
        if show then
            local wasHidden = not object.Visible
            object.Visible = true
            if wasHidden and not immediate then
                for _, target in ipairs(state.targets) do
                    UI.cancel(target.object, target.property)
                    target.object[target.property] = 1
                end
            end
        end
        for _, target in ipairs(state.targets) do
            UI.animate(target.object, {[target.property] = show and target.value or 1}, immediate and 0 or 0.20)
        end
        if immediate then
            object.Visible = show
        elseif not show then
            task.delay(0.21, function()
                if UI.alive and state.generation == generation and not state.wanted and object.Parent then
                    object.Visible = false
                end
            end)
        end
    end

    function UI.isShown(object)
        local state = UI.visibility[object]
        if state then return state.wanted end
        return object.Visible
    end

    function UI.row(object, show, height)
        if not UI.alive then return end
        local old = UI.rows[object]
        if old == show then return end
        UI.rows[object] = show
        UI.animate(object, {Size = UDim2.new(1, 0, 0, show and height or 0)}, 0.22)
        UI.show(object, show)
    end

    function UI.text(object, text)
        if not UI.alive or object.Text == text then return end
        object.Text = text
        if UI.ready then
            UI.cancel(object, "TextTransparency")
            object.TextTransparency = 0.40
            UI.animate(object, {TextTransparency = 0}, 0.13)
        end
    end

    -- This lock freezes dragging only; all buttons remain clickable.
    UI.dragTargets = setmetatable({}, {__mode = "k"})
    UI.dragLocked = false
    function UI.trackDrag(frame, cancel)
        UI.dragTargets[frame] = cancel
    end
    function UI.setDragLocked(locked)
        UI.dragLocked = locked == true
        if UI.dragLocked then
            for frame, cancel in pairs(UI.dragTargets) do
                if not frame:GetAttribute("K2AlwaysDraggable") then
                    cancel()
                    UI.cancel(frame, "Position")
                end
            end
        end
    end
    function UI.drag(frame, handle, ignoreLock)
        handle = handle or frame
        handle.Active = true
        local active, pointer, start, position = false, nil, nil, nil
        local function cancel() active, pointer, start, position = false, nil, nil, nil end
        UI.trackDrag(frame, cancel)
        local connections = {}
        table.insert(connections, handle.InputBegan:Connect(function(input)
            if not UI.alive or (UI.dragLocked and not ignoreLock) then return end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
            UI.cancel(frame, "Position")
            active, pointer, start, position = true, input, input.Position, frame.Position
        end))
        table.insert(connections, UserInputService.InputChanged:Connect(function(input)
            if not UI.alive or (UI.dragLocked and not ignoreLock) or not active or not pointer then return end
            local matches = input == pointer or (pointer.UserInputType == Enum.UserInputType.MouseButton1
                and input.UserInputType == Enum.UserInputType.MouseMovement)
            if not matches then return end
            local delta = input.Position - start
            local destination = UDim2.new(position.X.Scale, position.X.Offset + delta.X,
                position.Y.Scale, position.Y.Offset + delta.Y)
            if UI.constrainDrag then destination = UI.constrainDrag(frame, destination) end
            UI.animate(frame, {Position = destination}, 0.08)
        end))
        table.insert(connections, UserInputService.InputEnded:Connect(function(input)
            if input == pointer or (pointer and pointer.UserInputType == Enum.UserInputType.MouseButton1
                and input.UserInputType == Enum.UserInputType.MouseButton1) then cancel() end
        end))
        UI.addCleanup(function()
            cancel()
            for _, connection in ipairs(connections) do connection:Disconnect() end
            UI.dragTargets[frame] = nil
        end)
    end

    function UI.destroy()
        if not UI.alive then return end
        UI.alive = false
        for index = #UI.cleanup, 1, -1 do pcall(UI.cleanup[index]) end
        table.clear(UI.cleanup)
        for object, states in pairs(UI.tweens) do
            for property in pairs(states) do UI.cancel(object, property) end
        end
        if UI.root then pcall(function() UI.root:Destroy() end) end
        if runtimeEnvironment[runtimeKey] == UI then runtimeEnvironment[runtimeKey] = nil end
    end
end


-- ========================================================================
-- CONSTANTS & VARIABLES
-- ========================================================================
-- Keep shared state in one local table instead of 67 long-lived locals.
-- This avoids Luau's 200-local-register limit without creating globals.
local State = {}

State.NS                  = 60
State.CS                  = 30
State.LAGGER_SPEED        = 15
State.LAGGER_CARRY_SPEED  = 24.5

State.speedMode           = false
State.autoCarrySpeedEnabled = false
State.autoCarryLastSpeed    = 0
-- Auto Switch Carry Speed state, ported from Horizon's Auto Carry logic.
State.autoCarryFromSteal    = false
State.autoCarryGraceUntil   = 0
State.autoCarryReturnMode   = nil
State.autoCarryWaitingForPickup = false
State.autoCarryPickupWatchUntil = 0
State.stealAttrWasActive    = false
State.laggerToggled       = false
State.laggerPhase         = 0

State.antiRagdollEnabled  = false
State.antiRagdollMode     = "Off"
State.infJumpEnabled      = false
State.infJumpMode         = "manual"

_G.AdaptAntiVoidEnabled = true
_G.AdaptAntiVoidConnection = _G.AdaptAntiVoidConnection or nil
_G.AdaptAntiVoidSafeCFrame = _G.AdaptAntiVoidSafeCFrame or nil

function _G.AdaptAntiVoidSaveSafe()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then return end
    if hum.FloorMaterial ~= Enum.Material.Air then
        _G.AdaptAntiVoidSafeCFrame = root.CFrame
    end
end

function _G.AdaptAntiVoidStop()
    if _G.AdaptAntiVoidConnection then
        pcall(function() _G.AdaptAntiVoidConnection:Disconnect() end)
        _G.AdaptAntiVoidConnection = nil
    end
end

function _G.AdaptAntiVoidSet(on)
    _G.AdaptAntiVoidEnabled = on == true
    _G.AdaptAntiVoidStop()
    if not _G.AdaptAntiVoidEnabled then return end

    _G.AdaptAntiVoidSaveSafe()

    _G.AdaptAntiVoidConnection = RunService.Heartbeat:Connect(function()
        local char = LP.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not _G.AdaptAntiVoidEnabled or not hum or not root or hum.Health <= 0 then return end

        local voidY = workspace.FallenPartsDestroyHeight + 30
        if hum.FloorMaterial ~= Enum.Material.Air and root.Position.Y > voidY + 12 then
            _G.AdaptAntiVoidSafeCFrame = root.CFrame
        elseif root.Position.Y <= voidY and _G.AdaptAntiVoidSafeCFrame then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.CFrame = _G.AdaptAntiVoidSafeCFrame + Vector3.new(0, 4, 0)
            hum.PlatformStand = false
            hum.Sit = false
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
        end
    end)
end

-- Always-on Anti Void: no menu/toggle is created.
pcall(function() _G.AdaptAntiVoidSet(true) end)
if not _G.__K2_AntiVoidCharacterHook then
    _G.__K2_AntiVoidCharacterHook = true
    LP.CharacterAdded:Connect(function()
        task.wait(0.5)
        if _G.AdaptAntiVoidEnabled then
            pcall(function() _G.AdaptAntiVoidSaveSafe() end)
        end
    end)
end
State.medusaCounterEnabled= false
State.batCounterEnabled   = false
State.unwalkEnabled       = false
State.autoBatEnabled      = false
State.antiDieEnabled      = false
State.instantResetOnDieEnabled = false
State.antiFlingEnabled    = false
State.bodyLockEnabled     = false
State.bodyLockRange       = 20
State.tpBatEnabled        = false
State.autoSwingEnabled    = true
State.animPack            = "OFF"
State.antiLagEnabled      = false
State.fpsBoostEnabled     = false
State.espEnabled          = false
State.tracersEnabled      = false
State.stretchRezEnabled   = false
State.autoTPEnabled       = false
State.autoTPHeight        = 20
State.introEnabled        = true

State.autoLeftEnabled     = false
State.autoRightEnabled    = false

-- Auto Play Mode:
-- Half = the existing two-button Auto Left / Auto Right system.
-- Auto = the Auto Play route taken from EclipseHub.
State.autoPlayMode        = "Half"
State.autoPlayEnabled     = false
State.autoPlayRoute       = "none"
State.autoPlayWPIndex     = 1

State.dropActive          = false
State.medusaDebounce      = false
State.medusaLastUsed      = 0
State.batCounterDebounce  = false
State.isStealing          = false
State.stealStartTime      = nil

State.HIT_DIST               = 8
State.MEDUSA_COOLDOWN        = 25
State.DROP_ASCEND_DURATION   = 0.2
State.DROP_ASCEND_SPEED      = 150


State.AP_L1 = Vector3.new(-476.47, -6.28, 92.73)
State.AP_L2 = Vector3.new(-483.12, -4.95, 94.81)
State.AP_R1 = Vector3.new(-476.16, -6.52, 25.62)
State.AP_R2 = Vector3.new(-483.06, -5.03, 25.48)

State.PLOT3_POS = Vector3.new(-476.75, 10.46, 7.11)
State.PLOT7_POS = Vector3.new(-476.75, 10.46, 114.11)
State.TP_PLOT3  = Vector3.new(-475.34, -6.81, 32.33)
State.TP_PLOT7  = Vector3.new(-474.24, -6.81, 87.08)

-- AUTO GRAB settings: engine selection is independent of appearance.
State.SemiMode       = "V1" -- Normal engine: V1 or V2
State.SemiEnabled    = false -- SEMI instant engine from the second file
State.SemiNormalOpen = false -- Normal engine ON/OFF AND category visibility
State.AutoGrabStyle  = {V1 = 2, V2 = 2, SEMI = 2}
State.v1Scale        = 1.0
State.v2Scale        = 1.0
State.semiScale      = 1.0

State.StealV1 = {
    AutoStealEnabled = false,
    StealRadius      = 61, -- LOCKED, cannot be changed
    StealDuration    = 1.3,
    StealDelay       = 0.25,
    Data             = {}
}
State.autoGrabSetDelayRadius = 9
State.autoGrabStopTime       = 0.975
State.autoGrabStopEnabled    = true
State.autoGrabMode            = 75

State.StealV2 = {
    AutoStealEnabled = false,
    StealRadius      = 61, -- Yout AutoSteal radius is fixed; no radius control in the UI.
    StealDuration    = 0.3,
    Mode             = "half",
    HalfFireRange    = 10,
    HalfHoldMin      = 1.3,
    HalfHoldMax      = 2.6,
    HalfEntryDelay   = 0.3,
    Data             = {}
}
State.isStealingV1   = false
State.isStealingV2   = false
State.stealStartTimeV2 = nil

local KB = {
    DropBrainrot = {kb = Enum.KeyCode.X, gp = nil},
    AutoLeft     = {kb = Enum.KeyCode.Z, gp = nil},
    AutoRight    = {kb = Enum.KeyCode.C, gp = nil},
    AutoBat      = {kb = Enum.KeyCode.E, gp = nil},
    TPFloor      = {kb = Enum.KeyCode.F, gp = nil},
    TpBat        = {kb = Enum.KeyCode.T, gp = nil},
    GuiHide      = {kb = Enum.KeyCode.LeftControl, gp = nil},
    SpeedToggle  = {kb = Enum.KeyCode.Q, gp = nil},
    -- Horizon uses R for Instant Reset; move Lagger off the same key.
    LaggerToggle = {kb = Enum.KeyCode.G, gp = nil},
    InstantReset = {kb = Enum.KeyCode.R, gp = nil}
}

local MOVE_KEYS = {
    [Enum.KeyCode.W] = true, [Enum.KeyCode.A] = true,
    [Enum.KeyCode.S] = true, [Enum.KeyCode.D] = true,
    [Enum.KeyCode.Up] = true, [Enum.KeyCode.Left] = true,
    [Enum.KeyCode.Down] = true, [Enum.KeyCode.Right] = true
}

-- Connection Management Table
local Conns = {
    autoStealV1 = nil,
    autoStealV2 = nil,
    autoStealSemi = nil,
    antiRag = nil,
    batCounter = nil,
    anchor = {},
    progress = nil,
    autoTP = nil,
    autoLeft = nil,
    autoRight = nil,
    autoPlay = nil,
    stretchRez = nil,
    antiLagDesc = nil,
    fpsBoostDesc = nil
}

-- UI Callback Setters
local setInfJumpVisual, setAntiRagVisual, setMedusaVisual, setJumpModeVisual
local setUnwalkVisual, setAntiLagVisual, setAutoSwingVisual, setBatCounterVisual
local setStretchRezVisual, setAutoTPVisual, setFPSBoostVisual
local setESPVisual, setTracersVisual, applyESPState, applyTracersState
local setAutoBatVisual, setAutoGrabVisual, setAutoSwitchSpeedVisual, autoLeftSetVisual, autoRightSetVisual, autoPlayLeftSetVisual, autoPlayRightSetVisual
local setBodyLockVisual, setAntiFlingVisual, setInstantResetOnDieVisual
local setSkyVisual, setIntroVisual
local normalBox, carryBox, laggerCarryBox, autoTPHeightBox, bodyLockRangeBox
local speedLabel, modeValLbl
-- One shared controller avoids extra long-lived locals / Luau register pressure.
local Combat = {}
local AntiDie
local InstantReset

local Grab = {
    alive = true, epoch = 0, uiTarget = "V1", appearanceOpen = false,
    views = {}, connections = {}, displayed = 0, progressV1 = 0, v2Ready = false,
    phaseV1 = "idle", phaseV2 = "idle",
    -- Performance is sampled over real RenderStepped frames, not 1/dt from
    -- the last frame. The fill is capped before the opaque stats plate.
    perf = {elapsed = 0, frames = 0, fps = 0, ping = 0, pingAt = 0},
    visualFillLimit = 0.70,
    purple = UI.theme,
}
local refreshSemiUI = nil

-- ========================================================================
-- ARABI SPEED: supplied PreSimulation / normalized XZ AssemblyLinearVelocity.
-- The supplied Arabi file updates a spoof vector but contains NO velocity read
-- hook. No Haze LinearVelocity constraint, hook, loader or unrelated Arabi code.
-- ========================================================================
local function isRagdollState(hum)
    if not hum then return true end
    local state = hum:GetState()
    return hum.PlatformStand or state == Enum.HumanoidStateType.Physics
        or state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown
end

local Speed = {alive = true, connections = {}, lastMoveDir = Vector3.zero, spoofedVelocity = Vector3.zero}
function Speed.pathActive() return State.autoLeftEnabled or State.autoRightEnabled or State.autoPlayEnabled end

-- Horizon Auto Switch Carry Speed port. It only switches speed while a steal /
-- carry handoff is active; enabling the button does not force Carry forever.
local AutoCarry = {
    nearAt = 0, nearValue = false,
}

local function isCarryName(name)
    local value = tostring(name or ""):lower()
    return value:find("brainrot") or value:find("animal") or value:find("carry")
        or value:find("grab") or value:find("steal") or value:find("hold")
end

local function isIgnoredCarryTool(name)
    local value = tostring(name or ""):lower()
    return value:find("bat") or value:find("slap") or value:find("medusa")
        or value:find("head") or value:find("stone")
end

local function isCarryingBrainrot(char)
    if not char then return false end
    for _, name in ipairs({"Carrying", "IsCarrying", "Grabbed", "Holding", "StealHold", "HasGrab"}) do
        local value = char:FindFirstChild(name, true)
        if value then
            if value:IsA("BoolValue") and value.Value then return true end
            if value:IsA("ObjectValue") and value.Value then return true end
            if value:IsA("StringValue") and value.Value ~= "" then return true end
        end
    end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Model") and child:FindFirstChildWhichIsA("BasePart", true) then
            if child:FindFirstChildOfClass("Humanoid") and child:FindFirstChild("HumanoidRootPart") then return true end
            if isCarryName(child.Name) then return true end
        elseif child:IsA("Tool") and not isIgnoredCarryTool(child.Name) then
            return true
        end
    end
    return false
end

local function isNearBrainrot(char)
    local now = tick()
    if now - AutoCarry.nearAt < 0.15 then return AutoCarry.nearValue end
    AutoCarry.nearAt, AutoCarry.nearValue = now, false
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    for _, prompt in ipairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            local holder = prompt.Parent
            local part = holder and holder:IsA("BasePart") and holder
                or holder and holder:FindFirstAncestorWhichIsA("BasePart")
            if part and (part.Position - root.Position).Magnitude <= 11 then
                AutoCarry.nearValue = true
                return true
            end
        end
    end
    return false
end

local function setAutoCarryBaseMode(on)
    State.speedMode = on == true
end

-- Horizon Auto Switch Carry Speed logic. The selected speed family is saved
-- before switching, then restored exactly when the prompt/steal/carry ends.
local function enableAutoCarrySpeed()
    State.autoCarryWaitingForPickup = false
    State.autoCarryPickupWatchUntil = 0
    if not State.autoCarryFromSteal then
        State.autoCarryReturnMode = (State.laggerToggled and State.laggerPhase == 2 and "Lagger Carry")
            or (State.laggerToggled and "Lagger")
            or (State.speedMode and "Carry")
            or "Normal"
    end
    State.autoCarryFromSteal = true
    State.autoCarryGraceUntil = tick() + 0.75

    if State.autoCarryReturnMode == "Lagger" or State.autoCarryReturnMode == "Lagger Carry" then
        State.laggerToggled, State.laggerPhase, State.speedMode = true, 2, false
    else
        setAutoCarryBaseMode(true)
    end
    if Speed.refreshVisuals then Speed.refreshVisuals() end
end

local function disableAutoCarrySpeed()
    if not State.autoCarryFromSteal and not State.autoCarryWaitingForPickup then return end
    local wasAutoApplied = State.autoCarryFromSteal
    local returnMode = State.autoCarryReturnMode
    State.autoCarryFromSteal = false
    State.autoCarryWaitingForPickup = false
    State.autoCarryPickupWatchUntil = 0
    State.autoCarryReturnMode = nil
    if not wasAutoApplied then return end

    if returnMode == "Lagger Carry" then
        State.laggerToggled, State.laggerPhase, State.speedMode = true, 2, false
    elseif returnMode == "Lagger" then
        State.laggerToggled, State.laggerPhase, State.speedMode = true, 1, false
    elseif returnMode == "Carry" then
        State.laggerToggled, State.laggerPhase, State.speedMode = false, 0, true
    else
        State.laggerToggled, State.laggerPhase, State.speedMode = false, 0, false
    end
    State.autoCarryLastSpeed = 0
    if Speed.refreshVisuals then Speed.refreshVisuals() end
end

function Speed.updateAutoCarry(char, hum)
    -- Unwalk only removes the walk animation; Auto Switch Carry must continue
    -- to detect real steal/carry handoffs while it is enabled.
    if not State.autoCarrySpeedEnabled then
        if State.autoCarryFromSteal or State.autoCarryWaitingForPickup then disableAutoCarrySpeed() end
        return
    end

    -- Same detection/order as Horizon Hub: prompt nearby, Stealing attribute,
    -- and actual carry state. State.isStealing is deliberately not used here;
    -- it can outlive a finished grab and was making Carry Speed stick on.
    local gotHit = isRagdollState(hum)
    local stealingAttr = LP:GetAttribute("Stealing") == true
    local nearBrainrot = isNearBrainrot(char)
    local carryingBrainrot = isCarryingBrainrot(char) or nearBrainrot

    if nearBrainrot and not State.autoCarryFromSteal then enableAutoCarrySpeed() end
    if stealingAttr and not State.stealAttrWasActive then
        State.stealAttrWasActive = true
        enableAutoCarrySpeed()
    elseif not stealingAttr then
        State.stealAttrWasActive = false
    end
    if State.autoCarryWaitingForPickup then
        if gotHit or tick() > (State.autoCarryPickupWatchUntil or 0) then
            State.autoCarryWaitingForPickup = false
        elseif carryingBrainrot then
            enableAutoCarrySpeed()
        end
    end
    if carryingBrainrot and not State.autoCarryFromSteal then enableAutoCarrySpeed() end
    if State.autoCarryFromSteal and (gotHit
        or (tick() > State.autoCarryGraceUntil and not carryingBrainrot and not stealingAttr)) then
        disableAutoCarrySpeed()
    end
end

local function getActiveMoveSpeed()
    if Speed.pathActive() then return State.NS end
    if State.autoCarryFromSteal then
        if State.autoCarryReturnMode == "Lagger" or State.autoCarryReturnMode == "Lagger Carry" then
            return State.LAGGER_CARRY_SPEED
        end
        return State.CS
    end
    local carry = State.speedMode or (State.laggerToggled and State.laggerPhase == 2)
    if State.laggerToggled and carry then return State.LAGGER_CARRY_SPEED end
    if State.laggerToggled then return State.LAGGER_SPEED end
    if carry then return State.CS end
    return State.NS
end
local function getAutoPathSpeed()
    return State.NS
end
do
    function Speed.readVelocity(root) return root.AssemblyLinearVelocity end
    function Speed.writeVelocity(root, value) root.AssemblyLinearVelocity = value end
    function Speed.suspend() Speed.lastMoveDir = Vector3.zero end
    function Speed.blocked()
        return State.autoBatEnabled or State.autoLeftEnabled or State.autoRightEnabled
            or State.tpBatEnabled or State.dropActive
    end
    -- Exact Arabi-style drive: real X/Z velocity is set to the selected speed.
    -- Anti Drop may spoof reads, but it does not replace this movement calculation.
    function Speed.syncSpoofFromReal(root)
        local v = root.AssemblyLinearVelocity
        local flat = Vector3.new(v.X, 0, v.Z)
        if flat.Magnitude > 1 then
            local u = flat.Unit
            Speed.spoofedVelocity = Vector3.new(u.X * 16, v.Y, u.Z * 16)
        else
            Speed.spoofedVelocity = Vector3.new(0, v.Y, 0)
        end
    end
    function Speed.applyDrive(root, flat, speed)
        local realY = root.AssemblyLinearVelocity.Y
        root.AssemblyLinearVelocity = Vector3.new(flat.X * speed, realY, flat.Z * speed)
    end
    function Speed.step()
        if not Speed.alive then return end
        local char, hum, root = getCharData()
        if not char or not hum or not root or hum.Health <= 0 then return end
        Speed.updateAutoCarry(char, hum)

        if isRagdollState(hum) then
            Speed.lastMoveDir = Vector3.zero
            Speed.syncSpoofFromReal(root)
            return
        end

        local busy = Speed.blocked()
        if busy then
            if State.autoBatEnabled then Speed.lastMoveDir = Vector3.zero end
            Speed.syncSpoofFromReal(root)
        else
            local direction = hum.MoveDirection
            if direction.Magnitude > 0 then
                Speed.lastMoveDir = direction
            elseif State.antiRagdollEnabled and Speed.lastMoveDir.Magnitude > 0 then
                local anyHeld = false
                for key in pairs(MOVE_KEYS) do
                    if UserInputService:IsKeyDown(key) then
                        anyHeld = true
                        break
                    end
                end
                if anyHeld then direction = Speed.lastMoveDir end
            end

            if direction and direction.Magnitude > 0 then
                local flat = Vector3.new(direction.X, 0, direction.Z)
                if flat.Magnitude > 0 then flat = flat.Unit end
                pcall(function()
                    if root.SetNetworkOwner then root:SetNetworkOwner(LP) end
                end)

                -- IMPORTANT: this is the actual selected speed, not the display value.
                -- Carry Speed 30 therefore drives X/Z at 30 while Carry is active.
                local activeSpeed = getActiveMoveSpeed()
                Speed.applyDrive(root, flat, activeSpeed)
            else
                Speed.syncSpoofFromReal(root)
            end
        end

        -- Match Arabi: display the actual X/Z velocity produced by the drive.
        if speedLabel and not State.isStealing then
            speedLabel.Text = string.format("%.1f",
                Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude)
        end
    end
    function Speed.destroy()
        if not Speed.alive then return end
        Speed.alive = false
        for _, connection in ipairs(Speed.connections) do connection:Disconnect() end
        table.clear(Speed.connections)
        Speed.lastMoveDir, Speed.spoofedVelocity = Vector3.zero, Vector3.zero
    end
    local connected, speedConnection = pcall(function()
        return RunService.PreSimulation:Connect(Speed.step)
    end)
    if not connected then
        connected, speedConnection = pcall(function()
            return RunService.Heartbeat:Connect(Speed.step)
        end)
    end
    if connected and speedConnection then
        table.insert(Speed.connections, speedConnection)
    else
        warn("[K2 Duels] Speed update signal unavailable: " .. tostring(speedConnection))
    end
    table.insert(Speed.connections, LP.CharacterRemoving:Connect(function()
        Speed.lastMoveDir, Speed.spoofedVelocity = Vector3.zero, Vector3.zero
    end))
    UI.addCleanup(Speed.destroy)
end
local function applyPathMovement(hum, root, moveDir, speed)
    if not hum or not root then return end
    Speed.applyDrive(root, moveDir, speed)
end

-- ========================================================================
-- TP BAT (High-Power Engine from tpbat.txt with Jump Restoration)
-- ========================================================================
local TpBat = {alive = true, generation = 0, connections = {}}
do
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local LP = Players.LocalPlayer

    local TP_BAT_CONFIG = {
        Range = 250,
        LoopDelay = 0.02,
        PredictMovement = true,
        PredictionFactor = 0.15,
        HealthCheck = true,
        TeamCheck = false,
        AutoBatDelay = 0.08,
    }

    local Engine = {
        running = false,
        thread = nil,
        hittingCooldown = false,
        humanoid = nil,
        hrp = nil,
        oldWalkSpeed = nil,
        oldJumpPower = nil,
        oldJumpHeight = nil,
        oldAutoRotate = nil,
    }

    local function getMyHRP()
        local char = LP.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function getMyHumanoid()
        local char = LP.Character
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    local function getBat()
        local char = LP.Character
        if not char then return nil end
        local tool = char:FindFirstChild("Bat")
        if tool then return tool end
        local bp = LP:FindFirstChild("Backpack")
        if bp then
            tool = bp:FindFirstChild("Bat")
            if tool then
                tool.Parent = char
                return tool
            end
        end
        return nil
    end

    local function tryHitBat()
        if Engine.hittingCooldown then return end
        Engine.hittingCooldown = true
        pcall(function()
            local bat = getBat()
            if bat then
                bat:Activate()
                local ev = bat:FindFirstChildWhichIsA("RemoteEvent")
                if ev then ev:FireServer() end
            end
        end)
        task.delay(TP_BAT_CONFIG.AutoBatDelay, function()
            Engine.hittingCooldown = false
        end)
    end

    local function isValidEnemy(player)
        if player == LP or not player.Character then return false end
        local hum = player.Character:FindFirstChildOfClass("Humanoid")
        if not hum or (TP_BAT_CONFIG.HealthCheck and hum.Health <= 0) then return false end
        if TP_BAT_CONFIG.TeamCheck and player.Team and player.Team == LP.Team then return false end
        local hrp = player.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
        return true, hrp, hum
    end

    local function findNearestEnemy()
        local myHRP = getMyHRP()
        if not myHRP then return nil end
        local nearestHRP, shortestDist = nil, TP_BAT_CONFIG.Range
        for _, player in ipairs(Players:GetPlayers()) do
            local valid, hrp = isValidEnemy(player)
            if valid then
                local dist = (hrp.Position - myHRP.Position).Magnitude
                if dist < shortestDist then
                    shortestDist = dist
                    nearestHRP = hrp
                end
            end
        end
        return nearestHRP
    end

    local function restoreCharacterMovement()
        local hum = Engine.humanoid or getMyHumanoid()
        if hum and hum.Parent then
            pcall(function()
                -- Restore WalkSpeed
                if Engine.oldWalkSpeed ~= nil and Engine.oldWalkSpeed > 0 then
                    hum.WalkSpeed = Engine.oldWalkSpeed
                else
                    hum.WalkSpeed = 16
                end

                -- Restore JumpPower and JumpHeight
                if Engine.oldJumpPower ~= nil and Engine.oldJumpPower > 0 then
                    hum.JumpPower = Engine.oldJumpPower
                else
                    hum.JumpPower = 50
                end

                if Engine.oldJumpHeight ~= nil and Engine.oldJumpHeight > 0 then
                    hum.JumpHeight = Engine.oldJumpHeight
                else
                    hum.JumpHeight = 7.2
                end

                -- Re-enable Jumping State explicitly so the mobile jump button and spacebar ALWAYS work!
                hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)

                if Engine.oldAutoRotate ~= nil then
                    hum.AutoRotate = Engine.oldAutoRotate
                else
                    hum.AutoRotate = true
                end

                hum.PlatformStand = false
                hum.Sit = false
            end)
        end

        Engine.oldWalkSpeed = nil
        Engine.oldJumpPower = nil
        Engine.oldJumpHeight = nil
        Engine.oldAutoRotate = nil
        Engine.humanoid = nil
        Engine.hrp = nil
    end

    local function teleportToTarget(targetHRP)
        local myHRP = getMyHRP()
        local myHum = getMyHumanoid()
        if not myHRP or not myHum or not targetHRP then return end

        pcall(function()
            myHum.WalkSpeed = 0
            myHum.JumpPower = 0
            myHum.AutoRotate = false
            myHum:Move(Vector3.zero)
            myHum.PlatformStand = false
            myHum.Sit = false

            -- Exact Body-Lock onto target HumanoidRootPart
            myHRP.CFrame = targetHRP.CFrame

            myHRP.Velocity = Vector3.zero
            myHRP.AssemblyLinearVelocity = Vector3.zero
            myHRP.RotVelocity = Vector3.zero
            myHRP.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    local function startTpBatEngine()
        if Engine.running then return end
        local char = LP.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then return end

        Engine.humanoid = hum
        Engine.hrp = hrp
        Engine.oldWalkSpeed = hum.WalkSpeed > 0 and hum.WalkSpeed or 16
        Engine.oldJumpPower = hum.JumpPower > 0 and hum.JumpPower or 50
        Engine.oldJumpHeight = hum.JumpHeight > 0 and hum.JumpHeight or 7.2
        Engine.oldAutoRotate = hum.AutoRotate
        Engine.running = true

        pcall(function()
            hum.WalkSpeed = 0
            hum.JumpPower = 0
            hum.AutoRotate = true
            hum:Move(Vector3.zero)
            hrp.Velocity = Vector3.zero
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.RotVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)

        Engine.thread = task.spawn(function()
            while Engine.running and State.tpBatEnabled do
                local target = findNearestEnemy()
                if target then
                    teleportToTarget(target)
                    tryHitBat()
                else
                    local curHRP = getMyHRP()
                    local curHum = getMyHumanoid()
                    if curHRP and curHum then
                        pcall(function()
                            curHum.WalkSpeed = 0
                            curHum.JumpPower = 0
                            curHum.AutoRotate = false
                            curHum:Move(Vector3.zero)
                            curHRP.Velocity = Vector3.zero
                            curHRP.AssemblyLinearVelocity = Vector3.zero
                            curHRP.AssemblyAngularVelocity = Vector3.zero
                        end)
                    end
                end
                task.wait(TP_BAT_CONFIG.LoopDelay)
            end
        end)
    end

    local function stopTpBatEngine()
        if not Engine.running then return end
        Engine.running = false

        if Engine.thread then
            pcall(function() task.cancel(Engine.thread) end)
            Engine.thread = nil
        end

        restoreCharacterMovement()
        Engine.hittingCooldown = false
    end

    function TpBat.refresh()
        if TpBat.uiSet then TpBat.uiSet(State.tpBatEnabled) end
        if TpBat.mobileSet then TpBat.mobileSet(State.tpBatEnabled) end
    end

    function TpBat.setEnabled(on)
        if not TpBat.alive then return false end
        on = (on == true)

        if State.tpBatEnabled == on then
            TpBat.refresh()
            return on
        end

        TpBat.generation += 1
        State.tpBatEnabled = on

        if on then
            -- The old file referenced missing suspend/restore functions.
            -- Stop only conflicting movement modes; keep their UI/features.
            if State.autoPlayEnabled and TpBat.stopAutoPlay then TpBat.stopAutoPlay() end
            if State.autoBatEnabled and Combat.stopGood then Combat.stopGood() end
            State.autoLeftEnabled, State.autoRightEnabled = false, false
            if Conns.autoLeft then Conns.autoLeft:Disconnect(); Conns.autoLeft = nil end
            if Conns.autoRight then Conns.autoRight:Disconnect(); Conns.autoRight = nil end
            if autoLeftSetVisual then autoLeftSetVisual(false) end
            if autoRightSetVisual then autoRightSetVisual(false) end
            if State.autoTPEnabled then
                State.autoTPEnabled = false
                if Conns.autoTP then pcall(task.cancel, Conns.autoTP); Conns.autoTP = nil end
                if setAutoTPVisual then setAutoTPVisual(false) end
            end
            Speed.suspend()
            startTpBatEngine()
        else
            stopTpBatEngine()
            -- Other movement modes can be turned on again normally in the UI.
        end

        TpBat.refresh()
        return on
    end

    function TpBat.toggle()
        return TpBat.setEnabled(not State.tpBatEnabled)
    end

    function TpBat.destroy()
        if not TpBat.alive then return end
        TpBat.setEnabled(false)
        TpBat.alive = false
        for _, connection in ipairs(TpBat.connections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(TpBat.connections)
    end

    table.insert(TpBat.connections, LP.CharacterRemoving:Connect(function()
        if State.tpBatEnabled then stopTpBatEngine() end
    end))
    table.insert(TpBat.connections, LP.CharacterAdded:Connect(function(character)
        task.delay(0.5, function()
            if TpBat.alive and State.tpBatEnabled and LP.Character == character then
                startTpBatEngine()
            end
        end)
    end))
    UI.addCleanup(TpBat.destroy)
end

-- Optimized Player Collision (Safe & Real Mass Preserved)
task.spawn(function()
    while true do
        task.wait(0.5)
        if not State.tpBatEnabled then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LP and p.Character then
                    for _, part in ipairs(p.Character:GetChildren()) do
                        if part:IsA("BasePart") and part.CanCollide then
                            part.CanCollide = false
                        end
                    end
                end
            end
        end
    end
end)

-- ========================================================================
-- PLOT DETECTION
-- ========================================================================
local function isMyPlotByName(plotName)
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return false end
    local plot = plots:FindFirstChild(plotName)
    if not plot then return false end
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local yb = sign:FindFirstChild("YourBase")
        if yb and yb:IsA("BillboardGui") then
            return yb.Enabled == true
        end
    end
    return false
end

local function getMyPlot()
    for plotNum, plotPos in pairs({[3] = State.PLOT3_POS, [7] = State.PLOT7_POS}) do
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name == "PlotSign" then
                if (obj.Position - plotPos).Magnitude < 5 then
                    for _, child in ipairs(obj:GetDescendants()) do
                        if child:IsA("SurfaceGui") then
                            for _, label in ipairs(child:GetDescendants()) do
                                if label:IsA("TextLabel") and label.Text ~= "" then
                                    if string.find(label.Text, LP.Name) or string.find(label.Text, LP.DisplayName) then
                                        return plotNum
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function getMyPlotPosition()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, plot in ipairs(plots:GetChildren()) do
        if isMyPlotByName(plot.Name) then
            local sign = plot:FindFirstChild("PlotSign")
            if sign then return sign.Position + Vector3.new(0, 5, 0) end
            local ok, cf = pcall(function() return plot:GetModelCFrame() end)
            if ok and cf then return cf.Position + Vector3.new(0, 5, 0) end
        end
    end
    return nil
end

-- ========================================================================
-- AUTO GRAB: independent engines, shared skins, single active owner.
-- Normal V1/V2 keep their supplied ranges/timing. SEMI uses the second file.
-- Generation checks cancel old holds BEFORE another engine is enabled.
-- ========================================================================
do
    -- CLEAN Y/OUT AUTO GRAB ENGINE
    -- Ported only from the safe steal portion of the supplied file:
    -- 61-stud prompt targeting, hold/stop/range/final-trigger sequence and
    -- the 75/80/85/90 timing modes. No donor GUI, HTTP/loadstring code,
    -- teleport/CFrame behaviour, hidden loader, or unrelated remote logic.
    local function disconnect(connection)
        if connection then pcall(function() connection:Disconnect() end) end
    end

    function Grab.currentEngine()
        return (State.SemiNormalOpen and State.StealV1.AutoStealEnabled) and "YOUT" or nil
    end

    function Grab.uiEngine() return "YOUT" end

    function Grab.getStyle()
        return State.AutoGrabStyle.V1 or 2
    end

    function Grab.getScale()
        return State.v1Scale
    end

    function Grab.applyScale()
        local scale = Grab.getScale()
        for _, view in pairs(Grab.views) do
            UI.animate(view.scale, {Scale = scale}, 0.28)
        end
        if Grab.linkScale then UI.animate(Grab.linkScale, {Scale = math.max(scale, 0.9)}, 0.28) end
        if Grab.linkSync then Grab.linkSync() end
    end

    function Grab.updateBars()
        local active = Grab.currentEngine() ~= nil
        local style = active and Grab.getStyle() or nil
        Grab.visibleStyle = style
        if not active then Grab.displayed = 0 end
        for number, view in pairs(Grab.views) do
            UI.show(view.frame, active and style == number)
        end
        if Grab.linkFrame then UI.show(Grab.linkFrame, active and style == 2) end
        Grab.applyScale()
    end

    function Grab.refresh()
        Grab.updateBars()
        if refreshSemiUI then refreshSemiUI() end
    end

    function Grab.setStyle(style)
        if not Grab.alive then return end
        -- Any skin request resolves to the screenshot pill (skin 2).
        State.AutoGrabStyle.V1 = 2
        Grab.refresh()
    end

    function Grab.changeScale(delta)
        if not Grab.alive or type(delta) ~= "number" or delta ~= delta then return end
        State.v1Scale = math.clamp(math.floor((State.v1Scale + delta) * 10 + 0.5) / 10, 0.5, 2)
        Grab.refresh()
    end

    local function promptDistance(prompt)
        local char = LP.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root or not prompt then return math.huge end
        local node = prompt.Parent
        while node and node ~= workspace do
            if node:IsA("BasePart") then return (root.Position - node.Position).Magnitude end
            node = node.Parent
        end
        return math.huge
    end

    -- The Y/out target selection is restricted to steal prompts in other plots.
    local function findNearestYoutPrompt()
        local char = LP.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local plots = workspace:FindFirstChild("Plots")
        if not root or not plots then return nil, nil end

        local nearestPrompt, nearestDistance, nearestName = nil, math.huge, nil
        for _, plot in ipairs(plots:GetChildren()) do
            if isMyPlotByName(plot.Name) then continue end
            local podiums = plot:FindFirstChild("AnimalPodiums")
            if not podiums then continue end
            for _, podium in ipairs(podiums:GetChildren()) do
                local base = podium:FindFirstChild("Base")
                local spawn = base and base:FindFirstChild("Spawn")
                local attachment = spawn and spawn:FindFirstChild("PromptAttachment")
                if spawn and attachment then
                    local distance = (spawn.Position - root.Position).Magnitude
                    if distance <= State.StealV1.StealRadius and distance < nearestDistance then
                        for _, prompt in ipairs(attachment:GetChildren()) do
                            if prompt:IsA("ProximityPrompt") and tostring(prompt.ActionText):find("Steal") then
                                nearestPrompt, nearestDistance, nearestName = prompt, distance, podium.Name
                                break
                            end
                        end
                    end
                end
            end
        end
        return nearestPrompt, nearestName
    end

    local function callbacksFor(prompt)
        local data = State.StealV1.Data[prompt]
        if data then return data end
        data = {hold = {}, trigger = {}, ready = true}
        State.StealV1.Data[prompt] = data
        if getconnections then
            for _, pair in ipairs({{prompt.PromptButtonHoldBegan, data.hold}, {prompt.Triggered, data.trigger}}) do
                local ok, connections = pcall(getconnections, pair[1])
                if ok and type(connections) == "table" then
                    for _, connection in ipairs(connections) do
                        if type(connection.Function) == "function" then table.insert(pair[2], connection.Function) end
                    end
                end
            end
        end
        return data
    end

    local function dispatch(callbacks, current)
        for _, callback in ipairs(callbacks) do
            task.spawn(function()
                if current() then pcall(callback) end
            end)
        end
    end

    local function clearYoutSession(session)
        if session then session.active = false end
        if Grab.yout == session then Grab.yout = nil end
        State.isStealingV1, State.isStealingV2, State.isStealing = false, false, false
        Grab.progressV1, Grab.phaseV1 = 0, "idle"
        if session and session.data then session.data.ready = true end
        Grab.refresh()
    end

    local function fireYoutSteal(session)
        if session.fired or not session.active then return end
        session.fired = true
        dispatch(session.data.trigger, session.current)
        pcall(function()
            if not session.current() then return end
            local prompt = session.prompt
            if prompt then
                pcall(function() if prompt.InputHoldEnd then prompt:InputHoldEnd() end end)
                pcall(function() if fireproximityprompt then fireproximityprompt(prompt) end end)
            end
            local remote = ReplicatedStorage:FindFirstChild("StealAnimal")
            if remote and session.podName then remote:FireServer(session.podName) end
            if session.current() and prompt and prompt.Fire then prompt:Fire() end
        end)
    end

    local function executeYoutSteal(prompt, podName)
        if not Grab.alive or not State.StealV1.AutoStealEnabled or Grab.yout then return end
        if not prompt or not prompt.Parent then return end
        local data = callbacksFor(prompt)
        if not data.ready then return end

        local epoch, character = Grab.epoch, LP.Character
        if not character then return end
        local session = {
            epoch = epoch, character = character, prompt = prompt, podName = podName,
            data = data, active = true, fired = false, phase = "holding", progress = 0,
            startedAt = tick(),
        }
        function session.current()
            return Grab.alive and Grab.yout == session and session.active and Grab.epoch == epoch
                and State.SemiNormalOpen and State.StealV1.AutoStealEnabled
                and LP.Character == character and character.Parent and prompt.Parent
        end

        data.ready = false
        Grab.yout = session
        Grab.phaseV1, Grab.progressV1 = "holding", 0
        State.isStealingV1, State.isStealing = true, true
        Grab.refresh()

        task.spawn(function()
            local ok, err = pcall(function()
                -- Printed Auto Grab: captured hold callbacks, with a prompt fallback
                -- for executors that do not expose getconnections.
                dispatch(data.hold, session.current)
                if #data.hold == 0 then
                    pcall(function() if prompt.InputHoldBegin then prompt:InputHoldBegin() end end)
                end
                local duration = math.max(tonumber(State.StealV1.StealDuration) or 1.3, 0.05)
                local stopAt = math.clamp(State.autoGrabStopTime, 0, duration)

                if State.autoGrabStopEnabled then
                    while session.current() do
                        if promptDistance(prompt) > State.StealV1.StealRadius then return end
                        local elapsed = tick() - session.startedAt
                        if elapsed >= stopAt then break end
                        session.progress = math.clamp(elapsed / duration, 0, 1)
                        Grab.progressV1 = session.progress
                        task.wait()
                    end
                    if not session.current() then return end

                    local stopProgress = math.clamp(stopAt / duration, 0, 1)
                    session.progress, Grab.progressV1 = stopProgress, stopProgress
                    session.phase, Grab.phaseV1 = "waitingRange", "waitingRange"
                    local timeout = math.max(2.99 - stopAt - math.max(duration - stopAt, 0), 0.05)
                    local waitStarted = tick()
                    while session.current() do
                        local distance = promptDistance(prompt)
                        if distance <= State.autoGrabSetDelayRadius then break end
                        if distance > State.StealV1.StealRadius or tick() - waitStarted >= timeout then return end
                        task.wait()
                    end
                    if not session.current() then return end

                    session.phase, Grab.phaseV1 = "finishing", "finishing"
                    local fillStarted = tick()
                    local fillDuration = math.max(duration - stopAt, 0.05)
                    while session.current() do
                        local fillProgress = math.clamp((tick() - fillStarted) / fillDuration, 0, 1)
                        session.progress = stopProgress + fillProgress * (1 - stopProgress)
                        Grab.progressV1 = session.progress
                        if fillProgress >= 1 then fireYoutSteal(session); return end
                        task.wait()
                    end
                else
                    while session.current() do
                        if promptDistance(prompt) > State.StealV1.StealRadius then return end
                        local elapsed = tick() - session.startedAt
                        session.progress = math.clamp(elapsed / duration, 0, 1)
                        Grab.progressV1 = session.progress
                        if elapsed >= duration then fireYoutSteal(session); return end
                        task.wait()
                    end
                end
            end)
            if not ok then warn("[K2 Duels Yout Auto Grab] " .. tostring(err)) end
            clearYoutSession(session)
        end)
    end

    function Grab.stopAll()
        -- Invalidate first: no old hold/trigger task may fire after Off.
        Grab.epoch += 1
        disconnect(Conns.autoStealV1); Conns.autoStealV1 = nil
        disconnect(Conns.autoStealV2); Conns.autoStealV2 = nil
        disconnect(Conns.autoStealSemi); Conns.autoStealSemi = nil
        if Grab.yout then Grab.yout.active = false end
        Grab.yout = nil
        State.SemiNormalOpen, State.SemiEnabled = false, false
        State.StealV1.AutoStealEnabled = false
        State.StealV2.AutoStealEnabled = false
        State.StealV1.Data, State.StealV2.Data = {}, {}
        State.isStealingV1, State.isStealingV2, State.isStealing = false, false, false
        Grab.progressV1, Grab.phaseV1, Grab.phaseV2, Grab.v2Ready = 0, "idle", "idle", false
        Grab.refresh()
    end

    function Grab.startNormal()
        if not Grab.alive then return end
        Grab.stopAll()
        State.SemiNormalOpen, State.SemiEnabled = true, false
        State.StealV1.AutoStealEnabled = true
        Grab.uiTarget = "YOUT"
        Conns.autoStealV1 = RunService.Heartbeat:Connect(function()
            if not Grab.alive or not State.StealV1.AutoStealEnabled or Grab.yout then return end
            local prompt, podName = findNearestYoutPrompt()
            if prompt then executeYoutSteal(prompt, podName) end
        end)
        Grab.refresh()
    end

    -- Old saved SEMI/V2 selections safely map to the new single Y/out engine.
    function Grab.startSemi() Grab.startNormal() end
    function Grab.toggleNormal()
        if State.SemiNormalOpen then Grab.stopAll() else Grab.startNormal() end
    end
    function Grab.toggleSemi() Grab.toggleNormal() end
    function Grab.switchMode(mode)
        if mode == "V1" or mode == "V2" then State.SemiMode = mode end
        Grab.refresh()
    end

    function Grab.getProgress()
        return Grab.yout and math.clamp(Grab.yout.progress or 0, 0, 1) or 0
    end

    function Grab.isReady()
        local session = Grab.yout
        return session ~= nil and session.active
            and (session.phase == "waitingRange" or session.phase == "finishing")
    end

    function Grab.loadSettings(cfg)
        -- Retain only display scale/style and the request to restore Auto Grab.
        if type(cfg.v1Scale) == "number" and cfg.v1Scale == cfg.v1Scale then
            State.v1Scale = math.clamp(cfg.v1Scale, 0.5, 2)
        end
        -- The reference-screenshot pill (skin 2) is the only appearance now.
        -- Older configs saved "skin 1"; always force the new pill instead.
        State.AutoGrabStyle.V1 = 2
        Grab.restoreRequested = (cfg.semiNormalOpen == true or cfg.semiEnabled == true) and "YOUT" or nil
    end

    function Grab.restore()
        if Grab.restoreRequested == "YOUT" then Grab.startNormal() else Grab.refresh() end
    end

    function Grab.destroy()
        if not Grab.alive then return end
        if Grab.linkFrame then
            pcall(function() Grab.linkFrame.Visible = false end)
        end
        Grab.stopAll()
        Grab.alive = false
        disconnect(Grab.renderConnection)
        Grab.renderConnection = nil
        for _, connection in ipairs(Grab.connections) do disconnect(connection) end
        table.clear(Grab.connections)
    end
end

UI.addCleanup(Grab.destroy)

-- ========================================================================
-- AUTO LEFT & AUTO RIGHT PATHRUNNERS
-- ========================================================================
local alPhase, arPhase = 1, 1

local function stopAutoLeft()
    if Conns.autoLeft then Conns.autoLeft:Disconnect(); Conns.autoLeft = nil end
    alPhase = 1
    local char, hum = getCharData()
    if hum then hum:Move(Vector3.zero, false) end
    if autoLeftSetVisual then autoLeftSetVisual(false) end
end

local function stopAutoRight()
    if Conns.autoRight then Conns.autoRight:Disconnect(); Conns.autoRight = nil end
    arPhase = 1
    local char, hum = getCharData()
    if hum then hum:Move(Vector3.zero, false) end
    if autoRightSetVisual then autoRightSetVisual(false) end
end

local function startAutoLeft()
    if Conns.autoLeft then Conns.autoLeft:Disconnect() end
    alPhase = 1
    Conns.autoLeft = RunService.Heartbeat:Connect(function()
        if not State.autoLeftEnabled then return end
        local char, hum, hrp = getCharData()
        if not hrp or not hum then return end
        if isRagdollState(hum) then hum:Move(Vector3.zero, false); return end
        
        -- Half uses Normal/boost speed going out, then Carry Speed for the
        -- complete return leg (no final switch back to Normal Speed).
        local spd = (alPhase == 2) and (State.CS or getAutoPathSpeed()) or getAutoPathSpeed()
        if alPhase == 1 then
            local tgt = Vector3.new(State.AP_L1.X, hrp.Position.Y, State.AP_L1.Z)
            if (tgt - hrp.Position).Magnitude < 1.2 then
                alPhase = 2
                local d = State.AP_L2 - hrp.Position
                local mv = Vector3.new(d.X, 0, d.Z).Unit
                hum:Move(mv, false)
                applyPathMovement(hum, hrp, mv, spd)
                return
            end
            local d = State.AP_L1 - hrp.Position
            local mv = Vector3.new(d.X, 0, d.Z).Unit
            hum:Move(mv, false)
            applyPathMovement(hum, hrp, mv, spd)
        elseif alPhase == 2 then
            local tgt = Vector3.new(State.AP_L2.X, hrp.Position.Y, State.AP_L2.Z)
            if (tgt - hrp.Position).Magnitude < 1.2 then
                hum:Move(Vector3.zero, false)
                hrp.AssemblyLinearVelocity = Vector3.zero
                State.autoLeftEnabled = false
                stopAutoLeft()
                return
            end
            local d = State.AP_L2 - hrp.Position
            local mv = Vector3.new(d.X, 0, d.Z).Unit
            hum:Move(mv, false)
            applyPathMovement(hum, hrp, mv, spd)
        end
    end)
end

local function startAutoRight()
    if Conns.autoRight then Conns.autoRight:Disconnect() end
    arPhase = 1
    Conns.autoRight = RunService.Heartbeat:Connect(function()
        if not State.autoRightEnabled then return end
        local char, hum, hrp = getCharData()
        if not hrp or not hum then return end
        if isRagdollState(hum) then hum:Move(Vector3.zero, false); return end
        
        -- Half uses Normal/boost speed going out, then Carry Speed for the
        -- complete return leg (no final switch back to Normal Speed).
        local spd = (arPhase == 2) and (State.CS or getAutoPathSpeed()) or getAutoPathSpeed()
        if arPhase == 1 then
            local tgt = Vector3.new(State.AP_R1.X, hrp.Position.Y, State.AP_R1.Z)
            if (tgt - hrp.Position).Magnitude < 1.2 then
                arPhase = 2
                local d = State.AP_R2 - hrp.Position
                local mv = Vector3.new(d.X, 0, d.Z).Unit
                hum:Move(mv, false)
                applyPathMovement(hum, hrp, mv, spd)
                return
            end
            local d = State.AP_R1 - hrp.Position
            local mv = Vector3.new(d.X, 0, d.Z).Unit
            hum:Move(mv, false)
            applyPathMovement(hum, hrp, mv, spd)
        elseif arPhase == 2 then
            local tgt = Vector3.new(State.AP_R2.X, hrp.Position.Y, State.AP_R2.Z)
            if (tgt - hrp.Position).Magnitude < 1.2 then
                hum:Move(Vector3.zero, false)
                hrp.AssemblyLinearVelocity = Vector3.zero
                State.autoRightEnabled = false
                stopAutoRight()
                return
            end
            local d = State.AP_R2 - hrp.Position
            local mv = Vector3.new(d.X, 0, d.Z).Unit
            hum:Move(mv, false)
            applyPathMovement(hum, hrp, mv, spd)
        end
    end)
end

local function queueAutoLeftStart()
    State.autoLeftEnabled = true
    if State.autoRightEnabled then State.autoRightEnabled = false; stopAutoRight() end
    if State.autoBatEnabled then Combat.stopGood() end
    startAutoLeft()
end

local function queueAutoRightStart()
    State.autoRightEnabled = true
    if State.autoLeftEnabled then State.autoLeftEnabled = false; stopAutoLeft() end
    if State.autoBatEnabled then Combat.stopGood() end
    startAutoRight()
end

-- ========================================================================
-- AUTO PLAY: EclipseHub route, exposed as one button when Mode = Auto.
-- Half mode keeps the original Auto Left / Auto Right buttons untouched.
-- ========================================================================
local AutoPlay = {
    alive = true, active = false, route = "none", wpIndex = 1, conn = nil,
    autoCarryOwned = false,
}

-- EclipseHub AutoPlay waypoints (kept exactly for the Auto mode).
local AUTO_PLAY_LEFT = {
    Vector3.new(-475.86,-7,91.97), Vector3.new(-485.83,-7,97.37),
    Vector3.new(-475.86,-7,91.97), Vector3.new(-476.35,-7,27.88), Vector3.new(-477.09,-7,19.85),
}
local AUTO_PLAY_RIGHT = {
    Vector3.new(-475.84,-7,28.81), Vector3.new(-486.04,-7,23.32),
    Vector3.new(-475.51,-7,29.01), Vector3.new(-476.43,-7,91.61), Vector3.new(-476.27,-7,98.86),
}
_G.__autoLeftWaypoints = AUTO_PLAY_LEFT
_G.__autoRightWaypoints = AUTO_PLAY_RIGHT
_G.__autoplayMode = _G.__autoplayMode or "Full"

local function getAutoPlayRouteForMyBase()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return "left" end
    for _, plot in ipairs(plots:GetChildren()) do
        local sign = plot:FindFirstChild("PlotSign")
        local yourBase = sign and sign:FindFirstChild("YourBase")
        if yourBase and yourBase.Enabled then
            local target = plot:FindFirstChild("AnimalTarget", true)
            local refPos = target and target.Position
            if not refPos then
                local delivery = plot:FindFirstChild("DeliveryHitbox")
                refPos = delivery and delivery.Position
            end
            if refPos then
                local leftDist = (refPos - AUTO_PLAY_LEFT[1]).Magnitude
                local rightDist = (refPos - AUTO_PLAY_RIGHT[1]).Magnitude
                return (leftDist <= rightDist) and "right" or "left"
            end
            local pivotPos
            pcall(function() pivotPos = plot:GetPivot().Position end)
            if pivotPos then return (pivotPos.Z >= 60) and "right" or "left" end
            local _, _, root = getCharData()
            if root then return (root.Position.Z >= 60) and "right" or "left" end
            return "left"
        end
    end
    return "left"
end

local function getAutoPlaySpeed(wpIndex)
    -- EclipseHub AutoPlay changes to carry/steal speed after waypoint 2.
    -- Do not wait for the Stealing attribute: the return leg must stay at
    -- Carry Speed all the way to the final waypoint.
    if wpIndex > 2 then
        if State.autoCarryReturnMode == "Lagger" or State.autoCarryReturnMode == "Lagger Carry" then
            return State.LAGGER_CARRY_SPEED or State.CS
        end
        return State.CS
    end
    return getAutoPathSpeed()
end

local function stopAutoPlay(keepToggle)
    AutoPlay.active = false
    State.autoPlayEnabled = false
    AutoPlay.route = "none"
    State.autoPlayRoute = "none"
    AutoPlay.wpIndex = 1
    State.autoPlayWPIndex = 1
    if Conns.autoPlay then Conns.autoPlay:Disconnect(); Conns.autoPlay = nil end
    if AutoPlay.autoCarryOwned then
        AutoPlay.autoCarryOwned = false
        pcall(disableAutoCarrySpeed)
    end
    local _, hum, root = getCharData()
    if hum then hum:Move(Vector3.zero, false) end
    if root then
        local v = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
    end
    -- The route is stopped, so the shared AUTO button must also show OFF.
    if autoLeftSetVisual then autoLeftSetVisual(false) end
    if autoRightSetVisual then autoRightSetVisual(false) end
    if autoPlayLeftSetVisual then autoPlayLeftSetVisual(false) end
    if autoPlayRightSetVisual then autoPlayRightSetVisual(false) end
    if autoPlaySetVisual then autoPlaySetVisual(false) end
end
TpBat.stopAutoPlay = stopAutoPlay

local function startAutoPlay()
    if State.autoPlayMode ~= "Auto" then return end
    if AutoPlay.active then stopAutoPlay(true) end

    -- AutoPlay takes control of movement just like EclipseHub.
    if State.autoLeftEnabled then State.autoLeftEnabled = false; stopAutoLeft() end
    if State.autoRightEnabled then State.autoRightEnabled = false; stopAutoRight() end
    if State.autoBatEnabled and Combat and Combat.stopGood then pcall(Combat.stopGood) end
    if State.tpBatEnabled and TpBat and TpBat.setEnabled then pcall(function() TpBat.setEnabled(false) end) end

    if AutoPlay.route ~= "left" and AutoPlay.route ~= "right" then
        AutoPlay.route = getAutoPlayRouteForMyBase()
    end
    State.autoPlayRoute = AutoPlay.route
    AutoPlay.wpIndex = 1
    State.autoPlayWPIndex = 1
    AutoPlay.active = true
    State.autoPlayEnabled = true

    -- EclipseHub keeps Auto Carry Speed active while AutoPlay is running.
    if not State.autoCarryFromSteal then
        AutoPlay.autoCarryOwned = true
        pcall(enableAutoCarrySpeed)
    end

    if AutoPlay.route == "left" then
        if autoLeftSetVisual then autoLeftSetVisual(true) end
        if autoRightSetVisual then autoRightSetVisual(false) end
    else
        if autoRightSetVisual then autoRightSetVisual(true) end
        if autoLeftSetVisual then autoLeftSetVisual(false) end
    end

    Conns.autoPlay = RunService.Heartbeat:Connect(function(dt)
        if not AutoPlay.active or State.autoPlayMode ~= "Auto" then return end
        local char, hum, root = getCharData()
        if not char or not hum or not root or hum.Health <= 0 then return end

        local waypoints = (AutoPlay.route == "left") and AUTO_PLAY_LEFT or AUTO_PLAY_RIGHT
        local stopIdx = (_G.__autoplayMode == "Semi") and 2 or #waypoints
        local wp = waypoints[AutoPlay.wpIndex]
        if not wp then stopAutoPlay(); return end

        local myPos = root.Position
        local targetXZ = Vector3.new(wp.X, 0, wp.Z)
        local myXZ = Vector3.new(myPos.X, 0, myPos.Z)
        local delta = targetXZ - myXZ
        local dXZ = delta.Magnitude

        if dXZ <= 1.1 then
            root.Velocity = Vector3.new(0, root.Velocity.Y, 0)

            if AutoPlay.wpIndex >= stopIdx then
                -- Full mode waits at the final point until the steal ends.
                if State.isStealing ~= true and LP:GetAttribute("Stealing") ~= true then
                    stopAutoPlay()
                end
                return
            end
            AutoPlay.wpIndex += 1
            State.autoPlayWPIndex = AutoPlay.wpIndex
            return
        end

        local dir = delta
        if dir.Magnitude > 0.001 then dir = dir.Unit end
        local speed = getAutoPlaySpeed(AutoPlay.wpIndex) + 1
        if dXZ < 1.5 then speed = speed * math.clamp(dXZ / 1.5, 0.6, 1) end
        speed = math.min(speed, dXZ / math.max(dt or (1/60), 1/240))

        -- Match EclipseHub: horizontal velocity drives the route.
        root.Velocity = Vector3.new(dir.X * speed, root.Velocity.Y, dir.Z * speed)
    end)
end

LP.CharacterAdded:Connect(function()
    task.wait(0.5)
    if AutoPlay.active and State.autoPlayMode == "Auto" then startAutoPlay() end
end)

UI.addCleanup(function()
    AutoPlay.alive = false
    stopAutoPlay()
end)


-- ========================================================================
-- ANTI RAGDOLL: OFF / ORIGINAL NORMAL (V1) / Unpatched Old Anti rag (V2).
-- V1 stays on RenderStepped. V2 uses the donor Heartbeat + 0.15s reset gate.
-- The old V2 constraint-destruction/attribute/yaw reset is not used by V2.
-- ========================================================================
local Ragdoll = {alive = true, open = false, cameraRecord = nil,
    generation = 0, lastReset = 0, resetBusy = false}
do
    local function releaseCamera()
        local record = Ragdoll.cameraRecord
        Ragdoll.cameraRecord = nil
        if record then
            pcall(function()
                if record.camera.CameraSubject == record.humanoid then record.camera.CameraSubject = record.previous end
            end)
        end
    end
    local function bindCamera(humanoid)
        local camera = workspace.CurrentCamera
        if not camera then return end
        local record = Ragdoll.cameraRecord
        if not record or record.camera ~= camera or record.humanoid ~= humanoid then
            releaseCamera()
            Ragdoll.cameraRecord = {camera = camera, humanoid = humanoid, previous = camera.CameraSubject}
        end
        camera.CameraSubject = humanoid
    end
    local function removeConstraintsV1(character)
        for _, item in ipairs(character:GetDescendants()) do
            if item:IsA("BallSocketConstraint") or (item:IsA("Attachment") and item.Name:find("RagdollAttachment")) then
                pcall(function() item:Destroy() end)
            end
        end
    end
    local function isDonorRagdoll(state)
        return state == Enum.HumanoidStateType.Physics or state == Enum.HumanoidStateType.Ragdoll
            or state == Enum.HumanoidStateType.FallingDown
    end
    function Ragdoll.resetV2(character, humanoid, root)
        local generation = Ragdoll.generation
        local function current()
            return Ragdoll.alive and State.antiRagdollMode == "Custom" and Ragdoll.generation == generation
                and LP.Character == character and character.Parent and humanoid.Parent and root.Parent and humanoid.Health > 0
        end
        if not current() or Ragdoll.resetBusy then return end
        Ragdoll.resetBusy = true
        local ok, err = pcall(function()
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            -- Deprecated and current velocity properties are both in the donor.
            pcall(function() root.Velocity = Vector3.zero; root.RotVelocity = Vector3.zero end)
            root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
            for _, object in ipairs(character:GetDescendants()) do
                if object:IsA("Motor6D") or object:IsA("Constraint") then
                    pcall(function() object.Enabled = true end)
                end
            end
            bindCamera(humanoid)
            local playerScripts = LP:FindFirstChild("PlayerScripts")
            local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
            local controlModule = playerModule and playerModule:FindFirstChild("ControlModule")
            if controlModule then
                local loaded, controls = pcall(require, controlModule)
                if not current() then return end
                if loaded and controls and type(controls.Enable) == "function" then
                    pcall(function() controls:Enable() end)
                end
            end
            if not current() then return end
            humanoid.AutoRotate = true
            humanoid.PlatformStand = false
            humanoid.Sit = false
        end)
        if Ragdoll.generation == generation then
            Ragdoll.resetBusy = false
            if not ok then warn("[K2 Duels Anti Ragdoll V2] " .. tostring(err)) end
        end
    end
    function Ragdoll.step()
        if not Ragdoll.alive or State.antiRagdollMode == "Off" then return end
        local character, humanoid, root = getCharData()
        if not character or not humanoid or not root or not humanoid.Parent or humanoid.Health <= 0 then return end
        local state = humanoid:GetState()
        if State.antiRagdollMode == "Custom" then
            if isDonorRagdoll(state) then
                local now = tick()
                if not Ragdoll.resetBusy and now - Ragdoll.lastReset > 0.15 then
                    Ragdoll.lastReset = now
                    Ragdoll.resetV2(character, humanoid, root)
                end
            end
            return
        end
        -- Original V1 behavior, preserved separately.
        local ragdolled = isRagdollState(humanoid)
        local endTime = LP:GetAttribute("RagdollEndTime")
        if not ragdolled and type(endTime) == "number" then ragdolled = endTime > workspace:GetServerTimeNow() end
        if not ragdolled then return end
        removeConstraintsV1(character)
        pcall(function() LP:SetAttribute("RagdollEndTime", workspace:GetServerTimeNow()) end)
        humanoid.PlatformStand = false
        pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end)
        pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Running) end)
        root.Anchored = false
        root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
        root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, select(2, root.CFrame:ToEulerAnglesYXZ()), 0)
        bindCamera(humanoid)
    end
    function Ragdoll.refresh()
        if Ragdoll.refreshUI then Ragdoll.refreshUI() end
    end
    function Ragdoll.setMode(mode)
        if not Ragdoll.alive or (mode ~= "Off" and mode ~= "Normal" and mode ~= "Custom") then return end
        if State.antiRagdollMode == mode and (mode == "Off" or Conns.antiRag) then Ragdoll.refresh(); return end
        Ragdoll.generation += 1
        if Conns.antiRag then Conns.antiRag:Disconnect(); Conns.antiRag = nil end
        releaseCamera()
        Ragdoll.resetBusy, Ragdoll.lastReset = false, 0
        State.antiRagdollMode, State.antiRagdollEnabled = mode, mode ~= "Off"
        if mode == "Normal" then Conns.antiRag = RunService.RenderStepped:Connect(Ragdoll.step)
        elseif mode == "Custom" then Conns.antiRag = RunService.Heartbeat:Connect(Ragdoll.step) end
        Ragdoll.refresh()
    end
    function Ragdoll.destroy()
        if not Ragdoll.alive then return end
        Ragdoll.setMode("Off")
        Ragdoll.alive = false
    end
    UI.addCleanup(Ragdoll.destroy)
end
local function startAntiRagdoll()
    Ragdoll.setMode(State.antiRagdollMode ~= "Off" and State.antiRagdollMode or "Normal")
end
local function stopAntiRagdoll() Ragdoll.setMode("Off") end

-- ========================================================================
-- INFINITE JUMP
-- ========================================================================
UserInputService.JumpRequest:Connect(function()
    if not State.infJumpEnabled then return end
    local char, hum, root = getCharData()
    if root then
        root.Velocity = Vector3.new(root.Velocity.X, 55, root.Velocity.Z)
    end
end)

RunService.Heartbeat:Connect(function()
    if not State.infJumpEnabled then return end
    local char, hum, root = getCharData()
    if not root or not hum then return end
    
    if State.infJumpMode == "hold" then
        local jumpHeld = UserInputService:IsKeyDown(Enum.KeyCode.Space) or hum.Jump == true
        if jumpHeld and root.Velocity.Y < 30 then
            root.Velocity = Vector3.new(root.Velocity.X, 55, root.Velocity.Z)
        end
    elseif State.infJumpMode == "manual" then
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) and root.Velocity.Y < 30 then
            root.Velocity = Vector3.new(root.Velocity.X, 55, root.Velocity.Z)
        end
    end
    if root.Velocity.Y < -120 then
        root.Velocity = Vector3.new(root.Velocity.X, -120, root.Velocity.Z)
    end
end)

-- ========================================================================
-- UNWALK & DROP & TP FLOOR
-- ========================================================================
local unwalkSavedAnimate = nil
local function startUnwalk()
    -- Unwalk is visual/animation-only. Do not cancel Auto Switch Carry here:
    -- when a real steal prompt/carry is detected it must still use Carry Speed.
    Speed.suspend()

    local char, hum, root = getCharData()
    if root then
        local velocity = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
    end
    if hum then
        for _, t in ipairs(hum:GetPlayingAnimationTracks()) do
            pcall(function() t:Stop() end)
        end
    end
    if char then
        local anim = char:FindFirstChild("Animate")
        if anim then
            unwalkSavedAnimate = anim:Clone()
            anim:Destroy()
        end
    end
end

local function stopUnwalk()
    local char = LP.Character
    if char and unwalkSavedAnimate then
        unwalkSavedAnimate:Clone().Parent = char
        unwalkSavedAnimate = nil
    end
end

local function runDrop()
    if State.dropActive then return end
    if State.autoBatEnabled then Combat.stopGood() end
    local char, hum, root = getCharData()
    if not root then return end
    
    State.dropActive = true
    local startTime = tick()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        local c, h, r = getCharData()
        if not r then
            conn:Disconnect()
            State.dropActive = false
            return
        end
        if tick() - startTime >= State.DROP_ASCEND_DURATION then
            conn:Disconnect()
            local rp = RaycastParams.new()
            rp.FilterDescendantsInstances = {c}
            rp.FilterType = Enum.RaycastFilterType.Exclude
            local rayResult = workspace:Raycast(r.Position, Vector3.new(0, -2000, 0), rp)
            if rayResult then
                local hum2 = c:FindFirstChildOfClass("Humanoid")
                local offset = (hum2 and hum2.HipHeight or 2) + (r.Size.Y / 2)
                r.CFrame = CFrame.new(r.Position.X, rayResult.Position.Y + offset, r.Position.Z)
                r.AssemblyLinearVelocity = Vector3.zero
            end
            State.dropActive = false
            return
        end
        r.AssemblyLinearVelocity = Vector3.new(r.AssemblyLinearVelocity.X, State.DROP_ASCEND_SPEED, r.AssemblyLinearVelocity.Z)
    end)
end

local function doAutoTPDown(force)
    local char, hum, hrp = getCharData()
    if not hrp or not hum then return end
    if not force then
        if hum.FloorMaterial ~= Enum.Material.Air then return end
        if hrp.Position.Y < State.autoTPHeight then return end
    end
    local rp = RaycastParams.new()
    rp.FilterDescendantsInstances = {char}
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local ray = workspace:Raycast(hrp.Position, Vector3.new(0, -500, 0), rp)
    local targetY = ray and (ray.Position.Y + (hum.HipHeight or 2) + 1.5) or 2.5
    hrp.CFrame = CFrame.new(hrp.Position.X, targetY, hrp.Position.Z) * CFrame.Angles(0, select(2, hrp.CFrame:ToEulerAnglesYXZ()), 0)
    hrp.AssemblyLinearVelocity = Vector3.zero
end

local function startAutoTP()
    if Conns.autoTP then task.cancel(Conns.autoTP); Conns.autoTP = nil end
    Conns.autoTP = task.spawn(function()
        while State.autoTPEnabled do
            task.wait(0.1)
            pcall(function() doAutoTPDown(false) end)
        end
    end)
end

local function stopAutoTP()
    State.autoTPEnabled = false
    if Conns.autoTP then task.cancel(Conns.autoTP); Conns.autoTP = nil end
end

local function runTPFloor()
    pcall(function() doAutoTPDown(true) end)
end


-- ========================================================================
-- HORIZON ANIMATION PACK PORT
-- Local Animate-object replacement only: all Horizon pack IDs, Unwalk and
-- Hit Harder mappings are retained. No Horizon GUI, network, movement, target,
-- remote-event or loader behavior is included.
-- ========================================================================
local HORIZON_ANIMATION_PACK_LIST = {
    "OFF",
    "Unwalk",
    "Hit Harder",
    "Crazy",
    "Adidas Sports",
    "Adidas Community",
    "Adidas Aura",
    "Wicked Popular",
    "Elder",
    "Zombie",
    "Mage",
    "Catwalk Glam",
    "Astronaut",
    "Wicked \"Dancing Through Life\"",
    "Werewolf",
    "Superhero",
    "Toy",
    "No Boundaries",
    "NFL",
    "Amazon Unboxed",
    "Vampire",
    "Ninja",
    "Robot",
    "Levitation",
    "Stylish",
    "Bubbly",
    "Cartoon"
}
local HORIZON_ANIMATION_PACKS = {
    ["Crazy"] = {
        WalkAnim = 134824450619865,
        RunAnim = 134824450619865,
        JumpAnim = 121454505477205,
        FallAnim = 94788218468396,
        SwimIdle = 121454505477205,
        Swim = 121454505477205,
        Animation1 = 133806214992291,
        Animation2 = 94970088341563,
        ClimbAnim = 121454505477205,
    },
    ["Adidas Sports"] = {
        WalkAnim = 18537392113,
        RunAnim  = 18537384940,
        JumpAnim = 18537380791,
        FallAnim = 18537367238,
        SwimIdle = 18537387180,
        Swim     = 18537389531,
        Animation1 = 18537376492,
        Animation2 = 18537371272,
        ClimbAnim = 18537363391,
    },
    ["Adidas Community"] = {
        WalkAnim = 122150855457006,
        RunAnim  = 82598234841035,
        JumpAnim = 75290611992385,
        FallAnim = 98600215928904,
        SwimIdle = 109346520324160,
        Swim     = 133308483266208,
        Animation1 = 122257458498464,
        Animation2 = 102357151005774,
        ClimbAnim = 88763136693023,
    },
    ["Adidas Aura"] = {
        WalkAnim = 83842218823011,
        RunAnim  = 118320322718866,
        JumpAnim = 109996626521204,
        FallAnim = 95603166884636,
        SwimIdle = 94922130551805,
        Swim     = 134530128383903,
        Animation1 = 110211186840347,
        Animation2 = 114191137265065,
        ClimbAnim = 97824616490448,
    },
    ["Wicked Popular"] = {
        WalkAnim = 92072849924640,
        RunAnim = 72301599441680,
        JumpAnim = 104325245285198,
        FallAnim = 121152442762481,
        Animation1 = 118832222982049,
        ClimbAnim = 131326830509784,
        SwimIdle = 113199415118199,
        Swim = 99384245425157,
        Animation2 = 76049494037641,
    },
    Elder = {
        WalkAnim = 10921111375,
        RunAnim  = 10921104374,
        JumpAnim = 10921107367,
        FallAnim = 10921105765,
        SwimIdle = 10921110146,
        Swim     = 10921108971,
        ClimbAnim = 10921100400,
        Animation1 = 10921101664,
        Animation2 = 10921102574,
    },
    Zombie = {
        WalkAnim = 10921355261,
        RunAnim  = 616163682,
        JumpAnim = 10921351278,
        FallAnim = 10921350320,
        SwimIdle = 10921353442,
        Swim     = 10921352344,
        Animation1 = 10921344533,
        Animation2 = 10921345304,
        ClimbAnim = 10921343576,
    },
    Mage = {
        WalkAnim = 10921152678,
        RunAnim  = 10921148209,
        JumpAnim = 10921149743,
        FallAnim = 10921148939,
        SwimIdle = 10921151661,
        Swim     = 10921150788,
        ClimbAnim = 10921143404,
        Animation1 = 10921144709,
        Animation2 = 10921145797,
    },
    ["Catwalk Glam"] = {
        WalkAnim = 109168724482748,
        RunAnim  = 81024476153754,
        JumpAnim = 116936326516985,
        FallAnim = 92294537340807,
        SwimIdle = 98854111361360,
        Swim     = 134591743181628,
        ClimbAnim = 119377220967554,
        Animation1 = 133806214992291,
        Animation2 = 94970088341563,
    },
    Astronaut = {
        WalkAnim = 10921046031,
        RunAnim  = 10921039308,
        JumpAnim = 10921042494,
        FallAnim = 10921040576,
        SwimIdle = 10921045006,
        Swim     = 10921044000,
        ClimbAnim = 10921032124,
        Animation1 = 10921034824,
        Animation2 = 10921036806,
    },
    ['Wicked "Dancing Through Life"'] = {
        WalkAnim = 73718308412641,
        RunAnim  = 135515454877967,
        JumpAnim = 78508480717326,
        FallAnim = 78147885297412,
        SwimIdle = 129183123083281,
        Swim     = 110657013921774,
        ClimbAnim = 129447497744818,
        Animation1 = 92849173543269,
        Animation2 = 132238900951109,
    },
    Werewolf = {
        WalkAnim = 10921342074,
        RunAnim  = 10921336997,
        JumpAnim = nil,
        FallAnim = 10921337907,
        SwimIdle = 10921341319,
        Swim     = 10921340419,
        ClimbAnim = 10921329322,
        Animation1 = 10921330408,
        Animation2 = 10921333667,
    },
    Superhero = {
        WalkAnim = 10921298616,
        RunAnim  = 10921291831,
        JumpAnim = 10921294559,
        FallAnim = 10921293373,
        SwimIdle = 10921297391,
        Swim     = 10921295495,
        ClimbAnim = 10921286911,
        Animation1 = 10921288909,
        Animation2 = 10921290167,
    },
    Toy = {
        WalkAnim = 10921312010,
        RunAnim  = 10921306285,
        JumpAnim = 10921308158,
        FallAnim = 10921307241,
        SwimIdle = 10921310341,
        Swim     = 10921309319,
        ClimbAnim = 10921300839,
        Animation1 = 10921301576,
        Animation2 = nil,
    },
    ["No Boundaries"] = {
        WalkAnim = 18747074203,
        RunAnim  = 18747070484,
        JumpAnim = 18747069148,
        FallAnim = 18747062535,
        SwimIdle = 18747071682,
        Swim     = 18747073181,
        ClimbAnim = 18747060903,
        Animation1 = 18747067405,
        Animation2 = 18747063918,
    },
    NFL = {
        WalkAnim = 110358958299415,
        RunAnim  = 117333533048078,
        JumpAnim = 119846112151352,
        FallAnim = 129773241321032,
        SwimIdle = 79090109939093,
        Swim     = 132697394189921,
        ClimbAnim = 134630013742019,
        Animation1 = 92080889861410,
        Animation2 = 74451233229259,
    },
    ["Amazon Unboxed"] = {
        WalkAnim = 90478085024465,
        RunAnim  = 134824450619865,
        JumpAnim = 121454505477205,
        FallAnim = 94788218468396,
        SwimIdle = 129126268464847,
        Swim     = 105962919001086,
        ClimbAnim = 121145883950231,
        Animation1 = 98281136301627,
        Animation2 = nil,
    },
    Vampire = {
        WalkAnim = 10921326949,
        RunAnim  = 10921320299,
        JumpAnim = 10921322186,
        FallAnim = 10921321317,
        SwimIdle = 10921325443,
        Swim     = 10921324408,
        ClimbAnim = 10921314188,
        Animation1 = 10921315373,
        Animation2 = nil,
    },
    Ninja = {
        Run=656118852, Walk=656121766, Jump=656117878, Fall=656115606,
        Swim=656119721, SwimIdle=656121397, Climb=656114359,
        Idle={656117400,656118341,886742569}
    },
    Robot = {
        Run=616091570, Walk=616095330, Jump=616090535, Fall=616087089,
        Swim=616092998, SwimIdle=616094091, Climb=616086039,
        Idle={616088211,616089559,885531463}
    },
    Levitation = {
        Run=616010382, Walk=616013216, Jump=616008936, Fall=616005863,
        Swim=616011509, SwimIdle=616012453, Climb=616003713,
        Idle={616006778,616008087,886862142}
    },
    Stylish = {
        Run=616140816, Walk=616146177, Jump=616139451, Fall=616134815,
        Swim=616143378, SwimIdle=616144772, Climb=616133594,
        Idle={616136790,616138447,886888594}
    },
    Bubbly = {
        Run=910025107, Walk=910034870, Jump=910016857, Fall=910001910,
        Swim=910028158, SwimIdle=910030921, Climb=909997997,
        Idle={910004836,910009958,1018536639}
    },
    Cartoon = {
        Run=742638842, Walk=742640026, Jump=742637942, Fall=742637151,
        Swim=742639220, SwimIdle=742639812, Climb=742636889,
        Idle={742637544,742638445,885477856}
    },
}

local AnimPack = {alive = true, selected = "OFF", originals = setmetatable({}, {__mode = "k"}), connections = {}}
do
    local HIT_HARDER = {
        idle1 = "rbxassetid://133806214992291", idle2 = "rbxassetid://94970088341563",
        walk = "rbxassetid://707897309", run = "rbxassetid://707861613",
        jump = "rbxassetid://116936326516985", fall = "rbxassetid://116936326516985",
    }

    local function isKnownPack(name)
        return type(name) == "string" and table.find(HORIZON_ANIMATION_PACK_LIST, name) ~= nil
    end
    local function getAnimate(character)
        return character and character:FindFirstChild("Animate") or nil
    end
    local function stopTracks(character)
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end
        for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
            pcall(function() track:Stop(0) end)
        end
    end
    local function rememberOriginal(character)
        if not character or AnimPack.originals[character] then return end
        local animate = getAnimate(character)
        if animate then AnimPack.originals[character] = animate:Clone() end
    end
    local function refreshAnimate(animate)
        if not animate then return end
        pcall(function()
            animate.Disabled = true
            task.wait(0.03)
            if animate.Parent then animate.Disabled = false end
        end)
    end
    local function restoreOriginal(character)
        if not character then return end
        local original = AnimPack.originals[character]
        if not original then return end
        stopTracks(character)
        local current = getAnimate(character)
        if current then current:Destroy() end
        local restored = original:Clone()
        restored.Parent = character
        refreshAnimate(restored)
    end
    local function setAnim(animation, id)
        if not animation or not id then return end
        local value = tostring(id)
        if not value:find("rbxassetid://", 1, true) then value = "rbxassetid://" .. value end
        pcall(function() animation.AnimationId = value end)
    end
    local function ensureAnimation(folder, name)
        if not folder then return nil end
        local animation = folder:FindFirstChild(name)
        if not animation then
            animation = Instance.new("Animation")
            animation.Name = name
            animation.Parent = folder
        end
        return animation
    end
    local function pick(pack, ...)
        for i = 1, select("#", ...) do
            local value = pack[select(i, ...)]
            if value ~= nil then return value end
        end
        return nil
    end
    local function releaseUnwalk()
        if AnimPack.selected == "Unwalk" and State.unwalkEnabled then
            stopUnwalk()
            State.unwalkEnabled = false
            if setUnwalkVisual then setUnwalkVisual(false) end
        end
    end
    local function applyHitHarder(character)
        local animate = getAnimate(character)
        if not animate then return end
        rememberOriginal(character)
        stopTracks(character)
        setAnim(animate.idle and animate.idle:FindFirstChild("Animation1"), HIT_HARDER.idle1)
        setAnim(animate.idle and animate.idle:FindFirstChild("Animation2"), HIT_HARDER.idle2)
        setAnim(animate.walk and animate.walk:FindFirstChild("WalkAnim"), HIT_HARDER.walk)
        setAnim(animate.run and animate.run:FindFirstChild("RunAnim"), HIT_HARDER.run)
        setAnim(animate.jump and animate.jump:FindFirstChild("JumpAnim"), HIT_HARDER.jump)
        setAnim(animate.fall and animate.fall:FindFirstChild("FallAnim"), HIT_HARDER.fall)
        refreshAnimate(animate)
    end
    local function applyDataPack(character, pack)
        local animate = getAnimate(character)
        if not animate or not pack then return end
        rememberOriginal(character)
        stopTracks(character)
        local run = ensureAnimation(animate:FindFirstChild("run"), "RunAnim")
        local walk = ensureAnimation(animate:FindFirstChild("walk"), "WalkAnim")
        local jump = ensureAnimation(animate:FindFirstChild("jump"), "JumpAnim")
        local fall = ensureAnimation(animate:FindFirstChild("fall"), "FallAnim")
        local climb = ensureAnimation(animate:FindFirstChild("climb"), "ClimbAnim")
        local swim = ensureAnimation(animate:FindFirstChild("swim"), "Swim")
        local swimIdle = ensureAnimation(animate:FindFirstChild("swimidle"), "SwimIdle")
        setAnim(walk, pick(pack, "WalkAnim", "Walk", "walk"))
        setAnim(run, pick(pack, "RunAnim", "Run", "run"))
        setAnim(jump, pick(pack, "JumpAnim", "Jump", "jump"))
        setAnim(fall, pick(pack, "FallAnim", "Fall", "fall"))
        setAnim(climb, pick(pack, "ClimbAnim", "Climb", "climb"))
        setAnim(swim, pick(pack, "Swim", "swim"))
        setAnim(swimIdle, pick(pack, "SwimIdle", "swimidle") or pick(pack, "Swim", "swim"))
        local idle = animate:FindFirstChild("idle")
        if idle then
            local first, second = pick(pack, "Animation1"), pick(pack, "Animation2")
            if first or second then
                local one = ensureAnimation(idle, "Animation1")
                local two = ensureAnimation(idle, "Animation2")
                setAnim(one, first or second)
                setAnim(two, second or first or second)
            elseif pack.Idle and #pack.Idle > 0 then
                local one = ensureAnimation(idle, "Animation1")
                local two = ensureAnimation(idle, "Animation2")
                setAnim(one, pack.Idle[1])
                setAnim(two, pack.Idle[2] or pack.Idle[1])
                for index = 3, #pack.Idle do setAnim(ensureAnimation(idle, "Animation" .. index), pack.Idle[index]) end
            end
        end
        refreshAnimate(animate)
    end

    function AnimPack.apply(name)
        if not AnimPack.alive then return end
        name = isKnownPack(name) and name or "OFF"
        local previous = AnimPack.selected
        if previous == "Unwalk" and name ~= "Unwalk" then releaseUnwalk() end
        AnimPack.selected, State.animPack = name, name
        local character = LP.Character
        if name == "OFF" then
            restoreOriginal(character)
        elseif name == "Unwalk" then
            restoreOriginal(character)
            State.unwalkEnabled = true
            if setUnwalkVisual then setUnwalkVisual(true) end
            startUnwalk()
        elseif name == "Hit Harder" then
            applyHitHarder(character)
        else
            applyDataPack(character, HORIZON_ANIMATION_PACKS[name])
        end
        if AnimPack.visual then AnimPack.visual(name) end
    end
    function AnimPack.destroy()
        if not AnimPack.alive then return end
        if AnimPack.selected == "Unwalk" then releaseUnwalk() end
        restoreOriginal(LP.Character)
        AnimPack.alive = false
        for _, connection in ipairs(AnimPack.connections) do connection:Disconnect() end
        table.clear(AnimPack.connections)
    end
    table.insert(AnimPack.connections, LP.CharacterAdded:Connect(function(character)
        task.delay(0.35, function()
            if AnimPack.alive and LP.Character == character and AnimPack.selected ~= "OFF" then
                AnimPack.apply(AnimPack.selected)
            end
        end)
    end))
    UI.addCleanup(AnimPack.destroy)
end

-- ========================================================================
-- CLEAN ANTI DIE: local health/death-state logic only.
-- No donor GUI, overhead text, hotkeys, images, config or external loader.
-- Local client protection is not a guarantee against server-authoritative death.
-- ========================================================================
AntiDie = {alive = true, generation = 0, connections = {},
    deathLocks = setmetatable({}, {__mode = "k"}), healing = false}
do
    local function disconnect(connection) if connection then connection:Disconnect() end end
    -- Both the existing aimbot and this toggle use the Dead state. Neither may
    -- restore it while the other still owns it; restore the original once last.
    function AntiDie.acquireDead(humanoid, owner)
        local record = AntiDie.deathLocks[humanoid]
        if not record then
            local original = true
            pcall(function() original = humanoid:GetStateEnabled(Enum.HumanoidStateType.Dead) end)
            record = {original = original, owners = {}}
            AntiDie.deathLocks[humanoid] = record
        end
        record.owners[owner] = true
        pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
    end
    function AntiDie.releaseDead(humanoid, owner)
        local record = AntiDie.deathLocks[humanoid]
        if not record then return end
        record.owners[owner] = nil
        if next(record.owners) then
            pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
        else
            AntiDie.deathLocks[humanoid] = nil
            pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, record.original) end)
        end
    end
    local function unprotect()
        local record = AntiDie.owner
        AntiDie.owner = nil
        AntiDie.healing = false
        if not record then return end
        for _, connection in ipairs(record.connections) do disconnect(connection) end
        -- Default Roblox health restores to 100 like the donor, but custom
        -- games retain their original MaxHealth rather than being forced to 100.
        pcall(function()
            record.humanoid.MaxHealth = record.maxHealth
            record.humanoid.Health = record.maxHealth
        end)
        AntiDie.releaseDead(record.humanoid, "toggle")
    end
    local function refill(record)
        if not AntiDie.alive or not State.antiDieEnabled or AntiDie.owner ~= record
            or not record.humanoid.Parent or AntiDie.healing then return end
        AntiDie.healing = true
        pcall(function()
            if record.humanoid.Health < record.humanoid.MaxHealth then record.humanoid.Health = math.huge end
        end)
        AntiDie.healing = false
    end
    function AntiDie.protectCharacter(character, generation)
        if not AntiDie.alive or not State.antiDieEnabled or LP.Character ~= character or not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
        if not humanoid or not AntiDie.alive or not State.antiDieEnabled or generation ~= AntiDie.generation
            or LP.Character ~= character or not character.Parent then return end
        if AntiDie.owner and AntiDie.owner.humanoid == humanoid then return end
        unprotect()
        local record = {humanoid = humanoid, character = character, maxHealth = humanoid.MaxHealth, connections = {}}
        AntiDie.owner = record
        AntiDie.acquireDead(humanoid, "toggle")
        pcall(function() humanoid.MaxHealth = math.huge; humanoid.Health = math.huge end)
        table.insert(record.connections, humanoid.StateChanged:Connect(function(_, state)
            if not AntiDie.alive or not State.antiDieEnabled or AntiDie.owner ~= record then return end
            if state == Enum.HumanoidStateType.Dead then
                pcall(function() humanoid.Health = math.huge end)
                AntiDie.acquireDead(humanoid, "toggle")
            end
        end))
        table.insert(record.connections, humanoid:GetPropertyChangedSignal("Health"):Connect(function() refill(record) end))
    end
    function AntiDie.refresh()
        if AntiDie.visual then AntiDie.visual(State.antiDieEnabled) end
    end
    function AntiDie.setEnabled(on)
        if not AntiDie.alive then return end
        on = on == true
        if State.antiDieEnabled == on and (not on or AntiDie.heartbeat) then AntiDie.refresh(); return end
        AntiDie.generation += 1
        State.antiDieEnabled = on
        for _, connection in ipairs(AntiDie.connections) do disconnect(connection) end
        table.clear(AntiDie.connections)
        disconnect(AntiDie.heartbeat); AntiDie.heartbeat = nil
        unprotect()
        if on then
            local generation = AntiDie.generation
            task.spawn(AntiDie.protectCharacter, LP.Character, generation)
            table.insert(AntiDie.connections, LP.CharacterRemoving:Connect(function()
                AntiDie.generation += 1
                unprotect()
            end))
            table.insert(AntiDie.connections, LP.CharacterAdded:Connect(function(character)
                local currentGeneration = AntiDie.generation
                task.delay(0.1, function() AntiDie.protectCharacter(character, currentGeneration) end)
            end))
            AntiDie.heartbeat = RunService.Heartbeat:Connect(function()
                local record = AntiDie.owner
                if record then refill(record) end
            end)
        end
        AntiDie.refresh()
    end
    function AntiDie.destroy()
        if not AntiDie.alive then return end
        AntiDie.setEnabled(false)
        AntiDie.alive = false
    end
    UI.addCleanup(AntiDie.destroy)
end


-- ========================================================================
-- INSTANT RESET: action shared by the UI and keybind.
-- It never puts the camera in Scriptable mode; the camera is always restored
-- to Custom and attached to the current/new humanoid.
-- ========================================================================
InstantReset = {
    alive = true, resetCooldown = false, lastResetAt = 0, generation = 0,
    respawnConn = nil, cameraConn = nil, connections = {},
}
do
    -- Reset must never use a Scriptable camera. Scriptable is what left the
    -- view parked at the old position whenever the character respawn event was
    -- delayed or cancelled by the game.
    local function disconnect(connection)
        if connection then pcall(function() connection:Disconnect() end) end
    end

    local function restoreCamera(character)
        local camera = workspace.CurrentCamera or Camera
        if not camera then return end
        Camera = camera
        local humanoid = character and (character:FindFirstChildOfClass("Humanoid")
            or character:FindFirstChild("Humanoid", true))
        pcall(function()
            camera.CameraType = Enum.CameraType.Custom
            if humanoid then camera.CameraSubject = humanoid end
        end)
    end

    local function finishReset(generation, character)
        if not InstantReset.alive or generation ~= InstantReset.generation then return end
        restoreCamera(character or LP.Character)
        disconnect(InstantReset.respawnConn)
        disconnect(InstantReset.cameraConn)
        InstantReset.respawnConn, InstantReset.cameraConn = nil, nil
        InstantReset.resetCooldown = false
    end

    function InstantReset.reset()
        -- Only block an accidental double-tap. Do not wait for CharacterAdded:
        -- some games delay/suppress it, which previously made the second reset
        -- look permanently disabled.
        if not InstantReset.alive or tick() - InstantReset.lastResetAt < 0.35 then return false end
        InstantReset.lastResetAt = tick()
        local character = LP.Character
        if not character then return false end
        local hrp = character:FindFirstChild("HumanoidRootPart")
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not hrp or not humanoid then return false end

        InstantReset.resetCooldown = true
        InstantReset.generation += 1
        local generation = InstantReset.generation
        disconnect(InstantReset.respawnConn)
        disconnect(InstantReset.cameraConn)
        InstantReset.respawnConn, InstantReset.cameraConn = nil, nil

        -- Keep following the current character even if the reset never makes
        -- Roblox create a new one.
        restoreCamera(character)
        InstantReset.cameraConn = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
            if InstantReset.alive and generation == InstantReset.generation then
                restoreCamera(LP.Character)
            end
        end)
        InstantReset.respawnConn = LP.CharacterAdded:Connect(function(newCharacter)
            task.delay(0.1, function()
                finishReset(generation, newCharacter)
            end)
        end)

        -- The existing launch action is retained. It no longer takes ownership
        -- of the camera, so the camera cannot become a fixed cinematic view.
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.new(0, 3e6, 0)
        end)
        task.defer(function()
            if InstantReset.alive and generation == InstantReset.generation then
                restoreCamera(LP.Character)
            end
        end)
        -- Re-enable the action after a short tap debounce rather than waiting
        -- for a respawn callback. The long camera failsafe remains independent.
        task.delay(0.35, function()
            if InstantReset.alive and generation == InstantReset.generation then
                InstantReset.resetCooldown = false
            end
        end)
        -- Failsafe for games that cancel the respawn or take too long to fire:
        -- restore normal camera control regardless.
        task.delay(1.5, function()
            finishReset(generation, LP.Character)
        end)
        return true
    end

    function InstantReset.stop()
        InstantReset.generation += 1
        disconnect(InstantReset.respawnConn)
        disconnect(InstantReset.cameraConn)
        InstantReset.respawnConn, InstantReset.cameraConn = nil, nil
        InstantReset.resetCooldown = false
        restoreCamera(LP.Character)
    end

    function InstantReset.destroy()
        if not InstantReset.alive then return end
        InstantReset.alive = false
        InstantReset.stop()
        for _, connection in ipairs(InstantReset.connections) do disconnect(connection) end
        table.clear(InstantReset.connections)
    end
    UI.addCleanup(InstantReset.destroy)
end

-- ========================================================================
-- COMBAT PROTECTION: Horizon Body Lock / Anti Fling / Instant Reset on Die.
-- Ports only local combat safety behaviour. No loaders, teleports or unrelated
-- Horizon features are included.
-- ========================================================================
local BodyLock = {alive = true, connection = nil}
do
    local function stop()
        if BodyLock.connection then BodyLock.connection:Disconnect(); BodyLock.connection = nil end
        local _, hum, root = getCharData()
        if hum then hum.AutoRotate = true end
        if root then root.AssemblyAngularVelocity = Vector3.zero end
    end

    local function step()
        if not BodyLock.alive or not State.bodyLockEnabled then return end
        local _, hum, root = getCharData()
        if not hum or not root or hum.Health <= 0 or State.tpBatEnabled then
            if hum then hum.AutoRotate = true end
            if root then root.AssemblyAngularVelocity = Vector3.zero end
            return
        end
        local target, distance = nil, math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LP and player.Character then
                local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
                local targetHum = player.Character:FindFirstChildOfClass("Humanoid")
                if targetRoot and targetHum and targetHum.Health > 0 then
                    local d = (targetRoot.Position - root.Position).Magnitude
                    if d < distance then target, distance = targetRoot, d end
                end
            end
        end
        if not target or distance > State.bodyLockRange then
            hum.AutoRotate = true
            root.AssemblyAngularVelocity = Vector3.zero
            return
        end
        -- Horizon prediction/yaw-force body lock.
        hum.AutoRotate = false
        local velocity = target.AssemblyLinearVelocity
        local predicted = target.Position + velocity * math.clamp(velocity.Magnitude / 80, 0.08, 0.35)
        local head = target.Parent and target.Parent:FindFirstChild("Head")
        local targetY = head and head.Position.Y or target.Position.Y
        local correction = math.clamp((targetY - (root.Position.Y + (hum.HipHeight or 0))) * 0.15, -1.5, 1.5)
        local flat = Vector3.new(predicted.X, root.Position.Y + correction, predicted.Z)
        if (flat - root.Position).Magnitude > 0.1 then
            local goal = CFrame.lookAt(root.Position, flat)
            local diff = root.CFrame:Inverse() * goal
            local _, yaw = diff:ToEulerAnglesXYZ()
            yaw = math.clamp(yaw, -2.5, 2.5)
            root.AssemblyAngularVelocity = root.CFrame:VectorToWorldSpace(Vector3.new(0, yaw * 42, 0))
        end
    end

    function BodyLock.setEnabled(on)
        on = on == true
        State.bodyLockEnabled = on
        stop()
        if on then BodyLock.connection = RunService.RenderStepped:Connect(step) end
        if BodyLock.visual then BodyLock.visual(on) end
    end
    function BodyLock.destroy()
        if not BodyLock.alive then return end
        BodyLock.setEnabled(false)
        BodyLock.alive = false
    end
    LP.CharacterAdded:Connect(function()
        task.delay(0.2, function()
            if BodyLock.alive and State.bodyLockEnabled then BodyLock.setEnabled(true) end
        end)
    end)
    UI.addCleanup(BodyLock.destroy)
end

local AntiFling = {alive = true, connection = nil, fixing = false, untilAt = 0}
do
    function AntiFling.step()
        if not AntiFling.alive or not State.antiFlingEnabled or State.tpBatEnabled or State.dropActive then
            AntiFling.fixing = false
            return
        end
        local _, _, root = getCharData()
        if not root then return end
        -- Horizon thresholds: cancel a strong linear/angular fling for 0.15s.
        if AntiFling.fixing then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            if os.clock() >= AntiFling.untilAt then AntiFling.fixing = false end
        elseif root.AssemblyLinearVelocity.Magnitude >= 140 or root.AssemblyAngularVelocity.Magnitude >= 90 then
            AntiFling.fixing = true
            AntiFling.untilAt = os.clock() + 0.15
        end
    end
    function AntiFling.setEnabled(on)
        State.antiFlingEnabled = on == true
        AntiFling.fixing = false
        if AntiFling.visual then AntiFling.visual(State.antiFlingEnabled) end
    end
    function AntiFling.destroy()
        if not AntiFling.alive then return end
        AntiFling.alive = false
        if AntiFling.connection then AntiFling.connection:Disconnect(); AntiFling.connection = nil end
    end
    AntiFling.connection = RunService.Heartbeat:Connect(AntiFling.step)
    UI.addCleanup(AntiFling.destroy)
end

local DeathReset = {
    alive = true, enabled = false, connections = {}, monitor = nil,
    resetThread = nil, resetCooldown = false, resetStop = false, lastAt = 0,
    activeCharacter = nil, activeHumanoid = nil, originalHipHeight = nil
}
do
    local RESET_STEP, MAX_ATTEMPTS = 0.05, 40

    local function disconnectAll()
        for _, connection in ipairs(DeathReset.connections) do connection:Disconnect() end
        table.clear(DeathReset.connections)
    end
    local function restoreCamera(character)
        local camera = workspace.CurrentCamera or Camera
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if camera then
            pcall(function()
                -- Keep the prior K2 reset fix: never leave the client in
                -- Scriptable/camera-lock mode after a death reset.
                camera.CameraType = Enum.CameraType.Custom
                if humanoid then camera.CameraSubject = humanoid end
            end)
        end
    end
    local function restoreParts(character, humanoid, originalHipHeight)
        if not character then return end
        pcall(function()
            if humanoid and humanoid.Parent then humanoid.HipHeight = originalHipHeight end
            for _, part in ipairs(character:GetChildren()) do
                if part:IsA("BasePart") then part.CanCollide = true end
            end
        end)
    end

    -- Local adaptation of Horizon's Nexus/Lord reset path: collision strip,
    -- repeated giant HipHeight reset, then a Health=0 fallback after 40 passes.
    -- It does not load anything or change server state except the local humanoid.
    local function resetPlayer()
        if not DeathReset.alive or not DeathReset.enabled or DeathReset.resetCooldown then return end
        DeathReset.resetCooldown = true
        DeathReset.resetStop = false
        DeathReset.lastAt = tick()

        -- Anti Die captures/replaces death signals. Horizon turns it off before
        -- a reset; retain that explicit conflict handling in this architecture.
        if State.antiDieEnabled then
            AntiDie.setEnabled(false)
            if AntiDie.visual then AntiDie.visual(false) end
        end

        local character = LP.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not character or not humanoid then
            DeathReset.resetCooldown = false
            restoreCamera(LP.Character)
            return
        end
        local originalHipHeight = humanoid.HipHeight
        DeathReset.activeCharacter = character
        DeathReset.activeHumanoid = humanoid
        DeathReset.originalHipHeight = originalHipHeight
        local succeeded = false
        DeathReset.resetThread = task.spawn(function()
            local attempts = 0
            while DeathReset.alive and DeathReset.enabled and not DeathReset.resetStop
                and character.Parent and LP.Character == character
                and humanoid.Parent and humanoid.Health > 0 do
                pcall(function()
                    humanoid.HipHeight = 1e30
                    humanoid.AutoRotate = true
                    for _, part in ipairs(character:GetChildren()) do
                        if part:IsA("BasePart") then part.CanCollide = false end
                    end
                end)
                attempts += 1
                if attempts >= MAX_ATTEMPTS then break end
                task.wait(RESET_STEP)
            end

            if not DeathReset.resetStop and character.Parent and LP.Character == character
                and humanoid.Parent and humanoid.Health > 0 then
                pcall(function() humanoid.Health = 0 end)
                task.wait(0.1)
            end
            succeeded = (not character.Parent) or LP.Character ~= character or humanoid.Health <= 0
            if not succeeded then restoreParts(character, humanoid, originalHipHeight) end
            DeathReset.activeCharacter, DeathReset.activeHumanoid, DeathReset.originalHipHeight = nil, nil, nil
            DeathReset.resetThread = nil
            DeathReset.resetCooldown = false
            DeathReset.resetStop = false
            restoreCamera(LP.Character)
        end)
    end

    local function onDeath(character)
        if not DeathReset.alive or not DeathReset.enabled or tick() - DeathReset.lastAt < 0.10 then return end
        -- The exact Horizon automatic trigger is a dead/absent character. This
        -- call also restores client camera ownership immediately during respawn.
        restoreCamera(character)
        resetPlayer()
    end
    local function bindCharacter(character)
        disconnectAll()
        if not DeathReset.enabled or not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
        if not humanoid or not DeathReset.enabled then return end
        table.insert(DeathReset.connections, humanoid.Died:Connect(function() onDeath(character) end))
        table.insert(DeathReset.connections, humanoid:GetPropertyChangedSignal("Health"):Connect(function()
            if humanoid.Health <= 0 then onDeath(character) end
        end))
    end
    local function startMonitor()
        if DeathReset.monitor then return end
        DeathReset.monitor = task.spawn(function()
            local absentCooldown = 0
            while DeathReset.alive and DeathReset.enabled do
                task.wait(0.1)
                local character = LP.Character
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                if not character then
                    if tick() - absentCooldown > 2 then
                        absentCooldown = tick()
                        resetPlayer()
                    end
                elseif humanoid and humanoid.Health <= 0 then
                    onDeath(character)
                end
            end
            DeathReset.monitor = nil
        end)
    end
    local function stopSequence()
        DeathReset.resetStop = true
        if DeathReset.resetThread then pcall(task.cancel, DeathReset.resetThread); DeathReset.resetThread = nil end
        -- Cleanup if the toggle is turned off halfway through a HipHeight pass.
        restoreParts(DeathReset.activeCharacter, DeathReset.activeHumanoid, DeathReset.originalHipHeight)
        DeathReset.activeCharacter, DeathReset.activeHumanoid, DeathReset.originalHipHeight = nil, nil, nil
        DeathReset.resetCooldown = false
        restoreCamera(LP.Character)
    end
    function DeathReset.setEnabled(on)
        DeathReset.enabled = on == true
        State.instantResetOnDieEnabled = DeathReset.enabled
        disconnectAll()
        stopSequence()
        if DeathReset.enabled then
            if State.antiDieEnabled then
                AntiDie.setEnabled(false)
                if AntiDie.visual then AntiDie.visual(false) end
            end
            bindCharacter(LP.Character)
            startMonitor()
        end
        if DeathReset.visual then DeathReset.visual(DeathReset.enabled) end
    end
    function DeathReset.destroy()
        if not DeathReset.alive then return end
        DeathReset.setEnabled(false)
        DeathReset.alive = false
    end
    LP.CharacterAdded:Connect(function(character)
        task.delay(0.1, function()
            if not DeathReset.alive then return end
            stopSequence()
            restoreCamera(character)
            if DeathReset.enabled then bindCharacter(character) end
        end)
    end)
    UI.addCleanup(DeathReset.destroy)
end

-- ========================================================================
-- HORIZON AUTO SWING PORT
-- Horizon's swingCurrentBat() is called on every RenderStepped pass and only
-- activates a Bat/Slap Tool when it is already equipped in the character.
-- This independent controller preserves that timing/strength without importing
-- Horizon's unrelated Aimbot target, movement, remote-event or loader code.
-- ========================================================================
local AutoSwing = {alive = true, connection = nil}
do
    local function findEquippedBat(character)
        if not character then return nil end
        for _, tool in ipairs(character:GetChildren()) do
            local name = tool.Name:lower()
            if tool:IsA("Tool") and (name:find("bat") or name:find("slap")) then
                return tool
            end
        end
        return nil
    end

    function AutoSwing.step()
        if not AutoSwing.alive or not State.autoSwingEnabled then return end
        if Combat.good and Combat.good.alive and Combat.good.enabled and State.autoBatEnabled then return end
        local character = LP.Character
        -- Exact effective Horizon swing behavior: equipped tool only, no delay
        -- or artificial cooldown between RenderStepped activations.
        local bat = findEquippedBat(character)
        if bat and bat.Parent == character and bat:IsA("Tool") then
            pcall(function() bat:Activate() end)
        end
    end
    function AutoSwing.setEnabled(on)
        State.autoSwingEnabled = on == true
        if setAutoSwingVisual then setAutoSwingVisual(State.autoSwingEnabled) end
    end
    function AutoSwing.destroy()
        if not AutoSwing.alive then return end
        AutoSwing.alive = false
        State.autoSwingEnabled = false
        if AutoSwing.connection then AutoSwing.connection:Disconnect(); AutoSwing.connection = nil end
    end
    AutoSwing.connection = RunService.RenderStepped:Connect(AutoSwing.step)
    UI.addCleanup(AutoSwing.destroy)
end

-- ========================================================================
-- DONOR COMBAT ENGINE: good.aimbot.txt (Insta Reset is a separate action).
-- Existing hub controls call these APIs; superseded motion loops are removed.
-- ========================================================================
do
    local G = {alive = true, enabled = false, generation = 0, connections = {}, antiDie = {},
        speed = 56.5, meleeOffset = 2, autoDropBrainrot = true, highlightEnabled = true}
    Combat.good = G

    local slapNames = {"Bat", "Slap", "Iron Slap", "Gold Slap", "Diamond Slap", "Emerald Slap", "Ruby Slap",
        "Dark Matter Slap", "Flame Slap", "Nuclear Slap", "Galaxy Slap", "Glitched Slap"}
    local function disconnect(connection) if connection then connection:Disconnect() end end
    local function findGoodBat()
        local char = LP.Character
        if not char then return nil end
        local backpack = LP:FindFirstChildOfClass("Backpack")
        for _, container in ipairs(backpack and {char, backpack} or {char}) do
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") and (tool.Name:lower():find("bat") or tool.Name:lower():find("slap")) then return tool end
            end
        end
        for _, name in ipairs(slapNames) do
            local tool = char:FindFirstChild(name) or (backpack and backpack:FindFirstChild(name))
            if tool then return tool end
        end
    end
    -- Shared utility for the unchanged Bat Counter feature, not an aim engine.
    function Combat.swingCounter()
        local char, hum = getCharData()
        if not char or not hum then return end
        local bat = findGoodBat()
        if not bat then return end
        if bat.Parent ~= char then pcall(function() hum:EquipTool(bat) end) end
        local remote = bat:FindFirstChildOfClass("RemoteEvent") or bat:FindFirstChildOfClass("RemoteFunction")
        if remote and remote:IsA("RemoteEvent") then pcall(function() remote:FireServer() end)
        else pcall(function() bat:Activate() end) end
    end

    -- good.aimbot: locked target, speed 56.5, prediction /150 (0.05..0.2),
    -- 2-stud behind offset, +2.6 height, -15 degree pitch, optional jump-drop.
    -- Repair the previous version's unscoped workspace highlight only.
    -- Never remove highlights belonging to the game or to other scripts.
    for _, effect in ipairs(workspace:GetChildren()) do
        if effect:IsA("Highlight") and effect.Name == "K2AimbotTarget" then
            effect.Enabled = false
            effect:Destroy()
        elseif effect:IsA("Folder") and effect.Name == "K2DuelsEffects"
            and effect:GetAttribute("K2DuelsOwned") == true then
            effect:Destroy()
        end
    end
    G.effects = Instance.new("Folder")
    G.effects.Name = "K2DuelsEffects"
    G.effects:SetAttribute("K2DuelsOwned", true)
    G.effects.Parent = workspace
    G.highlight = Instance.new("Highlight")
    -- Highlight defaults to its parent when Adornee is nil. Disable it BEFORE
    -- parenting and use a geometry-free holder, NEVER Workspace as its parent.
    G.highlight.Enabled = false
    G.highlight.Name = "K2AimbotTarget"
    G.highlight.FillColor, G.highlight.OutlineColor = UI.theme.accent, UI.theme.light
    G.highlight.FillTransparency, G.highlight.OutlineTransparency = 0.5, 0
    G.highlight.Adornee = nil
    G.highlight.Parent = G.effects
    function G.setHighlightTarget(character)
        local valid = G.alive and G.enabled and State.autoBatEnabled and G.highlightEnabled
            and typeof(character) == "Instance" and character ~= workspace and character ~= LP.Character
            and character:IsA("Model") and character.Parent ~= nil
            and character:FindFirstChildOfClass("Humanoid") and character:FindFirstChild("HumanoidRootPart")
        if not valid then character = nil end
        if G.highlightTarget ~= character then
            disconnect(G.highlightTargetGone)
            G.highlightTargetGone = nil
            G.highlightTarget = character
            if character then
                G.highlightTargetGone = character.Destroying:Connect(function()
                    if G.highlightTarget == character then G.setHighlightTarget(nil) end
                end)
            end
        end
        if character then
            if G.highlight.Adornee ~= character then
                G.highlight.Enabled = false
                G.highlight.Adornee = character
            end
            G.highlight.Enabled = true
        else
            G.highlight.Enabled = false
            G.highlight.Adornee = nil
        end
    end
    -- Printed V1 target selection: choose the closest living player's HumanoidRootPart
    -- on every RenderStepped update (no sticky target lock).
    local function getGoodTarget(root)
        local bestPart, bestCharacter, bestDistance = nil, nil, math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LP and player.Character then
                local character = player.Character
                local part = character:FindFirstChild("HumanoidRootPart")
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                if part and humanoid and humanoid.Health > 0 then
                    local distance = (part.Position - root.Position).Magnitude
                    if distance < bestDistance then
                        bestPart, bestCharacter, bestDistance = part, character, distance
                    end
                end
            end
        end
        return bestPart, bestCharacter
    end
    local function restoreGoodOwner()
        for _, connection in ipairs(G.antiDie) do disconnect(connection) end
        table.clear(G.antiDie)
        if G.owner then
            local owner = G.owner
            pcall(function()
                owner.humanoid.BreakJointsOnDeath = owner.breakJoints
                AntiDie.releaseDead(owner.humanoid, "aimbot")
                owner.humanoid.AutoRotate = owner.autoRotate
                if G.dropping then owner.humanoid.Jump = false end
            end)
            pcall(function() owner.root.AssemblyLinearVelocity = Vector3.zero end)
        end
        G.owner, G.dropping = nil, false
    end
    local function bindGood(humanoid, root)
        if G.owner and G.owner.humanoid == humanoid then return end
        restoreGoodOwner()
        local enabled = true
        pcall(function() enabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Dead) end)
        G.owner = {humanoid = humanoid, root = root, breakJoints = humanoid.BreakJointsOnDeath,
            deadEnabled = enabled, autoRotate = humanoid.AutoRotate}
        humanoid.BreakJointsOnDeath = false
        AntiDie.acquireDead(humanoid, "aimbot")
        table.insert(G.antiDie, humanoid:GetPropertyChangedSignal("Health"):Connect(function()
            if G.alive and G.enabled and State.autoBatEnabled and G.owner and G.owner.humanoid == humanoid and humanoid.Health <= 0 then
                humanoid.Health = humanoid.MaxHealth
            end
        end))
    end
    local function holdingBrainrot(char)
        for _, tool in ipairs(char:GetChildren()) do
            if tool:IsA("Tool") then
                local name = tool.Name:lower()
                if not name:find("bat") and not name:find("slap") and not name:find("medusa") then return true end
            end
        end
        return false
    end
    -- Printed V1 Aimbot movement logic, transplanted to K2's existing toggle/UI.
    -- Target selection, prediction, velocity and angular movement mirror Printed V1.
    -- This V1 mode does not set Humanoid.Jump or run an automatic jump/drop routine.
    G.savedAutoRotate = nil
    function G.step()
        if not G.alive or not G.enabled or not State.autoBatEnabled then
            G.setHighlightTarget(nil)
            return
        end

        local character = LP.Character
        if not character then G.setHighlightTarget(nil); return end
        local root = character:FindFirstChild("HumanoidRootPart")
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not root or not humanoid or humanoid.Health <= 0 then
            G.setHighlightTarget(nil)
            return
        end

        if G.savedAutoRotate == nil then G.savedAutoRotate = humanoid.AutoRotate end
        humanoid.AutoRotate = false

        if not character:FindFirstChildOfClass("Tool") then
            local bat = findGoodBat()
            if bat then pcall(function() humanoid:EquipTool(bat) end) end
        end

        local target, targetCharacter = getGoodTarget(root)
        if not target or not target.Parent or not targetCharacter or not targetCharacter.Parent then
            G.setHighlightTarget(nil)
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            return
        end

        G.setHighlightTarget(targetCharacter)
        local targetVelocity = target.AssemblyLinearVelocity
        local position = root.Position
        local targetPosition = target.Position
        local offset = targetPosition + targetVelocity * 0.14 + target.CFrame.LookVector * 0.3 - position
        local horizontal = Vector3.new(offset.X, 0, offset.Z)
        if horizontal.Magnitude > 0.001 then
            local moveSpeed = State.laggerToggled and 40 or 58
            local verticalValue = (targetPosition.Y + 3.7 - position.Y) * 19.5 + targetVelocity.Y * 0.8
            local vertical
            if humanoid.FloorMaterial ~= Enum.Material.Air then
                vertical = math.max(verticalValue, 13)
            else
                vertical = verticalValue
            end
            local desiredVelocity = Vector3.new(horizontal.Unit.X * moveSpeed,
                math.clamp(vertical, -70, 110), horizontal.Unit.Z * moveSpeed)
            root.AssemblyLinearVelocity = root.AssemblyLinearVelocity:Lerp(desiredVelocity, 0.8)
        end

        local predicted = targetPosition + targetVelocity * math.clamp(targetVelocity.Magnitude / 150, 0.05, 0.2)
        if (predicted - position).Magnitude > 0.1 then
            local targetCFrame = CFrame.lookAt(position, predicted)
            local rx, ry, rz = (root.CFrame:Inverse() * targetCFrame):ToEulerAnglesXYZ()
            root.AssemblyAngularVelocity = root.CFrame:VectorToWorldSpace(Vector3.new(
                math.clamp(rx, -2.5, 2.5) * 42,
                math.clamp(ry, -2.5, 2.5) * 42,
                math.clamp(rz, -2.5, 2.5) * 42))
        end

        -- Printed V1 swings from this same loop when Auto Swing is enabled.
        if State.autoSwingEnabled then
            local tool = character:FindFirstChildOfClass("Tool")
            if tool then pcall(function() tool:Activate() end) end
        end
    end
    function G.stopLoop()
        G.generation += 1
        disconnect(G.heartbeat); G.heartbeat = nil
        restoreGoodOwner()
        local character = LP.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if humanoid and G.savedAutoRotate ~= nil then humanoid.AutoRotate = G.savedAutoRotate end
        G.savedAutoRotate = nil
        if root then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
        G.locked, G.noTargetSince = nil, nil
        G.setHighlightTarget(nil)
    end
    function G.startLoop()
        G.stopLoop()
        G.heartbeat = RunService.RenderStepped:Connect(G.step)
    end
    function G.setEnabled(on)
        on = on == true
        if not G.alive then return end
        G.enabled, State.autoBatEnabled = on, on
        if on then
            if not G.heartbeat then G.startLoop() end
        else G.stopLoop() end
    end

    function Combat.refresh()
        if setAutoBatVisual then setAutoBatVisual(State.autoBatEnabled) end
        if Combat.mobileGood then Combat.mobileGood(State.autoBatEnabled) end
    end
    function Combat.stopGood()
        G.setEnabled(false)
        if Combat.autoTPWasEnabled then
            Combat.autoTPWasEnabled = false
            State.autoTPEnabled = true
            if setAutoTPVisual then setAutoTPVisual(true) end
            startAutoTP()
        end
        Combat.refresh()
    end
    function Combat.startGood()
        if State.autoLeftEnabled then State.autoLeftEnabled = false; if Conns.autoLeft then Conns.autoLeft:Disconnect(); Conns.autoLeft = nil end end
        if State.autoRightEnabled then State.autoRightEnabled = false; if Conns.autoRight then Conns.autoRight:Disconnect(); Conns.autoRight = nil end end
        if not G.enabled and State.autoTPEnabled then Combat.autoTPWasEnabled = true; stopAutoTP() end
        G.setEnabled(true)
        Combat.refresh()
    end
    function Combat.destroy()
        G.setEnabled(false)
        G.alive = false
        for _, connection in ipairs(G.connections) do disconnect(connection) end
        table.clear(G.connections)
        G.effects:Destroy()
    end
    table.insert(G.connections, LP.CharacterRemoving:Connect(function() G.stopLoop() end))
    table.insert(G.connections, LP.CharacterAdded:Connect(function(character)
        task.delay(0.5, function()
            if LP.Character ~= character or not G.alive then return end
            if G.enabled and State.autoBatEnabled then G.startLoop() end
        end)
    end))
    UI.addCleanup(Combat.destroy)
end
local function equipAndSwingBat() Combat.swingCounter() end
local function resetAutoBatMotion() Combat.good.stopLoop() end
local function enableAutoBat() Combat.startGood() end
local function disableAutoBat() Combat.stopGood() end
local function queueAutoBatStart() Combat.startGood() end

-- ========================================================================
-- MEDUSA & BAT COUNTER
-- ========================================================================
local function findMedusa()
    local char = LP.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") and (t.Name:lower():find("medusa") or t.Name:lower():find("head") or t.Name:lower():find("stone")) then
                return t
            end
        end
    end
    local bp = LP:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and (t.Name:lower():find("medusa") or t.Name:lower():find("head") or t.Name:lower():find("stone")) then
                return t
            end
        end
    end
    return nil
end

local function useMedusaCounter()
    if State.medusaDebounce or tick() - State.medusaLastUsed < State.MEDUSA_COOLDOWN then return end
    local char, hum = getCharData()
    if not char or not hum then return end
    
    State.medusaDebounce = true
    local med = findMedusa()
    if not med then State.medusaDebounce = false; return end
    if med.Parent ~= char then pcall(function() hum:EquipTool(med) end) end
    pcall(function() med:Activate() end)
    State.medusaLastUsed = tick()
    State.medusaDebounce = false
end

local function onAnchorChanged(part)
    return part:GetPropertyChangedSignal("Anchored"):Connect(function()
        if part.Anchored and part.Transparency == 1 then
            useMedusaCounter()
        end
    end)
end

local function setupMedusa(char)
    for _, c in pairs(Conns.anchor) do pcall(function() c:Disconnect() end) end
    Conns.anchor = {}
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then table.insert(Conns.anchor, onAnchorChanged(part)) end
    end
    table.insert(Conns.anchor, char.DescendantAdded:Connect(function(part)
        if part:IsA("BasePart") then table.insert(Conns.anchor, onAnchorChanged(part)) end
    end))
end

local function stopMedusaCounter()
    for _, c in pairs(Conns.anchor) do pcall(function() c:Disconnect() end) end
    Conns.anchor = {}
end

local function startBatCounter()
    if Conns.batCounter then return end
    Conns.batCounter = RunService.Heartbeat:Connect(function()
        if not State.batCounterEnabled or State.batCounterDebounce then return end
        local char, hum = getCharData()
        if not hum then return end
        local st = hum:GetState()
        if st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.FallingDown then
            State.batCounterDebounce = true
            task.spawn(function()
                equipAndSwingBat()
                task.wait(0.5)
                State.batCounterDebounce = false
            end)
        end
    end)
end

local function stopBatCounter()
    if Conns.batCounter then
        Conns.batCounter:Disconnect()
        Conns.batCounter = nil
    end
    State.batCounterDebounce = false
end



-- ========================================================================
-- BILLBOARDS: SPEED INDICATOR & HIT COUNTDOWN
-- ========================================================================
local function setupSpeedIndicator(char)
    if not Speed.alive or not char then return end
    local head = char:WaitForChild("Head", 5)
    if not head or not Speed.alive or char ~= LP.Character then return end
    if Speed.billboard then pcall(function() Speed.billboard:Destroy() end) end
    for _, name in ipairs({"K2OverheadBB", "K2SpeedOnly"}) do
        local old = head:FindFirstChild(name)
        if old then old:Destroy() end
    end
    -- Invisible attachment container; its ONLY visible child is the number.
    local bb = Instance.new("BillboardGui", head)
    bb.Name = "K2SpeedOnly"
    bb.Size = UDim2.fromOffset(90, 26)
    bb.StudsOffset = Vector3.new(0, 2.8, 0)
    bb.AlwaysOnTop = true
    speedLabel = Instance.new("TextLabel", bb)
    speedLabel.Name = "SpeedValue"
    speedLabel.Size = UDim2.new(1, 0, 1, 0)
    speedLabel.BackgroundTransparency = 1
    speedLabel.BorderSizePixel = 0
    speedLabel.Text = "0.0"
    speedLabel.TextColor3 = UI.theme.accent
    speedLabel.TextStrokeColor3 = UI.theme.background
    speedLabel.TextStrokeTransparency = 0.5
    speedLabel.Font = Enum.Font.GothamBold
    speedLabel.TextSize = 18
    speedLabel.TextXAlignment = Enum.TextXAlignment.Center
    speedLabel.TextYAlignment = Enum.TextYAlignment.Center
    Speed.billboard = bb
end
UI.addCleanup(function()
    if Speed.billboard then pcall(function() Speed.billboard:Destroy() end); Speed.billboard = nil end
    speedLabel = nil
end)

local countdownBB = nil
local countdownLabel = nil
local countdownActive = false
local countdownStateConn = nil

local function createCountdownBB(char)
    if not char then return end
    local head = char:FindFirstChild("Head")
    if not head then return end
    if countdownBB then pcall(function() countdownBB:Destroy() end) end
    
    countdownBB = Instance.new("BillboardGui", head)
    countdownBB.Name = "K2CountdownBB"
    countdownBB.Size = UDim2.new(0, 140, 0, 60)
    countdownBB.StudsOffset = Vector3.new(0, 5.5, 0)
    countdownBB.AlwaysOnTop = true
    countdownBB.Enabled = false
    
    countdownLabel = Instance.new("TextLabel", countdownBB)
    countdownLabel.Size = UDim2.new(1, 0, 1, 0)
    countdownLabel.BackgroundTransparency = 1
    countdownLabel.Text = ""
    countdownLabel.Font = Enum.Font.GothamBlack
    countdownLabel.TextScaled = true
    countdownLabel.TextStrokeTransparency = 0
    countdownLabel.TextStrokeColor3 = UI.theme.background
    countdownLabel.TextColor3 = UI.theme.text
end

local function runCountdown()
    if countdownActive then return end
    countdownActive = true
    if not countdownBB or not countdownLabel then
        createCountdownBB(LP.Character)
    end
    if not countdownBB or not countdownLabel then countdownActive = false; return end
    
    countdownBB.Enabled = true
    local steps = {
        {text = "3", color = UI.theme.deep},
        {text = "2", color = UI.theme.accent},
        {text = "1", color = UI.theme.light},
        {text = "GRAB!", color = UI.theme.text},
    }
    for _, step in ipairs(steps) do
        if not countdownLabel or not countdownLabel.Parent then break end
        countdownLabel.Text = step.text
        countdownLabel.TextColor3 = step.color
        task.wait(1)
    end
    if countdownBB then countdownBB.Enabled = false end
    if countdownLabel then countdownLabel.Text = "" end
    countdownActive = false
end

local function setupCountdown(char)
    if countdownStateConn then countdownStateConn:Disconnect() end
    task.wait(0.3)
    createCountdownBB(char)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    countdownStateConn = hum.StateChanged:Connect(function(_, newState)
        if newState == Enum.HumanoidStateType.Physics
            or newState == Enum.HumanoidStateType.Ragdoll
            or newState == Enum.HumanoidStateType.FallingDown then
            task.spawn(runCountdown)
        end
    end)
end

-- Connect Character Events
LP.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    setupSpeedIndicator(char)
    setupCountdown(char)
    if State.medusaCounterEnabled then setupMedusa(char) end
    if State.batCounterEnabled then startBatCounter() end
    if State.unwalkEnabled then task.wait(0.5); startUnwalk() end
    if State.antiRagdollEnabled then startAntiRagdoll() end
end)
if LP.Character then
    setupSpeedIndicator(LP.Character)
    setupCountdown(LP.Character)
end

-- ========================================================================
-- SKY THEMES ENGINE
-- ========================================================================
local K2_SKY_TAG = "K2DuelsSkyTheme"
local currentSkyTheme = "Off"
local k2OriginalLighting = nil

local K2_SKY_PRESETS = {
    ["Off"] = {kind = "off"},
    ["Night"] = {clock = 22, brightness = 2, ambient = {110, 100, 130}, outAmb = {120, 110, 140}, sky = {stars = 4000, moon = 18, sun = 0, moonTex = true}, atm = {dens = 0.45, color = {120, 60, 180}, decay = {60, 20, 100}, glare = 0.5, haze = 1.2}},
    ["Aurora"] = {clock = 14, brightness = 3, ambient = {150, 120, 150}, outAmb = {160, 130, 160}, atm = {dens = 0.55, color = {255, 80, 200}, decay = {255, 20, 150}, glare = 2.5, haze = 3}, clouds = {cover = 0.7, dens = 0.7, color = {255, 240, 250}}},
    ["Sunset"] = {clock = 17.2, brightness = 2.5, ambient = {170, 120, 100}, outAmb = {180, 130, 110}, sky = {stars = 0, sun = 25, moon = 0}, atm = {dens = 0.5, color = {255, 130, 60}, decay = {255, 80, 30}, glare = 2, haze = 2.5}, clouds = {cover = 0.55, dens = 0.55, color = {255, 200, 140}}},
    ["Galaxy"] = {clock = 0, brightness = 1.5, ambient = {70, 60, 100}, outAmb = {80, 70, 110}, sky = {stars = 10000, moon = 30, sun = 0}, atm = {dens = 0.15, color = {40, 20, 80}, decay = {20, 10, 50}, glare = 0.3, haze = 0.5}},
    ["Blood Moon"] = {clock = 22.5, brightness = 1.6, ambient = {130, 40, 40}, outAmb = {150, 50, 50}, sky = {stars = 1500, moon = 28, sun = 0, moonTex = true}, atm = {dens = 0.6, color = {220, 30, 30}, decay = {120, 10, 10}, glare = 1.4, haze = 2}, clouds = {cover = 0.5, dens = 0.7, color = {120, 30, 30}}},
    ["Volcanic"] = {clock = 19, brightness = 2, ambient = {180, 80, 40}, outAmb = {200, 90, 50}, sky = {stars = 200, sun = 12, moon = 0}, atm = {dens = 0.75, color = {255, 60, 0}, decay = {180, 20, 0}, glare = 3, haze = 3.5}, clouds = {cover = 0.8, dens = 0.9, color = {120, 40, 20}}},
    ["Vaporwave"] = {clock = 19.5, brightness = 2.4, ambient = {180, 120, 200}, outAmb = {190, 130, 210}, sky = {stars = 1000, moon = 14}, atm = {dens = 0.45, color = {255, 100, 220}, decay = {120, 60, 255}, glare = 2.2, haze = 2.4}, clouds = {cover = 0.5, dens = 0.55, color = {200, 150, 255}}},
    ["Heaven"] = {clock = 12, brightness = 4, ambient = {240, 235, 210}, outAmb = {250, 245, 220}, sky = {sun = 16, moon = 0, stars = 0}, atm = {dens = 0.25, color = {255, 250, 220}, decay = {255, 240, 200}, glare = 3, haze = 1.5}, clouds = {cover = 0.85, dens = 0.5, color = {255, 255, 255}}},
    ["Storm"] = {clock = 15, brightness = 1.4, ambient = {90, 90, 110}, outAmb = {100, 100, 120}, sky = {stars = 0, sun = 6, moon = 0}, atm = {dens = 0.65, color = {80, 90, 120}, decay = {40, 50, 80}, glare = 0.5, haze = 3}, clouds = {cover = 0.95, dens = 0.95, color = {60, 65, 80}}},
    ["Deep Space"] = {clock = 0, brightness = 1, ambient = {30, 25, 50}, outAmb = {40, 35, 60}, sky = {stars = 15000, moon = 0, sun = 0}, atm = {dens = 0.08, color = {15, 5, 40}, decay = {5, 0, 20}, glare = 0.2, haze = 0.3}}
}

local K2_SKY_ORDER = {"Off", "Night", "Aurora", "Sunset", "Galaxy", "Blood Moon", "Volcanic", "Vaporwave", "Heaven", "Storm", "Deep Space"}

local function k2SaveOriginalLighting()
    if k2OriginalLighting then return end
    k2OriginalLighting = {
        ClockTime = Lighting.ClockTime,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        Ambient = Lighting.Ambient,
        Brightness = Lighting.Brightness,
        FogStart = Lighting.FogStart,
        FogEnd = Lighting.FogEnd,
        FogColor = Lighting.FogColor,
        GlobalShadows = Lighting.GlobalShadows,
        LightingChildren = {},
        TerrainChildren = {}
    }
    for _, child in ipairs(Lighting:GetChildren()) do
        if child:IsA("Sky") or child:IsA("Atmosphere") then
            table.insert(k2OriginalLighting.LightingChildren, child:Clone())
        end
    end
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        for _, child in ipairs(terrain:GetChildren()) do
            if child:IsA("Clouds") then
                table.insert(k2OriginalLighting.TerrainChildren, child:Clone())
            end
        end
    end
end
k2SaveOriginalLighting()

local function k2ClearSky(removeAll)
    for _, child in ipairs(Lighting:GetChildren()) do
        if child:GetAttribute(K2_SKY_TAG) or (removeAll and (child:IsA("Sky") or child:IsA("Atmosphere"))) then
            pcall(function() child:Destroy() end)
        end
    end
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        for _, child in ipairs(terrain:GetChildren()) do
            if child:GetAttribute(K2_SKY_TAG) or (removeAll and child:IsA("Clouds")) then
                pcall(function() child:Destroy() end)
            end
        end
    end
end

local function k2SkyInstance(className, parent, props)
    local inst = Instance.new(className)
    inst:SetAttribute(K2_SKY_TAG, true)
    for k, v in pairs(props or {}) do
        pcall(function() inst[k] = v end)
    end
    inst.Parent = parent
    return inst
end

local function k2Color(rgb)
    return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function k2ApplySky(mode)
    k2SaveOriginalLighting()
    k2ClearSky(true)
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    local preset = K2_SKY_PRESETS[mode]
    if not preset or preset.kind == "off" then
        if k2OriginalLighting then
            for k, v in pairs(k2OriginalLighting) do
                if k ~= "LightingChildren" and k ~= "TerrainChildren" then
                    pcall(function() Lighting[k] = v end)
                end
            end
            for _, child in ipairs(k2OriginalLighting.LightingChildren or {}) do
                pcall(function() child:Clone().Parent = Lighting end)
            end
            local offTerrain = workspace:FindFirstChildOfClass("Terrain")
            if offTerrain then
                for _, child in ipairs(k2OriginalLighting.TerrainChildren or {}) do
                    pcall(function() child:Clone().Parent = offTerrain end)
                end
            end
        end
        return
    end

    Lighting.FogStart = 0
    Lighting.FogEnd = 100000
    Lighting.FogColor = Color3.fromRGB(200, 200, 200)
    Lighting.GlobalShadows = true
    Lighting.ClockTime = preset.clock or 14
    Lighting.Brightness = preset.brightness or 2
    if preset.outAmb then Lighting.OutdoorAmbient = k2Color(preset.outAmb) end
    if preset.ambient then Lighting.Ambient = k2Color(preset.ambient) end
    if preset.sky then
        local skyProps = {}
        if preset.sky.stars then skyProps.StarCount = preset.sky.stars end
        if preset.sky.moon then skyProps.MoonAngularSize = preset.sky.moon end
        if preset.sky.sun then skyProps.SunAngularSize = preset.sky.sun end
        if preset.sky.moonTex then skyProps.MoonTextureId = "rbxasset://sky/moon.jpg" end
        k2SkyInstance("Sky", Lighting, skyProps)
    end
    if preset.atm then
        k2SkyInstance("Atmosphere", Lighting, {
            Density = preset.atm.dens or 0.3,
            Color = k2Color(preset.atm.color),
            Decay = k2Color(preset.atm.decay),
            Glare = preset.atm.glare or 1,
            Haze = preset.atm.haze or 1
        })
    end
    if preset.clouds and terrain then
        k2SkyInstance("Clouds", terrain, {
            Cover = preset.clouds.cover or 0.5,
            Density = preset.clouds.dens or 0.5,
            Color = k2Color(preset.clouds.color)
        })
    end
end

-- ========================================================================

-- ========================================================================
-- SKIN CHANGER SYSTEM & FULLSCREEN 3D CAROUSEL
-- ========================================================================

-- Best Outfits module ported from Rival Hub; exposed through the existing Skin Changer.
local function createBestOutfitsModule()
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local InsertService = game:GetService("InsertService")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local huiOk, huiResult = pcall(function() return gethui and gethui() end)
local CoreGui = huiOk and huiResult or game:GetService("CoreGui")
local LP = Players.LocalPlayer
local OUTFITS = {
{
id = 10997283529,
label = "Outfit 1",
hideOriginal = false,
hideOriginalHead = true,
clearOriginalWearables = true,
bodyItems = {115566893133129, 103980259507115, 109790632200416, 112532740065682, 120301257476322},
items = {10997283529, 125085889448130},
},
{
label = "Outfit 2",
hideOriginal = false,
clearOriginalWearables = true,
bodyItems = {115566893133129, 103980259507115, 109790632200416, 112532740065682, 120301257476322},
items = {125157548394108, 123231522991173, 74827642361405},
},
{
label = "Outfit 3",
hideOriginal = false,
clearOriginalWearables = true,
bodyItems = {115566893133129, 103980259507115, 109790632200416, 112532740065682, 120301257476322},
scales = {HeightScale = 1, WidthScale = 0.85, DepthScale = 0.88, HeadScale = 0.95, BodyTypeScale = 1, ProportionScale = 0.85},
face = 86109936998865,
faceMode = "decal",
items = {136644276218918, 132022106987543, 131740907052260},
},
{
label = "Outfit 4",
hideOriginal = false,
headless = true,
clearOriginalWearables = true,
bodyItems = {115566893133129, 103980259507115, 109790632200416, 112532740065682, 120301257476322},
scales = {HeightScale = 1, WidthScale = 0.82, DepthScale = 0.85, HeadScale = 0.95, BodyTypeScale = 1, ProportionScale = 0.9},
layeredPuffiness = 0,
items = {119331031817124, 84952305140948},
},
{
label = "Outfit 5",
hideOriginal = false,
headless = true,
clearOriginalWearables = true,
bodyItems = {115566893133129, 103980259507115, 109790632200416, 112532740065682, 120301257476322},
scales = {HeightScale = 1, WidthScale = 0.82, DepthScale = 0.85, HeadScale = 0.95, BodyTypeScale = 1, ProportionScale = 0.9},
layeredPuffiness = 0,
items = {18902416696, 17739456422, 116750288839357, 12842417046, 122223069519702},
},
{
label = "Outfit 6",
hideOriginal = false,
clearOriginalWearables = true,
items = {13935333090, 16110951997, 10632503818},
},
{
label = "Outfit 7",
hideOriginal = false,
headless = true,
clearOriginalWearables = true,
items = {74891470, 4390891467, 91274263831244, 128424248603010, 91151766440767, 17044638424},
},
{
label = "Outfit 8",
hideOriginal = false,
headless = true,
hideRightLeg = true,
localOnly = true,
clearOriginalWearables = true,
items = {76479271580913, 1402432199, 140627490971265, 128912609563885, 17449551560, 5796531729, 139607718},
},
{
label = "Outfit 9",
localOnly = true,
preserveRig = true,
hideOriginal = false,
hideLeftLeg = true,
hideRightLeg = true,
clearOriginalWearables = true,
items = {70414871864071,14863917259,133498027006138,82277826177074},
accessorySlots = {[70414871864071]=Enum.AccessoryType.Waist,[14863917259]=Enum.AccessoryType.Neck,
[133498027006138]=Enum.AccessoryType.Shoulder,[82277826177074]=Enum.AccessoryType.Sweater},
},
}
local BODY_PART_NAMES = {
Head = true, UpperTorso = true, LowerTorso = true, Torso = true,
LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
RightUpperArm = true, RightLowerArm = true, RightHand = true,
LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
["Left Arm"] = true, ["Right Arm"] = true,
["Left Leg"] = true, ["Right Leg"] = true,
}
local PART_NAME_ALIASES = {
["Korblox-Deathspeaker-Right-Leg"] = "RightUpperLeg",
}
local state = {
enabled = false,
selected = 1,
visuals = {},
hidden = {},
wearableConn = nil,
headlessConn = nil,
headlessLoop = nil,
statsLoop = nil,
savedWalkSpeed = nil,
savedJumpPower = nil,
originalDescription = nil,
descriptionCharacter = nil,
connections = {},
}
local function currentCharacter()
local character = LP.Character or LP.CharacterAdded:Wait()
local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 8)
local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 8)
return character, humanoid, root
end
local function restoreOriginalBody()
for object, saved in pairs(state.hidden) do
if object and object.Parent then
pcall(function()
if type(saved) == "table" and saved.basePart then
object.LocalTransparencyModifier = saved.localTransparency
object.Transparency = saved.transparency
elseif type(saved) == "table" and saved.properties then
for property, value in pairs(saved.properties) do object[property] = value end
elseif type(saved) == "table" and saved.property then
object[saved.property] = saved.value
elseif object:IsA("BasePart") then
object.LocalTransparencyModifier = saved
elseif object:IsA("Decal") or object:IsA("Texture") then
object.Transparency = saved
end
end)
end
end
state.hidden = {}
end
local stopHeadless
local enforceHeadless
local enforceStats
local function clearVisuals()
stopHeadless()
if state.wearableConn then
state.wearableConn:Disconnect()
state.wearableConn = nil
end
for _, object in ipairs(state.visuals) do
if object and object.Parent then pcall(function() object:Destroy() end) end
end
state.visuals = {}
restoreOriginalBody()
end
local function belongsToLocalVisual(object)
for _, visual in ipairs(state.visuals) do
if object == visual or object:IsDescendantOf(visual) then return true end
end
return false
end
local function hideOriginalBody(character)
restoreOriginalBody()
for _, object in ipairs(character:GetDescendants()) do
if not belongsToLocalVisual(object) then
if object:IsA("BasePart") then
state.hidden[object] = object.LocalTransparencyModifier
object.LocalTransparencyModifier = 1
elseif object:IsA("Decal") or object:IsA("Texture") then
state.hidden[object] = object.Transparency
object.Transparency = 1
end
end
end
end
local function hideOriginalHead(character)
local head = character:FindFirstChild("Head")
if not head or not head:IsA("BasePart") then return end
if state.hidden[head] == nil then
state.hidden[head] = {
basePart = true,
localTransparency = head.LocalTransparencyModifier,
transparency = head.Transparency,
}
elseif type(state.hidden[head]) ~= "table" then
state.hidden[head] = {
basePart = true,
localTransparency = state.hidden[head],
transparency = head.Transparency,
}
end
head.LocalTransparencyModifier = 1
head.Transparency = 1
for _, object in ipairs(head:GetDescendants()) do
if (object:IsA("Decal") or object:IsA("Texture")) and state.hidden[object] == nil then
state.hidden[object] = object.Transparency
object.Transparency = 1
end
end
end
local function hideLegSide(character, side)
local names = {side .. "UpperLeg", side .. "LowerLeg", side .. "Foot", side .. " Leg", side .. "Toe"}
for _, name in ipairs(names) do
local part = character:FindFirstChild(name)
if part and part:IsA("BasePart") then
if state.hidden[part] == nil then
state.hidden[part] = {
basePart = true,
localTransparency = part.LocalTransparencyModifier,
transparency = part.Transparency,
}
elseif type(state.hidden[part]) ~= "table" then
state.hidden[part] = {
basePart = true,
localTransparency = state.hidden[part],
transparency = part.Transparency,
}
end
part.LocalTransparencyModifier = 1
part.Transparency = 1
end
end
end
local function hideLeftLeg(character)
hideLegSide(character, "Left")
end
local function hideRightLeg(character)
hideLegSide(character, "Right")
end
stopHeadless = function()
if state.headlessConn then
pcall(state.headlessConn.Disconnect, state.headlessConn)
state.headlessConn = nil
end
if state.headlessLoop then
pcall(task.cancel, state.headlessLoop)
state.headlessLoop = nil
end
if state.statsLoop then
pcall(task.cancel, state.statsLoop)
state.statsLoop = nil
end
end
enforceHeadless = function(character, option)
stopHeadless()
if not option or not character or not (option.headless or option.hideLeftLeg or option.hideRightLeg) then return end
if option.headless then hideOriginalHead(character) end
if option.hideLeftLeg then hideLeftLeg(character) end
if option.hideRightLeg then hideRightLeg(character) end
state.headlessConn = character.ChildAdded:Connect(function(child)
if child:IsA("BasePart") and (option.hideLeftLeg or option.hideRightLeg) then
task.defer(function()
if state.enabled and LP.Character==character then
local active=OUTFITS[state.selected]
if active.hideLeftLeg then hideLeftLeg(character) end
if active.hideRightLeg then hideRightLeg(character) end end end) end
if child.Name == "Head" and child:IsA("BasePart") and OUTFITS[state.selected].headless then
task.defer(function()
if state.enabled and LP.Character == character and OUTFITS[state.selected].headless then
pcall(hideOriginalHead, character)
end
end)
end
end)
state.headlessLoop = task.spawn(function()
while state.enabled and LP.Character == character do
local opt = OUTFITS[state.selected]
if opt and opt.headless then
local head = character:FindFirstChild("Head")
if head and head:IsA("BasePart") and head.LocalTransparencyModifier < 1 then
pcall(hideOriginalHead, character)
end
end
if opt and opt.hideLeftLeg then
pcall(hideLeftLeg, character)
end
if opt and opt.hideRightLeg then
pcall(hideRightLeg, character)
end
task.wait(0.6)
end
end)
end
enforceStats = function(character)
if state.statsLoop then
pcall(task.cancel, state.statsLoop)
state.statsLoop = nil
end
state.statsLoop = task.spawn(function()
while state.enabled and LP.Character == character do
local humanoid = character:FindFirstChildOfClass("Humanoid")
if humanoid then
if state.savedWalkSpeed ~= nil and humanoid.WalkSpeed ~= state.savedWalkSpeed then
humanoid.WalkSpeed = state.savedWalkSpeed
end
if state.savedJumpPower ~= nil and humanoid.JumpPower ~= state.savedJumpPower then
humanoid.JumpPower = state.savedJumpPower
end
end
task.wait(0.4)
end
end)
end
local function hideOriginalWearables(character, watchForNew)
for _, child in ipairs(character:GetChildren()) do
if child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") then
if not child:GetAttribute("VX7LocalOnly") and state.hidden[child] == nil then
local property = child:IsA("Shirt") and "ShirtTemplate"
or child:IsA("Pants") and "PantsTemplate"
or "Graphic"
state.hidden[child] = {property = property, value = child[property]}
child[property] = ""
end
end
end
for _, child in ipairs(character:GetDescendants()) do
if (child:IsA("Accessory") or child:IsA("Accoutrement")) and not child:GetAttribute("VX7LocalOnly") then
local objects = child:GetDescendants()
if child:IsA("BasePart") then table.insert(objects, child) end
for _, object in ipairs(objects) do
if object:IsA("BasePart") then
local saved = state.hidden[object]
if saved == nil then
state.hidden[object] = {
basePart = true,
localTransparency = object.LocalTransparencyModifier,
transparency = object.Transparency,
}
elseif type(saved) ~= "table" then
state.hidden[object] = {
basePart = true,
localTransparency = saved,
transparency = object.Transparency,
}
end
object.LocalTransparencyModifier = 1
object.Transparency = 1
elseif (object:IsA("Decal") or object:IsA("Texture")) and state.hidden[object] == nil then
state.hidden[object] = object.Transparency
object.Transparency = 1
elseif (object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")) and state.hidden[object] == nil then
state.hidden[object] = {property = "Enabled", value = object.Enabled}
object.Enabled = false
end
end
end
end
if watchForNew and not state.wearableConn then
state.wearableConn = character.DescendantAdded:Connect(function(object)
if not state.enabled or not OUTFITS[state.selected].clearOriginalWearables then return end
if object:IsA("Accessory") or object:IsA("Accoutrement")
or object:FindFirstAncestorWhichIsA("Accessory")
or object:FindFirstAncestorWhichIsA("Accoutrement") then
task.defer(function()
if state.enabled and character.Parent then hideOriginalWearables(character, false) end
end)
end
end)
end
end
local function loadAssetObjects(assetId)
local insertOk, inserted = pcall(function() return InsertService:LoadAsset(assetId) end)
if insertOk and inserted then return {inserted}, "InsertService" end
local objectOk, objects = pcall(function() return game:GetObjects("rbxassetid://" .. assetId) end)
if objectOk and objects and #objects > 0 then return objects, "GetObjects" end
return nil, tostring(inserted or objects or "unknown loading error")
end
local faceTextureCache = {}
local function resolveFaceTexture(faceId)
if faceTextureCache[faceId] then return faceTextureCache[faceId] end
local objects = loadAssetObjects(faceId)
if objects then
local texture
for _, root in ipairs(objects) do
local candidates = {root}
for _, object in ipairs(root:GetDescendants()) do table.insert(candidates, object) end
for _, object in ipairs(candidates) do
if object:IsA("Decal") or object:IsA("Texture") then
texture = object.Texture
if texture and texture ~= "" then break end
end
end
pcall(function() root:Destroy() end)
if texture and texture ~= "" then break end
end
if texture and texture ~= "" then
faceTextureCache[faceId] = texture
return texture
end
end
return "rbxassetid://" .. tostring(faceId)
end
local function applyLocalFace(character, faceId)
local head = character:FindFirstChild("Head")
if not head then return false end
local face = head:FindFirstChild("face") or head:FindFirstChildWhichIsA("Decal")
if face and not face:IsA("Decal") then face = nil end
-- Remove duplicate face decals that can cover the selected outfit's face.
for _, child in ipairs(head:GetChildren()) do
if child:IsA("Decal") and child ~= face then
pcall(function() child:Destroy() end)
end
end
if face then
if state.hidden[face] == nil then
state.hidden[face] = {
properties = {Texture = face.Texture, Transparency = face.Transparency},
}
end
else
face = Instance.new("Decal")
face.Name = "face"
face.Face = Enum.NormalId.Front
face:SetAttribute("VX7LocalOnly", true)
face.Parent = head
table.insert(state.visuals, face)
end
face.Texture = resolveFaceTexture(faceId)
face.Transparency = 0
return true
end
local function applyLocalFaceStable(character, faceId)
pcall(applyLocalFace, character, faceId)
for _, delayTime in ipairs({0.2, 0.8}) do
task.delay(delayTime, function()
local option = OUTFITS[state.selected]
if state.enabled and LP.Character == character and option and option.face == faceId then
pcall(applyLocalFace, character, faceId)
end
end)
end
end
local function findCharacterAttachment(character, name)
for _, object in ipairs(character:GetDescendants()) do
if object:IsA("Attachment") and object.Name == name and not object:FindFirstAncestorWhichIsA("Accessory") then
return object
end
end
end
local function sanitizeVisual(container)
local objects = container:GetDescendants()
if container:IsA("BasePart") then table.insert(objects, container) end
for _, object in ipairs(objects) do
if object:IsA("LuaSourceContainer") then
object:Destroy()
elseif object:IsA("BasePart") then
object.Anchored = false
object.CanCollide = false
object.CanTouch = false
object.CanQuery = false
object.Massless = true
object.CastShadow = false
elseif object:IsA("JointInstance") and object.Name == "AccessoryWeld" then
object:Destroy()
end
end
end
local function weldPart(part, target)
local weld = Instance.new("WeldConstraint")
weld.Name = "VX7LocalVisualWeld"
weld.Part0 = target
weld.Part1 = part
weld.Parent = part
end
local function countStackedAccessories(character, attachmentName)
local count = 0
for _, visual in ipairs(state.visuals) do
if visual:IsA("Accessory") then
local h = visual:FindFirstChild("Handle") or visual:FindFirstChildWhichIsA("BasePart", true)
if h then
for _, child in ipairs(h:GetChildren()) do
if child:IsA("Attachment") and child.Name == attachmentName then
count = count + 1
break
end
end
end
end
end
return count
end
local function attachAccessoryLocal(accessory, character, rootPart, assetId)
local handle = accessory:FindFirstChild("Handle") or accessory:FindFirstChildWhichIsA("BasePart", true)
if not handle then return false end
sanitizeVisual(accessory)
accessory.Name = "VX7_LocalOutfit_" .. tostring(assetId)
accessory:SetAttribute("VX7AssetId", assetId)
accessory:SetAttribute("VX7LocalOnly", true)
local option=OUTFITS[state.selected]
local slot=option and option.accessorySlots and option.accessorySlots[assetId]
if slot then pcall(function() accessory.AccessoryType=slot end) end
accessory.Parent = character
local sourceAttachment
for _, child in ipairs(handle:GetChildren()) do
if child:IsA("Attachment") and findCharacterAttachment(character, child.Name) then
sourceAttachment = child
break
end
end
local targetAttachment = sourceAttachment and findCharacterAttachment(character, sourceAttachment.Name)
local targetPart = targetAttachment and targetAttachment.Parent
if targetAttachment and targetPart and targetPart:IsA("BasePart") then
handle.CFrame = targetAttachment.WorldCFrame * sourceAttachment.CFrame:Inverse()
local stacked = countStackedAccessories(character, sourceAttachment.Name)
if stacked > 0 then
handle.CFrame = handle.CFrame * CFrame.new(0, stacked * 0.15, 0)
end
else
targetPart = character:FindFirstChild("LowerTorso")
or character:FindFirstChild("Torso")
or rootPart
if not targetPart then accessory:Destroy(); return false end
handle.CFrame = rootPart.CFrame
end
weldPart(handle, targetPart)
table.insert(state.visuals, accessory)
return true
end
local function attachLooseVisual(rootObject, character, rootPart, assetId, textureId, targetPart)
local clone = rootObject:Clone()
sanitizeVisual(clone)
clone.Name = "VX7_LocalOutfit_" .. tostring(assetId)
clone:SetAttribute("VX7AssetId", assetId)
clone.Parent = character
local parts = {}
if clone:IsA("BasePart") then table.insert(parts, clone) end
for _, object in ipairs(clone:GetDescendants()) do
if object:IsA("BasePart") then table.insert(parts, object) end
end
if #parts == 0 then clone:Destroy(); return false end
local anchor = targetPart or rootPart
if textureId then
for _, part in ipairs(parts) do
if part:IsA("MeshPart") then
pcall(function() part.TextureID = "rbxassetid://" .. tostring(textureId) end)
end
end
end
local pivot = clone:IsA("Model") and clone:GetPivot() or parts[1].CFrame
for _, part in ipairs(parts) do
local offset = pivot:ToObjectSpace(part.CFrame)
part.CFrame = anchor.CFrame * offset
weldPart(part, anchor)
end
table.insert(state.visuals, clone)
return true
end
local function attachClassicClothingLocal(rootObject, character, assetId)
local candidates = {}
if rootObject:IsA("Shirt") or rootObject:IsA("Pants") or rootObject:IsA("ShirtGraphic") then
table.insert(candidates, rootObject)
end
for _, object in ipairs(rootObject:GetDescendants()) do
if object:IsA("Shirt") or object:IsA("Pants") or object:IsA("ShirtGraphic") then
table.insert(candidates, object)
end
end
local added = 0
for _, source in ipairs(candidates) do
for _, existing in ipairs(character:GetChildren()) do
if existing.ClassName == source.ClassName and not existing:GetAttribute("VX7LocalOnly") then
local property = existing:IsA("Shirt") and "ShirtTemplate"
or existing:IsA("Pants") and "PantsTemplate"
or "Graphic"
state.hidden[existing] = {property = property, value = existing[property]}
existing[property] = ""
end
end
local clone = source:Clone()
clone.Name = "VX7_LocalClothing_" .. tostring(assetId)
clone:SetAttribute("VX7AssetId", assetId)
clone:SetAttribute("VX7LocalOnly", true)
clone.Parent = character
table.insert(state.visuals, clone)
added = added + 1
end
return added
end
local function attachBodyPartsLocal(rootObject, character, assetId, textureId)
local holder = Instance.new("Model")
holder.Name = "VX7_LocalBody_" .. tostring(assetId)
holder:SetAttribute("VX7AssetId", assetId)
holder:SetAttribute("VX7LocalOnly", true)
holder.Parent = character
local bodyColors = rootObject:FindFirstChildOfClass("BodyColors")
local colorProperties = {
Head = "HeadColor", UpperTorso = "TorsoColor", LowerTorso = "TorsoColor", Torso = "TorsoColor",
LeftUpperArm = "LeftArmColor", LeftLowerArm = "LeftArmColor", LeftHand = "LeftArmColor", ["Left Arm"] = "LeftArmColor",
RightUpperArm = "RightArmColor", RightLowerArm = "RightArmColor", RightHand = "RightArmColor", ["Right Arm"] = "RightArmColor",
LeftUpperLeg = "LeftLegColor", LeftLowerLeg = "LeftLegColor", LeftFoot = "LeftLegColor", ["Left Leg"] = "LeftLegColor",
RightUpperLeg = "RightLegColor", RightLowerLeg = "RightLegColor", RightFoot = "RightLegColor", ["Right Leg"] = "RightLegColor",
}
local added = 0
local candidates = {}
if rootObject:IsA("BasePart") then table.insert(candidates, rootObject) end
for _, object in ipairs(rootObject:GetDescendants()) do
if object:IsA("BasePart") and not object:FindFirstAncestorWhichIsA("Accessory") then
table.insert(candidates, object)
end
end
for _, source in ipairs(candidates) do
local partName = source.Name
if BODY_PART_NAMES[partName] then
local target = character:FindFirstChild(partName)
if not target then
local alias = PART_NAME_ALIASES[partName]
if alias then target = character:FindFirstChild(alias) end
end
if target and target:IsA("BasePart") then
local clone = source:Clone()
for _, child in ipairs(clone:GetDescendants()) do
if child:IsA("JointInstance") or child:IsA("Constraint") or child:IsA("LuaSourceContainer") then
child:Destroy()
end
end
sanitizeVisual(clone)
clone.Name = source.Name
if clone:IsA("MeshPart") and textureId then
pcall(function() clone.TextureID = "rbxassetid://" .. tostring(textureId) end)
end
if bodyColors and colorProperties[source.Name] then
pcall(function() clone.Color = bodyColors[colorProperties[source.Name]].Color end)
end
clone.CFrame = target.CFrame
clone.Parent = holder
weldPart(clone, target)
added = added + 1
end
end
end
if added == 0 then holder:Destroy(); return 0 end
table.insert(state.visuals, holder)
return added
end
local assetInfoCache = {}
local ASSET_INFO_CACHE_FILE="RivalHubAvatarAssets.json"
pcall(function()
if isfile and readfile and isfile(ASSET_INFO_CACHE_FILE) then
local decoded=HttpService:JSONDecode(readfile(ASSET_INFO_CACHE_FILE))
if type(decoded)=="table" then for id,assetType in pairs(decoded) do
local numericId=tonumber(id);local numericType=tonumber(assetType)
if numericId and numericType then assetInfoCache[numericId]=numericType end end end end end)
local assetInfoSaveQueued=false
local function saveAssetInfoCache()
if assetInfoSaveQueued or not writefile then return end
assetInfoSaveQueued=true;task.delay(.4,function()
assetInfoSaveQueued=false;pcall(function()
local encoded={};for id,assetType in pairs(assetInfoCache) do encoded[tostring(id)]=assetType end
writefile(ASSET_INFO_CACHE_FILE,HttpService:JSONEncode(encoded)) end) end) end
local bodyPropertyByType = {
[17] = "Head", [27] = "Torso", [28] = "RightArm",
[29] = "LeftArm", [30] = "LeftLeg", [31] = "RightLeg", [79] = "Head",
}
local bodyPartAnchorNames = {
[17] = {"Head"}, [79] = {"Head"},
[27] = {"UpperTorso", "Torso"},
[28] = {"RightUpperArm", "Right Arm"},
[29] = {"LeftUpperArm", "Left Arm"},
[30] = {"LeftUpperLeg", "Left Leg"},
[31] = {"RightUpperLeg", "Right Leg"},
}
local accessoryTypeByAssetType = {
[8] = Enum.AccessoryType.Hat,
[41] = Enum.AccessoryType.Hair,
[42] = Enum.AccessoryType.Face,
[43] = Enum.AccessoryType.Neck,
[44] = Enum.AccessoryType.Shoulder,
[45] = Enum.AccessoryType.Front,
[46] = Enum.AccessoryType.Back,
[47] = Enum.AccessoryType.Waist,
[64] = Enum.AccessoryType.TShirt,
[65] = Enum.AccessoryType.Shirt,
[66] = Enum.AccessoryType.Pants,
[67] = Enum.AccessoryType.Jacket,
[68] = Enum.AccessoryType.Sweater,
[69] = Enum.AccessoryType.Shorts,
[70] = Enum.AccessoryType.LeftShoe,
[71] = Enum.AccessoryType.RightShoe,
[72] = Enum.AccessoryType.DressSkirt,
[76] = Enum.AccessoryType.Eyebrow,
[77] = Enum.AccessoryType.Eyelash,
}
local function getAssetTypeId(assetId)
if assetInfoCache[assetId] then return assetInfoCache[assetId] end
local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, assetId, Enum.InfoType.Asset)
if ok and info and info.AssetTypeId then
assetInfoCache[assetId] = info.AssetTypeId
saveAssetInfoCache()
return info.AssetTypeId
end
end
local accessoryDescriptionProperties = {
"BackAccessory", "FaceAccessory", "FrontAccessory", "HairAccessory",
"HatAccessory", "NeckAccessory", "ShouldersAccessory", "WaistAccessory",
"TShirtAccessory", "ShirtAccessory", "PantsAccessory", "JacketAccessory",
"SweaterAccessory", "ShortsAccessory", "DressSkirtAccessory",
"EyebrowAccessory", "EyelashAccessory",
}
local function createDirectDescription(option, humanoid)
local directOutfitId = option.outfitId
local completeOutfitDescription
if directOutfitId then
local ok, outfitDescription = pcall(
Players.GetHumanoidDescriptionFromOutfitId,
Players,
directOutfitId
)
if not ok or not outfitDescription then return nil end
completeOutfitDescription = outfitDescription
if not option.items and not option.face and not option.head then return outfitDescription end
end
local source = completeOutfitDescription or state.originalDescription
if not source then
local ok, applied = pcall(function() return humanoid:GetAppliedDescription() end)
if not ok or not applied then return nil end
source = applied
end
local description = source:Clone()
if completeOutfitDescription then completeOutfitDescription:Destroy() end
if not directOutfitId then
description.Shirt = 0
description.Pants = 0
description.GraphicTShirt = 0
for _, property in ipairs(accessoryDescriptionProperties) do
pcall(function() description[property] = "" end)
end
pcall(function() description:SetAccessories({}, true) end)
end
local accessories = {}
if directOutfitId then
pcall(function() accessories = description:GetAccessories(true) end)
end
local allItems = {}
for _, id in ipairs(option.bodyItems or {}) do table.insert(allItems, id) end
for _, id in ipairs(option.items or {}) do table.insert(allItems, id) end
for _, id in ipairs(allItems) do
local assetTypeId = getAssetTypeId(id)
if not assetTypeId then description:Destroy(); return nil end
local bodyProperty = bodyPropertyByType[assetTypeId]
local accessoryType = accessoryTypeByAssetType[assetTypeId]
if bodyProperty then
description[bodyProperty] = id
elseif assetTypeId == 11 then
description.Shirt = id
elseif assetTypeId == 12 then
description.Pants = id
elseif assetTypeId == 1 then
description.GraphicTShirt = id
elseif assetTypeId == 18 then
description.Face = id
elseif accessoryType then
local accessory = {
AssetId = id,
AccessoryType = accessoryType,
Order = #accessories + 1,
}
if assetTypeId >= 64 and assetTypeId <= 72 then
accessory.IsLayered = true
accessory.Puffiness = option.layeredPuffiness or 0
end
table.insert(accessories, accessory)
else
description:Destroy()
return nil
end
end
if option.face then
local faceTypeId = getAssetTypeId(option.face)
local faceBodyProperty = faceTypeId and bodyPropertyByType[faceTypeId]
local faceAccessoryType = faceTypeId and accessoryTypeByAssetType[faceTypeId]
if option.faceMode == "decal" then
if faceTypeId == 18 then description.Face = option.face end
elseif faceBodyProperty then
description[faceBodyProperty] = option.face
elseif faceAccessoryType then
table.insert(accessories, {
AssetId = option.face,
AccessoryType = faceAccessoryType,
Order = #accessories + 1,
})
elseif faceTypeId == 18 then
description.Face = option.face
end
end
if option.head then description.Head = option.head end
for property, value in pairs(option.scales or {}) do
pcall(function() description[property] = value end)
end
if option.skinColor then
for _, property in ipairs({"HeadColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor", "TorsoColor"}) do
description[property] = option.skinColor
end
end
if #accessories > 0 then
local ok = pcall(function() description:SetAccessories(accessories, true) end)
if not ok then description:Destroy(); return nil end
end
return description
end
local statusText
local function setStatus(text, good)
if not statusText or not statusText.Parent then return end
statusText.Text = text
statusText.TextColor3 = good and Color3.fromRGB(215, 255, 222) or Color3.fromRGB(190, 190, 198)
end
local function applyOutfit()
local character, humanoid, rootPart = currentCharacter()
if not character or not humanoid or not rootPart then setStatus("Character not found", false); return false end
if state.descriptionCharacter ~= character or not state.originalDescription then
state.descriptionCharacter = character
state.originalDescription = nil
local ok, applied = pcall(function() return humanoid:GetAppliedDescription() end)
if ok and applied then state.originalDescription = applied:Clone() end
end
clearVisuals()
setStatus("Loading local visual...", false)
local option = OUTFITS[state.selected]
local assetId = option.id or option.outfitId
state.skipDescriptionRestore=option.preserveRig==true
if option.forceBodyParts or option.localOnly then
setStatus("Local visual only (no rig change)...", false)
end
if (option.bodyItems or option.items or option.outfitId) and not option.forceBodyParts and not option.localOnly then
setStatus(option.outfitId and "Loading complete outfit..." or "Applying outfit and complexion...", false)
local description = createDirectDescription(option, humanoid)
if description then
local savedHead = character:FindFirstChild("Head")
local savedHealth = humanoid.Health
state.savedWalkSpeed = humanoid.WalkSpeed
state.savedJumpPower = humanoid.JumpPower
local savedCFrame = rootPart.CFrame
local savedVelocity = rootPart.AssemblyLinearVelocity
local ok = pcall(function() humanoid:ApplyDescription(description) end)
if not ok then ok = pcall(function() humanoid:ApplyDescriptionReset(description) end) end
description:Destroy()
if ok then
local currentHumanoid = character:FindFirstChildOfClass("Humanoid")
local currentRoot = character:FindFirstChild("HumanoidRootPart")
if currentHumanoid and savedHealth > 0 then
currentHumanoid.Health = math.min(savedHealth, currentHumanoid.MaxHealth)
end
if currentRoot then
currentRoot.CFrame = savedCFrame
currentRoot.AssemblyLinearVelocity = savedVelocity
currentRoot.AssemblyAngularVelocity = Vector3.zero
end
if option.face then
local faceTypeId = getAssetTypeId(option.face)
if option.faceMode == "decal" or not faceTypeId or faceTypeId == 18 then
applyLocalFaceStable(character, option.face)
end
end
state.enabled = true
enforceStats(character)
enforceHeadless(character, option)
if option.hideLeftLeg then hideLeftLeg(character) end
if option.hideRightLeg then hideRightLeg(character) end
if option.head and character:FindFirstChild("Head") == savedHead then
hideOriginalHead(character)
end
setStatus(option.label .. " applied - native avatar method", true)
return true
end
end
setStatus("Native apply failed; using visual fallback...", false)
end
local assetIds = {}
-- Load every body asset in the local fallback too. The native HumanoidDescription
-- path can fail when even one catalog asset cannot be classified by GetProductInfo.
for _, id in ipairs(option.bodyItems or {}) do table.insert(assetIds, id) end
for _, id in ipairs(option.items or {}) do table.insert(assetIds, id) end
if option.head then table.insert(assetIds, option.head) end
if #assetIds == 0 and assetId and not option.outfitId then table.insert(assetIds, assetId) end
local fallbackFaceType = option.face and getAssetTypeId(option.face)
local faceIsAccessory = option.faceMode ~= "decal"
and fallbackFaceType
and accessoryTypeByAssetType[fallbackFaceType] ~= nil
if faceIsAccessory then table.insert(assetIds, option.face) end
local attached, expected = 0, 0
local lastError
expected = expected + (option.face and not faceIsAccessory and 1 or 0)
for _, currentAssetId in ipairs(assetIds) do
local objects, method = loadAssetObjects(currentAssetId)
if objects then
for _, loadedRoot in ipairs(objects) do
local rootAttached = false
local bodyPartsAttached = false
local classics = {}
if loadedRoot:IsA("Shirt") or loadedRoot:IsA("Pants") or loadedRoot:IsA("ShirtGraphic") then
table.insert(classics, loadedRoot)
end
for _, object in ipairs(loadedRoot:GetDescendants()) do
if object:IsA("Shirt") or object:IsA("Pants") or object:IsA("ShirtGraphic") then
table.insert(classics, object)
end
end
local accessories = {}
if loadedRoot:IsA("Accessory") then
table.insert(accessories, loadedRoot)
else
for _, object in ipairs(loadedRoot:GetDescendants()) do
if object:IsA("Accessory") then table.insert(accessories, object:Clone()) end
end
end
local assetTypeId = getAssetTypeId(currentAssetId)
local isBodyPartAsset = assetTypeId ~= nil and bodyPropertyByType[assetTypeId] ~= nil
local bodyCandidates = 0
local isDeclaredBodyItem = table.find(option.bodyItems or {}, currentAssetId) ~= nil
local wantsBodyParts = not loadedRoot:IsA("Accessory")
and (isDeclaredBodyItem or option.hideOriginal or option.hideOriginalHead or currentAssetId == option.head or (option.forceBodyParts and isBodyPartAsset))
if wantsBodyParts then
local candidates = {}
if loadedRoot:IsA("BasePart") then table.insert(candidates, loadedRoot) end
for _, object in ipairs(loadedRoot:GetDescendants()) do
if object:IsA("BasePart") and not object:FindFirstAncestorWhichIsA("Accessory") then
table.insert(candidates, object)
end
end
for _, object in ipairs(candidates) do
if BODY_PART_NAMES[object.Name] or PART_NAME_ALIASES[object.Name] then bodyCandidates = bodyCandidates + 1 end
end
end
expected = expected + #classics + #accessories + bodyCandidates
if #accessories == 0 and #classics == 0 and bodyCandidates == 0 then expected = expected + 1 end
if #classics > 0 then
local ok, result = pcall(attachClassicClothingLocal, loadedRoot, character, currentAssetId)
if ok and result and result > 0 then attached = attached + result; rootAttached = true end
end
if wantsBodyParts and bodyCandidates > 0 then
local ok, result = pcall(attachBodyPartsLocal, loadedRoot, character, currentAssetId, option.headTexture)
if ok and result and result > 0 then
attached = attached + result
rootAttached = true
bodyPartsAttached = true
end
end
for _, accessory in ipairs(accessories) do
local ok, result = pcall(attachAccessoryLocal, accessory, character, rootPart, currentAssetId)
if ok and result then
attached = attached + 1
rootAttached = true
else
pcall(function() accessory:Destroy() end)
end
end
if not rootAttached and not bodyPartsAttached and #accessories == 0 and #classics == 0 then
local headAnchor = character:FindFirstChild("Head")
local anchor = rootPart
if currentAssetId == option.head then
anchor = headAnchor
elseif isBodyPartAsset then
local anchorNames = bodyPartAnchorNames[assetTypeId]
if anchorNames then
for _, name in ipairs(anchorNames) do
local target = character:FindFirstChild(name)
if target and target:IsA("BasePart") then anchor = target; break end
end
end
end
local ok, result = pcall(attachLooseVisual, loadedRoot, character, rootPart, currentAssetId, option.headTexture, anchor)
if ok and result then attached = attached + 1 end
end
if loadedRoot.Parent == nil and not table.find(state.visuals, loadedRoot) then
pcall(function() loadedRoot:Destroy() end)
end
end
else
lastError = method
end
end
local faceApplied = false
if option.face and not faceIsAccessory then
local ok, result = pcall(applyLocalFace, character, option.face)
faceApplied = ok and result == true
end
local headlessApplied = false
if option.headless then
enforceHeadless(character, option)
headlessApplied = true
end
local legApplied = false
if option.hideLeftLeg then
hideLeftLeg(character)
legApplied = true
end
if option.hideRightLeg then
hideRightLeg(character)
legApplied = true
end
local totalItems = expected
local loadedItems = attached + (faceApplied and 1 or 0)
state.enabled = attached > 0 or faceApplied or headlessApplied or legApplied
if state.enabled then
if option.preserveRig and (option.hideLeftLeg or option.hideRightLeg) then enforceHeadless(character,option) end
if option.hideOriginal then hideOriginalBody(character) end
if option.hideOriginalHead then hideOriginalHead(character) end
if option.head then hideOriginalHead(character) end
if option.clearOriginalWearables then hideOriginalWearables(character, true) end
setStatus(string.format("%s fallback - %d/%d items", option.label, loadedItems, totalItems), loadedItems == totalItems)
else
setStatus("Could not attach outfit - " .. tostring(lastError or "no 3D parts"), false)
end
return state.enabled
end
local function restoreOriginalDescription()
local description = state.originalDescription
local character = LP.Character
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
if description and humanoid and character == state.descriptionCharacter and not state.skipDescriptionRestore then
local clone = description:Clone()
local ok = pcall(function() humanoid:ApplyDescription(clone) end)
if not ok then pcall(function() humanoid:ApplyDescriptionReset(clone) end) end
clone:Destroy()
end
if state.originalDescription then state.originalDescription:Destroy() end
state.originalDescription = nil
state.descriptionCharacter = nil
state.skipDescriptionRestore=false
end
local function removeOutfit()
state.enabled = false
clearVisuals()
restoreOriginalDescription()
setStatus("Local visual removed", true)
end
return {
outfits = OUTFITS,
apply = function(index)
state.selected = math.clamp(math.floor(tonumber(index) or 1), 1, #OUTFITS)
return applyOutfit()
end,
remove = removeOutfit,
description = function(index)
local character = LP.Character
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
local option = OUTFITS[math.clamp(math.floor(tonumber(index) or 1), 1, #OUTFITS)]
if not humanoid or not option then return nil end
local strict = createDirectDescription(option, humanoid)
if strict then return strict end
local ok, applied = pcall(function() return humanoid:GetAppliedDescription() end)
if not ok or not applied then return nil end
local description = applied:Clone(); applied:Destroy()
description.Shirt=0; description.Pants=0; description.GraphicTShirt=0
for _,property in ipairs(accessoryDescriptionProperties) do pcall(function() description[property]="" end) end
pcall(function() description:SetAccessories({},true) end)
local accessories={}; local all={}
for _,id in ipairs(option.bodyItems or {}) do table.insert(all,id) end
for _,id in ipairs(option.items or {}) do table.insert(all,id) end
for _,id in ipairs(all) do
local assetTypeId=getAssetTypeId(id); local bodyProperty=assetTypeId and bodyPropertyByType[assetTypeId]; local accessoryType=assetTypeId and accessoryTypeByAssetType[assetTypeId]
if bodyProperty then description[bodyProperty]=id elseif assetTypeId==11 then description.Shirt=id elseif assetTypeId==12 then description.Pants=id elseif assetTypeId==1 then description.GraphicTShirt=id elseif assetTypeId==18 then description.Face=id elseif accessoryType then
table.insert(accessories,{AssetId=id,AccessoryType=accessoryType,Order=#accessories+1,IsLayered=assetTypeId>=64 and assetTypeId<=72,Puffiness=option.layeredPuffiness or 0}) end
end
if option.face then local faceType=getAssetTypeId(option.face); if faceType==18 then description.Face=option.face elseif faceType and bodyPropertyByType[faceType] then description[bodyPropertyByType[faceType]]=option.face elseif faceType and accessoryTypeByAssetType[faceType] then table.insert(accessories,{AssetId=option.face,AccessoryType=accessoryTypeByAssetType[faceType],Order=#accessories+1}) end end
if option.head then description.Head=option.head end
for property,value in pairs(option.scales or {}) do pcall(function() description[property]=value end) end
if #accessories>0 then pcall(function() description:SetAccessories(accessories,true) end) end
return description
end,
previewModel = function(index)
    local outfitIndex = math.clamp(math.floor(tonumber(index) or 1), 1, #OUTFITS)
    local option = OUTFITS[outfitIndex]
    if not option then return nil end

    -- Build the preview from a HumanoidDescription instead of cloning the live
    -- avatar and manually welding catalog assets (which caused giant gray slabs).
    local character = LP.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end

    local desc = nil
    local okDesc, resultDesc = pcall(function()
        return createDirectDescription(option, humanoid)
    end)
    if okDesc then desc = resultDesc end
    if not desc then return nil end

    local model = nil
    local okModel, resultModel = pcall(function()
        return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
    end)
    pcall(function() desc:Destroy() end)
    if not okModel or not resultModel then return nil end

    model.Name = "RivalOutfitPreview_" .. tostring(option.label or outfitIndex)
    for _, object in ipairs(model:GetDescendants()) do
        if object:IsA("BasePart") then
            object.Anchored = true
            object.CanCollide = false
            object.CastShadow = false
            object.LocalTransparencyModifier = 0
            if object.Name == "HumanoidRootPart" then
                object.Transparency = 1
            end
        elseif object:IsA("LuaSourceContainer") then
            object:Destroy()
        end
    end
    local previewHumanoid = model:FindFirstChildOfClass("Humanoid")
    if previewHumanoid then
        previewHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    end
    return model
end,
-- Preview that does NOT depend on MarketplaceService / HumanoidDescription.
-- createDirectDescription() aborts as soon as ONE catalog asset cannot be
-- classified by GetProductInfo, so on executors where that call is blocked the
-- description preview is nil and the carousel fell back to the blocky dummy.
-- This clones the local avatar, strips it, then dresses it with exactly the
-- same local attachment helpers used when the outfit is really applied.
previewRigModel = function(index)
    local outfitIndex = math.clamp(math.floor(tonumber(index) or 1), 1, #OUTFITS)
    local option = OUTFITS[outfitIndex]
    local character = LP.Character
    if not option or not character then return nil end

    local okClone, rig = pcall(function()
        character.Archivable = true
        local clone = character:Clone()
        character.Archivable = false
        return clone
    end)
    if not (okClone and rig) then return nil end

    -- Strip the clone down to a clean mannequin (scripts, clothes, accessories).
    for _, object in ipairs(rig:GetDescendants()) do
        if object:IsA("LuaSourceContainer") then
            pcall(function() object:Destroy() end)
        end
    end
    for _, object in ipairs(rig:GetChildren()) do
        if object:IsA("Accessory") or object:IsA("Accoutrement")
            or object:IsA("Shirt") or object:IsA("Pants") or object:IsA("ShirtGraphic")
            or object:IsA("BodyColors") then
            pcall(function() object:Destroy() end)
        end
    end

    local humanoid = rig:FindFirstChildOfClass("Humanoid")
    local rootPart = rig:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then
        pcall(function() rig:Destroy() end)
        return nil
    end
    humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

    local assetIds = {}
    for _, id in ipairs(option.bodyItems or {}) do table.insert(assetIds, id) end
    for _, id in ipairs(option.items or {}) do table.insert(assetIds, id) end
    if option.head then table.insert(assetIds, option.head) end

    local attached = 0
    for _, assetId in ipairs(assetIds) do
        local okAssets, objects = pcall(loadAssetObjects, assetId)
        if okAssets and objects then
            for _, loadedRoot in ipairs(objects) do
                local rootAttached = false
                local classics = {}
                if loadedRoot:IsA("Shirt") or loadedRoot:IsA("Pants") or loadedRoot:IsA("ShirtGraphic") then
                    table.insert(classics, loadedRoot)
                end
                for _, object in ipairs(loadedRoot:GetDescendants()) do
                    if object:IsA("Shirt") or object:IsA("Pants") or object:IsA("ShirtGraphic") then
                        table.insert(classics, object)
                    end
                end
                local accessories = {}
                if loadedRoot:IsA("Accessory") then
                    table.insert(accessories, loadedRoot)
                else
                    for _, object in ipairs(loadedRoot:GetDescendants()) do
                        if object:IsA("Accessory") then
                            local okCopy, copy = pcall(function() return object:Clone() end)
                            if okCopy and copy then table.insert(accessories, copy) end
                        end
                    end
                end

                if #classics > 0 then
                    local okClassic, count = pcall(attachClassicClothingLocal, loadedRoot, rig, assetId)
                    if okClassic and type(count) == "number" and count > 0 then
                        attached = attached + count
                        rootAttached = true
                    end
                end

                local isDeclaredBodyItem = table.find(option.bodyItems or {}, assetId) ~= nil
                if (isDeclaredBodyItem or assetId == option.head) and not loadedRoot:IsA("Accessory") then
                    local okBody, count = pcall(attachBodyPartsLocal, loadedRoot, rig, assetId, option.headTexture)
                    if okBody and type(count) == "number" and count > 0 then
                        attached = attached + count
                        rootAttached = true
                    end
                end

                for _, accessory in ipairs(accessories) do
                    local okAcc, result = pcall(attachAccessoryLocal, accessory, rig, rootPart, assetId)
                    if okAcc and result then
                        attached = attached + 1
                        rootAttached = true
                    else
                        pcall(function() accessory:Destroy() end)
                    end
                end

                if not rootAttached then
                    local anchor = rootPart
                    if assetId == option.head then anchor = rig:FindFirstChild("Head") or rootPart end
                    local okLoose, result = pcall(attachLooseVisual, loadedRoot, rig, rootPart, assetId, option.headTexture, anchor)
                    if okLoose and result then attached = attached + 1 end
                end

                if loadedRoot.Parent == nil then pcall(function() loadedRoot:Destroy() end) end
            end
        end
    end

    if option.face then pcall(applyLocalFace, rig, option.face) end

    if attached == 0 then
        pcall(function() rig:Destroy() end)
        return nil
    end

    -- Static, clean rig for the ViewportFrame.
    for _, object in ipairs(rig:GetDescendants()) do
        if object:IsA("BasePart") then
            object.Anchored = true
            object.CanCollide = false
            object.CastShadow = false
            object.LocalTransparencyModifier = 0
        elseif object:IsA("LuaSourceContainer") then
            pcall(function() object:Destroy() end)
        end
    end
    local root = rig:FindFirstChild("HumanoidRootPart")
    if root then root.Transparency = 1 end
    rig.Name = "RivalOutfitPreviewRig_" .. tostring(option.label or outfitIndex)
    return rig
end,
cleanup = function()
state.enabled = false
clearVisuals()
restoreOriginalDescription()
end,
}

end

local SkinChanger = {}
do
    local originalHumanoidDesc = nil
    local originalClothes = {shirt = nil, pants = nil, tShirt = nil}
    local originalAccessories = {}

    local function cacheOriginalPlayerAvatar()
        local char = LP.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        
        -- Cache HumanoidDescription if possible (guarantees 100% exact player avatar restore!)
        if hum and not originalHumanoidDesc then
            pcall(function()
                originalHumanoidDesc = hum:GetAppliedDescription()
            end)
            if not originalHumanoidDesc then
                pcall(function()
                    originalHumanoidDesc = Players:GetHumanoidDescriptionFromUserId(LP.UserId)
                end)
            end
        end

        -- Cache direct clothing instances
        if not originalClothes.cached then
            originalClothes.cached = true
            local s = char:FindFirstChildWhichIsA("Shirt")
            local p = char:FindFirstChildWhichIsA("Pants")
            local t = char:FindFirstChildWhichIsA("ShirtGraphic")
            originalClothes.shirt = s and s.ShirtTemplate or nil
            originalClothes.pants = p and p.PantsTemplate or nil
            originalClothes.tShirt = t and t.Graphic or nil
        end

        -- Cache original accessories
        if #originalAccessories == 0 then
            for _, item in ipairs(char:GetChildren()) do
                if item:IsA("Accessory") or item:IsA("Hat") then
                    pcall(function()
                        table.insert(originalAccessories, item:Clone())
                    end)
                end
            end
        end
    end

    local BLEED_PACKS = {
        ["Off"] = {
            name = "Default Skin",
            shirt = nil,
            pants = nil,
            headMesh = nil,
            headTexture = nil,
            headColor = Color3.fromRGB(253, 234, 141),
            torsoColor = Color3.fromRGB(13, 105, 172),
            limbColor = Color3.fromRGB(218, 134, 122),
            hatId = nil,
        },
        ["1"] = {
            name = "Outfit 1",
            accessory = 306969564,
            offset = Vector3.new(0, 0.3, 0),
            headMesh = "http://www.roblox.com/asset/?id=134079402",
            headTexture = "http://www.roblox.com/asset/?id=133940918",
            shirt = "http://www.roblox.com/asset/?id=10632503795",
            pants = "http://www.roblox.com/asset/?id=123161592384863",
            headColor = Color3.fromRGB(240, 240, 240),
            torsoColor = Color3.fromRGB(25, 25, 30),
            limbColor = Color3.fromRGB(20, 20, 25),
            hatId = 306969564,
        },
        ["2"] = {
            name = "Outfit 2",
            accessory = 1744060292,
            offset = Vector3.new(0, 1.4, -0.2),
            headMesh = "http://www.roblox.com/asset/?id=134079402",
            headTexture = "http://www.roblox.com/asset/?id=133940918",
            shirt = "http://www.roblox.com/asset/?id=11526718530",
            pants = "http://www.roblox.com/asset/?id=93710523210027",
            headColor = Color3.fromRGB(20, 20, 30),
            torsoColor = Color3.fromRGB(15, 35, 60),
            limbColor = Color3.fromRGB(15, 25, 45),
            hatId = 1744060292,
        },
        ["3"] = {
            name = "Outfit 3",
            accessory = 112564966849233,
            offset = Vector3.new(0, 0.6, 0),
            headMesh = "http://www.roblox.com/asset/?id=134079402",
            headTexture = "http://www.roblox.com/asset/?id=133940918",
            shirt = "http://www.roblox.com/asset/?id=11849088376",
            pants = "http://www.roblox.com/asset/?id=16534673928",
            headColor = Color3.fromRGB(30, 30, 35),
            torsoColor = Color3.fromRGB(20, 20, 22),
            limbColor = Color3.fromRGB(18, 18, 20),
            hatId = 112564966849233,
        },
        ["Best1"] = {
            name = "Outfit 4",
            headColor = Color3.fromRGB(225, 205, 190),
            torsoColor = Color3.fromRGB(75, 90, 140),
            limbColor = Color3.fromRGB(65, 80, 130),
            hatId = nil,
            bestOutfitIndex = 1,
        },
        ["Best2"] = {
            name = "Outfit 5",
            headColor = Color3.fromRGB(225, 205, 190),
            torsoColor = Color3.fromRGB(85, 55, 125),
            limbColor = Color3.fromRGB(75, 45, 115),
            hatId = nil,
            bestOutfitIndex = 2,
        },
        ["Best3"] = {
            name = "Outfit 6",
            headColor = Color3.fromRGB(225, 205, 190),
            torsoColor = Color3.fromRGB(45, 75, 115),
            limbColor = Color3.fromRGB(35, 65, 105),
            hatId = nil,
            bestOutfitIndex = 3,
        },
        ["Best4"] = {
            name = "Outfit 7",
            headColor = Color3.fromRGB(225, 205, 190),
            torsoColor = Color3.fromRGB(40, 40, 55),
            limbColor = Color3.fromRGB(30, 30, 45),
            hatId = nil,
            bestOutfitIndex = 4,
        },
        ["Best5"] = {
            name = "Outfit 8",
            headColor = Color3.fromRGB(225, 205, 190),
            torsoColor = Color3.fromRGB(130, 80, 120),
            limbColor = Color3.fromRGB(120, 70, 110),
            hatId = nil,
            bestOutfitIndex = 5,
        },
        ["Best6"] = {
            name = "Outfit 9",
            headColor = Color3.fromRGB(225, 205, 190),
            torsoColor = Color3.fromRGB(45, 45, 65),
            limbColor = Color3.fromRGB(35, 35, 55),
            hatId = nil,
            bestOutfitIndex = 6,
        },
        ["Best7"] = {
            name = "Outfit 10",
            headColor = Color3.fromRGB(225, 205, 190),
            torsoColor = Color3.fromRGB(25, 25, 35),
            limbColor = Color3.fromRGB(15, 15, 25),
            hatId = nil,
            bestOutfitIndex = 7,
        },
        ["Best8"] = {
            name = "Outfit 11",
            headColor = Color3.fromRGB(225, 205, 190),
            torsoColor = Color3.fromRGB(30, 70, 100),
            limbColor = Color3.fromRGB(20, 60, 90),
            hatId = nil,
            bestOutfitIndex = 8,
        },
        ["Best9"] = {
            name = "Outfit 12",
            headColor = Color3.fromRGB(225, 205, 190),
            torsoColor = Color3.fromRGB(70, 45, 90),
            limbColor = Color3.fromRGB(60, 35, 80),
            hatId = nil,
            bestOutfitIndex = 9,
        },
    }

    local PACK_ORDER = {"Off", "1", "2", "3", "Best1", "Best2", "Best3", "Best4", "Best5", "Best6", "Best7", "Best8", "Best9"}

    local function clearCurrentOutfit(char)
        if not char then return end
        for _, obj in ipairs(char:GetChildren()) do
            if obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic") or obj:IsA("Accessory") or obj:IsA("Hat") then
                pcall(function() obj:Destroy() end)
            end
        end
    end

    local function restoreOriginalAvatar()
        local char = LP.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")

        -- Attempt official HumanoidDescription restore
        local appliedDesc = false
        if hum and originalHumanoidDesc then
            pcall(function()
                hum:ApplyDescription(originalHumanoidDesc)
                appliedDesc = true
            end)
        end

        if not appliedDesc then
            -- Fallback restore via cached clothing and accessories
            clearCurrentOutfit(char)

            if originalClothes.shirt then
                local s = Instance.new("Shirt", char)
                s.ShirtTemplate = originalClothes.shirt
            end
            if originalClothes.pants then
                local p = Instance.new("Pants", char)
                p.PantsTemplate = originalClothes.pants
            end
            if originalClothes.tShirt then
                local t = Instance.new("ShirtGraphic", char)
                t.Graphic = originalClothes.tShirt
            end

            -- Restore original accessories
            for _, acc in ipairs(originalAccessories) do
                pcall(function()
                    local clone = acc:Clone()
                    if hum then
                        hum:AddAccessory(clone)
                    else
                        clone.Parent = char
                    end
                end)
            end
        end

        -- Guarantee head mesh and face are fully visible
        local head = char:FindFirstChild("Head")
        if head then
            head.Transparency = 0
            local sm = head:FindFirstChildWhichIsA("SpecialMesh")
            if sm then
                sm.MeshType = Enum.MeshType.Head
                sm.Scale = Vector3.new(1.25, 1.25, 1.25)
            end
            local face = head:FindFirstChild("face")
            if face then face.Transparency = 0 end
        end
    end

    local function applyBleedSkin(packKey)
        local config = BLEED_PACKS[packKey]
        if not config then return end
        local char = LP.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local head = char:FindFirstChild("Head") or char:WaitForChild("Head", 5)
        if not head then return end

        clearCurrentOutfit(char)

        -- Apply head mesh
        if config.headMesh then
            pcall(function()
                if head:IsA("MeshPart") then
                    head.MeshId = config.headMesh
                    if config.headTexture then head.TextureID = config.headTexture end
                else
                    local sm = head:FindFirstChildWhichIsA("SpecialMesh") or Instance.new("SpecialMesh", head)
                    sm.MeshType = Enum.MeshType.FileMesh
                    sm.MeshId = config.headMesh
                    sm.TextureId = config.headTexture or ""
                end
            end)
        end

        -- Apply shirt
        if config.shirt then
            pcall(function()
                local s = Instance.new("Shirt", char)
                s.Name = "Shirt"
                s.ShirtTemplate = config.shirt
            end)
        end

        -- Apply pants
        if config.pants then
            pcall(function()
                local p = Instance.new("Pants", char)
                p.Name = "Pants"
                p.PantsTemplate = config.pants
            end)
        end

        -- Apply accessory
        if config.accessory then
            task.spawn(function()
                local asset = nil
                pcall(function() asset = InsertService:LoadAsset(config.accessory) end)
                if not asset then
                    pcall(function()
                        local objs = game:GetObjects("rbxassetid://" .. tostring(config.accessory))
                        if objs and #objs > 0 then asset = objs[1] end
                    end)
                end
                if asset then
                    local acc = asset:IsA("Accessory") and asset or asset:FindFirstChildWhichIsA("Accessory")
                    if acc then
                        acc.Name = "BleedHat"
                        local handle = acc:FindFirstChild("Handle")
                        if handle and config.offset then
                            local att = handle:FindFirstChildWhichIsA("Attachment") or Instance.new("Attachment", handle)
                            att.Position = att.Position + config.offset
                        end
                        if hum then hum:AddAccessory(acc) else acc.Parent = char end
                    end
                end
            end)
        end
    end

    local bestOutfitsModule = nil
    local bestOutfitsBusy = false
    -- Keep the selected skin key so it can be restored after respawn.
    local activeSkinPackKey = "Off"
    local skinRespawnToken = 0

    function SkinChanger.apply(packKey)
        activeSkinPackKey = tostring(packKey or "Off")
        skinRespawnToken = skinRespawnToken + 1
        cacheOriginalPlayerAvatar()
        local bestIndex = tostring(packKey):match("^Best(%d+)$")
        if bestIndex then
            if bestOutfitsBusy then return end
            bestOutfitsBusy = true
            task.spawn(function()
                if not bestOutfitsModule then
                    local ok, module = pcall(createBestOutfitsModule)
                    if ok and type(module) == "table" then bestOutfitsModule = module end
                end
                if bestOutfitsModule and type(bestOutfitsModule.apply) == "function" then
                    local ok, applied = pcall(bestOutfitsModule.apply, tonumber(bestIndex))
                    if not ok then
                        warn("[K2 Skin Changer] Best Outfit failed: " .. tostring(applied))
                    elseif applied == false then
                        warn("[K2 Skin Changer] Best Outfit " .. tostring(bestIndex) .. " could not fully apply; check asset loading/permissions in the executor console.")
                    end
                else
                    warn("[K2 Skin Changer] Could not initialize Best Outfits module.")
                end
                bestOutfitsBusy = false
            end)
            return
        end

        if bestOutfitsModule and type(bestOutfitsModule.remove) == "function" then
            pcall(bestOutfitsModule.remove)
        end
        if packKey == "Off" then
            restoreOriginalAvatar()
        else
            applyBleedSkin(packKey)
        end
    end

    -- Reapply the last selected skin after Roblox creates the new character.
    if not _G.__K2SkinChangerRespawnHook then
        _G.__K2SkinChangerRespawnHook = true
        LP.CharacterAdded:Connect(function(newCharacter)
            local token = skinRespawnToken
            task.spawn(function()
                -- Give Roblox time to create the Humanoid, head and body parts.
                for _ = 1, 20 do
                    task.wait(0.25)
                    if LP.Character ~= newCharacter then return end
                    local hum = newCharacter:FindFirstChildOfClass("Humanoid")
                    local root = newCharacter:FindFirstChild("HumanoidRootPart")
                    if hum and root and hum.Health > 0 then break end
                end
                task.wait(0.35)
                if LP.Character ~= newCharacter or token ~= skinRespawnToken then return end
                local key = activeSkinPackKey
                if not key or key == "Off" then return end
                if key:match("^Best%d+$") then
                    bestOutfitsBusy = false
                    if not bestOutfitsModule then
                        local ok, module = pcall(createBestOutfitsModule)
                        if ok and type(module) == "table" then bestOutfitsModule = module end
                    end
                    if bestOutfitsModule and type(bestOutfitsModule.apply) == "function" then
                        local index = tonumber(key:match("^Best(%d+)$"))
                        if index then
                            local ok, err = pcall(bestOutfitsModule.apply, index)
                            if not ok then warn("[K2 Skin Changer] Respawn reapply failed: " .. tostring(err)) end
                        end
                    end
                else
                    pcall(function() applyBleedSkin(key) end)
                end
            end)
        end)
    end

    -- -------------------------------------------------------------
    -- FULLSCREEN 3D CAROUSEL VIEWER
    -- -------------------------------------------------------------
    local viewerGui = nil
    local currentSelectedIndex = 1
    local isFocusedOnSelected = false
    local rotateConns = {}

    local function cleanupViewer()
        for _, c in ipairs(rotateConns) do pcall(function() c:Disconnect() end) end
        rotateConns = {}
        if viewerGui then
            viewerGui:Destroy()
            viewerGui = nil
        end
        isFocusedOnSelected = false
    end

    function SkinChanger.openViewer()
        cacheOriginalPlayerAvatar()
        if viewerGui then cleanupViewer() end

        local parent = getSafeGuiParent()
        viewerGui = Instance.new("ScreenGui")
        viewerGui.Name = "K2SkinViewer"
        viewerGui.ResetOnSpawn = false
        viewerGui.DisplayOrder = 1000
        viewerGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        viewerGui.Parent = parent

        local backdrop = Instance.new("Frame")
        backdrop.Size = UDim2.fromScale(1, 1)
        backdrop.BackgroundColor3 = Color3.fromRGB(8, 5, 14)
        backdrop.BackgroundTransparency = 0.25
        backdrop.Parent = viewerGui

        -- Top Header
        local topBar = Instance.new("Frame")
        topBar.Size = UDim2.new(1, 0, 0, 56)
        topBar.BackgroundColor3 = Color3.fromRGB(18, 12, 28)
        topBar.BorderSizePixel = 0
        topBar.Parent = backdrop

        local headerTitle = Instance.new("TextLabel")
        headerTitle.Size = UDim2.new(0, 300, 1, 0)
        headerTitle.Position = UDim2.new(0, 24, 0, 0)
        headerTitle.BackgroundTransparency = 1
        headerTitle.Text = "SKIN CHANGER"
        headerTitle.TextColor3 = Color3.fromRGB(240, 220, 255)
        headerTitle.Font = Enum.Font.GothamBlack
        headerTitle.TextSize = 16
        headerTitle.TextXAlignment = Enum.TextXAlignment.Left
        headerTitle.Parent = topBar

        local closeXBtn = Instance.new("TextButton")
        closeXBtn.Size = UDim2.new(0, 34, 0, 34)
        closeXBtn.Position = UDim2.new(1, -48, 0.5, -17)
        closeXBtn.BackgroundColor3 = Color3.fromRGB(85, 25, 40)
        closeXBtn.Text = "X"
        closeXBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        closeXBtn.TextSize = 14
        closeXBtn.Font = Enum.Font.GothamBold
        closeXBtn.Parent = topBar
        Instance.new("UICorner", closeXBtn).CornerRadius = UDim.new(0, 8)
        closeXBtn.MouseButton1Click:Connect(cleanupViewer)

        -- Central Carousel Area
        local carousel = Instance.new("Frame")
        carousel.Name = "CarouselArea"
        carousel.Size = UDim2.new(1, -80, 1, -160)
        carousel.Position = UDim2.new(0, 40, 0, 70)
        carousel.BackgroundTransparency = 1
        carousel.Parent = backdrop

        -- Navigation Arrows
        local leftArrow = Instance.new("TextButton")
        leftArrow.Size = UDim2.new(0, 52, 0, 52)
        leftArrow.Position = UDim2.new(0, 14, 0.5, -26)
        leftArrow.BackgroundColor3 = Color3.fromRGB(40, 20, 68)
        leftArrow.Text = "◀"
        leftArrow.TextColor3 = Color3.fromRGB(255, 255, 255)
        leftArrow.TextSize = 22
        leftArrow.Font = Enum.Font.GothamBold
        leftArrow.ZIndex = 60
        leftArrow.Parent = backdrop
        Instance.new("UICorner", leftArrow).CornerRadius = UDim.new(1, 0)
        local lStroke = Instance.new("UIStroke", leftArrow)
        lStroke.Color = Color3.fromRGB(175, 92, 255)
        lStroke.Thickness = 1.5

        local rightArrow = Instance.new("TextButton")
        rightArrow.Size = UDim2.new(0, 52, 0, 52)
        rightArrow.Position = UDim2.new(1, -66, 0.5, -26)
        rightArrow.BackgroundColor3 = Color3.fromRGB(40, 20, 68)
        rightArrow.Text = "▶"
        rightArrow.TextColor3 = Color3.fromRGB(255, 255, 255)
        rightArrow.TextSize = 22
        rightArrow.Font = Enum.Font.GothamBold
        rightArrow.ZIndex = 60
        rightArrow.Parent = backdrop
        Instance.new("UICorner", rightArrow).CornerRadius = UDim.new(1, 0)
        local rStroke = Instance.new("UIStroke", rightArrow)
        rStroke.Color = Color3.fromRGB(175, 92, 255)
        rStroke.Thickness = 1.5

        -- Bottom Actions (Back & Confirm)
        local bottomActions = Instance.new("Frame")
        bottomActions.Size = UDim2.new(1, 0, 0, 70)
        bottomActions.Position = UDim2.new(0, 0, 1, -78)
        bottomActions.BackgroundTransparency = 1
        bottomActions.Visible = false
        bottomActions.ZIndex = 70
        bottomActions.Parent = backdrop

        local backBtn = Instance.new("TextButton")
        backBtn.Size = UDim2.new(0, 150, 0, 44)
        backBtn.Position = UDim2.new(0.5, -165, 0.5, -22)
        backBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 80)
        backBtn.Text = "◀ BACK"
        backBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        backBtn.Font = Enum.Font.GothamBold
        backBtn.TextSize = 14
        backBtn.Parent = bottomActions
        Instance.new("UICorner", backBtn).CornerRadius = UDim.new(0, 8)

        local confirmBtn = Instance.new("TextButton")
        confirmBtn.Size = UDim2.new(0, 160, 0, 44)
        confirmBtn.Position = UDim2.new(0.5, 15, 0.5, -22)
        confirmBtn.BackgroundColor3 = Color3.fromRGB(35, 160, 75)
        confirmBtn.Text = "CONFIRM ✔"
        confirmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        confirmBtn.Font = Enum.Font.GothamBlack
        confirmBtn.TextSize = 14
        confirmBtn.Parent = bottomActions
        Instance.new("UICorner", confirmBtn).CornerRadius = UDim.new(0, 8)

        -- Helper to create 3D avatar preview with accurate clothes & accessories
        local function createSkin3DModel(packKey)
            local packData = BLEED_PACKS[packKey]

            -- Best Outfits use a real preview assembled from Rival's outfit asset IDs,
            -- rather than K2's generic colored dummy.
            -- Preview model generation from catalog descriptions is unreliable in some
            -- executor environments. Keep the existing K2 preview builder as a safe
            -- fallback so the carousel never receives a nil/blank model. Actual outfit
            -- application still uses the Rival module when the user confirms.
            if packData and packData.bestOutfitIndex and not bestOutfitsModule then
                local ok, module = pcall(createBestOutfitsModule)
                if ok and type(module) == "table" then bestOutfitsModule = module end
            end

            local model = Instance.new("Model")
            model.Name = "SkinModel_" .. packKey

            local hum = Instance.new("Humanoid")
            hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            hum.Parent = model

            local torso = Instance.new("Part", model)
            torso.Name = "Torso"
            torso.Size = Vector3.new(2, 2, 1)
            torso.Position = Vector3.new(0, 0, 0)
            torso.Color = packData.torsoColor
            torso.Material = Enum.Material.SmoothPlastic
            torso.Anchored = true
            torso.CanCollide = false

            local head = Instance.new("Part", model)
            head.Name = "Head"
            head.Size = Vector3.new(1.2, 1.2, 1.2)
            head.Position = Vector3.new(0, 1.5, 0)
            head.Color = packData.headColor
            head.Material = Enum.Material.SmoothPlastic
            head.Anchored = true
            head.CanCollide = false

            local sm = Instance.new("SpecialMesh", head)
            if packData.headMesh then
                sm.MeshType = Enum.MeshType.FileMesh
                sm.MeshId = packData.headMesh
                sm.TextureId = packData.headTexture or ""
            else
                sm.MeshType = Enum.MeshType.Head
                sm.Scale = Vector3.new(1.25, 1.25, 1.25)
            end

            local function makeLimb(name, pos, color)
                local part = Instance.new("Part", model)
                part.Name = name
                part.Size = Vector3.new(1, 2, 1)
                part.Position = pos
                part.Color = color
                part.Material = Enum.Material.SmoothPlastic
                part.Anchored = true
                part.CanCollide = false
                return part
            end

            makeLimb("Left Arm", Vector3.new(-1.5, 0, 0), packData.limbColor)
            makeLimb("Right Arm", Vector3.new(1.5, 0, 0), packData.limbColor)
            makeLimb("Left Leg", Vector3.new(-0.5, -2, 0), packData.limbColor)
            makeLimb("Right Leg", Vector3.new(0.5, -2, 0), packData.limbColor)

            if packData.shirt then
                local s = Instance.new("Shirt", model)
                s.ShirtTemplate = packData.shirt
            end
            if packData.pants then
                local p = Instance.new("Pants", model)
                p.PantsTemplate = packData.pants
            end

            if packData.hatId then
                local hatPart = Instance.new("Part", model)
                hatPart.Name = "Hat"
                hatPart.Size = Vector3.new(1.5, 1, 1.5)
                hatPart.Position = head.Position + (packData.offset or Vector3.new(0, 0.4, 0))
                hatPart.Color = Color3.fromRGB(240, 190, 40)
                hatPart.Anchored = true
                hatPart.CanCollide = false
                local hatMesh = Instance.new("SpecialMesh", hatPart)
                hatMesh.MeshType = Enum.MeshType.FileMesh
                hatMesh.MeshId = "rbxassetid://" .. tostring(packData.hatId)
            end

            return model
        end

        local skinCards = {}
        local numSkins = #PACK_ORDER

        for i, packKey in ipairs(PACK_ORDER) do
            local packData = BLEED_PACKS[packKey]

            local card = Instance.new("Frame")
            card.Name = "SkinCard_" .. packKey
            card.Size = UDim2.new(0, 220, 0, 290)
            card.AnchorPoint = Vector2.new(0.5, 0.5)
            card.BackgroundColor3 = Color3.fromRGB(20, 12, 34)
            card.BorderSizePixel = 0
            card.ZIndex = 40
            card.Parent = carousel
            Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)

            local cardStroke = Instance.new("UIStroke", card)
            cardStroke.Color = Color3.fromRGB(175, 92, 255)
            cardStroke.Thickness = 1.5
            cardStroke.Transparency = 0.4

            local viewport = Instance.new("ViewportFrame")
            viewport.Size = UDim2.new(1, -20, 0, 220)
            viewport.Position = UDim2.new(0, 10, 0, 10)
            viewport.BackgroundTransparency = 1
            viewport.BackgroundColor3 = Color3.fromRGB(20, 12, 34)
            viewport.BorderSizePixel = 0
            viewport.LightColor = Color3.fromRGB(255, 255, 255)
            viewport.LightDirection = Vector3.new(-1, -2, -1)
            viewport.Ambient = Color3.fromRGB(210, 210, 210)
            viewport.ZIndex = 42
            viewport.Parent = card
            Instance.new("UICorner", viewport).CornerRadius = UDim.new(0, 10)

            local vpCamera = Instance.new("Camera")
            vpCamera.FieldOfView = 48
            viewport.CurrentCamera = vpCamera
            vpCamera.Parent = viewport

            local char3D = createSkin3DModel(packKey)
            char3D.Parent = viewport

            local previewCenter = Vector3.new(0, -0.3, 0)
            local previewDist = 6.4
            pcall(function()
                local boundsCFrame, boundsSize = char3D:GetBoundingBox()
                previewCenter = boundsCFrame.Position + Vector3.new(0, boundsSize.Y * 0.03, 0)
                local largest = math.max(boundsSize.X, boundsSize.Y, boundsSize.Z, 3)
                previewDist = (largest * 0.62) / math.tan(math.rad(vpCamera.FieldOfView / 2))
                previewDist = math.clamp(previewDist, 4.0, 10.5)
            end)

            -- SKINS 4-12 (Best outfits): the blocky dummy cannot show what the
            -- outfit really looks like, so build the true rig from its
            -- HumanoidDescription in the background and swap it in when ready.
            -- The dummy stays on screen until then, and is kept if it fails.
            if packData and packData.bestOutfitIndex then
                local loadingLbl = Instance.new("TextLabel")
                loadingLbl.Name = "PreviewLoading"
                loadingLbl.Size = UDim2.new(1, 0, 0, 20)
                loadingLbl.Position = UDim2.new(0, 0, 0.5, -10)
                loadingLbl.BackgroundTransparency = 1
                loadingLbl.Text = "LOADING..."
                loadingLbl.TextColor3 = Color3.fromRGB(245, 245, 250)
                loadingLbl.Font = Enum.Font.GothamBlack
                loadingLbl.TextSize = 12
                loadingLbl.ZIndex = 46
                loadingLbl.Parent = viewport

                task.spawn(function()
                    -- Stagger the background builds so the loader is not hit
                    -- by nine outfits at the exact same moment.
                    task.wait(0.12 * (i - 1))
                    local function finish()
                        if loadingLbl.Parent then pcall(function() loadingLbl:Destroy() end) end
                    end
                    if not bestOutfitsModule then
                        local okModule, module = pcall(createBestOutfitsModule)
                        if okModule and type(module) == "table" then bestOutfitsModule = module end
                    end
                    local module = bestOutfitsModule
                    local function tryBuild(builder)
                        if type(builder) ~= "function" then return nil end
                        local ok, model = pcall(builder, packData.bestOutfitIndex)
                        if ok and typeof(model) == "Instance" and model:IsA("Model") then return model end
                        if typeof(model) == "Instance" then pcall(function() model:Destroy() end) end
                        return nil
                    end
                    -- 1) HumanoidDescription rig (needs MarketplaceService,
                    --    which some executors block).
                    local realModel = module and tryBuild(module.previewModel)
                    -- 2) Local rig: clone the avatar and dress it with the same
                    --    loaders used when the outfit is really applied.
                    if not realModel then
                        realModel = module and tryBuild(module.previewRigModel)
                    end
                    if not realModel then finish(); return end

                    -- Clean rig for the ViewportFrame: no scripts, no physics.
                    for _, object in ipairs(realModel:GetDescendants()) do
                        if object:IsA("BasePart") then
                            object.Anchored = true
                            object.CanCollide = false
                            object.CastShadow = false
                            object.LocalTransparencyModifier = 0
                        elseif object:IsA("LuaSourceContainer") then
                            pcall(function() object:Destroy() end)
                        end
                    end
                    local realHumanoid = realModel:FindFirstChildOfClass("Humanoid")
                    if realHumanoid then
                        realHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
                    end
                    realModel.Name = "SkinModel_" .. tostring(packKey)

                    if not viewport.Parent then
                        pcall(function() realModel:Destroy() end)
                        finish(); return
                    end
                    pcall(function() char3D:Destroy() end)
                    realModel.Parent = viewport
                    -- Re-frame the orbiting camera on the real rig.
                    pcall(function()
                        local boundsCFrame, boundsSize = realModel:GetBoundingBox()
                        previewCenter = boundsCFrame.Position + Vector3.new(0, boundsSize.Y * 0.03, 0)
                        local largest = math.max(boundsSize.X, boundsSize.Y, boundsSize.Z, 3)
                        previewDist = (largest * 0.62) / math.tan(math.rad(vpCamera.FieldOfView / 2))
                        previewDist = math.clamp(previewDist, 4.0, 10.5)
                    end)
                    finish()
                end)
            end

            local rotAngle = 0
            local rotConn = RunService.RenderStepped:Connect(function(dt)
                rotAngle = (rotAngle + dt * 28) % 360
                local rad = math.rad(rotAngle)
                local dist = (isFocusedOnSelected and currentSelectedIndex == i) and previewDist * 0.88 or previewDist
                local camPos = previewCenter + Vector3.new(math.sin(rad) * dist, 0.15 * dist, math.cos(rad) * dist)
                vpCamera.CFrame = CFrame.new(camPos, previewCenter)
            end)
            table.insert(rotateConns, rotConn)

            -- Clean Title Only (No description text!)
            local titleLbl = Instance.new("TextLabel")
            titleLbl.Size = UDim2.new(1, -20, 0, 36)
            titleLbl.Position = UDim2.new(0, 10, 0, 240)
            titleLbl.BackgroundTransparency = 1
            titleLbl.Text = packData.name
            titleLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
            titleLbl.Font = Enum.Font.GothamBlack
            titleLbl.TextSize = 14
            titleLbl.ZIndex = 43
            titleLbl.Parent = card

            local selectHit = Instance.new("TextButton")
            selectHit.Size = UDim2.fromScale(1, 1)
            selectHit.BackgroundTransparency = 1
            selectHit.Text = ""
            selectHit.ZIndex = 45
            selectHit.Parent = card

            skinCards[i] = {
                card = card,
                viewport = viewport,
                stroke = cardStroke,
                packKey = packKey,
            }

            selectHit.MouseButton1Click:Connect(function()
                if not isFocusedOnSelected then
                    currentSelectedIndex = i
                    SkinChanger.focusSelected()
                end
            end)
        end

        local function updateCarouselPositions(animated)
            local tweenInfo = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
            local centerOffset = 0.5
            
            for i, item in ipairs(skinCards) do
                local offsetIndex = i - currentSelectedIndex
                local targetScaleX = centerOffset + (offsetIndex * 0.32)
                local targetSize = UDim2.new(0, 220, 0, 290)
                local targetTransp = math.abs(offsetIndex) > 1 and 0.6 or 0
                local isCurrent = (i == currentSelectedIndex)

                item.card.ZIndex = isCurrent and 48 or 35
                item.card.Visible = math.abs(offsetIndex) <= 2

                if animated then
                    TweenService:Create(item.card, tweenInfo, {
                        Position = UDim2.fromScale(targetScaleX, 0.5),
                        Size = targetSize,
                        BackgroundTransparency = targetTransp,
                    }):Play()
                    TweenService:Create(item.stroke, tweenInfo, {
                        Transparency = isCurrent and 0.1 or 0.6,
                        Color = isCurrent and Color3.fromRGB(255, 175, 50) or Color3.fromRGB(175, 92, 255),
                        Thickness = isCurrent and 2 or 1,
                    }):Play()
                else
                    item.card.Position = UDim2.fromScale(targetScaleX, 0.5)
                    item.card.Size = targetSize
                    item.card.BackgroundTransparency = targetTransp
                    item.stroke.Transparency = isCurrent and 0.1 or 0.6
                end
            end
        end

        function SkinChanger.focusSelected()
            isFocusedOnSelected = true
            bottomActions.Visible = true
            leftArrow.Visible = false
            rightArrow.Visible = false

            local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
            for i, item in ipairs(skinCards) do
                if i == currentSelectedIndex then
                    item.card.Visible = true
                    item.card.ZIndex = 50
                    TweenService:Create(item.card, tweenInfo, {
                        Position = UDim2.fromScale(0.5, 0.46),
                        Size = UDim2.new(0, 290, 0, 370),
                        BackgroundTransparency = 0,
                    }):Play()
                    TweenService:Create(item.viewport, tweenInfo, {
                        Size = UDim2.new(1, -24, 0, 290),
                    }):Play()
                    TweenService:Create(item.stroke, tweenInfo, {
                        Transparency = 0.05,
                        Thickness = 2.5,
                        Color = Color3.fromRGB(255, 180, 50),
                    }):Play()
                else
                    TweenService:Create(item.card, TweenInfo.new(0.2), {
                        BackgroundTransparency = 1,
                    }):Play()
                    task.delay(0.2, function()
                        if isFocusedOnSelected and i ~= currentSelectedIndex then
                            item.card.Visible = false
                        end
                    end)
                end
            end
        end

        function SkinChanger.unfocusSelected()
            isFocusedOnSelected = false
            bottomActions.Visible = false
            leftArrow.Visible = true
            rightArrow.Visible = true

            local tweenInfo = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
            for i, item in ipairs(skinCards) do
                item.card.Visible = true
                TweenService:Create(item.viewport, tweenInfo, {
                    Size = UDim2.new(1, -20, 0, 220),
                }):Play()
                TweenService:Create(item.stroke, tweenInfo, {
                    Color = Color3.fromRGB(175, 92, 255),
                }):Play()
            end
            updateCarouselPositions(true)
        end

        leftArrow.MouseButton1Click:Connect(function()
            if not isFocusedOnSelected then
                currentSelectedIndex = math.max(1, currentSelectedIndex - 1)
                updateCarouselPositions(true)
            end
        end)

        rightArrow.MouseButton1Click:Connect(function()
            if not isFocusedOnSelected then
                currentSelectedIndex = math.min(numSkins, currentSelectedIndex + 1)
                updateCarouselPositions(true)
            end
        end)

        backBtn.MouseButton1Click:Connect(function()
            SkinChanger.unfocusSelected()
        end)

        confirmBtn.MouseButton1Click:Connect(function()
            local chosenPack = PACK_ORDER[currentSelectedIndex]
            SkinChanger.apply(chosenPack)
            cleanupViewer()
        end)

        updateCarouselPositions(false)
    end
end

-- VISUALS: PRINTED-compatible ANTI-LAG, FPS BOOST, STRETCH REZ
-- ========================================================================
-- PRINTED-style Stretch Rez: 120 FOV plus the camera aspect stretch.
-- Keep FOV ownership centralized so POV and Stretch cannot fight each other.
local stretchRezConn
local function enableStretchRez()
    State.stretchRezEnabled = true
    if stretchRezConn then stretchRezConn:Disconnect(); stretchRezConn = nil end
    stretchRezConn = RunService.RenderStepped:Connect(function()
        if not State.stretchRezEnabled then return end
        local camera = workspace.CurrentCamera
        if not camera then return end
        pcall(function()
            camera.CFrame = camera.CFrame * CFrame.new(0, 0, 0, 1, 0, 0, 0, 0.7, 0, 0, 0, 1)
        end)
    end)
end

local function disableStretchRez()
    State.stretchRezEnabled = false
    if stretchRezConn then stretchRezConn:Disconnect(); stretchRezConn = nil end
    -- Hand the camera back: an armed POV value wins instead of a hard 70.
    local pov = State.povValue or 70
    local camera = workspace.CurrentCamera
    if camera then camera.FieldOfView = pov > 70 and pov or 70 end
end

Conns.fovControl = RunService.RenderStepped:Connect(function()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local fov = State.stretchRezEnabled and 120 or (State.povValue or 70)
    if fov > 70 and camera.FieldOfView ~= fov then camera.FieldOfView = fov end
end)
UI.addCleanup(function()
    if Conns.fovControl then Conns.fovControl:Disconnect(); Conns.fovControl = nil end
    if stretchRezConn then stretchRezConn:Disconnect(); stretchRezConn = nil end
end)

local function isLocalCharacterAsset(obj)
    -- Never strip accessories, faces, textures, or outfit visuals from the local
    -- character. Best Outfits are assembled from local body/accessory instances.
    local character = LP.Character
    if not character or not obj then return false end
    local ok, inside = pcall(function()
        return obj == character or obj:IsDescendantOf(character)
    end)
    return ok and inside == true
end

local function applyAntiLagDerender(obj)
    if isLocalCharacterAsset(obj) then return end
    pcall(function()
        if obj:IsA("Accessory") or obj:IsA("Hat") then
            obj:Destroy()
        elseif obj:IsA("BasePart") then
            obj.Material = Enum.Material.Plastic
            obj.Reflectance = 0
            obj.CastShadow = false
        elseif obj:IsA("Decal") or obj:IsA("Texture") then
            obj.Transparency = 1
        elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
            obj.Enabled = false
        elseif obj:IsA("AnimationController") or obj:IsA("Animator") then
            for _, t in ipairs(obj:GetPlayingAnimationTracks()) do
                pcall(function() t:Stop(0) end)
            end
        end
    end)
end

local defLightBrightness, defLightClock, defLightAmbient
local function enableAntiLag()
    State.antiLagEnabled = true
    defLightBrightness = defLightBrightness or Lighting.Brightness
    defLightClock = defLightClock or Lighting.ClockTime
    defLightAmbient = defLightAmbient or Lighting.OutdoorAmbient
    Lighting.GlobalShadows = false
    Lighting.FogEnd = 1e10
    Lighting.Brightness = 1
    Lighting.EnvironmentDiffuseScale = 0
    Lighting.EnvironmentSpecularScale = 0
    for _, e in pairs(Lighting:GetChildren()) do
        pcall(function()
            if e:IsA("BlurEffect") or e:IsA("SunRaysEffect") or e:IsA("ColorCorrectionEffect") or e:IsA("BloomEffect") or e:IsA("DepthOfFieldEffect") then
                e.Enabled = false
            end
        end)
    end
    for _, obj in ipairs(workspace:GetDescendants()) do applyAntiLagDerender(obj) end
    if Conns.antiLagDesc then Conns.antiLagDesc:Disconnect() end
    Conns.antiLagDesc = workspace.DescendantAdded:Connect(function(obj)
        if State.antiLagEnabled then applyAntiLagDerender(obj) end
    end)
end

local function disableAntiLag()
    State.antiLagEnabled = false
    if Conns.antiLagDesc then Conns.antiLagDesc:Disconnect(); Conns.antiLagDesc = nil end
    pcall(function()
        if defLightBrightness then Lighting.Brightness = defLightBrightness end
        if defLightClock then Lighting.ClockTime = defLightClock end
        if defLightAmbient then Lighting.OutdoorAmbient = defLightAmbient end
        Lighting.ExposureCompensation = 0
    end)
end

local function applyFPSBoost()
    State.fpsBoostEnabled = true
    pcall(function() if setfpscap then setfpscap(999999) end end)
    local function optimizeObj(v)
        -- FPS Boost may optimize the world, but must not erase the chosen skin:
        -- keep character accessories, faces, SpecialMesh textures and body overlays.
        if isLocalCharacterAsset(v) then return end
        pcall(function()
            if v:IsA("Model") then
                v.LevelOfDetail = Enum.ModelLevelOfDetail.Disabled
            elseif v:IsA("MeshPart") then
                v.CastShadow = false
                v.DoubleSided = false
                v.RenderFidelity = Enum.RenderFidelity.Performance
            elseif v:IsA("BasePart") then
                v.CastShadow = false
                v.Material = Enum.Material.Plastic
                v.Reflectance = 0
            elseif v:IsA("Decal") or v:IsA("Texture") then
                v.Transparency = 1
            elseif v:IsA("SpecialMesh") then
                v.TextureId = ""
            elseif v:IsA("Fire") or v:IsA("SpotLight") or v:IsA("Smoke") or v:IsA("Sparkles") or v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then
                v.Enabled = false
            elseif v:IsA("SurfaceAppearance") or v:IsA("MaterialVariant") then
                v:Destroy()
            elseif v:IsA("Attachment") then
                v.Visible = false
            end
        end)
    end
    for _, v in pairs(workspace:GetDescendants()) do optimizeObj(v) end
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        Lighting.Brightness = 0
        local ter = workspace:FindFirstChildOfClass("Terrain")
        if ter then
            ter.WaterReflectance = 0
            ter.WaterTransparency = 0.7
            ter.WaterWaveSize = 0
            ter.WaterWaveSpeed = 0
        end
    end)
    if Conns.fpsBoostDesc then Conns.fpsBoostDesc:Disconnect() end
    Conns.fpsBoostDesc = workspace.DescendantAdded:Connect(function(v)
        if State.fpsBoostEnabled then task.spawn(optimizeObj, v) end
    end)
end

local function disableFPSBoost()
    State.fpsBoostEnabled = false
    if Conns.fpsBoostDesc then Conns.fpsBoostDesc:Disconnect(); Conns.fpsBoostDesc = nil end
end

-- ========================================================================
-- CONFIGURATION SYSTEM (JSON SAVING / LOADING)
-- ========================================================================
local function saveConfig()
    local function ks(e)
        return {kb = e.kb and e.kb.Name or nil, gp = e.gp and e.gp.Name or nil}
    end
    local cfg = {
        normalSpeed       = State.NS,
        carrySpeed        = State.CS,
        autoSwitchCarrySpeed = State.autoCarrySpeedEnabled,
        dropBrainrotKey   = ks(KB.DropBrainrot),
        autoLeftKey       = ks(KB.AutoLeft),
        autoRightKey      = ks(KB.AutoRight),
        autoBatKey        = ks(KB.AutoBat),
        laggerToggleKey   = ks(KB.LaggerToggle),
        tpFloorKey        = ks(KB.TPFloor),
        tpBatKey          = ks(KB.TpBat),
        tpBatEnabled      = State.tpBatEnabled,
        guiHideKey        = ks(KB.GuiHide),
        speedToggleKey    = ks(KB.SpeedToggle),
        autoGrabSchema    = 2,
        semiMode          = State.SemiMode,
        semiEnabled       = State.SemiEnabled,
        semiNormalOpen    = State.SemiNormalOpen,
        autoGrabStyle     = State.AutoGrabStyle,
        -- Yout AutoSteal radius is fixed at 61; the old editable radius control is gone.
        autoGrabRadius    = 61,
        autoGrabMode      = State.autoGrabMode,
        v1Scale           = State.v1Scale,
        v2Scale           = State.v2Scale,
        semiScale         = State.semiScale,
        antiRagdoll       = State.antiRagdollEnabled,
        antiRagdollMode   = State.antiRagdollMode,
        speedEngine      = "Arabi",
        infiniteJump      = State.infJumpEnabled,
        infJumpMode       = State.infJumpMode,
        medusaCounter     = State.medusaCounterEnabled,
        batCounter        = State.batCounterEnabled,
        carryMode         = State.speedMode,
        laggerMode        = State.laggerToggled,
        laggerCarryMode   = (State.laggerPhase == 2),
        laggerSpeed       = State.LAGGER_SPEED,
        laggerCarrySpeed  = State.LAGGER_CARRY_SPEED,
        autoBat           = State.autoBatEnabled,
        antiDie          = State.antiDieEnabled,
        instantResetOnDie = State.instantResetOnDieEnabled,
        antiFling         = State.antiFlingEnabled,
        bodyLockEnabled   = State.bodyLockEnabled,
        bodyLockRange     = State.bodyLockRange,
        autoSwing         = State.autoSwingEnabled,
        animPack          = State.animPack,
        unwalkEnabled     = State.unwalkEnabled,
        antiLag           = State.antiLagEnabled,
        fpsBoost          = State.fpsBoostEnabled,
        espEnabled        = State.espEnabled,
        tracersEnabled    = State.tracersEnabled,
        autoGrabStopEnabled = State.autoGrabStopEnabled,
        stretchRez        = State.stretchRezEnabled,
        autoTPEnabled     = State.autoTPEnabled,
        autoTPHeight      = State.autoTPHeight,
        autoPlayMode      = State.autoPlayMode,
        instantResetKey   = ks(KB.InstantReset),
        introEnabled      = State.introEnabled,
        skyTheme          = currentSkyTheme
    }
    local ok, json = pcall(function() return HttpService:JSONEncode(cfg) end)
    if ok and json then
        safeWriteFile("k2_duels_config.json", json)
        safeWriteFile("k2_duels_backup.json", json)
    end
end
task.spawn(function()
    while task.wait(6) do
        saveConfig()
    end
end)

local function refreshSpeedModeLabel()
    if modeValLbl then
        if State.laggerToggled then
            if State.laggerPhase == 2 then
                UI.text(modeValLbl, "LAGGER CARRY")
            else
                UI.text(modeValLbl, "LAGGER NORM")
            end
        else
            if State.speedMode then
                UI.text(modeValLbl, "CARRY")
            else
                UI.text(modeValLbl, "NORMAL")
            end
        end
    end
    if Speed.laggerVisual then Speed.laggerVisual(State.laggerToggled) end
    if Speed.carryVisual then Speed.carryVisual(State.speedMode and not State.laggerToggled) end
    if Speed.mobileRefresh then Speed.mobileRefresh() end
end
Speed.refreshVisuals = refreshSpeedModeLabel

local function toggleCarryMode()
    local combined = State.laggerToggled and State.laggerPhase == 2
    if combined then
        State.laggerToggled, State.laggerPhase, State.speedMode = false, 0, true
    else
        State.speedMode = not State.speedMode
        if State.speedMode then State.laggerToggled, State.laggerPhase = false, 0 end
    end
    refreshSpeedModeLabel()
end
local function toggleLaggerMode()
    local combined = State.laggerToggled and State.laggerPhase == 2
    if combined then
        State.laggerToggled, State.laggerPhase, State.speedMode = true, 1, false
    else
        State.laggerToggled = not State.laggerToggled
        State.laggerPhase = State.laggerToggled and 1 or 0
        if State.laggerToggled then State.speedMode = false end
    end
    refreshSpeedModeLabel()
end

-- ========================================================================
-- USER INTERFACE (K2 DUELS PURPLE / SMOOTH UI)
-- ========================================================================

-- ========================================================================
-- MODERN GLASS UI (Vx7-style) — M10RU functions wired, K2 branding
-- ========================================================================
local mbContainers = {}

local function buildGui()
    local glass = {
        bg         = Color3.fromRGB(14, 14, 18),
        panel      = Color3.fromRGB(22, 22, 28),
        panelHover = Color3.fromRGB(32, 32, 40),
        side       = Color3.fromRGB(18, 18, 24),
        top        = Color3.fromRGB(16, 16, 22),
        border     = Color3.fromRGB(48, 48, 58),
        accent     = Color3.fromRGB(200, 200, 210),
        accent2    = Color3.fromRGB(230, 230, 240),
        text       = Color3.fromRGB(255, 255, 255),
        muted      = Color3.fromRGB(140, 140, 155),
        tween      = TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
    }

    local function mkCorner(parent, radius)
        local c = Instance.new("UICorner", parent)
        c.CornerRadius = UDim.new(0, radius or 10)
        return c
    end
    local function mkStroke(parent, color, thickness)
        local s = Instance.new("UIStroke", parent)
        s.Color = color or glass.border
        s.Thickness = thickness or 1
        s.Transparency = 0.35
        return s
    end

    local function mkSwitch(parent, enabled, onToggle)
        local toggleFrame = Instance.new("Frame", parent)
        toggleFrame.Name = "ModernToggle"
        toggleFrame.Size = UDim2.new(0, 42, 0, 22)
        toggleFrame.AnchorPoint = Vector2.new(1, 0.5)
        toggleFrame.Position = UDim2.new(1, -12, 0.5, 0)
        toggleFrame.BackgroundColor3 = enabled and Color3.fromRGB(70, 70, 82) or glass.panelHover
        toggleFrame.BorderSizePixel = 0
        mkCorner(toggleFrame, 11)
        local stroke = mkStroke(toggleFrame, glass.border, 0.8)
        local knob = Instance.new("Frame", toggleFrame)
        knob.Size = UDim2.new(0, 16, 0, 16)
        knob.Position = enabled and UDim2.new(1, -19, 0, 3) or UDim2.new(0, 3, 0, 3)
        knob.BackgroundColor3 = enabled and Color3.new(1,1,1) or glass.muted
        knob.BorderSizePixel = 0
        mkCorner(knob, 8)
        local btn = Instance.new("TextButton", toggleFrame)
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.ZIndex = 5
        local state = enabled
        local function setVisual(val)
            state = val
            TweenService:Create(toggleFrame, glass.tween, {
                BackgroundColor3 = state and Color3.fromRGB(70, 70, 82) or glass.panelHover
            }):Play()
            TweenService:Create(knob, glass.tween, {
                Position = state and UDim2.new(1, -19, 0, 3) or UDim2.new(0, 3, 0, 3),
                BackgroundColor3 = state and Color3.new(1,1,1) or glass.muted
            }):Play()
        end
        btn.MouseButton1Click:Connect(function()
            state = not state
            setVisual(state)
            if onToggle then onToggle(state) end
        end)
        return setVisual, toggleFrame
    end

    local function makeToggleRow(parent, labelText, defaultVal, onToggle)
        local row = Instance.new("Frame", parent)
        row.Size = UDim2.new(1, 0, 0, 40)
        row.BackgroundColor3 = glass.panel
        row.BackgroundTransparency = 0.15
        row.BorderSizePixel = 0
        mkCorner(row, 10)
        mkStroke(row, glass.border, 0.8)
        local lbl = Instance.new("TextLabel", row)
        lbl.Size = UDim2.new(1, -60, 1, 0)
        lbl.Position = UDim2.new(0, 14, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = glass.text
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        local setVisual = mkSwitch(row, defaultVal == true, onToggle)
        return setVisual, row
    end

    local function makeSectionHeader(parent, title)
        local frame = Instance.new("Frame", parent)
        frame.Size = UDim2.new(1, 0, 0, 26)
        frame.BackgroundTransparency = 1
        local bar = Instance.new("Frame", frame)
        bar.Size = UDim2.new(0, 3, 0, 14)
        bar.Position = UDim2.new(0, 4, 0.5, -7)
        bar.BackgroundColor3 = glass.accent2
        bar.BorderSizePixel = 0
        mkCorner(bar, 2)
        local lbl = Instance.new("TextLabel", frame)
        lbl.Size = UDim2.new(1, -16, 1, 0)
        lbl.Position = UDim2.new(0, 14, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = string.upper(title)
        lbl.TextColor3 = glass.muted
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 11
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        return frame
    end

    local function makeNumericRow(parent, labelText, defaultVal, onConfirm)
        local row = Instance.new("Frame", parent)
        row.Size = UDim2.new(1, 0, 0, 40)
        row.BackgroundColor3 = glass.panel
        row.BackgroundTransparency = 0.15
        row.BorderSizePixel = 0
        mkCorner(row, 10)
        mkStroke(row, glass.border, 0.8)
        local lbl = Instance.new("TextLabel", row)
        lbl.Size = UDim2.new(1, -90, 1, 0)
        lbl.Position = UDim2.new(0, 14, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = glass.text
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        local box = Instance.new("TextBox", row)
        box.Size = UDim2.new(0, 64, 0, 26)
        box.AnchorPoint = Vector2.new(1, 0.5)
        box.Position = UDim2.new(1, -12, 0.5, 0)
        box.BackgroundColor3 = glass.side
        box.TextColor3 = glass.accent2
        box.Font = Enum.Font.GothamBold
        box.TextSize = 12
        box.Text = tostring(defaultVal)
        box.ClearTextOnFocus = false
        mkCorner(box, 6)
        mkStroke(box, glass.border, 0.8)
        box.FocusLost:Connect(function()
            local num = tonumber(box.Text)
            if num then
                onConfirm(num)
            else
                box.Text = tostring(defaultVal)
            end
        end)
        return box, row
    end

    local targetParent = getSafeGuiParent()
    for _, name in ipairs({"Vx7ModernV2", "K2Duels", "K2DuelsSettings", "VX7QuickButtons", "M10RUDuels"}) do
        local old = targetParent:FindFirstChild(name)
        if old then pcall(function() old:Destroy() end) end
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "K2Duels"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 50
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    protectGuiObject(gui)
    gui.Parent = targetParent
    UI.root = gui

    local function drag(frame, handle, ignoreLock)
        UI.drag(frame, handle, ignoreLock)
    end

    -- Open pill (when main hidden)
    local menuBtn = Instance.new("TextButton", gui)
    menuBtn.Name = "OpenK2Menu"
    menuBtn.Size = UDim2.fromOffset(56, 56)
    menuBtn.Position = UDim2.new(0, 16, 0.35, 0)
    menuBtn.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
    menuBtn.Text = "K2"
    menuBtn.TextColor3 = Color3.new(1,1,1)
    menuBtn.Font = Enum.Font.GothamBlack
    menuBtn.TextSize = 16
    menuBtn.Visible = false
    menuBtn.ZIndex = 200
    mkCorner(menuBtn, 28)
    mkStroke(menuBtn, glass.border, 1.2)
    menuBtn:SetAttribute("K2AlwaysDraggable", true)
    UI.drag(menuBtn, menuBtn, true)

    local main = Instance.new("CanvasGroup", gui)
    main.Name = "K2DuelsSettings"
    main.Size = UDim2.new(0, 320, 0, 500)
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.Position = UDim2.new(0.5, 0, 0.5, 0)
    main.BackgroundColor3 = glass.bg
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.GroupTransparency = 0
    mkCorner(main, 16)
    mkStroke(main, glass.border, 1.2)

    local topBar = Instance.new("Frame", main)
    topBar.Size = UDim2.new(1, 0, 0, 52)
    topBar.BackgroundColor3 = glass.top
    topBar.BorderSizePixel = 0
    local title = Instance.new("TextLabel", topBar)
    title.Size = UDim2.new(1, -50, 1, 0)
    title.Position = UDim2.new(0, 16, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "K2"
    title.TextColor3 = glass.text
    title.Font = Enum.Font.GothamBlack
    title.TextSize = 28
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextYAlignment = Enum.TextYAlignment.Center

    local closeBtn = Instance.new("TextButton", topBar)
    closeBtn.Size = UDim2.fromOffset(28, 28)
    closeBtn.Position = UDim2.new(1, -38, 0.5, -14)
    closeBtn.BackgroundColor3 = glass.panelHover
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = glass.muted
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 12
    mkCorner(closeBtn, 14)

    local function showGui()
        main.Visible = true
        menuBtn.Visible = false
        main.GroupTransparency = 0
    end
    local function hideGui()
        main.Visible = false
        menuBtn.Visible = true
    end
    closeBtn.MouseButton1Click:Connect(hideGui)
    menuBtn.MouseButton1Click:Connect(showGui)
    UI.drag(main, topBar, true)

    -- Tab strip under header (SPEE COMB VISU MISC BINDS style)
    local tabBar = Instance.new("Frame", main)
    tabBar.Size = UDim2.new(1, -20, 0, 30)
    tabBar.Position = UDim2.new(0, 10, 0, 56)
    tabBar.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
    tabBar.BorderSizePixel = 0
    mkCorner(tabBar, 15)

    local tabs = {
        { id = "Main",    label = "SPEE" },
        { id = "Combat",  label = "COMB" },
        { id = "Visuals", label = "VISU" },
        { id = "Misc",    label = "MISC" },
        { id = "Config",  label = "BINDS" },
    }
    local pages = {}
    local tabButtons = {}

    local contentArea = Instance.new("Frame", main)
    contentArea.Size = UDim2.new(1, -16, 1, -100)
    contentArea.Position = UDim2.new(0, 8, 0, 92)
    contentArea.BackgroundTransparency = 1

    local function buildPage(id)
        local sf = Instance.new("ScrollingFrame", contentArea)
        sf.Name = id .. "Page"
        sf.Size = UDim2.new(1, 0, 1, 0)
        sf.BackgroundTransparency = 1
        sf.BorderSizePixel = 0
        sf.ScrollBarThickness = 2
        sf.ScrollBarImageColor3 = glass.accent
        sf.CanvasSize = UDim2.new(0, 0, 0, 0)
        sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
        sf.Visible = false
        local layout = Instance.new("UIListLayout", sf)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 6)
        local pad = Instance.new("UIPadding", sf)
        pad.PaddingLeft = UDim.new(0, 2)
        pad.PaddingRight = UDim.new(0, 2)
        pad.PaddingTop = UDim.new(0, 4)
        pad.PaddingBottom = UDim.new(0, 10)
        pages[id] = sf
        return sf
    end
    for _, t in ipairs(tabs) do buildPage(t.id) end
    pages["Main"].Visible = true

    local tabW = 1 / #tabs
    for i, t in ipairs(tabs) do
        local b = Instance.new("TextButton", tabBar)
        b.Size = UDim2.new(tabW, -4, 1, -6)
        b.Position = UDim2.new((i - 1) * tabW, 2, 0, 3)
        b.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
        b.BackgroundTransparency = (i == 1) and 0 or 1
        b.Text = t.label
        b.TextColor3 = (i == 1) and glass.text or glass.muted
        b.Font = Enum.Font.GothamBold
        b.TextSize = 10
        b.BorderSizePixel = 0
        mkCorner(b, 10)
        tabButtons[t.id] = b
        local tid = t.id
        b.MouseButton1Click:Connect(function()
            for id, page in pairs(pages) do page.Visible = (id == tid) end
            for id, btn in pairs(tabButtons) do
                local sel = (id == tid)
                btn.BackgroundTransparency = sel and 0 or 1
                btn.TextColor3 = sel and glass.text or glass.muted
            end
        end)
    end

    local function handleAutoSwitchCarrySpeed(on)
        State.autoCarrySpeedEnabled = on == true
        if not on then
            pcall(function()
                if disableAutoCarrySpeed then disableAutoCarrySpeed() end
            end)
        end
        saveConfig()
    end

    -- ========== MAIN / SPEED ==========
    local mainPage = pages["Main"]
    makeSectionHeader(mainPage, "Speed")
    makeNumericRow(mainPage, "Normal Speed", State.NS, function(v) State.NS = v; saveConfig() end)
    makeNumericRow(mainPage, "Carry Speed", State.CS, function(v)
        State.CS = v
        State.autoCarryLastSpeed = 0
        if Speed and Speed.refreshVisuals then pcall(Speed.refreshVisuals) end
        saveConfig()
    end)
    makeToggleRow(mainPage, "Auto Switch Carry Speed", State.autoCarrySpeedEnabled, handleAutoSwitchCarrySpeed)
    makeSectionHeader(mainPage, "Lagger")
    makeNumericRow(mainPage, "Lagger Speed", State.LAGGER_SPEED, function(v) State.LAGGER_SPEED = v; saveConfig() end)
    makeNumericRow(mainPage, "Lagger Carry Speed", State.LAGGER_CARRY_SPEED, function(v) State.LAGGER_CARRY_SPEED = v; saveConfig() end)
    makeToggleRow(mainPage, "Lagger Mode", State.laggerToggled, function(on)
        if on ~= State.laggerToggled then toggleLaggerMode() end
        saveConfig()
    end)
    makeSectionHeader(mainPage, "Auto Grab")
    makeToggleRow(mainPage, "Auto Grab", State.StealV1 and State.StealV1.AutoStealEnabled or State.SemiNormalOpen, function(on)
        if on then
            if Grab and Grab.startNormal then Grab.startNormal()
            elseif Grab and Grab.toggleNormal then Grab.toggleNormal() end
        else
            if Grab and Grab.stopAll then Grab.stopAll() end
        end
        saveConfig()
    end)

    -- ========== COMBAT ==========
    local combatPage = pages["Combat"]
    makeSectionHeader(combatPage, "Safety")
    makeToggleRow(combatPage, "Anti Die", true, function(on)
        pcall(function() if AntiDie and AntiDie.setEnabled then AntiDie.setEnabled(on) end end)
        saveConfig()
    end)
    makeToggleRow(combatPage, "Anti Fling", State.antiFlingEnabled, function(on)
        State.antiFlingEnabled = on
        pcall(function() if AntiFling and AntiFling.setEnabled then AntiFling.setEnabled(on) end end)
        saveConfig()
    end)
    makeToggleRow(combatPage, "Body Lock", State.bodyLockEnabled, function(on)
        State.bodyLockEnabled = on
        pcall(function() if BodyLock and BodyLock.setEnabled then BodyLock.setEnabled(on) end end)
        saveConfig()
    end)
    makeSectionHeader(combatPage, "Offense")
    makeToggleRow(combatPage, "Bat Aimbot", State.autoBatEnabled, function(on)
        State.autoBatEnabled = on
        if on then
            pcall(function() if queueAutoBatStart then queueAutoBatStart() end end)
        else
            pcall(function() if disableAutoBat then disableAutoBat() end end)
        end
        saveConfig()
    end)
    makeToggleRow(combatPage, "TP Bat", State.tpBatEnabled, function(on)
        State.tpBatEnabled = on
        pcall(function() if TpBat then if on and TpBat.enable then TpBat.enable() elseif TpBat.setEnabled then TpBat.setEnabled(on) elseif TpBat.toggle and on ~= (TpBat.active) then TpBat.toggle() end end end)
        saveConfig()
    end)
    makeToggleRow(combatPage, "Infinite Jump", State.infJumpEnabled, function(on)
        State.infJumpEnabled = on; saveConfig()
    end)
    makeToggleRow(combatPage, "Anti Ragdoll", State.antiRagdollEnabled, function(on)
        State.antiRagdollEnabled = on; saveConfig()
    end)

    -- ========== VISUALS ==========
    local visPage = pages["Visuals"]
    makeSectionHeader(visPage, "ESP")
    makeToggleRow(visPage, "ESP", State.espEnabled, function(on)
        State.espEnabled = on; saveConfig()
    end)
    makeToggleRow(visPage, "Tracers", State.tracersEnabled, function(on)
        State.tracersEnabled = on; saveConfig()
    end)
    makeSectionHeader(visPage, "Display")
    makeToggleRow(visPage, "FPS Boost", State.fpsBoostEnabled, function(on)
        State.fpsBoostEnabled = on; saveConfig()
    end)
    makeToggleRow(visPage, "Unwalk", State.unwalkEnabled, function(on)
        State.unwalkEnabled = on
        if on then pcall(function() if startUnwalk then startUnwalk() end end)
        else pcall(function() if stopUnwalk then stopUnwalk() end end) end
        saveConfig()
    end)

    -- ========== MISC ==========
    local miscPage = pages["Misc"]
    makeSectionHeader(miscPage, "Utility")
    makeToggleRow(miscPage, "Intro Screen", State.introEnabled ~= false, function(on)
        State.introEnabled = on; saveConfig()
    end)
    local saveBtn = Instance.new("TextButton", miscPage)
    saveBtn.Size = UDim2.new(1, 0, 0, 36)
    saveBtn.BackgroundColor3 = glass.panel
    saveBtn.Text = "SAVE CONFIG"
    saveBtn.TextColor3 = glass.text
    saveBtn.Font = Enum.Font.GothamBold
    saveBtn.TextSize = 12
    mkCorner(saveBtn, 8)
    mkStroke(saveBtn, glass.border, 0.8)
    saveBtn.MouseButton1Click:Connect(function()
        saveConfig()
        saveBtn.Text = "SAVED"
        task.delay(1, function() saveBtn.Text = "SAVE CONFIG" end)
    end)

    -- ========== CONFIG / keybind note ==========
    local cfgPage = pages["Config"]
    makeSectionHeader(cfgPage, "Keybinds")
    local kbNote = Instance.new("TextLabel", cfgPage)
    kbNote.Size = UDim2.new(1, 0, 0, 48)
    kbNote.BackgroundTransparency = 1
    kbNote.Text = "Keybinds use the same M10RU bindings.\nChange them via executor config if needed."
    kbNote.TextColor3 = glass.muted
    kbNote.Font = Enum.Font.Gotham
    kbNote.TextSize = 11
    kbNote.TextWrapped = true

    -- ========== CIRCULAR QUICK BUTTONS (1:1 with K2 reference) ==========
    local function buildQuickButtons()
        -- Solid black circles, no purple, no square edges
        local btnSize = 68
        local gap = 10
        local cols = 2
        local viewport = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
        local startX = math.floor(viewport.X - (btnSize * cols + gap * (cols - 1)) - 20)
        local startY = math.floor(viewport.Y * 0.20)

        local function makeCircleButton(parent, key, label, x, y, onClick)
            local frame = Instance.new("Frame")
            frame.Name = "MB_" .. key
            frame.Size = UDim2.fromOffset(btnSize, btnSize)
            frame.Position = UDim2.fromOffset(x, y)
            frame.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
            frame.BackgroundTransparency = 0
            frame.BorderSizePixel = 0
            frame.ZIndex = 100
            frame.Active = true
            frame.ClipsDescendants = true
            frame.Parent = parent

            -- Full circle (scale-based corner, not pixel radius)
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(1, 0)
            corner.Parent = frame

            -- Subtle dark edge only (never purple)
            local stroke = Instance.new("UIStroke")
            stroke.Color = Color3.fromRGB(28, 28, 32)
            stroke.Thickness = 1
            stroke.Transparency = 0.25
            stroke.Parent = frame

            local btn = Instance.new("TextButton")
            btn.Size = UDim2.fromScale(1, 1)
            btn.BackgroundTransparency = 1
            btn.BorderSizePixel = 0
            btn.Text = label
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 11
            btn.TextWrapped = true
            btn.ZIndex = 101
            btn.Parent = frame

            local dragStart, startPos, moved
            btn.InputBegan:Connect(function(input)
                if input.UserInputType ~= Enum.UserInputType.MouseButton1
                    and input.UserInputType ~= Enum.UserInputType.Touch then
                    return
                end
                dragStart = input.Position
                startPos = frame.Position
                moved = false
                local conn
                conn = input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        conn:Disconnect()
                        local wasDrag = moved
                        dragStart = nil
                        if not wasDrag then
                            onClick()
                            -- brief press feedback (stay black family, no purple)
                            frame.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
                            task.delay(0.12, function()
                                if frame.Parent then
                                    frame.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
                                end
                            end)
                        end
                    end
                end)
            end)
            UserInputService.InputChanged:Connect(function(input)
                if not dragStart then return end
                if input.UserInputType ~= Enum.UserInputType.MouseMovement
                    and input.UserInputType ~= Enum.UserInputType.Touch then
                    return
                end
                local delta = input.Position - dragStart
                if delta.Magnitude > 6 then
                    moved = true
                    frame.Position = UDim2.fromOffset(
                        startPos.X.Offset + delta.X,
                        startPos.Y.Offset + delta.Y
                    )
                end
            end)

            table.insert(mbContainers, frame)
            return frame
        end

        local actions = {
            { key = "DROP_BR",      text = "DROP\nBR",      fn = function()
                pcall(function()
                    if dropBrainrot then dropBrainrot()
                    elseif DropBrainrot then DropBrainrot() end
                end)
            end },
            { key = "AUTO_LEFT",    text = "AUTO\nLEFT",    fn = function()
                State.autoLeftEnabled = not State.autoLeftEnabled
                if State.autoLeftEnabled then
                    pcall(function()
                        if startAutoLeft then startAutoLeft()
                        elseif queueAutoLeftStart then queueAutoLeftStart() end
                    end)
                else
                    pcall(function() if stopAutoLeft then stopAutoLeft() end end)
                end
            end },
            { key = "BAT_AIMBOT",   text = "BAT\nAIMBOT",   fn = function()
                State.autoBatEnabled = not State.autoBatEnabled
                if State.autoBatEnabled then
                    pcall(function() if queueAutoBatStart then queueAutoBatStart() end end)
                else
                    pcall(function() if disableAutoBat then disableAutoBat() end end)
                end
                saveConfig()
            end },
            { key = "AUTO_RIGHT",   text = "AUTO\nRIGHT",   fn = function()
                State.autoRightEnabled = not State.autoRightEnabled
                if State.autoRightEnabled then
                    pcall(function()
                        if startAutoRight then startAutoRight()
                        elseif queueAutoRightStart then queueAutoRightStart() end
                    end)
                else
                    pcall(function() if stopAutoRight then stopAutoRight() end end)
                end
            end },
            { key = "TP_DOWN",      text = "TP\nDOWN",      fn = function()
                pcall(function()
                    if tpFloor then tpFloor()
                    elseif TPDown then TPDown() end
                end)
            end },
            { key = "CARRY_SPD",    text = "CARRY\nSPD",    fn = function()
                toggleCarryMode()
                saveConfig()
            end },
            { key = "LAGGER_CARRY", text = "LAGGER\nCARRY", fn = function()
                toggleLaggerMode()
                saveConfig()
            end },
            { key = "LAGGER_MODE",  text = "LAGGER\nMODE",  fn = function()
                toggleLaggerMode()
                saveConfig()
            end },
            { key = "TP_BAT",       text = "TP\nBAT",       fn = function()
                State.tpBatEnabled = not State.tpBatEnabled
                pcall(function()
                    if TpBat and TpBat.toggle then TpBat.toggle()
                    elseif TpBat and TpBat.setEnabled then TpBat.setEnabled(State.tpBatEnabled) end
                end)
                saveConfig()
            end },
            { key = "INSTA_RESET",  text = "INSTA\nRESET",  fn = function()
                pcall(function()
                    if InstantReset and InstantReset.reset then InstantReset.reset() end
                end)
            end },
        }

        for idx, item in ipairs(actions) do
            local col = (idx - 1) % cols
            local row = math.floor((idx - 1) / cols)
            local x = startX + col * (btnSize + gap)
            local y = startY + row * (btnSize + gap)
            makeCircleButton(gui, item.key, item.text, x, y, item.fn)
        end
    end
    buildQuickButtons()

    -- Visual stubs for systems that call set*Visual from combat loops
    autoLeftSetVisual = function() end
    autoRightSetVisual = function() end
    setAutoBatVisual = function() end
    setAutoGrabVisual = function() end
    setAutoSwitchSpeedVisual = function() end


    -- Auto-grab progress skins (kept from M10RU)
    -- TWO PURPLE SKINS, shared by Normal V1, Normal V2 and instant SEMI.
    -- No floating names, RAD fields, or ON/OFF buttons; skin 2 has its readiness state.
    -- Shape 1: slim rail + percentage. Shape 2: rounded full-width fill.
    -- ============================================================
    do
        local P = Grab.purple
        local function corner(object, radius)
            Instance.new("UICorner", object).CornerRadius = UDim.new(0, radius)
        end
        local function gradient(parent, first, last)
            local object = Instance.new("UIGradient", parent)
            object.Color = ColorSequence.new(first, last)
            return object
        end
        local function makeView(number, width, height, radius)
            local frame = Instance.new("CanvasGroup", gui)
            frame.Name = "AutoGrabSkin" .. number
            frame.Size = UDim2.fromOffset(width, height)
            frame.AnchorPoint = Vector2.new(0.5, 1)
            frame.Position = UDim2.new(0.5, 0, 1, -88)
            frame.BackgroundColor3 = P.background
            frame.BackgroundTransparency = 0.06
            frame.BorderSizePixel = 0
            frame.Active = true
            frame:SetAttribute("K2AlwaysDraggable", true)
            frame.Visible = false
            frame.ZIndex = 10
            corner(frame, radius)
            local stroke = Instance.new("UIStroke", frame)
            stroke.Color = P.light
            stroke.Thickness = 1.3
            stroke.Transparency = 0.12
            stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            local scale = Instance.new("UIScale", frame)
            scale.Name = "AutoGrabScale"
            scale.Scale = 1
            local view = {frame = frame, scale = scale, stroke = stroke, baseSize = UDim2.fromOffset(width, height)}
            Grab.views[number] = view
            drag(frame, frame, true)
            return view
        end
        local function zoomButtons(view)
            for _, item in ipairs({{name="ZoomOut", text="-", x=-58, delta=-0.1},
                {name="ZoomIn", text="+", x=-32, delta=0.1}}) do
                local object = Instance.new("TextButton", view.frame)
                object.Name = item.name
                object.Size = UDim2.fromOffset(22, 22)
                object.Position = UDim2.new(1, item.x, 0.5, -11)
                object.BackgroundColor3 = P.button
                object.BackgroundTransparency = 0.04
                object.BorderSizePixel = 0
                object.AutoButtonColor = false
                object.Text = item.text
                object.TextColor3 = P.text
                object.Font = Enum.Font.GothamBlack
                object.TextSize = 14
                object.ZIndex = 16
                corner(object, 6)
                local stroke = Instance.new("UIStroke", object)
                stroke.Color = P.border
                stroke.Transparency = 0.1
                object.Activated:Connect(function()
                    if _anyKeyListening or not Grab.alive then return end
                    -- zoom controls are retained internally but not exposed on the bar
                    return
                end)
            end
        end

        local one = makeView(1, 250, 34, 6)
        local track = Instance.new("Frame", one.frame)
        track.Name = "ProgressTrack"
        track.Position = UDim2.new(0, 42, 0.5, -7)
        track.Size = UDim2.new(1, -50, 0, 14)
        track.BackgroundColor3 = P.track
        track.BorderSizePixel = 0
        track.ClipsDescendants = true
        track.ZIndex = 11
        corner(track, 7)
        one.fill = Instance.new("Frame", track)
        one.fill.Name = "ProgressFill"
        one.fill.Size = UDim2.new(0, 0, 1, 0)
        one.fill.BackgroundColor3 = P.light
        one.fill.BorderSizePixel = 0
        one.fill.ZIndex = 12
        corner(one.fill, 7)
        gradient(one.fill, P.accent, P.light)
        one.percent = Instance.new("TextLabel", one.frame)
        one.percent.Name = "Percentage"
        one.percent.Position = UDim2.new(0, 7, 0.5, -8)
        one.percent.Size = UDim2.fromOffset(30, 16)
        one.percent.BackgroundTransparency = 1
        one.percent.Text = "0%"
        one.percent.TextColor3 = P.text
        one.percent.Font = Enum.Font.GothamBlack
        one.percent.TextSize = 12
        one.percent.TextXAlignment = Enum.TextXAlignment.Left
        one.percent.ZIndex = 13
        -- no visible V1/V2 zoom controls

        -- Shape 2 rebuilt to the requested layout:
        --   * a THIN rounded-rectangle progress LINE near the bottom of the
        --     card (no more fat circular / pill-shaped fill),
        --   * the small character AVATAR centred ABOVE that line,
        --   * the counter numbers (live % and MAX) on the LEFT, above the line,
        --   * the FPS / PING plate on the RIGHT, kept as it was but without
        --     the old "|" divider.
        -- Card size is driven by these three values - edit them to resize it.
        local GRAB_W, GRAB_H, GRAB_R = 320, 58, 14   -- width, height, corner radius
        local LINE_H, LINE_R = 7, 3                   -- progress line: thickness, corner radius

        local two = makeView(2, GRAB_W, GRAB_H, GRAB_R)
        -- No clipping: the small link card is parented here and sits above it.
        -- (The progress fill is clipped by its own rail, so nothing spills.)
        two.frame.ClipsDescendants = false
        two.frame.BackgroundColor3 = Color3.fromRGB(12, 11, 24)
        two.stroke.Color = Color3.fromRGB(40, 40, 48)
        two.stroke.Thickness = 1.5
        two.stroke.Transparency = 0
        -- Racing light: a bright violet comet chases around the card border
        -- while the rest of the edge stays a dim purple.
        two.outlineGradient = gradient(two.stroke, Color3.fromRGB(58, 22, 112), Color3.fromRGB(58, 22, 112))
        two.outlineGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, Color3.fromRGB(58, 22, 112)),
            ColorSequenceKeypoint.new(0.34, Color3.fromRGB(58, 22, 112)),
            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(224, 184, 255)),
            ColorSequenceKeypoint.new(0.66, Color3.fromRGB(58, 22, 112)),
            ColorSequenceKeypoint.new(1.00, Color3.fromRGB(58, 22, 112)),
        })

        -- THIN PROGRESS LINE --------------------------------------------------
        -- A low rectangle with rounded corners (NOT a circle / pill). The fill
        -- grows inside this rail, so it can never run under the avatar or the
        -- FPS / PING text.
        two.track = Instance.new("Frame", two.frame)
        two.track.Name = "ProgressTrack"
        two.track.Position = UDim2.new(0, 12, 1, -15)
        two.track.Size = UDim2.new(1, -24, 0, LINE_H)
        two.track.BackgroundColor3 = P.track
        two.track.BackgroundTransparency = 0.25
        two.track.BorderSizePixel = 0
        two.track.ClipsDescendants = true
        two.track.ZIndex = 11
        corner(two.track, LINE_R)
        local lineStroke = Instance.new("UIStroke", two.track)
        lineStroke.Color = Color3.fromRGB(40, 40, 48)
        lineStroke.Thickness = 1
        lineStroke.Transparency = 0.5
        two.fill = Instance.new("Frame", two.track)
        two.fill.Name = "ProgressFill"
        -- Hard-anchored to the rail's LEFT edge: the fill starts at x = 0 and
        -- grows to the right. Nothing may mirror it.
        two.fill.AnchorPoint = Vector2.new(0, 0)
        two.fill.Position = UDim2.fromOffset(0, 0)
        two.fill.Size = UDim2.fromOffset(0, LINE_H)
        two.fill.BackgroundColor3 = P.light
        two.fill.BackgroundTransparency = 0.10
        two.fill.BorderSizePixel = 0
        two.fill.ZIndex = 12
        corner(two.fill, LINE_R)
        two.fillGradient = gradient(two.fill, P.deep, Color3.fromRGB(154, 108, 255))

        -- CHARACTER AVATAR (moved out of the settings identity badge) ---------
        -- Small head-shot, centred above the progress line.
        two.avatar = Instance.new("ImageLabel", two.frame)
        two.avatar.Name = "GrabAvatar"
        two.avatar.AnchorPoint = Vector2.new(0.5, 0)
        two.avatar.Position = UDim2.new(0.5, 0, 0, 4)
        two.avatar.Size = UDim2.fromOffset(26, 26)
        two.avatar.BackgroundColor3 = Color3.fromRGB(20, 17, 38)
        two.avatar.BorderSizePixel = 0
        two.avatar.ScaleType = Enum.ScaleType.Crop
        two.avatar.ZIndex = 14
        corner(two.avatar, 13)
        local avatarStroke = Instance.new("UIStroke", two.avatar)
        avatarStroke.Color = Color3.fromRGB(40, 40, 48)
        avatarStroke.Thickness = 1.5
        avatarStroke.Transparency = 0.15
        task.spawn(function()
            local ok, thumbnail = pcall(function()
                local players = game:GetService("Players")
                return players:GetUserThumbnailAsync(players.LocalPlayer.UserId,
                    Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
            end)
            if ok and thumbnail and two.avatar.Parent then two.avatar.Image = thumbnail end
        end)

        -- LEFT SIDE: counter numbers ------------------------------------------
        -- Slim violet tick that brightens while a steal target is ready.
        two.accent = Instance.new("Frame", two.frame)
        two.accent.Name = "Accent"
        two.accent.Size = UDim2.fromOffset(3, 34)
        two.accent.Position = UDim2.fromOffset(4, 12)
        two.accent.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
        two.accent.BorderSizePixel = 0
        two.accent.ZIndex = 13
        corner(two.accent, 2)

        -- The number and the state word live in one horizontal row and both
        -- size themselves to their text, so WAIT / STEAL! always sits right
        -- next to the counter instead of floating far to its right.
        local counterRow = Instance.new("Frame", two.frame)
        counterRow.Name = "CounterRow"
        counterRow.Position = UDim2.fromOffset(12, 2)
        counterRow.Size = UDim2.fromOffset(128, 18)
        counterRow.BackgroundTransparency = 1
        counterRow.BorderSizePixel = 0
        counterRow.ZIndex = 14
        local counterLayout = Instance.new("UIListLayout", counterRow)
        counterLayout.FillDirection = Enum.FillDirection.Horizontal
        counterLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        counterLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        counterLayout.SortOrder = Enum.SortOrder.LayoutOrder
        counterLayout.Padding = UDim.new(0, 4)

        two.counter = Instance.new("TextLabel", counterRow)
        two.counter.Name = "GrabCounter"
        two.counter.LayoutOrder = 1
        two.counter.Size = UDim2.new(0, 0, 1, 0)
        two.counter.AutomaticSize = Enum.AutomaticSize.X
        two.counter.BackgroundTransparency = 1
        two.counter.Text = "0%"
        two.counter.TextColor3 = P.text
        two.counter.Font = Enum.Font.GothamBlack
        two.counter.TextSize = 15
        two.counter.TextXAlignment = Enum.TextXAlignment.Left
        two.counter.ZIndex = 14

        two.status = Instance.new("TextLabel", counterRow)
        two.status.Name = "Readiness"
        two.status.LayoutOrder = 2
        two.status.Size = UDim2.new(0, 0, 0, 12)
        two.status.AutomaticSize = Enum.AutomaticSize.X
        two.status.BackgroundTransparency = 1
        two.status.Text = "WAIT"
        two.status.TextColor3 = Color3.fromRGB(167, 139, 250)
        two.status.Font = Enum.Font.GothamBold
        two.status.TextSize = 10
        two.status.TextXAlignment = Enum.TextXAlignment.Left
        two.status.ZIndex = 14

        two.limit = Instance.new("TextLabel", two.frame)
        two.limit.Name = "ProgressLimit"
        two.limit.Position = UDim2.fromOffset(12, 20)
        two.limit.Size = UDim2.fromOffset(84, 12)
        two.limit.BackgroundTransparency = 1
        two.limit.Text = "MAX: 75%"
        two.limit.TextColor3 = Color3.fromRGB(196, 181, 255)
        two.limit.Font = Enum.Font.GothamBlack
        two.limit.TextSize = 9
        two.limit.TextXAlignment = Enum.TextXAlignment.Left
        two.limit.ZIndex = 14

        -- RIGHT SIDE: FPS / PING plate (unchanged, "|" divider removed) ------
        local statsPlate = Instance.new("Frame", two.frame)
        statsPlate.Name = "PerformancePlate"
        statsPlate.Position = UDim2.new(1, -108, 0, 8)
        statsPlate.Size = UDim2.fromOffset(100, 18)
        -- Opaque dark capsule: nothing can bleed through the FPS/PING text.
        statsPlate.BackgroundColor3 = Color3.fromRGB(20, 17, 38)
        statsPlate.BackgroundTransparency = 0
        statsPlate.BorderSizePixel = 0
        statsPlate.ZIndex = 13
        corner(statsPlate, 9)
        local statsStroke = Instance.new("UIStroke", statsPlate)
        statsStroke.Color = Color3.fromRGB(40, 40, 48)
        statsStroke.Transparency = 0.10
        statsStroke.Thickness = 1
        two.stats = Instance.new("TextLabel", statsPlate)
        two.stats.Name = "Performance"
        two.stats.Position = UDim2.fromOffset(0, 0)
        two.stats.Size = UDim2.new(1, 0, 1, 0)
        two.stats.BackgroundTransparency = 1
        two.stats.Text = "FPS --   PING --ms"
        two.stats.TextColor3 = Color3.fromRGB(196, 181, 255)
        two.stats.Font = Enum.Font.GothamSemibold
        two.stats.TextSize = 9
        two.stats.TextXAlignment = Enum.TextXAlignment.Center
        two.stats.ZIndex = 14

        -- EXTRA LINK CARD ----------------------------------------------------
        -- A small companion panel pinned directly ABOVE the Auto Grab card.
        -- NOTE: it cannot be parented to the card - a CanvasGroup always clips
        -- its children to its own rectangle, so it would stay invisible. It is
        -- parented to the same ScreenGui and bound to the card instead: it
        -- follows the card while dragging, scales with it and fades in/out with
        -- it, so it behaves as one attached widget.
        local GRAB_LINK = ".gg/xefq3VrMet"
        local linkPlate = Instance.new("Frame", gui)
        linkPlate.Name = "GrabLinkPlate"
        linkPlate.AnchorPoint = Vector2.new(0.5, 1)
        linkPlate.Size = UDim2.fromOffset(132, 20)
        linkPlate.BackgroundColor3 = Color3.fromRGB(12, 11, 24)
        linkPlate.BackgroundTransparency = 0.06
        linkPlate.BorderSizePixel = 0
        linkPlate.Visible = false
        linkPlate.ZIndex = 12
        corner(linkPlate, 8)
        local linkScale = Instance.new("UIScale", linkPlate)
        linkScale.Name = "GrabLinkScale"
        -- The link must stay readable: it never shrinks below 0.9 even when
        -- the Auto Grab card itself is scaled further down.
        linkScale.Scale = math.max(Grab.getScale(), 0.9)
        local linkStroke = Instance.new("UIStroke", linkPlate)
        linkStroke.Color = Color3.fromRGB(40, 40, 48)
        linkStroke.Thickness = 1.2
        linkStroke.Transparency = 0.15
        local linkButton = Instance.new("TextButton", linkPlate)
        linkButton.Name = "GrabLink"
        linkButton.Size = UDim2.new(1, 0, 1, 0)
        linkButton.BackgroundTransparency = 1
        linkButton.BorderSizePixel = 0
        linkButton.AutoButtonColor = false
        linkButton.Text = GRAB_LINK
        linkButton.TextColor3 = Color3.fromRGB(245, 245, 250)
        linkButton.Font = Enum.Font.GothamBold
        linkButton.TextSize = 11
        linkButton.TextXAlignment = Enum.TextXAlignment.Center
        linkButton.ZIndex = 13
        -- Tapping it copies the link when the executor exposes a clipboard.
        linkButton.Activated:Connect(function()
            if _anyKeyListening or not Grab.alive then return end
            local copied = false
            pcall(function()
                if type(setclipboard) == "function" then setclipboard(GRAB_LINK); copied = true
                elseif type(toclipboard) == "function" then toclipboard(GRAB_LINK); copied = true
                elseif type(clipboard) == "function" then clipboard.set(GRAB_LINK); copied = true end
            end)
            if not copied then return end
            UI.text(linkButton, "COPIED!")
            task.delay(1.2, function()
                if linkButton.Parent then UI.text(linkButton, GRAB_LINK) end
            end)
        end)
        -- Bind the link card to the Auto Grab card: same centre, flush against
        -- the card's top edge (2px overlap kills the seam, so they read as one
        -- attached widget). The card's OWN scale drives the height.
        local function syncLinkPlate()
            local cardScale = two.scale and two.scale.Scale or 1
            local cardTop = two.frame.Position.Y.Offset - (two.frame.Size.Y.Offset * cardScale)
            linkPlate.Position = UDim2.new(
                two.frame.Position.X.Scale, two.frame.Position.X.Offset,
                two.frame.Position.Y.Scale, cardTop + 2)
        end
        Grab.linkFrame, Grab.linkScale, Grab.linkSync = linkPlate, linkScale, syncLinkPlate
        syncLinkPlate()
        two.frame:GetPropertyChangedSignal("Position"):Connect(syncLinkPlate)
        linkScale:GetPropertyChangedSignal("Scale"):Connect(syncLinkPlate)

        -- no visible V1/V2 zoom controls

        Grab.renderConnection = RunService.RenderStepped:Connect(function(dt)
            if not Grab.alive then return end
            local target = Grab.currentEngine() and Grab.getProgress() or 0
            Grab.displayed = Grab.displayed + (target - Grab.displayed) * (1 - math.exp(-dt * 12))
            local progress = math.clamp(Grab.displayed, 0, 1)
            one.fill.Size = UDim2.new(progress, 0, 1, 0)
            one.percent.Text = tostring(math.floor(progress * 100 + 0.5)) .. "%"
            -- The fill lives on its own thin row now, so it shows the true
            -- percentage across the whole rail (no right-side reservation).
            -- Width is computed in PIXELS from the rail's left edge (x = 0),
            -- so the bar can only ever start on the left and grow rightwards.
            do
                local rail = two.track.AbsoluteSize
                local railW = rail.X > 0 and rail.X or (GRAB_W - 24)
                local railH = rail.Y > 0 and rail.Y or LINE_H
                two.fill.Position = UDim2.fromOffset(0, 0)
                two.fill.Size = UDim2.fromOffset(math.max(0, railW * progress), railH)
            end
            if Grab.visibleStyle == 2 then
                local ready = Grab.isReady()
                local phase = Grab.phaseV1
                -- WAIT while the bar fills; STEAL! the moment it reaches the
                -- configured MAX (that is the point where the grab fires).
                local maxFraction = math.clamp((tonumber(State.autoGrabMode) or 100) / 100, 0, 1)
                local stealNow = phase == "finishing"
                    or (maxFraction > 0 and progress >= maxFraction - 0.004)
                    or (maxFraction <= 0 and ready)
                local statusWord = stealNow and "STEAL!" or "WAIT"
                local percentText = tostring(math.floor(progress * 100 + 0.5)) .. "%"
                local bright = stealNow or ready
                UI.text(two.counter, percentText)
                UI.text(two.status, statusWord)
                UI.animate(two.counter, {TextColor3 = bright and Color3.fromRGB(226, 216, 255) or P.text}, 0.16)
                UI.animate(two.status, {TextColor3 = bright and Color3.fromRGB(226, 216, 255) or Color3.fromRGB(167, 139, 250)}, 0.16)
                UI.animate(two.accent, {BackgroundColor3 = bright and P.light or Color3.fromRGB(40, 40, 48)}, 0.16)
                two.outlineGradient.Rotation = (two.outlineGradient.Rotation + dt * 135) % 360
                two.fillGradient.Offset = Vector2.new(math.sin(os.clock() * 1.8) * 0.15, 0)
                -- Real render FPS: count frames over a quarter-second window
                -- and smooth the result, rather than displaying one noisy dt.
                local perf = Grab.perf
                perf.elapsed += dt
                perf.frames += 1
                if perf.elapsed >= 0.25 then
                    local measured = perf.frames / math.max(perf.elapsed, 0.001)
                    perf.fps = perf.fps <= 0 and measured or (perf.fps * 0.65 + measured * 0.35)
                    perf.elapsed, perf.frames = 0, 0
                end
                if tick() - perf.pingAt >= 0.35 then
                    perf.pingAt = tick()
                    local ping = 0
                    pcall(function()
                        ping = math.floor(LP:GetNetworkPing() * 1000 + 0.5)
                    end)
                    if ping <= 0 then
                        pcall(function()
                            local item = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]
                            ping = item and math.floor(item:GetValue() + 0.5) or 0
                        end)
                    end
                    perf.ping = ping
                end
                two.stats.Text = string.format("FPS%d   PING %dms", math.floor(perf.fps + 0.5), perf.ping)
                two.limit.Text = "MAX: " .. tostring(math.floor(State.autoGrabMode + 0.5)) .. "%"
            end
        end)
        table.insert(Grab.connections, gui.Destroying:Connect(Grab.destroy))
        Grab.refresh()
    end
    -- 
UI.ready = true
end

-- ========================================================================
-- CONFIGURATION RESTORATION
-- ========================================================================
local _savedCfg = nil

local function loadConfigKeys()
    local raw = safeReadFile("k2_duels_config.json") or safeReadFile("k2_duels_backup.json")
    if not raw then return end
    local ok, cfg = pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok or not cfg then return end
    _savedCfg = cfg
    -- Restored here (synchronously, before the intro thread fires) so turning
    -- the Intro toggle OFF really keeps the intro from playing on the next run.
    if cfg.introEnabled ~= nil then State.introEnabled = cfg.introEnabled == true end
    if cfg.espEnabled ~= nil then State.espEnabled = cfg.espEnabled == true end
    if cfg.tracersEnabled ~= nil then State.tracersEnabled = cfg.tracersEnabled == true end
    if cfg.fpsBoost ~= nil then State.fpsBoostEnabled = cfg.fpsBoost == true end
    if cfg.autoGrabStopEnabled ~= nil then State.autoGrabStopEnabled = cfg.autoGrabStopEnabled == true end

    local function lk(e, d)
        if type(d) ~= "table" then return end
        if d.kb and Enum.KeyCode[d.kb] then e.kb = Enum.KeyCode[d.kb] end
        if d.gp and Enum.KeyCode[d.gp] then e.gp = Enum.KeyCode[d.gp] end
    end

    lk(KB.DropBrainrot, cfg.dropBrainrotKey)
    lk(KB.AutoLeft, cfg.autoLeftKey)
    lk(KB.AutoRight, cfg.autoRightKey)
    lk(KB.AutoBat, cfg.autoBatKey)
    lk(KB.LaggerToggle, cfg.laggerToggleKey)
    lk(KB.TPFloor, cfg.tpFloorKey)
    lk(KB.TpBat, cfg.tpBatKey or cfg.tpBatNormalKey)
    lk(KB.InstantReset, cfg.instantResetKey or cfg.instaResetKey)
    lk(KB.GuiHide, cfg.guiHideKey)
    lk(KB.SpeedToggle, cfg.speedToggleKey)
    if (KB.LaggerToggle.kb and KB.InstantReset.kb and KB.LaggerToggle.kb == KB.InstantReset.kb)
        or (KB.LaggerToggle.gp and KB.InstantReset.gp and KB.LaggerToggle.gp == KB.InstantReset.gp) then
        KB.LaggerToggle.kb, KB.LaggerToggle.gp = Enum.KeyCode.G, nil
    end

    if cfg.normalSpeed and type(cfg.normalSpeed) == "number" then State.NS = cfg.normalSpeed end
    if cfg.carrySpeed and type(cfg.carrySpeed) == "number" then State.CS = cfg.carrySpeed end
    if cfg.autoSwitchCarrySpeed ~= nil then
        State.autoCarrySpeedEnabled = cfg.autoSwitchCarrySpeed == true
    elseif cfg.autoCarrySpeed ~= nil then
        State.autoCarrySpeedEnabled = cfg.autoCarrySpeed == true
    end
    -- Radius is intentionally not loaded from old configs. Yout's 61-stud
    -- limit is authoritative for both visual and normal grab targeting.
    State.StealV1.StealRadius, State.StealV2.StealRadius = 61, 61
    if type(cfg.autoGrabMode) == "number" then
        State.autoGrabMode = math.clamp(math.round(cfg.autoGrabMode), 0, 100)
        State.autoGrabStopTime = State.autoGrabMode == 0 and 0 or (State.autoGrabMode / 100) * State.StealV1.StealDuration
    end
    Grab.loadSettings(cfg)
    if cfg.antiRagdollMode == "Off" or cfg.antiRagdollMode == "Normal" or cfg.antiRagdollMode == "Custom" then
        State.antiRagdollMode = cfg.antiRagdollMode
    else
        State.antiRagdollMode = cfg.antiRagdoll == true and "Normal" or "Off"
    end
    if cfg.laggerSpeed and type(cfg.laggerSpeed) == "number" then State.LAGGER_SPEED = cfg.laggerSpeed end
    if cfg.laggerCarrySpeed and type(cfg.laggerCarrySpeed) == "number" then State.LAGGER_CARRY_SPEED = cfg.laggerCarrySpeed end
    if cfg.speedEngine ~= "Arabi" then
        if cfg.laggerSpeed == 40 then State.LAGGER_SPEED = 15 end
        if cfg.laggerCarrySpeed == 20 then State.LAGGER_CARRY_SPEED = 24.5 end
    end
    if cfg.autoTPHeight and type(cfg.autoTPHeight) == "number" then State.autoTPHeight = cfg.autoTPHeight end
    if type(cfg.bodyLockRange) == "number" then State.bodyLockRange = math.clamp(math.floor(cfg.bodyLockRange), 5, 200) end
    -- Body Lock now restores its saved state: the pill is wired to the engine
    -- (BodyLock.visual), so a re-armed lock shows as ON instead of silently
    -- running while the pill looked Off.
    if cfg.bodyLockEnabled ~= nil then State.bodyLockEnabled = cfg.bodyLockEnabled == true end
    if cfg.antiFling ~= nil then State.antiFlingEnabled = cfg.antiFling == true end
    if cfg.instantResetOnDie ~= nil then State.instantResetOnDieEnabled = cfg.instantResetOnDie == true end
    if cfg.autoSwing ~= nil then State.autoSwingEnabled = cfg.autoSwing == true end
    if type(cfg.animPack) == "string" and table.find(HORIZON_ANIMATION_PACK_LIST, cfg.animPack) then
        State.animPack = cfg.animPack
    end
end

local function loadConfigState()
    local cfg = _savedCfg
    if not cfg then return end

    if cfg.autoPlayMode == "Auto" or cfg.autoPlayMode == "Half" then
        State.autoPlayMode = cfg.autoPlayMode
    else
        local savedMode = safeReadFile("k2AutoPlayMode.txt")
        if savedMode == "Auto" or savedMode == "Half" then
            State.autoPlayMode = savedMode
        end
    end

    if normalBox then normalBox.Text = tostring(State.NS) end
    if carryBox then carryBox.Text = tostring(State.CS) end
    if laggerCarryBox then laggerCarryBox.Text = tostring(State.LAGGER_CARRY_SPEED) end
    if autoTPHeightBox then autoTPHeightBox.Text = tostring(State.autoTPHeight) end
    if bodyLockRangeBox then bodyLockRangeBox.Text = tostring(State.bodyLockRange) end

    task.spawn(function()
        task.wait(0.15)
        if cfg.infJumpMode then
            State.infJumpMode = cfg.infJumpMode
            if setJumpModeVisual then setJumpModeVisual(State.infJumpMode) end
        end
        AntiDie.setEnabled(cfg.antiDie == true)
        BodyLock.setEnabled(State.bodyLockEnabled)
        AntiFling.setEnabled(State.antiFlingEnabled)
        DeathReset.setEnabled(State.instantResetOnDieEnabled)
        AnimPack.apply(State.animPack)
        if State.instantResetOnDieEnabled and State.antiDieEnabled then
            AntiDie.setEnabled(false)
            if AntiDie.visual then AntiDie.visual(false) end
        end
        Ragdoll.setMode(State.antiRagdollMode)
        Grab.applyScale()
        Grab.restore()
        if setAutoGrabVisual then setAutoGrabVisual(State.SemiNormalOpen) end

        if TpBat.refreshModeUI then TpBat.refreshModeUI() end
        if cfg.tpBatEnabled == true then TpBat.setEnabled(true) end
        if cfg.infiniteJump then
            State.infJumpEnabled = true
            if setInfJumpVisual then setInfJumpVisual(true) end
        end
        if cfg.medusaCounter then
            State.medusaCounterEnabled = true
            if setMedusaVisual then setMedusaVisual(true) end
            setupMedusa(LP.Character)
        end
        if cfg.batCounter then
            State.batCounterEnabled = true
            if setBatCounterVisual then setBatCounterVisual(true) end
            startBatCounter()
        end
        if cfg.laggerMode then
            State.laggerToggled = true
            State.speedMode = false
            if cfg.laggerCarryMode then
                State.laggerPhase = 2
            else
                State.laggerPhase = 1
            end
            refreshSpeedModeLabel()
        elseif cfg.carryMode then
            State.speedMode = false
            toggleCarryMode()
        end
        if State.autoCarrySpeedEnabled then
            -- Keep the SPEED switch armed; Horizon's logic selects Carry only
            -- when a prompt/steal/carry handoff is actually detected.
            if setAutoSwitchSpeedVisual then setAutoSwitchSpeedVisual(true) end
            refreshSpeedModeLabel()
        end
        if cfg.autoTPEnabled then
            State.autoTPEnabled = true
            if setAutoTPVisual then setAutoTPVisual(true) end
            startAutoTP()
        end
        AutoSwing.setEnabled(State.autoSwingEnabled)
        if cfg.autoBat then
            State.autoBatEnabled = true
            if setAutoBatVisual then setAutoBatVisual(true) end
            queueAutoBatStart()
        end
        if cfg.unwalkEnabled then
            State.unwalkEnabled = true
            if setUnwalkVisual then setUnwalkVisual(true) end
            task.spawn(function() task.wait(0.5); startUnwalk() end)
        end
        if cfg.antiLag then
            enableAntiLag()
            if setAntiLagVisual then setAntiLagVisual(true) end
        end
        if cfg.fpsBoost then
            applyFPSBoost()
            if setFPSBoostVisual then setFPSBoostVisual(true) end
        end
        if cfg.espEnabled and applyESPState then applyESPState(true) end
        if cfg.tracersEnabled and applyTracersState then applyTracersState(true) end
        if cfg.stretchRez then
            enableStretchRez()
            if setStretchRezVisual then setStretchRezVisual(true) end
        end

        if cfg.introEnabled ~= nil then
            State.introEnabled = cfg.introEnabled == true
            if setIntroVisual then setIntroVisual(State.introEnabled) end
        end
        if cfg.skyTheme and K2_SKY_PRESETS[cfg.skyTheme] then
            currentSkyTheme = cfg.skyTheme
            if currentSkyTheme ~= "Off" then k2ApplySky(currentSkyTheme) end
            if setSkyVisual then setSkyVisual(currentSkyTheme) end
        end
    end)
end

-- ========================================================================
-- INTRO SCREEN - BLACK SPACE / FLYING STARS / PURPLE "K2 DUELS" + CHARGE LINE
-- ========================================================================
local function playK2Intro()
    if not State.introEnabled then return end

    local parent = getSafeGuiParent()

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "K2DuelsIntro"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.DisplayOrder = 5000
    protectGuiObject(screenGui)
    screenGui.Parent = parent

    local PURPLE_ACCENT = UI.theme.accent
    local PURPLE_DEEP   = Color3.fromRGB(40, 40, 48)
    local PURPLE_LIGHT  = UI.theme.light
    local PURPLE_FILL   = Color3.fromRGB(200, 200, 210)

    local rng = Random.new(os.clock() * 9973)

    local finished = false
    local starConnection = nil

    local function tween(object, duration, style, direction, goal)
        if finished then return end
        pcall(function()
            TweenService:Create(object, TweenInfo.new(duration, style, direction), goal):Play()
        end)
    end

    -- --------------------------------------------------------------------
    -- PURE BLACK SPACE
    -- --------------------------------------------------------------------
    local space = Instance.new("Frame")
    space.Name = "Space"
    space.Size = UDim2.fromScale(1, 1)
    space.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    space.BorderSizePixel = 0
    space.ZIndex = 1
    space.Parent = screenGui

    -- Everything that animates lives inside one CanvasGroup, so the intro can
    -- dissolve in a single smooth step (exactly like a skip).
    local content = Instance.new("CanvasGroup")
    content.Name = "IntroContent"
    content.Size = UDim2.fromScale(1, 1)
    content.BackgroundTransparency = 1
    content.GroupTransparency = 1
    content.ZIndex = 2
    content.Parent = screenGui

    -- --------------------------------------------------------------------
    -- PURPLE NEBULA GLOW (built from frames, no external assets)
    -- --------------------------------------------------------------------
    for index = 1, 3 do
        local blob = Instance.new("Frame")
        blob.Name = "Nebula" .. index
        blob.AnchorPoint = Vector2.new(0.5, 0.5)
        blob.Position = UDim2.fromScale(0.16 + index * 0.26, 0.2 + (index % 2) * 0.55)
        blob.Size = UDim2.fromScale(0.64, 0.64)
        blob.Rotation = index * 26
        blob.BackgroundColor3 = index == 2 and PURPLE_DEEP or PURPLE_ACCENT
        blob.BackgroundTransparency = 0.9
        blob.BorderSizePixel = 0
        blob.ZIndex = 2
        Instance.new("UICorner", blob).CornerRadius = UDim.new(1, 0)
        local gradient = Instance.new("UIGradient", blob)
        gradient.Rotation = index * 70
        gradient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.25),
            NumberSequenceKeypoint.new(0.55, 0.92),
            NumberSequenceKeypoint.new(1, 1),
        })
        blob.Parent = content
    end

    -- --------------------------------------------------------------------
    -- FLYING STARFIELD: small white stars with a purple hue
    -- --------------------------------------------------------------------
    local starLayer = Instance.new("Frame")
    starLayer.Name = "StarField"
    starLayer.BackgroundTransparency = 1
    starLayer.Size = UDim2.fromScale(1, 1)
    starLayer.ZIndex = 3
    starLayer.Parent = content

    local stars = {}
    for index = 1, 96 do
        local size = rng:NextInteger(1, 3)
        local star = Instance.new("Frame")
        star.Name = "Star"
        star.AnchorPoint = Vector2.new(0.5, 0.5)
        star.BorderSizePixel = 0
        star.BackgroundTransparency = 0.2
        star.Size = UDim2.fromOffset(size, size)
        star.ZIndex = 3
        Instance.new("UICorner", star).CornerRadius = UDim.new(1, 0)

        -- Mostly pure white stars, with a purple minority for the purple space.
        local roll = rng:NextNumber()
        if roll > 0.84 then
            star.BackgroundColor3 = PURPLE_LIGHT
        elseif roll > 0.68 then
            star.BackgroundColor3 = PURPLE_FILL
        else
            star.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        end

        local angle = rng:NextNumber(-0.5, 0.5)
        local speed = rng:NextNumber(0.05, 0.2)
        local startX = rng:NextNumber()
        local startY = rng:NextNumber()
        star.Position = UDim2.fromScale(startX, startY)
        star.Parent = starLayer

        stars[index] = {
            object = star,
            x = startX,
            y = startY,
            vx = math.cos(angle) * speed * (rng:NextNumber() < 0.5 and -1 or 1),
            vy = math.sin(angle) * speed,
            phase = rng:NextNumber(0, math.pi * 2),
            twinkle = rng:NextNumber(1.5, 4),
            base = rng:NextNumber(0.15, 0.55),
            bright = size >= 3,
        }
    end

    -- A few fast streaks for depth.
    local streaks = {}
    for index = 1, 4 do
        local streak = Instance.new("Frame")
        streak.Name = "Streak" .. index
        streak.AnchorPoint = Vector2.new(0.5, 0.5)
        streak.BackgroundColor3 = PURPLE_LIGHT
        streak.BackgroundTransparency = 0.3
        streak.BorderSizePixel = 0
        streak.Rotation = 18
        streak.Size = UDim2.fromOffset(rng:NextInteger(18, 42), 1)
        streak.ZIndex = 3
        Instance.new("UICorner", streak).CornerRadius = UDim.new(1, 0)
        streak.Position = UDim2.fromScale(rng:NextNumber(-0.1, 1), rng:NextNumber())
        streak.Parent = starLayer

        streaks[index] = {
            object = streak,
            x = rng:NextNumber(-0.1, 1),
            y = rng:NextNumber(0, 0.9),
            speed = rng:NextNumber(0.32, 0.58),
        }
    end

    local clock = 0
    starConnection = RunService.RenderStepped:Connect(function(delta)
        if finished or not screenGui.Parent then return end
        clock = clock + delta

        for _, record in ipairs(stars) do
            local object = record.object
            if object and object.Parent then
                record.x = record.x + record.vx * delta
                record.y = record.y + record.vy * delta
                if record.x > 1.08 then
                    record.x = -0.08
                    record.y = rng:NextNumber()
                elseif record.x < -0.08 then
                    record.x = 1.08
                    record.y = rng:NextNumber()
                end
                if record.y > 1.08 then
                    record.y = -0.08
                    record.x = rng:NextNumber()
                elseif record.y < -0.08 then
                    record.y = 1.08
                    record.x = rng:NextNumber()
                end
                object.Position = UDim2.fromScale(record.x, record.y)

                local shimmer = (math.sin(clock * record.twinkle + record.phase) + 1) * 0.5
                local transparency = record.base + (1 - shimmer) * 0.45
                if record.bright then transparency = transparency - 0.22 end
                object.BackgroundTransparency = math.clamp(transparency, 0, 0.96)
            end
        end

        for _, record in ipairs(streaks) do
            local object = record.object
            if object and object.Parent then
                record.x = record.x + record.speed * delta
                if record.x > 1.15 then
                    record.x = -0.15
                    record.y = rng:NextNumber(0, 0.85)
                end
                object.Position = UDim2.fromScale(record.x, record.y)
                object.BackgroundTransparency = 0.2 + 0.35 * math.abs(math.sin(clock * 1.5 + record.y * 6))
            end
        end
    end)

    -- --------------------------------------------------------------------
    -- TITLE: "K2 Duels" in purple
    -- --------------------------------------------------------------------
    local titleHolder = Instance.new("Frame")
    titleHolder.Name = "TitleHolder"
    titleHolder.AnchorPoint = Vector2.new(0.5, 0.5)
    titleHolder.Position = UDim2.fromScale(0.5, 0.5)
    titleHolder.Size = UDim2.fromScale(0.5, 0.11)
    titleHolder.BackgroundTransparency = 1
    titleHolder.ZIndex = 6
    titleHolder.Parent = content

    local titleGlow = Instance.new("TextLabel")
    titleGlow.Name = "TitleGlow"
    titleGlow.Size = UDim2.fromScale(1, 1)
    titleGlow.BackgroundTransparency = 1
    titleGlow.Text = "K2 Duels"
    titleGlow.Font = Enum.Font.GothamBlack
    titleGlow.TextScaled = true
    titleGlow.TextColor3 = PURPLE_DEEP
    titleGlow.TextTransparency = 1
    titleGlow.ZIndex = 5
    local glowStroke = Instance.new("UIStroke", titleGlow)
    glowStroke.Color = PURPLE_FILL
    glowStroke.Thickness = 2.5
    glowStroke.Transparency = 1
    titleGlow.Parent = titleHolder

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.fromScale(1, 1)
    title.BackgroundTransparency = 1
    title.Text = "K2 Duels"
    title.Font = Enum.Font.GothamBlack
    title.TextScaled = true
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextTransparency = 1
    title.ZIndex = 6
    local titleGradient = Instance.new("UIGradient", title)
    titleGradient.Rotation = 90
    titleGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, PURPLE_LIGHT),
        ColorSequenceKeypoint.new(0.45, PURPLE_FILL),
        ColorSequenceKeypoint.new(1, PURPLE_ACCENT),
    })
    title.Parent = titleHolder

    -- --------------------------------------------------------------------
    -- CHARGE LINE: keeps filling with purple under the word
    -- --------------------------------------------------------------------
    local track = Instance.new("Frame")
    track.Name = "ChargeTrack"
    track.AnchorPoint = Vector2.new(0.5, 0.5)
    track.Position = UDim2.fromScale(0.5, 0.6)
    track.Size = UDim2.new(0.4, 0, 0, 4)
    track.BackgroundColor3 = Color3.fromRGB(38, 22, 62)
    track.BackgroundTransparency = 1
    track.BorderSizePixel = 0
    track.ClipsDescendants = true
    track.ZIndex = 6
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
    local trackStroke = Instance.new("UIStroke", track)
    trackStroke.Color = PURPLE_FILL
    trackStroke.Thickness = 1
    trackStroke.Transparency = 1
    track.Parent = content

    local fill = Instance.new("Frame")
    fill.Name = "ChargeFill"
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = PURPLE_ACCENT
    fill.BorderSizePixel = 0
    fill.ZIndex = 7
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
    local fillGradient = Instance.new("UIGradient", fill)
    fillGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, PURPLE_DEEP),
        ColorSequenceKeypoint.new(0.65, PURPLE_ACCENT),
        ColorSequenceKeypoint.new(1, PURPLE_LIGHT),
    })
    fill.Parent = track

    local fillHead = Instance.new("Frame")
    fillHead.Name = "ChargeHead"
    fillHead.AnchorPoint = Vector2.new(0.5, 0.5)
    fillHead.Position = UDim2.fromScale(0, 0.5)
    fillHead.Size = UDim2.new(0, 10, 0, 10)
    fillHead.BackgroundColor3 = PURPLE_LIGHT
    fillHead.BackgroundTransparency = 1
    fillHead.BorderSizePixel = 0
    fillHead.ZIndex = 8
    Instance.new("UICorner", fillHead).CornerRadius = UDim.new(1, 0)
    fillHead.Parent = track

    -- --------------------------------------------------------------------
    -- EXIT (also used by the one click/tap skip)
    -- --------------------------------------------------------------------
    local function finishIntro()
        if finished then return end
        finished = true
        if starConnection then
            pcall(function() starConnection:Disconnect() end)
            starConnection = nil
        end
        pcall(function()
            TweenService:Create(content, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {GroupTransparency = 1}):Play()
            TweenService:Create(space, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {BackgroundTransparency = 1}):Play()
        end)
        task.delay(0.55, function()
            pcall(function() screenGui:Destroy() end)
        end)
    end

    -- Skip button removed

    -- --------------------------------------------------------------------
    -- ANIMATION TIMELINE
    -- --------------------------------------------------------------------
    task.spawn(function()
        -- Intro music (unchanged asset).
        pcall(function()
            local asset = safeGetAsset("k2DuelsIntro_iyw1cb.mp3")
            if asset and asset ~= "" then
                local sound = Instance.new("Sound")
                sound.Name = "K2DuelsIntroSong"
                sound.SoundId = asset
                sound.Volume = 1
                sound.Parent = parent
                sound:Play()
            end
        end)

        if finished or not screenGui.Parent then return end

        -- Space fades in, then the word rises into place with a purple glow.
        tween(content, 0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, {GroupTransparency = 0})
        tween(titleGlow, 0.95, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {TextTransparency = 0.55})
        tween(glowStroke, 0.95, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {Transparency = 0.5})
        tween(title, 0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, {TextTransparency = 0})
        tween(titleHolder, 0.95, Enum.EasingStyle.Back, Enum.EasingDirection.Out, {
            Size = UDim2.fromScale(0.62, 0.142),
            Position = UDim2.fromScale(0.5, 0.45),
        })

        -- Breathing purple glow while the intro is on screen.
        task.spawn(function()
            local dim = false
            while not finished and screenGui.Parent do
                dim = not dim
                tween(glowStroke, 1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, {
                    Transparency = dim and 0.75 or 0.5,
                })
                task.wait(1.1)
            end
        end)

        task.wait(0.45)
        if finished then return end

        -- The charge line appears and keeps filling with purple.
        tween(track, 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, {BackgroundTransparency = 0})
        tween(trackStroke, 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, {Transparency = 0.35})
        tween(fillHead, 0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, {BackgroundTransparency = 0})
        tween(fill, 4.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, {Size = UDim2.fromScale(1, 1)})
        tween(fillHead, 4.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, {Position = UDim2.fromScale(1, 0.5)})

        task.spawn(function()
            local big = false
            while not finished and screenGui.Parent do
                big = not big
                tween(fillHead, 0.34, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, {
                    Size = UDim2.new(0, big and 16 or 10, 0, big and 16 or 10),
                })
                task.wait(0.34)
            end
        end)

        task.wait(4.8)
        if finished then return end

        -- Charge complete: the intro dissolves smoothly, like a skip.
        tween(title, 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, {TextTransparency = 1})
        tween(titleGlow, 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, {TextTransparency = 1})
        tween(titleHolder, 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
            Size = UDim2.fromScale(0.68, 0.156),
            Position = UDim2.fromScale(0.5, 0.44),
        })
        task.wait(0.14)
        finishIntro()
    end)
end

-- Song Preload (Failsafe)
task.spawn(function()
    pcall(function()
        if not safeIsFile("k2DuelsIntro_iyw1cb.mp3") then
            local songData = safeHttpGet("https://files.catbox.moe/iyw1cb.mp3")
            if songData then
                safeWriteFile("k2DuelsIntro_iyw1cb.mp3", songData)
            end
        end
    end)
    task.wait(0.3)
    playK2Intro()
end)

-- ========================================================================
-- INITIALIZATION (protected: shows error on screen if boot fails)
-- ========================================================================
local function k2ShowBootError(where, err)
    pcall(function()
        local parent = getSafeGuiParent()
        local old = parent:FindFirstChild("K2BootError")
        if old then old:Destroy() end
        local g = Instance.new("ScreenGui")
        g.Name = "K2BootError"
        g.ResetOnSpawn = false
        g.DisplayOrder = 9999
        g.Parent = parent
        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(1, -20, 0, 140)
        t.Position = UDim2.new(0, 10, 0, 120)
        t.BackgroundColor3 = UI.theme.panel
        t.BackgroundTransparency = 0.2
        t.BorderSizePixel = 0
        t.TextColor3 = UI.theme.text
        t.Font = Enum.Font.GothamBold
        t.TextSize = 13
        t.TextWrapped = true
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.TextYAlignment = Enum.TextYAlignment.Top
        t.Text = "K2 Duels BOOT ERROR [" .. tostring(where) .. "]: " .. tostring(err)
        t.Parent = g
    end)
    warn("[K2 Duels] Boot failed at " .. tostring(where) .. ": " .. tostring(err))
end

local tracebackHandler = type(debug) == "table" and type(debug.traceback) == "function"
    and debug.traceback or function(err) return tostring(err) end
local okKeys, errKeys = xpcall(loadConfigKeys, tracebackHandler)
if not okKeys then k2ShowBootError("loadConfigKeys", errKeys) end
local okBuild, errBuild = xpcall(buildGui, tracebackHandler)
if not okBuild then
    k2ShowBootError("buildGui", errBuild)
else
    local okState, errState = xpcall(loadConfigState, tracebackHandler)
    if not okState then
        k2ShowBootError("loadConfigState", errState)
    elseif okKeys then
        print("[K2 Duels] Interface loaded successfully (purple auto grab).")
    else
        warn("[K2 Duels] Interface loaded, but configuration could not be fully restored. See K2BootError.")
    end
end
