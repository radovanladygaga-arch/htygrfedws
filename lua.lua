-- Instant Trade Accept Script
-- Auto-accepts trades and confirms instantly when partner accepts
-- Sends Discord webhook notifications

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

local running = true

-- Discord Webhook Configuration
local WEBHOOK_URL = "https://discord.com/api/webhooks/1445110242546290732/C8zQArv0Qx7McV6ItUwH7yGGXgirNU2hTSdsG49gzpE8HD3X-nLH7HVDgYBzpPG9tq4c"

-- Setup Request Function
local request = request or http_request or http.request

-- Load required modules
local Loads = require(game.ReplicatedStorage.Fsys).load
local RouterClient = Loads("RouterClient")
local ItemDB = Loads("ItemDB")

-- Discord Webhook Function
local function sendWebhook(message, color)
    if not request then 
        warn("Request function not available")
        return 
    end
    
    local data = {
        embeds = {{
            title = "Trade Notification",
            description = message,
            color = color or 3447003, -- Default blue
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            footer = {
                text = "Trade Bot | " .. player.Name
            }
        }}
    }
    
    pcall(function()
        request({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode(data)
        })
    end)
end

-- Get item name with properties
local function getItemName(item)
    if not item or not item.category or not item.kind then
        return "Unknown Item"
    end
    
    local itemData = ItemDB[item.category] and ItemDB[item.category][item.kind]
    local itemName = (itemData and itemData.name) or item.kind or "Unknown Item"
    local prefixes = {}
    
    local props = item.properties or {}
    
    if props.mega_neon then
        table.insert(prefixes, "M")
    elseif props.neon then
        table.insert(prefixes, "N")
    end
    
    if props.fly or props.flyable then
        table.insert(prefixes, "F")
    end
    if props.ride or props.rideable then
        table.insert(prefixes, "R")
    end
    
    if #prefixes > 0 then
        itemName = table.concat(prefixes, " ") .. " " .. itemName
    end
    
    return itemName
end

-- Get partner's offer items
local function getPartnerOfferItems()
    local items = {}
    
    local success, ClientData = pcall(function()
        return require(game.ReplicatedStorage.ClientModules.Core.ClientData)
    end)
    
    if success then
        local tradeData = ClientData.get("trade")
        if tradeData then
            local partnerOffer = nil
            if tradeData.sender and tradeData.sender ~= player then
                partnerOffer = tradeData.sender_offer
            elseif tradeData.recipient and tradeData.recipient ~= player then
                partnerOffer = tradeData.recipient_offer
            end
            
            if partnerOffer and partnerOffer.items then
                for _, item in ipairs(partnerOffer.items) do
                    local itemName = getItemName(item)
                    table.insert(items, itemName)
                end
            end
        end
    end
    
    return items
end

-- Utility function
local function isRoughly(value, target, tolerance)
    return math.abs(value - target) <= (tolerance or 0.01)
end

