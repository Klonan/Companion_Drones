local util = require("util")

local script_data =
{
  companions = {},
  tick_updates = {},
  player_data = {},
  search_schedule = {}
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
    robots = {},
    active_construction = true,
    active_combat = true,
    follow_range = 6
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
    if not robot.get_inventory(defines.inventory.robot_cargo).is_empty() or robot.energy < 1000000 then
      robot.energy = 1000000
      position.x = position.x + robot_position.x
      position.y = position.y + robot_position.y
      count = count + 1
    end
  end
  if count == 0 then return end
  position.x = ((position.x / count))-- + our_position.x) / 2
  position.y = ((position.y / count))-- + our_position.y) / 2
  self.entity.autopilot_destination = position
  self:propose_tick_update(math.random(15, 25))
  return true
end

function Companion:update_busy_state()
  self.is_busy = self.moving_to_destination or self:move_to_robot_average()
end

function Companion:is_getting_full()
  return self:get_inventory()[11].valid_for_read
end

function Companion:propose_tick_update(ticks)
  if ticks < 1 then error("WTF?") end
  self.next_tick_update = math.min(math.ceil(ticks), (self.next_tick_update or math.huge))
end

function Companion:update()

  if self.flagged_for_equipment_changed then
    self.flagged_for_equipment_changed = nil
    --self:say("Checking equipment")
    self:check_robots()
  end

  self:update_busy_state()
  --self:say("U")

  if self:is_getting_full() or not self.is_busy then
    self:return_to_player()
  end

  self:schedule_next_update()

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
  local y2 = position[y] or position.y
  return (((source.x - x2) ^ 2) + ((source.y - y2) ^ 2)) ^ 0.5
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
  local total_inserted = 0
  for k = 1, #inventory do
    local stack = inventory[k]
    if not (stack and stack.valid_for_read) then break end
    local inserted = self.player.insert(stack)
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
      duration = math.max(math.ceil(total_inserted / 5), 5),
      max_length = 10
    }
  end

  if self.flagged_for_mine then
    self.entity.mine
    {
      inventory = self.player.character and self.player.character.get_main_inventory() or nil,
      force = true,
      ignore_minable = true
    }
  end
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
    self:propose_tick_update(17)
  end

  local distance = self:distance(target_position)
  if distance > self.follow_range then
    self.entity.autopilot_destination = target_position
    return
  end


  self:try_to_shove_inventory()

end

function Companion:on_spider_command_completed()
  self.moving_to_destination = nil
end

function Companion:take_item(item)
  local inventory = self:get_inventory()
  local count = math.max(math.min(math.ceil(game.item_prototypes[item.name].stack_size / 2), self.player.get_item_count(item.name)), item.count)
  local removed = self.player.remove_item({name = item.name, count = count})
  if removed == 0 then return end
  inventory.insert({name = item.name, count = removed})

  self.entity.surface.create_entity
  {
    name = "inserter-beam",
    source = self.entity,
    target = self.player.character,
    target_position = self.player.position,
    force = self.entity.force,
    position = self.entity.position,
    duration = math.max(math.ceil(removed / 5), 5),
    max_length = self.follow_range + 4
  }

  return removed >= item.count
end


local angle = function(position_1, position_2)
  local d_x = (position_2[1] or position_2.x) - (position_1[1] or position_1.x)
  local d_y = (position_2[2] or position_2.y) - (position_1[2] or position_1.y)
  return math.atan2(d_y, d_x)
end

function Companion:get_offset(target_position, length)

    -- Angle in rads
    local angle = angle(self.entity.position, target_position)
    angle = angle + (math.pi / 2)
    local x1 = (length * math.sin(angle))
    local y1 = (-length * math.cos(angle))

    return {x1, y1}
end

function Companion:set_job_destination(position, delay_update)
  local self_position = self.entity.position
  local distance = self:distance(position) - 4

  local update = 0
  --if delay_update then update = update + 80 end

  if distance > 0 then
    local offset = self:get_offset(position, distance)
    self_position.x = self_position.x + offset[1]
    self_position.y = self_position.y + offset[2]
    self.entity.autopilot_destination = self_position
    self.moving_to_destination = true
    update = update + math.ceil(distance / 0.25)
    self:propose_tick_update(update)
  end

  self.is_busy = true
