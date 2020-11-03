local util = require("util")

local script_data =
{
  companions = {},
  tick_updates = {},
  player_data = {},
  search_schedule = {}
}

local get_companion = function(unit_number)
  return unit_number and script_data.companions[unit_number]
end

local distance = function(position_1, position_2)
  local x1 = position_1[1] or position_1.x
  local y1 = position_1[2] or position_1.y
  local x2 = position_2[1] or position_2.x
  local y2 = position_2[2] or position_2.y
  return (((x2 - x1) * (x2 - x1)) + ((y2 - y1) * (y2 - y1))) ^ 0.5
end

local Companion = {}
Companion.metatable = {__index = Companion}

Companion.new = function(entity, player)
  local companion =
  {
    entity = entity,
    player = player,
    unit_number = entity.unit_number,
    robots = {}
  }
  setmetatable(companion, Companion.metatable)
  script_data.companions[entity.unit_number] = companion
  script.register_on_entity_destroyed(entity)
  companion:say("I love you!")
  entity.operable = false
  entity.minable = false
  local grid = companion:get_grid()
  grid.put{name = "companion-roboport-equipment"}

  for k, equipment in pairs (grid.equipment) do
    equipment.energy = equipment.max_energy
  end

  companion.flagged_for_equipment_changed = true
  companion:schedule_tick_update(1)
  companion:add_passengers()

  entity.color = player.color
  local player_data = script_data.player_data[player.index]
  if not player_data then
    player_data = {companions = {}, last_search_offset = 0}
    script_data.player_data[player.index] = player_data
  end
  player_data.companions[entity.unit_number] = companion
end

function Companion:get_grid()
  return self.entity.grid
end

function Companion:add_passengers()
  local driver = self.entity.surface.create_entity{name = "character", position = self.entity.position, force = self.entity.force}
  self.entity.set_driver(driver)
  self.driver = driver
  local passenger = self.entity.surface.create_entity{name = "character", position = self.entity.position, force = self.entity.force}
  self.entity.set_passenger(passenger)
  self.passenger = passenger
end

function Companion:check_robots()

  local grid = self:get_grid()

  local network = self.entity.logistic_network
  local max_robots = (network and network.robot_limit) or 0

  local robot_count = table_size(self.robots)

  if robot_count == max_robots then return end

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

end

function Companion:is_full()
  local stack = self:get_first_stack()
  if not (stack and stack.valid_for_read) then return end
  return stack.count == stack.prototype.stack_size
end

function Companion:move_to_robot_average()
  local position = {x = 0, y = 0}
  local our_position = self.entity.position
  local count = 0
  for k, robot in pairs (self.robots) do
    local robot_position = robot.position
    robot_position.y = robot_position.y + 2
    if util.distance(robot_position, our_position) > 0.5 then
      position.x = position.x + robot_position.x
      position.y = position.y + robot_position.y
      count = count + 1
    end
  end
  if count == 0 then return end
  position.x = ((position.x / count))-- + our_position.x) / 2
  position.y = ((position.y / count))-- + our_position.y) / 2

  if util.distance(our_position, position) < 2 then return end
  self.entity.autopilot_destination = position
end

function Companion:update_busy_state()
  self.is_busy = false
  local network = self.entity.logistic_network
  if network then
    self.is_busy = (network.available_construction_robots ~= table_size(self.robots))
  end
end

function Companion:is_getting_full()
  return self:get_inventory()[5].valid_for_read
end

function Companion:update()
  self:schedule_tick_update(math.random(7, 23))

  if self.moving_to_destination then
    return
  end

  self:update_busy_state()
  --self:say("U")

  if self.flagged_for_equipment_changed then
    self.flagged_for_equipment_changed = nil
    self:check_robots()
  end

  if self:is_getting_full() or not self.is_busy then
    self:return_to_player()
  else
    self:move_to_robot_average()
  end

end

function Companion:schedule_tick_update(ticks)
  local tick = game.tick + ticks
  script_data.tick_updates[tick] = script_data.tick_updates[tick] or {}
  script_data.tick_updates[tick][self.unit_number] = true
end

function Companion:say(string)
  self.entity.surface.create_entity{name = "tutorial-flying-text", position = {self.entity.position.x, self.entity.position.y - 2.5}, text = string or "??"}
end

function Companion:on_destroyed()
  if self.driver and self.driver.valid then
    self.driver.destroy()
    self.driver = nil
  end
  if self.passenger and self.passenger.valid then
    self.passenger.destroy()
    self.passenger = nil
  end

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

