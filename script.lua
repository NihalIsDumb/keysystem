--[[ =====================================================
     Dexa Hub · MM2 Panel
     Aimbot · Target · Player · Misc · Settings
     ===================================================== ]]

--[[
    ================================================================
    [ SCRIPT INFORMATION ]
    Project: Custom Script
    Author: OYB
    YouTube: https://www.youtube.com/channel/UCAlXXV1Hbvf7WbfXARuVtiQ
    
    [ TERMS AND CONDITIONS ]
    - You ARE allowed to use and modify this script for your own games.
    - You ARE NOT allowed to re-upload, redistribute, or claim 
      ownership of this script.
    - Removing or altering these credits is strictly prohibited.
    
    Copyright (c) 2026 OYB. All rights reserved.
    ================================================================
]]

-- ⚠️ IMPORTANT: Put this code at the VERY TOP of your Main Script (before obfuscating) ⚠️

local ProtectionConfig = {
    -- 🔴 CRITICAL: This MUST exactly match the 'Secret' value in your Key System's Config!
    -- If your Key System has: Secret = "Test"
    -- Then this must also be: SecretKey = "Test"
    SecretKey = "1234",
    
    -- The name of your Hub (shown in the kick message if they try to bypass)
    HubName = "Dexa Hub"
}

-- Anti-Bypass Logic: Checks if the Key System successfully set the global variable
if not _G[ProtectionConfig.SecretKey] then
    local player = game:GetService("Players").LocalPlayer
    if player then
        player:Kick("\n🛡️ Unauthorized Execution 🛡️\n\nPlease use the official Key System to run " .. ProtectionConfig.HubName)
    end
    return -- Stops the rest of the script from loading!
end

-------------------------------------------------------------------------------
-- 👇 YOUR MAIN SCRIPT CODE STARTS HERE 👇
-------------------------------------------------------------------------------

