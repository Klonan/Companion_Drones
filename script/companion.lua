local util = require("util")
local follow_range = 10

local script_data =
{
  companions = {},
  tick_updates = {},
  player_data = {},
  search_schedule = {}
}

local make_player_gui = function(player)
  local gui = player.gui.relative
  if gui.companion_gui then return end

  local frame = gui.add
  {
    name = "companion_gui",
    type = "frame",
    caption = "Companion control",
    anchor =
    {
      position = defines.relative_gui_position.right,
      name = "companion",
      gui = defines.relative_gui_type.spider_vehicle_gui
    },
    direction = "vertical"
  }

  local inner = frame.add{type = "frame", direction = "vertical", style = "inside_shallow_frame_with_padding"}
  inner.style.padding = 4
  inner.style.horizontally_stretchable = true

  local combat_mode_frame = inner.add{type = "frame", style = "bordered_frame", caption = "Combat mode"}
  local switch = combat_mode_frame.add{type = "switch", left_label_caption = "Defensive", right_label_caption = "Aggressive", allow_none_state = false, switch_state = "left", tags = {companion_function = "combat_mode_switch"}}

  local construction_mode_frame = inner.add{type = "frame", style = "bordered_frame", caption = "Construction mode"}
  local switch = construction_mode_frame.add{type = "switch", left_label_caption = "Passive", right_label_caption = "Active", allow_none_state = false, switch_state = "left", tags = {companion_function = "construction_mode_switch"}}

  local extra_settings_frame = inner.add{type = "frame", style = "bordered_frame", caption = "Additional options"}
  local auto_refuel_checkbox = extra_settings_frame.add{type = "checkbox", state = true, caption = "Auto-refuel", tags = {companion_function = "auto_refuel_checkbox"}}

  local button = frame.add{type = "button", caption = "Return to me", tags = {companion_function = "return_home"}}
  button.style.horizontally_stretchable = true

end

local repair_tools
local get_repair_tools = function()
  if repair_tools then
    return repair_tools
  end
  repair_tools = {}
  for k, item in pairs (game.item_prototypes) do
    if item.type == "repair-tool" then
      repair_tools[item.name] = {name = item.name, count = 1}
    end
  end
  return repair_tools
end

local fuel_items
local get_fuel_items = function()
  if fuel_items then
    return fuel_items
  end
  fuel_items = {}
  for k, item in pairs (game.item_prototypes) do
    if item.fuel_value > 0 then
      table.insert(fuel_items, {name = item.name, count = 1, fuel_top_speed_multiplier = item.fuel_top_speed_multiplier})
    end
  end

  table.sort(fuel_items, function(a, b)
    return a.fuel_top_speed_multiplier > b.fuel_top_speed_multiplier
  end)

  --error(serpent.block(fuel_items))
  return fuel_items
end

local get_companion = function(unit_number)

  local companion = unit_number and script_data.companions[unit_number]
  if not companion then return end

  if not companion.entity.valid then
    companion:on_destroyed()
  end

  return companion
end

local distance = function(position_1, position_2)
  local x1 = position_1[1] or position_1.x
  local y1 = position_1[2] or position_1.y
  local x2 = position_2[1] or position_2.x
  local y2 = position_2[2] or position_2.y
  return (((x2 - x1) * (x2 - x1)) + ((y2 - y1) * (y2 - y1))) ^ 0.5
end

local name = "secret_companion_surface_please_dont_touch"
local get_secret_surface = function()
  local surface = game.surfaces[name]
  if surface then
    return surface
  end
  surface = game.create_surface(name, {height = 1, width = 1})
  return surface
end

local Companion = {}
Companion.metatable = {__index = Companion}

Companion.new = function(entity, player)

  local companion =
  {
    entity = entity,
    player = player,
    unit_number = entity.unit_number,
    robots = {},
    active_construction = true,
    active_combat = true,
    auto_fuel = true,
    flagged_for_equipment_changed = true,
    last_attack_tick = 0
  }
  setmetatable(companion, Companion.metatable)
  script_data.companions[entity.unit_number] = companion
  script.register_on_entity_destroyed(entity)
  entity.operable = true
  entity.minable = false

  companion.flagged_for_equipment_changed = true
  companion:propose_tick_update(1)
  companion:schedule_next_update()
  companion:add_passengers()
  companion:try_to_refuel()

  local player_data = script_data.player_data[player.index]
  if not player_data then
    player_data =
    {
      companions = {},
      last_job_search_offset = 0,
      last_attack_search_offset = 0
    }
    script_data.player_data[player.index] = player_data
  end
  player_data.companions[entity.unit_number] = true
end

local base_speed = 0.275

function Companion:clear_speed_sticker()
  if not self.speed_sticker then return end
  self.speed_sticker.destroy()
  self.speed_sticker = nil
end