function Companion:on_player_placed_equipment(event)
  self.flagged_for_equipment_changed = true
  --self:schedule_tick_update(1)
  self:say("Equipment added")
end

function Companion:on_player_removed_equipment(event)
  self.flagged_for_equipment_changed = true
  --self:schedule_tick_update(1)
  self:say("Equipment removed")
end

function Companion:distance(position)
  local source = self.entity.position
  local x2 = position[1] or position.x
  local y2 = position[y] or position.y
  return (((source.x - x2) ^ 2) + ((source.y - y2) ^ 2)) ^ 0.5
end

function Companion:on_robot_built_entity(event)

  local entity = event.created_entity
  if not (entity and entity.valid) then return end

  if true then return end
  local distance = self:distance(entity.position)
  local duration = math.ceil((distance / 0.5) * 0.9)
  self.entity.surface.create_entity{name = "inserter-beam", position = self.entity.position, target = entity, source = self.entity, force = self.entity.force, source_offset = {0, -0}, duration = duration* 100}

  if distance > 5 then
    self.entity.autopilot_destination =
    {
      (entity.position.x + self.entity.position.x) / 2,
      (entity.position.y + self.entity.position.y) / 2
    }
  end
  self:schedule_tick_update((duration * 2) + 100)

end

function Companion:on_robot_built_tile(event)

  local tiles = event.tiles
  if not tiles and tiles[1] then return end

  if true then return end
  local distance = self:distance(tiles[1].position)
  local duration = math.ceil((distance / 0.5) * 0.9)
  for k, tile in pairs (tiles) do
    self.entity.surface.create_entity{name = "companion-build-beam", position = self.entity.position, target_position = tile.position, source = self.entity, force = self.entity.force, source_offset = {0, -0}, duration = duration}
  end

  if distance > 5 then
    self.entity.autopilot_destination =
    {
      (tiles[1].position.x + self.entity.position.x) / 2,
      (tiles[1].position.y + self.entity.position.y) / 2
    }
  end
  self:schedule_tick_update((duration * 2) + 100)

end

