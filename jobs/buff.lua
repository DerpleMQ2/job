---@diagnostic disable: deprecated
local mq = require('mq')
local LIP = require('lib/LIP')
require('lib/ed/utils')
local BFOUtils = require('lib/bfoutils')
local actors = require 'actors'

local ImGui = require('ImGui')

local curState = "Idle..."
local sortedSpellKeys = {}
local lastFullBuff = 0
local currentMelodySet = ""
local bardModeIndex = 0

local requiredBuffs = {}
local spellTargets = {}

local newSpellPopup = "new_spell_popup"

local buffSpellSlot = "5"
local buffSpellIndex = 4

local canni = true

local buffInCombat = true

local configLocked = true

local SpellSlots = {
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
}

local CanniSpells = {
    "Cannibalize",
    "Cannibalize II",
    "Cannibalize III",
    "Cannibalize IV",
    "Cannibalize V",
}

---@type string
local buff_settings_file = '/lua/config/buff.ini'
---@type string
local buff_settings_path = ""
local buffsettings = {}

local Buff = {}

local requestRebuff = function()
    curState = "Rebuff Requested..."
    print(curState)
    lastFullBuff = (os.clock() - buffsettings["Default"]["FullRebuffCheckTimer"])
end

mq.event('Rebuff', "#*#tells you, 'rebuff'#*#", requestRebuff)

---@param doBroadcast boolean
local SaveSettings = function(doBroadcast)
    LIP.save(buff_settings_path, buffsettings)

    if doBroadcast then
        actors.send({ from = CharConfig, module = "JobBuff", event = "SaveSettings" })
    end
end

local doCanni = function()
    if BFOUtils.IsCasting() or canni == false then return end

    if mq.TLO.Me.Class.Name() ~= "Shaman" then return end

    local curTargetId = mq.TLO.Target.ID()
    local curTargetDist = mq.TLO.Target.Distance()
    local shouldCanni = ((mq.TLO.Me.PctHPs() > 80 and mq.TLO.Me.PctMana() < 85) or (mq.TLO.Me.PctHPs() > 99 and mq.TLO.Me.PctMana() < 95))

    if ((not BFOUtils.IsInCombat()) or curTargetId == 0 or curTargetId == mq.TLO.Me.ID() or curTargetId == mq.TLO.Me.Pet.ID() or curTargetDist > 40) and shouldCanni then
        local canniSpell = BFOUtils.GetHighestSpell(CanniSpells, nil)
        BFOUtils.Cast(canniSpell, 8, 0, true)
        curState = "Canni..."

        while not mq.TLO.Me.Sitting() and not mq.TLO.Me.Moving() do
            mq.cmd("/if (!${Me.Sitting} && !${Me.Moving}) /sit")
            mq.delay(10)
        end
    end
end

local doMelody = function()
    if mq.TLO.Me.Class.Name() ~= "Bard" then
        return
    end

    curState = "Idle..."

    local MelodyTune = buffsettings[CharConfig]["BardMode"]

    if MelodyTune == "Silent" and currentMelodySet ~= MelodyTune then
        --print(currentMelodySet .." ".. MelodyTune)
        currentMelodySet = MelodyTune
        mq.cmd("/stopcast")
        mq.cmd("/stopsong")
    else
        --print(mq.TLO.Cast.Effect.ID())
        ---@diagnostic disable-next-line: undefined-field
        if mq.TLO.Cast.Effect.ID() and mq.TLO.Cast.Effect.ID() > 0 then
            ---@diagnostic disable-next-line: undefined-field
            if mq.TLO.Cast.Status() == "I" then
                curState = "Melody is Stuck.  Resetting..."
                mq.cmd("/stopcast")
            else
                if MelodyTune == "" then
                    currentMelodySet = MelodyTune
                    mq.cmd("/melody")
                    return
                end

                if currentMelodySet == MelodyTune then
                    return
                end
            end
        end

        if MelodyTune == "" then
            currentMelodySet = MelodyTune
            return
        end

        if MelodyTune and MelodyTune:len() > 0 and buffsettings[CharConfig][MelodyTune] then
            --print( MelodyTune .. "=="..currentMelodySet)
            currentMelodySet = MelodyTune
            curState = "Starting Melody Set: " .. currentMelodySet
            mq.cmd("/melody " .. buffsettings[CharConfig][currentMelodySet])
        end
    end
