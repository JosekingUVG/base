const std = @import("std");
const rl = @import("raylib");
const Texture = @import("textures.zig").Texture;
const Forma = @import("../formas/formas.zig").Forma;
const htmlColor = @import("cute_colors.zig").htmlColor;
const obscured = @import("sombras.zig").obscured;

pub fn V3FromColor(src: rl.Color) rl.Vector3 {
    const x: f32 = @floatFromInt(src.r);
    const y: f32 = @floatFromInt(src.g);
    const z: f32 = @floatFromInt(src.b);
    return .{ .x = x / 255, .y = y / 255, .z = z / 255 };
}

pub fn V3ToColor(color: rl.Vector3) rl.Color {
    const r: u8 = @intFromFloat(@max(0, @min(255, color.x * 255)));
    const g: u8 = @intFromFloat(@max(0, @min(255, color.y * 255)));
    const b: u8 = @intFromFloat(@max(0, @min(255, color.z * 255)));
    return .{ .r = r, .g = g, .b = b, .a = 0xff };
}

pub const Light = struct {
    Color: rl.Vector3,
    Position: rl.Vector3,
    Intensity: f32,
};

// Material que representa las propiedades ópticas de una superfficie, en este caso, el entorno de la escena. Se utiliza para calcular la iluminación difusa y especular de los objetos en la escena.
pub const Material = struct {
    //xyz como rgb, pero reducimos conversiones primero haciendo mate en f32 y luego convertimos de regreso a u8
    Color: rl.Vector3,
    Especular: f32,
    Refractive_index: f32,
    Texture: ?*const Texture = null,
    // Luz ambiental neutra aproximada; 0 conserva la iluminacion directa.
    Ambient: f32 = 0.0,
    // proporciones, de 0 a 1, de cuanto refleja y cuanto deja pasar la luz
    Propiedades: struct {
        Albedo: f32,
        Especular: f32,
        Reflectividad: f32,
        Transparencia: f32,
    },

    pub fn surfaceColor(
        self: Material,
        uv: rl.Vector2,
    ) rl.Vector3 {
        if (self.Texture) |texture| {
            return texture.sample(uv);
        }

        return self.Color;
    }
};

pub const Intersect = struct {
    Material: Material,
    Distancia: f32,
    Normal: rl.Vector3,
    Punto: rl.Vector3,
    UV: rl.Vector2,
};

// Función que calcula la refracción de un rayo incidente en una superficie con un índice de refracción dado
fn refract(incident: rl.Vector3, normal: rl.Vector3, refractive_index: f32) ?rl.Vector3 {
    var cosi = incident.dotProduct(normal);

    var etai: f32 = 1;
    var etat = refractive_index;
    var n = normal;

    if (cosi > 0) {
        std.mem.swap(f32, &etai, &etat);
        n = n.scale(-1);
    } else {
        cosi = -cosi;
    }

    const eta = etai / etat;
    const k = 1 - eta * eta * (1 - cosi * cosi);

    if (k < 0) {
        return null;
    } else {
        return (incident.scale(eta).add(n.scale(eta * cosi - @sqrt(k)))).normalize();
    }
}

