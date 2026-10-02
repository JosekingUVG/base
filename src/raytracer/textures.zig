const std = @import("std");
const rl = @import("raylib");

pub const Texture = struct {
    width: usize,
    height: usize,
    data: []rl.Vector3,
    allocator: std.mem.Allocator,

    pub fn sample(self: Texture, uv: rl.Vector2) rl.Vector3 {
        // Repetir la textura si u o v salen del intervalo [0, 1).
        const wrapped_u = uv.x - @floor(uv.x);
        const wrapped_v = uv.y - @floor(uv.y);

        const x: usize = @intFromFloat(
            wrapped_u * @as(f32, @floatFromInt(self.width)),
        );

        // Se invierte V porque normalmente las imágenes comienzan arriba.
        const y: usize = @intFromFloat(
            (1.0 - wrapped_v) *
                @as(f32, @floatFromInt(self.height - 1)),
        );

        const index = y * self.width + x;
        return self.data[index];
    }

    pub fn deinit(self: *Texture) void {
        self.allocator.free(self.data);
    }
};
