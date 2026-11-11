// Configuración del modelo de prueba asistida por OpenAI Codex (2026-11-09).
// El koala permanece fijo por ahora; luego esta configuración alojará la nave.
const Forma = @import("../formas/formas.zig").Forma;
const Material = @import("../raytracer/raytracer.zig").Material;
const Texture = @import("../raytracer/textures.zig").Texture;
const Mesh = @import("../formas/modelos/mesh.zig").Mesh;
const V3FromColor = @import("../raytracer/raytracer.zig").V3FromColor;
const htmlColor = @import("../raytracer/cute_colors.zig").htmlColor;

pub const model_texture_path = "assets/nave/texture.png";
// Modelo extraído de https://kenney.nl/assets/cube-pets
pub const model_path = "assets/nave/nave.obj";

pub fn material(model_texture: *const Texture) Material {
    return .{
        .Texture = model_texture,
        .Ambient = 0.6,
        .Color = V3FromColor(htmlColor("#fff")),
        .Propiedades = .{
            .Albedo = 0.4,
            .Especular = 0.0,
            .Reflectividad = 0.0,
            .Transparencia = 0.0,
        },
        .Especular = 1000,
        .Refractive_index = 1.0,
    };
}

// Por ahora el koala permanece en el origen para comprobar que la cámara
// realmente puede trasladarse y rotar alrededor de un objeto fijo.
pub fn create(mesh: Mesh, model_material: Material) Forma {
    return .{
        .Model = .{
            .mesh = mesh,
            .position = .{ .x = 0, .y = -5, .z = 0 },
            .scale = 20,
            .bounding_sphere = .{
                .center = .{ .x = 0, .y = 10, .z = 0 },
                .radius = 30,
                .material = model_material,
            },
        },
    };
}
