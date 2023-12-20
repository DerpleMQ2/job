---@diagnostic disable: lowercase-global
local mq = require('mq')
local LIP = require('lib/LIP')
require('lib/ed/utils')
require('lib/bfoutils')

local ImGui = require('ImGui')
ImGuiTabBarFlags = ImGuiTabBarFlags

local travelColors = {}
travelColors["Group v2"] = {}
travelColors["Group v1"] = {}
travelColors["Self"] = {}
travelColors["Single"] = {}

-- evac
travelColors["Group v2"]["r"] = 220
travelColors["Group v2"]["g"] = 0
travelColors["Group v2"]["b"] = 0

-- group port
travelColors["Group v1"]["r"] = 141
travelColors["Group v1"]["g"] = 0
travelColors["Group v1"]["b"] = 250

-- self gate
travelColors["Self"]["r"] = 200
travelColors["Self"]["g"] = 240
travelColors["Self"]["b"] = 0

-- translocation
travelColors["Single"]["r"] = 180
travelColors["Single"]["g"] = 0
travelColors["Single"]["b"] = 180

local gateClasses = {}

local configLocked = true
local classIndex = 0
local classNames = { "Druid", "Wizard" }
local className = "Druid"
local charName = ""

local gateClasses = {}

local travelTabs = {}
local travelTabsSorted = {}

TravelJobSettings = {}

local TravelJob = {}

local bfo_travel_pickle_path = mq.configDir .. '/bfo/' .. 'bfo_travel.lua'

local TravelJob_settings_file = '/lua/config/travel.ini'
local TravelJob_settings_path = nil

function TravelJob.Setup(config_dir)
    if not TravelJob_settings_path and config_dir then
        TravelJob_settings_path = config_dir .. TravelJob_settings_file
    end

    if file_exists(TravelJob_settings_path) then
        TravelJobSettings = LIP.load(TravelJob_settings_path)
    else
        print("Can't find TravelJob.ini at: " .. TravelJob_settings_path)
        return
    end

    TravelJobSettings["Default"] = TravelJobSettings["Default"] or {}

    if not TravelJobSettings["Default"]["Class"] then
        TravelJobSettings["Default"]["Class"] = "Wizard"
    end

    className = TravelJobSettings["Default"]["Class"]
    for i, v in ipairs(classNames) do
        if v == className then
            classIndex = i
        end
    end

    local config, _ = loadfile(bfo_travel_pickle_path)
    local travelConfig = {}
    if config then travelConfig = config() end

    gateClasses["Druid"] = travelConfig.Druid
    gateClasses["Wizard"] = travelConfig.Wizard

    charName = TravelJobSettings["Default"]["Char"] or "None"

    travelTabs = {}
    travelTabsSorted = {}

    for v, _ in pairs(gateClasses[TravelJobSettings["Default"]["Class"]]) do
        local subCat = mq.TLO.Spell(v).Subcategory()

        if subCat ~= "Unknown" or TravelJobSettings["Default"]["WMCast"] == 1 then
            travelTabs[subCat] = travelTabs[subCat] or {}
            table.insert(travelTabs[subCat], mq.TLO.Spell(v).Name())
        end
    end

    for k in pairs(travelTabs) do table.insert(travelTabsSorted, k) end
    table.sort(travelTabsSorted)

    for k, v in pairs(travelColors) do
        for kc, kv in pairs(v) do
            if TravelJobSettings[k] and TravelJobSettings[k][kc] then
                travelColors[k][kc] = TravelJobSettings[k][kc]
            end
        end
    end
end

---@param doBroadcast boolean
local SaveSettings = function(doBroadcast)
    LIP.save(TravelJob_settings_path, TravelJobSettings)

    if doBroadcast then
        JobActors.send({ from = CharConfig, script = "Job", module = "JobTravel", event = "SaveSettings" })
    end
end