function Companion:get_speed_sticker()
  if self.speed_sticker and self.speed_sticker.valid then
    return self.speed_sticker
  end
  self.speed_sticker = self.entity.surface.create_entity
  {
    name = "speed-sticker",
    target = self.entity,
    force = self.entity.force,
    position = self.entity.position
  }
  self.speed_sticker.active = false
  return self.speed_sticker
end

local sticker_life = 100
--0 ticks = 1x
--sticker life = 10x

function Companion:set_speed(speed)
  if speed == self.speed then return end
  self.speed = speed
  self:say(speed)
  local difference = speed - base_speed
  if difference <= 0 then
    self:clear_speed_sticker()
  else
    local sticker = self:get_speed_sticker()
    sticker.time_to_live = (sticker_life / 10) * difference
  end
  local was_too_fast = self.too_fast_for_bots
  if speed > 0.40 then
    self.too_fast_for_bots = true
    self:clear_robots()
  else
    self.too_fast_for_bots = false
    if was_too_fast then
      self:check_equipment()
    end
  end
end

function Companion:get_speed()
  return self.speed or base_speed
end

function Companion:get_grid()
  return self.entity.grid
end

function Companion:add_passengers()
  local driver = self.entity.surface.create_entity{name = "companion-passenger", position = self.entity.position, force = self.entity.force}
  self.entity.set_driver(driver)
  self.driver = driver
  local passenger = self.entity.surface.create_entity{name = "companion-passenger", position = self.entity.position, force = self.entity.force}
  self.entity.set_passenger(passenger)
  self.passenger = passenger
end

function Companion:clear_passengers()

  if self.driver and self.driver.valid then
    self.driver.destroy()
    self.driver = nil
  end

  if self.passenger and self.passenger.valid then
    self.passenger.destroy()
    self.passenger = nil
  end

end

function Companion:check_equipment()

  self.flagged_for_equipment_changed = nil

  local grid = self:get_grid()

  local network = self.entity.logistic_network
  local max_robots = (network and network.robot_limit) or 0

  local robot_count = table_size(self.robots)

  if robot_count ~= max_robots then

    if robot_count > max_robots then
      for k = 1, robot_count - max_robots do
        local index, robot = next(self.robots)
        if not index then break end
        self.robots[index] = nil
        robot.destroy()
      end
    end

    if robot_count < max_robots then
      local surface = self.entity.surface
      local position = self.entity.position
      local force = self.entity.force
      for k = 1, max_robots - robot_count do
        local robot = surface.create_entity{name = "companion-construction-robot", position = position, force = force}
        robot.logistic_network = network
        self.robots[robot.unit_number] = robot
        robot.destructible = false
        robot.minable = false
        self.entity.surface.create_entity
        {
          name = "inserter-beam",
          position = self.entity.position,
          target = robot,
          source = self.entity,
          force = self.entity.force,
          source_offset = {0, 0}
        }
      end
    end


    self.can_construct = max_robots > 0
  end

  for k, robot in pairs (self.robots) do
    robot.logistic_network = network
  end

  local can_attack = false

  for k, equipment in pairs (grid.equipment) do
    if equipment.type == "active-defense-equipment" then
      can_attack = true
      break
    end
  end

  self.can_attack = can_attack

end

function Companion:clear_robots()
  for k, robot in pairs (self.robots) do
    robot.mine
    {
      inventory = self:get_inventory(),
      force = true,
      ignore_minable = true
    }
    self.robots[k] = nil
  end
end

function Companion:check_broken_robots()
  --We are gathered here today, because we should have all our robots available to us. That is that the move to robot average has said.
  if self.entity.logistic_network.available_construction_robots ~= table_size(self.robots) then
    self:clear_robots()
    self:check_equipment()
  end
end

function Companion:move_to_robot_average()
  if self.too_fast_for_bots then return end
  if not next(self.robots) then return end

  local position = {x = 0, y = 0}
  local our_position = self.entity.position
  local count = 0
  for k, robot in pairs (self.robots) do
    local robot_position = robot.position
    local dx = math.abs(robot_position.x - our_position.x)
    local dy = math.abs((robot_position.y + 2) - our_position.y)
    if dx > 0.3 or dy > 0.3 then
      position.x = position.x + robot_position.x
      position.y = position.y + robot_position.y
      count = count + 1
    end
  end
  if count == 0 then
    self:check_broken_robots()
    return
  end
  position.x = ((position.x / count))-- + our_position.x) / 2
  position.y = ((position.y / count))-- + our_position.y) / 2
  self.entity.autopilot_destination = position
  self:propose_tick_update(math.random(10, 20))
  return true
end

function Companion:try_to_refuel()

  if not self:get_fuel_inventory().is_empty() then return end

  if self.auto_fuel and self:distance(self.player.position) <= follow_range then
    for k, item in pairs (get_fuel_items()) do
      if self:find_and_take_from_player(item) then
        return
      end
    end
  end

  return true
end

