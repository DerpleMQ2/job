local mq = require('mq')
local LIP = require('lib/LIP')
local utils = require('lib/ed/utils')
local BFOUtils = require('lib/bfoutils')

local ImGui = require('ImGui')

local Bard = {}
local InstrumentSlot = 14
local SongType = "None"

local validateItem = function(item, instType)
    instType = instType or ""
    local instFocus = item.Focus2() or ""
    instFocus = BFOUtils.Tokenize(instFocus, " ")[1] or "None"

    --print( (item.Name() or "None") .. " : " ..instFocus .. " == ".. instType)
    if item.Type.Find(instType)() ~= nil or string.find(instType, instFocus) ~= nil then
        mq.cmd("/exchange \"" .. item.Name() .. "\" offhand")
        return true
    end

    return false
end

local findBestInPack = function(packSlot, instType)
    for i = 1, BFOUtils.GetItem(packSlot).Container() do
        if validateItem(BFOUtils.GetItemInContainer(packSlot, i), instType) then
            return
        end
    end
end

local findBestInstrument = function(instType)
    for i = 1, 8 do
        if BFOUtils.GetItem(InstrumentSlot).Type.Find(instType)() ~= nil then return end

        if BFOUtils.GetItem(i).Container() then
            findBestInPack(i, instType)
        else
            if validateItem(BFOUtils.GetItem(i), instType) then
                return
            end
        end
    end
end

function Bard.Setup(config_dir)
end

function Bard.Render()
    ImGui.Text("Bard configuration..")
    ImGui.Separator()

    ImGui.Text("Current Song Type: " .. SongType)
    ImGui.Text("Current Instrument: " .. (mq.TLO.Me.Inventory(InstrumentSlot).Name() or "None"))
    ImGui.Text("Current Instrument Type: " .. (mq.TLO.Me.Inventory(InstrumentSlot).Type() or "None"))
    ImGui.Text("Currently Casting: " .. (mq.TLO.Cast.Effect() or "N/A"))
end

function Bard.GiveTime()
    if mq.TLO.Me.Class() ~= "Bard" then return end

    if mq.TLO.Cast.Effect.ID() == nil or mq.TLO.Cast.Effect.ID() <= 0 then return end

    SongType = mq.TLO.Me.Book(mq.TLO.Me.Book(mq.TLO.Cast.Effect())()).Skill()

    SongType = BFOUtils.Tokenize(SongType, " ")[1] or ""

    if SongType == "" then return end

    --print(mq.TLO.Me.Inventory(InstrumentSlot).Type())

    if mq.TLO.Me.Inventory(InstrumentSlot).Type.Find(SongType)() ~= nil then
        --print ("We are good with what we have")
    else
        --print("Need a new item for "..SongType)
        findBestInstrument(SongType)
    end
end

function Bard.ShutDown()
end

return Bard
