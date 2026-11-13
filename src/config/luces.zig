const Light = @import("../raytracer/raytracer.zig").Light;
const V3FromColor = @import("../raytracer/raytracer.zig").V3FromColor;
const htmlColor = @import("../raytracer/cute_colors.zig").htmlColor;
const formas = @import("formas.zig");

// Luces de la escena
pub const lights = [_]Light{
    // LUZ SOLAR
    .{
        .Color = V3FromColor(htmlColor("#ffd27a")),
        // cast_ray aplica atenuacion 1 / distancia^2. Una intensidad de 1 era
        // imperceptible a las distancias de esta escena.
        .Intensity = 10_000,
        .Position = formas.sun_position,
        .Object_index = formas.sun_object_index,
    },
};
