local mq = require('mq')
local LIP = require('lib/LIP')
require('lib/ed/utils')
local BFOUtils = require('lib/bfoutils')
local ImGui = require('ImGui')

local curState = "Idle..."
local tanksTable = {}
local healthTable = {}
local groupNeedsHealCount = 0

local spellTargets = {}

local configLocked = true

local heal_settings_file = '/lua/config/heal.ini'
local heal_settings_path = ""
local healsettings = {}

local Heal = {}

local createOrUpdateTableEntry = function(p, CurChar, CurCharId)
    healthTable[p] = healthTable[p] or {}

    healthTable[p]["ID"] = CurCharId
    healthTable[p]["Name"] = CurChar

    if tonumber(mq.TLO.NetBots(CurChar).PctHPs()) then
        healthTable[p]["HP"] = tonumber(mq.TLO.NetBots(CurChar).PctHPs())
        healthTable[p]["Source"] = "NetBots"
    elseif tonumber(mq.TLO.Group.Member(CurChar).PctHPs()) then
        healthTable[p]["HP"] = tonumber(mq.TLO.Group.Member(CurChar).PctHPs())
        healthTable[p]["Source"] = "Group"
    elseif tonumber(mq.TLO.Raid.Member(CurChar).PctHPs()) then
        healthTable[p]["HP"] = tonumber(mq.TLO.Raid.Member(CurChar).PctHPs())
        healthTable[p]["Source"] = "Raid"
    else
        healthTable[p]["HP"] = tonumber(mq.TLO.Spawn(CurChar).PctHPs()) or 0
        healthTable[p]["Source"] = "Spawn"
    end
end

local healPlayer = function(p, CurChar, CurCharId)
    if CurCharId == 0 or mq.TLO.Spawn(CurCharId).Dead() or not spellTargets[p] then
        return
    end

    local TargetHPLastFrame = 0

    if CurCharId > 0 then
        -- need to index on p because if a pet owner goes away we dont know the pet name any more.
        healthTable[p] = healthTable[p] or {}

        TargetHPLastFrame = healthTable[p]["HP"] or 0

        createOrUpdateTableEntry(p, CurChar, CurCharId)
    else
        healthTable[p] = nil
        return
    end

    if BFOUtils.IsCasting() or not mq.TLO.Cast.Ready() or mq.TLO.Me.Moving() then
        return
    end

    curState = "Idle..."

    -- not really dps more like dpframe but its close enough
    local pdps = (healthTable[p]["HP"] or 0) - TargetHPLastFrame
    healthTable[p]["PDPS"] = pdps

    local normalHealPDPS = healsettings[CharConfig]["NormalHealPDPS"] or 80
    local quickHealPDPS = healsettings[CharConfig]["QuickHealPDPS"] or 180

    if BFOUtils.CanCast(healsettings[CharConfig]["BigHeal"]) then
        if healthTable[p]["HP"] <= (healsettings[CharConfig]["BigHealPoint"] or 0) then
            curState = "Big Healing: " .. CurChar
            BFOUtils.Cast(healsettings[CharConfig]["BigHeal"], 5, CurCharId, false)
            return
        end
    end

    if BFOUtils.CanCast(healsettings[CharConfig]["NormalHeal"]) then
        if healthTable[p]["HP"] <= (healsettings[CharConfig]["NormalHealPoint"] or 0) and pdps <= normalHealPDPS then
            curState = "Normal Healing: " .. CurChar
            BFOUtils.Cast(healsettings[CharConfig]["NormalHeal"], 5, CurCharId, false)
            return
        end
    end

    if BFOUtils.CanCast(healsettings[CharConfig]["QuickHeal"]) then
        if healthTable[p]["HP"] <= (healsettings[CharConfig]["QuickHealPoint"] or 0) and pdps <= quickHealPDPS then
            curState = "Quick Healing: " .. CurChar
            BFOUtils.Cast(healsettings[CharConfig]["QuickHeal"], 5, CurCharId, false)
            return
        end
    end