function Companion:update_state_flags()
  self.out_of_energy = self:try_to_refuel()
  self.is_in_combat = (game.tick - self.last_attack_tick) < 60
  self.is_on_low_health = self.entity.get_health_ratio() < 0.5
  self.is_busy_for_construction = self.is_in_combat or self:move_to_robot_average() or self.moving_to_destination
  self.is_getting_full = self:get_inventory()[16].valid_for_read
end

function Companion:propose_tick_update(ticks)
  if ticks < 1 then error("WTF?") end
  self.next_tick_update = math.min(math.ceil(ticks), (self.next_tick_update or math.huge))
end

function Companion:search_for_nearby_work()
  if not self.can_construct then return end
  local cell = self.entity.logistic_cell
  if not cell then return end
  local range = cell.construction_radius + 8
  local origin = self.entity.position
  local area = {{origin.x - range, origin.y - range}, {origin.x + range, origin.y + range}}
  --self:say("NICE")
  self:try_to_find_work(area)
end

function Companion:search_for_nearby_targets()
  if not self.can_attack then return end
  local range = 21 + 8
  local origin = self.entity.position
  local area = {{origin.x - range, origin.y - range}, {origin.x + range, origin.y + range}}
  --self:say("NICE")
  self:try_to_find_targets(area)
end

function Companion:update()

  if self.flagged_for_equipment_changed then
    self:check_equipment()
  end


  local was_busy = self.is_busy_for_construction
  local was_in_combat = self.is_in_combat

  self:update_state_flags()

  if was_busy and not self.is_busy_for_construction then
    --So we were building, and now we are finished, lets try to find some work nearby
    self:search_for_nearby_work()
  end

  if was_in_combat and not self.is_in_combat then
    --Same as above
    self:search_for_nearby_targets()
  end

  if self.is_getting_full or self.is_on_low_health or not (self.is_in_combat or self.is_busy_for_construction or self.moving_to_destination) then
    self:return_to_player()
  end

  self:schedule_next_update()

  --self:say("U")
end

local default_update_time = 60
function Companion:schedule_next_update()
  local ticks = self.next_tick_update or default_update_time
  local tick = game.tick + ticks
  script_data.tick_updates[tick] = script_data.tick_updates[tick] or {}
  script_data.tick_updates[tick][self.unit_number] = true
  --self:say(ticks)
  self.next_tick_update = nil
end

function Companion:say(string)
  self.entity.surface.create_entity{name = "tutorial-flying-text", position = {self.entity.position.x, self.entity.position.y - 2.5}, text = string or "??"}
end

function Companion:on_destroyed()

  if not script_data.companions[self.unit_number] then
    --On destroyed has already been called.
    return
  end

  self:clear_passengers()

  for k, robot in pairs (self.robots) do
    robot.destroy()
  end

  script_data.companions[self.unit_number] = nil
  local player_data = script_data.player_data[self.player.index]

  player_data.companions[self.unit_number] = nil

  if not next(player_data.companions) then
    script_data.player_data[self.player.index] = nil
  end

end

function Companion:distance(position)
  local source = self.entity.position
  local x2 = position[1] or position.x
  local y2 = position[2] or position.y
  return (((source.x - x2) ^ 2) + ((source.y - y2) ^ 2)) ^ 0.5
end

function Companion:get_inventory()
  local inventory = self.entity.get_inventory(defines.inventory.spider_trunk)
  inventory.sort_and_merge()
  return inventory
end

function Companion:get_fuel_inventory()
  local inventory = self.entity.get_fuel_inventory()
  inventory.sort_and_merge()
  return inventory
end

function Companion:insert_to_player_or_vehicle(stack)

  local inserted = self.player.insert(stack)
  if inserted > 0 then return inserted end

  if self.player.vehicle then
    return self.player.vehicle.insert(stack)
  end

  return 0

end

function Companion:try_to_shove_inventory()

  local inventory = self:get_inventory()
  local total_inserted = 0
  for k = 1, #inventory do
    local stack = inventory[k]
    if not (stack and stack.valid_for_read) then break end
    local inserted = self:insert_to_player_or_vehicle(stack)
    if inserted == 0 then
      self.player.print({"inventory-restriction.player-inventory-full", stack.prototype.localised_name, {"inventory-full-message.main"}})
      break
    else
      total_inserted = total_inserted + inserted
      if inserted == stack.count then
        stack.clear()
      else
        stack.count = stack.count - inserted
      end
    end
  end

  if total_inserted > 0 then
    self.entity.surface.create_entity
    {
      name = "inserter-beam",
      source = self.entity,
      target = self.player.character,
      target_position = self.player.position,
      force = self.entity.force,
      position = self.entity.position,
      duration = math.min(math.max(math.ceil(total_inserted / 5), 5), 60),
      max_length = follow_range + 4
    }
  end

  if self.flagged_for_mine then
    self.entity.mine
    {
      inventory = self.player.character and self.player.character.get_main_inventory() or nil,
      force = true,
      ignore_minable = true
    }
    self:on_destroyed()
  end
end