print(ProtectionConfig.HubName .. " Loaded Successfully!")

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local TeleportService    = game:GetService("TeleportService")
local TweenService       = game:GetService("TweenService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local HttpService        = game:GetService("HttpService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera    = workspace.CurrentCamera

----------------------------------------------------------------------
-- EXECUTOR CLEANUP (re-execution safe)
----------------------------------------------------------------------

if getgenv and getgenv().DexaHub_Instance then
    pcall(function() getgenv().DexaHub_Instance:Destroy() end)
    getgenv().DexaHub_Instance = nil
end

----------------------------------------------------------------------
-- FILE I/O
----------------------------------------------------------------------

local SETTINGS_FILE = "DexaHub_Settings.json"
local HAS_FILEIO = (getfenv().writefile ~= nil)
    and (getfenv().readfile ~= nil)
    and (getfenv().isfile ~= nil)

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------

local State = {
    -- Aim
    Aimbot              = false,
    Aiming              = false,
    OnePressAimingMode  = false,
    AimKey              = Enum.UserInputType.MouseButton2,
    AimKeyName          = "RMB",
    AimbotMode          = "Lock",
    AimbotSmoothness    = 30,
    AimbotPart          = "Head",
    WallCheck           = true,

    -- Aimbot Highlight
    HighlightTarget     = true,
    HighlightFill       = true,
    HighlightFillColor  = Color3.fromRGB(255, 60, 60),
    HighlightOutline    = true,
    HighlightOutlineColor = Color3.fromRGB(255, 255, 255),

    -- Target ESP
    TargetESP           = false,
    TargetESPFill       = true,
    TargetESPFillColor  = Color3.fromRGB(255, 200, 80),
    TargetESPOutline    = true,
    TargetESPOutlineColor = Color3.fromRGB(120, 200, 255),

    -- TriggerBot
    TriggerBot          = false,
    TriggerBotDelay     = 0,
    TriggerBotChance    = 100,

    -- MM2 features
    TouchFling          = false,
    FlingTarget         = false,
    SpectateTarget      = false,
    AntiFling           = false,

    WalkSpeed           = false,
    WalkSpeedValue      = 16,
    JumpPower           = false,
    JumpPowerValue      = 50,

    Chams               = false,
    RoleChams           = true,       -- color by role
    GunCham             = false,
    ESP                 = false,

    SelectedPlayer      = nil,

    -- Nearest target
    NearestTarget       = false,
    NearestRange        = 1000,
    NearestLockMode     = "Lock",  -- "Lock" | "Follow"
    _nearestLocked      = nil,     -- internal: which player we locked onto

    -- Hotkeys
    MinimizeKey         = Enum.KeyCode.LeftControl,
    MinimizeKeyName     = "LeftControl",
    TriggerKey          = Enum.KeyCode.F,
    TriggerKeyName      = "F",

    -- Settings
    AutoSave            = false,
    AutoReExecute       = false,
    AutoRejoin          = false,
    ScriptURL           = "",
}

local espObjects           = {}
local touchFlingThread     = nil
local aimbotConnection     = nil
local triggerbotConnection = nil

local BASE_SENSITIVITY = UserInputService.MouseDeltaSensitivity

local lockStartTime        = nil
local lastLockMs           = 0

local aimbotHighlight      = nil
local aimbotHighlightTarget = nil

-- Forward declarations
local targetSelectButton
local targetListFrame
local targetSearchBox
local notifHolder
local updateVisuals
local resetLockTimer
local clearAimbotHighlight
local refreshMiniNotifier   -- unused placeholder, kept for compatibility

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

local function getCharacter() return player.Character end
local function getHumanoid(c) return c and c:FindFirstChildOfClass("Humanoid") end
local function getRoot(c) return c and c:FindFirstChild("HumanoidRootPart") end
local function getTargetCharacter()
    if not State.SelectedPlayer then return nil end
    return State.SelectedPlayer.Character
end

local function lockSensitivity()
    UserInputService.MouseDeltaSensitivity = 0
end
local function restoreSensitivity()
    UserInputService.MouseDeltaSensitivity = BASE_SENSITIVITY
end

local function setWalkSpeedValue(v)
    State.WalkSpeedValue = v
    if State.WalkSpeed then
        local h = getHumanoid(getCharacter())
        if h then h.WalkSpeed = v end
    end
end
local function setJumpPowerValue(v)
    State.JumpPowerValue = v
    if State.JumpPower then
        local h = getHumanoid(getCharacter())
        if h then h.JumpPower = v end
    end
end

----------------------------------------------------------------------
-- SETTINGS SAVE / LOAD
----------------------------------------------------------------------

local SAVE_KEYS = {
    "Chams", "RoleChams", "GunCham", "ESP",
    "AimbotMode", "AimbotPart", "AimbotSmoothness",
    "WallCheck", "OnePressAimingMode", "HighlightTarget",
    "HighlightFill", "HighlightOutline",
    "TargetESP", "TargetESPFill", "TargetESPOutline",
    "NearestTarget", "NearestRange", "NearestLockMode",
    "TriggerBotDelay", "TriggerBotChance",
    "WalkSpeedValue", "JumpPowerValue",
    "ScriptURL",
    "MinimizeKeyName", "TriggerKeyName",
    "AimKeyName",
}

local COLOR_SAVE_KEYS = {
    "HighlightFillColor", "HighlightOutlineColor",
    "TargetESPFillColor", "TargetESPOutlineColor",
}

local function colorToTable(c)
    return {
        R = math.floor(c.R * 255 + 0.5),
        G = math.floor(c.G * 255 + 0.5),
        B = math.floor(c.B * 255 + 0.5),
    }
end
local function tableToColor(t)
    return Color3.fromRGB(t.R or 255, t.G or 255, t.B or 255)
end

local function buildSettingsData()
    local data = {}
    for _, k in ipairs(SAVE_KEYS) do data[k] = State[k] end
    for _, k in ipairs(COLOR_SAVE_KEYS) do data[k] = colorToTable(State[k]) end
    return data
end

local function applySettingsData(data)
    for _, k in ipairs(SAVE_KEYS) do
        if data[k] ~= nil then State[k] = data[k] end
    end
    for _, k in ipairs(COLOR_SAVE_KEYS) do
        if data[k] then State[k] = tableToColor(data[k]) end
    end
end

local function saveSettingsToFile()
    if not HAS_FILEIO then return false end
    local ok = pcall(function()
        getfenv().writefile(SETTINGS_FILE, HttpService:JSONEncode(buildSettingsData()))
    end)
    return ok
end

local function loadSettingsFromFile()
    if not HAS_FILEIO then return false end
    local ok, exists = pcall(function() return getfenv().isfile(SETTINGS_FILE) end)
    if not ok or not exists then return false end
    local ok2, data = pcall(function()
        return HttpService:JSONDecode(getfenv().readfile(SETTINGS_FILE))
    end)
    if ok2 and data then
        applySettingsData(data)
        return true
    end
    return false
end

local LOADED_FROM_FILE = loadSettingsFromFile()

-- Rebuild Enum items from saved names (JSON can't store EnumItems)
do
    local function enumKeyFromName(name, fallback)
        if type(name) == "string" and Enum.KeyCode[name] then
            return Enum.KeyCode[name]
        end
        return fallback
    end

    -- Aim Key can be a keyboard key OR a mouse button, so handle both
    local function rebuildAimKey(name, fallback)
        if type(name) ~= "string" then return fallback end
        if name == "LMB" then return Enum.UserInputType.MouseButton1 end
        if name == "RMB" then return Enum.UserInputType.MouseButton2 end
        if name == "MMB" then return Enum.UserInputType.MouseButton3 end
        if Enum.KeyCode[name] then return Enum.KeyCode[name] end
        return fallback
    end

    State.MinimizeKey     = enumKeyFromName(State.MinimizeKeyName, Enum.KeyCode.LeftControl)
    State.MinimizeKeyName = State.MinimizeKey.Name

    State.TriggerKey      = enumKeyFromName(State.TriggerKeyName, Enum.KeyCode.F)
    State.TriggerKeyName  = State.TriggerKey.Name

    State.AimKey          = rebuildAimKey(State.AimKeyName, Enum.UserInputType.MouseButton2)
    -- Refresh the name string so the Aim Key box shows the correct thing
    if typeof(State.AimKey) == "EnumItem" and State.AimKey.EnumType == Enum.KeyCode then
        State.AimKeyName = State.AimKey.Name
    elseif State.AimKey == Enum.UserInputType.MouseButton1 then
        State.AimKeyName = "LMB"
    elseif State.AimKey == Enum.UserInputType.MouseButton2 then
        State.AimKeyName = "RMB"
    elseif State.AimKey == Enum.UserInputType.MouseButton3 then
        State.AimKeyName = "MMB"
    end
end

----------------------------------------------------------------------
-- NEAREST TARGET HELPERS
----------------------------------------------------------------------

local function getNearbyPlayers()
    local myRoot = getRoot(getCharacter())
    if not myRoot then return {} end
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local root = getRoot(p.Character)
            local hum  = getHumanoid(p.Character)
            if root and hum and hum.Health > 0 then
                local d = (root.Position - myRoot.Position).Magnitude
                if d <= State.NearestRange then
                    table.insert(list, { player = p, dist = d })
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end

local function pickNearestTarget()
    local nearby = getNearbyPlayers()
    if #nearby == 0 then return nil end
    return nearby[1].player
end

local function distanceToPlayer(p)
    local myRoot = getRoot(getCharacter())
    if not myRoot or not p or not p.Character then return nil end
    local root = getRoot(p.Character)
    if not root then return nil end
    return (root.Position - myRoot.Position).Magnitude
end

local function isTargetValid()
    local sp = State.SelectedPlayer
    if not sp or not sp.Character then return false end
    local hum = getHumanoid(sp.Character)
    if not hum or hum.Health <= 0 then return false end
    if State.NearestTarget then
        local d = distanceToPlayer(sp)
        if d and d > State.NearestRange then return false end
    end
    return true
end

-- Called when NearestTarget toggle is flipped ON
local function acquireNearestNow()
    local nearest = pickNearestTarget()
    if nearest then
        State.SelectedPlayer  = nearest
        State._nearestLocked  = nearest
        if targetSelectButton then
            targetSelectButton.Text = nearest.DisplayName
        end
        if resetLockTimer then resetLockTimer() end
        if clearAimbotHighlight then clearAimbotHighlight() end
        if State.TargetESP and updateVisuals then updateVisuals() end
    end
end

----------------------------------------------------------------------
-- MM2 ROLE DETECTION
----------------------------------------------------------------------

local ROLE_COLOR = {
    Murderer = Color3.fromRGB(255, 60, 60),    -- red
    Sheriff  = Color3.fromRGB(60, 130, 255),   -- blue
    Innocent = Color3.fromRGB(60, 210, 100),   -- green
}

local function hasToolIn(container, toolName)
    if not container then return false end
    local t = container:FindFirstChild(toolName)
    if t and (t:IsA("Tool") or t:IsA("Model")) then return true end
    -- Some MM2 variants prefix the tool name
    for _, c in ipairs(container:GetChildren()) do
        if (c:IsA("Tool") or c:IsA("Model")) and string.find(c.Name, toolName, 1, true) then
            return true
        end
    end
    return false
end

local function getPlayerRole(plr)
    if not plr then return "Innocent" end

    -- 1. Attribute (some MM2 forks)
    local attr = plr:GetAttribute("Role")
    if typeof(attr) == "string" then
        local a = string.lower(attr)
        if string.find(a, "murder") then return "Murderer" end
        if string.find(a, "sher") then return "Sheriff" end
        if string.find(a, "inno") then return "Innocent" end
    end

    -- 2. StringValue named Role on player / character
    for _, c in ipairs({ plr, plr.Character }) do
        if c then
            local rv = c:FindFirstChild("Role") or c:FindFirstChild("role")
            if rv and rv:IsA("StringValue") then
                local v = string.lower(rv.Value)
                if string.find(v, "murder") then return "Murderer" end
                if string.find(v, "sher") then return "Sheriff" end
                if string.find(v, "inno") then return "Innocent" end
            end
        end
    end

    -- 3. Tool-based fallback (works on vanilla MM2)
    local backpack  = plr:FindFirstChild("Backpack")
    local character = plr.Character
    if hasToolIn(character, "Knife") or hasToolIn(backpack, "Knife") then
        return "Murderer"
    end
    if hasToolIn(character, "Gun") or hasToolIn(backpack, "Gun") then
        return "Sheriff"
    end

    return "Innocent"
end

----------------------------------------------------------------------
-- GUN CHAM (dropped gun highlight)
----------------------------------------------------------------------

local gunHighlight      = nil
local gunHighlightTarget = nil

local function clearGunHighlight()
    if gunHighlight and gunHighlight.Parent then
        gunHighlight:Destroy()
    end
    gunHighlight = nil
    gunHighlightTarget = nil
end

local function findDroppedGun()
    -- The dropped gun is a Tool or Model named "Gun" parented somewhere in workspace
    for _, obj in ipairs(workspace:GetChildren()) do
        if (obj:IsA("Tool") or obj:IsA("Model")) and obj.Name == "Gun" then
            return obj
        end
        -- Sometimes it sits one level deeper
        for _, sub in ipairs(obj:GetChildren()) do
            if (sub:IsA("Tool") or sub:IsA("Model")) and sub.Name == "Gun" then
                return sub
            end
        end
    end
    return nil
end

local function updateGunCham()
    if not State.GunCham then
        clearGunHighlight()
        return
    end

    local gun = findDroppedGun()
    if not gun then
        clearGunHighlight()
        return
    end

    if gunHighlightTarget ~= gun or not gunHighlight or not gunHighlight.Parent then
        clearGunHighlight()
        local h = Instance.new("Highlight")
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.FillColor = Color3.fromRGB(120, 210, 255)
        h.OutlineColor = Color3.fromRGB(255, 255, 255)
        h.FillTransparency = 0.3
        h.OutlineTransparency = 0
        h.Parent = gun
        gunHighlight = h
        gunHighlightTarget = gun
    end
end

-- Watch for gun drops / pickups
workspace.DescendantAdded:Connect(function(obj)
    if State.GunCham and obj.Name == "Gun" then
        task.defer(updateGunCham)
    end
end)
workspace.DescendantRemoving:Connect(function(obj)
    if State.GunCham and obj.Name == "Gun" then
        task.defer(updateGunCham)
    end
end)

----------------------------------------------------------------------
-- NOTIFICATIONS
----------------------------------------------------------------------

local function createNotificationHolder(screenGui)
    local holder = Instance.new("Frame")
    holder.Name = "NotifHolder"
    holder.AnchorPoint = Vector2.new(1, 0)
    holder.Size = UDim2.new(0, 320, 0, 500)
    holder.Position = UDim2.new(1, -20, 0, 60)
    holder.BackgroundTransparency = 1
    holder.ZIndex = 100
    holder.Parent = screenGui

    local layout = Instance.new("UIListLayout", holder)
    layout.Padding = UDim.new(0, 8)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.VerticalAlignment = Enum.VerticalAlignment.Top
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Right

    return holder
end

local function notify(holder, title, message, duration)
    if not holder then return end
    duration = duration or 3
    local n = Instance.new("Frame")
    n.Size = UDim2.new(1, 0, 0, 66)
    n.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    n.BackgroundTransparency = 1
    n.BorderSizePixel = 0
    n.LayoutOrder = math.floor(tick() * 1000)
    n.Parent = holder
    Instance.new("UICorner", n).CornerRadius = UDim.new(0, 14)

    local stroke = Instance.new("UIStroke", n)
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Transparency = 0.88
    stroke.Thickness = 1

    local t = Instance.new("TextLabel", n)
    t.Size = UDim2.new(1, -28, 0, 22)
    t.Position = UDim2.new(0, 16, 0, 10)
    t.BackgroundTransparency = 1
    t.Text = title
    t.TextColor3 = Color3.fromRGB(245, 245, 250)
    t.TextTransparency = 1
    t.Font = Enum.Font.GothamBold
    t.TextSize = 13
    t.TextXAlignment = Enum.TextXAlignment.Left

    local m = Instance.new("TextLabel", n)
    m.Size = UDim2.new(1, -28, 0, 30)
    m.Position = UDim2.new(0, 16, 0, 32)
    m.BackgroundTransparency = 1
    m.Text = message
    m.TextColor3 = Color3.fromRGB(155, 158, 168)
    m.TextTransparency = 1
    m.Font = Enum.Font.Gotham
    m.TextSize = 11
    m.TextXAlignment = Enum.TextXAlignment.Left
    m.TextYAlignment = Enum.TextYAlignment.Top
    m.TextWrapped = true

    TweenService:Create(n, TweenInfo.new(0.22), { BackgroundTransparency = 0.08 }):Play()
    TweenService:Create(t, TweenInfo.new(0.22), { TextTransparency = 0 }):Play()
    TweenService:Create(m, TweenInfo.new(0.22), { TextTransparency = 0 }):Play()
    TweenService:Create(stroke, TweenInfo.new(0.22), { Transparency = 0.6 }):Play()

    task.delay(duration, function()
        TweenService:Create(n, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
        TweenService:Create(t, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
        TweenService:Create(m, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
        TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 1 }):Play()
        task.wait(0.3)
        n:Destroy()
    end)
end

----------------------------------------------------------------------
-- SPECTATE
----------------------------------------------------------------------

local function restoreCamera()
    local humanoid = getHumanoid(getCharacter())
    if humanoid and not State.Aimbot and not State.Aiming then
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = humanoid
    end
end

local function spectateTarget()
    if not State.SpectateTarget then restoreCamera(); return end
    local targetHumanoid = getHumanoid(getTargetCharacter())
    if targetHumanoid and targetHumanoid.Health > 0 then
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = targetHumanoid
    else
        restoreCamera()
    end
end

local function setSpectate(enabled)
    State.SpectateTarget = enabled
    if enabled then spectateTarget() else restoreCamera() end
end

----------------------------------------------------------------------
-- AIMBOT
----------------------------------------------------------------------

local function getAimPart(character)
    if not character then return nil end
    if State.AimbotPart == "Head" then
        return character:FindFirstChild("Head")
    end
    return character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("HumanoidRootPart")
end

local function isAimbotActive()
    return State.Aimbot or State.Aiming
end

local function hasLineOfSight(targetCharacter)
    if not State.WallCheck then return true end
    local myChar = getCharacter()
    if not myChar or not targetCharacter then return false end
    local myRoot = getRoot(myChar)
    local targetPart = getAimPart(targetCharacter)
    if not myRoot or not targetPart then return false end

    local origin    = myRoot.Position
    local direction = targetPart.Position - origin

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { myChar, camera }
    params.IgnoreWater = true

    local result = workspace:Raycast(origin, direction, params)
    if result and result.Instance then
        return result.Instance:IsDescendantOf(targetCharacter)
    end
    return true
end

clearAimbotHighlight = function()
    if aimbotHighlight and aimbotHighlight.Parent then
        aimbotHighlight:Destroy()
    end
    aimbotHighlight = nil
    aimbotHighlightTarget = nil
end

local function updateAimbotHighlight(targetChar)
    if not State.HighlightTarget or not isAimbotActive() or not targetChar then
        clearAimbotHighlight()
        return
    end
    if aimbotHighlightTarget ~= targetChar
        or not aimbotHighlight
        or not aimbotHighlight.Parent then
        clearAimbotHighlight()
        local h = Instance.new("Highlight")
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent = targetChar
        aimbotHighlight = h
        aimbotHighlightTarget = targetChar
    end
    aimbotHighlight.FillColor        = State.HighlightFillColor
    aimbotHighlight.FillTransparency = State.HighlightFill and 0.4 or 1
    aimbotHighlight.OutlineColor     = State.HighlightOutlineColor
    aimbotHighlight.OutlineTransparency = State.HighlightOutline and 0 or 1
end

local LOCK_ANGLE_TOLERANCE = 5

local function angleToTarget()
    local targetChar = getTargetCharacter()
    if not targetChar then return nil end
    local part = getAimPart(targetChar)
    if not part then return nil end
    local cam = workspace.CurrentCamera
    local look = cam.CFrame.LookVector
    local dir  = (part.Position - cam.CFrame.Position).Unit
    local dot  = math.clamp(look:Dot(dir), -1, 1)
    return math.deg(math.acos(dot))
end

resetLockTimer = function()
    lockStartTime = tick()
    lastLockMs = 0
end

local function updateLockTimer()
    if not isAimbotActive() or not lockStartTime then return end
    local ang = angleToTarget()
    if ang and ang <= LOCK_ANGLE_TOLERANCE then
        lastLockMs = math.floor((tick() - lockStartTime) * 1000)
        lockStartTime = tick()
    end
end

local function aimbotStep()
    if not isAimbotActive() then
        clearAimbotHighlight()
        return
    end

    local targetChar = getTargetCharacter()
    if not targetChar or not targetChar.Parent then
        clearAimbotHighlight()
        return
    end

    local humanoid = getHumanoid(targetChar)
    if humanoid and humanoid.Health <= 0 then
        clearAimbotHighlight()
        return
    end

    if not hasLineOfSight(targetChar) then
        clearAimbotHighlight()
        -- Target is behind a wall → give the user camera control back
        if State.AimbotMode == "Lock" then
            restoreSensitivity()
        end
        return
    end

    local part = getAimPart(targetChar)
    if not part or not part.Parent then
        clearAimbotHighlight()
        return
    end

    -- We can see the target → re-lock sensitivity in Lock mode
    if State.AimbotMode == "Lock" then
        lockSensitivity()
    end

    updateAimbotHighlight(targetChar)

    local cam = workspace.CurrentCamera
    local goal = CFrame.new(cam.CFrame.Position, part.Position)

    if State.AimbotMode == "Lock" then
        cam.CFrame = goal
    else
        local alpha = math.max(0.02, 0.25 * (1 - State.AimbotSmoothness / 100))
        cam.CFrame = cam.CFrame:Lerp(goal, alpha)
    end

    updateLockTimer()
end

local function applySensitivityForMode()
    if not (State.Aimbot or State.Aiming) then return end
    if State.AimbotMode == "Lock" then
        lockSensitivity()
    else
        restoreSensitivity()
    end
end

local function ensureAimbotLoop()
    if not aimbotConnection then
        aimbotConnection = RunService.RenderStepped:Connect(aimbotStep)
    end
end

local function stopAimbotLoop()
    if aimbotConnection then
        aimbotConnection:Disconnect()
        aimbotConnection = nil
    end
end

local function setAimbotEnabled(enabled)
    State.Aimbot = enabled
    State.Aiming = enabled

    if enabled then
        -- Re-acquire nearest target on enable if Nearest is on
        if State.NearestTarget then
            local nearest = pickNearestTarget()
            if nearest then
                State.SelectedPlayer = nearest
                State._nearestLocked = nearest
                if targetSelectButton then
                    targetSelectButton.Text = nearest.DisplayName
                end
            end
        end
        applySensitivityForMode()
        resetLockTimer()
        ensureAimbotLoop()
    else
        stopAimbotLoop()
        restoreSensitivity()
        clearAimbotHighlight()
        State._nearestLocked = nil
    end
end

----------------------------------------------------------------------
-- NEAREST TARGET AUTO-LOOP
--   - "Lock"   : keep the one we locked onto at toggle time
--   - "Follow" : always switch to the closest
----------------------------------------------------------------------

task.spawn(function()
    while task.wait(0.4) do
        if State.NearestTarget and State.Aimbot then
            if State.NearestLockMode == "Follow" then
                local nearest = pickNearestTarget()
                if nearest and nearest ~= State.SelectedPlayer then
                    State.SelectedPlayer = nearest
                    State._nearestLocked = nearest
                    if targetSelectButton then
                        targetSelectButton.Text = nearest.DisplayName
                    end
                    resetLockTimer()
                    clearAimbotHighlight()
                    if State.TargetESP and updateVisuals then updateVisuals() end
                elseif not nearest and State.SelectedPlayer then
                    State.SelectedPlayer = nil
                    if targetSelectButton then targetSelectButton.Text = "Target" end
                    clearAimbotHighlight()
                end
            else
                -- Lock mode: keep locked target until it becomes invalid
                if not isTargetValid() then
                    local nearest = pickNearestTarget()
                    State.SelectedPlayer = nearest
                    State._nearestLocked = nearest
                    if targetSelectButton then
                        targetSelectButton.Text = nearest and nearest.DisplayName or "Target"
                    end
                    resetLockTimer()
                    clearAimbotHighlight()
                    if State.TargetESP and updateVisuals then updateVisuals() end
                end
            end
        end
    end
end)

----------------------------------------------------------------------
-- TRIGGERBOT
----------------------------------------------------------------------

local function getPlayerFromPart(part)
    if not part then return nil end
    local char = part:FindFirstAncestorWhichIsA("Model")
    if not char then return nil end
    local plr = Players:GetPlayerFromCharacter(char)
    if plr and plr ~= player then return plr, char end
    return nil
end

local function fireClick()
    if getfenv().mouse1click then
        getfenv().mouse1click()
        return true
    end
    local VIM = game:GetService("VirtualInputManager")
    if VIM then
        local ok = pcall(function()
            VIM:SendMouseButtonEvent(0, 0, 0, true,  game, 1)
            VIM:SendMouseButtonEvent(0, 0, 0, false, game, 1)
        end)
        if ok then return true end
    end
    return false
end

local function triggerbotStep()
    if not State.TriggerBot then return end
    if UserInputService:GetFocusedTextBox() then return end

    local mouseTarget = player:GetMouse().Target
    if not mouseTarget then return end

    local plr, char = getPlayerFromPart(mouseTarget)
    if not plr then return end

    if State.SelectedPlayer and plr ~= State.SelectedPlayer then return end

    local humanoid = getHumanoid(char)
    if not humanoid or humanoid.Health <= 0 then return end

    if math.random(1, 100) > State.TriggerBotChance then return end

    if State.TriggerBotDelay > 0 then
        task.wait(State.TriggerBotDelay / 1000)
        if not State.TriggerBot then return end
        if not plr.Character or not getHumanoid(plr.Character) then return end
    end

    fireClick()
end

local function setTriggerBotEnabled(enabled)
    State.TriggerBot = enabled
    if enabled then
        if not triggerbotConnection then
            triggerbotConnection = RunService.RenderStepped:Connect(triggerbotStep)
        end
    else
        if triggerbotConnection then
            triggerbotConnection:Disconnect()
            triggerbotConnection = nil
        end
    end
end

----------------------------------------------------------------------
-- TOUCH FLING
----------------------------------------------------------------------

local function runTouchFling()
    local movel = 0.1
    while State.TouchFling do
        RunService.Heartbeat:Wait()
        local root = getRoot(getCharacter())
        if root and root.Parent then
            local saved = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = saved * 10000 + Vector3.new(0, 10000, 0)
            RunService.RenderStepped:Wait()
            if not State.TouchFling then root.AssemblyLinearVelocity = Vector3.zero; break end
            root.AssemblyLinearVelocity = saved
            RunService.Stepped:Wait()
            if not State.TouchFling then root.AssemblyLinearVelocity = Vector3.zero; break end
            root.AssemblyLinearVelocity = saved + Vector3.new(0, movel, 0)
            movel = -movel
        end
    end
    local root = getRoot(getCharacter())
    if root then root.AssemblyLinearVelocity = Vector3.zero end
end

local function setTouchFling(enabled)
    State.TouchFling = enabled
    if enabled then
        touchFlingThread = task.spawn(runTouchFling)
    else
        task.spawn(function()
            task.wait(0.1)
            local root = getRoot(getCharacter())
            if root then
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
        end)
    end
end

----------------------------------------------------------------------
-- TARGET FLING
----------------------------------------------------------------------

local function flingCharacter(targetCharacter)
    if not targetCharacter then return end
    local targetRoot = getRoot(targetCharacter)
    local myRoot = getRoot(getCharacter())
    if not targetRoot or not myRoot then return end

    local savedCFrame = myRoot.CFrame
    local bav = Instance.new("BodyAngularVelocity")
    bav.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bav.AngularVelocity = Vector3.new(0, 10000, 0)
    bav.Parent = myRoot

    local startTime = tick()
    local connection
    connection = RunService.Heartbeat:Connect(function()
        if tick() - startTime > 1.5
            or not targetRoot or not targetRoot.Parent
            or not myRoot or not myRoot.Parent then
            if connection then connection:Disconnect() end
            if bav then bav:Destroy() end
            if myRoot and myRoot.Parent then
                myRoot.AssemblyLinearVelocity = Vector3.zero
                myRoot.AssemblyAngularVelocity = Vector3.zero
                myRoot.CFrame = savedCFrame
            end
            return
        end
        myRoot.CFrame = targetRoot.CFrame *
            CFrame.new(math.random(-1, 1), 0, math.random(-1, 1))
        myRoot.AssemblyLinearVelocity = Vector3.new(10000, 10000, 10000)
    end)
end

----------------------------------------------------------------------
-- TELEPORT TO LOBBY
----------------------------------------------------------------------

local function findRegularLobby()
    local direct = workspace:FindFirstChild("RegularLobby")
    if direct then return direct end
    local found = workspace:FindFirstChild("RegularLobby", true)
    if found then return found end
    return ReplicatedStorage:FindFirstChild("RegularLobby", true)
end

local function getPositionFromObject(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj.CFrame + Vector3.new(0, 5, 0) end
    if obj:IsA("Model") or obj:IsA("Folder") then
        local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
        if part then return part.CFrame + Vector3.new(0, 5, 0) end
    end
    return nil
end

local function teleportToLobby()
    local myRoot = getRoot(getCharacter())
    if not myRoot then return false end
    local lobby = findRegularLobby()
    if not lobby then return false end
    local pos = getPositionFromObject(lobby)
    if pos then myRoot.CFrame = pos; return true end
    return false
end

----------------------------------------------------------------------
-- PLAYER SETTINGS LOOP
----------------------------------------------------------------------

RunService.Stepped:Connect(function()
    local character = getCharacter()
    local humanoid = getHumanoid(character)
    if humanoid then
        if State.WalkSpeed then humanoid.WalkSpeed = State.WalkSpeedValue end
        if State.JumpPower then humanoid.JumpPower = State.JumpPowerValue end
    end
    if State.AntiFling and character then
        for _, object in ipairs(character:GetDescendants()) do
            if object:IsA("BasePart") then object.CanCollide = false end
        end
    end
end)

----------------------------------------------------------------------
-- VISUALS
----------------------------------------------------------------------

local function clearVisuals()
    for _, object in ipairs(espObjects) do
        if object and object.Parent then object:Destroy() end
    end
    table.clear(espObjects)
end

updateVisuals = function()
    clearVisuals()
    if not State.Chams and not State.RoleChams and not State.ESP and not State.TargetESP then
        updateGunCham()
        return
    end

    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= player then
            local character = targetPlayer.Character
            if character then
                -- Chams: Player Chams (flat red) OR Role Chams (red/blue/green)
                if State.Chams or State.RoleChams then
                    local highlight = Instance.new("Highlight")
                    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

                    if State.RoleChams then
                        local role = getPlayerRole(targetPlayer)
                        highlight.FillColor    = ROLE_COLOR[role] or ROLE_COLOR.Innocent
                        highlight.OutlineColor = Color3.new(1, 1, 1)
                        highlight.FillTransparency    = 0.4
                        highlight.OutlineTransparency = 0
                    else
                        highlight.FillColor    = Color3.fromRGB(255, 75, 75)
                        highlight.OutlineColor = Color3.new(1, 1, 1)
                    end

                    highlight.Parent = character
                    table.insert(espObjects, highlight)
                end

                -- Name ESP
                if State.ESP then
                    local head = character:FindFirstChild("Head")
                    if head then
                        local billboard = Instance.new("BillboardGui")
                        billboard.Size = UDim2.new(0, 100, 0, 40)
                        billboard.StudsOffset = Vector3.new(0, 2, 0)
                        billboard.AlwaysOnTop = true
                        billboard.Parent = head

                        local label = Instance.new("TextLabel")
                        label.Size = UDim2.new(1, 0, 1, 0)
                        label.BackgroundTransparency = 1
                        label.Text = targetPlayer.DisplayName
                        label.TextColor3 = Color3.new(1, 1, 1)
                        label.TextStrokeTransparency = 0.5
                        label.Font = Enum.Font.GothamBold
                        label.TextSize = 12
                        label.Parent = billboard
                        table.insert(espObjects, billboard)
                    end
                end

                -- Target ESP
                if State.TargetESP and targetPlayer == State.SelectedPlayer then
                    local highlight = Instance.new("Highlight")
                    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    highlight.FillColor   = State.TargetESPFillColor
                    highlight.FillTransparency   = State.TargetESPFill and 0.5 or 1
                    highlight.OutlineColor       = State.TargetESPOutlineColor
                    highlight.OutlineTransparency = State.TargetESPOutline and 0 or 1
                    highlight.Parent = character
                    table.insert(espObjects, highlight)

                    local head = character:FindFirstChild("Head")
                    if head then
                        local billboard = Instance.new("BillboardGui")
                        billboard.Size = UDim2.new(0, 160, 0, 44)
                        billboard.StudsOffset = Vector3.new(0, 3, 0)
                        billboard.AlwaysOnTop = true
                        billboard.Parent = head

                        local label = Instance.new("TextLabel")
                        label.Size = UDim2.new(1, 0, 1, 0)
                        label.BackgroundTransparency = 1
                        label.Text = "🎯 " .. targetPlayer.DisplayName
                        label.TextColor3 = State.TargetESPFillColor
                        label.TextStrokeTransparency = 0.3
                        label.Font = Enum.Font.GothamBold
                        label.TextSize = 14
                        label.Parent = billboard
                        table.insert(espObjects, billboard)
                    end
                end
            end
        end
    end

    updateGunCham()
end

local function refreshTargetESP()
    if State.TargetESP then updateVisuals() end
end
----------------------------------------------------------------------
-- TARGET LIST
----------------------------------------------------------------------

local function clearTargetList()
    if not targetListFrame then return end
    for _, child in ipairs(targetListFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
end

local function refreshTargets()
    clearTargetList()
    if not targetListFrame then return end

    local searchText = ""
    if targetSearchBox and targetSearchBox.Text ~= "Search..." then
        searchText = string.lower(targetSearchBox.Text)
    end

    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= player then
            local matches = true
            if searchText ~= "" then
                local n = string.lower(targetPlayer.Name)
                local d = string.lower(targetPlayer.DisplayName)
                matches = string.find(n, searchText, 1, true)
                    or string.find(d, searchText, 1, true)
            end

            if matches then
                local button = Instance.new("TextButton")
                button.Size = UDim2.new(1, -8, 0, 30)
                button.Position = UDim2.new(0, 4, 0, 0)
                button.BackgroundColor3 = Color3.fromRGB(40, 44, 55)
                button.BackgroundTransparency = 1
                button.Text = "    @" .. targetPlayer.Name ..
                    " (" .. targetPlayer.DisplayName .. ")"
                button.TextColor3 = Color3.fromRGB(210, 210, 218)
                button.Font = Enum.Font.Gotham
                button.TextSize = 12
                button.TextXAlignment = Enum.TextXAlignment.Left
                button.AutoButtonColor = false
                button.Parent = targetListFrame
                Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)

                button.MouseEnter:Connect(function()
                    TweenService:Create(button, TweenInfo.new(0.15),
                        { BackgroundTransparency = 0.6 }):Play()
                end)
                button.MouseLeave:Connect(function()
                    TweenService:Create(button, TweenInfo.new(0.15),
                        { BackgroundTransparency = 1 }):Play()
                end)

                button.MouseButton1Click:Connect(function()
                    State.SelectedPlayer = targetPlayer
                    State._nearestLocked = targetPlayer
                    targetSelectButton.Text = targetPlayer.DisplayName
                    targetListFrame.Visible = false
                    targetSearchBox.Text = "Search..."
                    targetSearchBox.TextColor3 = Color3.fromRGB(140, 145, 160)
                    if State.SpectateTarget then spectateTarget() end
                    resetLockTimer()
                    clearAimbotHighlight()
                    refreshTargetESP()
                    if notifHolder then
                        notify(notifHolder, "Dexa Hub",
                            "Target: @" .. targetPlayer.Name, 2)
                    end
                end)
            end
        end
    end

    local layout = targetListFrame:FindFirstChildOfClass("UIListLayout")
    if layout then
        targetListFrame.CanvasSize =
            UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
    end
end

----------------------------------------------------------------------
-- CYCLE TARGET (P)
----------------------------------------------------------------------

local function cycleTarget()
    if State.NearestTarget then
        local nearby = getNearbyPlayers()
        if #nearby == 0 then
            if notifHolder then
                notify(notifHolder, "Dexa Hub", "No nearby players in range.", 2)
            end
            return
        end

        local idx = 0
        for i, entry in ipairs(nearby) do
            if entry.player == State.SelectedPlayer then idx = i; break end
        end

        local nextIdx = (idx % #nearby) + 1
        State.SelectedPlayer = nearby[nextIdx].player
        State._nearestLocked = nearby[nextIdx].player
        if targetSelectButton then
            targetSelectButton.Text = nearby[nextIdx].player.DisplayName
        end

        resetLockTimer()
        clearAimbotHighlight()
        refreshTargetESP()
        if notifHolder then
            notify(notifHolder, "Dexa Hub",
                string.format("Target: @%s (%.0f studs)",
                    nearby[nextIdx].player.Name, nearby[nextIdx].dist), 2)
        end
    else
        local list = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player then table.insert(list, p) end
        end
        if #list == 0 then return end

        local idx = 0
        for i, p in ipairs(list) do
            if p == State.SelectedPlayer then idx = i; break end
        end

        local nextIdx = (idx % #list) + 1
        State.SelectedPlayer = list[nextIdx]
        State._nearestLocked = list[nextIdx]
        if targetSelectButton then
            targetSelectButton.Text = list[nextIdx].DisplayName
        end

        resetLockTimer()
        clearAimbotHighlight()
        refreshTargetESP()
        if notifHolder then
            notify(notifHolder, "Dexa Hub", "Target: @" .. list[nextIdx].Name, 2)
        end
    end
end

----------------------------------------------------------------------
-- PLAYER JOIN / LEAVE
----------------------------------------------------------------------

----------------------------------------------------------------------
-- PLAYER JOIN / LEAVE / RESPAWN HOOKS
----------------------------------------------------------------------

local function refreshAllVisuals()
    task.defer(function()
        if State.Chams or State.ESP or State.TargetESP then
            updateVisuals()
        end
    end)
end

local function hookCharacter(p)
    p.CharacterAdded:Connect(function(char)
        -- Wait for the character parts to load in
        task.wait(0.35)
        refreshAllVisuals()
    end)
    p.CharacterRemoving:Connect(function()
        -- Rebuild so we drop the old highlight
        task.defer(refreshAllVisuals)
    end)
    if p.Character then
        task.defer(refreshAllVisuals)
    end
end

-- Hook everyone currently in the game
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= player then
        hookCharacter(p)
    end
end

-- And every new player
Players.PlayerAdded:Connect(function(p)
    hookCharacter(p)
    task.wait(0.6)
    refreshAllVisuals()
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
    if State.SelectedPlayer == leavingPlayer then
        State.SelectedPlayer = nil
        State._nearestLocked = nil
        if targetSelectButton then targetSelectButton.Text = "Target" end
        State.SpectateTarget = false
        restoreCamera()
        clearAimbotHighlight()
    end
    refreshAllVisuals()
end)

-- Local player respawn → rebuild everything
player.CharacterAdded:Connect(function()
    task.wait(0.5)
    refreshAllVisuals()
    updateGunCham()
end)

----------------------------------------------------------------------
-- THEME
----------------------------------------------------------------------

local COLOR = {
    bg        = Color3.fromRGB(15, 15, 20),
    sidebar   = Color3.fromRGB(18, 19, 26),
    rowBg     = Color3.fromRGB(30, 32, 42),
    text      = Color3.fromRGB(235, 235, 240),
    textDim   = Color3.fromRGB(140, 145, 160),
    stroke    = Color3.fromRGB(255, 255, 255),
    divider   = Color3.fromRGB(48, 50, 62),
    toggleOff = Color3.fromRGB(60, 62, 72),
    toggleOn  = Color3.fromRGB(115, 118, 128),
    knobOff   = Color3.fromRGB(160, 162, 170),
    knobOn    = Color3.fromRGB(255, 255, 255),
    inputBg   = Color3.fromRGB(38, 40, 50),
}

----------------------------------------------------------------------
-- GUI ROOT
----------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DexaHub"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 2147483647
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

if getgenv then getgenv().DexaHub_Instance = screenGui end

notifHolder = createNotificationHolder(screenGui)

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 620, 0, 420)
mainFrame.Position = UDim2.new(0.5, -310, 0.5, -210)
mainFrame.BackgroundColor3 = COLOR.bg
mainFrame.BackgroundTransparency = 0.15
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.ClipsDescendants = true
mainFrame.ZIndex = 1
mainFrame.Parent = screenGui

Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 16)

local mainStroke = Instance.new("UIStroke", mainFrame)
mainStroke.Color = COLOR.stroke
mainStroke.Transparency = 0.82
mainStroke.Thickness = 1.4

local strokeGradient = Instance.new("UIGradient", mainStroke)
strokeGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0.0, Color3.fromRGB(160, 140, 235)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 120, 210)),
    ColorSequenceKeypoint.new(1.0, Color3.fromRGB(225, 140, 190)),
})
strokeGradient.Rotation = 45

