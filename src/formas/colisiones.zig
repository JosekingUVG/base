const rl = @import("raylib");

/// Volumen esferico que impide que un punto lo atraviese.
/// Por ahora es suficiente para planetas y para las esferas envolventes
/// de los modelos; mas adelante se pueden agregar otros tipos de collider.
pub const Collider = struct {
    center: rl.Vector3,
    radius: f32,
    solid: bool = true,

    /// Devuelve la fraccion del desplazamiento que puede recorrerse antes de
    /// tocar el collider. null significa que el segmento no lo golpea.
    ///
    /// Se prueba todo el segmento y no solamente su punto final, evitando que
    /// un movimiento rapido atraviese por completo una esfera.
    pub fn movementFraction(
        self: Collider,
        origin: rl.Vector3,
        displacement: rl.Vector3,
    ) ?f32 {
        if (!self.solid or self.radius <= 0) return null;

        const relative_origin = origin.subtract(self.center);
        const radius_squared = self.radius * self.radius;
        const origin_distance_squared = relative_origin.dotProduct(relative_origin);

        // Si el punto ya se encuentra dentro, no permitimos que se interne mas.
        // Si se esta alejando, lo dejamos salir del volumen.
        if (origin_distance_squared < radius_squared) {
            return if (relative_origin.dotProduct(displacement) < 0) 0 else null;
        }

        const movement_squared = displacement.dotProduct(displacement);
        if (movement_squared < 0.00000001) return null;

        // Ecuacion cuadratica del segmento contra la esfera. Se usa la mitad
        // del termino lineal para evitar multiplicaciones innecesarias por dos.
        const toward_center = relative_origin.dotProduct(displacement);
        if (toward_center >= 0) return null;

        const discriminant = toward_center * toward_center -
            movement_squared * (origin_distance_squared - radius_squared);
        if (discriminant < 0) return null;

        const hit_fraction =
            (-toward_center - @sqrt(discriminant)) / movement_squared;
        if (hit_fraction < 0 or hit_fraction > 1) return null;

        // Dejamos un margen diminuto fuera de la superficie para que los
        // errores de f32 no hagan que el siguiente fotograma empiece dentro.
        const movement_length = @sqrt(movement_squared);
        const safe_fraction = @max(0, hit_fraction - 0.001 / movement_length);
        return safe_fraction;
    }

    /// Calcula el choque de una esfera movil contra este collider. Sumar ambos
    /// radios convierte la prueba esfera-esfera en la misma prueba de un punto
    /// contra una esfera expandida (suma de Minkowski).
    pub fn movementFractionFor(
        self: Collider,
        moving: Collider,
        displacement: rl.Vector3,
    ) ?f32 {
        if (!moving.solid or moving.radius < 0) return null;

        var expanded = self;
        expanded.radius += moving.radius;
        return expanded.movementFraction(moving.center, displacement);
    }
};

test "un collider esferico detiene un segmento antes de atravesarlo" {
    const collider: Collider = .{
        .center = .zero(),
        .radius = 2,
    };

    const fraction = collider.movementFraction(
        .{ .x = 0, .y = 0, .z = 5 },
        .{ .x = 0, .y = 0, .z = -10 },
    ) orelse return error.ExpectedCollision;

    try @import("std").testing.expect(fraction > 0.29);
    try @import("std").testing.expect(fraction < 0.3);
}

test "un collider no bloquea movimientos que se alejan" {
    const collider: Collider = .{
        .center = .zero(),
        .radius = 2,
    };

    try @import("std").testing.expectEqual(
        null,
        collider.movementFraction(
            .{ .x = 0, .y = 0, .z = 5 },
            .{ .x = 0, .y = 0, .z = 3 },
        ),
    );
}

test "dos esferas se detienen cuando sus superficies se tocan" {
    const obstacle: Collider = .{
        .center = .zero(),
        .radius = 2,
    };
    const moving: Collider = .{
        .center = .{ .x = 0, .y = 0, .z = 8 },
        .radius = 3,
    };

    const fraction = obstacle.movementFractionFor(
        moving,
        .{ .x = 0, .y = 0, .z = -10 },
    ) orelse return error.ExpectedCollision;

    // Los centros deben quedar separados por 2 + 3 unidades.
    try @import("std").testing.expect(fraction > 0.29);
    try @import("std").testing.expect(fraction < 0.3);
}
