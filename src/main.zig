const std = @import("std");

const rl = @import("raylib");
const Framebuffer = @import("dominio/framebuffer.zig").Framebuffer;
const Forma = @import("formas/formas.zig").Forma;
const Camera = @import("dominio/camera.zig").Camera;
const Light = @import("raytracer/raytracer.zig").Light;
const Texture = @import("raytracer/textures.zig").Texture;
const BackgroundTexture = @import("raytracer/textures.zig").BackgroundTexture;
const Mesh = @import("formas/modelos/mesh.zig").Mesh;

const cast_ray = @import("raytracer/raytracer.zig").cast_ray;
const V3ToColor = @import("raytracer/raytracer.zig").V3ToColor;

const luces = @import("config/luces.zig");
const controls = @import("config/controls.zig");
const nave_espacial = @import("config/nave_espacial.zig");
const formas = @import("config/formas.zig");

const Clock = std.Io.Clock.real; // Reloj de tiempo real para medir el tiempo entre fotogramas y calcular delta time (dt)

const width = 1300;
const height = 600;
const background_texture_path = "assets/textures/hipp2.png"; //skybox de fondo panorámico para la escena, cargado como textura 2D y copiado a RAM para que los hilos del raytracer puedan leer sus píxeles.

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

    // Textura del modelo
    var model_texture = try Texture.load(
        gpa,
        nave_espacial.model_texture_path,
    );
    defer model_texture.deinit();

    // Raylib carga la imagen en RAM para que
    // los hilos del raytracer puedan consultar sus píxeles.
    var background_texture = try BackgroundTexture.load(background_texture_path);
    defer background_texture.deinit();

    // Modelo
    const model_material = nave_espacial.material(&model_texture);

    // Cargar el modelo OBJ
    var mesh = try Mesh.loadObj(
        gpa,
        io,
        nave_espacial.model_path,
        model_material,
    );
    defer mesh.deinit();

    // Necesitamos saber el tiempo que tarda cada fotograma para calcular el delta time (dt) y mover la cámara de forma suave.
    var last_frame_time = Clock.now(io); // usamos clock para medir el tiempo entre fotogramas y calcular delta
    // delta es la diferencia de tiempo entre el marco actual y el anterior
    var delta: i64 = 1;

    // Escena mínima para validar el movimiento libre sin el costo adicional
    // de los objetos reflectivos y transparentes de la demostración anterior.
    var objects = [_]Forma{
        nave_espacial.create(mesh, model_material),
        formas.createSun(),
    };

    // Vista inicial en tres cuartos: detrás y 30 grados debajo de la nave.
    var camera: Camera = .init(
        nave_espacial.initial_camera_position,
        nave_espacial.model_center,
    );
    const initial_camera = camera;
    const initial_model = objects[0].Model;

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

        // Integración de cámara libre asistida por OpenAI Codex (2026-11-09).
        // Movimiento local: WASD, espacio/control y boost con shift.
        // Las flechas cambian yaw y pitch sin fijar la cámara al origen.
        const dt = @min(
            @as(f32, @floatFromInt(delta)) / 1_000_000,
            1.0 / 15.0,
        );
        const speed = controls.move_speed * dt *
            (if (rl.isKeyDown(controls.boost)) controls.boost_multiplier else 1);
        const turn = controls.turn_speed * dt;

        var local_right: f32 = 0;
        var local_up: f32 = 0;
        var local_forward: f32 = 0;
        var yaw: f32 = 0;
        var pitch: f32 = 0;

        if (rl.isKeyDown(controls.left)) local_right -= speed;
        if (rl.isKeyDown(controls.right)) local_right += speed;
        if (rl.isKeyDown(controls.rise)) local_up += speed;
        if (rl.isKeyDown(controls.descend)) local_up -= speed;
        if (rl.isKeyDown(controls.forward)) local_forward += speed;
        if (rl.isKeyDown(controls.backward)) local_forward -= speed;

        if (rl.isKeyDown(controls.look_left)) yaw -= turn;
        if (rl.isKeyDown(controls.look_right)) yaw += turn;
        if (rl.isKeyDown(controls.look_up)) pitch += turn;
        if (rl.isKeyDown(controls.look_down)) pitch -= turn;

        const moving = local_right != 0 or local_up != 0 or local_forward != 0 or
            yaw != 0 or pitch != 0;
        if (moving) {
            camera.lookFree(yaw, pitch);
            camera.moveLocal(local_right, local_up, local_forward);

            // La nave conserva su desplazamiento y orientación respecto de la
            // cámara, como personaje controlado en tercera persona.
            nave_espacial.followCamera(
                &objects[0].Model,
                initial_model,
                initial_camera,
                camera,
            );
        }

        // Durante el movimiento usamos bloques grandes. Al detenerse, refinamos
        // una vez y reutilizamos esa imagen mientras la escena no cambie.
        const needs_render = !has_rendered or moving or was_moving;
        if (needs_render) { // si la cámara se está moviendo o es el primer fotograma, renderizamos la escena
            // El koala tiene 594 triángulos y todavía no hay BVH. Para que esta
            // prueba sea interactiva usamos bloques grandes al volar y una
            // resolución intermedia al detenernos. Más adelante el BVH permitirá
            // volver a bloques de 1 píxel sin recorrer toda la malla por rayo.
            const pixel_block: usize = if (moving) 8 else 4;
            // Renderizamos la escena usando ray tracing, con una franja horizontal fija por tarea
            const render_start = Clock.now(io);
            try render(io, worker_count, &framebuffer, &objects, &luces.lights, &background_texture, camera, pixel_block);
            if (!has_rendered) {
                const elapsed_ms = render_start.durationTo(Clock.now(io)).toMilliseconds();
                std.debug.print("Primer frame del koala: {} ms\n", .{elapsed_ms});
            }
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
    background: ?*const BackgroundTexture,
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
                const color = V3ToColor(cast_ray(camera.Postition, direction, job.objects, job.lights, job.background, 5));
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
fn render(io: std.Io, worker_count: usize, target: *Framebuffer, objects: []const Forma, lights: []const Light, background: ?*const BackgroundTexture, camera: Camera, pixel_block: usize) !void {
    std.debug.assert(pixel_block > 0);
    const job: RenderJob = .{
        .pixels = target.pixels(),
        .image_width = @intCast(target.width),
        .image_height = @intCast(target.height),
        .objects = objects,
        .lights = lights,
        .background = background,
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
fn renderReference(target: *Framebuffer, objects: []const Forma, lights: []const Light, background: ?*const BackgroundTexture, camera: Camera, pixel_block: usize) !void {
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

            const col = cast_ray(camera.Postition, direction, objects, lights, background, 5);
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
        try renderReference(&expected, &objects, &luces.lights, null, camera, block);
        for ([_]usize{ 1, 2, 3, 32 }) |workers| {
            for (0..3) |_| {
                @memset(actual.pixels(), .white);
                try render(threaded.io(), workers, &actual, &objects, &luces.lights, null, camera, block);
                try std.testing.expectEqualSlices(rl.Color, expected.pixels(), actual.pixels());
            }
        }
    }
}
