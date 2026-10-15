const rl = @import("raylib");

const Intersect = @import("../raytracer/raytracer.zig").Intersect;
const Material = @import("../raytracer/raytracer.zig").Material;

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
        const epsilon: f32 = 0.000001;

        const edge_1 =
            self.b.position.subtract(self.a.position);

        const edge_2 =
            self.c.position.subtract(self.a.position);

        const p_vector =
            direction.crossProduct(edge_2);

        const determinant =
            edge_1.dotProduct(p_vector);

        // Rayo paralelo o triángulo degenerado.
        if (@abs(determinant) < epsilon) {
            return null;
        }

        const inverse_determinant = 1.0 / determinant;

        const origin_to_a =
            origin.subtract(self.a.position);

        // Influencia del vértice B.
        const b_weight =
            origin_to_a.dotProduct(p_vector) *
            inverse_determinant;

        if (b_weight < 0.0 or b_weight > 1.0) {
            return null;
        }

        const q_vector =
            origin_to_a.crossProduct(edge_1);

        // Influencia del vértice C.
        const c_weight =
            direction.dotProduct(q_vector) *
            inverse_determinant;

        if (c_weight < 0.0 or
            b_weight + c_weight > 1.0)
        {
            return null;
        }

        const distance =
            edge_2.dotProduct(q_vector) *
            inverse_determinant;

        if (distance <= 0.001) {
            return null;
        }

        const barycentric = Barycentric{
            .a = 1.0 - b_weight - c_weight,
            .b = b_weight,
            .c = c_weight,
        };

        const point =
            origin.add(direction.scale(distance));

        const uv =
            self.calculateUV(barycentric);

        var normal =
            self.calculateNormal(barycentric);

        if (normal.dotProduct(direction) > 0.0) {
            normal = normal.scale(-1.0);
        }

        return .{
            .Material = self.material,
            .Distancia = distance,
            .Normal = normal,
            .Punto = point,
            .UV = uv,
        };
    }
};
