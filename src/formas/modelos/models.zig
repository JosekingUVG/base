const std = @import("std");
const rl = @import("raylib");

const Sphere = @import("../sphere.zig").Sphere;
const Mesh = @import("mesh.zig").Mesh;
const Intersect =
    @import("../raytracer/raytracer.zig").Intersect;

pub const Model = struct {
    bounding_sphere: Sphere,
    mesh: Mesh,

    pub fn intersect(
        self: Model,
        origin: rl.Vector3,
        direction: rl.Vector3,
    ) ?Intersect {
        // Usamos la Sphere que ya existe, pero descartamos
        // su impacto porque la esfera es invisible.
        _ = self.bounding_sphere.intersect(
            origin,
            direction,
        ) orelse return null;

        var closest_hit: ?Intersect = null;
        var closest_distance =
            std.math.floatMax(f32);

        for (self.mesh.triangles) |triangle| {
            const hit = triangle.intersect(
                origin,
                direction,
            ) orelse continue;

            if (hit.Distancia < closest_distance) {
                closest_distance = hit.Distancia;
                closest_hit = hit;
            }
        }

        return closest_hit;
    }
};