local stretch_bonus = 0
local stretch_modifier = 2
function Companion:return_to_player()

  if not self.player.valid then return end

  local distance = self:distance(self.player.position)
  --self:say(distance)
  if distance <= follow_range then
    self:try_to_shove_inventory()
  end

  if distance > 500 then
    self:teleport(self.player.position, self.entity.surface)
    return
  end

  local distance_boost = 1
  distance_boost = 1 + (distance/ 100)

  local follow_target = self.entity.follow_target

  if self.player.vehicle then
    if follow_target ~= self.player.vehicle then
      self.entity.follow_target = self.player.vehicle
    end
    self:set_speed((math.abs(self.player.vehicle.speed) + stretch_bonus) * stretch_modifier * distance_boost)
    return
  end

  if self.player.character then
    if follow_target ~= self.player.character then
      self.entity.follow_target = self.player.character
    end
    self:set_speed((self.player.character_running_speed + stretch_bonus) * stretch_modifier * distance_boost)
    return
  end


end

function Companion:on_spider_command_completed()
  self.moving_to_destination = nil
  local distance = self:distance(self.player.position)
  if distance <= follow_range then
    self:try_to_shove_inventory()
  end
end

function Companion:take_item(item, target)
  local inventory = self:get_inventory()

  local to_take_count

  local target_count = target.get_item_count(item.name)
  local stack_size = game.item_prototypes[item.name].stack_size

  if target_count <= (stack_size * 2) then
    to_take_count = math.min(target_count, math.ceil(stack_size / 2))
  else
    to_take_count = math.min(target_count, stack_size)
  end

  target_count = math.max(item.count, target_count)
  local removed = target.remove_item({name = item.name, count = to_take_count})
  if removed == 0 then return end
  self.entity.insert({name = item.name, count = removed})

  self.entity.surface.create_entity
  {
    name = "inserter-beam",
    source = self.entity,
    target = (target.is_player() and target.character) or nil,
    target_position = target.position,
    force = self.entity.force,
    position = self.entity.position,
    duration = math.min(math.max(math.ceil(removed / 5), 5), 60),
    max_length = follow_range + 4
  }

  return removed >= item.count
end


local angle = function(position_1, position_2)
  local d_x = (position_2[1] or position_2.x) - (position_1[1] or position_1.x)
  local d_y = (position_2[2] or position_2.y) - (position_1[2] or position_1.y)
  return math.atan2(d_y, d_x)
end

function Companion:get_offset(target_position, length, angle_adjustment)

    -- Angle in rads
    local angle = angle(self.entity.position, target_position)
    angle = angle + (math.pi / 2) + (angle_adjustment or 0)
    local x1 = (length * math.sin(angle))
    local y1 = (-length * math.cos(angle))

    return {x1, y1}
end

function Companion:set_attack_destination(position)
  self:set_speed(0)
  local self_position = self.entity.position
  local distance = self:distance(position) - 16

  local update = 30

  if math.abs(distance) > 2 then
    local offset = self:get_offset(position, distance, (distance < 0 and math.pi/4) or 0)
    self_position.x = self_position.x + offset[1]

    self_position.y = self_position.y + offset[2]
    self.entity.autopilot_destination = self_position
    self.moving_to_destination = true
    update = update + math.ceil(math.abs(distance) / 0.25)
    self:propose_tick_update(update)
  end

  self.last_attack_tick = game.tick
  self.is_in_combat = true
end

function Companion:set_job_destination(position, delay_update)
  self:set_speed(0)
  local self_position = self.entity.position
  local distance = self:distance(position) - 4

  local update = 50
  --if delay_update then update = update + 80 end

  if distance > 0 then
    local offset = self:get_offset(position, distance)
    self_position.x = self_position.x + offset[1]
    self_position.y = self_position.y + offset[2]
    self.entity.autopilot_destination = self_position
    self.moving_to_destination = true
    --update about half way there
    --update = update + math.ceil(distance / 0.5)
    self:propose_tick_update(update)
  end

  self.is_busy_for_construction = true
end

function Companion:attack(entity)
  --self:say("Attacking "..entity.name.. " "..self.entity.force.name.." "..entity.force.name)
  local position = self.entity.position
  for k, offset in pairs  {0, -0.25, 0.25} do
    local projectile = self.entity.surface.create_entity
    {
      name = "companion-projectile",
      position = {position.x, position.y - 1.5},
      speed = 0.05,
      force = self.entity.force,
      target = entity,
      max_range = 55
    }

    projectile.orientation = projectile.orientation + offset

    local beam = self.entity.surface.create_entity{name = "inserter-beam", source = self.entity, target = self.entity, position = {0,0}}
    beam.set_beam_target(projectile)
  end

  self:set_attack_destination(entity.position)
  self.last_attack_tick = game.tick
end

local ghost_types =
{
  ["entity-ghost"] = true,
  ["tile-ghost"] = true
}

local item_request_types =
{
  ["entity-ghost"] = true,
  ["item-request-proxy"] = true

}

