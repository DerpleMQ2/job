local mq = require('mq')
local LIP = require('lib/LIP')
require('lib/ed/utils')
require('lib/bfoutils')
local ICONS = require('mq.Icons')
local ImGui = require('ImGui')

local Hunter = {}

local hunter_pickle_path = mq.configDir .. '/job/' .. 'hunter.lua'

local hunterSettings = {}
local curState = "Idle.."
local pauseHunter = true

local SaveSettings = function(doBroadcast)
    mq.pickle(hunter_pickle_path, hunterSettings)

    if doBroadcast then
        JobActors.send({ from = CharConfig, script = "Job", module = "JobHunter", event = "SaveSettings" })
    end
end

function Hunter.Setup()
    local config, err = loadfile(hunter_pickle_path)
    if err then
        mq.pickle(hunter_pickle_path, hunterSettings)
    else
        if config then hunterSettings = config() end
    end

    if not hunterSettings.Config then
        hunterSettings.Config = {}
        hunterSettings.Config.RequireNav = false
        hunterSettings.Config.ClearXTargFirst = true
        SaveSettings(true)
    end
end

local function targetFilter(spawn)
    if spawn.DisplayName():len() == 0 then return false end
    local targetName = spawn.DisplayName()
    local zoneName = mq.TLO.Zone.ShortName()

    local res = (spawn.Type() == "NPC" and spawn.Targetable() and
        TableContains(hunterSettings.HuntList[zoneName], targetName))

    return res
end

local function getValidTargets()
    local possibleTargets = mq.getFilteredSpawns(function(spawn) return targetFilter(spawn) end)

    table.sort(possibleTargets, function(k1, k2) return k1.Distance() < k2.Distance() end)

    return possibleTargets
end

local function getBestTarget()
    local possibleTargets = getValidTargets()

    return possibleTargets[1]
end

local possibleTargetCount = 0

function Hunter.Render()
    if not hunterSettings then return end

    local zoneName = mq.TLO.Zone.ShortName()

    ImGui.Text("Hunter configuration..")

    if ImGui.SmallButton("Reload INI") then
        Hunter.Setup()
    end

    local pressed

    hunterSettings.Config.RequireNav, pressed = ImGui.Checkbox("Require Nav Path",
        hunterSettings.Config.RequireNav)
    if pressed then SaveSettings(true) end

    local pressed

    hunterSettings.Config.ClearXTargFirst, pressed = ImGui.Checkbox("Clear XTarg before next hunt Target",
        hunterSettings.Config.ClearXTargFirst)
    if pressed then SaveSettings(true) end

    ImGui.Separator()
    ImGui.Text(string.format("Current State: %s", curState))

    pauseHunter, _ = ImGui.Checkbox("Pause", pauseHunter)

    if mq.TLO.Target and mq.TLO.Target.ID() > 0 then
        ImGui.Separator()
        local targetName = mq.TLO.Target.DisplayName()
        if ImGui.SmallButton("Add to Hunt List") then
            hunterSettings.HuntList = hunterSettings.HuntList or {}
            hunterSettings.HuntList[zoneName] = hunterSettings.HuntList[zoneName] or {}

            if not TableContains(hunterSettings.HuntList[zoneName], targetName) then
                printf("\agAdded \am%s\ag to Hunt List...", targetName)
                table.insert(hunterSettings.HuntList[zoneName], targetName)
                SaveSettings(true)
            end
        end
    end

    ImGui.Separator()
    ImGui.BeginTable("Hunt List", 3, ImGuiTableFlags.Resizable + ImGuiTableFlags.Borders)
    ImGui.TableSetupColumn('Hunt Mob Name', ImGuiTableColumnFlags.None, 250.0)
    ImGui.TableSetupColumn('Count', ImGuiTableColumnFlags.None, 50.0)
    ImGui.TableSetupColumn('Actions', ImGuiTableColumnFlags.None, 50.0)
    ImGui.TableHeadersRow()
    possibleTargetCount = 0
    for ki, vh in pairs(hunterSettings.HuntList[zoneName] or {}) do
        ImGui.TableNextColumn()
        if ImGui.Selectable(vh, false, 0) then
            local validTargets = getValidTargets()
            for _, t in ipairs(validTargets) do
                if t.DisplayName() == vh then
                    mq.cmdf("/target id %d", t.ID())
                    break
                end
            end
        end
        ImGui.TableNextColumn()
        local targetCount = mq.TLO.SpawnCount("=" .. vh)()
        possibleTargetCount = possibleTargetCount + targetCount
        ImGui.Text(tostring(targetCount))
        ImGui.TableNextColumn()
        ImGui.PushID(vh .. "_trash_btn")
        if ImGui.SmallButton(ICONS.FA_TRASH) then
            local zoneName = mq.TLO.Zone.ShortName()
            hunterSettings.HuntList[zoneName][ki] = nil
            SaveSettings(true)
        end
        ImGui.PopID()
    end
    ImGui.EndTable()
end

function Hunter.GiveTime()
    if (not hunterSettings) or pauseHunter then
        curState = "Paused..."
        return
    end

    if not mq.TLO.Target or mq.TLO.Target.ID() <= 0 or mq.TLO.Target.Dead() then
        -- Find a new target.
        local targetSpawn = getBestTarget()

        if mq.TLO.Me.XTarget(1).ID() > 0 then
            if hunterSettings.Config.ClearXTargFirst or not targetSpawn then
                targetSpawn = mq.TLO.Me.XTarget(1)
            end
        end

        if targetSpawn then
            if possibleTargetCount > 0 then
                curState = string.format("Looking for a new Hunt Target...")
            else
                curState = "Idle..."
            end
            mq.cmdf("/target id %d", targetSpawn.ID())
            printf("\agNew target: %s (%d)", targetSpawn.DisplayName(), targetSpawn.ID())
            mq.cmdf("/nav id %d", targetSpawn.ID())
        end
    end

    if mq.TLO.Target() and not mq.TLO.Target.Dead() and not mq.TLO.Nav.Active() and mq.TLO.Target.Distance() > 15 and mq.TLO.Target.Type() == "NPC" then
        if mq.TLO.Nav.PathExists() then
            curState = string.format("Pathing to: %s", mq.TLO.Target.DisplayName())
            mq.cmdf("/nav id %d", mq.TLO.Target.ID())
        end

        if not hunterSettings.Config.RequireNav then
            if not mq.TLO.Nav.Active() and mq.TLO.MoveUtils() ~= "STICK" then
                curState = string.format("Sticking to to: %s", mq.TLO.Target.DisplayName())
                mq.cmdf("/stick id %d uw 10", mq.TLO.Target.ID())
            end
        else
            if not mq.TLO.Nav.Active() and mq.TLO.Target.ID() > 0 then
                curState = "No Pathing to Target..."
            end
        end
    end

    if mq.TLO.Target and not mq.TLO.Nav.Active() and not mq.TLO.Me.Combat() and mq.TLO.Melee.Status() == "WAITING " and mq.TLO.Target.Distance() < 20 then
        mq.cmdf("/killthis")
    end

    if not mq.TLO.Target() or mq.TLO.Target.Dead() then
        curState = "Waiting for Spawns.."
    end
end

function Hunter.ShutDown()
end

return Hunter
