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
        const local_origin = origin.subtract(self.position).scale(1.0 / self.scale);

        for (self.mesh.triangles) |triangle| {
            var hit = triangle.intersect(
                local_origin,
                direction,
            ) orelse continue;

            // Devolvemos el impacto en coordenadas de la escena.
            hit.Punto = hit.Punto.scale(self.scale).add(self.position);
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
