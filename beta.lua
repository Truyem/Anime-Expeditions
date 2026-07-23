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
local function safeFireGameAction(actionName, ...)
    local Event = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteEvents")
    if not Event or not Event:FindFirstChild("ReplicaSignal") then return false end

    if actionName == "VoteStart" then
        warn("[AE-LOG] Scanning GC for VotePrompt ID for action: VoteStart")
        local promptId = nil
        for _, v in pairs(getgc(true)) do
            if type(v) == "table" and rawget(v, "Id") and type(rawget(v, "Token")) == "string" then
                if v.Token == "VotePrompt" then
                    promptId = v.Id
                    break
                end
            end
        end
        if promptId then
            Event.ReplicaSignal:FireServer(promptId, "Response", true)
            warn("[AE-LOG] Fired VoteStart (Response) with VotePrompt ID: " .. tostring(promptId))
            return true
        end
        warn("[AE-LOG] VotePrompt ID NOT FOUND!")
        return false
    end

    warn("[AE-LOG] Scanning GC for GameState ID for action: " .. actionName)
    local validId = nil
    for _, v in pairs(getgc(true)) do
        if type(v) == "table" and rawget(v, "Id") and type(rawget(v, "Token")) == "string" then
            if v.Token == "GameState" then
                validId = v.Id
                warn("[AE-LOG] Found GameState ID via GC: " .. tostring(validId))
                break
            end
        end
    end
    if validId then
        Event.ReplicaSignal:FireServer(validId, actionName, ...)
        warn("[AE-LOG] Fired " .. actionName .. " with ID: " .. tostring(validId))
        return true
    else
        warn("[AE-LOG] GameState ID NOT FOUND; skipped action: " .. actionName)
        return false
    end
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
        log("installed task.delay Kick protection")
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
-- Synthetic mouse input can switch Roblox's preferred input on phones. Keep only
-- the preferred-input read in Touch mode; desktop clients are left untouched.
do
    local inputService = game:GetService("UserInputService")
    local mobileInputState = getgenv().AnimeExpeditionsMobileInput or {}
    getgenv().AnimeExpeditionsMobileInput = mobileInputState
    if inputService.TouchEnabled and not mobileInputState.hooked
        and type(hookmetamethod) == "function" and type(newcclosure) == "function" then
        local oldIndex
        oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
            if self == inputService and key == "PreferredInput"
                and (type(checkcaller) ~= "function" or not checkcaller()) then
                return Enum.PreferredInput.Touch
            end
            return oldIndex(self, key)
        end))
        mobileInputState.hooked = true
        if type(getconnections) == "function" then
            for _, connection in ipairs(getconnections(inputService:GetPropertyChangedSignal("PreferredInput"))) do
                pcall(function() connection:Fire() end)
            end
        end
    end
end
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
    autoShopEnabled = false,
    ShopSelections = {},
    TeamSelections = {},
    Macros = {},
    autoRecordEnabled = false,
    autoPlayEnabled = false,
    autoVoteStart = false,
    autoRestartInf = false,
    restartWaveNum = 50,
    autoLeaveSpriteMax = false,
    autoLeaveOnDefeat = false,
    autoLeaveOnPlayerJoin = false,
    AntiAFK = true,
    MobileToggle = true,
    WebhookUrl = "",
    webhookWinEnabled = false,
    webhookSummonEnabled = true,
    autoClaimQuests = false,
    autoClaimBP = false,
    autoClaimCalendar = false,
    autoClaimMilestones = false,
    hidePlayerNames = false,
    fixLagEnabled = false,
    ExpeditionAuto = nil
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
    "autoRecordEnabled", "autoPlayEnabled", "autoVoteStart", "autoRestartInf", "restartWaveNum", "autoLeaveSpriteMax", "autoLeaveOnDefeat", "autoLeaveOnPlayerJoin", "AntiAFK", "MobileToggle", "WebhookUrl", "webhookWinEnabled", "webhookSummonEnabled", "ExpeditionAuto"
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
    getgenv().AnimeExpeditionsCleanLegacyIngameConfig = type(savedMacroBackup) == "table"
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
if getgenv().AnimeExpeditionsCleanLegacyIngameConfig then
    saveConfig()
    getgenv().AnimeExpeditionsCleanLegacyIngameConfig = nil
end
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
                local acts = {}
                if type(mapData.Acts) == "table" then
                    for actId, _ in pairs(mapData.Acts) do table.insert(acts, tostring(actId)) end
                end
                if mode == "Infinite" and #acts == 0 then table.insert(acts, "1") end
                local diffs = {}
                if type(mapData.Difficulties) == "table" then
                    for diffId, diffName in pairs(mapData.Difficulties) do
                        if type(diffName) == "string" then
                            table.insert(diffs, diffName)
                        else
                            table.insert(diffs, tostring(diffId))
                        end
                    end
                end
                if #diffs == 0 then table.insert(diffs, "") end
                for _, act in ipairs(acts) do
                    for _, diff in ipairs(diffs) do
                        if diff == "" then
                            table.insert(gamemodesMap[mode][mapId], act)
                        else
                            table.insert(gamemodesMap[mode][mapId], act .. " - " .. diff)
                        end
                    end
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
-- Expedition has one map selector plus a separate 1-3 difficulty selector.
-- Keep it out of the generic map dropdown and expose a dedicated combined list below.
local expeditionJoinOptions = {}
for mapId, mapData in pairs((MapInfo.MapData and MapInfo.MapData.Expedition) or {}) do
    local displayName = tostring(mapData.Name or mapData.DisplayName or mapId)
    displayName = displayName:gsub("Expedition$", ""):gsub("(%l)(%u)", "%1 %2")
    for difficulty = 1, 3 do
        table.insert(expeditionJoinOptions, {
            Label = displayName .. " - Difficulty " .. difficulty,
            MapId = mapId,
            Difficulty = difficulty,
        })
    end
end
table.sort(expeditionJoinOptions, function(left, right) return left.Label < right.Label end)
gamemodesMap["Expedition"] = nil
local cachedFallbackMapName = ""
local cachedFallbackActName = ""
local function getExpeditionMapProgress()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return nil end
    for _, object in ipairs(playerGui:GetDescendants()) do
        if object:IsA("TextLabel") and object.Visible then
            local current, total = object.Text:match("Map Progress%s+(%d+)%s*/%s*(%d+)")
            if current and total then return tonumber(current), tonumber(total) end
        end
    end
    return nil
end
local function isExpeditionItemTargeting()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return false end
    for _, object in ipairs(playerGui:GetDescendants()) do
        if object:IsA("TextLabel") and object.Visible and object.Text:match("^Apply .- Tome$") then
            return true
        end
    end
    return false
end
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
        local mapName = tostring(safePeek(params.Map) or safePeek(params.MapName) or "")
        local actName = tostring(safePeek(params.Act) or safePeek(params.ActName) or "")
        local difficulty = tonumber(safePeek(params.DifficultyLevel)) or safePeek(params.Difficulty) or ""
        local currentGameState = tostring(safePeek(state.CurrentGameState))
        if currentGameState == "Lobby" and (gamemode == "" or gamemode == "nil") then
            -- Tạm thời không xoá cache ở đây nữa để tránh Wave 0 bị xoá nhầm
        end
        if (mapName == "" or mapName == "nil") then
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
            Status = tostring(safePeek(state.Status) or ""),
            BaseHealth = tonumber(safePeek(state.BaseHealth)) or 0,
            Gamemode = gamemode,
            Map = mapName,
            Act = actName,
            Difficulty = difficulty,
            GameIncrement = tonumber(safePeek(state.GameIncrement)) or 0,
            GameTime = parseTime(safePeek(state.GameTime)) or parseTime(safePeek(state.SessionTime)) or parseTime(safePeek(state.Timer)) or 0,
            TotalKills = tonumber(safePeek(validPlayerState.TotalKills)) or tonumber(safePeek(validPlayerState.Kills)) or 0,
            TotalDamage = tonumber(safePeek(validPlayerState.TotalDamage)) or tonumber(safePeek(validPlayerState.Damage)) or 0
        }
    end
    return nil
end
local function getCurrentStageKey(stateInfo, previousStateInfo)
    if not stateInfo then return "Unknown" end
    local actName = stateInfo.Act
    local mapName = stateInfo.Map
    
    if (mapName == "" or mapName == "nil") and previousStateInfo and previousStateInfo.Map and previousStateInfo.Map ~= "" then
        mapName = previousStateInfo.Map
        if actName == "" or actName == "nil" then actName = previousStateInfo.Act end
    end
    
    if (mapName == "" or mapName == "nil") and appConfig.AutoJoin and appConfig.AutoJoin ~= "" then
        local parts = string.split(appConfig.AutoJoin, "|")
        if parts[1] == stateInfo.Gamemode and parts[2] then
            mapName = parts[2]
            if actName == "" and parts[3] then actName = parts[3] end
        end
    end
    if mapName == "" then mapName = "UnknownMap" end
    if stateInfo.Gamemode == "Expedition" then
        local difficulty = stateInfo.Difficulty
        if (difficulty == nil or difficulty == "") and appConfig.AutoJoin ~= "" then
            local parts = string.split(appConfig.AutoJoin, "|")
            difficulty = parts[4]
        end
        return ("Expedition_" .. mapName:gsub("%s", "") .. "_Difficulty" .. tostring(difficulty or 1)):gsub("[^%w%-_]", "")
    end
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
Tabs.Shop:AddToggle("AutoShopEnabled", {Title = "Bật Auto Shop", Default = appConfig.autoShopEnabled}):OnChanged(function(state)
    appConfig.autoShopEnabled = state
    saveConfig()
end)
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
local function setJoinMap(mode, mapId, act, diff)
    local uid = mode .. "|" .. mapId .. (act and ("|" .. act) or "") .. (diff and ("|" .. diff) or "")
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
            if parts[4] and parts[4] ~= "" then
                defaultVal = parts[2] .. " - " .. parts[3] .. " - " .. parts[4]
            elseif parts[3] and parts[3] ~= "" then
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
            setJoinMap(mode, parts[1], parts[2], parts[3])
        end
    end)
end
local function hasMacroHotbarUnits()
    local hotbar = Fusion.peek(Dependencies.HotbarState)
    local slots = hotbar and Fusion.peek(hotbar.Slots)
    for _, slot in pairs(type(slots) == "table" and slots or {}) do
        if type(slot) == "table" and slot.AssetType == "Unit" then return true end
    end
    return false
end
if #expeditionJoinOptions > 0 then
    local expeditionLabels = {}
    local expeditionByLabel = {}
    for _, option in ipairs(expeditionJoinOptions) do
        table.insert(expeditionLabels, option.Label)
        expeditionByLabel[option.Label] = option
    end
    local expeditionDefault
    local selectedParts = string.split(appConfig.AutoJoin or "", "|")
    if selectedParts[1] == "Expedition" then
        for _, option in ipairs(expeditionJoinOptions) do
            if option.MapId == selectedParts[2] and tostring(option.Difficulty) == tostring(selectedParts[4]) then
                expeditionDefault = option.Label
                break
            end
        end
    end
    Tabs.Join:AddSection("Expedition Difficulty")
    Tabs.Join:AddDropdown("JoinExpeditionDifficulty", {
        Title = "Expedition Map + Difficulty",
        Values = expeditionLabels,
        Multi = false,
        Default = expeditionDefault,
    }):OnChanged(function(value)
        local option = expeditionByLabel[value]
        if option then
            setJoinMap("Expedition", option.MapId, "", tostring(option.Difficulty))
        end
    end)
end
task.wait()
Tabs.Macro:AddParagraph({ Title = "Hệ Thống Macro", Content = "Tự động nhận diện Map đang chơi để chạy Macro tương ứng." })
local installMacroHook
local isRecording = false
local isPlaying = false
local startTime = 0
local currentStageKey = "Unknown"
local CachedUnitGCMap = nil
local currentMacroPara = Tabs.Macro:AddParagraph({ Title = "Trạng Thái", Content = "Đang ở Lobby" })

local RecordButton = Tabs.Macro:AddButton({
    Title = "Ghi Macro Ván Mới (Tự Động)",
    Description = "Bấm 1 lần. Sẽ tự Restart, tự Ghi khi ván bắt đầu và tự Lưu khi hết ván.",
    Callback = function()
        installMacroHook()
        local sInfo = getGameStates()
        if not sInfo or sInfo.CurrentGameState == "Finished" then
            Fluent:Notify({Title = "Lỗi", Content = "Phải ở trong Game mới được Record!", Duration = 3})
            return
        end
        if appConfig.autoPlayEnabled then
            Fluent:Notify({Title = "Lỗi", Content = "Hãy tắt Auto Play trước khi ghi hình!", Duration = 3})
            return
        end
        if sInfo.Gamemode == "Expedition" then
            getgenv().PendingRecord = true
            getgenv().ExpeditionRecordGameIncrement = sInfo.GameIncrement
            getgenv().IsManualRestart = true
            isRecording = false
            isPlaying = false
            Fluent:Notify({Title = "Macro", Content = "Đang Restart Expedition. Sẽ ghi tại Checkpoint mới.", Duration = 5})
            pcall(function() safeFireGameAction("Restart") end)
            return
        end
        getgenv().PendingRecord = true
        getgenv().IsManualRestart = true
        isRecording = false
        isPlaying = false
        Fluent:Notify({Title = "Macro", Content = "Đang khởi động lại ván đấu. Sẽ tự động ghi khi vào ván...", Duration = 5})
        pcall(function() safeFireGameAction("Restart") end)
    end
})