local mainGradient = Instance.new("UIGradient", mainFrame)
mainGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(32, 34, 46)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 12, 18)),
})
mainGradient.Rotation = 45

----------------------------------------------------------------------
-- SIDEBAR
----------------------------------------------------------------------

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 155, 1, 0)
sidebar.BackgroundColor3 = COLOR.sidebar
sidebar.BackgroundTransparency = 0.25
sidebar.BorderSizePixel = 0
sidebar.ZIndex = 2
sidebar.Parent = mainFrame
Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, 16)

local sidebarCover = Instance.new("Frame")
sidebarCover.Size = UDim2.new(0, 16, 1, 0)
sidebarCover.Position = UDim2.new(1, -16, 0, 0)
sidebarCover.BackgroundColor3 = COLOR.sidebar
sidebarCover.BackgroundTransparency = 0.25
sidebarCover.BorderSizePixel = 0
sidebarCover.ZIndex = 2
sidebarCover.Parent = sidebar

local sidebarGradient = Instance.new("UIGradient", sidebar)
sidebarGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 30, 42)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 14, 20)),
})
sidebarGradient.Rotation = 90

local sidebarStroke = Instance.new("UIStroke", sidebar)
sidebarStroke.Color = Color3.fromRGB(150, 130, 220)
sidebarStroke.Transparency = 0.88
sidebarStroke.Thickness = 1

