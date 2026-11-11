const std = @import("std");
const rl = @import("raylib");

const Forma = @import("../formas/formas.zig").Forma;
const Material = @import("../raytracer/raytracer.zig").Material;
const Texture = @import("../raytracer/textures.zig").Texture;
const Mesh = @import("../formas/modelos/mesh.zig").Mesh;
const V3FromColor = @import("../raytracer/raytracer.zig").V3FromColor;
const htmlColor = @import("../raytracer/cute_colors.zig").htmlColor;

pub const model_texture_path = "assets/nave/texture.png";
pub const model_path = "assets/nave/nave.obj";

/// Centro de la nave en coordenadas del mundo.
pub const model_center = rl.Vector3{ .x = 0, .y = 10, .z = 0 };

/// La nave original ocupa aproximadamente 4.2 unidades de largo.
/// Una escala de 12 mantiene el detalle sin llenar toda la pantalla.
pub const model_scale: f32 = 12;

/// Vista inicial: detrás de la nave, 30 grados por debajo y ligeramente
/// desplazada hacia un costado para mostrar también su silueta lateral.
pub const initial_camera_position = rl.Vector3{
    .x = -120,
    .y = 40,
    .z = -30,
};

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

pub fn create(mesh: Mesh, model_material: Material) Forma {
    const bounds = calculateBounds(mesh);
    const position = model_center.subtract(
        bounds.center.scale(model_scale),
    );

    return .{
        .Model = .{
            .mesh = mesh,
            // Compensa el origen desplazado del OBJ para que el centro real de
            // la geometría termine exactamente en model_center.
            .position = position,
            .scale = model_scale,
            .bounding_sphere = .{
                .center = model_center,
                // Un pequeño margen evita recortes por redondeo de f32.
                .radius = bounds.radius * model_scale * 1.01,
                .material = model_material,
            },
        },
    };
}

const Bounds = struct {
    center: rl.Vector3,
    radius: f32,
};

/// Calcula una esfera que contiene toda la malla, incluso si el OBJ es
/// rectangular o si su origen está lejos del centro de la geometría.
fn calculateBounds(mesh: Mesh) Bounds {
    std.debug.assert(mesh.triangles.len > 0);

    const first = mesh.triangles[0].a.position;
    var minimum = first;
    var maximum = first;

    for (mesh.triangles) |triangle| {
        for ([_]rl.Vector3{
            triangle.a.position,
            triangle.b.position,
            triangle.c.position,
        }) |vertex| {
            minimum.x = @min(minimum.x, vertex.x);
            minimum.y = @min(minimum.y, vertex.y);
            minimum.z = @min(minimum.z, vertex.z);
            maximum.x = @max(maximum.x, vertex.x);
            maximum.y = @max(maximum.y, vertex.y);
            maximum.z = @max(maximum.z, vertex.z);
        }
    }

    const center = minimum.add(maximum).scale(0.5);
    var radius_squared: f32 = 0;

    for (mesh.triangles) |triangle| {
        for ([_]rl.Vector3{
            triangle.a.position,
            triangle.b.position,
            triangle.c.position,
        }) |vertex| {
            const offset = vertex.subtract(center);
            radius_squared = @max(
                radius_squared,
                offset.dotProduct(offset),
            );
        }
    }

    return .{
        .center = center,
        .radius = @sqrt(radius_squared),
    };
}
