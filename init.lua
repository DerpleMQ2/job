local mq = require('mq')
require('lib/ed/utils')

local LIP = require('lib/LIP')
local BFOUtils = require('lib/bfoutils')
local ImGui = require('ImGui')

local __WMCasting = false

JobActors = require 'actors'

local jobs = {}
jobs["JobPet"] = require('jobs/pet')
jobs["JobBuff"] = require('jobs/buff')
jobs["JobHeal"] = require('jobs/heal')
jobs["JobBard"] = require('jobs/bard')
jobs["JobLich"] = require('jobs/lich')
jobs["JobTravel"] = require('jobs/travel')
jobs["JobAuction"] = require('jobs/auction')

CurLoadedChar = mq.TLO.Me.CleanName()
CharConfig = mq.TLO.Me.CleanName() --'Char_'..mq.TLO.EverQuest.Server()..'_'..mq.TLO.Me.CleanName()..'_Config'
CharConfigTarget = CharConfig .. "_Targets"
local openGUI = true
local shouldDrawGUI = true
local bgOpacity = 1.0
local sitOOC = false -- not saved.

local MaxCursorSec = 10

local cursorSeconds = 0
local curState = "Idle..."

local animItems = mq.FindTextureAnimation("A_DragItem")
local animBox = mq.FindTextureAnimation("A_RecessedBox")

local config_dir = mq.TLO.MacroQuest.Path():gsub('\\', '/')
local settings_file = '/lua/config/job.ini'
local settings_path = config_dir .. settings_file
local settings = {}
local terminate = false

-- Constants
local ICON_WIDTH = 40
local ICON_HEIGHT = 40
local COUNT_X_OFFSET = 39
local COUNT_Y_OFFSET = 23
local EQ_ICON_OFFSET = 500

local function display_item_on_cursor()
    if mq.TLO.Cursor() then
        local cursor_item = mq.TLO.Cursor -- this will be an MQ item, so don't forget to use () on the members!
        local mouse_x, mouse_y = ImGui.GetMousePos()
        local window_x, window_y = ImGui.GetWindowPos()
        local icon_x = mouse_x - window_x + 10
        local icon_y = mouse_y - window_y + 10
        local stack_x = icon_x + COUNT_X_OFFSET
        local stack_y = icon_y + COUNT_Y_OFFSET
        local text_size = ImGui.CalcTextSize(tostring(cursor_item.Stack()))
        ImGui.SetCursorPos(icon_x, icon_y)
        animItems:SetTextureCell(cursor_item.Icon() - EQ_ICON_OFFSET)
        ImGui.DrawTextureAnimation(animItems, ICON_WIDTH, ICON_HEIGHT)
        if cursor_item.Stackable() then
            ImGui.SetCursorPos(stack_x, stack_y)
            ImGui.DrawTextureAnimation(animBox, text_size, ImGui.GetTextLineHeight())
            ImGui.SetCursorPos(stack_x - text_size, stack_y)
            ImGui.TextUnformatted(tostring(cursor_item.Stack()))
        end
    end
end

local SaveSettings = function()
    LIP.save(settings_path, settings)
end

local updateWMCast = function()
    BFOUtils.UpdateWMCast(__WMCasting)
    for k, v in pairs(jobs) do
        if settings[CharConfig][k] and settings[CharConfig][k] == 1 and jobs[k].UpdateWMCast then
            jobs[k].UpdateWMCast(__WMCasting)
        end
    end
end

local LoadSettings = function()
    CharConfig = mq.TLO.Me.CleanName()
    CharConfigTarget = CharConfig .. "_Targets"



    if file_exists(settings_path) then
        settings = LIP.load(settings_path)
    else
        print("Can't find job.ini at: " .. settings_path)
        terminate = true
        return false
    end

    -- if this character doesn't have the sections in the ini, create them
    if settings[CharConfig] == nil then
        print("Can't find jobs for " .. CharConfig .. " in: " .. settings_path .. " ... Creating it!")

        settings[CharConfig] = {}

        for k, v in pairs(jobs) do
            settings[CharConfig][k] = 0
        end

        settings[CharConfig]["MaxCursorSec"] = 10
        settings[CharConfig]["BgOpacity"] = 1.0

        SaveSettings()
    end

    -- turn off any new jobs by default.
    for k, v in pairs(jobs) do
        settings[CharConfig][k] = settings[CharConfig][k] or 0
    end

    if settings[CharConfig]["MaxCursorSec"] == nil then
        settings[CharConfig]["MaxCursorSec"] = 10
        SaveSettings()
    end

    if settings[CharConfig]["BgOpacity"] == nil then
        settings[CharConfig]["BgOpacity"] = 1.0
        SaveSettings()
    end

    bgOpacity = settings[CharConfig]["BgOpacity"]

    for k, v in pairs(jobs) do
        jobs[k].Setup(config_dir)
    end

    __WMCasting = false
    updateWMCast()

    CurLoadedChar = mq.TLO.Me.CleanName()

    MaxCursorSec = settings[CharConfig]["MaxCursorSec"]

    return true
end

local ToggleJob = function(job)
    settings[CharConfig][job] = (settings[CharConfig][job] + 1) % 2
    --print( "Toggled: "..job.." to "..settings[CharConfig][job])
    SaveSettings()
end

