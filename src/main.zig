const std = @import("std");
const rl = @import("raylib");

const Framebuffer = @import("dominio/framebuffer.zig").Framebuffer;
const Camera = @import("dominio/camera.zig").Camera;
const Forma = @import("formas/formas.zig").Forma;
const Mesh = @import("formas/modelos/mesh.zig").Mesh;
const Light = @import("raytracer/raytracer.zig").Light;
const Texture = @import("raytracer/textures.zig").Texture;
const castRay = @import("raytracer/raytracer.zig").cast_ray;
const vectorToColor = @import("raytracer/raytracer.zig").V3ToColor;

const controls = @import("config/controls.zig");
const lights = @import("config/luces.zig").lights;
const ship = @import("config/nave_espacial.zig");

const Clock = std.Io.Clock.real;
const width = 1300;
const height = 600;
const background_texture_path = "assets/textures/hipp2.ppm";

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Zig 0.16 necesita un contexto de I/O para leer el OBJ y consultar el reloj.
    // Usamos explícitamente su implementación global de un solo hilo.
    const io = std.Io.Threaded.global_single_threaded.io();

    rl.initWindow(width, height, "Raytracer");
    defer rl.closeWindow();
    rl.setTraceLogLevel(.warning);
    rl.setTargetFPS(60);

    var framebuffer = Framebuffer.init(width, height, .black, .white);
    defer framebuffer.deinit();

    var model_texture = try Texture.load(
        allocator,
        io,
        ship.model_texture_path,
    );
    defer model_texture.deinit();

    var background_texture = try Texture.load(
        allocator,
        io,
        background_texture_path,
    );
    defer background_texture.deinit();

    const model_material = ship.material(&model_texture);
    var mesh = try Mesh.loadObj(
        allocator,
        io,
        ship.model_path,
        model_material,
    );
    defer mesh.deinit();

    const objects = [_]Forma{ship.create(mesh, model_material)};
    var camera: Camera = .init(
        .{ .x = 0, .y = 15, .z = 80 },
        .{ .x = 0, .y = 10, .z = 0 },
    );

    var previous_time = Clock.now(io);
    var has_rendered = false;
    var was_moving = false;

    while (!rl.windowShouldClose()) {
        const now = Clock.now(io);
        const elapsed = previous_time.durationTo(now).toMicroseconds();
        previous_time = now;

        // Evita saltos enormes si un frame tarda mucho en renderizarse.
        const dt = @min(
            @as(f32, @floatFromInt(elapsed)) / 1_000_000,
            1.0 / 15.0,
        );

        const moving = updateCamera(&camera, dt);
        const needs_render = !has_rendered or moving or was_moving;

        if (needs_render) {
            // Sin una estructura BVH, el koala todavía es costoso. Usamos
            // bloques grandes al movernos y refinamos una vez al detenernos.
            const pixel_block: usize = if (moving) 8 else 4;
            render(
                &framebuffer,
                &objects,
                &lights,
                &background_texture,
                camera,
                pixel_block,
            );
            has_rendered = true;
        }

        was_moving = moving;
        try framebuffer.swap_buffers(needs_render);
    }
}

// Integración de cámara libre asistida por OpenAI Codex (2026-11-09).
fn updateCamera(camera: *Camera, dt: f32) bool {
    const speed = controls.move_speed * dt *
        (if (rl.isKeyDown(controls.boost)) controls.boost_multiplier else 1);
    const turn = controls.turn_speed * dt;

    var right: f32 = 0;
    var up: f32 = 0;
    var forward: f32 = 0;
    var yaw: f32 = 0;
    var pitch: f32 = 0;

    if (rl.isKeyDown(controls.left)) right -= speed;
    if (rl.isKeyDown(controls.right)) right += speed;
    if (rl.isKeyDown(controls.rise)) up += speed;
    if (rl.isKeyDown(controls.descend)) up -= speed;
    if (rl.isKeyDown(controls.forward)) forward += speed;
    if (rl.isKeyDown(controls.backward)) forward -= speed;

    if (rl.isKeyDown(controls.look_left)) yaw -= turn;
    if (rl.isKeyDown(controls.look_right)) yaw += turn;
    if (rl.isKeyDown(controls.look_up)) pitch += turn;
    if (rl.isKeyDown(controls.look_down)) pitch -= turn;

    const moving = right != 0 or up != 0 or forward != 0 or
        yaw != 0 or pitch != 0;

    if (moving) {
        camera.lookFree(yaw, pitch);
        camera.moveLocal(right, up, forward);
    }

    return moving;
}

// Raytracer secuencial: recorre la imagen de arriba a abajo y de izquierda
// a derecha. Cada iteración lanza un rayo y pinta un bloque del framebuffer.
fn render(
    target: *Framebuffer,
    objects: []const Forma,
    scene_lights: []const Light,
    background: *const Texture,
    camera: Camera,
    pixel_block: usize,
) void {
    std.debug.assert(pixel_block > 0);

    const image_width: usize = @intCast(target.width);
    const image_height: usize = @intCast(target.height);
    const width_float: f32 = @floatFromInt(image_width);
    const height_float: f32 = @floatFromInt(image_height);
    const aspect_ratio = width_float / height_float;
    const perspective_scale = @tan(std.math.pi / 6.0);
    const pixels = target.pixels();

    var screen_y: usize = 0;
    while (screen_y < image_height) : (screen_y += pixel_block) {
        const y: f32 = @floatFromInt(screen_y);
        const y_direction = (1 - (y * 2) / height_float) * perspective_scale;

        var screen_x: usize = 0;
        while (screen_x < image_width) : (screen_x += pixel_block) {
            const x: f32 = @floatFromInt(screen_x);
            const x_direction = ((x * 2) / width_float - 1) *
                aspect_ratio * perspective_scale;

            const camera_ray = (rl.Vector3{
                .x = x_direction,
                .y = y_direction,
                .z = 1,
            }).normalize();

            const world_ray = rl.Vector3{
                .x = camera_ray.x * camera.Right.x + camera_ray.y * camera.Up.x + camera_ray.z * camera.Forward.x,
                .y = camera_ray.x * camera.Right.y + camera_ray.y * camera.Up.y + camera_ray.z * camera.Forward.y,
                .z = camera_ray.x * camera.Right.z + camera_ray.y * camera.Up.z + camera_ray.z * camera.Forward.z,
            };

            const color = vectorToColor(castRay(
                camera.Postition,
                world_ray,
                objects,
                scene_lights,
                background,
                5,
            ));

            const end_x = @min(screen_x + pixel_block, image_width);
            const end_y = @min(screen_y + pixel_block, image_height);
            for (screen_y..end_y) |paint_y| {
                const row = paint_y * image_width;
                @memset(pixels[row + screen_x .. row + end_x], color);
            }
        }
    }
}