local dotsFrame = Instance.new("Frame")
dotsFrame.Size = UDim2.new(0, 60, 0, 20)
dotsFrame.Position = UDim2.new(0, 12, 0, 10)
dotsFrame.BackgroundTransparency = 1
dotsFrame.ZIndex = 3
dotsFrame.Parent = sidebar

for i, c in ipairs({
    Color3.fromRGB(255, 95, 87),
    Color3.fromRGB(255, 189, 46),
    Color3.fromRGB(40, 200, 64),
}) do
    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 9, 0, 9)
    dot.Position = UDim2.new(0, (i - 1) * 14, 0.5, -4)
    dot.BackgroundColor3 = c
    dot.BorderSizePixel = 0
    dot.ZIndex = 3
    dot.Parent = dotsFrame
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
end

local brand = Instance.new("TextLabel")
brand.Size = UDim2.new(1, -20, 0, 22)
brand.Position = UDim2.new(0, 12, 0, 34)
brand.BackgroundTransparency = 1
brand.Text = "Dexa Hub"
brand.TextColor3 = COLOR.text
brand.Font = Enum.Font.GothamBold
brand.TextSize = 15
brand.TextXAlignment = Enum.TextXAlignment.Left
brand.ZIndex = 3
brand.Parent = sidebar

local brandSub = Instance.new("TextLabel")
brandSub.Size = UDim2.new(1, -20, 0, 14)
brandSub.Position = UDim2.new(0, 12, 0, 56)
brandSub.BackgroundTransparency = 1
brandSub.Text = "MM2 Panel"
brandSub.TextColor3 = COLOR.textDim
brandSub.Font = Enum.Font.Gotham
brandSub.TextSize = 9
brandSub.TextXAlignment = Enum.TextXAlignment.Left
brandSub.ZIndex = 3
brandSub.Parent = sidebar

local brandDivider = Instance.new("Frame")
brandDivider.Size = UDim2.new(1, -24, 0, 1)
brandDivider.Position = UDim2.new(0, 12, 0, 78)
brandDivider.BackgroundColor3 = COLOR.divider
brandDivider.BorderSizePixel = 0
brandDivider.ZIndex = 3
brandDivider.Parent = sidebar

----------------------------------------------------------------------
-- CONTENT AREA
----------------------------------------------------------------------

local contentArea = Instance.new("Frame")
contentArea.Size = UDim2.new(1, -155, 1, 0)
contentArea.Position = UDim2.new(0, 155, 0, 0)
contentArea.BackgroundTransparency = 1
contentArea.ZIndex = 2
contentArea.Parent = mainFrame

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 45)
header.BackgroundTransparency = 1
header.ZIndex = 3
header.Parent = contentArea

local headerLabel = Instance.new("TextLabel")
headerLabel.Size = UDim2.new(1, -60, 1, 0)
headerLabel.Position = UDim2.new(0, 20, 0, 0)
headerLabel.BackgroundTransparency = 1
headerLabel.Text = "Aimbot"
headerLabel.TextColor3 = COLOR.text
headerLabel.Font = Enum.Font.GothamMedium
headerLabel.TextSize = 13
headerLabel.TextXAlignment = Enum.TextXAlignment.Left
headerLabel.ZIndex = 3
headerLabel.Parent = header

local moveIcon = Instance.new("TextLabel")
moveIcon.Size = UDim2.new(0, 22, 0, 22)
moveIcon.Position = UDim2.new(1, -34, 0.5, -11)
moveIcon.BackgroundTransparency = 1
moveIcon.Text = "✥"
moveIcon.TextColor3 = COLOR.textDim
moveIcon.Font = Enum.Font.GothamBold
moveIcon.TextSize = 16
moveIcon.ZIndex = 3
moveIcon.Parent = header

local headerDivider = Instance.new("Frame")
headerDivider.Size = UDim2.new(1, 0, 0, 1)
headerDivider.Position = UDim2.new(0, 0, 1, -1)
headerDivider.BackgroundColor3 = COLOR.divider
headerDivider.BorderSizePixel = 0
headerDivider.ZIndex = 3
headerDivider.Parent = header

local panelArea = Instance.new("Frame")
panelArea.Size = UDim2.new(1, -24, 1, -60)
panelArea.Position = UDim2.new(0, 12, 0, 50)
panelArea.BackgroundTransparency = 1
panelArea.ZIndex = 3
panelArea.Parent = contentArea

----------------------------------------------------------------------
-- TABS
----------------------------------------------------------------------

local tabData = {}
local tabPanels = {}

local function createTab(name, icon, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -16, 0, 34)
    btn.Position = UDim2.new(0, 8, 0, 92 + (order - 1) * 38)
    btn.BackgroundColor3 = Color3.fromRGB(40, 42, 55)
    btn.BackgroundTransparency = 1
    btn.Text = "   " .. icon .. "    " .. name
    btn.TextColor3 = COLOR.textDim
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 12
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.AutoButtonColor = false
    btn.ZIndex = 3
    btn.Parent = sidebar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

    local indicator = Instance.new("Frame")
    indicator.Size = UDim2.new(0, 3, 0, 16)
    indicator.Position = UDim2.new(0, -2, 0.5, -8)
    indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    indicator.BorderSizePixel = 0
    indicator.Visible = false
    indicator.ZIndex = 4
    indicator.Parent = btn
    Instance.new("UICorner", indicator).CornerRadius = UDim.new(1, 0)

    local panel = Instance.new("ScrollingFrame")
    panel.Size = UDim2.new(1, 0, 1, 0)
    panel.BackgroundTransparency = 1
    panel.BorderSizePixel = 0
    panel.ScrollBarThickness = 3
    panel.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 130)
    panel.CanvasSize = UDim2.new(0, 0, 0, 0)
    panel.Visible = false
    panel.ZIndex = 3
    panel.Parent = panelArea

    local layout = Instance.new("UIListLayout", panel)
    layout.Padding = UDim.new(0, 6)

    btn.MouseButton1Click:Connect(function()
        for _, p in pairs(tabPanels) do p.Visible = false end
        for _, d in pairs(tabData) do
            d.button.BackgroundTransparency = 1
            d.button.TextColor3 = COLOR.textDim
            d.indicator.Visible = false
        end
        panel.Visible = true
        btn.BackgroundTransparency = 0.4
        btn.TextColor3 = COLOR.text
        indicator.Visible = true
        headerLabel.Text = name
    end)

    table.insert(tabData, { button = btn, indicator = indicator })
    tabPanels[name] = panel
    return panel
end

----------------------------------------------------------------------
-- COMPONENTS
----------------------------------------------------------------------

local function addDivider(panel)
    local div = Instance.new("Frame")
    div.Size = UDim2.new(1, -20, 0, 1)
    div.BackgroundColor3 = COLOR.divider
    div.BorderSizePixel = 0
    div.ZIndex = 4
    div.Parent = panel
end

local function addSection(panel, text)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -6, 0, 22)
    lbl.BackgroundTransparency = 1
    lbl.Text = string.upper(text)
    lbl.TextColor3 = Color3.fromRGB(120, 125, 140)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.ZIndex = 4
    lbl.Parent = panel
    local pad = Instance.new("UIPadding", lbl)
    pad.PaddingLeft = UDim.new(0, 8)
end

local function addSubText(panel, text)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -12, 0, 16)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = Color3.fromRGB(120, 125, 140)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextWrapped = true
    lbl.ZIndex = 4
    lbl.Parent = panel
    local pad = Instance.new("UIPadding", lbl)
    pad.PaddingLeft = UDim.new(0, 12)
    return lbl
