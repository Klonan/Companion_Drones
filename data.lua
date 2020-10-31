local bot = util.copy(data.raw["construction-robot"]["construction-robot"])
bot.name = "companion-construction-robot"
bot.max_payload_size = 1
bot.speed = 1
bot.max_energy = "1000MJ"
bot.energy_per_tick = "1J"
bot.speed_multiplier_when_out_of_energy = 1
bot.energy_per_move = "1J"
bot.min_to_charge = 0
bot.max_to_charge = 1
bot.working_sound = nil
--bot.minable = nil
bot.selection_box = {{0,0}, {0,0}}
bot.selectable_in_game = false
bot.draw_cargo = false
bot.max_health = 9999999

bot.idle = util.empty_sprite()
bot.idle_with_cargo = util.empty_sprite()
bot.in_motion = util.empty_sprite()
bot.in_motion_with_cargo = util.empty_sprite()
bot.shadow_idle = util.empty_sprite()
bot.shadow_idle_with_cargo = util.empty_sprite()
bot.shadow_in_motion = util.empty_sprite()
bot.shadow_in_motion_with_cargo = util.empty_sprite()
bot.working = util.empty_sprite()
bot.shadow_working = util.empty_sprite()

local bot_item =
{
  type = "item",
  name = "companion-construction-robot",
  icon = "__base__/graphics/icons/construction-robot.png",
  icon_size = 64, icon_mipmaps = 4,
  subgroup = "logistic-network",
  order = "a[robot]-b[construction-robot]",
  place_result = "companion-construction-robot",
  stack_size = 50
}

local equipment =
{
  type = "roboport-equipment",
  name = "companion-roboport-equipment",
  take_result = "companion-roboport-equipment",
  sprite =
  {
    filename = "__base__/graphics/equipment/personal-roboport-equipment.png",
    width = 64,
    height = 64,
    priority = "medium"
  },

  shape =
  {
    width = 2,
    height = 2,
    type = "full"
  },

  energy_source =
  {
    type = "electric",
    buffer_capacity = "0W",
    input_flow_limit = "0KW",
    usage_priority = "secondary-input"
  },

  charging_energy = "0kW",

  robot_limit = 10,
  construction_radius = 100,
  spawn_and_station_height = 0,
  spawn_and_station_shadow_height_offset = 0,
  charge_approach_distance = -0.6,
  robots_shrink_when_entering_and_exiting = true,

  recharging_animation =
  {
    filename = "__base__/graphics/entity/roboport/roboport-recharging.png",
    priority = "high",
    width = 37,
    height = 35,
    frame_count = 16,
    scale = 1.5,
    animation_speed = 0.5
  },

  recharging_light = {intensity = 0.4, size = 5},
  stationing_offset = {0, 0},
  charging_station_shift = {0, 0},
  charging_station_count = 0,
  charging_distance = 0,
  charging_threshold_distance = 0,
  categories = {"armor"}
}

local equipment_item =
{
  type = "item",
  name = "companion-roboport-equipment",
  icon = "__base__/graphics/icons/personal-roboport-equipment.png",
  icon_size = 64, icon_mipmaps = 4,
  placed_as_equipment_result = "companion-roboport-equipment",
  subgroup = "equipment",
  order = "e[robotics]-a[personal-roboport-equipment]",
  default_request_amount = 1,
  stack_size = 20
}

local attach_beam_graphics = require("data/beam_sprites")

local build_beam = util.copy(data.raw["beam"]["electric-beam-no-sound"])
build_beam.name = "companion-build-beam"
build_beam.action = nil
attach_beam_graphics(build_beam, nil, nil, {0, 1, 0}, {0, 1, 0})

local deconstruct_beam = util.copy(data.raw["beam"]["electric-beam-no-sound"])
deconstruct_beam.name = "companion-deconstruct-beam"
deconstruct_beam.action = nil
attach_beam_graphics(deconstruct_beam, nil, nil, {1, 0, 0}, {1, 0, 0})