end

local healTanks = function()
    if #tanksTable == 0 then return end
    for i, p in ipairs(tanksTable) do
        if spellTargets[p] then
            local CurChar = p or "None"
            local CurCharId = mq.TLO.Spawn("=" .. CurChar).ID() or -1

            if CurChar == "Self" then
                CurChar = mq.TLO.Me.Name() or "None"
                CurCharId = mq.TLO.Me.ID() or -1
            end

            if string.find(CurChar, "_pet") ~= nil then
                local PetOwner = string.gsub(CurChar, "_pet", "")
                if mq.TLO.Spawn("=" .. PetOwner).ID() > 0 then
                    CurCharId = mq.TLO.Spawn("=" .. PetOwner).Pet.ID() or -1
                    CurChar = mq.TLO.Spawn("=" .. PetOwner).Pet.Name() or "None"
                else
                    CurCharId = 0
                end
            end

            healPlayer(p, CurChar, CurCharId)
        end
    end
end

local healGroup = function()
    if not healsettings[CharConfig]["GroupCountThreshold"] or not healsettings[CharConfig]["GroupHeal"] then
        return
    end

    if not BFOUtils.CanCast(healsettings[CharConfig]["GroupHeal"]) then return end

    local groupMemberCount = mq.TLO.Group.Members()
    local i = 0
    groupNeedsHealCount = 0

    for i = 1, groupMemberCount do
        local member = mq.TLO.Group.Member(i)

        if (member.ID() or 0) > 0 and (not member.Dead()) and (member.PctHPs() or 0) <= (healsettings[CharConfig]["GroupHealPoint"] or 0) then
            groupNeedsHealCount = groupNeedsHealCount + 1
        end

        if groupNeedsHealCount >= healsettings[CharConfig]["GroupCountThreshold"] then
            BFOUtils.Cast(healsettings[CharConfig]["GroupHeal"], 5, 0, true)
        end
    end
end

local SaveSettings = function()
    LIP.save(heal_settings_path, healsettings)
end

function Heal.Setup(config_dir)
    heal_settings_path = config_dir .. heal_settings_file

    if file_exists(heal_settings_path) then
        healsettings = LIP.load(heal_settings_path)
    else
        print("Can't find heal.ini at: " .. heal_settings_path)
        return
    end

    if not healsettings[CharConfig] then return end

    tanksTable = {}

    if healsettings[CharConfig]["Tank"] and healsettings[CharConfig]["Tank"]:len() > 0 then
        tanksTable = BFOUtils.Tokenize(healsettings[CharConfig]["Tank"], "|")
    end

    healthTable = {}
    spellTargets = {}

    healsettings[CharConfigTarget] = healsettings[CharConfigTarget] or {}

    for i, p in ipairs(tanksTable) do
        local CurChar = p or "None"
        local CurCharId = mq.TLO.Spawn("=" .. CurChar).ID() or -1

        healsettings[CharConfigTarget][p] = healsettings[CharConfigTarget][p] or "1"

        spellTargets[CurChar] = healsettings[CharConfigTarget][CurChar] ~= 0

        if CurChar == "Self" then
            CurChar = mq.TLO.Me.Name() or "None"
            CurCharId = mq.TLO.Me.ID() or -1
        end

        if string.find(CurChar, "_pet") ~= nil then
            local PetOwner = string.gsub(CurChar, "_pet", "")
            if mq.TLO.Spawn("=" .. PetOwner).ID() > 0 then
                CurCharId = mq.TLO.Spawn("=" .. PetOwner).Pet.ID() or -1
                CurChar = mq.TLO.Spawn("=" .. PetOwner).Pet.Name() or "None"
            else
                CurCharId = 0
            end
        end

        createOrUpdateTableEntry(p, CurChar, CurCharId)
    end

    SaveSettings()
end