function TravelJob.UpdateWMCast(wmCast)
    TravelJobSettings["Default"] = TravelJobSettings["Default"] or {}
    TravelJobSettings["Default"]["WMCast"] = 0

    if wmCast then
        TravelJobSettings["Default"]["WMCast"] = 1
    end

    SaveSettings(true)
    TravelJob.Setup()
end

local renderTabs = function()
    if not TravelJobSettings then return end
    if ImGui.BeginTabBar("Tabs", ImGuiTabBarFlags.FittingPolicyScroll) then
        for _, k in ipairs(travelTabsSorted) do
            local v = travelTabs[k]
            ImGui.TableNextColumn()
            if ImGui.BeginTabItem(k) then
                ImGui.BeginTable("Buttons", 3)
                for si, sv in ipairs(v) do
                    if (si - 1) % 3 == 0 or si == 1 then
                        ImGui.TableNextRow()
                    end
                    ImGui.TableNextColumn()
                    local spellType = mq.TLO.Spell(sv).TargetType() or "Single"
                    ImGui.PushStyleColor(ImGuiCol.Text, 0, 0, 0, 1)
                    ImGui.PushStyleColor(ImGuiCol.Button, travelColors[spellType]["r"] / 255,
                        travelColors[spellType]["g"] / 255, travelColors[spellType]["b"] / 255, 1.0)
                    if ImGui.Button(sv, 150, 25) then
                        if TravelJobSettings["Default"]["WMCast"] ~= 1 then
                            if spellType == "Single" then
                                mq.cmd("/bct " ..
                                    charName .. " //casting \"" ..
                                    sv .. "\" -maxtries|10 -targetid|" .. (mq.TLO.Target.ID() or 0))
                            else
                                mq.cmd("/bct " .. charName .. " //casting \"" .. sv .. "\" -maxtries|10")
                            end
                        else
                            if spellType == "Single" then
                                mq.cmd("/wm cast " .. mq.TLO.Spell(sv).ID() .. " " .. (mq.TLO.Target.ID() or 0))
                            else
                                mq.cmd("/wm cast " .. mq.TLO.Spell(sv).ID())
                            end
                        end
                    end
                    ImGui.PopStyleColor(2)
                end
                ImGui.EndTable()
                ImGui.EndTabItem()
            end
        end

        ImGui.EndTabBar();
    end
end

function TravelJob.Render()
    if not TravelJobSettings then return end
    local pressed

    ImGui.BeginTable("Header", 2, ImGuiTableFlags.SizingStretchProp)
    ImGui.TableNextColumn()
    ImGui.Text("Travel Panel")
    ImGui.TableNextColumn()
    configLocked, _ = ImGui.Checkbox("Locked", configLocked)
    ImGui.EndTable()
    ImGui.Separator()

    if ImGui.Button("Reload INI") then
        TravelJob.Setup()
    end

    ImGui.BeginTable("CharInfo", 2, ImGuiTableFlags.SizingStretchProp)
    ImGui.TableNextColumn()
    classIndex, pressed = ImGui.Combo("Class", classIndex, classNames, #classNames)
    if pressed then
        local className = classNames[classIndex]
        TravelJobSettings["Default"] = TravelJobSettings["Default"] or {}
        TravelJobSettings["Default"]["Class"] = className
        SaveSettings(true)
        TravelJob.Setup()
    end

    ImGui.TableNextColumn()
    local flags = ImGuiInputTextFlags.CharsNoBlank
    if configLocked then flags = bit32.bor(flags, ImGuiInputTextFlags.CharsNoBlank, ImGuiInputTextFlags.ReadOnly) end
    local newText, _ = ImGui.InputText("Char Name", charName, flags)
    if newText ~= charName then
        charName = newText
        TravelJobSettings["Default"]["Char"] = newText
        SaveSettings(true)
    end
    ImGui.EndTable()

    renderTabs()
end

function TravelJob.GiveTime()
    if (not TravelJobSettings["Default"]) then
        curState = "No configuration for " .. CharConfig .. "..."
        return
    end
end

function TravelJob.ShutDown()
end

return TravelJob