local scale = 1
local leg_scale = 1
local arguments = {name = "spidertron"}
local drone =
{
  type = "spider-vehicle",
  name = "companion",
  collision_box = {{-1 * scale, -1 * scale}, {1 * scale, 1 * scale}},
  selection_box = {{-1 * scale, -1 * scale}, {1 * scale, 1 * scale}},
  drawing_box = {{-3 * scale, -4 * scale}, {3 * scale, 2 * scale}},
  icon = "__base__/graphics/icons/spidertron.png",
  mined_sound = {filename = "__core__/sound/deconstruct-large.ogg",volume = 0.8},
  open_sound = { filename = "__base__/sound/spidertron/spidertron-door-open.ogg", volume= 0.35 },
  close_sound = { filename = "__base__/sound/spidertron/spidertron-door-close.ogg", volume = 0.4 },
  sound_minimum_speed = 0.1,
  sound_scaling_ratio = 0.6,
  working_sound =
  {
    sound =
    {
      filename = "__base__/sound/spidertron/spidertron-vox.ogg",
      volume = 0.35
    },
    activate_sound =
    {
      filename = "__base__/sound/spidertron/spidertron-activate.ogg",
      volume = 0.5
    },
    deactivate_sound =
    {
      filename = "__base__/sound/spidertron/spidertron-deactivate.ogg",
      volume = 0.5
    },
    match_speed_to_activity = true
  },
  icon_size = 64, icon_mipmaps = 4,
  weight = 1,
  braking_force = 1,
  friction_force = 1,
  flags = {"placeable-neutral", "player-creation", "placeable-off-grid"},
  collision_mask = {},
  minable = {mining_time = 1, result = "spidertron"},
  max_health = 3000,
  resistances =
  {
    {
      type = "fire",
      decrease = 15,
      percent = 60
    },
    {
      type = "physical",
      decrease = 15,
      percent = 60
    },
    {
      type = "impact",
      decrease = 50,
      percent = 80
    },
    {
      type = "explosion",
      decrease = 20,
      percent = 75
    },
    {
      type = "acid",
      decrease = 0,
      percent = 70
    },
    {
      type = "laser",
      decrease = 0,
      percent = 70
    },
    {
      type = "electric",
      decrease = 0,
      percent = 70
    }
  },
  minimap_representation =
  {
    filename = "__base__/graphics/entity/spidertron/spidertron-map.png",
    flags = {"icon"},
    size = {128, 128},
    scale = 0.5
  },
  --corpse = "spidertron-remnants",
  --dying_explosion = "spidertron-explosion",
  energy_per_hit_point = 1,
  guns = {},
  inventory_size = 10,
  equipment_grid = "spidertron-equipment-grid",
  trash_inventory_size = 0,
  height = 1,
  torso_rotation_speed = 0.05,
  chunk_exploration_radius = 3,
  selection_priority = 51,
  graphics_set = spidertron_torso_graphics_set(1),
  base_render_layer = "smoke",
  render_layer = "air-object",
  energy_source =
  {
    type = "void"
  },
  movement_energy_consumption = "1W",
  automatic_weapon_cycling = true,
  chain_shooting_cooldown_modifier = 0.5,
  spider_engine =
  {
    legs =
    {
      { -- 1
        leg = "companion-leg",
        mount_position = {0,0},
        ground_position = {0,0},
        blocking_legs = {},
        leg_hit_the_ground_trigger = nil
      },
    },
    military_target = "spidertron-military-target"
  }
}
drone.graphics_set.render_layer = "air-object"
drone.graphics_set.base_render_layer = "air-object"

local leg =
{
  type = "spider-leg",
  name = "companion-leg",

  localised_name = {"entity-name.spidertron-leg"},
  collision_box = {{-0.0, -0.0}, {0.0, 0.0}},
  selection_box = {{-0, -0}, {0, 0}},
  icon = "__base__/graphics/icons/spidertron.png",
  icon_size = 64, icon_mipmaps = 4,
  walking_sound_volume_modifier = 0,
  target_position_randomisation_distance = 0.25 * scale,
  minimal_step_size = 1 * scale,
  working_sound = nil,
  part_length = 1,
  initial_movement_speed = 1,
  movement_acceleration = 1,
  max_health = 100,
  movement_based_position_selection_distance = 1,
  selectable_in_game = false,
  graphics_set = create_spidertron_leg_graphics_set(0, 1)
}

data:extend
{
  bot,
  bot_item,
  equipment,
  equipment_item,
  build_beam,
  deconstruct_beam,
  drone,
  leg
}
