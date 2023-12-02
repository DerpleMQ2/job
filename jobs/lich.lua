local mq = require('mq')
local LIP = require('lib/LIP')
local utils = require('lib/ed/utils')
local BFOUtils = require('lib/bfoutils')

local ImGui = require('ImGui')
Buff = Buff

local lichSpells = {
    "Dark Pact",
    "Allure of Death",
    "Call of Bones",
    "Lich",
    "Demi Lich",
    "Arch Lich",
    "Ancient: Master of Death",
    "Seduction of Saryrn",
    "Ancient: Seduction of Chaos",
    "Dark Possession",
    "Grave Pact",
    "Otherside",
    "Otherside Rk. II",
    "Otherside Rk. III",
    "Spectralside",
    "Spectralside Rk. II",
    "Spectralside Rk. III",
    "Netherside",
    "Netherside Rk. II",
    "Netherside Rk. III",
    "Darkside",
    "Darkside Rk. II",
    "Darkside Rk. III",
    "Shadowside",
    "Shadowside Rk. II",
    "Shadowside Rk. III",
    "Forsakenside",
    "Forsakenside Rk. II",
    "Forsakenside Rk. III",
    "Forgottenside",
    "Forgottenside Rk. II",
    "Forgottenside Rk. III",
    "Contraside",
    "Contraside Rk. II",
    "Contraside Rk. III",
}

local Lich = {}
local enableLich = false
local LichSpell = "None"
local curState = "Idle..."

local lich_settings_file = '/lua/config/lich.ini'
local lich_settings_path = ""
local lichsettings = {}

local SaveSettings = function()
    LIP.save(lich_settings_path, lichsettings)
end

function Lich.Setup(config_dir)
    lich_settings_path = config_dir .. lich_settings_file

    if file_exists(lich_settings_path) then
        lichsettings = LIP.load(lich_settings_path)
    else
        print("Can't find lich.ini at: " .. lich_settings_path)
        return
    end

    if not lichsettings[CharConfig] or not lichsettings[CharConfig]["LichEnabled"] then
        lichsettings[CharConfig] = lichsettings[CharConfig] or {}
        lichsettings[CharConfig]["LichEnabled"] = 0
        SaveSettings()
    end

    LichSpell = BFOUtils.GetHighestSpell(lichSpells, nil)
    enableLich = lichsettings[CharConfig]["LichEnabled"] == 1
end

local renderToggleButton = function(text)
    if ImGui.Button(text) then
        enableLich = not enableLich

        if enableLich then
            lichsettings[CharConfig]["LichEnabled"] = 1
        else
            lichsettings[CharConfig]["LichEnabled"] = 0
        end

        SaveSettings()
    end
end

local removeLich = function()
    mq.cmd("/removebuff " .. LichSpell)
    mq.delay(500)
end

function Lich.Render()
    if not lichsettings then return end

    ImGui.Text("Lich configuration..")
    ImGui.Separator()

    if ImGui.Button("Reload INI") then
        Buff.Setup()
    end

    BFOUtils.RenderCurrentState(curState)

    ImGui.Text("Lich Spell: " .. LichSpell)
    ImGui.Text("Lich Buff Slot: " .. (mq.TLO.Me.Buff(LichSpell).ID() or "N/A"))


    if enableLich then
        renderToggleButton("Disable Lich")
    else
        renderToggleButton("Enable Lich")
    end
end

function Lich.GiveTime()
    if (not lichsettings) then
        curState = "No configuration for lich."
        return
    end

    if BFOUtils.IsCasting() or not mq.TLO.Cast.Ready() or mq.TLO.Me.Moving() then
        return
    end

    if enableLich and (not mq.TLO.Me.Feigning()) and mq.TLO.Me.Buff(LichSpell).ID() == nil and mq.TLO.Me.PctHPs() >= lichsettings["Default"]["TurnOnAtPerc"] then
        BFOUtils.Cast(LichSpell, 5, nil, false)
        curState = "Casting: " .. LichSpell
    end

    if mq.TLO.Me.Buff(LichSpell).ID() ~= nil and (mq.TLO.Me.PctHPs() < lichsettings["Default"]["TurnOffAtPerc"] or not enableLich) then
        removeLich()
    end

    curState = "Idle..."
end

function Lich.ShutDown()
    removeLich()
end

return Lich
