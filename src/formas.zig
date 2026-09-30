const Intersect = @import("raytracer.zig").Intersect;
const rl = @import("raylib");

const Sphere = @import("sphere.zig").Sphere;
const Plane = @import("plane.zig").Plane;
const Triangle = @import("triangles.zig").Triangle;

pub const Forma = union(enum) {
    Sphere: Sphere,
    Plane: Plane,
    Triangle: Triangle,

    pub fn intersect(
        self: Forma,
        origin: rl.Vector3,
        direction: rl.Vector3,
    ) ?Intersect {
        switch (self) {
            .Sphere => |sphere| {
                return sphere.intersect(origin, direction);
            },

            .Plane => |plane| {
                return plane.intersect(origin, direction);
            },

            .Triangle => |triangle| {
                return triangle.intersect(origin, direction);
            },
        }
    }
};
