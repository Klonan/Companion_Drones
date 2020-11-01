local script_data =
{
  companions = {},
  tick_updates = {}
}

local get_companion = function(unit_number)
  return unit_number and script_data.companions[unit_number]
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
  companion.flagged_for_equipment_changed = true
  companion:schedule_tick_update(1)
  companion:add_passengers()

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
    end
  end

end

function Companion:update()
  if self.flagged_for_equipment_changed then
    self.flagged_for_equipment_changed = nil
    self:check_robots()
  end

  if not self:is_busy() then
    self:return_to_player()
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
  script_data.companions[self.unit_number] = nil
end

function Companion:on_player_placed_equipment(event)
  self.flagged_for_equipment_changed = true
  self:schedule_tick_update(1)
  self:say("Equipment added")
end

function Companion:on_player_removed_equipment(event)
  self.flagged_for_equipment_changed = true
  self:schedule_tick_update(1)
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

  local distance = self:distance(entity.position)
  local duration = math.ceil((distance / 0.5) * 0.9)
  self.entity.surface.create_entity{name = "companion-build-beam", position = self.entity.position, target = entity, source = self.entity, force = self.entity.force, source_offset = {0, -0}, duration = duration}

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

  local distance = self:distance(entity.position)
  local duration = math.ceil((distance / 0.5) * 0.9)
  self.entity.surface.create_entity{name = "companion-deconstruct-beam", position = self.entity.position, target_position = entity.position, source = self.entity, force = self.entity.force, source_offset = {0, -0}, duration = duration}
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

function Companion:return_to_player()
  if not self.player.valid then return end


  local target_position = self.player.position

  local walking_state = self.player.walking_state


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
    self:schedule_tick_update(math.random(21,42))
  elseif self:distance(target_position) > 5 then
    self.entity.autopilot_destination = target_position
    self:schedule_tick_update(math.random(60,100))
  else
    self:schedule_tick_update(math.random(30, 60))
  end

end

function Companion:is_busy()
  local network = self.entity.logistic_network
  if network then
    if network.available_construction_robots ~= network.robot_limit then
      return true
    end
  end
end

function Companion:on_spider_command_completed()

  if self:is_busy() then return end

  self:return_to_player()

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

local on_tick = function(event)
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
