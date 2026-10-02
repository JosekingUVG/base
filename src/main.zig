const std = @import("std");
const builtin = @import("builtin");

const rl = @import("raylib");
const Framebuffer = @import("dominio/framebuffer.zig").Framebuffer;
const Forma = @import("formas/formas.zig").Forma;
const Camera = @import("dominio/camera.zig").Camera;
const Light = @import("raytracer/raytracer.zig").Light;
const Intersect = @import("raytracer/raytracer.zig").Intersect;
const Material = @import("raytracer/raytracer.zig").Material;

const htmlColor = @import("raytracer/cute_colors.zig").htmlColor;
const V3FromColor = @import("raytracer/raytracer.zig").V3FromColor;
const V3ToColor = @import("raytracer/raytracer.zig").V3ToColor;

const Clock = std.Io.Clock.real;

const width = 1300;
const height = 900;

const block_sz = 100;

pub fn main() !void {
    // Variable para manejar la memoria de manera diferente dependiendo del modo de compilación
    var alloc = switch (builtin.mode) {
        // En modo debug, usamos un allocator que nos permite detectar fugas de memoria y errores de uso
        .Debug, .ReleaseSafe => std.heap.DebugAllocator(.{}).init,
        // En modo release, usamos un allocator más rápido y eficiente
        .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator,
    };
    // gpa es un alias para el allocator que vamos a usar en el resto del programa
    const gpa: std.mem.Allocator = switch (builtin.mode) {
        .Debug, .ReleaseSafe => alloc.allocator(),
        .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator,
    };
    // Defer para limpiar el allocator al final de la función main
    defer switch (builtin.mode) {
        .Debug, .ReleaseSafe => _ = alloc.deinit(),
        .ReleaseFast, .ReleaseSmall => {},
    };

    // threaded es un wrapper para manejar la entrada/salida de manera concurrente y segura
    var threaded: std.Io.Threaded = .init(gpa, .{});
    const io = threaded.io();

    // Inicializamos el framebuffer con el tamaño de la ventana y los colores de fondo y borde
    // .black, ... .white significa que el color de fondo es negro y el color de borde es blanco
    var framebuffer = Framebuffer.init(width, height, .black, .white);

    rl.initWindow(width, height, "Raytracer!!!");
    rl.setTraceLogLevel(.warning);
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var last_frame_time = Clock.now(io);
    // delta es la diferencia de tiempo entre el marco actual y el anterior
    var delta: i64 = 1;

    //ESPEJO:
    const espejo = Material{
        .Color = V3FromColor(htmlColor("#fff")),
        .Propiedades = .{
            .Albedo = 0, // albedo es la capacidad de dispersión de la luz
            .Especular = 1,
            .Reflectividad = 0.9,
            .Transparencia = 0,
        },
        .Especular = 100,
        .Refractive_index = 0,
    };

    // VIDRIO:
    const vidrio = Material{
        .Color = V3FromColor(htmlColor("#aaa")),
        .Propiedades = .{
            .Albedo = 0,
            .Especular = 0.5,
            .Reflectividad = 0.1,
            .Transparencia = 0.8,
        },
        .Especular = 125,
        .Refractive_index = 1.5,
    };

    // DIAMANTE:
    const diamante = Material{
        .Color = V3FromColor(htmlColor("#aaa")),
        .Propiedades = .{
            .Albedo = 0,
            .Especular = 0.5,
            .Reflectividad = 0.1,
            .Transparencia = 0.8,
        },
        .Especular = 125,
        .Refractive_index = 2.417,
    };

    // MARMOL:
    const marmol = Material{
        .Color = V3FromColor(htmlColor("#66664c")),
        .Propiedades = .{
            .Albedo = 0.4,
            .Especular = 0.3,
            .Reflectividad = 0,
            .Transparencia = 0,
        },
        .Especular = 10,
        .Refractive_index = 0,
    };

    const spheres = [_]Forma{
        .{ .Sphere = .{
            .center = .{ .x = 10, .y = 0, .z = -40 },
            .radius = 5,
            .material = espejo,
        } },
        .{ .Sphere = .{
            .center = .{ .x = 12.5, .y = 0, .z = -60 },
            .radius = 5,
            .material = .{
                .Color = V3FromColor(htmlColor("#4c1919")),
                .Propiedades = .{
                    .Albedo = 0.9,
                    .Especular = 0.1,
                    .Reflectividad = 0,
                    .Transparencia = 0,
                },
                .Especular = 10,
                .Refractive_index = 0,
            },
        } },
        .{ .Sphere = .{
            .center = .{ .x = 0, .y = 0, .z = 0 },
            .radius = 5,
            .material = marmol,
        } },
        .{ .Sphere = .{
            .center = .{ .x = 22, .y = 0, .z = -45 },
            .radius = 5,
            .material = espejo,
        } },
        .{ .Sphere = .{
            .center = .{ .x = -25, .y = 0, .z = -40 },
            .radius = 5,
            .material = vidrio,
        } },
        .{ .Sphere = .{
            .center = .{ .x = -37, .y = 0, .z = -40 },
            .radius = 5,
            .material = diamante,
        } },
    };

    // Luces de la escena
    const lights = [_]Light{
        .{
            // Corresponde a la luz roja que ilumina la escena desde arriba y a la derecha
            .Color = V3FromColor(htmlColor("#f00")),
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

    const cameraDistance = 100;
    var camera: Camera = .init(.{
        .x = 0,
        .y = 0,
        .z = cameraDistance,
    }, .zero());

    const cameraTurnSpeed: f32 = std.math.pi / 2.0;
    var camera_x_angle: f32 = std.math.pi;
    var camera_y_angle: f32 = 0;

    const camera_y_angle_max = std.math.pi / 4.0;
    const camera_y_angle_min = -camera_y_angle_max;

    while (!rl.windowShouldClose()) {
        defer {
            const now = Clock.now(io);
            delta = last_frame_time.durationTo(now).toMicroseconds();
            last_frame_time = now;
        }
        framebuffer.clear();

        const dt: f32 = @as(f32, @floatFromInt(delta)) / 1_000_000;

        // Control de la cámara con las teclas WASD
        if (rl.isKeyDown(.a)) {
            camera_x_angle += cameraTurnSpeed * dt;
        }
        if (rl.isKeyDown(.d)) {
            camera_x_angle -= cameraTurnSpeed * dt;
        }
        if (rl.isKeyDown(.w)) {
            camera_y_angle += cameraTurnSpeed * dt;
            camera_y_angle = @max(camera_y_angle_min, @min(camera_y_angle_max, camera_y_angle));
        }
        if (rl.isKeyDown(.s)) {
            camera_y_angle -= cameraTurnSpeed * dt;
            camera_y_angle = @max(camera_y_angle_min, @min(camera_y_angle_max, camera_y_angle));
        }

        // Actualizamos la posición de la cámara en función de los ángulos calculados
        camera.Postition.x = @cos(camera_x_angle) * cameraDistance;
        camera.Postition.y = @sin(camera_y_angle) * cameraDistance;
        camera.Postition.z = @sin(camera_x_angle) * cameraDistance;

        // Hacemos que la cámara mire hacia el origen (0, 0, 0)
        camera.lookAt(.zero());

        // Renderizamos la escena con las esferas, luces y cámara actuales
        try render(&framebuffer, &spheres, &lights, camera);

        // Dibujamos el framebuffer en la ventana de Raylib
        try framebuffer.swap_buffers();
    }
}

// Renderiza la escena en el framebuffer dado, usando las formas, luces y cámara proporcionadas
fn render(target: *Framebuffer, objects: []const Forma, lights: []const Light, camera: Camera) !void {
    const width_f32: f32 = @floatFromInt(target.width);
    const height_f32: f32 = @floatFromInt(target.height);

    const aspect_ratio = width_f32 / height_f32;
    const FOV = std.math.pi / 3.0;
    // tan de FOV/2 nos da la escala de la perspectiva, que es la relación entre la altura de la imagen y la distancia focal
    const perspective_scale = @tan(FOV * 0.5);

    // Iteramos sobre cada píxel de la pantalla y calculamos el color correspondiente usando ray tracing
    // La idea es que para cada píxel, generamos un rayo desde la cámara hacia el mundo 3D, y vemos qué objeto (si hay alguno) intersecta con ese rayo.
    // Luego calculamos el color del píxel en función de la luz y el material del objeto intersectado.
    for (0..height) |screen_y| {
        for (0..width) |screen_x| {
            const x_f32: f32 = @floatFromInt(screen_x);
            const y_f32: f32 = @floatFromInt(screen_y);

            const x_minus1_to_1 = (x_f32 * 2) / width_f32 - 1;
            const y_minus1_to_1 = 1 - (y_f32 * 2) / height_f32;

            const x_direction = x_minus1_to_1 * aspect_ratio * perspective_scale;
            const y_direction = y_minus1_to_1 * perspective_scale;

            const direction_from_camera = (rl.Vector3{
                .x = x_direction,
                .y = y_direction,
                .z = 1,
            }).normalize();

            const direction = rl.Vector3{
                .x = direction_from_camera.x * camera.Right.x + direction_from_camera.y * camera.Up.x + direction_from_camera.z * camera.Forward.x,
                .y = direction_from_camera.x * camera.Right.y + direction_from_camera.y * camera.Up.y + direction_from_camera.z * camera.Forward.y,
                .z = direction_from_camera.x * camera.Right.z + direction_from_camera.y * camera.Up.z + direction_from_camera.z * camera.Forward.z,
            };

            const col = cast_ray(camera.Postition, direction, objects, lights, 5);
            target.set_current_color(V3ToColor(col));
            try target.set_pixel(@intCast(screen_x), @intCast(screen_y));
        }
    }
}

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
fn cast_ray(origin: rl.Vector3, direction: rl.Vector3, objects: []const Forma, lights: []const Light, max_recursion: usize) rl.Vector3 {
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
        var color: rl.Vector3 = .zero();

        // Dirección desde el punto hacia la cámara.
        const view_direction = direction.scale(-1);

        if (mat.Propiedades.Reflectividad > 0) {
            if (max_recursion > 0) {
                const reflect_direction =
                    rl.Vector3.reflect(direction, hit.Normal);

                // Pequeño desplazamiento para no volver a golpear
                // inmediatamente la misma superficie.
                const new_origin =
                    hit.Punto.add(hit.Normal.scale(0.001));

                const reflect_color = cast_ray(
                    new_origin,
                    reflect_direction,
                    objects,
                    lights,
                    max_recursion - 1,
                );

                color = color.add(
                    reflect_color.scale(
                        mat.Propiedades.Reflectividad,
                    ),
                );
            }
        }

        if (mat.Propiedades.Transparencia > 0) {
            if (max_recursion > 0) {
                if (refract(
                    direction,
                    hit.Normal,
                    mat.Refractive_index,
                )) |refract_direction| {
                    // Para refractar debemos entrar al objeto,
                    // por eso avanzamos contra la normal.
                    const new_origin =
                        hit.Punto.subtract(hit.Normal.scale(0.001));

                    const refract_color = cast_ray(
                        new_origin,
                        refract_direction,
                        objects,
                        lights,
                        max_recursion - 1,
                    );

                    color = color.add(
                        refract_color.scale(
                            mat.Propiedades.Transparencia,
                        ),
                    );
                }
            }
        }

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
                    @max(
                        view_direction.dotProduct(reflection_dir),
                        0,
                    ),
                    mat.Especular,
                ) * light.Intensity;

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

    return V3FromColor(htmlColor("#87ceeb"));
}

fn obscured(origin: rl.Vector3, light: Light, objects: []const Forma, normal: rl.Vector3) bool {
    const point_to_light = light.Position.subtract(origin);

    const light_distance = point_to_light.length();

    const light_direction = point_to_light.normalize();

    const shadow_origin = origin.add(normal.scale(0.001));

    // Iteramos sobre todos los objetos de la escena y calculamos si el rayo que va desde el punto hacia la luz intersecta con algún objeto antes de llegar a la luz
    for (objects) |object| {
        const hit = object.intersect(
            shadow_origin,
            light_direction,
        ) orelse continue; // si no hay intersección, pasamos al siguiente objeto

        // Si la distancia de la intersección es menor que la distancia a la luz, significa que el punto está en sombra
        if (hit.Distancia < light_distance) {
            return true;
        }
    }

    return false;
}
