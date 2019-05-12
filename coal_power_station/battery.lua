--[[

	TechAge
	=======

	Copyright (C) 2019 Joachim Stolberg

	LGPLv2.1+
	See LICENSE.txt for more information
	
	TA3 Battery Box

]]--

-- for lazy programmers
local S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local P = minetest.string_to_pos
local M = minetest.get_meta

-- Load support for intllib.
local MP = minetest.get_modpath("techage")
local I,_ = dofile(MP.."/intllib.lua")

local STANDBY_TICKS = 4
local COUNTDOWN_TICKS = 4
local CYCLE_TIME = 2
local POWER_CONSUMPTION = 10
local POWER_MAX_LOAD = 1000

local Power = techage.ElectricCable
local generator = techage.generator

-- called from pipe network
local function valid_power_dir(pos, power_dir, in_dir)
	return power_dir == in_dir
end

local function formspec(self, pos, mem)
	return "size[5,3]"..
		default.gui_bg..
		default.gui_bg_img..
		default.gui_slots..
		"image[0,0.5;1,2;"..generator.formspec_battery_capa(POWER_MAX_LOAD, mem.capa)..
		"label[0.2,2.5;Load]"..
		"button[1.1,1;1.8,1;update;"..I("Update").."]"..
		"image_button[3,1;1,1;".. self:get_state_button_image(mem) ..";state_button;]"..
		"image[4,0.5;1,2;"..generator.formspec_battery_load(mem)..
		"label[4.2,2.5;Flow]"
end

local function turn_off(pos, mem)
	generator.turn_power_on(pos, 0)
	mem.charging = false
	mem.unloading = false
end

local function switch_to_unloading(pos, mem)
	if not mem.unloading then
		mem.unloading = true
		mem.charging = false
		generator.turn_power_on(pos, 2 * POWER_CONSUMPTION)
	end
end

local function switch_to_charging(pos, mem)
	if mem.sum > POWER_CONSUMPTION and not mem.charging then
		mem.charging = true
		mem.unloading = false
		generator.turn_power_on(pos, -POWER_CONSUMPTION)
	end
	mem.delayed_call = false
end

local function start_node(pos, mem, state)
	turn_off(pos, mem)
end

local function stop_node(pos, mem, state)
	turn_off(pos, mem)
end

local State = techage.NodeStates:new({
	node_name_passive = "techage:ta3_battery",
	cycle_time = CYCLE_TIME,
	standby_ticks = STANDBY_TICKS,
	formspec_func = formspec,
	start_node = start_node,
	stop_node = stop_node,
})

local function node_timer(pos, elapsed)
	local mem = tubelib2.get_mem(pos)
	if State:is_active(mem) then
		mem.capa = mem.capa or 0
		if mem.charging then
			if mem.capa < POWER_MAX_LOAD then
				mem.capa = mem.capa + 1
			else
				turn_off(pos, mem)
			end
		elseif mem.unloading then
			if mem.capa > 0 then
				mem.capa = mem.capa - 1
			else
				turn_off(pos, mem)
			end
		end
	end
	--print("node_timer", S(pos), mem.sum, mem.power_capacity)
	return State:is_active(mem)
end

local function turn_power_on(pos, in_dir, sum)
	local mem = tubelib2.get_mem(pos)
	if State:is_active(mem) then
		mem.capa = mem.capa or 0
		mem.sum = sum
		--print("turn_power_on", sum, dump(mem))
		if mem.unloading then
			if sum < 0 then
				turn_off(pos, mem)
			elseif sum > 2 * POWER_CONSUMPTION then
				turn_off(pos, mem)
			end
		elseif mem.charging then
			if sum < 0 then
				turn_off(pos, mem)
			end
		else -- turned off
			if sum > POWER_CONSUMPTION and not mem.delayed_call then
				minetest.after(math.random(1.2, 5.0), 
						switch_to_charging, pos, mem)
				mem.delayed_call = true
			end
		end
	end
end

local function on_receive_fields(pos, formname, fields, player)
	if minetest.is_protected(pos, player:get_player_name()) then
		return
	end
	local mem = tubelib2.get_mem(pos)
	State:state_button_event(pos, mem, fields)
	
	if fields.update then
		local mem = tubelib2.get_mem(pos)
		M(pos):set_string("formspec", formspec(State, pos, mem))
	end
end

local function on_rightclick(pos)
	local mem = tubelib2.get_mem(pos)
	M(pos):set_string("formspec", formspec(State, pos, mem))
end

minetest.register_node("techage:ta3_battery", {
	description = "TA3 Battery",
	tiles = {
		-- up, down, right, left, back, front
		"techage_filling_ta3.png^techage_frame_ta3_top.png",
		"techage_filling_ta3.png^techage_frame_ta3.png",
		"techage_filling_ta3.png^techage_frame_ta3.png^techage_appl_hole_electric.png",
		"techage_filling_ta3.png^techage_frame_ta3.png^techage_appl_source.png",
		"techage_filling_ta3.png^techage_frame_ta3.png^techage_appl_source.png",
		"techage_filling_ta3.png^techage_frame_ta3.png^techage_appl_source.png",
	},
	paramtype2 = "facedir",
	groups = {cracky=2, crumbly=2, choppy=2},
	on_rotate = screwdriver.disallow,
	is_ground_content = false,

	techage = {
		turn_on = turn_power_on,
		read_power_consumption = generator.read_power_consumption,
		power_network = Power,
		power_side = "R",
	},
	
	after_place_node = function(pos, placer)
		local mem = generator.after_place_node(pos)
		State:node_init(pos, mem, "")
		mem.charging = false
		mem.unloading = false
		on_rightclick(pos)
	end,
	
	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		State:after_dig_node(pos, oldnode, oldmetadata, digger)
		generator.after_dig_node(pos, oldnode)
	end,
	
	after_tube_update = generator.after_tube_update,	
	on_receive_fields = on_receive_fields,
	on_rightclick = on_rightclick,
	on_timer = node_timer,
})

Power:add_secondary_node_names({"techage:ta3_battery"})