local entities_with_force_type = {"unit", "character", "turret", "ammo-turret", "electric-turret", "fluid-turret", "radar", "unit-spawner", "spider-vehicle", "artillery-turret"}
function Companion:try_to_find_targets(search_area)

  local entities = self.entity.surface.find_entities_filtered
  {
    area = search_area,
    type = entities_with_force_type
  }

  local our_force = self.entity.force
  for k, entity in pairs (entities) do
    local force = entity.force
    if not (force == our_force or our_force.get_cease_fire(entity.force)) then
      self:set_attack_destination(entity.position)
    end
  end


end

function Companion:find_and_take_from_player(item)
  local count = self.player.get_item_count(item.name)
  if count >= item.count then
    if self:take_item(item, self.player) then
      return true
    end
  end

  if self.player.vehicle then
    local count = self.player.vehicle.get_item_count(item.name)
    if count >= item.count then
      if self:take_item(item, self.player.vehicle) then
        return true
      end
    end
  end

end

function Companion:try_to_find_work(search_area)

  local force = self.entity.force
  local entities = self.entity.surface.find_entities_filtered{area = search_area, force = force}
  local neutral

  local current_items = self:get_inventory().get_contents()
  local can_take_from_player = self:distance(self.player.position) <= follow_range

  local has_or_can_take = function(item)
    if current_items[item.name] or 0 >= item.count then
      return true
    end
    if not can_take_from_player then return end
    return self:find_and_take_from_player(item)
  end

  local attempted_ghost_names = {}
  local attempted_upgrade_names = {}
  local attempted_proxy_items = {}
  local repair_attempted = false
  local deconstruction_attempted = false
  local max_item_type_count = 10

  for k, entity in pairs (entities) do

    if max_item_type_count <= 0 then
      return
    end

    local entity_type = entity.type

    if not deconstruction_attempted and entity.is_registered_for_deconstruction(force) then
      deconstruction_attempted = true
      if not self.moving_to_destination then
        self:set_job_destination(entity.position, true)
      end
    end

    if ghost_types[entity_type] and entity.is_registered_for_construction()  then
      local ghost_name = entity.ghost_name
      if not attempted_ghost_names[ghost_name] then
        local item = entity.ghost_prototype.items_to_place_this[1]
        if has_or_can_take(item) then
          if not self.moving_to_destination then
            self:set_job_destination(entity.position, true)
          end
          max_item_type_count = max_item_type_count - 1
          attempted_ghost_names[ghost_name] = 1
        else
          attempted_ghost_names[ghost_name] = 0
        end
      end
      if item_request_types[entity_type] and attempted_ghost_names[ghost_name] == 1 then
        local items = entity.item_requests
        for name, item_count in pairs (items) do
          if not attempted_proxy_items[name] then
            attempted_proxy_items[name] = true
            if has_or_can_take({name = name, count = item_count}) then
              max_item_type_count = max_item_type_count - 1
            end
          end
        end
      end
    end

    if entity.is_registered_for_upgrade() then
      local upgrade_target = entity.get_upgrade_target()
      if not attempted_upgrade_names[upgrade_target.name] then
        if upgrade_target.name == entity.name then
          if not self.moving_to_destination then
            self:set_job_destination(entity.position, true)
          end
        else
          local item = upgrade_target.items_to_place_this[1]
          if has_or_can_take(item) then
            if not self.moving_to_destination then
              self:set_job_destination(entity.position, true)
            end
            max_item_type_count = max_item_type_count - 1
          end
        end
        attempted_upgrade_names[upgrade_target.name] = true
      end
    end

    if not repair_attempted and entity.is_registered_for_repair() then
      repair_attempted = true
      for k, item in pairs (get_repair_tools()) do
        if has_or_can_take(item) then
          if not self.moving_to_destination then
            self:set_job_destination(entity.position, true)
          end
          break
        end
      end
    end

    if entity_type == "item-request-proxy" and entity.is_registered_for_construction() then
      local items = entity.item_requests
      for name, item_count in pairs (items) do
        if not attempted_proxy_items[name] then
          attempted_proxy_items[name] = true
          if has_or_can_take({name = name, count = item_count}) then
            if not self.moving_to_destination then
              self:set_job_destination(entity.position, true)
            end
            max_item_type_count = max_item_type_count - 1
          end
        end
      end
    end

  end

  if self.moving_to_destination then
    --We have a job.
    return
  end

  local attempted_cliff_names = {}
  local neutral_entities = self.entity.surface.find_entities_filtered{area = search_area, force = "neutral", to_be_deconstructed = true}
  for k, entity in pairs (neutral_entities) do
    if entity.type == "cliff" then
      if not attempted_cliff_names[entity.name] and entity.is_registered_for_deconstruction(force) then
        local item_name = entity.prototype.cliff_explosive_prototype
        if has_or_can_take({name = item_name, count = 1}) then
          if not self.moving_to_destination then
            self:set_job_destination(entity.position, true)
          end
          max_item_type_count = max_item_type_count - 1
        end
        attempted_cliff_names[entity.name] = true
      end
    elseif not deconstruction_attempted and entity.is_registered_for_deconstruction(force) then
      deconstruction_attempted = true
      if not self.moving_to_destination then
        self:set_job_destination(entity.position, true)
      end
    end

  end