function Companion:on_robot_pre_mined(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  if true then return end
  local distance = self:distance(entity.position)
  local duration = math.ceil((distance / 0.5) * 0.9)
  self.entity.surface.create_entity{name = "inserter-beam", position = self.entity.position, target_position = entity.position, source = self.entity, force = self.entity.force, source_offset = {0, -0}, duration = duration * 30}
  self.entity.surface.play_sound{position = self.entity.position, path = "utility/drop_item"}

  if distance > 5 then
    self.entity.autopilot_destination =
    {
      (entity.position.x + self.entity.position.x) / 2,
      (entity.position.y + self.entity.position.y) / 2
    }
  end
  self:schedule_tick_update((duration * 2) + 100)

end

function Companion:get_inventory()
  local inventory = self.entity.get_inventory(defines.inventory.spider_trunk)
  inventory.sort_and_merge()
  return inventory
end

function Companion:get_first_stack()
  return self:get_inventory()[1]
end

function Companion:try_to_shove_inventory()
  local inventory = self:get_inventory()
  for k = 1, #inventory do
    local stack = inventory[k]
    if not (stack and stack.valid_for_read) then return end
    local inserted = self.player.insert(stack)
    if inserted == 0 then
      self.player.print({"inventory-restriction.player-inventory-full", stack.prototype.localised_name, {"inventory-full-message.main"}})
      return
    end

    if inserted == stack.count then
      stack.clear()
      return
    end

    stack.count = stack.count - inserted
  end
end

function Companion:return_to_player()

  if not self.player.valid then return end

  local target_position = self.player.position
  local walking_state = self.player.walking_state


  if self:distance(target_position) > 6 then
    self.entity.autopilot_destination = target_position
    --self:schedule_tick_update(math.random(60,100))
    return
  end

  if walking_state.walking then
    local orientation = walking_state.direction / 8
    local rads = (orientation - 0.5) * math.pi * 2
    local unit_number = self.unit_number
    local offset_x = math.random(-4, 4)
    local offset_y = math.random(-4, 4)
    local rotated_x = -2 * math.sin(rads)
    local rotated_y = 2 * math.cos(rads)
    target_position.x = target_position.x + offset_x + rotated_x
    target_position.y = target_position.y + offset_y + rotated_y
    self.entity.autopilot_destination = target_position
  end

  self:try_to_shove_inventory()

end

function Companion:on_spider_command_completed()
  self:update()
  self.moving_to_destination = nil
end

function Companion:take_item(item)
  local inventory = self:get_inventory()
  local count = math.max(math.min(game.item_prototypes[item.name].stack_size, math.floor(self.player.get_item_count(item.name) / 2)), item.count)
  local removed = self.player.remove_item({name = item.name, count = count})
  if removed == 0 then return end
  inventory.insert({name = item.name, count = removed})
  return removed >= item.count
end

function Companion:set_job_destination(position)
  self.entity.autopilot_destination = position
  self.moving_to_destination = true
  self.is_busy = true
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

  table.sort(search_offsets, function(a, b) return distance(a[1], {0,0}) < distance(b[1], {0,0}) end)
  search_refresh = #search_offsets
end
setup_search_offsets()

local perform_job_search = function(player, player_data)

  local free_companion
  for k, companion in pairs (player_data.companions) do
    if not companion.is_busy then free_companion = companion end
  end
  if not free_companion then return end

  player_data.last_search_offset = player_data.last_search_offset + 1
  local area = search_offsets[player_data.last_search_offset]
  if not area then
    player_data.last_search_offset = 0
    return
  end

  local position = player.position
  local search_area = {{area[1][1] + position.x, area[1][2] + position.y}, {area[2][1] + position.x, area[2][2] + position.y}}


  local force = player.force
  local entities = player.surface.find_entities_filtered{area = search_area}
  local failed_ghost_names = {}

  for k, entity in pairs (entities) do

    if entity.to_be_deconstructed() then
      if entity.force == player.force or entity.force.name == "neutral" then
        free_companion:set_job_destination(entity.position)
        return
      end
    end

    if entity.type == "entity-ghost" then
      if not failed_ghost_names[entity.ghost_name] and entity.force == player.force then
        local item = entity.ghost_prototype.items_to_place_this[1]
        local count = player.get_item_count(item.name)
        if count >= item.count then
          if free_companion:take_item(item) then
            free_companion:set_job_destination(entity.position)
            return
          end
        end
        failed_ghost_names[entity.ghost_name] = true
      end
    end

  end

  --player.surface.create_entity{name = "flying-text", position = search_area[1], text = player_data.last_search_offset}
  --player.surface.create_entity{name = "flying-text", position = search_area[2], text = player_data.last_search_offset}

end

local check_job_search = function()
  for k, player in pairs (game.connected_players) do
    local player_data = script_data.player_data[player.index]
    if player_data then
      perform_job_search(player, player_data)
    end
  end
end

local on_tick = function(event)
  check_job_search(event)
  check_companion_updates(event)
end

local on_robot_pre_mined = function(event)
  local robot = event.robot
  if not (robot and robot.valid) then return end
  if robot.name ~= "companion-construction-robot" then return end

  local source = robot.logistic_network.cells[1].owner
  local companion = get_companion(source.unit_number)
  if not companion then
    robot.destroy()
    return
  end

  companion:on_robot_pre_mined(event)

end

local on_robot_built_entity = function(event)
  local robot = event.robot
  if not (robot and robot.valid) then return end
  if robot.name ~= "companion-construction-robot" then return end

  local source = robot.logistic_network.cells[1].owner
  local companion = get_companion(source.unit_number)
  if not companion then
    robot.destroy()
    return
  end

  companion:on_robot_built_entity(event)

end

local on_robot_built_tile = function(event)

  local robot = event.robot
  if not (robot and robot.valid) then return end
  if robot.name ~= "companion-construction-robot" then return end

  local source = robot.logistic_network.cells[1].owner
  local companion = get_companion(source.unit_number)
  if not companion then
    robot.destroy()
    return
  end

  companion:on_robot_built_tile(event)

end

local on_spider_command_completed = function(event)
  local spider = event.vehicle
  local companion = get_companion(spider.unit_number)
  if not companion then return end
  companion:on_spider_command_completed()
end

local lib = {}

lib.events =
{
  [defines.events.on_built_entity] = on_built_entity,
  [defines.events.on_entity_destroyed] = on_entity_destroyed,
  --[defines.events.on_player_placed_equipment] = on_player_placed_equipment,
  --[defines.events.on_player_removed_equipment] = on_player_removed_equipment,
  [defines.events.on_tick] = on_tick,
  [defines.events.on_robot_pre_mined] = on_robot_pre_mined,
  [defines.events.on_robot_built_entity] = on_robot_built_entity,
  [defines.events.on_robot_built_tile] = on_robot_built_tile,
  [defines.events.on_spider_command_completed] = on_spider_command_completed,
}

lib.on_load = function()
  script_data = global.companion or script_data
  for unit_number, companion in pairs(script_data.companions) do
    setmetatable(companion, Companion.metatable)
  end
end

lib.on_init = function()
  global.companion = global.companion or script_data
end

return lib
