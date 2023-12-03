local mq = require('mq')
local LIP = require('lib/LIP')
local utils = require('lib/ed/utils')
local BFOUtils = require('lib/bfoutils')

local ImGui = require('ImGui')

local highestBuff = nil
local highestStackableBuff = nil
local highestShield = nil
local highestPet = nil
local petType = "Water"
local petTypeIndex = 0
local curState = "Idle..."

local castPetBuffs = false
local castStackableBuffs = false
local castPetShield = false
local castPetInCombat = true

local pet_settings_file = '/lua/config/pet.ini'
local pet_settings_path = ""
local petsettings = {}

local Pet = {}

local killRadius
local killZRadius

local PetElements = {
	"Water",
	"Fire",
	"Earth",
	"Air",
}

local Buffs = {
	"Burnout I",
	"Burnout II",
	"Burnout III",
	"Burnout IV",
	"Burnout V",
	"Burnout VI",
	"Burnout VII",
	"Burnout VIII",
	"Burnout IX",
	"Burnout X",
	"Burnout XI",
	"Burnout XII",
	"Augment Death",
	"Augmentation of Death",
	"Rune of Death",
	"Glyph of Darkness",
	"Sigil of the Unnatural",
	"Sigil of the Aberrant",
	"Sigil of the Moribund",
	"Sigil of the Preternatural",
	"Sigil of the Sundered",
	"Sigil of Doomscale",
	"Yekan's Quickening",
	"Omakin's Alacrity",
	"Sha's Ferocity",
	"Arag's Celerity",
	"Growl of the Beast",
	"Unparalleled Voracity",
	"Peerless Penchant",
	"Unrivaled Rapidity",
	"Incomparable Velocity",
	"Exceptional Velocity",
	"Extraordinary Velocity",
	"Alacrity",
}

local StackableBuffs = {
	"Spirit of Lightning",
	"Spirit of Blizzard",
	"Spirit of Inferno",
	"Spirit of the Scorpion",
	"Spirit of Vermin",
	"Spirit of the Storm",
	"Spirit of Snow",
	"Spirit of Flame",
	"Spirit of Rellic",
	"Spirit of Irionu",
	"Spirit of Oroshar",
	"Spirit of Lairn",
	"Spirit of Jeswin",
	"Spirit of Vaxztn",
	"Spirit of Kron",
	"Spirit of Bale",
	"Spirit of Nak",
	"Spirit of Visoracius",
	"Lockfang Jaws",
	"Neivr's Aggression",
	"Bestial Evulsing",
	"Withering Bite",
	"Sekmoset's Aggression",
	"Growl of the Leopard",
}

local ShieldSpells = {
	"Shield of Lava",
	"Cadeau of Flame",
	"Flameshield of Ro",
}

local PetSpells = {
	"Lesser Conjuration: %s",
	"Conjuration: %s",
	"Greater Conjuration: %s",
	"Vocarate: %s",
	"Greater Vocaration: %s",
	"Ward of Xegony",
	"Servant of Marr",
	"Child of Ro",
	"Rathe's Son",
	"Child of %s",
	"Essence of %s",
	"Core of %s",
	"Aspect of %s",
	"Construct of %s",
	"Facet of %s",
	"Shade of %s",
	"Convocation of %s",
	"Pendril's Animation",
	"Juli's Animation",
	"Mircyl's Animation",
	"Kilan's Animation",
	"Shalee's Animation",
	"Sisna's Animation",
	"Sagar's Animation",
	"Uleen's Animation",
	"Boltran's Animation",
	"Aanya's Animation",
	"Yegoreff's Animation",
	"Kintaz's Animation",
	"Zumailk's Animation",
	"Aeldorb's Animation",
	"Salik's Animation",
	"Leering Corpse",
	"Bone Walk",
	"Convoke Shadow",
	"Restless Bones",
	"Animate Dead",
	"Haunting Corpse",
	"Summon Dead",
	"Invoke Shadow",
	"Malignant Dead",
	"Cackling Bones",
	"Invoke Death",
	"Son of Decay",
	"Servant of Bones",
	"Emissary of Thule",
	"Legacy of Zek",
	"Saryrn's Companion",
	"Child of Bertoxxulous",
	"Lost Soul",
	"Dark Assassin",
	"Riza'Farr's Shadow",
	"Putrescent Servant",
	"Relamar's Shade",
	"Noxious Servant",
	"Bloodreaper's Shade",
	"Unliving Murderer",
	"Aziad's Shade",
	"Raised Assassin",
	"Vak'Ridel's Shade",
	"Reborn Assassin",
	"Zalifur's Shade",
	"Unearthed Assasisin",
	"Miktokla's Shade",
	"Revived Assassin",
	"Frenzied Spirit",
	"Spirit of the Howler",
	"True Spirit",
	"Farrel's Companion",
	"Spirit of Kashek",
	"Spirit of Omakin",
	"Spirit of Zehkes",
	"Spirit of Khurenz",
	"Spirit of Khati Sha",
	"Spirit of Arag",
	"Spirit of Sorsha",
	"Spirit of Alladnu",
	"Spirit of Rashara",
	"Spirit of Uluanes",
	"Spirit of Silverwing",
	"Spirit of Hoshkar",
	"Spirit of Averc",
	"Spirit of Kolos",
	"Spirit of Lechemit",
	"Spirit of Avalit",
}