end

function Companion:on_player_placed_equipment(event)
  self.flagged_for_equipment_changed = true
  self:say("Equipment added")
end

function Companion:on_player_removed_equipment(event)
  self.flagged_for_equipment_changed = true
  self:say("Equipment removed")
end

local get_gui_by_tag
get_gui_by_tag = function(gui, tag)

  for k, v in pairs (gui.tags) do
    if v == tag then
      return gui
    end
  end

  for k, child in pairs (gui.children) do
    local gui = get_gui_by_tag(child, tag)
    if gui then
      return gui
    end
  end

end

function Companion:update_gui_based_on_settings(event)
  local player = game.get_player(event.player_index)
  if player ~= self.player then
    player.opened = nil
    self:say("DON'T TOUCH ME I BELONG TO "..self.player.name)
    return
  end

  local gui = player.gui.relative.companion_gui
  if not (gui and gui.valid) then
    make_player_gui(player)
    gui = player.gui.relative.companion_gui
  end

  local combat_mode_switch = get_gui_by_tag(gui, "combat_mode_switch")
  combat_mode_switch.switch_state = (self.active_combat and "right") or "left"

  local construction_mode_switch = get_gui_by_tag(gui, "construction_mode_switch")
  construction_mode_switch.switch_state = (self.active_construction and "right") or "left"

  local auto_refuel_checkbox = get_gui_by_tag(gui, "auto_refuel_checkbox")
  auto_refuel_checkbox.state = self.auto_fuel
end

function Companion:teleport(position, surface)
  self:clear_robots()
  self:clear_passengers()
  self:clear_speed_sticker()
  self.entity.teleport(
    {
      position.x + math.random(-follow_range, follow_range),
      position.y + math.random(-follow_range, follow_range),
    },
    surface
  )
  self:check_equipment()
  self:add_passengers()
  self:set_speed(self.speed)
end

function Companion:change_force(force)

  self:clear_passengers()

  self.entity.force = force
  for k, robot in pairs (self.robots) do
    if robot.valid then
      robot.force = force
    end
  end

  self:check_equipment()
  self:add_passengers()

end

local get_opened_companion = function(player_index)
  local player = game.get_player(player_index)
  if not player then return end

  if player.opened_gui_type ~= defines.gui_type.entity then return end

  local opened = player.opened
  if not (opened and opened.valid) then return end

  return get_companion(opened.unit_number)
end

local companion_gui_functions =
{
  return_home = function(event)
    local companion = get_opened_companion(event.player_index)
    if not companion then return end
    companion:say("SIR YES SIR")
    companion.flagged_for_mine = true
    companion:return_to_player()
  end,
  combat_mode_switch = function(event)
    local companion = get_opened_companion(event.player_index)
    if not companion then return end
    local switch = event.element
    companion.active_combat = switch.switch_state == "right"
  end,
  construction_mode_switch = function(event)
    local companion = get_opened_companion(event.player_index)
    if not companion then return end
    local switch = event.element
    companion.active_construction = switch.switch_state == "right"
  end,
  auto_refuel_checkbox = function(event)
    local companion = get_opened_companion(event.player_index)
    if not companion then return end
    local checkbox = event.element
    companion.auto_fuel = checkbox.state
  end
}

local on_gui_event = function(event)
  local gui = event.element
  if not (gui and gui.valid) then return end
  local function_name = gui.tags.companion_function
  if not function_name then return end
  local action = companion_gui_functions[function_name]
  if action then action(event) end
end

local on_built_entity = function(event)
  local entity = event.created_entity
  if not (entity and entity.valid) then return end

  if entity.name ~= "companion" then
    return
  end

  local player = event.player_index and game.get_player(event.player_index)
  if not player then return end

  Companion.new(entity, player)

  make_player_gui(player)

end

local on_entity_destroyed = function(event)
  local companion = get_companion(event.unit_number)
  if not companion then return end
  companion:on_destroyed()
end

local check_companion_updates = function(event)
  local tick_updates = script_data.tick_updates[event.tick]
  if not tick_updates then return end
  for unit_number, bool in pairs (tick_updates) do
    local companion = get_companion(unit_number)
    if companion then
      companion:update()
    end
  end
  script_data.tick_updates[event.tick] = nil
end

local search_offsets = {}
local search_refresh = nil
local search_distance = 100
local search_divisions = 7

