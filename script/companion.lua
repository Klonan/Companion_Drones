local util = require("util")
local follow_range = 12
local companion_update_interval = 17
local base_speed = 0.25
local build_speed = 0.30
local sticker_life = 100

local script_data =
{
  companions = {},
  active_companions = {},
  player_data = {},
  search_schedule = {},
  specific_job_search_queue = {}
}

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
    if item.fuel_value > 0 and item.fuel_category == "chemical" then
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
    return
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


local get_speed_boost = function(burner)
  local burning = burner.currently_burning
  if not burning then return 1 end
  return burning.fuel_top_speed_multiplier
end

local rotate_vector = function(vector, orientation)
  local x = vector[1] or vector.x
  local y = vector[2] or vector.y
  local angle = (orientation) * math.pi * 2
  return
  {
    x = (math.cos(angle) * x) - (math.sin(angle) * y),
    y = (math.sin(angle) * x) + (math.cos(angle) * y)
  }
end

local get_player_speed = function(player, boost)
  local boost = boost or 1.0
  if player.vehicle then
    return math.abs(player.vehicle.speed) * boost
  end

  if player.character then
    return player.character_running_speed * boost
  end

  return 0.3

end

local adjust_follow_behavior = function(player)
  local player_data = script_data.player_data[player.index]
  if not player_data then return end
  local count = 0
  local guys = {}

  local surface = player.surface

  for unit_number, bool in pairs (player_data.companions) do
    local companion = get_companion(unit_number)
    if companion then
      if not companion.active and (companion.entity.surface == surface) then
        count = count + 1
        guys[count] = companion
      end
    end
  end

  if count == 0 then return end

  local reach = player.reach_distance - 2
  local length = math.min(5 + (count * 0.33), reach)
  if count == 1 then length = 2 end
  local dong = 0.75 + (0.5 / count)
  local shift = {x = 0, y =0}
  local speed = get_player_speed(player)
  if player.vehicle then
    local orientation = player.vehicle.orientation
    dong = dong + orientation
    shift = rotate_vector({0, -speed * 15}, orientation)
  elseif player.character then
    local walking_state = player.character.walking_state
    if walking_state.walking then
      shift = rotate_vector({0, -speed * 15}, walking_state.direction / 8)
    end
  end

  local offset = {length, 0}
  local position = player.position
  for k, companion in pairs (guys) do
    local angle = (k / count) + dong
    local follow_offset = rotate_vector(offset, angle)
    follow_offset.x = follow_offset.x + shift.x
    follow_offset.y = follow_offset.y + shift.y
    local target = companion.entity.follow_target
    if not (target and target.valid) then
      if player.character then
        companion.entity.follow_target = player.character
      else
        companion.entity.autopilot_destination = {position.x + follow_offset.x, position.y + follow_offset.y}
      end
    end
    companion.entity.follow_offset = follow_offset
    companion:set_speed(speed + companion:get_distance_boost(companion.entity.autopilot_destination))
    companion:try_to_refuel()
  end
end

local Companion = {}
Companion.metatable = {__index = Companion}

Companion.new = function(entity, player)

  local player_data = script_data.player_data[player.index]
  if not player_data then
    player_data =
    {
      companions = {},
      last_job_search_offset = 0,
      last_attack_search_offset = 0
    }
    script_data.player_data[player.index] = player_data
    player.set_shortcut_available("companion-attack-toggle", true)
    player.set_shortcut_toggled("companion-attack-toggle", true)
    player.set_shortcut_available("companion-construction-toggle", true)
    player.set_shortcut_toggled("companion-construction-toggle", true)
  end
  player_data.companions[entity.unit_number] = true

  local companion =
  {
    entity = entity,
    player = player,
    unit_number = entity.unit_number,
    robots = {},
    flagged_for_equipment_changed = true,
    last_attack_tick = 0,
    speed = 0
  }

  setmetatable(companion, Companion.metatable)
  script_data.companions[entity.unit_number] = companion
  script.register_on_entity_destroyed(entity)

  companion:try_to_refuel()
  companion:set_active()

end

