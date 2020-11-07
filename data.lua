local bot = util.copy(data.raw["construction-robot"]["construction-robot"])
bot.name = "companion-construction-robot"
bot.max_payload_size = 1
bot.speed = 0.3
bot.max_speed = 0.3
bot.max_energy = "1000000J"
bot.energy_per_tick = "0J"
bot.speed_multiplier_when_out_of_energy = 2
bot.energy_per_move = "1J"
bot.min_to_charge = 0
bot.max_to_charge = 0
bot.working_sound = nil
bot.minable = {name = "fish", amount = 0, mining_time = 1}
bot.selection_box = {{-0.25,-0.25}, {0.25,0.25}}
bot.cargo_centered = {0, -1}
bot.selectable_in_game = false
bot.draw_cargo = true
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
bot.sparks = util.empty_sprite()
bot.smoke = nil
bot.water_reflection = nil
bot.placeable_by =
{
  {item = "construction-robot", count = 0}
}

local bot_item =
{
  type = "item",
  name = "companion-construction-robot",
  icon = "__Companion_Drones__/drone-icon.png",
  icon_size = 200,
  subgroup = "logistic-network",
  order = "a[robot]-b[construction-robot]",
  --place_result = "companion-construction-robot",
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
    buffer_capacity = "10000000GW",
    input_flow_limit = "1000KW",
    usage_priority = "secondary-input",
  },

  charging_energy = "10kW",

  robot_limit = 6,
  construction_radius = (100/7) * 0.707,
  draw_construction_radius_visualization = false,
  spawn_and_station_height = -100000,
  spawn_and_station_shadow_height_offset = 0,
  charge_approach_distance = 0,
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
  stationing_offset = {0, -2},
  charging_station_shift = {0, -2},
  charging_station_count = 0,
  charging_distance = 0,
  charging_threshold_distance = 0,
  robot_vertical_acceleration = -0.01,
  categories = {"companion"}
}

local equipment_item =
{
  type = "item",
  name = "companion-roboport-equipment",
  icon = "__Companion_Drones__/drone-icon.png",
  icon_size = 200,
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

local inserter_beam = util.copy(util.copy(data.raw["beam"]["laser-beam"]))
inserter_beam.name = "inserter-beam"
--inserter_beam.head = util.empty_sprite()
--inserter_beam.head.repeat_count = 8
--inserter_beam.head =
--{
--  filename = "__Companion_Drones__/data//hr-fast-inserter-hand-closed.png",
--  priority = "extra-high",
--  width = 164,
--  height = 72,
--  scale = 0.25
--}
--inserter_beam.start = util.empty_sprite()
--inserter_beam.start.repeat_count = 8
--inserter_beam.body =
--{
--  filename = "__Companion_Drones__/data//hr-fast-inserter-hand-base.png",
--  priority = "extra-high",
--  height = 32,
--  width = 136,
--  scale = 0.25
--}
--inserter_beam.tail = util.empty_sprite()
--inserter_beam.tail.repeat_count = 8
--inserter_beam.ending = util.empty_sprite()
--inserter_beam.ending.repeat_count = 8
--inserter_beam.light_animations = nil
inserter_beam.target_offset = {0, 0}
inserter_beam.random_target_offset = false
inserter_beam.working_sound = nil
inserter_beam.damage_interval = 9999999
inserter_beam.action_triggered_automatically = false
inserter_beam.action = nil

local scale = 0.6
local leg_scale = 1
local arguments = {name = "spidertron"}
local drone =
{
  type = "spider-vehicle",
  name = "companion",
  collision_box = {{-1 * scale, -1 * scale}, {1 * scale, 1 * scale}},
  selection_box = {{-1 * scale, -1 * scale}, {1 * scale, 1 * scale}},
  drawing_box = {{-3 * scale, -4 * scale}, {3 * scale, 2 * scale}},
  icon = "__Companion_Drones__/drone-icon.png",
  icon_size = 200,
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
  weight = 1,
  braking_force = 1,
  friction_force = 1,
  flags = {"placeable-neutral", "player-creation", "placeable-off-grid"},
  collision_mask = {},
  minable = nil,
  max_health = 250,
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
  inventory_size = 12,
  equipment_grid = "companion-equipment-grid",
  trash_inventory_size = 0,
  height = 2,
  torso_rotation_speed = 0.05,
  chunk_exploration_radius = 3,
  selection_priority = 51,
  graphics_set = spidertron_torso_graphics_set(0.6),
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
        mount_position = {0, 0},
        ground_position = {0, 0},
        blocking_legs = {},
        leg_hit_the_ground_trigger = nil
      }
    },
    military_target = "spidertron-military-target"
  }
}
drone.graphics_set.render_layer = "air-entity-info-icon"
drone.graphics_set.base_render_layer = "air-object"
drone.graphics_set.light =
{
  {
    type = "oriented",
    minimum_darkness = 0.3,
    picture =
    {
      filename = "__core__/graphics/light-cone.png",
      priority = "extra-high",
      flags = { "light" },
      scale = 1,
      width = 200,
      height = 200,
      shift = {0, -1}
    },
    source_orientation_offset = 0,
    shift = {0, (-200/32)- 0.5},
    add_perspective = false,
    size = 2,
    intensity = 0.6,
    color = {r = 0.92, g = 0.77, b = 0.3}
  }
}
drone.graphics_set.eye_light.size = 0