local setup_search_offsets = function()
  local r = search_distance / search_divisions
  search_offsets = {}
  for y = 0, (search_divisions - 1) do
    local offset_y = (y - (search_divisions / 2)) * r
    for x = 0, (search_divisions - 1) do
      local offset_x = (x - (search_divisions / 2)) * r
      local area = {{offset_x, offset_y}, {offset_x + r, offset_y + r}}
      table.insert(search_offsets, area)
    end
  end

  --table.sort(search_offsets, function(a, b) return distance(a[1], {0,0}) < distance(b[1], {0,0}) end)

  for k, v in pairs (search_offsets) do
    local i = (((k * 19) ^ 2) % #search_offsets) + 1
    search_offsets[k], search_offsets[i] = search_offsets[i], search_offsets[k]
  end

  search_refresh = #search_offsets
end
setup_search_offsets()

local perform_job_search = function(player, player_data)

  local free_companion
  for unit_number, bool in pairs (player_data.companions) do
    local companion = get_companion(unit_number)
    if companion and not companion.out_of_energy and not companion.is_busy_for_construction and companion.active_construction and companion.can_construct then
      free_companion = companion
      break
    end
  end
  if not free_companion then return end

  player_data.last_job_search_offset = player_data.last_job_search_offset + 1
  local area = search_offsets[player_data.last_job_search_offset]
  if not area then
    player_data.last_job_search_offset = 0
    return
  end

  local position = player.position
  local search_area = {{area[1][1] + position.x, area[1][2] + position.y}, {area[2][1] + position.x, area[2][2] + position.y}}

  free_companion:try_to_find_work(search_area)

  --player.surface.create_entity{name = "flying-text", position = search_area[1], text = player_data.last_job_search_offset}
  --player.surface.create_entity{name = "flying-text", position = search_area[2], text = player_data.last_job_search_offset}

end

local perform_attack_search = function(player, player_data)

  local free_companion
  for unit_number, bool in pairs (player_data.companions) do
    local companion = get_companion(unit_number)
    if companion and not companion.out_of_energy and not companion.is_in_combat and companion.active_combat and companion.can_attack then
      free_companion = companion
      break
    end
  end
  if not free_companion then return end

  player_data.last_attack_search_offset = player_data.last_attack_search_offset + 1
  local area = search_offsets[player_data.last_attack_search_offset]
  if not area then
    player_data.last_attack_search_offset = 0
    return
  end

  local position = player.position
  local search_area = {{area[1][1] + position.x, area[1][2] + position.y}, {area[2][1] + position.x, area[2][2] + position.y}}

  free_companion:try_to_find_targets(search_area)

  --player.surface.create_entity{name = "flying-text", position = search_area[1], text = player_data.last_attack_search_offset}
  --player.surface.create_entity{name = "flying-text", position = search_area[2], text = player_data.last_attack_search_offset}

end

local job_mod = 3
local check_job_search = function(event)
  for k, player in pairs (game.connected_players) do
    if (k + event.tick) % job_mod == 0 then
      local player_data = script_data.player_data[player.index]
      if player_data then
        perform_job_search(player, player_data)
        perform_attack_search(player, player_data)
      end
    end
  end
end

local on_tick = function(event)
  check_job_search(event)
  check_companion_updates(event)
end

local on_spider_command_completed = function(event)
  local spider = event.vehicle
  local companion = get_companion(spider.unit_number)
  if not companion then return end
  companion:on_spider_command_completed()
end


--[[effect_id :: string: The effect_id specified in the trigger effect.
surface_index :: uint: The surface the effect happened on.
source_position :: Position (optional)
source_entity :: LuaEntity (optional)
target_position :: Position (optional)
target_entity :: LuaEntity (optional)]]
local on_script_trigger_effect = function(event)
  local id = event.effect_id
  if id ~= "companion-attack" then return end

  local source_entity = event.source_entity
  if not (source_entity and source_entity.valid) then
    return
  end

  local target_entity = event.target_entity
  if not (target_entity and target_entity.valid) then
    return
  end

  local companion = get_companion(source_entity.unit_number)
  if companion then
    companion:attack(target_entity)
  end


end

local on_player_placed_equipment = function(event)

  local player = game.get_player(event.player_index)
  if player.opened_gui_type ~= defines.gui_type.entity then return end


  local opened = player.opened
  if not (opened and opened.valid) then return end

  local companion = get_companion(opened.unit_number)
  if not companion then return end

  companion:on_player_placed_equipment(event)

end

local on_player_removed_equipment = function(event)
  local player = game.get_player(event.player_index)
  if player.opened_gui_type ~= defines.gui_type.entity then return end

  local opened = player.opened
  if not (opened and opened.valid) then return end

  local companion = get_companion(opened.unit_number)
  if not companion then return end

  companion:on_player_removed_equipment(event)

end

local on_entity_settings_pasted = function(event)

  local entity = event.destination
  if not (entity and entity.valid) then return end

  local companion = get_companion(entity.unit_number)
  if not companion then return end

  companion.flagged_for_equipment_changed = true

  local source = event.source
  if not (source and source.valid) then return end

  local source_companion = get_companion(source.unit_number)
  if not source_companion then return end

  companion.active_combat = source_companion.active_combat
  companion.active_construction = source_companion.active_construction
  companion.auto_fuel = source_companion.auto_fuel

end

local on_gui_opened = function(event)

  local player = game.get_player(event.player_index)
  if player.opened_gui_type ~= defines.gui_type.entity then return end

  local opened = player.opened
  if not (opened and opened.valid) then return end

  local companion = get_companion(opened.unit_number)
  if not companion then return end

  companion:update_gui_based_on_settings(event)
end

local on_player_changed_surface = function(event)
  local player_data = script_data.player_data[event.player_index]
  if not player_data then return end

  local player = game.get_player(event.player_index)
  local surface = player.surface
  local position = player.position

  for unit_number, bool in pairs (player_data.companions) do
    local companion = get_companion(unit_number)
    if companion then
      companion:teleport(position, surface)
    end
  end

end

local on_player_left_game = function(event)
  local player_data = script_data.player_data[event.player_index]
  if not player_data then return end

  local surface = get_secret_surface()
  local position = {x = 0, y = 0}

  for unit_number, bool in pairs (player_data.companions) do
    local companion = get_companion(unit_number)
    if companion then
      companion:teleport(position, surface)
    end
  end
end

local on_player_joined_game = function(event)
  local player_data = script_data.player_data[event.player_index]
  if not player_data then return end

  local player = game.get_player(event.player_index)
  local surface = player.surface
  local position = player.position

  for unit_number, bool in pairs (player_data.companions) do
    local companion = get_companion(unit_number)
    if companion then
      companion:teleport(position, surface)
    end
  end

end

local on_player_changed_force = function(event)
  local player_data = script_data.player_data[event.player_index]
  if not player_data then return end

  local player = game.get_player(event.player_index)
  local force = player.force
  for unit_number, bool in pairs (player_data.companions) do
    local companion = get_companion(unit_number)
    if companion then
      companion:change_force(force)
    end
  end
end

local lib = {}

lib.events =
{
  [defines.events.on_built_entity] = on_built_entity,
  [defines.events.on_entity_destroyed] = on_entity_destroyed,
  [defines.events.on_tick] = on_tick,
  [defines.events.on_spider_command_completed] = on_spider_command_completed,
  [defines.events.on_script_trigger_effect] = on_script_trigger_effect,
  [defines.events.on_player_placed_equipment] = on_player_placed_equipment,
  [defines.events.on_player_removed_equipment] = on_player_removed_equipment,
  [defines.events.on_entity_settings_pasted] = on_entity_settings_pasted,
  [defines.events.on_player_changed_surface] = on_player_changed_surface,
  [defines.events.on_player_left_game] = on_player_left_game,
  [defines.events.on_player_joined_game] = on_player_joined_game,
  [defines.events.on_player_changed_force] = on_player_changed_force,

  [defines.events.on_gui_checked_state_changed] = on_gui_event,
  [defines.events.on_gui_click] = on_gui_event,
  [defines.events.on_gui_elem_changed] = on_gui_event,
  [defines.events.on_gui_selected_tab_changed] = on_gui_event,
  [defines.events.on_gui_selection_state_changed] = on_gui_event,
  [defines.events.on_gui_switch_state_changed] = on_gui_event,
  [defines.events.on_gui_text_changed] = on_gui_event,
  [defines.events.on_gui_value_changed] = on_gui_event,

  --[defines.events.on_gui_confirmed] = on_gui_event,
  --[defines.events.on_gui_closed] = on_gui_event,
  --[defines.events.on_gui_location_changed] = on_gui_event,
  [defines.events.on_gui_opened] = on_gui_opened,
}

lib.on_load = function()
  script_data = global.companion or script_data
  for unit_number, companion in pairs(script_data.companions) do
    setmetatable(companion, Companion.metatable)
  end
end

lib.on_init = function()
  global.companion = global.companion or script_data
  if remote.interfaces["freeplay"] then
    local items = remote.call("freeplay", "get_created_items")
    items["companion"] = 2
    items["companion-roboport-equipment"] = 2
    items["companion-reactor-equipment"] = 2
    items["companion-defense-equipment"] = 2
    items["companion-shield-equipment"] = 2
    remote.call("freeplay", "set_created_items", items)
  end
  local force = game.forces.player
  if force.max_failed_attempts_per_tick_per_construction_queue == 1 then
    force.max_failed_attempts_per_tick_per_construction_queue = 4
  end
  if force.max_successful_attempts_per_tick_per_construction_queue == 3 then
    force.max_successful_attempts_per_tick_per_construction_queue = 8
  end
end

lib.on_configuration_changed = function()
  for player_index, player_data in pairs (script_data.player_data) do

    if player_data.last_search_offset then
      player_data.last_job_search_offset = player_data.last_search_offset
      player_data.last_attack_search_offset = player_data.last_search_offset
      player_data.last_search_offset = nil
    end

    local player = game.get_player(player_index)
    if player then
      local gui = player.gui.relative
      if gui.companion_gui then
        gui.companion_gui.destroy()
      end
    end

  end
end

return lib
