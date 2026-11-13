const rl = @import("raylib");

const Forma = @import("../formas/formas.zig").Forma;
const Material = @import("../raytracer/raytracer.zig").Material;
const Texture = @import("../raytracer/textures.zig").Texture;
const V3FromColor = @import("../raytracer/raytracer.zig").V3FromColor;
const htmlColor = @import("../raytracer/cute_colors.zig").htmlColor;

pub const sun_texture_path = "assets/textures/sun-texture.png";

pub fn modelMaterial(model_texture: *const Texture) Material {
    return .{
        .Texture = model_texture,
        .Ambient = 0.6,
        .Color = V3FromColor(htmlColor("#fff")),
        .Propiedades = .{
            .Albedo = 0.4,
            .Especular = 0,
            .Reflectividad = 0,
            .Transparencia = 0,
        },
        .Especular = 1000,
        .Refractive_index = 1,
    };
}

/// Posicion compartida por la esfera visible y la luz puntual que representa.
pub const sun_position = rl.Vector3{ .x = 12.5, .y = 0, .z = -60 };

/// La nave ocupa objects[0] y el sol ocupa objects[1].
pub const sun_object_index: usize = 1;

pub fn createSun() Forma {
    return .{
        .Sphere = .{
            .center = sun_position,
            .radius = 5,
            // Ambient = 1 hace que el sol sea emisivo visualmente: no depende de
            // recibir su propia luz para conservar su color.
            .material = .{
                .Color = V3FromColor(htmlColor("#ffd27a")),
                .Ambient = 1,
                .Propiedades = .{
                    .Albedo = 0,
                    .Especular = 0,
                    .Reflectividad = 0,
                    .Transparencia = 0,
                },
                .Especular = 1,
                .Refractive_index = 1,
            },
        },
    };
}