end

local doAltAct = function()
    if (not buffsettings) or (not buffsettings["AltAct"]) or (not buffsettings["AltAct"][CharConfig]) then
        return
    end

    local AltAct = buffsettings["AltAct"][CharConfig]

    local tokens = BFOUtils.Tokenize(AltAct, "|")

    local AltId = tokens[1]
    local AltSpell = tokens[2]
    local ClickOff = tokens[3]

    if mq.TLO.Me.Buff(AltSpell).ID() > 0 then
        mq.cmd("/removebuff " .. ClickOff)
    else
        mq.cmd("/alt act " .. AltId)
        mq.delay(1000)
    end
end

local fullRebuffCheck = function()
    -- build a table of required buffs.
    requiredBuffs = {}

    local validCharList = {}

    -- build a map of valid characters to spells to minimize targeting.
    for i, s in ipairs(sortedSpellKeys) do
        if buffsettings[CharConfig][s] == nil then return end

        local charList = BFOUtils.Tokenize(buffsettings[CharConfig][s], "|")

        for pi, pl in ipairs(charList) do
            if spellTargets[pl] then
                local CurChar = pl or "None"
                local CurCharId = mq.TLO.Spawn("=" .. CurChar).ID() or 0

                if CurChar == "Self" then
                    CurChar = mq.TLO.Me.Name()
                    CurCharId = mq.TLO.Me.ID()
                end

                if string.find(CurChar, "_pet") ~= nil then
                    local PetOwner = string.gsub(CurChar, "_pet", "")
                    CurCharId = mq.TLO.Spawn("=" .. PetOwner).Pet.ID() or 0
                    CurChar = mq.TLO.Spawn("=" .. PetOwner).Pet.Name() or "None"
                end

                if CurCharId > 0 then
                    --print(s..":"..pi.." : "..pl .. " " .. CurChar.." ("..CurCharId..")")
                    validCharList[CurChar] = validCharList[CurChar] or {}
                    validCharList[CurChar]["ID"] = CurCharId
                    validCharList[CurChar]["Spells"] = validCharList[CurChar]["Spells"] or {}
                    table.insert(validCharList[CurChar]["Spells"], s)
                end
            else
                --print("skipping invalid target "..pl)
            end
        end
    end

    for k, v in pairs(validCharList) do
        --print(k.." : "..v["ID"])
        ---@type character|pet|target|fun():string|nil
        local buffTarget = mq.TLO.Me
        if tonumber(v["ID"]) == tonumber(mq.TLO.Pet.ID()) then
            buffTarget = mq.TLO.Pet
        elseif tonumber(v["ID"]) ~= tonumber(mq.TLO.Me.ID()) then
            mq.cmd("/target id " .. v["ID"])
            mq.delay(900)
            buffTarget = mq.TLO.Target
        end

        for i, s in ipairs(v["Spells"]) do
            -- make sure the spell is valid.
            print(buffTarget.Name() ..
                ": " ..
                (mq.TLO.Spell(s).ID() or 0) ..
                " " ..
                s ..
                " -- " ..
                (mq.TLO.Spell(s)() or "unknown") .. " -> " .. (BFOUtils.GetBuffByName(buffTarget, s) or "missing"))
            if mq.TLO.Spell(s)() ~= nil then
                local buffDuration = BFOUtils.GetBuffDuration(BFOUtils.GetBuffByName(buffTarget, s))
                local needRebuff = (not BFOUtils.HasBuffByName(buffTarget, s) or (buffDuration > 0 and buffDuration <= 10))
                local checkPass = true
                local spellRange = mq.TLO.Spell(s).Range() or 0
                local targetDistance = buffTarget.Distance() or 9999

                if buffsettings[s] then
                    local ifCheck = buffsettings[s]["LuaIf"] or nil
                    if ifCheck ~= nil then
                        local luaCode = "local mq = require('mq') if " ..
                            ifCheck .. " then return true else return false end"
                        checkPass = loadstring(luaCode)()
                    end
                end

                if needRebuff and (spellRange <= 0 or targetDistance < spellRange) then
                    --print(buffTarget.Name().." needs "..s)
                    --print(v["ID"] .. " " .. buffTarget.ID())
                    requiredBuffs[s] = requiredBuffs[s] or {}
                    table.insert(requiredBuffs[s], v["ID"])
                end
            else
                if buffsettings["SpellItemMap"] and buffsettings["SpellItemMap"][s] then
                    local buff = buffsettings["SpellItemMap"][s]
                    local buffDuration = BFOUtils.GetBuffDuration(buffTarget.Buff(buff))
                    local needRebuff = (buffTarget.Buff(buff).ID() == nil or (buffDuration > 0 and buffDuration <= 10))
                    local checkPass = true

                    if buffsettings[buff] then
                        local ifCheck = buffsettings[buff]["LuaIf"] or nil
                        if ifCheck ~= nil then
                            local luaCode = "local mq = require('mq') if " ..
                                ifCheck .. " then return true else return false end"
                            checkPass = loadstring(luaCode)()
                        end
                    end

                    if needRebuff then
                        requiredBuffs[s] = requiredBuffs[s] or {}
                        table.insert(requiredBuffs[s], v["ID"])
                    end
                end
            end
        end
    end
