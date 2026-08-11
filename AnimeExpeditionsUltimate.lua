local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local ScriptContext = game:GetService("ScriptContext")
local LocalPlayer = Players.LocalPlayer
do
    local earlyState = getgenv().KickBlockConnectionLost or {}
    getgenv().KickBlockConnectionLost = earlyState
    earlyState.enabled = true
    earlyState.kickAttempts = earlyState.kickAttempts or 0
    earlyState.kickBlocks = earlyState.kickBlocks or 0
    earlyState.delayBlocks = earlyState.delayBlocks or 0
    earlyState.errorConnectionBlocks = earlyState.errorConnectionBlocks or 0
    earlyState.disconnectedErrorConnections = earlyState.disconnectedErrorConnections or 0

    if typeof(getconnections) == "function" then
        for _, connection in ipairs(getconnections(ScriptContext.Error)) do
            if pcall(function() connection:Disconnect() end) then
                earlyState.disconnectedErrorConnections += 1
            end
        end
    end
    if not earlyState.hookedNamecall and typeof(hookmetamethod) == "function" and typeof(newcclosure) == "function" then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if self == ScriptContext.Error and (method == "Connect" or method == "Once")
                and (typeof(checkcaller) ~= "function" or not checkcaller()) then
                earlyState.errorConnectionBlocks += 1
                return oldNamecall(self, function() end)
            end
            if self == LocalPlayer and method == "Kick" then
                earlyState.kickAttempts += 1
                earlyState.kickBlocks += 1
                return nil
            end
            return oldNamecall(self, ...)
        end))
        earlyState.hookedNamecall = true
    end
    if not earlyState.hookedIndexKick and typeof(hookmetamethod) == "function" and typeof(newcclosure) == "function" then
        local oldIndex
        oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
            if self == LocalPlayer and key == "Kick" then
                return function(player, ...)
                    if player == LocalPlayer then
                        earlyState.kickAttempts += 1
                        earlyState.kickBlocks += 1
                        return nil
                    end
                    return oldIndex(self, key)(player, ...)
                end
            end
            return oldIndex(self, key)
        end))
        earlyState.hookedIndexKick = true
    end
    if LocalPlayer and not earlyState.hookedFunctionKick and typeof(hookfunction) == "function" and typeof(newcclosure) == "function" then
        pcall(function()
            local oldKick
            oldKick = hookfunction(LocalPlayer.Kick, newcclosure(function(self, ...)
                if self == LocalPlayer then
                    earlyState.kickAttempts += 1
                    earlyState.kickBlocks += 1
                    return nil
                end
                return oldKick(self, ...)
            end))
            earlyState.hookedFunctionKick = true
        end)
    end
    if not earlyState.hookedTaskDelay and typeof(hookfunction) == "function" and typeof(newcclosure) == "function" then
        pcall(function()
            local oldDelay
            oldDelay = hookfunction(task.delay, newcclosure(function(delayTime, callback, ...)
                local looksLikeKick = type(callback) ~= "function"
                if type(callback) == "function" and debug and typeof(debug.getconstants) == "function" then
                    local ok, constants = pcall(debug.getconstants, callback)
                    looksLikeKick = not ok
                    if ok then
                        for _, constant in ipairs(constants) do
                            if type(constant) == "string" and constant:lower():find("kick", 1, true) then looksLikeKick = true break end
                        end
                    end
                end
                local numericDelay = tonumber(delayTime)
                if numericDelay and numericDelay >= 30 and numericDelay <= 60 and looksLikeKick then
                    earlyState.delayBlocks += 1
                    return task.spawn(function() end)
                end
                return oldDelay(delayTime, callback, ...)
            end))
            earlyState.hookedTaskDelay = true
        end)
    end
end
local scriptGeneration = {}
getgenv().AnimeExpeditionsScriptGeneration = scriptGeneration
getgenv().AnimeExpeditionsMapSwitchPending = false
getgenv().AnimeExpeditionsMapSwitchRestartDispatch = false
getgenv().AnimeExpeditionsAutoJoinCooldownUntil = 0
getgenv().AnimeExpeditionsJoinLock = nil
local function expeditionScriptIsCurrent()
    return getgenv().AnimeExpeditionsScriptGeneration == scriptGeneration
end
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
    if getgenv().AnimeExpeditionsMapSwitchPending
        and not (actionName == "Restart" and getgenv().AnimeExpeditionsMapSwitchRestartDispatch) then return false end
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
state.errorConnectionBlocks = state.errorConnectionBlocks or 0
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
        local ok = false
        if connection ~= diagnosticConnection then
            ok = pcall(function()
                connection:Disconnect()
            end)
        end
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
        if self == ScriptContext.Error and (method == "Connect" or method == "Once") and not checkcaller() then
            state.errorConnectionBlocks += 1
            log(("blocked ScriptContext.Error:%s listener, blocked=%d"):format(method, state.errorConnectionBlocks))
            return oldNamecall(self, function() end)
        end
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
            task.wait(2)
            disconnectErrorConnections("watchdog")
            if not diagnosticConnection or not diagnosticConnection.Connected then connectDiagnostic() end
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
        errorConnectionBlocks = state.errorConnectionBlocks,
        disconnectedErrorConnections = state.disconnectedErrorConnections,
        uptime = os.clock() - startedAt,
    }
end
log("loaded. Use getgenv().ErrorCheckSafe(label, fn) and getgenv().KickBlockStatus()")
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
    Language = "English",
    autoSummonEnabled = false,
    autoSummonBanners = {},
    autoSummonUnits = {},
    autoSummonAmount = 1,
    EventAuto = {
        autoGuessUnit = false,
        guessDifficulties = {"Normal", "Hard"},
        autoBossBounty = false,
        bossBountyAutoReroll = false,
        bossBountyKeepRarities = {"Rare", "Legendary", "Secret"},
        bossBountyMapMacros = {},
        autoDragonWish = false,
        dragonWishMapMacros = {},
        autoRedeemWish = false,
        wishUnitId = nil,
    },
    QuestAuto = {Enabled = false, MapMacros = {}, ActiveTarget = nil},
    storyMapMacros = {},
    autoChallengeEnabled = false,
    autoDailyChallengeEnabled = false,
    challengeAutoSelectedSlots = {['1'] = true, ['2'] = true, ['3'] = true},
    challengeMapMacros = {},
    challengeActiveTarget = nil,
    challengeSkippedSlots = {ResetKey = "", Slots = {}},
    AutoJoin = "",
    autoJoinEnabled = false,
    autoJoinTeamEnabled = false,
    autoCraftEnabled = false,
    autoCraftItems = {},
    autoExpeditionCraftEnabled = false,
    autoExpeditionCraftItems = {},
    autoShopEnabled = false,
    ShopSelections = {},
    TeamSelections = {},
    Macros = {},
    autoRecordEnabled = false,
    autoPlayEnabled = false,
    skipExpeditionDefenseMacro = false,
    expeditionAutoVoteStart = false,
    autoRestartInf = false,
    restartWaveNum = 50,
    autoLeaveSpriteMax = false,
    autoLeaveExpeditionScrapMax = false,
    expeditionScrapCraftPending = false,
    expeditionScrapCraftPendingSince = 0,
    autoLeaveOnDefeat = false,
    autoLeaveOnPlayerJoin = false,
    autoLeaveAfterMinutes = false,
    autoLeaveAfterMinutesValue = 30,
    AntiAFK = true,
    MobileToggle = true,
    WebhookUrl = "",
    webhookWinEnabled = false,
    webhookSummonEnabled = true,
    autoClaimQuests = false,
    autoClaimBP = false,
    autoClaimCalendar = false,
    autoClaimMilestones = false,
    autoClaimIndex = false,
    autoClaimAchievements = false,
    autoRedeemCodes = false,
    hidePlayerNames = false,
    fixLagEnabled = false,
    fpsCap = 60,
    AutoStatRoll = {Enabled = false, Rarities = {}, Stats = {}, Grades = {Z = true, SSS = true}, Webhook = true},
    ExpeditionAuto = nil,
    LobbyMaintenance = {Epoch = 0, Phase = "Idle", Reasons = {}, RequestedAt = 0, StatRoll = {}}
}
local playerID = tostring(game.Players.LocalPlayer.UserId)
local folderName = "AnimeExpeditions_" .. playerID
local SaveManager
local autoSaveFolderPath = folderName .. "/AutoSave"
local autoSaveConfigPath = autoSaveFolderPath .. "/autosave.json"
local splitLobbyConfigPath = autoSaveFolderPath .. "/lobby.json"
local splitIngameConfigPath = autoSaveFolderPath .. "/ingame.json"
local legacyLobbyConfigPath = folderName .. "/lobby.json"
local legacyIngameConfigPath = folderName .. "/ingame.json"
local macrosFolderPath = folderName .. "/macros"
if makefolder then
    if not isfolder(folderName) then makefolder(folderName) end
    if not isfolder(autoSaveFolderPath) then makefolder(autoSaveFolderPath) end
    if not isfolder(macrosFolderPath) then makefolder(macrosFolderPath) end
end
local lobbyConfigKeys = {
    "Language",
    "autoSummonEnabled", "autoSummonBanners", "autoSummonUnits", "autoSummonAmount",
    "EventAuto", "QuestAuto", "storyMapMacros",
    "autoChallengeEnabled", "autoDailyChallengeEnabled", "challengeAutoSelectedSlots", "challengeMapMacros", "challengeActiveTarget", "challengeSkippedSlots",
    "AutoJoin", "autoJoinEnabled", "autoJoinTeamEnabled", "autoJoinMode", "autoCraftEnabled", "autoCraftItems", "autoExpeditionCraftEnabled", "autoExpeditionCraftItems", "autoShopEnabled", "ShopSelections", "TeamSelections",
    "autoClaimQuests", "autoClaimBP", "autoClaimCalendar", "autoClaimMilestones", "autoClaimIndex", "autoClaimAchievements", "autoRedeemCodes", "hidePlayerNames", "fixLagEnabled", "fpsCap", "autoLeaveAfterMinutes", "autoLeaveAfterMinutesValue", "AutoStatRoll"
}
local ingameConfigKeys = {
    "autoRecordEnabled", "autoPlayEnabled", "skipExpeditionDefenseMacro", "expeditionAutoVoteStart", "autoRestartInf", "restartWaveNum", "autoLeaveSpriteMax", "autoLeaveExpeditionScrapMax", "expeditionScrapCraftPending", "expeditionScrapCraftPendingSince", "autoLeaveOnDefeat", "autoLeaveOnPlayerJoin", "AntiAFK", "MobileToggle", "WebhookUrl", "webhookWinEnabled", "webhookSummonEnabled", "ExpeditionAuto", "LobbyMaintenance"
}
local function normalizeLanguage(value)
    return value == "Tiếng Việt" and "Tiếng Việt" or "English"
end
local function loadConfig()
    if not isfile then return end
    local savedMacroBackup = nil
    if isfile(autoSaveConfigPath) then
        local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(autoSaveConfigPath)) end)
        if ok and type(decoded) == "table" then
            local lobbyData = type(decoded.lobby) == "table" and decoded.lobby or {}
            local ingameData = type(decoded.ingame) == "table" and decoded.ingame or {}
            for k, v in pairs(lobbyData) do appConfig[k] = v end
            for k, v in pairs(ingameData) do appConfig[k] = v end
            if type(ingameData.Macros) == "table" then savedMacroBackup = ingameData.Macros end
        end
    else
        local lobbyLoadPath = isfile(splitLobbyConfigPath) and splitLobbyConfigPath or legacyLobbyConfigPath
        local ingameLoadPath = isfile(splitIngameConfigPath) and splitIngameConfigPath or legacyIngameConfigPath
        if isfile(lobbyLoadPath) then
            local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(lobbyLoadPath)) end)
            if ok and type(decoded) == "table" then
                for k, v in pairs(decoded) do appConfig[k] = v end
            end
            getgenv().AnimeExpeditionsMigrateAutoSave = true
        end
        if isfile(ingameLoadPath) then
            local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(ingameLoadPath)) end)
            if ok and type(decoded) == "table" then
                for k, v in pairs(decoded) do appConfig[k] = v end
                if type(decoded.Macros) == "table" then savedMacroBackup = decoded.Macros end
            end
            getgenv().AnimeExpeditionsMigrateAutoSave = true
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
    appConfig.Language = normalizeLanguage(appConfig.Language)
    local lobbyData = {}
    for _, k in ipairs(lobbyConfigKeys) do lobbyData[k] = appConfig[k] end
    local ingameData = {}
    for _, k in ipairs(ingameConfigKeys) do ingameData[k] = appConfig[k] end
    pcall(function()
        writefile(autoSaveConfigPath, HttpService:JSONEncode({lobby = lobbyData, ingame = ingameData}))
        for mapName, macroData in pairs(appConfig.Macros) do
            local safeName = mapName:gsub("[^%w%-_]", "")
            if safeName ~= "" then
                writefile(macrosFolderPath .. "/" .. safeName .. ".json", HttpService:JSONEncode(macroData))
            end
        end
    end)
    if SaveManager then
        pcall(function() SaveManager:Save("Auto Save") end)
    end
end
logInit("Đang tải Config...")
loadConfig()
appConfig.Language = normalizeLanguage(appConfig.Language)
if getgenv().AnimeExpeditionsCleanLegacyIngameConfig or getgenv().AnimeExpeditionsMigrateAutoSave then
    saveConfig()
    getgenv().AnimeExpeditionsCleanLegacyIngameConfig = nil
    getgenv().AnimeExpeditionsMigrateAutoSave = nil
end
appConfig.ShopSelections = type(appConfig.ShopSelections) == "table" and appConfig.ShopSelections or {}
appConfig.autoCraftItems = type(appConfig.autoCraftItems) == "table" and appConfig.autoCraftItems or {}
appConfig.autoExpeditionCraftItems = type(appConfig.autoExpeditionCraftItems) == "table" and appConfig.autoExpeditionCraftItems or {}
appConfig.Macros = appConfig.Macros or {}
appConfig.autoSummonBanners = appConfig.autoSummonBanners or {}
appConfig.autoSummonUnits = appConfig.autoSummonUnits or {}
appConfig.EventAuto = type(appConfig.EventAuto) == "table" and appConfig.EventAuto or {}
appConfig.EventAuto.autoGuessUnit = appConfig.EventAuto.autoGuessUnit == true
appConfig.EventAuto.autoBossBounty = appConfig.EventAuto.autoBossBounty == true
appConfig.EventAuto.bossBountyAutoReroll = appConfig.EventAuto.bossBountyAutoReroll == true
appConfig.EventAuto.autoDragonWish = appConfig.EventAuto.autoDragonWish == true
appConfig.EventAuto.autoRedeemWish = appConfig.EventAuto.autoRedeemWish == true
appConfig.EventAuto.wishUnitId = appConfig.EventAuto.wishUnitId and tostring(appConfig.EventAuto.wishUnitId) or nil
appConfig.EventAuto.bossBountyMapMacros = type(appConfig.EventAuto.bossBountyMapMacros) == "table" and appConfig.EventAuto.bossBountyMapMacros or {}
appConfig.EventAuto.dragonWishMapMacros = type(appConfig.EventAuto.dragonWishMapMacros) == "table" and appConfig.EventAuto.dragonWishMapMacros or {}
do
local allowedFields = {
    guessDifficulties = {Normal = true, Hard = true},
    bossBountyKeepRarities = {Rare = true, Legendary = true, Secret = true},
}
local defaults = {
    guessDifficulties = {"Normal", "Hard"},
    bossBountyKeepRarities = {"Rare", "Legendary", "Secret"},
}
for field, allowed in pairs(allowedFields) do
    local selected, seen = {}, {}
    for key, value in pairs(type(appConfig.EventAuto[field]) == "table" and appConfig.EventAuto[field] or defaults[field]) do
        local option = type(key) == "number" and value or (value and key or nil)
        option = option and tostring(option) or nil
        if option and allowed[option] and not seen[option] then
            seen[option] = true
            table.insert(selected, option)
        end
    end
    appConfig.EventAuto[field] = selected
end
end
appConfig.QuestAuto = type(appConfig.QuestAuto) == "table" and appConfig.QuestAuto or {}
appConfig.QuestAuto.Enabled = appConfig.QuestAuto.Enabled == true
appConfig.QuestAuto.MapMacros = type(appConfig.QuestAuto.MapMacros) == "table" and appConfig.QuestAuto.MapMacros or {}
appConfig.QuestAuto.ActiveTarget = type(appConfig.QuestAuto.ActiveTarget) == "table" and appConfig.QuestAuto.ActiveTarget or nil
if not appConfig.QuestAuto.Enabled then appConfig.QuestAuto.ActiveTarget = nil end
appConfig.storyMapMacros = type(appConfig.storyMapMacros) == "table" and appConfig.storyMapMacros or {}
for key in pairs(appConfig) do
    if tostring(key):lower():find("b" .. "ounty", 1, true) then appConfig[key] = nil end
end
appConfig.challengeMapMacros = type(appConfig.challengeMapMacros) == "table" and appConfig.challengeMapMacros or {}
appConfig.autoChallengeEnabled = appConfig.autoChallengeEnabled == true
appConfig.autoDailyChallengeEnabled = appConfig.autoDailyChallengeEnabled == true
do
local selectedSlots = {}
for key, value in pairs(type(appConfig.challengeAutoSelectedSlots) == "table" and appConfig.challengeAutoSelectedSlots or {}) do
    local index = type(key) == "number" and tonumber(value) or (value and tonumber(key) or nil)
    if index and index >= 1 and index <= 3 then selectedSlots[tostring(index)] = true end
end
appConfig.challengeAutoSelectedSlots = selectedSlots
end
appConfig.challengeActiveTarget = type(appConfig.challengeActiveTarget) == "table" and appConfig.challengeActiveTarget or nil
if not appConfig.autoChallengeEnabled and not appConfig.autoDailyChallengeEnabled then appConfig.challengeActiveTarget = nil end
if type(appConfig.challengeActiveTarget) == "table" then
    local savedType = tostring(appConfig.challengeActiveTarget.ChallengeType or "Regular")
    if savedType == "Daily" and not appConfig.autoDailyChallengeEnabled
        or savedType ~= "Daily" and not appConfig.autoChallengeEnabled then appConfig.challengeActiveTarget = nil end
end
appConfig.challengeSkippedSlots = type(appConfig.challengeSkippedSlots) == "table" and appConfig.challengeSkippedSlots or {ResetKey = "", Slots = {}}
appConfig.challengeSkippedSlots.Slots = type(appConfig.challengeSkippedSlots.Slots) == "table" and appConfig.challengeSkippedSlots.Slots or {}
appConfig.AutoStatRoll = type(appConfig.AutoStatRoll) == "table" and appConfig.AutoStatRoll or {}
appConfig.AutoStatRoll.Enabled = appConfig.AutoStatRoll.Enabled == true
appConfig.AutoStatRoll.Webhook = appConfig.AutoStatRoll.Webhook ~= false
do
local allowed, fields = {
    Rarities = {Rare = true, Epic = true, Legendary = true, Mythic = true, Exclusive = true, Secret = true, Godly = true},
    Stats = {Damage = true, SPA = true, Range = true},
    Grades = {Z = true, SSS = true},
}, {"Rarities", "Stats", "Grades"}
for _, field in ipairs(fields) do
    local selected, seen = {}, {}
    for key, value in pairs(type(appConfig.AutoStatRoll[field]) == "table" and appConfig.AutoStatRoll[field] or {}) do
        local option = type(key) == "number" and value or (value and key or nil)
        option = option and tostring(option) or nil
        if option and allowed[field][option] and not seen[option] then seen[option] = true; table.insert(selected, option) end
    end
    table.sort(selected)
    appConfig.AutoStatRoll[field] = selected
end
if #appConfig.AutoStatRoll.Grades == 0 then appConfig.AutoStatRoll.Grades = {"Z", "SSS"} end
end
appConfig.ExpeditionAuto = type(appConfig.ExpeditionAuto) == "table" and appConfig.ExpeditionAuto or {}
appConfig.ExpeditionAuto.autoLobbyFuel = appConfig.ExpeditionAuto.autoLobbyFuel == true
if appConfig.ExpeditionAuto.autoLeaveFuel == nil then appConfig.ExpeditionAuto.autoLeaveFuel = appConfig.ExpeditionAuto.autoLobbyFuel end
appConfig.ExpeditionAuto.autoLeaveFuel = appConfig.ExpeditionAuto.autoLeaveFuel == true and appConfig.ExpeditionAuto.autoLobbyFuel
appConfig.ExpeditionAuto.fuelBuildings = type(appConfig.ExpeditionAuto.fuelBuildings) == "table" and appConfig.ExpeditionAuto.fuelBuildings or {"GoldMine", "ResourceDrill"}
appConfig.ExpeditionAuto.autoClaimBuildingRewards = appConfig.ExpeditionAuto.autoClaimBuildingRewards == true
appConfig.ExpeditionAuto.autoClaimQuestBoard = appConfig.ExpeditionAuto.autoClaimQuestBoard == true
appConfig.ExpeditionAuto.autoOpenGeodes = appConfig.ExpeditionAuto.autoOpenGeodes == true
appConfig.ExpeditionAuto.openGeodesWhenSpriteFull = appConfig.ExpeditionAuto.openGeodesWhenSpriteFull == true
do
local selected, seen = {}, {}
for key, value in pairs(type(appConfig.ExpeditionAuto.claimRewardBuildings) == "table" and appConfig.ExpeditionAuto.claimRewardBuildings or {"GoldMine", "ResourceDrill"}) do
    local building = type(key) == "number" and value or (value and key or nil)
    if (building == "GoldMine" or building == "ResourceDrill") and not seen[building] then seen[building] = true; table.insert(selected, building) end
end
table.sort(selected)
appConfig.ExpeditionAuto.claimRewardBuildings = selected
end
appConfig.ExpeditionAuto.autoSkillTree = appConfig.ExpeditionAuto.autoSkillTree == true
appConfig.ExpeditionAuto.autoTraining = appConfig.ExpeditionAuto.autoTraining == true
appConfig.ExpeditionAuto.autoLeaveTraining = appConfig.ExpeditionAuto.autoLeaveTraining == true and appConfig.ExpeditionAuto.autoTraining
appConfig.ExpeditionAuto.trainingTraitFilter = table.find({"All", "Has Trait", "No Trait"}, appConfig.ExpeditionAuto.trainingTraitFilter) and appConfig.ExpeditionAuto.trainingTraitFilter or "All"
appConfig.ExpeditionAuto.trainingRarities = type(appConfig.ExpeditionAuto.trainingRarities) == "table" and appConfig.ExpeditionAuto.trainingRarities or {"Mythic", "Secret"}
appConfig.ExpeditionAuto.trainingCompletionMode = table.find({"Level 50", "Potential 400%"}, appConfig.ExpeditionAuto.trainingCompletionMode) and appConfig.ExpeditionAuto.trainingCompletionMode or "Potential 400%"
appConfig.ExpeditionAuto.trainingUnitIds = type(appConfig.ExpeditionAuto.trainingUnitIds) == "table" and appConfig.ExpeditionAuto.trainingUnitIds or {}
appConfig.LobbyMaintenance = type(appConfig.LobbyMaintenance) == "table" and appConfig.LobbyMaintenance or {}
appConfig.LobbyMaintenance.Epoch = tonumber(appConfig.LobbyMaintenance.Epoch) or 0
appConfig.LobbyMaintenance.Phase = tostring(appConfig.LobbyMaintenance.Phase or "Idle")
appConfig.LobbyMaintenance.Reasons = type(appConfig.LobbyMaintenance.Reasons) == "table" and appConfig.LobbyMaintenance.Reasons or {}
appConfig.LobbyMaintenance.RequestedAt = tonumber(appConfig.LobbyMaintenance.RequestedAt) or 0
appConfig.LobbyMaintenance.StatRoll = type(appConfig.LobbyMaintenance.StatRoll) == "table" and appConfig.LobbyMaintenance.StatRoll or {}
if appConfig.expeditionScrapCraftPending then
    appConfig.LobbyMaintenance.Reasons.ExpeditionScrapCraft = true
    appConfig.LobbyMaintenance.Phase = "Queued"
end
local englishTranslations = {
    ["Ngôn ngữ"] = "Language",
    ["Đã lưu ngôn ngữ. Hãy chạy lại script để cập nhật toàn bộ giao diện."] = "Language saved. Rerun the script to update the full UI.",
    ["Import Macro từ link"] = "Import Macro from Link",
    ["Chỉ mục được tick sẽ ghi đè"] = "Only checked entries will be overwritten",
    ["Chọn tất cả"] = "Select All",
    ["Hủy"] = "Cancel",
    ["Import mục đã chọn"] = "Import Selected",
    ["ĐANG TREO"] = "RUNNING",
    ["TRẬN"] = "MATCHES",
    ["THỜI GIAN TREO"] = "RUN TIME",
    ["SỐ TRẬN ĐÃ ĐÁNH"] = "MATCHES PLAYED",
    ["PHẦN THƯỞNG ĐÃ NHẬN"] = "REWARDS RECEIVED",
    ["Chưa nhận được phần thưởng nào từ lúc script bắt đầu"] = "No rewards received since the script started",
    ["Vật phẩm nhận được trong quá trình farm."] = "An item received while farming.",
    ["nhận được"] = "received",
    ["đang có"] = "owned",
    ["LOẠI"] = "TYPE",
    ["TÊN PHẦN THƯỞNG"] = "REWARD NAME",
    ["SỐ LƯỢNG"] = "AMOUNT",
    ["VẬT PHẨM"] = "ITEM",
    ["VŨ KHÍ"] = "EQUIPMENT",
    ["Thông Tin"] = "Information",
    ["Tự động nhận quà và nhiệm vụ ngầm."] = "Automatically claims rewards and quests in the background.",
    ["Auto Claim Thành Tựu"] = "Auto Claim Achievements",
    ["Auto Nhập Code"] = "Auto Redeem Codes",
    ["Quét code active từ Anime Expeditions Wiki mỗi 10 phút."] = "Checks the Anime Expeditions Wiki for active codes every 10 minutes.",
    ["Tự động quét server và roll Unit nếu có trong Banner."] = "Scans servers and summons when a target Unit appears in a Banner.",
    ["Bật Auto Summon (Snipe)"] = "Enable Auto Summon (Snipe)",
    ["Tự hoàn thành các difficulty đã chọn mỗi ngày."] = "Completes the selected difficulties each day.",
    ["Roll và đánh tối đa 5 Boss Bounty mỗi ngày."] = "Rerolls and clears up to 5 Boss Bounties each day.",
    ["Tốn 5.000 Gold nếu rarity hiện tại không nằm trong danh sách giữ."] = "Spends 5,000 Gold when the current rarity is not in the keep list.",
    ["Boss rarity muốn giữ"] = "Boss rarities to keep",
    ["Đọc quest ShenronEvent runtime, tự claim và chạy objective được hỗ trợ."] = "Reads the live ShenronEvent quest, claims it, and runs supported objectives.",
    ["Mặc định tắt. Chỉ áp Unbound khi đã chọn UnitID DBZ hợp lệ."] = "Off by default. Applies Unbound only when a valid DBZ UnitID is selected.",
    ["DBZ Unit nhận Unbound"] = "DBZ Unit to receive Unbound",
    ["Boss Bounty - Macro Theo Map"] = "Boss Bounty - Macro by Map",
    ["Mỗi map chọn Macro riêng chỉ dùng khi Boss Bounty điều khiển trận."] = "Choose a separate Macro for each map, used only when Boss Bounty controls the match.",
    ["Dragon Wish - Macro Theo Map"] = "Dragon Wish - Macro by Map",
    ["Mỗi map chọn Macro riêng chỉ dùng khi Dragon Wish chạy objective."] = "Choose a separate Macro for each map, used only for Dragon Wish objectives.",
    ["Bật Auto Daily + Weekly Quest"] = "Enable Auto Daily + Weekly Quest",
    ["Ưu tiên Quest trước Challenge và Auto Join Map."] = "Prioritizes Quests over Challenges and Auto Join Map.",
    ["Macro Theo Map"] = "Macro by Map",
    ["Một Macro cho mỗi map, dùng khi Quest chạy Story, Infinite, Mastery hoặc Regular Challenge."] = "One Macro per map for Quest-controlled Story, Infinite, Mastery, or Regular Challenge matches.",
    ["Một Macro cho mọi Act"] = "One Macro for Every Act",
    ["Mỗi World chọn một Macro Story đã ghi ở bất kỳ Act nào. Macro tự chạy cho mọi Act của World này; chọn Không chọn để tắt. Quest và Challenge vẫn dùng Macro riêng."] = "Choose one recorded Story Macro per World. It runs for every Act in that World; choose None to disable it. Quests and Challenges still use separate Macros.",
    ["Bật Auto Regular Challenge"] = "Enable Auto Regular Challenge",
    ["Chạy các Regular Challenge khả dụng; khi cooldown sẽ nhường Auto Join Map."] = "Runs available Regular Challenges and yields to Auto Join Map during cooldown.",
    ["Tự chạy Daily Challenge"] = "Auto Run Daily Challenge",
    ["Ưu tiên Daily Challenge trước Regular; dùng Macro theo Map đã chọn bên dưới."] = "Prioritizes Daily Challenge over Regular and uses the selected Macro for each Map below.",
    ["Regular slot Auto Challenge sẽ chạy"] = "Regular Challenge slots to run",
    ["Mặc định chọn cả 3; bỏ chọn slot nào thì chỉ Auto Challenge skip slot đó."] = "All 3 are selected by default; deselected slots are skipped.",
    ["Mỗi map chọn một Macro chỉ dùng khi Auto Challenge điều khiển trận."] = "Choose one Macro per map, used only when Auto Challenge controls the match.",
    ["Tự động mua số lượng tối đa có thể của từng vật phẩm đã chọn, theo stock, tiền và giới hạn kho."] = "Buys as many selected items as possible within stock, currency, and inventory limits.",
    ["Bật Auto Shop"] = "Enable Auto Shop",
    ["Tự động ghép đồ khi đang ở Lobby."] = "Automatically crafts items while in the Lobby.",
    ["Bật Auto Craft (Lobby)"] = "Enable Auto Craft (Lobby)",
    ["Chọn đồ muốn Craft"] = "Select items to craft",
    ["Tự động Về Đảo khi Full Sprite (Grey)"] = "Return to Lobby when Sprite (Grey) is full",
    ["Tự động ghép trang bị tại Armory Forge khi đang ở Lobby."] = "Automatically crafts equipment at the Armory Forge while in the Lobby.",
    ["Bật Auto Craft Expedition"] = "Enable Auto Craft Expedition",
    ["Chọn đồ Expedition muốn Craft"] = "Select Expedition items to craft",
    ["Tự động Về Đảo khi Full Equipment Scrap"] = "Return to Lobby when Equipment Scrap is full",
    ["Chọn Map và bật Auto Join để tự động ghép trận."] = "Select a Map and enable Auto Join to start matching automatically.",
    ["Map Đang Chọn"] = "Selected Map",
    ["Chưa chọn Map nào"] = "No Map selected",
    ["Trạng Thái Join"] = "Join Status",
    ["Đang khởi tạo scheduler..."] = "Initializing scheduler...",
    ["Bật Auto Join Map Đang Chọn"] = "Enable Auto Join for Selected Map",
    ["Cài Đặt Đội Hình"] = "Team Setup",
    ["Chọn Team riêng cho từng Map; Auto Load Team dùng cấu hình này trước khi vào trận."] = "Choose a Team for each Map; Auto Load Team applies it before entering a match.",
    ["Tự động nạp Team (Auto Load Team)"] = "Auto Load Team",
    ["Chọn Map"] = "Select Map",
    ["Chế độ"] = "Mode",
    ["Chọn chế độ trước để lọc danh sách World."] = "Select a mode first to filter the World list.",
    ["Chỉ hiện map thuộc chế độ đã chọn."] = "Shows only maps in the selected mode.",
    ["Độ khó"] = "Difficulty",
    ["Hệ Thống Macro"] = "Macro System",
    ["Tự động nhận diện Map đang chơi để chạy Macro tương ứng."] = "Detects the current Map and runs its matching Macro.",
    ["Trạng Thái"] = "Status",
    ["Đang ở Lobby"] = "In Lobby",
    ["Ghi Macro Ván Mới (Tự Động)"] = "Record New Match Macro (Automatic)",
    ["Bấm 1 lần. Sẽ tự Restart, tự Ghi khi ván bắt đầu và tự Lưu khi hết ván."] = "Click once to restart, record when the match starts, and save when it ends.",
    ["Tối ưu Macro"] = "Optimize Macro",
    ["Tối ưu Macro nhanh nhất"] = "Optimize Macro timing",
    ["Bật Auto Play"] = "Enable Auto Play",
    ["Không chạy Macro ở map Defense"] = "Skip Macro on Defense maps",
    ["Bật: chỉ chạy Macro ở Assault. Tắt: chạy Macro ở mọi map Expedition."] = "On: run Macros only in Assault. Off: run them on every Expedition map.",
    ["Auto Restart (Chỉ Infinite)"] = "Auto Restart (Infinite Only)",
    ["Ví dụ: 50"] = "Example: 50",
    ["Tự động Thoát khi Thua (Defeat/Lose)"] = "Auto Leave on Defeat/Loss",
    ["Tự động Thoát khi có người vào phòng Solo"] = "Auto Leave when a player joins the Solo room",
    ["Chia Sẻ Macro / Config"] = "Share Macro / Config",
    ["Chia Sẻ Config"] = "Share Config",
    ["Dữ liệu Macro hoặc Link vĩnh viễn"] = "Macro Data or Permanent Link",
    ["Dán JSON Macro hoặc link animeexpeditionsmarcoshare..."] = "Paste Macro JSON or an animeexpeditionsmarcoshare link...",
    ["Dữ liệu Config hoặc Link vĩnh viễn"] = "Config Data or Permanent Link",
    ["Dán JSON Config hoặc link animeexpeditionsmarcoshare..."] = "Paste Config JSON or an animeexpeditionsmarcoshare link...",
    ["Nhận mã JSON cũ, bundle JSON hoặc link Macro vĩnh viễn."] = "Accepts legacy JSON, JSON bundles, or permanent Macro links.",
    ["Export Link vĩnh viễn (Map hiện tại)"] = "Export Permanent Link (Current Map)",
    ["Upload Macro của Map đang chơi và copy link không hết hạn."] = "Uploads the current Map Macro and copies a permanent link.",
    ["Export Link vĩnh viễn (Tất cả Macro)"] = "Export Permanent Link (All Macros)",
    ["Upload toàn bộ thư viện Macro và copy link không hết hạn."] = "Uploads the full Macro library and copies a permanent link.",
    ["Export Config thành Link vĩnh viễn"] = "Export Config as Permanent Link",
    ["Không gồm Macro, trạng thái chạy tạm thời hoặc Webhook URL."] = "Excludes Macros, temporary runtime state, and the Webhook URL.",
    ["Import Config từ Link / JSON"] = "Import Config from Link / JSON",
    ["Giữ nguyên Macro và Webhook URL; chạy lại script sau khi import."] = "Keeps Macros and the Webhook URL; rerun the script after importing.",
    ["Auto Vote Start (Chỉ Expedition)"] = "Auto Vote Start (Expedition Only)",
    ["Vào Expedition sẽ tạm bật; khi rời sẽ khôi phục trạng thái Auto Vote Start trước đó."] = "Temporarily enables it in Expeditions and restores the previous state afterward.",
    ["Tự động thoát sau X phút"] = "Auto Leave after X minutes",
    ["Yêu cầu bật Auto Join Map. Tính theo thời gian trận hiện tại."] = "Requires Auto Join Map. Uses the current match duration.",
    ["Thời gian Auto Leave (phút)"] = "Auto Leave time (minutes)",
    ["Ví dụ: 30"] = "Example: 30",
    ["Giới hạn FPS"] = "FPS Limit",
    ["Bật/tắt chế độ giảm đồ họa để đỡ lag"] = "Toggle reduced graphics to improve performance.",
    ["Nút Mở UI (Cho Mobile)"] = "Open UI Button (Mobile)",
    ["Nhận thông báo khi quay ra Unit xịn hoặc khi đi xong Map."] = "Receive notifications for rare summons or completed Maps.",
    ["Thông báo khi mở ra Mythic/Secret"] = "Notify on Mythic/Secret summon",
    ["Thông báo tổng kết khi Thắng Map"] = "Send summary after winning a Map",
    ["Buildings cần nạp Fuel"] = "Buildings to refuel",
    ["Tự nạp các building đã chọn khi ở Lobby; không yêu cầu Auto Join Map."] = "Refuels selected buildings in the Lobby; Auto Join Map is not required.",
    ["Auto Leave khi hết Fuel"] = "Auto Leave when Fuel runs out",
    ["Building hết Fuel thì thoát ngay để nạp; không ngắt Quest/Challenge. Bắt buộc Auto Fuel và Auto Join."] = "Leaves immediately to refuel an empty building without interrupting Quest/Challenge. Requires Auto Fuel and Auto Join.",
    ["Auto Claim và Auto Open"] = "Auto Claim and Auto Open",
    ["Claim rewards từ Gold Mine/Resource Drill tại Lobby. Auto Open mô phỏng Hold của game: phát một request mới mỗi 0.033333 giây."] = "Claims Gold Mine/Resource Drill rewards in the Lobby. Auto Open emulates the game's Hold action with one request every 0.033333 seconds.",
    ["Quét nhanh một lần mỗi khi vào Lobby; claim Expedition Weekly và toàn bộ milestone đã mở khóa trước Auto Join."] = "Scans once on entering the Lobby and claims Expedition Weekly rewards and unlocked milestones before Auto Join.",
    ["Buildings cần Auto Claim"] = "Buildings to Auto Claim",
    ["Tự claim reward đang tích trong các building đã chọn."] = "Claims accumulated rewards from selected buildings.",
    ["Vẫn mở khi SpriteGrey đầy"] = "Keep opening when SpriteGrey is full",
    ["Mở hết Geode tại Lobby bằng burst 0.033333 giây và giữ Auto Join đến khi hoàn tất."] = "Opens all Geodes in the Lobby at 0.033333-second intervals and holds Auto Join until complete.",
    ["Mặc định tắt. Khi bật sẽ ignore inventory limit; SpriteGrey vượt 125 có thể bị mất."] = "Off by default. Ignores the inventory limit when enabled; SpriteGrey above 125 may be lost.",
    ["Mở từng node đủ dependency, Research Lab level và nguyên liệu."] = "Unlocks each node when dependencies, Research Lab level, and materials are sufficient.",
    ["Điều kiện hoàn thành"] = "Completion Conditions",
    ["Tự tháo khi Unit đạt điều kiện Level hoặc Potential đang chọn, rồi lấp đủ Max Units. Chỉ scan Level 1 thuộc rarity đã chọn; luôn bỏ qua Locked, Favorited và Equipped."] = "Removes Units that meet the selected Level or Potential condition, then fills all slots. Scans only Level 1 Units of selected rarities and skips Locked, Favorited, and Equipped Units.",
    ["Auto Leave khi Training đủ điều kiện"] = "Auto Leave when Training completes",
    ["Đủ điều kiện thì thoát ngay để thay Unit; không ngắt Quest/Challenge. Bắt buộc Auto Training và Auto Join."] = "Leaves immediately to replace completed Units without interrupting Quest/Challenge. Requires Auto Training and Auto Join.",
    ["Điều kiện lấy Unit ra"] = "Unit removal condition",
    ["Chỉ cần đạt điều kiện đang chọn; không bắt buộc điều kiện còn lại."] = "Only the selected condition is required.",
    ["Rarity được phép Training"] = "Rarities allowed for Training",
    ["Chỉ đưa Unit thuộc rarity đã chọn; không chọn = không gửi Unit."] = "Uses only Units of selected rarities; no selection means no Units are sent.",
    ["Lọc Trait"] = "Trait Filter",
    ["Ưu tiên Unit Level 1 (không chọn = bất kỳ)"] = "Prioritize Level 1 Units (none = any)",
    ["Quy tắc an toàn"] = "Safety Rules",
    ["Chỉ bắt đầu Unit đúng 400% Potential, cần tối thiểu 4 StatReroll + 8 StatLock. Luôn bỏ qua Locked, Equipped, Favorited, Training và Unit đã có Z/SSS. Mỗi Unit tối đa 4 roll; không tự retry request chưa xác nhận."] = "Starts only Units at exactly 400% Potential with at least 4 StatReroll and 8 StatLock. Skips Locked, Equipped, Favorited, Training, and existing Z/SSS Units. Maximum 4 rolls per Unit; unconfirmed requests are not retried.",
    ["Bật Auto Stat Roll"] = "Enable Auto Stat Roll",
    ["Chỉ chạy khi đã về Lobby; không tự rời trận."] = "Runs only in the Lobby and never leaves a match automatically.",
    ["Rarity được phép Roll"] = "Rarities allowed for rolling",
    ["Stat mục tiêu"] = "Target Stats",
    ["Grade mục tiêu"] = "Target Grades",
    ["Webhook khi đạt Stat mục tiêu"] = "Webhook when a target Stat is reached",
    ["Hủy Unit đang Roll"] = "Cancel Current Unit Roll",
    ["Dừng phiên hiện tại; Unit dưới 400% sẽ không tự được chọn lại."] = "Stops the current session; Units below 400% will not be selected again.",
    ["Tự Động Expedition"] = "Expedition Automation",
    ["Tự Động Kích Hoạt"] = "Automatic Activation",
    ["Tự chạy khi vào Expedition và Macro của map có ít nhất một lệnh. Macro rỗng sẽ không chạy automation."] = "Runs on entering an Expedition when the Map Macro contains at least one action. Empty Macros do not start automation.",
    ["Tìm Route Reward"] = "Find Route Reward",
    ["Cách Hoạt Động"] = "How It Works",
    ["Tại checkpoint đầu: Restart đến khi Route Rewards có reward đã chọn rồi chạy Expedition. Nếu bật Sell All, sau khi qua Boss sẽ bán sạch unit rồi Extract tại checkpoint kế tiếp."] = "At the first checkpoint, restarts until Route Rewards contain a target reward, then runs the Expedition. With Sell All enabled, sells all Units after the Boss and extracts at the next checkpoint.",
    ["Reward cần tìm"] = "Target Reward",
    ["Tự Restart tìm Reward"] = "Auto Restart to Find Reward",
    ["Số lượng Reward tối thiểu"] = "Minimum Reward Amount",
    ["Delay giữa mỗi Restart"] = "Delay Between Restarts",
    ["Tự Chọn Nâng Cấp"] = "Auto Select Upgrades",
    ["Tự chọn Nâng cấp / Đe"] = "Auto Select Upgrades / Anvils",
    ["Set muốn build"] = "Sets to Build",
    ["Ưu tiên card mới tiến gần hoặc mở bonus Set; card thuộc hai Set được cộng điểm cả hai."] = "Prioritizes cards that advance or unlock Set bonuses; cards in two Sets score for both.",
    ["Tiến Độ Set"] = "Set Progress",
    ["Ưu tiên Nâng cấp"] = "Upgrade Priority",
    ["Chọn dự phòng"] = "Fallback Choice",
    ["Tự Chọn Đe"] = "Auto Select Anvil",
    ["Ưu Tiên Chỉ Số Đe"] = "Anvil Stat Priority",
    ["Tự chọn chỉ số Đe đầu tiên có trong danh sách ưu tiên."] = "Selects the first Anvil stat in the priority list.",
    ["Chọn chỉ số Đe"] = "Select Anvil Stats",
    ["Tự mua / dùng Đe"] = "Auto Buy / Use Anvil",
    ["Cửa Hàng Checkpoint"] = "Checkpoint Shop",
    ["Trait Sách Cần Mua"] = "Tome Traits to Buy",
    ["Chỉ mua Sách có Trait phù hợp với danh sách đã chọn và Unit tương ứng đã được đặt."] = "Buys only Tomes whose Trait matches the selected list and whose corresponding Unit has been placed.",
    ["Trait Unit Farm"] = "Farm Unit Traits",
    ["Trait Đang Chọn"] = "Selected Traits",
    ["Tự mua Shop Checkpoint"] = "Auto Buy from Checkpoint Shop",
    ["Tự mua / dùng Sách Trait"] = "Auto Buy / Use Trait Tomes",
    ["Tự mua Búa / sửa Payload"] = "Auto Buy Hammer / Repair Payload",
    ["Tự nhặt Orb"] = "Auto Collect Orbs",
    ["Tự tiếp tục"] = "Auto Continue",
    ["Thời gian chờ tiếp tục"] = "Continue Delay",
    ["Vị Trí Helper Expedition"] = "Expedition Helper Positions",
    ["Tự thuê Helper EVO"] = "Auto Hire EVO Helper",
    ["Lỗi"] = "Error",
    ["Phải ở trong Game mới được Record!"] = "Enter a match before recording.",
    ["Hãy tắt Auto Play trước khi ghi hình!"] = "Disable Auto Play before recording.",
    ["Đang Restart Expedition. Sẽ ghi tại Checkpoint mới."] = "Restarting the Expedition. Recording will begin at the new Checkpoint.",
    ["Đang khởi động lại ván đấu. Sẽ tự động ghi khi vào ván..."] = "Restarting the match. Recording will begin automatically.",
    ["Phải đứng trong Ải mới tối ưu được Macro!"] = "Enter a stage before optimizing a Macro.",
    ["Map hiện tại chưa có dữ liệu Macro!"] = "The current Map has no Macro data.",
    ["Đang khởi động lại ván đấu để chạy Macro từ đầu..."] = "Restarting the match to run the Macro from the beginning...",
    ["Không thể Export"] = "Unable to Export",
    ["Không thể mã hóa dữ liệu."] = "Unable to encode data.",
    ["Dữ liệu vượt giới hạn 2 MB."] = "Data exceeds the 2 MB limit.",
    ["Import thất bại"] = "Import Failed",
    ["Import thành công"] = "Import Successful",
    ["Chưa tick Macro nào."] = "No Macros selected.",
    ["Chưa nhập mã JSON hoặc link Macro!"] = "Enter Macro JSON or a link.",
    ["Chưa nhập JSON hoặc link Config!"] = "Enter Config JSON or a link.",
    ["Mã JSON không hợp lệ."] = "Invalid JSON.",
    ["API trả về dữ liệu không hợp lệ."] = "The API returned invalid data.",
    ["JSON kiểu cũ cần đứng trong Ải để xác định tên Macro."] = "Enter a stage so legacy JSON can determine the Macro name.",
    ["Phải đứng trong Ải mới Export được!"] = "Enter a stage before exporting.",
    ["Chưa có Macro nào ở Map này để Export!"] = "This Map has no Macro to export.",
    ["Link không hợp lệ"] = "Invalid Link",
    ["Chỉ nhận link từ animeexpeditionsmarcoshare.netlify.app."] = "Only animeexpeditionsmarcoshare.netlify.app links are accepted.",
    ["Tải link thất bại"] = "Link Download Failed",
    ["Upload thất bại"] = "Upload Failed",
    ["Đã tạo Link vĩnh viễn"] = "Permanent Link Created",
    ["Phải bật Auto Join Map trước khi bật tính năng Leave."] = "Enable Auto Join Map before enabling Auto Leave.",
    ["Đã tắt toàn bộ Auto Leave vì Auto Join Map đang tắt."] = "All Auto Leave options were disabled because Auto Join Map is off.",
    ["Hãy chọn ít nhất một building."] = "Select at least one building.",
    ["Phải bật Auto Fuel trước."] = "Enable Auto Fuel first.",
    ["Phải bật Auto Training Grounds trước."] = "Enable Auto Training Grounds first.",
    ["Hãy chọn ít nhất một Rarity, Stat và Grade."] = "Select at least one Rarity, Stat, and Grade.",
    ["Không thể hủy"] = "Cannot Cancel",
    ["Đang chờ server xác nhận một roll. Hủy lúc này có thể mất dấu request."] = "Waiting for the server to confirm a roll. Canceling now may lose track of the request.",
    ["Không có Unit đang roll."] = "No Unit is currently rolling.",
    ["Hãy chọn ít nhất một reward cần tìm."] = "Select at least one target reward.",
    ["Chưa Chọn Reward"] = "No Reward Selected",
    ["Chọn Equipment Reroll hoặc Equipment Lock trước khi bật."] = "Select Equipment Reroll or Equipment Lock before enabling.",
    ["Load xong!"] = "Loaded!",
    ["Đã tối ưu Macro"] = "Macro Optimized",
    ["Không thể Craft Expedition"] = "Unable to Craft Expedition Items",
    ["Phòng Lỗi"] = "Unexpected Player",
    ["Webhook payload bị từ chối"] = "Webhook Payload Rejected",
    ["Webhook đang chờ retry"] = "Webhook Awaiting Retry",
    ["Lỗi Gửi Discord"] = "Discord Send Error",
    ["Lỗi Build Embed"] = "Embed Build Error",
    ["Test Webhook Thắng Map"] = "Test Map Victory Webhook",
    ["Gửi thử Webhook với data giả lập"] = "Sends a test Webhook with sample data.",
    ["Tự Động Triệu Hồi Thành Công!"] = "Automatic Summon Successful!",
    ["Độ Hiếm"] = "Rarity",
    ["Auto Stat Roll đạt mục tiêu"] = "Auto Stat Roll Target Reached",
    ["Chỉ số"] = "Stat",
    ["Potential còn lại"] = "Remaining Potential",
    ["Tiến độ"] = "Progress",
    ["Toàn bộ stat"] = "All Stats",
    ["Không nhận được Item nào"] = "No items received",
    ["Không có Unit nào nhận EXP"] = "No Units gained EXP",
    ["Webhook URL trống!"] = "The Webhook URL is empty!",
    ["Lỗi HTTP Request"] = "HTTP request failed",
    ["Discord trả response không hợp lệ"] = "Discord returned an invalid response",
    ["Gửi Discord thành công!"] = "Discord message sent successfully!",
    ["Đang lấy phần thưởng để gửi Discord..."] = "Collecting rewards to send to Discord...",
    ["Không có phần thưởng mới, bỏ qua gửi Discord."] = "No new rewards; skipping the Discord message.",
    ["Controller lỗi 3 lần liên tiếp; đã tắt để mở khóa scheduler."] = "The controller failed 3 consecutive times and was disabled to unlock the scheduler.",
    ["Controller lỗi 3 lần liên tiếp; đã tắt để mở khóa Auto Join."] = "The controller failed 3 consecutive times and was disabled to unlock Auto Join.",
    ["Đã Craft xong. Đang tiếp tục Auto Join Expedition!"] = "Crafting complete. Resuming Auto Join Expedition!",
    ["Equipment Scrap vẫn đầy. Đã tắt riêng Auto Leave Equipment Scrap để tránh lặp vô hạn."] = "Equipment Scrap is still full. Auto Leave for Equipment Scrap was disabled to prevent an endless loop.",
    ["Phát hiện có người khác trong phòng Solo! Đang tự động thoát..."] = "Another player was detected in the Solo room. Leaving automatically...",
    ["Phát hiện thua cuộc! Đang tự động vứt trận về Lobby..."] = "Defeat detected. Returning to the Lobby automatically...",
    ["Đã đầy 250 Equipment Scrap. Đang tự động về sảnh để Craft!"] = "Equipment Scrap reached 250. Returning to the Lobby to craft automatically!",
    ["Đã bỏ qua Macro tại map Defense."] = "Skipped the Macro on the Defense map.",
    ["Hoàn tất kịch bản Macro!"] = "Macro playback complete!",
    ["Trận đấu kết thúc! Đã tự động TẮT và LƯU bản ghi Macro."] = "The match ended. Recording was stopped and the Macro was saved automatically.",
    ["Scheduler vừa bỏ qua một lỗi UI/game; sẽ thử lại tick kế tiếp."] = "The scheduler recovered from a UI/game error and will retry on the next tick.",
    ["Đang chờ dữ liệu Fuel..."] = "Waiting for Fuel data...",
    ["Đang chờ dữ liệu building..."] = "Waiting for building data...",
    ["Đang chờ dữ liệu Training Grounds..."] = "Waiting for Training Grounds data...",
    ["Bảng thông tin Stat Roll"] = "Stat Roll Details",
    ["Đang đọc UnitData..."] = "Reading UnitData...",
    ["Đọc lại UnitData và giữ các Unit ID còn hợp lệ."] = "Reloads UnitData and keeps valid Unit IDs.",
    ["Không thể tải Fluent SaveManager. Hãy kiểm tra kết nối mạng rồi chạy lại script."] = "Unable to load Fluent SaveManager. Check your network connection and rerun the script.",
    ["Chưa chọn Set cần build."] = "No Set selected to build.",
    ["Đã đủ mọi mốc"] = "All milestones reached",
    ["Không có Auto Craft/recipe phù hợp; đã tắt riêng Auto Leave tương ứng."] = "No suitable Auto Craft recipe is configured; the corresponding Auto Leave option was disabled.",
    ["Craft không làm inventory giảm sau 15 giây; đã mở khóa scheduler."] = "Crafting did not reduce the inventory after 15 seconds; the scheduler was unlocked.",
    ["Nạp Fuel không được server xác nhận sau 3 lần; đã tắt riêng Auto Fuel."] = "The server did not confirm refueling after 3 attempts; Auto Fuel was disabled.",
    ["Nạp Fuel lỗi 3 lần; đã tắt Auto Fuel và mở khóa Auto Join."] = "Refueling failed 3 times; Auto Fuel was disabled and Auto Join was unlocked.",
    ["Không còn Unit Level 1 thuộc rarity đã chọn; bỏ qua Training và mở khóa Join."] = "No Level 1 Units match the selected rarities; skipping Training and unlocking Join.",
    ["Auto Join đang tắt."] = "Auto Join is disabled.",
    ["Chưa chọn Map."] = "No Map selected.",
    ["Đang chờ Auto Event."] = "Waiting for Auto Event.",
    ["Đang chờ Auto Quest."] = "Waiting for Auto Quest.",
    ["Đang chờ Auto Challenge."] = "Waiting for Auto Challenge.",
    ["Đang chờ Auto Shop."] = "Waiting for Auto Shop.",
    ["Đang chờ Auto Craft."] = "Waiting for Auto Craft.",
    ["Đang chờ Lobby Utility."] = "Waiting for Lobby Utility.",
    ["Đang chờ Craft Expedition Scrap."] = "Waiting to craft Expedition Scrap.",
    ["Đang chờ Mandatory Maintenance."] = "Waiting for mandatory maintenance.",
    ["Đang chờ chuyển về Lobby."] = "Waiting to return to the Lobby.",
    ["Đang chờ JoinLock cũ hết hạn."] = "Waiting for the previous JoinLock to expire.",
    ["Scheduler chưa tạo được JoinValue."] = "The scheduler could not create a JoinValue.",
    ["Đang ở Lobby..."] = "In the Lobby...",
    ["Không chọn"] = "None",
    ["Chưa chọn building."] = "No building selected.",
    ["Đang chờ rewards"] = "Waiting for rewards",
    ["Pause: SpriteGrey có nguy cơ đầy"] = "Paused: SpriteGrey may become full",
    ["Sẵn sàng mở Geode"] = "Ready to open Geodes",
    ["Có"] = "Yes",
    ["Không"] = "No",
    ["Sẵn sàng"] = "Ready",
    ["Thiếu tài nguyên tối thiểu"] = "Insufficient minimum resources",
    ["Đang chờ Unit 400%"] = "Waiting for a 400% Unit",
    ["Đang roll"] = "Rolling",
    ["Đang chờ server xác nhận"] = "Waiting for server confirmation",
    ["Người dùng đã hủy phiên hiện tại."] = "The user canceled the current session.",
    ["Chưa có Unit trong Training Grounds."] = "No Units are in the Training Grounds.",
    ["Đang chờ dữ liệu Daily / Weekly..."] = "Waiting for Daily / Weekly data...",
    ["Đang chờ dữ liệu Regular Challenge..."] = "Waiting for Regular Challenge data...",
    ["Auto Event đang tắt."] = "Auto Event is disabled.",
    ["Auto Quest đang tắt."] = "Auto Quest is disabled.",
    ["Auto Daily / Regular Challenge đang tắt."] = "Auto Daily / Regular Challenge is disabled.",
    ["Đã hoàn thành mọi nhiệm vụ."] = "All quests completed.",
    ["Đang ở trận không thuộc Auto Quest."] = "The current match is not controlled by Auto Quest.",
    ["Đang ở trận không thuộc Auto Challenge."] = "The current match is not controlled by Auto Challenge.",
    ["Đang chờ Auto Event hoàn tất..."] = "Waiting for Auto Event to finish...",
    ["Đang chờ Auto Quest hoàn tất..."] = "Waiting for Auto Quest to finish...",
    ["Chưa có Act"] = "No Act",
    ["Đã xóa %d Select dư%s"] = "Removed %d redundant Select actions%s",
    [", thêm %d Select còn thiếu."] = ", and added %d missing Select actions.",
    ["Đã import %d Macro; mục không tick được giữ nguyên."] = "Imported %d Macros; unchecked entries were preserved.",
    ["Đang upload %d%s..."] = "Uploading %d%s...",
    [". Link đã được copy vào Clipboard."] = ". The link was copied to the Clipboard.",
    ["Đã import JSON cho %s"] = "Imported JSON for %s",
    ["Đã lưu %d thiết lập. Hãy chạy lại script để cập nhật toàn bộ UI."] = "Saved %d settings. Rerun the script to update the full UI.",
    ["Đang ở: %s\nSố lệnh Macro đã lưu: %d"] = "Current stage: %s\nSaved Macro actions: %d",
    ["GameState chưa được nhận là Lobby: %s | %s"] = "GameState has not reported the Lobby: %s | %s",
    ["Đã đủ %d phút. Đang về Lobby..."] = "%d minutes elapsed. Returning to the Lobby...",
    ["Đã cập nhật tên Map thật: %s"] = "Updated the actual Map name: %s",
    ["Bắt đầu TỰ ĐỘNG GHI hình cho [%s]"] = "Starting automatic recording for [%s]",
    ["Đã tìm thấy thư viện Macro cho [%s]. Đang bắt đầu tự động xây!"] = "Found the Macro library for [%s]. Starting automatic placement!",
    ["%s x%s. Đang tiếp tục Expedition."] = "%s x%s. Continuing the Expedition.",
    ["Đang tiếp tục Expedition."] = "Continuing the Expedition.",
    ["Discord từ chối (Mã %s)"] = "Discord rejected the request (code %s)",
    ["Tài khoản **%s** vừa quay ra Unit xịn!"] = "Account **%s** just summoned a rare Unit!",
    ["Fuel trong túi: %s"] = "Fuel in inventory: %s",
    ["%s: %d/%d | hết sau ~%s"] = "%s: %d/%d | runs out in ~%s",
    ["%s: đang chờ dữ liệu..."] = "%s: waiting for data...",
    ["Slots: %d/%d | Lấy ra: %s"] = "Slots: %d/%d | Remove at: %s",
    ["Unit %s: đang chờ dữ liệu..."] = "Unit %s: waiting for data...",
    ["Trạng thái     : %s"] = "Status         : %s",
    ["SpriteGrey     : %d/125 | Mở khi đầy: %s"] = "SpriteGrey     : %d/125 | Open when full: %s",
    ["Trạng thái : %s"] = "Status     : %s",
    ["Tài nguyên : StatReroll %d | StatLock %d | Lock kế %d"] = "Resources  : StatReroll %d | StatLock %d | Next locks %d",
    ["Mục tiêu   : %s -> %s"] = "Targets    : %s -> %s",
    ["Gần nhất   : %s"] = "Latest     : %s",
    ["%s: %d/%d card | đã mở %d/%d bonus"] = "%s: %d/%d cards | %d/%d bonuses unlocked",
    ["Mốc %d [%s]: %s"] = "Milestone %d [%s]: %s",
    ["*Không nhận được Item nào*"] = "*No items received*",
    ["*Không có Unit nào nhận EXP*"] = "*No Units gained EXP*",
    [" thiết lập"] = " settings",
    ["không rõ"] = "unknown",
    ["Import Config thất bại"] = "Config Import Failed",
    ["Import Config thành công"] = "Config Import Successful",
    ["Macro không có action."] = "The Macro has no actions.",
    ["Một Macro vượt quá 5.000 action."] = "A Macro exceeds 5,000 actions.",
    ["Macro chứa action không hợp lệ."] = "The Macro contains an invalid action.",
    ["Bundle Macro không đúng định dạng."] = "The Macro bundle has an invalid format.",
    ["Tên Macro trong bundle không hợp lệ."] = "The bundle contains an invalid Macro name.",
    ["Bundle vượt quá 50.000 action."] = "The bundle exceeds 50,000 actions.",
    ["Bundle vượt quá 250 Macro."] = "The bundle exceeds 250 Macros.",
    ["Bundle không có Macro."] = "The bundle contains no Macros.",
    ["Bundle Config không đúng định dạng."] = "The Config bundle has an invalid format.",
    ["Bundle không có Config."] = "The bundle contains no Config settings.",
    ["Executor không hỗ trợ HTTP request POST."] = "The executor does not support HTTP POST requests.",
    ["Đã gửi %d code active từ Wiki."] = "Submitted %d active codes from the Wiki.",
    ["Đã xóa skip cho #%s %s."] = "Cleared the skip for #%s %s.",
    ["#%d %s không có Macro; đã skip slot."] = "#%d %s has no Macro; the slot was skipped.",
    ["Team cho %s"] = "Team for %s",
    ["Đổi map trực tiếp hoàn tất."] = "Direct map change complete.",
    ["Quest chưa phản hồi, sẽ thử lại."] = "The Quest did not respond; retrying.",
    ["Đang để Auto Challenge chạy trước; Quest Summon sẽ làm sau cùng."] = "Auto Challenge has priority; the Quest summon will run afterward.",
    ["Daily / Weekly chưa tải sau 15s; tạm nhường Challenge / Auto Join."] = "Daily / Weekly data did not load within 15 seconds; yielding to Challenge / Auto Join.",
    ["Đang chờ dữ liệu Daily / Weekly; giữ khóa Auto Join Map..."] = "Waiting for Daily / Weekly data; holding the Auto Join Map lock...",
    ["Đang chờ server cập nhật tiến độ Quest..."] = "Waiting for the server to update Quest progress...",
    ["Quest còn mục tiêu map nhưng chưa có Macro phù hợp. Đang nhường automation thấp hơn."] = "A Quest still requires a map, but no suitable Macro is configured. Yielding to lower-priority automation.",
    ["Đang chờ dữ liệu Regular Challenge. Đang nhường automation thấp hơn."] = "Waiting for Regular Challenge data. Yielding to lower-priority automation.",
    ["Không còn Daily / Weekly Quest khả thi lúc này. Đang nhường automation thấp hơn."] = "No feasible Daily / Weekly Quests remain right now. Yielding to lower-priority automation.",
    ["Đã đạt số Wave dự kiến; đang chờ Quest server xác nhận tiến độ..."] = "Reached the expected Wave count; waiting for the Quest server to confirm progress...",
    ["Quest Infinite đã đạt Wave 50; đang Restart để tiếp tục cộng Wave..."] = "Quest Infinite reached Wave 50; restarting to continue accumulating Waves...",
    ["Quest Infinite chưa đủ mục tiêu; đang chờ game Auto Retry..."] = "Quest Infinite has not reached its target; waiting for the game's Auto Retry...",
    ["Quest chưa đủ mục tiêu; đang quay lại đúng map Quest."] = "The Quest target is incomplete; returning to the assigned Quest map.",
    ["Quest chưa đủ mục tiêu; đang chờ game Auto Retry..."] = "The Quest target is incomplete; waiting for the game's Auto Retry...",
    ["Đang chờ trận hiện tại kết thúc (theo Matches Played)..."] = "Waiting for the current match to end (based on Matches Played)...",
    ["Boss Bounty chưa được server xác nhận sau 15s; đã nhường automation thấp hơn."] = "The server did not confirm Boss Bounty within 15 seconds; yielding to lower-priority automation.",
    ["Boss Bounty đang chờ TrackCounter xác nhận hoàn thành."] = "Boss Bounty is waiting for TrackCounter to confirm completion.",
    ["Boss Bounty cần 5.000 Gold để Reroll; đang giữ bounty hiện tại."] = "Boss Bounty requires 5,000 Gold to reroll; keeping the current bounty.",
    ["Boss Bounty đã xác nhận; đang chờ về Lobby để Roll lượt tiếp theo."] = "Boss Bounty was confirmed; waiting to return to the Lobby for the next roll.",
    ["Boss Bounty không cập nhật sau trận; đã nhường automation thấp hơn."] = "Boss Bounty did not update after the match; yielding to lower-priority automation.",
    ["Boss Bounty kết thúc; đang chờ server xác nhận."] = "Boss Bounty ended; waiting for server confirmation.",
    ["Đang chờ quest category ShenronEvent tải..."] = "Waiting for the ShenronEvent quest category to load...",
    ["ShenronEvent chưa được server load; nhường automation thấp hơn."] = "The server has not loaded ShenronEvent; yielding to lower-priority automation.",
    ["Dragon's Wish đã redeem."] = "Dragon's Wish has been redeemed.",
    ["Đã đủ 7 Orb; Auto Redeem đang tắt hoặc chưa chọn unit hợp lệ."] = "All 7 Orbs are ready; Auto Redeem is disabled or no valid Unit is selected.",
    ["Dragon Wish Infinite đã đạt mốc; đang về Lobby để cập nhật tiến độ."] = "Dragon Wish Infinite reached its target; returning to the Lobby to update progress.",
    ["Dragon Wish đang chờ trận hiện tại kết thúc."] = "Dragon Wish is waiting for the current match to end.",
    ["Dragon Wish chỉ còn objective passive/unsupported hoặc thiếu Macro; nhường automation thấp hơn."] = "Dragon Wish has only passive or unsupported objectives, or lacks a Macro; yielding to lower-priority automation.",
    ["Tất cả Regular Challenge hiện tại đã skip. Đang nhường Auto Join Map."] = "All current Regular Challenges were skipped. Yielding to Auto Join Map.",
    ["Regular Challenge chưa khả dụng theo dữ liệu game. Đang nhường Auto Join Map."] = "Regular Challenge is unavailable according to game data. Yielding to Auto Join Map.",
    ["Đã hết lượt Regular Challenge hôm nay. Đang nhường Auto Join Map."] = "No Regular Challenge attempts remain today. Yielding to Auto Join Map.",
    ["Đang ở trong Challenge; chờ trận kết thúc rồi đổi trực tiếp."] = "In a Challenge; waiting for the match to end before switching directly.",
    ["Daily Challenge đã xong hoặc không khả dụng. Regular Challenge đang tắt."] = "Daily Challenge is complete or unavailable. Regular Challenge is disabled.",
    ["Auto Geode paused: SpriteGrey có nguy cơ đầy."] = "Auto Geode paused: SpriteGrey may become full.",
    ["Đang chọn map mới: %s"] = "Selecting a new map: %s",
    ["Đang đổi map trực tiếp (không retry Restart): %s"] = "Changing maps directly (without retrying Restart): %s",
    ["Cooldown Join còn %.1fs."] = "Join cooldown: %.1fs remaining.",
    ["Sẵn sàng gửi queue: %s"] = "Ready to submit queue: %s",
}
local dynamicEnglishFragments = {
    {"Đang chờ dữ liệu", "Waiting for data"},
    {"Đang tải link", "Downloading link"},
    {"Đang khởi động lại ván đấu", "Restarting the match"},
    {"Đang tiếp tục", "Continuing"},
    {"Đang về Lobby", "Returning to Lobby"},
    {"Đang ở Lobby", "In Lobby"},
    {"Đã tắt", "Disabled"},
    {"Đã bật", "Enabled"},
    {"Đã lưu", "Saved"},
    {"Đã xóa", "Removed"},
    {"Đã import", "Imported"},
    {"Đã cập nhật", "Updated"},
    {"Đã tìm thấy", "Found"},
    {"Đã gửi", "Sent"},
    {"Hoàn tất", "Completed"},
    {"Thành công", "Successful"},
    {"thất bại", "failed"},
    {"không hợp lệ", "is invalid"},
    {"Không có", "No"},
    {"Chưa có", "No"},
    {"Chưa chọn", "Not selected"},
    {"Hãy chọn ít nhất một", "Select at least one"},
    {"Phải bật", "Enable"},
    {"trước khi bật", "before enabling"},
    {"Tự động", "Automatically"},
    {"Trạng thái", "Status"},
    {"Trạng Thái", "Status"},
    {"Đang chạy", "Running"},
    {"Đang chờ", "Waiting"},
    {"Đang đọc", "Reading"},
    {"Đang xử lý", "Processing"},
    {"Đang tìm", "Searching"},
    {"Đang mở", "Opening"},
    {"Đang nạp", "Refueling"},
    {"Đã đầy", "Full"},
    {"đã chọn", "selected"},
    {"mỗi ngày", "each day"},
    {"mỗi phút", "each minute"},
    {"phút", "minutes"},
}
local function replacePlain(text, target, replacement)
    local start = 1
    while true do
        local first, last = string.find(text, target, start, true)
        if not first then return text end
        text = string.sub(text, 1, first - 1) .. replacement .. string.sub(text, last + 1)
        start = first + #replacement
    end
end
local function localizeText(value)
    if appConfig.Language ~= "English" or type(value) ~= "string" then return value end
    local exact = englishTranslations[value]
    if exact then return exact end
    local localized = value
    for _, replacement in ipairs(dynamicEnglishFragments) do
        localized = replacePlain(localized, replacement[1], replacement[2])
    end
    return localized
end
logInit("Đang móc nối Modules Game...")
local FusionPackage = ReplicatedStorage:WaitForChild("FusionPackage")
local Actions = require(FusionPackage:WaitForChild("Actions"))
local Fusion = require(FusionPackage:WaitForChild("Fusion"))
local Dependencies = require(FusionPackage:WaitForChild("Dependencies"))
pcall(function()
    local oldConnection = getgenv().AnimeExpeditionsHotbarReplicaConnection
    if oldConnection and oldConnection.Disconnect then oldConnection:Disconnect() end
    local ReplicaClient = require(ReplicatedStorage.Shared.ReplicaClient)
    getgenv().AnimeExpeditionsHotbarReplicaConnection = ReplicaClient.OnNew("HotbarData", function(replica)
        getgenv().AnimeExpeditionsHotbarReplicaId = replica.Id
        getgenv().CachedHotbarDataId = replica.Id
    end)
end)
local SharedInfo = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Information")
local BattlepassInfo = require(SharedInfo:WaitForChild("Battlepass"))
local CalendarInfo = require(SharedInfo:WaitForChild("Calendars"))
local MapInfo = require(SharedInfo:WaitForChild("Maps"))
local ChallengeInfo = require(SharedInfo:WaitForChild("ChallengeInfo"))
local BannerInfo = require(SharedInfo:WaitForChild("BannerInfo"))
local ShopsInfo = require(SharedInfo:WaitForChild("Shops"))
local UnitsInfo = require(SharedInfo:WaitForChild("Units"))
local EventsInfo = require(SharedInfo:WaitForChild("Events"))
local QuestsInfo = require(SharedInfo:WaitForChild("Quests"))
local EventAuto = {
    Runtime = {
        Status = "Đang chờ dữ liệu Event...",
        LastDisplay = "",
        Pending = nil,
        ActiveTarget = nil,
        LastJoinAt = 0,
        FinishedAt = 0,
        MissingSince = {},
        WishUnitLabels = {},
        WishLabelToId = {},
    },
}
local QuestAuto = {
    Maps = (function()
        local mapSet = {}
        for _, modeName in ipairs({"Story", "Infinite", "Mastery"}) do
            for mapName in pairs((MapInfo.MapData and MapInfo.MapData[modeName]) or {}) do
                mapSet[tostring(mapName)] = true
            end
        end
        local maps = {}
        for mapName in pairs(mapSet) do table.insert(maps, mapName) end
        table.sort(maps)
        return maps
    end)(),
    Runtime = {Status = "Đang chờ dữ liệu Daily / Weekly...", LastDisplay = "", LastJoinAt = 0, LastReturnAt = 0, FinishedAt = 0, Pending = nil, SkippedChallenges = {}, SkippedModes = {}},
}
function EventAuto:Peek(value)
    local ok, result = pcall(function() return Fusion.peek(value) end)
    return ok and result or value
end
function EventAuto:GetPlayerData()
    local playerData = self:Peek(Dependencies.PlayerData)
    return type(playerData) == "table" and playerData or nil
end
function EventAuto:GetEventData(eventId)
    local playerData = self:GetPlayerData()
    local eventData = playerData and self:Peek(playerData.EventData) or nil
    local result = type(eventData) == "table" and self:Peek(eventData[eventId]) or nil
    return type(result) == "table" and result or nil
end
function EventAuto:TargetMatchesState(stateInfo)
    local target = self.Runtime.ActiveTarget
    if type(target) ~= "table" or type(stateInfo) ~= "table" or not target.JoinIssuedAt then return false end
    if tostring(stateInfo.CurrentGameState or "") == "Lobby" then return false end
    local function normalize(value) return tostring(value or ""):lower():gsub("[^%w]", "") end
    local modeMatches = normalize(target.Mode) == normalize(stateInfo.Gamemode)
    local stateMap = normalize(stateInfo.Map)
    local targetMap = normalize(target.Map)
    local mapMatches = targetMap == "" or (stateMap ~= "" and stateMap ~= "nil" and targetMap == stateMap)
    local actMatches = normalize(target.Act) == "" or normalize(stateInfo.Act) == "" or normalize(target.Act) == normalize(stateInfo.Act)
    return modeMatches and mapMatches and actMatches
end
local achievementCategoryIds = {}
do
    for categoryId, categoryInfo in pairs(QuestsInfo.Categories or {}) do
        if type(categoryInfo) == "table" and categoryInfo.IsAchievement then
            table.insert(achievementCategoryIds, categoryId)
        end
    end
end
table.sort(achievementCategoryIds)
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
local function unitHasDBZCategory(assetId)
    local info = UnitsInfo[tostring(assetId)]
    if type(info) ~= "table" then return false end
    if info.DBZCategory == true then return true end
    local tagGroups = {info.Tags, info.Tag, info.Categories, type(info.UpgradeInfo) == "table" and type(info.UpgradeInfo[0]) == "table" and info.UpgradeInfo[0].Tags or nil}
    for _, tags in pairs(tagGroups) do
        if type(tags) == "table" then
            if tags.DBZCategory == true then return true end
            for _, tag in pairs(tags) do
                if tostring(tag) == "DBZCategory" then return true end
            end
        end
    end
    return false
end
local function getWishUnitOptions()
    local options, labelToId, idToLabel = {"Không chọn"}, {}, {}
    local playerData = EventAuto:GetPlayerData()
    local unitData = playerData and EventAuto:Peek(playerData.UnitData) or nil
    for id, rawUnit in pairs(type(unitData) == "table" and unitData or {}) do
        local unit = EventAuto:Peek(rawUnit)
        if type(unit) == "table" then
            local asset = tostring(EventAuto:Peek(unit.Asset) or "")
            local trait = tostring(EventAuto:Peek(unit.Trait) or "")
            if asset ~= "" and trait ~= "Unbound" and unitHasDBZCategory(asset) then
                local info = UnitsInfo[asset] or {}
                local name = tostring(info.Name or info.DisplayName or asset)
                local label = string.format("%s | %s | %s", name, trait ~= "" and trait or "No Trait", tostring(id))
                table.insert(options, label)
                labelToId[label] = tostring(id)
                idToLabel[tostring(id)] = label
            end
        end
    end
    table.sort(options, function(left, right)
        if left == "Không chọn" then return true end
        if right == "Không chọn" then return false end
        return left < right
    end)
    return options, labelToId, idToLabel
end
local allShops = {}
local function extractShopItems(shopNode, dataKey, shopKey)
    if type(shopNode) == "table" then
        if type(shopNode.Items) == "table" then
            for index, item in pairs(shopNode.Items) do
                if type(item) == "table" then
                    local name = item.Name or item.Product or item.Id
                    if name then
                        table.insert(allShops, {
                            StoreId = tostring(shopKey or dataKey),
                            DataKey = tostring(dataKey),
                            ShopKey = tostring(shopKey or dataKey),
                            ProductId = tostring(name),
                            ItemIndex = tonumber(index) or index,
                        })
                    end
                elseif type(item) == "string" or type(item) == "number" then
                    table.insert(allShops, {
                        StoreId = tostring(shopKey or dataKey),
                        DataKey = tostring(dataKey),
                        ShopKey = tostring(shopKey or dataKey),
                        ProductId = tostring(item),
                        ItemIndex = tonumber(index) or index,
                    })
                end
            end
        else
            for k, v in pairs(shopNode) do
                if type(v) == "table" then
                    extractShopItems(v, dataKey, k)
                end
            end
        end
    end
end
for shopName, shopData in pairs(ShopsInfo) do
    extractShopItems(shopData, shopName)
end
do
    local replica
    for _ = 1, 20 do
        pcall(function() replica = require(ReplicatedStorage.Nodes).GET_SHOP_REPLICA:InvokeSelf("ExpeditionShop") end)
        if replica and replica.Data and replica.Data.Shops and replica.Data.Shops.Shop then break end
        task.wait(0.1)
    end
    local shop = replica and replica.Data and replica.Data.Shops and replica.Data.Shops.Shop
    if type(shop) == "table" then
        for index, item in ipairs(shop.Items or {}) do
            local duplicate = false
            for _, entry in ipairs(allShops) do
                if entry.DataKey == "ExpeditionShop" and entry.ShopKey == "Shop" and entry.ProductId == tostring(item.Name) then
                    duplicate = true
                    break
                end
            end
            if not duplicate then
                table.insert(allShops, {
                    StoreId = "ExpeditionShop",
                    DataKey = "ExpeditionShop",
                    ShopKey = "Shop",
                    ProductId = tostring(item.Name),
                    ItemIndex = index,
                    Currency = "ExpeditionCoin",
                    PurchaseKind = "ExpeditionShop",
                })
            end
        end
    end
end
local function getAutoShopPurchasableAmount(entry)
    local Nodes = require(ReplicatedStorage.Nodes)
    local ok, replica = pcall(function() return Nodes.GET_SHOP_REPLICA:InvokeSelf(entry.DataKey) end)
    if not ok or not replica or type(replica.Data) ~= "table" then return 0, nil, false end
    local shop = replica.Data.Shops and replica.Data.Shops[entry.ShopKey]
    if type(shop) ~= "table" or type(shop.Items) ~= "table" then return 0, nil, false end
    local itemIndex = entry.ItemIndex
    local item = shop.Items[itemIndex]
    if type(item) ~= "table" or tostring(item.Name) ~= entry.ProductId then
        for index, candidate in ipairs(shop.Items) do
            if type(candidate) == "table" and tostring(candidate.Name) == entry.ProductId then
                itemIndex, item = index, candidate
                break
            end
        end
    end
    if type(item) ~= "table" then return 0, nil, false end
    local function peek(value)
        local success, result = pcall(function() return Fusion.peek(value) end)
        return success and result or value
    end
    local playerData = peek(Dependencies.PlayerData) or {}
    local itemData = peek(playerData.ItemData) or {}
    local shopData = peek(playerData.ShopData) or {}
    local purchaseHistory = peek(shopData.PurchaseHistory) or {}
    local playerResetKeys = peek(shopData.ResetKeys) or {}
    local history = peek(purchaseHistory[entry.DataKey]) or {}
    history = peek(history[entry.ShopKey]) or {}
    local purchased = tonumber(peek(history[item.Name])) or 0
    local resetKeys = peek(playerResetKeys[entry.DataKey]) or {}
    local playerResetKey = peek(resetKeys[entry.ShopKey])
    local shopResetKey = replica.Data.ResetKeys and replica.Data.ResetKeys[entry.ShopKey]
    if item.Restocks and playerResetKey ~= shopResetKey then purchased = 0 end
    local remainingStock = math.max(0, (tonumber(item.Stock) or 999999) - purchased)
    local currency = tostring(item.Currency or shop.Currency or entry.Currency or "")
    local currencyData = peek(itemData[currency])
    local currencyAmount = type(currencyData) == "table" and (tonumber(peek(currencyData.Amount)) or 0) or (tonumber(currencyData) or 0)
    local price = math.max(0, (tonumber(item.Price) or 0) - (tonumber(item.Discount) or 0))
    local affordable = price > 0 and math.floor(currencyAmount / price) or math.huge
    local ownedData = peek(itemData[item.Name])
    local ownedAmount = type(ownedData) == "table" and (tonumber(peek(ownedData.Amount)) or 0) or (tonumber(ownedData) or 0)
    local inventoryLimit = math.huge
    pcall(function() inventoryLimit = Dependencies.Information:GetAssetInventoryLimit(item.Name) or math.huge end)
    local itemAmount = math.max(1, tonumber(item.Amount) or 1)
    local inventorySpace = inventoryLimit < math.huge and math.floor(math.max(0, inventoryLimit - ownedAmount) / itemAmount) or math.huge
    return math.max(0, math.floor(math.min(remainingStock, affordable, inventorySpace))), itemIndex, true
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
local function getSessionMatchesPlayed()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return nil end
    for _, label in ipairs(playerGui:GetDescendants()) do
        if label:IsA("TextLabel") and label.Visible and label.Text:lower():find("matches played", 1, true) then
            local headingCenter = label.AbsolutePosition.X + label.AbsoluteSize.X / 2
            local bestValue, bestScore
            local root = label.Parent
            for _ = 1, 2 do
                if not root then break end
                for _, candidate in ipairs(root:GetDescendants()) do
                    if candidate:IsA("TextLabel") and candidate.Visible and candidate ~= label then
                        local value = tonumber(candidate.Text:gsub(",", ""):match("^%s*(%d+)%s*$"))
                        if value then
                            local candidateCenter = candidate.AbsolutePosition.X + candidate.AbsoluteSize.X / 2
                            local score = math.abs(candidateCenter - headingCenter)
                            if not bestScore or score < bestScore then
                                bestValue, bestScore = value, score
                            end
                        end
                    end
                end
                if bestValue ~= nil then return bestValue end
                root = root.Parent
            end
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
        local sessionStats = safePeek(state.SessionStats) or {}
        local gamemode = tostring(safePeek(params.Gamemode) or "")
        local mapName = tostring(safePeek(params.Map) or safePeek(params.MapName) or "")
        local actName = tostring(safePeek(params.Act) or safePeek(params.ActName) or "")
        local difficulty = tonumber(safePeek(params.DifficultyLevel)) or safePeek(params.Difficulty) or ""
        local challengeType = tostring(safePeek(params.ChallengeType) or "")
        local challengeIndex = tonumber(safePeek(params.ChallengeIndex) or safePeek(params.Index))
        local currentGameState = tostring(safePeek(state.CurrentGameState))
        local gameIncrement = tonumber(safePeek(state.GameIncrement)) or 0
        local mapObserved = mapName ~= "" and mapName ~= "nil" and mapName ~= "false"
        if (currentGameState == "" or currentGameState == "nil" or currentGameState == "false")
            and (gamemode == "" or gamemode == "nil" or gamemode == "false") then
            return nil
        end
        if currentGameState == "Lobby" and (gamemode == "" or gamemode == "nil") then
        end
        if mapObserved then
            cachedFallbackMapName = mapName
            cachedFallbackActName = actName
            getgenv().AnimeExpeditionsMapCacheIncrement = gameIncrement
            getgenv().AnimeExpeditionsMapCacheMode = gamemode
        elseif currentGameState ~= "Lobby" then
            if cachedFallbackMapName ~= ""
                and tonumber(getgenv().AnimeExpeditionsMapCacheIncrement) == gameIncrement
                and tostring(getgenv().AnimeExpeditionsMapCacheMode or "") == gamemode then
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
                                            getgenv().AnimeExpeditionsMapCacheIncrement = gameIncrement
                                            getgenv().AnimeExpeditionsMapCacheMode = gamemode
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
            ChallengeType = challengeType,
            ChallengeIndex = challengeIndex,
            GameIncrement = gameIncrement,
            MapObserved = mapObserved,
            GameTime = parseTime(safePeek(state.GameTime)) or parseTime(safePeek(state.SessionTime)) or parseTime(safePeek(state.Timer)) or 0,
            TotalKills = tonumber(safePeek(validPlayerState.TotalKills)) or tonumber(safePeek(validPlayerState.Kills)) or 0,
            TotalDamage = tonumber(safePeek(validPlayerState.TotalDamage)) or tonumber(safePeek(validPlayerState.Damage)) or 0,
            SessionMatchesPlayed = tonumber(safePeek(sessionStats.MatchesPlayed)) or tonumber(safePeek(sessionStats.Matches))
        }
    end
    return nil
end
function QuestAuto:TargetMatchesState(stateInfo)
    local target = appConfig.QuestAuto.Enabled and appConfig.QuestAuto.ActiveTarget or nil
    if type(target) ~= "table" or type(stateInfo) ~= "table" or target.Owner ~= "Quest" or not target.JoinIssuedAt then return false end
    local function normalize(value)
        return tostring(value or ""):lower():gsub("[^%w]", "")
    end
    local stateMap = normalize(stateInfo.Map)
    local modeMatches = normalize(target.Mode) == normalize(stateInfo.Gamemode)
    if target.Mode == "Challenge" then
        local joinLock = getgenv().AnimeExpeditionsJoinLock
        if type(joinLock) == "table" and joinLock.Owner == "Quest" and normalize(joinLock.TargetMode) == "challenge"
            and (normalize(stateInfo.ChallengeType) == "" or stateInfo.ChallengeIndex == nil
                or normalize(stateInfo.ChallengeType) ~= normalize(joinLock.ChallengeType)
                or tonumber(stateInfo.ChallengeIndex) ~= tonumber(joinLock.ChallengeIndex)) then return false end
        local indexMatches = not stateInfo.ChallengeIndex or tonumber(target.Index) == tonumber(stateInfo.ChallengeIndex)
        return modeMatches and indexMatches and (stateMap == "" or stateMap == "nil" or normalize(target.Map) == stateMap)
    end
    local actMatches = normalize(target.Act) == "" or normalize(stateInfo.Act) == "" or normalize(target.Act) == normalize(stateInfo.Act)
    return modeMatches and actMatches and normalize(target.Map) == stateMap
end
local function getCurrentStageKey(stateInfo, previousStateInfo)
    if not stateInfo then return "Unknown" end
    local actName = stateInfo.Act
    local mapName = stateInfo.Map
    
    if (mapName == "" or mapName == "nil") and previousStateInfo and previousStateInfo.Map and previousStateInfo.Map ~= "" then
        mapName = previousStateInfo.Map
        if actName == "" or actName == "nil" then actName = previousStateInfo.Act end
    end
    
    local questTarget = appConfig.QuestAuto.Enabled and appConfig.QuestAuto.ActiveTarget or nil
    if (mapName == "" or mapName == "nil") and type(questTarget) == "table" and questTarget.Mode == stateInfo.Gamemode then
        mapName = tostring(questTarget.Map or "")
        if actName == "" or actName == "nil" then actName = tostring(questTarget.Act or "") end
    end
    local eventTarget = EventAuto.Runtime.ActiveTarget
    if (mapName == "" or mapName == "nil") and type(eventTarget) == "table" and eventTarget.Mode == stateInfo.Gamemode then
        mapName = tostring(eventTarget.Map or "")
        if actName == "" or actName == "nil" then actName = tostring(eventTarget.Act or "") end
    end
    local challengeTarget = appConfig.autoChallengeEnabled and appConfig.challengeActiveTarget or nil
    if (mapName == "" or mapName == "nil") and type(challengeTarget) == "table" and challengeTarget.Mode == stateInfo.Gamemode then
        mapName = tostring(challengeTarget.Map or "")
        if actName == "" or actName == "nil" then actName = tostring(challengeTarget.Act or "") end
    end
    if (mapName == "" or mapName == "nil") and appConfig.autoJoinEnabled and appConfig.AutoJoin and appConfig.AutoJoin ~= "" then
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
local function challengeTargetMatchesState(stateInfo)
    local target = (appConfig.autoChallengeEnabled or appConfig.autoDailyChallengeEnabled) and appConfig.challengeActiveTarget or nil
    if type(target) ~= "table" or type(stateInfo) ~= "table" then return false end
    if target.Owner ~= "Challenge" or not target.JoinIssuedAt then return false end
    local function normalize(value)
        return tostring(value or ""):lower():gsub("[^%w]", "")
    end
    local stateMode = normalize(stateInfo.Gamemode)
    local stateType = normalize(stateInfo.ChallengeType)
    local modeMatches = stateMode:find("challenge", 1, true) ~= nil or stateInfo.ChallengeIndex ~= nil
    local joinLock = getgenv().AnimeExpeditionsJoinLock
    if type(joinLock) == "table" and joinLock.Owner == "Challenge" and normalize(joinLock.TargetMode) == "challenge"
        and (stateType == "" or stateInfo.ChallengeIndex == nil
            or stateType ~= normalize(joinLock.ChallengeType)
            or tonumber(stateInfo.ChallengeIndex) ~= tonumber(joinLock.ChallengeIndex)) then return false end
    local typeMatches = stateType == "" or stateType == normalize(target.ChallengeType or "Regular")
    local indexMatches = not stateInfo.ChallengeIndex or tonumber(target.Index) == tonumber(stateInfo.ChallengeIndex)
    -- A Challenge slot index is unique within its type. Map replicas can arrive later or use a different display name.
    return modeMatches and typeMatches and indexMatches
end
local function automationMacroPlaybackEnabled(stateInfo)
    if getgenv().AnimeExpeditionsMapSwitchPending then return false end
    if type(stateInfo) == "table" and stateInfo.Gamemode == "Expedition" then
        if tostring(stateInfo.Status) == "Encounter" then return false end
        if getgenv().ExpeditionRouteRewardSearching or getgenv().ExpeditionPostBossSellMode then return false end
        if getgenv().ExpeditionHelperPlacementPending then return false end
        local checker = getgenv().ExpeditionHasUnplacedHelper
        if type(checker) == "function" then
            local ok, hasUnplacedHelper = pcall(checker)
            if ok and hasUnplacedHelper then return false end
        end
    end
    local eventOwned = EventAuto:TargetMatchesState(stateInfo)
    local questOwned = QuestAuto:TargetMatchesState(stateInfo)
    local challengeOwned = challengeTargetMatchesState(stateInfo)
    local ownedTarget = eventOwned and EventAuto.Runtime.ActiveTarget
        or (questOwned and appConfig.QuestAuto.ActiveTarget)
        or (challengeOwned and appConfig.challengeActiveTarget)
    local restartPhase = type(ownedTarget) == "table" and ownedTarget.MacroRestartPhase or nil
    if restartPhase and restartPhase ~= "Ready" and restartPhase ~= "Failed" then return false end
    return appConfig.autoPlayEnabled or eventOwned or questOwned or challengeOwned
end
local function getMacroListForStage(stageKey, stateInfo)
    local eventTarget = EventAuto:TargetMatchesState(stateInfo) and EventAuto.Runtime.ActiveTarget or nil
    if type(eventTarget) == "table" and eventTarget.MacroKey then
        local eventMacro = appConfig.Macros[tostring(eventTarget.MacroKey)]
        if type(eventMacro) == "table" then
            return eventMacro, tostring(eventTarget.MacroKey)
        end
    end
    local questTarget = QuestAuto:TargetMatchesState(stateInfo) and appConfig.QuestAuto.ActiveTarget or nil
    if type(questTarget) == "table" and questTarget.MacroKey then
        local questMacro = appConfig.Macros[tostring(questTarget.MacroKey)]
        if type(questMacro) == "table" then
            return questMacro, tostring(questTarget.MacroKey)
        end
    end
    local challengeTarget = challengeTargetMatchesState(stateInfo) and appConfig.challengeActiveTarget or nil
    if type(challengeTarget) == "table" and challengeTarget.MacroKey then
        local challengeMacro = appConfig.Macros[tostring(challengeTarget.MacroKey)]
        if type(challengeMacro) == "table" then
            return challengeMacro, tostring(challengeTarget.MacroKey)
        end
    end
    if not eventTarget and not questTarget and not challengeTarget and type(stateInfo) == "table" and stateInfo.Gamemode == "Story" then
        local requestedKey = appConfig.storyMapMacros[tostring(stateInfo.Map or "")]
        if not requestedKey then
            local normalizedStage = normalizeStageKey(stageKey)
            for mapName, macroKey in pairs(appConfig.storyMapMacros) do
                local normalizedMap = normalizeStageKey("Story_" .. tostring(mapName))
                local stageSuffix = normalizedStage:sub(#normalizedMap + 1)
                if normalizedStage:sub(1, #normalizedMap) == normalizedMap
                    and (stageSuffix == "" or stageSuffix:match("^%d+$") or stageSuffix:match("^act%d+$")) then
                    requestedKey = macroKey
                    break
                end
            end
        end
        local storyMacro = requestedKey and appConfig.Macros[tostring(requestedKey)] or nil
        if type(storyMacro) == "table" and #storyMacro > 0 then
            return storyMacro, tostring(requestedKey)
        end
    end
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
local presentationFields = {"Title", "Content", "Description", "Placeholder"}
local wrappedControls = setmetatable({}, {__mode = "k"})
local function localizeOptions(options)
    if type(options) ~= "table" then return options end
    local localized
    for _, field in ipairs(presentationFields) do
        local value = options[field]
        local translated = localizeText(value)
        if translated ~= value then
            if not localized then
                localized = {}
                for key, optionValue in pairs(options) do localized[key] = optionValue end
            end
            localized[field] = translated
        end
    end
    return localized or options
end
local function wrapControl(control)
    if type(control) ~= "table" or wrappedControls[control] then return control end
    wrappedControls[control] = true
    local function wrapTextMethod(methodName)
        local original = control[methodName]
        if type(original) == "function" then
            control[methodName] = function(self, value, ...)
                return original(self, localizeText(value), ...)
            end
        end
    end
    for _, methodName in ipairs({"SetDesc", "SetTitle"}) do
        wrapTextMethod(methodName)
    end
    return control
end
local function wrapTab(tab)
    if type(tab) ~= "table" then return tab end
    local function wrapAddMethod(methodName)
        local original = tab[methodName]
        if type(original) == "function" then
            tab[methodName] = function(self, ...)
                local arguments = table.pack(...)
                if methodName == "AddSection" and type(arguments[1]) == "string" then
                    arguments[1] = localizeText(arguments[1])
                else
                    for index = 1, arguments.n do
                        if type(arguments[index]) == "table" then
                            arguments[index] = localizeOptions(arguments[index])
                            break
                        end
                    end
                end
                local results = table.pack(original(self, table.unpack(arguments, 1, arguments.n)))
                results[1] = wrapControl(results[1])
                return table.unpack(results, 1, results.n)
            end
        end
    end
    for _, methodName in ipairs({"AddParagraph", "AddToggle", "AddDropdown", "AddInput", "AddButton", "AddSection", "AddSlider", "AddKeybind", "AddColorpicker"}) do
        wrapAddMethod(methodName)
    end
    return tab
end
do
    local originalNotify = Fluent.Notify
    if type(originalNotify) == "function" then
        Fluent.Notify = function(self, options, ...)
            return originalNotify(self, localizeOptions(options), ...)
        end
    end
    local originalCreateWindow = Fluent.CreateWindow
    if type(originalCreateWindow) == "function" then
        Fluent.CreateWindow = function(self, options, ...)
            local results = table.pack(originalCreateWindow(self, localizeOptions(options), ...))
            local window = results[1]
            if type(window) == "table" and type(window.AddTab) == "function" then
                local originalAddTab = window.AddTab
                window.AddTab = function(windowSelf, tabOptions, ...)
                    local tabResults = table.pack(originalAddTab(windowSelf, localizeOptions(tabOptions), ...))
                    tabResults[1] = wrapTab(tabResults[1])
                    return table.unpack(tabResults, 1, tabResults.n)
                end
            end
            return table.unpack(results, 1, results.n)
        end
    end
end
local saveManagerPath = "AnimeExpeditions/FluentSaveManager.lua"
if isfile and isfile(saveManagerPath) then
    local ok, res = pcall(function() return compile(readfile(saveManagerPath))() end)
    if ok and type(res) == "table" then SaveManager = res end
end
if not SaveManager then
    local ok, res = pcall(function()
        return request({
            Url = "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua",
            Method = "GET",
        })
    end)
    if ok and res and res.Body then
        if writefile then pcall(function() writefile(saveManagerPath, res.Body) end) end
        local loaded, manager = pcall(function() return compile(res.Body)() end)
        if loaded and type(manager) == "table" then SaveManager = manager end
    end
end
if SaveManager then
    function SaveManager:Load(name)
        if not name then return false, "no config file is selected" end
        local path = self.Folder .. "/settings/" .. name .. ".json"
        if not isfile(path) then return false, "invalid file" end
        local decodedOk, decoded = pcall(function()
            return HttpService:JSONDecode(readfile(path))
        end)
        if not decodedOk or type(decoded) ~= "table" or type(decoded.objects) ~= "table" then
            return false, "decode error"
        end
        for _, optionData in ipairs(decoded.objects) do
            local parser = self.Parser[optionData.type]
            if parser then
                local loadedOk, loadError = pcall(parser.Load, optionData.idx, optionData)
                if not loadedOk then return false, tostring(loadError) end
            end
        end
        return true
    end
end
getgenv().AnimeExpeditionsLeaveToggles = {}
getgenv().AnimeExpeditionsGuardAutoLeave = function(value, toggleKey)
    if not value or appConfig.autoJoinEnabled then return value end
    local toggle = getgenv().AnimeExpeditionsLeaveToggles[toggleKey]
    if toggle then task.defer(function() pcall(function() toggle:SetValue(false) end) end) end
    if tick() - (getgenv().AnimeExpeditionsLeaveGuardNotifyAt or 0) >= 2 then
        getgenv().AnimeExpeditionsLeaveGuardNotifyAt = tick()
        pcall(function()
            Fluent:Notify({Title = "Auto Leave", Content = "Phải bật Auto Join Map trước khi bật tính năng Leave.", Duration = 5})
        end)
    end
    return false
end
getgenv().AnimeExpeditionsDisableAutoLeaves = function(showNotice)
    appConfig.autoLeaveSpriteMax = false
    appConfig.autoLeaveExpeditionScrapMax = false
    appConfig.expeditionScrapCraftPending = false
    appConfig.expeditionScrapCraftPendingSince = 0
    appConfig.autoLeaveOnDefeat = false
    appConfig.autoLeaveOnPlayerJoin = false
    appConfig.autoLeaveAfterMinutes = false
    appConfig.ExpeditionAuto.autoLeaveFuel = false
    appConfig.ExpeditionAuto.autoLeaveTraining = false
    local maintenance = appConfig.LobbyMaintenance
    if type(maintenance) == "table" and type(maintenance.Reasons) == "table" then
        maintenance.Reasons.SpriteCraft = nil
        maintenance.Reasons.ExpeditionScrapCraft = nil
        maintenance.Reasons.ExpeditionFuel = nil
        maintenance.Reasons.TrainingRotation = nil
        if next(maintenance.Reasons) == nil then
            maintenance.Phase = "Idle"
            maintenance.RequestedAt = 0
        end
    end
    local coordinator = getgenv().AnimeExpeditionsCoordinator
    if coordinator then coordinator.FuelPending = nil end
    for _, toggle in pairs(getgenv().AnimeExpeditionsLeaveToggles) do
        if toggle and toggle.Value == true then task.defer(function() pcall(function() toggle:SetValue(false) end) end) end
    end
    saveConfig()
    if showNotice then
        pcall(function()
            Fluent:Notify({Title = "Auto Leave Disabled", Content = "Đã tắt toàn bộ Auto Leave vì Auto Join Map đang tắt.", Duration = 5})
        end)
    end
end
local Window = Fluent:CreateWindow({
    Title = "Anime Expeditions",
    SubTitle = "by Truyem789",
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
    Event = Window:AddTab({ Title = "Auto Event", Icon = "calendar-days" }),
    Quest = Window:AddTab({ Title = "Auto Quest", Icon = "scroll-text" }),
    Story = Window:AddTab({ Title = "Auto Story", Icon = "book-open" }),
    Challenge = Window:AddTab({ Title = "Auto Challenge", Icon = "swords" }),
    Shop = Window:AddTab({ Title = "Auto Shop", Icon = "shopping-cart" }),
    Craft = Window:AddTab({ Title = "Auto Craft", Icon = "hammer" }),
    Expeditions = Window:AddTab({ Title = "Expeditions", Icon = "compass" }),
    Join = Window:AddTab({ Title = "Auto Join Map", Icon = "map" }),
    Team = Window:AddTab({ Title = "Team", Icon = "users" }),
    Macro = Window:AddTab({ Title = "Macro In-Game", Icon = "play" }),
    Webhook = Window:AddTab({ Title = "Webhook", Icon = "message-circle" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
    Configs = Window:AddTab({ Title = "Configs", Icon = "folder" })
}
Tabs.Settings:AddDropdown("Language", {
    Title = "Ngôn ngữ",
    Description = "English / Tiếng Việt",
    Values = {"English", "Tiếng Việt"},
    Multi = false,
    Default = appConfig.Language,
}):OnChanged(function(value)
    appConfig.Language = normalizeLanguage(value)
    saveConfig()
    Fluent:Notify({
        Title = "Ngôn ngữ",
        Content = "Đã lưu ngôn ngữ. Hãy chạy lại script để cập nhật toàn bộ giao diện.",
        Duration = 7,
    })
end)
local paragraphUpdateErrors = setmetatable({}, {__mode = "k"})
local function safeSetParagraphDesc(paragraph, description)
    if not paragraph then return false end
    local getIdentity = getthreadidentity or get_thread_identity
    local setIdentity = setthreadidentity or set_thread_identity
    local previousIdentity
    if type(getIdentity) == "function" then
        pcall(function() previousIdentity = getIdentity() end)
    end
    if type(setIdentity) == "function" then pcall(setIdentity, 8) end
    local ok, err = pcall(function() paragraph:SetDesc(description) end)
    if type(setIdentity) == "function" and previousIdentity then pcall(setIdentity, previousIdentity) end
    if not ok and tick() - (paragraphUpdateErrors[paragraph] or 0) >= 10 then
        paragraphUpdateErrors[paragraph] = tick()
        warn("[UI] SetDesc failed: " .. tostring(err))
    end
    return ok
end
task.wait()
Tabs.Lobby:AddParagraph({ Title = "Thông Tin", Content = "Tự động nhận quà và nhiệm vụ ngầm." })
Tabs.Lobby:AddToggle("ToggleQuest", {Title = "Auto Claim Quests & Events", Default = appConfig.autoClaimQuests}):OnChanged(function(v) appConfig.autoClaimQuests = v; saveConfig() end)
Tabs.Lobby:AddToggle("ToggleBP", {Title = "Auto Claim Battlepass", Default = appConfig.autoClaimBP}):OnChanged(function(v) appConfig.autoClaimBP = v; saveConfig() end)
Tabs.Lobby:AddToggle("ToggleCal", {Title = "Auto Claim Calendar", Default = appConfig.autoClaimCalendar}):OnChanged(function(v) appConfig.autoClaimCalendar = v; saveConfig() end)
Tabs.Lobby:AddToggle("ToggleMilestone", {Title = "Auto Claim Milestones", Default = appConfig.autoClaimMilestones}):OnChanged(function(v) appConfig.autoClaimMilestones = v; saveConfig() end)
Tabs.Lobby:AddToggle("ToggleIndex", {Title = "Auto Claim Index (Unit / Enemy / Equipment)", Default = appConfig.autoClaimIndex}):OnChanged(function(v) appConfig.autoClaimIndex = v; saveConfig() end)
Tabs.Lobby:AddToggle("ToggleAchievements", {Title = "Auto Claim Thành Tựu", Default = appConfig.autoClaimAchievements}):OnChanged(function(v) appConfig.autoClaimAchievements = v; saveConfig() end)
Tabs.Lobby:AddToggle("ToggleRedeemCodes", {Title = "Auto Nhập Code", Description = "Quét code active từ Anime Expeditions Wiki mỗi 10 phút.", Default = appConfig.autoRedeemCodes}):OnChanged(function(v) appConfig.autoRedeemCodes = v; saveConfig() end)
task.wait()
Tabs.Summon:AddParagraph({ Title = "Snipe Unit", Content = "Tự động quét server và roll Unit nếu có trong Banner." })
local function multiDropdownDefaults(values)
    local defaults = {}
    for key, value in pairs(type(values) == "table" and values or {}) do
        local selected = type(key) == "number" and value or (value and key or nil)
        if selected ~= nil then defaults[tostring(selected)] = true end
    end
    return defaults
end
do
local DropBanners = Tabs.Summon:AddDropdown("DropBanners", {Title = "Select Banners", Values = allBanners, Multi = true, Default = multiDropdownDefaults(appConfig.autoSummonBanners)})
DropBanners:OnChanged(function(Value)
    local selected = {}
    for k, v in pairs(Value) do
        local banner = type(k) == "number" and v or (v and k or nil)
        if banner then table.insert(selected, tostring(banner)) end
    end
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
local DropUnits = Tabs.Summon:AddDropdown("DropUnits", {Title = "Target Units", Values = allUnits, Multi = true, Default = multiDropdownDefaults(defaultSummonUnitLabels)})
DropUnits:OnChanged(function(Value)
    local selected = {}
    for k, v in pairs(Value) do
        local label = type(k) == "number" and v or (v and k or nil)
        if label then
            local assetId = unitLabelToAssetId[label] or tostring(label):match("%[(.-)%]$") or tostring(label)
            if assetId ~= "" then
                table.insert(selected, assetId)
            end
        end
    end
    appConfig.autoSummonUnits = selected
    saveConfig()
end)
Tabs.Summon:AddDropdown("DropAmount", {Title = "Summon Amount", Values = {"1", "10", "50", "Max"}, Multi = false, Default = tostring(appConfig.autoSummonAmount) == "Max" and 4 or (tostring(appConfig.autoSummonAmount) == "50" and 3 or (tostring(appConfig.autoSummonAmount) == "10" and 2 or 1))}):OnChanged(function(Value) appConfig.autoSummonAmount = Value == "Max" and "Max" or (tonumber(Value) or 1); saveConfig() end)
Tabs.Summon:AddToggle("ToggleSummon", {Title = "Bật Auto Summon (Snipe)", Default = appConfig.autoSummonEnabled}):OnChanged(function(v) appConfig.autoSummonEnabled = v; saveConfig() end)
end
task.wait()
EventAuto.StatusParagraph = Tabs.Event:AddParagraph({
    Title = "Event Priority",
    Content = "Guess That Unit > Boss Bounty > Dragon's Wish > Quest > Challenge > AutoJoin",
})
Tabs.Event:AddToggle("AutoGuessUnit", {
    Title = "Auto Guess That Unit",
    Description = "Tự hoàn thành các difficulty đã chọn mỗi ngày.",
    Default = appConfig.EventAuto.autoGuessUnit,
}):OnChanged(function(value) appConfig.EventAuto.autoGuessUnit = value; EventAuto.Runtime.Pending = nil; saveConfig() end)
Tabs.Event:AddDropdown("GuessUnitDifficulties", {
    Title = "Guess difficulties",
    Values = {"Normal", "Hard"},
    Multi = true,
    Default = multiDropdownDefaults(appConfig.EventAuto.guessDifficulties),
}):OnChanged(function(value)
    local selected = {}
    for key, enabled in pairs(value or {}) do
        local difficulty = type(key) == "number" and enabled or (enabled and key or nil)
        if difficulty == "Normal" or difficulty == "Hard" then table.insert(selected, difficulty) end
    end
    appConfig.EventAuto.guessDifficulties = selected
    EventAuto.Runtime.Pending = nil
    saveConfig()
end)
Tabs.Event:AddToggle("AutoBossBounty", {
    Title = "Auto Boss Bounty",
    Description = "Roll và đánh tối đa 5 Boss Bounty mỗi ngày.",
    Default = appConfig.EventAuto.autoBossBounty,
}):OnChanged(function(value) appConfig.EventAuto.autoBossBounty = value; EventAuto.Runtime.ActiveTarget = nil; EventAuto.Runtime.Pending = nil; saveConfig() end)
Tabs.Event:AddToggle("AutoBossBountyReroll", {
    Title = "Auto Reroll Boss Bounty",
    Description = "Tốn 5.000 Gold nếu rarity hiện tại không nằm trong danh sách giữ.",
    Default = appConfig.EventAuto.bossBountyAutoReroll,
}):OnChanged(function(value) appConfig.EventAuto.bossBountyAutoReroll = value; saveConfig() end)
Tabs.Event:AddDropdown("BossBountyKeepRarities", {
    Title = "Boss rarity muốn giữ",
    Values = {"Rare", "Legendary", "Secret"},
    Multi = true,
    Default = multiDropdownDefaults(appConfig.EventAuto.bossBountyKeepRarities),
}):OnChanged(function(value)
    local selected = {}
    for key, enabled in pairs(value or {}) do
        local rarity = type(key) == "number" and enabled or (enabled and key or nil)
        if rarity == "Rare" or rarity == "Legendary" or rarity == "Secret" then table.insert(selected, rarity) end
    end
    appConfig.EventAuto.bossBountyKeepRarities = selected
    saveConfig()
end)
Tabs.Event:AddToggle("AutoDragonWish", {
    Title = "Auto Dragon's Wish",
    Description = "Đọc quest ShenronEvent runtime, tự claim và chạy objective được hỗ trợ.",
    Default = appConfig.EventAuto.autoDragonWish,
}):OnChanged(function(value) appConfig.EventAuto.autoDragonWish = value; EventAuto.Runtime.ActiveTarget = nil; EventAuto.Runtime.Pending = nil; saveConfig() end)
Tabs.Event:AddToggle("AutoRedeemDragonWish", {
    Title = "Auto Redeem Wish",
    Description = "Mặc định tắt. Chỉ áp Unbound khi đã chọn UnitID DBZ hợp lệ.",
    Default = appConfig.EventAuto.autoRedeemWish,
}):OnChanged(function(value) appConfig.EventAuto.autoRedeemWish = value; EventAuto.Runtime.Pending = nil; saveConfig() end)
do
local options, labelToId, idToLabel = getWishUnitOptions()
EventAuto.Runtime.WishUnitLabels = options
EventAuto.Runtime.WishLabelToId = labelToId
EventAuto.WishUnitDropdown = Tabs.Event:AddDropdown("DragonWishUnit", {
    Title = "DBZ Unit nhận Unbound",
    Values = options,
    Multi = false,
    Default = idToLabel[appConfig.EventAuto.wishUnitId] or "Không chọn",
})
EventAuto.WishUnitDropdown:OnChanged(function(value)
    appConfig.EventAuto.wishUnitId = EventAuto.Runtime.WishLabelToId[tostring(value)]
    saveConfig()
end)
Tabs.Event:AddButton({
    Title = "Refresh DBZ Units",
    Callback = function() EventAuto:RefreshWishUnits(true) end,
})
end
local eventMacroMaps = {}
do
    local seen = {}
    for _, modeName in ipairs({"Story", "Raid", "Mastery", "Infinite"}) do
        for mapName in pairs((MapInfo.MapData and MapInfo.MapData[modeName]) or {}) do
            mapName = tostring(mapName)
            if not seen[mapName] then seen[mapName] = true; table.insert(eventMacroMaps, mapName) end
        end
    end
    table.sort(eventMacroMaps)
end
local function addEventMapMacroDropdowns(title, description, configField, idPrefix, modes, owner)
    Tabs.Event:AddParagraph({Title = title, Content = description})
    for _, mapName in ipairs(eventMacroMaps) do
        local macroChoices = {"Không chọn"}
        for macroKey, macroData in pairs(appConfig.Macros) do
            local normalizedMacroKey = normalizeStageKey(macroKey)
            local belongsToMap = false
            for _, modeName in ipairs(modes) do
                local normalizedModeMap = normalizeStageKey(modeName .. "_" .. mapName)
                local stageSuffix = normalizedMacroKey:sub(#normalizedModeMap + 1)
                if normalizedMacroKey:sub(1, #normalizedModeMap) == normalizedModeMap
                    and (stageSuffix == "" or stageSuffix:match("^%d+$") or stageSuffix:match("^act%d+$")) then
                    belongsToMap = true
                    break
                end
            end
            if type(macroData) == "table" and #macroData > 0 and belongsToMap then table.insert(macroChoices, tostring(macroKey)) end
        end
        table.sort(macroChoices, function(left, right)
            if left == right then return false end
            if left == "Không chọn" then return true end
            if right == "Không chọn" then return false end
            return left < right
        end)
        local selectedMacro = appConfig.EventAuto[configField][mapName]
        if selectedMacro and not table.find(macroChoices, selectedMacro) then
            local normalizedSelected = normalizeStageKey(selectedMacro)
            for _, choice in ipairs(macroChoices) do
                if normalizeStageKey(choice) == normalizedSelected then
                    selectedMacro = choice
                    appConfig.EventAuto[configField][mapName] = choice
                    break
                end
            end
            if not table.find(macroChoices, selectedMacro) and appConfig.Macros[selectedMacro] then table.insert(macroChoices, selectedMacro) end
        end
        Tabs.Event:AddDropdown(idPrefix .. mapName:gsub("[^%w%-_]", ""), {
            Title = mapName,
            Values = macroChoices,
            Multi = false,
            Default = selectedMacro or "Không chọn",
        }):OnChanged(function(value)
            appConfig.EventAuto[configField][mapName] = value ~= "Không chọn" and value or nil
            local stateInfo = getGameStates()
            local target = EventAuto.Runtime.ActiveTarget
            if (not stateInfo or stateInfo.CurrentGameState == "Lobby") and type(target) == "table" and target.Owner == owner then
                EventAuto.Runtime.ActiveTarget = nil
            end
            saveConfig()
        end)
    end
end
addEventMapMacroDropdowns(
    "Boss Bounty - Macro Theo Map",
    "Mỗi map chọn Macro riêng chỉ dùng khi Boss Bounty điều khiển trận.",
    "bossBountyMapMacros",
    "BossBountyMapMacro_",
    {"Story", "Raid", "Mastery", "Infinite", "Challenge"},
    "BossBounty"
)
addEventMapMacroDropdowns(
    "Dragon Wish - Macro Theo Map",
    "Mỗi map chọn Macro riêng chỉ dùng khi Dragon Wish chạy objective.",
    "dragonWishMapMacros",
    "DragonWishMapMacro_",
    {"Story", "Raid", "Mastery", "Infinite", "Challenge"},
    "DragonWish"
)
task.wait()
QuestAuto.StatusParagraph = Tabs.Quest:AddParagraph({
    Title = "Daily + Weekly Quest",
    Content = "Đang chờ dữ liệu Daily / Weekly...",
})
QuestAuto.Toggle = Tabs.Quest:AddToggle("ToggleAutoQuest", {
    Title = "Bật Auto Daily + Weekly Quest",
    Description = "Ưu tiên Quest trước Challenge và Auto Join Map.",
    Default = appConfig.QuestAuto.Enabled,
})
QuestAuto.Toggle:OnChanged(function(value)
    appConfig.QuestAuto.Enabled = value
    if not value then
        appConfig.QuestAuto.ActiveTarget = nil
        QuestAuto.Runtime.Pending = nil
    end
    saveConfig()
end)
Tabs.Quest:AddParagraph({
    Title = "Macro Theo Map",
    Content = "Một Macro cho mỗi map, dùng khi Quest chạy Story, Infinite, Mastery hoặc Regular Challenge.",
})
do
for _, mapName in ipairs(QuestAuto.Maps) do
    local macroChoices = {"Không chọn"}
    for macroKey, macroData in pairs(appConfig.Macros) do
        local normalizedMacroKey = normalizeStageKey(macroKey)
        local belongsToMap = false
        for _, modeName in ipairs({"Story", "Infinite", "Mastery", "Challenge"}) do
            local normalizedModeMap = normalizeStageKey(modeName .. "_" .. mapName)
            local stageSuffix = normalizedMacroKey:sub(#normalizedModeMap + 1)
            if normalizedMacroKey:sub(1, #normalizedModeMap) == normalizedModeMap
                and (stageSuffix == "" or stageSuffix:match("^%d+$") or stageSuffix:match("^act%d+$")) then
                belongsToMap = true
                break
            end
        end
        if type(macroData) == "table" and #macroData > 0 and belongsToMap then table.insert(macroChoices, tostring(macroKey)) end
    end
    table.sort(macroChoices, function(left, right)
        if left == right then return false end
        if left == "Không chọn" then return true end
        if right == "Không chọn" then return false end
        return left < right
    end)
    local selectedMacro = appConfig.QuestAuto.MapMacros[mapName]
    if selectedMacro then
        local found = table.find(macroChoices, selectedMacro)
        if not found then
            local normSelected = normalizeStageKey(selectedMacro)
            for _, choice in ipairs(macroChoices) do
                if normalizeStageKey(choice) == normSelected then
                    selectedMacro = choice
                    appConfig.QuestAuto.MapMacros[mapName] = choice
                    found = true
                    break
                end
            end
        end
        if not found and appConfig.Macros[selectedMacro] then
            table.insert(macroChoices, selectedMacro)
        end
    end
    Tabs.Quest:AddDropdown("QuestMapMacro_" .. mapName, {
        Title = mapName,
        Values = macroChoices,
        Multi = false,
        Default = selectedMacro or "Không chọn",
    }):OnChanged(function(value)
        local nextMacro = value ~= "Không chọn" and value or nil
        if appConfig.QuestAuto.MapMacros[mapName] ~= nextMacro then
            appConfig.QuestAuto.MapMacros[mapName] = nextMacro
            QuestAuto.Runtime.SkippedModes = {}
            QuestAuto.Runtime.SkippedChallenges = {}
            local stateInfo = getGameStates()
            if not stateInfo or stateInfo.CurrentGameState == "Lobby" then appConfig.QuestAuto.ActiveTarget = nil end
            saveConfig()
        end
    end)
end
end
task.wait()
Tabs.Story:AddParagraph({
    Title = "Một Macro cho mọi Act",
    Content = "Mỗi World chọn một Macro Story đã ghi ở bất kỳ Act nào. Macro tự chạy cho mọi Act của World này; chọn Không chọn để tắt. Quest và Challenge vẫn dùng Macro riêng.",
})
do
local storyMapNames = {}
for mapName in pairs((MapInfo.MapData and MapInfo.MapData.Story) or {}) do
    table.insert(storyMapNames, tostring(mapName))
end
table.sort(storyMapNames)
for _, mapName in ipairs(storyMapNames) do
    local macroChoices = {"Không chọn"}
    local normalizedStoryMap = normalizeStageKey("Story_" .. mapName)
    for macroKey, macroData in pairs(appConfig.Macros) do
        local normalizedMacroKey = normalizeStageKey(macroKey)
        local stageSuffix = normalizedMacroKey:sub(#normalizedStoryMap + 1)
        if type(macroData) == "table" and #macroData > 0
            and normalizedMacroKey:sub(1, #normalizedStoryMap) == normalizedStoryMap
            and (stageSuffix == "" or stageSuffix:match("^%d+$") or stageSuffix:match("^act%d+$")) then
            table.insert(macroChoices, tostring(macroKey))
        end
    end
    table.sort(macroChoices, function(left, right)
        if left == right then return false end
        if left == "Không chọn" then return true end
        if right == "Không chọn" then return false end
        return left < right
    end)
    local selectedMacro = appConfig.storyMapMacros[mapName]
    if selectedMacro then
        local found = table.find(macroChoices, selectedMacro)
        if not found then
            local normSelected = normalizeStageKey(selectedMacro)
            for _, choice in ipairs(macroChoices) do
                if normalizeStageKey(choice) == normSelected then
                    selectedMacro = choice
                    appConfig.storyMapMacros[mapName] = choice
                    found = true
                    break
                end
            end
        end
        if not found and appConfig.Macros[selectedMacro] then
            table.insert(macroChoices, selectedMacro)
        end
    end
    Tabs.Story:AddDropdown("StoryMapMacro_" .. mapName:gsub("[^%w%-_]", ""), {
        Title = mapName,
        Values = macroChoices,
        Multi = false,
        Default = selectedMacro or "Không chọn",
    }):OnChanged(function(value)
        appConfig.storyMapMacros[mapName] = value ~= "Không chọn" and value or nil
        saveConfig()
    end)
end
end
task.wait()
local challengeStatusPara = Tabs.Challenge:AddParagraph({
    Title = "Regular Challenge",
    Content = "Đang chờ dữ liệu Regular Challenge...",
})
local autoChallengeToggle = Tabs.Challenge:AddToggle("ToggleAutoChallenge", {
    Title = "Bật Auto Regular Challenge",
    Description = "Chạy các Regular Challenge khả dụng; khi cooldown sẽ nhường Auto Join Map.",
    Default = appConfig.autoChallengeEnabled,
}):OnChanged(function(value)
    appConfig.autoChallengeEnabled = value
    if not value and type(appConfig.challengeActiveTarget) == "table" and appConfig.challengeActiveTarget.ChallengeType ~= "Daily" then
        appConfig.challengeActiveTarget = nil
    end
    saveConfig()
end)
Tabs.Challenge:AddToggle("ToggleAutoDailyChallenge", {
    Title = "Tự chạy Daily Challenge",
    Description = "Ưu tiên Daily Challenge trước Regular; dùng Macro theo Map đã chọn bên dưới.",
    Default = appConfig.autoDailyChallengeEnabled,
}):OnChanged(function(value)
    appConfig.autoDailyChallengeEnabled = value
    if not value and type(appConfig.challengeActiveTarget) == "table" and appConfig.challengeActiveTarget.ChallengeType == "Daily" then
        appConfig.challengeActiveTarget = nil
    end
    saveConfig()
end)
Tabs.Challenge:AddDropdown("ChallengeAutoSelectedSlots", {
    Title = "Regular slot Auto Challenge sẽ chạy",
    Description = "Mặc định chọn cả 3; bỏ chọn slot nào thì chỉ Auto Challenge skip slot đó.",
    Values = {"Regular #1", "Regular #2", "Regular #3"},
    Multi = true,
    Default = {
        ["Regular #1"] = appConfig.challengeAutoSelectedSlots["1"] == true,
        ["Regular #2"] = appConfig.challengeAutoSelectedSlots["2"] == true,
        ["Regular #3"] = appConfig.challengeAutoSelectedSlots["3"] == true,
    },
}):OnChanged(function(value)
    local selected = {}
    for key, enabled in pairs(value or {}) do
        local label = type(key) == "number" and enabled or (enabled and key or nil)
        local index = label and tonumber(tostring(label):match("#(%d+)$")) or nil
        if index and index >= 1 and index <= 3 then selected[tostring(index)] = true end
    end
    local changed = false
    for index = 1, 3 do
        local key = tostring(index)
        if (appConfig.challengeAutoSelectedSlots[key] == true) ~= (selected[key] == true) then changed = true break end
    end
    appConfig.challengeAutoSelectedSlots = selected
    local target = appConfig.challengeActiveTarget
    if changed and type(target) == "table" and target.Owner == "Challenge" and target.ChallengeType ~= "Daily" then appConfig.challengeActiveTarget = nil end
    saveConfig()
end)
Tabs.Challenge:AddParagraph({
    Title = "Macro Theo Map",
    Content = "Mỗi map chọn một Macro chỉ dùng khi Auto Challenge điều khiển trận.",
})
do
local challengeMapNames = {}
for mapName in pairs((MapInfo.MapData and MapInfo.MapData.Story) or {}) do
    table.insert(challengeMapNames, tostring(mapName))
end
table.sort(challengeMapNames)
for _, mapName in ipairs(challengeMapNames) do
    local macroChoices = {"Không chọn"}
    for macroKey, macroData in pairs(appConfig.Macros) do
        local normalizedMacroKey = normalizeStageKey(macroKey)
        local belongsToMap = false
        for _, modeName in ipairs({"Story", "Infinite", "Challenge"}) do
            local normalizedModeMap = normalizeStageKey(modeName .. "_" .. mapName)
            local stageSuffix = normalizedMacroKey:sub(#normalizedModeMap + 1)
            if normalizedMacroKey:sub(1, #normalizedModeMap) == normalizedModeMap
                and (stageSuffix == "" or stageSuffix:match("^%d+$") or stageSuffix:match("^act%d+$")) then
                belongsToMap = true
                break
            end
        end
        if type(macroData) == "table" and #macroData > 0 and belongsToMap then
            table.insert(macroChoices, tostring(macroKey))
        end
    end
    table.sort(macroChoices, function(left, right)
        if left == right then return false end
        if left == "Không chọn" then return true end
        if right == "Không chọn" then return false end
        return left < right
    end)
    local selectedMacro = appConfig.challengeMapMacros[mapName]
    if selectedMacro then
        local found = table.find(macroChoices, selectedMacro)
        if not found then
            local normSelected = normalizeStageKey(selectedMacro)
            for _, choice in ipairs(macroChoices) do
                if normalizeStageKey(choice) == normSelected then
                    selectedMacro = choice
                    appConfig.challengeMapMacros[mapName] = choice
                    found = true
                    break
                end
            end
        end
        if not found and appConfig.Macros[selectedMacro] then
            table.insert(macroChoices, selectedMacro)
        end
    end
    Tabs.Challenge:AddDropdown("ChallengeMapMacro_" .. mapName:gsub("[^%w%-_]", ""), {
        Title = mapName,
        Values = macroChoices,
        Multi = false,
        Default = selectedMacro or "Không chọn",
    }):OnChanged(function(value)
        appConfig.challengeMapMacros[mapName] = value ~= "Không chọn" and value or nil
        saveConfig()
    end)
end
end
task.wait()
Tabs.Shop:AddParagraph({ Title = "Auto Shop", Content = "Tự động mua số lượng tối đa có thể của từng vật phẩm đã chọn, theo stock, tiền và giới hạn kho." })
Tabs.Shop:AddToggle("AutoShopEnabled", {Title = "Bật Auto Shop", Default = appConfig.autoShopEnabled}):OnChanged(function(state)
    appConfig.autoShopEnabled = state
    saveConfig()
end)
do
local groupedShops = {}
for _, item in ipairs(allShops) do
    if not groupedShops[item.StoreId] then groupedShops[item.StoreId] = {} end
    table.insert(groupedShops[item.StoreId], item.ProductId)
end
for storeId, products in pairs(groupedShops) do
    local productSet = {}
    for _, productId in ipairs(products) do productSet[tostring(productId)] = true end
    local savedProducts = {}
    for _, productId in ipairs(appConfig.ShopSelections[storeId] or {}) do
        if productSet[tostring(productId)] then table.insert(savedProducts, tostring(productId)) end
    end
    appConfig.ShopSelections[storeId] = savedProducts
    Tabs.Shop:AddDropdown("ShopDrop_" .. storeId, {
        Title = storeId,
        Values = products,
        Multi = true,
        Default = multiDropdownDefaults(appConfig.ShopSelections[storeId])
    }):OnChanged(function(value)
        local selected = {}
        for k, v in pairs(value) do
            local productId = type(k) == "number" and v or (v and k or nil)
            if productId and productSet[tostring(productId)] then table.insert(selected, tostring(productId)) end
        end
        appConfig.ShopSelections[storeId] = selected
        saveConfig()
    end)
end
saveConfig()
end
task.wait()
Tabs.Craft:AddParagraph({ Title = "Auto Craft", Content = "Tự động ghép đồ khi đang ở Lobby." })
Tabs.Craft:AddToggle("AutoCraftEnabled", {Title = "Bật Auto Craft (Lobby)", Default = appConfig.autoCraftEnabled}):OnChanged(function(state)
    appConfig.autoCraftEnabled = state
    saveConfig()
end)
do
local craftableList = {
    "HexedBlade", "HolyPendant",
    "SpriteRainbow", "SpriteBlue", "SpriteGreen",
    "SpritePink", "SpritePurple", "SpriteRed",
    "SpriteYellow", "SpriteGrey"
}
Tabs.Craft:AddDropdown("DropCraft", {Title = "Chọn đồ muốn Craft", Values = craftableList, Multi = true, Default = multiDropdownDefaults(appConfig.autoCraftItems)}):OnChanged(function(Value)
    local t = {}
    for k, v in pairs(Value) do
        local asset = type(k) == "number" and v or (v and k or nil)
        if asset then table.insert(t, tostring(asset)) end
    end
    appConfig.autoCraftItems = t
    saveConfig()
end)
getgenv().AnimeExpeditionsLeaveToggles.Sprite = Tabs.Craft:AddToggle("AutoLeaveSpriteMax", {Title = "Tự động Về Đảo khi Full Sprite (Grey)", Default = appConfig.autoLeaveSpriteMax})
getgenv().AnimeExpeditionsLeaveToggles.Sprite:OnChanged(function(state)
    state = getgenv().AnimeExpeditionsGuardAutoLeave(state, "Sprite")
    appConfig.autoLeaveSpriteMax = state
    local coordinator = getgenv().AnimeExpeditionsCoordinator
    if not state and coordinator and coordinator:GetMaintenance().Reasons.SpriteCraft then coordinator:ClearReason("SpriteCraft") end
    saveConfig()
end)
local function getExpeditionCraftableList()
    local crafting = Fusion.peek(Dependencies.Crafting)
    if type(crafting) ~= "table" then return {}, false end
    local recipesByStation = Fusion.peek(crafting.Recipes)
    local recipes = type(recipesByStation) == "table" and Fusion.peek(recipesByStation["Armory Forge"]) or nil
    if type(recipes) ~= "table" then return {}, false end
    local result = {}
    for asset in pairs(recipes) do
        table.insert(result, tostring(asset))
    end
    table.sort(result)
    return result, true
end
local expeditionCraftableList, expeditionCraftDataReady = getExpeditionCraftableList()
if expeditionCraftDataReady then
    local available = {}
    for _, asset in ipairs(expeditionCraftableList) do available[asset] = true end
    local selected = {}
    for _, asset in ipairs(appConfig.autoExpeditionCraftItems) do
        if available[asset] then table.insert(selected, asset) end
    end
    appConfig.autoExpeditionCraftItems = selected
end
Tabs.Craft:AddParagraph({ Title = "Auto Craft Expedition", Content = "Tự động ghép trang bị tại Armory Forge khi đang ở Lobby." })
Tabs.Craft:AddToggle("AutoExpeditionCraftEnabled", {Title = "Bật Auto Craft Expedition", Default = appConfig.autoExpeditionCraftEnabled}):OnChanged(function(state)
    appConfig.autoExpeditionCraftEnabled = state
    saveConfig()
end)
Tabs.Craft:AddDropdown("DropExpeditionCraft", {Title = "Chọn đồ Expedition muốn Craft", Values = expeditionCraftableList, Multi = true, Default = multiDropdownDefaults(appConfig.autoExpeditionCraftItems)}):OnChanged(function(Value)
    local selected = {}
    for k, v in pairs(Value) do
        local asset = type(k) == "number" and v or (v and k or nil)
        if asset then table.insert(selected, tostring(asset)) end
    end
    appConfig.autoExpeditionCraftItems = selected
    saveConfig()
end)
getgenv().AnimeExpeditionsLeaveToggles.ExpeditionScrap = Tabs.Craft:AddToggle("AutoLeaveExpeditionScrapMax", {Title = "Tự động Về Đảo khi Full Equipment Scrap", Default = appConfig.autoLeaveExpeditionScrapMax})
getgenv().AnimeExpeditionsLeaveToggles.ExpeditionScrap:OnChanged(function(state)
    state = getgenv().AnimeExpeditionsGuardAutoLeave(state, "ExpeditionScrap")
    appConfig.autoLeaveExpeditionScrapMax = state
    if not state then
        appConfig.expeditionScrapCraftPending = false
        appConfig.expeditionScrapCraftPendingSince = 0
        local coordinator = getgenv().AnimeExpeditionsCoordinator
        if coordinator and coordinator:GetMaintenance().Reasons.ExpeditionScrapCraft then coordinator:ClearReason("ExpeditionScrapCraft") end
    end
    saveConfig()
end)
end
task.wait()
local AutoJoinStatusPara
local function setupJoinAndTeamTabs()
Tabs.Join:AddParagraph({ Title = "Auto Join Map", Content = "Chọn Map và bật Auto Join để tự động ghép trận." })
local CurrentJoinPara = Tabs.Join:AddParagraph({ Title = "Map Đang Chọn", Content = appConfig.AutoJoin ~= "" and appConfig.AutoJoin or "Chưa chọn Map nào" })
AutoJoinStatusPara = Tabs.Join:AddParagraph({ Title = "Trạng Thái Join", Content = "Đang khởi tạo scheduler..." })
getgenv().AnimeExpeditionsAutoJoinToggle = Tabs.Join:AddToggle("ToggleJoinMaster", {Title = "Bật Auto Join Map Đang Chọn", Default = appConfig.autoJoinEnabled})
getgenv().AnimeExpeditionsAutoJoinToggle:OnChanged(function(v)
    appConfig.autoJoinEnabled = v
    if not v then getgenv().AnimeExpeditionsDisableAutoLeaves(false) else saveConfig() end
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

Tabs.Team:AddParagraph({ Title = "Cài Đặt Đội Hình", Content = "Chọn Team riêng cho từng Map; Auto Load Team dùng cấu hình này trước khi vào trận." })
Tabs.Team:AddToggle("ToggleAutoTeam", {Title = "Tự động nạp Team (Auto Load Team)", Default = appConfig.autoJoinTeamEnabled}):OnChanged(function(v)
    appConfig.autoJoinTeamEnabled = v
    saveConfig()
end)
do
local allUniqueMaps = {}
local seenMaps = {}
for mode, maps in pairs(MapInfo.MapData or {}) do
    if mode ~= "Trial" and type(maps) == "table" then
    for mapId in pairs(maps) do
        if not seenMaps[mapId] then
            seenMaps[mapId] = true
            table.insert(allUniqueMaps, mapId)
        end
    end
    end
end
table.sort(allUniqueMaps)
for _, mapId in ipairs(allUniqueMaps) do
    Tabs.Team:AddDropdown("TeamSelect_" .. mapId, {
        Title = string.format(localizeText("Team cho %s"), mapId),
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
end

Tabs.Join:AddSection("Chọn Map")
local function setJoinMap(mode, mapId, act, diff)
    local uid = mode .. "|" .. mapId .. (act and ("|" .. act) or "") .. (diff and ("|" .. diff) or "")
    appConfig.AutoJoin = uid
    safeSetParagraphDesc(CurrentJoinPara, string.gsub(uid, "|", " -> "))
    saveConfig()
end
local joinTree, worldLabels, worldLabelToId, worldIdToLabel = {}, {}, {}, {}
for mode, maps in pairs(MapInfo.MapData or {}) do
    if mode ~= "Trial" and type(maps) == "table" then
        for mapId, mapData in pairs(maps) do
            mapData = type(mapData) == "table" and mapData or {}
            joinTree[mapId] = joinTree[mapId] or {Modes = {}}
            local entry = joinTree[mapId]
            local displayName = tostring(mapData.Name or mapData.DisplayName or mapId):gsub("Expedition$", ""):gsub("(%l)(%u)", "%1 %2")
            entry.Label = entry.Label or displayName
            entry.Modes[mode] = entry.Modes[mode] or {}
            local difficulties = {}
            if mode == "Expedition" then
                for difficulty = 1, 3 do table.insert(difficulties, {Label = "Difficulty " .. difficulty, Value = tostring(difficulty)}) end
            elseif type(mapData.Difficulties) == "table" then
                for difficultyId, difficultyName in pairs(mapData.Difficulties) do
                    local value = type(difficultyName) == "string" and difficultyName or tostring(difficultyId)
                    table.insert(difficulties, {Label = value, Value = value})
                end
            end
            if #difficulties == 0 then
                local value = (mode == "Infinite" or mode == "Mastery") and "Hard" or ""
                table.insert(difficulties, {Label = value ~= "" and value or "Default", Value = value})
            end
            local acts = {}
            if mode ~= "Expedition" and type(mapData.Acts) == "table" then
                for actId in pairs(mapData.Acts) do table.insert(acts, tostring(actId)) end
            end
            if #acts == 0 then table.insert(acts, mode == "Infinite" and "1" or "") end
            for _, difficulty in ipairs(difficulties) do
                entry.Modes[mode][difficulty.Label] = {Value = difficulty.Value, Acts = {}}
                for _, act in ipairs(acts) do
                    local actLabel = act ~= "" and (act:find("Act", 1, true) and act or "Act " .. act) or "Không có Act"
                    entry.Modes[mode][difficulty.Label].Acts[actLabel] = act
                end
            end
        end
    end
end
for mapId, entry in pairs(joinTree) do
    local label = entry.Label
    if worldLabelToId[label] and worldLabelToId[label] ~= mapId then label = label .. " [" .. mapId .. "]" end
    worldLabelToId[label] = mapId
    worldIdToLabel[mapId] = label
    table.insert(worldLabels, label)
end
table.sort(worldLabels)
local selectedParts = string.split(appConfig.AutoJoin or "", "|")
local allModes, seenModes = {}, {}
for _, entry in pairs(joinTree) do
    for mode in pairs(entry.Modes) do
        if not seenModes[mode] then seenModes[mode] = true; table.insert(allModes, mode) end
    end
end
table.sort(allModes)
local selectedMode = seenModes[selectedParts[1]] and selectedParts[1] or (seenModes.Story and "Story" or allModes[1] or "(Không có)")
local selectedWorldLabel = worldIdToLabel[selectedParts[2]]
if not selectedWorldLabel or not (joinTree[selectedParts[2]] and joinTree[selectedParts[2]].Modes[selectedMode]) then
    selectedWorldLabel = nil
    for _, label in ipairs(worldLabels) do
        local mapId = worldLabelToId[label]
        if joinTree[mapId] and joinTree[mapId].Modes[selectedMode] then selectedWorldLabel = label break end
    end
end
selectedWorldLabel = selectedWorldLabel or "(Không có Map)"
local selectedWorldId = worldLabelToId[selectedWorldLabel]
local selectedWorld = joinTree[selectedWorldId] or {Modes = {}}
local selectedDifficultyLabel = "Default"
for label, data in pairs(selectedWorld.Modes[selectedMode] or {}) do
    if tostring(data.Value or "") == tostring(selectedParts[4] or "") then selectedDifficultyLabel = label break end
end
local selectedActLabel = "Không có Act"
local selectedDifficultyData = (selectedWorld.Modes[selectedMode] or {})[selectedDifficultyLabel]
for label, value in pairs(selectedDifficultyData and selectedDifficultyData.Acts or {}) do
    if tostring(value or "") == tostring(selectedParts[3] or "") then selectedActLabel = label break end
end
local joinModeDropdown = Tabs.Join:AddDropdown("JoinGamemode", {Title = "Chế độ", Description = "Chọn chế độ trước để lọc danh sách World.", Values = #allModes > 0 and allModes or {"(Không có)"}, Multi = false, Default = selectedMode})
local joinWorldDropdown = Tabs.Join:AddDropdown("JoinWorld", {Title = "Story / World", Description = "Chỉ hiện map thuộc chế độ đã chọn.", Values = {selectedWorldLabel}, Multi = false, Default = selectedWorldLabel})
local joinDifficultyDropdown = Tabs.Join:AddDropdown("JoinDifficulty", {Title = "Độ khó", Values = {selectedDifficultyLabel}, Multi = false, Default = selectedDifficultyLabel})
local joinActDropdown = Tabs.Join:AddDropdown("JoinAct", {Title = "Map / Act", Values = {selectedActLabel}, Multi = false, Default = selectedActLabel})
local refreshingJoinControls = false
local function sortedJoinKeys(data)
    local values = {}
    for key in pairs(data or {}) do table.insert(values, key) end
    table.sort(values, function(left, right)
        local leftNumber, rightNumber = tonumber(tostring(left):match("%d+")), tonumber(tostring(right):match("%d+"))
        if leftNumber and rightNumber and leftNumber ~= rightNumber then return leftNumber < rightNumber end
        return tostring(left) < tostring(right)
    end)
    return values
end
local function refreshJoinControls(commitSelection)
    if refreshingJoinControls then return end
    refreshingJoinControls = true
    local mode = joinModeDropdown.Value
    local availableWorlds = {}
    for _, label in ipairs(worldLabels) do
        local mapId = worldLabelToId[label]
        if joinTree[mapId] and joinTree[mapId].Modes[mode] then table.insert(availableWorlds, label) end
    end
    joinWorldDropdown:SetValues(#availableWorlds > 0 and availableWorlds or {"(Không có Map)"})
    local currentWorldId = worldLabelToId[joinWorldDropdown.Value]
    if not currentWorldId or not (joinTree[currentWorldId] and joinTree[currentWorldId].Modes[mode]) then
        joinWorldDropdown:SetValue(availableWorlds[1] or "(Không có Map)")
    end
    local worldId = worldLabelToId[joinWorldDropdown.Value]
    local world = joinTree[worldId] or {Modes = {}}
    local modeData = world.Modes[mode] or {}
    local difficulties = sortedJoinKeys(modeData)
    joinDifficultyDropdown:SetValues(#difficulties > 0 and difficulties or {"Default"})
    if not modeData[joinDifficultyDropdown.Value] then joinDifficultyDropdown:SetValue(difficulties[1] or "Default") end
    local difficultyLabel = joinDifficultyDropdown.Value
    local difficultyData = modeData[difficultyLabel] or {Value = "", Acts = {}}
    local acts = sortedJoinKeys(difficultyData.Acts)
    joinActDropdown:SetValues(#acts > 0 and acts or {"Không có Act"})
    if difficultyData.Acts[joinActDropdown.Value] == nil then joinActDropdown:SetValue(acts[1] or "Không có Act") end
    local act = difficultyData.Acts[joinActDropdown.Value] or ""
    refreshingJoinControls = false
    if commitSelection and worldId and modeData[difficultyLabel] then setJoinMap(mode, worldId, act, difficultyData.Value) end
end
joinModeDropdown:OnChanged(function() refreshJoinControls(true) end)
joinWorldDropdown:OnChanged(function() refreshJoinControls(true) end)
joinDifficultyDropdown:OnChanged(function() refreshJoinControls(true) end)
joinActDropdown:OnChanged(function() refreshJoinControls(true) end)
refreshJoinControls(false)
end
setupJoinAndTeamTabs()
local function hasMacroHotbarUnits()
    local hotbar = Fusion.peek(Dependencies.HotbarState)
    local slots = hotbar and Fusion.peek(hotbar.Slots)
    for _, slot in pairs(type(slots) == "table" and slots or {}) do
        slot = Fusion.peek(slot)
        if type(slot) == "table" and Fusion.peek(slot.AssetType) == "Unit" then return true end
    end
    return false
end
task.wait()
Tabs.Macro:AddParagraph({ Title = "Hệ Thống Macro", Content = "Tự động nhận diện Map đang chơi để chạy Macro tương ứng." })
local installMacroHook
local macroHookGeneration = {}
local isRecording = false
local isPlaying = false
local lastHasRunMacro = false
local startTime = 0
local currentStageKey = "Unknown"
local function shouldSkipExpeditionDefenseMacro(stateInfo)
    if not appConfig.skipExpeditionDefenseMacro or not stateInfo or stateInfo.Gamemode ~= "Expedition" then return false end
    return tostring(stateInfo.Status or ""):lower():find("defen", 1, true) ~= nil
end
local currentMacroPara = Tabs.Macro:AddParagraph({ Title = "Trạng Thái", Content = "Đang ở Lobby" })

local function optimizeStandardMacro(macroData)
    local filtered = {}
    local pendingSelects = {}
    local removedSelects = 0
    local generatedSelects = 0
    local sourceOrder = 0
    local function append(action, order)
        table.insert(filtered, {action = action, order = order})
    end
    local function flushSelects(keepNearestOnly)
        if keepNearestOnly and #pendingSelects > 0 then
            removedSelects += #pendingSelects - 1
            local nearest = pendingSelects[#pendingSelects]
            append(nearest.action, nearest.order)
        else
            for _, entry in ipairs(pendingSelects) do append(entry.action, entry.order) end
        end
        table.clear(pendingSelects)
    end
    for _, action in ipairs(macroData) do
        sourceOrder += 1
        if type(action) == "table" and action.type == "Select" then
            table.insert(pendingSelects, {action = action, order = sourceOrder})
        else
            if type(action) == "table" and action.type == "Place" then
                if #pendingSelects == 0 then
                    generatedSelects += 1
                    append({type = "Select", time = action.time, slot = action.slot, wave = action.wave}, sourceOrder - 0.5)
                else
                    flushSelects(true)
                end
            else
                flushSelects(false)
            end
            append(action, sourceOrder)
        end
    end
    flushSelects(false)

    local lastMutableTime
    local hasFirstSelect = false
    local hasFirstPlace = false
    local function addTime(delta)
        return math.round(((lastMutableTime or 0) + delta) * 10) / 10
    end
    for _, entry in ipairs(filtered) do
        local action = entry.action
        if type(action) == "table" then
            if action.type == "Select" then
                action.time = hasFirstSelect and addTime(0.1) or 0.0
                hasFirstSelect = true
                lastMutableTime = action.time
            elseif action.type == "Place" then
                action.time = hasFirstPlace and addTime(0.3) or 0.3
                hasFirstPlace = true
                lastMutableTime = action.time
            elseif action.type == "VoteStart" then
                action.time = addTime(0.1)
                lastMutableTime = action.time
            else
                local originalTime = tonumber(action.time)
                if originalTime then
                    local minimumTime = lastMutableTime and addTime(0.1) or originalTime
                    action.time = math.max(originalTime, minimumTime)
                    lastMutableTime = action.time
                end
            end
        end
    end

    table.sort(filtered, function(left, right)
        local leftTime = type(left.action) == "table" and tonumber(left.action.time) or nil
        local rightTime = type(right.action) == "table" and tonumber(right.action.time) or nil
        leftTime = leftTime or math.huge
        rightTime = rightTime or math.huge
        if leftTime == rightTime then return left.order < right.order end
        return leftTime < rightTime
    end)
    local result = {}
    for _, entry in ipairs(filtered) do table.insert(result, entry.action) end
    return result, removedSelects, generatedSelects
end
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

Tabs.Macro:AddButton({
    Title = "Tối ưu Macro",
    Description = "Tối ưu Macro nhanh nhất",
    Callback = function()
        local stateInfo = getGameStates()
        if not stateInfo or not currentStageKey or currentStageKey == "" or currentStageKey == "Unknown" then
            Fluent:Notify({Title = "Lỗi", Content = "Phải đứng trong Ải mới tối ưu được Macro!", Duration = 5})
            return
        end
        local macroData, savedStageKey = getMacroListForStage(currentStageKey, stateInfo)
        if type(macroData) ~= "table" or #macroData == 0 then
            Fluent:Notify({Title = "Lỗi", Content = "Map hiện tại chưa có dữ liệu Macro!", Duration = 5})
            return
        end
        local optimized, removed, generated = optimizeStandardMacro(macroData)
        appConfig.Macros[savedStageKey] = optimized
        saveConfig()
        local macroInput = Fluent.Options and Fluent.Options.MacroDataString
        if macroInput then macroInput:SetValue(HttpService:JSONEncode(optimized)) end
        Fluent:Notify({
            Title = "Đã tối ưu Macro",
            Content = (stateInfo.Gamemode == "Expedition" and "Expedition: " or "")
                .. string.format(localizeText("Đã xóa %d Select dư%s"), removed,
                    generated > 0 and string.format(localizeText(", thêm %d Select còn thiếu."), generated) or "."),
            Duration = 6,
        })
    end,
})

local TogglePlay = Tabs.Macro:AddToggle("TogglePlay", {Title = "Bật Auto Play", Default = appConfig.autoPlayEnabled})
TogglePlay:OnChanged(function(state)
    appConfig.autoPlayEnabled = state
    saveConfig()
    if not state then
        local currentState = getGameStates()
        if not EventAuto:TargetMatchesState(currentState) and not QuestAuto:TargetMatchesState(currentState) and not challengeTargetMatchesState(currentState) then isPlaying = false end
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
Tabs.Macro:AddToggle("SkipExpeditionDefenseMacro", {
    Title = "Không chạy Macro ở map Defense",
    Description = "Bật: chỉ chạy Macro ở Assault. Tắt: chạy Macro ở mọi map Expedition.",
    Default = appConfig.skipExpeditionDefenseMacro,
}):OnChanged(function(state)
    appConfig.skipExpeditionDefenseMacro = state
    if state and shouldSkipExpeditionDefenseMacro(getGameStates()) then
        isPlaying = false
        lastHasRunMacro = false
        getgenv().ExpeditionContinueBlocked = false
    elseif not state then
        getgenv().ExpeditionMacroHandledNodeKey = nil
        lastHasRunMacro = false
    end
    saveConfig()
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
getgenv().AnimeExpeditionsLeaveToggles.Defeat = Tabs.Macro:AddToggle("AutoLeaveOnDefeat", {Title = "Tự động Thoát khi Thua (Defeat/Lose)", Default = appConfig.autoLeaveOnDefeat})
getgenv().AnimeExpeditionsLeaveToggles.Defeat:OnChanged(function(state)
    appConfig.autoLeaveOnDefeat = getgenv().AnimeExpeditionsGuardAutoLeave(state, "Defeat")
    saveConfig()
end)
getgenv().AnimeExpeditionsLeaveToggles.PlayerJoin = Tabs.Macro:AddToggle("AutoLeaveOnPlayerJoin", {Title = "Tự động Thoát khi có người vào phòng Solo", Default = appConfig.autoLeaveOnPlayerJoin})
getgenv().AnimeExpeditionsLeaveToggles.PlayerJoin:OnChanged(function(state)
    appConfig.autoLeaveOnPlayerJoin = getgenv().AnimeExpeditionsGuardAutoLeave(state, "PlayerJoin")
    saveConfig()
end)
Tabs.Macro:AddSection("Chia Sẻ Macro / Config")
getgenv().AnimeExpeditionsMacroShare = {
    BaseUrl = "https://animeexpeditionsmarcoshare.netlify.app",
    Format = "AnimeExpeditionsMacroBundle",
    ConfigFormat = "AnimeExpeditionsConfigBundle",
    Version = 1,
}
getgenv().AnimeExpeditionsMacroShare.ValidateActions = function(actions, allowEmpty)
    if type(actions) ~= "table" or (not allowEmpty and #actions == 0) then return false, "Macro không có action." end
    if #actions > 5000 then return false, "Một Macro vượt quá 5.000 action." end
    for _, action in ipairs(actions) do
        if type(action) ~= "table" then return false, "Macro chứa action không hợp lệ." end
    end
    return true
end
getgenv().AnimeExpeditionsMacroShare.ValidateBundle = function(bundle)
    local share = getgenv().AnimeExpeditionsMacroShare
    if type(bundle) ~= "table" or bundle.format ~= share.Format or tonumber(bundle.version) ~= share.Version or type(bundle.macros) ~= "table" then
        return false, "Bundle Macro không đúng định dạng."
    end
    local names, total = {}, 0
    for name, actions in pairs(bundle.macros) do
        if type(name) ~= "string" or name == "" or #name > 180 or name == "__proto__" or name == "constructor" or name == "prototype" then
            return false, "Tên Macro trong bundle không hợp lệ."
        end
        local ok, err = share.ValidateActions(actions, true)
        if not ok then return false, name .. ": " .. err end
        total += #actions
        if total > 50000 then return false, "Bundle vượt quá 50.000 action." end
        table.insert(names, name)
        if #names > 250 then return false, "Bundle vượt quá 250 Macro." end
    end
    if #names == 0 then return false, "Bundle không có Macro." end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
    return true, names, total
end
getgenv().AnimeExpeditionsMacroShare.ValidateConfigBundle = function(bundle)
    local share = getgenv().AnimeExpeditionsMacroShare
    if type(bundle) ~= "table" or bundle.format ~= share.ConfigFormat or tonumber(bundle.version) ~= share.Version or type(bundle.config) ~= "table" then
        return false, "Bundle Config không đúng định dạng."
    end
    local allowed, excluded = {}, {
        Macros = true, WebhookUrl = true,
        challengeActiveTarget = true, challengeSkippedSlots = true, expeditionScrapCraftPending = true,
        expeditionScrapCraftPendingSince = true, LobbyMaintenance = true,
    }
    for _, key in ipairs(lobbyConfigKeys) do if not excluded[key] then allowed[key] = true end end
    for _, key in ipairs(ingameConfigKeys) do if not excluded[key] then allowed[key] = true end end
    local count, ignoredLegacy = 0, false
    for key in pairs(bundle.config) do
        if type(key) ~= "string" then return false, "Config chứa khóa không được hỗ trợ: " .. tostring(key) end
        if key:lower():find("b" .. "ounty", 1, true) then
            ignoredLegacy = true
        else
            if not allowed[key] then return false, "Config chứa khóa không được hỗ trợ: " .. tostring(key) end
            count += 1
        end
    end
    if count == 0 and not ignoredLegacy then return false, "Bundle không có Config." end
    return true, count
end
getgenv().AnimeExpeditionsMacroShare.Request = function(options)
    if type(request) == "function" then
        local ok, response = pcall(request, options)
        if not ok then return nil, tostring(response) end
        local status = tonumber(response and (response.StatusCode or response.Status))
        if status and (status < 200 or status >= 300) then
            local message = "HTTP " .. tostring(status)
            pcall(function()
                local body = HttpService:JSONDecode(response.Body or "")
                if type(body) == "table" and body.error then message = tostring(body.error) end
            end)
            return nil, message
        end
        return response and response.Body
    end
    if options.Method == "GET" then
        local ok, body = pcall(function() return game:HttpGet(options.Url, true) end)
        if ok then return body end
        return nil, tostring(body)
    end
    return nil, "Executor không hỗ trợ HTTP request POST."
end
getgenv().AnimeExpeditionsMacroShare.ShowImportPopup = function(bundle)
    local share = getgenv().AnimeExpeditionsMacroShare
    local valid, names, totalActions = share.ValidateBundle(bundle)
    if not valid then
        Fluent:Notify({Title = "Import thất bại", Content = tostring(names), Duration = 6})
        return
    end

    local old = CoreGui:FindFirstChild("AnimeExpeditionsMacroImport")
    if old then old:Destroy() end
    local gui = Instance.new("ScreenGui")
    gui.Name = "AnimeExpeditionsMacroImport"
    gui.DisplayOrder = 10000
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    if syn and syn.protect_gui then pcall(syn.protect_gui, gui) elseif protectgui then pcall(protectgui, gui) end
    local parented = pcall(function() gui.Parent = CoreGui end)
    if not parented then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

    local shade = Instance.new("TextButton")
    shade.AutoButtonColor = false
    shade.Text = ""
    shade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    shade.BackgroundTransparency = 0.25
    shade.Size = UDim2.fromScale(1, 1)
    shade.Parent = gui
    local panel = Instance.new("Frame")
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.new(0.88, 0, 0.78, 0)
    panel.BackgroundColor3 = Color3.fromRGB(24, 25, 32)
    panel.Parent = shade
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
    local constraint = Instance.new("UISizeConstraint", panel)
    constraint.MinSize = Vector2.new(290, 330)
    constraint.MaxSize = Vector2.new(520, 560)

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(18, 14)
    title.Size = UDim2.new(1, -36, 0, 26)
    title.Font = Enum.Font.GothamBold
    title.Text = localizeText("Import Macro từ link")
    title.TextColor3 = Color3.fromRGB(245, 245, 248)
    title.TextSize = 19
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = panel
    local details = Instance.new("TextLabel")
    details.BackgroundTransparency = 1
    details.Position = UDim2.fromOffset(18, 42)
    details.Size = UDim2.new(1, -36, 0, 22)
    details.Font = Enum.Font.Gotham
    details.Text = tostring(#names) .. " Macro | " .. tostring(totalActions) .. " action | " .. localizeText("Chỉ mục được tick sẽ ghi đè")
    details.TextColor3 = Color3.fromRGB(165, 168, 180)
    details.TextSize = 12
    details.TextXAlignment = Enum.TextXAlignment.Left
    details.Parent = panel

    local selected, rows = {}, {}
    for _, name in ipairs(names) do selected[name] = true end
    local selectAll = Instance.new("TextButton")
    selectAll.AutoButtonColor = false
    selectAll.BackgroundColor3 = Color3.fromRGB(37, 39, 49)
    selectAll.Position = UDim2.fromOffset(18, 70)
    selectAll.Size = UDim2.new(1, -36, 0, 34)
    selectAll.Font = Enum.Font.GothamSemibold
    selectAll.TextColor3 = Color3.fromRGB(220, 222, 230)
    selectAll.TextSize = 13
    Instance.new("UICorner", selectAll).CornerRadius = UDim.new(0, 7)
    selectAll.Parent = panel
    local list = Instance.new("ScrollingFrame")
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.Position = UDim2.fromOffset(18, 112)
    list.Size = UDim2.new(1, -36, 1, -178)
    list.ScrollBarThickness = 4
    list.ScrollBarImageColor3 = Color3.fromRGB(100, 105, 125)
    list.CanvasSize = UDim2.fromOffset(0, 0)
    list.Parent = panel
    local layout = Instance.new("UIListLayout", list)
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    local function renderSelectAll()
        local count = 0
        for _, name in ipairs(names) do if selected[name] then count += 1 end end
        selectAll.Text = (count == #names and "[x] " or "[ ] ") .. localizeText("Chọn tất cả") .. " (" .. tostring(count) .. "/" .. tostring(#names) .. ")"
    end
    for index, name in ipairs(names) do
        local row = Instance.new("TextButton")
        row.AutoButtonColor = false
        row.BackgroundColor3 = Color3.fromRGB(31, 33, 42)
        row.Size = UDim2.new(1, -6, 0, 40)
        row.LayoutOrder = index
        row.Font = Enum.Font.Gotham
        row.Text = "[x]  " .. name .. "  (" .. tostring(#bundle.macros[name]) .. ")"
        row.TextColor3 = Color3.fromRGB(232, 233, 239)
        row.TextSize = 13
        row.TextXAlignment = Enum.TextXAlignment.Left
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)
        local padding = Instance.new("UIPadding", row)
        padding.PaddingLeft = UDim.new(0, 12)
        row.Parent = list
        rows[name] = row
        row.Activated:Connect(function()
            selected[name] = not selected[name]
            row.Text = (selected[name] and "[x]  " or "[ ]  ") .. name .. "  (" .. tostring(#bundle.macros[name]) .. ")"
            renderSelectAll()
        end)
    end
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 4)
    end)
    renderSelectAll()
    selectAll.Activated:Connect(function()
        local enable = false
        for _, name in ipairs(names) do if not selected[name] then enable = true break end end
        for _, name in ipairs(names) do
            selected[name] = enable
            rows[name].Text = (enable and "[x]  " or "[ ]  ") .. name .. "  (" .. tostring(#bundle.macros[name]) .. ")"
        end
        renderSelectAll()
    end)

    local cancel = Instance.new("TextButton")
    cancel.BackgroundColor3 = Color3.fromRGB(46, 48, 59)
    cancel.Position = UDim2.new(0, 18, 1, -54)
    cancel.Size = UDim2.new(0.38, -4, 0, 38)
    cancel.Font = Enum.Font.GothamSemibold
    cancel.Text = localizeText("Hủy")
    cancel.TextColor3 = Color3.fromRGB(225, 226, 232)
    cancel.TextSize = 13
    Instance.new("UICorner", cancel).CornerRadius = UDim.new(0, 7)
    cancel.Parent = panel
    cancel.Activated:Connect(function() gui:Destroy() end)
    local confirm = Instance.new("TextButton")
    confirm.BackgroundColor3 = Color3.fromRGB(86, 118, 255)
    confirm.Position = UDim2.new(0.38, 22, 1, -54)
    confirm.Size = UDim2.new(0.62, -40, 0, 38)
    confirm.Font = Enum.Font.GothamBold
    confirm.Text = localizeText("Import mục đã chọn")
    confirm.TextColor3 = Color3.fromRGB(255, 255, 255)
    confirm.TextSize = 13
    Instance.new("UICorner", confirm).CornerRadius = UDim.new(0, 7)
    confirm.Parent = panel
    confirm.Activated:Connect(function()
        local imported = 0
        for _, name in ipairs(names) do
            if selected[name] then
                appConfig.Macros[name] = bundle.macros[name]
                imported += 1
            end
        end
        if imported == 0 then
            Fluent:Notify({Title = "Import Macro", Content = "Chưa tick Macro nào.", Duration = 4})
            return
        end
        saveConfig()
        gui:Destroy()
        Fluent:Notify({Title = "Import thành công", Content = string.format(localizeText("Đã import %d Macro; mục không tick được giữ nguyên."), imported), Duration = 6})
    end)
end
local ImportExportInput = Tabs.Macro:AddInput("MacroDataString", {
    Title = "Dữ liệu Macro hoặc Link vĩnh viễn",
    Default = "",
    Placeholder = "Dán JSON Macro hoặc link animeexpeditionsmarcoshare...",
    Numeric = false,
    Finished = false
})
Tabs.Configs:AddSection("Chia Sẻ Config")
getgenv().AnimeExpeditionsConfigShareInput = Tabs.Configs:AddInput("ConfigDataString", {
    Title = "Dữ liệu Config hoặc Link vĩnh viễn",
    Default = "",
    Placeholder = "Dán JSON Config hoặc link animeexpeditionsmarcoshare...",
    Numeric = false,
    Finished = false
})
getgenv().AnimeExpeditionsMacroShare.UploadBundle = function(bundle)
    local share = getgenv().AnimeExpeditionsMacroShare
    local isConfig = bundle.format == share.ConfigFormat
    local valid, itemsOrError
    if isConfig then
        valid, itemsOrError = share.ValidateConfigBundle(bundle)
    else
        valid, itemsOrError = share.ValidateBundle(bundle)
    end
    if not valid then
        Fluent:Notify({Title = "Không thể Export", Content = tostring(itemsOrError), Duration = 7})
        return
    end
    local encodedOk, body = pcall(function() return HttpService:JSONEncode(bundle) end)
    if not encodedOk then
        Fluent:Notify({Title = "Không thể Export", Content = "Không thể mã hóa dữ liệu.", Duration = 6})
        return
    end
    if #body > 2097152 then
        Fluent:Notify({Title = "Không thể Export", Content = "Dữ liệu vượt giới hạn 2 MB.", Duration = 6})
        return
    end
    local itemCount = isConfig and itemsOrError or #itemsOrError
    local itemLabel = isConfig and localizeText(" thiết lập") or " Macro"
    Fluent:Notify({Title = "Export Link", Content = string.format(localizeText("Đang upload %d%s..."), itemCount, itemLabel), Duration = 4})
    task.spawn(function()
        local responseBody, requestError = share.Request({
            Url = share.BaseUrl .. "/api/macros",
            Method = "POST",
            Headers = {["Content-Type"] = "application/json", Accept = "application/json"},
            Body = body,
        })
        if not responseBody then
            Fluent:Notify({Title = "Upload thất bại", Content = tostring(requestError), Duration = 7})
            return
        end
        local decodedOk, result = pcall(function() return HttpService:JSONDecode(responseBody) end)
        if not decodedOk or type(result) ~= "table" or result.ok ~= true or type(result.shareUrl) ~= "string" then
            Fluent:Notify({Title = "Upload thất bại", Content = "API trả về dữ liệu không hợp lệ.", Duration = 7})
            return
        end
        if isConfig then
            getgenv().AnimeExpeditionsConfigShareInput:SetValue(result.shareUrl)
        else
            ImportExportInput:SetValue(result.shareUrl)
        end
        if setclipboard then pcall(function() setclipboard(result.shareUrl) end) end
        Fluent:Notify({Title = "Đã tạo Link vĩnh viễn", Content = tostring((isConfig and result.configKeys) or result.macroCount or itemCount) .. itemLabel .. localizeText(". Link đã được copy vào Clipboard."), Duration = 7})
    end)
end
Tabs.Macro:AddButton({
    Title = "Import Macro",
    Description = "Nhận mã JSON cũ, bundle JSON hoặc link Macro vĩnh viễn.",
    Callback = function()
        local dataString = tostring(ImportExportInput.Value or ""):match("^%s*(.-)%s*$")
        if dataString == "" then
            Fluent:Notify({Title = "Lỗi", Content = "Chưa nhập mã JSON hoặc link Macro!", Duration = 5})
            return
        end
        local share = getgenv().AnimeExpeditionsMacroShare
        if dataString:match("^https?://") then
            local id = dataString:match("^https?://animeexpeditionsmarcoshare%.netlify%.app/m/([a-fA-F0-9]+)")
                or dataString:match("^https?://animeexpeditionsmarcoshare%.netlify%.app/api/macros/([a-fA-F0-9]+)")
            if not id or #id ~= 24 then
                Fluent:Notify({Title = "Link không hợp lệ", Content = "Chỉ nhận link từ animeexpeditionsmarcoshare.netlify.app.", Duration = 6})
                return
            end
            Fluent:Notify({Title = "Import Macro", Content = "Đang tải link...", Duration = 3})
            task.spawn(function()
                local body, requestError = share.Request({Url = share.BaseUrl .. "/api/macros/" .. string.lower(id), Method = "GET", Headers = {Accept = "application/json"}})
                if not body then
                    Fluent:Notify({Title = "Tải link thất bại", Content = tostring(requestError), Duration = 7})
                    return
                end
                local decodedOk, decoded = pcall(function() return HttpService:JSONDecode(body) end)
                if not decodedOk then
                    Fluent:Notify({Title = "Import thất bại", Content = "API trả về dữ liệu không hợp lệ.", Duration = 6})
                    return
                end
                share.ShowImportPopup(decoded)
            end)
            return
        end
        local success, decoded = pcall(function() return HttpService:JSONDecode(dataString) end)
        if not success or type(decoded) ~= "table" then
            Fluent:Notify({Title = "Import thất bại", Content = "Mã JSON không hợp lệ.", Duration = 5})
            return
        end
        if decoded.format == share.Format then
            share.ShowImportPopup(decoded)
            return
        end
        if not currentStageKey or currentStageKey == "" or currentStageKey == "Unknown" then
            Fluent:Notify({Title = "Lỗi", Content = "JSON kiểu cũ cần đứng trong Ải để xác định tên Macro.", Duration = 6})
            return
        end
        local actionsOk, actionsError = share.ValidateActions(decoded, false)
        if actionsOk then
            appConfig.Macros[currentStageKey] = decoded
            saveConfig()
            Fluent:Notify({Title = "Import thành công", Content = string.format(localizeText("Đã import JSON cho %s"), currentStageKey), Duration = 5})
        else
            Fluent:Notify({Title = "Import thất bại", Content = tostring(actionsError), Duration = 5})
        end
    end
})
Tabs.Macro:AddButton({
    Title = "Export Link vĩnh viễn (Map hiện tại)",
    Description = "Upload Macro của Map đang chơi và copy link không hết hạn.",
    Callback = function()
        if not currentStageKey or currentStageKey == "" or currentStageKey == "Unknown" then
            Fluent:Notify({Title = "Lỗi", Content = "Phải đứng trong Ải mới Export được!", Duration = 5})
            return
        end
        local macroData = appConfig.Macros[currentStageKey]
        if (not macroData or #macroData == 0) and isfile and readfile then
            local filePath = macrosFolderPath .. "/" .. currentStageKey:gsub("[^%w%-_]", "") .. ".json"
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
        local share = getgenv().AnimeExpeditionsMacroShare
        share.UploadBundle({
            format = share.Format,
            version = share.Version,
            gameId = tostring(game.GameId),
            macros = {[currentStageKey] = macroData},
        })
    end
})
Tabs.Macro:AddButton({
    Title = "Export Link vĩnh viễn (Tất cả Macro)",
    Description = "Upload toàn bộ thư viện Macro và copy link không hết hạn.",
    Callback = function()
        local share = getgenv().AnimeExpeditionsMacroShare
        local macros = {}
        for name, actions in pairs(appConfig.Macros) do
            if type(name) == "string" and type(actions) == "table" and #actions > 0 then macros[name] = actions end
        end
        local bundle = {format = share.Format, version = share.Version, gameId = tostring(game.GameId), macros = macros}
        share.UploadBundle(bundle)
    end
})
Tabs.Configs:AddButton({
    Title = "Export Config thành Link vĩnh viễn",
    Description = "Không gồm Macro, trạng thái chạy tạm thời hoặc Webhook URL.",
    Callback = function()
        local share, config, excluded = getgenv().AnimeExpeditionsMacroShare, {}, {
            WebhookUrl = true,
            challengeActiveTarget = true, challengeSkippedSlots = true, expeditionScrapCraftPending = true,
            expeditionScrapCraftPendingSince = true, LobbyMaintenance = true,
        }
        for _, key in ipairs(lobbyConfigKeys) do if not excluded[key] then config[key] = appConfig[key] end end
        for _, key in ipairs(ingameConfigKeys) do if not excluded[key] then config[key] = appConfig[key] end end
        if type(config.QuestAuto) == "table" then
            local ok, copy = pcall(function() return HttpService:JSONDecode(HttpService:JSONEncode(config.QuestAuto)) end)
            if ok then config.QuestAuto = copy; config.QuestAuto.ActiveTarget = nil end
        end
        share.UploadBundle({format = share.ConfigFormat, version = share.Version, gameId = tostring(game.GameId), config = config})
    end
})
Tabs.Configs:AddButton({
    Title = "Import Config từ Link / JSON",
    Description = "Giữ nguyên Macro và Webhook URL; chạy lại script sau khi import.",
    Callback = function()
        local dataString = tostring(getgenv().AnimeExpeditionsConfigShareInput.Value or ""):match("^%s*(.-)%s*$")
        if dataString == "" then
            Fluent:Notify({Title = "Lỗi", Content = "Chưa nhập JSON hoặc link Config!", Duration = 5})
            return
        end
        local share = getgenv().AnimeExpeditionsMacroShare
        local function applyConfig(bundle)
            local valid, countOrError = share.ValidateConfigBundle(bundle)
            if not valid then
                Fluent:Notify({Title = "Import Config thất bại", Content = tostring(countOrError), Duration = 7})
                return
            end
            for key, value in pairs(bundle.config) do
                if not key:lower():find("b" .. "ounty", 1, true) then appConfig[key] = value end
            end
            appConfig.challengeActiveTarget = nil
            appConfig.challengeSkippedSlots = {ResetKey = "", Slots = {}}
            appConfig.expeditionScrapCraftPending = false
            appConfig.expeditionScrapCraftPendingSince = 0
            appConfig.LobbyMaintenance = {Epoch = 0, Phase = "Idle", Reasons = {}, RequestedAt = 0}
            if type(appConfig.QuestAuto) == "table" then appConfig.QuestAuto.ActiveTarget = nil end
            saveConfig()
            Fluent:Notify({Title = "Import Config thành công", Content = string.format(localizeText("Đã lưu %d thiết lập. Hãy chạy lại script để cập nhật toàn bộ UI."), countOrError), Duration = 8})
        end
        if dataString:match("^https?://") then
            local id = dataString:match("^https?://animeexpeditionsmarcoshare%.netlify%.app/m/([a-fA-F0-9]+)")
                or dataString:match("^https?://animeexpeditionsmarcoshare%.netlify%.app/api/macros/([a-fA-F0-9]+)")
            if not id or #id ~= 24 then
                Fluent:Notify({Title = "Link không hợp lệ", Content = "Chỉ nhận link từ animeexpeditionsmarcoshare.netlify.app.", Duration = 6})
                return
            end
            Fluent:Notify({Title = "Import Config", Content = "Đang tải link...", Duration = 3})
            task.spawn(function()
                local body, requestError = share.Request({Url = share.BaseUrl .. "/api/macros/" .. string.lower(id), Method = "GET", Headers = {Accept = "application/json"}})
                if not body then
                    Fluent:Notify({Title = "Tải link thất bại", Content = tostring(requestError), Duration = 7})
                    return
                end
                local ok, decoded = pcall(function() return HttpService:JSONDecode(body) end)
                if not ok then
                    Fluent:Notify({Title = "Import Config thất bại", Content = "API trả về dữ liệu không hợp lệ.", Duration = 6})
                    return
                end
                applyConfig(decoded)
            end)
            return
        end
        local ok, decoded = pcall(function() return HttpService:JSONDecode(dataString) end)
        if not ok then
            Fluent:Notify({Title = "Import Config thất bại", Content = "Mã JSON không hợp lệ.", Duration = 6})
            return
        end
        applyConfig(decoded)
    end
})
task.wait()
Tabs.Settings:AddToggle("HidePlayerNames", {Title = "Hide Player Names", Default = appConfig.hidePlayerNames}):OnChanged(function(v)
    appConfig.hidePlayerNames = v
    saveConfig()
end)
Tabs.Settings:AddToggle("AntiAFK", {Title = "Anti AFK", Default = appConfig.AntiAFK}):OnChanged(function(v)
    appConfig.AntiAFK = v
    saveConfig()
end)
Tabs.Settings:AddToggle("AutoVoteStartExpedition", {
    Title = "Auto Vote Start (Chỉ Expedition)",
    Description = "Vào Expedition sẽ tạm bật; khi rời sẽ khôi phục trạng thái Auto Vote Start trước đó.",
    Default = appConfig.expeditionAutoVoteStart,
}):OnChanged(function(value)
    appConfig.expeditionAutoVoteStart = value
    saveConfig()
end)
Tabs.Settings:AddSection("Auto Leave")
getgenv().AnimeExpeditionsLeaveToggles.MatchTimer = Tabs.Settings:AddToggle("AutoLeaveAfterMinutes", {
    Title = "Tự động thoát sau X phút",
    Description = "Yêu cầu bật Auto Join Map. Tính theo thời gian trận hiện tại.",
    Default = appConfig.autoLeaveAfterMinutes,
})
getgenv().AnimeExpeditionsLeaveToggles.MatchTimer:OnChanged(function(value)
    appConfig.autoLeaveAfterMinutes = getgenv().AnimeExpeditionsGuardAutoLeave(value, "MatchTimer")
    saveConfig()
end)
Tabs.Settings:AddInput("AutoLeaveAfterMinutesValue", {
    Title = "Thời gian Auto Leave (phút)",
    Default = tostring(appConfig.autoLeaveAfterMinutesValue or 30),
    Placeholder = "Ví dụ: 30",
    Numeric = true,
    Finished = true,
    Callback = function(value)
        appConfig.autoLeaveAfterMinutesValue = math.clamp(math.floor(tonumber(value) or 30), 1, 1440)
        saveConfig()
    end,
})
local function applyFPSCap(value)
    local cap = math.clamp(math.floor(tonumber(value) or 60), 1, 360)
    appConfig.fpsCap = cap
    if type(setfpscap) == "function" then pcall(setfpscap, cap) end
    return cap
end
applyFPSCap(appConfig.fpsCap)
Tabs.Settings:AddInput("FPSCap", {
    Title = "Giới hạn FPS",
    Default = tostring(appConfig.fpsCap),
    Placeholder = "60",
    Numeric = true,
    Finished = true,
    Callback = function(value)
        applyFPSCap(value)
        saveConfig()
    end,
})
local fixLagState = {
    lighting = nil,
    parts = {},
    decals = {}
}
local function SetFixLagEnabled(enabled)
    local lighting = game:GetService("Lighting")
    if enabled then
        for _, settingName in ipairs({"OwnUnitVFXEnabled", "AbilityVFXEnabled", "UnitAuraEnabled", "TraitAuraEnabled", "BuffIndicatorsEnabled", "DamageIndicatorsEnabled"}) do
            local ok, value = pcall(Actions.GetSettingValue, settingName)
            if ok and value == true then pcall(Actions.ChangeSetting, settingName, false) end
        end
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
    getgenv().AE_AntiAfkInputUntil = tick() + 0.25
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
        return true
    end
    return false
end
game:GetService("Players").LocalPlayer.Idled:Connect(function()
    if appConfig.AntiAFK then
        PulseAntiAFKInput()
    end
end)
task.spawn(function()
    while expeditionScriptIsCurrent() and task.wait(3) do
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
local function safeParentScreenGui(gui)
    if not gui then return false end
    if type(gethui) == "function" then
        local ok, parent = pcall(gethui)
        if ok and parent and pcall(function() gui.Parent = parent end) then return true end
    end
    if pcall(function() gui.Parent = CoreGui end) then return true end
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
    return playerGui ~= nil and pcall(function() gui.Parent = playerGui end)
end
local function setupBlackScreen()
local blackScreenGui = Instance.new("ScreenGui")
blackScreenGui.Name = "BlackScreenGUI"
blackScreenGui.ResetOnSpawn = false
blackScreenGui.IgnoreGuiInset = true
blackScreenGui.DisplayOrder = -10
local blackFrame = Instance.new("Frame", blackScreenGui)
blackFrame.Size = UDim2.new(1, 0, 1, 0)
blackFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
blackFrame.BorderSizePixel = 0
blackFrame.Visible = false
local blackPanel = Instance.new("Frame", blackFrame)
blackPanel.AnchorPoint = Vector2.new(0.5, 0.5)
blackPanel.Position = UDim2.fromScale(0.5, 0.5)
blackPanel.Size = UDim2.fromOffset(1040, 720)
blackPanel.BackgroundTransparency = 1
local blackPanelScale = Instance.new("UIScale", blackPanel)
local function updateBlackScreenScale()
    local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
    blackPanelScale.Scale = math.min(1, math.max(0.5, math.min((viewport.X - 32) / 1040, (viewport.Y - 32) / 720)))
end
updateBlackScreenScale()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateBlackScreenScale) end
local blackTitle = Instance.new("TextLabel", blackPanel)
blackTitle.AnchorPoint = Vector2.new(0.5, 0)
blackTitle.Position = UDim2.new(0.5, 0, 0, 24)
blackTitle.Size = UDim2.fromOffset(400, 30)
blackTitle.BackgroundTransparency = 1
blackTitle.Text = "ANIME EXPEDITIONS"
blackTitle.TextColor3 = Color3.fromRGB(239, 241, 248)
blackTitle.TextSize = 22
blackTitle.Font = Enum.Font.GothamBold
blackTitle.TextXAlignment = Enum.TextXAlignment.Center
local blackFPS = Instance.new("TextLabel", blackPanel)
blackFPS.AnchorPoint = Vector2.new(0.5, 0)
blackFPS.Position = UDim2.new(0.5, 0, 0, 58)
blackFPS.Size = UDim2.fromOffset(180, 20)
blackFPS.BackgroundTransparency = 1
blackFPS.Text = "FPS: 0"
blackFPS.TextColor3 = Color3.fromRGB(139, 119, 238)
blackFPS.TextSize = 11
blackFPS.Font = Enum.Font.GothamBold
local blackFPSFrames = 0
local blackFPSStartedAt = tick()
game:GetService("RunService").RenderStepped:Connect(function()
    blackFPSFrames += 1
    local now = tick()
    local elapsed = now - blackFPSStartedAt
    if elapsed >= 0.5 then
        blackFPS.Text = "FPS: " .. tostring(math.floor(blackFPSFrames / elapsed + 0.5))
        blackFPSFrames = 0
        blackFPSStartedAt = now
    end
end)
local blackLive = Instance.new("TextLabel", blackPanel)
blackLive.AnchorPoint = Vector2.new(0.5, 0)
blackLive.Position = UDim2.new(0.5, 0, 0, 210)
blackLive.Size = UDim2.fromOffset(320, 28)
blackLive.BackgroundTransparency = 1
blackLive.Text = localizeText("ĐANG TREO") .. "  /  0 " .. localizeText("TRẬN")
blackLive.TextColor3 = Color3.fromRGB(139, 119, 238)
blackLive.TextSize = 12
blackLive.Font = Enum.Font.GothamBold
local blackLiveCorner = Instance.new("UICorner", blackLive)
blackLiveCorner.CornerRadius = UDim.new(1, 0)
local blackTimer = Instance.new("TextLabel", blackPanel)
blackTimer.AnchorPoint = Vector2.new(0.5, 0)
blackTimer.Position = UDim2.new(0.5, 0, 0, 104)
blackTimer.Size = UDim2.new(1, 0, 0, 76)
blackTimer.BackgroundTransparency = 1
blackTimer.Text = "00:00:00"
blackTimer.TextColor3 = Color3.fromRGB(247, 248, 252)
blackTimer.TextSize = 62
blackTimer.Font = Enum.Font.GothamBold
local blackTimerCaption = Instance.new("TextLabel", blackPanel)
blackTimerCaption.AnchorPoint = Vector2.new(0.5, 0)
blackTimerCaption.Position = UDim2.new(0.5, 0, 0, 177)
blackTimerCaption.Size = UDim2.fromOffset(220, 20)
blackTimerCaption.BackgroundTransparency = 1
blackTimerCaption.Text = localizeText("THỜI GIAN TREO")
blackTimerCaption.TextColor3 = Color3.fromRGB(106, 113, 132)
blackTimerCaption.TextSize = 11
blackTimerCaption.Font = Enum.Font.GothamBold
blackTimerCaption.Visible = false
local blackMatchCard = Instance.new("Frame", blackPanel)
blackMatchCard.AnchorPoint = Vector2.new(0.5, 0)
blackMatchCard.Position = UDim2.new(0.5, 0, 0, 215)
blackMatchCard.Size = UDim2.fromOffset(226, 72)
blackMatchCard.BackgroundColor3 = Color3.fromRGB(13, 17, 26)
blackMatchCard.BorderSizePixel = 0
blackMatchCard.Visible = false
local blackMatchCorner = Instance.new("UICorner", blackMatchCard)
blackMatchCorner.CornerRadius = UDim.new(0, 16)
local blackMatchStroke = Instance.new("UIStroke", blackMatchCard)
blackMatchStroke.Color = Color3.fromRGB(45, 50, 67)
blackMatchStroke.Transparency = 0.25
local blackMatchValue = Instance.new("TextLabel", blackMatchCard)
blackMatchValue.Position = UDim2.fromOffset(0, 5)
blackMatchValue.Size = UDim2.new(1, 0, 0, 38)
blackMatchValue.BackgroundTransparency = 1
blackMatchValue.Text = "0"
blackMatchValue.TextColor3 = Color3.fromRGB(177, 157, 255)
blackMatchValue.TextSize = 30
blackMatchValue.Font = Enum.Font.GothamBold
local blackMatchCaption = Instance.new("TextLabel", blackMatchCard)
blackMatchCaption.Position = UDim2.fromOffset(0, 43)
blackMatchCaption.Size = UDim2.new(1, 0, 0, 18)
blackMatchCaption.BackgroundTransparency = 1
blackMatchCaption.Text = localizeText("SỐ TRẬN ĐÃ ĐÁNH")
blackMatchCaption.TextColor3 = Color3.fromRGB(107, 114, 132)
blackMatchCaption.TextSize = 11
blackMatchCaption.Font = Enum.Font.GothamBold
local blackRewardsTitle = Instance.new("TextLabel", blackPanel)
blackRewardsTitle.AnchorPoint = Vector2.new(0.5, 0)
blackRewardsTitle.Position = UDim2.new(0.5, 0, 0, 292)
blackRewardsTitle.Size = UDim2.new(1, 0, 0, 22)
blackRewardsTitle.BackgroundTransparency = 1
blackRewardsTitle.Text = localizeText("PHẦN THƯỞNG ĐÃ NHẬN")
blackRewardsTitle.TextColor3 = Color3.fromRGB(225, 228, 238)
blackRewardsTitle.TextSize = 14
blackRewardsTitle.Font = Enum.Font.GothamBold
blackRewardsTitle.TextXAlignment = Enum.TextXAlignment.Center
local blackDivider = Instance.new("Frame", blackPanel)
blackDivider.Position = UDim2.new(0.1, 0, 0, 272)
blackDivider.Size = UDim2.new(0.8, 0, 0, 1)
blackDivider.BackgroundColor3 = Color3.fromRGB(29, 33, 42)
blackDivider.BorderSizePixel = 0
local blackRewards = Instance.new("ScrollingFrame", blackPanel)
blackRewards.Position = UDim2.fromOffset(0, 355)
blackRewards.Size = UDim2.new(1, 0, 0, 355)
blackRewards.BackgroundTransparency = 1
blackRewards.BorderSizePixel = 0
blackRewards.ScrollBarThickness = 3
blackRewards.ScrollBarImageColor3 = Color3.fromRGB(112, 91, 220)
blackRewards.AutomaticCanvasSize = Enum.AutomaticSize.Y
blackRewards.CanvasSize = UDim2.new()
blackRewards.ScrollingDirection = Enum.ScrollingDirection.Y
local blackRewardsLayout = Instance.new("UIListLayout", blackRewards)
blackRewardsLayout.FillDirection = Enum.FillDirection.Vertical
blackRewardsLayout.Padding = UDim.new(0, 6)
blackRewardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
local blackRewardsPadding = Instance.new("UIPadding", blackRewards)
blackRewardsPadding.PaddingLeft = UDim.new(0, 4)
blackRewardsPadding.PaddingRight = UDim.new(0, 8)
blackRewardsPadding.PaddingBottom = UDim.new(0, 8)
local blackEmpty = Instance.new("TextLabel", blackRewards)
blackEmpty.Name = "EmptyState"
blackEmpty.Size = UDim2.new(1, 0, 1, -8)
blackEmpty.BackgroundTransparency = 1
blackEmpty.Text = localizeText("Chưa nhận được phần thưởng nào từ lúc script bắt đầu")
blackEmpty.TextColor3 = Color3.fromRGB(91, 98, 116)
blackEmpty.TextSize = 14
blackEmpty.Font = Enum.Font.GothamMedium
local function addBlackHeader(text, position, size, alignment)
    local header = Instance.new("TextLabel", blackPanel)
    header.Position = position
    header.Size = size
    header.BackgroundTransparency = 1
    header.Text = text
    header.TextColor3 = Color3.fromRGB(91, 98, 116)
    header.TextSize = 9
    header.Font = Enum.Font.GothamBold
    header.TextXAlignment = alignment or Enum.TextXAlignment.Left
    return header
end
addBlackHeader("ICON", UDim2.fromOffset(20, 329), UDim2.fromOffset(105, 18), Enum.TextXAlignment.Center)
addBlackHeader(localizeText("LOẠI"), UDim2.fromOffset(145, 329), UDim2.fromOffset(110, 18))
addBlackHeader(localizeText("TÊN PHẦN THƯỞNG"), UDim2.fromOffset(280, 329), UDim2.fromOffset(400, 18))
addBlackHeader(localizeText("SỐ LƯỢNG"), UDim2.new(1, -135, 0, 329), UDim2.fromOffset(115, 18), Enum.TextXAlignment.Right)
local blackItemInfo = require(ReplicatedStorage.Shared.Information.Items)
local blackItemMeta = blackItemInfo.ItemData or blackItemInfo.Items or blackItemInfo
local blackRarityColors = {
    Rare = Color3.fromRGB(91, 160, 255), Epic = Color3.fromRGB(177, 103, 255),
    Legendary = Color3.fromRGB(255, 180, 73), Mythic = Color3.fromRGB(255, 83, 135),
    Secret = Color3.fromRGB(105, 238, 207),
}
local blackScreenItemSnapshot
local blackTooltip = Instance.new("Frame", blackFrame)
blackTooltip.Name = "RewardTooltip"
blackTooltip.Size = UDim2.fromOffset(400, 230)
blackTooltip.BackgroundColor3 = Color3.fromRGB(9, 10, 14)
blackTooltip.BorderSizePixel = 0
blackTooltip.Visible = false
blackTooltip.ZIndex = 30
local blackTooltipCorner = Instance.new("UICorner", blackTooltip)
blackTooltipCorner.CornerRadius = UDim.new(0, 14)
local blackTooltipStroke = Instance.new("UIStroke", blackTooltip)
blackTooltipStroke.Thickness = 3
blackTooltipStroke.Color = Color3.fromRGB(255, 190, 54)
local blackTooltipScale = Instance.new("UIScale", blackTooltip)
local blackTooltipIcon = Instance.new("ImageLabel", blackTooltip)
blackTooltipIcon.Position = UDim2.new(1, -132, 0, 54)
blackTooltipIcon.Size = UDim2.fromOffset(108, 108)
blackTooltipIcon.BackgroundTransparency = 1
blackTooltipIcon.ScaleType = Enum.ScaleType.Fit
blackTooltipIcon.ZIndex = 31
local blackTooltipTitle = Instance.new("TextLabel", blackTooltip)
blackTooltipTitle.Position = UDim2.fromOffset(18, 14)
blackTooltipTitle.Size = UDim2.new(1, -36, 0, 34)
blackTooltipTitle.BackgroundTransparency = 1
blackTooltipTitle.TextColor3 = Color3.fromRGB(247, 247, 250)
blackTooltipTitle.TextSize = 23
blackTooltipTitle.Font = Enum.Font.GothamBold
blackTooltipTitle.TextXAlignment = Enum.TextXAlignment.Left
blackTooltipTitle.TextTruncate = Enum.TextTruncate.AtEnd
blackTooltipTitle.ZIndex = 31
local blackTooltipType = Instance.new("TextLabel", blackTooltip)
blackTooltipType.Position = UDim2.fromOffset(18, 49)
blackTooltipType.Size = UDim2.new(1, -168, 0, 25)
blackTooltipType.BackgroundTransparency = 1
blackTooltipType.TextColor3 = Color3.fromRGB(255, 194, 42)
blackTooltipType.TextSize = 17
blackTooltipType.Font = Enum.Font.GothamBold
blackTooltipType.TextXAlignment = Enum.TextXAlignment.Left
blackTooltipType.ZIndex = 31
local blackTooltipDescription = Instance.new("TextLabel", blackTooltip)
blackTooltipDescription.Position = UDim2.fromOffset(18, 82)
blackTooltipDescription.Size = UDim2.new(1, -168, 0, 80)
blackTooltipDescription.BackgroundTransparency = 1
blackTooltipDescription.TextColor3 = Color3.fromRGB(205, 207, 215)
blackTooltipDescription.TextSize = 14
blackTooltipDescription.Font = Enum.Font.GothamMedium
blackTooltipDescription.TextWrapped = true
blackTooltipDescription.TextXAlignment = Enum.TextXAlignment.Left
blackTooltipDescription.TextYAlignment = Enum.TextYAlignment.Top
blackTooltipDescription.ZIndex = 31
local blackTooltipAmount = Instance.new("TextLabel", blackTooltip)
blackTooltipAmount.Position = UDim2.fromOffset(18, 180)
blackTooltipAmount.Size = UDim2.new(1, -36, 0, 34)
blackTooltipAmount.BackgroundColor3 = Color3.fromRGB(19, 20, 27)
blackTooltipAmount.TextColor3 = Color3.fromRGB(242, 243, 248)
blackTooltipAmount.TextSize = 15
blackTooltipAmount.Font = Enum.Font.GothamBold
blackTooltipAmount.ZIndex = 31
local blackTooltipAmountCorner = Instance.new("UICorner", blackTooltipAmount)
blackTooltipAmountCorner.CornerRadius = UDim.new(0, 8)
local blackScreenCloseBtn = Instance.new("TextButton", blackFrame)
blackScreenCloseBtn.Name = "CloseBlackScreenBtn"
blackScreenCloseBtn.AnchorPoint = Vector2.new(1, 0)
local blackScreenTopInset = (select(1, game:GetService("GuiService"):GetGuiInset())).Y
blackScreenCloseBtn.Position = UDim2.new(1, -24, 0, blackScreenTopInset + 24)
blackScreenCloseBtn.Size = UDim2.fromOffset(64, 64)
blackScreenCloseBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
blackScreenCloseBtn.Text = "X"
blackScreenCloseBtn.TextColor3 = Color3.fromRGB(235, 237, 244)
blackScreenCloseBtn.TextSize = 24
blackScreenCloseBtn.Font = Enum.Font.GothamBold
blackScreenCloseBtn.ZIndex = 40
local blackScreenCloseCorner = Instance.new("UICorner", blackScreenCloseBtn)
blackScreenCloseCorner.CornerRadius = UDim.new(1, 0)
local blackScreenCloseStroke = Instance.new("UIStroke", blackScreenCloseBtn)
blackScreenCloseStroke.Color = Color3.fromRGB(62, 62, 68)
blackScreenCloseStroke.Thickness = 1
local blackTooltipToken = 0
local function hideBlackTooltip()
    blackTooltipToken += 1
    local token = blackTooltipToken
    game:GetService("TweenService"):Create(blackTooltipScale, TweenInfo.new(0.12), {Scale = 0.94}):Play()
    task.delay(0.12, function()
        if token == blackTooltipToken then blackTooltip.Visible = false end
    end)
end
local function showBlackTooltip(asset, amount)
    blackTooltipToken += 1
    local meta = blackItemMeta[asset] or {}
    local rarity = tostring(meta.Rarity or "Item")
    local accent = blackRarityColors[rarity] or Color3.fromRGB(255, 190, 54)
    blackTooltipTitle.Text = tostring(meta.DisplayName or asset)
    blackTooltipType.Text = tostring(meta.DisplaySubType or meta.SubType or meta.Type or rarity)
    blackTooltipDescription.Text = tostring(meta.Description or localizeText("Vật phẩm nhận được trong quá trình farm."))
    blackTooltipIcon.Image = tostring(meta.Icon or "")
    blackTooltipStroke.Color = accent
    blackTooltipType.TextColor3 = accent
    local owned = blackScreenItemSnapshot()[asset] or 0
    blackTooltipAmount.Text = "+" .. tostring(math.floor(amount)) .. " " .. localizeText("nhận được") .. "   /   " .. tostring(math.floor(owned)) .. " " .. localizeText("đang có")
    local mouse = game:GetService("UserInputService"):GetMouseLocation()
    local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
    local x = math.clamp(mouse.X + 18, 12, viewport.X - 412)
    local y = math.clamp(mouse.Y - 115, 12, viewport.Y - 242)
    blackTooltip.Position = UDim2.fromOffset(x, y)
    blackTooltipScale.Scale = 0.94
    blackTooltip.Visible = true
    game:GetService("TweenService"):Create(blackTooltipScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
end
blackScreenItemSnapshot = function()
    local ok, playerData = pcall(function() return Fusion.peek(Dependencies.PlayerData) end)
    if not ok or type(playerData) ~= "table" then return {} end
    local snapshot = {}
    for key, value in pairs(playerData.ItemData or {}) do
        local data = Fusion.peek(value)
        snapshot[tostring(key)] = type(data) == "table" and tonumber(Fusion.peek(data.Amount)) or tonumber(data) or 0
    end
    return snapshot
end
local function blackScreenUnitSnapshot()
    local ok, playerData = pcall(function() return Fusion.peek(Dependencies.PlayerData) end)
    if not ok or type(playerData) ~= "table" then return {} end
    local snapshot = {}
    for id, value in pairs(playerData.UnitData or {}) do
        local data = Fusion.peek(value)
        if type(data) == "table" then
            local asset = Fusion.peek(data.Asset)
            if asset then
                snapshot[tostring(id)] = {
                    asset = tostring(asset),
                    shiny = Fusion.peek(data.Shiny) == true,
                }
            end
        end
    end
    return snapshot
end
local function blackScreenEquipmentSnapshot()
    local ok, playerData = pcall(function() return Fusion.peek(Dependencies.PlayerData) end)
    if not ok or type(playerData) ~= "table" then return {} end
    local snapshot = {}
    for id, value in pairs(playerData.EquipmentData or {}) do
        local data = Fusion.peek(value)
        if type(data) == "table" then
            local asset = Fusion.peek(data.Asset)
            if asset then snapshot[tostring(id)] = tostring(asset) end
        end
    end
    return snapshot
end
local blackLastItems = blackScreenItemSnapshot()
local blackLastUnits = blackScreenUnitSnapshot()
local blackLastEquipment = blackScreenEquipmentSnapshot()
local blackReceivedRewards = {}
local blackRewardOrder = 0
local function addBlackReceivedReward(rewardType, asset, amount, shiny)
    if not asset or not amount or amount <= 0 then return end
    local key = rewardType .. ":" .. asset
    if rewardType == "Unit" then key = key .. (shiny and ":Shiny" or ":Normal") end
    local reward = blackReceivedRewards[key]
    if reward then
        reward.amount += amount
        return
    end
    blackRewardOrder += 1
    blackReceivedRewards[key] = {
        type = rewardType,
        asset = asset,
        amount = amount,
        shiny = shiny == true,
        order = blackRewardOrder,
    }
end
local function getBlackMatchesPlayed()
    local stateInfo = getGameStates()
    return getSessionMatchesPlayed() or (stateInfo and stateInfo.SessionMatchesPlayed) or 0
end
local blackMatchesPlayed = getBlackMatchesPlayed()
local function getBlackRewardMeta(asset)
    local ok, meta = pcall(function() return Fusion.peek(Dependencies.Information.Assets[asset]) end)
    if ok and type(meta) == "table" then return meta end
    return blackItemMeta[asset] or {}
end
local function mountBlackUnitAvatar(holder, asset, shiny)
    task.spawn(function()
        local sourceModel
        local loadedAssets = game.Players.LocalPlayer.PlayerGui:FindFirstChild("_loadedAssets")
        local folder = loadedAssets and loadedAssets:FindFirstChild(asset)
        if folder then
            sourceModel = shiny and folder:FindFirstChild("Shiny") or folder:FindFirstChild("Model")
            sourceModel = sourceModel or folder:FindFirstChildWhichIsA("Model")
        end
        if not sourceModel then
            pcall(function() sourceModel = Actions.GetAssetModel(asset, {Shiny = shiny}) end)
        end
        if not holder.Parent or typeof(sourceModel) ~= "Instance" or not sourceModel:IsA("Model") then return end
        local viewport = Instance.new("ViewportFrame", holder)
        viewport.Size = UDim2.fromScale(1, 1)
        viewport.BackgroundTransparency = 1
        viewport.Ambient = Color3.fromRGB(255, 255, 255)
        viewport.LightColor = Color3.fromRGB(255, 255, 255)
        viewport.LightDirection = Vector3.new(-1, -1, -1)
        local camera = Instance.new("Camera", viewport)
        camera.FieldOfView = 30
        viewport.CurrentCamera = camera
        local world = Instance.new("WorldModel", viewport)
        local model = sourceModel:Clone()
        for _, descendant in ipairs(model:GetDescendants()) do
            if descendant:IsA("BasePart") then
                descendant.Anchored = true
                descendant.CanCollide = false
                descendant.CanTouch = false
                descendant.CanQuery = false
            end
        end
        model:PivotTo(CFrame.identity)
        model.Parent = world
        local root = model:FindFirstChild("HumanoidRootPart", true)
        local head = model:FindFirstChild("Head", true)
        if root and root:IsA("BasePart") then
            local target = head and head:IsA("BasePart") and head.Position + Vector3.new(0, -0.35, 0) or root.Position + Vector3.new(0, 1.5, 0)
            camera.CFrame = CFrame.lookAt(target + Vector3.new(0, 0, -3.6), target)
        end
    end)
end
local blackTypeNames = {Item = localizeText("VẬT PHẨM"), Unit = "UNIT", Equipment = localizeText("VŨ KHÍ")}
local function addBlackRewardCard(reward)
    local meta = getBlackRewardMeta(reward.asset)
    local rarity = tostring(Fusion.peek(meta.Rarity) or "Rare")
    local accent = blackRarityColors[rarity] or Color3.fromRGB(91, 160, 255)
    local card = Instance.new("Frame", blackRewards)
    card.Name = "RewardCard"
    card.LayoutOrder = reward.order
    card.Size = UDim2.new(1, -4, 0, 61)
    card.BackgroundColor3 = Color3.fromRGB(9, 11, 17)
    card.BorderSizePixel = 0
    local cardCorner = Instance.new("UICorner", card)
    cardCorner.CornerRadius = UDim.new(0, 12)
    local cardStroke = Instance.new("UIStroke", card)
    cardStroke.Color = accent
    cardStroke.Transparency = 0.62
    local iconBackground = Instance.new("Frame", card)
    iconBackground.Position = UDim2.fromOffset(18, 6)
    iconBackground.Size = UDim2.fromOffset(49, 49)
    iconBackground.BackgroundColor3 = Color3.fromRGB(17, 19, 27)
    iconBackground.BorderSizePixel = 0
    local iconCorner = Instance.new("UICorner", iconBackground)
    iconCorner.CornerRadius = UDim.new(0, 10)
    if reward.type == "Unit" then
        mountBlackUnitAvatar(iconBackground, reward.asset, reward.shiny)
    else
        local icon = Instance.new("ImageLabel", iconBackground)
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
        icon.Position = UDim2.fromScale(0.5, 0.5)
        icon.Size = UDim2.fromOffset(39, 39)
        icon.BackgroundTransparency = 1
        icon.Image = tostring(Fusion.peek(meta.Icon) or Fusion.peek(meta.Image) or "")
        icon.ScaleType = Enum.ScaleType.Fit
    end
    local typeBadge = Instance.new("TextLabel", card)
    typeBadge.Position = UDim2.fromOffset(92, 18)
    typeBadge.Size = UDim2.fromOffset(122, 26)
    typeBadge.BackgroundColor3 = accent
    typeBadge.BackgroundTransparency = 0.84
    typeBadge.Text = blackTypeNames[reward.type] or reward.type
    typeBadge.TextColor3 = accent
    typeBadge.TextSize = 9
    typeBadge.Font = Enum.Font.GothamBold
    local badgeCorner = Instance.new("UICorner", typeBadge)
    badgeCorner.CornerRadius = UDim.new(1, 0)
    local itemName = Instance.new("TextLabel", card)
    itemName.Position = UDim2.fromOffset(240, 0)
    itemName.Size = UDim2.new(1, -390, 1, 0)
    itemName.BackgroundTransparency = 1
    itemName.Text = tostring(Fusion.peek(meta.DisplayName) or reward.asset) .. (reward.shiny and " (Shiny)" or "")
    itemName.TextColor3 = Color3.fromRGB(216, 220, 231)
    itemName.TextSize = 13
    itemName.Font = Enum.Font.GothamMedium
    itemName.TextXAlignment = Enum.TextXAlignment.Left
    itemName.TextTruncate = Enum.TextTruncate.AtEnd
    local itemAmount = Instance.new("TextLabel", card)
    itemAmount.Position = UDim2.new(1, -130, 0, 0)
    itemAmount.Size = UDim2.fromOffset(110, 61)
    itemAmount.BackgroundTransparency = 1
    itemAmount.Text = "x" .. tostring(math.floor(reward.amount))
    itemAmount.TextColor3 = Color3.fromRGB(199, 177, 255)
    itemAmount.TextSize = 19
    itemAmount.Font = Enum.Font.GothamBold
    itemAmount.TextXAlignment = Enum.TextXAlignment.Right
    if reward.type == "Item" then
        card.Active = true
        card.MouseEnter:Connect(function() showBlackTooltip(reward.asset, reward.amount) end)
        card.MouseLeave:Connect(hideBlackTooltip)
        card.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch then
                if blackTooltip.Visible then hideBlackTooltip() else showBlackTooltip(reward.asset, reward.amount) end
            end
        end)
    end
end
local function refreshBlackRewards()
    for _, child in ipairs(blackRewards:GetChildren()) do
        if child.Name == "RewardCard" then child:Destroy() end
    end
    local rewards = {}
    for _, reward in pairs(blackReceivedRewards) do
        if reward.amount > 0 then table.insert(rewards, reward) end
    end
    table.sort(rewards, function(left, right) return left.order < right.order end)
    blackEmpty.Visible = #rewards == 0
    for _, reward in ipairs(rewards) do addBlackRewardCard(reward) end
end
if not safeParentScreenGui(blackScreenGui) then
    blackScreenGui:Destroy()
    return
end
local lastBlackScreenInputAt = tick()
blackScreenCloseBtn.Activated:Connect(function()
    lastBlackScreenInputAt = tick()
    blackFrame.Visible = false
end)
game:GetService("UserInputService").InputBegan:Connect(function(input)
    local inputType = input.UserInputType
    if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.MouseButton2
        or inputType == Enum.UserInputType.MouseButton3 or inputType == Enum.UserInputType.Touch then
        if tick() >= (getgenv().AE_AntiAfkInputUntil or 0) then
            lastBlackScreenInputAt = tick()
        end
    end
end)
task.spawn(function()
    while expeditionScriptIsCurrent() and task.wait(1) do
        if not blackFrame.Visible and tick() - lastBlackScreenInputAt >= 120 then
            blackFrame.Visible = true
        end
    end
end)
task.spawn(function()
    while expeditionScriptIsCurrent() and task.wait(1) do
        local elapsed = math.max(0, math.floor(tick() - _initStartTime))
        blackTimer.Text = string.format("%02d:%02d:%02d", math.floor(elapsed / 3600), math.floor(elapsed % 3600 / 60), elapsed % 60)
        local currentItems = blackScreenItemSnapshot()
        local currentUnits = blackScreenUnitSnapshot()
        local currentEquipment = blackScreenEquipmentSnapshot()
        local rewardsChanged = false
        for asset, amount in pairs(currentItems) do
            local gained = amount - (blackLastItems[asset] or 0)
            if gained > 0 then
                addBlackReceivedReward("Item", asset, gained)
                rewardsChanged = true
            end
        end
        for id, unit in pairs(currentUnits) do
            if not blackLastUnits[id] then
                addBlackReceivedReward("Unit", unit.asset, 1, unit.shiny)
                rewardsChanged = true
            end
        end
        for id, asset in pairs(currentEquipment) do
            if not blackLastEquipment[id] then
                addBlackReceivedReward("Equipment", asset, 1)
                rewardsChanged = true
            end
        end
        blackLastItems = currentItems
        blackLastUnits = currentUnits
        blackLastEquipment = currentEquipment
        if rewardsChanged then refreshBlackRewards() end
        blackMatchesPlayed = getBlackMatchesPlayed()
        blackMatchValue.Text = tostring(blackMatchesPlayed)
        blackLive.Text = localizeText("ĐANG TREO") .. "  /  " .. tostring(blackMatchesPlayed) .. " " .. localizeText("TRẬN")
    end
end)
end
do
    local ok, err = pcall(setupBlackScreen)
    if not ok then warn("[BLACK SCREEN] Disabled because setup failed: " .. tostring(err)) end
end
do
local MobileGui = Instance.new("ScreenGui")
MobileGui.Name = "MobileToggleGui"
MobileGui.ResetOnSpawn = false
MobileGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
MobileGui.DisplayOrder = 100
local ToggleBtn = Instance.new("ImageButton", MobileGui)
ToggleBtn.Size = UDim2.new(0, 45, 0, 45)
ToggleBtn.AnchorPoint = Vector2.new(1, 0.5)
ToggleBtn.Position = UDim2.new(1, -14, 0.38, 0)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
ToggleBtn.Image = "rbxthumb://type=GameIcon&id=" .. game.GameId .. "&w=150&h=150"
local corner = Instance.new("UICorner", ToggleBtn)
corner.CornerRadius = UDim.new(0, 8)
ToggleBtn.MouseButton1Click:Connect(function()
    game:GetService("VirtualInputManager"):SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
    task.wait(0.1)
    game:GetService("VirtualInputManager"):SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
end)
if not safeParentScreenGui(MobileGui) then MobileGui:Destroy() end
Tabs.Settings:AddToggle("MobileToggleBtn", {Title = "Nút Mở UI (Cho Mobile)", Default = appConfig.MobileToggle}):OnChanged(function(v)
    appConfig.MobileToggle = v
    MobileGui.Enabled = v
    saveConfig()
end)
MobileGui.Enabled = appConfig.MobileToggle or false
end
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
getgenv().AnimeExpeditionsCoordinator = {
    Generation = scriptGeneration,
    Return = {Active = false, LastAttempt = 0, Attempts = 0},
    LobbyObservedAt = nil,
    LobbyObservedJob = nil,
    LastActionAt = 0,
    ReasonStartedAt = {},
    CraftIndex = {},
    FuelPending = nil,
    BuildingClaimPending = nil,
    BuildingSkipped = {},
    GeodeBurst = nil,
    MapSwitch = nil,
    UtilityPending = nil,
    UtilityLastActionAt = 0,
    StatRollLastActionAt = 0,
    Status = "Idle",
}
getgenv().AnimeExpeditionsCoordinator.SetStatus = function(self, status)
    if self.Status == status then return end
    self.Status = status
    if self.StatusParagraph then safeSetParagraphDesc(self.StatusParagraph, status) end
    print("[LOBBY MAINTENANCE] " .. status)
end
getgenv().AnimeExpeditionsCoordinator.Peek = function(self, value)
    local ok, result = pcall(function() return Fusion.peek(value) end)
    return ok and result or value
end
getgenv().AnimeExpeditionsCoordinator.GetPlayerData = function(self)
    local data = self:Peek(Dependencies.PlayerData)
    return type(data) == "table" and data or nil
end
getgenv().AnimeExpeditionsCoordinator.GetMaintenance = function(self)
    appConfig.LobbyMaintenance = type(appConfig.LobbyMaintenance) == "table" and appConfig.LobbyMaintenance or {}
    appConfig.LobbyMaintenance.Reasons = type(appConfig.LobbyMaintenance.Reasons) == "table" and appConfig.LobbyMaintenance.Reasons or {}
    appConfig.LobbyMaintenance.Payloads = type(appConfig.LobbyMaintenance.Payloads) == "table" and appConfig.LobbyMaintenance.Payloads or {}
    appConfig.LobbyMaintenance.StatRoll = type(appConfig.LobbyMaintenance.StatRoll) == "table" and appConfig.LobbyMaintenance.StatRoll or {}
    local known = {SpriteCraft = true, ExpeditionScrapCraft = true, ExpeditionFuel = true, TrainingRotation = true}
    for reason, enabled in pairs(appConfig.LobbyMaintenance.Reasons) do
        local featureEnabled = reason == "SpriteCraft" and appConfig.autoLeaveSpriteMax
            or reason == "ExpeditionScrapCraft" and (appConfig.autoLeaveExpeditionScrapMax or appConfig.expeditionScrapCraftPending)
            or reason == "ExpeditionFuel" and appConfig.ExpeditionAuto.autoLobbyFuel
            or reason == "TrainingRotation" and appConfig.ExpeditionAuto.autoTraining and appConfig.ExpeditionAuto.autoLeaveTraining
        if enabled ~= true or not known[reason] or not featureEnabled then
            appConfig.LobbyMaintenance.Reasons[reason] = nil
            appConfig.LobbyMaintenance.Payloads[reason] = nil
            self.ReasonStartedAt[reason] = nil
        end
    end
    if next(appConfig.LobbyMaintenance.Reasons) == nil then
        appConfig.LobbyMaintenance.Phase = "Idle"
        appConfig.LobbyMaintenance.RequestedAt = 0
    end
    return appConfig.LobbyMaintenance
end
getgenv().AnimeExpeditionsCoordinator.Queue = function(self, reason, payload)
    local maintenance = self:GetMaintenance()
    if maintenance.Reasons[reason] then return false end
    maintenance.Epoch = (tonumber(maintenance.Epoch) or 0) + 1
    maintenance.Phase = "Queued"
    maintenance.RequestedAt = os.time()
    maintenance.Reasons[reason] = true
    maintenance.Payloads[reason] = payload
    self.ReasonStartedAt[reason] = nil
    saveConfig()
    self:SetStatus("Queued " .. tostring(reason) .. " (epoch " .. tostring(maintenance.Epoch) .. ")")
    return true
end
getgenv().AnimeExpeditionsCoordinator.ClearReason = function(self, reason)
    local maintenance = self:GetMaintenance()
    maintenance.Reasons[reason] = nil
    maintenance.Payloads[reason] = nil
    self.ReasonStartedAt[reason] = nil
    self.CraftIndex[reason] = nil
    if reason == "ExpeditionScrapCraft" then
        appConfig.expeditionScrapCraftPending = false
        appConfig.expeditionScrapCraftPendingSince = 0
    end
    if next(maintenance.Reasons) == nil then
        maintenance.Phase = "Idle"
        maintenance.RequestedAt = 0
        self:SetStatus("Maintenance complete.")
    end
    saveConfig()
end
getgenv().AnimeExpeditionsCoordinator.HasMandatory = function(self)
    return next(self:GetMaintenance().Reasons) ~= nil
end
getgenv().AnimeExpeditionsCoordinator.IsTransitionBusy = function(self)
    return self.Return.Active == true
end
getgenv().AnimeExpeditionsCoordinator.RequestLobby = function(self, owner, reason, stateInfo)
    local now = tick()
    if self.Return.Active and now - (self.Return.SentAt or 0) < 20 then return true end
    if self.Return.Active then
        self.Return.Active = false
        self.Return.Attempts = 0
    end
    if now - (self.Return.LastAttempt or 0) < 5 then return false end
    self.Return.LastAttempt = now
    self.Return.Attempts = (self.Return.Attempts or 0) + 1
    local sent = false
    local ok = pcall(function() sent = safeFireGameAction("Lobby") == true end)
    if ok and sent then
        self.Return.Active = true
        self.Return.Owner = owner
        self.Return.Reason = reason
        self.Return.SentAt = now
        self.Return.GameIncrement = stateInfo and stateInfo.GameIncrement or nil
        if self:HasMandatory() then
            self:GetMaintenance().Phase = "WaitingLobby"
            saveConfig()
        end
        self:SetStatus(tostring(owner) .. " requested Lobby: " .. tostring(reason))
        return true
    end
    if self.Return.Attempts >= 3 and self:HasMandatory() then
        self:SetStatus("Lobby request failed 3 times; waiting for a fresh GameState replica")
    end
    return false
end
getgenv().AnimeExpeditionsCoordinator.BuildMapSwitchLevelData = function(self, joinValue, owner)
    local parts = string.split(tostring(joinValue or ""), "|")
    if #parts < 2 then return nil end
    if owner == "BossBounty" then
        local target = EventAuto.Runtime.ActiveTarget
        if type(target) == "table" and type(target.QueueData) == "table" then return table.clone(target.QueueData) end
    end
    if parts[1] == "Challenge" then
        local target = owner == "DragonWish" and EventAuto.Runtime.ActiveTarget
            or (owner == "Quest" and appConfig.QuestAuto.ActiveTarget)
            or appConfig.challengeActiveTarget
        return {
            Gamemode = "Challenge",
            ChallengeType = parts[2],
            ChallengeIndex = tonumber(parts[3]) or 1,
            MapName = type(target) == "table" and tostring(target.Map or "") or "",
            ActName = type(target) == "table" and tostring(target.Act or "") or "",
            Difficulty = type(target) == "table" and tostring(target.Difficulty or "Hard") or "Hard",
        }
    end
    local levelData = {Gamemode = parts[1], MapName = parts[2], ActName = parts[3] or "", Difficulty = parts[4] or ""}
    if levelData.ActName ~= "" and not levelData.ActName:find("Act", 1, true) then levelData.ActName = "Act " .. levelData.ActName end
    if levelData.Gamemode == "Expedition" then
        levelData.ActName = ""
        levelData.Difficulty = "Hard"
        levelData.DifficultyLevel = tonumber(parts[4]) or 1
    elseif levelData.Gamemode == "Infinite" or levelData.Gamemode == "Mastery" then
        levelData.Difficulty = "Hard"
    end
    return levelData
end
getgenv().AnimeExpeditionsCoordinator.BeginMapSwitchResolution = function(self, owner, reason, stateInfo)
    if not stateInfo or stateInfo.CurrentGameState == "Lobby" then return false end
    if owner == "AutoJoin" then
        local eventTarget = EventAuto.Runtime.ActiveTarget
        local questTarget = appConfig.QuestAuto.Enabled and appConfig.QuestAuto.ActiveTarget or nil
        local challengeTarget = (appConfig.autoChallengeEnabled or appConfig.autoDailyChallengeEnabled) and appConfig.challengeActiveTarget or nil
        if type(eventTarget) == "table" and (eventTarget.Owner == "BossBounty" or eventTarget.Owner == "DragonWish")
            or type(questTarget) == "table" and questTarget.Owner == "Quest"
            or type(challengeTarget) == "table" and challengeTarget.Owner == "Challenge" then return false end
    end
    local currentState = tostring(stateInfo.CurrentGameState or "")
    local currentMode = tostring(stateInfo.Gamemode or ""):lower():gsub("[^%w]", "")
    if currentState ~= "Finished" and currentState ~= "Victory" and currentState ~= "Defeat"
        and (currentMode:find("challenge", 1, true) ~= nil or stateInfo.ChallengeIndex ~= nil) then
        return false
    end
    local current = self.MapSwitch
    if current and current.Phase == "Sent" then return true end
    local previousAutoVote = false
    pcall(function()
        previousAutoVote = Actions.GetSettingValue("AutoVoteStart") == true
        Actions.ChangeSetting("AutoVoteStart", false)
    end)
    self.MapSwitch = {
        Phase = "Resolve",
        Owner = tostring(owner or "AutoJoin"),
        Reason = tostring(reason or "Map change requested"),
        RequestedAt = tick(),
        PreviousIncrement = tonumber(stateInfo.GameIncrement),
        PreviousMode = tostring(stateInfo.Gamemode or ""),
        PreviousMap = tostring(stateInfo.Map or ""),
        PreviousAutoVote = previousAutoVote,
        Attempts = 0,
    }
    getgenv().AnimeExpeditionsMapSwitchPending = true
    getgenv().ExpeditionRouteRewardSearching = false
    getgenv().ExpeditionPostBossSellMode = false
    getgenv().ExpeditionContinueBlocked = false
    macroHookGeneration.Playback = (tonumber(macroHookGeneration.Playback) or 0) + 1
    isPlaying = false
    lastHasRunMacro = false
    getgenv().ExpeditionContinueBlocked = false
    self:SetStatus(string.format(localizeText("Đang chọn map mới: %s"), tostring(reason)))
    return true
end
getgenv().AnimeExpeditionsCoordinator.DispatchMapSwitch = function(self)
    local switch = self.MapSwitch
    if type(switch) ~= "table" or type(switch.LevelData) ~= "table" then return false end
    switch.Attempts = (tonumber(switch.Attempts) or 0) + 1
    switch.SentAt = tick()
    switch.Phase = "Sent"
    switch.DispatchDone = false
    switch.DispatchError = nil
    task.spawn(function()
        local ok, err = pcall(function()
            Actions.ChangeSetting("AutoVoteStart", false)
            task.wait(0.2)
            local restartState = getGameStates()
            if self.MapSwitch ~= switch then error("Map switch cancelled before Restart") end
            local restartCurrent = restartState and tostring(restartState.CurrentGameState or "") or ""
            local restartMode = restartState and tostring(restartState.Gamemode or ""):lower():gsub("[^%w]", "") or ""
            if restartCurrent ~= "Finished" and restartCurrent ~= "Victory" and restartCurrent ~= "Defeat" and restartCurrent ~= "Lobby"
                and (restartMode:find("challenge", 1, true) ~= nil or restartState and restartState.ChallengeIndex ~= nil) then
                error("Blocked map switch during an active Challenge")
            end
            local restartIncrement = restartState and tonumber(restartState.GameIncrement)
            getgenv().IsManualRestart = true
            getgenv().AnimeExpeditionsMapSwitchRestartDispatch = true
            local restartOk, restartSent = pcall(function() return safeFireGameAction("Restart") end)
            getgenv().AnimeExpeditionsMapSwitchRestartDispatch = false
            if not restartOk or restartSent ~= true then error("GameState replica not found for map-switch Restart") end
            local restartDeadline = tick() + 8
            repeat
                task.wait(0.1)
                restartState = getGameStates()
            until tick() >= restartDeadline or (restartState and tonumber(restartState.GameIncrement) ~= restartIncrement)
            switch.DispatchBaseIncrement = restartState and tonumber(restartState.GameIncrement) or restartIncrement
            task.wait(0.25)
            local teamName = switch.LevelData.MapName and appConfig.TeamSelections[tostring(switch.LevelData.MapName)] or nil
            if appConfig.autoJoinTeamEnabled and teamName then
                Actions.LoadUnitTeam(tostring(teamName))
                task.wait(1)
            end
            Actions.ToggleMenu("Play")
            task.wait(0.4)
            if self.MapSwitch ~= switch then error("Map switch cancelled before queue setup") end
            Actions.CancelMatchmaking()
            task.wait(0.1)
            if self.MapSwitch ~= switch then error("Map switch cancelled before SetQueueData") end
            Actions.SetQueueData(switch.LevelData)
            task.wait(0.2)
            if self.MapSwitch ~= switch then error("Map switch cancelled before StartGame") end
            Actions.StartGame()
        end)
        switch.DispatchDone = true
        switch.DispatchError = not ok and tostring(err) or nil
        if not ok then warn("[MAP SWITCH] Dispatch failed: " .. tostring(err)) end
    end)
    self:SetStatus(string.format(localizeText("Đang đổi map trực tiếp (không retry Restart): %s"), tostring(switch.JoinValue)))
    return true
end
getgenv().AnimeExpeditionsCoordinator.StartMapSwitch = function(self, joinValue, owner, stateInfo)
    local switch = self.MapSwitch
    if not switch then
        if not self:BeginMapSwitchResolution(owner, "Auto Join đổi map", stateInfo) then return false end
        switch = self.MapSwitch
    end
    if switch.Phase == "Sent" and switch.JoinValue == joinValue then return true end
    local levelData = self:BuildMapSwitchLevelData(joinValue, owner)
    if not levelData then return false end
    switch.Owner = owner or switch.Owner or "AutoJoin"
    if switch.Owner == "AutoJoin" then getgenv().AnimeExpeditionsAutoJoinCooldownUntil = tick() + 30 end
    switch.JoinValue = tostring(joinValue)
    switch.LevelData = levelData
    switch.TargetMode = tostring(levelData.Gamemode or "")
    switch.TargetMap = tostring(levelData.MapName or "")
    switch.PreviousIncrement = tonumber(stateInfo and stateInfo.GameIncrement) or switch.PreviousIncrement
    local target = (switch.Owner == "BossBounty" or switch.Owner == "DragonWish") and EventAuto.Runtime.ActiveTarget
        or (switch.Owner == "Quest" and appConfig.QuestAuto.ActiveTarget)
        or (switch.Owner == "Challenge" and appConfig.challengeActiveTarget or nil)
    if type(target) == "table" then
        target.Owner = switch.Owner
        target.JoinIssuedAt = os.time()
        target.JoinValue = switch.JoinValue
        if switch.Owner == "Quest" or switch.Owner == "BossBounty" or switch.Owner == "DragonWish" then
            target.MatchesPlayedAtJoin = getSessionMatchesPlayed() or tonumber(stateInfo and stateInfo.SessionMatchesPlayed)
        end
        if switch.Owner == "Quest" or switch.Owner == "Challenge" then saveConfig() end
    end
    getgenv().AnimeExpeditionsJoinLock = {
        Owner = switch.Owner,
        JoinValue = switch.JoinValue,
        SentAt = tick(),
        BaseIncrement = tonumber(stateInfo and stateInfo.GameIncrement),
        TargetMode = switch.TargetMode,
        TargetMap = switch.TargetMap,
        ChallengeType = switch.LevelData and switch.LevelData.ChallengeType,
        ChallengeIndex = switch.LevelData and switch.LevelData.ChallengeIndex,
    }
    return self:DispatchMapSwitch()
end
getgenv().AnimeExpeditionsCoordinator.FinishMapSwitch = function(self, stateInfo, message)
    local switch = self.MapSwitch
    if switch then pcall(function() Actions.ChangeSetting("AutoVoteStart", switch.PreviousAutoVote == true) end) end
    self.MapSwitch = nil
    getgenv().AnimeExpeditionsMapSwitchPending = false
    getgenv().AnimeExpeditionsMapSwitchRestartDispatch = false
    getgenv().AnimeExpeditionsJoinLock = nil
    macroHookGeneration.Playback = (tonumber(macroHookGeneration.Playback) or 0) + 1
    isPlaying = false
    lastHasRunMacro = false
    self:SetStatus(message or "Đổi map trực tiếp hoàn tất.")
end
getgenv().AnimeExpeditionsCoordinator.CheckMapSwitch = function(self, stateInfo)
    local switch = self.MapSwitch
    if not switch then
        getgenv().AnimeExpeditionsMapSwitchPending = false
        return false
    end
    local currentState = stateInfo and tostring(stateInfo.CurrentGameState or "") or ""
    local currentMode = stateInfo and tostring(stateInfo.Gamemode or ""):lower():gsub("[^%w]", "") or ""
    if switch.Phase == "Resolve"
        and currentState ~= "Finished" and currentState ~= "Victory" and currentState ~= "Defeat" and currentState ~= "Lobby"
        and (currentMode:find("challenge", 1, true) ~= nil or stateInfo and stateInfo.ChallengeIndex ~= nil) then
        self:FinishMapSwitch(stateInfo, "Đã hủy đổi map: Challenge hiện tại vẫn đang chạy.")
        return false
    end
    getgenv().AnimeExpeditionsMapSwitchPending = true
    pcall(function() Actions.ChangeSetting("AutoVoteStart", false) end)
    if switch.Phase == "Resolve" then
        if tick() - (switch.RequestedAt or tick()) >= 15 then
            self:FinishMapSwitch(stateInfo, "Không tìm được map mới; fallback về Lobby.")
            self:RequestLobby(switch.Owner or "MapSwitch", switch.Reason or "No direct target", stateInfo)
            return true
        end
        return false
    end
    local incrementChanged = stateInfo and tonumber(stateInfo.GameIncrement) ~= tonumber(switch.DispatchBaseIncrement or switch.PreviousIncrement)
    local stateMode = stateInfo and tostring(stateInfo.Gamemode or ""):lower():gsub("[^%w]", "") or ""
    local targetMode = tostring(switch.TargetMode or ""):lower():gsub("[^%w]", "")
    local modeMatches = targetMode == "challenge" and stateMode:find("challenge", 1, true) ~= nil or stateMode == targetMode
    local stateMap = stateInfo and tostring(stateInfo.Map or "") or ""
    local normalizedStateMap = stateMap:lower():gsub("[^%w]", "")
    local normalizedTargetMap = tostring(switch.TargetMap or ""):lower():gsub("[^%w]", "")
    local mapMatches = normalizedTargetMap == "" or (normalizedStateMap ~= "" and normalizedStateMap ~= "nil" and normalizedStateMap == normalizedTargetMap)
    local challengeIdentityMatches = targetMode ~= "challenge" or stateInfo
        and tostring(stateInfo.ChallengeType or "") ~= ""
        and stateInfo.ChallengeIndex ~= nil
        and tostring(stateInfo.ChallengeType):lower() == tostring(switch.LevelData and switch.LevelData.ChallengeType or ""):lower()
        and tonumber(stateInfo.ChallengeIndex) == tonumber(switch.LevelData and switch.LevelData.ChallengeIndex)
    local activeState = currentState ~= "" and currentState ~= "nil" and currentState ~= "Finished"
        and currentState ~= "Victory" and currentState ~= "Defeat" and currentState ~= "Lobby"
    if switch.DispatchDone and incrementChanged and modeMatches and challengeIdentityMatches and activeState then
        switch.TargetStateSeenAt = switch.TargetStateSeenAt or tick()
        if mapMatches then
            self:FinishMapSwitch(stateInfo, "Đổi map trực tiếp hoàn tất: " .. tostring(switch.TargetMap))
            return false
        end
        local confirmationAge = tick() - switch.TargetStateSeenAt
        if stateInfo.MapObserved ~= true and confirmationAge >= 1 then
            self:FinishMapSwitch(stateInfo, "Đổi map đã vào đúng mode/increment; map replica đang tải.")
            return false
        elseif stateInfo.MapObserved == true and confirmationAge >= 2 then
            self:FinishMapSwitch(stateInfo, "Đã vào game increment mới; dừng retry để tránh Restart lặp.")
            return false
        end
        return true
    end
    if tick() - (switch.SentAt or tick()) >= 35 then
        local owner, reason = switch.Owner, switch.Reason
        self:FinishMapSwitch(stateInfo, "Đổi map không được xác nhận; fallback về Lobby, không tự Restart lại.")
        self:RequestLobby(owner or "MapSwitch", reason or "Direct map switch failed", stateInfo)
    end
    return true
end
getgenv().AnimeExpeditionsCoordinator.IsLobbyReady = function(self, stateInfo)
    local explicitLobby = type(stateInfo) == "table" and stateInfo.CurrentGameState == "Lobby"
    local stateCurrent = type(stateInfo) == "table" and tostring(stateInfo.CurrentGameState or "") or ""
    local stateMode = type(stateInfo) == "table" and tostring(stateInfo.Gamemode or "") or ""
    local idleState = not stateInfo or explicitLobby
        or ((stateCurrent == "" or stateCurrent == "nil" or stateCurrent == "false")
            and (stateMode == "" or stateMode == "nil" or stateMode == "false"))
    if not idleState then
        self.LobbyObservedAt = nil
        return false
    end
    if getgenv().AnimeExpeditionsJoinLock then
        self.LobbyObservedAt = nil
        return false
    end
    for _, object in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
        if object:IsA("TextLabel") and object.Visible and tostring(object.Text):lower():find("teleporting", 1, true) then
            self.LobbyObservedAt = nil
            return false
        end
    end
    local rawGameState = self:Peek(Dependencies.GameState)
    local rawPlayerState = self:Peek(Dependencies.GamePlayerState)
    local rawCurrent = type(rawGameState) == "table" and tostring(self:Peek(rawGameState.CurrentGameState) or "") or ""
    local rawParameters = type(rawGameState) == "table" and self:Peek(rawGameState.Parameters) or nil
    local rawMode = type(rawParameters) == "table" and tostring(self:Peek(rawParameters.Gamemode) or "") or ""
    local rawPlayerId = type(rawPlayerState) == "table" and self:Peek(rawPlayerState.ID) or nil
    local rawGameActive = rawCurrent ~= "" and rawCurrent ~= "nil" and rawCurrent ~= "false"
        or (rawMode ~= "" and rawMode ~= "nil" and rawMode ~= "false")
    if not explicitLobby and (rawGameActive or rawPlayerId ~= nil) then
        self.LobbyObservedAt = nil
        return false
    end
    if not workspace:FindFirstChild("Lobby") then
        self.LobbyObservedAt = nil
        return false
    end
    local playerData = self:GetPlayerData()
    local expeditionData = playerData and self:Peek(playerData.ExpeditionData)
    if type(expeditionData) ~= "table" or type(self:Peek(expeditionData.Buildings)) ~= "table" then
        self.LobbyObservedAt = nil
        return false
    end
    if self.LobbyObservedJob ~= game.JobId then
        self.LobbyObservedJob = game.JobId
        self.LobbyObservedAt = tick()
        return false
    end
    self.LobbyObservedAt = self.LobbyObservedAt or tick()
    return tick() - self.LobbyObservedAt >= 0.25
end
getgenv().AnimeExpeditionsCoordinator.GetFuelState = function(self, selectedBuildings)
    local playerData = self:GetPlayerData()
    local expeditionData = playerData and self:Peek(playerData.ExpeditionData)
    local buildings = type(expeditionData) == "table" and self:Peek(expeditionData.Buildings) or nil
    local itemData = playerData and self:Peek(playerData.ItemData)
    local fuelData = type(itemData) == "table" and self:Peek(itemData.ExpeditionFuel) or nil
    local owned = type(fuelData) == "table" and tonumber(self:Peek(fuelData.Amount)) or tonumber(fuelData) or 0
    local selected, seen = {}, {}
    for key, value in pairs(type(selectedBuildings) == "table" and selectedBuildings or {}) do
        local name = type(key) == "number" and value or (value == true and key or nil)
        if (name == "GoldMine" or name == "ResourceDrill") and not seen[name] then
            seen[name] = true
            table.insert(selected, name)
        end
    end
    table.sort(selected)
    local result = {Ready = type(buildings) == "table", Owned = math.max(0, owned), TotalDeficit = 0, AnyEmpty = false, Selected = selected, Buildings = {}}
    if not result.Ready then return result end
    for _, name in ipairs(selected) do
        local data = self:Peek(buildings[name])
        if type(data) == "table" then
            local current = tonumber(self:Peek(data.Fuel)) or 0
            local maxFuel = 0
            local buildingInfo
            local buildingUpgrade
            pcall(function()
                buildingInfo = Dependencies.Information.Expeditions:GetBuildingInfo(name)
                maxFuel = tonumber(buildingInfo.MaxFuel) or 0
                buildingUpgrade = Dependencies.Information.Expeditions:GetBuildingUpgrade(name, tonumber(self:Peek(data.Upgrade)) or 0)
            end)
            local deficit = math.max(0, maxFuel - current)
            local secondsPerFuel = type(buildingUpgrade) == "table" and tonumber(buildingUpgrade.SecondsPerFuel) or nil
            local timePerTick = secondsPerFuel or (type(buildingInfo) == "table" and (tonumber(buildingInfo.TimePerTick) or tonumber(buildingInfo.FuelTime) or tonumber(buildingInfo.FuelInterval)) or nil)
            local fuelPerTick = type(buildingInfo) == "table" and (tonumber(buildingInfo.FuelPerTick) or tonumber(buildingInfo.FuelCost) or tonumber(buildingInfo.FuelConsumption)) or nil
            local drainRate = type(buildingInfo) == "table" and tonumber(buildingInfo.FuelDrainRate) or nil
            local secondsRemaining
            if timePerTick and timePerTick > 0 then
                secondsRemaining = current / math.max(fuelPerTick or 1, 0.0001) * timePerTick
                local lastRewardTime = tonumber(self:Peek(data.LastRewardTime))
                if current > 0 and lastRewardTime then
                    secondsRemaining = math.max(0, secondsRemaining - math.clamp(workspace:GetServerTimeNow() - lastRewardTime, 0, timePerTick))
                end
            elseif drainRate and drainRate > 0 then
                secondsRemaining = current / drainRate
            end
            result.Buildings[name] = {Fuel = current, MaxFuel = maxFuel, Deficit = deficit, SecondsRemaining = secondsRemaining}
            result.TotalDeficit = result.TotalDeficit + deficit
            if current <= 0 and deficit > 0 then result.AnyEmpty = true end
        end
    end
    return result
end
getgenv().AnimeExpeditionsCoordinator.FormatFuelTime = function(self, seconds)
    seconds = tonumber(seconds)
    if not seconds then return "không rõ" end
    seconds = math.max(0, math.floor(seconds))
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds % 86400 / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    if days > 0 then return string.format("%dd %dh", days, hours) end
    if hours > 0 then return string.format("%dh %dm", hours, minutes) end
    return string.format("%dm", minutes)
end
getgenv().AnimeExpeditionsCoordinator.UpdateFuelDisplay = function(self, force)
    if not force and tick() - (self.LastFuelDisplayAt or 0) < 1 then return end
    self.LastFuelDisplayAt = tick()
    if not self.FuelParagraph then return end
    local fuel = self:GetFuelState(appConfig.ExpeditionAuto.fuelBuildings)
    local lines = {string.format(localizeText("Fuel trong túi: %s"), tostring(fuel.Owned or 0))}
    local labels = {GoldMine = "Gold Mine", ResourceDrill = "Resource Drill"}
    if #fuel.Selected == 0 then table.insert(lines, "Chưa chọn building.") end
    for _, name in ipairs(fuel.Selected) do
        local building = fuel.Buildings[name]
        if building then
            table.insert(lines, string.format(localizeText("%s: %d/%d | hết sau ~%s"), labels[name] or name, building.Fuel, building.MaxFuel, self:FormatFuelTime(building.SecondsRemaining)))
        else
            table.insert(lines, string.format(localizeText("%s: đang chờ dữ liệu..."), labels[name] or name))
        end
    end
    safeSetParagraphDesc(self.FuelParagraph, table.concat(lines, "\n"))
end
getgenv().AnimeExpeditionsCoordinator.GetBuildingResourceState = function(self)
    local playerData = self:GetPlayerData()
    local expeditionData = playerData and self:Peek(playerData.ExpeditionData)
    local buildings = type(expeditionData) == "table" and self:Peek(expeditionData.Buildings) or nil
    local items = playerData and self:Peek(playerData.ItemData)
    local result = {Ready = type(buildings) == "table", Buildings = {}, Geodes = 0, GeodeAssets = {}, SpriteGrey = 0}
    for asset, rawItem in pairs(type(items) == "table" and items or {}) do
        asset = tostring(asset)
        local item = self:Peek(rawItem)
        local amount = math.max(0, math.floor(type(item) == "table" and (tonumber(self:Peek(item.Amount)) or 0) or (tonumber(item) or 0)))
        if asset:find("ExpeditionGeode", 1, true) and amount > 0 then
            result.Geodes += amount
            table.insert(result.GeodeAssets, {Asset = asset, Amount = amount})
        elseif asset == "SpriteGrey" then
            result.SpriteGrey = amount
        end
    end
    table.sort(result.GeodeAssets, function(left, right) return left.Asset < right.Asset end)
    for _, name in ipairs({"GoldMine", "ResourceDrill"}) do
        local data = type(buildings) == "table" and self:Peek(buildings[name]) or nil
        local rewards = type(data) == "table" and self:Peek(data.Rewards) or nil
        local count, signature = 0, {}
        for key, rawReward in pairs(type(rewards) == "table" and rewards or {}) do
            local reward = self:Peek(rawReward)
            count += 1
            if type(reward) == "table" then
                table.insert(signature, tostring(key) .. ":" .. tostring(self:Peek(reward.Asset) or "") .. ":" .. tostring(self:Peek(reward.Amount) or ""))
            else
                table.insert(signature, tostring(key) .. ":" .. tostring(reward))
            end
        end
        table.sort(signature)
        result.Buildings[name] = {Available = type(data) == "table", RewardCount = count, Signature = table.concat(signature, "|")}
    end
    return result
end
getgenv().AnimeExpeditionsCoordinator.RunQuestBoardClaims = function(self)
    if not appConfig.ExpeditionAuto.autoClaimQuestBoard or self.QuestBoardClaimCycleDone then return false end
    if self.QuestBoardClaimPending then
        if tick() - self.QuestBoardClaimPending < 0.25 then return true end
        self.QuestBoardClaimPending = nil
        self.QuestBoardClaimCycleDone = true
        return false
    end
    local playerData = self:GetPlayerData()
    if type(playerData) ~= "table" then return false end
    local category = tostring(Dependencies.Information.Expeditions.Milestones.QuestCategory or "Expedition_Weekly")
    local questData = self:Peek(playerData.QuestData)
    local categoryData = type(questData) == "table" and self:Peek(questData[category]) or nil
    local quests = type(categoryData) == "table" and self:Peek(categoryData.Quests) or nil
    local sent = false
    for questId, rawQuest in pairs(type(quests) == "table" and quests or {}) do
        local quest = self:Peek(rawQuest)
        if type(quest) == "table" and self:Peek(quest.Completed) == true and self:Peek(quest.Claimed) ~= true then
            pcall(function() Actions.ClaimQuest(category, tostring(questId)) end)
            sent = true
        end
    end
    local expeditionData = self:Peek(playerData.ExpeditionData)
    local buildings = type(expeditionData) == "table" and self:Peek(expeditionData.Buildings) or nil
    local questBoard = type(buildings) == "table" and self:Peek(buildings.QuestBoard) or nil
    local milestone = type(questBoard) == "table" and tonumber(self:Peek(questBoard.Milestone)) or 0
    local claimed = type(questBoard) == "table" and self:Peek(questBoard.ClaimedMilestones) or nil
    for index = 1, milestone do
        if type(claimed) ~= "table" or self:Peek(claimed["Milestone" .. tostring(index)]) ~= true then
            pcall(function() Actions.ExpeditionBuilding_ClaimAllMilestoneRewards() end)
            sent = true
            break
        end
    end
    if sent then
        self.QuestBoardClaimPending = tick()
        return true
    end
    self.QuestBoardClaimCycleDone = true
    return false
end
getgenv().AnimeExpeditionsCoordinator.UpdateBuildingResourceDisplay = function(self, force)
    if not force and tick() - (self.LastBuildingResourceDisplayAt or 0) < 1 then return end
    self.LastBuildingResourceDisplayAt = tick()
    if not self.BuildingResourceParagraph then return end
    local state = self:GetBuildingResourceState()
    local claim = self.BuildingClaimPending
    local burst = self.GeodeBurst
    local status = "Đang chờ rewards"
    if claim then status = "Đang claim " .. tostring(claim.Building)
    elseif burst then status = string.format("Đang mở Geode: gửi %d/%d | chờ %d", burst.Sent or 0, burst.Budget or 0, burst.InFlight or 0)
    elseif appConfig.ExpeditionAuto.autoOpenGeodes and state.Geodes > 0 and not appConfig.ExpeditionAuto.openGeodesWhenSpriteFull and state.SpriteGrey > 120 then status = "Pause: SpriteGrey có nguy cơ đầy"
    elseif appConfig.ExpeditionAuto.autoOpenGeodes and state.Geodes > 0 then status = "Sẵn sàng mở Geode"
    elseif not appConfig.ExpeditionAuto.autoClaimBuildingRewards and not appConfig.ExpeditionAuto.autoOpenGeodes then status = "Đã tắt" end
    local gold = state.Buildings.GoldMine or {}
    local drill = state.Buildings.ResourceDrill or {}
    safeSetParagraphDesc(self.BuildingResourceParagraph, table.concat({
        string.format(localizeText("Trạng thái     : %s"), localizeText(status)),
        string.format("Gold Mine      : %d reward", gold.RewardCount or 0),
        string.format("Resource Drill : %d reward", drill.RewardCount or 0),
        string.format("Geode          : %d", state.Geodes),
        string.format(localizeText("SpriteGrey     : %d/125 | Mở khi đầy: %s"), state.SpriteGrey, localizeText(appConfig.ExpeditionAuto.openGeodesWhenSpriteFull and "Có" or "Không")),
    }, "\n"))
end
getgenv().AnimeExpeditionsCoordinator.RunBuildingResources = function(self, stateInfo)
    if not self:IsLobbyReady(stateInfo) or self:HasMandatory() then return false end
    local config = appConfig.ExpeditionAuto
    local state = self:GetBuildingResourceState()
    if not state.Ready then return false end
    self.BuildingSkipped = self.BuildingSkipped or {}
    if self.BuildingClaimPending then
        local pending = self.BuildingClaimPending
        local current = state.Buildings[pending.Building]
        if current and (current.RewardCount == 0 or current.Signature ~= pending.BeforeSignature) then
            self.BuildingClaimPending = nil
            self:SetStatus("Claimed rewards from " .. tostring(pending.Building))
        elseif tick() - pending.SentAt < 2 then
            return true
        else
            self.BuildingSkipped[pending.Building] = true
            self.BuildingClaimPending = nil
            warn("[BUILDING CLAIM] Server did not confirm " .. tostring(pending.Building) .. "; skipping this Lobby cycle")
        end
        state = self:GetBuildingResourceState()
    end
    if config.autoClaimBuildingRewards then
        for _, name in ipairs(config.claimRewardBuildings or {}) do
            local building = state.Buildings[name]
            if building and building.Available and building.RewardCount > 0 and not self.BuildingSkipped[name] then
                local ok, err = pcall(function() Actions.ExpeditionBuilding_ClaimRewards(name) end)
                if ok then
                    self.BuildingClaimPending = {Building = name, BeforeSignature = building.Signature, SentAt = tick()}
                    self:SetStatus("Claiming rewards from " .. name)
                    self:UpdateBuildingResourceDisplay(true)
                    return true
                end
                self.BuildingSkipped[name] = true
                warn("[BUILDING CLAIM] Request failed for " .. name .. ": " .. tostring(err))
            end
        end
    end
    local burst = self.GeodeBurst
    if burst then
        if (burst.DispatchDone or burst.DispatchStopped) and (burst.InFlight or 0) <= 0 then
            burst.FinishedAt = burst.FinishedAt or tick()
            if tick() - burst.FinishedAt < 0.5 then return true end
            local remaining = self:GetBuildingResourceState().Geodes
            if remaining >= (burst.BeforeAmount or remaining) and tick() - burst.FinishedAt < 1 then return true end
            self.GeodeBurst = nil
            if remaining >= (burst.BeforeAmount or remaining) then
                self.BuildingSkipped.Geode = true
                warn("[AUTO GEODE] Burst made no confirmed progress; skipping this Lobby cycle")
                return false
            end
            if remaining <= 0 then
                self:SetStatus("Auto Open Geode complete.")
                self:UpdateBuildingResourceDisplay(true)
                return false
            end
        else
            return true
        end
    end
    state = self:GetBuildingResourceState()
    if not config.autoOpenGeodes or state.Geodes <= 0 or self.BuildingSkipped.Geode then return false end
    if not config.openGeodesWhenSpriteFull and state.SpriteGrey > 120 then
        self:SetStatus("Auto Geode paused: SpriteGrey có nguy cơ đầy.")
        return false
    end
    burst = {
        Budget = state.Geodes,
        BeforeAmount = state.Geodes,
        Assets = state.GeodeAssets,
        AssetIndex = 1,
        AssetSent = 0,
        Sent = 0,
        InFlight = 0,
        Completed = 0,
        Failed = 0,
        StartedAt = tick(),
        Generation = self.Generation,
    }
    self.GeodeBurst = burst
    self:SetStatus(string.format("Auto opening %d Geode at 0.033333s", burst.Budget))
    task.spawn(function()
        while burst.Sent < burst.Budget and burst.Generation == getgenv().AnimeExpeditionsScriptGeneration and config.autoOpenGeodes do
            if not config.openGeodesWhenSpriteFull and (snapshotItemData().SpriteGrey or 0) > 120 then
                burst.DispatchStopped = true
                break
            end
            local assetBudget = burst.Assets[burst.AssetIndex]
            while assetBudget and burst.AssetSent >= assetBudget.Amount do
                burst.AssetIndex += 1
                burst.AssetSent = 0
                assetBudget = burst.Assets[burst.AssetIndex]
            end
            if not assetBudget then break end
            local geodeAsset = assetBudget.Asset
            burst.Sent += 1
            burst.AssetSent += 1
            burst.InFlight += 1
            task.spawn(function()
                local ok, result = pcall(function()
                    local requestObject = require(ReplicatedStorage.Nodes).RESOURCEDRILL_OPEN_GEODE:Request(geodeAsset, config.openGeodesWhenSpriteFull == true)
                    requestObject:Timeout(10)
                    return requestObject:Wait()
                end)
                burst.InFlight = math.max(0, burst.InFlight - 1)
                if ok and result ~= nil then burst.Completed += 1 else burst.Failed += 1 end
            end)
            task.wait(Dependencies.Information.Traits.RerollDebounce or 0.033333333333333)
        end
        burst.DispatchDone = true
    end)
    self:UpdateBuildingResourceDisplay(true)
    return true
end
getgenv().AnimeExpeditionsCoordinator.FailReason = function(self, reason, message)
    if reason == "SpriteCraft" then appConfig.autoLeaveSpriteMax = false end
    if reason == "ExpeditionScrapCraft" then appConfig.autoLeaveExpeditionScrapMax = false end
    if reason == "ExpeditionFuel" then
        appConfig.ExpeditionAuto.autoLobbyFuel = false
        appConfig.ExpeditionAuto.autoLeaveFuel = false
        local fuelToggle = getgenv().AnimeExpeditionsFuelToggle
        local leaveToggle = getgenv().AnimeExpeditionsLeaveToggles and getgenv().AnimeExpeditionsLeaveToggles.Fuel
        if fuelToggle then task.defer(function() pcall(function() fuelToggle:SetValue(false) end) end) end
        if leaveToggle then task.defer(function() pcall(function() leaveToggle:SetValue(false) end) end) end
    end
    if reason == "TrainingRotation" then
        self.UtilityPending = nil
        warn("[TRAINING AUTO LEAVE] Rotation timed out; keeping Auto Leave enabled for the next check")
    end
    pcall(function() Fluent:Notify({Title = "Lobby Maintenance", Content = message, Duration = 8}) end)
    self:SetStatus(message)
    self:ClearReason(reason)
end
getgenv().AnimeExpeditionsCoordinator.ProcessCraftReason = function(self, reason)
    local isSprite = reason == "SpriteCraft"
    local current = snapshotItemData()[isSprite and "SpriteGrey" or "EquipmentScrap"] or 0
    local threshold = isSprite and 125 or 250
    if current < threshold then
        self:ClearReason(reason)
        return true
    end
    self.ReasonStartedAt[reason] = self.ReasonStartedAt[reason] or tick()
    local enabled = isSprite and appConfig.autoCraftEnabled or appConfig.autoExpeditionCraftEnabled
    local recipes = isSprite and appConfig.autoCraftItems or appConfig.autoExpeditionCraftItems
    if not enabled or type(recipes) ~= "table" or #recipes == 0 then
        self:FailReason(reason, "Không có Auto Craft/recipe phù hợp; đã tắt riêng Auto Leave tương ứng.")
        return true
    end
    if tick() - self.ReasonStartedAt[reason] >= 15 then
        self:FailReason(reason, "Craft không làm inventory giảm sau 15 giây; đã mở khóa scheduler.")
        return true
    end
    if tick() - self.LastActionAt < 0.5 then return false end
    self.CraftIndex[reason] = (self.CraftIndex[reason] or 0) % #recipes + 1
    local recipe = recipes[self.CraftIndex[reason]]
    self.LastActionAt = tick()
    local ok, err = pcall(function()
        if isSprite then
            Actions.CraftRecipe(recipe, 5)
            Actions.CraftRecipe(recipe, 1)
        else
            Actions.CraftRecipe(recipe, 1, 5)
            Actions.CraftRecipe(recipe, 1, 1)
        end
    end)
    if not ok then warn("[LOBBY MAINTENANCE] Craft failed: " .. tostring(err)) end
    self:SetStatus(string.format("Crafting %s (%d/%d)", tostring(recipe), current, threshold))
    return false
end
getgenv().AnimeExpeditionsCoordinator.ProcessFuelReason = function(self)
    local payload = self:GetMaintenance().Payloads.ExpeditionFuel
    local selected = type(payload) == "table" and payload.Buildings or appConfig.ExpeditionAuto.fuelBuildings
    local fuel = self:GetFuelState(selected)
    if not fuel.Ready then return false end
    if fuel.TotalDeficit <= 0 or fuel.Owned <= 0 or #fuel.Selected == 0 then
        self.FuelPending = nil
        self:ClearReason("ExpeditionFuel")
        return true
    end
    if self.FuelPending then
        local current = fuel.Buildings[self.FuelPending.Building]
        local confirmed = current and current.Fuel > self.FuelPending.BeforeFuel or fuel.Owned < self.FuelPending.BeforeOwned
        if confirmed then
            self.FuelRetryBuilding = nil
            self.FuelRetryCount = 0
            self.FuelPending = nil
        elseif tick() - self.FuelPending.SentAt < 2 then
            return false
        else
            self.FuelPending.Attempts = self.FuelPending.Attempts + 1
            if self.FuelPending.Attempts >= 3 then
                self:FailReason("ExpeditionFuel", "Nạp Fuel không được server xác nhận sau 3 lần; đã tắt riêng Auto Fuel.")
                self.FuelPending = nil
                return true
            end
            self.FuelPending = nil
        end
    end
    if tick() - self.LastActionAt < 0.25 then return false end
    for _, name in ipairs(fuel.Selected) do
        local building = fuel.Buildings[name]
        if building and building.Deficit > 0 then
            local amount = math.floor(math.min(building.Deficit, fuel.Owned))
            if amount <= 0 then break end
            self.LastActionAt = tick()
            local previousAttempts = self.FuelRetryBuilding == name and self.FuelRetryCount or 0
            local ok, err = pcall(function() Actions.ExpeditionBuilding_AddFuel(name, amount) end)
            if ok then
                self.FuelRetryBuilding = name
                self.FuelRetryCount = previousAttempts + 1
                self.FuelPending = {Building = name, BeforeFuel = building.Fuel, BeforeOwned = fuel.Owned, SentAt = tick(), Attempts = previousAttempts}
                self:SetStatus(string.format("Adding %d Fuel to %s (%d/%d)", amount, name, building.Fuel, building.MaxFuel))
            else
                self.FuelRetryBuilding = name
                self.FuelRetryCount = previousAttempts + 1
                warn("[LOBBY MAINTENANCE] AddFuel failed: " .. tostring(err))
                if self.FuelRetryCount >= 3 then
                    self:FailReason("ExpeditionFuel", "Nạp Fuel lỗi 3 lần; đã tắt Auto Fuel và mở khóa Auto Join.")
                    return true
                end
            end
            return false
        end
    end
    return false
end
getgenv().AnimeExpeditionsCoordinator.ProcessMandatory = function(self, stateInfo)
    local maintenance = self:GetMaintenance()
    if next(maintenance.Reasons) == nil then return false end
    local now = os.time()
    local requestedAt = tonumber(maintenance.RequestedAt) or 0
    if requestedAt <= 0 or requestedAt > now then
        maintenance.RequestedAt = now
        saveConfig()
    elseif now - requestedAt >= 45 then
        for _, reason in ipairs({"SpriteCraft", "ExpeditionScrapCraft", "ExpeditionFuel", "TrainingRotation"}) do
            if maintenance.Reasons[reason] then
                self:FailReason(reason, tostring(reason) .. " không hoàn tất sau 45 giây; đã mở khóa Auto Join.")
                return true
            end
        end
    end
    if not self:IsLobbyReady(stateInfo) then
        self:SetStatus("Waiting for confirmed Lobby replicas...")
        return true
    end
    if self.Return.Active then
        self.Return.Active = false
        self.Return.Attempts = 0
    end
    if maintenance.Phase ~= "Running" then
        maintenance.Phase = "Running"
        saveConfig()
    end
    for _, reason in ipairs({"SpriteCraft", "ExpeditionScrapCraft", "ExpeditionFuel", "TrainingRotation"}) do
        if maintenance.Reasons[reason] then
            if reason == "ExpeditionFuel" then
                self:ProcessFuelReason()
            elseif reason == "TrainingRotation" then
                self:ClearReason(reason)
            else
                self:ProcessCraftReason(reason)
            end
            return true
        end
    end
    return false
end
getgenv().AnimeExpeditionsCoordinator.BeforeAutomation = function(self, stateInfo, eventOwned, questOwned, challengeOwned)
    if self.Generation ~= getgenv().AnimeExpeditionsScriptGeneration then return false end
    self:UpdateFuelDisplay()
    self:UpdateBuildingResourceDisplay()
    self:UpdateTrainingDisplay()
    self:UpdateStatRollDisplay()
    if appConfig.expeditionScrapCraftPending and not self:GetMaintenance().Reasons.ExpeditionScrapCraft then
        self:Queue("ExpeditionScrapCraft")
    end
    -- Keep the timeout alive even if a failed Lobby request never reaches the Lobby branch.
    if self:HasMandatory() and stateInfo and stateInfo.CurrentGameState ~= "Lobby" then self:ProcessMandatory(stateInfo) end
    local isLobby = not stateInfo or stateInfo.CurrentGameState == "Lobby"
    if isLobby and not self.WasLobby then
        self.ShopPending = nil
        self.ShopSkipped = {}
        self.ShopWaitAt = {}
        self.CraftPending = nil
        self.CraftSkipped = {}
        self.UtilityPending = nil
        self.UtilitySkipped = {}
        self.BuildingSkipped = {}
        self.QuestBoardClaimPending = nil
        self.QuestBoardClaimCycleDone = false
        self.LobbyPreflightAt = tick()
        self.LobbyPreflightReady = false
    end
    self.WasLobby = isLobby
    if isLobby then
        local lobbyReady = self:IsLobbyReady(stateInfo)
        local preparationEnabled = appConfig.ExpeditionAuto.autoLobbyFuel or appConfig.autoShopEnabled
            or appConfig.autoCraftEnabled or appConfig.autoExpeditionCraftEnabled
            or appConfig.ExpeditionAuto.autoClaimBuildingRewards or appConfig.ExpeditionAuto.autoOpenGeodes
            or appConfig.ExpeditionAuto.autoTraining or appConfig.ExpeditionAuto.autoSkillTree
        if preparationEnabled and not lobbyReady and not self.LobbyPreflightReady then
            self.LobbyPreflightAt = self.LobbyPreflightAt or tick()
            if tick() - self.LobbyPreflightAt < 2 then
                self:SetStatus("Waiting for Lobby preparation replicas before Join...")
                return true
            end
            self.LobbyPreflightReady = true
            self:SetStatus("Lobby preparation replicas unavailable after 2s; opening Join.")
        elseif lobbyReady then
            self.LobbyPreflightReady = true
            if self.Return.Active then
                self.Return.Active = false
                self.Return.Attempts = 0
            end
            if appConfig.ExpeditionAuto.autoLobbyFuel and not self:GetMaintenance().Reasons.ExpeditionFuel then
                local fuel = self:GetFuelState(appConfig.ExpeditionAuto.fuelBuildings)
                if fuel.Ready and fuel.TotalDeficit > 0 and fuel.Owned > 0 then
                    self:Queue("ExpeditionFuel", {Buildings = fuel.Selected})
                end
            end
        end
        return self:HasMandatory()
    end
    self.LobbyObservedAt = nil
    local expeditionConfig = appConfig.ExpeditionAuto or {}
    local specialLifecycle = getgenv().ExpeditionRouteRewardSearching or getgenv().ExpeditionPostBossSellMode
        or getgenv().ExpeditionHelperPlacementPending or expeditionConfig.routeRewardRestartEnabled or expeditionConfig.sellAllAfterBoss
        or getgenv().PendingRecord
    if appConfig.ExpeditionAuto.autoTraining and appConfig.ExpeditionAuto.autoLeaveTraining
        and not self:GetMaintenance().Reasons.TrainingRotation and self:TrainingCompletionReady() then
        self:Queue("TrainingRotation")
        print("[TRAINING AUTO LEAVE] Completion reached; queued mandatory Lobby rotation")
    end
    if appConfig.ExpeditionAuto.autoLeaveFuel and appConfig.ExpeditionAuto.autoLobbyFuel then
        local fuel = self:GetFuelState(appConfig.ExpeditionAuto.fuelBuildings)
        if fuel.Ready and fuel.AnyEmpty and fuel.TotalDeficit > 0 and fuel.Owned >= fuel.TotalDeficit then
            self:Queue("ExpeditionFuel", {Buildings = fuel.Selected})
            print("[FUEL AUTO LEAVE] Empty building detected; queued mandatory Lobby refill")
        end
    end
    local trainingMandatory = self:GetMaintenance().Reasons.TrainingRotation == true
    local fuelMandatory = self:GetMaintenance().Reasons.ExpeditionFuel == true
    if trainingMandatory or fuelMandatory then
        if eventOwned or questOwned or challengeOwned then return false end
        self:RequestLobby("Maintenance", "Fuel/Training pending; Exit Immediately", stateInfo)
        return true
    end
    if self:HasMandatory() and not eventOwned and not questOwned and not challengeOwned and not specialLifecycle then
        self:RequestLobby("Maintenance", "Craft pending", stateInfo)
    end
    return self:HasMandatory() and not eventOwned and not questOwned and not challengeOwned and not specialLifecycle
end
getgenv().AnimeExpeditionsCoordinator.GetTrainingProjection = function(self, unitData, assignedAt, trainingUpgrade)
    local expeditionInfo = Dependencies.Information.Expeditions
    local buildingInfo = expeditionInfo:GetBuildingInfo("TrainingGrounds")
    local elapsed = math.min(math.max(0, workspace:GetServerTimeNow() - (tonumber(assignedAt) or workspace:GetServerTimeNow())), tonumber(buildingInfo.MaxTime) or 86400)
    local ticks = math.floor(elapsed / math.max(1, tonumber(buildingInfo.TimePerTick) or 90))
    local totalExp = (tonumber(self:Peek(unitData.EXP)) or 0) + ticks * (tonumber(trainingUpgrade.ExpRate) or 0)
    local worthiness = math.min((tonumber(self:Peek(unitData.Worthiness)) or 0) + ticks * (tonumber(trainingUpgrade.WorthinessRate) or 0) / 100 * Dependencies.Information.StatPotential.WorthinessPerRoll, Dependencies.Information.StatPotential.MaxWorthiness)
    return Dependencies.Information.UnitLevelInfo:GetLevel(totalExp), worthiness
end
getgenv().AnimeExpeditionsCoordinator.TrainingCompleted = function(self, level, worthiness)
    if appConfig.ExpeditionAuto.trainingCompletionMode == "Level 50" then
        return level >= Dependencies.Information.UnitLevelInfo.MaxLevel
    end
    return worthiness >= Dependencies.Information.StatPotential.MaxWorthiness
end
getgenv().AnimeExpeditionsCoordinator.TrainingCompletionReady = function(self)
    if not appConfig.ExpeditionAuto.autoTraining then return false end
    local playerData = self:GetPlayerData()
    local expeditionData = playerData and self:Peek(playerData.ExpeditionData)
    local buildings = type(expeditionData) == "table" and self:Peek(expeditionData.Buildings) or nil
    local training = type(buildings) == "table" and self:Peek(buildings.TrainingGrounds) or nil
    local assigned = type(training) == "table" and self:Peek(training.Units) or nil
    local upgradeLevel = type(training) == "table" and tonumber(self:Peek(training.Upgrade)) or 0
    local upgradeInfo
    pcall(function() upgradeInfo = Dependencies.Information.Expeditions:GetBuildingUpgrade("TrainingGrounds", upgradeLevel) end)
    if type(assigned) ~= "table" or type(upgradeInfo) ~= "table" then return false end
    for id, assignedAt in pairs(assigned) do
        local unit = self:Peek(playerData.UnitData and playerData.UnitData[id])
        if type(unit) == "table" then
            local level, worthiness = self:GetTrainingProjection(unit, self:Peek(assignedAt), upgradeInfo)
            if self:TrainingCompleted(level, worthiness) then return true end
        end
    end
    return false
end
getgenv().AnimeExpeditionsCoordinator.GetTrainingUnitRarity = function(self, unitData)
    if type(unitData) ~= "table" then return "Unknown" end
    local asset = tostring(self:Peek(unitData.Asset) or "")
    local unitInfo = UnitsInfo[asset]
    return tostring(self:Peek(unitData.Rarity) or (type(unitInfo) == "table" and unitInfo.Rarity) or "Unknown")
end
getgenv().AnimeExpeditionsCoordinator.TrainingRarityMatches = function(self, unitData)
    local rarity = self:GetTrainingUnitRarity(unitData)
    for key, value in pairs(appConfig.ExpeditionAuto.trainingRarities or {}) do
        if (key == rarity and value == true) or value == rarity then return true end
    end
    return false
end
getgenv().AnimeExpeditionsCoordinator.GetTrainingCapacity = function(self, training, upgradeInfo)
    local capacity = type(training) == "table" and tonumber(self:Peek(training.MaxUnits)) or nil
    capacity = capacity or (type(upgradeInfo) == "table" and tonumber(self:Peek(upgradeInfo.MaxUnits)))
    capacity = capacity or (type(upgradeInfo) == "table" and tonumber(self:Peek(upgradeInfo.UnitCapacity)))
    capacity = capacity or (type(upgradeInfo) == "table" and tonumber(self:Peek(upgradeInfo.Capacity)))
    capacity = capacity or (type(upgradeInfo) == "table" and tonumber(self:Peek(upgradeInfo.Slots)))
    return math.max(1, math.floor(capacity or 1))
end
getgenv().AnimeExpeditionsCoordinator.UpdateTrainingDisplay = function(self, force)
    if not force and tick() - (self.LastTrainingDisplayAt or 0) < 1 then return end
    self.LastTrainingDisplayAt = tick()
    if not self.TrainingParagraph then return end
    local playerData = self:GetPlayerData()
    local expeditionData = playerData and self:Peek(playerData.ExpeditionData)
    local buildings = type(expeditionData) == "table" and self:Peek(expeditionData.Buildings) or nil
    local training = type(buildings) == "table" and self:Peek(buildings.TrainingGrounds) or nil
    local assigned = type(training) == "table" and self:Peek(training.Units) or nil
    local upgradeLevel = type(training) == "table" and tonumber(self:Peek(training.Upgrade)) or 0
    local upgradeInfo
    pcall(function() upgradeInfo = Dependencies.Information.Expeditions:GetBuildingUpgrade("TrainingGrounds", upgradeLevel) end)
    if type(assigned) ~= "table" or type(upgradeInfo) ~= "table" then
        safeSetParagraphDesc(self.TrainingParagraph, "Đang chờ dữ liệu Training Grounds...")
        return
    end
    local count = 0
    for _ in pairs(assigned) do count += 1 end
    local lines = {
        string.format(localizeText("Slots: %d/%d | Lấy ra: %s"), count, self:GetTrainingCapacity(training, upgradeInfo), appConfig.ExpeditionAuto.trainingCompletionMode),
        "Rarity: " .. (#(appConfig.ExpeditionAuto.trainingRarities or {}) > 0 and table.concat(appConfig.ExpeditionAuto.trainingRarities, ", ") or localizeText("Không chọn")),
    }
    for id, assignedAt in pairs(assigned) do
        local unit = self:Peek(playerData.UnitData and playerData.UnitData[id])
        if type(unit) == "table" then
            local level, worthiness = self:GetTrainingProjection(unit, self:Peek(assignedAt), upgradeInfo)
            local asset = tostring(self:Peek(unit.Asset) or "Unknown")
            local displayName = asset
            pcall(function() displayName = Dependencies.Information:GetAssetDisplayName(asset) or asset end)
            local potentialPercent = math.floor(worthiness / math.max(1, Dependencies.Information.StatPotential.MaxWorthiness) * 4000 + 0.5) / 10
            table.insert(lines, string.format("%s [%s]: Lv.%d/%d | Potential %.1f%%/400%%", displayName, self:GetTrainingUnitRarity(unit), level, Dependencies.Information.UnitLevelInfo.MaxLevel, potentialPercent))
        else
            table.insert(lines, string.format(localizeText("Unit %s: đang chờ dữ liệu..."), tostring(id)))
        end
    end
    if count == 0 then table.insert(lines, "Chưa có Unit trong Training Grounds.") end
    safeSetParagraphDesc(self.TrainingParagraph, table.concat(lines, "\n"))
end
getgenv().AnimeExpeditionsCoordinator.TrainingRotationNeeded = function(self)
    if not appConfig.ExpeditionAuto.autoTraining then return false end
    if self.UtilityPending and (self.UtilityPending.Type == "TrainingRemove" or self.UtilityPending.Type == "TrainingSend") then return true end
    self.UtilitySkipped = self.UtilitySkipped or {}
    local playerData = self:GetPlayerData()
    local expeditionData = playerData and self:Peek(playerData.ExpeditionData)
    local buildings = type(expeditionData) == "table" and self:Peek(expeditionData.Buildings) or nil
    local training = type(buildings) == "table" and self:Peek(buildings.TrainingGrounds) or nil
    local assigned = type(training) == "table" and self:Peek(training.Units) or nil
    local upgradeLevel = type(training) == "table" and tonumber(self:Peek(training.Upgrade)) or 0
    local upgradeInfo
    pcall(function() upgradeInfo = Dependencies.Information.Expeditions:GetBuildingUpgrade("TrainingGrounds", upgradeLevel) end)
    if type(assigned) ~= "table" or type(upgradeInfo) ~= "table" then return false end
    local assignedCount = 0
    for id, assignedAt in pairs(assigned) do
        assignedCount += 1
        local unit = self:Peek(playerData.UnitData and playerData.UnitData[id])
        if type(unit) == "table" then
            local level, worthiness = self:GetTrainingProjection(unit, self:Peek(assignedAt), upgradeInfo)
            if self:TrainingCompleted(level, worthiness) and not self.UtilitySkipped["TrainingRemove:" .. tostring(id)] then return true end
        end
    end
    if assignedCount >= self:GetTrainingCapacity(training, upgradeInfo) then return false end
    for id, rawUnit in pairs(playerData.UnitData or {}) do
        local unit = self:Peek(rawUnit)
        local trait = type(unit) == "table" and self:Peek(unit.Trait) or nil
        local filter = appConfig.ExpeditionAuto.trainingTraitFilter
        local filterMatches = filter == "All" or (filter == "Has Trait" and trait ~= nil and trait ~= "") or (filter == "No Trait" and (trait == nil or trait == ""))
        if type(unit) == "table" and (tonumber(self:Peek(unit.Level)) or 0) == 1 and filterMatches and self:TrainingRarityMatches(unit)
            and not self:Peek(unit.Locked) and not self:Peek(unit.Favorited) and not self:Peek(unit.Equipped) and not self:Peek(unit.InTrainingGrounds)
            and not self.UtilitySkipped["TrainingSend:" .. tostring(id)] then
            return true
        end
    end
    return false
end
getgenv().AnimeExpeditionsCoordinator.RefreshTrainingOptions = function(self)
    local playerData = self:GetPlayerData()
    local values, labels, ids = {}, {}, {}
    local selectedSet = {}
    for _, id in ipairs(appConfig.ExpeditionAuto.trainingUnitIds or {}) do selectedSet[tostring(id)] = true end
    for id, rawUnit in pairs(playerData and playerData.UnitData or {}) do
        local unit = self:Peek(rawUnit)
        local trait = type(unit) == "table" and self:Peek(unit.Trait) or nil
        local level = type(unit) == "table" and tonumber(self:Peek(unit.Level)) or 0
        local filter = appConfig.ExpeditionAuto.trainingTraitFilter
        local filterMatches = filter == "All" or (filter == "Has Trait" and trait ~= nil and trait ~= "") or (filter == "No Trait" and (trait == nil or trait == ""))
        if type(unit) == "table" and level == 1 and filterMatches and self:TrainingRarityMatches(unit)
            and not self:Peek(unit.Locked) and not self:Peek(unit.Favorited) and not self:Peek(unit.Equipped)
            and (not self:Peek(unit.InTrainingGrounds) or selectedSet[tostring(id)]) then
            local asset = tostring(self:Peek(unit.Asset) or "Unknown")
            local rarity = self:GetTrainingUnitRarity(unit)
            local displayName = asset
            pcall(function() displayName = Dependencies.Information:GetAssetDisplayName(asset) or asset end)
            local shortId = tostring(id):match("#(.+)") or tostring(id)
            shortId = shortId:sub(1, 8)
            local label = string.format("%s | %s | Lv.1 | %s | %s", displayName, rarity, trait and tostring(trait) or "No Trait", shortId)
            table.insert(values, label)
            labels[label] = tostring(id)
            ids[tostring(id)] = label
        end
    end
    table.sort(values)
    self.UnitLabelToId = labels
    self.UnitIdToLabel = ids
    if self.TrainingDropdown then
        local selectedLabels = {}
        for _, id in ipairs(appConfig.ExpeditionAuto.trainingUnitIds or {}) do
            local label = ids[tostring(id)]
            if label then selectedLabels[label] = true end
        end
        self.RefreshingTrainingDropdown = true
        local ok, err = pcall(function()
            self.TrainingDropdown:SetValues(values)
            self.TrainingDropdown:SetValue(selectedLabels)
        end)
        self.RefreshingTrainingDropdown = false
        if not ok and tick() - (self.LastTrainingDropdownErrorAt or 0) >= 10 then
            self.LastTrainingDropdownErrorAt = tick()
            warn("[TRAINING UI] Dropdown refresh skipped: " .. tostring(err))
        end
    end
    return values, ids
end
getgenv().AnimeExpeditionsCoordinator.StatRollContains = function(self, values, option)
    for key, value in pairs(type(values) == "table" and values or {}) do
        if tostring(type(key) == "number" and value or (value and key or "")) == tostring(option) then return true end
    end
    return false
end
getgenv().AnimeExpeditionsCoordinator.GetStatRollGrade = function(self, unit, stat)
    local potentials = type(unit) == "table" and self:Peek(unit.StatPotential) or nil
    local potential = type(potentials) == "table" and self:Peek(potentials[stat]) or nil
    return type(potential) == "table" and tostring(self:Peek(potential.Potential) or "?") or "?"
end
getgenv().AnimeExpeditionsCoordinator.GetStatRollResources = function(self, playerData)
    local result = {}
    for _, asset in ipairs({"StatReroll", "StatLock"}) do
        local item = playerData and playerData.ItemData and self:Peek(playerData.ItemData[asset])
        result[asset] = math.max(0, math.floor(type(item) == "table" and (tonumber(self:Peek(item.Amount)) or 0) or (tonumber(item) or 0)))
    end
    return result
end
getgenv().AnimeExpeditionsCoordinator.FindStatRollCandidate = function(self, playerData)
    local config = appConfig.AutoStatRoll
    if not config or #config.Rarities == 0 or #config.Stats == 0 or #config.Grades == 0 then return nil end
    local ids = {}
    for id in pairs(playerData and playerData.UnitData or {}) do table.insert(ids, tostring(id)) end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local unit = self:Peek(playerData.UnitData[id])
        local worthiness = type(unit) == "table" and tonumber(self:Peek(unit.Worthiness)) or -1
        local protected = type(unit) ~= "table" or self:Peek(unit.Locked) or self:Peek(unit.Equipped) or self:Peek(unit.Favorited) or self:Peek(unit.InTrainingGrounds)
        local hasHighStat = false
        if type(unit) == "table" then
            for _, stat in ipairs({"Damage", "SPA", "Range"}) do
                local grade = self:GetStatRollGrade(unit, stat)
                if grade == "Z" or grade == "SSS" then hasHighStat = true break end
            end
        end
        if not protected and not hasHighStat and worthiness == Dependencies.Information.StatPotential.MaxWorthiness
            and self:StatRollContains(config.Rarities, self:GetTrainingUnitRarity(unit)) then
            return id, unit
        end
    end
    return nil
end
getgenv().AnimeExpeditionsCoordinator.StopStatRollSession = function(self, message, unit)
    local maintenance = self:GetMaintenance()
    local session = maintenance.StatRoll
    maintenance.StatRoll = {
        LastMessage = tostring(message),
        LastUnitId = session.ActiveUnitId,
        LastAsset = type(unit) == "table" and tostring(self:Peek(unit.Asset) or "Unknown") or session.Asset,
        LastAt = os.time(),
    }
    self.StatRollPending = nil
    saveConfig()
    self:SetStatus("Auto Stat Roll: " .. tostring(message))
    self:UpdateStatRollDisplay(true)
end
getgenv().AnimeExpeditionsCoordinator.UpdateStatRollDisplay = function(self, force)
    if not force and tick() - (self.LastStatRollDisplayAt or 0) < 1 then return end
    self.LastStatRollDisplayAt = tick()
    if not self.StatRollParagraph then return end
    local playerData = self:GetPlayerData()
    local resources = self:GetStatRollResources(playerData)
    local session = self:GetMaintenance().StatRoll
    local id = session.ActiveUnitId
    local unit = id and playerData and self:Peek(playerData.UnitData and playerData.UnitData[id]) or nil
    local state = session.State or (appConfig.AutoStatRoll.Enabled and "Đang chờ Unit 400%" or "Đã tắt")
    if not id and appConfig.AutoStatRoll.Enabled then
        id, unit = self:FindStatRollCandidate(playerData)
        if id then state = resources.StatReroll >= 4 and resources.StatLock >= 8 and "Sẵn sàng" or "Thiếu tài nguyên tối thiểu" end
    end
    local asset, rarity, worthiness = "-", "-", 0
    if type(unit) == "table" then
        asset = tostring(self:Peek(unit.Asset) or "Unknown")
        pcall(function() asset = tostring(Dependencies.Information:GetAssetDisplayName(asset) or asset) end)
        rarity = self:GetTrainingUnitRarity(unit)
        worthiness = tonumber(self:Peek(unit.Worthiness)) or 0
    end
    local potentialPercent = math.floor(worthiness / math.max(1, Dependencies.Information.StatPotential.WorthinessPerRoll) * 100 + 0.5)
    local nextLocks = 0
    if type(unit) == "table" and session.ActiveUnitId then
        for _, stat in ipairs({"Damage", "SPA", "Range"}) do
            if self:StatRollContains(session.TargetStats, stat) and self:StatRollContains(session.TargetGrades, self:GetStatRollGrade(unit, stat)) then nextLocks += 1 end
        end
    end
    local lines = {
        string.format(localizeText("Trạng thái : %s"), localizeText(state)),
        string.format("Unit       : %s%s", asset, id and " | " .. tostring(id):sub(-8) or ""),
        string.format("Rarity     : %s", rarity),
        string.format("Potential  : %d%% | Roll %d/4", potentialPercent, tonumber(session.ConfirmedRolls) or 0),
        string.format("Stats      : Damage %s | SPA %s | Range %s", self:GetStatRollGrade(unit, "Damage"), self:GetStatRollGrade(unit, "SPA"), self:GetStatRollGrade(unit, "Range")),
        string.format(localizeText("Tài nguyên : StatReroll %d | StatLock %d | Lock kế %d"), resources.StatReroll, resources.StatLock, nextLocks),
        string.format(localizeText("Mục tiêu   : %s -> %s"), table.concat(session.TargetStats or appConfig.AutoStatRoll.Stats, ", "), table.concat(session.TargetGrades or appConfig.AutoStatRoll.Grades, ", ")),
    }
    if session.LastMessage and not session.ActiveUnitId then table.insert(lines, string.format(localizeText("Gần nhất   : %s"), localizeText(tostring(session.LastMessage)))) end
    safeSetParagraphDesc(self.StatRollParagraph, table.concat(lines, "\n"))
end
getgenv().AnimeExpeditionsCoordinator.RunStatRoll = function(self, stateInfo)
    local config = appConfig.AutoStatRoll
    if not config.Enabled or not self:IsLobbyReady(stateInfo) or self:HasMandatory() then return false end
    local playerData = self:GetPlayerData()
    if type(playerData) ~= "table" or type(playerData.UnitData) ~= "table" then return false end
    local maintenance = self:GetMaintenance()
    local session = maintenance.StatRoll
    local resources = self:GetStatRollResources(playerData)
    local id = session.ActiveUnitId
    local unit = id and self:Peek(playerData.UnitData[id]) or nil
    if not id then
        if #config.Rarities == 0 or #config.Stats == 0 or #config.Grades == 0 then return false end
        id, unit = self:FindStatRollCandidate(playerData)
        if not id then return false end
        if resources.StatReroll < 4 or resources.StatLock < 8 then
            return false
        end
        local stats, grades = {}, {}
        for _, stat in ipairs(config.Stats) do table.insert(stats, stat) end
        for _, grade in ipairs(config.Grades) do table.insert(grades, grade) end
        session = {
            ActiveUnitId = id,
            Asset = tostring(self:Peek(unit.Asset) or "Unknown"),
            Rarity = self:GetTrainingUnitRarity(unit),
            TargetStats = stats,
            TargetGrades = grades,
            StartRollAmount = tonumber(self:Peek(unit.StatRollAmount)) or 0,
            ConfirmedRolls = 0,
            Notified = {},
            State = "Đang roll",
            StartedAt = os.time(),
        }
        maintenance.StatRoll = session
        saveConfig()
    end
    unit = self:Peek(playerData.UnitData[id])
    if type(unit) ~= "table" then self:StopStatRollSession("Unit không còn trong UnitData; đã dừng an toàn."); return false end
    if self:Peek(unit.Locked) or self:Peek(unit.Equipped) or self:Peek(unit.Favorited) or self:Peek(unit.InTrainingGrounds) then
        session.State = "Pause: Unit đang Locked/Equipped/Favorited/Training"
        return false
    end
    local pending = session.Pending
    if type(pending) == "table" then
        local currentRollAmount = tonumber(self:Peek(unit.StatRollAmount)) or 0
        if currentRollAmount > (tonumber(pending.BeforeRollAmount) or currentRollAmount) then
            local delta = currentRollAmount - (tonumber(pending.BeforeRollAmount) or currentRollAmount)
            local currentWorthiness = tonumber(self:Peek(unit.Worthiness)) or 0
            local expectedWorthiness = math.max(0, (tonumber(pending.BeforeWorthiness) or 0) - Dependencies.Information.StatPotential.WorthinessPerRoll)
            if delta ~= 1 or currentWorthiness ~= expectedWorthiness then
                session.State = "Uncertain: replica thay đổi ngoài dự kiến"
                saveConfig()
                return false
            end
            session.ConfirmedRolls = (tonumber(session.ConfirmedRolls) or 0) + 1
            session.Pending = nil
            session.State = "Đã xác nhận roll " .. tostring(session.ConfirmedRolls) .. "/4"
            saveConfig()
        elseif os.time() - (tonumber(pending.SentAt) or os.time()) >= 8 then
            session.State = "Uncertain: chưa xác nhận request, không tự gửi lại"
            self:UpdateStatRollDisplay(true)
            return false
        else
            session.State = "Đang chờ server xác nhận"
            return true
        end
    end
    local observedRolls = (tonumber(self:Peek(unit.StatRollAmount)) or 0) - (tonumber(session.StartRollAmount) or 0)
    local expectedWorthiness = Dependencies.Information.StatPotential.MaxWorthiness - (tonumber(session.ConfirmedRolls) or 0) * Dependencies.Information.StatPotential.WorthinessPerRoll
    if observedRolls ~= (tonumber(session.ConfirmedRolls) or 0) or (tonumber(self:Peek(unit.Worthiness)) or 0) ~= expectedWorthiness then
        session.State = "Uncertain: UnitData không khớp journal, đã khóa request"
        saveConfig()
        return false
    end
    session.Notified = type(session.Notified) == "table" and session.Notified or {}
    local lockedStats, lockCount, protectedConflict, notifiedChanged = {}, 0, nil, false
    for _, stat in ipairs({"Damage", "SPA", "Range"}) do
        local grade = self:GetStatRollGrade(unit, stat)
        local targetReached = self:StatRollContains(session.TargetStats, stat) and self:StatRollContains(session.TargetGrades, grade)
        if targetReached then
            lockedStats[stat] = true
            lockCount += 1
            if not session.Notified[stat] then
                session.Notified[stat] = grade
                notifiedChanged = true
                local callback = self.PostStatRollWebhook
                if config.Webhook and type(callback) == "function" then task.spawn(callback, self, id, unit, stat, grade, tonumber(session.ConfirmedRolls) or 0) end
            end
        elseif grade == "Z" or grade == "SSS" then
            protectedConflict = stat .. " " .. grade
        end
    end
    if notifiedChanged then saveConfig() end
    if protectedConflict then self:StopStatRollSession("Giữ " .. protectedConflict .. " ngoài mục tiêu; đã dừng unit.", unit); return false end
    local worthiness = tonumber(self:Peek(unit.Worthiness)) or 0
    if (tonumber(session.ConfirmedRolls) or 0) >= 4 or worthiness < Dependencies.Information.StatPotential.WorthinessPerRoll then
        self:StopStatRollSession("Đã hoàn thành 4 roll và hết Potential.", unit)
        return false
    end
    if lockCount >= 3 then self:StopStatRollSession("Cả 3 stat đã đạt; dừng vì game không cho lock cả 3.", unit); return false end
    if resources.StatReroll < 1 or resources.StatLock < lockCount then
        session.State = string.format("Pause: cần 1 StatReroll và %d StatLock", lockCount)
        return false
    end
    if tick() - (self.StatRollLastActionAt or 0) < 1 then return true end
    session.Pending = {
        BeforeRollAmount = tonumber(self:Peek(unit.StatRollAmount)) or 0,
        BeforeWorthiness = worthiness,
        SentAt = os.time(),
    }
    session.State = string.format("Đang gửi roll %d/4 | lock %d stat", (tonumber(session.ConfirmedRolls) or 0) + 1, lockCount)
    saveConfig()
    self.StatRollLastActionAt = tick()
    local ok, err = pcall(function() Actions.RerollStatPotential(id, lockedStats, true) end)
    if not ok then
        session.State = "Uncertain: request lỗi, không tự gửi lại"
        warn("[AUTO STAT ROLL] Request failed: " .. tostring(err))
        saveConfig()
        return false
    end
    self:SetStatus(session.State)
    self:UpdateStatRollDisplay(true)
    return true
end
getgenv().AnimeExpeditionsCoordinator.CheckUtilityPending = function(self)
    local pending = self.UtilityPending
    if not pending then return false end
    local playerData = self:GetPlayerData()
    local expeditionData = playerData and self:Peek(playerData.ExpeditionData)
    local buildings = type(expeditionData) == "table" and self:Peek(expeditionData.Buildings) or nil
    local training = type(buildings) == "table" and self:Peek(buildings.TrainingGrounds) or nil
    local assigned = type(training) == "table" and self:Peek(training.Units) or nil
    local upgrades = type(expeditionData) == "table" and self:Peek(expeditionData.Upgrades) or nil
    local confirmed = (pending.Type == "TrainingRemove" and type(assigned) == "table" and assigned[pending.Id] == nil)
        or (pending.Type == "TrainingSend" and type(assigned) == "table" and assigned[pending.Id] ~= nil)
        or (pending.Type == "Skill" and type(upgrades) == "table" and self:Peek(upgrades[pending.TargetKey]) == true)
    if confirmed then
        if pending.Type == "TrainingRemove" then
            local remaining = {}
            for _, id in ipairs(appConfig.ExpeditionAuto.trainingUnitIds or {}) do if tostring(id) ~= pending.Id then table.insert(remaining, id) end end
            appConfig.ExpeditionAuto.trainingUnitIds = remaining
            saveConfig()
            self:RefreshTrainingOptions()
        end
        self.UtilityPending = nil
        return false
    end
    if tick() - pending.SentAt >= 2 then
        warn("[EXP LOBBY] Utility action was not confirmed: " .. tostring(pending.Type))
        self.UtilitySkipped = self.UtilitySkipped or {}
        self.UtilitySkipped[pending.Key] = true
        self.UtilityPending = nil
        return false
    end
    return true
end
getgenv().AnimeExpeditionsCoordinator.RunLobbyUtility = function(self, stateInfo)
    if not self:IsLobbyReady(stateInfo) or self:HasMandatory() then return false end
    self.UtilitySkipped = self.UtilitySkipped or {}
    if self:CheckUtilityPending() then return true end
    if tick() - self.UtilityLastActionAt < 0.25 then return self:TrainingRotationNeeded() end
    local playerData = self:GetPlayerData()
    local expeditionData = playerData and self:Peek(playerData.ExpeditionData)
    local buildings = type(expeditionData) == "table" and self:Peek(expeditionData.Buildings) or {}
    if appConfig.ExpeditionAuto.autoTraining and type(buildings) == "table" then
        local training = self:Peek(buildings.TrainingGrounds)
        local assigned = type(training) == "table" and self:Peek(training.Units) or {}
        local upgradeLevel = type(training) == "table" and tonumber(self:Peek(training.Upgrade)) or 0
        local upgradeInfo
        pcall(function() upgradeInfo = Dependencies.Information.Expeditions:GetBuildingUpgrade("TrainingGrounds", upgradeLevel) end)
        if type(assigned) == "table" and type(upgradeInfo) == "table" then
            for id, assignedAt in pairs(assigned) do
                local unit = self:Peek(playerData.UnitData and playerData.UnitData[id])
                if type(unit) == "table" then
                    local level, worthiness = self:GetTrainingProjection(unit, self:Peek(assignedAt), upgradeInfo)
                    local utilityKey = "TrainingRemove:" .. tostring(id)
                    if self:TrainingCompleted(level, worthiness) and not self.UtilitySkipped[utilityKey] then
                        self.UtilityLastActionAt = tick()
                        local ok, err = pcall(function() Actions.ExpeditionBuilding_RemoveUnit(id) end)
                        if ok then
                            self.UtilityPending = {Type = "TrainingRemove", Key = utilityKey, Id = tostring(id), SentAt = tick()}
                            self:SetStatus("Retrieving completed Training unit: " .. tostring(id))
                            return true
                        end
                        self.UtilitySkipped[utilityKey] = true
                        warn("[EXP LOBBY] Training remove failed; skipping this Lobby cycle: " .. tostring(err))
                    end
                end
            end
            local count = 0
            for _ in pairs(assigned) do count += 1 end
            if count < self:GetTrainingCapacity(training, upgradeInfo) then
                local candidateIds, seenIds, fallbackIds = {}, {}, {}
                for _, id in ipairs(appConfig.ExpeditionAuto.trainingUnitIds or {}) do
                    id = tostring(id)
                    if not seenIds[id] then seenIds[id] = true; table.insert(candidateIds, id) end
                end
                for id in pairs(playerData.UnitData or {}) do
                    id = tostring(id)
                    if not seenIds[id] then table.insert(fallbackIds, id) end
                end
                table.sort(fallbackIds)
                for _, id in ipairs(fallbackIds) do table.insert(candidateIds, id) end
                for _, id in ipairs(candidateIds) do
                    local unit = self:Peek(playerData.UnitData and playerData.UnitData[id])
                    local trait = type(unit) == "table" and self:Peek(unit.Trait) or nil
                    local level = type(unit) == "table" and tonumber(self:Peek(unit.Level)) or 0
                    local filter = appConfig.ExpeditionAuto.trainingTraitFilter
                    local filterMatches = filter == "All" or (filter == "Has Trait" and trait ~= nil and trait ~= "") or (filter == "No Trait" and (trait == nil or trait == ""))
                    local utilityKey = "TrainingSend:" .. tostring(id)
                    if type(unit) == "table" and level == 1 and assigned[id] == nil and filterMatches and self:TrainingRarityMatches(unit) and not self:Peek(unit.Locked)
                        and not self:Peek(unit.Favorited) and not self:Peek(unit.Equipped) and not self:Peek(unit.InTrainingGrounds) and not self.UtilitySkipped[utilityKey] then
                        self.UtilityLastActionAt = tick()
                        local ok, err = pcall(function() Actions.ExpeditionBuilding_SendUnit(id) end)
                        if ok then
                            self.UtilityPending = {Type = "TrainingSend", Key = utilityKey, Id = id, SentAt = tick()}
                            self:SetStatus("Sending Level 1 Training unit: " .. id)
                            return true
                        end
                        self.UtilitySkipped[utilityKey] = true
                        warn("[EXP LOBBY] Training send failed; skipping this Lobby cycle: " .. tostring(err))
                    end
                end
                self:SetStatus("Không còn Unit Level 1 thuộc rarity đã chọn; bỏ qua Training và mở khóa Join.")
            end
        end
    end
    if appConfig.ExpeditionAuto.autoSkillTree and type(expeditionData) == "table" and type(buildings) == "table" then
        local research = self:Peek(buildings.ResearchLab)
        local labLevel = type(research) == "table" and tonumber(self:Peek(research.Upgrade)) or 0
        local owned = self:Peek(expeditionData.Upgrades)
        local tree = Dependencies.Information.Expeditions.Buildings.ResearchLab.Tree
        local layout = tree:GetLayout()
        local nodes = {}
        for _, node in pairs(layout or {}) do table.insert(nodes, node) end
        table.sort(nodes, function(left, right)
            if tonumber(left.R) == tonumber(right.R) then return tonumber(left.Q) < tonumber(right.Q) end
            return tonumber(left.R) < tonumber(right.R)
        end)
        for _, node in ipairs(nodes) do
            local key = tree:GetNextUpgradeKey(type(owned) == "table" and owned or {}, node.Upgrade)
            if key then
                local unlockable = tree:CanUnlock(type(owned) == "table" and owned or {}, key, labLevel)
                local info = tree.UpgradeInfo[key]
                local affordable = unlockable == true
                for _, requirement in ipairs(type(info) == "table" and info.Requirements or {}) do
                    local item = self:Peek(playerData.ItemData and playerData.ItemData[requirement.Asset])
                    local amount = type(item) == "table" and tonumber(self:Peek(item.Amount)) or tonumber(item) or 0
                    if amount < (tonumber(requirement.Amount) or 0) then affordable = false break end
                end
                if affordable then
                    local utilityKey = "Skill:" .. tostring(key)
                    if not self.UtilitySkipped[utilityKey] then
                        self.UtilityLastActionAt = tick()
                        local ok, err = pcall(function() Actions.ExpeditionUnlockUpgrade(key) end)
                        if ok then
                            self.UtilityPending = {Type = "Skill", Key = utilityKey, TargetKey = key, SentAt = tick()}
                            self:SetStatus("Unlocking Research node: " .. tostring(key))
                            return true
                        end
                        self.UtilitySkipped[utilityKey] = true
                        warn("[EXP LOBBY] Skill unlock failed; skipping this Lobby cycle: " .. tostring(err))
                    end
                end
            end
        end
    end
    return false
end
getgenv().AnimeExpeditionsCoordinator.GetCraftableRecipe = function(self, asset, station, skipped)
    local crafting = self:Peek(Dependencies.Crafting)
    local recipesByStation = type(crafting) == "table" and self:Peek(crafting.Recipes) or nil
    local stationRecipes = type(recipesByStation) == "table" and self:Peek(recipesByStation[station]) or nil
    local recipes = type(stationRecipes) == "table" and self:Peek(stationRecipes[asset]) or nil
    local items = snapshotItemData()
    for index, rawRecipe in pairs(type(recipes) == "table" and recipes or {}) do
        local recipe = self:Peek(rawRecipe)
        local craftable = math.huge
        for _, rawRequirement in ipairs(type(recipe) == "table" and recipe.Requirements or {}) do
            local requirement = self:Peek(rawRequirement)
            local needed = type(requirement) == "table" and tonumber(self:Peek(requirement.Amount)) or nil
            local requirementAsset = type(requirement) == "table" and tostring(self:Peek(requirement.Asset) or "") or ""
            if needed and needed > 0 then craftable = math.min(craftable, math.floor((items[requirementAsset] or 0) / needed)) end
        end
        local key = station .. ":" .. tostring(asset) .. ":" .. tostring(index)
        if craftable ~= math.huge and craftable > 0 and not (skipped and skipped[key]) then return tonumber(index) or index, craftable, recipe end
    end
    return nil
end
getgenv().AnimeExpeditionsCoordinator.RunCraftPreparation = function(self, stateInfo)
    if not self:IsLobbyReady(stateInfo) then return false end
    self.CraftSkipped = self.CraftSkipped or {}
    local normalEnabled = appConfig.autoCraftEnabled and type(appConfig.autoCraftItems) == "table" and #appConfig.autoCraftItems > 0
    local expeditionEnabled = appConfig.autoExpeditionCraftEnabled and type(appConfig.autoExpeditionCraftItems) == "table" and #appConfig.autoExpeditionCraftItems > 0
    if not normalEnabled and not expeditionEnabled then self.CraftPending = nil; return false end
    if self.CraftPending and ((self.CraftPending.Station == "Crafting" and not normalEnabled) or (self.CraftPending.Station == "Armory Forge" and not expeditionEnabled)) then
        self.CraftPending = nil
    end
    local playerData = self:GetPlayerData()
    local itemData = playerData and self:Peek(playerData.ItemData)
    if type(itemData) ~= "table" then
        self.CraftDataWaitAt = self.CraftDataWaitAt or tick()
        if tick() - self.CraftDataWaitAt < 2 then return true end
        self.CraftPending = nil
        return false
    end
    self.CraftDataWaitAt = nil
    local pending = self.CraftPending
    if pending then
        local items = snapshotItemData()
        local changed = (items[pending.Asset] or 0) > pending.BeforeOutput
        for requirementAsset, beforeAmount in pairs(pending.BeforeRequirements) do
            if (items[requirementAsset] or 0) < beforeAmount then changed = true break end
        end
        if changed then
            print("[LOBBY CRAFT] Confirmed: " .. pending.Key)
            self.CraftPending = nil
        elseif tick() - pending.SentAt < 2 then
            return true
        else
            self.CraftSkipped[pending.Key] = true
            self.CraftPending = nil
            warn("[LOBBY CRAFT] Server did not accept " .. pending.Key .. "; skipping this Lobby cycle")
        end
    end
    local groups = {
        {Enabled = normalEnabled, Assets = appConfig.autoCraftItems, Station = "Crafting"},
        {Enabled = expeditionEnabled, Assets = appConfig.autoExpeditionCraftItems, Station = "Armory Forge"},
    }
    for _, group in ipairs(groups) do
        if group.Enabled then
            for _, asset in ipairs(type(group.Assets) == "table" and group.Assets or {}) do
                asset = tostring(asset)
                local index, craftable, recipe = self:GetCraftableRecipe(asset, group.Station, self.CraftSkipped)
                local key = group.Station .. ":" .. asset .. ":" .. tostring(index)
                if index and not self.CraftSkipped[key] then
                    local amount = math.max(1, math.min(math.floor(craftable), 5))
                    local beforeItems = snapshotItemData()
                    local beforeRequirements = {}
                    for _, rawRequirement in ipairs(recipe.Requirements or {}) do
                        local requirement = self:Peek(rawRequirement)
                        local requirementAsset = tostring(self:Peek(requirement.Asset) or "")
                        beforeRequirements[requirementAsset] = beforeItems[requirementAsset] or 0
                    end
                    local ok, err = pcall(function() Actions.CraftRecipe(asset, index, amount) end)
                    if ok then
                        self.CraftPending = {Key = key, Asset = asset, Station = group.Station, BeforeOutput = beforeItems[asset] or 0, BeforeRequirements = beforeRequirements, SentAt = tick()}
                        self:SetStatus(string.format("Crafting %dx %s before Join", amount, asset))
                        return true
                    end
                    self.CraftSkipped[key] = true
                    warn("[LOBBY CRAFT] Request failed for " .. key .. ": " .. tostring(err))
                end
            end
        end
    end
    return false
end
local function fusionPeek(value)
    local ok, result = pcall(function() return Fusion.peek(value) end)
    return ok and result or value
end
local getRegularChallengeState
local getChallengeMacro
local findAvailableChallenge
local markChallengeSkipped
local challengeRuntime = {
    Status = "Đang chờ dữ liệu Regular Challenge...",
    LastDisplay = "",
    LastJoinAt = 0,
    LastReturnAt = 0,
    FinishedAt = 0,
    NoMacroAttempts = 0,
    NoMacroResetKey = nil,
}
getRegularChallengeState = function(challengeType)
    challengeType = challengeType == "Daily" and "Daily" or "Regular"
    local challengeData = fusionPeek(Fusion.peek(Dependencies.ChallengeData))
    local ok, playerData = pcall(function() return Fusion.peek(Dependencies.PlayerData) end)
    if type(challengeData) ~= "table" or not ok or type(playerData) ~= "table" then
        return {Valid = false, Challenges = {}, Remaining = 0}
    end
    local regularData = fusionPeek(challengeData[challengeType])
    local playerChallengeData = fusionPeek(playerData.ChallengeData)
    playerChallengeData = type(playerChallengeData) == "table" and playerChallengeData or {}
    local clearHistoryData = fusionPeek(playerChallengeData.ClearHistory)
    local dailyHistoryData = fusionPeek(playerChallengeData.DailyClearHistory)
    local clearHistory = type(clearHistoryData) == "table" and fusionPeek(clearHistoryData[challengeType]) or {}
    local dailyHistory = type(dailyHistoryData) == "table" and fusionPeek(dailyHistoryData[challengeType]) or {}
    clearHistory = type(clearHistory) == "table" and clearHistory or {}
    dailyHistory = type(dailyHistory) == "table" and dailyHistory or {}
    if type(regularData) ~= "table" then return {Valid = false, Challenges = {}, Remaining = 0} end

    local now = os.time()
    local result = {
        Valid = true,
        Challenges = {},
        ResetKey = challengeType .. ":" .. ChallengeInfo:GetResetKey(now, challengeType),
        Remaining = tonumber(ChallengeInfo:GetRemainingTimeFromType(challengeType)) or 0,
        ChallengeType = challengeType,
    }
    for index, challengeState in pairs(regularData) do
        local data = fusionPeek(challengeState)
        data = type(data) == "table" and data or {}
        local challengeIndex = tonumber(index) or tonumber(fusionPeek(data.Index))
        if challengeIndex then
            local available, reason = false, "Data"
            local availabilityOk, availabilityResult, availabilityReason = pcall(function()
                return ChallengeInfo:IsChallengeAvailable(clearHistory, dailyHistory, challengeType, challengeIndex, now)
            end)
            if availabilityOk then
                available = availabilityResult == true
                reason = availabilityReason
            end
            local attemptsLeft = 0
            local attemptsOk, attemptsResult = pcall(function()
                return ChallengeInfo:GetDailyAttemptsLeft(dailyHistory, challengeType, challengeIndex, now)
            end)
            if attemptsOk then attemptsLeft = tonumber(attemptsResult) or 0 end
            table.insert(result.Challenges, {
                Index = challengeIndex,
                ChallengeType = challengeType,
                Map = tostring(fusionPeek(data.MapName) or ""),
                Act = tostring(fusionPeek(data.ActName) or ""),
                Difficulty = tostring(fusionPeek(data.Difficulty) or "Hard"),
                Available = available,
                Reason = reason,
                AttemptsLeft = attemptsLeft,
            })
        end
    end
    table.sort(result.Challenges, function(left, right) return left.Index < right.Index end)
    return result
end
local function syncChallengeSkippedSlots(resetKey)
    if tostring(appConfig.challengeSkippedSlots.ResetKey) ~= tostring(resetKey) then
        appConfig.challengeSkippedSlots = {ResetKey = tostring(resetKey or ""), Slots = {}}
        saveConfig()
    end
end
local function challengeSlotIsSkipped(resetKey, challengeIndex)
    syncChallengeSkippedSlots(resetKey)
    local value = appConfig.challengeSkippedSlots.Slots[tostring(challengeIndex)]
    return value ~= nil and value ~= false
end
local function challengeSlotSkipReason(resetKey, challengeIndex)
    syncChallengeSkippedSlots(resetKey)
    return appConfig.challengeSkippedSlots.Slots[tostring(challengeIndex)]
end
local function clearChallengeSkipped(resetKey, challengeIndex)
    syncChallengeSkippedSlots(resetKey)
    appConfig.challengeSkippedSlots.Slots[tostring(challengeIndex)] = nil
    saveConfig()
end
markChallengeSkipped = function(resetKey, challengeIndex, reason)
    syncChallengeSkippedSlots(resetKey)
    appConfig.challengeSkippedSlots.Slots[tostring(challengeIndex)] = reason or true
    saveConfig()
end
local function formatChallengeTime(seconds)
    local value = math.max(0, math.floor(tonumber(seconds) or 0))
    return string.format("%02d:%02d", math.floor(value / 60), value % 60)
end
local function setChallengeStatus(status)
    challengeRuntime.Status = tostring(status or "")
end
local function updateChallengeDisplay(challengeState)
    local lines = {challengeRuntime.Status}
    if challengeState.Valid then
        for _, challenge in ipairs(challengeState.Challenges) do
            local availability
            local skipReason = challengeSlotSkipReason(challengeState.ResetKey, challenge.Index)
            if skipReason == "Completed" and tonumber(challengeState.Remaining) and challengeState.Remaining > 0 then
                availability = "Đã xong | Mở lại sau " .. formatChallengeTime(challengeState.Remaining)
            elseif skipReason then
                availability = "Đã skip: " .. (skipReason == true and "Legacy" or tostring(skipReason))
            elseif challenge.Available then
                availability = "Sẵn sàng"
            elseif challenge.Reason == "DailyLimit" then
                availability = "Hết lượt ngày"
            elseif tostring(challenge.Reason or ""):lower():find("cooldown", 1, true) then
                availability = "Cooldown " .. formatChallengeTime(challengeState.Remaining)
            else
                availability = "Không khả dụng: " .. tostring(challenge.Reason or "GameData")
            end
            table.insert(lines, string.format(
                "#%d %s - %s - %s | %s | lượt: %d",
                challenge.Index,
                challenge.Map,
                challenge.Act,
                challenge.Difficulty,
                availability,
                challenge.AttemptsLeft
            ))
        end
    end
    local description = table.concat(lines, "\n")
    if description ~= challengeRuntime.LastDisplay then
        challengeRuntime.LastDisplay = description
        safeSetParagraphDesc(challengeStatusPara, description)
    end
end
local function getChallengeByIndex(challengeState, challengeIndex)
    for _, challenge in ipairs(challengeState.Challenges or {}) do
        if tonumber(challenge.Index) == tonumber(challengeIndex) then return challenge end
    end
    return nil
end
getChallengeMacro = function(mapName)
    local requestedKey = appConfig.challengeMapMacros[tostring(mapName)]
    if not requestedKey or requestedKey == "" then return nil end
    local macroList, matchedKey = getMacroListForStage(requestedKey)
    if type(macroList) ~= "table" or #macroList == 0 then return nil end
    return matchedKey
end
findAvailableChallenge = function(challengeState, scanAll, selectedSlots)
    local missingMacros = {}
    for _, challenge in ipairs(challengeState.Challenges or {}) do
        if challenge.Available and challenge.AttemptsLeft > 0 and getChallengeMacro(challenge.Map) then
            local skipReason = challengeSlotSkipReason(challengeState.ResetKey, challenge.Index)
            if skipReason == "MissingMacro" or skipReason == true then
                clearChallengeSkipped(challengeState.ResetKey, challenge.Index)
                Fluent:Notify({Title = "Challenge Macro Found", Content = string.format(localizeText("Đã xóa skip cho #%s %s."), challenge.Index, challenge.Map), Duration = 4})
            end
        end
    end
    for _, challenge in ipairs(challengeState.Challenges or {}) do
        if challenge.Available and challenge.AttemptsLeft > 0
            and (not selectedSlots or selectedSlots[tostring(challenge.Index)] == true) then
            local macroKey = getChallengeMacro(challenge.Map)
            local skipReason = challengeSlotSkipReason(challengeState.ResetKey, challenge.Index)
            if not skipReason then
                if macroKey then return challenge, macroKey, missingMacros end
                table.insert(missingMacros, {Index = challenge.Index, Map = challenge.Map})
                if not scanAll then break end
            end
        end
    end
    return nil, nil, missingMacros
end
local function challengeJoinValue(target)
    return table.concat({"Challenge", tostring(target.ChallengeType or "Regular"), tostring(target.Index)}, "|")
end
local function requestChallengeLobby(reason)
    setChallengeStatus(reason .. " Đang chọn map tiếp theo...")
    if tick() - challengeRuntime.LastReturnAt < 5 then return end
    local coordinator = getgenv().AnimeExpeditionsCoordinator
    local stateInfo = getGameStates()
    if coordinator and stateInfo and stateInfo.CurrentGameState ~= "Lobby" and coordinator:BeginMapSwitchResolution("Challenge", reason, stateInfo) then
        challengeRuntime.LastReturnAt = tick()
    elseif coordinator and coordinator:RequestLobby("Challenge", reason, stateInfo) then
        challengeRuntime.LastReturnAt = tick()
    elseif not coordinator then
        challengeRuntime.LastReturnAt = tick()
        pcall(function() safeFireGameAction("Lobby") end)
    end
end
local function runChallengeLobbyTick(challengeState)
    local directive = {BlockNormalJoin = true, JoinValue = nil}
    if not challengeState.Valid then
        setChallengeStatus("Đang chờ dữ liệu " .. tostring(challengeState.ChallengeType or "Challenge") .. " Challenge...")
        directive.BlockNormalJoin = false
        return directive
    end
    if tostring(challengeRuntime.NoMacroResetKey) ~= tostring(challengeState.ResetKey) then
        challengeRuntime.NoMacroResetKey = challengeState.ResetKey
        challengeRuntime.NoMacroAttempts = 0
    end
    local target = appConfig.challengeActiveTarget
    if type(target) == "table" then
        local current = getChallengeByIndex(challengeState, target.Index)
        local targetSkipped = challengeSlotIsSkipped(challengeState.ResetKey, target.Index)
            or challengeState.ChallengeType == "Regular" and target.Owner == "Challenge"
                and appConfig.challengeAutoSelectedSlots[tostring(target.Index)] ~= true
        local joinLock = getgenv().AnimeExpeditionsJoinLock
        local targetJoinValue = challengeJoinValue(target)
        if type(joinLock) == "table" and joinLock.Owner == "Challenge" and joinLock.JoinValue == targetJoinValue then
            setChallengeStatus(string.format("Đang vào %s Challenge #%d: %s.", tostring(target.ChallengeType or "Regular"), target.Index, target.Map))
            return directive
        end
        if not targetSkipped and tostring(target.ResetKey) == tostring(challengeState.ResetKey) and current and current.Available then
            if challengeRuntime.LastReturnAt > 0 and tick() - challengeRuntime.LastReturnAt < 5 then
                setChallengeStatus("Đang chờ server cập nhật kết quả " .. tostring(target.ChallengeType or "Regular") .. " Challenge...")
                return directive
            end
            setChallengeStatus(string.format("Đang retry %s Challenge #%d: %s.", tostring(target.ChallengeType or "Regular"), target.Index, target.Map))
            if tick() - challengeRuntime.LastJoinAt >= 5 then directive.JoinValue = targetJoinValue end
            return directive
        end
        appConfig.challengeActiveTarget = nil
        saveConfig()
    end

    local selectedSlots = challengeState.ChallengeType == "Regular" and appConfig.challengeAutoSelectedSlots or nil
    local challenge, macroKey, missingMacros = findAvailableChallenge(challengeState, false, selectedSlots)
    if challenge then
        challengeRuntime.NoMacroAttempts = 0
        target = {
            Owner = "Challenge",
            Mode = "Challenge",
        ChallengeType = challenge.ChallengeType or "Regular",
            Index = challenge.Index,
            Map = challenge.Map,
            Act = challenge.Act,
            Difficulty = challenge.Difficulty,
            MacroKey = macroKey,
            ResetKey = challengeState.ResetKey,
        }
        appConfig.challengeActiveTarget = target
        saveConfig()
        setChallengeStatus(string.format("Ưu tiên Regular Challenge #%d: %s %s.", target.Index, target.Map, target.Act))
        if tick() - challengeRuntime.LastJoinAt >= 5 then directive.JoinValue = challengeJoinValue(target) end
        return directive
    end

    local missing = missingMacros[1]
    if missing then
        markChallengeSkipped(challengeState.ResetKey, missing.Index, "MissingMacro")
        setChallengeStatus(string.format("Challenge #%d %s không có Macro. Đã skip và đang đổi slot.", missing.Index, missing.Map))
        Fluent:Notify({Title = "Challenge Missing Macro", Content = string.format(localizeText("#%d %s không có Macro; đã skip slot."), missing.Index, missing.Map), Duration = 5})
        return directive
    end

    directive.BlockNormalJoin = false
    local hasDailyAttempts = false
    local hasUnskippedAttempt = false
    local hasRealCooldown = false
    local hasCompletedSlot = false
    for _, challengeInfo in ipairs(challengeState.Challenges) do
        if challengeInfo.AttemptsLeft > 0 then
            hasDailyAttempts = true
            local skipReason = challengeSlotSkipReason(challengeState.ResetKey, challengeInfo.Index)
            local manualSkip = challengeState.ChallengeType == "Regular" and appConfig.challengeAutoSelectedSlots[tostring(challengeInfo.Index)] ~= true
            if skipReason == "Completed" then hasCompletedSlot = true end
            if not skipReason and not manualSkip then
                hasUnskippedAttempt = true
                if not challengeInfo.Available and tostring(challengeInfo.Reason or ""):lower():find("cooldown", 1, true) then
                    hasRealCooldown = true
                end
            end
        end
    end
    if hasRealCooldown then
        setChallengeStatus("Regular Challenge đang cooldown " .. formatChallengeTime(challengeState.Remaining) .. ". Đang nhường Auto Join Map.")
    elseif hasDailyAttempts and not hasUnskippedAttempt and hasCompletedSlot and challengeState.Remaining > 0 then
        setChallengeStatus("Regular Challenge mở lại sau " .. formatChallengeTime(challengeState.Remaining) .. ". Đang nhường Auto Join Map.")
    elseif hasDailyAttempts and not hasUnskippedAttempt then
        setChallengeStatus("Tất cả Regular Challenge hiện tại đã skip. Đang nhường Auto Join Map.")
    elseif hasDailyAttempts then
        setChallengeStatus("Regular Challenge chưa khả dụng theo dữ liệu game. Đang nhường Auto Join Map.")
    else
        setChallengeStatus("Đã hết lượt Regular Challenge hôm nay. Đang nhường Auto Join Map.")
    end
    return directive
end
local function runChallengeInGameTick(stateInfo, challengeState, canTakePriority)
    local target = appConfig.challengeActiveTarget
    if type(target) == "table" and challengeTargetMatchesState(stateInfo) then
        local macro = target.MacroKey and appConfig.Macros[tostring(target.MacroKey)] or nil
        if type(macro) ~= "table" or #macro == 0 then
            markChallengeSkipped(target.ResetKey, target.Index, "MissingMacro")
            appConfig.challengeActiveTarget = nil
            saveConfig()
            requestChallengeLobby("Challenge không có Macro; đã skip slot #" .. tostring(target.Index) .. ".")
            return
        end
        if QuestAuto:EnsureMacroRestart("Challenge", target, stateInfo) then return end
        local currentState = tostring(stateInfo.CurrentGameState or "")
        local finished = currentState == "Finished" or currentState == "Victory" or currentState == "Defeat"
        local defeated = currentState == "Defeat" or (currentState == "Finished" and tonumber(stateInfo.BaseHealth or 0) <= 0)
        if defeated then
            markChallengeSkipped(target.ResetKey, target.Index, "Defeat")
            appConfig.challengeActiveTarget = nil
            saveConfig()
            requestChallengeLobby("Challenge bị thua; đã skip slot #" .. tostring(target.Index) .. ".")
            return
        end
        if finished then
            if challengeRuntime.FinishedAt == 0 then challengeRuntime.FinishedAt = tick() end
            if tick() - challengeRuntime.FinishedAt >= 3 then
                markChallengeSkipped(target.ResetKey, target.Index, "Completed")
                appConfig.challengeActiveTarget = nil
                saveConfig()
                requestChallengeLobby("Đã kết thúc Regular Challenge #" .. tostring(target.Index) .. "; chọn Challenge khác.")
            end
        else
            challengeRuntime.FinishedAt = 0
            setChallengeStatus(string.format("Đang chạy Regular Challenge #%d: %s %s.", target.Index, target.Map, target.Act))
        end
        return
    end

    challengeRuntime.FinishedAt = 0
    local currentMode = tostring(stateInfo.Gamemode or ""):lower():gsub("[^%w]", "")
    if currentMode:find("challenge", 1, true) or stateInfo.ChallengeIndex ~= nil then
        local currentState = tostring(stateInfo.CurrentGameState or "")
        local challengeFinished = currentState == "Finished" or currentState == "Victory" or currentState == "Defeat"
        local currentChallenge = getChallengeByIndex(challengeState, stateInfo.ChallengeIndex)
        local wave, maxWave = tonumber(stateInfo.Wave) or 0, tonumber(stateInfo.MaxWave) or 0
        if challengeFinished or (currentChallenge and not currentChallenge.Available and maxWave > 0 and wave >= maxWave) then
            requestChallengeLobby("Challenge đã kết thúc; chọn Challenge khác.")
        else
            setChallengeStatus("Đang ở trong Challenge; chờ trận kết thúc rồi đổi trực tiếp.")
        end
        return
    end
    local available = canTakePriority and select(1, findAvailableChallenge(challengeState, false, appConfig.challengeAutoSelectedSlots)) or nil
    if available then
        requestChallengeLobby("Regular Challenge đã sẵn sàng; đổi map trực tiếp.")
    else
        setChallengeStatus("Đang ở trận không thuộc Auto Challenge.")
    end
end
local function runChallengeTick(stateInfo, canTakePriority)
    local challengeState = getRegularChallengeState()
    local directive = {BlockNormalJoin = false, JoinValue = nil}
    local coordinator = getgenv().AnimeExpeditionsCoordinator
    local resolvingMap = coordinator and coordinator.MapSwitch and coordinator.MapSwitch.Phase == "Resolve"
    if not appConfig.autoChallengeEnabled and not appConfig.autoDailyChallengeEnabled then
        setChallengeStatus("Auto Daily / Regular Challenge đang tắt.")
    elseif resolvingMap or not stateInfo or stateInfo.CurrentGameState == "Lobby" then
        local selectedDaily = false
        if canTakePriority and appConfig.autoDailyChallengeEnabled then
            local dailyState = getRegularChallengeState("Daily")
            local dailyTarget, _, missingDailyMacros = findAvailableChallenge(dailyState)
            local activeTarget = appConfig.challengeActiveTarget
            if dailyTarget or (missingDailyMacros and missingDailyMacros[1])
                or (type(activeTarget) == "table" and activeTarget.ChallengeType == "Daily") then
                challengeState = dailyState
                selectedDaily = true
            end
        end
        if canTakePriority and (selectedDaily or appConfig.autoChallengeEnabled) then
            directive = runChallengeLobbyTick(challengeState)
        else
            setChallengeStatus("Daily Challenge đã xong hoặc không khả dụng. Regular Challenge đang tắt.")
        end
    else
        runChallengeInGameTick(stateInfo, challengeState, canTakePriority)
    end
    updateChallengeDisplay(challengeState)
    return directive
end
function QuestAuto:Peek(value)
    local ok, result = pcall(function() return Fusion.peek(value) end)
    return ok and result or value
end
function QuestAuto:Condition(objective, conditionName)
    for _, condition in pairs((objective and objective.Conditions) or {}) do
        if condition.ValueName == conditionName then return condition.Value end
    end
    return nil
end
function QuestAuto:Snapshot()
    local playerData = self:Peek(Dependencies.PlayerData)
    local questData = type(playerData) == "table" and self:Peek(playerData.QuestData) or nil
    local result = {Valid = false, Complete = false, Categories = {}, Quests = {}, ResetKeys = {}, Ready = {}, ReadyCategories = 0}
    if type(questData) ~= "table" then return result end
    for categoryOrder, categoryId in ipairs({"Daily", "Weekly"}) do
        local categoryData = self:Peek(questData[categoryId])
        local rawQuests = type(categoryData) == "table" and self:Peek(categoryData.Quests) or nil
        local resetKey = type(categoryData) == "table" and self:Peek(categoryData.ResetKey) or nil
        if type(rawQuests) == "table" and resetKey ~= nil then
            result.Ready[categoryId] = true
            result.ReadyCategories += 1
            result.ResetKeys[categoryId] = resetKey
            local category = {Id = categoryId, Order = categoryOrder, Quests = {}, Claimed = 0}
            for questId, rawState in pairs(rawQuests) do
                local state = self:Peek(rawState)
                state = type(state) == "table" and state or {}
                local info = ((QuestsInfo.Quests or {})[categoryId] or {})[questId] or {}
                local progress = self:Peek(state.ObjectiveProgress)
                progress = type(progress) == "table" and progress or {}
                local quest = {
                    Category = categoryId,
                    Id = tostring(questId),
                    Name = tostring(info.DisplayName or info.Name or questId),
                    Completed = self:Peek(state.Completed) == true,
                    Claimed = self:Peek(state.Claimed) == true,
                    Objectives = {},
                }
                if quest.Claimed then category.Claimed += 1 end
                for objectiveId, objectiveInfo in pairs(info.Objectives or {}) do
                    table.insert(quest.Objectives, {
                        Id = tostring(objectiveId),
                        Type = tostring(objectiveInfo.Type or "Unknown"),
                        Info = objectiveInfo,
                        Goal = tonumber(objectiveInfo.Goal) or 1,
                        Progress = tonumber(self:Peek(progress[objectiveId] or progress[tostring(objectiveId)])) or 0,
                    })
                end
                table.sort(quest.Objectives, function(left, right) return left.Id < right.Id end)
                result.Quests[categoryId .. ":" .. quest.Id] = quest
                table.insert(category.Quests, quest)
            end
            table.sort(category.Quests, function(left, right) return left.Id < right.Id end)
            table.insert(result.Categories, category)
        end
    end
    result.Valid = result.ReadyCategories > 0
    result.Complete = result.ReadyCategories == 2
    return result
end
function QuestAuto:GetQuest(snapshot, reference)
    return type(reference) == "table" and snapshot.Quests[tostring(reference.Category) .. ":" .. tostring(reference.QuestId)] or nil
end
function QuestAuto:GetObjective(snapshot, reference)
    local quest = self:GetQuest(snapshot, reference)
    for _, objective in ipairs((quest and quest.Objectives) or {}) do
        if objective.Id == tostring(reference.ObjectiveId) then return objective, quest end
    end
    return nil, quest
end
function QuestAuto:RefsCompleted(snapshot, target)
    if type(target) ~= "table" or type(target.Refs) ~= "table" or #target.Refs == 0 then return false end
    for _, reference in ipairs(target.Refs) do
        local objective, quest = self:GetObjective(snapshot, reference)
        if objective then
            if objective.Progress < objective.Goal then return false end
        elseif quest then
            if not quest.Completed and not quest.Claimed then return false end
        elseif not snapshot.Ready[reference.Category] then
            return false
        end
    end
    return true
end
function QuestAuto:TargetResetValid(snapshot, target)
    if type(target) ~= "table" or type(target.ResetKeys) ~= "table" then return false end
    for categoryId, resetKey in pairs(target.ResetKeys) do
        if snapshot.Ready[categoryId] and tostring(snapshot.ResetKeys[categoryId]) ~= tostring(resetKey) then return false end
    end
    return true
end
function QuestAuto:ResetKeysForRefs(snapshot, refs)
    local resetKeys = {}
    for _, reference in ipairs(refs or {}) do
        resetKeys[reference.Category] = snapshot.ResetKeys[reference.Category]
    end
    return resetKeys
end
function QuestAuto:SetStatus(status)
    self.Runtime.Status = tostring(status or "")
end
function QuestAuto:SetOwnerStatus(owner, status)
    if owner == "Challenge" then
        setChallengeStatus(status)
    else
        self:SetStatus(status)
    end
end
function QuestAuto:MatchAdvanced(target, stateInfo)
    if type(target) ~= "table" then return false end
    local current = getSessionMatchesPlayed() or (type(stateInfo) == "table" and tonumber(stateInfo.SessionMatchesPlayed))
    if current == nil then return false end
    local baseline = tonumber(target.MatchesPlayedAtJoin)
    if baseline == nil or current < baseline then
        target.MatchesPlayedAtJoin = current
        saveConfig()
        return false
    end
    return current > baseline
end
function QuestAuto:EnsureMacroRestart(owner, target, stateInfo)
    if type(target) ~= "table" or not target.MacroKey or type(stateInfo) ~= "table" then return false end
    local restartKey = game.JobId .. ":" .. tostring(target.JoinIssuedAt or "")
    local currentWave = tonumber(stateInfo.Wave) or 0
    if target.MacroRestartKey ~= restartKey then
        macroHookGeneration.Playback = (tonumber(macroHookGeneration.Playback) or 0) + 1
        isPlaying = false
        lastHasRunMacro = false
        target.MacroRestartKey = restartKey
        target.MacroRestartPhase = "Requested"
        target.MacroRestartAttempts = 0
        target.MacroRestartRequestedAt = 0
        target.MacroRestartWave = currentWave
    end
    if target.MacroRestartPhase == "Ready" or target.MacroRestartPhase == "Failed" then return false end
    local elapsed = os.time() - (tonumber(target.MacroRestartRequestedAt) or 0)
    local confirmed = (tonumber(target.MacroRestartRequestedAt) or 0) > 0
        and ((currentWave < (tonumber(target.MacroRestartWave) or currentWave)) or (currentWave <= 1 and elapsed >= 4))
    if confirmed then
        target.MacroRestartPhase = "Ready"
        isPlaying = false
        lastHasRunMacro = false
        saveConfig()
        self:SetOwnerStatus(owner, "Restart đã xác nhận; chuẩn bị chạy Macro từ đầu...")
        print("[AUTO " .. string.upper(owner) .. "] Restart confirmed; Macro unlocked")
        return false
    end
    if (tonumber(target.MacroRestartAttempts) or 0) < 3 and elapsed >= 10 then
        target.MacroRestartAttempts = (tonumber(target.MacroRestartAttempts) or 0) + 1
        target.MacroRestartRequestedAt = os.time()
        target.MacroRestartWave = currentWave
        getgenv().IsManualRestart = true
        isPlaying = false
        lastHasRunMacro = false
        saveConfig()
        local ok, sent = pcall(function() return safeFireGameAction("Restart") end)
        self:SetOwnerStatus(owner, string.format("Đang Restart để chạy Macro từ đầu (%d/3)...", target.MacroRestartAttempts))
        print("[AUTO " .. string.upper(owner) .. "] Restart requested for owned match (" .. tostring(target.MacroRestartAttempts) .. "/3)")
        if not ok or sent ~= true then warn("[AUTO " .. string.upper(owner) .. "] Restart request failed: " .. tostring(sent)) end
    elseif (tonumber(target.MacroRestartAttempts) or 0) < 3 then
        self:SetOwnerStatus(owner, string.format("Đang chờ Restart xác nhận (%d/3)...", target.MacroRestartAttempts))
    else
        target.MacroRestartPhase = "Failed"
        saveConfig()
        self:SetOwnerStatus(owner, "Restart thất bại sau 3 lần; đang tiếp tục trận hiện tại.")
        warn("[AUTO " .. string.upper(owner) .. "] Restart failed after 3 attempts")
        return false
    end
    return true
end
function QuestAuto:UpdateDisplay(snapshot)
    local lines = {self.Runtime.Status}
    for _, category in ipairs(snapshot.Categories or {}) do
        local labels = {}
        for _, quest in ipairs(category.Quests) do
            if not quest.Claimed then
                local objectives = {}
                for _, objective in ipairs(quest.Objectives) do
                    local asset = self:Condition(objective.Info, "AssetName")
                    local mode = self:Condition(objective.Info, "Gamemode")
                    table.insert(objectives, string.format("%s%s%s %d/%d", objective.Type, asset and (" " .. asset) or "", mode and (" " .. mode) or "", objective.Progress, objective.Goal))
                end
                table.insert(labels, quest.Name .. ": " .. (quest.Completed and "chờ claim" or table.concat(objectives, ", ")))
            end
        end
        table.insert(lines, string.format("%s: %d/%d claimed%s", category.Id, category.Claimed, #category.Quests, #labels > 0 and (" | " .. table.concat(labels, " | ")) or ""))
    end
    local description = table.concat(lines, "\n")
    if description ~= self.Runtime.LastDisplay then
        self.Runtime.LastDisplay = description
        safeSetParagraphDesc(self.StatusParagraph, description)
    end
end
function QuestAuto:GetMacro(mapName)
    local requestedKey = appConfig.QuestAuto.MapMacros[tostring(mapName)]
    if not requestedKey or requestedKey == "" then return nil end
    local macroList, matchedKey = getMacroListForStage(requestedKey)
    if type(macroList) ~= "table" or #macroList == 0 then return nil end
    return matchedKey
end
function QuestAuto:GetConfiguredMap()
    for _, mapName in ipairs(self.Maps) do
        local macroKey = self:GetMacro(mapName)
        if macroKey then return mapName, macroKey end
    end
    return nil, nil
end
function QuestAuto:JoinValue(target)
    if target.Mode == "Challenge" then
        return table.concat({"Challenge", tostring(target.ChallengeType or "Regular"), tostring(target.Index or 1)}, "|")
    end
    return table.concat({tostring(target.Mode), tostring(target.Map), tostring(target.Act or ""), tostring(target.Difficulty or "Hard")}, "|")
end
function QuestAuto:RequestLobby(reason)
    self:SetStatus(reason .. " Đang chọn map tiếp theo...")
    if tick() - self.Runtime.LastReturnAt < 5 then return end
    local coordinator = getgenv().AnimeExpeditionsCoordinator
    local stateInfo = getGameStates()
    if coordinator and stateInfo and stateInfo.CurrentGameState ~= "Lobby" and coordinator:BeginMapSwitchResolution("Quest", reason, stateInfo) then
        self.Runtime.LastReturnAt = tick()
    elseif coordinator and coordinator:RequestLobby("Quest", reason, stateInfo) then
        self.Runtime.LastReturnAt = tick()
    elseif not coordinator then
        self.Runtime.LastReturnAt = tick()
        pcall(function() safeFireGameAction("Lobby") end)
    end
end
function QuestAuto:ProcessPending(snapshot)
    local pending = self.Runtime.Pending
    if not pending then return false end
    if pending.Type == "Claim" then
        local quest = snapshot.Quests[pending.Category .. ":" .. pending.QuestId]
        if snapshot.Ready[pending.Category] and (not quest or quest.Claimed) then
            self.Runtime.Pending = nil
            local target = appConfig.QuestAuto.ActiveTarget
            for _, reference in ipairs(type(target) == "table" and target.Refs or {}) do
                if tostring(reference.Category) == tostring(pending.Category)
                    and tostring(reference.QuestId) == tostring(pending.QuestId) then
                    appConfig.QuestAuto.ActiveTarget = nil
                    saveConfig()
                    break
                end
            end
            return false
        end
    elseif tick() - pending.RequestedAt >= 2 then
        self.Runtime.Pending = nil
        return false
    end
    if tick() - pending.RequestedAt >= 8 then
        self.Runtime.Pending = nil
        self:SetStatus("Quest chưa phản hồi, sẽ thử lại.")
        return false
    end
    self:SetStatus(pending.Status)
    return true
end
function QuestAuto:RequestClaim(quest)
    self.Runtime.Pending = {
        Type = "Claim",
        Category = quest.Category,
        QuestId = quest.Id,
        RequestedAt = tick(),
        Status = "Đang claim " .. quest.Category .. " / " .. quest.Name .. "...",
    }
    local ok = pcall(function() Actions.ClaimQuest(quest.Category, quest.Id) end)
    if not ok then self.Runtime.Pending = nil end
    return ok
end
function QuestAuto:BuildChallengeTarget(snapshot)
    local refs = {}
    for _, category in ipairs(snapshot.Categories) do
        for _, quest in ipairs(category.Quests) do
            if not quest.Completed and not quest.Claimed then
                for _, objective in ipairs(quest.Objectives) do
                    if objective.Progress < objective.Goal and self:Condition(objective.Info, "Gamemode") == "Challenge"
                        and tostring(self:Condition(objective.Info, "ChallengeType") or "Regular") == "Regular" then
                        table.insert(refs, {Category = quest.Category, QuestId = quest.Id, ObjectiveId = objective.Id})
                    end
                end
            end
        end
    end
    if #refs == 0 then return nil, false end
    local challengeState = getRegularChallengeState()
    if not challengeState.Valid then return nil, true end
    local resetKey = tostring(challengeState.ResetKey or "")
    if self.Runtime.ChallengeResetKey ~= resetKey then
        self.Runtime.ChallengeResetKey = resetKey
        self.Runtime.SkippedChallenges = {}
    end
    for _, challenge in ipairs(challengeState.Challenges or {}) do
        local macroKey = self:GetMacro(challenge.Map)
        local skipKey = resetKey .. ":" .. tostring(challenge.Index)
        if challenge.Available and challenge.AttemptsLeft > 0 and not self.Runtime.SkippedChallenges[skipKey] then
            if macroKey then
                return {
                    Owner = "Quest",
                    Mode = "Challenge",
                    ChallengeType = "Regular",
                    Index = challenge.Index,
                    Map = challenge.Map,
                    Act = challenge.Act,
                    Difficulty = challenge.Difficulty,
                    MacroKey = macroKey,
                    ChallengeResetKey = challengeState.ResetKey,
                    ResetKeys = self:ResetKeysForRefs(snapshot, refs),
                    Refs = refs,
                }, false
            end
            self.Runtime.SkippedChallenges[skipKey] = true
            self:SetStatus(string.format("Quest Challenge #%d %s không có Macro; đã skip slot.", challenge.Index, challenge.Map))
        end
    end
    return nil, false
end
function QuestAuto:BuildModeTarget(snapshot, mode)
    local refs = {}
    local targetWave = 0
    for _, category in ipairs(snapshot.Categories) do
        for _, quest in ipairs(category.Quests) do
            if not quest.Completed and not quest.Claimed then
                for _, objective in ipairs(quest.Objectives) do
                    if objective.Progress < objective.Goal then
                        local objectiveMode = self:Condition(objective.Info, "Gamemode")
                        local matches = mode == "Mastery" and objective.Type == "FinishMap" and objectiveMode == "Mastery"
                            or mode == "Infinite" and objective.Type == "ClearWave" and objectiveMode == "Infinite"
                            or mode == "Story" and ((objective.Type == "FinishMap" and (objectiveMode == nil or objectiveMode == "Story"))
                                or (objective.Type == "Takedowns" and (objectiveMode == nil or objectiveMode == "Story")))
                        if matches then
                            table.insert(refs, {Category = quest.Category, QuestId = quest.Id, ObjectiveId = objective.Id})
                            if mode == "Infinite" then targetWave = math.max(targetWave, objective.Goal - objective.Progress) end
                        end
                    end
                end
            end
        end
    end
    if #refs == 0 then return nil, false end
    if self.Runtime.SkippedModes[mode] then return nil, false end
    local mapName, macroKey = self:GetConfiguredMap()
    if not mapName then
        self.Runtime.SkippedModes[mode] = true
        self:SetStatus("Quest " .. mode .. " không có Macro; đã skip mode này đến lần reset tiếp theo.")
        return nil, true
    end
    return {
        Owner = "Quest",
        Mode = mode,
        Map = mapName,
        Act = "Act 1",
        Difficulty = "Hard",
        MacroKey = macroKey,
        TargetWave = targetWave,
        ResetKeys = self:ResetKeysForRefs(snapshot, refs),
        Refs = refs,
    }, false
end
function QuestAuto:RecoverTargetInGame(stateInfo, snapshot)
    if not snapshot.Valid or type(stateInfo) ~= "table" then return nil end
    local mode = tostring(stateInfo.Gamemode or "")
    local mapName = tostring(stateInfo.Map or "")
    local macroKey = self:GetMacro(mapName)
    if not macroKey then return nil end
    local target
    if mode == "Challenge" and tostring(stateInfo.ChallengeType or "Regular") == "Regular" then
        local refs = {}
        for _, category in ipairs(snapshot.Categories) do
            for _, quest in ipairs(category.Quests) do
                if not quest.Completed and not quest.Claimed then
                    for _, objective in ipairs(quest.Objectives) do
                        if objective.Progress < objective.Goal and self:Condition(objective.Info, "Gamemode") == "Challenge"
                            and tostring(self:Condition(objective.Info, "ChallengeType") or "Regular") == "Regular" then
                            table.insert(refs, {Category = quest.Category, QuestId = quest.Id, ObjectiveId = objective.Id})
                        end
                    end
                end
            end
        end
        if #refs == 0 then return nil end
        local challengeState = getRegularChallengeState()
        target = {
            Mode = "Challenge",
            ChallengeType = "Regular",
            Index = stateInfo.ChallengeIndex,
            Map = mapName,
            Act = tostring(stateInfo.Act or ""),
            Difficulty = tostring(stateInfo.Difficulty or "Hard"),
            MacroKey = macroKey,
            ChallengeResetKey = challengeState.ResetKey,
            ResetKeys = self:ResetKeysForRefs(snapshot, refs),
            Refs = refs,
        }
    elseif mode == "Story" or mode == "Infinite" or mode == "Mastery" then
        target = select(1, self:BuildModeTarget(snapshot, mode))
        if not target then return nil end
        target.Map = mapName
        target.Act = tostring(stateInfo.Act or target.Act or "")
        target.Difficulty = tostring(stateInfo.Difficulty or target.Difficulty or "Hard")
        target.MacroKey = macroKey
    else
        return nil
    end
    target.Owner = "Quest"
    target.JoinIssuedAt = os.time()
    target.JoinValue = self:JoinValue(target)
    target.MatchesPlayedAtJoin = getSessionMatchesPlayed() or tonumber(stateInfo.SessionMatchesPlayed)
    appConfig.QuestAuto.ActiveTarget = target
    saveConfig()
    print("[AUTO QUEST] Recovered active target in game: " .. tostring(target.Mode) .. " " .. tostring(target.Map))
    return target
end
function QuestAuto:TrySummon(snapshot)
    local needed = 0
    for _, category in ipairs(snapshot.Categories) do
        for _, quest in ipairs(category.Quests) do
            if not quest.Completed and not quest.Claimed then
                for _, objective in ipairs(quest.Objectives) do
                    local remaining = math.max(0, objective.Goal - objective.Progress)
                    if objective.Type == "Summon" then
                        needed = math.max(needed, remaining)
                    elseif objective.Type == "SpendAsset" and self:Condition(objective.Info, "AssetName") == "Gem" then
                        needed = math.max(needed, math.ceil(remaining / 50))
                    end
                end
            end
        end
    end
    if needed <= 0 then return false end
    local challengeReady = appConfig.autoDailyChallengeEnabled
        and select(1, findAvailableChallenge(getRegularChallengeState("Daily"))) ~= nil
    if not challengeReady and appConfig.autoChallengeEnabled then
        challengeReady = select(1, findAvailableChallenge(getRegularChallengeState(), false, appConfig.challengeAutoSelectedSlots)) ~= nil
    end
    if challengeReady then
        self:SetStatus("Đang để Auto Challenge chạy trước; Quest Summon sẽ làm sau cùng.")
        return false
    end
    local coordinator = getgenv().AnimeExpeditionsCoordinator
    if coordinator and coordinator.MapSwitch and coordinator.MapSwitch.Phase == "Resolve" then
        local stateInfo = getGameStates()
        coordinator:FinishMapSwitch(stateInfo, "Không còn Quest map; đang về Lobby để làm Summon cuối cùng.")
        coordinator:RequestLobby("Quest", "Làm nhiệm vụ Summon cuối cùng", stateInfo)
        return true
    end
    local gems = snapshotItemData().Gem or 0
    if gems < needed * 50 then return false end
    local amount = math.min(50, needed)
    self.Runtime.Pending = {Type = "Summon", RequestedAt = tick(), Status = string.format("Đang Summon Standard x%d cho Daily / Weekly...", amount)}
    local ok = pcall(function() Actions.Summon("Standard", amount) end)
    if not ok then self.Runtime.Pending = nil return false end
    return true
end
function QuestAuto:TrySpendGold(snapshot)
    local remaining = 0
    for _, category in ipairs(snapshot.Categories) do
        for _, quest in ipairs(category.Quests) do
            if not quest.Completed and not quest.Claimed then
                for _, objective in ipairs(quest.Objectives) do
                    if objective.Type == "SpendAsset" and self:Condition(objective.Info, "AssetName") == "Gold" then
                        remaining = math.max(remaining, math.max(0, objective.Goal - objective.Progress))
                    end
                end
            end
        end
    end
    if remaining <= 0 or tick() - (getgenv().lastAutoShopPurchase or 0) < 2 then return false end
    local replica
    pcall(function() replica = require(ReplicatedStorage.Nodes).GET_SHOP_REPLICA:InvokeSelf("GoldShop") end)
    local priorities = {"TraitReroll", "StatReroll", "StatLock", "EquipmentReroll", "EquipmentLock", "SpriteGrey", "FoodItem5", "FoodItem4", "FoodItem3", "FoodItem2", "FoodItem1"}
    for _, productId in ipairs(priorities) do
        local entry
        for _, candidate in ipairs(allShops) do
            if candidate.DataKey == "GoldShop" and candidate.ShopKey == "GoldShop1" and candidate.ProductId == productId then entry = candidate break end
        end
        if entry then
            local maxAmount, itemIndex = getAutoShopPurchasableAmount(entry)
            local shop = replica and replica.Data and replica.Data.Shops and replica.Data.Shops[entry.ShopKey]
            local item = shop and shop.Items and shop.Items[itemIndex]
            local price = item and math.max(0, (tonumber(item.Price) or 0) - (tonumber(item.Discount) or 0)) or 0
            if maxAmount > 0 and price > 0 then
                local amount = math.min(maxAmount, math.max(1, math.ceil(remaining / price)))
                getgenv().lastAutoShopPurchase = tick()
                self.Runtime.Pending = {Type = "SpendGold", RequestedAt = tick(), Status = string.format("Đang mua %s x%d để dùng Gold cho Quest...", productId, amount)}
                local ok = pcall(function() Actions.ShopPurchaseItem(entry.DataKey, entry.ShopKey, itemIndex, amount) end)
                if ok then return true end
                self.Runtime.Pending = nil
            end
        end
    end
    return false
end
function QuestAuto:RunLobby(snapshot)
    local directive = {BlockNormalJoin = true, BlockNormalSummon = true, JoinValue = nil}
    if not snapshot.Valid then
        self.Runtime.InvalidSince = self.Runtime.InvalidSince or tick()
        if tick() - self.Runtime.InvalidSince >= 15 then
            directive.BlockNormalJoin = false
            directive.BlockNormalSummon = false
            self:SetStatus("Daily / Weekly chưa tải sau 15s; tạm nhường Challenge / Auto Join.")
        else
            self:SetStatus("Đang chờ dữ liệu Daily / Weekly; giữ khóa Auto Join Map...")
        end
        return directive
    end
    self.Runtime.InvalidSince = nil
    if snapshot.Complete then self.Runtime.IncompleteSince = nil
    else self.Runtime.IncompleteSince = self.Runtime.IncompleteSince or tick() end
    local skipResetKey = tostring(snapshot.ResetKeys.Daily or "") .. ":" .. tostring(snapshot.ResetKeys.Weekly or "")
    if self.Runtime.SkipResetKey ~= skipResetKey then
        self.Runtime.SkipResetKey = skipResetKey
        self.Runtime.SkippedModes = {}
        self.Runtime.SkippedChallenges = {}
    end
    if self:ProcessPending(snapshot) then return directive end
    local target = appConfig.QuestAuto.ActiveTarget
    if type(target) == "table" then
        for categoryId in pairs(type(target.ResetKeys) == "table" and target.ResetKeys or {}) do
            if not snapshot.Ready[categoryId] then
                if self.Runtime.IncompleteSince and tick() - self.Runtime.IncompleteSince >= 15 then
                    appConfig.QuestAuto.ActiveTarget = nil
                    directive.BlockNormalJoin = false
                    directive.BlockNormalSummon = false
                    saveConfig()
                    self:SetStatus("Category " .. tostring(categoryId) .. " chưa tải; đã bỏ target stale và nhường automation thấp hơn.")
                else
                    self:SetStatus("Đang chờ category " .. tostring(categoryId) .. " tải trước khi tiếp tục target Quest.")
                end
                return directive
            end
        end
        for _, reference in ipairs(type(target.Refs) == "table" and target.Refs or {}) do
            if reference.Category and not snapshot.Ready[reference.Category] then
                if self.Runtime.IncompleteSince and tick() - self.Runtime.IncompleteSince >= 15 then
                    appConfig.QuestAuto.ActiveTarget = nil
                    directive.BlockNormalJoin = false
                    directive.BlockNormalSummon = false
                    saveConfig()
                    self:SetStatus("Reference Quest stale vì category chưa tải; đã nhường automation thấp hơn.")
                else
                    self:SetStatus("Đang chờ category " .. tostring(reference.Category) .. " tải trước khi tiếp tục target Quest.")
                end
                return directive
            end
        end
        local targetUsable = self:TargetResetValid(snapshot, target) and not self:RefsCompleted(snapshot, target)
        local macro = target.MacroKey and appConfig.Macros[tostring(target.MacroKey)] or nil
        targetUsable = targetUsable and type(macro) == "table" and #macro > 0
        if targetUsable and target.Mode == "Challenge" then
            targetUsable = false
            local challengeState = getRegularChallengeState()
            for _, challenge in ipairs(challengeState.Challenges or {}) do
                if tonumber(challenge.Index) == tonumber(target.Index) and challenge.Available and challenge.AttemptsLeft > 0 then
                    targetUsable = true
                    break
                end
            end
        end
        if targetUsable then
            if self.Runtime.LastReturnAt > 0 and tick() - self.Runtime.LastReturnAt < 5 then
                self:SetStatus("Đang chờ server cập nhật tiến độ Quest...")
            elseif tick() - self.Runtime.LastJoinAt >= 10 then
                self:SetStatus("Đang tiếp tục " .. tostring(target.Mode) .. " " .. tostring(target.Map) .. " cho Quest...")
                directive.JoinValue = self:JoinValue(target)
            end
            return directive
        end
        appConfig.QuestAuto.ActiveTarget = nil
        saveConfig()
    end
    for _, category in ipairs(snapshot.Categories) do
        for _, quest in ipairs(category.Quests) do
            if quest.Completed and not quest.Claimed then
                self:RequestClaim(quest)
                return directive
            end
        end
    end
    if self:TrySpendGold(snapshot) then return directive end
    local challengeTarget, challengeWaiting = self:BuildChallengeTarget(snapshot)
    if challengeTarget then
        appConfig.QuestAuto.ActiveTarget = challengeTarget
        saveConfig()
        self:SetStatus(string.format("Ưu tiên Quest Challenge #%d: %s %s.", challengeTarget.Index, challengeTarget.Map, challengeTarget.Act))
        if tick() - self.Runtime.LastJoinAt >= 10 then directive.JoinValue = self:JoinValue(challengeTarget) end
        return directive
    end
    local missingMacro = false
    for _, mode in ipairs({"Mastery", "Infinite", "Story"}) do
        local modeTarget, missing = self:BuildModeTarget(snapshot, mode)
        missingMacro = missingMacro or missing
        if modeTarget then
            appConfig.QuestAuto.ActiveTarget = modeTarget
            saveConfig()
            self:SetStatus(string.format("Ưu tiên Quest: %s %s%s.", mode, modeTarget.Map, modeTarget.TargetWave > 0 and (" đến Wave " .. modeTarget.TargetWave) or ""))
            if tick() - self.Runtime.LastJoinAt >= 10 then directive.JoinValue = self:JoinValue(modeTarget) end
            return directive
        end
    end
    if self:TrySummon(snapshot) then return directive end
    if not snapshot.Complete then
        local missing = not snapshot.Ready.Daily and "Daily" or "Weekly"
        if self.Runtime.IncompleteSince and tick() - self.Runtime.IncompleteSince >= 15 then
            directive.BlockNormalJoin = false
            directive.BlockNormalSummon = false
            self:SetStatus("Category " .. missing .. " chưa tải sau 15s; tạm nhường Challenge / Auto Join.")
        else
            self:SetStatus("Đã xử lý category sẵn sàng; đang chờ " .. missing .. " tải, giữ khóa Auto Join Map.")
        end
        return directive
    end
    directive.BlockNormalJoin = false
    directive.BlockNormalSummon = false
    if missingMacro then
        self:SetStatus("Quest còn mục tiêu map nhưng chưa có Macro phù hợp. Đang nhường automation thấp hơn.")
    elseif challengeWaiting then
        self:SetStatus("Đang chờ dữ liệu Regular Challenge. Đang nhường automation thấp hơn.")
    else
        self:SetStatus("Không còn Daily / Weekly Quest khả thi lúc này. Đang nhường automation thấp hơn.")
    end
    return directive
end
function QuestAuto:RunInGame(stateInfo, snapshot)
    local target = appConfig.QuestAuto.ActiveTarget
    if type(target) ~= "table" or not self:TargetMatchesState(stateInfo) then
        self:SetStatus("Đang ở trận không thuộc Auto Quest.")
        return
    end
    if snapshot.Valid and not self:TargetResetValid(snapshot, target) then
        appConfig.QuestAuto.ActiveTarget = nil
        saveConfig()
        self:RequestLobby("Daily / Weekly đã reset.")
        return
    end
    local currentState = tostring(stateInfo.CurrentGameState or "")
    local finished = currentState == "Finished" or currentState == "Victory" or currentState == "Defeat"
    local defeated = currentState == "Defeat" or (currentState == "Finished" and tonumber(stateInfo.BaseHealth or 0) <= 0)
    local refsCompleted = snapshot.Valid and self:RefsCompleted(snapshot, target)
    local countMatchMode = target.Mode == "Story" or target.Mode == "Mastery"
    local matchAdvanced = countMatchMode and self:MatchAdvanced(target, stateInfo)
    if matchAdvanced then
        target.MatchesPlayedAtJoin = getSessionMatchesPlayed() or tonumber(stateInfo.SessionMatchesPlayed) or target.MatchesPlayedAtJoin
        saveConfig()
    end
    if refsCompleted and not target.CompletionPending then
        target.CompletionPending = true
        saveConfig()
    end
    if target.CompletionPending and target.Mode ~= "Infinite" and finished then
        if target.Mode == "Challenge" then
            self.Runtime.SkippedChallenges[tostring(target.ChallengeResetKey or "") .. ":" .. tostring(target.Index)] = true
        end
        appConfig.QuestAuto.ActiveTarget = nil
        saveConfig()
        self:RequestLobby("Mục tiêu Quest đã hoàn thành; chọn map tiếp theo.")
        return
    end
    if target.CompletionPending and target.Mode == "Infinite" then
        appConfig.QuestAuto.ActiveTarget = nil
        saveConfig()
        self:RequestLobby("Server đã xác nhận đủ Infinite Wave cho Quest.")
        return
    end
    if self:EnsureMacroRestart("Quest", target, stateInfo) then return end
    if finished then
        if self.Runtime.FinishedAt == 0 then self.Runtime.FinishedAt = tick() end
    else
        self.Runtime.FinishedAt = 0
    end
    if target.Mode == "Challenge" and defeated then
        self.Runtime.SkippedChallenges[tostring(target.ChallengeResetKey or "") .. ":" .. tostring(target.Index)] = true
        appConfig.QuestAuto.ActiveTarget = nil
        saveConfig()
        self:RequestLobby("Quest Challenge bị thua; chuyển slot khác.")
    elseif target.Mode == "Challenge" and finished and tick() - self.Runtime.FinishedAt >= 3 then
        self.Runtime.SkippedChallenges[tostring(target.ChallengeResetKey or "") .. ":" .. tostring(target.Index)] = true
        appConfig.QuestAuto.ActiveTarget = nil
        saveConfig()
        self:RequestLobby("Quest Challenge đã kết thúc.")
    elseif target.Mode == "Infinite" then
        local targetWave = tonumber(target.TargetWave) or 0
        local currentWave = tonumber(stateInfo.Wave) or 0
        local restartWave = tonumber(target.InfiniteRestartWave)
        if restartWave and restartWave > 0 then
            local restarted = currentWave < restartWave
                or (target.InfiniteRestartGameIncrement ~= nil
                    and tostring(stateInfo.GameIncrement) ~= tostring(target.InfiniteRestartGameIncrement))
            if restarted then
                targetWave = math.max(0, targetWave - restartWave)
                target.TargetWave = targetWave
                target.InfiniteRestartWave = nil
                target.InfiniteRestartGameIncrement = nil
                target.InfiniteRestartAt = nil
                saveConfig()
                print(string.format("[AUTO QUEST] Infinite Restart confirmed; %d waves remaining", targetWave))
            end
        end
        if targetWave > 0 and currentWave >= targetWave then
            self:SetStatus("Đã đạt số Wave dự kiến; đang chờ Quest server xác nhận tiến độ...")
        elseif currentWave >= 50 then
            local lastRestart = tonumber(target.InfiniteRestartAt) or 0
            if tick() - lastRestart >= 15 then
                target.InfiniteRestartAt = tick()
                local ok, sent = pcall(function() return safeFireGameAction("Restart") end)
                if ok and sent == true then
                    target.InfiniteRestartWave = currentWave
                    target.InfiniteRestartGameIncrement = stateInfo.GameIncrement
                    getgenv().AutoPlayRestartGameIncrement = stateInfo.GameIncrement
                    getgenv().WasAutoRestarted = true
                    isPlaying = false
                    lastHasRunMacro = true
                else
                    warn("[AUTO QUEST] Infinite Restart request failed: " .. tostring(sent))
                end
                saveConfig()
            end
            self:SetStatus("Quest Infinite đã đạt Wave 50; đang Restart để tiếp tục cộng Wave...")
        elseif finished then
            self:SetStatus("Quest Infinite chưa đủ mục tiêu; đang chờ game Auto Retry...")
        else
            self:SetStatus(string.format("Quest Infinite %s: Wave %s/%s.", tostring(target.Map), tostring(stateInfo.Wave or 0), tostring(targetWave)))
        end
    elseif finished then
        self:SetStatus("Quest " .. tostring(target.Mode) .. " chưa đủ mục tiêu; đang chờ game Auto Retry...")
    else
        self:SetStatus("Đang chạy Quest " .. tostring(target.Mode) .. " " .. tostring(target.Map) .. "...")
    end
end
function QuestAuto:Tick(stateInfo)
    local snapshot = self:Snapshot()
    local directive = {BlockNormalJoin = false, BlockNormalSummon = false, JoinValue = nil}
    if appConfig.QuestAuto.Enabled and not snapshot.Complete then
        directive.BlockNormalJoin = true
        directive.BlockNormalSummon = true
    end
    local allQuestsClaimed = snapshot.Complete and #snapshot.Categories > 0
    local claimableQuest
    for _, category in ipairs(snapshot.Categories or {}) do
        if category.Claimed < #category.Quests then allQuestsClaimed = false break end
    end
    for _, category in ipairs(snapshot.Categories or {}) do
        for _, quest in ipairs(category.Quests or {}) do
            if quest.Completed and not quest.Claimed then claimableQuest = quest break end
        end
        if claimableQuest then break end
    end
    if not appConfig.QuestAuto.Enabled then
        self.Runtime.InvalidSince = nil
        self.Runtime.WaitingSince = nil
        self.Runtime.WaitingMatchesPlayed = nil
        self:SetStatus("Auto Quest đang tắt.")
    elseif self:ProcessPending(snapshot) then
        directive.BlockNormalJoin = true
        directive.BlockNormalSummon = true
    elseif claimableQuest then
        directive.BlockNormalJoin = true
        directive.BlockNormalSummon = true
        self:RequestClaim(claimableQuest)
    elseif allQuestsClaimed then
        self.Runtime.WaitingSince = nil
        self.Runtime.WaitingMatchesPlayed = nil
        if type(appConfig.QuestAuto.ActiveTarget) == "table" then
            appConfig.QuestAuto.ActiveTarget = nil
            saveConfig()
        end
        self:SetStatus("Đã hoàn thành mọi nhiệm vụ.")
    elseif (getgenv().AnimeExpeditionsCoordinator and getgenv().AnimeExpeditionsCoordinator.MapSwitch
        and getgenv().AnimeExpeditionsCoordinator.MapSwitch.Phase == "Resolve") or not stateInfo or stateInfo.CurrentGameState == "Lobby" then
        self.Runtime.WaitingSince = nil
        self.Runtime.WaitingMatchesPlayed = nil
        directive = self:RunLobby(snapshot)
    elseif self:TargetMatchesState(stateInfo) then
        self.Runtime.WaitingSince = nil
        self.Runtime.WaitingMatchesPlayed = nil
        directive.BlockNormalJoin = true
        directive.BlockNormalSummon = true
        self:RunInGame(stateInfo, snapshot)
    else
        local existingTarget = appConfig.QuestAuto.ActiveTarget
        local recovered
        if type(existingTarget) ~= "table" or existingTarget.Owner ~= "Quest" then
            recovered = self:RecoverTargetInGame(stateInfo, snapshot)
        end
        if recovered then
            self.Runtime.WaitingSince = nil
            self.Runtime.WaitingMatchesPlayed = nil
            directive.BlockNormalJoin = true
            directive.BlockNormalSummon = true
            self:RunInGame(stateInfo, snapshot)
        else
            local target = appConfig.QuestAuto.ActiveTarget
            if type(target) == "table" and target.Owner == "Quest" then
                directive.BlockNormalJoin = true
                directive.BlockNormalSummon = true
            end
            local objectiveDone = type(target) == "table" and snapshot.Valid and self:RefsCompleted(snapshot, target)
            local countMatchMode = type(target) == "table" and (target.Mode == "Story" or target.Mode == "Mastery")
            local matchAdvanced = countMatchMode and self:MatchAdvanced(target, stateInfo)
            local claimable = false
            for _, category in ipairs(snapshot.Categories or {}) do
                for _, quest in ipairs(category.Quests or {}) do
                    if quest.Completed and not quest.Claimed then claimable = true break end
                end
                if claimable then break end
            end
            local currentMatches = getSessionMatchesPlayed() or tonumber(stateInfo.SessionMatchesPlayed)
            self.Runtime.WaitingSince = self.Runtime.WaitingSince or tick()
            if self.Runtime.WaitingMatchesPlayed == nil then self.Runtime.WaitingMatchesPlayed = currentMatches end
            if currentMatches ~= nil and self.Runtime.WaitingMatchesPlayed ~= nil and currentMatches < self.Runtime.WaitingMatchesPlayed then
                self.Runtime.WaitingMatchesPlayed = currentMatches
            end
            local waitedMatchEnded = currentMatches ~= nil and self.Runtime.WaitingMatchesPlayed ~= nil
                and currentMatches > self.Runtime.WaitingMatchesPlayed
            local currentState = tostring(stateInfo.CurrentGameState or "")
            local finished = currentState == "Finished" or currentState == "Victory" or currentState == "Defeat"
            local retryOwned = type(target) == "table" and target.Owner == "Quest" and target.Mode ~= "Challenge"
            if retryOwned then
                if matchAdvanced then
                    target.MatchesPlayedAtJoin = currentMatches or target.MatchesPlayedAtJoin
                    saveConfig()
                end
                if objectiveDone and not target.CompletionPending then
                    target.CompletionPending = true
                    saveConfig()
                end
                if target.CompletionPending and (finished or waitedMatchEnded) then
                    appConfig.QuestAuto.ActiveTarget = nil
                    saveConfig()
                    self:RequestLobby("Quest đã hoàn thành; cần về Lobby để claim.")
                elseif finished and target.JoinValue then
                    directive.JoinValue = target.JoinValue
                    self:SetStatus("Quest chưa đủ mục tiêu; đang quay lại đúng map Quest.")
                else
                    self:SetStatus("Quest chưa đủ mục tiêu; đang chờ game Auto Retry...")
                end
            elseif objectiveDone or claimable or matchAdvanced or waitedMatchEnded then
                appConfig.QuestAuto.ActiveTarget = nil
                saveConfig()
                self:RequestLobby((objectiveDone or claimable) and "Quest đã hoàn thành; cần về Lobby để claim." or "Trận đã kết thúc/Auto Retry; tiếp tục Auto Quest.")
            else
                self:SetStatus("Đang chờ trận hiện tại kết thúc (theo Matches Played)...")
            end
        end
    end
    self:UpdateDisplay(snapshot)
    return directive
end
function EventAuto:SetStatus(status)
    self.Runtime.Status = tostring(status or "")
end
function EventAuto:RefreshWishUnits(force)
    if not force and tick() - (self.Runtime.LastWishRefreshAt or 0) < 5 then return end
    self.Runtime.LastWishRefreshAt = tick()
    local options, labelToId, idToLabel = getWishUnitOptions()
    self.Runtime.WishUnitLabels = options
    self.Runtime.WishLabelToId = labelToId
    if appConfig.EventAuto.wishUnitId and not idToLabel[appConfig.EventAuto.wishUnitId] then
        appConfig.EventAuto.wishUnitId = nil
        saveConfig()
    end
    if self.WishUnitDropdown then
        pcall(function()
            self.WishUnitDropdown:SetValues(options)
            self.WishUnitDropdown:SetValue(idToLabel[appConfig.EventAuto.wishUnitId] or "Không chọn")
        end)
    end
end
function EventAuto:UpdateDisplay(dragonSnapshot)
    local lines = {self.Runtime.Status}
    local target = self.Runtime.ActiveTarget
    if type(target) == "table" then
        table.insert(lines, string.format("Target: %s | %s %s %s", tostring(target.Owner), tostring(target.Mode), tostring(target.Map), tostring(target.Act or "")))
    end
    if type(dragonSnapshot) == "table" and dragonSnapshot.Valid then
        table.insert(lines, string.format("Dragon's Wish: %d/%d claimed", dragonSnapshot.Claimed, dragonSnapshot.Total))
        for _, quest in ipairs(dragonSnapshot.QuestArray) do
            local objectives = {}
            for _, objective in ipairs(quest.Objectives) do
                table.insert(objectives, string.format("%s %d/%d [%s]", objective.Type, objective.Progress, objective.Goal, objective.Support))
            end
            local state = quest.Claimed and "Claimed" or (quest.Completed and "Claimable" or (quest.Unlocked and "In Progress" or "Locked"))
            table.insert(lines, string.format("C%d %s [%s]: %s", quest.Chapter, quest.Name, state, table.concat(objectives, ", ")))
        end
    end
    local description = table.concat(lines, "\n")
    if description ~= self.Runtime.LastDisplay then
        self.Runtime.LastDisplay = description
        safeSetParagraphDesc(self.StatusParagraph, description)
    end
end
function EventAuto:Condition(objective, conditionName)
    for _, condition in pairs((objective and objective.Conditions) or {}) do
        if condition.ValueName == conditionName then return condition.Value end
    end
    return objective and objective[conditionName] or nil
end
function EventAuto:ObjectiveSupport(objective)
    local objectiveType = tostring(objective.Type or "Unknown")
    local mode = tostring(self:Condition(objective, "Gamemode") or "")
    if objectiveType == "GuessThatUnit" or objectiveType == "GuessUnit" then return appConfig.EventAuto.autoGuessUnit and "Supported" or "Needs Auto Guess" end
    if objectiveType == "FinishMap" then
        if mode == "" or mode == "Story" or mode == "Mastery" or mode == "Raid" then return "Supported" end
        if mode == "Challenge" and tostring(self:Condition(objective, "ChallengeType") or "Regular") == "Regular" then return "Supported" end
        return "Unsupported mode"
    end
    if objectiveType == "ClearWave" then return mode == "Infinite" and "Supported" or "Unsupported mode" end
    if objectiveType == "Takedowns" then return (mode == "" or mode == "Story") and "Supported" or "Unsupported mode" end
    if objectiveType == "Summon" then return "Supported" end
    if objectiveType == "SpendAsset" then
        local asset = tostring(self:Condition(objective, "AssetName") or "")
        return (asset == "Gem" or asset == "Gold") and "Supported" or "Unsupported asset"
    end
    if objectiveType == "OwnAsset" or objectiveType == "ObtainAsset" then return "Passive" end
    return "Unsupported"
end
function EventAuto:DragonSnapshot()
    local result = {Valid = false, Total = 0, Claimed = 0, QuestArray = {}, Quests = {}}
    local definitions = (QuestsInfo.Quests or {}).ShenronEvent
    local playerData = self:GetPlayerData()
    local categoryData = playerData and self:Peek((self:Peek(playerData.QuestData) or {}).ShenronEvent) or nil
    local states = type(categoryData) == "table" and self:Peek(categoryData.Quests) or nil
    if type(definitions) ~= "table" or type(states) ~= "table" then return result end
    result.Valid = true
    local eventInfo = EventsInfo.ShenronEvent
    local update = tonumber((Dependencies.Information or {}).Update) or 1
    for questId, info in pairs(definitions) do
        local state = self:Peek(states[questId])
        state = type(state) == "table" and state or {}
        local chapter = tonumber(info.Chapter) or 1
        local unlocked = state.Completed == true or state.Claimed == true
        local unlockChecked = false
        if not unlocked and type(eventInfo) == "table" and type(eventInfo.IsChapterUnlocked) == "function" then
            local ok, value = pcall(function() return eventInfo:IsChapterUnlocked(chapter, os.time(), update) end)
            unlockChecked = ok
            unlocked = ok and value == true
        end
        if not unlockChecked and chapter == 1 then unlocked = true end
        local quest = {
            Id = tostring(questId),
            Name = tostring(info.DisplayName or info.Name or questId),
            Chapter = chapter,
            Unlocked = unlocked,
            Completed = self:Peek(state.Completed) == true,
            Claimed = self:Peek(state.Claimed) == true,
            Prerequisites = info.Prerequisites or {},
            Objectives = {},
        }
        local progress = self:Peek(state.ObjectiveProgress)
        progress = type(progress) == "table" and progress or {}
        for objectiveId, objectiveInfo in pairs(info.Objectives or {}) do
            table.insert(quest.Objectives, {
                Id = tostring(objectiveId),
                Type = tostring(objectiveInfo.Type or "Unknown"),
                Info = objectiveInfo,
                Goal = tonumber(objectiveInfo.Goal) or 1,
                Progress = tonumber(self:Peek(progress[objectiveId] or progress[tostring(objectiveId)])) or 0,
                Support = self:ObjectiveSupport(objectiveInfo),
            })
        end
        table.sort(quest.Objectives, function(left, right) return left.Id < right.Id end)
        result.Total += 1
        if quest.Claimed then result.Claimed += 1 end
        result.Quests[quest.Id] = quest
        table.insert(result.QuestArray, quest)
    end
    table.sort(result.QuestArray, function(left, right)
        if left.Chapter ~= right.Chapter then return left.Chapter < right.Chapter end
        return left.Id < right.Id
    end)
    return result
end
function EventAuto:QuestAccessible(quest, snapshot)
    if not quest.Unlocked then return false end
    for _, prerequisite in pairs(quest.Prerequisites or {}) do
        local required = snapshot.Quests[tostring(prerequisite)]
        if required and not required.Claimed then return false end
    end
    return true
end
function EventAuto:Request(action, status, ...)
    local args = table.pack(...)
    self.Runtime.Pending = {Action = action, RequestedAt = tick(), Status = status}
    local ok = pcall(function() Actions.SendEventRequest(args[1], action, table.unpack(args, 2, args.n)) end)
    if not ok then self.Runtime.Pending = nil end
    return ok
end
function EventAuto:PendingActive()
    local pending = self.Runtime.Pending
    if not pending then return false end
    if tick() - pending.RequestedAt >= 3 then
        self.Runtime.Pending = nil
        return false
    end
    self:SetStatus(pending.Status)
    return true
end
function EventAuto:RunGuess(stateInfo)
    if not appConfig.EventAuto.autoGuessUnit or #appConfig.EventAuto.guessDifficulties == 0 then return false end
    if type(self.Runtime.ActiveTarget) == "table" and self:TargetMatchesState(stateInfo) then return false end
    if QuestAuto:TargetMatchesState(stateInfo) or challengeTargetMatchesState(stateInfo) then return false end
    local eventData = self:GetEventData("GuessUnitEvent") or {}
    local history = self:Peek(eventData.ClearHistory)
    history = type(history) == "table" and history or {}
    local resetKey = os.time() - os.time() % 86400
    local nextDifficulty
    local needsRetry = false
    local gold = snapshotItemData().Gold or 0
    for _, difficulty in ipairs(appConfig.EventAuto.guessDifficulties) do
        local clear = self:Peek(history[difficulty])
        clear = type(clear) == "table" and clear or {}
        if tonumber(self:Peek(clear.ClearTime)) and tonumber(self:Peek(clear.ClearTime)) >= resetKey then
            if self:Peek(clear.IsVictory) ~= true then
                local retryCost = difficulty == "Hard" and 5000 or 2500
                if gold >= retryCost then
                    nextDifficulty, needsRetry = difficulty, true
                    break
                else
                    self.Runtime.GuessSkippedForGold = difficulty
                end
            end
        else
            nextDifficulty = difficulty
            break
        end
    end
    if not nextDifficulty then
        if self.Runtime.GuessSkippedForGold then self:SetStatus("Guess " .. self.Runtime.GuessSkippedForGold .. " đã thua nhưng không đủ Gold để Retry; đang nhường automation thấp hơn.") end
        return false
    end
    self.Runtime.GuessSkippedForGold = nil
    if stateInfo and stateInfo.CurrentGameState ~= "Lobby" then
        self:SetStatus("Guess That Unit đang chờ về Lobby: " .. nextDifficulty)
        local coordinator = getgenv().AnimeExpeditionsCoordinator
        local currentState = tostring(stateInfo.CurrentGameState or "")
        if coordinator and (currentState == "Finished" or currentState == "Victory" or currentState == "Defeat") then
            coordinator:RequestLobby("GuessUnit", "Hoàn thành Guess That Unit", stateInfo)
        end
        return true
    end
    if self:PendingActive() then return true end
    if needsRetry then
        if self.Runtime.GuessRetryDifficulty == nextDifficulty and tick() >= (self.Runtime.GuessRetryReadyAt or 0) then
            self.Runtime.GuessRetryDifficulty = nil
            self.Runtime.GuessRetryReadyAt = nil
            self:Request("GameResult", "Đang hoàn thành Guess " .. nextDifficulty .. " sau Retry...", "GuessUnitEvent", nextDifficulty, true)
        else
            self.Runtime.GuessRetryDifficulty = nextDifficulty
            self.Runtime.GuessRetryReadyAt = tick() + 3
            self:Request("Retry", "Đang Retry Guess " .. nextDifficulty .. "...", "GuessUnitEvent", nextDifficulty)
        end
    else
        self.Runtime.GuessRetryDifficulty = nil
        self.Runtime.GuessRetryReadyAt = nil
        self:Request("GameResult", "Đang hoàn thành Guess " .. nextDifficulty .. "...", "GuessUnitEvent", nextDifficulty, true)
    end
    return true
end
function EventAuto:BossProgress()
    local playerData = self:GetPlayerData() or {}
    local trackCounter = self:Peek(playerData.TrackCounter)
    local entry = type(trackCounter) == "table" and self:Peek(trackCounter.BossBountyEvent) or nil
    return type(entry) == "table" and (tonumber(self:Peek(entry.Count)) or 0) or 0
end
function EventAuto:BossSignature(boss, queue)
    local function fingerprint(value, seen)
        if type(value) ~= "table" then return tostring(value) end
        seen = seen or {}
        if seen[value] then return "<cycle>" end
        seen[value] = true
        local keys = {}
        for key in pairs(value) do table.insert(keys, tostring(key)) end
        table.sort(keys)
        local parts = {}
        for _, key in ipairs(keys) do
            local child = value[key]
            if child == nil then child = value[tonumber(key)] end
            table.insert(parts, key .. "=" .. fingerprint(child, seen))
        end
        seen[value] = nil
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return fingerprint({Boss = boss, QueueData = queue})
end
function EventAuto:GetMapMacro(configField, mapName)
    local mapMacros = appConfig.EventAuto[configField]
    local requestedKey = type(mapMacros) == "table" and mapMacros[tostring(mapName)] or nil
    if not requestedKey or requestedKey == "" then return nil end
    local macroList = appConfig.Macros[tostring(requestedKey)]
    if type(macroList) == "table" and #macroList > 0 then return tostring(requestedKey) end
    local normalizedRequested = normalizeStageKey(requestedKey)
    for macroKey, candidate in pairs(appConfig.Macros) do
        if normalizeStageKey(macroKey) == normalizedRequested and type(candidate) == "table" and #candidate > 0 then
            return tostring(macroKey)
        end
    end
    return nil
end
function EventAuto:RunBoss(stateInfo)
    if not appConfig.EventAuto.autoBossBounty then
        if type(self.Runtime.ActiveTarget) == "table" and self.Runtime.ActiveTarget.Owner == "BossBounty" then self.Runtime.ActiveTarget = nil end
        return false
    end
    if QuestAuto:TargetMatchesState(stateInfo) or challengeTargetMatchesState(stateInfo) then return false end
    local count = self:BossProgress()
    if count >= 5 then
        if type(self.Runtime.ActiveTarget) == "table" and self.Runtime.ActiveTarget.Owner == "BossBounty" then self.Runtime.ActiveTarget = nil end
        return false
    end
    local eventData = self:GetEventData("BossBountyEvent") or {}
    local boss = self:Peek(eventData.Boss)
    local queue = self:Peek(eventData.QueueData)
    if type(boss) ~= "table" or type(queue) ~= "table" then
        local active = self.Runtime.ActiveTarget
        if type(active) == "table" and active.Owner == "BossBounty" then
            if count > (tonumber(active.CountBefore) or count) then
                self.Runtime.LastCompletedBossSignature = active.Signature
                self.Runtime.ActiveTarget = nil
                self.Runtime.BossStalledSince = nil
            else
                self.Runtime.BossStalledSince = self.Runtime.BossStalledSince or tick()
                if tick() - self.Runtime.BossStalledSince >= 15 then
                    self.Runtime.ActiveTarget = nil
                    self.Runtime.BossStalledSince = nil
                    self:SetStatus("Boss Bounty chưa được server xác nhận sau 15s; đã nhường automation thấp hơn.")
                    return false
                end
                self:SetStatus("Boss Bounty đang chờ TrackCounter xác nhận hoàn thành.")
                local coordinator = getgenv().AnimeExpeditionsCoordinator
                local currentState = stateInfo and tostring(stateInfo.CurrentGameState or "") or ""
                if coordinator and (currentState == "Finished" or currentState == "Victory" or currentState == "Defeat") then
                    coordinator:RequestLobby("BossBounty", "Chờ TrackCounter Boss Bounty", stateInfo)
                end
                return true
            end
        end
        if stateInfo and stateInfo.CurrentGameState ~= "Lobby" then
            self:SetStatus(string.format("Boss Bounty %d/5: chờ về Lobby để Roll.", count))
            local coordinator = getgenv().AnimeExpeditionsCoordinator
            if coordinator and (stateInfo.CurrentGameState == "Finished" or stateInfo.CurrentGameState == "Victory" or stateInfo.CurrentGameState == "Defeat") then
                coordinator:RequestLobby("BossBounty", "Roll Boss Bounty tiếp theo", stateInfo)
            end
            return true
        end
        if not self:PendingActive() then self:Request("Roll", string.format("Đang Roll Boss Bounty %d/5...", count + 1), "BossBountyEvent") end
        return true
    end
    local rarity = ({"Rare", "Legendary", "Secret"})[tonumber(self:Peek(boss.Difficulty)) or 1] or "Rare"
    if appConfig.EventAuto.bossBountyAutoReroll and not table.find(appConfig.EventAuto.bossBountyKeepRarities, rarity) then
        if stateInfo and stateInfo.CurrentGameState ~= "Lobby" then
            self:SetStatus("Boss Bounty " .. rarity .. " đang chờ về Lobby để Reroll.")
            return true
        end
        if (snapshotItemData().Gold or 0) < 5000 then
            self:SetStatus("Boss Bounty cần 5.000 Gold để Reroll; đang giữ bounty hiện tại.")
        elseif not self:PendingActive() then
            self:Request("Reroll", "Đang Reroll Boss Bounty " .. rarity .. "...", "BossBountyEvent", rarity == "Secret")
            return true
        else
            return true
        end
    end
    local signature = self:BossSignature(boss, queue)
    self.Runtime.BossStalledSince = nil
    local target = self.Runtime.ActiveTarget
    if self.Runtime.LastCompletedBossSignature == signature and (type(target) ~= "table" or target.Owner ~= "BossBounty") then
        if stateInfo and stateInfo.CurrentGameState ~= "Lobby" then
            self:SetStatus("Boss Bounty đã xác nhận; đang chờ về Lobby để Roll lượt tiếp theo.")
            local coordinator = getgenv().AnimeExpeditionsCoordinator
            if coordinator and (stateInfo.CurrentGameState == "Finished" or stateInfo.CurrentGameState == "Victory" or stateInfo.CurrentGameState == "Defeat") then
                coordinator:RequestLobby("BossBounty", "Roll Boss Bounty tiếp theo", stateInfo)
            end
        elseif not self:PendingActive() then
            self:Request("Roll", string.format("Đang Roll Boss Bounty %d/5...", count + 1), "BossBountyEvent")
        end
        return true
    end
    if self.Runtime.LastCompletedBossSignature and self.Runtime.LastCompletedBossSignature ~= signature then self.Runtime.LastCompletedBossSignature = nil end
    if type(target) ~= "table" or target.Owner ~= "BossBounty" or target.Signature ~= signature then
        local macroKey = self:GetMapMacro("bossBountyMapMacros", queue.MapName)
        if not macroKey then
            self.Runtime.ActiveTarget = nil
            self:SetStatus(string.format("Boss Bounty %s %s %s chưa chọn Macro trong tab Event; nhường automation thấp hơn.", rarity, tostring(queue.MapName), tostring(queue.ActName)))
            return false
        end
        target = {
            Owner = "BossBounty", Mode = tostring(queue.Gamemode or "Story"), Map = tostring(queue.MapName or ""),
            Act = tostring(queue.ActName or ""), Difficulty = tostring(queue.Difficulty or "Hard"), MacroKey = macroKey,
            Signature = signature, CountBefore = count, QueueData = table.clone(queue),
        }
        self.Runtime.ActiveTarget = target
    end
        if self:TargetMatchesState(stateInfo) then
        local currentState = tostring(stateInfo.CurrentGameState or "")
            if currentState == "Finished" or currentState == "Victory" or currentState == "Defeat" then
                self.Runtime.FinishedAt = self.Runtime.FinishedAt > 0 and self.Runtime.FinishedAt or tick()
            if self:BossProgress() > (target.CountBefore or count) or self:BossSignature(self:Peek(eventData.Boss), self:Peek(eventData.QueueData)) ~= target.Signature then
                self.Runtime.LastCompletedBossSignature = target.Signature
                self.Runtime.ActiveTarget = nil
                self.Runtime.FinishedAt = 0
            elseif tick() - self.Runtime.FinishedAt >= 3 then
                self.Runtime.BossStalledSince = self.Runtime.BossStalledSince or tick()
                if tick() - self.Runtime.BossStalledSince >= 15 then
                    self.Runtime.ActiveTarget = nil
                    self.Runtime.BossStalledSince = nil
                    self:SetStatus("Boss Bounty không cập nhật sau trận; đã nhường automation thấp hơn.")
                    return false
                end
                self:SetStatus("Boss Bounty kết thúc; đang chờ server xác nhận.")
            end
        else
            self.Runtime.FinishedAt = 0
            self:SetStatus(string.format("Đang đánh Boss Bounty %s (%d/5) tại %s %s.", rarity, count + 1, target.Map, target.Act))
        end
        return true
    end
    local joinValue = table.concat({target.Mode, target.Map, target.Act, target.Difficulty}, "|")
    self:SetStatus(string.format("Boss Bounty %s (%d/5): %s %s.", rarity, count + 1, target.Map, target.Act))
    return true, joinValue, "BossBounty"
end
function EventAuto:ObjectiveComplete(snapshot, target)
    local quest = snapshot.Quests[tostring(target.QuestId)]
    if not quest then return true end
    for _, objective in ipairs(quest.Objectives) do
        if objective.Id == tostring(target.ObjectiveId) then return objective.Progress >= objective.Goal end
    end
    return quest.Completed or quest.Claimed
end
function EventAuto:GetTargetMacro(mode, mapName)
    return self:GetMapMacro("dragonWishMapMacros", mapName)
end
function EventAuto:GetConfiguredDragonMap()
    for _, mapName in ipairs(eventMacroMaps) do
        local macroKey = self:GetTargetMacro(nil, mapName)
        if macroKey then return mapName, macroKey end
    end
    return nil, nil
end
function EventAuto:BuildDragonTarget(snapshot)
    for _, quest in ipairs(snapshot.QuestArray) do
        if not quest.Completed and not quest.Claimed and self:QuestAccessible(quest, snapshot) then
            for _, objective in ipairs(quest.Objectives) do
                if objective.Progress < objective.Goal and objective.Support == "Supported" then
                    local info = objective.Info
                    local mode = tostring(self:Condition(info, "Gamemode") or "")
                    if objective.Type == "ClearWave" then mode = "Infinite"
                    elseif objective.Type == "Takedowns" and mode == "" then mode = "Story"
                    elseif objective.Type == "FinishMap" and mode == "" then mode = "Story" end
                    if objective.Type == "FinishMap" or objective.Type == "ClearWave" or objective.Type == "Takedowns" then
                        if mode == "Challenge" then
                            local challengeState = getRegularChallengeState()
                            for _, challenge in ipairs(challengeState.Challenges or {}) do
                                local macroKey = self:GetTargetMacro("Challenge", challenge.Map)
                                if challenge.Available and challenge.AttemptsLeft > 0 and macroKey then
                                    return {Owner = "DragonWish", Mode = "Challenge", ChallengeType = "Regular", Index = challenge.Index, Map = challenge.Map, Act = challenge.Act, Difficulty = challenge.Difficulty, MacroKey = macroKey, QuestId = quest.Id, ObjectiveId = objective.Id}
                                end
                            end
                        else
                            local map = self:Condition(info, "MapName")
                            local macroKey = map and self:GetTargetMacro(mode, tostring(map)) or nil
                            if not map then map, macroKey = self:GetConfiguredDragonMap() end
                            if map and macroKey then
                                return {Owner = "DragonWish", Mode = mode, Map = tostring(map), Act = tostring(self:Condition(info, "ActName") or "Act 1"), Difficulty = tostring(self:Condition(info, "Difficulty") or "Hard"), MacroKey = macroKey, TargetWave = objective.Type == "ClearWave" and math.max(0, objective.Goal - objective.Progress) or 0, QuestId = quest.Id, ObjectiveId = objective.Id}
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end
function EventAuto:TryDragonLobbyAction(snapshot)
    if self:PendingActive() then return true end
    for _, quest in ipairs(snapshot.QuestArray) do
        if quest.Completed and not quest.Claimed and self:QuestAccessible(quest, snapshot) then
            self.Runtime.Pending = {Action = "ClaimQuest", RequestedAt = tick(), Status = "Đang claim Dragon Wish / " .. quest.Name .. "..."}
            local ok = pcall(function() Actions.ClaimQuest("ShenronEvent", quest.Id) end)
            if not ok then self.Runtime.Pending = nil end
            return true
        end
    end
    local summonNeeded, goldNeeded = 0, 0
    for _, quest in ipairs(snapshot.QuestArray) do
        if not quest.Completed and not quest.Claimed and self:QuestAccessible(quest, snapshot) then
            for _, objective in ipairs(quest.Objectives) do
                local remaining = math.max(0, objective.Goal - objective.Progress)
                if objective.Type == "Summon" then summonNeeded = math.max(summonNeeded, remaining) end
                if objective.Type == "SpendAsset" and self:Condition(objective.Info, "AssetName") == "Gem" then summonNeeded = math.max(summonNeeded, math.ceil(remaining / 50)) end
                if objective.Type == "SpendAsset" and self:Condition(objective.Info, "AssetName") == "Gold" then goldNeeded = math.max(goldNeeded, remaining) end
            end
        end
    end
    if goldNeeded > 0 then
        for _, entry in ipairs(allShops) do
            if entry.DataKey == "GoldShop" and entry.ShopKey == "GoldShop1" then
                local maxAmount, itemIndex = getAutoShopPurchasableAmount(entry)
                if maxAmount > 0 then
                    self.Runtime.Pending = {Action = "SpendGold", RequestedAt = tick(), Status = "Đang dùng Gold cho Dragon Wish..."}
                    pcall(function() Actions.ShopPurchaseItem(entry.DataKey, entry.ShopKey, itemIndex, 1) end)
                    return true
                end
            end
        end
    end
    if summonNeeded > 0 and (snapshotItemData().Gem or 0) >= 50 then
        local amount = math.min(50, summonNeeded)
        self.Runtime.Pending = {Action = "Summon", RequestedAt = tick(), Status = string.format("Đang Summon Standard x%d cho Dragon Wish...", amount)}
        pcall(function() Actions.Summon("Standard", amount) end)
        return true
    end
    return false
end
function EventAuto:WishUnitValid(unitId)
    local playerData = self:GetPlayerData()
    local units = playerData and self:Peek(playerData.UnitData) or nil
    local unit = type(units) == "table" and self:Peek(units[tostring(unitId)]) or nil
    if type(unit) ~= "table" then return false end
    return tostring(self:Peek(unit.Trait) or "") ~= "Unbound" and unitHasDBZCategory(tostring(self:Peek(unit.Asset) or ""))
end
function EventAuto:RunDragon(stateInfo)
    if not appConfig.EventAuto.autoDragonWish then
        if type(self.Runtime.ActiveTarget) == "table" and self.Runtime.ActiveTarget.Owner == "DragonWish" then self.Runtime.ActiveTarget = nil end
        return false, nil, nil, nil
    end
    if QuestAuto:TargetMatchesState(stateInfo) or challengeTargetMatchesState(stateInfo) then return false, nil, nil, nil end
    local snapshot = self:DragonSnapshot()
    if not snapshot.Valid then
        self.Runtime.MissingSince.ShenronEvent = self.Runtime.MissingSince.ShenronEvent or tick()
        if tick() - self.Runtime.MissingSince.ShenronEvent < 10 then
            self:SetStatus("Đang chờ quest category ShenronEvent tải...")
            return true, nil, nil, snapshot
        end
        if type(self.Runtime.ActiveTarget) == "table" and self.Runtime.ActiveTarget.Owner == "DragonWish" then self.Runtime.ActiveTarget = nil end
        self:SetStatus("ShenronEvent chưa được server load; nhường automation thấp hơn.")
        return false, nil, nil, snapshot
    end
    self.Runtime.MissingSince.ShenronEvent = nil
    self:RefreshWishUnits(false)
    local eventData = self:GetEventData("ShenronEvent") or {}
    if snapshot.Total > 0 and snapshot.Claimed >= snapshot.Total then
        self.Runtime.ActiveTarget = nil
        if appConfig.EventAuto.autoRedeemWish and self:Peek(eventData.ClaimedWish) == nil and self:WishUnitValid(appConfig.EventAuto.wishUnitId) then
            if not self:PendingActive() then self:Request("Wish", "Đang áp Unbound cho unit đã chọn...", "ShenronEvent", appConfig.EventAuto.wishUnitId) end
            return true, nil, nil, snapshot
        end
        self:SetStatus(self:Peek(eventData.ClaimedWish) ~= nil and "Dragon's Wish đã redeem." or "Đã đủ 7 Orb; Auto Redeem đang tắt hoặc chưa chọn unit hợp lệ.")
        return false, nil, nil, snapshot
    end
    local target = self.Runtime.ActiveTarget
    if type(target) == "table" and target.Owner == "DragonWish" and self:ObjectiveComplete(snapshot, target) then
        local targetWasActive = self:TargetMatchesState(stateInfo)
        self.Runtime.ActiveTarget = nil
        target = nil
        if targetWasActive then
            local coordinator = getgenv().AnimeExpeditionsCoordinator
            if coordinator then coordinator:RequestLobby("DragonWish", "Objective Dragon Wish đã hoàn thành", stateInfo) end
            return true, nil, nil, snapshot
        end
    end
    if self:TargetMatchesState(stateInfo) then
        local currentState = tostring(stateInfo.CurrentGameState or "")
        if currentState == "Finished" or currentState == "Victory" or currentState == "Defeat" then
            self.Runtime.FinishedAt = self.Runtime.FinishedAt > 0 and self.Runtime.FinishedAt or tick()
            if tick() - self.Runtime.FinishedAt >= 2 then
                local coordinator = getgenv().AnimeExpeditionsCoordinator
                if coordinator then coordinator:RequestLobby("DragonWish", "Cập nhật tiến độ Dragon Wish", stateInfo) end
            end
        else
            self.Runtime.FinishedAt = 0
            if target.Mode == "Infinite" and (tonumber(stateInfo.Wave) or 0) >= math.min(math.max(1, tonumber(target.TargetWave) or 1), 50) then
                local coordinator = getgenv().AnimeExpeditionsCoordinator
                self:SetStatus("Dragon Wish Infinite đã đạt mốc; đang về Lobby để cập nhật tiến độ.")
                if coordinator then coordinator:RequestLobby("DragonWish", "Cập nhật Infinite Wave Dragon Wish", stateInfo) end
            else
                self:SetStatus(string.format("Đang chạy Dragon Wish: %s %s %s.", tostring(target.Mode), tostring(target.Map), tostring(target.Act)))
            end
        end
        return true, nil, nil, snapshot
    end
    if stateInfo and stateInfo.CurrentGameState ~= "Lobby" and not (getgenv().AnimeExpeditionsCoordinator and getgenv().AnimeExpeditionsCoordinator.MapSwitch) then
        self:SetStatus("Dragon Wish đang chờ trận hiện tại kết thúc.")
        return type(target) == "table", nil, nil, snapshot
    end
    if self:TryDragonLobbyAction(snapshot) then return true, nil, nil, snapshot end
    if not target then
        target = self:BuildDragonTarget(snapshot)
        self.Runtime.ActiveTarget = target
    end
    if target then
        local joinValue
        if target.Mode == "Challenge" then joinValue = table.concat({"Challenge", target.ChallengeType or "Regular", tostring(target.Index or 1)}, "|")
        else joinValue = table.concat({target.Mode, target.Map, target.Act or "", target.Difficulty or "Hard"}, "|") end
        self:SetStatus(string.format("Dragon Wish: chuẩn bị %s %s %s.", target.Mode, target.Map, target.Act or ""))
        return true, joinValue, "DragonWish", snapshot
    end
    self:SetStatus("Dragon Wish chỉ còn objective passive/unsupported hoặc thiếu Macro; nhường automation thấp hơn.")
    return false, nil, nil, snapshot
end
function EventAuto:Tick(stateInfo)
    local directive = {BlockNormalJoin = false, BlockNormalSummon = false, JoinValue = nil, Owner = nil}
    if not appConfig.EventAuto.autoBossBounty and type(self.Runtime.ActiveTarget) == "table" and self.Runtime.ActiveTarget.Owner == "BossBounty" then self.Runtime.ActiveTarget = nil end
    if not appConfig.EventAuto.autoDragonWish and type(self.Runtime.ActiveTarget) == "table" and self.Runtime.ActiveTarget.Owner == "DragonWish" then self.Runtime.ActiveTarget = nil end
    if self:RunGuess(stateInfo) then
        directive.BlockNormalJoin = true
        directive.BlockNormalSummon = true
        self:UpdateDisplay(nil)
        return directive
    end
    local bossBlocks, bossJoin, bossOwner = self:RunBoss(stateInfo)
    if bossBlocks then
        directive.BlockNormalJoin = true
        directive.BlockNormalSummon = true
        directive.JoinValue = bossJoin
        directive.Owner = bossOwner
        self:UpdateDisplay(nil)
        return directive
    end
    local dragonBlocks, dragonJoin, dragonOwner, snapshot = self:RunDragon(stateInfo)
    directive.BlockNormalJoin = dragonBlocks == true
    directive.BlockNormalSummon = dragonBlocks == true
    directive.JoinValue = dragonJoin
    directive.Owner = dragonOwner
    if not appConfig.EventAuto.autoGuessUnit and not appConfig.EventAuto.autoBossBounty and not appConfig.EventAuto.autoDragonWish then
        self:SetStatus("Auto Event đang tắt.")
    end
    self:UpdateDisplay(snapshot)
    return directive
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
local expeditionWebhookState = {
    itemData = snapshotItemData(),
    unitData = snapshotUnitData(),
    equipmentData = snapshotEquipmentData(),
    provisionalItemData = nil,
    provisionalUnitData = nil,
    provisionalEquipmentData = nil,
    lastMatchesPlayed = nil,
}
expeditionWebhookState.provisionalItemData = expeditionWebhookState.itemData
expeditionWebhookState.provisionalUnitData = expeditionWebhookState.unitData
expeditionWebhookState.provisionalEquipmentData = expeditionWebhookState.equipmentData
getgenv().AnimeExpeditionsWebhookProvisionalItemData = getgenv().StartItemData
getgenv().AnimeExpeditionsWebhookProvisionalUnitData = getgenv().StartUnitData
getgenv().AnimeExpeditionsWebhookProvisionalEquipmentData = getgenv().StartEquipmentData
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
    if #itemLines == 0 then table.insert(itemLines, localizeText("*Không nhận được Item nào*")) end
    if #unitLines == 0 then table.insert(unitLines, localizeText("*Không có Unit nào nhận EXP*")) end
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
    }, newItemData, newUnitData, newEquipmentData
end
local function sendWebhook(payload)
    local webhookUrl = tostring(appConfig.WebhookUrl or "")
    if webhookUrl == "" then
        return false, localizeText("Webhook URL trống!")
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
    if not ok or type(resp) ~= "table" then return false, localizeText("Lỗi HTTP Request") end
    local status = tonumber(resp.StatusCode)
    if not status then return false, localizeText("Discord trả response không hợp lệ") end
    if status >= 200 and status < 300 then
        return true, localizeText("Gửi Discord thành công!"), status
    else
        local retryAfter
        if status == 429 then
            pcall(function()
                local decoded = HttpService:JSONDecode(tostring(resp.Body or ""))
                retryAfter = tonumber(decoded.retry_after)
            end)
        end
        return false, string.format(localizeText("Discord từ chối (Mã %s)"), tostring(status)), status, retryAfter
    end
end
getgenv().AnimeExpeditionsWebhookQueue = type(getgenv().AnimeExpeditionsWebhookQueue) == "table" and getgenv().AnimeExpeditionsWebhookQueue or {}
getgenv().AnimeExpeditionsWebhookBuildPending = nil
getgenv().AnimeExpeditionsEnqueueWebhook = function(entry)
    local queue = getgenv().AnimeExpeditionsWebhookQueue
    if entry then table.insert(queue, entry) end
    if getgenv().AnimeExpeditionsWebhookWorker then
        task.delay(1, function()
            if expeditionScriptIsCurrent() then getgenv().AnimeExpeditionsEnqueueWebhook() end
        end)
        return
    end
    if #queue == 0 then return end
    local workerToken = {}
    getgenv().AnimeExpeditionsWebhookWorker = workerToken
    task.spawn(function()
        while expeditionScriptIsCurrent() and getgenv().AnimeExpeditionsWebhookWorker == workerToken and #queue > 0 do
            local current = queue[1]
            local success, message, status
            for attempt = 1, 3 do
                if not expeditionScriptIsCurrent() or getgenv().AnimeExpeditionsWebhookWorker ~= workerToken then break end
                local retryAfter
                success, message, status, retryAfter = sendWebhook(current.Payload)
                if not expeditionScriptIsCurrent() or getgenv().AnimeExpeditionsWebhookWorker ~= workerToken then break end
                if success or status == 400 or status == 401 or status == 404 then break end
                if attempt < 3 then task.wait(status == 429 and math.max(1, tonumber(retryAfter) or 3) or (attempt == 1 and 3 or 10)) end
            end
            if not expeditionScriptIsCurrent() or getgenv().AnimeExpeditionsWebhookWorker ~= workerToken then break end
            if success then
                if current.CommitItemData then
                    getgenv().StartItemData = current.CommitItemData
                    getgenv().StartUnitData = current.CommitUnitData
                    getgenv().StartEquipmentData = current.CommitEquipmentData
                    if current.IsExpedition then
                        expeditionWebhookState.itemData = current.CommitItemData
                        expeditionWebhookState.unitData = current.CommitUnitData
                        expeditionWebhookState.equipmentData = current.CommitEquipmentData
                    end
                end
                table.remove(queue, 1)
                Fluent:Notify({Title = "Webhook", Content = message, Duration = 5})
            elseif status == 400 then
                if current.CommitItemData then
                    getgenv().StartItemData = current.CommitItemData
                    getgenv().StartUnitData = current.CommitUnitData
                    getgenv().StartEquipmentData = current.CommitEquipmentData
                end
                table.remove(queue, 1)
                Fluent:Notify({Title = "Webhook payload bị từ chối", Content = message, Duration = 7})
            else
                local delay = (status == 401 or status == 404) and 60 or 30
                warn("[WEBHOOK] Payload vẫn trong queue; retry lại sau " .. tostring(delay) .. " giây: " .. tostring(message))
                Fluent:Notify({Title = "Webhook đang chờ retry", Content = tostring(message), Duration = 7})
                task.wait(delay)
            end
        end
        if getgenv().AnimeExpeditionsWebhookWorker == workerToken then getgenv().AnimeExpeditionsWebhookWorker = nil end
    end)
end
for index = #getgenv().AnimeExpeditionsWebhookQueue, 1, -1 do
    local queued = getgenv().AnimeExpeditionsWebhookQueue[index]
    if queued.CommitItemData then
        getgenv().AnimeExpeditionsWebhookProvisionalItemData = queued.CommitItemData
        getgenv().AnimeExpeditionsWebhookProvisionalUnitData = queued.CommitUnitData
        getgenv().AnimeExpeditionsWebhookProvisionalEquipmentData = queued.CommitEquipmentData
        if queued.IsExpedition then
            expeditionWebhookState.provisionalItemData = queued.CommitItemData
            expeditionWebhookState.provisionalUnitData = queued.CommitUnitData
            expeditionWebhookState.provisionalEquipmentData = queued.CommitEquipmentData
        end
        break
    end
end
getgenv().AnimeExpeditionsEnqueueWebhook()
getgenv().AnimeExpeditionsCoordinator.PostStatRollWebhook = function(self, unitId, unit, stat, grade, confirmedRolls)
    local asset = tostring(self:Peek(unit.Asset) or "Unknown")
    local displayName = asset
    pcall(function() displayName = tostring(Dependencies.Information:GetAssetDisplayName(asset) or asset) end)
    local worthiness = tonumber(self:Peek(unit.Worthiness)) or 0
    local payload = {
        username = "Anime Expeditions Auto",
        avatar_url = gameIconUrl,
        embeds = {{
            title = localizeText("Auto Stat Roll đạt mục tiêu"),
            color = grade == "Z" and 16766720 or 10181046,
            fields = {
                {name = "Unit", value = displayName .. " [" .. self:GetTrainingUnitRarity(unit) .. "]", inline = true},
                {name = localizeText("Chỉ số"), value = tostring(stat) .. " " .. tostring(grade), inline = true},
                {name = localizeText("Potential còn lại"), value = tostring(math.floor(worthiness / math.max(1, Dependencies.Information.StatPotential.WorthinessPerRoll) * 100 + 0.5)) .. "%", inline = true},
                {name = localizeText("Tiến độ"), value = tostring(confirmedRolls) .. "/4 roll", inline = true},
                {name = localizeText("Toàn bộ stat"), value = string.format("Damage %s | SPA %s | Range %s", self:GetStatRollGrade(unit, "Damage"), self:GetStatRollGrade(unit, "SPA"), self:GetStatRollGrade(unit, "Range")), inline = false},
                {name = "Unit ID", value = "`" .. tostring(unitId) .. "`", inline = false},
            },
            timestamp = DateTime.now():ToIsoDate(),
            footer = {text = "Anime Expeditions Ultimate"},
        }},
    }
    getgenv().AnimeExpeditionsEnqueueWebhook({Payload = payload})
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
                title = "🎉 " .. localizeText("Tự Động Triệu Hồi Thành Công!"),
                description = string.format(localizeText("Tài khoản **%s** vừa quay ra Unit xịn!"), game.Players.LocalPlayer.Name),
                color = 16766720,
                fields = {
                    { name = "Unit", value = unitName, inline = true },
                    { name = localizeText("Độ Hiếm"), value = rarity, inline = true }
                }
            }
        }
    }
    getgenv().AnimeExpeditionsEnqueueWebhook({Payload = data})
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
local lastStateInfo = nil
local lastSentTime = 0
local autoClaimTimes = {Quests = 0, Index = 0, Achievements = 0, Codes = 0, ExpeditionVoteActive = false, ExpeditionVotePrevious = false, ExpeditionVoteLastCheck = 0}
local function teleportScreenVisible()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return false end
    for _, object in ipairs(playerGui:GetDescendants()) do
        if object:IsA("TextLabel") and object.Visible
            and tostring(object.Text):lower():find("teleporting", 1, true) then
            return true
        end
    end
    return false
end
task.spawn(function()
    while expeditionScriptIsCurrent() and task.wait(0.25) do
        local schedulerOk, schedulerError = xpcall(function()
        pcall(checkNewSummonedUnits)
        local stateInfo = getGameStates()
        local coordinator = getgenv().AnimeExpeditionsCoordinator
        local mapSwitchBlocking = coordinator and coordinator:CheckMapSwitch(stateInfo) or false
        local inExpedition = stateInfo ~= nil and stateInfo.Gamemode == "Expedition" and stateInfo.CurrentGameState ~= "Lobby"
        if not getgenv().AnimeExpeditionsMapSwitchPending and appConfig.expeditionAutoVoteStart and inExpedition then
            if not autoClaimTimes.ExpeditionVoteActive then
                autoClaimTimes.ExpeditionVoteActive = true
                pcall(function() autoClaimTimes.ExpeditionVotePrevious = Actions.GetSettingValue("AutoVoteStart") == true end)
            end
            if tick() - autoClaimTimes.ExpeditionVoteLastCheck >= 1 then
                autoClaimTimes.ExpeditionVoteLastCheck = tick()
                pcall(function()
                    if Actions.GetSettingValue("AutoVoteStart") ~= true then Actions.ChangeSetting("AutoVoteStart", true) end
                end)
            end
        elseif not getgenv().AnimeExpeditionsMapSwitchPending and autoClaimTimes.ExpeditionVoteActive and (not appConfig.expeditionAutoVoteStart or not inExpedition) then
            if not autoClaimTimes.ExpeditionVotePrevious then
                pcall(function() Actions.ChangeSetting("AutoVoteStart", false) end)
            end
            autoClaimTimes.ExpeditionVoteActive = false
            autoClaimTimes.ExpeditionVotePrevious = false
            autoClaimTimes.ExpeditionVoteLastCheck = 0
        end
        local joinLock = getgenv().AnimeExpeditionsJoinLock
        if joinLock and not (coordinator and coordinator.MapSwitch) then
            local currentState = stateInfo and tostring(stateInfo.CurrentGameState or "") or ""
            local currentMode = stateInfo and tostring(stateInfo.Gamemode or ""):lower():gsub("[^%w]", "") or ""
            local targetMode = tostring(joinLock.TargetMode or ""):lower():gsub("[^%w]", "")
            local incrementChanged = stateInfo and tonumber(stateInfo.GameIncrement) ~= tonumber(joinLock.BaseIncrement)
            local activeState = currentState ~= "" and currentState ~= "nil" and currentState ~= "Lobby"
                and currentState ~= "Finished" and currentState ~= "Victory" and currentState ~= "Defeat"
            local modeMatches = targetMode == "" or targetMode == "challenge" and currentMode:find("challenge", 1, true) ~= nil or currentMode == targetMode
            local challengeMatches = targetMode ~= "challenge" or stateInfo
                and tostring(stateInfo.ChallengeType or "") ~= ""
                and stateInfo.ChallengeIndex ~= nil
                and tostring(stateInfo.ChallengeType):lower() == tostring(joinLock.ChallengeType or ""):lower()
                and tonumber(stateInfo.ChallengeIndex) == tonumber(joinLock.ChallengeIndex)
            if incrementChanged and activeState and modeMatches and challengeMatches then
                getgenv().AnimeExpeditionsJoinLock = nil
            elseif tick() - (joinLock.SentAt or 0) >= 60 or not teleportScreenVisible() and tick() - (joinLock.SentAt or 0) >= 45 then
                getgenv().AnimeExpeditionsJoinLock = nil
            end
        end
        local maintenanceBlocking = mapSwitchBlocking or (not getgenv().AnimeExpeditionsMapSwitchPending and coordinator and coordinator:BeforeAutomation(
            stateInfo,
            EventAuto:TargetMatchesState(stateInfo),
            QuestAuto:TargetMatchesState(stateInfo),
            challengeTargetMatchesState(stateInfo)
        ) or false)
        if coordinator and not getgenv().AnimeExpeditionsMapSwitchPending and (not stateInfo or stateInfo.CurrentGameState == "Lobby") then
            maintenanceBlocking = coordinator:RunQuestBoardClaims() or maintenanceBlocking
        end
        local eventDirective = {BlockNormalJoin = false, BlockNormalSummon = false, JoinValue = nil, Owner = nil}
        local questDirective = {BlockNormalJoin = false, BlockNormalSummon = false, JoinValue = nil}
        local challengeDirective = {BlockNormalJoin = false, JoinValue = nil}
        if maintenanceBlocking then
            eventDirective.BlockNormalJoin = true
            eventDirective.BlockNormalSummon = true
            questDirective.BlockNormalJoin = true
            questDirective.BlockNormalSummon = true
            challengeDirective.BlockNormalJoin = true
        else
            local eventOk, eventResult = xpcall(function() return EventAuto:Tick(stateInfo) end, debug.traceback)
            if eventOk and type(eventResult) == "table" then
                eventDirective = eventResult
                EventAuto.Runtime.ErrorCount = 0
            elseif not eventOk then
                eventDirective.BlockNormalJoin = true
                eventDirective.BlockNormalSummon = true
                EventAuto.Runtime.ErrorCount = (EventAuto.Runtime.ErrorCount or 0) + 1
                if tick() - (EventAuto.Runtime.LastErrorAt or 0) >= 10 then
                    EventAuto.Runtime.LastErrorAt = tick()
                    warn("[AUTO EVENT] " .. tostring(eventResult))
                end
                if EventAuto.Runtime.ErrorCount >= 3 then
                    appConfig.EventAuto.autoGuessUnit = false
                    appConfig.EventAuto.autoBossBounty = false
                    appConfig.EventAuto.autoDragonWish = false
                    EventAuto.Runtime.ActiveTarget = nil
                    EventAuto.Runtime.Pending = nil
                    saveConfig()
                    Fluent:Notify({Title = "Auto Event Disabled", Content = "Controller lỗi 3 lần liên tiếp; đã tắt để mở khóa scheduler.", Duration = 7})
                end
            end
            local eventWaitingInLobby = eventDirective.BlockNormalJoin and eventDirective.JoinValue == nil
                and type(EventAuto.Runtime.ActiveTarget) ~= "table"
                and (not stateInfo or stateInfo.CurrentGameState == "Lobby")
            if eventWaitingInLobby then
                EventAuto.Runtime.LobbyBlockedSince = EventAuto.Runtime.LobbyBlockedSince or tick()
                if tick() - EventAuto.Runtime.LobbyBlockedSince >= 15 then
                    eventDirective.BlockNormalJoin = false
                    eventDirective.BlockNormalSummon = false
                end
            else
                EventAuto.Runtime.LobbyBlockedSince = nil
            end
            local eventOwnsPriority = eventDirective.BlockNormalJoin or eventDirective.JoinValue ~= nil
            if not eventOwnsPriority then
            do
                local questOk, questResult = xpcall(function() return QuestAuto:Tick(stateInfo) end, debug.traceback)
                if questOk and type(questResult) == "table" then
                    questDirective = questResult
                    QuestAuto.Runtime.ErrorCount = 0
                elseif not questOk then
                    questDirective.BlockNormalJoin = true
                    questDirective.BlockNormalSummon = true
                    QuestAuto.Runtime.ErrorCount = (QuestAuto.Runtime.ErrorCount or 0) + 1
                    if tick() - (QuestAuto.Runtime.LastErrorAt or 0) >= 10 then
                        QuestAuto.Runtime.LastErrorAt = tick()
                        warn("[AUTO QUEST] " .. tostring(questResult))
                    end
                    if QuestAuto.Runtime.ErrorCount >= 3 then
                        appConfig.QuestAuto.Enabled = false
                        appConfig.QuestAuto.ActiveTarget = nil
                        QuestAuto.Runtime.Pending = nil
                        saveConfig()
                        if QuestAuto.Toggle then task.defer(function() pcall(function() QuestAuto.Toggle:SetValue(false) end) end) end
                        Fluent:Notify({Title = "Auto Quest Disabled", Content = "Controller lỗi 3 lần liên tiếp; đã tắt để mở khóa scheduler.", Duration = 7})
                    end
                end
                local questWaitingInLobby = questDirective.BlockNormalJoin and questDirective.JoinValue == nil
                    and type(appConfig.QuestAuto.ActiveTarget) ~= "table"
                    and (not stateInfo or stateInfo.CurrentGameState == "Lobby")
                if questWaitingInLobby then
                    QuestAuto.Runtime.LobbyBlockedSince = QuestAuto.Runtime.LobbyBlockedSince or tick()
                    if tick() - QuestAuto.Runtime.LobbyBlockedSince >= 15 then
                        questDirective.BlockNormalJoin = false
                        questDirective.BlockNormalSummon = false
                    end
                else
                    QuestAuto.Runtime.LobbyBlockedSince = nil
                end
            end
            else
                QuestAuto:SetStatus("Đang chờ Auto Event hoàn tất...")
                QuestAuto:UpdateDisplay(QuestAuto:Snapshot())
                questDirective.BlockNormalJoin = true
                questDirective.BlockNormalSummon = true
            end
            local questTarget = appConfig.QuestAuto.Enabled and appConfig.QuestAuto.ActiveTarget or nil
            local questOwnsPriority = type(questTarget) == "table" and questTarget.Owner == "Quest"
                or questDirective.BlockNormalJoin or questDirective.JoinValue ~= nil
            local challengeCanTakePriority = not questOwnsPriority
            if challengeCanTakePriority then
                local challengeOk, challengeResult = xpcall(function()
                    return runChallengeTick(stateInfo, challengeCanTakePriority)
                end, debug.traceback)
                if challengeOk and type(challengeResult) == "table" then
                    challengeDirective = challengeResult
                    challengeRuntime.ErrorCount = 0
                elseif not challengeOk then
                    challengeDirective.BlockNormalJoin = true
                    challengeRuntime.ErrorCount = (challengeRuntime.ErrorCount or 0) + 1
                    if tick() - (challengeRuntime.LastErrorAt or 0) >= 10 then
                        challengeRuntime.LastErrorAt = tick()
                        warn("[AUTO CHALLENGE] " .. tostring(challengeResult))
                    end
                    if challengeRuntime.ErrorCount >= 3 then
                        appConfig.autoChallengeEnabled = false
                        appConfig.autoDailyChallengeEnabled = false
                        appConfig.challengeActiveTarget = nil
                        challengeDirective.BlockNormalJoin = false
                        saveConfig()
                        Fluent:Notify({Title = "Auto Challenge Disabled", Content = "Controller lỗi 3 lần liên tiếp; đã tắt để mở khóa Auto Join.", Duration = 7})
                    end
                end
            else
                setChallengeStatus(eventOwnsPriority and "Đang chờ Auto Event hoàn tất..." or "Đang chờ Auto Quest hoàn tất...")
                updateChallengeDisplay(getRegularChallengeState())
            end
        end
        if coordinator and not coordinator.MapSwitch and stateInfo and eventDirective.JoinValue
            and (stateInfo.CurrentGameState == "Finished" or stateInfo.CurrentGameState == "Victory" or stateInfo.CurrentGameState == "Defeat") then
            coordinator:BeginMapSwitchResolution(eventDirective.Owner or "Event", "Auto Event cần đổi map", stateInfo)
        end
        if coordinator and not coordinator.MapSwitch and stateInfo and appConfig.autoJoinEnabled and appConfig.AutoJoin ~= ""
            and tick() >= (getgenv().AnimeExpeditionsAutoJoinCooldownUntil or 0)
            and (stateInfo.CurrentGameState == "Finished" or stateInfo.CurrentGameState == "Victory" or stateInfo.CurrentGameState == "Defeat")
            and not eventDirective.BlockNormalJoin and eventDirective.JoinValue == nil
            and not questDirective.BlockNormalJoin and questDirective.JoinValue == nil
            and not challengeDirective.BlockNormalJoin and challengeDirective.JoinValue == nil
            and not (type(appConfig.QuestAuto.ActiveTarget) == "table" and appConfig.QuestAuto.ActiveTarget.Owner == "Quest")
            and not (type(appConfig.challengeActiveTarget) == "table" and appConfig.challengeActiveTarget.Owner == "Challenge")
            and not maintenanceBlocking and not getgenv().AnimeExpeditionsJoinLock
            and not EventAuto:TargetMatchesState(stateInfo) and not QuestAuto:TargetMatchesState(stateInfo) and not challengeTargetMatchesState(stateInfo) then
            local autoJoinParts = string.split(appConfig.AutoJoin, "|")
            local desiredMode = autoJoinParts[1] == "Challenge" and "Challenge" or tostring(autoJoinParts[1] or "")
            local desiredMap = tostring(autoJoinParts[2] or "")
            local modeDiffers = desiredMode ~= "" and desiredMode:lower() ~= tostring(stateInfo.Gamemode or ""):lower()
            local mapDiffers = desiredMap ~= "" and tostring(stateInfo.Map or "") ~= "" and desiredMap:lower() ~= tostring(stateInfo.Map or ""):lower()
            if modeDiffers or mapDiffers then coordinator:BeginMapSwitchResolution("AutoJoin", "Auto Join cần đổi map", stateInfo) end
        end
        if coordinator and coordinator.MapSwitch and coordinator.MapSwitch.Phase == "Resolve" then
            local switchJoinValue = eventDirective.JoinValue or questDirective.JoinValue or challengeDirective.JoinValue
            local switchOwner = eventDirective.JoinValue and eventDirective.Owner or (questDirective.JoinValue and "Quest" or (challengeDirective.JoinValue and "Challenge" or nil))
            local higherPriorityOwned = eventDirective.BlockNormalJoin or questDirective.BlockNormalJoin or challengeDirective.BlockNormalJoin
                or type(appConfig.QuestAuto.ActiveTarget) == "table" and appConfig.QuestAuto.ActiveTarget.Owner == "Quest"
                or type(appConfig.challengeActiveTarget) == "table" and appConfig.challengeActiveTarget.Owner == "Challenge"
            if not switchJoinValue and not eventDirective.BlockNormalJoin and not questDirective.BlockNormalJoin and not challengeDirective.BlockNormalJoin
                and not higherPriorityOwned
                and tick() >= (getgenv().AnimeExpeditionsAutoJoinCooldownUntil or 0)
                and appConfig.autoJoinEnabled and appConfig.AutoJoin ~= "" then
                switchJoinValue = appConfig.AutoJoin
                switchOwner = "AutoJoin"
            end
            if switchJoinValue then
                coordinator:StartMapSwitch(switchJoinValue, switchOwner, stateInfo)
            elseif coordinator.MapSwitch and coordinator.MapSwitch.Owner == "AutoJoin" and higherPriorityOwned then
                coordinator:FinishMapSwitch(stateInfo, "Đã hủy Auto Join Map vì automation ưu tiên cao hơn vẫn chưa xong.")
            end
        end
        if getgenv().AnimeExpeditionsMapSwitchPending then
            lastStateInfo = stateInfo
            return
        end
        if appConfig.autoClaimQuests and tick() - autoClaimTimes.Quests >= 2 then
            autoClaimTimes.Quests = tick()
            pcall(function() Actions.ClaimAllQuests() end)
            pcall(function()
                local categories = {}
                for _, eventData in pairs(EventsInfo) do
                    if type(eventData) == "table" and type(eventData.QuestCategories) == "table" then
                        for _, category in ipairs(eventData.QuestCategories) do table.insert(categories, category) end
                    end
                end
                if #categories > 0 then Actions.ClaimQuestCategories(categories) end
            end)
        end
        local matchesPlayedIncreased = false
        local sessionMatchesPlayed = getSessionMatchesPlayed() or (stateInfo and stateInfo.SessionMatchesPlayed)
        if sessionMatchesPlayed ~= nil then
            if expeditionWebhookState.lastMatchesPlayed == nil or sessionMatchesPlayed < expeditionWebhookState.lastMatchesPlayed then
                expeditionWebhookState.itemData = snapshotItemData()
                expeditionWebhookState.unitData = snapshotUnitData()
                expeditionWebhookState.equipmentData = snapshotEquipmentData()
                expeditionWebhookState.provisionalItemData = expeditionWebhookState.itemData
                expeditionWebhookState.provisionalUnitData = expeditionWebhookState.unitData
                expeditionWebhookState.provisionalEquipmentData = expeditionWebhookState.equipmentData
            else
                matchesPlayedIncreased = sessionMatchesPlayed >= expeditionWebhookState.lastMatchesPlayed + 1
            end
            expeditionWebhookState.lastMatchesPlayed = sessionMatchesPlayed
        end
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
            local macroList = getMacroListForStage(skey, stateInfo)
            local macroCount = macroList and #macroList or 0
            safeSetParagraphDesc(currentMacroPara, string.format(localizeText("Đang ở: %s\nSố lệnh Macro đã lưu: %d"), skey, macroCount))
        else
            safeSetParagraphDesc(currentMacroPara, "Đang ở Lobby...")
            lastHasRunMacro = false
            isPlaying = false
        end
        if stateInfo and lastStateInfo and stateInfo.Gamemode ~= "Expedition" and stateInfo.Wave == 1 and lastStateInfo.Wave > 1 then
            lastHasRunMacro = false
            isPlaying = false
        end
        if not stateInfo or stateInfo.CurrentGameState == "Lobby" then
            if maintenanceBlocking and coordinator then
                coordinator:ProcessMandatory(stateInfo)
            else
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
            if appConfig.autoClaimIndex and tick() - autoClaimTimes.Index >= 15 then
                autoClaimTimes.Index = tick()
                for _, indexType in ipairs({"Unit", "Enemy", "Equipment"}) do
                    pcall(function() Actions.IndexClaimAllRewards(indexType) end)
                end
            end
            if appConfig.autoClaimAchievements and tick() - autoClaimTimes.Achievements >= 15 then
                autoClaimTimes.Achievements = tick()
                for _, categoryId in ipairs(achievementCategoryIds) do
                    pcall(function() Actions.ClaimQuestCategory(categoryId) end)
                    pcall(function() Actions.ClaimAchievementCategory(categoryId) end)
                end
            end
            if appConfig.autoRedeemCodes and tick() - autoClaimTimes.Codes >= 600 then
                autoClaimTimes.Codes = tick()
                task.spawn(function()
                    local ok, response = pcall(request, {Url = getgenv().AnimeExpeditionsMacroShare.BaseUrl .. "/api/codes", Method = "GET"})
                    local decodedOk, decoded = false, nil
                    if ok and response and response.Body then decodedOk, decoded = pcall(function() return HttpService:JSONDecode(response.Body) end) end
                    local codes = decodedOk and type(decoded) == "table" and decoded.ok == true and decoded.codes
                    if type(codes) ~= "table" then return end
                    local playerData = Fusion.peek(Dependencies.PlayerData)
                    local claimedCodes = type(playerData) == "table" and Fusion.peek(playerData.ClaimedCodes) or {}
                    local redeemed = 0
                    for _, code in ipairs(codes) do
                        if type(code) == "string" and code:match("^[%w%+!#_%-]+$") and type(claimedCodes) == "table" and not claimedCodes[code] then
                            pcall(function() Actions.RedeemCode(code) end)
                            redeemed += 1
                            task.wait(0.1)
                        end
                    end
                    if redeemed > 0 then Fluent:Notify({Title = "Auto Nhập Code", Content = string.format(localizeText("Đã gửi %d code active từ Wiki."), redeemed), Duration = 5}) end
                end)
            end
            local shopBlockedJoin = false
            if appConfig.autoShopEnabled and coordinator then
                coordinator.ShopSkipped = coordinator.ShopSkipped or {}
                coordinator.ShopWaitAt = coordinator.ShopWaitAt or {}
                local pending = coordinator.ShopPending
                if pending then
                    local currentAmount, _, ready = getAutoShopPurchasableAmount(pending.Entry)
                    if not ready and tick() - pending.SentAt < 2 then
                        shopBlockedJoin = true
                    elseif not ready then
                        coordinator.ShopSkipped[pending.Key] = true
                        coordinator.ShopPending = nil
                        warn("[AUTO SHOP] Replica unavailable for " .. pending.Key .. "; skipping this Lobby cycle")
                    elseif currentAmount < pending.BeforeAmount then
                        print("[AUTO SHOP] Confirmed: " .. pending.Key)
                        coordinator.ShopPending = nil
                    elseif tick() - pending.SentAt < 2 then
                        shopBlockedJoin = true
                    else
                        coordinator.ShopSkipped[pending.Key] = true
                        coordinator.ShopPending = nil
                        warn("[AUTO SHOP] Server did not accept " .. pending.Key .. "; skipping this Lobby cycle")
                    end
                end
                if not coordinator.ShopPending then
                    for storeId, products in pairs(appConfig.ShopSelections) do
                        for _, productId in ipairs(type(products) == "table" and products or {}) do
                            local entry
                            for _, shopItem in ipairs(allShops) do
                                if shopItem.StoreId == tostring(storeId) and shopItem.ProductId == tostring(productId) then entry = shopItem break end
                            end
                            if entry then
                                local key = tostring(entry.DataKey) .. ":" .. tostring(entry.ShopKey) .. ":" .. tostring(entry.ProductId)
                                local amount, itemIndex, ready = getAutoShopPurchasableAmount(entry)
                                if not ready and not coordinator.ShopSkipped[key] then
                                    coordinator.ShopWaitAt[key] = coordinator.ShopWaitAt[key] or tick()
                                    if tick() - coordinator.ShopWaitAt[key] < 2 then
                                        shopBlockedJoin = true
                                        break
                                    end
                                    coordinator.ShopSkipped[key] = true
                                    warn("[AUTO SHOP] Replica unavailable for " .. key .. "; skipping this Lobby cycle")
                                elseif ready then
                                    coordinator.ShopWaitAt[key] = nil
                                end
                                if ready and amount > 0 and not coordinator.ShopSkipped[key] then
                                    local ok, err = pcall(function()
                                        if entry.PurchaseKind == "ExpeditionShop" then
                                            Actions.ExpeditionShopPurchaseItem(entry.ShopKey, itemIndex, amount)
                                        else
                                            Actions.ShopPurchaseItem(entry.DataKey, entry.ShopKey, itemIndex, amount)
                                        end
                                    end)
                                    if ok then
                                        coordinator.ShopPending = {Key = key, Entry = entry, BeforeAmount = amount, SentAt = tick()}
                                        coordinator:SetStatus(string.format("Buying %dx %s before Join", amount, entry.ProductId))
                                        print(string.format("[AUTO SHOP] %s/%s: requested max %d x %s", entry.DataKey, entry.ShopKey, amount, entry.ProductId))
                                        shopBlockedJoin = true
                                        break
                                    end
                                    coordinator.ShopSkipped[key] = true
                                    warn("[AUTO SHOP] Purchase failed: " .. tostring(err))
                                end
                            end
                        end
                        if coordinator.ShopPending or shopBlockedJoin then break end
                    end
                end
                shopBlockedJoin = shopBlockedJoin or coordinator.ShopPending ~= nil
            elseif coordinator then
                coordinator.ShopPending = nil
                coordinator.ShopSkipped = {}
                coordinator.ShopWaitAt = {}
            end
            if appConfig.autoSummonEnabled and not eventDirective.BlockNormalSummon and not questDirective.BlockNormalSummon then
                local targetBanner = getActiveTargetBanner()
                if targetBanner then
                    local summonAmount = appConfig.autoSummonAmount
                    if summonAmount == "Max" then
                        local currentBannerData = Fusion.peek(Dependencies.BannerData)
                        local bannerState = currentBannerData and currentBannerData[targetBanner]
                        local bannerInfo = bannerState and Fusion.peek(bannerState.BannerInfo)
                        local cost = tonumber(bannerInfo and Fusion.peek(bannerInfo.Cost)) or 0
                        local currency = tostring(bannerInfo and Fusion.peek(bannerInfo.Currency) or "Gem")
                        summonAmount = cost > 0 and math.min(50, math.floor((snapshotItemData()[currency] or 0) / cost)) or 0
                    end
                    summonAmount = tonumber(summonAmount) or 0
                    if summonAmount > 0 then
                        pcall(function() Actions.Summon(targetBanner, summonAmount) end)
                        task.wait(0.1)
                    end
                end
            end
            local craftBlockedJoin = coordinator and coordinator:RunCraftPreparation(stateInfo) or false
            local function AutoStartMatchmaking(levelData)
                local ok, err = pcall(function()
                    Actions.StartMatchmaking(levelData)
                end)
                if ok then
                    return true
                end
                return false
            end
            local blockAutoJoinForScrapCraft = false
            if appConfig.expeditionScrapCraftPending then
                local ok, playerData = pcall(function() return Fusion.peek(Dependencies.PlayerData) end)
                local itemDataReady = ok and type(playerData) == "table" and type(playerData.ItemData) == "table"
                local currentScrap = itemDataReady and (snapshotItemData()["EquipmentScrap"] or 0) or nil
                local pendingSince = tonumber(appConfig.expeditionScrapCraftPendingSince) or 0
                if itemDataReady and pendingSince <= 0 then
                    pendingSince = os.time()
                    appConfig.expeditionScrapCraftPendingSince = pendingSince
                    saveConfig()
                end
                if currentScrap and currentScrap < 250 then
                    appConfig.expeditionScrapCraftPending = false
                    appConfig.expeditionScrapCraftPendingSince = 0
                    saveConfig()
                    Fluent:Notify({Title = "Auto Craft Expedition", Content = "Đã Craft xong. Đang tiếp tục Auto Join Expedition!", Duration = 5})
                elseif currentScrap and (not appConfig.autoExpeditionCraftEnabled or #appConfig.autoExpeditionCraftItems == 0 or os.time() - pendingSince >= 15) then
                    appConfig.expeditionScrapCraftPending = false
                    appConfig.expeditionScrapCraftPendingSince = 0
                    appConfig.autoLeaveExpeditionScrapMax = false
                    saveConfig()
                    Fluent:Notify({Title = "Không thể Craft Expedition", Content = "Equipment Scrap vẫn đầy. Đã tắt riêng Auto Leave Equipment Scrap để tránh lặp vô hạn.", Duration = 10})
                else
                    blockAutoJoinForScrapCraft = true
                end
            end
            local utilityBlockedJoin = not shopBlockedJoin and not craftBlockedJoin and coordinator and coordinator:RunBuildingResources(stateInfo) or false
            if not utilityBlockedJoin and not shopBlockedJoin and not craftBlockedJoin and coordinator then
                utilityBlockedJoin = coordinator:RunStatRoll(stateInfo)
            end
            local trainingRequired = coordinator and coordinator:TrainingRotationNeeded()
            if not utilityBlockedJoin and coordinator and (trainingRequired or (not eventDirective.BlockNormalJoin and not questDirective.BlockNormalJoin and not challengeDirective.BlockNormalJoin
                and not eventDirective.JoinValue and not questDirective.JoinValue and not challengeDirective.JoinValue)) then
                utilityBlockedJoin = coordinator:RunLobbyUtility(stateInfo)
            end
            local effectiveAutoJoin = eventDirective.JoinValue or questDirective.JoinValue or challengeDirective.JoinValue
            local joinOwner = eventDirective.JoinValue and eventDirective.Owner or (questDirective.JoinValue and "Quest" or (challengeDirective.JoinValue and "Challenge" or nil))
            if not effectiveAutoJoin and not eventDirective.BlockNormalJoin and not questDirective.BlockNormalJoin and not challengeDirective.BlockNormalJoin
                and not (type(appConfig.QuestAuto.ActiveTarget) == "table" and appConfig.QuestAuto.ActiveTarget.Owner == "Quest")
                and not (type(appConfig.challengeActiveTarget) == "table" and appConfig.challengeActiveTarget.Owner == "Challenge")
                and tick() >= (getgenv().AnimeExpeditionsAutoJoinCooldownUntil or 0)
                and appConfig.autoJoinEnabled and appConfig.AutoJoin ~= "" then
                effectiveAutoJoin = appConfig.AutoJoin
            end
            if effectiveAutoJoin and not joinOwner and #string.split(effectiveAutoJoin, "|") < 2 then
                warn("[AUTO JOIN] Invalid saved JoinValue; disabling Auto Join: " .. tostring(effectiveAutoJoin))
                appConfig.autoJoinEnabled = false
                saveConfig()
                task.defer(function()
                    local toggle = getgenv().AnimeExpeditionsAutoJoinToggle
                    if toggle then pcall(function() toggle:SetValue(false) end) end
                end)
                effectiveAutoJoin = nil
            end
            local joinStatus
            if not appConfig.autoJoinEnabled then joinStatus = "Auto Join đang tắt."
            elseif appConfig.AutoJoin == "" then joinStatus = "Chưa chọn Map."
            elseif eventDirective.BlockNormalJoin then joinStatus = "Đang chờ Auto Event."
            elseif questDirective.BlockNormalJoin then joinStatus = "Đang chờ Auto Quest."
            elseif challengeDirective.BlockNormalJoin then joinStatus = "Đang chờ Auto Challenge."
            elseif shopBlockedJoin then joinStatus = "Đang chờ Auto Shop."
            elseif craftBlockedJoin then joinStatus = "Đang chờ Auto Craft."
            elseif utilityBlockedJoin then joinStatus = "Đang chờ Lobby Utility."
            elseif blockAutoJoinForScrapCraft then joinStatus = "Đang chờ Craft Expedition Scrap."
            elseif coordinator and coordinator:HasMandatory() then joinStatus = "Đang chờ Mandatory Maintenance."
            elseif coordinator and coordinator:IsTransitionBusy() then joinStatus = "Đang chờ chuyển về Lobby."
            elseif getgenv().AnimeExpeditionsJoinLock then joinStatus = "Đang chờ JoinLock cũ hết hạn."
            elseif tick() < (getgenv().AnimeExpeditionsAutoJoinCooldownUntil or 0) then
                joinStatus = string.format(localizeText("Cooldown Join còn %.1fs."), (getgenv().AnimeExpeditionsAutoJoinCooldownUntil or 0) - tick())
            elseif effectiveAutoJoin then joinStatus = string.format(localizeText("Sẵn sàng gửi queue: %s"), tostring(effectiveAutoJoin))
            else joinStatus = "Scheduler chưa tạo được JoinValue."
            end
            safeSetParagraphDesc(AutoJoinStatusPara, joinStatus)
            if effectiveAutoJoin and not shopBlockedJoin and not craftBlockedJoin and not utilityBlockedJoin and not blockAutoJoinForScrapCraft
                and not (coordinator and (coordinator:HasMandatory() or coordinator:IsTransitionBusy()))
                and (joinOwner ~= nil or tick() >= (getgenv().AnimeExpeditionsAutoJoinCooldownUntil or 0))
                and not getgenv().AnimeExpeditionsJoinLock then
                local parts = string.split(effectiveAutoJoin, "|")
                if #parts >= 2 then
                    local isChallengeJoin = parts[1] == "Challenge"
                    local challengeTarget = isChallengeJoin
                        and (joinOwner == "DragonWish" and EventAuto.Runtime.ActiveTarget
                            or (joinOwner == "Quest" and appConfig.QuestAuto.ActiveTarget or appConfig.challengeActiveTarget))
                        or nil
                    local levelData
                    if joinOwner == "BossBounty" and type(EventAuto.Runtime.ActiveTarget) == "table" and type(EventAuto.Runtime.ActiveTarget.QueueData) == "table" then
                        levelData = table.clone(EventAuto.Runtime.ActiveTarget.QueueData)
                    elseif isChallengeJoin then
                        levelData = {
                            Gamemode = "Challenge",
                            ChallengeType = parts[2],
                            ChallengeIndex = tonumber(parts[3]) or 1,
                            MapName = type(challengeTarget) == "table" and tostring(challengeTarget.Map or "") or "",
                            ActName = type(challengeTarget) == "table" and tostring(challengeTarget.Act or "") or "",
                            Difficulty = type(challengeTarget) == "table" and tostring(challengeTarget.Difficulty or "Hard") or "Hard",
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
                    getgenv().AnimeExpeditionsJoinLock = {
                        Owner = joinOwner or "AutoJoin",
                        JoinValue = effectiveAutoJoin,
                        SentAt = tick(),
                        BaseIncrement = stateInfo and tonumber(stateInfo.GameIncrement),
                        TargetMode = levelData.Gamemode,
                        TargetMap = levelData.MapName,
                        ChallengeType = levelData.ChallengeType,
                        ChallengeIndex = levelData.ChallengeIndex,
                    }
                    if not joinOwner then getgenv().AnimeExpeditionsAutoJoinCooldownUntil = tick() + 30 end
                    local teamMap = isChallengeJoin and levelData.MapName or parts[2]
                    if appConfig.autoJoinTeamEnabled and appConfig.TeamSelections[teamMap] then
                        pcall(function() Actions.LoadUnitTeam(tostring(appConfig.TeamSelections[teamMap])) end)
                        task.wait(0.25)
                    end
                    if joinOwner == "BossBounty" or joinOwner == "DragonWish" then
                        if type(EventAuto.Runtime.ActiveTarget) == "table" then
                            EventAuto.Runtime.ActiveTarget.Owner = joinOwner
                            EventAuto.Runtime.ActiveTarget.JoinIssuedAt = os.time()
                            EventAuto.Runtime.ActiveTarget.JoinValue = effectiveAutoJoin
                            EventAuto.Runtime.ActiveTarget.MatchesPlayedAtJoin = getSessionMatchesPlayed() or (stateInfo and tonumber(stateInfo.SessionMatchesPlayed))
                        end
                        EventAuto.Runtime.LastJoinAt = tick()
                    elseif joinOwner == "Quest" then
                        if type(appConfig.QuestAuto.ActiveTarget) == "table" then
                            appConfig.QuestAuto.ActiveTarget.Owner = "Quest"
                            appConfig.QuestAuto.ActiveTarget.JoinIssuedAt = os.time()
                            appConfig.QuestAuto.ActiveTarget.JoinValue = effectiveAutoJoin
                            appConfig.QuestAuto.ActiveTarget.MatchesPlayedAtJoin = getSessionMatchesPlayed() or (stateInfo and tonumber(stateInfo.SessionMatchesPlayed))
                            saveConfig()
                        end
                        QuestAuto.Runtime.LastJoinAt = tick()
                    elseif joinOwner == "Challenge" then
                        if type(appConfig.challengeActiveTarget) == "table" then
                            appConfig.challengeActiveTarget.Owner = "Challenge"
                            appConfig.challengeActiveTarget.JoinIssuedAt = os.time()
                            appConfig.challengeActiveTarget.JoinValue = effectiveAutoJoin
                            saveConfig()
                        end
                        challengeRuntime.LastJoinAt = tick()
                    end
                    if appConfig.autoJoinMode == "Matchmaking (Multiplayer)" then
                        local matchmakingOk = AutoStartMatchmaking(levelData)
                        if not matchmakingOk then getgenv().AnimeExpeditionsJoinLock = nil end
                    else
                        local queueOk, queueError = pcall(function()
                            Actions.ToggleMenu("Play")
                            task.wait(0.5)
                            Actions.CancelMatchmaking()
                            task.wait(0.1)
                            Actions.SetQueueData(levelData)
                        end)
                        if not queueOk then
                            getgenv().AnimeExpeditionsJoinLock = nil
                            warn("[AUTO JOIN] SetQueueData failed: " .. tostring(queueError))
                        else
                            task.wait(0.2)
                            local startOk, startError = pcall(function() Actions.StartGame() end)
                            if startOk then
                                print("[AUTO JOIN] StartGame sent with queue: " .. HttpService:JSONEncode(levelData))
                                task.wait(5)
                            else
                                getgenv().AnimeExpeditionsJoinLock = nil
                                warn("[AUTO JOIN] StartGame failed: " .. tostring(startError))
                            end
                        end
                    end
                end
            end
            end
        else
            safeSetParagraphDesc(AutoJoinStatusPara, string.format(localizeText("GameState chưa được nhận là Lobby: %s | %s"), tostring(stateInfo.CurrentGameState), tostring(stateInfo.Gamemode)))
            if appConfig.autoJoinEnabled and appConfig.autoLeaveOnPlayerJoin and appConfig.autoJoinMode == "Start Instantly (Solo)" and stateInfo.CurrentGameState ~= "Lobby" and stateInfo.CurrentGameState ~= "Finished" then
                if #game:GetService("Players"):GetPlayers() > 1 then
                    local lastAutoReturnTrigger = getgenv().lastAutoReturnTrigger or 0
                    if tick() - lastAutoReturnTrigger > 5 then
                        getgenv().lastAutoReturnTrigger = tick()
                        Fluent:Notify({Title = "Phòng Lỗi", Content = "Phát hiện có người khác trong phòng Solo! Đang tự động thoát...", Duration = 5})
                        if coordinator then coordinator:RequestLobby("Safety", "Unexpected player in solo room", stateInfo)
                        else pcall(function() safeFireGameAction("Lobby") end) end
                    end
                end
            end
            if appConfig.autoJoinEnabled and appConfig.autoLeaveAfterMinutes and stateInfo.CurrentGameState ~= "Lobby" and stateInfo.CurrentGameState ~= "Finished" then
                local leaveAfterSeconds = math.max(1, tonumber(appConfig.autoLeaveAfterMinutesValue) or 30) * 60
                if (tonumber(stateInfo.GameTime) or 0) >= leaveAfterSeconds then
                    local lastTimerLeave = getgenv().AnimeExpeditionsTimerLeaveAt or 0
                    if tick() - lastTimerLeave >= 5 then
                        getgenv().AnimeExpeditionsTimerLeaveAt = tick()
                        Fluent:Notify({Title = "Auto Leave", Content = string.format(localizeText("Đã đủ %d phút. Đang về Lobby..."), math.floor(leaveAfterSeconds / 60)), Duration = 5})
                        if coordinator then coordinator:RequestLobby("Timer", "Match time limit reached", stateInfo)
                        else pcall(function() safeFireGameAction("Lobby") end) end
                    end
                end
            end
            if appConfig.autoJoinEnabled and appConfig.autoLeaveOnDefeat and stateInfo.CurrentGameState == "Finished" then
                if stateInfo.BaseHealth <= 0 then
                    local lastAutoReturnTrigger = getgenv().lastAutoReturnTrigger or 0
                    if tick() - lastAutoReturnTrigger > 5 then
                        getgenv().lastAutoReturnTrigger = tick()
                        Fluent:Notify({Title = "Auto Leave", Content = "Phát hiện thua cuộc! Đang tự động vứt trận về Lobby...", Duration = 5})
                        if coordinator then coordinator:RequestLobby("Safety", "Defeat", stateInfo)
                        else pcall(function() safeFireGameAction("Lobby") end) end
                    end
                end
            end
            if appConfig.autoJoinEnabled and appConfig.autoLeaveSpriteMax and stateInfo.CurrentGameState ~= "Lobby" and stateInfo.CurrentGameState ~= "Finished" then
                local currentSprites = snapshotItemData()["SpriteGrey"] or 0
                if currentSprites >= 125 then
                    if coordinator then
                        coordinator:Queue("SpriteCraft")
                            if not EventAuto:TargetMatchesState(stateInfo) and not QuestAuto:TargetMatchesState(stateInfo) and not challengeTargetMatchesState(stateInfo) then
                                coordinator:RequestLobby("Craft", "Sprite Grey full", stateInfo)
                        end
                    else
                        pcall(function() safeFireGameAction("Lobby") end)
                    end
                end
            end
            if appConfig.autoJoinEnabled and appConfig.autoLeaveExpeditionScrapMax and stateInfo.Gamemode == "Expedition" and stateInfo.CurrentGameState ~= "Lobby" and stateInfo.CurrentGameState ~= "Finished" then
                local currentScrap = snapshotItemData()["EquipmentScrap"] or 0
                if currentScrap >= 250 then
                    local lastAutoReturnTrigger = getgenv().lastAutoReturnTrigger or 0
                    if tick() - lastAutoReturnTrigger > 5 then
                        getgenv().lastAutoReturnTrigger = tick()
                        appConfig.expeditionScrapCraftPending = true
                        appConfig.expeditionScrapCraftPendingSince = 0
                        saveConfig()
                        Fluent:Notify({Title = "Auto Leave Expedition", Content = "Đã đầy 250 Equipment Scrap. Đang tự động về sảnh để Craft!", Duration = 5})
                        if coordinator then
                            coordinator:Queue("ExpeditionScrapCraft")
                            coordinator:RequestLobby("Craft", "Equipment Scrap full", stateInfo)
                        else
                            pcall(function() safeFireGameAction("Lobby") end)
                        end
                    end
                end
            end
            if appConfig.autoRestartInf and isInfiniteGamemode(stateInfo.Gamemode) and not EventAuto:TargetMatchesState(stateInfo) and not QuestAuto:TargetMatchesState(stateInfo)
                and not (coordinator and coordinator:IsTransitionBusy()) then
                if stateInfo.Wave >= appConfig.restartWaveNum and stateInfo.CurrentGameState ~= "Lobby" then
                    local lastAutoRestartTrigger = getgenv().lastAutoRestartTrigger or 0
                    if tick() - lastAutoRestartTrigger > 15 then
                        getgenv().lastAutoRestartTrigger = tick()
                        getgenv().WasAutoRestarted = true
                        pcall(function() safeFireGameAction("Restart") end)
                    end
                end
            end
            local willBeEndMatch = false
            if stateInfo.CurrentGameState == "Finished" or stateInfo.CurrentGameState == "Victory" or stateInfo.CurrentGameState == "Defeat" then
                willBeEndMatch = true
            elseif stateInfo.Gamemode == "Expedition" and matchesPlayedIncreased then
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
                if stateInfo.Gamemode == "Expedition" then
                    getgenv().ExpeditionMacroNodeKey = nil
                    getgenv().ExpeditionMacroHandledNodeKey = nil
                    getgenv().ExpeditionHelperPlacementPending = nil
                end
            end
            if stateInfo.Gamemode == "Expedition" and lastStateInfo and lastStateInfo.Gamemode == "Expedition"
                and tostring(stateInfo.GameIncrement) ~= tostring(lastStateInfo.GameIncrement) then
                isPlaying = false
                lastHasRunMacro = false
                getgenv().ExpeditionMacroNodeKey = nil
                getgenv().ExpeditionMacroHandledNodeKey = nil
                getgenv().ExpeditionHelperPlacementPending = nil
                print("[MACRO] New Expedition GameIncrement; cleared stale playback locks")
            end
            if stateInfo.Gamemode == "Expedition" and lastStateInfo
                and (lastStateInfo.CurrentGameState == "Finished" or lastStateInfo.CurrentGameState == "Victory" or lastStateInfo.CurrentGameState == "Defeat")
                and stateInfo.CurrentGameState ~= "Finished" and stateInfo.CurrentGameState ~= "Victory" and stateInfo.CurrentGameState ~= "Defeat" then
                isPlaying = false
                lastHasRunMacro = false
                getgenv().ExpeditionMacroNodeKey = nil
                getgenv().ExpeditionMacroHandledNodeKey = nil
                getgenv().ExpeditionHelperPlacementPending = nil
                print("[MACRO] Expedition end screen closed; unlocked playback for the new run")
            end
            local expeditionNodeKey
            if stateInfo.Gamemode == "Expedition" then
                local nodeStatus = tostring(stateInfo.Status or ""):lower()
                if nodeStatus:find("assault", 1, true) or nodeStatus:find("defen", 1, true) then
                    expeditionNodeKey = tostring(stateInfo.GameIncrement) .. ":" .. nodeStatus
                    if getgenv().ExpeditionMacroNodeKey ~= expeditionNodeKey then
                        getgenv().ExpeditionMacroNodeKey = expeditionNodeKey
                        isPlaying = false
                        lastHasRunMacro = false
                        getgenv().ExpeditionContinueBlocked = false
                        print("[MACRO] New Expedition node unlocked: " .. expeditionNodeKey)
                    end
                end
            end
            if stateInfo.Gamemode == "Expedition" and lastStateInfo and lastStateInfo.Wave > 0 and stateInfo.Wave == 0 then
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
                    Fluent:Notify({Title = "Macro", Content = string.format(localizeText("Đã cập nhật tên Map thật: %s"), realKey), Duration = 3})
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
                Fluent:Notify({Title = "Macro", Content = string.format(localizeText("Bắt đầu TỰ ĐỘNG GHI hình cho [%s]"), currentStageKey), Duration = 5})
            end

            if automationMacroPlaybackEnabled(stateInfo) and not isRecording and not isPlaying and not lastHasRunMacro then
                local canStartMacro = stateInfo.Wave == 0 or stateInfo.Wave == 1
                if stateInfo.Gamemode == "Expedition" then
                    canStartMacro = getExpeditionMapProgress() == nil
                    if expeditionNodeKey and getgenv().ExpeditionMacroHandledNodeKey == expeditionNodeKey then
                        canStartMacro = false
                    end
                    if shouldSkipExpeditionDefenseMacro(stateInfo) then
                        canStartMacro = false
                        isPlaying = false
                        lastHasRunMacro = false
                        getgenv().ExpeditionContinueBlocked = false
                        if expeditionNodeKey then getgenv().ExpeditionMacroHandledNodeKey = expeditionNodeKey end
                        local skipKey = tostring(stateInfo.GameIncrement) .. ":" .. tostring(stateInfo.Status)
                        if getgenv().LastSkippedExpeditionDefenseMacro ~= skipKey then
                            getgenv().LastSkippedExpeditionDefenseMacro = skipKey
                            print("[MACRO] Skipped Expedition Defense node: " .. tostring(stateInfo.Status))
                            Fluent:Notify({Title = "Macro Expedition", Content = "Đã bỏ qua Macro tại map Defense.", Duration = 4})
                        end
                    end
                end
                if stateInfo.CurrentGameState ~= "Lobby" and canStartMacro and not willBeEndMatch then
                    local skey = getCurrentStageKey(stateInfo, lastStateInfo)
                    local macroList, matchedMacroKey = getMacroListForStage(skey, stateInfo)
                    if macroList and #macroList > 0 and hasMacroHotbarUnits() then
                        if expeditionNodeKey then getgenv().ExpeditionMacroHandledNodeKey = expeditionNodeKey end
                        macroHookGeneration.Playback = (tonumber(macroHookGeneration.Playback) or 0) + 1
                        local playbackGeneration = macroHookGeneration.Playback
                        isPlaying = true
                        if stateInfo.Gamemode == "Expedition" then getgenv().ExpeditionContinueBlocked = true end
                        lastHasRunMacro = true
                        print("[AE-LOG DEBUG] TÌM THẤY MACRO! Bắt đầu thread Playback...")
                        Fluent:Notify({Title = "Macro", Content = string.format(localizeText("Đã tìm thấy thư viện Macro cho [%s]. Đang bắt đầu tự động xây!"), matchedMacroKey), Duration = 5})
                        task.spawn(function()
                            if stateInfo.Gamemode == "Expedition" then
                                print("[MACRO] Expedition node " .. tostring(stateInfo.Status) .. ": running " .. #macroList .. " recorded actions")
                            end
                            local Event = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ReplicaSignal")
                            local function getCurrentMacroReplicaIds()
                                local playerState = Fusion.peek(Dependencies.GamePlayerState)
                                local gamePlayerDataId = type(playerState) == "table" and tonumber(Fusion.peek(playerState.ID)) or nil
                                local hotbarDataId = getgenv().AnimeExpeditionsHotbarReplicaId
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

                             local playStart = tick()
                             local itemPauseLogged = false
                              local macroStoppedForDefense = false
                              for i, action in ipairs(macroList) do
                                  if macroHookGeneration.Playback ~= playbackGeneration or not isPlaying or not automationMacroPlaybackEnabled(stateInfo) then break end
                                 if shouldSkipExpeditionDefenseMacro(getGameStates()) then
                                     macroStoppedForDefense = true
                                     isPlaying = false
                                     lastHasRunMacro = false
                                     getgenv().ExpeditionContinueBlocked = false
                                     print("[MACRO] Playback stopped before action because current Expedition node is Defense")
                                     break
                                 end
                                 while isExpeditionItemTargeting() do
                                    if not itemPauseLogged then
                                        itemPauseLogged = true
                                        print("[MACRO] Paused while selecting an Expedition Tome target")
                                    end
                                    task.wait(0.25)
                                    if macroHookGeneration.Playback ~= playbackGeneration or not isPlaying or not automationMacroPlaybackEnabled(stateInfo) then break end
                                end
                                itemPauseLogged = false
                                if macroHookGeneration.Playback ~= playbackGeneration or not isPlaying or not automationMacroPlaybackEnabled(stateInfo) then break end
                                
                                if i == initialEndIndex + 1 then
                                    print("[Macro Playback] Đã xong Phase 1. Đang ép Start Game và chờ Wave 1...")
                                     while stateInfo.Wave == 0 do
                                        if macroHookGeneration.Playback ~= playbackGeneration or not isPlaying then break end
                                         safeFireGameAction("VoteStart")
                                        task.wait(1)
                                        stateInfo = getGameStates()
                                        if macroHookGeneration.Playback ~= playbackGeneration or not isPlaying or not automationMacroPlaybackEnabled(stateInfo) then break end
                                    end
                                    playStart = tick() - action.time
                                end

                                 while (tick() - playStart) < action.time do
                                     task.wait(0.01)
                                     if macroHookGeneration.Playback ~= playbackGeneration or not isPlaying or not automationMacroPlaybackEnabled(stateInfo) then break end
                                  end
                                  if macroHookGeneration.Playback ~= playbackGeneration or not isPlaying or not automationMacroPlaybackEnabled(stateInfo) then break end
                                 if shouldSkipExpeditionDefenseMacro(getGameStates()) then
                                     macroStoppedForDefense = true
                                     isPlaying = false
                                     lastHasRunMacro = false
                                     getgenv().ExpeditionContinueBlocked = false
                                     print("[MACRO] Playback stopped before sending action because current Expedition node is Defense")
                                     break
                                 end
                                 
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
                                        Event:FireServer(pId, "PlaceGameUnit", action.slot, CFrame.new(unpack(action.pos)))
                                        print("[MACRO] PlaceGameUnit slot " .. tostring(action.slot) .. " using GamePlayerData " .. tostring(pId))
                                    else
                                        warn("[MACRO] PlaceGameUnit skipped: GamePlayerData replica missing")
                                    end
                                    local execTime = tick() - playStart
                                elseif action.type == "VoteStart" then
                                    safeFireGameAction("VoteStart")
                                    local execTime = tick() - playStart
                                    print(string.format("[Macro Playback] Đã tự động bấm VoteStart lúc %.2fs", execTime))
                                elseif action.type == "Upgrade" or action.type == "Sell" or action.type == "AutoUpgrade" or action.type == "Priority" then
                                    local pId = getCurrentMacroReplicaIds()
                                    if not pId then
                                        warn("[MACRO] Unit action skipped: GamePlayerData replica missing")
                                        continue
                                    end
                                    local uId = action.unitId
                                    if action.pos then
                                        local targetPos = Vector3.new(action.pos[1], action.pos[2], action.pos[3])
                                        local closestDist = 20
                                        local gameUnits = Fusion.peek(Dependencies.GameUnits)
                                        if type(gameUnits) == "table" then
                                            for model, unitState in pairs(gameUnits) do
                                                local unitData = Fusion.peek(unitState)
                                                if typeof(model) == "Instance" and type(unitData) == "table"
                                                    and Fusion.peek(unitData.Owner) == LocalPlayer
                                                    and (not action.asset or model.Name == action.asset) then
                                                    local unitCFrame = Fusion.peek(unitData.CFrame)
                                                    local unitPosition = typeof(unitCFrame) == "CFrame" and unitCFrame.Position
                                                        or (model:IsA("Model") and model:GetPivot().Position or nil)
                                                    if unitPosition then
                                                        local distance = (unitPosition - targetPos).Magnitude
                                                        if distance < closestDist then
                                                            local currentId = Fusion.peek(unitData.ID)
                                                            if currentId ~= nil then
                                                                closestDist = distance
                                                                uId = tostring(currentId)
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                        if closestDist == 20 then
                                            warn("[AE-LOG] Macro Playback WARNING: Could not find owned unit within 20 studs for " .. tostring(action.type))
                                        end
                                    else
                                        warn("[AE-LOG] Macro Playback WARNING: action.pos is MISSING for " .. tostring(action.type) .. "! Using OLD ID: " .. tostring(uId))
                                    end
                                    
                                    if action.type == "Upgrade" then 
                                        Event:FireServer(pId, "UpgradeGameUnit", uId)
                                        local execTime = tick() - playStart
                                        print(string.format("[Macro Playback] Nâng cấp lính (Mã MỚI: %s) lúc %.2fs", tostring(uId), execTime))
                                    elseif action.type == "AutoUpgrade" then
                                        if action.enabled == false then
                                            Event:FireServer(pId, "DisableGameUnitAutoUpgrade", uId)
                                        elseif action.priority ~= nil then
                                            Event:FireServer(pId, "ChangeGameUnitAutoUpgradePriority", uId, action.priority)
                                        else
                                            Event:FireServer(pId, "ChangeGameUnitAutoUpgradePriority", uId)
                                        end
                                        local execTime = tick() - playStart
                                        print(string.format("[Macro Playback] Auto Upgrade=%s priority=%s (Mã MỚI: %s) lúc %.2fs", tostring(action.enabled ~= false), tostring(action.priority), tostring(uId), execTime))
                                    elseif action.type == "Priority" then
                                        Event:FireServer(pId, "ChangeGameUnitPriority", uId, action.priority)
                                        local execTime = tick() - playStart
                                        print(string.format("[Macro Playback] Chuyển Priority=%s (Mã MỚI: %s) lúc %.2fs", tostring(action.priority), tostring(uId), execTime))
                                    else
                                        Event:FireServer(pId, "SellGameUnit", uId) 
                                        local execTime = tick() - playStart

                                        print(string.format("[Macro Playback] Bán lính (Mã MỚI: %s) lúc %.2fs", tostring(uId), execTime))
                                    end
                                end
                             end
                            if macroHookGeneration.Playback ~= playbackGeneration then return end
                            if initialEndIndex == #macroList and stateInfo.Gamemode ~= "Expedition" then
                                task.spawn(function()
                                    task.wait(1)
                                    if macroHookGeneration.Playback ~= playbackGeneration then return end
                                    safeFireGameAction("VoteStart")
                                    print("[Macro Playback] Đã tự động VoteStart vì Macro đã chạy hết toàn bộ Phase 1!")
                                end)
                            end
                            print("[AE-LOG DEBUG] Macro đã kết thúc an toàn!")
                            if not macroStoppedForDefense then
                                Fluent:Notify({Title = "Macro", Content = "Hoàn tất kịch bản Macro!", Duration = 3})
                            end
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
            elseif stateInfo.Gamemode == "Expedition" and matchesPlayedIncreased then
                isEndMatch = true
                resultStatus = "Victory"
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
            if isEndMatch and (not wasManualRestart or matchesPlayedIncreased) and appConfig.webhookWinEnabled
                and not getgenv().AnimeExpeditionsWebhookBuildPending
                and (matchesPlayedIncreased or tick() - lastSentTime > 15) then
                lastSentTime = tick()
                local webhookBuildToken = {}
                getgenv().AnimeExpeditionsWebhookBuildPending = webhookBuildToken
                getgenv().HasRunMacroThisMatch = false
                local isExpeditionStageReward = stateInfo.Gamemode == "Expedition" and matchesPlayedIncreased
                local capturedOldItemData = isExpeditionStageReward and expeditionWebhookState.provisionalItemData or (getgenv().AnimeExpeditionsWebhookProvisionalItemData or {})
                local capturedOldUnitData = isExpeditionStageReward and expeditionWebhookState.provisionalUnitData or (getgenv().AnimeExpeditionsWebhookProvisionalUnitData or {})
                local capturedOldEquipmentData = isExpeditionStageReward and expeditionWebhookState.provisionalEquipmentData or (getgenv().AnimeExpeditionsWebhookProvisionalEquipmentData or {})
                local statsToUse = stateInfo
                if stateInfo.Wave == 0 and lastStateInfo then
                    statsToUse = lastStateInfo
                end
                isPlaying = false
                if appConfig.autoPlayEnabled then
                end
                Fluent:Notify({Title = "Match Ended", Content = "Đang lấy phần thưởng để gửi Discord...", Duration = 3})
                task.spawn(function()
                    task.wait(4)
                    if not expeditionScriptIsCurrent() or getgenv().AnimeExpeditionsWebhookBuildPending ~= webhookBuildToken then return end
                    local ok, result, committedItems, committedUnits, committedEquipment = pcall(function()
                        return buildMatchStatsEmbed(statsToUse, false, resultStatus, capturedOldItemData, capturedOldUnitData, capturedOldEquipmentData)
                    end)
                    if ok then
                        local gainedSomething = false
                        for _, field in ipairs(result.embeds[1].fields) do
                            if field.name:find("Gained Rewards") and not field.value:find(localizeText("Không nhận được Item nào"), 1, true) then gainedSomething = true end
                            if field.name:find("Unit EXP") and not field.value:find(localizeText("Không có Unit nào nhận EXP"), 1, true) then gainedSomething = true end
                        end
                        if gainedSomething or resultStatus ~= "Finished" then
                            getgenv().AnimeExpeditionsWebhookProvisionalItemData = committedItems
                            getgenv().AnimeExpeditionsWebhookProvisionalUnitData = committedUnits
                            getgenv().AnimeExpeditionsWebhookProvisionalEquipmentData = committedEquipment
                            if isExpeditionStageReward then
                                expeditionWebhookState.provisionalItemData = committedItems
                                expeditionWebhookState.provisionalUnitData = committedUnits
                                expeditionWebhookState.provisionalEquipmentData = committedEquipment
                            end
                            getgenv().AnimeExpeditionsEnqueueWebhook({
                                Payload = result,
                                CommitItemData = committedItems,
                                CommitUnitData = committedUnits,
                                CommitEquipmentData = committedEquipment,
                                IsExpedition = isExpeditionStageReward,
                            })
                        else
                            getgenv().StartItemData = committedItems
                            getgenv().StartUnitData = committedUnits
                            getgenv().StartEquipmentData = committedEquipment
                            getgenv().AnimeExpeditionsWebhookProvisionalItemData = committedItems
                            getgenv().AnimeExpeditionsWebhookProvisionalUnitData = committedUnits
                            getgenv().AnimeExpeditionsWebhookProvisionalEquipmentData = committedEquipment
                            if isExpeditionStageReward then
                                expeditionWebhookState.itemData = committedItems
                                expeditionWebhookState.unitData = committedUnits
                                expeditionWebhookState.equipmentData = committedEquipment
                                expeditionWebhookState.provisionalItemData = committedItems
                                expeditionWebhookState.provisionalUnitData = committedUnits
                                expeditionWebhookState.provisionalEquipmentData = committedEquipment
                            end
                            Fluent:Notify({Title = "Webhook", Content = "Không có phần thưởng mới, bỏ qua gửi Discord.", Duration = 4})
                        end
                    else
                        Fluent:Notify({Title = "Lỗi Build Embed", Content = tostring(result), Duration = 7})
                    end
                    if getgenv().AnimeExpeditionsWebhookBuildPending == webhookBuildToken then getgenv().AnimeExpeditionsWebhookBuildPending = nil end
                end)
            end
        end
        lastStateInfo = stateInfo
        end, debug.traceback)
        if not schedulerOk and tick() - (getgenv().AnimeExpeditionsSchedulerLastErrorAt or 0) >= 5 then
            getgenv().AnimeExpeditionsSchedulerLastErrorAt = tick()
            warn("[AUTO SCHEDULER] Tick failed but scheduler remains alive: " .. tostring(schedulerError))
            safeSetParagraphDesc(AutoJoinStatusPara, "Scheduler vừa bỏ qua một lỗi UI/game; sẽ thử lại tick kế tiếp.")
        end
    end
end)
installMacroHook = function()
    if getgenv().AnimeExpeditionsMacroHookInstalled == macroHookGeneration then return end
    logInit("Đang cài đặt Hook Bypass & Macro...")
    local oldNamecall
    local getCFrameComponents = CFrame.new().GetComponents
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
                    warn(logStr)
                end
            end

        local helperCapture = getgenv().ExpeditionAutoHelperCapture
        local helperCaptureHandled = false
        if helperCapture and args[2] == "PlaceGameUnit" then
            local position
            for index = 3, #args do
                if typeof(args[index]) == "CFrame" then
                    position = {getCFrameComponents(args[index])}
                    break
                end
            end
            if position then
                getgenv().ExpeditionAutoCapturedPosition = {priority = helperCapture.priority, position = position}
                getgenv().ExpeditionAutoHelperCapture = nil
                helperCaptureHandled = true
            end
        end
        if helperCaptureHandled then return nil end

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
                for i = 3, #args do
                    if typeof(args[i]) == "CFrame" or typeof(args[i]) == "Vector3" then pArg = args[i]; break end
                end
                if pArg then
                    local p = typeof(pArg) == "CFrame" and {getCFrameComponents(pArg)} or {pArg.X, pArg.Y, pArg.Z}
                    local curWave = lastStateInfo and lastStateInfo.Wave or 0
                    table.insert(mList, {time = currentTime, type = "Place", slot = args[3], pos = p, wave = curWave})
                end
            elseif action == "VoteStart" or (action == "Response" and args[3] == true and (function()
                for _, value in pairs(getgc(true)) do
                    if type(value) == "table" and rawget(value, "Token") == "VotePrompt"
                        and tostring(rawget(value, "Id")) == tostring(args[1]) then return true end
                end
                return false
            end)()) then
                local curWave = lastStateInfo and lastStateInfo.Wave or 0
                table.insert(mList, {time = currentTime, type = "VoteStart", wave = curWave})
                print("[Macro Record] Đã lưu hành động bấm VoteStart lúc: " .. tostring(currentTime))
            elseif action == "UpgradeGameUnit" or action == "SellGameUnit" or action == "ChangeGameUnitAutoUpgradePriority"
                or action == "DisableGameUnitAutoUpgrade" or action == "ChangeGameUnitPriority" then
                local p
                local targetAsset
                local gameUnits = Fusion.peek(Dependencies.GameUnits)
                if type(gameUnits) == "table" then
                    for model, unitState in pairs(gameUnits) do
                        local unitData = Fusion.peek(unitState)
                        if typeof(model) == "Instance" and type(unitData) == "table"
                            and Fusion.peek(unitData.Owner) == LocalPlayer
                            and tostring(Fusion.peek(unitData.ID)) == tostring(args[3]) then
                            local unitCFrame = Fusion.peek(unitData.CFrame)
                            local unitPosition = typeof(unitCFrame) == "CFrame" and unitCFrame.Position
                                or (model:IsA("Model") and model:GetPivot().Position or nil)
                            if unitPosition then
                                p = {unitPosition.X, unitPosition.Y, unitPosition.Z}
                                targetAsset = model.Name
                            end
                            break
                        end
                    end
                end
                if not p then
                    warn("[AE-LOG] Macro Record WARNING: GameUnits ID not found: " .. tostring(args[3]))
                end
                if action == "UpgradeGameUnit" then
                    local curWave = lastStateInfo and lastStateInfo.Wave or 0
                    table.insert(mList, {time = currentTime, type = "Upgrade", unitId = args[3], asset = targetAsset, pos = p, wave = curWave})
                elseif action == "SellGameUnit" then
                    local curWave = lastStateInfo and lastStateInfo.Wave or 0
                    table.insert(mList, {time = currentTime, type = "Sell", unitId = args[3], asset = targetAsset, pos = p, wave = curWave})
                elseif action == "ChangeGameUnitAutoUpgradePriority" then
                    local curWave = lastStateInfo and lastStateInfo.Wave or 0
                    table.insert(mList, {time = currentTime, type = "AutoUpgrade", enabled = true, priority = args[4], unitId = args[3], asset = targetAsset, pos = p, wave = curWave})
                elseif action == "DisableGameUnitAutoUpgrade" then
                    local curWave = lastStateInfo and lastStateInfo.Wave or 0
                    table.insert(mList, {time = currentTime, type = "AutoUpgrade", enabled = false, unitId = args[3], asset = targetAsset, pos = p, wave = curWave})
                elseif action == "ChangeGameUnitPriority" then
                    local curWave = lastStateInfo and lastStateInfo.Wave or 0
                    table.insert(mList, {time = currentTime, type = "Priority", priority = args[4], unitId = args[3], asset = targetAsset, pos = p, wave = curWave})
                end
            end
        end
        if typeof(setnamecallmethod) == "function" then pcall(setnamecallmethod, method) end
        return oldNamecall(self, ...)
    end
end
        if typeof(setnamecallmethod) == "function" then pcall(setnamecallmethod, method) end
        return oldNamecall(self, ...)
    end))
    getgenv().AnimeExpeditionsMacroHookInstalled = macroHookGeneration
end
local helperCaptureSerial = 0
local function armExpeditionHelperCapture(priority)
    helperCaptureSerial += 1
    local serial = helperCaptureSerial
    getgenv().ExpeditionAutoHelperCapture = {priority = priority, serial = serial}
    local previousNamecall
    local getCFrameComponents = CFrame.new().GetComponents
    previousNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        local capture = getgenv().ExpeditionAutoHelperCapture
        if capture and capture.serial == serial and not checkcaller()
            and method == "FireServer" and typeof(self) == "Instance" and self.Name == "ReplicaSignal"
            and args[2] == "PlaceGameUnit" then
            for index = 3, #args do
                if typeof(args[index]) == "CFrame" then
                    getgenv().ExpeditionAutoCapturedPosition = {
                        priority = priority,
                        position = {getCFrameComponents(args[index])},
                    }
                    getgenv().ExpeditionAutoHelperCapture = nil
                    return nil
                end
            end
        end
        if typeof(setnamecallmethod) == "function" then pcall(setnamecallmethod, method) end
        return previousNamecall(self, ...)
    end))
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
    while not getgenv().CachedGamePlayerDataId do
        local playerState = Fusion.peek(Dependencies.GamePlayerState)
        if type(playerState) == "table" then
            getgenv().CachedGamePlayerDataId = tonumber(Fusion.peek(playerState.ID))
        end
        if not getgenv().CachedGamePlayerDataId then task.wait(0.25) end
    end
end)
Fluent:Notify({Title = "AE", Content = "Load xong!", Duration = 5})

local function setupExpeditionAutomation()
getgenv().ExpeditionRouteRewardSearching = false
getgenv().ExpeditionPostBossSellMode = false
local ExpeditionAutoDefaults = {
    enabled = false,
    autoLobbyFuel = false,
    autoLeaveFuel = false,
    fuelBuildings = {"GoldMine", "ResourceDrill"},
    autoSkillTree = false,
    autoTraining = false,
    autoLeaveTraining = false,
    trainingTraitFilter = "All",
    trainingRarities = {"Mythic", "Secret"},
    trainingCompletionMode = "Potential 400%",
    trainingUnitIds = {},
    autoCards = true,
    cardFallback = "First",
    upgradePriority = {},
    setPriority = {},
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
    routeRewardRestartEnabled = false,
    routeRewardTargets = {"EquipmentReroll"},
    routeRewardMinimumAmount = 1,
    routeRewardRestartDelay = 3,
    sellAllAfterBoss = false,
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
ExpeditionAuto.setPriority = expeditionUniqueList(ExpeditionAuto.setPriority)
ExpeditionAuto.statPriority = expeditionUniqueList(ExpeditionAuto.statPriority)
ExpeditionAuto.routeRewardTargets = expeditionUniqueList(ExpeditionAuto.routeRewardTargets)
ExpeditionAuto.routeRewardMinimumAmount = math.max(1, math.floor(tonumber(ExpeditionAuto.routeRewardMinimumAmount) or 1))
ExpeditionAuto.routeRewardRestartDelay = math.max(2, tonumber(ExpeditionAuto.routeRewardRestartDelay) or 3)
ExpeditionAuto.trunksEncounterRestartEnabled = nil
saveConfig()
for index = 1, 10 do
    if type(ExpeditionAuto.helperPositions[index]) ~= "table" then
        ExpeditionAuto.helperPositions[index] = {}
    end
end
local ExpeditionNodes = require(ReplicatedStorage.Nodes)
local ExpeditionTraits = require(SharedInfo.Traits)
local ExpeditionInfo = require(SharedInfo.Expeditions)
local ExpeditionGameUpgrades = require(SharedInfo.GameUpgradesInfo)
local ExpeditionReplicaClient = require(ReplicatedStorage.Shared.ReplicaClient)
local expeditionCardPromptReplica
ExpeditionReplicaClient.OnNew("CardSelectionPrompt", function(replica)
    expeditionCardPromptReplica = replica
    replica.Maid:Add(function()
        if expeditionCardPromptReplica == replica then expeditionCardPromptReplica = nil end
    end)
end)
local expeditionRuntime = {
    lastCard = 0,
    lastHire = 0,
    lastBuy = 0,
    lastShopScan = 0,
    lastShopAction = 0,
    pendingRepairCount = nil,
    pendingRepairAt = 0,
    pendingAnvilPurchaseAt = nil,
    pendingAnvilCount = nil,
    firstCheckpointIncrement = nil,
    lastContinue = 0,
    lastUse = 0,
    lastNoYenLog = 0,
    hired = {},
    helperPending = {},
    helperUsedPositions = {},
    helperSkippedAssets = {},
    helperGameId = nil,
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
    routeRewardPending = nil,
    routeRewardAcceptedSignature = nil,
    routeRewardLastRestart = 0,
    routeRewardLastLog = "",
    postBossCycle = nil,
    postBossGameKey = nil,
    postBossSeen = false,
    postBossSellStartedAt = nil,
    postBossSellSentAt = nil,
    postBossSold = false,
    postBossExtractSentAt = nil,
    postBossExtractReplicaId = nil,
    postBossExtractIncrement = nil,
    encounterKey = nil,
    encounterNpc = nil,
    encounterChoiceSentAt = 0,
    encounterChoiceAttempts = 0,
    encounterBlocking = false,
    encounterLastLog = "",
    dicePromptState = nil,
    dicePromptStateAt = 0,
    dicePromptLastClick = 0,
}
local routeRewardMinimumInput
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
local function expeditionRouteRewardSnapshot(replica)
    local data = replica and replica.Data or {}
    local totals, signatureParts, hasBoss = {}, {}, false
    for routeIndex, nodeIndex in ipairs(data.NodeQueue or {}) do
        local node = type(nodeIndex) == "number" and data.GridNodes and data.GridNodes[nodeIndex] or nodeIndex
        local rewardParts = {}
        if type(node) == "table" then
            if node.Node == "Boss" then hasBoss = true end
            for _, reward in ipairs(node.Rewards or {}) do
                local asset = tostring(reward.Asset or reward.Name or "")
                local amount = tonumber(reward.Amount) or 0
                if asset ~= "" then
                    totals[asset] = (totals[asset] or 0) + amount
                    table.insert(rewardParts, asset .. "=" .. tostring(amount))
                end
            end
            table.sort(rewardParts)
            signatureParts[routeIndex] = table.concat({
                tostring(node.X), tostring(node.Y), tostring(node.Node), table.concat(rewardParts, ","),
            }, ":")
        else
            signatureParts[routeIndex] = tostring(nodeIndex)
        end
    end
    return totals, table.concat(signatureParts, "|"), #signatureParts, hasBoss
end
local function expeditionRouteRewardMinimum()
    local displayedValue = routeRewardMinimumInput and tonumber(routeRewardMinimumInput.Value)
    local minimumAmount = math.max(1, math.floor(displayedValue or ExpeditionAuto.routeRewardMinimumAmount or 1))
    if ExpeditionAuto.routeRewardMinimumAmount ~= minimumAmount then
        ExpeditionAuto.routeRewardMinimumAmount = minimumAmount
        saveConfig()
    end
    return minimumAmount
end
local function expeditionRouteRewardMatch(rewards)
    local minimumAmount = expeditionRouteRewardMinimum()
    for _, asset in ipairs(ExpeditionAuto.routeRewardTargets or {}) do
        local amount = tonumber(rewards[asset]) or 0
        if amount >= minimumAmount then return asset, amount end
    end
    return nil, 0
end
local function expeditionAtRouteStart(replica, state)
    local data = replica and replica.Data
    local currentNode = data and data.CurrentNode
    return state and state.status == "Checkpoint" and state.current == "InProgress"
        and type(currentNode) == "table" and tonumber(currentNode.X) == 1
        and type(data.NodeHistory) == "table" and next(data.NodeHistory) == nil
end
local function expeditionResetPostBoss()
    expeditionRuntime.postBossCycle = nil
    expeditionRuntime.postBossGameKey = nil
    expeditionRuntime.postBossSeen = false
    expeditionRuntime.postBossSellStartedAt = nil
    expeditionRuntime.postBossSellSentAt = nil
    expeditionRuntime.postBossSold = false
    expeditionRuntime.postBossExtractSentAt = nil
    expeditionRuntime.postBossExtractReplicaId = nil
    expeditionRuntime.postBossExtractIncrement = nil
    getgenv().ExpeditionPostBossSellMode = false
end
local function expeditionOwnedGameUnitCount()
    local count = 0
    local gameUnits = expeditionPeek(Dependencies.GameUnits)
    for _, unitState in pairs(type(gameUnits) == "table" and gameUnits or {}) do
        local unitData = expeditionPeek(unitState)
        if type(unitData) == "table" and expeditionPeek(unitData.Owner) == LocalPlayer then count += 1 end
    end
    return count
end
local expeditionEncounterChoices = {
    Trunks = "Speak",
    Itachi = "Barter",
    Frieren = "Discuss",
    Himmel = "Engage",
    Kenpachi = "Discuss",
    Doflamingo = "Barter",
}
local expeditionEncounterDialogueSignals = {
    Trunks = {"dont have much time", "take this before i go"},
    Itachi = {"seek my flames", "choose wisely"},
    Frieren = {"sit with me a while", "we have time"},
    Himmel = {"hero always has time", "spare for a chat"},
    Kenpachi = {"worth cutting", "talk fast dont bore me"},
    Doflamingo = {"strings youre attached", "fufufu"},
}
local function expeditionNormalizeText(value)
    return tostring(value or ""):lower():gsub("[^%w%s]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end
local function expeditionGuiVisible(object)
    if not object or not object:IsA("GuiObject") or not object.Visible then return false end
    local ancestor = object.Parent
    while ancestor do
        if ancestor:IsA("GuiObject") and not ancestor.Visible then return false end
        if ancestor:IsA("LayerCollector") and not ancestor.Enabled then return false end
        ancestor = ancestor.Parent
    end
    return object.AbsoluteSize.X > 0 and object.AbsoluteSize.Y > 0
end
local function expeditionVisibleGuiText()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return "" end
    local parts = {}
    for _, object in ipairs(playerGui:GetDescendants()) do
        if (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")) and expeditionGuiVisible(object) then
            local text = expeditionNormalizeText(object.Text)
            if text ~= "" then table.insert(parts, text) end
        end
    end
    return table.concat(parts, " ")
end
local function expeditionEncounterNPC()
    local text = expeditionVisibleGuiText()
    for npc, signals in pairs(expeditionEncounterDialogueSignals) do
        for _, signal in ipairs(signals) do
            if text:find(signal, 1, true) then return npc end
        end
    end
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    for _, object in ipairs(playerGui and playerGui:GetDescendants() or {}) do
        if (object:IsA("TextLabel") or object:IsA("TextButton")) and expeditionGuiVisible(object) then
            local label = expeditionNormalizeText(object.Text)
            for npc in pairs(expeditionEncounterChoices) do
                if label == expeditionNormalizeText(npc) then
                    local ancestor = object.Parent
                    while ancestor and ancestor ~= playerGui do
                        local name = tostring(ancestor.Name):lower()
                        if name:find("dialog", 1, true) or name:find("encounter", 1, true) then return npc end
                        ancestor = ancestor.Parent
                    end
                end
            end
        end
    end
    return nil
end
local function expeditionButtonHasLabel(button, wanted)
    wanted = expeditionNormalizeText(wanted)
    if button:IsA("TextButton") and expeditionNormalizeText(button.Text) == wanted then return true end
    for _, child in ipairs(button:GetDescendants()) do
        if (child:IsA("TextLabel") or child:IsA("TextButton")) and expeditionGuiVisible(child) and expeditionNormalizeText(child.Text) == wanted then
            return true
        end
    end
    return false
end
local function expeditionActivateButton(button)
    if not button or not expeditionGuiVisible(button) or not button.Active then return false end
    if firesignal then
        local fired = false
        for _, signalName in ipairs({"Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up"}) do
            local signalOk, signal = pcall(function() return button[signalName] end)
            if signalOk and signal then
                local fireOk = pcall(firesignal, signal)
                fired = fireOk or fired
            end
        end
        if fired then return true end
    end
    local center = button.AbsolutePosition + button.AbsoluteSize / 2
    local ok = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
        VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
    end)
    return ok
end
local function expeditionDicePromptState()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return nil, nil end
    for _, object in ipairs(playerGui:GetDescendants()) do
        if (object:IsA("TextLabel") or object:IsA("TextButton")) and expeditionGuiVisible(object) then
            local text = expeditionNormalizeText(object.Text)
            if text == "click anywhere to roll dice" then return "Roll", object:FindFirstAncestorWhichIsA("ScreenGui") end
            if text == "click anywhere to skip" then return "Rolling", object:FindFirstAncestorWhichIsA("ScreenGui") end
            if text == "click anywhere to close" then return "Close", object:FindFirstAncestorWhichIsA("ScreenGui") end
        end
    end
    return nil, nil
end
local function expeditionActivateFullscreenPrompt(screenGui)
    local bestButton, bestArea
    for _, object in ipairs(screenGui and screenGui:GetDescendants() or {}) do
        if object:IsA("GuiButton") and expeditionGuiVisible(object) and object.Active then
            local area = object.AbsoluteSize.X * object.AbsoluteSize.Y
            if not bestArea or area > bestArea then bestButton, bestArea = object, area end
        end
    end
    if bestButton and expeditionActivateButton(bestButton) then return true end
    local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
    return pcall(function()
        VirtualInputManager:SendMouseButtonEvent(viewport.X / 2, viewport.Y / 2, 0, true, game, 0)
        VirtualInputManager:SendMouseButtonEvent(viewport.X / 2, viewport.Y / 2, 0, false, game, 0)
    end)
end
local function expeditionHandleDicePrompt()
    local promptState, screenGui = expeditionDicePromptState()
    if not promptState then
        expeditionRuntime.dicePromptState = nil
        expeditionRuntime.dicePromptStateAt = 0
        return false
    end
    if expeditionRuntime.dicePromptState ~= promptState then
        expeditionRuntime.dicePromptState = promptState
        expeditionRuntime.dicePromptStateAt = tick()
    end
    local requiredDelay = promptState == "Close" and 0.8 or (promptState == "Rolling" and 3 or 0.25)
    if tick() - (expeditionRuntime.dicePromptStateAt or 0) < requiredDelay
        or tick() - (expeditionRuntime.dicePromptLastClick or 0) < 1 then return true end
    if expeditionActivateFullscreenPrompt(screenGui) then
        expeditionRuntime.dicePromptLastClick = tick()
        print("[EXP ENCOUNTER] Dice prompt -> " .. promptState)
    end
    return true
end
local function expeditionTryEncounter()
    local state = expeditionState()
    if not state or state.mode ~= "Expedition" or tostring(state.status) ~= "Encounter" then
        if expeditionRuntime.encounterBlocking then
            expeditionRuntime.encounterBlocking = false
            if not isPlaying then getgenv().ExpeditionContinueBlocked = false end
            print("[EXP ENCOUNTER] Encounter finished; released Continue lock")
        end
        expeditionRuntime.encounterKey = nil
        expeditionRuntime.encounterNpc = nil
        expeditionRuntime.encounterChoiceSentAt = 0
        expeditionRuntime.encounterChoiceAttempts = 0
        expeditionRuntime.encounterLastLog = ""
        expeditionRuntime.dicePromptState = nil
        expeditionRuntime.dicePromptStateAt = 0
        return false
    end
    isPlaying = false
    lastHasRunMacro = true
    expeditionRuntime.encounterBlocking = true
    getgenv().ExpeditionContinueBlocked = true
    if expeditionHandleDicePrompt() then return true end
    local replica = expeditionGameReplica()
    local currentNode = replica and replica.Data and replica.Data.CurrentNode
    local detectedNpc = expeditionEncounterNPC()
    if detectedNpc then expeditionRuntime.encounterNpc = detectedNpc end
    local npc = detectedNpc or expeditionRuntime.encounterNpc
    local key = table.concat({tostring(state.increment), tostring(currentNode and currentNode.X), tostring(currentNode and currentNode.Y), tostring(npc)}, ":")
    if expeditionRuntime.encounterKey ~= key then
        expeditionRuntime.encounterKey = key
        expeditionRuntime.encounterChoiceSentAt = 0
        expeditionRuntime.encounterChoiceAttempts = 0
    end
    if not npc then
        if expeditionRuntime.encounterLastLog ~= key then
            expeditionRuntime.encounterLastLog = key
            print("[EXP ENCOUNTER] Đang chờ nhận diện NPC...")
        end
        return true
    end
    local choice = expeditionEncounterChoices[npc]
    if (expeditionRuntime.encounterChoiceSentAt or 0) > 0 then
        if tick() - expeditionRuntime.encounterChoiceSentAt < 2 then return true end
        expeditionRuntime.encounterChoiceSentAt = 0
    end
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    for _, button in ipairs(playerGui and playerGui:GetDescendants() or {}) do
        if button:IsA("GuiButton") and expeditionGuiVisible(button) and expeditionButtonHasLabel(button, choice) then
            if expeditionActivateButton(button) then
                expeditionRuntime.encounterChoiceSentAt = tick()
                expeditionRuntime.encounterChoiceAttempts = (expeditionRuntime.encounterChoiceAttempts or 0) + 1
                local logKey = key .. ":" .. choice
                expeditionRuntime.encounterLastLog = logKey
                print("[EXP ENCOUNTER] " .. npc .. " -> " .. choice .. " (attempt " .. expeditionRuntime.encounterChoiceAttempts .. ")")
            end
            return true
        end
    end
    local logKey = key .. ":missing:" .. choice
    if expeditionRuntime.encounterLastLog ~= logKey then
        expeditionRuntime.encounterLastLog = logKey
        warn("[EXP ENCOUNTER] Không tìm thấy lựa chọn an toàn " .. choice .. " cho " .. npc .. "; không chọn nhánh rủi ro.")
    end
    return true
end
local function expeditionTryPostBoss()
    if not ExpeditionAuto.sellAllAfterBoss then
        getgenv().ExpeditionPostBossSellMode = false
        return false
    end
    local state = expeditionState()
    if not state then return expeditionRuntime.postBossSeen or expeditionRuntime.postBossSold end
    if state.current == "Lobby" then
        expeditionResetPostBoss()
        return false
    end
    local now = tick()
    if expeditionRuntime.postBossSold then
        getgenv().ExpeditionPostBossSellMode = true
        isPlaying = false
        lastHasRunMacro = true
        local extractReplica = expeditionGameReplica()
        if expeditionRuntime.postBossExtractSentAt then
            local extractData = extractReplica and extractReplica.Data or {}
            local replicaChanged = extractReplica and expeditionRuntime.postBossExtractReplicaId
                and tostring(extractReplica.Id) ~= expeditionRuntime.postBossExtractReplicaId
            local incrementChanged = expeditionRuntime.postBossExtractIncrement
                and tostring(extractData.GameIncrement) ~= expeditionRuntime.postBossExtractIncrement
            local extractFinished = state.current == "Finished" or state.current == "Victory" or state.current == "Defeat"
            if extractFinished or state.status ~= "Checkpoint" or replicaChanged or incrementChanged then
                print("[EXP BOSS] Extract confirmed by game-state transition")
                expeditionResetPostBoss()
                isPlaying = false
                lastHasRunMacro = false
                getgenv().ExpeditionMacroNodeKey = nil
                getgenv().ExpeditionMacroHandledNodeKey = nil
                getgenv().ExpeditionHelperPlacementPending = nil
                return false
            end
        end
        if state.status == "Checkpoint"
            and (not expeditionRuntime.postBossExtractSentAt or now - expeditionRuntime.postBossExtractSentAt >= 2) then
            expeditionRuntime.postBossExtractSentAt = now
            expeditionRuntime.postBossExtractReplicaId = extractReplica and tostring(extractReplica.Id) or nil
            expeditionRuntime.postBossExtractIncrement = extractReplica and tostring((extractReplica.Data or {}).GameIncrement) or nil
            local ok, err = pcall(function() Actions.Expedition_Extract() end)
            if ok then
                print("[EXP BOSS] Extract requested at post-Boss checkpoint")
            else
                expeditionRuntime.postBossExtractSentAt = nil
                warn("[EXP BOSS] Extract failed: " .. tostring(err))
            end
        end
        return true
    end
    local replica = expeditionGameReplica()
    if not replica then return expeditionRuntime.postBossSeen end
    local data = replica.Data or {}
    local gameKey = tostring(replica.Id) .. ":" .. tostring(data.GameIncrement)
    local currentNode = data.CurrentNode
    local currentIsBoss = type(currentNode) == "table" and currentNode.Node == "Boss"
    local passedBossCount = 0
    for _, node in pairs(data.NodeHistory or {}) do
        if type(node) == "table" and node.Node == "Boss" then passedBossCount += 1 end
    end
    local bossPassed = passedBossCount > 0
    if currentIsBoss or bossPassed then
        local cycle = tostring(replica.Id) .. ":Boss:" .. tostring(math.max(1, passedBossCount))
        if expeditionRuntime.postBossCycle ~= cycle then
            expeditionResetPostBoss()
            expeditionRuntime.postBossCycle = cycle
            expeditionRuntime.postBossGameKey = gameKey
            expeditionRuntime.postBossSeen = true
            print("[EXP BOSS] Final Boss node detected: " .. cycle)
        end
    end
    if not expeditionRuntime.postBossSeen or (currentIsBoss and not bossPassed) then return false end
    getgenv().ExpeditionPostBossSellMode = true
    isPlaying = false
    lastHasRunMacro = true
    getgenv().ExpeditionContinueBlocked = false
    if ExpeditionAuto.sellAllAfterBoss and not expeditionRuntime.postBossSold then
        local unitsBefore = expeditionOwnedGameUnitCount()
        expeditionRuntime.postBossSellStartedAt = expeditionRuntime.postBossSellStartedAt or now
        if not expeditionRuntime.postBossSellSentAt or now - expeditionRuntime.postBossSellSentAt >= 2 then
            local ok, err = pcall(function() Actions.UnitManagerSellAll() end)
            expeditionRuntime.postBossSellSentAt = now
            if ok then
                print("[EXP BOSS] Sell All requested after Boss; owned units=" .. tostring(unitsBefore))
            else
                warn("[EXP BOSS] Sell All failed: " .. tostring(err))
            end
        end
        if unitsBefore == 0 or now - expeditionRuntime.postBossSellStartedAt >= 3 then
            expeditionRuntime.postBossSold = true
            print("[EXP BOSS] Sell All phase completed")
        else
            return true
        end
    end
    expeditionRuntime.postBossSold = true
    if state.status == "Checkpoint"
        and (not expeditionRuntime.postBossExtractSentAt or now - expeditionRuntime.postBossExtractSentAt >= 2) then
        expeditionRuntime.postBossExtractSentAt = now
        expeditionRuntime.postBossExtractReplicaId = tostring(replica.Id)
        expeditionRuntime.postBossExtractIncrement = tostring(data.GameIncrement)
        local ok, err = pcall(function() Actions.Expedition_Extract() end)
        if ok then
            print("[EXP BOSS] Extract requested at post-Boss checkpoint")
        else
            expeditionRuntime.postBossExtractSentAt = nil
            warn("[EXP BOSS] Extract failed: " .. tostring(err))
        end
    end
    return true
end
local function expeditionTryRouteReward()
    if getgenv().AnimeExpeditionsMapSwitchPending then
        getgenv().ExpeditionRouteRewardSearching = false
        expeditionRuntime.routeRewardPending = nil
        getgenv().AutoPlayRestartGameIncrement = nil
        return false
    end
    if not appConfig.autoPlayEnabled or isRecording or getgenv().PendingRecord then
        getgenv().ExpeditionRouteRewardSearching = false
        expeditionRuntime.routeRewardPending = nil
        getgenv().AutoPlayRestartGameIncrement = nil
        return false
    end
    if not ExpeditionAuto.routeRewardRestartEnabled then
        getgenv().ExpeditionRouteRewardSearching = false
        expeditionRuntime.routeRewardPending = nil
        return false
    end
    if #(ExpeditionAuto.routeRewardTargets or {}) == 0 then
        getgenv().ExpeditionRouteRewardSearching = false
        if expeditionRuntime.routeRewardLastLog ~= "no-target" then
            expeditionRuntime.routeRewardLastLog = "no-target"
            warn("[EXP ROUTE] Select at least one target reward before enabling Auto Restart")
        end
        return false
    end
    local state, replica = expeditionState(), expeditionGameReplica()
    if not replica or not expeditionAtRouteStart(replica, state) then
        getgenv().ExpeditionRouteRewardSearching = false
        return false
    end
    getgenv().ExpeditionRouteRewardSearching = true
    local rewards, signature, routeCount, hasBoss = expeditionRouteRewardSnapshot(replica)
    if routeCount == 0 or not hasBoss then return true end
    local matchedAsset, matchedAmount = expeditionRouteRewardMatch(rewards)
    if matchedAsset then
        getgenv().ExpeditionRouteRewardSearching = false
        expeditionRuntime.routeRewardPending = nil
        if expeditionRuntime.routeRewardAcceptedSignature ~= signature then
            expeditionRuntime.routeRewardAcceptedSignature = signature
            expeditionRuntime.routeRewardLastLog = "matched:" .. signature
            local displayName = matchedAsset
            pcall(function() displayName = Dependencies.Information:GetAssetDisplayName(matchedAsset) end)
            print("[EXP ROUTE] Accepted route: " .. tostring(displayName) .. " x" .. tostring(matchedAmount))
            Fluent:Notify({Title = "Expedition Route Found", Content = string.format(localizeText("%s x%s. Đang tiếp tục Expedition."), tostring(displayName), tostring(matchedAmount)), Duration = 5})
        end
        return false
    end
    expeditionRuntime.routeRewardAcceptedSignature = nil
    local pending = expeditionRuntime.routeRewardPending
    local increment = tonumber(replica.Data.GameIncrement) or 0
    local now = tick()
    if pending then
        if signature ~= pending.signature or increment ~= pending.increment then
            expeditionRuntime.routeRewardPending = nil
            pending = nil
        elseif now - pending.sentAt < math.max(8, ExpeditionAuto.routeRewardRestartDelay + 4) then
            return true
        else
            expeditionRuntime.routeRewardPending = nil
            pending = nil
            warn("[EXP ROUTE] Restart was not confirmed; retrying")
        end
    end
    if now - expeditionRuntime.routeRewardLastRestart < ExpeditionAuto.routeRewardRestartDelay then return true end
    local coordinator = getgenv().AnimeExpeditionsCoordinator
    if coordinator and coordinator:IsTransitionBusy() then return true end
    local wanted = table.concat(ExpeditionAuto.routeRewardTargets, ", ") .. " x" .. tostring(expeditionRouteRewardMinimum()) .. "+"
    if expeditionRuntime.routeRewardLastLog ~= signature then
        expeditionRuntime.routeRewardLastLog = signature
        print("[EXP ROUTE] Target missing (" .. wanted .. "); restarting route of " .. tostring(routeCount) .. " nodes")
    end
    isPlaying = false
    lastHasRunMacro = false
    getgenv().ExpeditionContinueBlocked = false
    getgenv().AutoPlayRestartGameIncrement = increment
    getgenv().AnimeExpeditionsAutoJoinCooldownUntil = math.max(getgenv().AnimeExpeditionsAutoJoinCooldownUntil or 0, tick() + 30)
    if getgenv().AnimeExpeditionsMapSwitchPending then return true end
    local ok, err = pcall(function()
        if getgenv().AnimeExpeditionsMapSwitchPending then return end
        replica:FireServer("Restart")
    end)
    expeditionRuntime.routeRewardLastRestart = now
    if ok then
        expeditionRuntime.routeRewardPending = {signature = signature, increment = increment, sentAt = now}
    else
        getgenv().AutoPlayRestartGameIncrement = nil
        warn("[EXP ROUTE] Restart request failed: " .. tostring(err))
    end
    return true
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
    if getgenv().AnimeExpeditionsMapSwitchPending then return true end
    if type(callback) ~= "function" then
        if not expeditionRuntime.missingCallbacks then expeditionRuntime.missingCallbacks = {} end
        if not expeditionRuntime.missingCallbacks[label] then
            expeditionRuntime.missingCallbacks[label] = true
            warn("[EXP AUTO] " .. label .. " callback missing; reload the current script build")
        end
        return
    end
    local ok, result = xpcall(callback, debug.traceback)
    if ok then return result end
    if tick() - (expeditionRuntime.lastErrorLog[label] or 0) >= 2 then
        expeditionRuntime.lastErrorLog[label] = tick()
        local phase = label == "Shop" and (" [phase=" .. tostring(expeditionRuntime.shopPhase) .. "]") or ""
        warn("[EXP AUTO] " .. label .. phase .. " error: " .. tostring(result))
    end
end
local function expeditionListFromDropdown(value)
    local result, seen = {}, {}
    for key, enabled in pairs(value or {}) do
        local selected = type(key) == "number" and enabled or (enabled and key or nil)
        selected = selected and tostring(selected) or nil
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
        local selected = type(key) == "number" and enabled or (enabled and key or nil)
        if selected then result[tostring(selected)] = true end
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
local expeditionSetParagraph
local function expeditionCardSetState()
    local gameState = expeditionPeek(Dependencies.GameState)
    local cards = type(gameState) == "table" and expeditionPeek(gameState.Cards) or {}
    local keys = {}
    for key in pairs(type(cards) == "table" and cards or {}) do table.insert(keys, key) end
    return cards, ExpeditionGameUpgrades:GetSetsAmount(keys)
end
local function expeditionSetBonusDescription(bonus)
    return tostring(bonus and bonus.Description or ""):gsub("%$([%w_]+)", function(key)
        local value = bonus[key]
        return value ~= nil and tostring(value) or key
    end)
end
local function expeditionSetSummary()
    if #(ExpeditionAuto.setPriority or {}) == 0 then return "Chưa chọn Set cần build." end
    local _, amounts = expeditionCardSetState()
    local lines = {}
    for _, setKey in ipairs(ExpeditionAuto.setPriority) do
        local setInfo = ExpeditionGameUpgrades.CardSets[setKey] or {}
        local count = amounts[setKey] or 0
        local milestones = {}
        for bonusKey, threshold in pairs(ExpeditionGameUpgrades:GetSetBonuses(setKey)) do
            table.insert(milestones, {key = bonusKey, threshold = threshold})
        end
        table.sort(milestones, function(left, right) return left.threshold < right.threshold end)
        local unlocked, nextMilestone = 0, nil
        for _, milestone in ipairs(milestones) do
            if count >= milestone.threshold then unlocked += 1 elseif not nextMilestone then nextMilestone = milestone end
        end
        local targetThreshold = nextMilestone and nextMilestone.threshold or (milestones[#milestones] and milestones[#milestones].threshold or 0)
        local line = string.format(localizeText("%s: %d/%d card | đã mở %d/%d bonus"), setInfo.Name or setKey, count, targetThreshold, unlocked, #milestones)
        if nextMilestone then
            local bonus = ExpeditionGameUpgrades.CardSetBonuses[nextMilestone.key]
            line = line .. "\n  " .. string.format(localizeText("Mốc %d [%s]: %s"), nextMilestone.threshold, tostring(bonus and bonus.Rarity or "?"), expeditionSetBonusDescription(bonus))
        else
            line = line .. " | " .. localizeText("Đã đủ mọi mốc")
        end
        table.insert(lines, line)
    end
    return table.concat(lines, "\n")
end
local function refreshExpeditionSetSummary()
    if expeditionSetParagraph then safeSetParagraphDesc(expeditionSetParagraph, expeditionSetSummary()) end
end
local function expeditionPickUpgrade(choice)
    local replica = expeditionCardPromptReplica
    if not replica or not replica.Id then return false end
    local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
    local replicaSignal = remoteEvents and remoteEvents:FindFirstChild("ReplicaSignal")
    if not replicaSignal then return false end
    replicaSignal:FireServer(replica.Id, "Response", {choice})
    print("[EXP CARD] Response sent via CardSelectionPrompt " .. tostring(replica.Id) .. ": {" .. tostring(choice) .. "}")
    return true
end
local function expeditionTryCards()
    if not ExpeditionAuto.autoCards then return end
    local buttons, prompt = expeditionUpgradeButtons()
    local statAnvil = expeditionIsStatAnvilPrompt(prompt)
    if #buttons > 0 and statAnvil and not expeditionAnvilConfigured() then return end
    local retryAttempts = 0
    if expeditionRuntime.cardPending then
        if #buttons == 0 then
            print("[EXP CARD] Selection confirmed: " .. expeditionRuntime.cardPending.label)
            expeditionRuntime.cardPending = nil
            expeditionRuntime.lastCard = tick()
            expeditionRuntime.cardPopupReadyAt = nil
        elseif tick() - expeditionRuntime.cardPending.sentAt < 1.5 then
            return
        elseif (expeditionRuntime.cardPending.attempts or 1) >= 3 then
            if not expeditionRuntime.cardPending.exhausted then
                expeditionRuntime.cardPending.exhausted = true
                warn("[EXP CARD] Selection still open after 3 responses; waiting for popup to close")
            end
            return
        else
            warn("[EXP CARD] Selection not confirmed after 1.5s; retrying " .. expeditionRuntime.cardPending.label)
            retryAttempts = expeditionRuntime.cardPending.attempts or 1
            expeditionRuntime.cardPending = nil
        end
    end
    if #buttons == 0 then expeditionRuntime.cardPopupReadyAt = nil; return end
    if #buttons < 3 then expeditionRuntime.cardPopupReadyAt = nil; return end
    if not expeditionRuntime.cardPopupReadyAt then expeditionRuntime.cardPopupReadyAt = tick(); return end
    if tick() - expeditionRuntime.cardPopupReadyAt < 0.7 then return end
    local knownUpgradeNames, knownStatNames = {}, {}
    for id, card in pairs(require(SharedInfo.GameUpgradesInfo).Cards or {}) do
        knownUpgradeNames[expeditionNormalizedLabel(card.Name or id)] = card.Name or id
    end
    for stat in pairs(ExpeditionInfo.StatAnvils.Stats or {}) do
        knownStatNames[expeditionNormalizedLabel(stat)] = stat
    end
    local knownNames = statAnvil and knownStatNames or knownUpgradeNames
    local entries = {}
    local promptParameters = expeditionCardPromptReplica and expeditionCardPromptReplica.Data and expeditionCardPromptReplica.Data.Parameters
    local promptCards = type(promptParameters) == "table" and promptParameters.Cards or {}
    for buttonIndex, button in ipairs(buttons) do
        local promptCard = type(promptCards) == "table" and promptCards[buttonIndex]
        local upgrade = type(promptCard) == "table" and expeditionPeek(promptCard.Upgrade)
        local cardInfo = upgrade and ExpeditionGameUpgrades.Cards[upgrade]
        table.insert(entries, {
            button = button,
            name = cardInfo and (cardInfo.Name or upgrade) or "Card #" .. buttonIndex,
            texts = {},
            upgrade = upgrade,
            sets = cardInfo and cardInfo.Sets or {},
        })
    end
    for _, object in ipairs(prompt:GetDescendants()) do
        if object:IsA("TextLabel") and object.Visible and object.Text ~= "Select Upgrade" and object.Text ~= "" then
            local labelCenterX = object.AbsolutePosition.X + object.AbsoluteSize.X * 0.5
            local closestIndex, closestDistance
            for index, entry in ipairs(entries) do
                local candidate = entry.button
                local buttonCenterX = candidate.AbsolutePosition.X + candidate.AbsoluteSize.X * 0.5
                local distance = math.abs(labelCenterX - buttonCenterX)
                if not closestDistance or distance < closestDistance then closestIndex, closestDistance = index, distance end
            end
            if closestIndex then
                entries[closestIndex].texts[object.Text] = true
                local knownName = knownNames[expeditionNormalizedLabel(object.Text)]
                if knownName then entries[closestIndex].name = knownName end
            end
        end
    end
    local choice, reason
    if not statAnvil and #(ExpeditionAuto.setPriority or {}) > 0 then
        local ownedCards, setAmounts = expeditionCardSetState()
        local bestScore = 0
        for index, entry in ipairs(entries) do
            local score, matchedSets = 0, {}
            local isNewCard = entry.upgrade and ownedCards[entry.upgrade] == nil
            for _, setKey in ipairs(ExpeditionAuto.setPriority) do
                if table.find(entry.sets, setKey) then
                    local count = setAmounts[setKey] or 0
                    local setData = ExpeditionGameUpgrades:GetSetData(setKey, count)
                    local advances = isNewCard and setData.NextBonusKey ~= nil
                    score += advances and 10000 or 100
                    if advances and count + 1 >= setData.NextThreshold then score += 50000 end
                    score += advances and math.max(0, 100 - (setData.NextThreshold - count)) or 0
                    table.insert(matchedSets, setKey)
                end
            end
            if score > bestScore then
                bestScore = score
                choice = index
                reason = "set=" .. table.concat(matchedSets, "+") .. (isNewCard and " (new card)" or " (stack)")
            end
        end
    end
    for _, wanted in ipairs(ExpeditionAuto.upgradePriority) do
        if choice then break end
        local normalizedWanted = expeditionNormalizedLabel(wanted)
        for index, entry in ipairs(entries) do
            for text in pairs(entry.texts) do
                if expeditionNormalizedLabel(text) == normalizedWanted then choice, reason = index, "upgradePriority=" .. wanted break end
            end
            if choice then break end
        end
        if choice then break end
    end
    if not choice then
        for _, wanted in ipairs(ExpeditionAuto.statPriority) do
            local normalizedWanted = expeditionNormalizedLabel(wanted)
            for index, entry in ipairs(entries) do
                for text in pairs(entry.texts) do
                    if expeditionNormalizedLabel(text) == normalizedWanted then choice, reason = index, "statPriority=" .. wanted break end
                end
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
    local responseKey = signature .. ":" .. tostring(choice)
    print("[EXP CARD] Choosing " .. labels[choice] .. " because " .. reason)
    if expeditionPickUpgrade(choice) then
        expeditionRuntime.cardPending = {key = responseKey, label = labels[choice], sentAt = tick(), attempts = retryAttempts + 1}
        task.delay(0.5, refreshExpeditionSetSummary)
    else
        warn("[EXP CARD] CardSelectionPrompt replica unavailable: " .. tostring(labels[choice]))
    end
end
local function expeditionHotbarUnitSlot(asset)
    local hotbar = expeditionPeek(Dependencies.HotbarState)
    local slots = hotbar and expeditionPeek(hotbar.Slots)
    for slotIndex, slotState in pairs(type(slots) == "table" and slots or {}) do
        local slot = expeditionPeek(slotState)
        local data = type(slot) == "table" and expeditionPeek(slot.Data) or nil
        local slotAsset = type(slot) == "table" and (expeditionPeek(slot.Asset) or (type(data) == "table" and expeditionPeek(data.Asset)))
        local unitId = type(slot) == "table" and tostring(expeditionPeek(slot.ID) or "") or ""
        if type(slot) == "table" and expeditionPeek(slot.AssetType) == "Unit" and slotAsset == asset
            and unitId:find('"IsHelper":true', 1, true) then
            return tonumber(slotIndex)
        end
    end
    return nil
end
local function expeditionPlacedHelperCount(asset)
    local count = 0
    local gameUnits = expeditionPeek(Dependencies.GameUnits)
    for model, unitState in pairs(type(gameUnits) == "table" and gameUnits or {}) do
        local unitData = expeditionPeek(unitState)
        local unitId = type(unitData) == "table" and tostring(expeditionPeek(unitData.UnitID) or "") or ""
        if typeof(model) == "Instance" and model.Name == asset
            and expeditionPeek(unitData.Owner) == LocalPlayer
            and unitId:find('"IsHelper":true', 1, true) then
            count += 1
        end
    end
    return count
end
local expeditionTryHelpers
local function expeditionTryHire()
    if not ExpeditionAuto.autoHire or tick() - expeditionRuntime.lastHire < 2 then return end
    local state, replica = expeditionState(), expeditionGameReplica()
    if not state or state.status ~= "Checkpoint" or not replica then return end
    local pending = expeditionRuntime.hirePending
    if pending then
        local helperStillAvailable = replica.Data.Helpers and replica.Data.Helpers[pending.key] ~= nil
        local slot = expeditionHotbarUnitSlot(pending.asset)
        if slot or not helperStillAvailable then
            expeditionRuntime.hired[pending.key] = true
            expeditionRuntime.hirePending = nil
            print("[EXP AUTO] Hire confirmed: " .. tostring(pending.asset) .. " slot=" .. tostring(slot))
            if slot and expeditionTryHelpers then expeditionTryHelpers() end
        elseif tick() - pending.sentAt < 3 then
            return
        else
            expeditionRuntime.hirePending = nil
            warn("[EXP AUTO] Hire not confirmed; retrying later: " .. tostring(pending.asset))
        end
    end
    local playerState = expeditionPeek(Dependencies.GamePlayerState)
    local yen = tonumber(playerState and expeditionPeek(playerState.Yen)) or 0
    for priority, wanted in ipairs(ExpeditionAuto.helperPriority) do
        local savedPositions = ExpeditionAuto.helperPositions[priority]
        if wanted ~= "" and string.find(wanted, "EVO", 1, true)
            and type(savedPositions) == "table" and #savedPositions > 0 then
            for key, helper in pairs(replica.Data.Helpers or {}) do
                local price = tonumber(helper.Price) or math.huge
                if helper.Asset == wanted and not expeditionRuntime.hired[key] and not expeditionHotbarUnitSlot(helper.Asset) and yen >= price then
                    local ok, err = pcall(function() replica:FireServer("HireUnit", key) end)
                    if ok then
                        expeditionRuntime.hirePending = {key = key, asset = helper.Asset, sentAt = tick()}
                        getgenv().ExpeditionHelperPlacementPending = helper.Asset
                        print("[EXP AUTO] Hire requested: " .. tostring(helper.Asset) .. " price=" .. tostring(price))
                        task.spawn(function()
                            local deadline = tick() + 4
                            while tick() < deadline do
                                if expeditionHotbarUnitSlot(helper.Asset) then
                                    if expeditionTryHelpers then expeditionTryHelpers() end
                                    return
                                end
                                task.wait(0.05)
                            end
                        end)
                    else
                        warn("[EXP AUTO] Hire helper failed: " .. tostring(err))
                    end
                    expeditionRuntime.lastHire = tick()
                    return
                end
        end
    end
end
end
expeditionTryHelpers = function()
    local replica = expeditionGameReplica()
    if not replica then return end
    if expeditionRuntime.helperGameId ~= replica.Id then
        expeditionRuntime.helperGameId = replica.Id
        expeditionRuntime.helperSkippedAssets = {}
        getgenv().ExpeditionHelperPlacementPending = nil
    end
    local increment = replica.Data and replica.Data.GameIncrement
    if expeditionRuntime.helperGameIncrement ~= increment then
        expeditionRuntime.helperGameIncrement = increment
        expeditionRuntime.helperPending = {}
        expeditionRuntime.helperUsedPositions = {}
        expeditionRuntime.unboundTargets = {}
        getgenv().ExpeditionHelperPlacementPending = nil
    end
    local placedHelperCounts = {}
    local gameUnits = expeditionPeek(Dependencies.GameUnits)
    for model, unitState in pairs(type(gameUnits) == "table" and gameUnits or {}) do
        local unitData = expeditionPeek(unitState)
        local unitId = type(unitData) == "table" and tostring(expeditionPeek(unitData.UnitID) or "") or ""
        if typeof(model) == "Instance" and expeditionPeek(unitData.Owner) == LocalPlayer
            and unitId:find('"IsHelper":true', 1, true) then
            placedHelperCounts[model.Name] = (placedHelperCounts[model.Name] or 0) + 1
        end
    end
    local pendingPlacementAsset = getgenv().ExpeditionHelperPlacementPending
    if pendingPlacementAsset and (placedHelperCounts[pendingPlacementAsset] or 0) > 0 then
        getgenv().ExpeditionHelperPlacementPending = nil
        print("[EXP AUTO] Helper placement confirmed before Macro: " .. tostring(pendingPlacementAsset))
    end
    local hotbar = expeditionPeek(Dependencies.HotbarState)
    local slots = hotbar and expeditionPeek(hotbar.Slots)
    local hiredHelpers = {}
    for slotIndex, slotState in pairs(type(slots) == "table" and slots or {}) do
        local slotData = expeditionPeek(slotState)
        local data = type(slotData) == "table" and expeditionPeek(slotData.Data) or nil
        local asset = type(slotData) == "table" and (expeditionPeek(slotData.Asset) or (type(data) == "table" and expeditionPeek(data.Asset)))
        local unitId = type(slotData) == "table" and tostring(expeditionPeek(slotData.ID) or "") or ""
        local priority
        for index, wantedAsset in ipairs(ExpeditionAuto.helperPriority) do
            local savedPositions = ExpeditionAuto.helperPositions[index]
            if wantedAsset ~= "" and wantedAsset == asset
                and type(savedPositions) == "table" and #savedPositions > 0 then
                priority = index
                break
            end
        end
        if priority and type(slotData) == "table" and expeditionPeek(slotData.AssetType) == "Unit"
            and unitId:find('"IsHelper":true', 1, true) then
            table.insert(hiredHelpers, {
                key = tostring(expeditionPeek(slotData.ID) or slotIndex),
                asset = asset,
                slot = tonumber(slotIndex),
                priority = priority,
            })
        end
    end
    table.sort(hiredHelpers, function(left, right)
        if left.priority == right.priority then return left.slot < right.slot end
        return left.priority < right.priority
    end)
    for _, helper in ipairs(hiredHelpers) do
        local helperKey, slot, priority = helper.key, helper.slot, helper.priority
        if expeditionRuntime.helperSkippedAssets[helper.asset] then continue end
        local pending = expeditionRuntime.helperPending[helperKey]
        if pending and not pending.done and (pending.sentAt or 0) > 0 and tick() - pending.sentAt >= 1.25 then
            local pendingAsset = pending.asset or helper.asset
            if (placedHelperCounts[pendingAsset] or 0) > (tonumber(pending.before) or 0) then
                pending.done = true
            else
                pending.position = pending.position + 1
                pending.sentAt = 0
            end
        end
        if (placedHelperCounts[helper.asset] or 0) > 0 then
            expeditionRuntime.helperPending[helperKey] = {done = true}
            pending = expeditionRuntime.helperPending[helperKey]
        end
        if priority and (not pending or (not pending.done and pending.sentAt == 0)) then
            local position = pending and pending.position or 1
            local savedPositions = ExpeditionAuto.helperPositions[priority] or {}
            local savedPosition = savedPositions[position]
            local positionKey = savedPosition and table.concat(savedPosition, ":")
            if not savedPosition then
                expeditionRuntime.helperSkippedAssets[helper.asset] = true
                expeditionRuntime.helperPending[helperKey] = {done = true, skipped = true}
                if getgenv().ExpeditionHelperPlacementPending == helper.asset then
                    getgenv().ExpeditionHelperPlacementPending = nil
                end
                warn("[EXP AUTO] Skip helper placement after all saved positions failed: " .. tostring(helper.asset))
            elseif expeditionRuntime.helperUsedPositions[positionKey] then
                expeditionRuntime.helperPending[helperKey] = {
                    position = position + 1,
                    sentAt = 0,
                    before = placedHelperCounts[helper.asset] or 0,
                    asset = helper.asset,
                }
            else
                local cframe = CFrame.new(unpack(savedPosition))
                local ok, sent = pcall(expeditionPlaceUsingMacroRemote, slot, cframe)
                if ok and sent then
                    expeditionRuntime.helperPending[helperKey] = {
                        position = position,
                        sentAt = tick(),
                        before = placedHelperCounts[helper.asset] or 0,
                        asset = helper.asset,
                    }
                    expeditionRuntime.helperUsedPositions[positionKey] = true
                    print("[EXP AUTO] Place helper " .. tostring(helper.asset) .. " from hotbar slot " .. tostring(slot) .. " at saved position " .. position)
                else
                    pending = {position = position + 1, sentAt = 0}
                    expeditionRuntime.helperPending[helperKey] = pending
                end
            end
        end
    end
end
getgenv().ExpeditionHasUnplacedHelper = function()
    for priority, asset in ipairs(ExpeditionAuto.helperPriority) do
        local savedPositions = ExpeditionAuto.helperPositions[priority]
        if asset ~= "" and type(savedPositions) == "table" and #savedPositions > 0
            and not expeditionRuntime.helperSkippedAssets[asset]
            and expeditionHotbarUnitSlot(asset) and expeditionPlacedHelperCount(asset) == 0 then
            return true
        end
    end
    return false
end
local function expeditionTryShop()
    expeditionRuntime.shopPhase = "gate"
    if not ExpeditionAuto.autoShop or tick() - expeditionRuntime.lastBuy < 1 then return end
    if #expeditionUpgradeButtons() > 0 then expeditionRuntime.shopPhase = "upgrade popup open"; return end
    expeditionRuntime.shopPhase = "get replica"
    local state, replica = expeditionState(), expeditionShopReplica()
    if not state or state.status ~= "Checkpoint" or not replica then return end
    local anvilCount = expeditionHotbarItemCount("ExpeditionStatAnvil")
    if expeditionRuntime.pendingAnvilPurchaseAt then
        if anvilCount > (expeditionRuntime.pendingAnvilCount or anvilCount) then
            print("[EXP SHOP] Anvil purchase confirmed: " .. tostring(anvilCount))
            expeditionRuntime.pendingAnvilPurchaseAt = nil
            expeditionRuntime.pendingAnvilCount = nil
        elseif tick() - expeditionRuntime.pendingAnvilPurchaseAt < 2 then
            return
        else
            print("[EXP SHOP] Anvil purchase request finished; allowing the next stock check")
            expeditionRuntime.pendingAnvilPurchaseAt = nil
            expeditionRuntime.pendingAnvilCount = nil
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
        local wantedStockUnaffordable = false
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
                        if yen < (tonumber(item.Price) or math.huge) then
                            wantedStockUnaffordable = true
                            itemWanted = false
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
                        wantedStockUnaffordable = true
                        if tick() - expeditionRuntime.lastNoYenLog >= 3 then
                            expeditionRuntime.lastNoYenLog = tick()
                            print("[EXP SHOP] Not enough Yen for Repair; continuing")
                        end
                        break
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
        local hasAnvilInShop = false
        for _, item in ipairs(shop.Items or {}) do
            if item.Name == "ExpeditionStatAnvil" and (item.Stock == nil or item.Stock > 0) then
                hasAnvilInShop = true
                break
            end
        end
        local usesFiniteStock = (expeditionRepairConfigured() and repairCount < 2)
            or (expeditionTomeConfigured() and not expeditionHotbarFull() and expeditionNeedsAnyTome())
            or (expeditionAnvilConfigured() and not expeditionHotbarFull())
        if usesFiniteStock and not wantedStockUnaffordable and not hasAnvilInShop and canRefresh and expeditionRuntime.refreshedShopSnapshots[snapshotKey] == nil and tick() - expeditionRuntime.lastBuy > 1.5 then
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
        if not expeditionAnvilConfigured() or expeditionHotbarFull() then return end
        for index, item in ipairs(shop.Items or {}) do
            expeditionRuntime.shopPhase = "scan support"
            local buy = item.Name == "ExpeditionStatAnvil" and (item.Stock == nil or item.Stock > 0)
            if buy and yen >= (tonumber(item.Price) or math.huge) then
                local requestKey = shopCycleKey .. ":anvil:" .. tostring(index) .. ":" .. tostring(item.Stock) .. ":" .. tostring(anvilCount)
                if expeditionRuntime.shopPurchaseRequests[requestKey] then return end
                expeditionRuntime.shopPhase = "purchase support"
                local ok, err = pcall(function() replica:FireServer("PurchaseItem", shopKey, index, 1) end)
                if not ok then warn("[EXP AUTO] Support purchase request failed: " .. tostring(err)); return end
                expeditionRuntime.shopPurchaseRequests[requestKey] = true
                expeditionRuntime.pendingAnvilPurchaseAt = tick()
                expeditionRuntime.pendingAnvilCount = anvilCount
                print("[EXP AUTO] Purchase requested: " .. item.Name .. " (currently " .. tostring(anvilCount) .. ")")
                expeditionRuntime.lastBuy = tick()
                expeditionRuntime.lastShopAction = tick()
                return
            end
        end
    end
end
local function expeditionTryItems()
    if tick() - expeditionRuntime.lastUse < 2 then return end
    local state = expeditionState()
    local itemStatus = state and tostring(state.status or ""):lower() or ""
    if not (itemStatus:find("assault", 1, true) or itemStatus:find("defen", 1, true)) then return end
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
    if expeditionRepairConfigured() and state and state.status ~= "Checkpoint" and state.health and state.maxHealth and state.maxHealth > 0 then
        local missingHealth = math.max(0, state.maxHealth - state.health)
        local repair, repairAmount
        for _, candidate in ipairs(expeditionHotbarItems("ExpeditionRepair")) do
            local amount = tonumber(candidate.data and expeditionPeek(candidate.data.Health))
            if amount and amount > 0 and missingHealth >= amount and (not repairAmount or amount > repairAmount) then
                repair = candidate
                repairAmount = amount
            end
        end
        if repair and repairAmount then
            require(FusionPackage.Shared).SelectedHotbarIndex:set(repair.slot)
            print("[EXP AUTO] Repair selected from hotbar slot " .. tostring(repair.slot) .. ": heals " .. tostring(repairAmount) .. " HP, missing " .. tostring(missingHealth) .. " HP")
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
            task.wait()
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
        expeditionRuntime.orbGameStateId = replica and replica.Id or nil
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
    local stateSignature = table.concat({tostring(state.current), tostring(state.status), tostring(state.wave), tostring(state.increment), tostring(state.enemyCount), tostring(state.active)}, "|")
    if expeditionRuntime.continueWatchdog then
        local watchdog = expeditionRuntime.continueWatchdog
        local progressed = (state.enemyCount > watchdog.enemyCount and state.enemyCount > 0)
            or state.current ~= watchdog.current or state.status ~= watchdog.status
            or state.wave ~= watchdog.wave or state.increment ~= watchdog.increment
        if now - watchdog.sentAt >= 30 and not progressed then
            print("[EXP CONTINUE] No progress for 30s; returning Lobby")
            local coordinator = getgenv().AnimeExpeditionsCoordinator
            if coordinator then coordinator:RequestLobby("ExpeditionContinue", "Continue watchdog timeout", getGameStates())
            else
                local replica = expeditionGameReplica()
                if replica then pcall(function() replica:FireServer("Lobby") end) end
            end
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
    elseif not expeditionRuntime.checkpointEnteredAt or now - expeditionRuntime.checkpointEnteredAt < 5 then blocker = "Checkpoint chưa ổn định"
    elseif ExpeditionAuto.autoShop and expeditionRuntime.lastShopScan == 0 then blocker = "Shop chưa scan"
    elseif ExpeditionAuto.autoShop and now - expeditionRuntime.lastShopAction < 2 then blocker = "Shop vừa mua/refresh"
    elseif ExpeditionAuto.autoShop and expeditionRepairConfigured() and expeditionRuntime.pendingRepairCount then blocker = "đang xác nhận mua Búa"
    elseif ExpeditionAuto.autoShop and expeditionRuntime.pendingAnvilPurchaseAt and now - expeditionRuntime.pendingAnvilPurchaseAt < 3 then blocker = "đang xác nhận mua Đe"
    elseif now - expeditionRuntime.lastUse < 2 then blocker = "Vừa chọn vật phẩm" end
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

local helperEvoOptions, traitOptions, upgradeOptions, statOptions, setOptions = {""}, {}, {}, {}, {}
local setLabelToKey, setKeyToLabel = {}, {}
local routeRewardOptions, routeRewardLabelToAsset, routeRewardAssetToLabel = {}, {}, {}
for _, reward in ipairs(((ExpeditionInfo.NodeTypes or {}).Boss or {}).RewardPool or {}) do
    local asset = tostring(reward.Asset or "")
    if asset:find("Equipment", 1, true) and asset ~= "EquipmentScrap" and not routeRewardAssetToLabel[asset] then
        local label = asset
        pcall(function() label = Dependencies.Information:GetAssetDisplayName(asset) end)
        label = tostring(label or asset)
        if routeRewardLabelToAsset[label] and routeRewardLabelToAsset[label] ~= asset then label = label .. " [" .. asset .. "]" end
        routeRewardLabelToAsset[label] = asset
        routeRewardAssetToLabel[asset] = label
        table.insert(routeRewardOptions, label)
    end
end
for _, helper in pairs(ExpeditionInfo.Helpers.List or {}) do if helper.Asset and string.find(helper.Asset, "EVO", 1, true) then table.insert(helperEvoOptions, helper.Asset) end end
for trait in pairs(ExpeditionTraits.TraitData or {}) do table.insert(traitOptions, trait) end
for id, card in pairs(ExpeditionGameUpgrades.Cards or {}) do table.insert(upgradeOptions, card.Name or id) end
for key, setInfo in pairs(ExpeditionGameUpgrades.CardSets or {}) do
    if next(ExpeditionGameUpgrades:GetSetBonuses(key)) then
        local label = tostring(setInfo.Name or key)
        setLabelToKey[label] = key
        setKeyToLabel[key] = label
        table.insert(setOptions, label)
    end
end
for stat in pairs(ExpeditionInfo.StatAnvils.Stats or {}) do table.insert(statOptions, stat) end
table.sort(helperEvoOptions); table.sort(traitOptions); table.sort(upgradeOptions); table.sort(statOptions); table.sort(setOptions); table.sort(routeRewardOptions)
local setDefaults = {}
for _, key in ipairs(ExpeditionAuto.setPriority) do
    if setKeyToLabel[key] then table.insert(setDefaults, setKeyToLabel[key]) end
end
local routeRewardDefaults = {}
for _, asset in ipairs(ExpeditionAuto.routeRewardTargets) do
    if routeRewardAssetToLabel[asset] then table.insert(routeRewardDefaults, routeRewardAssetToLabel[asset]) end
end
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
    if tomeTraitParagraph then safeSetParagraphDesc(tomeTraitParagraph, expeditionTomeTraitSummary()) end
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
        if paragraph then safeSetParagraphDesc(paragraph, helperPositionSummary(index)) end
    end
end

do
    local coordinator = getgenv().AnimeExpeditionsCoordinator
    local fuelLabelToBuilding = { ["Gold Mine"] = "GoldMine", ["Resource Drill"] = "ResourceDrill" }
    local fuelDefaults = {}
    for _, building in ipairs(ExpeditionAuto.fuelBuildings or {}) do
        if building == "GoldMine" then table.insert(fuelDefaults, "Gold Mine") end
        if building == "ResourceDrill" then table.insert(fuelDefaults, "Resource Drill") end
    end
    local claimDefaults = {}
    for _, building in ipairs(ExpeditionAuto.claimRewardBuildings or {}) do
        if building == "GoldMine" then table.insert(claimDefaults, "Gold Mine") end
        if building == "ResourceDrill" then table.insert(claimDefaults, "Resource Drill") end
    end
    Tabs.Expeditions:AddSection("Lobby Maintenance")
    if coordinator then
        coordinator.StatusParagraph = Tabs.Expeditions:AddParagraph({Title = "Maintenance Status", Content = coordinator.Status})
        coordinator.FuelParagraph = Tabs.Expeditions:AddParagraph({Title = "Fuel Status", Content = "Đang chờ dữ liệu Fuel..."})
        task.defer(function() coordinator:UpdateFuelDisplay(true) end)
    end
    local fuelToggle, fuelLeaveToggle
    local fuelDropdown = Tabs.Expeditions:AddDropdown("ExpeditionLobbyFuelBuildings", {
        Title = "Buildings cần nạp Fuel",
        Values = {"Gold Mine", "Resource Drill"},
        Multi = true,
        Default = multiDropdownDefaults(fuelDefaults),
    })
    fuelDropdown:OnChanged(function(value)
        local selected = {}
        for key, enabled in pairs(value or {}) do
            local label = type(key) == "number" and enabled or (enabled and key or nil)
            local building = label and fuelLabelToBuilding[tostring(label)] or nil
            if building then table.insert(selected, building) end
        end
        table.sort(selected)
        ExpeditionAuto.fuelBuildings = selected
        if #selected == 0 then
            ExpeditionAuto.autoLobbyFuel = false
            ExpeditionAuto.autoLeaveFuel = false
            if fuelToggle then task.defer(function() fuelToggle:SetValue(false) end) end
            if fuelLeaveToggle then task.defer(function() fuelLeaveToggle:SetValue(false) end) end
        end
        saveConfig()
        if coordinator then coordinator:UpdateFuelDisplay(true) end
    end)
    fuelToggle = Tabs.Expeditions:AddToggle("ExpeditionLobbyAutoFuel", {
        Title = "Auto Fuel",
        Description = "Tự nạp các building đã chọn khi ở Lobby; không yêu cầu Auto Join Map.",
        Default = ExpeditionAuto.autoLobbyFuel,
    })
    getgenv().AnimeExpeditionsFuelToggle = fuelToggle
    fuelToggle:OnChanged(function(value)
        if value and #(ExpeditionAuto.fuelBuildings or {}) == 0 then
            ExpeditionAuto.autoLobbyFuel = false
            task.defer(function() fuelToggle:SetValue(false) end)
            Fluent:Notify({Title = "Auto Fuel", Content = "Hãy chọn ít nhất một building.", Duration = 5})
            return
        end
        ExpeditionAuto.autoLobbyFuel = value
        if not value then
            ExpeditionAuto.autoLeaveFuel = false
            if fuelLeaveToggle then task.defer(function() fuelLeaveToggle:SetValue(false) end) end
            if coordinator and coordinator:GetMaintenance().Reasons.ExpeditionFuel then coordinator:ClearReason("ExpeditionFuel") end
            if coordinator then coordinator.FuelPending = nil end
        end
        saveConfig()
    end)
    fuelLeaveToggle = Tabs.Expeditions:AddToggle("ExpeditionAutoLeaveFuel", {
        Title = "Auto Leave khi hết Fuel",
        Description = "Building hết Fuel thì thoát ngay để nạp; không ngắt Quest/Challenge. Bắt buộc Auto Fuel và Auto Join.",
        Default = ExpeditionAuto.autoLeaveFuel,
    })
    getgenv().AnimeExpeditionsLeaveToggles.Fuel = fuelLeaveToggle
    fuelLeaveToggle:OnChanged(function(value)
        value = getgenv().AnimeExpeditionsGuardAutoLeave(value, "Fuel")
        if value and not ExpeditionAuto.autoLobbyFuel then
            ExpeditionAuto.autoLeaveFuel = false
            task.defer(function() fuelLeaveToggle:SetValue(false) end)
            Fluent:Notify({Title = "Auto Leave Fuel", Content = "Phải bật Auto Fuel trước.", Duration = 5})
            return
        end
        if value and #(ExpeditionAuto.fuelBuildings or {}) == 0 then
            ExpeditionAuto.autoLeaveFuel = false
            task.defer(function() fuelLeaveToggle:SetValue(false) end)
            Fluent:Notify({Title = "Auto Leave Fuel", Content = "Hãy chọn ít nhất một building.", Duration = 5})
            return
        end
        ExpeditionAuto.autoLeaveFuel = value
        if not value and coordinator and coordinator:GetMaintenance().Reasons.ExpeditionFuel then
            coordinator:ClearReason("ExpeditionFuel")
            coordinator.FuelPending = nil
        end
        saveConfig()
    end)
    Tabs.Expeditions:AddSection("Building Rewards / Geode")
    Tabs.Expeditions:AddParagraph({
        Title = "Auto Claim và Auto Open",
        Content = "Claim rewards từ Gold Mine/Resource Drill tại Lobby. Auto Open mô phỏng Hold của game: phát một request mới mỗi 0.033333 giây.",
    })
    if coordinator then
        coordinator.BuildingResourceParagraph = Tabs.Expeditions:AddParagraph({Title = "Building Resource Status", Content = "Đang chờ dữ liệu building..."})
        task.defer(function() coordinator:UpdateBuildingResourceDisplay(true) end)
    end
    Tabs.Expeditions:AddToggle("ExpeditionAutoClaimQuestBoard", {
        Title = "Auto Claim Expedition Quest Board",
        Description = "Quét nhanh một lần mỗi khi vào Lobby; claim Expedition Weekly và toàn bộ milestone đã mở khóa trước Auto Join.",
        Default = ExpeditionAuto.autoClaimQuestBoard,
    }):OnChanged(function(value)
        ExpeditionAuto.autoClaimQuestBoard = value
        if coordinator then
            coordinator.QuestBoardClaimPending = nil
            coordinator.QuestBoardClaimCycleDone = false
        end
        saveConfig()
    end)
    local claimToggle = Tabs.Expeditions:AddToggle("ExpeditionAutoClaimBuildingRewards", {
        Title = "Auto Claim Building Rewards",
        Description = "Tự claim reward đang tích trong các building đã chọn.",
        Default = ExpeditionAuto.autoClaimBuildingRewards,
    })
    Tabs.Expeditions:AddDropdown("ExpeditionClaimRewardBuildings", {
        Title = "Buildings cần Auto Claim",
        Values = {"Gold Mine", "Resource Drill"},
        Multi = true,
        Default = multiDropdownDefaults(claimDefaults),
    }):OnChanged(function(value)
        local selected = {}
        for key, enabled in pairs(value or {}) do
            local label = type(key) == "number" and enabled or (enabled and key or nil)
            local building = label and fuelLabelToBuilding[tostring(label)] or nil
            if building then table.insert(selected, building) end
        end
        table.sort(selected)
        ExpeditionAuto.claimRewardBuildings = selected
        if #selected == 0 and ExpeditionAuto.autoClaimBuildingRewards then
            ExpeditionAuto.autoClaimBuildingRewards = false
            task.defer(function() claimToggle:SetValue(false) end)
        end
        saveConfig()
        if coordinator then coordinator:UpdateBuildingResourceDisplay(true) end
    end)
    claimToggle:OnChanged(function(value)
        if value and #(ExpeditionAuto.claimRewardBuildings or {}) == 0 then
            ExpeditionAuto.autoClaimBuildingRewards = false
            task.defer(function() claimToggle:SetValue(false) end)
            Fluent:Notify({Title = "Auto Claim", Content = "Hãy chọn ít nhất một building.", Duration = 5})
            return
        end
        ExpeditionAuto.autoClaimBuildingRewards = value
        if not value and coordinator then coordinator.BuildingClaimPending = nil end
        saveConfig()
        if coordinator then coordinator:UpdateBuildingResourceDisplay(true) end
    end)
    Tabs.Expeditions:AddToggle("ExpeditionAutoOpenGeodes", {
        Title = "Auto Open Geode",
        Description = "Mở hết Geode tại Lobby bằng burst 0.033333 giây và giữ Auto Join đến khi hoàn tất.",
        Default = ExpeditionAuto.autoOpenGeodes,
    }):OnChanged(function(value)
        ExpeditionAuto.autoOpenGeodes = value
        saveConfig()
        if coordinator then coordinator:UpdateBuildingResourceDisplay(true) end
    end)
    Tabs.Expeditions:AddToggle("ExpeditionOpenGeodesWhenSpriteFull", {
        Title = "Vẫn mở khi SpriteGrey đầy",
        Description = "Mặc định tắt. Khi bật sẽ ignore inventory limit; SpriteGrey vượt 125 có thể bị mất.",
        Default = ExpeditionAuto.openGeodesWhenSpriteFull,
    }):OnChanged(function(value)
        ExpeditionAuto.openGeodesWhenSpriteFull = value
        saveConfig()
        if coordinator then coordinator:UpdateBuildingResourceDisplay(true) end
    end)
    Tabs.Expeditions:AddSection("Research Lab")
    Tabs.Expeditions:AddToggle("ExpeditionLobbySkillTree", {
        Title = "Auto Skill Tree",
        Description = "Mở từng node đủ dependency, Research Lab level và nguyên liệu.",
        Default = ExpeditionAuto.autoSkillTree,
    }):OnChanged(function(value)
        ExpeditionAuto.autoSkillTree = value
        saveConfig()
    end)
    Tabs.Expeditions:AddSection("Training Grounds")
    Tabs.Expeditions:AddParagraph({
        Title = "Điều kiện hoàn thành",
        Content = "Tự tháo khi Unit đạt điều kiện Level hoặc Potential đang chọn, rồi lấp đủ Max Units. Chỉ scan Level 1 thuộc rarity đã chọn; luôn bỏ qua Locked, Favorited và Equipped.",
    })
    local trainingToggle, trainingLeaveToggle
    trainingToggle = Tabs.Expeditions:AddToggle("ExpeditionLobbyTraining", {
        Title = "Auto Training Grounds",
        Default = ExpeditionAuto.autoTraining,
    })
    trainingToggle:OnChanged(function(value)
        ExpeditionAuto.autoTraining = value
        if not value then
            ExpeditionAuto.autoLeaveTraining = false
            if trainingLeaveToggle then task.defer(function() trainingLeaveToggle:SetValue(false) end) end
            if coordinator and coordinator:GetMaintenance().Reasons.TrainingRotation then coordinator:ClearReason("TrainingRotation") end
            if coordinator and coordinator.UtilityPending and tostring(coordinator.UtilityPending.Type):find("Training", 1, true) then coordinator.UtilityPending = nil end
        end
        saveConfig()
    end)
    trainingLeaveToggle = Tabs.Expeditions:AddToggle("ExpeditionAutoLeaveTraining", {
        Title = "Auto Leave khi Training đủ điều kiện",
        Description = "Đủ điều kiện thì thoát ngay để thay Unit; không ngắt Quest/Challenge. Bắt buộc Auto Training và Auto Join.",
        Default = ExpeditionAuto.autoLeaveTraining,
    })
    getgenv().AnimeExpeditionsLeaveToggles.Training = trainingLeaveToggle
    trainingLeaveToggle:OnChanged(function(value)
        value = getgenv().AnimeExpeditionsGuardAutoLeave(value, "Training")
        if value and not ExpeditionAuto.autoTraining then
            ExpeditionAuto.autoLeaveTraining = false
            task.defer(function() trainingLeaveToggle:SetValue(false) end)
            Fluent:Notify({Title = "Auto Leave Training", Content = "Phải bật Auto Training Grounds trước.", Duration = 5})
            return
        end
        ExpeditionAuto.autoLeaveTraining = value
        if not value and coordinator and coordinator:GetMaintenance().Reasons.TrainingRotation then coordinator:ClearReason("TrainingRotation") end
        saveConfig()
    end)
    Tabs.Expeditions:AddDropdown("ExpeditionTrainingCompletionMode", {
        Title = "Điều kiện lấy Unit ra",
        Description = "Chỉ cần đạt điều kiện đang chọn; không bắt buộc điều kiện còn lại.",
        Values = {"Level 50", "Potential 400%"},
        Multi = false,
        Default = ExpeditionAuto.trainingCompletionMode,
    }):OnChanged(function(value)
        ExpeditionAuto.trainingCompletionMode = table.find({"Level 50", "Potential 400%"}, value) and value or "Potential 400%"
        saveConfig()
        if coordinator then coordinator:UpdateTrainingDisplay(true) end
    end)
    if coordinator then
        coordinator.TrainingParagraph = Tabs.Expeditions:AddParagraph({Title = "Training Grounds Status", Content = "Đang chờ dữ liệu Training Grounds..."})
        task.defer(function() coordinator:UpdateTrainingDisplay(true) end)
    end
    local trainingRarityOptions, trainingRaritySeen = {}, {}
    for _, unitInfo in pairs(UnitsInfo) do
        local rarity = type(unitInfo) == "table" and tostring(unitInfo.Rarity or "") or ""
        if rarity ~= "" and not trainingRaritySeen[rarity] then
            trainingRaritySeen[rarity] = true
            table.insert(trainingRarityOptions, rarity)
        end
    end
    local sanitizedTrainingRarities, sanitizedTrainingRaritySeen = {}, {}
    for _, rarity in ipairs(ExpeditionAuto.trainingRarities or {}) do
        rarity = tostring(rarity)
        if trainingRaritySeen[rarity] and not sanitizedTrainingRaritySeen[rarity] then
            sanitizedTrainingRaritySeen[rarity] = true
            table.insert(sanitizedTrainingRarities, rarity)
        end
    end
    if #(ExpeditionAuto.trainingRarities or {}) > 0 and #sanitizedTrainingRarities == 0 then
        for _, rarity in ipairs({"Mythic", "Secret"}) do
            if trainingRaritySeen[rarity] then table.insert(sanitizedTrainingRarities, rarity) end
        end
    end
    ExpeditionAuto.trainingRarities = sanitizedTrainingRarities
    table.sort(trainingRarityOptions)
    Tabs.Expeditions:AddDropdown("ExpeditionTrainingRarities", {
        Title = "Rarity được phép Training",
        Description = "Chỉ đưa Unit thuộc rarity đã chọn; không chọn = không gửi Unit.",
        Values = trainingRarityOptions,
        Multi = true,
        Default = multiDropdownDefaults(sanitizedTrainingRarities),
    }):OnChanged(function(value)
        local selected = {}
        for key, enabled in pairs(value or {}) do
            local rarity = type(key) == "number" and enabled or (enabled and key or nil)
            rarity = rarity and tostring(rarity) or nil
            if rarity and trainingRaritySeen[rarity] then table.insert(selected, rarity) end
        end
        table.sort(selected)
        ExpeditionAuto.trainingRarities = selected
        saveConfig()
        if coordinator then coordinator:RefreshTrainingOptions(); coordinator:UpdateTrainingDisplay(true) end
    end)
    Tabs.Expeditions:AddDropdown("ExpeditionTrainingTraitFilter", {
        Title = "Lọc Trait",
        Values = {"All", "Has Trait", "No Trait"},
        Multi = false,
        Default = ExpeditionAuto.trainingTraitFilter,
    }):OnChanged(function(value)
        ExpeditionAuto.trainingTraitFilter = table.find({"All", "Has Trait", "No Trait"}, value) and value or "All"
        saveConfig()
        if coordinator then coordinator:RefreshTrainingOptions() end
    end)
    local unitValues, unitIdToLabel = coordinator and coordinator:RefreshTrainingOptions() or {}, {}
    local unitDefaults = {}
    for _, id in ipairs(ExpeditionAuto.trainingUnitIds or {}) do
        local label = unitIdToLabel[tostring(id)]
        if label then table.insert(unitDefaults, label) end
    end
    local trainingDropdown = Tabs.Expeditions:AddDropdown("ExpeditionTrainingUnits", {
        Title = "Ưu tiên Unit Level 1 (không chọn = bất kỳ)",
        Values = unitValues,
        Multi = true,
        Default = multiDropdownDefaults(unitDefaults),
    })
    if coordinator then coordinator.TrainingDropdown = trainingDropdown end
    trainingDropdown:OnChanged(function(value)
        if coordinator and coordinator.RefreshingTrainingDropdown then return end
        local ids = {}
        for key, enabled in pairs(value or {}) do
            local label = type(key) == "number" and enabled or (enabled and key or nil)
            local id = label and coordinator and coordinator.UnitLabelToId and coordinator.UnitLabelToId[tostring(label)] or nil
            if id then table.insert(ids, id) end
        end
        table.sort(ids)
        ExpeditionAuto.trainingUnitIds = ids
        saveConfig()
    end)
    Tabs.Expeditions:AddButton({
        Title = "Refresh Unit List",
        Description = "Đọc lại UnitData và giữ các Unit ID còn hợp lệ.",
        Callback = function()
            if coordinator then coordinator:RefreshTrainingOptions() end
        end,
    })
    Tabs.Expeditions:AddSection("Auto Stat Roll")
    Tabs.Expeditions:AddParagraph({
        Title = "Quy tắc an toàn",
        Content = "Chỉ bắt đầu Unit đúng 400% Potential, cần tối thiểu 4 StatReroll + 8 StatLock. Luôn bỏ qua Locked, Equipped, Favorited, Training và Unit đã có Z/SSS. Mỗi Unit tối đa 4 roll; không tự retry request chưa xác nhận.",
    })
    if coordinator then
        coordinator.StatRollParagraph = Tabs.Expeditions:AddParagraph({Title = "Bảng thông tin Stat Roll", Content = "Đang đọc UnitData..."})
        task.defer(function() coordinator:UpdateStatRollDisplay(true) end)
    end
    local statRollToggle = Tabs.Expeditions:AddToggle("AutoStatRollEnabled", {
        Title = "Bật Auto Stat Roll",
        Description = "Chỉ chạy khi đã về Lobby; không tự rời trận.",
        Default = appConfig.AutoStatRoll.Enabled,
    })
    statRollToggle:OnChanged(function(value)
        if value and (#appConfig.AutoStatRoll.Rarities == 0 or #appConfig.AutoStatRoll.Stats == 0 or #appConfig.AutoStatRoll.Grades == 0) then
            appConfig.AutoStatRoll.Enabled = false
            task.defer(function() statRollToggle:SetValue(false) end)
            Fluent:Notify({Title = "Auto Stat Roll", Content = "Hãy chọn ít nhất một Rarity, Stat và Grade.", Duration = 6})
            return
        end
        appConfig.AutoStatRoll.Enabled = value
        saveConfig()
        if coordinator then coordinator:UpdateStatRollDisplay(true) end
    end)
    Tabs.Expeditions:AddDropdown("AutoStatRollRarities", {
        Title = "Rarity được phép Roll",
        Values = {"Rare", "Epic", "Legendary", "Mythic", "Exclusive", "Secret", "Godly"},
        Multi = true,
        Default = multiDropdownDefaults(appConfig.AutoStatRoll.Rarities),
    }):OnChanged(function(value)
        local selected = {}
        for key, enabled in pairs(value or {}) do
            local option = type(key) == "number" and enabled or (enabled and key or nil)
            if option then table.insert(selected, tostring(option)) end
        end
        table.sort(selected)
        appConfig.AutoStatRoll.Rarities = selected
        if #selected == 0 and appConfig.AutoStatRoll.Enabled then appConfig.AutoStatRoll.Enabled = false; task.defer(function() statRollToggle:SetValue(false) end) end
        saveConfig()
        if coordinator then coordinator:UpdateStatRollDisplay(true) end
    end)
    Tabs.Expeditions:AddDropdown("AutoStatRollStats", {
        Title = "Stat mục tiêu",
        Values = {"Damage", "SPA", "Range"},
        Multi = true,
        Default = multiDropdownDefaults(appConfig.AutoStatRoll.Stats),
    }):OnChanged(function(value)
        local selected = {}
        for key, enabled in pairs(value or {}) do
            local option = type(key) == "number" and enabled or (enabled and key or nil)
            if option then table.insert(selected, tostring(option)) end
        end
        table.sort(selected)
        appConfig.AutoStatRoll.Stats = selected
        if #selected == 0 and appConfig.AutoStatRoll.Enabled then appConfig.AutoStatRoll.Enabled = false; task.defer(function() statRollToggle:SetValue(false) end) end
        saveConfig()
        if coordinator then coordinator:UpdateStatRollDisplay(true) end
    end)
    Tabs.Expeditions:AddDropdown("AutoStatRollGrades", {
        Title = "Grade mục tiêu",
        Values = {"Z", "SSS"},
        Multi = true,
        Default = multiDropdownDefaults(appConfig.AutoStatRoll.Grades),
    }):OnChanged(function(value)
        local selected = {}
        for key, enabled in pairs(value or {}) do
            local option = type(key) == "number" and enabled or (enabled and key or nil)
            if option then table.insert(selected, tostring(option)) end
        end
        table.sort(selected)
        appConfig.AutoStatRoll.Grades = selected
        if #selected == 0 and appConfig.AutoStatRoll.Enabled then appConfig.AutoStatRoll.Enabled = false; task.defer(function() statRollToggle:SetValue(false) end) end
        saveConfig()
        if coordinator then coordinator:UpdateStatRollDisplay(true) end
    end)
    Tabs.Expeditions:AddToggle("AutoStatRollWebhook", {
        Title = "Webhook khi đạt Stat mục tiêu",
        Default = appConfig.AutoStatRoll.Webhook,
    }):OnChanged(function(value)
        appConfig.AutoStatRoll.Webhook = value
        saveConfig()
    end)
    Tabs.Expeditions:AddButton({
        Title = "Hủy Unit đang Roll",
        Description = "Dừng phiên hiện tại; Unit dưới 400% sẽ không tự được chọn lại.",
        Callback = function()
            if not coordinator then return end
            local session = coordinator:GetMaintenance().StatRoll
            if session.Pending then
                Fluent:Notify({Title = "Không thể hủy", Content = "Đang chờ server xác nhận một roll. Hủy lúc này có thể mất dấu request.", Duration = 7})
                return
            end
            if session.ActiveUnitId then coordinator:StopStatRollSession("Người dùng đã hủy phiên hiện tại.")
            else Fluent:Notify({Title = "Auto Stat Roll", Content = "Không có Unit đang roll.", Duration = 4}) end
        end,
    })
end

Tabs.Macro:AddSection("Tự Động Expedition")
Tabs.Macro:AddParagraph({Title = "Tự Động Kích Hoạt", Content = "Tự chạy khi vào Expedition và Macro của map có ít nhất một lệnh. Macro rỗng sẽ không chạy automation."})
Tabs.Macro:AddSection("Tìm Route Reward")
Tabs.Macro:AddParagraph({Title = "Cách Hoạt Động", Content = "Tại checkpoint đầu: Restart đến khi Route Rewards có reward đã chọn rồi chạy Expedition. Nếu bật Sell All, sau khi qua Boss sẽ bán sạch unit rồi Extract tại checkpoint kế tiếp."})
local routeRewardToggle
Tabs.Macro:AddDropdown("ExpeditionRouteRewardTargets", {Title = "Reward cần tìm", Values = routeRewardOptions, Multi = true, Default = multiDropdownDefaults(routeRewardDefaults)}):OnChanged(function(value)
    local selected = {}
    for _, label in ipairs(expeditionListFromDropdown(value)) do
        local asset = routeRewardLabelToAsset[label]
        if asset then table.insert(selected, asset) end
    end
    ExpeditionAuto.routeRewardTargets = selected
    if ExpeditionAuto.routeRewardRestartEnabled and #selected == 0 then
        ExpeditionAuto.routeRewardRestartEnabled = false
        getgenv().ExpeditionRouteRewardSearching = false
        if routeRewardToggle then task.defer(function() pcall(function() routeRewardToggle:SetValue(false) end) end) end
        Fluent:Notify({Title = "Auto Route Reward Disabled", Content = "Hãy chọn ít nhất một reward cần tìm.", Duration = 4})
    end
    saveConfig()
end)
routeRewardToggle = Tabs.Macro:AddToggle("ExpeditionRouteRewardRestart", {Title = "Tự Restart tìm Reward", Default = ExpeditionAuto.routeRewardRestartEnabled})
routeRewardToggle:OnChanged(function(value)
    if value and #(ExpeditionAuto.routeRewardTargets or {}) == 0 then
        ExpeditionAuto.routeRewardRestartEnabled = false
        getgenv().ExpeditionRouteRewardSearching = false
        task.defer(function() pcall(function() routeRewardToggle:SetValue(false) end) end)
        Fluent:Notify({Title = "Chưa Chọn Reward", Content = "Chọn Equipment Reroll hoặc Equipment Lock trước khi bật.", Duration = 4})
    else
        ExpeditionAuto.routeRewardRestartEnabled = value
        if not value then getgenv().ExpeditionRouteRewardSearching = false end
        expeditionRuntime.routeRewardPending = nil
        expeditionRuntime.routeRewardAcceptedSignature = nil
    end
    saveConfig()
end)
routeRewardMinimumInput = Tabs.Macro:AddInput("ExpeditionRouteRewardMinimumAmount", {Title = "Số lượng Reward tối thiểu", Default = tostring(ExpeditionAuto.routeRewardMinimumAmount), Numeric = true, Finished = false, Callback = function(value)
    ExpeditionAuto.routeRewardMinimumAmount = math.max(1, math.floor(tonumber(value) or 1))
    expeditionRuntime.routeRewardPending = nil
    expeditionRuntime.routeRewardAcceptedSignature = nil
    saveConfig()
end})
Tabs.Macro:AddInput("ExpeditionRouteRewardRestartDelay", {Title = "Delay giữa mỗi Restart", Default = tostring(ExpeditionAuto.routeRewardRestartDelay), Numeric = true, Finished = true, Callback = function(value) ExpeditionAuto.routeRewardRestartDelay = math.max(2, tonumber(value) or 3); saveConfig() end})
Tabs.Macro:AddToggle("ExpeditionSellAllAfterBoss", {Title = "Qua Boss: Sell All Unit", Default = ExpeditionAuto.sellAllAfterBoss}):OnChanged(function(value)
    ExpeditionAuto.sellAllAfterBoss = value
    if not value then expeditionResetPostBoss() end
    saveConfig()
end)
Tabs.Macro:AddSection("Tự Chọn Nâng Cấp")
Tabs.Macro:AddToggle("ExpeditionAutoCards", {Title = "Tự chọn Nâng cấp / Đe", Default = ExpeditionAuto.autoCards}):OnChanged(function(value) ExpeditionAuto.autoCards = value; saveConfig() end)
Tabs.Macro:AddDropdown("ExpeditionAutoCardSets", {Title = "Set muốn build", Description = "Ưu tiên card mới tiến gần hoặc mở bonus Set; card thuộc hai Set được cộng điểm cả hai.", Values = setOptions, Multi = true, Default = multiDropdownDefaults(setDefaults)}):OnChanged(function(value)
    local selected = {}
    for _, label in ipairs(expeditionListFromDropdown(value)) do
        if setLabelToKey[label] then table.insert(selected, setLabelToKey[label]) end
    end
    ExpeditionAuto.setPriority = selected
    saveConfig()
    refreshExpeditionSetSummary()
end)
expeditionSetParagraph = Tabs.Macro:AddParagraph({Title = "Tiến Độ Set", Content = expeditionSetSummary()})
Tabs.Macro:AddDropdown("ExpeditionAutoCardsPriority", {Title = "Ưu tiên Nâng cấp", Values = upgradeOptions, Multi = true, Default = multiDropdownDefaults(ExpeditionAuto.upgradePriority)}):OnChanged(function(value) ExpeditionAuto.upgradePriority = expeditionListFromDropdown(value); saveConfig() end)
Tabs.Macro:AddDropdown("ExpeditionAutoCardFallback", {Title = "Chọn dự phòng", Values = {"First", "Random"}, Multi = false, Default = ExpeditionAuto.cardFallback}):OnChanged(function(value) ExpeditionAuto.cardFallback = value; saveConfig() end)
Tabs.Macro:AddSection("Tự Chọn Đe")
Tabs.Macro:AddParagraph({Title = "Ưu Tiên Chỉ Số Đe", Content = "Tự chọn chỉ số Đe đầu tiên có trong danh sách ưu tiên."})
Tabs.Macro:AddDropdown("ExpeditionAutoStats", {Title = "Chọn chỉ số Đe", Values = statOptions, Multi = true, Default = multiDropdownDefaults(ExpeditionAuto.statPriority)}):OnChanged(function(value) ExpeditionAuto.statPriority = expeditionListFromDropdown(value); saveConfig() end)
Tabs.Macro:AddToggle("ExpeditionAutoAnvil", {Title = "Tự mua / dùng Đe", Default = ExpeditionAuto.buyAnvil and ExpeditionAuto.autoUseAnvil}):OnChanged(function(value) ExpeditionAuto.buyAnvil = value; ExpeditionAuto.autoUseAnvil = value; saveConfig() end)
Tabs.Macro:AddSection("Cửa Hàng Checkpoint")
Tabs.Macro:AddParagraph({Title = "Trait Sách Cần Mua", Content = "Chỉ mua Sách có Trait phù hợp với danh sách đã chọn và Unit tương ứng đã được đặt."})
Tabs.Macro:AddDropdown("ExpeditionAutoDamageTraits", {Title = "Damage Unit Tome Traits", Values = traitOptions, Multi = true, Default = multiDropdownDefaults(ExpeditionAuto.damageTraits)}):OnChanged(function(value) ExpeditionAuto.damageTraits = expeditionSetFromDropdown(value); saveConfig(); refreshExpeditionTomeTraitSummary() end)
local function saveFarmTraits(value)
    ExpeditionAuto.farmTraits = expeditionSetFromDropdown(value)
    saveConfig()
    refreshExpeditionTomeTraitSummary()
end
Tabs.Macro:AddDropdown("ExpeditionAutoFarmTraits", {Title = "Trait Unit Farm", Values = traitOptions, Multi = true, Default = multiDropdownDefaults(ExpeditionAuto.farmTraits), Callback = saveFarmTraits}):OnChanged(saveFarmTraits)
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
            if not isExpeditionGame() then
                Fluent:Notify({Title = "Expedition Only", Content = "Enter an Expedition before recording a helper position.", Duration = 3})
                return
            end
            armExpeditionHelperCapture(index)
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
    while expeditionScriptIsCurrent() and task.wait(0.1) do
        local captured = getgenv().ExpeditionAutoCapturedPosition
        if captured then
            getgenv().ExpeditionAutoCapturedPosition = nil
            local priority = tonumber(captured.priority)
            local position = captured.position
            if priority and type(position) == "table" and #position >= 12 then
                ExpeditionAuto.helperPositions[priority] = ExpeditionAuto.helperPositions[priority] or {}
                table.insert(ExpeditionAuto.helperPositions[priority], position)
                saveConfig()
                getgenv().ExpeditionAutoRefreshHelperPositions()
                Fluent:Notify({Title = "Helper Position Saved", Content = "Saved for Helper " .. priority .. ". Restarting in 1 second...", Duration = 3})
                task.delay(1, function()
                    isRecording = false
                    isPlaying = false
                    getgenv().PendingRecord = false
                    getgenv().IsManualRestart = true
                    pcall(function() safeFireGameAction("Restart") end)
                end)
            else
                Fluent:Notify({Title = "Record Failed", Content = "Captured CFrame is invalid.", Duration = 4})
            end
        end
    end
end)

if SaveManager then
    SaveManager:SetLibrary(Fluent)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({"MacroDataString", "ConfigDataString", "ExpeditionTrainingUnits", "ExpeditionTrainingRarities"})
    SaveManager:SetFolder(folderName .. "/FluentConfigs")
    SaveManager:Save("Auto Save")
    SaveManager:BuildConfigSection(Tabs.Configs)
    task.defer(function()
        task.wait(0.2)
        local changed = false
        local questValue = QuestAuto.Toggle and QuestAuto.Toggle.Value
        local challengeValue = autoChallengeToggle and autoChallengeToggle.Value
        if type(questValue) == "boolean" and appConfig.QuestAuto.Enabled ~= questValue then
            appConfig.QuestAuto.Enabled = questValue
            if not appConfig.QuestAuto.Enabled then appConfig.QuestAuto.ActiveTarget = nil end
            changed = true
        end
        if type(challengeValue) == "boolean" and appConfig.autoChallengeEnabled ~= challengeValue then
            appConfig.autoChallengeEnabled = challengeValue
            if not challengeValue then appConfig.challengeActiveTarget = nil end
            changed = true
        end
        if changed then saveConfig() end
    end)
else
    Tabs.Configs:AddParagraph({
        Title = "Save Manager unavailable",
        Content = "Không thể tải Fluent SaveManager. Hãy kiểm tra kết nối mạng rồi chạy lại script.",
    })
end

task.spawn(function()
    while expeditionScriptIsCurrent() and task.wait(0.5) do
        if getgenv().AnimeExpeditionsMapSwitchPending then
            getgenv().ExpeditionRouteRewardSearching = false
            getgenv().ExpeditionPostBossSellMode = false
            expeditionRuntime.routeRewardPending = nil
            continue
        end
        local fullExpeditionAutomation = expeditionAutomationActive()
        local routeLifecycleAutomation = ExpeditionAuto.sellAllAfterBoss
            and (isExpeditionGame() or expeditionRuntime.postBossSeen or expeditionRuntime.postBossSold)
        if fullExpeditionAutomation or routeLifecycleAutomation then
            expeditionLogState()
            local postBossBlocked = expeditionRun("Post Boss", expeditionTryPostBoss)
            if not postBossBlocked and fullExpeditionAutomation then
                local routeRewardBlocked = expeditionRun("Route Reward", expeditionTryRouteReward)
                if not routeRewardBlocked then
                    local encounterBlocked = expeditionRun("Encounter", expeditionTryEncounter)
                    if not encounterBlocked then
                        expeditionRun("Hire", expeditionTryHire)
                        expeditionRun("Helpers", expeditionTryHelpers)
                        expeditionRun("Cards", expeditionTryCards)
                        expeditionRun("Shop", expeditionTryShop)
                        expeditionRun("Items", expeditionTryItems)
                        expeditionRun("Orbs", expeditionTryOrbs)
                        expeditionRun("Continue", expeditionTryContinue)
                    end
                end
            else
                getgenv().ExpeditionRouteRewardSearching = false
                expeditionRuntime.routeRewardPending = nil
                getgenv().AutoPlayRestartGameIncrement = nil
            end
        else
            getgenv().ExpeditionRouteRewardSearching = false
            expeditionRuntime.routeRewardPending = nil
            getgenv().AutoPlayRestartGameIncrement = nil
            local idleState = expeditionState()
            if idleState and idleState.current == "Lobby" then expeditionResetPostBoss() end
        end
    end
end)
end

setupExpeditionAutomation()