function Companion:set_robot_stack()
  local inventory = self:get_inventory()
  if not inventory.set_filter(21,"companion-construction-robot") then
    inventory[21].clear()
    inventory.set_filter(21,"companion-construction-robot")
  end

  if self.can_construct then
    inventory[21].set_stack({name = "companion-construction-robot", count = 100})
  else
    inventory[21].clear()
  end

end


function Companion:clear_robot_stack()
  local inventory = self:get_inventory()
  if not inventory.set_filter(21,"companion-construction-robot") then
    inventory[21].clear()
    inventory.set_filter(21,"companion-construction-robot")
  end
  inventory[21].clear()
end

function Companion:set_active()
  self:set_robot_stack()
  self.flagged_for_equipment_changed = true
  local mod = self.unit_number % companion_update_interval
  local list = script_data.active_companions[mod]
  if not list then
    list = {}
    script_data.active_companions[mod] = list
  end
  list[self.unit_number] = true
  self.active = true
  self:set_speed(build_speed * get_speed_boost(self.entity.burner))
  adjust_follow_behavior(self.player)
end

function Companion:clear_active()
  if not self.active then return end
  local mod = self.unit_number % companion_update_interval
  local list = script_data.active_companions[mod]
  if not list then
    error("Wtf?")
    return
  end
  list[self.unit_number] = nil
  if not next(list) then
    script_data.active_companions[mod] = nil
  end
  self.active = false
  self:clear_robots()
  adjust_follow_behavior(self.player)
end

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

function Companion:get_distance_boost(position)

  local distance = self:distance(position)
  return (distance / 50)

end

function Companion:set_speed(speed)
  if self.entity.stickers then
    --self:say(#self.entity.stickers)
  end
  if speed == self.speed then return end
  self.speed = speed
  --self:say(speed)
  local ratio = speed/(base_speed * get_speed_boost(self.entity.burner))
  --self:say(ratio)
  if ratio <= 1 then
    self:clear_speed_sticker()
  else
    local sticker = self:get_speed_sticker()
    sticker.time_to_live = 1 + ((sticker_life/10) * ratio)
  end
  --game.print(self.speed.." - "..self.entity.speed)
end

function Companion:get_speed()
  return self.speed
end

function Companion:get_grid()
  return self.entity.grid
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
  self.can_construct = max_robots > 0
  if self.can_construct then
    self:set_robot_stack()
  else
    self:clear_robots()
  end


  self.can_attack = false

  for k, equipment in pairs (grid.equipment) do
    if equipment.type == "active-defense-equipment" then
      self.can_attack = true
      break
    end
  end

end

function Companion:robot_spawned(robot)
  self:set_active()
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

function Companion:clear_robots()
  for k, robot in pairs (self.robots) do
    if robot.valid then
      robot.mine
      {
        inventory = self:get_inventory(),
        force = true,
        ignore_minable = true
      }
    end
    self.robots[k] = nil
  end
  self:clear_robot_stack()
end

function Companion:move_to_robot_average()
  --if self.moving_to_destination then return end
  if not next(self.robots) then return end

  local position = {x = 0, y = 0}
  local our_position = self.entity.position
  local count = 0
  for k, robot in pairs (self.robots) do
    if robot.valid then
      local robot_position = robot.position
      position.x = position.x + robot_position.x
      position.y = position.y + robot_position.y
      count = count + 1
    else
      self.robots[k] = nil
    end
  end
  if count == 0 then
    return
  end
  position.x = ((position.x / count))-- + our_position.x) / 2
  position.y = ((position.y / count))-- + our_position.y) / 2
  self.entity.autopilot_destination = position
  return true
end

function Companion:try_to_refuel()

  if not self:get_fuel_inventory().is_empty() or self.entity.energy > 0 then
    return
  end

  if self:distance(self.player.position) <= follow_range then
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

function Companion:search_for_nearby_work()
  if not self:player_wants_construction() then return end
  if not self.can_construct then return end
  local cell = self.entity.logistic_cell
  if not cell then return end
  local range = cell.construction_radius + 16
  local origin = self.entity.position
  local area = {{origin.x - range, origin.y - range}, {origin.x + range, origin.y + range}}
  --self:say("NICE")
  self:try_to_find_work(area)
