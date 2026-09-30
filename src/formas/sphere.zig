const std = @import("std");
const rl = @import("raylib");

const Intersect = @import("../raytracer/raytracer.zig").Intersect;
const Material = @import("../raytracer/raytracer.zig").Material;

pub const Sphere = struct {
    center: rl.Vector3,
    radius: f32,
    material: Material,

    /// Convierte un punto de la esfera unitaria en coordenadas UV.
    fn calculateUV(normal: rl.Vector3) rl.Vector2 {
        const u =
            0.5 +
            std.math.atan2(normal.z, normal.x) /
                (2.0 * std.math.pi);

        // Evita pequeños errores donde normal.y sea 1.000001,
        // algo que produciría un valor inválido en asin.
        const safe_y = @max(-1.0, @min(1.0, normal.y));

        const v =
            0.5 -
            std.math.asin(safe_y) /
                std.math.pi;

        return .{
            .x = u,
            .y = v,
        };
    }

    pub fn intersect(
        self: Sphere,
        origin: rl.Vector3,
        direction: rl.Vector3,
    ) ?Intersect {
        // origin - center
        const center_to_origin = origin.subtract(self.center);

        const b = 2.0 * direction.dotProduct(center_to_origin);

        const c =
            center_to_origin.dotProduct(center_to_origin) -
            self.radius * self.radius;

        const discriminante = b * b - 4.0 * c;

        if (discriminante >= 0) {
            const solucion = (-b - @sqrt(discriminante)) / 2.0;

            if (solucion > 0) {
                // Punto exacto donde el rayo golpeó la esfera.
                const point = origin.add(
                    direction.scale(solucion),
                );

                // Dirección desde el centro hasta el punto.
                const normal = point
                    .subtract(self.center)
                    .normalize();

                // La normal también representa la posición del punto
                // sobre una esfera unitaria, por eso permite calcular UV.
                const uv = calculateUV(normal);

                return .{
                    .Material = self.material,
                    .Distancia = solucion,
                    .Normal = normal,
                    .Punto = point,
                    .UV = uv,
                };
            }
        }

        return null;
    }
};