// Función que lanza un rayo desde el origen en la dirección dada, y devuelve el color resultante
pub fn cast_ray(origin: rl.Vector3, direction: rl.Vector3, objects: []const Forma, lights: []const Light, max_recursion: usize) rl.Vector3 {
    // Buscamos la intersección más cercana del rayo con los objetos de la escena
    var closest_hit: ?Intersect = null;
    // z_buffer es la distancia al objeto más cercano que hemos encontrado hasta ahora
    var z_buffer: f32 = std.math.floatMax(f32);

    // Iteramos sobre todos los objetos de la escena y calculamos si el rayo intersecta con ellos
    for (objects) |object| {
        const hit = object.intersect(
            origin,
            direction,
        ) orelse continue; // si no hay intersección, pasamos al siguiente objeto

        // Si la distancia de la intersección es menor que la distancia al objeto más cercano que hemos encontrado hasta ahora, actualizamos closest_hit y z_buffer
        if (hit.Distancia < z_buffer) {
            z_buffer = hit.Distancia;

            closest_hit = hit;
        }
    }

    if (closest_hit) |hit| {
        const mat = hit.Material;

        // Primero averiguamos cuál es el color propio de este punto.
        //
        // Si el material tiene textura:
        //     usa hit.UV para leer un píxel.
        //
        // Si no tiene textura:
        //     usa mat.Color.
        const surface_color = mat.surfaceColor(hit.UV);

        // Aquí acumularemos luz, reflejos y refracción.
        var color = surface_color.scale(mat.Ambient);

        // Dirección desde el punto hacia la cámara.
        const view_direction = direction.scale(-1);

        // Si el material tiene reflectividad, calculamos el color reflejado y lo añadimos al color final.
        if (mat.Propiedades.Reflectividad > 0) {
            if (max_recursion > 0) {
                const reflect_direction =
                    rl.Vector3.reflect(direction, hit.Normal);

                // Pequeño desplazamiento para no volver a golpear
                // inmediatamente la misma superficie.
                const new_origin =
                    hit.Punto.add(hit.Normal.scale(0.001));

                // Llamamos recursivamente a cast_ray para calcular el color reflejado.

                const reflect_color = cast_ray(
                    new_origin,
                    reflect_direction,
                    objects,
                    lights,
                    max_recursion - 1, // recursión decreciente para evitar bucles infinitos
                );

                // añadimos el color reflejado al color final, escalado por la reflectividad del material
                color = color.add(
                    reflect_color.scale(
                        mat.Propiedades.Reflectividad,
                    ),
                );
            }
        }

        // Si el material tiene transparencia, calculamos el color refractado y lo añadimos al color final.
        if (mat.Propiedades.Transparencia > 0) {
            if (max_recursion > 0) {
                // si la refracción es posible, calculamos el color refractado y lo añadimos al color final
                if (refract(
                    direction,
                    hit.Normal,
                    mat.Refractive_index,
                )) |refract_direction| {
                    // Para refractar debemos entrar al objeto,
                    // por eso avanzamos contra la normal.
                    const new_origin =
                        hit.Punto.subtract(hit.Normal.scale(0.001));

                    // Llamamos recursivamente a cast_ray para calcular el color refractado.
                    const refract_color = cast_ray(
                        new_origin,
                        refract_direction,
                        objects,
                        lights,
                        max_recursion - 1,
                    );

                    // añadimos el color refractado al color final, escalado por la transparencia del material
                    color = color.add(
                        refract_color.scale(
                            mat.Propiedades.Transparencia,
                        ),
                    );
                }
            }
        }

        // Calculamos la iluminación difusa y especular de cada luz en la escena.
        for (lights) |light| {
            if (obscured(
                hit.Punto,
                light,
                objects,
                hit.Normal,
            )) {
                continue;
            }

            const light_dir =
                light.Position.subtract(hit.Punto).normalize();

            const diffuse_intensity =
                @max(
                    light_dir.dotProduct(hit.Normal),
                    0,
                ) * light.Intensity;

            // Calculamos el color de la superficie iluminada por la luz, multiplicando el color de la superficie por el color de la luz.
            const illuminated_surface = rl.Vector3{
                .x = surface_color.x * light.Color.x,
                .y = surface_color.y * light.Color.y,
                .z = surface_color.z * light.Color.z,
            };

            const diffuse =
                illuminated_surface.scale(diffuse_intensity);

            // Antes usabas mat.Color.
            // Ahora usamos el color del punto de la textura
            // o el color normal del material.

            const reflection_dir = rl.Vector3.reflect(
                light_dir.scale(-1),
                hit.Normal,
            );

            const specular_intensity =
                std.math.pow(
                    f32,
                    // Calculamos el coseno del ángulo entre la dirección de la vista y la dirección de reflexión de la luz.
                    // Si el ángulo es pequeño, el coseno es cercano a 1 y la intensidad especular es alta. Si el ángulo es grande, el coseno es cercano a 0 y la intensidad especular es baja.
                    @max(
                        view_direction.dotProduct(reflection_dir),
                        0,
                    ),
                    mat.Especular,
                ) * light.Intensity;

            // cAlculamos el color especular de la luz, multiplicando el color de la luz por la intensidad especular y por el color del material.
            const specular =
                light.Color.scale(specular_intensity);

            color = color.add(
                diffuse.scale(mat.Propiedades.Albedo),
            );

            color = color.add(
                specular.scale(mat.Propiedades.Especular),
            );
        }

        return color;
    }

    return V3FromColor(htmlColor("#87ceeb")); // color de fondo: azul cielo
}