local doPetCast = function(petSpell, wait)
	local petSlot = petsettings["Default"]["PetSlot"] or 5
	if mq.TLO.Pet.ID() <= 0 and BFOUtils.CanCast(petSpell) then
		BFOUtils.Cast(petSpell, petSlot, 0, wait)
	end
end

local doPetBuffCast = function(buff, wait)
	if mq.TLO.Pet.ID() and buff and BFOUtils.CanCast(buff) and not BFOUtils.HasBuffByName(mq.TLO.Pet, buff) then
		curState = "Casting: " .. buff .. "..."
		BFOUtils.Cast(buff, 5, mq.TLO.Pet.ID(), wait)
		return true
	end
	return false
end

function Pet.Setup(config_dir)
	if pet_settings_path:len() == 0 then
		pet_settings_path = config_dir .. pet_settings_file
	end

	if file_exists(pet_settings_path) then
		petsettings = LIP.load(pet_settings_path)
	else
		print("Can't find pet.ini at: " .. pet_settings_path)
		return
	end

	if not petsettings["Default"]["CastPetInCombat"] then
		petsettings["Default"]["CastPetInCombat"] = castPetInCombat
	end

	castPetBuffs = petsettings["Default"]["CastPetBuffs"] ~= 0
	castStackableBuffs = petsettings["Default"]["CastStackableBuffs"] ~= 0
	castPetShield = petsettings["Default"]["CastShieldBuffs"] ~= 0
	castPetInCombat = petsettings["Default"]["CastPetInCombat"] ~= 0

	highestBuff = BFOUtils.GetHighestSpell(Buffs, nil)
	highestStackableBuff = BFOUtils.GetHighestSpell(StackableBuffs, nil)
	highestShield = BFOUtils.GetHighestSpell(ShieldSpells, nil)

	if petsettings["Default"]["PetType"] then
		petType = petsettings["Default"]["PetType"]
		for i, v in ipairs(PetElements) do
			if v == petType then
				petTypeIndex = i
			end
		end
	end

	highestPet = BFOUtils.GetHighestSpell(PetSpells, petType)
end

local SaveSettings = function()
	LIP.save(pet_settings_path, petsettings)
end

function Pet.Render()
	ImGui.Text("Pet configuration..")
	ImGui.Separator()

	local pressed

	if ImGui.Button("Reload INI") then
		Pet.Setup()
	end

	BFOUtils.RenderCurrentState(curState)

	if highestBuff then
		ImGui.Text("Using Buff: " .. highestBuff)
	end

	if highestStackableBuff then
		ImGui.Text("Using Stackable Buff: " .. highestStackableBuff)
	end

	if highestShield then
		ImGui.Text("Using Shield: " .. highestShield)
	end

	if highestPet then
		ImGui.Text("Using Pet Spell: " .. highestPet)
	else
		ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.0, 0.0, 0.75)
		ImGui.Text("No Pet Spell Found!")
		ImGui.PopStyleColor(1)
	end

	if mq.TLO.Me.Class.Name() == "Magician" then
		petTypeIndex, pressed = ImGui.Combo("Pet Element", petTypeIndex, PetElements, 4)
		if pressed then
			local petSpellBefore = highestPet
			petType = PetElements[petTypeIndex]
			petsettings["Default"]["PetType"] = petType
			SaveSettings()
			Pet.Setup()

			if petSpellBefore ~= highestPet then
				mq.cmd("/pet leave")
			end
		end
	end

	castPetBuffs, pressed = ImGui.Checkbox("CastPetBuffs", castPetBuffs)
	if pressed then
		local check = "1"
		if castPetBuffs == false then check = "0" end

		petsettings["Default"]["CastPetBuffs"] = check
		SaveSettings()
		Pet.Setup()
	end

	castStackableBuffs, pressed = ImGui.Checkbox("CastStackableBuffs", castStackableBuffs)
	if pressed then
		local check = "1"
		if castStackableBuffs == false then check = "0" end

		petsettings["Default"]["CastStackableBuffs"] = check
		SaveSettings()
		Pet.Setup()
	end

	castPetShield, pressed = ImGui.Checkbox("CastShieldBuffs", castPetShield)
	if pressed then
		local check = "1"
		if castPetShield == false then check = "0" end

		petsettings["Default"]["CastShieldBuffs"] = check
		SaveSettings()
		Pet.Setup()
	end

	castPetInCombat, pressed = ImGui.Checkbox("CastPetInCombat", castPetInCombat)
	if pressed then
		local check = "1"
		if castPetInCombat == false then check = "0" end

		petsettings["Default"]["CastPetInCombat"] = check
		SaveSettings()
		Pet.Setup()
	end
