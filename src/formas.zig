const Sphere = @import("sphere.zig").Sphere;
//const Plane: @import("plane.zig").Plane;
//const Triangle: @import("triangles.zig").Triangle;
const Intersect = @import("raytracer.zig").Intersect;
const rl = @import("raylib");

pub const Forma = union(enum) {
    Sphere: Sphere,
    //Plane: Plane,
    //Triangle: Triangle,

    pub fn intersect(
        self: Forma,
        origin: rl.Vector3,
        direction: rl.Vector3,
    ) ?Intersect {
        return switch (self) {
            .Sphere => |sphere| sphere.intersect(origin, direction),
            .Plane => |plane| plane.intersect(origin, direction),
            .Triangle => |triangle| triangle.intersect(origin, direction),
        };
    }
};