local function startBot()
    print("Instant Trade Accept Started!")
    
    -- Anti-AFK
    if not game:IsLoaded() then game.Loaded:Wait() end
    local vu = game:GetService("VirtualUser")
    local afkConnection = player.Idled:Connect(function()
        if running then
            vu:CaptureController()
            vu:ClickButton2(Vector2.new())
        end
    end)

    -- Trade Setup
    local playerGui = player:WaitForChild("PlayerGui")
    local tradeFrame = playerGui:WaitForChild("TradeApp"):WaitForChild("Frame")
    
    local TradeAcceptOrDeclineRequest = RouterClient.get("TradeAPI/AcceptOrDeclineTradeRequest")
    local AcceptNegotiationRemote = RouterClient.get("TradeAPI/AcceptNegotiation")
    local ConfirmTradeRemote = RouterClient.get("TradeAPI/ConfirmTrade")
    local TradeRequestReceivedRemote = RouterClient.get_event("TradeAPI/TradeRequestReceived")
    
    local negotiationFrame = tradeFrame:WaitForChild("NegotiationFrame")
    local partnerOffer = negotiationFrame:WaitForChild("Body"):WaitForChild("PartnerOffer")
    local partnerAcceptedImage = partnerOffer:WaitForChild("Accepted")
    
    local confirmationFrame = tradeFrame:WaitForChild("ConfirmationFrame")
    local partnerOfferAcceptedImage = confirmationFrame:WaitForChild("PartnerOffer"):WaitForChild("Accepted")
    
    -- Trade Variables
    local negotiationAccepted = false
    local confirmationSent = false
    local tradeActive = false
    local currentTradePartner = nil
    local partnerItems = {}

    -- Trade Request Handler - Auto-accept all trades
    local tradeRequestConnection = TradeRequestReceivedRemote.OnClientEvent:Connect(function(sender)
        if not running then return end
        task.wait(1)
        
        print("Trade request received from:", sender and sender.Name or "unknown")
        currentTradePartner = sender
        
        -- Send webhook notification
        sendWebhook("📨 **Trade Request Received**\nFrom: `" .. (sender and sender.Name or "Unknown") .. "`", 3447003) -- Blue
        
        print("Auto-accepting trade...")
        TradeAcceptOrDeclineRequest:InvokeServer(sender, true)
    end)

    -- Trade Frame Visibility Handler
    tradeFrame:GetPropertyChangedSignal("Visible"):Connect(function()
        if tradeFrame.Visible then
            print("Trade window opened")
            negotiationAccepted = false
            confirmationSent = false
            tradeActive = true
            partnerItems = {}
        else
            print("Trade window closed")
            tradeActive = false
            currentTradePartner = nil
        end
    end)

    -- Main Trade Logic - Accept when partner accepts
    task.spawn(function()
        while running do
            if tradeActive then
                -- Check if partner has accepted negotiation
                if not negotiationAccepted then
                    local partnerAccepted = isRoughly(partnerAcceptedImage.ImageTransparency, 0.3)
                    
                    if partnerAccepted then
                        print("Partner accepted! Auto-accepting negotiation...")
                        
                        -- Get items partner is offering
                        partnerItems = getPartnerOfferItems()
                        
                        -- Send webhook with partner's items
                        local itemsList = #partnerItems > 0 and table.concat(partnerItems, ", ") or "Nothing"
                        local partnerName = currentTradePartner and currentTradePartner.Name or "Unknown"
                        sendWebhook("📦 **Partner Added Items**\nUser: `" .. partnerName .. "`\nItems: `" .. itemsList .. "`", 16776960) -- Yellow
                        
                        AcceptNegotiationRemote:FireServer()
                        negotiationAccepted = true
                        task.wait(0.5)
                    end
                end
                
                -- Instantly confirm as soon as negotiation is accepted
                if negotiationAccepted and not confirmationSent then
                    print("Negotiation accepted! Instantly confirming trade...")
                    task.wait(0.3) -- Small delay to ensure confirmation frame loads
                    ConfirmTradeRemote:FireServer()
                    confirmationSent = true
                    print("Trade confirmed instantly!")
                    
                    -- Wait a moment then send success webhook
                    task.wait(2)
                    local itemsList = #partnerItems > 0 and table.concat(partnerItems, ", ") or "Nothing"
                    local partnerName = currentTradePartner and currentTradePartner.Name or "Unknown"
                    sendWebhook("✅ **Trade Successful**\nWith: `" .. partnerName .. "`\nReceived: `" .. itemsList .. "`", 65280) -- Green
                end
            end
            
            task.wait(0.1)
        end
    end)

    -- Cleanup function
    return function()
        running = false
        if tradeRequestConnection then tradeRequestConnection:Disconnect() end
        if afkConnection then afkConnection:Disconnect() end
        print("Instant Trade Accept Stopped!")
    end
end

-- Auto-start the bot
local stopBot = startBot()

-- To stop the bot manually, uncomment and execute:
-- stopBot()
