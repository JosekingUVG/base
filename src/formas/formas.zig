const Intersect = @import("../raytracer/raytracer.zig").Intersect;
const rl = @import("raylib");

const Sphere = @import("sphere.zig").Sphere;
const Plane = @import("plane.zig").Plane;
const Triangle = @import("triangles.zig").Triangle;
const Model = @import("modelos/models.zig").Model;
const Cube = @import("cubo.zig").Cube;
const Collider = @import("colisiones.zig").Collider;

pub const Forma = union(enum) {
    Sphere: Sphere,
    Plane: Plane,
    Triangle: Triangle,
    Cube: Cube,
    Model: Model,

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

            .Model => |model| {
                return model.intersect(origin, direction);
            },

            .Cube => |cube| {
                return cube.intersect(origin, direction);
            },
        }
    }

    /// Volumen fisico aproximado de la forma. La representacion de colision
    /// vive junto a las formas y es independiente de su material visual.
    pub fn collider(self: Forma) ?Collider {
        return switch (self) {
            .Sphere => |sphere| .{
                .center = sphere.center,
                .radius = sphere.radius,
            },
            .Model => |model| .{
                .center = model.bounding_sphere.center,
                .radius = model.bounding_sphere.radius,
            },
            // Estas formas necesitaran su volumen correspondiente cuando se
            // incorporen a la escena jugable.
            .Plane, .Triangle, .Cube => null,
        };
    }
};