local TogglePlay = Tabs.Macro:AddToggle("TogglePlay", {Title = "Bật Auto Play", Default = appConfig.autoPlayEnabled})
TogglePlay:OnChanged(function(state)
    appConfig.autoPlayEnabled = state
    saveConfig()
    if not state then 
        isPlaying = false 
    else
        isRecording = false
        getgenv().PendingRecord = false
        local sInfo = getGameStates()
        if sInfo and sInfo.CurrentGameState ~= "Lobby" and sInfo.CurrentGameState ~= "Finished" then
            getgenv().IsManualRestart = true
            if sInfo.Gamemode == "Expedition" then
                getgenv().AutoPlayRestartGameIncrement = sInfo.GameIncrement
                getgenv().ExpeditionContinueBlocked = true
                lastHasRunMacro = true
            else
                getgenv().AutoPlayRestartGameIncrement = nil
                lastHasRunMacro = false
            end
            Fluent:Notify({Title = "Auto Play", Content = "Đang khởi động lại ván đấu để chạy Macro từ đầu...", Duration = 4})
            pcall(function() safeFireGameAction("Restart") end)
        else
            lastHasRunMacro = false
            isPlaying = false
        end
    end
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
Tabs.Macro:AddToggle("AutoLeaveOnPlayerJoin", {Title = "Tự động Thoát khi có người vào phòng Solo", Default = appConfig.autoLeaveOnPlayerJoin}):OnChanged(function(state)
    appConfig.autoLeaveOnPlayerJoin = state
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
        -- print("[ANTI AFK] Phát hiện AFK Chamber, đang tự quay về Lobby...")
        return true
    end
    -- warn("[ANTI AFK] Không thể rời AFK Chamber:", err)
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
local blackScreenCloseBtn = Instance.new("ImageButton", blackFrame)
blackScreenCloseBtn.Name = "CloseBlackScreenBtn"
blackScreenCloseBtn.Size = UDim2.new(0, 110, 0, 110)
blackScreenCloseBtn.Position = UDim2.new(0, 6, 0, 6)
blackScreenCloseBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
blackScreenCloseBtn.BackgroundTransparency = 0.2
blackScreenCloseBtn.Image = "rbxthumb://type=GameIcon&id=" .. game.GameId .. "&w=150&h=150"
blackScreenCloseBtn.ZIndex = 2
local blackScreenCloseCorner = Instance.new("UICorner", blackScreenCloseBtn)
blackScreenCloseCorner.CornerRadius = UDim.new(0, 12)
local coreGui = game:GetService("CoreGui")
if gethui then blackScreenGui.Parent = gethui() else blackScreenGui.Parent = coreGui end
local BlackScreenToggle = Tabs.Settings:AddToggle("BlackScreen", {Title = "Black Screen (Màn hình đen)", Default = false}):OnChanged(function(v)
    blackFrame.Visible = v
end)
blackScreenCloseBtn.MouseButton1Click:Connect(function()
    blackFrame.Visible = false
    if BlackScreenToggle and BlackScreenToggle.SetValue then
        BlackScreenToggle:SetValue(false)
    end
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
local function getGameIconUrl()
    local success, result = pcall(function()
        local req = (syn and syn.request) or request or http_request
        local resp = req({
            Url = "https://thumbnails.roblox.com/v1/places/gameicons?placeIds=" .. tostring(game.PlaceId) .. "&returnPolicy=PlaceHolder&size=512x512&format=Png&isCircular=false",
            Method = "GET"
        })
        if resp.StatusCode == 200 then
            local data = game:GetService("HttpService"):JSONDecode(resp.Body)
            if data and data.data and data.data[1] and data.data[1].imageUrl then
                return data.data[1].imageUrl
            end
        end
    end)
    if success and result then return result end
    return "https://tr.rbxcdn.com/180DAY-eeaa105a1844ec3811a2368a362736ec/256/256/Image/Webp"
end
local gameIconUrl = getGameIconUrl()
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
                    table.insert(gainedItems, {key = k, amount = amt - oldAmt, oldAmount = oldAmt})
                end
            end
        end
        for _, item in ipairs(gainedItems) do
            local emoji = getEmoji(item.key)
            if emoji == "" then emoji = "📦" end
            table.insert(itemLines, string.format("%s **%s:** %s + %s", emoji, item.key, formatNumber(item.oldAmount), formatNumber(item.amount)))
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
        local newUnitsDropped = {}
        for uid, u in pairs(newUnitData) do
            local oldU = oldUnitData[uid]
            if oldU then
                if u.EXP > oldU.EXP then
                    table.insert(gainedUnits, {name = u.Asset or "Unknown", expGained = u.EXP - oldU.EXP, level = u.Level, currentExp = u.EXP})
                end
            else
                table.insert(newUnitsDropped, {name = u.Asset or "Unknown", level = u.Level or 1})
            end
        end
        for _, u in ipairs(newUnitsDropped) do
            table.insert(unitLines, string.format("🎉 **%s** (Lvl %d): *New Drop!*", u.name, u.level))
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
    
    local pLevel = "?"
    pcall(function()
        pLevel = tostring(Fusion.peek(Dependencies.PlayerData).Level or "?")
    end)
    
    return {
        username = "Anime Expeditions Auto",
        avatar_url = gameIconUrl,
        embeds = {
            {
                author = { name = "Anime Expedition", icon_url = gameIconUrl },
                title = titlePrefix .. "||" .. (game.Players.LocalPlayer and game.Players.LocalPlayer.Name or "Player") .. " (Lv." .. pLevel .. ")|| - " .. tostring(matchResult),
                color = embedColor,
                thumbnail = { url = gameIconUrl },
                fields = fields,
                timestamp = DateTime.now():ToIsoDate(),
                footer = { text = "Anime Expeditions Ultimate" }
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
            local skey = getCurrentStageKey(stateInfo, lastStateInfo)
            currentStageKey = skey
            local macroList = getMacroListForStage(skey)
            local macroCount = macroList and #macroList or 0
            currentMacroPara:SetDesc("Đang ở: " .. skey .. "\nSố lệnh Macro đã lưu: " .. macroCount)
        else
            currentMacroPara:SetDesc("Đang ở Lobby...")
            lastHasRunMacro = false
            isPlaying = false
        end
        -- Expedition starts each node at Wave 1; that is not a new match and must
        -- not restart the macro playback state.
        if stateInfo and lastStateInfo and stateInfo.Gamemode ~= "Expedition" and stateInfo.Wave == 1 and lastStateInfo.Wave > 1 then
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
            if appConfig.autoShopEnabled then
                for storeId, products in pairs(appConfig.ShopSelections) do
                    for _, productId in ipairs(products) do
                        pcall(function()
                            local pId = getgenv().CachedGamePlayerDataId
                            if not pId then return end
                            local Event = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteEvents")
                            if Event and Event:FindFirstChild("ReplicaSignal") then
                                local realProductId = tonumber(productId) or productId
                                Event.ReplicaSignal:FireServer(pId, "PurchaseItem", storeId, realProductId, 1)
                            end
                        end)
                    end
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
                local lastCraft = getgenv().lastAutoCraft or 0
                if tick() - lastCraft > 2 then
                    getgenv().lastAutoCraft = tick()
                    for _, recipe in ipairs(appConfig.autoCraftItems) do
                        pcall(function() Actions.CraftRecipe(recipe, 5) end)
                        for i = 1, 5 do
                            pcall(function() Actions.CraftRecipe(recipe, 1) end)
                        end
                    end
                end
            end
            local function ClickGuiObject(guiObject)
                if not guiObject then return false end
                
                local fired = false
                pcall(function()
                    if type(firesignal) == "function" and (guiObject:IsA("TextButton") or guiObject:IsA("ImageButton")) then
                        pcall(function() firesignal(guiObject.MouseButton1Down) end)
                        pcall(function() firesignal(guiObject.MouseButton1Up) end)
                        pcall(function() firesignal(guiObject.MouseButton1Click) end)
                        pcall(function() firesignal(guiObject.Activated) end)
                        fired = true
                    elseif type(getconnections) == "function" then
                        for _, c in ipairs(getconnections(guiObject.MouseButton1Down)) do pcall(function() c:Fire() end) end
                        for _, c in ipairs(getconnections(guiObject.MouseButton1Up)) do pcall(function() c:Fire() end) end
                        for _, c in ipairs(getconnections(guiObject.MouseButton1Click)) do pcall(function() c:Fire() end) end
                        for _, c in ipairs(getconnections(guiObject.Activated)) do pcall(function() c:Fire() end) end
                        fired = true
                    end
                end)
                if fired then return true end
                return false
            end
            local function ClickButtonByText(targetText)
                local gui = game:GetService("Players").LocalPlayer.PlayerGui
                local btn = nil
                for _, v in pairs(gui:GetDescendants()) do
                    if v:IsA("TextLabel") or v:IsA("TextButton") then
                        if type(v.Text) == "string" and v.Text:lower():find(targetText:lower()) and not v.Text:lower():find("force") then
                            local isGameUI = false
                            local temp = v.Parent
                            while temp do
                                if temp:IsA("ScreenGui") then
                                    isGameUI = true
                                    break
                                end
                                temp = temp.Parent
                            end
                            if not isGameUI then continue end
                            
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
                local searchRoots = {gui:FindFirstChild("LeftHUD"), gui:FindFirstChild("HUD"), gui:FindFirstChild("Main"), gui:FindFirstChild("Lobby"), gui}
                local rootToSearch = gui
                for _, r in ipairs(searchRoots) do if r then rootToSearch = r; break end end
                
                if rootToSearch then
                    for _, v in ipairs(rootToSearch:GetDescendants()) do
                        if (v:IsA("TextLabel") or v:IsA("TextButton")) and type(v.Text) == "string" and string.match(v.Text:lower(), "^%s*play%s*$") then
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
                local searchRoots = {gui:FindFirstChild("Play"), gui:FindFirstChild("HUD"), gui:FindFirstChild("Main"), gui:FindFirstChild("Lobby"), gui}
                local rootToSearch = gui
                for _, r in ipairs(searchRoots) do if r then rootToSearch = r; break end end
                
                if rootToSearch then
                    for _, v in ipairs(rootToSearch:GetDescendants()) do
                        if (v:IsA("TextLabel") or v:IsA("TextButton")) and type(v.Text) == "string" and string.match(v.Text:lower(), "^%s*start%s*$") then
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

            local function WaitAndDismissPopupsForStart(timeout)
                local deadline = tick() + (timeout or 10)
                repeat
                    if ClickPartyStartButton() or WaitAndClickButtonByText("Start", 1) then
                        return true
                    end
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
                    -- print("[AUTO JOIN] StartMatchmaking OK:", levelData.Gamemode, levelData.MapName, levelData.ActName or "")
                    return true
                end
                -- warn("[AUTO JOIN] StartMatchmaking lỗi:", err)
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
                            ActName = parts[3] or "",
                            Difficulty = parts[4] or ""
                        }
                        if levelData.ActName ~= "" and not string.find(levelData.ActName, "Act") then
                            levelData.ActName = "Act " .. levelData.ActName
                        end
                        if parts[1] == "Expedition" then
                            levelData.ActName = ""
                            levelData.Difficulty = "Hard"
                            levelData.DifficultyLevel = tonumber(parts[4]) or 1
                        end
                        if parts[1] == "Infinite" or parts[1] == "Mastery" then
                            levelData.Difficulty = "Hard"
                        end
                    end
                    if parts[2] then
                        local mapToClick = parts[2]
                        if parts[1] and string.lower(parts[1]) == "infinite" then
                            mapToClick = "Infinite " .. parts[2]
                        elseif parts[1] == "Expedition" then
                            mapToClick = parts[2]:gsub("Expedition$", ""):gsub("(%l)(%u)", "%1 %2")
                        end
                        ClickButtonByText(mapToClick)
                        task.wait(0.5)
                    end
                    if parts[3] and parts[3] ~= "" and parts[1] ~= "Expedition" then
                        local actStr = parts[3]
                        if not string.find(actStr, "Act") then actStr = "Act " .. actStr end
                        ClickButtonByText(actStr)
                        task.wait(0.5)
                    end
                    if parts[4] and parts[4] ~= "" then
                        local difficultyButton = parts[1] == "Expedition" and ("Difficulty " .. parts[4]) or parts[4]
                        ClickButtonByText(difficultyButton)
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
                        -- Try to start instantly via Remote
                        pcall(function() Actions.PartyStartGame() end)
                        
                        local findDeadline = tick() + 15
                        local isPlayClicked = false
                        repeat
                            pcall(function() Actions.PartyStartGame() end)
                            if not isPlayClicked then
                                if ClickLobbyPlayButton() then
                                    isPlayClicked = true
                                    task.wait(0.5)
                                else
                                    task.wait(0.5)
                                end
                            end
                        until isPlayClicked or tick() >= findDeadline
                        if isPlayClicked then
                            -- print("[AUTO JOIN] Đã ấn PLAY, đợi 3 giây...")
                            task.wait(3)
                            -- print("[AUTO JOIN] Bắt đầu tìm START...")
                            local startDeadline = tick() + 20
                            local isStartClicked = false
                            repeat
                                pcall(function() Actions.PartyStartGame() end)
                                if ClickPartyStartButton() then
                                    isStartClicked = true
                                    break
                                else
                                    task.wait(0.5)
                                end
                            until tick() >= startDeadline
                            if isStartClicked then
                                -- print("[AUTO JOIN] Đã ấn START thành công! Chờ teleport...")
                                task.wait(5)
                            else
                                -- print("[AUTO JOIN] Lỗi: Không tìm thấy nút START!")
                            end
                        else
                            -- print("[AUTO JOIN] Lỗi: Không thể hoàn thành chuỗi X và PLAY!")
                        end
                        task.wait(2)
                    else
                        task.wait(2)
                    end
                end
            end
        else
            if appConfig.autoLeaveOnPlayerJoin and appConfig.autoJoinMode == "Start Instantly (Solo)" and stateInfo.CurrentGameState ~= "Lobby" and stateInfo.CurrentGameState ~= "Finished" then
                if #game:GetService("Players"):GetPlayers() > 1 then
                    local lastAutoReturnTrigger = getgenv().lastAutoReturnTrigger or 0
                    if tick() - lastAutoReturnTrigger > 5 then
                        getgenv().lastAutoReturnTrigger = tick()
                        stateInfo.CurrentGameState = "Finished"
                        Fluent:Notify({Title = "Phòng Lỗi", Content = "Phát hiện có người khác trong phòng Solo! Đang tự động thoát...", Duration = 5})
                        pcall(function() safeFireGameAction("Lobby") end)
                    end
                end
            end
            if appConfig.autoLeaveOnDefeat and stateInfo.CurrentGameState == "Finished" then
                if stateInfo.BaseHealth <= 0 then
                    local lastAutoReturnTrigger = getgenv().lastAutoReturnTrigger or 0
                    if tick() - lastAutoReturnTrigger > 5 then
                        getgenv().lastAutoReturnTrigger = tick()
                        Fluent:Notify({Title = "Auto Leave", Content = "Phát hiện thua cuộc! Đang tự động vứt trận về Lobby...", Duration = 5})
                        pcall(function() safeFireGameAction("Lobby") end)
                    end
                end
            end
            if appConfig.autoLeaveSpriteMax and stateInfo.CurrentGameState ~= "Lobby" and stateInfo.CurrentGameState ~= "Finished" then
                local currentSprites = snapshotItemData()["SpriteGrey"] or 0
                if currentSprites >= 125 then
                    if stateInfo.Wave == 0 or stateInfo.Wave == 1 then
                        if not getgenv().HasDisabledAutoLeaveForThisSession then
                            getgenv().HasDisabledAutoLeaveForThisSession = true
                            appConfig.autoLeaveSpriteMax = false
                            pcall(saveConfig)
                            Fluent:Notify({Title = "Kho Đồ Đã Đầy", Content = "Không thể Craft thêm (Max đồ hoặc thiếu mảnh). Đã tự động TẮT Auto Leave (Sprite Grey) để tránh lặp vô hạn!", Duration = 10})
                        end
                    else
                        local lastAutoReturnTrigger = getgenv().lastAutoReturnTrigger or 0
                        if tick() - lastAutoReturnTrigger > 5 then
                            getgenv().lastAutoReturnTrigger = tick()
                            stateInfo.CurrentGameState = "Finished"
                            Fluent:Notify({Title = "Auto Leave", Content = "Đã đầy 125 Sprite (Grey). Đang tự động về sảnh!", Duration = 5})
                            pcall(function() safeFireGameAction("Lobby") end)
                        end
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
                        pcall(function() safeFireGameAction("Restart") end)
                    end
                end
            end
            local willBeEndMatch = false
            if stateInfo.CurrentGameState == "Finished" or stateInfo.CurrentGameState == "Victory" or stateInfo.CurrentGameState == "Defeat" then
                willBeEndMatch = true
            elseif stateInfo.Gamemode ~= "Expedition" and lastStateInfo and lastStateInfo.Wave > 0 and stateInfo.Wave == 0 then
                willBeEndMatch = true
            end

            if stateInfo.Wave == 0 then
                local char = game.Players.LocalPlayer.Character
                if char and char:FindFirstChild("HumanoidRootPart") then
                    if not getgenv().Wave0StartTime or tick() - getgenv().Wave0StartTime > 30 then
                        getgenv().Wave0StartTime = tick()
                    end
                end
            end
            
            if lastStateInfo and lastStateInfo.CurrentGameState == "Lobby" and stateInfo.CurrentGameState ~= "Lobby" then
                isPlaying = false
                lastHasRunMacro = false
            end
            if stateInfo.Gamemode == "Expedition" and lastStateInfo and lastStateInfo.Wave > 0 and stateInfo.Wave == 0 then
                -- A node transition clears unplaced unit ghosts. Replay the recorded placements
                -- once when the next node actually begins (the route-map guard below delays it).
                isPlaying = false
                lastHasRunMacro = false
                print("[MACRO] Expedition returned to wave 0; placement replay unlocked")
            end
            if getgenv().AutoPlayRestartGameIncrement ~= nil and stateInfo.GameIncrement ~= getgenv().AutoPlayRestartGameIncrement then
                getgenv().AutoPlayRestartGameIncrement = nil
                isPlaying = false
                lastHasRunMacro = false
                print("[MACRO] Restart completed; macro playback unlocked for GameIncrement " .. tostring(stateInfo.GameIncrement))
            end
            
            if isRecording and currentStageKey and currentStageKey:find("UnknownMap") then
                local realKey = getCurrentStageKey(stateInfo, lastStateInfo)
                if not realKey:find("UnknownMap") then
                    appConfig.Macros[realKey] = appConfig.Macros[currentStageKey]
                    appConfig.Macros[currentStageKey] = nil
                    currentStageKey = realKey
                    Fluent:Notify({Title = "Macro", Content = "Đã cập nhật tên Map thật: " .. realKey, Duration = 3})
                end
            end

            local canBeginRecord = stateInfo.CurrentGameState ~= "Lobby" and (stateInfo.Wave == 0 or stateInfo.Wave == 1)
            if stateInfo.Gamemode == "Expedition" then
                local restartIncrement = getgenv().ExpeditionRecordGameIncrement
                canBeginRecord = stateInfo.CurrentGameState ~= "Lobby"
                    and restartIncrement ~= nil
                    and stateInfo.GameIncrement ~= restartIncrement
            end
            if getgenv().PendingRecord and canBeginRecord then
                getgenv().PendingRecord = false
                getgenv().ExpeditionRecordGameIncrement = nil
                isRecording = true
                currentStageKey = getCurrentStageKey(stateInfo, lastStateInfo)
                appConfig.Macros[currentStageKey] = {}
                startTime = tick()
                -- print("[Macro Record] Đã BẮT ĐẦU GHI HÌNH cho map: " .. currentStageKey .. " | Wave: " .. tostring(stateInfo.Wave))
                Fluent:Notify({Title = "Macro", Content = "Bắt đầu TỰ ĐỘNG GHI hình cho [" .. currentStageKey .. "]", Duration = 5})
            end

            if appConfig.autoPlayEnabled and not isRecording and not isPlaying and not lastHasRunMacro then
                local canStartMacro = stateInfo.Wave == 0 or stateInfo.Wave == 1
                if stateInfo.Gamemode == "Expedition" then
                    -- The route panel remains visible between nodes (1/10, 2/10, etc.).
                    -- Never replay a build macro while the player is choosing the next node.
                    canStartMacro = getExpeditionMapProgress() == nil
                end
                if stateInfo.CurrentGameState ~= "Lobby" and canStartMacro and not willBeEndMatch then
                    local skey = getCurrentStageKey(stateInfo, lastStateInfo)
                    local macroList, matchedMacroKey = getMacroListForStage(skey)
                    if macroList and #macroList > 0 and hasMacroHotbarUnits() then
                        isPlaying = true
                        if stateInfo.Gamemode == "Expedition" then getgenv().ExpeditionContinueBlocked = true end
                        lastHasRunMacro = true
                        print("[AE-LOG DEBUG] TÌM THẤY MACRO! Bắt đầu thread Playback...")
                        Fluent:Notify({Title = "Macro", Content = "Đã tìm thấy thư viện Macro cho ["..matchedMacroKey.."]. Đang bắt đầu tự động xây!", Duration = 5})
                        task.spawn(function()
                            if stateInfo.Gamemode == "Expedition" then
                                print("[MACRO] Expedition node " .. tostring(stateInfo.Status) .. ": running " .. #macroList .. " recorded actions")
                            end
                            local Event = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ReplicaSignal")
                            local function getCurrentMacroReplicaIds()
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
                                getgenv().CachedGamePlayerDataId = gamePlayerDataId
                                getgenv().CachedHotbarDataId = hotbarDataId
                                return gamePlayerDataId, hotbarDataId
                            end
                            
                            local initialEndIndex = #macroList
                            if stateInfo.Gamemode ~= "Expedition" then
                                local lastActionTime = 0
                                for i, act in ipairs(macroList) do
                                    if act.type == "VoteStart" or (act.wave and act.wave > 0) then
                                        initialEndIndex = i - 1
                                        break
                                    end
                                    if act.time - lastActionTime > 15 then
                                        initialEndIndex = i - 1
                                        break
                                    end
                                    lastActionTime = act.time
                                end
                            end
                            print("[AE-LOG DEBUG] Bắt đầu chạy Macro! Tổng lệnh: " .. tostring(#macroList) .. " | Điểm chia Phase 1: Lệnh thứ " .. tostring(initialEndIndex))

                            -- Luôn lấy tick() hiện tại làm mốc 0 để không bị tua nhanh nếu Wave0StartTime bị cũ
                            local playStart = tick()
                            local itemPauseLogged = false
                            for i, action in ipairs(macroList) do
                                if not isPlaying or not appConfig.autoPlayEnabled then break end
                                while isExpeditionItemTargeting() do
                                    if not itemPauseLogged then
                                        itemPauseLogged = true
                                        print("[MACRO] Paused while selecting an Expedition Tome target")
                                    end
                                    task.wait(0.25)
                                    if not isPlaying or not appConfig.autoPlayEnabled then break end
                                end
                                itemPauseLogged = false
                                if not isPlaying or not appConfig.autoPlayEnabled then break end
                                
                                if i == initialEndIndex + 1 then
                                    print("[Macro Playback] Đã xong Phase 1. Đang ép Start Game và chờ Wave 1...")
                                    while stateInfo.Wave == 0 do
                                        safeFireGameAction("VoteStart")
                                        task.wait(1)
                                        stateInfo = getGameStates()
                                        if not isPlaying or not appConfig.autoPlayEnabled then break end
                                    end
                                    -- Cập nhật lại mốc thời gian để Phase 2 chạy chuẩn xác tính từ lúc Wave 1 bắt đầu
                                    playStart = tick() - action.time
                                end

                                while (tick() - playStart) < action.time do
                                    task.wait(0.01)
                                    if not isPlaying or not appConfig.autoPlayEnabled then break end
                                end
                                if not isPlaying or not appConfig.autoPlayEnabled then break end
                                
                                if action.type == "Select" then
                                    local _, hId = getCurrentMacroReplicaIds()
                                    if hId then
                                        Event:FireServer(hId, "SelectSlot", action.slot)
                                        print("[MACRO] SelectSlot " .. tostring(action.slot) .. " using HotbarData " .. tostring(hId))
                                    else
                                        warn("[MACRO] SelectSlot skipped: HotbarData replica missing")
                                    end
                                elseif action.type == "Place" then 
                                    local pId = getCurrentMacroReplicaIds()
                                    if pId then
                                        local placementAction = action.placementAction == "PlaceGamePhantom" and "PlaceGamePhantom" or "PlaceGameUnit"
                                        Event:FireServer(pId, placementAction, action.slot, CFrame.new(unpack(action.pos)), action.quickPlacement)
                                        print("[MACRO] " .. placementAction .. " slot " .. tostring(action.slot) .. " using GamePlayerData " .. tostring(pId))
                                    else
                                        warn("[MACRO] Place skipped: GamePlayerData replica missing")
                                    end
                                    local execTime = tick() - playStart
                                    -- print(string.format("[Macro Playback] Đặt lính (Slot %d) lúc %.2fs | Gốc: %.2fs | Trễ: %.2fs | Wave: %s", action.slot, execTime, action.time, execTime - action.time, tostring(lastStateInfo and lastStateInfo.Wave or 0)))
                                elseif action.type == "VoteStart" then
                                    safeFireGameAction("VoteStart")
                                    local execTime = tick() - playStart
                                    print(string.format("[Macro Playback] Đã tự động bấm VoteStart lúc %.2fs", execTime))
                                elseif action.type == "Upgrade" or action.type == "Sell" or action.type == "AutoUpgrade" then
                                    local pId = getCurrentMacroReplicaIds()
                                    if not pId then
                                        warn("[MACRO] Unit action skipped: GamePlayerData replica missing")
                                        continue
                                    end
                                    local uId = action.unitId
                                    if action.pos then
                                        local targetPos = Vector3.new(action.pos[1], action.pos[2], action.pos[3])
                                        local closestDist = 20
                                        local closestModel = nil
                                        for _, v in pairs(workspace:GetDescendants()) do
                                            if v:IsA("Model") and not v:GetAttribute("EnemyID") then
                                                local part = v.PrimaryPart or v:FindFirstChild("HumanoidRootPart")
                                                if part then
                                                    local dist = (part.Position - targetPos).Magnitude
                                                    if dist < closestDist then
                                                        closestDist = dist
                                                        closestModel = v
                                                    end
                                                end
                                            end
                                        end
                                        
                                        if closestModel then
                                            local realId = nil
                                            local function checkTable(obj)
                                                for tk, tv in pairs(obj) do
                                                    if tv == closestModel and type(tk) == "string" and tonumber(tk) then return tk end
                                                    if tk == closestModel and type(tv) == "string" and tonumber(tv) then return tv end
                                                    if type(tv) == "table" and type(tk) == "string" and tonumber(tk) then
                                                        if tv.Model == closestModel or tv.Instance == closestModel or tv.Unit == closestModel or tv.Character == closestModel then return tk end
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
                                            if realId then
                                                uId = realId
                                            else
                                                uId = type(action.unitId) == "string" and closestModel.Name or closestModel
                                                warn("[AE-LOG] Failed to find NEW ID for unit at " .. tostring(closestModel.Name) .. "! Falling back to " .. tostring(uId))
                                            end
                                        else
                                            warn("[AE-LOG] Macro Playback WARNING: Could not find any unit within 20 studs of recorded position for " .. tostring(action.type))
                                        end
                                    else
                                        warn("[AE-LOG] Macro Playback WARNING: action.pos is MISSING for " .. tostring(action.type) .. "! Using OLD ID: " .. tostring(uId))
                                    end
                                    
                                    if action.type == "Upgrade" then 
                                        Event:FireServer(pId, "UpgradeGameUnit", uId)
                                        local execTime = tick() - playStart
                                        print(string.format("[Macro Playback] Nâng cấp lính (Mã MỚI: %s) lúc %.2fs", tostring(uId), execTime))
                                    elseif action.type == "AutoUpgrade" then
                                        Event:FireServer(pId, "ChangeGameUnitAutoUpgradePriority", uId)
                                        local execTime = tick() - playStart
                                        print(string.format("[Macro Playback] Bật/Tắt Auto Upgrade lính (Mã MỚI: %s) lúc %.2fs", tostring(uId), execTime))
                                    else 
                                        Event:FireServer(pId, "SellGameUnit", uId) 
                                        local execTime = tick() - playStart

                                        print(string.format("[Macro Playback] Bán lính (Mã MỚI: %s) lúc %.2fs", tostring(uId), execTime))
                                    end
                                end
                            end
                            if initialEndIndex == #macroList and stateInfo.Gamemode ~= "Expedition" then
                                task.spawn(function()
                                    task.wait(1)
                                    safeFireGameAction("VoteStart")
                                    print("[Macro Playback] Đã tự động VoteStart vì Macro đã chạy hết toàn bộ Phase 1!")
                                end)
                            end
                            print("[AE-LOG DEBUG] Macro đã kết thúc an toàn!")
                            Fluent:Notify({Title = "Macro", Content = "Hoàn tất kịch bản Macro!", Duration = 3})
                            isPlaying = false
                            if stateInfo.Gamemode == "Expedition" then getgenv().ExpeditionContinueBlocked = false end
                        end)
                    elseif macroList and #macroList > 0 and tick() - (getgenv().LastEmptyHotbarMacroLog or 0) > 30 then
                        getgenv().LastEmptyHotbarMacroLog = tick()
                        print("[MACRO] Skipped: no Unit slots in hotbar")
                    end
                end
            end
            local isEndMatch = false
            local resultStatus = "Finished"
            local isInfinite = isInfiniteGamemode(stateInfo.Gamemode) or (lastStateInfo and isInfiniteGamemode(lastStateInfo.Gamemode))
            if stateInfo.CurrentGameState == "Finished" or stateInfo.CurrentGameState == "Victory" or stateInfo.CurrentGameState == "Defeat" then
                isEndMatch = true
                resultStatus = stateInfo.BaseHealth > 0 and "Victory" or "Defeat"
                if getgenv().WasAutoRestarted then resultStatus = "Victory"; getgenv().WasAutoRestarted = false end
            end
            if not isEndMatch and stateInfo.Gamemode ~= "Expedition" and lastStateInfo and lastStateInfo.Wave > 0 and stateInfo.Wave == 0 then
                isEndMatch = true
                if lastStateInfo.Wave >= lastStateInfo.MaxWave or getgenv().WasAutoRestarted then
                    resultStatus = "Victory"
                else
                    resultStatus = "Defeat"
                end
                getgenv().WasAutoRestarted = false
            end
            
            local wasManualRestart = getgenv().IsManualRestart
            if isEndMatch then
                lastHasRunMacro = false
                isPlaying = false
                if wasManualRestart then
                    getgenv().IsManualRestart = false
                else
                    if isRecording then
                        isRecording = false
                        pcall(saveConfig)
                        Fluent:Notify({Title = "Macro", Content = "Trận đấu kết thúc! Đã tự động TẮT và LƯU bản ghi Macro.", Duration = 7})
                    end
                end
            end
            if isEndMatch and not wasManualRestart and appConfig.webhookWinEnabled and (tick() - lastSentTime > 15) then
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
                    -- The script already relies on safeFireGameAction("Restart") 
                    -- so we no longer need the fallback physical mouse click here.
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
installMacroHook = function()
    if getgenv().AnimeExpeditionsMacroHookInstalled then return end
    logInit("Đang cài đặt Hook Bypass & Macro...")
    local oldNamecall
    local rawFireServer = Instance.new("RemoteEvent").FireServer
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local method = getnamecallmethod()
    local args = {...}
    if not checkcaller() then
        if isRecording then
            if method == "FireServer" or method == "InvokeServer" then
                local actStr = "UNKNOWN"
                if typeof(args[1]) == "string" then actStr = args[1]
                elseif typeof(args[2]) == "string" then actStr = args[2] end
                if not (actStr:find("Mouse") or actStr:find("Move") or actStr:find("Camera")) then
                    print("[AE-LOG GLOBAL DEBUG] Remote: " .. tostring(self.Name) .. " | Method: " .. tostring(method) .. " | Args: " .. tostring(args[1]) .. ", " .. tostring(args[2]))
                end
            end
        end

        if method == "FireServer" and typeof(self) == "Instance" and self.Name == "ReplicaSignal" then
            if type(args[2]) == "string" then
                local act = args[2]
                if act:find("Place") or act:find("Upgrade") or act:find("Sell") or act:find("Unit") or act:find("Auto") or act == "Restart" or act == "Lobby" or act == "VoteStart" or act == "VoteRestart" then
                    local logStr = "[AE-LOG] " .. act .. " | "
                    for i, v in ipairs(args) do logStr = logStr .. i .. "=" .. tostring(v) .. "(" .. typeof(v) .. ") " end
                    print(logStr)
                    warn(logStr) -- In ra warning cho de nhin
                end
            end

        local helperCapture = getgenv().ExpeditionAutoHelperCapture
        if helperCapture and args[2] == "PlaceGameUnit" then
            local position
            for index = 3, #args do
                if typeof(args[index]) == "CFrame" then
                    position = {args[index]:GetComponents()}
                    break
                end
            end
            local expeditionConfig = appConfig.ExpeditionAuto
            if position and expeditionConfig and type(expeditionConfig.helperPositions) == "table" then
                expeditionConfig.helperPositions[helperCapture.priority] = expeditionConfig.helperPositions[helperCapture.priority] or {}
                table.insert(expeditionConfig.helperPositions[helperCapture.priority], position)
                getgenv().ExpeditionAutoHelperCapture = nil
                saveConfig()
                if getgenv().ExpeditionAutoRefreshHelperPositions then
                    getgenv().ExpeditionAutoRefreshHelperPositions()
                end
                Fluent:Notify({Title = "Helper Position Saved", Content = "Position saved. Restarting in 1 second...", Duration = 3})
                task.delay(1, function()
                    -- This capture is independent of the normal macro recorder.
                    -- Stop recording/playback first so only one restart is sent.
                    isRecording = false
                    isPlaying = false
                    getgenv().PendingRecord = false
                    getgenv().IsManualRestart = true
                    pcall(function() safeFireGameAction("Restart") end)
                end)
            end
        end

        if isRecording then
            local action = args[2]
            if type(action) == "string" and not (action:find("Mouse") or action:find("Move") or action:find("Camera")) then
                print("[AE-LOG DEBUG] Recorded FireServer: " .. tostring(action) .. " | Arg1: " .. tostring(args[1]))
            end
            local currentTime = tick() - startTime
            local mList = appConfig.Macros[currentStageKey]
            if action == "SelectSlot" then
                local curWave = lastStateInfo and lastStateInfo.Wave or 0
                table.insert(mList, {time = currentTime, type = "Select", slot = args[3], wave = curWave})
            elseif action == "PlaceGameUnit" or action == "PlaceGamePhantom" then
                local pArg
                local quickPlacement
                for i = 3, #args do
                    if not pArg and (typeof(args[i]) == "CFrame" or typeof(args[i]) == "Vector3") then
                        pArg = args[i]
                    elseif type(args[i]) == "boolean" then
                        quickPlacement = args[i]
                    end
                end
                if pArg then
                    local p = typeof(pArg) == "CFrame" and {pArg:components()} or {pArg.X, pArg.Y, pArg.Z}
                    local curWave = lastStateInfo and lastStateInfo.Wave or 0
                    table.insert(mList, {
                        time = currentTime,
                        type = "Place",
                        placementAction = action == "PlaceGamePhantom" and action or nil,
                        slot = args[3],
                        pos = p,
                        wave = curWave,
                        quickPlacement = quickPlacement,
                    })
                end
            elseif action == "VoteStart" or (action == "Response" and type(args[3]) == "boolean") then
                local curWave = lastStateInfo and lastStateInfo.Wave or 0
                table.insert(mList, {time = currentTime, type = "VoteStart", wave = curWave})
                print("[Macro Record] Đã lưu hành động bấm VoteStart lúc: " .. tostring(currentTime))
            elseif action == "UpgradeGameUnit" or action == "SellGameUnit" or action == "ChangeGameUnitAutoUpgradePriority" then
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
                -- print("[Anti-Lag] Hook Scan took " .. string.format("%.5f", tick() - tStart) .. "s")
                if not targetModel then
                    for _, v in pairs(workspace:GetDescendants()) do
                        if v.Name == tostring(args[3]) and v:IsA("Model") then targetModel = v; break end
                    end
                end
                if targetModel and targetModel:IsA("Model") then
                    local part = targetModel.PrimaryPart or targetModel:FindFirstChild("HumanoidRootPart")
                    if part then 
                        p = {part.Position.X, part.Position.Y, part.Position.Z} 
                    else
                        warn("[AE-LOG] Macro Record WARNING: targetModel found but no PrimaryPart or RootPart! " .. tostring(targetModel:GetFullName()))
                    end
                else
                    warn("[AE-LOG] Macro Record WARNING: targetModel NOT FOUND for ID: " .. tostring(args[3]))
                end
                if action == "UpgradeGameUnit" then
                    local curWave = lastStateInfo and lastStateInfo.Wave or 0
                    table.insert(mList, {time = currentTime, type = "Upgrade", unitId = args[3], pos = p, wave = curWave})
                elseif action == "SellGameUnit" then
                    local curWave = lastStateInfo and lastStateInfo.Wave or 0
                    table.insert(mList, {time = currentTime, type = "Sell", unitId = args[3], pos = p, wave = curWave})
                elseif action == "ChangeGameUnitAutoUpgradePriority" then
                    local curWave = lastStateInfo and lastStateInfo.Wave or 0
                    table.insert(mList, {time = currentTime, type = "AutoUpgrade", unitId = args[3], pos = p, wave = curWave})
                end
            end
        end
        return rawFireServer(self, ...)
    end
end
        return oldNamecall(self, ...)
    end))
    getgenv().AnimeExpeditionsMacroHookInstalled = true
end
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

task.spawn(function()
    if not getgenv().CachedGamePlayerDataId then
        local gId, hId
        for _, v in pairs(getgc(true)) do
            if type(v) == "table" and rawget(v, "Id") and type(rawget(v, "Token")) == "string" then
                if v.Token == "GamePlayerData" then
                    if not gId or v.Id > gId then gId = v.Id end
                elseif v.Token == "HotbarData" then
                    if not hId or v.Id > hId then hId = v.Id end
                end
            end
        end
        getgenv().CachedGamePlayerDataId = gId
        getgenv().CachedHotbarDataId = hId
    end
end)
-- print(string.format("[AnimeExpeditionsUltimate] TỔNG THỜI GIAN KHỞI ĐỘNG: %.4fs", tick() - _initStartTime))
Fluent:Notify({Title = "AE", Content = "Load xong!", Duration = 5})

-- Expedition Auto is kept in the existing Macro tab so its helper positions can
-- directly reuse the Place actions recorded by the built-in macro recorder.
local ExpeditionAutoDefaults = {
    enabled = false,
    autoCards = true,
    cardFallback = "First",
    upgradePriority = {},
    autoHire = true,
    helperPriority = {"", "", "", "", "", "", "", "", "", ""},
    helperPositions = {{}, {}, {}, {}, {}, {}, {}, {}, {}, {}},
    autoShop = true,
    buyTome = true,
    buyRepair = true,
    buyAnvil = true,
    autoUseTome = true,
    autoUseRepair = true,
    autoUseAnvil = true,
    damageTraits = {},
    farmTraits = {},
    statPriority = {"Damage", "Range", "SPA"},
    autoContinue = true,
    continueDelay = 3,
    autoOrbs = true,
    orbScanDelay = 10,
}
local function fillExpeditionDefaults(target, source)
    for key, value in pairs(source) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = {}
                fillExpeditionDefaults(target[key], value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            fillExpeditionDefaults(target[key], value)
        end
    end
end
appConfig.ExpeditionAuto = appConfig.ExpeditionAuto or {}
fillExpeditionDefaults(appConfig.ExpeditionAuto, ExpeditionAutoDefaults)
local ExpeditionAuto = appConfig.ExpeditionAuto
ExpeditionAuto.farmTraits = ExpeditionAuto.farmTraits or {}
local function expeditionUniqueList(values)
    local result, seen = {}, {}
    for _, value in ipairs(type(values) == "table" and values or {}) do
        if type(value) == "string" and value ~= "" and not seen[value] then
            seen[value] = true
            table.insert(result, value)
        end
    end
    return result
end
local normalizedFarmTraits = {}
for key, value in pairs(ExpeditionAuto.farmTraits or {}) do
    if type(key) == "string" and value then normalizedFarmTraits[key] = true
    elseif type(key) == "number" and type(value) == "string" then normalizedFarmTraits[value] = true end
end
ExpeditionAuto.farmTraits = normalizedFarmTraits
local normalizedDamageTraits = {}
for key, value in pairs(ExpeditionAuto.damageTraits or {}) do
    if type(key) == "string" and value then normalizedDamageTraits[key] = true
    elseif type(key) == "number" and type(value) == "string" then normalizedDamageTraits[value] = true end
end
ExpeditionAuto.damageTraits = normalizedDamageTraits
ExpeditionAuto.upgradePriority = expeditionUniqueList(ExpeditionAuto.upgradePriority)
ExpeditionAuto.statPriority = expeditionUniqueList(ExpeditionAuto.statPriority)
saveConfig()
for index = 1, 10 do
    if type(ExpeditionAuto.helperPositions[index]) ~= "table" then
        ExpeditionAuto.helperPositions[index] = {}
    end
end
local ExpeditionNodes = require(ReplicatedStorage.Nodes)
local ExpeditionTraits = require(SharedInfo.Traits)
local ExpeditionInfo = require(SharedInfo.Expeditions)
local expeditionRuntime = {
    lastCard = 0,
    lastHire = 0,
    lastBuy = 0,
    lastShopScan = 0,
    lastShopAction = 0,
    pendingRepairCount = nil,
    pendingRepairAt = 0,
    pendingAnvilPurchaseAt = nil,
    firstCheckpointIncrement = nil,
    lastContinue = 0,
    lastUse = 0,
    lastNoYenLog = 0,
    hired = {},
    helperPending = {},
    helperUsedPositions = {},
    helperGameIncrement = nil,
    tomeQueue = {},
    lastCardSignature = "",
    lastOrbLog = 0,
    lastOrbScan = 0,
    orbQueue = {},
    orbGameStateId = nil,
    orbDrainActive = false,
    lastStateSignature = "",
    lastErrorLog = {},
    refreshedShopSnapshots = {},
    shopPurchaseRequests = {},
    tomePurchasedCycles = {},
    repairPurchasedSnapshots = {},
    unboundTargets = {},
    cardPending = nil,
    continueScheduledAt = nil,
    continueWatchdog = nil,
    lastContinueBlock = "",
    lastContinueState = "",
}
local farmExpeditionAssets = {Ichiraku = true, Senku = true}
local expeditionPotentialOrder = {Z = 14, SSS = 13, SS = 12, S = 11, ["A+"] = 10, A = 9, ["A-"] = 8, ["B+"] = 7, B = 6, ["B-"] = 5, ["C+"] = 4, C = 3, ["C-"] = 2, F = 1}

local function expeditionPeek(value)
    local ok, result = pcall(function() return Fusion.peek(value) end)
    return ok and result or value
end
local function expeditionGameReplica()
    local ok, replica = pcall(function() return ExpeditionNodes.GET_GAME_REPLICA:InvokeSelf() end)
    return ok and replica or nil
end
local function expeditionShopReplica()
    local ok, replica = pcall(function() return ExpeditionNodes.GET_SHOP_REPLICA:InvokeSelf("CheckpointShop") end)
    return ok and replica or nil
end
local function expeditionState()
    local state = expeditionPeek(Dependencies.GameState)
    if type(state) ~= "table" then return nil end
    return {
        mode = expeditionPeek(state.Parameters) and expeditionPeek(expeditionPeek(state.Parameters).Gamemode),
        status = expeditionPeek(state.Status),
        current = expeditionPeek(state.CurrentGameState),
        wave = expeditionPeek(state.Wave),
        enemyCount = tonumber(expeditionPeek(state.EnemyCount)) or 0,
        active = expeditionPeek(state.Active) == true,
        health = tonumber(expeditionPeek(state.BaseHealth)),
        maxHealth = tonumber(expeditionPeek(state.BaseMaxHealth)),
        increment = tonumber(expeditionPeek(state.GameIncrement)) or 0,
    }
end
local function isExpeditionGame()
    local state = expeditionState()
    return state and state.mode == "Expedition"
end
local function expeditionAutomationActive()
    if not appConfig.autoPlayEnabled or not isExpeditionGame() then return false end
    local stageKey = currentStageKey
    if not stageKey or stageKey == "Unknown" then
        local stateInfo = getGameStates()
        stageKey = stateInfo and getCurrentStageKey(stateInfo)
    end
    local macro = stageKey and getMacroListForStage(stageKey)
    return type(macro) == "table" and #macro > 0
end
local function expeditionLogState()
    local state = expeditionState()
    if not state then return end
    local signature = table.concat({tostring(state.current), tostring(state.status), tostring(state.wave)}, " | ")
    if expeditionRuntime.lastStateSignature ~= signature then
        expeditionRuntime.lastStateSignature = signature
        print("[EXP AUTO] State: " .. signature)
    end
end
local function expeditionRun(label, callback)
    if type(callback) ~= "function" then
        if not expeditionRuntime.missingCallbacks then expeditionRuntime.missingCallbacks = {} end
        if not expeditionRuntime.missingCallbacks[label] then
            expeditionRuntime.missingCallbacks[label] = true
            warn("[EXP AUTO] " .. label .. " callback missing; reload the current script build")
        end
        return
    end
    local ok, err = xpcall(callback, debug.traceback)
    if not ok and tick() - (expeditionRuntime.lastErrorLog[label] or 0) >= 2 then
        expeditionRuntime.lastErrorLog[label] = tick()
        local phase = label == "Shop" and (" [phase=" .. tostring(expeditionRuntime.shopPhase) .. "]") or ""
        warn("[EXP AUTO] " .. label .. phase .. " error: " .. tostring(err))
    end
end
local function expeditionListFromDropdown(value)
    local result, seen = {}, {}
    for key, enabled in pairs(value or {}) do
        local selected = type(key) == "string" and enabled and key
        if selected and not seen[selected] then
            seen[selected] = true
            table.insert(result, selected)
        end
    end
    table.sort(result)
    return result
end
local function expeditionSetFromDropdown(value)
    local result = {}
    for key, enabled in pairs(value or {}) do
        if type(key) == "string" and enabled then result[key] = true end
    end
    return result
end
local function expeditionTraitSelected(selected, trait)
    for key, value in pairs(selected or {}) do
        if (key == trait and value) or value == trait then return true end
    end
    return false
end
local function expeditionMacroPlaces()
    local places = {}
    local macro = appConfig.Macros[currentStageKey] or {}
    for _, action in ipairs(macro) do
        if action.type == "Place" and type(action.pos) == "table" then table.insert(places, action) end
    end
    return places
end
local function expeditionScore(data)
    local score, potential = 0, data and data.StatPotential or {}
    for priority, stat in ipairs(ExpeditionAuto.statPriority) do
        local grade = potential[stat] and potential[stat].Potential
        score = score + (expeditionPotentialOrder[grade] or 0) * (10 ^ (4 - priority))
    end
    return score
end
local function expeditionPlacedTarget(kind, options)
    local units = expeditionPeek(Dependencies.GameUnits)
    local candidates = {}
    for id, value in pairs(type(units) == "table" and units or {}) do
        local data = expeditionPeek(value)
        local unitData = type(data) == "table" and (expeditionPeek(data.UnitData) or data.UnitData or data) or nil
        local asset = type(data) == "table" and (data.Asset or (type(unitData) == "table" and unitData.Asset))
        local isFarm = farmExpeditionAssets[asset] == true
        if asset and not data.IsClone and ((kind == "Farm" and isFarm) or (kind == "Damage" and not isFarm)) then
            local gameUnitId = data.ID or data.GameUnitID or data.GameID
            gameUnitId = gameUnitId and tostring(gameUnitId) or nil
            local trait = type(unitData) == "table" and unitData.Trait
            local hasTrait = trait and trait ~= "" and trait ~= "None"
            if (not options or not options.traitless or not hasTrait)
                and (not options or not options.traitFilter or options.traitFilter(trait, hasTrait))
                and (not options or not options.skipUnboundTargets or not expeditionRuntime.unboundTargets[gameUnitId])
                and (not options or not options.skipExistingUnbound or trait ~= "Unbound") then
                table.insert(candidates, {id = id, gameUnitId = gameUnitId, asset = asset, data = unitData})
            end
        end
    end
    table.sort(candidates, function(a, b) return expeditionScore(a.data) > expeditionScore(b.data) end)
    return candidates[1]
end
local function expeditionHotbarItem(asset)
    local hotbar = expeditionPeek(Dependencies.HotbarState)
    local slots = hotbar and expeditionPeek(hotbar.Slots)
    for slotIndex, slot in pairs(type(slots) == "table" and slots or {}) do
        local data = type(slot) == "table" and expeditionPeek(slot.Data)
        if type(slot) == "table" and slot.AssetType == "Item" and data and data.Asset == asset then return {slot = tonumber(slotIndex), id = slot.ID, data = data} end
    end
    return nil
end
local function expeditionHotbarItems(asset)
    local hotbar = expeditionPeek(Dependencies.HotbarState)
    local slots = hotbar and expeditionPeek(hotbar.Slots)
    local items = {}
    for slotIndex, slot in pairs(type(slots) == "table" and slots or {}) do
        local data = type(slot) == "table" and expeditionPeek(slot.Data)
        if type(slot) == "table" and slot.AssetType == "Item" and data and data.Asset == asset then
            table.insert(items, {slot = tonumber(slotIndex), id = slot.ID, data = data})
        end
    end
    table.sort(items, function(a, b) return (a.slot or math.huge) < (b.slot or math.huge) end)
    return items
end
local function expeditionTomeConfigured()
    return ExpeditionAuto.buyTome and ExpeditionAuto.autoUseTome
        and (#expeditionListFromDropdown(ExpeditionAuto.damageTraits) > 0 or #expeditionListFromDropdown(ExpeditionAuto.farmTraits) > 0)
end
local function expeditionAnvilConfigured()
    return ExpeditionAuto.buyAnvil and ExpeditionAuto.autoUseAnvil and ExpeditionAuto.autoCards and #ExpeditionAuto.statPriority > 0
end
local function expeditionRepairConfigured()
    return ExpeditionAuto.buyRepair and ExpeditionAuto.autoUseRepair
end
local function expeditionConfiguredTomeKind(trait)
    if trait == "Unbound" then
        return expeditionTraitSelected(ExpeditionAuto.damageTraits, trait) and "Damage" or nil
    end
    if expeditionTraitSelected(ExpeditionAuto.farmTraits, trait) then return "Farm" end
    if expeditionTraitSelected(ExpeditionAuto.damageTraits, trait) then return "Damage" end
    return nil
end
local function expeditionHotbarFull()
    local hotbar = expeditionPeek(Dependencies.HotbarState)
    local slots = hotbar and expeditionPeek(hotbar.Slots)
    local occupied = 0
    for _ in pairs(type(slots) == "table" and slots or {}) do occupied += 1 end
    local maxSlots = tonumber(hotbar and expeditionPeek(hotbar.MaxSlots))
    return maxSlots ~= nil and occupied >= maxSlots
end
local function expeditionHotbarItemCount(asset)
    local hotbar = expeditionPeek(Dependencies.HotbarState)
    local slots = hotbar and expeditionPeek(hotbar.Slots)
    local count = 0
    for _, slot in pairs(type(slots) == "table" and slots or {}) do
        local data = type(slot) == "table" and expeditionPeek(slot.Data)
        if type(slot) == "table" and slot.AssetType == "Item" and data and data.Asset == asset then
            count += tonumber(slot.Amount) or tonumber(data.Amount) or 1
        end
    end
    return count
end
local function expeditionOwnsItem(asset)
    if expeditionHotbarItem(asset) then return true end
    local playerData = expeditionPeek(Dependencies.PlayerData)
    local itemData = playerData and expeditionPeek(playerData.ItemData)
    local item = itemData and expeditionPeek(itemData[asset])
    return type(item) == "table" and (tonumber(item.Amount) or 0) > 0
end
local function expeditionUseHotbarItem(item, gameUnitId)
    if not item or not item.slot or not gameUnitId then return false, "item slot or target missing" end
    require(FusionPackage.Shared).SelectedHotbarIndex:set(item.slot)
    task.wait(0.35)
    local abilityId
    for _, value in ipairs(getgc(true)) do
        if type(value) == "table" and rawget(value, "Id") and rawget(value, "Token") == "AbilityInput" then
            if not abilityId or value.Id > abilityId then abilityId = value.Id end
        end
    end
    if not abilityId then return false, "AbilityInput replica missing" end
    ReplicatedStorage.RemoteEvents.ReplicaSignal:FireServer(abilityId, "Response", gameUnitId)
    return true
end
local function expeditionTomeTarget(item, queuedKind)
    if not item then return nil, nil end
    local trait = item.data and item.data.Trait
    local kind = expeditionConfiguredTomeKind(trait)
    if trait == "Unbound" then
        return expeditionPlacedTarget("Damage", {skipUnboundTargets = true, skipExistingUnbound = true}), "Damage"
    end
    if kind == "Farm" then
        return expeditionPlacedTarget("Farm", {
            traitFilter = function(currentTrait, hasTrait)
                return not hasTrait or not expeditionTraitSelected(ExpeditionAuto.farmTraits, currentTrait)
            end,
        }), "Farm"
    end
    if kind == "Damage" then
        return expeditionPlacedTarget("Damage", {
            traitFilter = function(currentTrait, hasTrait)
                return currentTrait ~= "Unbound" and (not hasTrait or not expeditionTraitSelected(ExpeditionAuto.damageTraits, currentTrait))
            end,
        }), "Damage"
    end
    -- Unconfigured non-Farm Tomes may fill empty Damage units, but never overwrite a Trait.
    return expeditionPlacedTarget("Damage", {
        traitless = true,
    }), "Damage"
end
local function expeditionTomeWithTarget()
    local bestItem, bestTarget, bestKind, bestPriority
    for _, item in ipairs(expeditionHotbarItems("ExpeditionTome")) do
        local target, kind = expeditionTomeTarget(item)
        if target and target.gameUnitId then
            local trait = item.data and item.data.Trait
            local priority = trait == "Unbound" and 0 or (expeditionConfiguredTomeKind(trait) and 1 or 2)
            if not bestPriority or priority < bestPriority then
                bestItem, bestTarget, bestKind, bestPriority = item, target, kind, priority
            end
        end
    end
    return bestItem, bestTarget, bestKind
end
local function expeditionNeedsAnyTome()
    for trait, selected in pairs(ExpeditionAuto.damageTraits or {}) do
        if selected then
            local target = expeditionTomeTarget({data = {Trait = trait}})
            if target and target.gameUnitId then return true end
        end
    end
    for trait, selected in pairs(ExpeditionAuto.farmTraits or {}) do
        if selected and trait ~= "Unbound" then
            local target = expeditionTomeTarget({data = {Trait = trait}})
            if target and target.gameUnitId then return true end
        end
    end
    return false
end
local function expeditionPlaceUsingMacroRemote(slot, cframe)
    local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
    local replicaSignal = remoteEvents and remoteEvents:FindFirstChild("ReplicaSignal")
    if not replicaSignal then return false end

    local replicaId = getgenv().CachedGamePlayerDataId
    if not replicaId then
        for _, value in pairs(getgc(true)) do
            if type(value) == "table" and rawget(value, "Id") and rawget(value, "Token") == "GamePlayerData" then
                if not replicaId or value.Id > replicaId then replicaId = value.Id end
            end
        end
        getgenv().CachedGamePlayerDataId = replicaId
    end
    if not replicaId then return false end

    replicaSignal:FireServer(replicaId, "PlaceGameUnit", slot, cframe)
    return true
end
local function expeditionUpgradeButtons()
    local buttons, seen, container = {}, {}, nil
    local roots = {LocalPlayer.PlayerGui:FindFirstChild("CardSelection"), LocalPlayer.PlayerGui:FindFirstChild("Prompt")}
    for _, root in ipairs(roots) do
        if root then
        for _, object in ipairs(root:GetDescendants()) do
            if object:IsA("TextLabel") and object.Visible and object.Text == "Select Upgrade" then
                local button = object:FindFirstAncestorWhichIsA("TextButton")
                if button and button.Visible and not seen[button] then
                    seen[button] = true
                    container = container or root
                    table.insert(buttons, button)
                end
            end
        end
        end
    end
    table.sort(buttons, function(a, b) return a.AbsolutePosition.X < b.AbsolutePosition.X end)
    return buttons, container
end
local function expeditionIsStatAnvilPrompt(container)
    if not container then return false end
    for _, object in ipairs(container:GetDescendants()) do
        if object:IsA("TextLabel") and object.Visible and object.Text == "Stat Anvil" then return true end
    end
    return false
end
local function expeditionNormalizedLabel(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
end
local function expeditionTryCards()
    if not ExpeditionAuto.autoCards then return end
    local buttons, prompt = expeditionUpgradeButtons()
    if #buttons > 0 and expeditionIsStatAnvilPrompt(prompt) and not expeditionAnvilConfigured() then return end
    if expeditionRuntime.cardPending then
        if #buttons == 0 then
            print("[EXP CARD] Selection confirmed: " .. expeditionRuntime.cardPending.label)
            expeditionRuntime.cardPending = nil
            expeditionRuntime.lastCard = tick()
        elseif tick() - expeditionRuntime.cardPending.sentAt < 0.75 then
            return
        else
            warn("[EXP CARD] Selection not confirmed after 0.75s; retrying " .. expeditionRuntime.cardPending.label)
            expeditionRuntime.cardPending = nil
        end
    end
    if #buttons == 0 then return end
    local knownNames = {}
    for id, card in pairs(require(SharedInfo.GameUpgradesInfo).Cards or {}) do knownNames[expeditionNormalizedLabel(card.Name or id)] = card.Name or id end
    for stat in pairs(ExpeditionInfo.StatAnvils.Stats or {}) do knownNames[expeditionNormalizedLabel(stat)] = stat end
    local entries = {}
    for buttonIndex, button in ipairs(buttons) do
        local entry = {button = button, name = "Card #" .. buttonIndex, texts = {}}
        local ancestor = button.Parent
        for _ = 1, 8 do
            if not ancestor or ancestor == prompt then break end
            local selectButtons = 0
            for _, object in ipairs(ancestor:GetDescendants()) do
                if object:IsA("TextLabel") and object.Text == "Select Upgrade" then
                    local selectButton = object:FindFirstAncestorWhichIsA("TextButton")
                    if selectButton and selectButton:IsDescendantOf(ancestor) then selectButtons += 1 end
                end
            end
            if selectButtons == 1 then
                local foundName
                for _, object in ipairs(ancestor:GetDescendants()) do
                    if object:IsA("TextLabel") and object.Visible then
                        entry.texts[object.Text] = true
                        local knownName = knownNames[expeditionNormalizedLabel(object.Text)]
                        if knownName then foundName = object.Text end
                    end
                end
                if foundName then entry.name = foundName; break end
            end
            ancestor = ancestor.Parent
        end
        table.insert(entries, entry)
    end
    local choice, reason
    for _, wanted in ipairs(ExpeditionAuto.upgradePriority) do
        local normalizedWanted = expeditionNormalizedLabel(wanted)
        for index, entry in ipairs(entries) do
            for text in pairs(entry.texts) do if expeditionNormalizedLabel(text) == normalizedWanted then choice, reason = index, "upgradePriority=" .. wanted break end end
            if choice then break end
        end
        if choice then break end
    end
    if not choice then
        for _, wanted in ipairs(ExpeditionAuto.statPriority) do
            local normalizedWanted = expeditionNormalizedLabel(wanted)
            for index, entry in ipairs(entries) do
                for text in pairs(entry.texts) do if expeditionNormalizedLabel(text) == normalizedWanted then choice, reason = index, "statPriority=" .. wanted break end end
                if choice then break end
            end
            if choice then break end
        end
    end
    if not choice then
        choice = ExpeditionAuto.cardFallback == "Random" and math.random(1, #entries) or 1
        reason = "fallback=" .. tostring(ExpeditionAuto.cardFallback)
    end
    local labels = {}
    for index, entry in ipairs(entries) do labels[index] = entry.name end
    local signature = table.concat(labels, " | ")
    if expeditionRuntime.lastCardSignature ~= signature then expeditionRuntime.lastCardSignature = signature; print("[EXP CARD] Options: " .. signature) end
    local button = entries[choice] and entries[choice].button
    if not button then return end
    local responseKey = signature .. ":" .. tostring(button.AbsolutePosition)
    print("[EXP CARD] Choosing " .. labels[choice] .. " because " .. reason)
    local ok, err = pcall(function()
        if type(firesignal) ~= "function" then error("firesignal is unavailable") end
        firesignal(button.Activated)
    end)
    if ok then
        expeditionRuntime.cardPending = {key = responseKey, label = labels[choice], sentAt = tick()}
    else
        warn("[EXP CARD] Click failed: " .. tostring(err))
    end
end
local function expeditionTryHire()
    if not ExpeditionAuto.autoHire or tick() - expeditionRuntime.lastHire < 2 then return end
    local state, replica = expeditionState(), expeditionGameReplica()
    if not state or state.status ~= "Checkpoint" or not replica then return end
    for _, wanted in ipairs(ExpeditionAuto.helperPriority) do
        if wanted ~= "" and string.find(wanted, "EVO", 1, true) then
            for key, helper in pairs(replica.Data.Helpers or {}) do
                if helper.Asset == wanted and not expeditionRuntime.hired[key] then
                    local ok, err = pcall(function() replica:FireServer("HireHelper", key) end)
                    if ok then print("[EXP AUTO] Hire helper: " .. tostring(helper.Asset)) else warn("[EXP AUTO] Hire helper failed: " .. tostring(err)) end
                    expeditionRuntime.hired[key] = true
                    expeditionRuntime.lastHire = tick()
                    return
                end
        end
    end
end
end
local function expeditionTryHelpers()
    local replica = expeditionGameReplica()
    if not replica then return end
    local increment = replica.Data and replica.Data.GameIncrement
    if expeditionRuntime.helperGameIncrement ~= increment then
        expeditionRuntime.helperGameIncrement = increment
        expeditionRuntime.helperPending = {}
        expeditionRuntime.helperUsedPositions = {}
        expeditionRuntime.unboundTargets = {}
    end
    local playerState = expeditionPeek(Dependencies.GamePlayerState)
    local totalPlaced = tonumber(playerState and expeditionPeek(playerState.TotalUnitsPlaced)) or 0
    for helperKey, helper in pairs(replica.Data.Helpers or {}) do
        local slot = tonumber(helper.Slot or helper.HotbarSlot)
        if slot then
            local priority
            for index, asset in ipairs(ExpeditionAuto.helperPriority) do if asset == helper.Asset then priority = index break end end
            local pending = priority and expeditionRuntime.helperPending[helperKey]
            if pending and not pending.done and tick() - pending.sentAt >= 1.25 then
                if totalPlaced > pending.before then pending.done = true else pending.position = pending.position + 1; pending.sentAt = 0 end
            end
            if priority and (not pending or (not pending.done and pending.sentAt == 0)) then
                local position = pending and pending.position or 1
                local savedPositions = ExpeditionAuto.helperPositions[priority] or {}
                local savedPosition = savedPositions[position]
                local positionKey = savedPosition and table.concat(savedPosition, ":")
                if savedPosition and not expeditionRuntime.helperUsedPositions[positionKey] then
                    local cframe = CFrame.new(unpack(savedPosition))
                    local ok, sent = pcall(expeditionPlaceUsingMacroRemote, slot, cframe)
                    if ok and sent then
                        expeditionRuntime.helperPending[helperKey] = {position = position, sentAt = tick(), before = totalPlaced}
                        expeditionRuntime.helperUsedPositions[positionKey] = true
                        print("[EXP AUTO] Place helper " .. tostring(helper.Asset) .. " at saved position " .. position)
                    else
                        pending = {position = position + 1, sentAt = 0}
                        expeditionRuntime.helperPending[helperKey] = pending
                    end
                end
        end
    end
end
end
local function expeditionTryShop()
    expeditionRuntime.shopPhase = "gate"
    if not ExpeditionAuto.autoShop or tick() - expeditionRuntime.lastBuy < 1 then return end
    if #expeditionUpgradeButtons() > 0 then expeditionRuntime.shopPhase = "upgrade popup open"; return end
    expeditionRuntime.shopPhase = "get replica"
    local state, replica = expeditionState(), expeditionShopReplica()
    if not state or state.status ~= "Checkpoint" or not replica then return end
    if ExpeditionAuto.autoUseTome and expeditionTomeWithTarget() then return end
    if expeditionAnvilConfigured() and expeditionHotbarItem("ExpeditionStatAnvil") then return end
    if expeditionRuntime.pendingAnvilPurchaseAt then
        if expeditionRuntime.lastCard > expeditionRuntime.pendingAnvilPurchaseAt then
            expeditionRuntime.pendingAnvilPurchaseAt = nil
        elseif tick() - expeditionRuntime.pendingAnvilPurchaseAt < 10 then
            return
        else
            warn("[EXP SHOP] Anvil purchase was not observed after 10s; allowing one retry")
            expeditionRuntime.pendingAnvilPurchaseAt = nil
        end
    end
    if expeditionRuntime.firstCheckpointIncrement ~= state.increment then
        expeditionRuntime.firstCheckpointIncrement = state.increment
        expeditionRuntime.lastShopScan = tick()
        print("[EXP AUTO] First checkpoint: skipping shop for GameIncrement " .. tostring(state.increment))
        return
    end
    expeditionRuntime.lastShopScan = tick()
    local playerState = expeditionPeek(Dependencies.GamePlayerState)
    local yen = tonumber(playerState and expeditionPeek(playerState.Yen)) or 0
    local repairCount = expeditionHotbarItemCount("ExpeditionRepair")
    expeditionRuntime.repairPurchaseAvailable = false
    if expeditionRuntime.lastRepairCount ~= repairCount then
        expeditionRuntime.lastRepairCount = repairCount
        print("[EXP SHOP] Repair count: " .. repairCount .. "/2")
    end
    if expeditionRuntime.pendingRepairCount then
        if repairCount > expeditionRuntime.pendingRepairCount then
            print("[EXP SHOP] Repair purchase confirmed: " .. repairCount .. "/2")
            expeditionRuntime.pendingRepairCount = nil
        elseif tick() - expeditionRuntime.pendingRepairAt < 2 then
            return
        else
            print("[EXP SHOP] Repair request finished; waiting for a new shop refresh")
            expeditionRuntime.pendingRepairCount = nil
        end
    end
    for shopKey, shop in pairs(replica.Data.Shops or {}) do
        expeditionRuntime.shopPhase = "scan tome " .. tostring(shopKey)
        local hasWantedTome = false
        local snapshot = {}
        local refreshVersion = tonumber(replica.Data.Refreshes and replica.Data.Refreshes[shopKey]) or 0
        local shopCycleKey = table.concat({tostring(replica.Data.DataKey), tostring(shopKey), tostring(state.increment), tostring(refreshVersion)}, ":")
        for index, item in ipairs(shop.Items or {}) do
            table.insert(snapshot, table.concat({tostring(item.Name), tostring(item.Stock), tostring(item.Data and item.Data.Trait)}, ":"))
            if item.Name == "ExpeditionTome" and expeditionTomeConfigured() and not expeditionHotbarFull() and not expeditionRuntime.tomePurchasedCycles[shopCycleKey] then
                local trait = item.Data and item.Data.Trait
                local tomeKind = expeditionConfiguredTomeKind(trait)
                local tomeTarget = tomeKind and expeditionTomeTarget({data = {Trait = trait}})
                if not tomeTarget or not tomeTarget.gameUnitId then tomeKind = nil end
                local itemWanted = tomeKind ~= nil and (item.Stock == nil or item.Stock > 0)
                    if itemWanted then
                        local requestKey = shopCycleKey .. ":" .. index .. ":" .. trait .. ":" .. tostring(item.Stock)
                        if expeditionRuntime.shopPurchaseRequests[requestKey] then
                            itemWanted = false
                        elseif yen >= (tonumber(item.Price) or math.huge) then
                            expeditionRuntime.shopPhase = "purchase tome"
                            expeditionRuntime.shopPurchaseRequests[requestKey] = true
                            local ok, err = pcall(function() replica:FireServer("PurchaseItem", shopKey, index, 1) end)
                            if not ok then
                                expeditionRuntime.shopPurchaseRequests[requestKey] = nil
                                warn("[EXP AUTO] Tome purchase request failed: " .. tostring(err))
                                return
                            end
                            expeditionRuntime.tomePurchasedCycles[shopCycleKey] = true
                            table.insert(expeditionRuntime.tomeQueue, tomeKind)
                            print("[EXP AUTO] Purchase requested: ExpeditionTome - " .. trait)
                            expeditionRuntime.lastBuy = tick()
                            expeditionRuntime.lastShopAction = tick()
                            return
                        elseif tick() - expeditionRuntime.lastNoYenLog >= 3 then
                            expeditionRuntime.lastNoYenLog = tick()
                            print("[EXP SHOP] Not enough Yen for selected Tome; continuing")
                        end
                        hasWantedTome = hasWantedTome or itemWanted
                    end
                end
            end
        local snapshotKey = shopCycleKey .. ":" .. table.concat(snapshot, "|")
        if hasWantedTome then return end
        if expeditionRepairConfigured() and repairCount < 2 and not expeditionRuntime.repairPurchasedSnapshots[shopCycleKey] then
            for index, item in ipairs(shop.Items or {}) do
                if item.Name == "ExpeditionRepair" and (item.Stock == nil or item.Stock > 0) then
                    if yen < (tonumber(item.Price) or math.huge) then
                        if tick() - expeditionRuntime.lastNoYenLog >= 3 then
                            expeditionRuntime.lastNoYenLog = tick()
                            print("[EXP SHOP] Not enough Yen for Repair; continuing")
                        end
                        return
                    end
                    expeditionRuntime.repairPurchaseAvailable = true
                    expeditionRuntime.shopPhase = "purchase repair"
                    local ok, err = pcall(function() replica:FireServer("PurchaseItem", shopKey, index, 1) end)
                    if not ok then warn("[EXP SHOP] Repair purchase request failed: " .. tostring(err)); return end
                    expeditionRuntime.repairPurchasedSnapshots[shopCycleKey] = true
                    expeditionRuntime.pendingRepairCount = repairCount
                    expeditionRuntime.pendingRepairAt = tick()
                    expeditionRuntime.lastShopAction = tick()
                    print("[EXP SHOP] Decision: buy Repair (" .. repairCount .. "/2)")
                    return
                end
            end
        end
        local maxRefreshes = tonumber(shop.MaxRefreshes)
        local usedRefreshes = refreshVersion
        local canRefresh = maxRefreshes == nil or usedRefreshes < maxRefreshes
        local usesFiniteStock = (expeditionRepairConfigured() and repairCount < 2)
            or (expeditionTomeConfigured() and not expeditionHotbarFull() and expeditionNeedsAnyTome())
        if usesFiniteStock and canRefresh and expeditionRuntime.refreshedShopSnapshots[snapshotKey] == nil and tick() - expeditionRuntime.lastBuy > 1.5 then
            expeditionRuntime.shopPhase = "refresh"
            local ok, err = pcall(function() replica:FireServer("Refresh", shopKey) end)
            if ok then
                expeditionRuntime.refreshedShopSnapshots[snapshotKey] = true
                expeditionRuntime.lastShopAction = tick()
                print("[EXP AUTO] Refresh requested: no selected Tome traits in " .. tostring(shopKey))
                return
            else
                warn("[EXP AUTO] Shop refresh failed: " .. tostring(err))
            end
        end
        -- Only after Tome purchase/refresh is resolved may the shop buy support items.
        if not expeditionAnvilConfigured() or expeditionOwnsItem("ExpeditionStatAnvil") then return end
        for index, item in ipairs(shop.Items or {}) do
            expeditionRuntime.shopPhase = "scan support"
            local buy = item.Name == "ExpeditionStatAnvil"
            if buy and yen >= (tonumber(item.Price) or math.huge) then
                expeditionRuntime.shopPhase = "purchase support"
                local ok, err = pcall(function() replica:FireServer("PurchaseItem", shopKey, index, 1) end)
                if not ok then warn("[EXP AUTO] Support purchase request failed: " .. tostring(err)); return end
                expeditionRuntime.pendingAnvilPurchaseAt = tick()
                print("[EXP AUTO] Purchase requested: " .. item.Name)
                expeditionRuntime.lastBuy = tick()
                expeditionRuntime.lastShopAction = tick()
                return
            end
        end
    end
end
local function expeditionTryItems()
    if tick() - expeditionRuntime.lastUse < 2 then return end
    local cardPopupOpen = #expeditionUpgradeButtons() > 0
    if cardPopupOpen then
        if tick() - (expeditionRuntime.lastItemWaitLog or 0) >= 5 then
            expeditionRuntime.lastItemWaitLog = tick()
            print("[EXP AUTO] Item use waiting for active card selection to close")
        end
        return
    end
    local item, target, kind = expeditionTomeWithTarget()
    if ExpeditionAuto.autoUseTome and item then
        local trait = item.data and item.data.Trait
        local isUnbound = trait == "Unbound"
        if target and target.gameUnitId then
            print("[EXP AUTO] Tome request: trait=" .. tostring(item and item.data and item.data.Trait) .. " slot=" .. tostring(item and item.slot) .. " target=" .. tostring(target.asset) .. " gameUnitId=" .. tostring(target.gameUnitId))
            local ok, sent, err = pcall(expeditionUseHotbarItem, item, target.gameUnitId)
            if ok and sent then
                if isUnbound then expeditionRuntime.unboundTargets[target.gameUnitId] = true end
                task.delay(0.75, function()
                    local stillOwned = expeditionOwnsItem("ExpeditionTome")
                    local gameUnits = expeditionPeek(Dependencies.GameUnits)
                    local placedData = target.id and gameUnits and expeditionPeek(gameUnits[target.id])
                    local unitData = placedData and (expeditionPeek(placedData.UnitData) or placedData.UnitData)
                    if isUnbound then expeditionRuntime.unboundTargets[target.gameUnitId] = unitData and unitData.Trait == "Unbound" or nil end
                    print("[EXP AUTO] Tome verify: hotbarPresent=" .. tostring(stillOwned) .. " target=" .. tostring(target.asset) .. " trait=" .. tostring(unitData and unitData.Trait))
                end)
            else
                warn("[EXP AUTO] Tome use failed: " .. tostring(sent or err))
            end
            if ok and sent and #expeditionRuntime.tomeQueue > 0 then table.remove(expeditionRuntime.tomeQueue, 1) end
            expeditionRuntime.lastUse = tick()
            return
        end
    end
    if ExpeditionAuto.autoUseTome and not item then
        local heldTomes = expeditionHotbarItems("ExpeditionTome")
        if #heldTomes > 0 and tick() - (expeditionRuntime.lastTomeTargetLog or 0) >= 5 then
            expeditionRuntime.lastTomeTargetLog = tick()
            local labels = {}
            for _, held in ipairs(heldTomes) do
                local trait = held.data and held.data.Trait
                local kind = expeditionConfiguredTomeKind(trait) or "FreeDamage"
                table.insert(labels, "slot=" .. tostring(held.slot) .. " trait=" .. tostring(trait) .. " kind=" .. kind)
            end
            print("[EXP TOME] Held but no traitless target: " .. table.concat(labels, " | "))
        end
    end
    local state = expeditionState()
    if expeditionRepairConfigured() and state and state.status ~= "Checkpoint" and state.health and state.maxHealth and state.health < state.maxHealth then
        local repair = expeditionHotbarItem("ExpeditionRepair")
        if repair then
            require(FusionPackage.Shared).SelectedHotbarIndex:set(repair.slot)
            print("[EXP AUTO] Repair selected from hotbar slot " .. tostring(repair.slot) .. " at " .. tostring(state.health) .. "/" .. tostring(state.maxHealth) .. " HP")
            expeditionRuntime.lastUse = tick()
            return
        end
    end
    if expeditionAnvilConfigured() and expeditionOwnsItem("ExpeditionStatAnvil") then
        local item = expeditionHotbarItem("ExpeditionStatAnvil")
        if not item then return end
        require(FusionPackage.Shared).SelectedHotbarIndex:set(item.slot)
        print("[EXP AUTO] Anvil selected from hotbar slot " .. tostring(item.slot) .. "; waiting for card choice")
        expeditionRuntime.lastUse = tick()
    end
end
local function expeditionDrainOrbs()
    if expeditionRuntime.orbDrainActive or #expeditionRuntime.orbQueue == 0 then return end
    expeditionRuntime.orbDrainActive = true
    task.spawn(function()
        local sent = 0
        while ExpeditionAuto.autoOrbs and expeditionRuntime.orbGameStateId and #expeditionRuntime.orbQueue > 0 do
            local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
            local replicaSignal = remoteEvents and remoteEvents:FindFirstChild("ReplicaSignal")
            if not replicaSignal then break end
            local pickupKey = table.remove(expeditionRuntime.orbQueue, 1)
            local ok, err = pcall(function()
                replicaSignal:FireServer(expeditionRuntime.orbGameStateId, "CollectPickup", pickupKey)
            end)
            if ok then
                sent = sent + 1
            else
                expeditionRuntime.orbGameStateId = nil
                warn("[EXP AUTO] Orb pickup failed for " .. tostring(pickupKey) .. ": " .. tostring(err))
                break
            end
            task.wait() -- One pickup per frame avoids a client-frame spike.
        end
        if sent > 0 then print("[EXP AUTO] Orb burst completed: " .. sent .. " pickups") end
        expeditionRuntime.orbDrainActive = false
    end)
end
local function expeditionTryOrbs()
    if not ExpeditionAuto.autoOrbs then return end
    local now = tick()
    if now - expeditionRuntime.lastOrbScan >= ExpeditionAuto.orbScanDelay then
        expeditionRuntime.lastOrbScan = now
        local startedAt = tick()
        local replica = expeditionGameReplica()
        local pickups = replica and replica.Data and replica.Data.RewardPickups or {}
        expeditionRuntime.orbQueue = {}
        for key in pairs(pickups) do table.insert(expeditionRuntime.orbQueue, key) end
        if not expeditionRuntime.orbGameStateId then
            for _, value in pairs(getgc(true)) do
                if type(value) == "table" and rawget(value, "Id") and rawget(value, "Token") == "GameState" then
                    expeditionRuntime.orbGameStateId = value.Id
                    break
                end
            end
        end
        print(string.format("[EXP AUTO] Orb scan: %d pending in %.3fs; next scan in %ss", #expeditionRuntime.orbQueue, tick() - startedAt, tostring(ExpeditionAuto.orbScanDelay)))
        expeditionDrainOrbs()
    end
end
local function expeditionTryContinue()
    if not ExpeditionAuto.autoContinue then expeditionRuntime.continueScheduledAt = nil; expeditionRuntime.continueWatchdog = nil; return end
    local now = tick()
    local state = expeditionState()
    if not state then return end
    if state.status == "Checkpoint" and state.current == "InProgress" then
        local checkpointKey = tostring(state.increment) .. ":" .. tostring(state.status)
        local newCheckpoint = expeditionRuntime.checkpointKey ~= checkpointKey
        if newCheckpoint then
            if tonumber(state.increment) and tonumber(state.increment) <= 1 then
                expeditionRuntime.checkpointOrdinal = 1
            else
                expeditionRuntime.checkpointOrdinal = (expeditionRuntime.checkpointOrdinal or 0) + 1
            end
        end
        if newCheckpoint
            or not expeditionRuntime.checkpointLastObserved
            or now - expeditionRuntime.checkpointLastObserved > 1.5 then
            expeditionRuntime.checkpointKey = checkpointKey
            expeditionRuntime.checkpointEnteredAt = now
            expeditionRuntime.checkpointForceSent = false
        end
        expeditionRuntime.checkpointLastObserved = now
    else
        expeditionRuntime.checkpointKey = nil
        expeditionRuntime.checkpointEnteredAt = nil
        expeditionRuntime.checkpointLastObserved = nil
        expeditionRuntime.checkpointForceSent = false
    end
    if appConfig.autoPlayEnabled and state.status == "Checkpoint" and state.current == "InProgress"
        and (expeditionRuntime.checkpointOrdinal or 0) >= 2
        and expeditionRuntime.checkpointEnteredAt and tick() - expeditionRuntime.checkpointEnteredAt >= 20
        and not expeditionRuntime.checkpointForceSent then
        local replica = expeditionGameReplica()
        expeditionRuntime.checkpointForceSent = true
        expeditionRuntime.continueScheduledAt = nil
        expeditionRuntime.continueWatchdog = nil
        expeditionRuntime.lastContinue = tick()
        if replica then
            local ok, err = pcall(function() replica:FireServer("Continue") end)
            if ok then
                print("[EXP CONTINUE] Forced after 20s at Checkpoint #" .. tostring(expeditionRuntime.checkpointOrdinal))
            else
                expeditionRuntime.checkpointForceSent = false
                warn("[EXP CONTINUE] Forced request failed: " .. tostring(err))
            end
        else
            expeditionRuntime.checkpointForceSent = false
            warn("[EXP CONTINUE] Forced request failed: GameState replica missing")
        end
        return
    end
    local stateSignature = table.concat({tostring(state.current), tostring(state.status), tostring(state.wave), tostring(state.increment), tostring(state.enemyCount), tostring(state.active)}, "|")
    if expeditionRuntime.continueWatchdog then
        local watchdog = expeditionRuntime.continueWatchdog
        local progressed = (state.enemyCount > watchdog.enemyCount and state.enemyCount > 0)
            or state.current ~= watchdog.current or state.status ~= watchdog.status
            or state.wave ~= watchdog.wave or state.increment ~= watchdog.increment
        if now - watchdog.sentAt >= 30 and not progressed then
            local replica = expeditionGameReplica()
            print("[EXP CONTINUE] No progress for 30s; returning Lobby")
            if replica then pcall(function() replica:FireServer("Lobby") end) end
            expeditionRuntime.continueWatchdog = nil
            expeditionRuntime.lastContinue = now
        elseif progressed then
            print("[EXP CONTINUE] Watchdog: progress detected " .. stateSignature)
            expeditionRuntime.continueWatchdog = nil
        elseif stateSignature ~= expeditionRuntime.lastContinueState then
            expeditionRuntime.lastContinueState = stateSignature
            print("[EXP CONTINUE] Watchdog: " .. stateSignature)
        end
        return
    end
    local blocker
    if isPlaying then blocker = "Macro đang chạy"
    elseif getgenv().ExpeditionContinueBlocked then blocker = "đang chờ Macro Expedition"
    elseif state.status ~= "Checkpoint" or state.current ~= "InProgress" then blocker = "state=" .. state.current .. "/" .. state.status
    elseif ExpeditionAuto.autoShop and expeditionRuntime.lastShopScan == 0 then blocker = "Shop chưa scan"
    elseif ExpeditionAuto.autoShop and now - expeditionRuntime.lastShopAction < 2 then blocker = "Shop vừa mua/refresh"
    elseif ExpeditionAuto.autoShop and expeditionRepairConfigured() and expeditionRuntime.pendingRepairCount then blocker = "đang xác nhận mua Búa"
    elseif ExpeditionAuto.autoShop and expeditionRepairConfigured() and expeditionHotbarItemCount("ExpeditionRepair") < 2 and expeditionRuntime.repairPurchaseAvailable then blocker = "Búa sửa dưới 2" end
    if not blocker and ExpeditionAuto.autoUseTome then
        local tomeItem, tomeTarget = expeditionTomeWithTarget()
        if tomeItem and tomeTarget then blocker = "Sách Trait còn target hợp lệ" end
    end
    if not blocker and expeditionAnvilConfigured() and expeditionHotbarItem("ExpeditionStatAnvil") then blocker = "Đe chưa dùng" end
    if not blocker and ExpeditionAuto.autoCards and expeditionRuntime.cardPending then blocker = "đang xác nhận Card" end
    local upgradeButtons, prompt = expeditionUpgradeButtons()
    if not blocker and ExpeditionAuto.autoCards and #upgradeButtons > 0 then
        local statAnvilPopup = expeditionIsStatAnvilPrompt(prompt)
        if not statAnvilPopup or expeditionAnvilConfigured() then blocker = "Card đang mở" end
    end
    if not blocker and ExpeditionAuto.autoUseTome then
        for _, object in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
            if object:IsA("TextLabel") and object.Visible and object.Text:match("^Apply .- Tome$") then blocker = "đang chọn target Tome" break end
        end
    end
    if blocker then
        expeditionRuntime.continueScheduledAt = nil
        if expeditionRuntime.lastContinueBlock ~= blocker then
            expeditionRuntime.lastContinueBlock = blocker
            print("[EXP CONTINUE] Blocked by: " .. blocker)
        end
        return
    end
    expeditionRuntime.lastContinueBlock = ""
    if now - expeditionRuntime.lastContinue < ExpeditionAuto.continueDelay + 3 then return end
    if not expeditionRuntime.continueScheduledAt then
        expeditionRuntime.continueScheduledAt = now
        expeditionRuntime.continueScheduledState = stateSignature
        print("[EXP CONTINUE] Ready; waiting " .. tostring(ExpeditionAuto.continueDelay) .. "s")
        return
    end
    if expeditionRuntime.continueScheduledState ~= stateSignature then
        expeditionRuntime.continueScheduledAt = nil
        print("[EXP CONTINUE] Scheduled request cancelled: state changed")
        return
    end
    if now - expeditionRuntime.continueScheduledAt < ExpeditionAuto.continueDelay then return end
    local replica = expeditionGameReplica()
    if not replica then warn("[EXP CONTINUE] Request failed: GameState replica missing"); expeditionRuntime.continueScheduledAt = nil; return end
    local ok, err = pcall(function() replica:FireServer("Continue") end)
    expeditionRuntime.continueScheduledAt = nil
    expeditionRuntime.lastContinue = now
    if not ok then warn("[EXP CONTINUE] Request failed: " .. tostring(err)); return end
    expeditionRuntime.continueWatchdog = {sentAt = now, current = state.current, status = state.status, wave = state.wave, increment = state.increment, enemyCount = state.enemyCount}
    expeditionRuntime.lastContinueState = stateSignature
    print("[EXP CONTINUE] Request sent via GameState " .. tostring(replica.Id) .. ": " .. stateSignature)
end

local helperEvoOptions, traitOptions, upgradeOptions, statOptions = {""}, {}, {}, {}
for _, helper in pairs(ExpeditionInfo.Helpers.List or {}) do if helper.Asset and string.find(helper.Asset, "EVO", 1, true) then table.insert(helperEvoOptions, helper.Asset) end end
for trait in pairs(ExpeditionTraits.TraitData or {}) do table.insert(traitOptions, trait) end
for id, card in pairs(require(SharedInfo.GameUpgradesInfo).Cards or {}) do table.insert(upgradeOptions, card.Name or id) end
for stat in pairs(ExpeditionInfo.StatAnvils.Stats or {}) do table.insert(statOptions, stat) end
table.sort(helperEvoOptions); table.sort(traitOptions); table.sort(upgradeOptions); table.sort(statOptions)
local helperPositionParagraphs = {}
local tomeTraitParagraph
local function expeditionTomeTraitSummary()
    local function selected(set)
        local values = expeditionListFromDropdown(set)
        return #values > 0 and table.concat(values, ", ") or "None"
    end
    return "Damage: " .. selected(ExpeditionAuto.damageTraits) .. "\nFarm: " .. selected(ExpeditionAuto.farmTraits)
end
local function refreshExpeditionTomeTraitSummary()
    if tomeTraitParagraph then tomeTraitParagraph:SetDesc(expeditionTomeTraitSummary()) end
end
local function helperPositionSummary(index)
    local lines = {}
    for positionIndex, position in ipairs(ExpeditionAuto.helperPositions[index] or {}) do
        local cframe = CFrame.new(unpack(position))
        local point = cframe.Position
        table.insert(lines, string.format("%d. %.0f, %.0f, %.0f", positionIndex, point.X, point.Y, point.Z))
    end
    return #lines > 0 and table.concat(lines, "\n") or "No saved position. Click Record, then place one real unit."
end
getgenv().ExpeditionAutoRefreshHelperPositions = function()
    for index, paragraph in pairs(helperPositionParagraphs) do
        if paragraph then paragraph:SetDesc(helperPositionSummary(index)) end
    end
end

Tabs.Macro:AddSection("Tự Động Expedition")
Tabs.Macro:AddParagraph({Title = "Tự Động Kích Hoạt", Content = "Tự chạy khi vào Expedition và Macro của map có ít nhất một lệnh. Macro rỗng sẽ không chạy automation."})
Tabs.Macro:AddSection("Tự Chọn Nâng Cấp")
Tabs.Macro:AddToggle("ExpeditionAutoCards", {Title = "Tự chọn Nâng cấp / Đe", Default = ExpeditionAuto.autoCards}):OnChanged(function(value) ExpeditionAuto.autoCards = value; saveConfig() end)
Tabs.Macro:AddDropdown("ExpeditionAutoCardsPriority", {Title = "Ưu tiên Nâng cấp", Values = upgradeOptions, Multi = true, Default = ExpeditionAuto.upgradePriority}):OnChanged(function(value) ExpeditionAuto.upgradePriority = expeditionListFromDropdown(value); saveConfig() end)
Tabs.Macro:AddDropdown("ExpeditionAutoCardFallback", {Title = "Chọn dự phòng", Values = {"First", "Random"}, Multi = false, Default = ExpeditionAuto.cardFallback}):OnChanged(function(value) ExpeditionAuto.cardFallback = value; saveConfig() end)
Tabs.Macro:AddSection("Tự Chọn Đe")
Tabs.Macro:AddParagraph({Title = "Ưu Tiên Chỉ Số Đe", Content = "Tự chọn chỉ số Đe đầu tiên có trong danh sách ưu tiên."})
Tabs.Macro:AddDropdown("ExpeditionAutoStats", {Title = "Chọn chỉ số Đe", Values = statOptions, Multi = true, Default = ExpeditionAuto.statPriority}):OnChanged(function(value) ExpeditionAuto.statPriority = expeditionListFromDropdown(value); saveConfig() end)
Tabs.Macro:AddToggle("ExpeditionAutoAnvil", {Title = "Tự mua / dùng Đe", Default = ExpeditionAuto.buyAnvil and ExpeditionAuto.autoUseAnvil}):OnChanged(function(value) ExpeditionAuto.buyAnvil = value; ExpeditionAuto.autoUseAnvil = value; saveConfig() end)
Tabs.Macro:AddSection("Cửa Hàng Checkpoint")
Tabs.Macro:AddParagraph({Title = "Trait Sách Cần Mua", Content = "Chỉ mua Sách có Trait phù hợp với danh sách đã chọn và Unit tương ứng đã được đặt."})
Tabs.Macro:AddDropdown("ExpeditionAutoDamageTraits", {Title = "Damage Unit Tome Traits", Values = traitOptions, Multi = true, Default = expeditionListFromDropdown(ExpeditionAuto.damageTraits)}):OnChanged(function(value) ExpeditionAuto.damageTraits = expeditionSetFromDropdown(value); saveConfig(); refreshExpeditionTomeTraitSummary(); print("[EXP AUTO] Saved damage traits: " .. table.concat(expeditionListFromDropdown(ExpeditionAuto.damageTraits), ", ")) end)
local function saveFarmTraits(value)
    ExpeditionAuto.farmTraits = expeditionSetFromDropdown(value)
    saveConfig()
    refreshExpeditionTomeTraitSummary()
    print("[EXP AUTO] Saved farm traits: " .. table.concat(expeditionListFromDropdown(ExpeditionAuto.farmTraits), ", "))
end
Tabs.Macro:AddDropdown("ExpeditionAutoFarmTraits", {Title = "Trait Unit Farm", Values = traitOptions, Multi = true, Default = expeditionListFromDropdown(ExpeditionAuto.farmTraits), Callback = saveFarmTraits}):OnChanged(saveFarmTraits)
tomeTraitParagraph = Tabs.Macro:AddParagraph({Title = "Trait Đang Chọn", Content = expeditionTomeTraitSummary()})
Tabs.Macro:AddToggle("ExpeditionAutoShop", {Title = "Tự mua Shop Checkpoint", Default = ExpeditionAuto.autoShop}):OnChanged(function(value) ExpeditionAuto.autoShop = value; saveConfig() end)
Tabs.Macro:AddToggle("ExpeditionAutoTome", {Title = "Tự mua / dùng Sách Trait", Default = ExpeditionAuto.buyTome and ExpeditionAuto.autoUseTome}):OnChanged(function(value) ExpeditionAuto.buyTome = value; ExpeditionAuto.autoUseTome = value; saveConfig() end)
Tabs.Macro:AddToggle("ExpeditionAutoRepair", {Title = "Tự mua Búa / sửa Payload", Default = ExpeditionAuto.buyRepair and ExpeditionAuto.autoUseRepair}):OnChanged(function(value) ExpeditionAuto.buyRepair = value; ExpeditionAuto.autoUseRepair = value; saveConfig() end)
Tabs.Macro:AddToggle("ExpeditionAutoOrbs", {Title = "Tự nhặt Orb", Default = ExpeditionAuto.autoOrbs}):OnChanged(function(value) ExpeditionAuto.autoOrbs = value; saveConfig() end)
Tabs.Macro:AddInput("ExpeditionAutoOrbScanDelay", {Title = "Orb Scan Delay (seconds)", Default = tostring(ExpeditionAuto.orbScanDelay), Numeric = true, Finished = true, Callback = function(value) ExpeditionAuto.orbScanDelay = math.max(5, tonumber(value) or 10); saveConfig() end})
Tabs.Macro:AddToggle("ExpeditionAutoContinue", {Title = "Tự tiếp tục", Default = ExpeditionAuto.autoContinue}):OnChanged(function(value) ExpeditionAuto.autoContinue = value; saveConfig() end)
Tabs.Macro:AddInput("ExpeditionAutoContinueDelay", {Title = "Thời gian chờ tiếp tục", Default = tostring(ExpeditionAuto.continueDelay), Numeric = true, Finished = true, Callback = function(value) ExpeditionAuto.continueDelay = math.max(0, tonumber(value) or 3); saveConfig() end})
Tabs.Macro:AddSection("Vị Trí Helper Expedition")
Tabs.Macro:AddToggle("ExpeditionAutoHire", {Title = "Tự thuê Helper EVO", Default = ExpeditionAuto.autoHire}):OnChanged(function(value) ExpeditionAuto.autoHire = value; saveConfig() end)
for index = 1, 10 do
    Tabs.Macro:AddDropdown("ExpeditionHelper" .. index, {Title = "Helper Priority " .. index, Values = helperEvoOptions, Multi = false, Default = ExpeditionAuto.helperPriority[index]}):OnChanged(function(value) ExpeditionAuto.helperPriority[index] = value or ""; saveConfig() end)
    Tabs.Macro:AddButton({
        Title = "Record Helper " .. index .. " Position",
        Description = "Click, place one real unit at the wanted spot, then the game restarts and saves this full CFrame.",
        Callback = function()
            installMacroHook()
            if not isExpeditionGame() then
                Fluent:Notify({Title = "Expedition Only", Content = "Enter an Expedition before recording a helper position.", Duration = 3})
                return
            end
            getgenv().ExpeditionAutoHelperCapture = {priority = index}
            Fluent:Notify({Title = "Place A Unit", Content = "Place one real unit at the helper position now.", Duration = 5})
        end,
    })
    helperPositionParagraphs[index] = Tabs.Macro:AddParagraph({Title = "Helper " .. index .. " Saved Positions", Content = helperPositionSummary(index)})
    Tabs.Macro:AddButton({
        Title = "Clear Helper " .. index .. " Positions",
        Callback = function()
            ExpeditionAuto.helperPositions[index] = {}
            saveConfig()
            getgenv().ExpeditionAutoRefreshHelperPositions()
        end,
    })
end

task.spawn(function()
    while task.wait(0.5) do
        if expeditionAutomationActive() then
            expeditionLogState()
            expeditionRun("Cards", expeditionTryCards)
            expeditionRun("Helpers", expeditionTryHelpers)
            expeditionRun("Hire", expeditionTryHire)
            expeditionRun("Shop", expeditionTryShop)
            expeditionRun("Items", expeditionTryItems)
            expeditionRun("Orbs", expeditionTryOrbs)
            expeditionRun("Continue", expeditionTryContinue)
        end
    end
end)