end

function Companion:attack(entity)
  --self:say("Attacking "..entity.name)
  local position = self.entity.position
  for k, offset in pairs  {0, -0.25, 0.25} do
    local projectile = self.entity.surface.create_entity
    {
      name = "companion-projectile",
      position = {position.x, position.y - 1.5},
      speed = 0.05,
      force = self.entity.force,
      target = entity,
      max_range = 30
    }

    projectile.orientation = projectile.orientation + offset

    local beam = self.entity.surface.create_entity{name = "inserter-beam", source = self.entity, target = self.entity, position = {0,0}}
    beam.set_beam_target(projectile)
  end
  if false then
    self.entity.autopilot_destination = {(position.x + entity.position.x) / 2, (position.y + entity.position.y) / 2}
  end
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

function Companion:try_to_find_work(search_area)

  local entities
  local deconstruction_only = self:distance(self.player.position) > 10
  if deconstruction_only then
    -- We are far away from the player, so we can only handle deconstruction
    entities = self.entity.surface.find_entities_filtered{area = search_area, to_be_deconstructed = true}
  else
    entities = self.entity.surface.find_entities_filtered{area = search_area}
  end

  local attempted_ghost_names = {}
  local attempted_upgrade_names = {}
  local attempted_cliff_names = {}
  local attempted_proxy_items = {}
  local repair_failed = false
  local max_item_type_count = table_size(self.robots)
  local force = self.entity.force

  for k, entity in pairs (entities) do
    local entity_force = entity.force
    if deconstruction_only or entity.to_be_deconstructed() then
      if entity.type == "cliff" then
        if not deconstruction_only and not attempted_cliff_names[entity.name] then
          local item = entity.prototype.cliff_explosive_prototype
          if item and self.player.get_item_count(item) > 0 then
            if self:take_item({name = item, count = 1}) then
              if not self.moving_to_destination then
                self:set_job_destination(entity.position, true)
              end
              max_item_type_count = max_item_type_count - 1
              if max_item_type_count <= 0 then
                return
              end
            end
          end
          attempted_cliff_names[entity.name] = true
        end
      else
        if entity_force == force or entity_force.name == "neutral" then
          self:set_job_destination(entity.position, true)
          return
        end
      end
    end

    if (not deconstruction_only) and entity_force == force then

      if ghost_types[entity.type] then
        if not attempted_ghost_names[entity.ghost_name] then
          local item = entity.ghost_prototype.items_to_place_this[1]
          local count = self.player.get_item_count(item.name)
          if count >= item.count then
            if self:take_item(item) then
              if not self.moving_to_destination then
                self:set_job_destination(entity.position, true)
              end
              max_item_type_count = max_item_type_count - 1
              if max_item_type_count <= 0 then
                return
              end
            end
          end
          attempted_ghost_names[entity.ghost_name] = true
        end
      end

      if entity.to_be_upgraded() then
        local upgrade_target = entity.get_upgrade_target()
        if not attempted_upgrade_names[upgrade_target.name] then
          if upgrade_target.name == entity.name then
            if not self.moving_to_destination then
              self:set_job_destination(entity.position, true)
            end
          else
            local item = upgrade_target.items_to_place_this[1]
            local count = self.player.get_item_count(item.name)
            if count >= item.count then
              if self:take_item(item) then
                if not self.moving_to_destination then
                  self:set_job_destination(entity.position, true)
                end
                max_item_type_count = max_item_type_count - 1
                if max_item_type_count <= 0 then
                  return
                end
              end
            end
          end
          attempted_upgrade_names[upgrade_target.name] = true
        end
      end

      if not repair_failed and (not entity.has_flag("not-repairable") and entity.get_health_ratio() and entity.get_health_ratio() < 1) then
        local repair_item
        for k, item in pairs (get_repair_tools()) do
          local count = self.player.get_item_count(item.name)
          if count >= item.count then
            repair_item = item
            break
          end
        end
        if repair_item then
          if self:take_item(repair_item) then
            if not self.moving_to_destination then
              self:set_job_destination(entity.position, true)
            end
          end
        else
          repair_failed = true
        end
      end

      if item_request_types[entity.type] then
        local items = entity.item_requests
        for name, item_count in pairs (items) do
          if not attempted_proxy_items[name] then
            local count = self.player.get_item_count(name)
            if count >= item_count then
              if self:take_item({name = name, count = item_count}) then
                if not self.moving_to_destination then
                  self:set_job_destination(entity.position, true)
                end
                max_item_type_count = max_item_type_count - 1
                if max_item_type_count <= 0 then
                  return
                end
              end
            end
          end
          attempted_proxy_items[name] = true
        end
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
  end

  local combat_mode_switch = get_gui_by_tag(gui, "combat_mode_switch")
  combat_mode_switch.switch_state = (self.active_combat and "right") or "left"

  local construction_mode_switch = get_gui_by_tag(gui, "construction_mode_switch")
  construction_mode_switch.switch_state = (self.active_construction and "right") or "left"

  local follow_slider = get_gui_by_tag(gui, "follow_range_slider")
  follow_slider.slider_value = self.follow_range

  local follow_textfield = get_gui_by_tag(gui, "follow_range_textfield")
  follow_textfield.text = tostring(self.follow_range)

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
    companion:return_to_player()
    companion.flagged_for_mine = true
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
  follow_range_slider = function(event)
    local companion = get_opened_companion(event.player_index)
    if not companion then return end
    local slider = event.element
    local number = math.min(math.max(2, slider.slider_value), 20)
    companion.follow_range = number
    local textfield = get_gui_by_tag(slider.parent, "follow_range_textfield")
    textfield.text = tostring(number)
  end,
  follow_range_textfield = function(event)
    local companion = get_opened_companion(event.player_index)
    if not companion then return end
    local textfield = event.element
    local number = tonumber(textfield.text)
    if not number then return end
    if number > 20 then return end
    if number < 2 then return end
    companion.follow_range = number
    local slider = get_gui_by_tag(textfield.parent, "follow_range_slider")
    slider.slider_value = number
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

  local follow_range_frame = inner.add{type = "frame", style = "bordered_frame", caption = "Follow distance"}
  local follow_range_flow = follow_range_frame.add{type = "flow", style = "player_input_horizontal_flow", }

  local slider = follow_range_flow.add{type = "slider", minimum_value = 2, maximum_value = 20, value = 6, value_step = 2, discrete_values = true, discrete_slider = true, style = "notched_slider", tags = {companion_function = "follow_range_slider"}}
  local textfield = follow_range_flow.add{type = "textfield", style = "slider_value_textfield", text = 6, numeric = true, allow_decimal = true, allow_negative = false, lose_focus_on_confirm = true, tags = {companion_function = "follow_range_textfield"}}

  local button = frame.add{type = "button", caption = "Return to me", tags = {companion_function = "return_home"}}
  button.style.horizontally_stretchable = true

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
  for k, companion in pairs (player_data.companions) do
    if not companion.is_busy and companion.active_construction and next(companion.robots) then
      free_companion = companion
      break
    end
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

  free_companion:try_to_find_work(search_area)

  --player.surface.create_entity{name = "flying-text", position = search_area[1], text = player_data.last_search_offset}
  --player.surface.create_entity{name = "flying-text", position = search_area[2], text = player_data.last_search_offset}

end

local job_mod = 3
local check_job_search = function(event)
  for k, player in pairs (game.connected_players) do
    if (k + event.tick) % job_mod == 0 then
      local player_data = script_data.player_data[player.index]
      if player_data then
        perform_job_search(player, player_data)
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

  local companion = get_companion(source_entity.unit_number)
  if companion then
    companion:attack(event.target_entity)
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
end

return lib
