const rl = @import("raylib");

const Intersect = @import("raytracer.zig").Intersect;
const Material = @import("raytracer.zig").Material;

pub const Plane = struct {
    // Un punto cualquiera perteneciente al plano.
    p_0: rl.Vector3,

    // Orientación del plano.
    normal: rl.Vector3,

    // Direcciones de la textura dentro del plano.
    u_axis: rl.Vector3,
    v_axis: rl.Vector3,

    // Tamaño de una repetición en unidades del mundo.
    u_size: f32,
    v_size: f32,

    material: Material,

    fn calculateUV(
        self: Plane,
        point: rl.Vector3,
    ) rl.Vector2 {
        // Vector desde el origen del plano hasta el punto de impacto.
        const relative_point = point.subtract(self.p_0);

        // Proyectamos el punto sobre los ejes de la textura.
        const u =
            relative_point.dotProduct(self.u_axis) /
            self.u_size;

        const v =
            relative_point.dotProduct(self.v_axis) /
            self.v_size;

        return .{
            .x = u,
            .y = v,
        };
    }

    pub fn intersect(
        self: Plane,
        origin: rl.Vector3,
        direction: rl.Vector3,
    ) ?Intersect {
        // Denominador de la ecuación rayo-plano:
        //
        // t = ((P₀ - O) · N) / (D · N)
        const denominator =
            direction.dotProduct(self.normal);

        // Si D · N ≈ 0, el rayo es paralelo al plano.
        if (@abs(denominator) < 0.000001) {
            return null;
        }

        const origin_to_plane =
            self.p_0.subtract(origin);

        const solution =
            origin_to_plane.dotProduct(self.normal) /
            denominator;

        // La intersección está detrás de la cámara
        // o demasiado cerca de su origen.
        if (solution <= 0.001) {
            return null;
        }

        // P = O + tD
        const point =
            origin.add(direction.scale(solution));

        // Ahora que conocemos P, podemos calcular sus UV.
        const uv = self.calculateUV(point);

        // Si queremos que el plano sea visible por ambos lados,
        // orientamos la normal contra el rayo.
        const surface_normal = if (denominator < 0)
            self.normal
        else
            self.normal.scale(-1);

        return .{
            .Material = self.material,
            .Distancia = solution,
            .Normal = surface_normal,
            .Punto = point,
            .UV = uv,
        };
    }
};
