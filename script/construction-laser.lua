local util = require("util")
local on_robot_built_entity = function(event)
  local robot = event.robot
  if not (robot and robot.valid) then return end
  if robot.name ~= "companion-construction-robot" then return end

  local entity = event.created_entity
  if not (entity and entity.valid) then return end

  local source = robot.logistic_network.cells[1].owner

  local duration = math.ceil((util.distance(source.position, entity.position) / 0.4) * 0.9)
  robot.surface.create_entity{name = "companion-build-beam", position = robot.position, target_position = entity.position, source = source, force = robot.force, source_offset = {0, -0}, duration = duration}

  if source.type == "spider-vehicle" then
    source.autopilot_destination =
    {
      (robot.position.x + source.position.x) / 2,
      (robot.position.y + source.position.y) / 2
    }
  end

end

local on_robot_mined_entity = function(event)
  local robot = event.robot
  if not (robot and robot.valid) then return end
  if robot.name ~= "companion-construction-robot" then return end

  local entity = event.entity
  if not (entity and entity.valid) then return end

  local source = robot.logistic_network.cells[1].owner
  local duration = math.ceil((util.distance(source.position, entity.position) / 0.4) / 2)
  robot.surface.create_entity{name = "companion-deconstruct-beam", position = robot.position, target_position = entity.position, source = source, force = robot.force, source_offset = {0, -0}, duration = duration}
  robot.surface.play_sound{position = robot.position, path = "utility/drop_item"}

  if source.type == "spider-vehicle" then
    source.autopilot_destination =
    {
      (robot.position.x + source.position.x) / 2,
      (robot.position.y + source.position.y) / 2
    }
  end

end

local spider_to_build = {}

local on_player_placed_equipment = function(event)
  local equipment = event.equipment
  if not (equipment and equipment.valid) then return end
  if equipment.name ~= "companion-roboport-equipment" then return end

  local player = game.get_player(event.player_index)
  if player.opened_gui_type ~= defines.gui_type.entity then return end

  local opened = player.opened
  if not (opened and opened.valid) then return end

  if true then
    spider_to_build[game.tick + 1] = opened
    game.print("HUKJE")
    return
  end
end

local on_tick = function()
  if not next(spider_to_build) then return end

  local opened = spider_to_build[game.tick]
  if not opened then return end
  spider_to_build[game.tick] = nil

  game.print("SHTSJH")
  local surface = opened.surface
  local position = opened.position
  local force = opened.force
  local network = opened.logistic_network

  if not network then error("WTF?") end
  for k = 1, 1 do
    local robot = surface.create_entity{name = "companion-construction-robot", position = {position.x + (math.random()-0.5), position.y + (math.random() - 0.5)}, force = force}
    robot.logistic_network = opened.logistic_network
    --surface.create_entity{name = "companion-beam", position = position, force = force, target = robot, source = opened}
  end

end

local lib = {}

lib.events =
{
  [defines.events.on_robot_built_entity] = on_robot_built_entity,
  [defines.events.on_robot_mined_entity] = on_robot_mined_entity,
  [defines.events.on_player_placed_equipment] = on_player_placed_equipment,
  [defines.events.on_tick] = on_tick
}

return lib