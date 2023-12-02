local mq = require('mq')
local LIP = require('lib/LIP')
local utils = require('lib/ed/utils')
local BFOUtils = require('lib/bfoutils')

local ImGui = require('ImGui')

local auctionjob_settings_file = '/lua/config/auction.ini'
local auctionjob_settings_path = ""
local auctionsettings = {}

local AuctionJob = {}
local newAuctionPopup = "new_auction_popup"
local AuctionTimer = 5 -- auction every 5 mins
local lastAuction = 0
local AuctionChannelNumber = "0"
local AuctionText = {}
local pauseAuctioning = true

local popupAuctionCost = ""
local popupAuctionItem = ""

local cacheItems = function()
    local itemCount = 0
    local line = ""
    local lineCount = 1

    if (auctionsettings and #AuctionText == 0) then
        if auctionsettings[CharConfig] then
            for k, v in pairs(auctionsettings[CharConfig]) do
                if line:len() > 0 then line = line .. " | " end
                line = line .. mq.TLO.LinkDB("=" .. k)() .. " " .. v
                itemCount = itemCount + 1
                if itemCount == 4 then
                    print(string.format("Cached[%d]: %s", lineCount, line))
                    AuctionText[lineCount] = line
                    lineCount = lineCount + 1
                    line = ""
                    itemCount = 0
                end
            end
        end
    end

    if line:len() > 0 then
        print(string.format("Cached[%d]: %s", lineCount, line))
        AuctionText[lineCount] = line
    end
end

local SaveSettings = function(clearItems)
    print("Saving Auction Settings...")
    LIP.save(auctionjob_settings_path, auctionsettings)

    if clearItems then
        AuctionText = {}
        cacheItems()
    end
end

function AuctionJob.Setup(config_dir)
    if auctionjob_settings_path:len() == 0 then
        auctionjob_settings_path = config_dir .. auctionjob_settings_file
    end

    auctionsettings = {}

    if file_exists(auctionjob_settings_path) then
        auctionsettings = LIP.load(auctionjob_settings_path)

        if auctionsettings["Default"] then
            AuctionTimer = auctionsettings["Default"]["Timer"] or 5
            AuctionChannelNumber = tostring(auctionsettings["Default"]["ChannelNumber"]) or "0"
        else
            auctionsettings["Default"] = {}
            auctionsettings["Default"]["Timer"] = 5
            auctionsettings["Default"]["ChannelNumber"] = "0"

            SaveSettings()
        end
    else
        print("Can't find auctionjob.ini at: " .. auctionjob_settings_path)
        return
    end

    cacheItems()
end

local RenderNewAuctionPopup = function()
    if ImGui.BeginPopup(newAuctionPopup) then
        ImGui.Text("Item Name:")
        local tmp_item, selected_item = ImGui.InputText("##edit_item", popupAuctionItem, 0)
        if selected_item then popupAuctionItem = tmp_item end

        ImGui.Text("Item Cost:")
        local tmp_cost, selected_cost = ImGui.InputText("##edit_cost", popupAuctionCost, 0)
        if selected_cost then popupAuctionCost = tmp_cost end

        if ImGui.Button("Save") then
            if popupAuctionItem ~= nil and popupAuctionItem:len() > 0 then
                auctionsettings[CharConfig] = auctionsettings[CharConfig] or {}
                auctionsettings[CharConfig][popupAuctionItem] = popupAuctionCost
                SaveSettings(true)
                AuctionJob.Setup()
            else
                print("\arError Saving Auction Item: Item Name cannot be empty.\ax")
            end

            popupAuctionCost = ""
            popupAuctionItem = ""

            ImGui.CloseCurrentPopup()
        end

        ImGui.SameLine()

        if ImGui.Button("Cancel") then
            ImGui.CloseCurrentPopup()
        end
        ImGui.EndPopup()
    end
end

local forceAuction = false

local doAuction = function(ignorePause)
    cacheItems()

    if not forceAuction then
        if pauseAuctioning and not ignorePause then
            return
        end
    end

    local tokens = BFOUtils.Tokenize(AuctionChannelNumber, "|")

    for _, v in ipairs(AuctionText) do
        for _, c in ipairs(tokens) do
            mq.cmdf("/%s WTS %s", c, v)
            print(string.format("/%s WTS %s", c, v))
            mq.delay(500)
        end
    end

    forceAuction = false
    lastAuction = os.clock()
end

local addCursorItem = function()
    if mq.TLO.Cursor() ~= nil then
        popupAuctionItem = mq.TLO.Cursor()
        openPopup = true
    end
end

local ICON_WIDTH = 50
local ICON_HEIGHT = 50

function AuctionJob.Render()
    if not auctionsettings then return end

    ImGui.Text("Auction Settings")
    AuctionTimer, used = ImGui.SliderInt("Auction Timer", AuctionTimer, 1, 10, "%d")
    if used then
        auctionsettings["Default"]["Timer"] = AuctionTimer
        SaveSettings(false)
    end
    newText, selected = ImGui.InputText("Auction Channel", AuctionChannelNumber, ImGuiInputTextFlags.None)
    if newText:len() > 0 and newText ~= AuctionChannelNumber then
        AuctionChannelNumber = newText
        auctionsettings["Default"]["ChannelNumber"] = newText
        SaveSettings()
    end
    ImGui.Separator()
    pauseAuctioning, pressed = ImGui.Checkbox("Pause Auction", pauseAuctioning)
    ImGui.SetWindowFontScale(1.2)
    ImGui.PushStyleColor(ImGuiCol.Text, 255, 255, 0, 1)
    ImGui.Text("Count Down: %ds", (AuctionTimer * 60) - (os.clock() - lastAuction))
    ImGui.PopStyleColor()
    if ImGui.Button("Auction Now!") then
        forceAuction = true
    end

    ImGui.Separator()

    ImGui.PushStyleColor(ImGuiCol.Text, 0, 100, 255, 1)
    ImGui.Text("Auction Items")
    ImGui.SetWindowFontScale(1)

    ImGui.BeginTable("Items", 3, ImGuiTableFlags.Resizable + ImGuiTableFlags.Borders)
    ImGui.TableNextColumn()
    ImGui.Text("Item")
    ImGui.TableNextColumn()
    ImGui.Text("Cost")
    ImGui.TableNextColumn()
    ImGui.Text("")
    ImGui.PopStyleColor()
    if (auctionsettings) then
        if auctionsettings[CharConfig] then
            for k, v in pairs(auctionsettings[CharConfig]) do
                ImGui.TableNextColumn()
                ImGui.Text(k)
                ImGui.TableNextColumn()
                ImGui.Text(v)
                ImGui.TableNextColumn()
                ImGui.PushID(k)
                if ImGui.SmallButton("Delete") then
                    auctionsettings[CharConfig][k] = nil
                    SaveSettings(true)
                end
                ImGui.PopID()
            end
        end
    end
    ImGui.EndTable()
    ImGui.Separator()

    ImGui.Text("Drag new Items")
    if ImGui.Button("HERE", ICON_WIDTH, ICON_HEIGHT) then
        addCursorItem()
        mq.cmd("/autoinv")
    end
    ImGui.Separator()


    if ImGui.Button("Manually Add Auction Line") then
        openPopup = true
    end

    ImGui.Separator()

    if openPopup and ImGui.IsPopupOpen(newAuctionPopup) == false then
        ImGui.OpenPopup(newAuctionPopup)
        openPopup = false
    end

    RenderNewAuctionPopup()
end

function AuctionJob.GiveTime()
    if (not auctionsettings[CharConfig]) then
        curState = "No configuration for " .. CharConfig .. "..."
        return
    end

    if lastAuction == 0 then
        lastAuction = os.clock()
    end

    if pauseAuctioning then
        lastAuction = os.clock() + (os.clock() - lastAuction)
    end

    if forceAuction or os.clock() - lastAuction >= AuctionTimer * 60 then
        print("Auctioning items")
        doAuction(false)
    end
end

function AuctionJob.ShutDown()
end

return AuctionJob
