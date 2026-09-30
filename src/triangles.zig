const rl = @import("raylib");

const Intersect = @import("raytracer.zig").Intersect;
const Material = @import("raytracer.zig").Material;

pub const Vertex = struct {
    position: rl.Vector3,
    normal: rl.Vector3,
    uv: rl.Vector2,
};

pub const Barycentric = struct {
    u: f32,
    v: f32,
    w: f32,
};

pub const Triangle = struct {
    a: Vertex,
    b: Vertex,
    c: Vertex,

    material: Material,

    /// Devuelve el doble del área del triángulo.
    ///
    /// No dividimos entre 2 porque las áreas solamente se utilizarán
    /// como proporciones, así que ese factor se cancelaría.
    fn doubleArea(
        p0: rl.Vector3,
        p1: rl.Vector3,
        p2: rl.Vector3,
    ) f32 {
        const edge_1 = p1.subtract(p0);
        const edge_2 = p2.subtract(p0);

        // Porque, evidentemente, la forma más intuitiva de calcular
        // un área era producir un vector que apunta fuera del triángulo.
        const cross = edge_1.crossProduct(edge_2);

        return cross.length();
    }

    /// Calcula las coordenadas baricéntricas del punto.
    ///
    /// Devuelve null si el punto está fuera del triángulo.
    pub fn calculateUVW(
        self: Triangle,
        point: rl.Vector3,
    ) ?Barycentric {
        const total_area = doubleArea(
            self.a.position,
            self.b.position,
            self.c.position,
        );

        // Los tres puntos no forman un triángulo válido.
        if (total_area < 0.000001) {
            return null;
        }

        // Influencia del vértice A:
        // área del triángulo PBC / área de ABC.
        const u = doubleArea(
            point,
            self.b.position,
            self.c.position,
        ) / total_area;

        // Influencia del vértice B:
        // área del triángulo APC / área de ABC.
        const v = doubleArea(
            self.a.position,
            point,
            self.c.position,
        ) / total_area;

        // Influencia del vértice C:
        // área del triángulo ABP / área de ABC.
        const w = doubleArea(
            self.a.position,
            self.b.position,
            point,
        ) / total_area;

        const sum = u + v + w;
        const epsilon: f32 = 0.0001;

        // Para un punto interior debe cumplirse:
        //
        // u >= 0
        // v >= 0
        // w >= 0
        // u + v + w ≈ 1
        if (u < -epsilon or
            v < -epsilon or
            w < -epsilon or
            @abs(sum - 1.0) > epsilon)
        {
            return null;
        }

        return .{
            .u = u,
            .v = v,
            .w = w,
        };
    }

    /// Interpola los UV de los tres vértices.
    fn calculateUV(
        self: Triangle,
        barycentric: Barycentric,
    ) rl.Vector2 {
        return .{
            .x = self.a.uv.x * barycentric.u +
                self.b.uv.x * barycentric.v +
                self.c.uv.x * barycentric.w,

            .y = self.a.uv.y * barycentric.u +
                self.b.uv.y * barycentric.v +
                self.c.uv.y * barycentric.w,
        };
    }

    /// Interpola las normales de los tres vértices.
    fn calculateNormal(
        self: Triangle,
        barycentric: Barycentric,
    ) rl.Vector3 {
        return self.a.normal
            .scale(barycentric.u)
            .add(self.b.normal.scale(barycentric.v))
            .add(self.c.normal.scale(barycentric.w))
            .normalize();
    }

    pub fn intersect(
        self: Triangle,
        origin: rl.Vector3,
        direction: rl.Vector3,
    ) ?Intersect {

        // 1. Encontrar el plano que contiene el triángulo.

        const ab = self.b.position.subtract(self.a.position);
        const ac = self.c.position.subtract(self.a.position);

        const cross = ab.crossProduct(ac);

        // Si el área es prácticamente cero, los vértices son
        // colineales y no forman un triángulo válido.
        if (cross.length() < 0.000001) {
            return null;
        }

        const plane_normal = cross.normalize();

        // 2. Intersectar el rayo con el plano.

        const denominator =
            direction.dotProduct(plane_normal);

        // El rayo es paralelo al plano.
        if (@abs(denominator) < 0.000001) {
            return null;
        }

        const solution =
            self.a.position
                .subtract(origin)
                .dotProduct(plane_normal) /
            denominator;

        // La intersección está detrás del rayo.
        if (solution <= 0.001) {
            return null;
        }

        // 3. Obtener el punto de impacto.

        // P = O + tD

        const point =
            origin.add(direction.scale(solution));

        // 4. Comprobar si el punto está dentro del triángulo.

        const barycentric =
            self.calculateUVW(point) orelse return null;

        // 5. Interpolar UV y normal.

        const uv = self.calculateUV(barycentric);

        var normal = self.calculateNormal(barycentric);

        // Hacemos que la normal apunte contra el rayo.
        if (normal.dotProduct(direction) > 0) {
            normal = normal.scale(-1);
        }

        return .{
            .Material = self.material,
            .Distancia = solution,
            .Normal = normal,
            .Punto = point,
            .UV = uv,
        };
    }
};
