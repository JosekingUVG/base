// Referencias: https://www.scratchapixel.com/lessons/3d-basic-rendering/ray-tracing-rendering-a-triangle//moller-trumbore-ray-triangle-intersection.html

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

    // Implementación del algoritmo de Möller-Trumbore para la intersección rayo-triángulo.
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

        // Interpolación de coordenadas baricéntricas.
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