local renderSettingsTab = function()
    if not settings or not settings[CharConfig] then return end
    ImGui.BeginTable("Settings", 5)
    for k, v in pairs(settings[CharConfig]) do
        if string.find(k, "^Job") then
            ImGui.TableNextColumn()
            if v == 1 then
                ImGui.PushStyleColor(ImGuiCol.Button, 0.0, 1.0, 0.0, 1)
                ImGui.PushStyleColor(ImGuiCol.Text, 0, 0, 0, 1)
            else
                ImGui.PushStyleColor(ImGuiCol.Button, 1.0, 0.0, 0.0, 0.75)
                ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 1.0, 1.0, 1)
            end
            if ImGui.Button(k, 95, 25) then
                ToggleJob(k)
            end
            ImGui.PopStyleColor(2)
        end
    end
    ImGui.EndTable()

    ImGui.Separator()
end

local renderJobTabs = function()
    if not settings or not settings[CharConfig] then return end
    for k, v in pairs(settings[CharConfig]) do
        if string.find(k, "^Job") then
            ImGui.TableNextColumn()
            if v == 1 then
                if ImGui.BeginTabItem(k) then
                    if jobs[k] then
                        jobs[k].Render()
                    end
                    ImGui.EndTabItem()
                end
            end
        end
    end
end

local JobGUI = function()
    if mq.TLO.MacroQuest.GameState() ~= "INGAME" then return end
    if mq.TLO.Me.Dead() then return end

    --ImGui.PushStyleColor(ImGuiCol.Window, 0.0, 1.0, 0.0, 0.5)
    ImGui.SetNextWindowBgAlpha(bgOpacity)
    openGUI, shouldDrawGUI = ImGui.Begin('BFO Jobs', openGUI)
    local pressed

    if shouldDrawGUI then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.0, 1.0, 0.0, 1)
        ImGui.Text("Jobs running for " .. CharConfig)

        if mq.TLO.Plugin("MQ2WriteMem").IsLoaded() then
            __WMCasting, pressed = ImGui.Checkbox("WMCast", __WMCasting)
            if pressed then
                updateWMCast()
            end
        end

        if ImGui.BeginTabBar("Tabs") then
            ImGui.SetItemDefaultFocus()
            if ImGui.BeginTabItem("Settings") then
                renderSettingsTab()
                BFOUtils.RenderCurrentState(curState)
                ImGui.EndTabItem()
            end

            renderJobTabs()

            ImGui.EndTabBar();
        end
        ImGui.PopStyleColor(1)
    end

    ImGui.NewLine()
    ImGui.NewLine()
    ImGui.Separator()

    sitOOC, _ = ImGui.Checkbox("Sit Out of Combat", sitOOC)
    ---@diagnostic disable-next-line: undefined-field
    if sitOOC and not BFOUtils.IsInCombat() and not mq.TLO.Me.Sitting() and not mq.TLO.Me.Moving() and not BFOUtils.IsCasting() and mq.TLO.Cast.Ready() then
        mq.cmd("/if (!${Me.Sitting} && !${Me.Moving}) /sit")
    end

    MaxCursorSec, pressed = ImGui.SliderInt("Drop Cursor Item After", MaxCursorSec, 0, 60, "%d")
    if pressed then
        settings[CharConfig]["MaxCursorSec"] = MaxCursorSec
        SaveSettings()
    end

    bgOpacity, pressed = ImGui.SliderFloat("BG Opacity", bgOpacity, 0, 1.0, "%.1f", 0.1)
    if pressed then
        settings[CharConfig]["BgOpacity"] = bgOpacity
        SaveSettings()
    end

    display_item_on_cursor()
    --ImGui.PopStyleColor(1)
    ImGui.End()
end
mq.imgui.init('jobGUI', JobGUI)

local Job = function()
    curState = "Idle..."

    if mq.TLO.MacroQuest.GameState() ~= "INGAME" then return end

    if CurLoadedChar ~= mq.TLO.Me.CleanName() then
        LoadSettings()
    end

    local now = os.clock()

    if mq.TLO.Cursor.ID() and settings[CharConfig]["MaxCursorSec"] > 0 then
        local onCurSec = math.floor(now - cursorSeconds)

        if cursorSeconds == 0 then
            cursorSeconds = now
        elseif onCurSec < settings[CharConfig]["MaxCursorSec"] then
            curState = "Item \'" .. mq.TLO.Cursor() .. "\' on my cursor for " .. onCurSec .. "s"
        else
            curState = "Dropping Item \'" .. mq.TLO.Cursor() .. "\' on my cursor after " .. onCurSec .. "s"
            mq.cmd("/autoinv")
            cursorSeconds = 0
        end
    else
        cursorSeconds = 0
    end

    for k, v in pairs(jobs) do
        if settings[CharConfig][k] and settings[CharConfig][k] == 1 then
            jobs[k].GiveTime()
        end
    end
end

-- Global Messaging callback
---@diagnostic disable-next-line: unused-local
local script_actor = JobActors.register(function(message)
    if message()["from"] == CharConfig then return end

    printf("\ayGot Event from(\am%s\ay) module(\at%s\ay) event(\at%s\ay)", message()["from"], message()["module"],
        message()["event"])

    if message()["module"] then
        jobs[message()["module"]].Setup(config_dir)
    end
end)

mq.bind('/jobend', function() terminate = true end)

mq.bind('/aa_add', function(who)
    mq.cmd("/autoaccept add " .. who)
    mq.delay(500)
    mq.cmd("/autoaccept save")
end)

LoadSettings()

while not terminate do
    Job()
    mq.doevents()
    mq.delay(10)
end

for k, v in pairs(jobs) do
    jobs[k].ShutDown()
end
