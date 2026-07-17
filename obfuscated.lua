local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local ScriptContext = game:GetService("ScriptContext")
local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait()
    LocalPlayer = Players.LocalPlayer
end
local _initStartTime = tick()
local _lastInitTime = _initStartTime
local function logInit(msg)
    local t = tick()
    print(string.format("[AnimeExpeditionsUltimate] %s (tốn %.4fs)", msg, t - _lastInitTime))
    _lastInitTime = t
end
local startedAt = os.clock()
local state = getgenv().KickBlockConnectionLost or {}
getgenv().KickBlockConnectionLost = state
state.enabled = true
state.errorCount = state.errorCount or 0
state.suspiciousCount = state.suspiciousCount or 0
state.kickAttempts = state.kickAttempts or 0
state.kickBlocks = state.kickBlocks or 0
state.delayBlocks = state.delayBlocks or 0
state.disconnectedErrorConnections = state.disconnectedErrorConnections or 0
local diagnosticConnection
local function log(message)
    warn(("[KickBlock] %s"):format(message))
end
local function describeSource(source)
    if typeof(source) ~= "Instance" then
        return "nil/non-instance source"
    end
    local ok, fullName = pcall(function()
        return source:GetFullName()
    end)
    return string.format("%s [%s] parent=%s", ok and fullName or tostring(source), source.ClassName, tostring(source.Parent))
end
local function isSuspiciousSource(source)
    return not (typeof(source) == "Instance" and source.Parent)
end
local function safe(label, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
        warn(("[ErrorCheckSafe:%s] %s"):format(tostring(label), tostring(err)))
    end
    return ok, err
end
local function callbackLooksLikeKick(callback)
    if type(callback) ~= "function" then
        return false
    end
    if not debug or typeof(debug.getconstants) ~= "function" then
        return true
    end
    local ok, constants = pcall(debug.getconstants, callback)
    if not ok or type(constants) ~= "table" then
        return true
    end
    for _, constant in ipairs(constants) do
        if type(constant) == "string" and constant:lower():find("kick", 1, true) then
            return true
        end
    end
    return false
end
local function connectDiagnostic()
    if diagnosticConnection then
        pcall(function()
            diagnosticConnection:Disconnect()
        end)
        diagnosticConnection = nil
    end
    diagnosticConnection = ScriptContext.Error:Connect(function(message, stackTrace, source)
        state.errorCount += 1
        local suspicious = isSuspiciousSource(source)
        if suspicious then
            state.suspiciousCount += 1
        end
        if suspicious then
            log(("suspicious ScriptContext.Error #%d uptime=%.1fs source=%s"):format(
                state.suspiciousCount,
                os.clock() - startedAt,
                describeSource(source)
            ))
            log("message: " .. tostring(message))
            if stackTrace and stackTrace ~= "" then
                log("stack: " .. tostring(stackTrace))
            end
            log("matched suspicious pattern: source missing or parentless; delayed Connection Lost kick may be scheduled")
        end
    end)
end
local function disconnectErrorConnections(source)
    if typeof(getconnections) ~= "function" then
        return 0
    end
    local disconnected = 0
    for _, connection in ipairs(getconnections(ScriptContext.Error)) do
        local ok = pcall(function()
            connection:Disconnect()
        end)
        if ok then
            disconnected += 1
            state.disconnectedErrorConnections += 1
        end
    end
    if disconnected > 0 and not (source == "watchdog" and disconnected <= 1) then
        log(("%s disconnected %d ScriptContext.Error connection(s), total=%d"):format(
            source,
            disconnected,
            state.disconnectedErrorConnections
        ))
    end
    return disconnected
end
local function isBlockedKick(self)
    return self == LocalPlayer
end
disconnectErrorConnections("startup")
connectDiagnostic()
if not state.hookedNamecall and typeof(hookmetamethod) == "function" and typeof(newcclosure) == "function" and typeof(checkcaller) == "function" then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        if self == LocalPlayer and method == "Kick" then
            state.kickAttempts += 1
            if not checkcaller() and isBlockedKick(self) then
                state.kickBlocks += 1
                log(("blocked LocalPlayer:Kick(%q), blocked=%d"):format(tostring(args[1]), state.kickBlocks))
                return nil
            end
        end
        return oldNamecall(self, ...)
    end))
    state.hookedNamecall = true
    log("installed __namecall Kick hook")
end
if not state.hookedIndexKick and typeof(hookmetamethod) == "function" and typeof(newcclosure) == "function" then
    local oldIndex
    oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
        if self == LocalPlayer and key == "Kick" then
            return function(player, reason, ...)
                state.kickAttempts += 1
                if isBlockedKick(player) then
                    state.kickBlocks += 1
                    log(("blocked LocalPlayer.Kick(LocalPlayer, %q), blocked=%d"):format(tostring(reason), state.kickBlocks))
                    return nil
                end
                return oldIndex(self, key)(player, reason, ...)
            end
        end
        return oldIndex(self, key)
    end))
    state.hookedIndexKick = true
    log("installed __index LocalPlayer.Kick hook")
end
if not state.hookedFunctionKick and typeof(hookfunction) == "function" and typeof(newcclosure) == "function" then
    pcall(function()
        local oldKick
        oldKick = hookfunction(LocalPlayer.Kick, newcclosure(function(self, reason, ...)
            if self == LocalPlayer then
                state.kickAttempts += 1
                if isBlockedKick(self) then
                    state.kickBlocks += 1
                    log(("blocked direct LocalPlayer.Kick(%q), blocked=%d"):format(tostring(reason), state.kickBlocks))
                    return nil
                end
            end
            return oldKick(self, reason, ...)
        end))
        state.hookedFunctionKick = true
        log("installed direct Kick hook")
    end)
end
if not state.hookedTaskDelay and typeof(hookfunction) == "function" and typeof(newcclosure) == "function" then
    pcall(function()
        local oldDelay
        oldDelay = hookfunction(task.delay, newcclosure(function(delayTime, callback, ...)
            local numericDelay = tonumber(delayTime)
            if numericDelay and numericDelay >= 30 and numericDelay <= 60 and callbackLooksLikeKick(callback) then
                state.delayBlocks += 1
                log(("blocked suspicious task.delay(%s), delayBlocks=%d"):format(tostring(delayTime), state.delayBlocks))
                return task.spawn(function() end)
            end
            return oldDelay(delayTime, callback, ...)
        end))
        state.hookedTaskDelay = true
        log("installed task.delay hook")
    end)
end
if not state.watchdogRunning then
    state.watchdogRunning = true
    task.spawn(function()
        while state.enabled do
            task.wait(5)
            disconnectErrorConnections("watchdog")
            connectDiagnostic()
        end
        state.watchdogRunning = false
    end)
end
getgenv().ErrorCheckSafe = safe
getgenv().KickBlockStatus = function()
    return {
        errorCount = state.errorCount,
        suspiciousCount = state.suspiciousCount,
        kickAttempts = state.kickAttempts,
        kickBlocks = state.kickBlocks,
        delayBlocks = state.delayBlocks,
        disconnectedErrorConnections = state.disconnectedErrorConnections,
        uptime = os.clock() - startedAt,
    }
end
log("loaded. Use getgenv().ErrorCheckSafe(label, fn) and getgenv().KickBlockStatus()")
_G.ShotgunBlacklist = _G.ShotgunBlacklist or {}
if not _G.ReplicaInterceptorActive then
    _G.ReplicaInterceptorActive = true
    local rc = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ReplicaCreate", 5)
    if rc then
        rc.OnClientEvent:Connect(function(data)
            if type(data) == "table" then
                for idStr, payload in pairs(data) do
                    local id = tonumber(idStr)
                    if id then
                        if not _G.LatestPartyId or id > _G.LatestPartyId then
                            _G.LatestPartyId = id
                        end
                    end
                end
            end
        end)
    end
    local rset = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ReplicaSet", 5)
    if rset then
        rset.OnClientEvent:Connect(function(idStr, path, value)
            if type(path) == "table" and path[1] == "Matchmaking" then
                local id = tonumber(idStr)
                if id then
                    _G.ShotgunBlacklist[id] = true
                end
            end
        end)
    end
end
local appConfig = {
    autoSummonEnabled = false,
    autoSummonBanners = {},
    autoSummonUnits = {},
    autoSummonAmount = 1,
    AutoJoin = "",
    autoJoinEnabled = false,
    autoJoinTeamEnabled = false,
    autoCraftEnabled = false,
    autoCraftItems = {},
    ShopSelections = {},
    TeamSelections = {},
    Macros = {},
    autoPlayEnabled = false,
    autoRestartInf = false,
    restartWaveNum = 50,
    autoLeaveSpriteMax = false,
    autoLeaveOnDefeat = false,
    AntiAFK = true,
    MobileToggle = false,
    WebhookUrl = "",
    webhookWinEnabled = false,
    webhookSummonEnabled = true,
    autoClaimQuests = false,
    autoClaimBP = false,
    autoClaimCalendar = false,
    autoClaimMilestones = false,
    hidePlayerNames = false,
    fixLagEnabled = false
}
local playerID = tostring(game.Players.LocalPlayer.UserId)
local folderName = "AnimeExpeditions_" .. playerID
local lobbyConfigPath = folderName .. "/lobby.json"
local ingameConfigPath = folderName .. "/ingame.json"
local macrosFolderPath = folderName .. "/macros"
if makefolder then
    if not isfolder(folderName) then makefolder(folderName) end
    if not isfolder(macrosFolderPath) then makefolder(macrosFolderPath) end
end
local lobbyConfigKeys = {
    "autoSummonEnabled", "autoSummonBanners", "autoSummonUnits", "autoSummonAmount",
    "AutoJoin", "autoJoinEnabled", "autoJoinTeamEnabled", "autoJoinMode", "autoCraftEnabled", "autoCraftItems", "ShopSelections", "TeamSelections",
    "autoClaimQuests", "autoClaimBP", "autoClaimCalendar", "autoClaimMilestones", "hidePlayerNames", "fixLagEnabled"
}
local ingameConfigKeys = {
    "autoPlayEnabled", "autoRestartInf", "restartWaveNum", "autoLeaveSpriteMax", "autoLeaveOnDefeat", "AntiAFK", "MobileToggle", "WebhookUrl", "webhookWinEnabled", "webhookSummonEnabled"
}
local function loadConfig()
    if not isfile then return end
    local savedMacroBackup = nil
    if isfile(lobbyConfigPath) then
        local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(lobbyConfigPath)) end)
        if ok and type(decoded) == "table" then
            for k, v in pairs(decoded) do appConfig[k] = v end
        end
    end
    if isfile(ingameConfigPath) then
        local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(ingameConfigPath)) end)
        if ok and type(decoded) == "table" then
            for k, v in pairs(decoded) do appConfig[k] = v end
            if type(decoded.Macros) == "table" then
                savedMacroBackup = decoded.Macros
            end
        end
    end
    appConfig.Macros = {}
    if listfiles and isfolder(macrosFolderPath) then
        pcall(function()
            for _, file in ipairs(listfiles(macrosFolderPath)) do
                if file:sub(-5) == ".json" then
                    local mapName = file:match("([^/\\]+)%.json$")
                    if mapName then
                        local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(file)) end)
                        if ok and type(decoded) == "table" then
                            appConfig.Macros[mapName] = decoded
                        end
                    end
                end
            end
        end)
    end
    if next(appConfig.Macros) == nil and type(savedMacroBackup) == "table" then
        appConfig.Macros = savedMacroBackup
    end
    appConfig.TeamSelections = appConfig.TeamSelections or {}
    appConfig.autoJoinMode = appConfig.autoJoinMode or "Start Instantly (Solo)"
    local isMobile = game:GetService("UserInputService").TouchEnabled
    if isMobile or appConfig.MobileToggle == nil then
        appConfig.MobileToggle = true
    end
