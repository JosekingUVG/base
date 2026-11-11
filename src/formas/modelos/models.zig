// ROTAR, TRANSLADAR Y ESCALAR MODELOS OBJ EN LA ESCENA
// https://chatgpt.com/share/e/6af49b98-96b4-83e8-96f4-a875b6758417

const std = @import("std");
const rl = @import("raylib");

const Sphere = @import("../sphere.zig").Sphere;
const Mesh = @import("mesh.zig").Mesh;
const Intersect =
    @import("../../raytracer/raytracer.zig").Intersect;

pub const Model = struct {
    bounding_sphere: Sphere,
    mesh: Mesh,
    // Posición del origen del OBJ en la escena y escala uniforme positiva.
    position: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 },
    scale: f32 = 1,

    // Orientación de los ejes del OBJ dentro del mundo.
    // Por defecto, el modelo conserva su orientación original.
    axis_x: rl.Vector3 = .{ .x = 1, .y = 0, .z = 0 },
    axis_y: rl.Vector3 = .{ .x = 0, .y = 1, .z = 0 },
    axis_z: rl.Vector3 = .{ .x = 0, .y = 0, .z = 1 },

    fn toLocal(self: Model, vector: rl.Vector3) rl.Vector3 {
        return .{
            .x = vector.dotProduct(self.axis_x),
            .y = vector.dotProduct(self.axis_y),
            .z = vector.dotProduct(self.axis_z),
        };
    }

    fn toWorld(self: Model, vector: rl.Vector3) rl.Vector3 {
        return self.axis_x.scale(vector.x)
            .add(self.axis_y.scale(vector.y))
            .add(self.axis_z.scale(vector.z));
    }

    pub fn intersect(
        self: Model,
        origin: rl.Vector3,
        direction: rl.Vector3,
    ) ?Intersect {
        std.debug.assert(self.scale > 0);
        // Un rayo que nace dentro también puede golpear la malla
        // (por ejemplo, los rayos de sombra y reflexión).
        const offset = origin.subtract(self.bounding_sphere.center);
        if (offset.dotProduct(offset) > self.bounding_sphere.radius * self.bounding_sphere.radius) {
            _ = self.bounding_sphere.intersect(origin, direction) orelse return null;
        }

        var closest_hit: ?Intersect = null;
        var closest_distance =
            std.math.floatMax(f32);

        // Consultamos la malla en las coordenadas originales del OBJ.
        // Esto permite colocarla sin modificar sus vértices.
        const local_origin = self.toLocal(
            origin.subtract(self.position),
        ).scale(1.0 / self.scale);

        const local_direction = self.toLocal(direction);

        for (self.mesh.triangles) |triangle| {
            var hit = triangle.intersect(
                local_origin,
                local_direction,
            ) orelse continue;

            // Regresamos del espacio del OBJ al mundo.
            hit.Punto = self.toWorld(
                hit.Punto.scale(self.scale),
            ).add(self.position);

            hit.Normal = self.toWorld(hit.Normal).normalize();
            hit.Distancia *= self.scale;

            if (hit.Distancia < closest_distance) {
                closest_distance = hit.Distancia;
                closest_hit = hit;
            }
        }

        return closest_hit;
    }
};

test "modelo trasladado y escalado devuelve impactos en la escena" {
    const material = std.mem.zeroes(@import("../../raytracer/raytracer.zig").Material);
    var mesh = try Mesh.loadObjFromMemory(std.testing.allocator, "v -1 -1 0\nv 1 -1 0\nv 0 1 0\nf 1 2 3\n", material);
    defer mesh.deinit();
    const model = Model{
        .mesh = mesh,
        .position = .{ .x = 10, .y = 0, .z = 5 },
        .scale = 2,
        .bounding_sphere = .{
            .center = .{ .x = 10, .y = 0, .z = 5 },
            .radius = 3,
            .material = material,
        },
    };
    // Probamos desde fuera y desde dentro de la esfera invisible.
    for ([_]f32{ 15, 6 }) |z| {
        const hit = model.intersect(.{ .x = 10, .y = 0, .z = z }, .{ .x = 0, .y = 0, .z = -1 }) orelse return error.ExpectedHit;
        try std.testing.expectApproxEqAbs(z - 5, hit.Distancia, 0.0001);
        try std.testing.expectApproxEqAbs(@as(f32, 10), hit.Punto.x, 0.0001);
        try std.testing.expectApproxEqAbs(@as(f32, 5), hit.Punto.z, 0.0001);
    }
    try std.testing.expectEqual(@as(f32, -1), mesh.triangles[0].a.position.x);
}

test "modelo rotado transforma rayos, puntos y normales" {
    const material = std.mem.zeroes(@import("../../raytracer/raytracer.zig").Material);
    var mesh = try Mesh.loadObjFromMemory(
        std.testing.allocator,
        "v -1 -1 0\nv 1 -1 0\nv 0 1 0\nf 1 2 3\n",
        material,
    );
    defer mesh.deinit();

    const model = Model{
        .mesh = mesh,
        // Rotación de +90 grados alrededor de Y:
        // el plano XY local se convierte en un plano YZ del mundo.
        .axis_x = .{ .x = 0, .y = 0, .z = -1 },
        .axis_y = .{ .x = 0, .y = 1, .z = 0 },
        .axis_z = .{ .x = 1, .y = 0, .z = 0 },
        .bounding_sphere = .{
            .center = .zero(),
            .radius = 2,
            .material = material,
        },
    };

    const hit = model.intersect(
        .{ .x = 5, .y = 0, .z = 0 },
        .{ .x = -1, .y = 0, .z = 0 },
    ) orelse return error.ExpectedHit;

    try std.testing.expectApproxEqAbs(@as(f32, 5), hit.Distancia, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), hit.Punto.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), hit.Normal.x, 0.0001);
}