end

local function addToggle(panel, text, callback, default)
    default = default or false
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -6, 0, 38)
    row.BackgroundTransparency = 1
    row.ZIndex = 4
    row.Parent = panel

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = COLOR.text
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 4
    label.Parent = row

    local track = Instance.new("TextButton")
    track.Size = UDim2.new(0, 40, 0, 22)
    track.Position = UDim2.new(1, -52, 0.5, -11)
    track.BackgroundColor3 = COLOR.toggleOff
    track.Text = ""
    track.AutoButtonColor = false
    track.ZIndex = 4
    track.Parent = row
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = UDim2.new(0, 2, 0.5, -9)
    knob.BackgroundColor3 = COLOR.knobOff
    knob.BorderSizePixel = 0
    knob.ZIndex = 5
    knob.Parent = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local enabled = default
    local function setState(on, skipCallback)
        enabled = on
        TweenService:Create(knob, TweenInfo.new(0.18), {
            Position = on and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9),
            BackgroundColor3 = on and COLOR.knobOn or COLOR.knobOff,
        }):Play()
        TweenService:Create(track, TweenInfo.new(0.18), {
            BackgroundColor3 = on and COLOR.toggleOn or COLOR.toggleOff,
        }):Play()
        if not skipCallback then callback(on) end
    end
    setState(default, true)
    track.MouseButton1Click:Connect(function() setState(not enabled) end)

    return { setState = setState, getState = function() return enabled end }
end