local leg =
{
  type = "spider-leg",
  name = "companion-leg",

  localised_name = {"entity-name.spidertron-leg"},
  collision_box = {{-0, -0}, {0, 0}},
  collision_mask = {},
  selection_box = {{-0, -0}, {0, 0}},
  icon = "__base__/graphics/icons/spidertron.png",
  icon_size = 64, icon_mipmaps = 4,
  walking_sound_volume_modifier = 0,
  target_position_randomisation_distance = 0,
  minimal_step_size = 0,
  working_sound = nil,
  part_length = 1.5,
  initial_movement_speed = 1,
  movement_acceleration = 1,
  max_health = 100,
  movement_based_position_selection_distance = 3,
  selectable_in_game = false,
  graphics_set = create_spidertron_leg_graphics_set(0, 1)
}

local layers = drone.graphics_set.base_animation.layers
for k, layer in pairs (layers) do
  layer.repeat_count = 8
  layer.hr_version.repeat_count = 8
end

table.insert(layers, 1,
{
  filename = "__base__/graphics/entity/rocket-silo/10-jet-flame.png",
  priority = "medium",
  blend_mode = "additive",
  draw_as_glow = true,
  width = 87,
  height = 128,
  frame_count = 8,
  line_length = 8,
  animation_speed = 0.5,
  scale = 1.13/4,
  shift = util.by_pixel(-0.5, 20),
  direction_count = 1,
  hr_version = {
    filename = "__base__/graphics/entity/rocket-silo/hr-10-jet-flame.png",
    priority = "medium",
    blend_mode = "additive",
    draw_as_glow = true,
    width = 172,
    height = 256,
    frame_count = 8,
    line_length = 8,
    animation_speed = 0.5,
    scale = 1.13/8,
    shift = util.by_pixel(-1, 20),
    direction_count = 1,
  }
})

local drone_item =
{
  type = "item",
  name = "companion",
  icon = "__Companion_Drones__/drone-icon.png",
  icon_size = 200,
  subgroup = "equipment",
  order = "e[robotics]-a[personal-roboport-equipment]",
  stack_size = 20,
  place_result = "companion"
}

local gun =
{
  type = "active-defense-equipment",
  name = "companion-defense-equipment",
  sprite =
  {
    filename = "__base__/graphics/equipment/personal-laser-defense-equipment.png",
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
    usage_priority = "secondary-input",
    buffer_capacity = "10000MJ"
  },

  attack_parameters =
  {
    type = "beam",
    cooldown = 30,
    cooldown_deviation = 0.1,
    range = 21,
    --source_direction_count = 64,
    --source_offset = {0, -3.423489 / 4},
    damage_modifier = 1,
    ammo_type =
    {
      category = "laser",
      energy_consumption = "1J",
      action =
      {
        type = "direct",
        action_delivery =
        {
          type = "instant",
          target_effects =
          {
            type = "script",
            effect_id = "companion-attack"
          }
        }
      },
    }
  },

  automatic = true,
  categories = {"companion"}
}