end

local popupSpellName

local RenderNewSpellPopup = function()
    if ImGui.BeginPopup(newSpellPopup) then
        ImGui.Text("New Spell:")
        local tmp_spell, selected_spell = ImGui.InputText("##edit", '', 0)
        if selected_spell then popupSpellName = tmp_spell end

        if ImGui.Button("Save") then
            --printf("%s", popupSpellName)
            if popupSpellName ~= nil and popupSpellName:len() > 0 then
                buffsettings[CharConfig] = buffsettings[CharConfig] or {}
                buffsettings[CharConfig][popupSpellName] = "|"
                SaveSettings(true)
                Buff.Setup()
            else
                print("\arError Saving Spell: Spell Name cannot be empty.\ax")
            end
            ImGui.CloseCurrentPopup()
        end

        ImGui.SameLine()

        if ImGui.Button("Cancel") then
            ImGui.CloseCurrentPopup()
        end
        ImGui.EndPopup()
    end
end

function Buff.Setup(config_dir)
    --print("Buff.Setup() Called")
    buff_settings_file = '/lua/config/buff.ini'
    ---@diagnostic disable-next-line: undefined-field
    if buff_settings_path:len() == 0 then
        buff_settings_path = config_dir .. buff_settings_file
    end

    if file_exists(buff_settings_path) then
        buffsettings = LIP.load(buff_settings_path)
    else
        print("Can't find buff.ini at: " .. buff_settings_path)
        return
    end

    sortedSpellKeys = {}
    spellTargets = {}

    local selectedBardMode = "Silent"

    if (buffsettings) then
        if buffsettings[CharConfig] then
            for k, v in pairs(buffsettings[CharConfig]) do
                if k ~= "BardMode" and k ~= "BuffInCombat" and k ~= "FullRebuffCheckTimer" then
                    table.insert(sortedSpellKeys, k)

                    local targets = BFOUtils.Tokenize(v, "|")
                    for ti, tv in ipairs(targets) do
                        --print(tv)
                        buffsettings[CharConfigTarget] = buffsettings[CharConfigTarget] or {}

                        spellTargets[tv] = buffsettings[CharConfigTarget][tv] ~= 0
                    end
                else
                    selectedBardMode = v
                end
            end
        end
    end

    table.sort(spellTargets)

    table.sort(sortedSpellKeys)

    for i, v in ipairs(sortedSpellKeys) do
        if v == selectedBardMode then
            bardModeIndex = i
        end
    end

    buffsettings[CharConfig] = buffsettings[CharConfig] or {}
    buffsettings["Default"] = buffsettings["Default"] or {}
    buffsettings["Default"]["FullRebuffCheckTimer"] = buffsettings[CharConfig]["FullRebuffCheckTimer"] or 600

    buffSpellSlot = tostring((buffsettings["Default"]["SpellSlot"] or 5))
    for i, v in ipairs(SpellSlots) do
        if v == buffSpellSlot then
            buffSpellIndex = i
        end
    end

    if buffsettings[CharConfig]["Canni"] ~= nil then
        canni = buffsettings[CharConfig]["Canni"]
    end

    buffInCombat = buffsettings[CharConfig]["BuffInCombat"] or buffsettings["Default"]["BuffInCombat"] or true

    SaveSettings(false)