end

function Pet.GiveTime()
	if highestPet == nil or highestPet == "None" or BFOUtils.IsCasting() then
		return
	end

	if BFOUtils.IsCasting() or not mq.TLO.Cast.Ready() or mq.TLO.Me.Moving() then
		return
	end

	curState = "Idle..."

	if not castPetInCombat and BFOUtils.IsInCombat() then
		return
	end

	if (not mq.TLO.Pet.ID() or mq.TLO.Pet.ID() <= 0) and BFOUtils.CanCast(highestPet) then
		curState = "Casting: " ..
			highestPet .. " (" .. mq.TLO.Me.CurrentMana() .. " / " .. mq.TLO.Spell(highestPet).Mana() .. ")..."
		doPetCast(highestPet, false)
		return
	end

	if castPetBuffs and mq.TLO.Pet.ID() > 0 then
		if doPetBuffCast(highestBuff, false) then
			return
		end
	end

	if castStackableBuffs and mq.TLO.Pet.ID() > 0 then
		if doPetBuffCast(highestStackableBuff, false) then
			return
		end
	end

	if castPetShield and mq.TLO.Pet.ID() > 0 then
		if doPetBuffCast(highestShield, false) then
			return
		end
	end

	if petsettings[CharConfig] and petsettings[CharConfig]["AutoKillNpcs"] then
		if petsettings["Default"]["AutoKillNpcsName"] then
			mq.cmd("/target " ..
				petsettings["Default"]["AutoKillNpcsName"] .. " npc radius " .. killRadius .. " zradius " .. killZRadius)
		else
			mq.cmd("/target npc radius " .. killRadius .. " zradius " .. killZRadius)
		end

		if mq.TLO.Target.Distance() > 175 or mq.TLO.Target.Type() ~= "NPC" or mq.TLO.Target.ID() == mq.TLO.Pet.ID() then
			mq.cmd("/target clear")
		end

		if mq.TLO.Target.ID() > 0 and mq.TLO.Pet.Distance() < 20 then
			mq.cmd("/pet attack " .. mq.TLO.Target.ID())
		end
	end

	if petsettings[CharConfig] and petsettings[CharConfig]["AutoKillPets"] then
		killRadius = petsettings["Default"]["AutoKillNpcsRadius"] or 165
		killZRadius = petsettings["Default"]["AutoKillNpcsZRadius"] or 10

		if mq.TLO.Target.ID() == nil and mq.TLO.Me.XTarget(1).ID() > 0 then
			mq.cmd("/target id " .. mq.TLO.Me.XTarget(1).ID())
		end

		if mq.TLO.Me.XTarget(1).ID() > 0 and mq.TLO.Target.ID() ~= mq.TLO.Me.XTarget(1).ID() then
			mq.cmd("/target id " .. mq.TLO.Me.XTarget(1).ID())
		end

		if mq.TLO.Target.ID() <= 0 then
			if petsettings["Default"]["AutoKillNpcsName"] then
				mq.cmd("/target " ..
					petsettings["Default"]["AutoKillNpcsName"] ..
					" npc radius " .. killRadius .. " zradius " .. killZRadius)
			else
				mq.cmd("/target npc radius " .. killRadius .. " zradius " .. killZRadius)
			end
		end

		if mq.TLO.Target.ID() > 0 and (mq.TLO.Target.Distance() > 200 or mq.TLO.Target.Type() ~= "NPC" or mq.TLO.Target.ID() == mq.TLO.Pet.ID()) then
			mq.cmd("/target clear")
		end

		if mq.TLO.Target.ID() > 0 and mq.TLO.Pet.Distance() < killRadius then
			mq.cmd("/bcaa //pet attack " .. mq.TLO.Target.ID())
		end
	end
end

local armPets = function()
	-- Currently Unsupported
end

function Pet.ShutDown()
end

return Pet