local gun_item =
{
  type = "item",
  name = "companion-defense-equipment",
  icon = "__Companion_Drones__/drone-icon.png",
  icon_size = 200,
  placed_as_equipment_result = "companion-defense-equipment",
  subgroup = "equipment",
  order = "e[robotics]-a[personal-roboport-equipment]",
  default_request_amount = 1,
  stack_size = 20
}

local plasma_projectile =
{
  type = "projectile",
  name = "companion-projectile",
  icon = "__Companion_Drones__/drone-icon.png",
  icon_size = 200,
  flags = {"not-on-map"},
  subgroup = "explosions",
  height = 1.4,
  rotatable = true,
  animation = nil,
  acceleration = 0.005,
  max_speed = 0.5,
  turn_speed = 0.001,
  turning_speed_increases_exponentially_with_projectile_speed = true,
  collision_box = {{-0.1, -0.1},{0.1, 0.1}},
  speed_modifier = {1, 0.707},
  hit_at_collision_position = true,
  force_condition = "enemy",
  action =
  {
    type = "direct",
    action_delivery =
    {
      type = "instant",
      target_effects =
      {
        {
          type = "create-entity",
          entity_name = "explosion"
        },
        {
          type = "damage",
          damage = {amount = 10, type = "laser"}
        },
      }
    }
  },
}

local companion_grid =
{
  type = "equipment-grid",
  name = "companion-equipment-grid",
  width = 10,
  height = 2,
  equipment_categories = {"companion"}
}


local shield =
{
  type = "energy-shield-equipment",
  name = "companion-shield-equipment",
  sprite =
  {
    filename = "__base__/graphics/equipment/energy-shield-equipment.png",
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
  max_shield_value = 250,
  energy_source =
  {
    type = "electric",
    buffer_capacity = "60J",
    input_flow_limit = "12W",
    usage_priority = "primary-input"
  },
  energy_per_shield = "1J",
  categories = {"companion"}
}

local shield_item =
{
  type = "item",
  name = "companion-shield-equipment",
  icon = "__Companion_Drones__/drone-icon.png",
  icon_size = 200,
  placed_as_equipment_result = "companion-shield-equipment",
  subgroup = "equipment",
  order = "e[robotics]-a[personal-roboport-equipment]",
  default_request_amount = 1,
  stack_size = 20
}

local battery =
{
  type = "battery-equipment",
  name = "companion-battery-equipment",
  sprite =
  {
    filename = "__base__/graphics/equipment/battery-equipment.png",
    width = 32,
    height = 64,
    priority = "medium"
  },
  shape =
  {
    width = 1,
    height = 2,
    type = "full"
  },
  energy_source =
  {
    type = "electric",
    buffer_capacity = "200000MJ",
    usage_priority = "tertiary"
  },
  categories = {"companion"}
}

local battery_item =
{
  type = "item",
  name = "companion-battery-equipment",
  icon = "__Companion_Drones__/drone-icon.png",
  icon_size = 200,
  placed_as_equipment_result = "companion-battery-equipment",
  subgroup = "equipment",
  order = "e[robotics]-a[personal-roboport-equipment]",
  default_request_amount = 1,
  stack_size = 20
}

local category =
{
  type = "equipment-category",
  name = "companion"
}


data:extend
{
  bot,
  bot_item,
  equipment,
  equipment_item,
  build_beam,
  deconstruct_beam,
  inserter_beam,
  drone,
  drone_item,
  leg,
  gun,
  gun_item,
  plasma_projectile,
  companion_grid,
  shield,
  shield_item,
  battery,
  battery_item,
  category

}
