const std = @import("std");
const builtin = @import("builtin");

const rl = @import("raylib");
const Framebuffer = @import("dominio/framebuffer.zig").Framebuffer;
const Forma = @import("formas/formas.zig").Forma;
const Camera = @import("dominio/camera.zig").Camera;
const Light = @import("raytracer/raytracer.zig").Light;
const Intersect = @import("raytracer/raytracer.zig").Intersect;
const Material = @import("raytracer/raytracer.zig").Material;
const Texture = @import("raytracer/textures.zig").Texture;
const Mesh = @import("formas/modelos/mesh.zig").Mesh;

const htmlColor = @import("raytracer/cute_colors.zig").htmlColor;
const V3FromColor = @import("raytracer/raytracer.zig").V3FromColor;
const V3ToColor = @import("raytracer/raytracer.zig").V3ToColor;

const Clock = std.Io.Clock.real;

const width = 1300;
const height = 900;

const near_distance: f32 = 70;
const min_distance: f32 = 15;
const max_distance: f32 = 250;

pub fn main() !void {

    // Implementación de la concurrencia, inspirado en https://akhil.sh/tutorials/zig/zig/concurrency_in_zig/
    // Respaldado con chatgpt: https://chatgpt.com/share/e/6ad05fa5-fa94-83e8-b9f4-06f5b300f1f2

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
    defer threaded.deinit();
    const io = threaded.io();
    const worker_count = @max(1, std.Thread.getCpuCount() catch 1);

    // Inicializamos el framebuffer con el tamaño de la ventana y los colores de fondo y borde
    // .black, ... .white significa que el color de fondo es negro y el color de borde es blanco
    var framebuffer = Framebuffer.init(width, height, .black, .white);

    rl.initWindow(width, height, "Raytracer!!!");
    rl.setTraceLogLevel(.warning);
    defer rl.closeWindow();
    defer framebuffer.deinit();
    rl.setTargetFPS(60);

    var floor_texture = Texture.load(
        gpa,
        "assets/plane/textures/hinoki_planks_disp_4k.png",
    ) catch |err| {
        std.debug.print(
            "No se pudo cargar la textura: {}\n",
            .{err},
        );
        return err;
    };
    defer floor_texture.deinit();

    // Modelo extraído de https://kenney.nl/assets/cube-pets

    var model_texture = try Texture.load(
        gpa,
        "assets/koala/colormap.png",
    );
    defer model_texture.deinit();

    const model_material = Material{
        .Texture = &model_texture,
        // Conserva el color de la textura incluso fuera de la luz directa.
        .Ambient = 0.6,

        // La textura define el color; blanco no la modifica.
        .Color = V3FromColor(htmlColor("#fff")),

        .Propiedades = .{
            .Albedo = 0.4,
            .Especular = 0.0,
            .Reflectividad = 0.0,
            .Transparencia = 0.0,
        },

        // No influye mientras Propiedades.Especular sea 0.
        .Especular = 1000,

        // Tampoco influye mientras Transparencia sea 0.
        .Refractive_index = 1.0,
    };

    var mesh = try Mesh.loadObj(
        gpa,
        io,
        "assets/koala/Untitled.obj",
        model_material,
    );
    defer mesh.deinit();

    // 1. Medir el modelo tal como viene del OBJ.
    // Buscamos una caja que contenga todos sus vértices:
    // model_min es la esquina con las coordenadas menores;
    // model_max es la esquina con las coordenadas mayores.
    // Este recorrido solo lee posiciones, no modifica los triángulos.
    const first_position = mesh.triangles[0].a.position; // loadObj rechaza mallas vacías.
    var model_min = first_position;
    var model_max = first_position;

    for (mesh.triangles) |triangle| {
        const positions = [_]rl.Vector3{
            triangle.a.position,
            triangle.b.position,
            triangle.c.position,
        };

        for (positions) |position| {
            model_min.x = @min(model_min.x, position.x);
            model_min.y = @min(model_min.y, position.y);
            model_min.z = @min(model_min.z, position.z);

            model_max.x = @max(model_max.x, position.x);
            model_max.y = @max(model_max.y, position.y);
            model_max.z = @max(model_max.z, position.z);
        }
    }

    // El punto medio entre las dos esquinas es el centro de la caja.
    // No necesariamente coincide con el origen del archivo OBJ.
    const model_center = model_min.add(model_max).scale(0.5);

    // 2. Decidir el tamaño y la posición en nuestra escena.
    const model_scale: f32 = 20; // Multiplica por 20 el tamaño original.
    const floor_y: f32 = -5; // Misma altura que el plano de la escena.
    const scaled_center = model_center.scale(model_scale);
    const scaled_bottom_y = model_min.y * model_scale;

    // Después de escalar, trasladamos el modelo:
    // - En X y Z, restamos su centro para dejarlo centrado en 0.
    // - En Y, llevamos su punto más bajo hasta la altura del piso.
    // Ejemplo: si la base escalada está en Y=2, moverla -7 la deja en -5.
    const model_offset = rl.Vector3{
        .x = -scaled_center.x,
        .y = floor_y - scaled_bottom_y,
        .z = -scaled_center.z,
    };

    // 3. Aplicar el cambio a cada vértice: posición nueva = posición * escala + traslado.
    // |*triangle| obtiene un puntero para modificar el triángulo guardado en la malla.
    // No interpolamos ni creamos triángulos; cambiamos sus posiciones.
    // Los UV se conservan. Las normales también, porque la escala es uniforme y positiva.
    for (mesh.triangles) |*triangle| {
        triangle.a.position = triangle.a.position.scale(model_scale).add(model_offset);
        triangle.b.position = triangle.b.position.scale(model_scale).add(model_offset);
        triangle.c.position = triangle.c.position.scale(model_scale).add(model_offset);
    }

    // 4. Crear una esfera invisible que encierre el modelo ya colocado.
    // El raytracer la usa para descartar rayos que no pueden tocar el modelo
    // sin tener que revisar todos sus triángulos.
    const model_bounds_center = scaled_center.add(model_offset);
    const box_size = model_max.subtract(model_min);
    const scaled_box_diagonal = box_size.length() * model_scale;

    // Desde el centro de la caja hasta una esquina hay media diagonal.
    // Ese radio encierra toda la caja y, por tanto, todo el modelo.
    const rounding_margin: f32 = 0.001;
    const model_bounds_radius = scaled_box_diagonal * 0.5 + rounding_margin;

    var last_frame_time = Clock.now(io);
    // delta es la diferencia de tiempo entre el marco actual y el anterior
    var delta: i64 = 1;

    //ESPEJO:
    //const espejo = Material{
    //    .Color = V3FromColor(htmlColor("#fff")),
    //    .Propiedades = .{
    //        .Albedo = 0, // albedo es la capacidad de dispersión de la luz
    //        .Especular = 1,
    //        .Reflectividad = 0.9,
    //        .Transparencia = 0,
    //    },
    //    .Especular = 100,
    //    .Refractive_index = 0,
    // };

    // Plano
    const floor_material = Material{
        .Color = V3FromColor(htmlColor("#fff")),
        .Texture = &floor_texture,

        // Propiedes extraidas de  https://www.lifeder.com/propiedades-opticas-materiales/ y https://gemini.com
        .Propiedades = .{
            .Albedo = 0.4,
            .Especular = 0.5,
            .Reflectividad = 0.1,
            .Transparencia = 0,
        },

        .Especular = 100,
        .Refractive_index = 1.5,
    };

    // VIDRIO:
    //const vidrio = Material{
    //    .Color = V3FromColor(htmlColor("#aaa")),
    //    .Propiedades = .{
    //        .Albedo = 0,
    //        .Especular = 0.5,
    //        .Reflectividad = 0.1,
    //       .Transparencia = 0.8,
    //   },
    //   .Especular = 125,
    //   .Refractive_index = 1.5,
    //};

    // DIAMANTE:
    //const diamante = Material{
    //   .Color = V3FromColor(htmlColor("#aaa")),
    //   .Propiedades = .{
    //       .Albedo = 0,
    //       .Especular = 0.5,
    //       .Reflectividad = 0.1,
    //       .Transparencia = 0.8,
    //   },
    //   .Refractive_index = 2.417,
    //   .Especular = 125,
    //};

    // MARMOL:
    //const marmol = Material{
    //    .Color = V3FromColor(htmlColor("#66664c")),
    //    .Propiedades = .{
    //        .Albedo = 0.4,
    //        .Especular = 0.3,
    //        .Reflectividad = 0,
    //        .Transparencia = 0,
    //    },
    //    .Especular = 10,
    //    .Refractive_index = 0,
    //};

    const spheres = [_]Forma{

        // Modelo 3D:
        .{ .Model = .{
            .mesh = mesh,
            .bounding_sphere = .{
                .center = model_bounds_center,
                .radius = model_bounds_radius,
                .material = model_material,
            },
        } },
        //.{ .Sphere = .{
        //    .center = .{ .x = 10, .y = 0, .z = -40 },
        //    .radius = 5,
        //    .material = espejo,
        //} },
        //.{ .Sphere = .{
        //    .center = .{ .x = 12.5, .y = 0, .z = -60 },
        //    .radius = 5,
        //    .material = .{
        //        .Color = V3FromColor(htmlColor("#fff")),
        //        .Propiedades = .{
        //            .Albedo = 0.9,
        //            .Especular = 0.1,
        //            .Reflectividad = 0,
        //            .Transparencia = 0,
        //        },
        //        .Especular = 10,
        //        .Refractive_index = 0,
        //    },
        //} },

        // Plano:

        .{ .Plane = .{
            .p_0 = .{ .x = 0, .y = -5, .z = 0 },
            .normal = .{ .x = 0, .y = 1, .z = 0 },

            .u_axis = .{ .x = 1, .y = 0, .z = 0 },
            .v_axis = .{ .x = 0, .y = 0, .z = 1 },

            .u_size = 10,
            .v_size = 10,

            .material = floor_material,
        } }, //,

        //.{ .Sphere = .{
        //    .center = .{ .x = 0, .y = 0, .z = 0 },
        //    .radius = 5,
        //    .material = marmol,
        //} },
        //.{ .Sphere = .{
        //    .center = .{ .x = 22, .y = 0, .z = -45 },
        //    .radius = 5,
        //    .material = espejo,
        //} },
        //.{ .Sphere = .{
        //    .center = .{ .x = -25, .y = 0, .z = -40 },
        //    .radius = 5,
        //    .material = vidrio,
        //} },
        //.{ .Sphere = .{
        //    .center = .{ .x = -37, .y = 0, .z = -40 },
        //    .radius = 5,
        //    .material = diamante,
        //} },
    };

    // Luces de la escena
    const lights = [_]Light{
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

    var cameraDistance: f32 = 100;
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

    var has_rendered = false;
    var was_moving = false;

    while (!rl.windowShouldClose()) {
        defer {
            const now = Clock.now(io);
            delta = last_frame_time.durationTo(now).toMicroseconds();
            last_frame_time = now;
        }
        const dt: f32 = @as(f32, @floatFromInt(delta)) / 1_000_000;
        const old_x_angle = camera_x_angle;
        const old_y_angle = camera_y_angle;
        const old_distance = cameraDistance;

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

        const wheel = rl.getMouseWheelMove();
        cameraDistance = std.math.clamp(cameraDistance - wheel * 5, min_distance, max_distance);
        const moving = camera_x_angle != old_x_angle or
            camera_y_angle != old_y_angle or cameraDistance != old_distance;

        // Actualizamos la posición de la cámara en función de los ángulos calculados
        camera.Postition.x = @cos(camera_x_angle) * cameraDistance;
        camera.Postition.y = @sin(camera_y_angle) * cameraDistance;
        camera.Postition.z = @sin(camera_x_angle) * cameraDistance;

        // Hacemos que la cámara mire hacia el origen (0, 0, 0)
        camera.lookAt(.zero());

        // Durante el movimiento usamos bloques grandes. Al detenerse, refinamos
        // una vez y reutilizamos esa imagen mientras la escena no cambie.
        const needs_render = !has_rendered or moving or was_moving;
        if (needs_render) {
            const pixel_block: usize = if (moving) 4 else if (cameraDistance > near_distance) 2 else 1;
            try render(io, worker_count, &framebuffer, &spheres, &lights, camera, pixel_block);
            has_rendered = true;
        }
        was_moving = moving;

        // Dibujamos el framebuffer en la ventana de Raylib
        try framebuffer.swap_buffers(needs_render);
    }
}

// El pool de std.Io.Threaded vive durante toda la aplicación y reutiliza hilos.
// Cada trabajador reclama una franja completa; solo el contador es compartido
// con escritura. La escena y la cámara no cambian hasta terminar el grupo.
const RenderJob = struct {
    pixels: []rl.Color,
    image_width: usize,
    image_height: usize,
    objects: []const Forma,
    lights: []const Light,
    camera: Camera,
    pixel_block: usize,
    stripe_height: usize,
    aspect_ratio: f32,
    perspective_scale: f32,
    next_y: std.atomic.Value(usize) = .init(0),

    fn init(target: *Framebuffer, objects: []const Forma, lights: []const Light, camera: Camera, pixel_block: usize) RenderJob {
        std.debug.assert(pixel_block > 0);
        return .{
            .pixels = target.pixels(),
            .image_width = @intCast(target.width),
            .image_height = @intCast(target.height),
            .objects = objects,
            .lights = lights,
            .camera = camera,
            .pixel_block = pixel_block,
            // Aproximadamente 16 filas, siempre alineadas con los bloques.
            .stripe_height = @max(1, 16 / pixel_block) * pixel_block,
            .aspect_ratio = @as(f32, @floatFromInt(target.width)) / @as(f32, @floatFromInt(target.height)),
            .perspective_scale = @tan(std.math.pi / 6.0),
        };
    }

    fn work(job: *RenderJob) void {
        while (true) {
            const first_y = job.next_y.fetchAdd(job.stripe_height, .monotonic);
            if (first_y >= job.image_height) return;
            job.renderStripe(first_y, @min(first_y + job.stripe_height, job.image_height));
        }
    }

    fn renderStripe(job: *const RenderJob, first_y: usize, end_y: usize) void {
        const width_f32: f32 = @floatFromInt(job.image_width);
        const height_f32: f32 = @floatFromInt(job.image_height);
        const camera = job.camera;
        var screen_y = first_y;
        while (screen_y < end_y) : (screen_y += job.pixel_block) {
            const y_f32: f32 = @floatFromInt(screen_y);
            const y_direction = (1 - (y_f32 * 2) / height_f32) * job.perspective_scale;
            var screen_x: usize = 0;
            while (screen_x < job.image_width) : (screen_x += job.pixel_block) {
                const x_f32: f32 = @floatFromInt(screen_x);
                const x_direction = ((x_f32 * 2) / width_f32 - 1) * job.aspect_ratio * job.perspective_scale;
                const ray = (rl.Vector3{ .x = x_direction, .y = y_direction, .z = 1 }).normalize();
                const direction = rl.Vector3{
                    .x = ray.x * camera.Right.x + ray.y * camera.Up.x + ray.z * camera.Forward.x,
                    .y = ray.x * camera.Right.y + ray.y * camera.Up.y + ray.z * camera.Forward.y,
                    .z = ray.x * camera.Right.z + ray.y * camera.Up.z + ray.z * camera.Forward.z,
                };
                const color = V3ToColor(cast_ray(camera.Postition, direction, job.objects, job.lights, 5));
                const end_x = @min(screen_x + job.pixel_block, job.image_width);
                for (screen_y..@min(screen_y + job.pixel_block, end_y)) |y| {
                    const row = y * job.image_width;
                    @memset(job.pixels[row + screen_x .. row + end_x], color);
                }
            }
        }
    }
};

fn render(io: std.Io, worker_count: usize, target: *Framebuffer, objects: []const Forma, lights: []const Light, camera: Camera, pixel_block: usize) !void {
    var job = RenderJob.init(target, objects, lights, camera, pixel_block);
    const stripe_count = std.math.divCeil(usize, job.image_height, job.stripe_height) catch unreachable;
    const workers = @max(1, @min(worker_count, stripe_count));
    var group: std.Io.Group = .init;
    defer group.cancel(io);
    for (1..workers) |_| {
        // Si no hay recursos para otro hilo, los existentes y main terminan
        // las franjas pendientes sin descartar el fotograma.
        group.concurrent(io, RenderJob.work, .{&job}) catch break;
    }
    job.work();
    try group.await(io);
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
        var color = surface_color.scale(mat.Ambient);

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

// Oráculo secuencial: conserva las operaciones de proyección del render original.
fn renderReference(target: *Framebuffer, objects: []const Forma, lights: []const Light, camera: Camera, pixel_block: usize) !void {
    const reference_width: usize = @intCast(target.width);
    const reference_height: usize = @intCast(target.height);
    const width_f32: f32 = @floatFromInt(target.width);
    const height_f32: f32 = @floatFromInt(target.height);

    const aspect_ratio = width_f32 / height_f32;
    const FOV = std.math.pi / 3.0;
    // tan de FOV/2 nos da la escala de la perspectiva, que es la relación entre la altura de la imagen y la distancia focal
    const perspective_scale = @tan(FOV * 0.5);

    // Iteramos sobre cada píxel de la pantalla y calculamos el color correspondiente usando ray tracing
    // La idea es que para cada píxel, generamos un rayo desde la cámara hacia el mundo 3D, y vemos qué objeto (si hay alguno) intersecta con ese rayo.
    // Luego calculamos el color del píxel en función de la luz y el material del objeto intersectado.
    var screen_y: usize = 0;
    while (screen_y < reference_height) : (screen_y += pixel_block) {
        var screen_x: usize = 0;
        while (screen_x < reference_width) : (screen_x += pixel_block) {
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
            // Un rayo pinta el bloque completo, incluso en los bordes.
            for (screen_y..@min(screen_y + pixel_block, reference_height)) |y| {
                for (screen_x..@min(screen_x + pixel_block, reference_width)) |x| {
                    try target.set_pixel(@intCast(x), @intCast(y));
                }
            }
        }
    }
}
