const rl = @import("raylib");
const Light = @import("raytracer.zig").Light;
const Forma = @import("../formas/formas.zig").Forma;

pub fn obscured(origin: rl.Vector3, light: Light, objects: []const Forma, normal: rl.Vector3) bool {
    const point_to_light = light.Position.subtract(origin);

    const light_distance = point_to_light.length();

    const light_direction = point_to_light.normalize();

    const shadow_origin = origin.add(normal.scale(0.001));

    // Iteramos sobre todos los objetos de la escena y calculamos si el rayo que va desde el punto hacia la luz intersecta con algún objeto antes de llegar a la luz
    for (objects) |object| {
        const hit = object.intersect(
            shadow_origin,
            light_direction,
        ) orelse continue; // si no hay intersección, pasamos al siguiente objeto

        // Si la distancia de la intersección es menor que la distancia a la luz, significa que el punto está en sombra
        if (hit.Distancia < light_distance) {
            return true;
        }
    }

    return false;
}
