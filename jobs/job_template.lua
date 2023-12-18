local mq = require('mq')
local LIP = require('lib/LIP')
require('lib/ed/utils')
local BFOUtils = require('lib/bfoutils')
local ImGui = require('ImGui')

local ExampleJob = {}

local examplejob_settings_file = '/lua/config/examplejob.ini'
local examplejob_settings_path = nil
local examplejobsettings = {}
local curState = "Idle.."

function ExampleJob.Setup(config_dir)
    if not examplejob_settings_path and config_dir then
        examplejob_settings_path = config_dir .. examplejob_settings_file
    end

    if file_exists(examplejob_settings_path) then
        examplejobsettings = LIP.load(examplejob_settings_path)
    else
        print("Can't find examplejob.ini at: " .. examplejob_settings_path)
        return
    end
end

local SaveSettings = function(doBroadcast)
    LIP.save(examplejob_settings_path, examplejobsettings)

    if doBroadcast then
        JobActors.send({ from = CharConfig, script = "Job", module = "JobExampleJob", event = "SaveSettings" })
    end
end

function ExampleJob.Render()
    if not examplejobsettings then return end

    ImGui.Text("examplejob configuration..")
    ImGui.Separator()
end

function ExampleJob.GiveTime()
    if (not examplejobsettings[CharConfig]) then
        curState = "No configuration for " .. CharConfig .. "..."
        return
    end
end

function ExampleJob.ShutDown()
end

return ExampleJob