local function addArrowButton(panel, text, callback)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, -6, 0, 38)
    row.BackgroundTransparency = 1
    row.Text = ""
    row.AutoButtonColor = false
    row.ZIndex = 4
    row.Parent = panel

    local label = Instance.new("TextLabel", row)
    label.Size = UDim2.new(0.8, 0, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = COLOR.text
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 4

    local arrow = Instance.new("TextLabel", row)
    arrow.Size = UDim2.new(0, 20, 1, 0)
    arrow.Position = UDim2.new(1, -30, 0, 0)
    arrow.BackgroundTransparency = 1
    arrow.Text = "›"
    arrow.TextColor3 = COLOR.textDim
    arrow.Font = Enum.Font.GothamBold
    arrow.TextSize = 20
    arrow.ZIndex = 4

    row.MouseEnter:Connect(function()
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        arrow.TextColor3 = Color3.fromRGB(255, 255, 255)
    end)
    row.MouseLeave:Connect(function()
        label.TextColor3 = COLOR.text
        arrow.TextColor3 = COLOR.textDim
    end)
    row.MouseButton1Click:Connect(callback)
    return row
end

local function addSegmented(panel, text, options, default, callback)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -6, 0, 38)
    row.BackgroundTransparency = 1
    row.ZIndex = 4
    row.Parent = panel

    local label = Instance.new("TextLabel", row)
    label.Size = UDim2.new(0.5, 0, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = COLOR.text
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 4

    local container = Instance.new("Frame", row)
    container.Size = UDim2.new(0, 140, 0, 24)
    container.Position = UDim2.new(1, -152, 0.5, -12)
    container.BackgroundColor3 = COLOR.inputBg
    container.BorderSizePixel = 0
    container.ZIndex = 4
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 6)

    local cStroke = Instance.new("UIStroke", container)
    cStroke.Color = COLOR.stroke
    cStroke.Transparency = 0.9

    local buttons = {}
    local function setValue(val, silent)
        for _, b in ipairs(buttons) do
            if b.Name == val then
                b.BackgroundTransparency = 0.05
                b.TextColor3 = COLOR.text
            else
                b.BackgroundTransparency = 1
                b.TextColor3 = COLOR.textDim
            end
        end
        if not silent then callback(val) end
    end

    for i, opt in ipairs(options) do
        local b = Instance.new("TextButton", container)
        b.Name = opt
        b.Size = UDim2.new(1 / #options, 0, 1, 0)
        b.Position = UDim2.new((i - 1) / #options, 0, 0, 0)
        b.BackgroundColor3 = Color3.fromRGB(70, 74, 88)
        b.BackgroundTransparency = (opt == default) and 0.05 or 1
        b.Text = opt
        b.TextColor3 = (opt == default) and COLOR.text or COLOR.textDim
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 11
        b.AutoButtonColor = false
        b.ZIndex = 5
        b.Parent = container
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        table.insert(buttons, b)

        b.MouseButton1Click:Connect(function()
            setValue(opt)
        end)
    end

    return { setValue = setValue }
end

local function addValueSlider(panel, text, min, max, default, onSlide)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -6, 0, 38)
    row.BackgroundTransparency = 1
    row.ZIndex = 4
    row.Parent = panel

    local label = Instance.new("TextLabel", row)
    label.Size = UDim2.new(0.7, 0, 0, 16)
    label.Position = UDim2.new(0, 12, 0, 2)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = COLOR.text
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 4

    local sliderBg = Instance.new("Frame", row)
    sliderBg.Size = UDim2.new(1, -120, 0, 4)
    sliderBg.Position = UDim2.new(0, 12, 1, -10)
    sliderBg.BackgroundColor3 = Color3.fromRGB(55, 58, 70)
    sliderBg.BorderSizePixel = 0
    sliderBg.ZIndex = 4
    Instance.new("UICorner", sliderBg).CornerRadius = UDim.new(1, 0)

    local rel0 = (default - min) / (max - min)

    local fill = Instance.new("Frame", sliderBg)
    fill.Size = UDim2.new(rel0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    fill.BorderSizePixel = 0
    fill.ZIndex = 5
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame", sliderBg)
    knob.Size = UDim2.new(0, 12, 0, 12)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(rel0, 0, 0.5, 0)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.ZIndex = 5
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local numberBox = Instance.new("TextBox", row)
    numberBox.Size = UDim2.new(0, 60, 0, 24)
    numberBox.Position = UDim2.new(1, -70, 0.5, -12)
    numberBox.BackgroundColor3 = COLOR.inputBg
    numberBox.BackgroundTransparency = 0.15
    numberBox.BorderSizePixel = 0
    numberBox.Text = tostring(default)
    numberBox.TextColor3 = COLOR.text
    numberBox.Font = Enum.Font.Gotham
    numberBox.TextSize = 12
    numberBox.ClearTextOnFocus = false
    numberBox.ZIndex = 6
    numberBox.Parent = row
    Instance.new("UICorner", numberBox).CornerRadius = UDim.new(0, 6)

    local nStroke = Instance.new("UIStroke", numberBox)
    nStroke.Color = COLOR.stroke
    nStroke.Transparency = 0.9

    local currentValue = default
    local function setValue(v, fromInput)
        v = math.clamp(math.floor(v), min, max)
        currentValue = v
        local rel = (v - min) / (max - min)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, 0, 0.5, 0)
        if not fromInput then numberBox.Text = tostring(v) end
        onSlide(v)
    end

    local hit = Instance.new("TextButton", row)
    hit.Size = UDim2.new(1, -120, 0, 26)
    hit.Position = UDim2.new(0, 12, 1, -22)
    hit.BackgroundTransparency = 1
    hit.Text = ""
    hit.AutoButtonColor = false
    hit.ZIndex = 5
    hit.Parent = row

    local dragging = false
    local function updateFromMouse(mouseX)
        local rel = math.clamp(
            (mouseX - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X, 0, 1)
        setValue(min + (max - min) * rel)
    end

    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateFromMouse(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromMouse(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    numberBox.FocusLost:Connect(function()
        local n = tonumber(numberBox.Text)
        if n then
            setValue(n, true)
            numberBox.Text = tostring(currentValue)
        else
            numberBox.Text = tostring(currentValue)
        end
    end)

    return { setValue = setValue, numberBox = numberBox }
end

local function addSlider(panel, text, min, max, default, onToggle, onSlide)
    addToggle(panel, text, onToggle, false)
    addValueSlider(panel, "", min, max, default, onSlide)
end

----------------------------------------------------------------------
-- COLOR PICKER
----------------------------------------------------------------------

local function addColorPicker(panel, text, defaultColor, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -6, 0, 92)
    frame.BackgroundColor3 = Color3.fromRGB(30, 32, 42)
    frame.BackgroundTransparency = 0.55
    frame.BorderSizePixel = 0
    frame.ZIndex = 4
    frame.Parent = panel
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
    local frStroke = Instance.new("UIStroke", frame)
    frStroke.Color = COLOR.stroke
    frStroke.Transparency = 0.92

    local label = Instance.new("TextLabel", frame)
    label.Size = UDim2.new(0.7, 0, 0, 20)
    label.Position = UDim2.new(0, 12, 0, 4)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = COLOR.text
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 5

    local swatch = Instance.new("Frame", frame)
    swatch.Size = UDim2.new(0, 44, 0, 20)
    swatch.Position = UDim2.new(1, -56, 0, 4)
    swatch.BackgroundColor3 = defaultColor
    swatch.BorderSizePixel = 0
    swatch.ZIndex = 5
    Instance.new("UICorner", swatch).CornerRadius = UDim.new(0, 6)
    local swStroke = Instance.new("UIStroke", swatch)
    swStroke.Color = COLOR.stroke
    swStroke.Transparency = 0.6

    local r = math.round(defaultColor.R * 255)
    local g = math.round(defaultColor.G * 255)
    local b = math.round(defaultColor.B * 255)

    local function updateSwatch()
        swatch.BackgroundColor3 = Color3.fromRGB(r, g, b)
        callback(Color3.fromRGB(r, g, b))
    end

    local function makeRGBSlider(name, idx, yPos)
        local row = Instance.new("Frame", frame)
        row.Size = UDim2.new(1, -24, 0, 20)
        row.Position = UDim2.new(0, 12, 0, yPos)
        row.BackgroundTransparency = 1
        row.ZIndex = 5

        local lbl = Instance.new("TextLabel", row)
        lbl.Size = UDim2.new(0, 12, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = name
        lbl.TextColor3 = COLOR.textDim
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 10
        lbl.ZIndex = 5

        local track = Instance.new("Frame", row)
        track.Size = UDim2.new(1, -80, 0, 4)
        track.Position = UDim2.new(0, 16, 0.5, -2)
        track.BackgroundColor3 = Color3.fromRGB(55, 58, 70)
        track.BorderSizePixel = 0
        track.ZIndex = 5
        Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

        local val = (idx == 1 and r) or (idx == 2 and g) or b
        local rel = val / 255
        local fill = Instance.new("Frame", track)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        fill.BorderSizePixel = 0
        fill.ZIndex = 6
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

        local numBox = Instance.new("TextBox", row)
        numBox.Size = UDim2.new(0, 42, 0, 18)
        numBox.Position = UDim2.new(1, -44, 0.5, -9)
        numBox.BackgroundColor3 = COLOR.inputBg
        numBox.BackgroundTransparency = 0.15
        numBox.BorderSizePixel = 0
        numBox.Text = tostring(val)
        numBox.TextColor3 = COLOR.text
        numBox.Font = Enum.Font.Gotham
        numBox.TextSize = 10
        numBox.ClearTextOnFocus = false
        numBox.ZIndex = 6
        Instance.new("UICorner", numBox).CornerRadius = UDim.new(0, 4)
        local nbStroke = Instance.new("UIStroke", numBox)
        nbStroke.Color = COLOR.stroke
        nbStroke.Transparency = 0.9

        local hit = Instance.new("TextButton", row)
        hit.Size = UDim2.new(1, -80, 0, 18)
        hit.Position = UDim2.new(0, 16, 0.5, -9)
        hit.BackgroundTransparency = 1
        hit.Text = ""
        hit.AutoButtonColor = false
        hit.ZIndex = 5
        hit.Parent = row

        local function setVal(v, fromInput)
            v = math.clamp(math.floor(v), 0, 255)
            if idx == 1 then r = v elseif idx == 2 then g = v else b = v end
            fill.Size = UDim2.new(v / 255, 0, 1, 0)
            if not fromInput then numBox.Text = tostring(v) end
            updateSwatch()
        end

        local dragging = false
        local function updateFromMouse(mx)
            local rel2 = math.clamp((mx - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            setVal(255 * rel2)
        end

        hit.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                updateFromMouse(inp.Position.X)
            end
        end)
        UserInputService.InputChanged:Connect(function(inp)
            if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
                updateFromMouse(inp.Position.X)
            end
        end)
        UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)
        numBox.FocusLost:Connect(function()
            local n = tonumber(numBox.Text)
            if n then
                setVal(n, true)
                numBox.Text = tostring(math.clamp(math.floor(n), 0, 255))
            else
                numBox.Text = tostring((idx == 1 and r) or (idx == 2 and g) or b)
            end
        end)
    end

    makeRGBSlider("R", 1, 28)
    makeRGBSlider("G", 2, 50)
    makeRGBSlider("B", 3, 72)

    return {
        setColor = function(c)
            r = math.round(c.R * 255)
            g = math.round(c.G * 255)
            b = math.round(c.B * 255)
            swatch.BackgroundColor3 = c
        end
    }
end

----------------------------------------------------------------------
-- KEYBIND PICKER
----------------------------------------------------------------------

local function addKeybind(panel, text, defaultName, onChanged)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -6, 0, 38)
    row.BackgroundTransparency = 1
    row.ZIndex = 4
    row.Parent = panel

    local label = Instance.new("TextLabel", row)
    label.Size = UDim2.new(0.6, 0, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = COLOR.text
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 4

    local box = Instance.new("TextButton", row)
    box.Size = UDim2.new(0, 100, 0, 26)
    box.Position = UDim2.new(1, -112, 0.5, -13)
    box.BackgroundColor3 = COLOR.inputBg
    box.BackgroundTransparency = 0.15
    box.BorderSizePixel = 0
    box.Text = defaultName
    box.TextColor3 = COLOR.text
    box.Font = Enum.Font.Gotham
    box.TextSize = 12
    box.AutoButtonColor = false
    box.ZIndex = 5
    box.Parent = row
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
    local kbStroke = Instance.new("UIStroke", box)
    kbStroke.Color = COLOR.stroke
    kbStroke.Transparency = 0.9

    local listening = false
    local listeningArmed = false

    box.MouseButton1Click:Connect(function()
        listening = true
        task.delay(0.15, function() listeningArmed = true end)
        box.Text = "Press..."
        box.TextColor3 = Color3.fromRGB(255, 220, 120)
    end)

    UserInputService.InputBegan:Connect(function(input, gp)
        if not listening or not listeningArmed then return end

        if input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode == Enum.KeyCode.Escape then
                listening = false; listeningArmed = false
                box.Text = defaultName
                box.TextColor3 = COLOR.text
                return
            end
            local name = input.KeyCode.Name
            if name == "Unknown" then return end
            box.Text = name
            box.TextColor3 = COLOR.text
            listening = false; listeningArmed = false
            onChanged(input.KeyCode, name)
        elseif input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2
            or input.UserInputType == Enum.UserInputType.MouseButton3 then
            local name = (input.UserInputType == Enum.UserInputType.MouseButton1 and "LMB")
                or (input.UserInputType == Enum.UserInputType.MouseButton2 and "RMB")
                or "MMB"
            box.Text = name
            box.TextColor3 = COLOR.text
            listening = false; listeningArmed = false
            onChanged(input.UserInputType, name)
        end
    end)
end

----------------------------------------------------------------------
-- TEXT INPUT
----------------------------------------------------------------------

local function addTextInput(panel, text, default, placeholder, callback)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -6, 0, 38)
    row.BackgroundTransparency = 1
    row.ZIndex = 4
    row.Parent = panel

    local label = Instance.new("TextLabel", row)
    label.Size = UDim2.new(0.35, 0, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = COLOR.text
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 4

    local box = Instance.new("TextBox", row)
    box.Size = UDim2.new(0.65, -16, 0, 26)
    box.Position = UDim2.new(0.35, 0, 0.5, -13)
    box.BackgroundColor3 = COLOR.inputBg
    box.BackgroundTransparency = 0.15
    box.BorderSizePixel = 0
    box.Text = default or ""
    box.PlaceholderText = placeholder or ""
    box.TextColor3 = COLOR.text
    box.Font = Enum.Font.Gotham
    box.TextSize = 11
    box.ClearTextOnFocus = false
    box.TextTruncate = Enum.TextTruncate.AtEnd
    box.ZIndex = 5
    box.Parent = row
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
    local stroke = Instance.new("UIStroke", box)
    stroke.Color = COLOR.stroke
    stroke.Transparency = 0.9

    box.FocusLost:Connect(function()
        callback(box.Text)
    end)
    return box
end
----------------------------------------------------------------------
-- TABS INSTANCES
----------------------------------------------------------------------

local pAimbot   = createTab("Aimbot",   "✜", 1)
local pTarget   = createTab("Target",   "◉", 2)
local pPlayer   = createTab("Player",   "☺", 3)
local pMisc     = createTab("Misc",     "✚", 4)
local pSettings = createTab("Settings", "⚙", 5)

----------------------------------------------------------------------
-- AIMBOT TAB
----------------------------------------------------------------------

addSection(pAimbot, "Aimbot")

local aimbotToggleRef = addToggle(pAimbot, "Aimbot", function(enabled)
    setAimbotEnabled(enabled)
    if notifHolder then
        notify(notifHolder, "Dexa Hub",
            enabled and "Aimbot enabled." or "Aimbot disabled.")
    end
end)

addToggle(pAimbot, "One-Press Mode", function(enabled)
    State.OnePressAimingMode = enabled
    if notifHolder then
        notify(notifHolder, "Dexa Hub",
            "One-Press: " .. (enabled and "ON" or "OFF"), 2)
    end
end, State.OnePressAimingMode)

addKeybind(pAimbot, "Aim Key", State.AimKeyName or "RMB", function(code, name)
    State.AimKey     = code
    State.AimKeyName = name
    if notifHolder then
        notify(notifHolder, "Dexa Hub", "Aim Key: " .. name, 2)
    end
end)

addSegmented(pAimbot, "Aim Part", { "Head", "Body" }, State.AimbotPart, function(opt)
    State.AimbotPart = opt
    if notifHolder then
        notify(notifHolder, "Dexa Hub", "Aim Part: " .. opt, 2)
    end
end)

addSegmented(pAimbot, "Aim Mode", { "Smooth", "Lock" }, State.AimbotMode, function(opt)
    State.AimbotMode = opt
    applySensitivityForMode()
    if notifHolder then
        notify(notifHolder, "Dexa Hub", "Aim Mode: " .. opt, 2)
    end
end)

addValueSlider(pAimbot, "Aim Smoothness (1 fast – 100 slow)", 1, 100,
    State.AimbotSmoothness, function(v) State.AimbotSmoothness = v end)

addDivider(pAimbot)

-- ================================================================
-- NEAREST TARGET SECTION
-- ================================================================

addSection(pAimbot, "Nearest Target")

addToggle(pAimbot, "Nearest Target", function(enabled)
    State.NearestTarget = enabled
    if enabled then
        acquireNearestNow()
        if notifHolder then
            local sp = State.SelectedPlayer
            notify(notifHolder, "Dexa Hub",
                sp and ("Nearest locked: @" .. sp.Name) or "Nearest Target: ON",
                sp and 2.5 or 2)
        end
    else
        State._nearestLocked = nil
        if notifHolder then
            notify(notifHolder, "Dexa Hub", "Nearest Target: OFF", 2)
        end
    end
end, State.NearestTarget)

-- Sub text explaining the two modes
addSubText(pAimbot,
    "Lock: keeps the target picked when aimbot turned on. Follow: switches to whoever is closest even if someone new gets nearer.")

-- Mode segmented control
addSegmented(pAimbot, "Nearest Mode", { "Lock", "Follow" },
    State.NearestLockMode or "Lock",
    function(opt)
        State.NearestLockMode = opt
        if opt == "Lock" then
            -- Re-lock onto whatever is nearest right now
            acquireNearestNow()
        end
        if notifHolder then
            if opt == "Lock" then
                notify(notifHolder, "Dexa Hub",
                    "Nearest Mode: Lock (keeps current target)", 2.5)
            else
                notify(notifHolder, "Dexa Hub",
                    "Nearest Mode: Follow (always closest)", 2.5)
            end
        end
    end)

addValueSlider(pAimbot, "Nearest Range (studs)", 100, 3000,
    State.NearestRange or 1000, function(v) State.NearestRange = v end)

addDivider(pAimbot)

-- ================================================================
-- CHECKS
-- ================================================================

addSection(pAimbot, "Checks")

addToggle(pAimbot, "Wall Check", function(enabled)
    State.WallCheck = enabled
    if notifHolder then
        notify(notifHolder, "Dexa Hub",
            "Wall Check: " .. (enabled and "ON" or "OFF"), 2)
    end
end, State.WallCheck)

addDivider(pAimbot)

-- ================================================================
-- AIMBOT HIGHLIGHT
-- ================================================================

addSection(pAimbot, "Aimbot Highlight")

addToggle(pAimbot, "Enable Aimbot Highlight", function(enabled)
    State.HighlightTarget = enabled
    if not enabled then clearAimbotHighlight() end
    if notifHolder then
        notify(notifHolder, "Dexa Hub",
            "Highlight: " .. (enabled and "ON" or "OFF"), 2)
    end
end, State.HighlightTarget)

addToggle(pAimbot, "Highlight Fill", function(enabled)
    State.HighlightFill = enabled
end, State.HighlightFill)

addColorPicker(pAimbot, "Highlight Fill Color", State.HighlightFillColor,
    function(c) State.HighlightFillColor = c end)

addToggle(pAimbot, "Highlight Outline", function(enabled)
    State.HighlightOutline = enabled
end, State.HighlightOutline)

addColorPicker(pAimbot, "Highlight Outline Color", State.HighlightOutlineColor,
    function(c) State.HighlightOutlineColor = c end)

addDivider(pAimbot)

-- ================================================================
-- TRIGGERBOT
-- ================================================================

addSection(pAimbot, "TriggerBot")

local triggerbotToggleRef = addToggle(pAimbot, "TriggerBot", function(enabled)
    setTriggerBotEnabled(enabled)
    if notifHolder then
        notify(notifHolder, "Dexa Hub",
            enabled and "TriggerBot enabled." or "TriggerBot disabled.")
    end
end)

addKeybind(pAimbot, "TriggerBot Key", State.TriggerKeyName or "F",
    function(code, name)
        State.TriggerKey     = code
        State.TriggerKeyName = name
        if notifHolder then
            notify(notifHolder, "Dexa Hub", "TriggerBot Key: " .. name, 2)
        end
    end)

addValueSlider(pAimbot, "TriggerBot Delay (ms)", 0, 500,
    State.TriggerBotDelay, function(v) State.TriggerBotDelay = v end)

addValueSlider(pAimbot, "TriggerBot Chance (%)", 1, 100,
    State.TriggerBotChance, function(v) State.TriggerBotChance = v end)

addDivider(pAimbot)

-- ================================================================
-- LIVE INFO
-- ================================================================

addSection(pAimbot, "Live Info")

local lockInfo = Instance.new("Frame")
lockInfo.Size = UDim2.new(1, -6, 0, 28)
lockInfo.BackgroundColor3 = Color3.fromRGB(38, 40, 50)
lockInfo.BackgroundTransparency = 0.15
lockInfo.BorderSizePixel = 0
lockInfo.ZIndex = 4
lockInfo.Parent = pAimbot
Instance.new("UICorner", lockInfo).CornerRadius = UDim.new(0, 6)
local liStroke = Instance.new("UIStroke", lockInfo)
liStroke.Color = COLOR.stroke
liStroke.Transparency = 0.9

local lockTitle = Instance.new("TextLabel", lockInfo)
lockTitle.Size = UDim2.new(0.6, 0, 1, 0)
lockTitle.Position = UDim2.new(0, 10, 0, 0)
lockTitle.BackgroundTransparency = 1
lockTitle.Text = "Lock Time"
lockTitle.TextColor3 = COLOR.textDim
lockTitle.Font = Enum.Font.Gotham
lockTitle.TextSize = 11
lockTitle.TextXAlignment = Enum.TextXAlignment.Left
lockTitle.ZIndex = 5

local lockValue = Instance.new("TextLabel", lockInfo)
lockValue.Size = UDim2.new(0.4, -10, 1, 0)
lockValue.Position = UDim2.new(0.6, 0, 0, 0)
lockValue.BackgroundTransparency = 1
lockValue.Text = "— ms"
lockValue.TextColor3 = Color3.fromRGB(140, 220, 160)
lockValue.Font = Enum.Font.GothamBold
lockValue.TextSize = 12
lockValue.TextXAlignment = Enum.TextXAlignment.Right
lockValue.ZIndex = 5

local statusInfo = Instance.new("Frame")
statusInfo.Size = UDim2.new(1, -6, 0, 28)
statusInfo.BackgroundColor3 = Color3.fromRGB(38, 40, 50)
statusInfo.BackgroundTransparency = 0.15
statusInfo.BorderSizePixel = 0
statusInfo.ZIndex = 4
statusInfo.Parent = pAimbot
Instance.new("UICorner", statusInfo).CornerRadius = UDim.new(0, 6)
local siStroke = Instance.new("UIStroke", statusInfo)
siStroke.Color = COLOR.stroke
siStroke.Transparency = 0.9

local statusTitle = Instance.new("TextLabel", statusInfo)
statusTitle.Size = UDim2.new(0.6, 0, 1, 0)
statusTitle.Position = UDim2.new(0, 10, 0, 0)
statusTitle.BackgroundTransparency = 1
statusTitle.Text = "Current Target"
statusTitle.TextColor3 = COLOR.textDim
statusTitle.Font = Enum.Font.Gotham
statusTitle.TextSize = 11
statusTitle.TextXAlignment = Enum.TextXAlignment.Left
statusTitle.ZIndex = 5

local statusValue = Instance.new("TextLabel", statusInfo)
statusValue.Size = UDim2.new(0.4, -10, 1, 0)
statusValue.Position = UDim2.new(0.6, 0, 0, 0)
statusValue.BackgroundTransparency = 1
statusValue.Text = "None"
statusValue.TextColor3 = Color3.fromRGB(255, 220, 120)
statusValue.Font = Enum.Font.GothamBold
statusValue.TextSize = 11
statusValue.TextXAlignment = Enum.TextXAlignment.Right
statusValue.ZIndex = 5

----------------------------------------------------------------------
-- TARGET TAB
----------------------------------------------------------------------

addSection(pTarget, "Select Target")

targetSelectButton = Instance.new("TextButton")
targetSelectButton.Size = UDim2.new(1, -6, 0, 38)
targetSelectButton.BackgroundColor3 = COLOR.inputBg
targetSelectButton.BackgroundTransparency = 0.15
targetSelectButton.BorderSizePixel = 0
targetSelectButton.Text = "Target"
targetSelectButton.TextColor3 = COLOR.text
targetSelectButton.Font = Enum.Font.Gotham
targetSelectButton.TextSize = 12
targetSelectButton.TextXAlignment = Enum.TextXAlignment.Left
targetSelectButton.AutoButtonColor = false
targetSelectButton.ZIndex = 4
targetSelectButton.Parent = pTarget
Instance.new("UICorner", targetSelectButton).CornerRadius = UDim.new(0, 8)

local tsStroke = Instance.new("UIStroke", targetSelectButton)
tsStroke.Color = COLOR.stroke
tsStroke.Transparency = 0.85

local tsPad = Instance.new("UIPadding", targetSelectButton)
tsPad.PaddingLeft = UDim.new(0, 12)

local gridHolder = Instance.new("Frame", targetSelectButton)
gridHolder.Size = UDim2.new(0, 12, 0, 12)
gridHolder.Position = UDim2.new(1, -22, 0.5, -6)
gridHolder.BackgroundTransparency = 1
gridHolder.ZIndex = 5
for i = 0, 3 do
    local dot = Instance.new("Frame", gridHolder)
    local col = i % 2
    local row = math.floor(i / 2)
    dot.Size = UDim2.new(0, 5, 0, 5)
    dot.Position = UDim2.new(0, col * 7, 0, row * 7)
    dot.BackgroundColor3 = Color3.fromRGB(200, 200, 210)
    dot.BorderSizePixel = 0
    dot.ZIndex = 5
    Instance.new("UICorner", dot).CornerRadius = UDim.new(0, 2)
end

targetSearchBox = Instance.new("TextBox")
targetSearchBox.Size = UDim2.new(1, -6, 0, 30)
targetSearchBox.BackgroundColor3 = Color3.fromRGB(48, 51, 62)
targetSearchBox.BackgroundTransparency = 0.1
targetSearchBox.BorderSizePixel = 0
targetSearchBox.Text = "Search..."
targetSearchBox.TextColor3 = COLOR.textDim
targetSearchBox.Font = Enum.Font.Gotham
targetSearchBox.TextSize = 12
targetSearchBox.TextXAlignment = Enum.TextXAlignment.Left
targetSearchBox.ClearTextOnFocus = false
targetSearchBox.Visible = false
targetSearchBox.ZIndex = 4
targetSearchBox.Parent = pTarget
Instance.new("UICorner", targetSearchBox).CornerRadius = UDim.new(0, 8)
local ssStroke = Instance.new("UIStroke", targetSearchBox)
ssStroke.Color = COLOR.stroke
ssStroke.Transparency = 0.85
local ssPad = Instance.new("UIPadding", targetSearchBox)
ssPad.PaddingLeft = UDim.new(0, 12)

targetListFrame = Instance.new("ScrollingFrame")
targetListFrame.Size = UDim2.new(1, -6, 0, 150)
targetListFrame.BackgroundColor3 = Color3.fromRGB(25, 26, 34)
targetListFrame.BackgroundTransparency = 0.35
targetListFrame.BorderSizePixel = 0
targetListFrame.ScrollBarThickness = 3
targetListFrame.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 130)
targetListFrame.Visible = false
targetListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
targetListFrame.ZIndex = 4
targetListFrame.Parent = pTarget
Instance.new("UICorner", targetListFrame).CornerRadius = UDim.new(0, 8)
local tlStroke = Instance.new("UIStroke", targetListFrame)
tlStroke.Color = COLOR.stroke
tlStroke.Transparency = 0.9
local targetLayout = Instance.new("UIListLayout", targetListFrame)
targetLayout.Padding = UDim.new(0, 2)
local tlPad = Instance.new("UIPadding", targetListFrame)
tlPad.PaddingTop = UDim.new(0, 6)
tlPad.PaddingBottom = UDim.new(0, 6)

targetSearchBox.Focused:Connect(function()
    if targetSearchBox.Text == "Search..." then
        targetSearchBox.Text = ""
        targetSearchBox.TextColor3 = COLOR.text
    end
end)
targetSearchBox.FocusLost:Connect(function()
    if targetSearchBox.Text == "" then
        targetSearchBox.Text = "Search..."
        targetSearchBox.TextColor3 = COLOR.textDim
    end
    refreshTargets()
end)
targetSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    if targetSearchBox.Text ~= "Search..." then refreshTargets() end
end)

targetSelectButton.MouseButton1Click:Connect(function()
    local showing = not targetSearchBox.Visible
    targetSearchBox.Visible = showing
    targetListFrame.Visible = showing
    if showing then
        refreshTargets()
        targetSearchBox.Text = "Search..."
        targetSearchBox.TextColor3 = COLOR.textDim
    end
end)

addDivider(pTarget)

addSection(pTarget, "Target ESP")

addToggle(pTarget, "Enable Target ESP", function(enabled)
    State.TargetESP = enabled
    updateVisuals()
    if notifHolder then
        notify(notifHolder, "Dexa Hub",
            "Target ESP: " .. (enabled and "ON" or "OFF"), 2)
    end
end, State.TargetESP)

addToggle(pTarget, "Target ESP Fill", function(enabled)
    State.TargetESPFill = enabled
    refreshTargetESP()
end, State.TargetESPFill)

addColorPicker(pTarget, "Target ESP Fill Color", State.TargetESPFillColor,
    function(c)
        State.TargetESPFillColor = c
        refreshTargetESP()
    end)

addToggle(pTarget, "Target ESP Outline", function(enabled)
    State.TargetESPOutline = enabled
    refreshTargetESP()
end, State.TargetESPOutline)

addColorPicker(pTarget, "Target ESP Outline Color", State.TargetESPOutlineColor,
    function(c)
        State.TargetESPOutlineColor = c
        refreshTargetESP()
    end)

addDivider(pTarget)

addSection(pTarget, "Actions")

addToggle(pTarget, "Fling Target", function(enabled)
    State.FlingTarget = enabled
end)

addToggle(pTarget, "Spectate Target", function(enabled)
    setSpectate(enabled)
end)

addToggle(pTarget, "Touch Fling", function(enabled)
    setTouchFling(enabled)
end)

addArrowButton(pTarget, "Teleport To Target", function()
    local targetRoot = getRoot(getTargetCharacter())
    local myRoot = getRoot(getCharacter())
    if targetRoot and myRoot then
        myRoot.CFrame = targetRoot.CFrame
    end
end)

----------------------------------------------------------------------
-- TARGET FLING LOOP
----------------------------------------------------------------------

task.spawn(function()
    while task.wait(0.5) do
        if State.FlingTarget
            and State.SelectedPlayer
            and State.SelectedPlayer.Character then
            flingCharacter(State.SelectedPlayer.Character)
            task.wait(1.6)
        end
    end
end)

----------------------------------------------------------------------
-- PLAYER TAB
----------------------------------------------------------------------

addSection(pPlayer, "Character")

addSlider(
    pPlayer, "Walk Speed", 16, 100, State.WalkSpeedValue,
    function(enabled)
        State.WalkSpeed = enabled
        if not enabled then
            local h = getHumanoid(getCharacter())
            if h then h.WalkSpeed = 16 end
        end
    end,
    function(value) setWalkSpeedValue(value) end
)

addSlider(
    pPlayer, "Jump Power", 50, 250, State.JumpPowerValue,
    function(enabled)
        State.JumpPower = enabled
        if not enabled then
            local h = getHumanoid(getCharacter())
            if h then h.JumpPower = 50 end
        end
    end,
    function(value) setJumpPowerValue(value) end
)

addDivider(pPlayer)

addToggle(pPlayer, "Anti Fling", function(enabled)
    State.AntiFling = enabled
end)

----------------------------------------------------------------------
-- MISC TAB
----------------------------------------------------------------------

addSection(pMisc, "Visuals")

addToggle(pMisc, "Player Chams", function(enabled)
    State.Chams = enabled
    updateVisuals()
end)

addToggle(pMisc, "Role Chams (Red/Blue/Green)", function(enabled)
    State.RoleChams = enabled
    updateVisuals()
    if notifHolder then
        notify(notifHolder, "Dexa Hub",
            "Role Chams: " .. (enabled and "ON" or "OFF"), 2)
    end
end, State.RoleChams)

addToggle(pMisc, "Gun Cham (dropped gun)", function(enabled)
    State.GunCham = enabled
    updateGunCham()
    if notifHolder then
        notify(notifHolder, "Dexa Hub",
            "Gun Cham: " .. (enabled and "ON" or "OFF"), 2)
    end
end, State.GunCham)

addToggle(pMisc, "Name ESP", function(enabled)
    State.ESP = enabled
    updateVisuals()
end)

addDivider(pMisc)

addSection(pMisc, "Utility")

addArrowButton(pMisc, "Teleport To Lobby", function()
    if teleportToLobby() then
        notify(notifHolder, "Dexa Hub", "Teleported to lobby.")
    else
        notify(notifHolder, "Notification", "RegularLobby not found.")
    end
end)
----------------------------------------------------------------------
-- SETTINGS TAB
----------------------------------------------------------------------

addSection(pSettings, "Configuration")

addToggle(pSettings, "Auto Save Settings", function(enabled)
    State.AutoSave = enabled
    if enabled then
        if saveSettingsToFile() then
            notify(notifHolder, "Dexa Hub", "Auto Save enabled. Settings saved.")
        else
            notify(notifHolder, "Dexa Hub",
                "Auto Save ON but executor has no file I/O.")
        end
    end
end, State.AutoSave)

addArrowButton(pSettings, "Save Settings Now", function()
    if saveSettingsToFile() then
        notify(notifHolder, "Dexa Hub", "Settings saved to " .. SETTINGS_FILE)
    else
        notify(notifHolder, "Dexa Hub",
            "Save failed. Executor must support writefile / readfile.")
    end
end)

addArrowButton(pSettings, "Load Settings From File", function()
    if loadSettingsFromFile() then
        notify(notifHolder, "Dexa Hub",
            "Settings loaded. Reopen the menu to see the changes.")
    else
        notify(notifHolder, "Dexa Hub",
            "No saved settings found or file I/O unsupported.")
    end
end)

addArrowButton(pSettings, "Delete Settings File", function()
    if HAS_FILEIO and getfenv().delfile then
        pcall(function() getfenv().delfile(SETTINGS_FILE) end)
        notify(notifHolder, "Dexa Hub", "Settings file deleted.")
    else
        notify(notifHolder, "Dexa Hub", "Executor doesn't support delfile.")
    end
end)

addDivider(pSettings)

addSection(pSettings, "Re-Execute")

addTextInput(pSettings, "Script URL", State.ScriptURL,
    "https://.../script.lua",
    function(txt) State.ScriptURL = txt end)

addToggle(pSettings, "Auto ReExecute", function(enabled)
    State.AutoReExecute = enabled
    notify(notifHolder, "Dexa Hub",
        "Auto ReExecute: " .. (enabled and "ON" or "OFF"), 2)
end, State.AutoReExecute)

addArrowButton(pSettings, "ReExecute Now", function()
    if State.ScriptURL == "" then
        notify(notifHolder, "Dexa Hub",
            "Set the Script URL above first.", 3)
        return
    end
    if not getfenv().loadstring then
        notify(notifHolder, "Dexa Hub",
            "Executor doesn't expose loadstring.", 3)
        return
    end

    saveSettingsToFile()
    notify(notifHolder, "Dexa Hub", "Re-executing script…", 2)

    task.spawn(function()
        task.wait(0.5)
        local ok, err = pcall(function()
            local src = game:HttpGet(State.ScriptURL, true)
            getfenv().loadstring(src)()
        end)
        if not ok then
            notify(notifHolder, "Dexa Hub",
                "ReExecute failed. Check the URL.", 3)
        end
    end)
end)

addDivider(pSettings)

addSection(pSettings, "Server")

addSection(pSettings, "Hotkeys")

addKeybind(pSettings, "Minimize Key", State.MinimizeKeyName or "LeftControl",
    function(code, name)
        State.MinimizeKey     = code
        State.MinimizeKeyName = name
        if notifHolder then
            notify(notifHolder, "Dexa Hub", "Minimize Key: " .. name, 2)
        end
    end)

addDivider(pSettings)

addSection(pSettings, "Server")

addToggle(pSettings, "Auto Rejoin", function(enabled)
    State.AutoRejoin = enabled
    notify(notifHolder, "Dexa Hub",
        "Auto Rejoin: " .. (enabled and "ON" or "OFF"), 2)

    if enabled and State.AutoReExecute and State.ScriptURL ~= "" then
        if getfenv().queue_on_teleport then
            pcall(function()
                getfenv().queue_on_teleport(string.format(
                    'loadstring(game:HttpGet("%s", true))()',
                    State.ScriptURL))
            end)
        end
    end
end, State.AutoRejoin)

addArrowButton(pSettings, "Rejoin Server", function()
    saveSettingsToFile()
    if State.AutoReExecute and State.ScriptURL ~= ""
        and getfenv().queue_on_teleport then
        pcall(function()
            getfenv().queue_on_teleport(string.format(
                'loadstring(game:HttpGet("%s", true))()',
                State.ScriptURL))
        end)
    end
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
end)

addArrowButton(pSettings, "Server Hop", function()
    saveSettingsToFile()
    if State.AutoReExecute and State.ScriptURL ~= ""
        and getfenv().queue_on_teleport then
        pcall(function()
            getfenv().queue_on_teleport(string.format(
                'loadstring(game:HttpGet("%s", true))()',
                State.ScriptURL))
        end)
    end
    TeleportService:Teleport(game.PlaceId, player)
end)

----------------------------------------------------------------------
-- PROFILE CARD
----------------------------------------------------------------------

local profileCard = Instance.new("Frame")
profileCard.Size = UDim2.new(1, -16, 0, 50)
profileCard.Position = UDim2.new(0, 8, 1, -58)
profileCard.BackgroundColor3 = Color3.fromRGB(30, 32, 42)
profileCard.BackgroundTransparency = 0.35
profileCard.BorderSizePixel = 0
profileCard.ZIndex = 3
profileCard.Parent = sidebar
Instance.new("UICorner", profileCard).CornerRadius = UDim.new(0, 10)
local pcStroke = Instance.new("UIStroke", profileCard)
pcStroke.Color = COLOR.stroke
pcStroke.Transparency = 0.9

local avatar = Instance.new("ImageLabel", profileCard)
avatar.Size = UDim2.new(0, 34, 0, 34)
avatar.Position = UDim2.new(0, 8, 0.5, -17)
avatar.BackgroundColor3 = Color3.fromRGB(55, 58, 70)
avatar.BorderSizePixel = 0
avatar.ZIndex = 4
avatar.Parent = profileCard
Instance.new("UICorner", avatar).CornerRadius = UDim.new(1, 0)

task.spawn(function()
    local ok, thumb = pcall(function()
        return Players:GetUserThumbnailAsync(
            player.UserId,
            Enum.ThumbnailType.HeadShot,
            Enum.ThumbnailSize.Size100x100)
    end)
    if ok and thumb then avatar.Image = thumb end
end)

local dnLabel = Instance.new("TextLabel", profileCard)
dnLabel.Size = UDim2.new(1, -52, 0, 16)
dnLabel.Position = UDim2.new(0, 48, 0, 8)
dnLabel.BackgroundTransparency = 1
dnLabel.Text = player.DisplayName
dnLabel.TextColor3 = COLOR.text
dnLabel.Font = Enum.Font.GothamBold
dnLabel.TextSize = 12
dnLabel.TextXAlignment = Enum.TextXAlignment.Left
dnLabel.TextTruncate = Enum.TextTruncate.AtEnd
dnLabel.ZIndex = 4

local unLabel = Instance.new("TextLabel", profileCard)
unLabel.Size = UDim2.new(1, -52, 0, 14)
unLabel.Position = UDim2.new(0, 48, 0, 26)
unLabel.BackgroundTransparency = 1
unLabel.Text = "@" .. player.Name
unLabel.TextColor3 = COLOR.textDim
unLabel.Font = Enum.Font.Gotham
unLabel.TextSize = 10
unLabel.TextXAlignment = Enum.TextXAlignment.Left
unLabel.TextTruncate = Enum.TextTruncate.AtEnd
unLabel.ZIndex = 4

----------------------------------------------------------------------
-- TAB INIT
----------------------------------------------------------------------

tabData[1].button.BackgroundTransparency = 0.4
tabData[1].button.TextColor3 = COLOR.text
tabData[1].indicator.Visible = true
tabPanels["Aimbot"].Visible = true

for _, panel in pairs(tabPanels) do
    local layout = panel:FindFirstChildOfClass("UIListLayout")
    if layout then
        local function updateCanvas()
            panel.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
        end
        layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
        updateCanvas()
    end
end

----------------------------------------------------------------------
-- MAIN FRAME DRAG
----------------------------------------------------------------------

local dragging = false
local dragStart
local startPosition

local INTERACTIVE_CLASSES = {
    TextButton = true,
    ImageButton = true,
    TextBox = true,
}

mainFrame.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then return end

    local guiObjects = playerGui:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
    local canDrag = true
    for _, obj in ipairs(guiObjects) do
        if obj ~= mainFrame
            and obj:IsDescendantOf(mainFrame)
            and INTERACTIVE_CLASSES[obj.ClassName] then
            canDrag = false
            break
        end
    end

    if canDrag then
        dragging = true
        dragStart = input.Position
        startPosition = mainFrame.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

----------------------------------------------------------------------
-- RESIZE HANDLES
----------------------------------------------------------------------

local MIN_W, MIN_H = 480, 320

local function createResizeHandle(dir)
    local handle = Instance.new("Frame")
    handle.BackgroundTransparency = 1
    handle.Active = true
    handle.ZIndex = 20
    handle.Parent = mainFrame

    if dir == "right" then
        handle.Size = UDim2.new(0, 6, 1, -24); handle.Position = UDim2.new(1, -3, 0, 12)
    elseif dir == "left" then
        handle.Size = UDim2.new(0, 6, 1, -24); handle.Position = UDim2.new(0, -3, 0, 12)
    elseif dir == "bottom" then
        handle.Size = UDim2.new(1, -24, 0, 6); handle.Position = UDim2.new(0, 12, 1, -3)
    elseif dir == "top" then
        handle.Size = UDim2.new(1, -24, 0, 6); handle.Position = UDim2.new(0, 12, 0, -3)
    elseif dir == "topright" then
        handle.Size = UDim2.new(0, 14, 0, 14); handle.Position = UDim2.new(1, -7, 0, -7)
    elseif dir == "topleft" then
        handle.Size = UDim2.new(0, 14, 0, 14); handle.Position = UDim2.new(0, -7, 0, -7)
    elseif dir == "bottomright" then
        handle.Size = UDim2.new(0, 14, 0, 14); handle.Position = UDim2.new(1, -7, 1, -7)
    elseif dir == "bottomleft" then
        handle.Size = UDim2.new(0, 14, 0, 14); handle.Position = UDim2.new(0, -7, 1, -7)
    end

    local isDragging = false
    local startMouse, startSize, startPos

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            isDragging = true
            startMouse = input.Position
            startSize = mainFrame.AbsoluteSize
            startPos = { x = mainFrame.AbsolutePosition.X, y = mainFrame.AbsolutePosition.Y }
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not isDragging or input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local delta = input.Position - startMouse
        local newW, newH = startSize.X, startSize.Y
        local posX, posY = startPos.x, startPos.y

        if dir:find("right") then newW = startSize.X + delta.X end
        if dir:find("left") then newW = startSize.X - delta.X; posX = startPos.x + delta.X end
        if dir:find("bottom") then newH = startSize.Y + delta.Y end
        if dir:find("top") then newH = startSize.Y - delta.Y; posY = startPos.y + delta.Y end
        if newW < MIN_W then
            if dir:find("left") then posX = startPos.x + (startSize.X - MIN_W) end
            newW = MIN_W
        end
        if newH < MIN_H then
            if dir:find("top") then posY = startPos.y + (startSize.Y - MIN_H) end
            newH = MIN_H
        end

        mainFrame.Size = UDim2.new(0, newW, 0, newH)
        mainFrame.Position = UDim2.new(0, posX, 0, posY)
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            isDragging = false
        end
    end)
end

for _, d in ipairs({
    "right", "left", "bottom", "top",
    "topright", "topleft", "bottomright", "bottomleft",
}) do
    createResizeHandle(d)
end

----------------------------------------------------------------------
-- LIVE INFO UPDATE
----------------------------------------------------------------------

RunService.RenderStepped:Connect(function()
    if not isAimbotActive() then
        lockValue.Text = "— ms"
        lockValue.TextColor3 = Color3.fromRGB(160, 160, 170)
    elseif lastLockMs > 0 then
        lockValue.Text = tostring(lastLockMs) .. " ms"
        if lastLockMs <= 50 then
            lockValue.TextColor3 = Color3.fromRGB(120, 230, 140)
        elseif lastLockMs <= 150 then
            lockValue.TextColor3 = Color3.fromRGB(240, 220, 120)
        else
            lockValue.TextColor3 = Color3.fromRGB(240, 140, 120)
        end
    else
        lockValue.Text = "locking…"
        lockValue.TextColor3 = Color3.fromRGB(160, 160, 170)
    end

    if State.SelectedPlayer then
        local suffix = ""
        if State.NearestTarget then
            local d = distanceToPlayer(State.SelectedPlayer)
            if d then suffix = string.format(" (%.0f)", d) end
        end
        statusValue.Text = "@" .. State.SelectedPlayer.Name .. suffix
        statusValue.TextColor3 = Color3.fromRGB(255, 220, 120)
    else
        statusValue.Text = "None"
        statusValue.TextColor3 = Color3.fromRGB(160, 160, 170)
    end
end)

----------------------------------------------------------------------
-- AIM KEY INPUT (hold or one-press)
----------------------------------------------------------------------

local function isAimKey(input)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        return input.KeyCode == State.AimKey
    end
    return input.UserInputType == State.AimKey
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if isAimKey(input) then
        if State.OnePressAimingMode then
            local newState = not State.Aimbot
            setAimbotEnabled(newState)
            if aimbotToggleRef then aimbotToggleRef.setState(newState) end
            if notifHolder then
                notify(notifHolder, "Dexa Hub",
                    newState and "Aimbot ON (toggled)" or "Aimbot OFF (toggled)", 1.5)
            end
        else
            if not State.Aimbot then
                State.Aiming = true
                if State.NearestTarget then
                    -- In nearest mode, don't stomp the currently locked target
                    if not isTargetValid() then
                        local nearest = pickNearestTarget()
                        State.SelectedPlayer = nearest
                        State._nearestLocked = nearest
                        if targetSelectButton then
                            targetSelectButton.Text = nearest and nearest.DisplayName or "Target"
                        end
                    end
                end
                applySensitivityForMode()
                resetLockTimer()
                ensureAimbotLoop()
            end
        end
        return
    end

    if input.KeyCode == Enum.KeyCode.P then
        cycleTarget()
    elseif input.KeyCode == State.MinimizeKey then
        mainFrame.Visible = not mainFrame.Visible
        if notifHolder then
            if not mainFrame.Visible then
                notify(notifHolder, "Dexa Hub",
                    "Minimized the menu. Use " .. State.MinimizeKeyName ..
                    " to toggle it.", 2.5)
            else
                notify(notifHolder, "Dexa Hub", "Menu restored.", 2)
            end
        end
    elseif input.KeyCode == State.TriggerKey then
        local newState = not State.TriggerBot
        setTriggerBotEnabled(newState)
        if triggerbotToggleRef then
            triggerbotToggleRef.setState(newState)
        end
        if notifHolder then
            notify(notifHolder, "Dexa Hub",
                "TriggerBot: " .. (newState and "ON" or "OFF"), 2)
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if isAimKey(input) and not State.OnePressAimingMode then
        if State.Aiming and not State.Aimbot then
            State.Aiming = false
            restoreSensitivity()
            stopAimbotLoop()
            clearAimbotHighlight()
        end
    end
end)

----------------------------------------------------------------------
-- RESPAWN
----------------------------------------------------------------------

player.CharacterAdded:Connect(function(character)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if humanoid and not State.SpectateTarget and not isAimbotActive() then
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = humanoid
    end
    if State.SpectateTarget then
        task.wait(0.2)
        spectateTarget()
    end
    if isAimbotActive() then
        applySensitivityForMode()
    else
        restoreSensitivity()
    end
end)

RunService.RenderStepped:Connect(function()
    if not State.SpectateTarget then return end
    if isAimbotActive() then return end
    local targetHumanoid = getHumanoid(getTargetCharacter())
    if targetHumanoid and targetHumanoid.Health > 0
        and camera.CameraSubject ~= targetHumanoid then
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = targetHumanoid
    end
end)

----------------------------------------------------------------------
-- PERIODIC AUTO-SAVE
----------------------------------------------------------------------

task.spawn(function()
    while task.wait(15) do
        if State.AutoSave and HAS_FILEIO then
            saveSettingsToFile()
        end
    end
end)

----------------------------------------------------------------------
-- INIT
----------------------------------------------------------------------

updateVisuals()

task.wait(0.4)
if notifHolder then
    local msg = LOADED_FROM_FILE
        and "Loaded. Settings restored from file."
        or "Loaded. Hold/Press Aim Key · P = Cycle Target · Ctrl = Hide"
    notify(notifHolder, "Dexa Hub", msg, 4)
end

print("[Dexa Hub] Loaded.")