local renderPlayerBar = function(p)
    if not healthTable[p] then return end

    local charName    = healthTable[p]["Name"] or "xxxNone"
    local charId      = healthTable[p]["ID"]
    local pctHPs      = healthTable[p]["HP"] or 0
    local pdps        = healthTable[p]["PDPS"] or 0
    local source      = healthTable[p]["Source"] or "Unknown"
    local target      = mq.TLO.Spawn("=" .. charName)

    local ratioHPs    = pctHPs / 100

    local targetName  = charName
    local targetClass = "None"
    local targetDist  = 0
    if not targetName then
        targetName = 'No Target'
    else
        targetClass = target.Class() or "None"
        targetDist = target.Distance() or 0
    end

    ImGui.BeginTable("HPs", 3, ImGuiTableFlags.SizingStretchProp)
    ImGui.TableNextColumn()
    ImGui.PushStyleColor(ImGuiCol.PlotHistogram, 1 - ratioHPs, ratioHPs, 0, 1)
    ImGui.PushStyleColor(ImGuiCol.Text, 0.33, 0.33, 0.33, 1)
    local labelText = '[ID: ' ..
        charId ..
        " - PDPS: " .. pdps ..
        ' - Dist: ' .. math.floor(targetDist) .. ' - DS: ' .. source .. ']: ' .. targetName .. ' ' .. pctHPs .. '%'
    ImGui.ProgressBar(ratioHPs, -1, 25, labelText)
    ImGui.PopStyleColor(2)
    ImGui.TableNextColumn()
    local targetCheck, target_checked = ImGui.Checkbox("", spellTargets[p])
    if target_checked then
        local check = "1"
        if targetCheck == false then check = "0" end
        healsettings[CharConfigTarget] = healsettings[CharConfigTarget] or {}
        healsettings[CharConfigTarget][p] = check
        SaveSettings()
        Heal.Setup()
    end
    ImGui.TableNextColumn()
    if ImGui.Button("+XT", 45, 25) then
        mq.cmd("/multiline ; /target " .. charName .. "; /timed 10 /xtarget add")
    end
    ImGui.EndTable()
end

function Heal.Render()
    if not healsettings then return end

    ImGui.BeginTable("Header", 2, ImGuiTableFlags.SizingStretchProp)
    ImGui.TableNextColumn()
    ImGui.Text("Heal configuration..")
    ImGui.TableNextColumn()
    configLocked, _ = ImGui.Checkbox("Locked", configLocked)
    ImGui.EndTable()

    ImGui.Separator()

    if ImGui.Button("Reload INI") then
        Heal.Setup()
    end

    if not healsettings[CharConfig] then
        ImGui.Text(CharConfig .. " is not configured in heal.ini!")
        return
    end

    BFOUtils.RenderCurrentState(curState)

    ImGui.Text("Group Needs Heal Count: " .. groupNeedsHealCount)

    local curTanks = tostring(healsettings[CharConfig]["Tank"]) or "None"
    local flags = ImGuiInputTextFlags.CharsNoBlank + ImGuiInputTextFlags.EnterReturnsTrue
    if configLocked then flags = flags + ImGuiInputTextFlags.ReadOnly end
    local newText, _ = ImGui.InputText("Tanks", curTanks, flags)
    if selected and newText ~= curTanks then
        healsettings[CharConfig]["Tank"] = newText
        SaveSettings()
        Heal.Setup()
    end

    for p, t in pairs(healthTable) do
        renderPlayerBar(p)
    end
    if ImGui.CollapsingHeader("Full INI") then
        for k, v in pairs(healsettings[CharConfig]) do
            ImGui.Text(k .. " = " .. v)
        end
    end
end

function Heal.GiveTime()
    if (not healsettings or not healsettings[CharConfig]) then
        curState = "No Buffs Configured for " .. CharConfig .. "..."
        return
    end

    healTanks()
    healGroup()
end

function Heal.ShutDown()
end

return Heal