end

function Companion:search_for_nearby_targets()
  if not self:player_wants_attack() then return end
  if not self.can_attack then return end
  local range = 32
  local origin = self.entity.position
  local area = {{origin.x - range, origin.y - range}, {origin.x + range, origin.y + range}}
  --self:say("NICE")
  self:try_to_find_targets(area)
end

function Companion:is_busy()
  return self.is_in_combat or self.is_busy_for_construction or self.moving_to_destination
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

  if self.is_getting_full or self.is_on_low_health or not self:is_busy() then
    self.moving_to_destination = nil
    self:return_to_player()
  end

  --self:say("U")
end

function Companion:say(string)
  self.entity.surface.create_entity{name = "tutorial-flying-text", position = {self.entity.position.x, self.entity.position.y - 2.5}, text = string or "??"}
end

function Companion:on_destroyed()

  if not script_data.companions[self.unit_number] then
    --On destroyed has already been called.
    return
  end

  for k, robot in pairs (self.robots) do
    robot.destroy()
  end

  script_data.companions[self.unit_number] = nil
  local player_data = script_data.player_data[self.player.index]

  player_data.companions[self.unit_number] = nil

  if not next(player_data.companions) then
    script_data.player_data[self.player.index] = nil
    self.player.set_shortcut_available("companion-attack-toggle", false)
    self.player.set_shortcut_toggled("companion-attack-toggle", false)
    self.player.set_shortcut_available("companion-construction-toggle", false)
    self.player.set_shortcut_toggled("companion-construction-toggle", false)
  end

  adjust_follow_behavior(self.player)
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
    inserted = self.player.vehicle.insert(stack)
    if inserted > 0 then return inserted end
    if self.player.vehicle.train then
      inserted = self.player.vehicle.train.insert(stack)
      if inserted > 0 then return inserted end
    end
  end

  return 0

end

function Companion:try_to_shove_inventory()
  local inventory = self:get_inventory()
  local total_inserted = 0
  for k = 1, 20 do
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
      duration = math.min(math.max(math.ceil(total_inserted / 5), 10), 60),
      max_length = follow_range + 4
    }
  end

end

function Companion:has_items()
  return self:get_inventory()[1].valid_for_read
end

function Companion:can_go_inactive()
  if self.out_of_energy then return end
  if self:is_busy() then return end
  if self:has_items() then return end
  if self:distance(self.player.position) > follow_range then return end
  return true
end

function Companion:return_to_player()

  if not self.player.valid then return end

  self.moving_to_destination = nil
  local distance = self:distance(self.player.position)

  if distance <= follow_range then
    self:try_to_shove_inventory()
    if not (self.entity.valid) then return end
  end

  if distance > 500 then
    self:teleport(self.player.position, self.entity.surface)
  end

  if self:can_go_inactive() then
    self:clear_active()
    return
  end

  self:set_speed(math.max(build_speed, get_player_speed(self.player, 1.2)))

  if self.player.character then
    self.entity.follow_target = self.player.character
    return
  end

  self.entity.autopilot_destination = self.player.position


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
    duration = math.min(math.max(math.ceil(removed / 5), 10), 60),
    max_length = follow_range + 4
  }

  return removed >= item.count
end