end

local renderBardUI = function()
    if mq.TLO.Me.Class.Name() ~= "Bard" then return end

    local bardModes = { "Silent" }
    for _, v in ipairs(sortedSpellKeys) do
        table.insert(bardModes, v)
    end

    local bardModeClicked

    bardModeIndex, bardModeClicked = ImGui.Combo("Melody Set", bardModeIndex, bardModes, #bardModes)
    if bardModeClicked then
        buffsettings[CharConfig]["BardMode"] = bardModes[bardModeIndex]
        SaveSettings(true)
    end
end

function Buff.Render()
    if not buffsettings then return end

    local openPopup = false
    local pressed

    ImGui.BeginTable("Header", 2, ImGuiTableFlags.SizingStretchProp)
    ImGui.TableNextColumn()
    ImGui.Text("Buff configuration..")
    ImGui.TableNextColumn()
    configLocked, _ = ImGui.Checkbox("Locked", configLocked)
    ImGui.EndTable()

    canni, pressed = ImGui.Checkbox("Canni", canni)
    if pressed then
        buffsettings[CharConfig]["Canni"] = tostring(canni)
        SaveSettings(true)
    end
    ImGui.SameLine()
    buffInCombat, pressed = ImGui.Checkbox("Buff In Combat", buffInCombat)
    if pressed then
        buffsettings[CharConfig]["BuffInCombat"] = tostring(buffInCombat)
        SaveSettings(true)
    end

    ImGui.Separator()

    ImGui.BeginTable("Buttons", 4)
    ImGui.TableNextColumn()
    if ImGui.Button("Reload INI") then
        Buff.Setup()
    end

    ImGui.TableNextColumn()
    if ImGui.Button("Rebuff Now") then
        requestRebuff()
    end

    ImGui.TableNextColumn()
    if ImGui.Button("Add Spell") then
        openPopup = true
    end

    ImGui.TableNextColumn()
    buffSpellIndex, pressed = ImGui.Combo("Slot", buffSpellIndex, SpellSlots, 8)
    if pressed then
        buffSpellSlot = SpellSlots[buffSpellIndex]
        buffsettings["Default"]["SpellSlot"] = buffSpellSlot
        SaveSettings(true)
    end
    ImGui.EndTable()

    ImGui.Text("Rebuff Check Timer: " .. FormatTime(buffsettings["Default"]["FullRebuffCheckTimer"]))
    ImGui.Text("Next Rebuff Check : " ..
        FormatTime(math.floor(tonumber(buffsettings["Default"]["FullRebuffCheckTimer"]) - (os.clock() - lastFullBuff))))

    ImGui.Text("Buff Count: " .. #sortedSpellKeys)

    BFOUtils.RenderCurrentState(curState)

    if next(requiredBuffs) ~= nil then
        ImGui.Separator()
        ImGui.Text("Queued Buffs")

        for s, v in pairs(requiredBuffs) do
            ImGui.PushStyleColor(ImGuiCol.Text, 0.93, 0.13, 0.13, 1.0)
            ImGui.Text(s)
            ImGui.PopStyleColor(1)
            ImGui.PushStyleColor(ImGuiCol.Text, 0.63, 0.13, 0.63, 1.0)
            ImGui.BeginTable("NeedBuff", 8)
            for i, p in ipairs(v) do
                ImGui.TableNextColumn()
                ImGui.Text(mq.TLO.Spawn(p).Name())
            end
            ImGui.EndTable()
            ImGui.PopStyleColor(1)
        end
        ImGui.Separator()
    end

    renderBardUI()

    if ImGui.CollapsingHeader("Spell Config") then
        if buffsettings[CharConfig] then
            local newText = ""
            for k, v in ipairs(sortedSpellKeys) do
                local curSpell = tostring(buffsettings[CharConfig][v])
                local flags = ImGuiInputTextFlags.None
                if configLocked then flags = flags + ImGuiInputTextFlags.ReadOnly end
                newText, _ = ImGui.InputText(v, curSpell, flags)
                if newText ~= curSpell then
                    buffsettings[CharConfig][v] = newText
                    SaveSettings(true)
                    Buff.Setup()
                    --printf("a '%s' ~= '%s'", newText, curSpell)
                end
            end
        end
    end

    if ImGui.CollapsingHeader("Target Config") then
        for k, _ in pairs(spellTargets) do
            local targetCheck, target_checked = ImGui.Checkbox(k, spellTargets[k])
            if target_checked then
                local check = "1"
                if targetCheck == false then check = "0" end
                buffsettings[CharConfigTarget] = buffsettings[CharConfigTarget] or {}
                buffsettings[CharConfigTarget][k] = check
                SaveSettings(true)
                Buff.Setup()
            end
        end
    end

    if openPopup and ImGui.IsPopupOpen(newSpellPopup) == false then
        ImGui.OpenPopup(newSpellPopup)
        openPopup = false
    end

    RenderNewSpellPopup()
end

function Buff.GiveTime()
    if (not buffsettings or not buffsettings[CharConfig]) then
        curState = "No Buffs Configured for " .. CharConfig .. "..."
        return
    end

    if (not buffsettings or not buffsettings["Default"]) then
        curState = "No Defaults Configured for " .. CharConfig .. "..."
        return
    end

    doMelody()

    ---@diagnostic disable-next-line: undefined-field
    if BFOUtils.IsCasting() or not mq.TLO.Cast.Ready() or mq.TLO.Me.Moving() then
        return
    end

    doAltAct()

    local lastFullBuffDelta = os.clock() - lastFullBuff

    if (lastFullBuffDelta > tonumber(buffsettings["Default"]["FullRebuffCheckTimer"])) or lastFullBuff == 0 then
        lastFullBuff = os.clock()
        --print(lastFullBuff)
        fullRebuffCheck()
    end

    if not buffsettings[CharConfig]["BuffInCombat"] and mq.TLO.Me.CombatState() == "COMBAT" then
        return
    end

    local MGBSpell = buffsettings[CharConfig]["MGB"]

    if MGBSpell and MGBSpell ~= "None" and mq.TLO.Me.AltAbilityReady("Mass Group Buff")() then
        curState = "Casting Mass Group Buff: " .. MGBSpell
        mq.cmd("/alt act " .. mq.TLO.AltAbility("Mass Group Buff").ID())
        mq.cmd("/casting \"" .. MGBSpell .. "\" -maxtries|15 -targetid|" .. mq.TLO.Me.ID() .. " -invis")
    end

    if #sortedSpellKeys == 0 then return end

    if next(requiredBuffs) == nil then
        curState = "Idle..."
        doCanni()
        return
    end

    curState = "Buffing Required Buffs..."

    local buffSpell = next(requiredBuffs)
    local buffTarget = requiredBuffs[buffSpell][1] or "None"

    if mq.TLO.Spawn(buffTarget).ID() ~= nil and (BFOUtils.CanCast(buffSpell) or mq.TLO.FindItemCount(buffSpell)() > 0) then
        curState = "Casting " .. buffSpell .. " on " .. (mq.TLO.Spawn(buffTarget).Name() or "None")

        --print(curState)

        if mq.TLO.Spell(buffSpell).TargetType() == "Self" then buffTarget = "0" end

        if BFOUtils.CanCast(buffSpell) then
            BFOUtils.Cast(buffSpell, buffSpellSlot, buffTarget, false)
        else
            mq.cmd("/casting \"" .. buffSpell .. "\"")
        end
    end

    table.remove(requiredBuffs[buffSpell], 1)
    if next(requiredBuffs[buffSpell]) == nil then
        requiredBuffs[buffSpell] = nil
    end
end

function Buff.ShutDown()
end

return Buff
