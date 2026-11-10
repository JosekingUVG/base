const std = @import("std");
const rl = @import("raylib");

// Integración de controles de cámara libre asistida por OpenAI Codex (2026-11-09).
pub const move_speed: f32 = 35;
pub const boost_multiplier: f32 = 4;
pub const turn_speed: f32 = std.math.pi / 2.0;

pub const forward: rl.KeyboardKey = .w;
pub const backward: rl.KeyboardKey = .s;
pub const left: rl.KeyboardKey = .a;
pub const right: rl.KeyboardKey = .d;
pub const rise: rl.KeyboardKey = .space;
pub const descend: rl.KeyboardKey = .left_control;
pub const boost: rl.KeyboardKey = .left_shift;

pub const look_left: rl.KeyboardKey = .left;
pub const look_right: rl.KeyboardKey = .right;
pub const look_up: rl.KeyboardKey = .up;
pub const look_down: rl.KeyboardKey = .down;
