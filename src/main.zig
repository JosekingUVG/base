const std = @import("std");

const rl = @import("raylib");
const Framebuffer = @import("dominio/framebuffer.zig").Framebuffer;
const Forma = @import("formas/formas.zig").Forma;
const Camera = @import("dominio/camera.zig").Camera;
const Light = @import("raytracer/raytracer.zig").Light;
const Texture = @import("raytracer/textures.zig").Texture;
const Mesh = @import("formas/modelos/mesh.zig").Mesh;

const cast_ray = @import("raytracer/raytracer.zig").cast_ray;
const V3ToColor = @import("raytracer/raytracer.zig").V3ToColor;

const formas = @import("config/formas.zig");
const luces = @import("config/luces.zig");
const controls = @import("config/controls.zig");

const Clock = std.Io.Clock.real;

const width = 1300;
const height = 600;

const near_distance: f32 = 70;

pub fn main() !void {

    // Implementación de la concurrencia, inspirado en https://akhil.sh/tutorials/zig/zig/concurrency_in_zig/
    // Respaldado con chatgpt: https://chatgpt.com/share/e/6ad05fa5-fa94-83e8-b9f4-06f5b300f1f2

    // Allocator compartido para todos los modos de compilación; no requiere deinit.
    // Cada recurso libera su propia memoria con su correspondiente defer.
    const gpa: std.mem.Allocator = std.heap.smp_allocator;

    // === CONCURRENCIA: GESTOR DE HILOS (THREAD POOL) ===
    // 'threaded' inicializa y administra el pool de hilos reutilizables del sistema.
    // Esto evita el costo de crear y destruir hilos de sistema operativo en cada fotograma.
    var threaded: std.Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // === CONCURRENCIA: CANTIDAD DE HILOS SEGÚN HARDWARE ===
    // Preguntamos al sistema operativo cuántos núcleos/hilos lógicos tiene el procesador (CPU).
    // Con @max(1, ...) garantizamos que al menos tengamos 1 hilo de ejecución.
    const worker_count = @max(1, std.Thread.getCpuCount() catch 1);

    // Inicializamos el framebuffer con el tamaño de la ventana y los colores de fondo y borde
    // .black, ... .white significa que el color de fondo es negro y el color de borde es blanco
    var framebuffer = Framebuffer.init(width, height, .black, .white);

    // Ventana Raylib
    rl.initWindow(width, height, "Raytracer!!!");
    rl.setTraceLogLevel(.warning);
    defer rl.closeWindow();
    defer framebuffer.deinit();
    rl.setTargetFPS(60);

    // Textura del plano
    var floor_texture = Texture.load(
        gpa,
        formas.floor_texture_path,
    ) catch |err| {
        std.debug.print(
            "No se pudo cargar la textura: {}\n",
            .{err},
        );
        return err;
    };
    defer floor_texture.deinit();

    // Textura del modelo
    var model_texture = try Texture.load(
        gpa,
        formas.model_texture_path,
    );
    defer model_texture.deinit();

    // Textura del cubo
    var cube_texture = try Texture.load(
        gpa,
        formas.cube_texture_path,
    );
    defer cube_texture.deinit();

    // Modelo
    const model_material = formas.modelMaterial(&model_texture);

    // Cargar el modelo OBJ
    var mesh = try Mesh.loadObj(
        gpa,
        io,
        formas.model_path,
        model_material,
    );
    defer mesh.deinit();

    // Necesitamos saber el tiempo que tarda cada fotograma para calcular el delta time (dt) y mover la cámara de forma suave.
    var last_frame_time = Clock.now(io); // usamos clock para medir el tiempo entre fotogramas y calcular delta
    // delta es la diferencia de tiempo entre el marco actual y el anterior
    var delta: i64 = 1;

    // Creamos los objetos de la escena a partir del modelo y la textura del piso
    const objects = formas.create(mesh, model_material, &floor_texture, &cube_texture);

    // Inicializamos la cámara con la distancia inicial y los ángulos de rotación iniciales
    var cameraDistance = controls.initial_distance;
    var camera: Camera = .init(.{
        .x = 0,
        .y = 0,
        .z = cameraDistance,
    }, .zero());

    // controles de la cámara: ángulos de rotación y distancia
    var camera_x_angle = controls.initial_x_angle;
    var camera_y_angle = controls.initial_y_angle;

    // Render loop: mientras la ventana no se cierre, actualizamos la cámara y renderizamos la escena
    var has_rendered = false; // variable para saber si ya se ha renderizado al menos un fotograma
    var was_moving = false; // variable para saber si la cámara se estaba moviendo en el fotograma anterior

    // ciclo principal del programa: mientras la ventana no se cierre, actualizamos la cámara y renderizamos la escena
    while (!rl.windowShouldClose()) {
        defer { // defer para medir el tiempo que tarda cada fotograma y calcular el delta time (dt)
            const now = Clock.now(io);
            delta = last_frame_time.durationTo(now).toMicroseconds();
            last_frame_time = now;
        }

        // COnstantes que controlan la velocidad de movimiento de la cámara y el zoom, y los límites de ángulo y distancia
        const dt: f32 = @as(f32, @floatFromInt(delta)) / 1_000_000;
        const old_x_angle = camera_x_angle;
        const old_y_angle = camera_y_angle;
        const old_distance = cameraDistance;

        // Control de la cámara con las teclas WASD
        if (rl.isKeyDown(controls.left) or rl.isKeyDown(controls.left_arrow)) {
            camera_x_angle += controls.turn_speed * dt;
        }
        if (rl.isKeyDown(controls.right) or rl.isKeyDown(controls.right_arrow)) {
            camera_x_angle -= controls.turn_speed * dt;
        }
        if (rl.isKeyDown(controls.up) or rl.isKeyDown(controls.up_arrow)) {
            camera_y_angle += controls.turn_speed * dt;
            camera_y_angle = @max(controls.y_angle_min, @min(controls.y_angle_max, camera_y_angle));
        }
        if (rl.isKeyDown(controls.down) or rl.isKeyDown(controls.down_arrow)) {
            camera_y_angle -= controls.turn_speed * dt;
            camera_y_angle = @max(controls.y_angle_min, @min(controls.y_angle_max, camera_y_angle));
        }

        // zoom con la rueda del mouse, con límites de distancia mínima y máxima
        const wheel = rl.getMouseWheelMove();
        cameraDistance = std.math.clamp(cameraDistance - wheel * controls.zoom_speed, controls.min_distance, controls.max_distance);
        // Detectamos si la cámara se está moviendo comparando los ángulos y la distancia actuales con los anteriores
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
        if (needs_render) { // si la cámara se está moviendo o es el primer fotograma, renderizamos la escena
            // Elegimos el tamaño del bloque de píxeles según si la cámara se está moviendo o no, y según la distancia de la cámara al origen
            const pixel_block: usize = if (moving) 4 else if (cameraDistance > near_distance) 2 else 1;
            // Renderizamos la escena usando ray tracing, con una franja horizontal fija por tarea
            try render(io, worker_count, &framebuffer, &objects, &luces.lights, camera, pixel_block);
            has_rendered = true;
        }
        was_moving = moving; // actualizamos la variable was_moving para el siguiente fotograma

        // Dibujamos el framebuffer en la ventana de Raylib
        try framebuffer.swap_buffers(needs_render);
    }
}

