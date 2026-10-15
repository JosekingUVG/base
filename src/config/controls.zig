const std = @import("std");
const rl = @import("raylib");

pub const initial_distance: f32 = 100;
pub const min_distance: f32 = 15;
pub const max_distance: f32 = 250;
pub const turn_speed: f32 = std.math.pi / 2.0;
pub const zoom_speed: f32 = 5;
pub const initial_x_angle: f32 = std.math.pi;
pub const initial_y_angle: f32 = 0;
pub const y_angle_max: f32 = std.math.pi / 4.0;
pub const y_angle_min: f32 = -y_angle_max;

pub const left: rl.KeyboardKey = .a;
pub const right: rl.KeyboardKey = .d;
pub const up: rl.KeyboardKey = .w;
pub const down: rl.KeyboardKey = .s;
pub const left_arrow: rl.KeyboardKey = .left;
pub const right_arrow: rl.KeyboardKey = .right;
pub const up_arrow: rl.KeyboardKey = .up;
pub const down_arrow: rl.KeyboardKey = .down;