end
local function saveConfig()
    if not writefile then return end
    local lobbyData = {}
    for _, k in ipairs(lobbyConfigKeys) do lobbyData[k] = appConfig[k] end
    local ingameData = {}
    for _, k in ipairs(ingameConfigKeys) do ingameData[k] = appConfig[k] end
    ingameData.Macros = appConfig.Macros
    pcall(function()
        writefile(lobbyConfigPath, HttpService:JSONEncode(lobbyData))
        writefile(ingameConfigPath, HttpService:JSONEncode(ingameData))
        for mapName, macroData in pairs(appConfig.Macros) do
            local safeName = mapName:gsub("[^%w%-_]", "")
            if safeName ~= "" then
                writefile(macrosFolderPath .. "/" .. safeName .. ".json", HttpService:JSONEncode(macroData))
            end
        end
    end)
end
logInit("Đang tải Config...")
loadConfig()
appConfig.ShopSelections = appConfig.ShopSelections or {}
appConfig.Macros = appConfig.Macros or {}
appConfig.autoSummonBanners = appConfig.autoSummonBanners or {}
appConfig.autoSummonUnits = appConfig.autoSummonUnits or {}
logInit("Đang móc nối Modules Game...")
local FusionPackage = ReplicatedStorage:WaitForChild("FusionPackage")
local Actions = require(FusionPackage:WaitForChild("Actions"))
local Fusion = require(FusionPackage:WaitForChild("Fusion"))
local Dependencies = require(FusionPackage:WaitForChild("Dependencies"))
local SharedInfo = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Information")
local BattlepassInfo = require(SharedInfo:WaitForChild("Battlepass"))
local CalendarInfo = require(SharedInfo:WaitForChild("Calendars"))
local MapInfo = require(SharedInfo:WaitForChild("Maps"))
local BannerInfo = require(SharedInfo:WaitForChild("BannerInfo"))
local ShopsInfo = require(SharedInfo:WaitForChild("Shops"))
local UnitsInfo = require(SharedInfo:WaitForChild("Units"))
local EventsInfo = require(SharedInfo:WaitForChild("Events"))
logInit("Đang cào dữ liệu Banner & Units...")
local allBanners = {}
if type(BannerInfo.Banners) == "table" then
    for k, _ in pairs(BannerInfo.Banners) do table.insert(allBanners, tostring(k)) end
end
table.sort(allBanners)
local allUnits = {}
local unitLabelToAssetId = {}
local unitAssetIdToLabel = {}
local bannerData = Fusion.peek(Dependencies.BannerData)
local waitTime = 0
while (not bannerData or not next(bannerData)) and waitTime < 5 do
    task.wait(0.5)
    waitTime = waitTime + 0.5
    bannerData = Fusion.peek(Dependencies.BannerData)
end
local snipeableUnits = {}
if bannerData then
    for _, bData in pairs(bannerData) do
        if type(bData) == "table" and bData.CurrentPool then
            for rarity, units in pairs(bData.CurrentPool) do
                if rarity == "Mythic" or rarity == "Secret" then
                    for _, u in ipairs(units) do
                        local assetId = tostring(u.Asset)
                        snipeableUnits[assetId] = true
                    end
                end
            end
        end
    end
end
for k, _ in pairs(snipeableUnits) do
    local uInfo = UnitsInfo[k]
    local displayName = (uInfo and (uInfo.Name or uInfo.DisplayName)) and (uInfo.Name or uInfo.DisplayName) or k
    local label = displayName .. " [" .. tostring(k) .. "]"
    unitLabelToAssetId[label] = tostring(k)
    unitAssetIdToLabel[tostring(k)] = label
    table.insert(allUnits, label)
end
table.sort(allUnits)
local function normalizeAutoSummonUnits(selectedUnits)
    local normalized = {}
    for _, value in ipairs(selectedUnits or {}) do
        local asString = tostring(value)
        local assetId = unitLabelToAssetId[asString] or asString:match("%[(.-)%]$") or asString
        if assetId ~= "" and not table.find(normalized, assetId) then
            table.insert(normalized, assetId)
        end
    end
    return normalized
end
appConfig.autoSummonUnits = normalizeAutoSummonUnits(appConfig.autoSummonUnits)
local allShops = {}
local function extractShopItems(shopNode, storeId)
    if type(shopNode) == "table" then
        if type(shopNode.Items) == "table" then
            for _, item in pairs(shopNode.Items) do
                if type(item) == "table" then
                    local name = item.Name or item.Product or item.Id
                    if name then
                        table.insert(allShops, {StoreId = storeId, ProductId = tostring(name)})
                    end
                elseif type(item) == "string" or type(item) == "number" then
                    table.insert(allShops, {StoreId = storeId, ProductId = tostring(item)})
                end
            end
        else
            for k, v in pairs(shopNode) do
                if type(v) == "table" then
                    extractShopItems(v, k)
                end
            end
        end
    end
end
for shopName, shopData in pairs(ShopsInfo) do
    extractShopItems(shopData, shopName)
end
local gamemodesMap = {}
if type(MapInfo.MapData) == "table" then
    for mode, v in pairs(MapInfo.MapData) do
        if mode ~= "Trial" and type(v) == "table" then
            gamemodesMap[mode] = {}
            for mapId, mapData in pairs(v) do
                gamemodesMap[mode][mapId] = {}
                if type(mapData.Acts) == "table" then
                    for actId, _ in pairs(mapData.Acts) do
                        table.insert(gamemodesMap[mode][mapId], tostring(actId))
                    end
                end
                if mode == "Infinite" and #gamemodesMap[mode][mapId] == 0 then
                    table.insert(gamemodesMap[mode][mapId], "1")
                end
            end
        end
    end
end
gamemodesMap["Challenge"] = {
    ["Daily"] = {},
    ["Weekly"] = {},
    ["Regular"] = {"1", "2", "3"}
}
local cachedFallbackMapName = ""
local cachedFallbackActName = ""
local function getGameStates()
    local ok, state = pcall(function() return Fusion.peek(Dependencies.GameState) end)
    local ok2, playerState = pcall(function() return Fusion.peek(Dependencies.GamePlayerState) end)
    local function safePeek(obj)
        if obj ~= nil then
            local success, val = pcall(function() return Fusion.peek(obj) end)
            if success then return val else return obj end
        end
        return nil
    end
    if ok and type(state) == "table" then
        local validPlayerState = (ok2 and type(playerState) == "table") and playerState or {}
        local params = safePeek(state.Parameters) or {}
        local gamemode = tostring(safePeek(params.Gamemode) or "")
        local mapName = tostring(safePeek(params.Map) or "")
        local actName = tostring(safePeek(params.Act) or "")
        local currentGameState = tostring(safePeek(state.CurrentGameState))
        if currentGameState == "Lobby" then
            cachedFallbackMapName = ""
            cachedFallbackActName = ""
        end
        if (mapName == "" or mapName == "nil") and currentGameState ~= "Lobby" then
            if cachedFallbackMapName ~= "" then
                mapName = cachedFallbackMapName
                if actName == "" or actName == "nil" then actName = cachedFallbackActName end
            else
                local lastScan = getgenv().lastGuiScanTime or 0
                if tick() - lastScan > 5 then
                    getgenv().lastGuiScanTime = tick()
                    local gui = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
                    if gui then
                        for _, v in pairs(gui:GetDescendants()) do
                            if v:IsA("TextLabel") and v.Visible and type(v.Text) == "string" then
                                local text = v.Text
                                if text:find("%- Act %d+") or text:lower():find("%- infinite") then
                                    local parts = string.split(text, " - ")
                                    if #parts >= 2 then
                                        local left = parts[1]
                                        if gamemode ~= "" and gamemode ~= "nil" then
                                            local gmPattern = gamemode:gsub("%-", "%%-")
                                            left = left:gsub(gmPattern, ""):gsub("^%s+", ""):gsub("%s+$", "")
                                        end
                                        if left ~= "" then
                                            mapName = left
                                            actName = parts[2]:gsub("Act ", "")
                                            cachedFallbackMapName = mapName
                                            cachedFallbackActName = actName
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        local function parseTime(t)
            if type(t) == "number" then return t end
            if type(t) == "string" then
                local m, s = t:match("(%d+):(%d+)")
                if m and s then return tonumber(m) * 60 + tonumber(s) end
                return tonumber(t) or 0
            end
            return 0
        end
        return {
            Wave = tonumber(safePeek(state.Wave)),
            MaxWave = tonumber(safePeek(state.MaxWave)) or 15,
            CurrentGameState = currentGameState,
            BaseHealth = tonumber(safePeek(state.BaseHealth)) or 0,
            Gamemode = gamemode,
            Map = mapName,
            Act = actName,
            GameTime = parseTime(safePeek(state.GameTime)) or parseTime(safePeek(state.SessionTime)) or parseTime(safePeek(state.Timer)) or 0,
            TotalKills = tonumber(safePeek(validPlayerState.TotalKills)) or tonumber(safePeek(validPlayerState.Kills)) or 0,
            TotalDamage = tonumber(safePeek(validPlayerState.TotalDamage)) or tonumber(safePeek(validPlayerState.Damage)) or 0
        }
    end
    return nil
end
local function getCurrentStageKey(stateInfo)
    if not stateInfo then return "Unknown" end
    local actName = stateInfo.Act
    local mapName = stateInfo.Map
    if (mapName == "" or mapName == "nil") and appConfig.AutoJoin and appConfig.AutoJoin ~= "" then
        local parts = string.split(appConfig.AutoJoin, "|")
        if parts[1] == stateInfo.Gamemode and parts[2] then
            mapName = parts[2]
            if actName == "" and parts[3] then actName = parts[3] end
        end
    end
    if mapName == "" then mapName = "UnknownMap" end
    if actName and actName ~= "" then
        actName = actName:gsub("Act ", "")
        return (stateInfo.Gamemode .. "_" .. mapName:gsub("%s", "") .. "_" .. actName):gsub("[^%w%-_]", "")
    else
        return (stateInfo.Gamemode .. "_" .. mapName:gsub("%s", "")):gsub("[^%w%-_]", "")
    end
end
local function normalizeStageKey(stageKey)
    return tostring(stageKey or ""):lower():gsub("[^%w]", "")
end
local function getMacroListForStage(stageKey)
    if appConfig.Macros[stageKey] then
        return appConfig.Macros[stageKey], stageKey
    end
    local normalizedTarget = normalizeStageKey(stageKey)
    for savedKey, macroList in pairs(appConfig.Macros) do
        if normalizeStageKey(savedKey) == normalizedTarget then
            return macroList, savedKey
        end
    end
    return nil, stageKey
end
local function isInfiniteGamemode(gamemode)
    return normalizeStageKey(gamemode) == "infinite"
end
logInit("Đang tải giao diện Fluent UI...")
local request = (syn and syn.request) or http_request or request
local compile = loadstring or load
local Fluent
local fluentPath = "AnimeExpeditions/FluentUI.lua"
if isfolder and not isfolder("AnimeExpeditions") then pcall(function() makefolder("AnimeExpeditions") end) end
if isfile and isfile(fluentPath) then
    local ok, res = pcall(function() return compile(readfile(fluentPath))() end)
    if ok and type(res) == "table" then Fluent = res end
