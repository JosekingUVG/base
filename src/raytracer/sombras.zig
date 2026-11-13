const rl = @import("raylib");
const std = @import("std");
const Light = @import("raytracer.zig").Light;
const Forma = @import("../formas/formas.zig").Forma;

pub fn obscured(origin: rl.Vector3, light: Light, objects: []const Forma, normal: rl.Vector3) bool {
    const point_to_light = light.Position.subtract(origin);

    const light_distance = point_to_light.length();

    const light_direction = point_to_light.normalize();

    const shadow_origin = origin.add(normal.scale(1e-4)); // Desplazamos el origen del rayo ligeramente para evitar problemas de auto-intersección

    // Referencia luz solar: https://chatgpt.com/share/e/6af66bec-4b98-83e8-b3f0-aa4db2cbd0ce

    // Iteramos sobre todos los objetos de la escena y calculamos si el rayo que va desde el punto hacia la luz intersecta con algún objeto antes de llegar a la luz
    for (objects, 0..) |object, index| {
        // Ignoramos solamente el objeto que representa esta luz.
        if (light.Object_index) |light_object_index| {
            if (index == light_object_index) continue;
        }

        const hit = object.intersect(
            shadow_origin,
            light_direction,
        ) orelse continue;

        // Distancias iguales o posteriores pertenecen a la luz o estan detras
        // de ella, por lo que no pueden bloquearla.
        if (hit.Distancia > 0.001 and hit.Distancia < light_distance) {
            return true;
        }
    }

    return false;
}

fn testSphere(center: rl.Vector3) Forma {
    return .{ .Sphere = .{
        .center = center,
        .radius = 1,
        .material = .{
            .Color = .{ .x = 1, .y = 1, .z = 1 },
            .Propiedades = .{
                .Albedo = 0,
                .Especular = 0,
                .Reflectividad = 0,
                .Transparencia = 0,
            },
            .Especular = 1,
            .Refractive_index = 1,
        },
    } };
}

test "la esfera que representa la luz no se bloquea a si misma" {
    const objects = [_]Forma{testSphere(.{ .x = 0, .y = 0, .z = 10 })};
    const light = Light{
        .Color = .{ .x = 1, .y = 1, .z = 1 },
        .Position = .{ .x = 0, .y = 0, .z = 10 },
        .Intensity = 1,
        .Object_index = 0,
    };

    try std.testing.expect(!obscured(
        .{ .x = 0, .y = 0, .z = 0 },
        light,
        &objects,
        .{ .x = 0, .y = 0, .z = 1 },
    ));
}

test "otro objeto situado antes de la luz si produce sombra" {
    const objects = [_]Forma{
        testSphere(.{ .x = 0, .y = 0, .z = 5 }),
        testSphere(.{ .x = 0, .y = 0, .z = 10 }),
    };
    const light = Light{
        .Color = .{ .x = 1, .y = 1, .z = 1 },
        .Position = .{ .x = 0, .y = 0, .z = 10 },
        .Intensity = 1,
        .Object_index = 1,
    };

    try std.testing.expect(obscured(
        .{ .x = 0, .y = 0, .z = 0 },
        light,
        &objects,
        .{ .x = 0, .y = 0, .z = 1 },
    ));
}
