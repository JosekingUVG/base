//Referencias: https://en.wikipedia.org/wiki/Slab_method
// https://chatgpt.com/share/e/6ad1795f-5184-83e8-b045-27e72bf3fa67

const std = @import("std");
const rl = @import("raylib");

const Intersect = @import("../raytracer/raytracer.zig").Intersect;
const Material = @import("../raytracer/raytracer.zig").Material;

fn updateSlab(
    origin: f32,
    direction: f32,
    min: f32,
    max: f32,
    negative_normal: rl.Vector3,
    positive_normal: rl.Vector3,
    t_enter: *f32,
    t_exit: *f32,
    enter_normal: *rl.Vector3,
    exit_normal: *rl.Vector3,
) bool {
    if (direction == 0.0) {
        return origin >= min and origin <= max;
    }

    const min_t = (min - origin) / direction;
    const max_t = (max - origin) / direction;
    const near_t = @min(min_t, max_t);
    const far_t = @max(min_t, max_t);
    const near_normal = if (direction > 0.0) negative_normal else positive_normal;
    const far_normal = if (direction > 0.0) positive_normal else negative_normal;

    if (near_t > t_enter.*) {
        t_enter.* = near_t;
        enter_normal.* = near_normal;
    }
    if (far_t < t_exit.*) {
        t_exit.* = far_t;
        exit_normal.* = far_normal;
    }

    return t_enter.* <= t_exit.*;
}

pub const Cube = struct {
    center: rl.Vector3,
    size: f32, // Longitud completa de un lado.
    material: Material,

    fn calculateUV(
        self: Cube,
        point: rl.Vector3,
        normal: rl.Vector3,
    ) rl.Vector2 {
        const half_size = self.size / 2.0;

        const min = self.center.subtract(.{
            .x = half_size,
            .y = half_size,
            .z = half_size,
        });

        // Posición relativa dentro del cubo, entre 0 y 1.
        const local = point.subtract(min).scale(1.0 / self.size);

        if (normal.x != 0.0) {
            // Caras izquierda y derecha: usamos Z e Y.
            return .{
                .x = local.z,
                .y = 1.0 - local.y,
            };
        } else if (normal.y != 0.0) {
            // Caras superior e inferior: usamos X y Z.
            return .{
                .x = local.x,
                .y = local.z,
            };
        } else {
            // Caras delantera y trasera: usamos X e Y.
            return .{
                .x = local.x,
                .y = 1.0 - local.y,
            };
        }
    }

    pub fn intersect(
        self: Cube,
        origin: rl.Vector3,
        direction: rl.Vector3,
    ) ?Intersect {
        if (self.size <= 0.0 or
            (direction.x == 0.0 and direction.y == 0.0 and direction.z == 0.0))
        {
            return null;
        }
        // Calculamos los límites del cubo.
        const half_size = self.size / 2.0;
        const min = self.center.subtract(.{ .x = half_size, .y = half_size, .z = half_size });
        const max = self.center.add(.{ .x = half_size, .y = half_size, .z = half_size });

        // Calculamos la intersección del rayo con el cubo usando el método de los slabs.
        var t_enter = -std.math.inf(f32);
        var t_exit = std.math.inf(f32);
        var enter_normal = rl.Vector3{ .x = 0.0, .y = 0.0, .z = 0.0 };
        var exit_normal = enter_normal;

        // Si alguna de las tres dimensiones no tiene intersección, el rayo no golpea el cubo.
        if (!updateSlab(
            origin.x,
            direction.x,
            min.x,
            max.x,
            .{ .x = -1.0, .y = 0.0, .z = 0.0 },
            .{ .x = 1.0, .y = 0.0, .z = 0.0 },
            &t_enter,
            &t_exit,
            &enter_normal,
            &exit_normal,
        )) return null;
        if (!updateSlab(
            origin.y,
            direction.y,
            min.y,
            max.y,
            .{ .x = 0.0, .y = -1.0, .z = 0.0 },
            .{ .x = 0.0, .y = 1.0, .z = 0.0 },
            &t_enter,
            &t_exit,
            &enter_normal,
            &exit_normal,
        )) return null;
        if (!updateSlab(
            origin.z,
            direction.z,
            min.z,
            max.z,
            .{ .x = 0.0, .y = 0.0, .z = -1.0 },
            .{ .x = 0.0, .y = 0.0, .z = 1.0 },
            &t_enter,
            &t_exit,
            &enter_normal,
            &exit_normal,
        )) return null;

        if (t_exit <= 0.001) return null;

        const hit_from_outside = t_enter > 0.001;
        const distance = if (hit_from_outside) t_enter else t_exit;
        const normal = if (hit_from_outside) enter_normal else exit_normal;
        const point = origin.add(direction.scale(distance));

        return .{
            .Material = self.material,
            .Distancia = distance,
            .Normal = normal,
            .Punto = point,
            .UV = self.calculateUV(point, normal),
        };
    }
};
