---@diagnostic disable: lowercase-global
local mq = require('mq')
local LIP = require('lib/LIP')
local utils = require('lib/ed/utils')
local BFOUtils = require('lib/bfoutils')

local ImGui = require('ImGui')
ImGuiTabBarFlags = ImGuiTabBarFlags

local wizardGates = {
    3183,
    3180,
    3181,
    3795,
    3793,
    3833,
    4963,
    5734,
    4965,
    5732,
    4964,
    5735,
    6181,
    6183,
    6182,
    6176,
    6177,
    6178,
    8236,
    8238,
    8239,
    10880,
    10881,
    10882,
    10876,
    10875,
    10877,
    10878,
    10879,
    11985,
    11984,
    15889,
    15890,
    15891,
    20541,
    20542,
    20543,


    1199,
    1264,
    1265,
    1516,
    1325,
    5824,
    1738,
    1739,
    1322,
    1336,
    1337,
    1338,
    1371,
    1372,
    1373,
    1374,
    1375,

    2023,
    2024,
    2022,
    2025,

    2026,
    2027,
    2028,
    1417,

    1418,
    2184,
    1423,
    1399,
    1425,


    36,
    541,
    542,
    543,
    544,
    545,
    546,
    547,
    548,
    561,
    562,
    563,
    564,
    565,
    566,
    567,
    568,
    602,
    603,
    604,
    605,
    606,
    666,
    674,
};

local druidGates = {
    3182,
    3184,
    24773,
    3794,
    3792,
    25903,
    4967,
    5733,
    4966,
    5731,
    25700,
    25691,
    6185,
    6184,
    25692,
    6180,
    6179,
    24774,
    24775,
    8235,
    8237,
    8965,
    8967,
    24776,
    9956,
    9957,
    9958,
    9953,
    9954,
    9955,
    9950,
    9951,
    9952,
    11982,
    11981,
    11980,
    20538,
    20539,
    20540,
    1199,
    1264,
    1265,
    1517,
    1326,
    25694,
    1322,
    1736,
    1737,
    5824,
    2020,
    2021,
    2183,
    1433,
    2029,
    2030,
    2031,
    1440,
    1438,
    1434,
    1398,
    24771,
    25689,
    25690,
    25695,
    25699,
    25899,
    25900,
    25901,
    25902,
    25904,
    25693,
    25696,
    25698,
    25906,
    36,
    530,
    531,
    532,
    533,
    534,
    535,
    536,
    537,
    538,
    550,
    551,
    552,
    553,
    554,
    555,
    556,
    557,
    558,
    607,
    608,
    609,
    610,
    611,
};

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

gateClasses["Druid"] = druidGates
gateClasses["Wizard"] = wizardGates

local travelTabs = {}
local travelTabsSorted = {}

TravelJobSettings = {}

local TravelJob = {}

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

    charName = TravelJobSettings["Default"]["Char"] or "None"

    travelTabs = {}
    travelTabsSorted = {}

    for _, v in ipairs(gateClasses[TravelJobSettings["Default"]["Class"]]) do
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
