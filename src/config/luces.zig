const Light = @import("../raytracer/raytracer.zig").Light;
const V3FromColor = @import("../raytracer/raytracer.zig").V3FromColor;
const htmlColor = @import("../raytracer/cute_colors.zig").htmlColor;

// Luces de la escena
pub const lights = [_]Light{
    .{
        // Corresponde a la luz roja que ilumina la escena desde arriba y a la derecha
        .Color = V3FromColor(htmlColor("#bc510e")),
        .Intensity = 1,
        .Position = .{ .x = 5, .y = 100, .z = 15 },
    },
    .{
        // Corresponde a la luz blanca que ilumina la escena desde arriba y a la izquierda
        .Color = V3FromColor(htmlColor("#fff")),
        .Intensity = 1,
        .Position = .{ .x = 0, .y = 0, .z = -250 },
    },
};