// Datos del fotograma: la escena se lee y cada tarea escribe filas diferentes.
const RenderJob = struct {
    pixels: []rl.Color,
    image_width: usize,
    image_height: usize,
    objects: []const Forma,
    lights: []const Light,
    camera: Camera,
    pixel_block: usize,
    aspect_ratio: f32,
    perspective_scale: f32,

    // Renderiza una franja horizontal [first_y, end_y).
    // Como cada hilo procesa un rango de 'y' diferente, no hay colisiones de memoria
    // al escribir en 'job.pixels'.
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

// === CONCURRENCIA: COORDINADOR DEL FOTOGRAMA (fn render) ===
// Despacha el trabajo a los hilos y espera a que todos terminen antes de continuar.
fn render(io: std.Io, worker_count: usize, target: *Framebuffer, objects: []const Forma, lights: []const Light, camera: Camera, pixel_block: usize) !void {
    std.debug.assert(pixel_block > 0);
    const job: RenderJob = .{
        .pixels = target.pixels(),
        .image_width = @intCast(target.width),
        .image_height = @intCast(target.height),
        .objects = objects,
        .lights = lights,
        .camera = camera,
        .pixel_block = pixel_block,
        .aspect_ratio = @as(f32, @floatFromInt(target.width)) / @as(f32, @floatFromInt(target.height)),
        .perspective_scale = @tan(std.math.pi / 6.0),
    };

    // Dividimos filas de BLOQUES para que ninguna franja corte un bloque de píxeles.
    const block_rows = std.math.divCeil(usize, job.image_height, pixel_block) catch unreachable;
    const workers = @max(1, @min(worker_count, block_rows));
    var group: std.Io.Group = .init;
    defer group.cancel(io);

    for (0..workers) |i| {
        const first_y = (block_rows * i / workers) * pixel_block;
        const end_y = @min((block_rows * (i + 1) / workers) * pixel_block, job.image_height);

        if (i == workers - 1) {
            // El hilo principal también pinta una franja.
            job.renderStripe(first_y, end_y);
        } else {
            // Si el pool no puede iniciar la tarea, pintamos esa franja aquí.
            group.concurrent(io, RenderJob.renderStripe, .{ &job, first_y, end_y }) catch {
                job.renderStripe(first_y, end_y);
            };
        }
    }

    // No mostrar ni modificar el fotograma hasta que todas las franjas terminen.
    try group.await(io);
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

// Compara el resultado concurrente con el render secuencial, sin abrir una ventana.
test "franjas producen los mismos pixeles que el render secuencial" {
    var threaded: std.Io.Threaded = .init(std.testing.allocator, .{});
    defer threaded.deinit();
    const camera: Camera = .init(.{ .x = 0, .y = 0, .z = 10 }, .zero());
    const objects = [_]Forma{.{ .Sphere = .{
        .center = .zero(),
        .radius = 3,
        .material = .{
            .Color = .{ .x = 1, .y = 0.2, .z = 0.1 },
            .Ambient = 0.5,
            .Especular = 10,
            .Refractive_index = 1,
            .Propiedades = .{ .Albedo = 0.8, .Especular = 0, .Reflectividad = 0, .Transparencia = 0 },
        },
    } }};
    var expected = Framebuffer.init(13, 11, .black, .white);
    defer expected.deinit();
    var actual = Framebuffer.init(13, 11, .white, .white);
    defer actual.deinit();

    for ([_]usize{ 1, 2, 4, 16 }) |block| {
        try renderReference(&expected, &objects, &luces.lights, camera, block);
        for ([_]usize{ 1, 2, 3, 32 }) |workers| {
            for (0..3) |_| {
                @memset(actual.pixels(), .white);
                try render(threaded.io(), workers, &actual, &objects, &luces.lights, camera, block);
                try std.testing.expectEqualSlices(rl.Color, expected.pixels(), actual.pixels());
            }
        }
    }
}
