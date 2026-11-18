const std = @import("std");
const rl = @import("raylib");

const Forma = @import("../formas/formas.zig").Forma;
const Material = @import("../raytracer/raytracer.zig").Material;
const Texture = @import("../raytracer/textures.zig").Texture;
const V3FromColor = @import("../raytracer/raytracer.zig").V3FromColor;
const htmlColor = @import("../raytracer/cute_colors.zig").htmlColor;

pub const sun_texture_path = "assets/textures/sun-texture.png";

pub const PlanetSpec = struct {
    texture_path: [:0]const u8,
    position: rl.Vector3,
    radius: f32,
    /// Velocidad angular de la orbita, en radianes por segundo.
    orbital_speed: f32,
};

/// Sistema planetario compacto. Las distancias orbitales aumentan desde
/// Mercurio hasta Jupiter, aunque los tamanos estan exagerados para que los
/// planetas sigan siendo visibles durante la navegacion.
/// texturas: https://space.jpl.nasa.gov/tmaps/
pub const planet_specs = [_]PlanetSpec{
    .{
        .texture_path = "assets/textures/mercury.png",
        .position = .{ .x = 26.5, .y = 2, .z = -52 },
        .radius = 1.3,
        .orbital_speed = 0.55,
    },
    .{
        .texture_path = "assets/textures/venus.png",
        .position = .{ .x = -7.5, .y = -3, .z = -43 },
        .radius = 2,
        .orbital_speed = 0.42,
    },
    .{
        .texture_path = "assets/textures/earth.png",
        .position = .{ .x = 22.5, .y = 5, .z = -99 },
        .radius = 2.1,
        .orbital_speed = 0.32,
    },
    .{
        .texture_path = "assets/textures/mars.png",
        .position = .{ .x = 62.5, .y = 8, .z = -37 },
        .radius = 1.6,
        .orbital_speed = 0.24,
    },
    .{
        .texture_path = "assets/textures/jupiter.png",
        .position = .{ .x = -67.5, .y = -15, .z = -101 },
        .radius = 6.5,
        .orbital_speed = 0.12,
    },
};

/// Posicion compartida por la esfera visible y la luz puntual que representa.
pub const sun_position = rl.Vector3{ .x = 12.5, .y = 0, .z = -60 };

/// Devuelve el angulo inicial del planeta alrededor del Sol en el plano XZ.
pub fn initialOrbitAngle(spec: PlanetSpec) f32 {
    return std.math.atan2(
        spec.position.z - sun_position.z,
        spec.position.x - sun_position.x,
    );
}
/// Inspirado en respuesta LLM de ChatGPT: https://chat.openai.com/share/0e7f3c8b-1d5a-4f6e-9c2b-0d8e1f3e4a5b
/// Calcula la posicion orbital sin alterar la altura inicial del planeta.
/// La distancia al Sol se obtiene de `spec.position`, por lo que cada planeta
/// conserva su propio radio orbital.
pub fn orbitalPosition(spec: PlanetSpec, angle: f32) rl.Vector3 {
    const offset_x = spec.position.x - sun_position.x;
    const offset_z = spec.position.z - sun_position.z;
    const orbital_radius = @sqrt(offset_x * offset_x + offset_z * offset_z);

    return .{
        .x = sun_position.x + @cos(angle) * orbital_radius,
        .y = spec.position.y,
        .z = sun_position.z + @sin(angle) * orbital_radius,
    };
}

/// La nave ocupa objects[0] y el sol ocupa objects[1].
pub const sun_object_index: usize = 1;

pub fn createSun(sun_texture: *const Texture) Forma {
    return .{
        .Sphere = .{
            .center = sun_position,
            .radius = 5,
            // Ambient = 1 hace que el sol sea emisivo visualmente: no depende de
            // recibir su propia luz para conservar su color.
            .material = .{
                .Texture = sun_texture,
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

pub fn createPlanet(spec: PlanetSpec, texture: *const Texture) Forma {
    return .{
        .Sphere = .{
            .center = spec.position,
            .radius = spec.radius,
            .material = .{
                .Texture = texture,
                .Color = V3FromColor(htmlColor("#fff")),
                // Una contribucion pequena permite reconocer el planeta
                // incluso cuando recibe la luz del sol en un angulo bajo.
                .Ambient = 0.08,
                .Propiedades = .{
                    .Albedo = 0.9,
                    .Especular = 0.05,
                    .Reflectividad = 0,
                    .Transparencia = 0,
                },
                .Especular = 24,
                .Refractive_index = 1,
            },
        },
    };
}
