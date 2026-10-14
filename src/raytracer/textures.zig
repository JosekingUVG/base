const std = @import("std");
const rl = @import("raylib");

pub const Texture = struct {
    width: usize,
    height: usize,
    data: []rl.Vector3,
    allocator: std.mem.Allocator,

    pub fn load(
        allocator: std.mem.Allocator,
        path: [:0]const u8,
    ) !Texture {
        const image = try rl.loadImage(path);
        defer rl.unloadImage(image);

        const width: usize = @intCast(image.width);
        const height: usize = @intCast(image.height);

        const data = try allocator.alloc(
            rl.Vector3,
            width * height,
        );
        errdefer allocator.free(data);

        for (0..height) |y| {
            for (0..width) |x| {
                const pixel = rl.getImageColor(
                    image,
                    @intCast(x),
                    @intCast(y),
                );

                data[y * width + x] = .{
                    .x = @as(f32, @floatFromInt(pixel.r)) / 255.0,
                    .y = @as(f32, @floatFromInt(pixel.g)) / 255.0,
                    .z = @as(f32, @floatFromInt(pixel.b)) / 255.0,
                };
            }
        }

        return .{
            .width = width,
            .height = height,
            .data = data,
            .allocator = allocator,
        };
    }

    pub fn sample(
        self: Texture,
        uv: rl.Vector2,
    ) rl.Vector3 {
        const wrapped_u = uv.x - @floor(uv.x);
        const wrapped_v = uv.y - @floor(uv.y);

        const x: usize = @intFromFloat(
            wrapped_u *
                @as(f32, @floatFromInt(self.width)),
        );

        const y: usize = @intFromFloat(
            (1.0 - wrapped_v) *
                @as(f32, @floatFromInt(self.height - 1)),
        );

        return self.data[y * self.width + x];
    }

    pub fn deinit(self: *Texture) void {
        self.allocator.free(self.data);

        // Evita conservar una referencia accidental
        // a memoria que ya fue liberada.
        self.* = undefined;
    }
};