function Companion:take_item_from_train(item, train)
  local inventory = self:get_inventory()

  local to_take_count

  local target_count = train.get_item_count(item.name)
  local stack_size = game.item_prototypes[item.name].stack_size

  if target_count <= (stack_size * 2) then
    to_take_count = math.min(target_count, math.ceil(stack_size / 2))
  else
    to_take_count = math.min(target_count, stack_size)
  end

  target_count = math.max(item.count, target_count)
  local removed = train.remove_item({name = item.name, count = to_take_count})
  if removed == 0 then return end

  self.entity.insert({name = item.name, count = removed})

  self.entity.surface.create_entity
  {
    name = "inserter-beam",
    source = self.entity,
    target = self.player.character,
    target_position = self.player.position,
    force = self.entity.force,
    position = self.entity.position,
    duration = math.min(math.max(math.ceil(removed / 5), 10), 60),
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
  local self_position = self.entity.position
  local distance = self:distance(position) - 16

  if math.abs(distance) > 2 then
    local offset = self:get_offset(position, distance, (distance < 0 and math.pi/4) or 0)
    self_position.x = self_position.x + offset[1]
    self_position.y = self_position.y + offset[2]
    self.moving_to_destination = true
    self.entity.autopilot_destination = self_position
  end

  self.last_attack_tick = game.tick
  self.is_in_combat = true
  self:set_active()
end

function Companion:set_job_destination(position)
  local self_position = self.entity.position
  local distance = self:distance(position) - 4

  if math.abs(distance) > 2 then
    local offset = self:get_offset(position, distance)
    self_position.x = self_position.x + offset[1]
    self_position.y = self_position.y + offset[2]
    self.moving_to_destination = true
    self.entity.autopilot_destination = self_position
  end

  self.is_busy_for_construction = true
  self:set_active()
end

function Companion:player_wants_attack()
  return self.player.is_shortcut_toggled("companion-attack-toggle")
end

function Companion:player_wants_construction()
  return self.player.is_shortcut_toggled("companion-construction-toggle")
end

function Companion:attack(entity)

  if not self:player_wants_attack() then return end

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
    if not entity.valid then break end
    local force = entity.force
    if not (force == our_force or force.name == "neutral" or our_force.get_cease_fire(entity.force)) then
      self:set_attack_destination(entity.position)
      return
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

  local vehicle = self.player.vehicle
  if vehicle then
    local count = vehicle.get_item_count(item.name)
    if count >= item.count then
      if self:take_item(item, vehicle) then
        return true
      end
    end
    local train = vehicle.train
    if train then
      local count = train.get_item_count(item.name)
      if count >= item.count then
        if self:take_item_from_train(item, train) then
          return true
        end
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

    if not entity.valid then break end

    local entity_type = entity.type

    if not deconstruction_attempted and entity.is_registered_for_deconstruction(force) then
      if entity.type ~= "vehicle" or entity.speed < 0.4 then
        deconstruction_attempted = true
        if not self.moving_to_destination then
          self:set_job_destination(entity.position)
        end
      end
    end


    if ghost_types[entity_type] and entity.is_registered_for_construction()  then
      local ghost_name = entity.ghost_name
      if not attempted_ghost_names[ghost_name] then
        local item = entity.ghost_prototype.items_to_place_this[1]
        if has_or_can_take(item) then
          if not self.moving_to_destination then
            self:set_job_destination(entity.position)
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
            self:set_job_destination(entity.position)
          end
        else
          local item = upgrade_target.items_to_place_this[1]
          if has_or_can_take(item) then
            if not self.moving_to_destination then
              self:set_job_destination(entity.position)
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
            self:set_job_destination(entity.position)
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
              self:set_job_destination(entity.position)
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
    if not entity.valid then break end
    if entity.type == "cliff" then
      if not attempted_cliff_names[entity.name] and entity.is_registered_for_deconstruction(force) then
        local item_name = entity.prototype.cliff_explosive_prototype
        if has_or_can_take({name = item_name, count = 1}) then
          if not self.moving_to_destination then
            self:set_job_destination(entity.position)
          end
          max_item_type_count = max_item_type_count - 1
        end
        attempted_cliff_names[entity.name] = true
      end
    elseif not deconstruction_attempted and entity.is_registered_for_deconstruction(force) then
      deconstruction_attempted = true
      if not self.moving_to_destination then
        self:set_job_destination(entity.position)
      end
    end

  end

end

function Companion:on_player_placed_equipment(event)
  self:set_active()
  --self:say("Equipment added")
end

function Companion:on_player_removed_equipment(event)
  self:set_active()
  --self:say("Equipment removed")
end

function Companion:teleport(position, surface)
  self:clear_robots()
  self:clear_speed_sticker()

  self.entity.teleport(position, surface)
  self:set_active()
  self:return_to_player()
end

function Companion:change_force(force)

  self.entity.force = force
  for k, robot in pairs (self.robots) do
    if robot.valid then
      robot.force = force
    end
  end

  self:check_equipment()

end

local get_opened_companion = function(player_index)
  local player = game.get_player(player_index)
  if not player then return end

  if player.opened_gui_type ~= defines.gui_type.entity then return end

  local opened = player.opened
  if not (opened and opened.valid) then return end

  return get_companion(opened.unit_number)
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

end

local on_entity_destroyed = function(event)
  local companion = get_companion(event.unit_number)
  if not companion then return end
  companion:on_destroyed()
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
    local i = (((k * 87)) % #search_offsets) + 1
    search_offsets[k], search_offsets[i] = search_offsets[i], search_offsets[k]
  end

  search_refresh = #search_offsets
end
setup_search_offsets()

local get_free_companion_for_construction = function(player_data)
  for unit_number, bool in pairs (player_data.companions) do
    local companion = get_companion(unit_number)
    if companion and (not companion.active) and companion.can_construct and not companion:move_to_robot_average() then
      return companion
    end
  end
end

local perform_job_search = function(player, player_data)

  if not player.is_shortcut_toggled("companion-construction-toggle") then return end

  local free_companion = get_free_companion_for_construction(player_data)
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

  if not player.is_shortcut_toggled("companion-attack-toggle") then return end

  local free_companion
  for unit_number, bool in pairs (player_data.companions) do
    local companion = get_companion(unit_number)
    if companion and not companion.active and companion.can_attack then
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

local process_specific_job_queue = function(player_index, player_data)

  local areas = script_data.specific_job_search_queue[player_index]
  local i, area = next(areas)

  if not i then
    script_data.specific_job_search_queue[player_index] = nil
    return
  end

  local free_companion = get_free_companion_for_construction(player_data)
  if not free_companion then
    return
  end

  --free_companion:say(i)
  --free_companion.entity.surface.create_entity{name = "flying-text", position = area[1], text = i}
  --free_companion.entity.surface.create_entity{name = "flying-text", position = area[2], text = i}
  if free_companion:distance(area[1]) < 250 then
    free_companion:try_to_find_work(area)
  end

  areas[i] = nil

end

local job_mod = 5
local check_job_search = function(event)

  if not next(script_data.player_data) then return end

  local job_search_queue = script_data.specific_job_search_queue
  local players = game.players
  for player_index, player_data in pairs(script_data.player_data) do
    if (player_index + event.tick) % job_mod == 0 then
      local player = players[player_index]
      if player.connected then
        local specific_areas = job_search_queue[player_index]
        if specific_areas then
          process_specific_job_queue(player_index, player_data)
        else
          perform_job_search(player, player_data)
        end
        perform_attack_search(player, player_data)
      end
    end
  end

end

local update_active_companions = function(event)
  local mod = event.tick % companion_update_interval
  local list = script_data.active_companions[mod]
  if not list then return end
  for unit_number, bool in pairs (list) do
    local companion = get_companion(unit_number)
    if companion then
      companion:update()
    end
  end

end

local follow_mod = 97
local check_follow_update = function(event)
  if not next(script_data.player_data) then return end
  local players = game.players
  for player_index, player_data in pairs(script_data.player_data) do
    if (player_index + event.tick) % follow_mod == 0 then
      local player = players[player_index]
      if player.connected then
        adjust_follow_behavior(player)
      end
    end
  end
end

local on_tick = function(event)
  update_active_companions(event)
  check_job_search(event)
  check_follow_update(event)
end

local on_spider_command_completed = function(event)
  local spider = event.vehicle
  local companion = get_companion(spider.unit_number)
  if not companion then return end
  companion:on_spider_command_completed()
end

local companion_attack_trigger = function(event)

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

local companion_robot_spawned_trigger = function(event)

  local source_entity = event.source_entity
  if not (source_entity and source_entity.valid) then
    return
  end

  local network = source_entity.logistic_network
  if not network then return end

  local owner = network.cells[1].owner

  local companion = get_companion(owner.unit_number)
  if companion then
    companion:robot_spawned(source_entity)
  end
end

--[[effect_id :: string: The effect_id specified in the trigger effect.
surface_index :: uint: The surface the effect happened on.
source_position :: Position (optional)
source_entity :: LuaEntity (optional)
target_position :: Position (optional)
target_entity :: LuaEntity (optional)]]

local on_script_trigger_effect = function(event)
  local id = event.effect_id
  --game.print(id)
  if id == "companion-attack" then
    companion_attack_trigger(event)
    return
  end

  if id == "companion-robot-spawned" then
    companion_robot_spawned_trigger(event)
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

  companion:set_active()

end

local on_player_changed_surface = function(event)
  local player_data = script_data.player_data[event.player_index]
  if not player_data then return end

  local player = game.get_player(event.player_index)
  if not player.character then
    --For the space exploration satellite viewer thing...
    --If there is no character, lets just not go with the player.
    return
  end
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
      companion:teleport({position.x + math.random(-20, 20), position.y + math.random(-20, 20)}, surface)
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

local reschedule_companions = function()
  script_data.active_companions = {}
  for k, companion in pairs (script_data.companions) do
    companion.moving_to_destination = nil
    companion:set_active()
  end
end

local on_player_driving_changed_state = function(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  if not player.vehicle then return end

  if player.vehicle.name == "companion" then
    player.driving = false
  end

  adjust_follow_behavior(player)

end

local rebukes =
{
  "You're not the boss of me",
  "Get lost",
  "Not me pal",
  "Maybe later",
  "Go bother someone else",
  "I do my own thing",
  "Jog on"
}

local on_player_used_spider_remote = function(event)
  local vehicle = event.vehicle
  if not (vehicle and vehicle.valid) then return end
  local companion = get_companion(vehicle.unit_number)
  if not companion then return end

  companion:say(rebukes[math.random(#rebukes)])
  companion.entity.follow_target = nil
  companion.entity.autopilot_destination = nil

end

local on_player_mined_entity = function(event)
  local player = game.get_player(event.player_index)
  player.remove_item{name = "companion-construction-robot", count = 1000}
end

local recall_fighting_robots = function(player)
  local player_data = script_data.player_data[player.index]
  if not player_data then return end
  for unit_number, bool in pairs (player_data.companions) do
    local companion = get_companion(unit_number)
    if companion then
      if companion.is_in_combat then
        companion:return_to_player()
      end
    end
  end
end

local recall_constructing_robots = function(player)
  local player_data = script_data.player_data[player.index]
  if not player_data then return end
  for unit_number, bool in pairs (player_data.companions) do
    local companion = get_companion(unit_number)
    if companion then
      if next(companion.robots) then
        companion:clear_robots()
        companion:return_to_player()
      end
    end
  end
end

local on_lua_shortcut = function(event)
  local player = game.get_player(event.player_index)
  local name = event.prototype_name
  if name == "companion-attack-toggle" then
    player.set_shortcut_toggled(name, not player.is_shortcut_toggled(name))
    recall_fighting_robots(player)
  end
  if name == "companion-construction-toggle" then
    player.set_shortcut_toggled(name, not player.is_shortcut_toggled(name))
    recall_constructing_robots(player)
  end
end

local dissect_area_size = 32

local dissect_and_queue_area = function(player_index, area)
  local player_queue = script_data.specific_job_search_queue[player_index]
  if not player_queue then
    player_queue = {}
    script_data.specific_job_search_queue[player_index] = player_queue
  end

  local count = #player_queue
  for x = area.left_top.x, area.right_bottom.x, dissect_area_size do
    for y = area.left_top.y, area.right_bottom.y, dissect_area_size do
      table.insert(player_queue, (count > 0 and math.random(count)) or 1, {{x, y}, {x + dissect_area_size, y + dissect_area_size}})
      count = count + 1
    end
  end

end

local on_player_deconstructed_area = function(event)
  local player = game.get_player(event.player_index)

  if not player.is_shortcut_toggled("companion-construction-toggle") then
    return
  end

  dissect_and_queue_area(event.player_index, event.area)

end

local get_blueprint_area = function(player, offset)


  local entities = player.get_blueprint_entities()

  if not entities then
    -- Tile blueprint
    local r = dissect_area_size
    return {left_top = {x = offset.x - r, y = offset.y - r}, right_bottom = {x = offset.x + r, y = offset.y + r}}
  end

  local x1, y1, x2, y2
  for k, entity in pairs (entities) do
    local position = entity.position
    x1 = math.min(x1 or position.x, position.x)
    y1 = math.min(y1 or position.y, position.y)
    x2 = math.max(x2 or position.x, position.x)
    y2 = math.max(y2 or position.y, position.y)
  end

  -- I am lazy, not going to bother with rotations and flips...
  -- So just get the max area
  local lazy = true
  if lazy then
    local r = math.min(x2 - x1, y2 - y1)
    return {left_top = {x = offset.x - r, y = offset.y - r}, right_bottom = {x = offset.x + r, y = offset.y + r}}
  end

end

local on_pre_build = function(event)
  local player = game.get_player(event.player_index)

  if not (player.is_cursor_blueprint()) then return end

  if not player.is_shortcut_toggled("companion-construction-toggle") then
    return
  end

  -- I am lazy, not going to bother with rotations and flips...

  local area = get_blueprint_area(player, event.position)
  dissect_and_queue_area(event.player_index, area)


end

local on_player_created = function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  local surface = player.surface
  local position = player.position

  for k = 1, 2 do
    local entity = surface.create_entity
    {
      name = "companion",
      position = position,
      force = player.force
    }
    entity.insert("coal")
    entity.color = player.color
    local grid = entity.grid
    grid.put{name = "companion-reactor-equipment"}
    grid.put{name = "companion-defense-equipment"}
    grid.put{name = "companion-shield-equipment"}
    grid.put{name = "companion-roboport-equipment"}
    local companion = Companion.new(entity, player)
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
  [defines.events.on_entity_settings_pasted] = on_entity_settings_pasted,

  [defines.events.on_player_placed_equipment] = on_player_placed_equipment,
  [defines.events.on_player_removed_equipment] = on_player_removed_equipment,

  [defines.events.on_player_changed_surface] = on_player_changed_surface,
  [defines.events.on_player_left_game] = on_player_left_game,
  [defines.events.on_player_joined_game] = on_player_joined_game,
  [defines.events.on_player_created] = on_player_created,
  [defines.events.on_player_changed_force] = on_player_changed_force,
  [defines.events.on_player_driving_changed_state] = on_player_driving_changed_state,
  [defines.events.on_player_used_spider_remote] = on_player_used_spider_remote,

  [defines.events.on_player_mined_entity] = on_player_mined_entity,
  [defines.events.on_lua_shortcut] = on_lua_shortcut,
  [defines.events.on_player_deconstructed_area] = on_player_deconstructed_area,
  [defines.events.on_pre_build] = on_pre_build,
}

lib.on_load = function()
  script_data = global.companion or script_data
  for unit_number, companion in pairs(script_data.companions) do
    setmetatable(companion, Companion.metatable)
  end
end

lib.on_init = function()
  global.companion = global.companion or script_data
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

      if not player.is_shortcut_available("companion-attack-toggle") then
        player.set_shortcut_available("companion-attack-toggle", true)
        player.set_shortcut_toggled("companion-attack-toggle", true)
      end

      if not player.is_shortcut_available("companion-construction-toggle") then
        player.set_shortcut_available("companion-construction-toggle", true)
        player.set_shortcut_toggled("companion-construction-toggle", true)
      end
    else
      script_data.player_data[player_index] = nil
    end

  end

  for k, companion in pairs (script_data.companions) do
    companion.speed = companion.speed or 0
    companion:clear_passengers()
    companion.entity.minable = true
  end

  if script_data.tick_updates then
    script_data.tick_updates = nil
  end

  script_data.specific_job_search_queue = script_data.specific_job_search_queue or {}

  reschedule_companions()
end

local jetpack_remote =
{
  on_character_swapped = function(event)
    local new_character = event.new_character
    if not (new_character and new_character.valid) then return end
    if new_character.player then
      adjust_follow_behavior(new_character.player)
    end
  end
}

remote.add_interface("this is the unique name that I am making for the interface for the jetpack mod if you know what I mean", jetpack_remote)

commands.add_command("reschedule_companions", "If they get stuck or something", reschedule_companions)

return lib
