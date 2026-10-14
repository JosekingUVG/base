const rl = @import("raylib");
const triangle = @import("triangle").Triangle;
pub const Model = struct {
    triangles: []Triangle,
    bounds: BoundingSphere,

    pub fn intersect(
        self: Model,
        origin: rl.Vector3,
        direction: rl.Vector3,
    ) ?Intersect {
        // 1. Probar esfera envolvente.
        // 2. Si falla, retornar null.
        // 3. Probar todos los triángulos.
        // 4. Retornar el impacto más cercano.
    }
};