end
if not Fluent then
    local res = request({Url = "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua", Method = "GET"})
    if res and res.Body then
        if writefile then pcall(function() writefile(fluentPath, res.Body) end) end
        Fluent = compile(res.Body)()
    end
end
local Window = Fluent:CreateWindow({
    Title = "Anime Expeditions",
    SubTitle = "by Sigma",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftShift
})
task.defer(function()
    task.wait(0.2)
    local minimized = pcall(function()
        Window:Minimize()
    end)
    if not minimized then
        local vim = game:GetService("VirtualInputManager")
        vim:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
        task.wait(0.05)
        vim:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
    end
end)
local Tabs = {
    Lobby = Window:AddTab({ Title = "Lobby Auto", Icon = "home" }),
    Summon = Window:AddTab({ Title = "Auto Summon", Icon = "sparkles" }),
    Shop = Window:AddTab({ Title = "Auto Shop", Icon = "shopping-cart" }),
    Craft = Window:AddTab({ Title = "Auto Craft", Icon = "hammer" }),
    Join = Window:AddTab({ Title = "Auto Join Map", Icon = "map" }),
    Macro = Window:AddTab({ Title = "Macro In-Game", Icon = "play" }),
    Webhook = Window:AddTab({ Title = "Webhook", Icon = "message-circle" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}
task.wait()
Tabs.Lobby:AddParagraph({ Title = "Thông Tin", Content = "Tự động nhận quà và nhiệm vụ ngầm." })
Tabs.Lobby:AddToggle("ToggleQuest", {Title = "Auto Claim Quests & Events", Default = appConfig.autoClaimQuests}):OnChanged(function(v) appConfig.autoClaimQuests = v; saveConfig() end)
Tabs.Lobby:AddToggle("ToggleBP", {Title = "Auto Claim Battlepass", Default = appConfig.autoClaimBP}):OnChanged(function(v) appConfig.autoClaimBP = v; saveConfig() end)
Tabs.Lobby:AddToggle("ToggleCal", {Title = "Auto Claim Calendar", Default = appConfig.autoClaimCalendar}):OnChanged(function(v) appConfig.autoClaimCalendar = v; saveConfig() end)
Tabs.Lobby:AddToggle("ToggleMilestone", {Title = "Auto Claim Milestones", Default = appConfig.autoClaimMilestones}):OnChanged(function(v) appConfig.autoClaimMilestones = v; saveConfig() end)
task.wait()
Tabs.Summon:AddParagraph({ Title = "Snipe Unit", Content = "Tự động quét server và roll Unit nếu có trong Banner." })
local DropBanners = Tabs.Summon:AddDropdown("DropBanners", {Title = "Select Banners", Values = allBanners, Multi = true, Default = appConfig.autoSummonBanners})
DropBanners:OnChanged(function(Value)
    local selected = {}
    for k, v in pairs(Value) do if v then table.insert(selected, k) end end
    appConfig.autoSummonBanners = selected
    saveConfig()
end)
local defaultSummonUnitLabels = {}
for _, assetId in ipairs(appConfig.autoSummonUnits) do
    local label = unitAssetIdToLabel[tostring(assetId)]
    if label then
        table.insert(defaultSummonUnitLabels, label)
    end
end
local DropUnits = Tabs.Summon:AddDropdown("DropUnits", {Title = "Target Units", Values = allUnits, Multi = true, Default = defaultSummonUnitLabels})
DropUnits:OnChanged(function(Value)
    local selected = {}
    for k, v in pairs(Value) do
        if v then
            local assetId = unitLabelToAssetId[k] or tostring(k):match("%[(.-)%]$") or tostring(k)
            if assetId ~= "" then
                table.insert(selected, assetId)
            end
        end
    end
    appConfig.autoSummonUnits = selected
    saveConfig()
end)
Tabs.Summon:AddDropdown("DropAmount", {Title = "Summon Amount", Values = {"1", "10"}, Multi = false, Default = tostring(appConfig.autoSummonAmount) == "10" and 2 or 1}):OnChanged(function(Value) appConfig.autoSummonAmount = tonumber(Value) or 1; saveConfig() end)
Tabs.Summon:AddToggle("ToggleSummon", {Title = "Bật Auto Summon (Snipe)", Default = appConfig.autoSummonEnabled}):OnChanged(function(v) appConfig.autoSummonEnabled = v; saveConfig() end)
task.wait()
Tabs.Shop:AddParagraph({ Title = "Auto Shop", Content = "Tự động mua các vật phẩm đã chọn." })
local groupedShops = {}
for _, item in ipairs(allShops) do
    if not groupedShops[item.StoreId] then groupedShops[item.StoreId] = {} end
    table.insert(groupedShops[item.StoreId], item.ProductId)
end
for storeId, products in pairs(groupedShops) do
    Tabs.Shop:AddDropdown("ShopDrop_" .. storeId, {
        Title = storeId,
        Values = products,
        Multi = true,
        Default = appConfig.ShopSelections[storeId] or {}
    }):OnChanged(function(value)
        local selected = {}
        for k, v in pairs(value) do if v then table.insert(selected, k) end end
        appConfig.ShopSelections[storeId] = selected
        saveConfig()
    end)
end
task.wait()
Tabs.Craft:AddParagraph({ Title = "Auto Craft", Content = "Tự động ghép đồ khi đang ở Lobby." })
Tabs.Craft:AddToggle("AutoCraftEnabled", {Title = "Bật Auto Craft (Lobby)", Default = appConfig.autoCraftEnabled}):OnChanged(function(state)
    appConfig.autoCraftEnabled = state
    saveConfig()
end)
local craftableList = {
    "HexedBlade", "HolyPendant",
    "SpriteRainbow", "SpriteBlue", "SpriteGreen",
    "SpritePink", "SpritePurple", "SpriteRed",
    "SpriteYellow", "SpriteGrey"
}
Tabs.Craft:AddDropdown("DropCraft", {Title = "Chọn đồ muốn Craft", Values = craftableList, Multi = true, Default = appConfig.autoCraftItems}):OnChanged(function(Value)
    local t = {}
    for k, v in pairs(Value) do if v then table.insert(t, k) end end
    appConfig.autoCraftItems = t
    saveConfig()
end)
Tabs.Craft:AddToggle("AutoLeaveSpriteMax", {Title = "Tự động Về Đảo khi Full Sprite (Grey)", Default = appConfig.autoLeaveSpriteMax}):OnChanged(function(state)
    appConfig.autoLeaveSpriteMax = state
    saveConfig()
end)
task.wait()
Tabs.Join:AddParagraph({ Title = "Auto Join Map", Content = "Chọn Map và bật Auto Join để tự động ghép trận." })
local CurrentJoinPara = Tabs.Join:AddParagraph({ Title = "Map Đang Chọn", Content = appConfig.AutoJoin ~= "" and appConfig.AutoJoin or "Chưa chọn Map nào" })
Tabs.Join:AddToggle("ToggleJoinMaster", {Title = "Bật Auto Join Map Đang Chọn", Default = appConfig.autoJoinEnabled}):OnChanged(function(v)
    appConfig.autoJoinEnabled = v
    saveConfig()
end)
Tabs.Join:AddToggle("ToggleAutoTeam", {Title = "Tự động nạp Team (Auto Load Team)", Default = appConfig.autoJoinTeamEnabled}):OnChanged(function(v)
    appConfig.autoJoinTeamEnabled = v
    saveConfig()
end)
Tabs.Join:AddDropdown("JoinModeSelect", {
    Title = "Auto Join Mode",
    Values = {"Start Instantly (Solo)", "Matchmaking (Multiplayer)"},
    Multi = false,
    Default = appConfig.autoJoinMode or "Start Instantly (Solo)"
}):OnChanged(function(value)
    appConfig.autoJoinMode = value
    saveConfig()
end)
Tabs.Join:AddSection("Cài Đặt Đội Hình")
Tabs.Join:AddParagraph({ Title = "Lưu Ý", Content = "Cài đặt Team tương ứng cho từng Map để Load tự động." })
local allUniqueMaps = {}
local seenMaps = {}
for mode, maps in pairs(gamemodesMap) do
    for mapId, _ in pairs(maps) do
        if not seenMaps[mapId] then
            seenMaps[mapId] = true
            table.insert(allUniqueMaps, mapId)
        end
    end
end
table.sort(allUniqueMaps)
for _, mapId in ipairs(allUniqueMaps) do
    Tabs.Join:AddDropdown("TeamSelect_" .. mapId, {
        Title = "Team cho " .. mapId,
        Values = {"1", "2", "3", "4", "5"},
        Multi = false,
        Default = appConfig.TeamSelections[mapId] or nil
    }):OnChanged(function(teamId)
        if teamId then
            appConfig.TeamSelections[mapId] = teamId
            saveConfig()
        end
    end)
end
Tabs.Join:AddSection("Chọn Map Tự Động Vào (Matchmaking)")
local function setJoinMap(mode, mapId, act)
    local uid = mode .. "|" .. mapId .. (act and ("|" .. act) or "")
    appConfig.AutoJoin = uid
    CurrentJoinPara:SetDesc(string.gsub(uid, "|", " -> "))
    saveConfig()
end
for mode, maps in pairs(gamemodesMap) do
    local mapNames = {}
    for mapId, acts in pairs(maps) do
        if #acts > 0 then
            for _, act in ipairs(acts) do table.insert(mapNames, mapId .. " - " .. act) end
        else
            table.insert(mapNames, mapId)
        end
    end
    table.sort(mapNames)
    local defaultVal = nil
    if appConfig.AutoJoin ~= "" then
        local parts = string.split(appConfig.AutoJoin, "|")
        if parts[1] == mode then
            if parts[3] and parts[3] ~= "" then
                defaultVal = parts[2] .. " - " .. parts[3]
            else
                defaultVal = parts[2]
            end
        end
    end
    Tabs.Join:AddDropdown("JoinDrop_" .. mode, {
        Title = mode,
        Values = mapNames,
        Multi = false,
        Default = defaultVal
    }):OnChanged(function(value)
        if value then
            local parts = string.split(value, " - ")
            setJoinMap(mode, parts[1], parts[2])
        end
    end)
end
task.wait()
Tabs.Macro:AddParagraph({ Title = "Hệ Thống Macro", Content = "Tự động nhận diện Map đang chơi để chạy Macro tương ứng." })
local isRecording = false
local isPlaying = false
local startTime = 0
local currentStageKey = "Unknown"
local CachedUnitGCMap = nil
local currentMacroPara = Tabs.Macro:AddParagraph({ Title = "Trạng Thái", Content = "Đang ở Lobby" })
local ToggleRecord = Tabs.Macro:AddToggle("ToggleRecord", {Title = "Ghi Hình (Record) Map Này", Default = false})
ToggleRecord:OnChanged(function(state)
    isRecording = state
    local sInfo = getGameStates()
    if not sInfo or sInfo.CurrentGameState == "Finished" then
        if state then
            ToggleRecord:SetValue(false)
            Fluent:Notify({Title = "Lỗi", Content = "Phải ở trong Game mới được Record!", Duration = 3})
        end
        return
    end
    currentStageKey = getCurrentStageKey(sInfo)
    if isRecording then
        if appConfig.autoPlayEnabled then ToggleRecord:SetValue(false) return end
        appConfig.Macros[currentStageKey] = {}
        startTime = tick()
        Fluent:Notify({Title = "Macro", Content = "Đang Record cho [" .. currentStageKey .. "]", Duration = 3})
    else
        saveConfig()
        Fluent:Notify({Title = "Macro", Content = "Đã lưu Macro cho [" .. currentStageKey .. "]", Duration = 3})
    end
end)
local TogglePlay = Tabs.Macro:AddToggle("TogglePlay", {Title = "Bật Auto Play", Default = appConfig.autoPlayEnabled})
TogglePlay:OnChanged(function(state)
    appConfig.autoPlayEnabled = state
    saveConfig()
    if not state then isPlaying = false end
end)
Tabs.Macro:AddToggle("AutoRestartInf", {Title = "Auto Restart (Chỉ Infinite)", Default = appConfig.autoRestartInf}):OnChanged(function(state)
    appConfig.autoRestartInf = state
    saveConfig()
end)
Tabs.Macro:AddInput("RestartWaveNum", {
    Title = "Wave Restart",
    Default = tostring(appConfig.restartWaveNum or 50),
    Numeric = true,
    Finished = false,
    Placeholder = "Ví dụ: 50",
    Callback = function(value)
        appConfig.restartWaveNum = tonumber(value) or 50
        saveConfig()
    end,
})
Tabs.Macro:AddToggle("AutoLeaveOnDefeat", {Title = "Tự động Thoát khi Thua (Defeat/Lose)", Default = appConfig.autoLeaveOnDefeat}):OnChanged(function(state)
    appConfig.autoLeaveOnDefeat = state
    saveConfig()
end)
Tabs.Macro:AddSection("Chia Sẻ Macro")
local ImportExportInput = Tabs.Macro:AddInput("MacroDataString", {
    Title = "Dữ liệu Macro",
    Default = "",
    Placeholder = "Dán mã Macro vào đây...",
    Numeric = false,
    Finished = false
})
Tabs.Macro:AddButton({
    Title = "Import Macro",
    Description = "Lưu mã Macro từ ô nhập liệu vào Map đang chơi.",
    Callback = function()
        if not currentStageKey or currentStageKey == "" or currentStageKey == "Unknown" then
            Fluent:Notify({Title = "Lỗi", Content = "Phải đứng trong Ải mới Import được!", Duration = 5})
            return
        end
        local dataString = ImportExportInput.Value
        if not dataString or dataString == "" then
            Fluent:Notify({Title = "Lỗi", Content = "Chưa nhập mã Macro!", Duration = 5})
            return
        end
        local success, decoded = pcall(function() return game:GetService("HttpService"):JSONDecode(dataString) end)
        if success and type(decoded) == "table" then
            appConfig.Macros[currentStageKey] = decoded
            saveConfig()
            Fluent:Notify({Title = "Thành công", Content = "Đã import Macro cho " .. currentStageKey, Duration = 5})
        else
            Fluent:Notify({Title = "Thất bại", Content = "Mã Macro không hợp lệ!", Duration = 5})
        end
    end
})
Tabs.Macro:AddButton({
    Title = "Import Từ Clipboard (Mã Dài)",
    Description = "Lấy mã Macro trực tiếp từ Clipboard (Copy) để không bị giới hạn độ dài.",
    Callback = function()
        if not currentStageKey or currentStageKey == "" or currentStageKey == "Unknown" then
            Fluent:Notify({Title = "Lỗi", Content = "Phải đứng trong Ải mới Import được!", Duration = 5})
            return
        end
        if not getclipboard then
            Fluent:Notify({Title = "Lỗi", Content = "Bản hack của bạn không hỗ trợ lấy Clipboard!", Duration = 5})
            return
        end
        local dataString = pcall(getclipboard) and getclipboard() or ""
        if not dataString or dataString == "" then
            Fluent:Notify({Title = "Lỗi", Content = "Clipboard đang trống!", Duration = 5})
            return
        end
        local success, decoded = pcall(function() return game:GetService("HttpService"):JSONDecode(dataString) end)
        if success and type(decoded) == "table" then
            appConfig.Macros[currentStageKey] = decoded
            saveConfig()
            Fluent:Notify({Title = "Thành công", Content = "Đã import từ Clipboard cho " .. currentStageKey, Duration = 5})
        else
            Fluent:Notify({Title = "Thất bại", Content = "Mã Macro không hợp lệ!", Duration = 5})
        end
    end
})
Tabs.Macro:AddButton({
    Title = "Export Macro",
    Description = "Lấy mã Macro của Map đang chơi.",
    Callback = function()
        if not currentStageKey or currentStageKey == "" or currentStageKey == "Unknown" then
            Fluent:Notify({Title = "Lỗi", Content = "Phải đứng trong Ải mới Export được!", Duration = 5})
            return
        end
        local macroData = appConfig.Macros[currentStageKey]
        if (not macroData or #macroData == 0) and isfile and readfile then
            local filePath = "AnimeExpeditions/Macros/" .. currentStageKey:gsub("[^%w%-_]", "") .. ".json"
            if isfile(filePath) then
                local ok, decoded = pcall(function() return game:GetService("HttpService"):JSONDecode(readfile(filePath)) end)
                if ok and type(decoded) == "table" and #decoded > 0 then
                    macroData = decoded
                    appConfig.Macros[currentStageKey] = macroData
                end
            end
        end
        if not macroData or #macroData == 0 then
            Fluent:Notify({Title = "Lỗi", Content = "Chưa có Macro nào ở Map này để Export!", Duration = 5})
            return
        end
        local dataString = game:GetService("HttpService"):JSONEncode(macroData)
        ImportExportInput:SetValue(dataString)
        if setclipboard then
            pcall(function() setclipboard(dataString) end)
            Fluent:Notify({Title = "Thành công", Content = "Đã Export và tự động copy vào Clipboard!", Duration = 5})
        else
            Fluent:Notify({Title = "Thành công", Content = "Đã Export! Hãy copy đoạn mã ở ô phía trên.", Duration = 5})
        end
    end
})
task.wait()
Tabs.Settings:AddParagraph({ Title = "Tự Động Lưu (Auto Save)", Content = "Mọi thiết lập của bạn (Kể cả Unit, Map, Macro) đều được tự động lưu ngay lập tức!" })
Tabs.Settings:AddToggle("HidePlayerNames", {Title = "Hide Player Names", Default = appConfig.hidePlayerNames}):OnChanged(function(v)
    appConfig.hidePlayerNames = v
    saveConfig()
end)
Tabs.Settings:AddToggle("AntiAFK", {Title = "Anti AFK", Default = appConfig.AntiAFK}):OnChanged(function(v)
    appConfig.AntiAFK = v
    saveConfig()
end)
local fixLagState = {
    lighting = nil,
    parts = {},
    decals = {}
}
local function SetFixLagEnabled(enabled)
    local lighting = game:GetService("Lighting")
    if enabled then
        if not fixLagState.lighting then
            fixLagState.lighting = {
                GlobalShadows = lighting.GlobalShadows,
                FogEnd = lighting.FogEnd,
            }
        end
        for _, v in ipairs(workspace:GetDescendants()) do
            if v:IsA("BasePart") then
                if not fixLagState.parts[v] then
                    fixLagState.parts[v] = {
                        Material = v.Material,
                        Color = v.Color,
                    }
                end
                v.Material = Enum.Material.SmoothPlastic
                v.Color = Color3.new(0.5, 0.5, 0.5)
            elseif v:IsA("Texture") or v:IsA("Decal") then
                if not fixLagState.decals[v] then
                    fixLagState.decals[v] = v.Transparency
                end
                v.Transparency = 1
            end
        end
        lighting.GlobalShadows = false
        lighting.FogEnd = 9e9
        return
    end
    if fixLagState.lighting then
        lighting.GlobalShadows = fixLagState.lighting.GlobalShadows
        lighting.FogEnd = fixLagState.lighting.FogEnd
    end
    for obj, state in pairs(fixLagState.parts) do
        if obj and obj.Parent then
            obj.Material = state.Material
            obj.Color = state.Color
        end
    end
    for obj, transparency in pairs(fixLagState.decals) do
        if obj and obj.Parent then
            obj.Transparency = transparency
        end
    end
end
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local lastAntiAfkInputAt = 0
local lastAFKChamberReturnAt = 0
local function IsAFKChamberVisible()
    local playerGui = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
    local chamberGui = playerGui and playerGui:FindFirstChild("AFKChamber")
    local frame = chamberGui and chamberGui:FindFirstChild("Frame")
    return chamberGui ~= nil and chamberGui.Enabled ~= false and frame ~= nil and frame.Visible
end
local lastAntiAfkJumpAt = 0
local function PulseAntiAFKInput()
    lastAntiAfkInputAt = tick()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        vim:SendMouseMoveEvent(5, 50, game)
        task.wait(0.02)
        vim:SendMouseButtonEvent(5, 50, 0, true, game, 1)
        task.wait(0.02)
        vim:SendMouseButtonEvent(5, 50, 0, false, game, 1)
    end)
    if tick() - lastAntiAfkJumpAt >= 600 then
        lastAntiAfkJumpAt = tick()
        local character = game:GetService("Players").LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            pcall(function()
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                humanoid:Move(Vector3.new(1, 0, 0), false)
                task.wait(0.05)
                humanoid:Move(Vector3.zero, false)
            end)
        end
    end
end
local function ReturnFromAFKChamber()
    if tick() - lastAFKChamberReturnAt < 10 then return false end
    lastAFKChamberReturnAt = tick()
    local ok, err = pcall(function()
        Actions.AFKChamber_ReturnToLobby()
    end)
    if ok then
        print("[ANTI AFK] Phát hiện AFK Chamber, đang tự quay về Lobby...")
        return true
    end
    warn("[ANTI AFK] Không thể rời AFK Chamber:", err)
    return false
end
game:GetService("Players").LocalPlayer.Idled:Connect(function()
    if appConfig.AntiAFK then
        PulseAntiAFKInput()
    end
end)
task.spawn(function()
    while task.wait(3) do
        if appConfig.AntiAFK then
            if IsAFKChamberVisible() then
                ReturnFromAFKChamber()
            elseif tick() - lastAntiAfkInputAt >= 20 then
                PulseAntiAFKInput()
            end
        end
    end
end)
Tabs.Settings:AddToggle("FixLagEnabled", {
    Title = "Fix Lag",
    Description = "Bật/tắt chế độ giảm đồ họa để đỡ lag",
    Default = appConfig.fixLagEnabled
}):OnChanged(function(v)
    appConfig.fixLagEnabled = v
    SetFixLagEnabled(v)
    saveConfig()
end)
local blackScreenGui = Instance.new("ScreenGui")
blackScreenGui.Name = "BlackScreenGUI"
blackScreenGui.ResetOnSpawn = false
blackScreenGui.IgnoreGuiInset = true
blackScreenGui.DisplayOrder = 99
local blackFrame = Instance.new("Frame", blackScreenGui)
blackFrame.Size = UDim2.new(1, 0, 1, 0)
blackFrame.BackgroundColor3 = Color3.new(0, 0, 0)
blackFrame.Visible = false
local coreGui = game:GetService("CoreGui")
if gethui then blackScreenGui.Parent = gethui() else blackScreenGui.Parent = coreGui end
Tabs.Settings:AddToggle("BlackScreen", {Title = "Black Screen (Màn hình đen)", Default = false}):OnChanged(function(v)
    blackFrame.Visible = v
end)
local MobileGui = Instance.new("ScreenGui")
MobileGui.Name = "MobileToggleGui"
MobileGui.ResetOnSpawn = false
MobileGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local ToggleBtn = Instance.new("ImageButton", MobileGui)
ToggleBtn.Size = UDim2.new(0, 45, 0, 45)
ToggleBtn.Position = UDim2.new(0.5, -120, 0, 10)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
ToggleBtn.Image = "rbxthumb://type=GameIcon&id=" .. game.GameId .. "&w=150&h=150"
local corner = Instance.new("UICorner", ToggleBtn)
corner.CornerRadius = UDim.new(0, 8)
ToggleBtn.MouseButton1Click:Connect(function()
    game:GetService("VirtualInputManager"):SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
    task.wait(0.1)
    game:GetService("VirtualInputManager"):SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
end)
if gethui then MobileGui.Parent = gethui() else MobileGui.Parent = coreGui end
Tabs.Settings:AddToggle("MobileToggleBtn", {Title = "Nút Mở UI (Cho Mobile)", Default = appConfig.MobileToggle}):OnChanged(function(v)
    appConfig.MobileToggle = v
    MobileGui.Enabled = v
    saveConfig()
end)
MobileGui.Enabled = appConfig.MobileToggle or false
SetFixLagEnabled(appConfig.fixLagEnabled)
task.wait()
Tabs.Webhook:AddParagraph({ Title = "Discord Webhook", Content = "Nhận thông báo khi quay ra Unit xịn hoặc khi đi xong Map." })
Tabs.Webhook:AddInput("WebhookUrl", {
    Title = "Discord Webhook URL",
    Default = appConfig.WebhookUrl,
    Placeholder = "https://discord.com/api/webhooks/...",
    Numeric = false,
    Finished = false,
    Callback = function(v)
        appConfig.WebhookUrl = v
        saveConfig()
    end
})
Tabs.Webhook:AddToggle("WebhookSummon", {Title = "Thông báo khi mở ra Mythic/Secret", Default = appConfig.webhookSummonEnabled}):OnChanged(function(v)
    appConfig.webhookSummonEnabled = v
    saveConfig()
end)
Tabs.Webhook:AddToggle("WebhookWin", {Title = "Thông báo tổng kết khi Thắng Map", Default = appConfig.webhookWinEnabled}):OnChanged(function(v)
    appConfig.webhookWinEnabled = v
    saveConfig()
end)
local function snapshotItemData()
    local ok, playerData = pcall(function() return Fusion.peek(Dependencies.PlayerData) end)
    if not ok or type(playerData) ~= "table" then return {} end
    local itemData = playerData.ItemData or {}
    local snap = {}
    for k, v in pairs(itemData) do
        local val = Fusion.peek(v)
        local rawAmount = type(val) == "table" and tonumber(Fusion.peek(val.Amount)) or tonumber(val) or 0
        snap[k] = math.floor(rawAmount + 0.5)
    end
    return snap
end
local function snapshotUnitData()
    local ok, playerData = pcall(function() return Fusion.peek(Dependencies.PlayerData) end)
    if not ok or type(playerData) ~= "table" then return {} end
    local unitData = playerData.UnitData or {}
    local snap = {}
    for uid, u in pairs(unitData) do
        local uTable = Fusion.peek(u)
        if type(uTable) == "table" then
            snap[uid] = {
                EXP = tonumber(Fusion.peek(uTable.EXP)) or 0,
                Level = tonumber(Fusion.peek(uTable.Level)) or 0,
                Asset = tostring(Fusion.peek(uTable.Asset))
            }
        end
    end
    return snap
end
local function snapshotEquipmentData()
    local ok, playerData = pcall(function() return Fusion.peek(Dependencies.PlayerData) end)
    if not ok or type(playerData) ~= "table" then return {} end
    local eqData = playerData.EquipmentData or {}
    local snap = {}
    for uid, e in pairs(eqData) do
        local eTable = Fusion.peek(e)
        if type(eTable) == "table" then
            local asset = Fusion.peek(eTable.Asset)
            snap[uid] = (asset and tostring(asset)) or uid:match("^(.-)#") or "Equipment"
        end
    end
    return snap
end
getgenv().StartItemData = getgenv().StartItemData or snapshotItemData()
getgenv().StartUnitData = getgenv().StartUnitData or snapshotUnitData()
getgenv().StartEquipmentData = getgenv().StartEquipmentData or snapshotEquipmentData()
local itemsMeta = {
    ["Gem"] = {name = "Gem", id = 1526890712530948186},
    ["Gold"] = {name = "Gold", id = 1526890682130632735},
    ["StatLock"] = {name = "StatLock", id = 1526890650816221287},
    ["StatReroll"] = {name = "StatReroll", id = 1526890740817334282},
    ["TraitReroll"] = {name = "TraitReroll", id = 1526890601558310973},
    ["RaidTicket"] = {name = "RaidTicket", id = 1526890650816221287},
    ["DungeonTicket"] = {name = "DungeonTicket", id = 1526890650816221287},
}
local function getEmoji(key)
    local meta = itemsMeta[key]
    if meta then return string.format("<:%s:%d>", meta.name:lower(), meta.id) end
    return ""
end
local function formatNumber(amount)
    local sign = amount < 0 and "-" or ""
    local formatted = tostring(math.floor(math.abs(amount)))
    local result, k = formatted:reverse():gsub("(%d%d%d)", "%1,")
    return sign .. result:reverse():gsub("^,", "")
end
local function chunkLines(lines)
    local chunks = {}
    local currentChunk = ""
    for _, line in ipairs(lines) do
        if #currentChunk + #line + 1 > 1024 then
            table.insert(chunks, currentChunk)
            currentChunk = line
        else
            currentChunk = currentChunk == "" and line or (currentChunk .. "\n" .. line)
        end
    end
    if currentChunk ~= "" then table.insert(chunks, currentChunk) end
    return chunks
end
local fallbackGameIconUrl = "https://tr.rbxcdn.com/180DAY-eeaa105a1844ec3811a2368a362736ec/256/256/Image/Png/noFilter"
local function buildMatchStatsEmbed(matchState, isTestMode, customResult, oldItemData, oldUnitData, oldEquipmentData)
    local newItemData = snapshotItemData()
    local newUnitData = snapshotUnitData()
    local newEquipmentData = snapshotEquipmentData()
    local inventoryLines = {}
    local itemLines = {}
    local unitLines = {}
    local trackedItems = {
        { key = "Gem", emoji = "<:gem:1526890712530948186>", label = "Gems" },
        { key = "Gold", emoji = "<:gold:1526890682130632735>", label = "Gold" },
        { key = "StatLock", emoji = "<:statlock:1526890650816221287>", label = "Stat Lock" },
        { key = "StatReroll", emoji = "<:statreroll:1526890740817334282>", label = "Stat Reroll" },
        { key = "TraitReroll", emoji = "<:traitcrystal:1526890601558310973>", label = "Trait Crystal" }
    }
    local trackedKeys = {}
    for _, item in ipairs(trackedItems) do
        trackedKeys[item.key] = true
        local amount = newItemData[item.key] or 0
        local oldAmt = (oldItemData or {})[item.key] or 0
        local diff = amount - oldAmt
        if not isTestMode and diff > 0 then
            table.insert(inventoryLines, string.format("%s **%s:** %s + %s", item.emoji, item.label, formatNumber(oldAmt), formatNumber(diff)))
        else
            table.insert(inventoryLines, string.format("%s **%s:** %s", item.emoji, item.label, formatNumber(amount)))
        end
    end
    if isTestMode then
        table.insert(itemLines, "📦 **TestItem:** +1,000")
        table.insert(itemLines, "🗡️ **TestEquipment:** +1")
        table.insert(unitLines, "🌟 **TestUnit** (Lvl 99): +500 EXP *(Total: 10,000)*")
    else
        oldItemData = oldItemData or getgenv().StartItemData or {}
        local gainedItems = {}
        for k, amt in pairs(newItemData) do
            if not trackedKeys[k] then
                local oldAmt = oldItemData[k] or 0
                if amt > oldAmt then
                    table.insert(gainedItems, {key = k, amount = amt - oldAmt})
                end
            end
        end
        for _, item in ipairs(gainedItems) do
            local emoji = getEmoji(item.key)
            if emoji == "" then emoji = "📦" end
            table.insert(itemLines, string.format("%s **%s:** +%s", emoji, item.key, formatNumber(item.amount)))
        end
        oldEquipmentData = oldEquipmentData or getgenv().StartEquipmentData or {}
        local equipCounts = {}
        for uid, name in pairs(newEquipmentData) do
            if not oldEquipmentData[uid] then
                equipCounts[name] = (equipCounts[name] or 0) + 1
            end
        end
        for name, count in pairs(equipCounts) do
            table.insert(itemLines, string.format("🗡️ **%s:** +%s", name, formatNumber(count)))
        end
        oldUnitData = oldUnitData or getgenv().StartUnitData or {}
        local gainedUnits = {}
        for uid, u in pairs(newUnitData) do
            local oldU = oldUnitData[uid]
            if oldU and u.EXP > oldU.EXP then
                table.insert(gainedUnits, {name = u.Asset or "Unknown", expGained = u.EXP - oldU.EXP, level = u.Level, currentExp = u.EXP})
            end
        end
        for _, u in ipairs(gainedUnits) do
            table.insert(unitLines, string.format("🌟 **%s** (Lvl %d): +%s EXP *(Total: %s)*", u.name, u.level, formatNumber(u.expGained), formatNumber(u.currentExp)))
        end
    end
    if #itemLines == 0 then table.insert(itemLines, "*Không nhận được Item nào*") end
    if #unitLines == 0 then table.insert(unitLines, "*Không có Unit nào nhận EXP*") end
    local minutes = math.floor((matchState.GameTime or 0) / 60)
    local seconds = (matchState.GameTime or 0) % 60
    local fields = {}
    table.insert(fields, { name = "⏱️ Clear Time", value = string.format("%dm, %ds", minutes, seconds), inline = true })
    table.insert(fields, { name = "☠️ Total Kills", value = formatNumber(matchState.TotalKills or 0), inline = true })
    table.insert(fields, { name = "⚔️ Total Damage", value = formatNumber(matchState.TotalDamage or 0), inline = true })
    local invChunks = chunkLines(inventoryLines)
    for i, chunk in ipairs(invChunks) do
        table.insert(fields, { name = (i == 1) and "🎒 Resources" or "🎒 Resources (Cont.)", value = chunk, inline = false })
    end
    local itemChunks = chunkLines(itemLines)
    for i, chunk in ipairs(itemChunks) do
        table.insert(fields, { name = (i == 1) and "🎁 Gained Rewards" or "🎁 Gained Rewards (Cont.)", value = chunk, inline = false })
    end
    local unitChunks = chunkLines(unitLines)
    for i, chunk in ipairs(unitChunks) do
        table.insert(fields, { name = (i == 1) and "✨ Unit EXP" or "✨ Unit EXP (Cont.)", value = chunk, inline = false })
    end
    local matchResult = isTestMode and "Test Match" or customResult
    local isInfinite = matchState.Gamemode and string.find(matchState.Gamemode:lower(), "infinite") ~= nil
    local embedColor = isInfinite and 0x9B59B6 or 0xF2C94C
    local titlePrefix = ""
    if isInfinite then
        titlePrefix = "[Infinite - Wave " .. tostring(matchState.Wave or 0) .. "] "
    else
        titlePrefix = "[" .. tostring(matchState.Gamemode or "Story") .. "] "
    end
    return {
        username = "Anime Expeditions Auto",
        embeds = {
            {
                author = { name = "Anime Expedition", icon_url = fallbackGameIconUrl },
                title = titlePrefix .. "||" .. (game.Players.LocalPlayer and game.Players.LocalPlayer.Name or "Player") .. "|| - " .. tostring(matchResult),
                color = embedColor,
                thumbnail = { url = fallbackGameIconUrl },
                fields = fields,
            },
        },
    }
end
local function sendWebhook(payload)
    local webhookUrl = tostring(appConfig.WebhookUrl or "")
    if webhookUrl == "" then
        return false, "Webhook URL trống!"
    end
    local ok, resp = pcall(function()
        local req = (syn and syn.request) or request or http_request
        return req({
            Url = webhookUrl,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode(payload),
        })
    end)
    if not ok then return false, "Lỗi HTTP Request" end
    if resp.StatusCode >= 200 and resp.StatusCode < 300 then
        return true, "Gửi Discord thành công!"
    else
        return false, "Discord từ chối (Mã " .. tostring(resp.StatusCode) .. ")"
    end
end
Tabs.Webhook:AddButton({
    Title = "Test Webhook Thắng Map",
    Description = "Gửi thử Webhook với data giả lập",
    Callback = function()
        local mockState = {
            CurrentGameState = "Test",
            BaseHealth = 15,
            GameTime = 300,
            TotalKills = 100,
            TotalDamage = 50000,
        }
        local ok, result = pcall(function() return buildMatchStatsEmbed(mockState, true, "Test Match") end)
        if ok then
            local success, msg = sendWebhook(result)
            if success then
                Fluent:Notify({Title = "Webhook", Content = msg, Duration = 5})
            else
                Fluent:Notify({Title = "Lỗi Gửi Discord", Content = msg, Duration = 7})
            end
        else
            Fluent:Notify({Title = "Lỗi Build Embed", Content = tostring(result), Duration = 7})
        end
    end,
})
local function postSummonWebhook(unitName, rarity)
    local webhookUrl = appConfig.WebhookUrl
    if not webhookUrl or webhookUrl == "" then return end
    local data = {
        username = "Anime Expeditions Auto",
        embeds = {
            {
                title = "🎉 Tự Động Triệu Hồi Thành Công!",
                description = "Tài khoản **" .. game.Players.LocalPlayer.Name .. "** vừa quay ra Unit xịn!",
                color = 16766720,
                fields = {
                    { name = "Unit", value = unitName, inline = true },
                    { name = "Độ Hiếm", value = rarity, inline = true }
                }
            }
        }
    }
    pcall(function()
        local req = (syn and syn.request) or request or http_request
        if req then
            req({
                Url = webhookUrl,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = game:GetService("HttpService"):JSONEncode(data)
            })
        end
    end)
end
local lastUnitIds = nil
local function checkNewSummonedUnits()
    local ok, playerData = pcall(function() return Fusion.peek(Dependencies.PlayerData) end)
    if not ok or type(playerData) ~= "table" then return end
    local unitData = playerData.UnitData or {}
    if not lastUnitIds then
        lastUnitIds = {}
        for uid, _ in pairs(unitData) do
            lastUnitIds[uid] = true
        end
        return
    end
    local newUnits = {}
    for uid, u in pairs(unitData) do
        if not lastUnitIds[uid] then
            lastUnitIds[uid] = true
            local uTable = Fusion.peek(u)
            if type(uTable) == "table" then
                local assetId = tostring(Fusion.peek(uTable.Asset))
                table.insert(newUnits, assetId)
            end
        end
    end
    if #newUnits > 0 and appConfig.WebhookUrl ~= "" and appConfig.webhookSummonEnabled then
        local bannerData = Fusion.peek(Dependencies.BannerData)
        for _, assetId in ipairs(newUnits) do
            local rarityName = "Unknown"
            if bannerData then
                for _, bData in pairs(bannerData) do
                    if type(bData) == "table" and bData.CurrentPool then
                        for rar, unitsList in pairs(bData.CurrentPool) do
                            for _, u in ipairs(unitsList) do
                                if tostring(u.Asset) == assetId then
                                    rarityName = rar
                                    break
                                end
                            end
                            if rarityName ~= "Unknown" then break end
                        end
                    end
                    if rarityName ~= "Unknown" then break end
                end
            end
            if rarityName == "Mythic" or rarityName == "Secret" then
                local uInfo = UnitsInfo[assetId]
                local displayName = (uInfo and (uInfo.Name or uInfo.DisplayName)) or assetId
                postSummonWebhook(displayName, rarityName)
            end
        end
    end
end
local isInitialLoad = true
task.delay(2, function() isInitialLoad = false end)
local function getActiveTargetBanner()
    if #appConfig.autoSummonBanners == 0 or #appConfig.autoSummonUnits == 0 then return nil end
    local bannerData = Fusion.peek(Dependencies.BannerData)
    if not bannerData then return nil end
    local targetUnits = {}
    for _, assetId in ipairs(appConfig.autoSummonUnits) do
        targetUnits[tostring(assetId)] = true
    end
    for _, bName in ipairs(appConfig.autoSummonBanners) do
        local pool = bannerData[bName] and bannerData[bName].CurrentPool
        if pool then
            for rarity, units in pairs(pool) do
                if rarity == "Mythic" or rarity == "Secret" then
                    for _, uData in ipairs(units) do
                        local assetName = tostring(uData.Asset)
                        if targetUnits[assetName] then
                            return bName
                        end
                    end
                end
            end
        end
    end
    return nil
end
local lastHasRunMacro = false
local lastStateInfo = nil
local lastSentTime = 0
task.spawn(function()
    while task.wait(1) do
        pcall(checkNewSummonedUnits)
        local stateInfo = getGameStates()
        if appConfig.hidePlayerNames then
            pcall(function()
                local pg = game.Players.LocalPlayer:FindFirstChild("PlayerGui")
                if pg and pg:FindFirstChild("PlayerOverhead") then pg.PlayerOverhead.Enabled = false end
                if pg and pg:FindFirstChild("NpcOverhead") then pg.NpcOverhead.Enabled = false end
                for _, player in ipairs(game.Players:GetPlayers()) do
                    if player ~= game.Players.LocalPlayer and player.Character and player.Character:FindFirstChild("Head") then
                        for _, v in ipairs(player.Character.Head:GetChildren()) do
                            if v:IsA("BillboardGui") then v.Enabled = false end
                        end
                    end
                end
            end)
        end
        if stateInfo then
            local skey = getCurrentStageKey(stateInfo)
            local macroList = getMacroListForStage(skey)
            local macroCount = macroList and #macroList or 0
            currentMacroPara:SetDesc("Đang ở: " .. skey .. "\nSố lệnh Macro đã lưu: " .. macroCount)
        else
            currentMacroPara:SetDesc("Đang ở Lobby...")
            lastHasRunMacro = false
            isPlaying = false
        end
        if stateInfo and lastStateInfo and stateInfo.Wave == 1 and lastStateInfo.Wave > 1 then
            lastHasRunMacro = false
            isPlaying = false
        end
        if not stateInfo then
            if appConfig.autoClaimQuests then
                pcall(function() Actions.ClaimAllQuests() end)
                pcall(function()
                    local categories = {}
                    for _, eventData in pairs(EventsInfo) do
                        if type(eventData) == "table" and type(eventData.QuestCategories) == "table" then
                            for _, cat in ipairs(eventData.QuestCategories) do table.insert(categories, cat) end
                        end
                    end
                    if #categories > 0 then Actions.ClaimQuestCategories(categories) end
                end)
            end
            if appConfig.autoClaimBP then pcall(function() Actions.ClaimAllBattlepassRewards(BattlepassInfo.CurrentSeason or "Season1") end) end
            if appConfig.autoClaimCalendar then
                pcall(function()
                    for _, calId in pairs({"DailyRewards", "ReleaseCalendar"}) do
                        for day = 1, 30 do Actions.ClaimCalendarReward(calId, day) end
                    end
                end)
            end
            if appConfig.autoClaimMilestones then
                pcall(function()
                    for level = 1, 100 do Actions.ClaimLevelMilestone(level) end
                end)
            end
            for storeId, products in pairs(appConfig.ShopSelections) do
                for _, productId in ipairs(products) do
                    pcall(function() Actions.StorePurchaseProduct(storeId, productId, 1) end)
                end
            end
            if appConfig.autoSummonEnabled then
                local targetBanner = getActiveTargetBanner()
                if targetBanner then
                    pcall(function() Actions.Summon(targetBanner, appConfig.autoSummonAmount) end)
                    task.wait(1)
                end
            end
            if appConfig.autoCraftEnabled and #appConfig.autoCraftItems > 0 then
                for _, recipe in ipairs(appConfig.autoCraftItems) do
                    pcall(function() Actions.CraftRecipe(recipe, 1) end)
                end
            end
            local function ClickGuiObject(guiObject)
                if not guiObject then return false end
                local vim = game:GetService("VirtualInputManager")
                local absPos = guiObject.AbsolutePosition
                local absSize = guiObject.AbsoluteSize
                local inset = game:GetService("GuiService"):GetGuiInset()
                local cx = absPos.X + (absSize.X / 2)
                local cy = absPos.Y + (absSize.Y / 2) + inset.Y
                vim:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
                task.wait(0.05)
                vim:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
                return true
            end
            local function ClickButtonByText(targetText)
                local gui = game:GetService("Players").LocalPlayer.PlayerGui
                local btn = nil
                for _, v in pairs(gui:GetDescendants()) do
                    if v:IsA("TextLabel") or v:IsA("TextButton") then
                        if type(v.Text) == "string" and v.Text:lower():find(targetText:lower()) and not v.Text:lower():find("force") then
                            local isVisible = true
                            local p = v.Parent
                            while p and p:IsA("GuiObject") do
                                if not p.Visible then isVisible = false break end
                                p = p.Parent
                            end
                            if isVisible then
                                local p2 = v
                                while p2 and not p2:IsA("TextButton") and not p2:IsA("ImageButton") do
                                    p2 = p2.Parent
                                end
                                if p2 then
                                    btn = p2
                                    break
                                end
                            end
                        end
                    end
                end
                if btn then
                    return ClickGuiObject(btn)
                end
                return false
            end
            local function WaitAndClickButtonByText(targetText, timeout)
                local deadline = tick() + (timeout or 3)
                repeat
                    if ClickButtonByText(targetText) then
                        return true
                    end
                    task.wait(0.25)
                until tick() >= deadline
                return false
            end
            local function ClickLobbyPlayButton()
                local gui = game:GetService("Players").LocalPlayer.PlayerGui
                local leftHUD = gui:FindFirstChild("LeftHUD")
                if leftHUD then
                    for _, v in ipairs(leftHUD:GetDescendants()) do
                        if (v:IsA("TextLabel") or v:IsA("TextButton")) and type(v.Text) == "string" and v.Text:lower() == "play" then
                            local isVisible = true
                            local p = v.Parent
                            while p and p:IsA("GuiObject") do
                                if not p.Visible then isVisible = false break end
                                p = p.Parent
                            end
                            if isVisible then
                                local button = v
                                while button and not button:IsA("TextButton") and not button:IsA("ImageButton") do
                                    button = button.Parent
                                end
                                if button then
                                    return ClickGuiObject(button)
                                end
                            end
                        end
                    end
                end
                return false
            end
            local function ClickPartyStartButton()
                local gui = game:GetService("Players").LocalPlayer.PlayerGui
                local playGui = gui:FindFirstChild("Play")
                if playGui then
                    for _, v in ipairs(playGui:GetDescendants()) do
                        if (v:IsA("TextLabel") or v:IsA("TextButton")) and type(v.Text) == "string" and v.Text:lower() == "start" then
                            local isVisible = true
                            local p = v.Parent
                            while p and p:IsA("GuiObject") do
                                if not p.Visible then isVisible = false break end
                                p = p.Parent
                            end
                            if isVisible then
                                local button = v
                                while button and not button:IsA("TextButton") and not button:IsA("ImageButton") do
                                    button = button.Parent
                                end
                                if button then
                                    return ClickGuiObject(button)
                                end
                            end
                        end
                    end
                end
                return false
            end
            local function ClickScreenCenter()
                local camera = workspace.CurrentCamera
                if not camera then return false end
                local vim = game:GetService("VirtualInputManager")
                local viewport = camera.ViewportSize
                local inset = game:GetService("GuiService"):GetGuiInset()
                local cx = viewport.X / 2
                local cy = viewport.Y / 2 + inset.Y
                vim:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
                task.wait(0.05)
                vim:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
                return true
            end
            local function WaitAndDismissPopupsForStart(timeout)
                local deadline = tick() + (timeout or 10)
                repeat
                    if ClickPartyStartButton() or WaitAndClickButtonByText("Start", 1) then
                        return true
                    end
                    ClickScreenCenter()
                    task.wait(0.5)
                until tick() >= deadline
                return ClickPartyStartButton() or WaitAndClickButtonByText("Start", 1)
            end
            local function FindVisibleMatchmakingCancelButton()
                local gui = game:GetService("Players").LocalPlayer.PlayerGui
                local notifications = gui:FindFirstChild("PriorityNotifications")
                if not notifications then return nil end
                for _, v in ipairs(notifications:GetDescendants()) do
                    if v:IsA("TextLabel") and v.Visible and type(v.Text) == "string" and string.find(v.Text:lower(), "matchmaking", 1, true) then
                        local container = v.Parent
                        while container and container ~= notifications do
                            local primaryButton = container:FindFirstChild("PrimaryButton", true)
                            if primaryButton and (primaryButton:IsA("TextButton") or primaryButton:IsA("ImageButton") or primaryButton:IsA("Frame")) then
                                return primaryButton
                            end
                            container = container.Parent
                        end
                    end
                end
                return nil
            end
            local function AutoStartMatchmaking(levelData)
                local ok, err = pcall(function()
                    Actions.StartMatchmaking(levelData)
                end)
                if ok then
                    print("[AUTO JOIN] StartMatchmaking OK:", levelData.Gamemode, levelData.MapName, levelData.ActName or "")
                    return true
                end
                warn("[AUTO JOIN] StartMatchmaking lỗi:", err)
                return false
            end
            local function WaitForMatchmakingBannerToDisappear(timeout)
                local deadline = tick() + (timeout or 8)
                local wasVisible = false
                repeat
                    local btnX = FindVisibleMatchmakingCancelButton()
                    if btnX then
                        wasVisible = true
                        ClickGuiObject(btnX)
                        task.wait(0.75)
                    else
                        if wasVisible then
                            return true
                        end
                        task.wait(0.25)
                    end
                until tick() >= deadline
                return FindVisibleMatchmakingCancelButton() == nil
            end
            if appConfig.autoJoinEnabled and appConfig.AutoJoin ~= "" then
                local parts = string.split(appConfig.AutoJoin, "|")
                if #parts >= 2 then
                    local levelData = {}
                    if parts[1] == "Challenge" then
                        levelData = {
                            Gamemode = "Challenge",
                            ChallengeType = parts[2],
                            ChallengeIndex = tonumber(parts[3]) or 1
                        }
                    else
                        levelData = {
                            Gamemode = parts[1],
                            MapName = parts[2],
                            ActName = parts[3] or ""
                        }
                        if levelData.ActName ~= "" and not string.find(levelData.ActName, "Act") then
                            levelData.ActName = "Act " .. levelData.ActName
                        end
                        if parts[1] == "Infinite" or parts[1] == "Mastery" then
                            levelData.Difficulty = "Hard"
                        end
                    end
                    if parts[2] then
                        local mapToClick = parts[2]
                        if parts[1] and string.lower(parts[1]) == "infinite" then
                            mapToClick = "Infinite " .. parts[2]
                        end
                        print("[AUTO JOIN] Bấm Map:", mapToClick)
                        ClickButtonByText(mapToClick)
                        task.wait(0.5)
                    end
                    if parts[3] and parts[3] ~= "" then
                        local actStr = parts[3]
                        if not string.find(actStr, "Act") then actStr = "Act " .. actStr end
                        print("[AUTO JOIN] Bấm Ải:", actStr)
                        ClickButtonByText(actStr)
                        task.wait(0.5)
                    end
                    if appConfig.autoJoinTeamEnabled and appConfig.TeamSelections[parts[2]] then
                        pcall(function() Actions.LoadUnitTeam(tostring(appConfig.TeamSelections[parts[2]])) end)
                        task.wait(1)
                    end
                    AutoStartMatchmaking(levelData)
                    if appConfig.autoJoinMode ~= "Matchmaking (Multiplayer)" then
                        task.wait(0.1)
                        pcall(function() Actions.CancelMatchmaking() end)
                        task.wait(0.5)
                        print("[AUTO JOIN] Đã hủy Matchmaking bằng lệnh hệ thống! Bắt đầu bấm Play -> Start...")
                        local findDeadline = tick() + 15
                        local isPlayClicked = false
                        repeat
                            if not isPlayClicked then
                                if ClickLobbyPlayButton() then
                                    isPlayClicked = true
                                    task.wait(0.5)
                                else
                                    ClickScreenCenter()
                                    task.wait(0.5)
                                end
                            end
                        until isPlayClicked or tick() >= findDeadline
                        if isPlayClicked then
                            print("[AUTO JOIN] Đã ấn PLAY, đợi 3 giây...")
                            task.wait(3)
                            print("[AUTO JOIN] Bắt đầu tìm START...")
                            local startDeadline = tick() + 20
                            local isStartClicked = false
                            repeat
                                if ClickPartyStartButton() then
                                    isStartClicked = true
                                    break
                                else
                                    ClickScreenCenter()
                                    task.wait(0.5)
                                end
                            until tick() >= startDeadline
                            if isStartClicked then
                                print("[AUTO JOIN] Đã ấn START thành công! Chờ teleport...")
                                task.wait(5)
                            else
                                print("[AUTO JOIN] Lỗi: Không tìm thấy nút START!")
                            end
                        else
                            print("[AUTO JOIN] Lỗi: Không thể hoàn thành chuỗi X và PLAY!")
                        end
                        task.wait(2)
                    else
                        task.wait(2)
                    end
                end
            end
        else
            if appConfig.autoJoinMode == "Start Instantly (Solo)" and stateInfo.CurrentGameState ~= "Lobby" and stateInfo.CurrentGameState ~= "Finished" then
                if #game:GetService("Players"):GetPlayers() > 1 then
                    local lastAutoReturnTrigger = getgenv().lastAutoReturnTrigger or 0
                    if tick() - lastAutoReturnTrigger > 5 then
                        getgenv().lastAutoReturnTrigger = tick()
                        stateInfo.CurrentGameState = "Finished"
                        Fluent:Notify({Title = "Phòng Lỗi", Content = "Phát hiện có người khác trong phòng Solo! Đang tự động thoát...", Duration = 5})
                        pcall(function() Actions.GameReturnLobby() end)
                    end
                end
            end
            if appConfig.autoLeaveOnDefeat and stateInfo.CurrentGameState == "Finished" then
                if stateInfo.BaseHealth <= 0 then
                    local lastAutoReturnTrigger = getgenv().lastAutoReturnTrigger or 0
                    if tick() - lastAutoReturnTrigger > 5 then
                        getgenv().lastAutoReturnTrigger = tick()
                        Fluent:Notify({Title = "Auto Leave", Content = "Phát hiện thua cuộc! Đang tự động vứt trận về Lobby...", Duration = 5})
                        pcall(function() Actions.GameReturnLobby() end)
                    end
                end
            end
            if appConfig.autoLeaveSpriteMax and stateInfo.CurrentGameState ~= "Lobby" and stateInfo.CurrentGameState ~= "Finished" then
                local currentSprites = snapshotItemData()["SpriteGrey"] or 0
                if currentSprites >= 125 then
                    local lastAutoReturnTrigger = getgenv().lastAutoReturnTrigger or 0
                    if tick() - lastAutoReturnTrigger > 5 then
                        getgenv().lastAutoReturnTrigger = tick()
                        stateInfo.CurrentGameState = "Finished"
                        Fluent:Notify({Title = "Auto Leave", Content = "Đã đầy 125 Sprite (Grey). Đang tự động về sảnh!", Duration = 5})
                        pcall(function() Actions.GameReturnLobby() end)
                    end
                end
            end
            if appConfig.autoRestartInf and isInfiniteGamemode(stateInfo.Gamemode) then
                if stateInfo.Wave >= appConfig.restartWaveNum and stateInfo.CurrentGameState ~= "Lobby" then
                    local lastAutoRestartTrigger = getgenv().lastAutoRestartTrigger or 0
                    if tick() - lastAutoRestartTrigger > 15 then
                        getgenv().lastAutoRestartTrigger = tick()
                        getgenv().WasAutoRestarted = true
                        stateInfo.CurrentGameState = "Finished"
                        pcall(function() ReplicatedStorage.RemoteEvents.ReplicaSignal:FireServer(59, "Restart") end)
                    end
                end
            end
            if appConfig.autoPlayEnabled and not isPlaying and not lastHasRunMacro then
                if stateInfo.Wave == 1 then
                    local skey = getCurrentStageKey(stateInfo)
                    local macroList, matchedMacroKey = getMacroListForStage(skey)
                    if macroList and #macroList > 0 then
                        isPlaying = true
                        lastHasRunMacro = true
                        Fluent:Notify({Title = "Macro", Content = "Đã tìm thấy thư viện Macro cho ["..matchedMacroKey.."]. Đang bắt đầu tự động xây!", Duration = 5})
                        task.spawn(function()
                            local playStart = tick()
                            for _, action in ipairs(macroList) do
                                if not isPlaying or not appConfig.autoPlayEnabled then break end
                                while (tick() - playStart) < action.time do
                                    task.wait(0.01)
                                    if not isPlaying or not appConfig.autoPlayEnabled then break end
                                end
                                if not isPlaying or not appConfig.autoPlayEnabled then break end
                                local Event = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ReplicaSignal")
                                local gamePlayerDataId, hotbarDataId
                                for _, v in pairs(getgc(true)) do
                                    if type(v) == "table" and rawget(v, "Id") and type(rawget(v, "Token")) == "string" then
                                        if v.Token == "GamePlayerData" then
                                            if not gamePlayerDataId or v.Id > gamePlayerDataId then gamePlayerDataId = v.Id end
                                        elseif v.Token == "HotbarData" then
                                            if not hotbarDataId or v.Id > hotbarDataId then hotbarDataId = v.Id end
                                        end
                                    end
                                end
                                local pId = gamePlayerDataId or 64
                                local hId = hotbarDataId or 65
                                if action.type == "Select" then Event:FireServer(hId, "SelectSlot", action.slot)
                                elseif action.type == "Place" then Event:FireServer(pId, "PlaceGameUnit", action.slot, CFrame.new(unpack(action.pos)))
                                elseif action.type == "Upgrade" or action.type == "Sell" then
                                    local uId = action.unitId
                                    if action.pos then
                                        local targetPos = Vector3.new(action.pos[1], action.pos[2], action.pos[3])
                                        local closestDist = 5
                                        for _, v in pairs(workspace:GetDescendants()) do
                                            if v:IsA("Model") and not v:GetAttribute("EnemyID") then
                                                local part = v.PrimaryPart or v:FindFirstChild("HumanoidRootPart")
                                                if part then
                                                    local dist = (part.Position - targetPos).Magnitude
                                                    if dist < closestDist then
                                                        closestDist = dist
                                                        local realId = nil
                                                        local tStart = tick()
                                                        local function checkTable(obj)
                                                            for tk, tv in pairs(obj) do
                                                                if tv == v and type(tk) == "string" and tonumber(tk) then return tk end
                                                                if tk == v and type(tv) == "string" and tonumber(tv) then return tv end
                                                                if type(tv) == "table" and type(tk) == "string" and tonumber(tk) then
                                                                    if tv.Model == v or tv.Instance == v or tv.Unit == v or tv.Character == v then return tk end
                                                                end
                                                            end
                                                            return nil
                                                        end
                                                        if CachedUnitGCMap then
                                                            realId = checkTable(CachedUnitGCMap)
                                                        end
                                                        if not realId then
                                                            for _, obj in pairs(getgc(true)) do
                                                                if type(obj) == "table" then
                                                                    realId = checkTable(obj)
                                                                    if realId then
                                                                        CachedUnitGCMap = obj
                                                                        break
                                                                    end
                                                                end
                                                            end
                                                        end
                                                        print("[Anti-Lag] Playback Scan took " .. string.format("%.5f", tick() - tStart) .. "s")
                                                        uId = realId or (type(action.unitId) == "string" and v.Name or v)
                                                    end
                                                end
                                            end
                                        end
                                    end
                                    if action.type == "Upgrade" then Event:FireServer(pId, "UpgradeGameUnit", uId)
                                    else Event:FireServer(pId, "SellGameUnit", uId) end
                                end
                            end
                            Fluent:Notify({Title = "Macro", Content = "Hoàn tất kịch bản Macro!", Duration = 3})
                            isPlaying = false
                        end)
                    end
                end
            end
            if stateInfo.Wave == 0 or stateInfo.CurrentGameState == "Finished" then
                lastHasRunMacro = false
                isPlaying = false
            end
            local isEndMatch = false
            local resultStatus = "Finished"
            local isInfinite = isInfiniteGamemode(stateInfo.Gamemode) or (lastStateInfo and isInfiniteGamemode(lastStateInfo.Gamemode))
            if stateInfo.CurrentGameState == "Finished" or stateInfo.CurrentGameState == "Victory" or stateInfo.CurrentGameState == "Defeat" then
                isEndMatch = true
                resultStatus = stateInfo.BaseHealth > 0 and "Victory" or "Defeat"
                if getgenv().WasAutoRestarted then resultStatus = "Victory"; getgenv().WasAutoRestarted = false end
            end
            if not isEndMatch and lastStateInfo and lastStateInfo.Wave > 0 and stateInfo.Wave == 0 then
                isEndMatch = true
                if lastStateInfo.Wave >= lastStateInfo.MaxWave or getgenv().WasAutoRestarted then
                    resultStatus = "Victory"
                else
                    resultStatus = "Defeat"
                end
                getgenv().WasAutoRestarted = false
            end
            if isEndMatch and appConfig.webhookWinEnabled and (tick() - lastSentTime > 15) then
                lastSentTime = tick()
                getgenv().HasRunMacroThisMatch = false
                local capturedOldItemData = getgenv().StartItemData or {}
                local capturedOldUnitData = getgenv().StartUnitData or {}
                local capturedOldEquipmentData = getgenv().StartEquipmentData or {}
                local statsToUse = stateInfo
                if stateInfo.Wave == 0 and lastStateInfo then
                    statsToUse = lastStateInfo
                end
                isPlaying = false
                if appConfig.autoPlayEnabled then
                    task.spawn(function()
                        task.wait(8)
                        local vim = game:GetService("VirtualInputManager")
                        local gui = game:GetService("Players").LocalPlayer.PlayerGui
                        local function clickBtn(txt)
                            for _, v in pairs(gui:GetDescendants()) do
                                if (v:IsA("TextLabel") or v:IsA("TextButton")) and type(v.Text) == "string" and v.Text:lower():find(txt:lower()) and v.Visible then
                                    local p = v
                                    while p and not p:IsA("TextButton") and not p:IsA("ImageButton") do p = p.Parent end
                                    if p and p.Visible then
                                        local ax, ay = p.AbsolutePosition.X, p.AbsolutePosition.Y
                                        local sx, sy = p.AbsoluteSize.X, p.AbsoluteSize.Y
                                        local cx = ax + sx/2
                                        local cy = ay + sy/2 + game:GetService("GuiService"):GetGuiInset().Y
                                        vim:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
                                        task.wait(0.05)
                                        vim:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
                                        return true
                                    end
                                end
                            end
                            return false
                        end
                        print("[AUTO PLAY] Tìm nút Replay/Retry...")
                        local clicked = clickBtn("Replay") or clickBtn("Retry") or clickBtn("Play Again")
                    end)
                end
                Fluent:Notify({Title = "Match Ended", Content = "Đang lấy phần thưởng để gửi Discord...", Duration = 3})
                task.spawn(function()
                    task.wait(4)
                    local ok, result = pcall(function() return buildMatchStatsEmbed(statsToUse, false, resultStatus, capturedOldItemData, capturedOldUnitData, capturedOldEquipmentData) end)
                    pcall(function()
                        getgenv().StartItemData = snapshotItemData()
                        getgenv().StartUnitData = snapshotUnitData()
                        getgenv().StartEquipmentData = snapshotEquipmentData()
                    end)
                    if ok then
                        local gainedSomething = false
                        for _, field in ipairs(result.embeds[1].fields) do
                            if field.name:find("Gained Rewards") and not field.value:find("Không nhận được Item nào") then gainedSomething = true end
                            if field.name:find("Unit EXP") and not field.value:find("Không có Unit nào nhận EXP") then gainedSomething = true end
                        end
                        if gainedSomething or resultStatus ~= "Finished" then
                            local success, msg = sendWebhook(result)
                            if success then
                                Fluent:Notify({Title = "Webhook", Content = msg, Duration = 5})
                            else
                                Fluent:Notify({Title = "Lỗi Gửi Discord", Content = msg, Duration = 7})
                            end
                        else
                            Fluent:Notify({Title = "Webhook", Content = "Không có phần thưởng mới, bỏ qua gửi Discord.", Duration = 4})
                        end
                    else
                        Fluent:Notify({Title = "Lỗi Build Embed", Content = tostring(result), Duration = 7})
                    end
                end)
            end
        end
        lastStateInfo = stateInfo
    end
end)
logInit("Đang cài đặt Hook Bypass & Macro...")
local oldNamecall
local rawFireServer = Instance.new("RemoteEvent").FireServer
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local method = getnamecallmethod()
    local args = {...}
    if not checkcaller() and method == "FireServer" and typeof(self) == "Instance" and self.Name == "ReplicaSignal" then
        if isRecording then
            local action = args[2]
            local currentTime = tick() - startTime
            local mList = appConfig.Macros[currentStageKey]
            if action == "SelectSlot" then
                table.insert(mList, {time = currentTime, type = "Select", slot = args[3]})
            elseif action == "PlaceGameUnit" then
                local pArg
                for i = 3, #args do
                    if typeof(args[i]) == "CFrame" or typeof(args[i]) == "Vector3" then pArg = args[i]; break end
                end
                if pArg then
                    local p = typeof(pArg) == "CFrame" and {pArg:components()} or {pArg.X, pArg.Y, pArg.Z}
                    table.insert(mList, {time = currentTime, type = "Place", slot = args[3], pos = p})
                end
            elseif action == "UpgradeGameUnit" or action == "SellGameUnit" then
                local p
                local targetModel = nil
                local tStart = tick()
                if typeof(args[3]) == "Instance" then targetModel = args[3]
                elseif type(args[3]) == "string" then
                    local function checkTable(obj)
                        for tk, tv in pairs(obj) do
                            if tk == args[3] and typeof(tv) == "Instance" then return tv end
                            if tv == args[3] and typeof(tk) == "Instance" then return tk end
                            if tk == args[3] and type(tv) == "table" then
                                if typeof(tv.Model) == "Instance" then return tv.Model end
                                if typeof(tv.Instance) == "Instance" then return tv.Instance end
                                if typeof(tv.Unit) == "Instance" then return tv.Unit end
                                if typeof(tv.Character) == "Instance" then return tv.Character end
                            end
                        end
                        return nil
                    end
                    if CachedUnitGCMap then targetModel = checkTable(CachedUnitGCMap) end
                    if not targetModel then
                        for _, obj in pairs(getgc(true)) do
                            if type(obj) == "table" then
                                targetModel = checkTable(obj)
                                if targetModel then
                                    CachedUnitGCMap = obj
                                    break
                                end
                            end
                        end
                    end
                end
                print("[Anti-Lag] Hook Scan took " .. string.format("%.5f", tick() - tStart) .. "s")
                if not targetModel then
                    for _, v in pairs(workspace:GetDescendants()) do
                        if v.Name == tostring(args[3]) and v:IsA("Model") then targetModel = v; break end
                    end
                end
                if targetModel and targetModel:IsA("Model") then
                    local part = targetModel.PrimaryPart or targetModel:FindFirstChild("HumanoidRootPart")
                    if part then p = {part.Position.X, part.Position.Y, part.Position.Z} end
                end
                if action == "UpgradeGameUnit" then
                    table.insert(mList, {time = currentTime, type = "Upgrade", unitId = args[3], pos = p})
                else
                    table.insert(mList, {time = currentTime, type = "Sell", unitId = args[3], pos = p})
                end
            end
        end
        return rawFireServer(self, ...)
    end
    return oldNamecall(self, ...)
end))
logInit("Đang kích hoạt chặn UI Rác...")
pcall(function()
    game.Players.LocalPlayer.PlayerGui.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("TextLabel") then
            local function check()
                local t = descendant.Text
                if t:find("already claimed") or t:find("can't claim") or t:find("Milestones to claim") then
                    descendant.Visible = false
                    if descendant.Parent and descendant.Parent:IsA("Frame") then descendant.Parent.Visible = false end
                end
            end
            check()
            descendant:GetPropertyChangedSignal("Text"):Connect(check)
        end
    end)
end)
Window:SelectTab(1)
logInit("Hoàn tất nạp Script thành công!")
print(string.format("[AnimeExpeditionsUltimate] TỔNG THỜI GIAN KHỞI ĐỘNG: %.4fs", tick() - _initStartTime))
Fluent:Notify({Title = "AE", Content = "Load xong!", Duration = 5})
