// REFERENCIA: https://chatgpt.com/share/e/6af25047-d2a4-83e8-9d65-4bcafc0536ad

const rl = @import("raylib");
const std = @import("std");

pub const Camera = struct {
    Postition: rl.Vector3,
    Forward: rl.Vector3,
    Right: rl.Vector3,
    Up: rl.Vector3,

    pub fn init(position: rl.Vector3, target: rl.Vector3) Camera {
        var out = Camera{
            .Forward = .zero(), //Se va a reemplazar
            .Postition = position,
            .Right = .{ .x = 1, .y = 0, .z = 0 },
            .Up = .{ .x = 0, .y = 1, .z = 0 },
        };
        out.lookAt(target);
        return out;
    }

    //https://www.scratchapixel.com/lessons/mathematics-physics-for-computer-graphics/lookat-function//framing-lookat-function.html
    pub fn lookAt(self: *Camera, target: rl.Vector3) void {
        const direction = target.subtract(self.Postition);
        const length_squared =
            direction.x * direction.x +
            direction.y * direction.y +
            direction.z * direction.z;

        // No existe una dirección si posición y objetivo coinciden.
        if (length_squared < 0.00000001) return;

        self.Forward = direction.normalize();

        var up_reference = self.Up;
        var right = self.Forward.crossProduct(up_reference);

        const right_length_squared =
            right.x * right.x +
            right.y * right.y +
            right.z * right.z;

        if (right_length_squared < 0.00000001) {
            up_reference = if (@abs(self.Forward.y) < 0.99)
                .{ .x = 0, .y = 1, .z = 0 }
            else
                .{ .x = 1, .y = 0, .z = 0 };

            right = self.Forward.crossProduct(up_reference);
        }

        self.Right = right.normalize();
        self.Up = self.Right.crossProduct(self.Forward).normalize();
    }

    // Desplazamiento respecto de los ejes locales de la cámara.
    // Los argumentos son distancias, no velocidades.
    pub fn moveLocal(
        self: *Camera,
        right: f32,
        up: f32,
        forward: f32,
    ) void {
        self.Postition = self.Postition
            .add(self.Right.scale(right))
            .add(self.Up.scale(up))
            .add(self.Forward.scale(forward));
    }

    // Rotación libre: la posición permanece fija.
    // Los ángulos se expresan en radianes.
    // yaw positivo: mirar a la derecha.
    // pitch positivo: mirar arriba.
    pub fn lookFree(self: *Camera, yaw: f32, pitch: f32) void {
        self.rotateBasis(yaw, pitch);
    }

    // Órbita: conserva la distancia al centro y gira a su alrededor.
    // Debes llamar a lookAt(center) una vez al entrar en modo orbital.
    pub fn orbit(
        self: *Camera,
        center: rl.Vector3,
        yaw: f32,
        pitch: f32,
    ) void {
        const offset = self.Postition.subtract(center);
        const radius = @sqrt(
            offset.x * offset.x +
                offset.y * offset.y +
                offset.z * offset.z,
        );

        if (radius < 0.000001) return;

        self.rotateBasis(yaw, pitch);
        self.Postition = center.subtract(self.Forward.scale(radius));
    }

    // Gira usando los ejes locales: permite atravesar los polos
    // e incluso quedar boca abajo.
    fn rotateBasis(self: *Camera, yaw: f32, pitch: f32) void {
        self.Forward = rotate(self.Forward, self.Up, -yaw);
        self.Right = rotate(self.Right, self.Up, -yaw);

        self.Forward = rotate(self.Forward, self.Right, pitch);
        self.Up = rotate(self.Up, self.Right, pitch);

        // Corrige pequeños errores numéricos acumulados.
        self.Forward = self.Forward.normalize();
        self.Right = self.Forward.crossProduct(self.Up).normalize();
        self.Up = self.Right.crossProduct(self.Forward).normalize();
    }

    // https://es.wikipedia.org/wiki/F%C3%B3rmula_de_Euler-Rodrigues
    // Fórmula de Rodrigues. El eje debe estar normalizado.
    // Evita depender del nombre que tenga rotateByAxisAngle
    fn rotate(v: rl.Vector3, axis: rl.Vector3, angle: f32) rl.Vector3 {
        const c = @cos(angle);
        const s = @sin(angle);
        const dot = axis.x * v.x + axis.y * v.y + axis.z * v.z;

        return v.scale(c)
            .add(axis.crossProduct(v).scale(s))
            .add(axis.scale(dot * (1.0 - c)));
    }
};

test "la camara se traslada y rota en sus ejes locales" {
    var camera: Camera = .init(
        .{ .x = 0, .y = 0, .z = 10 },
        .zero(),
    );

    camera.moveLocal(2, 3, 4);
    try std.testing.expectApproxEqAbs(@as(f32, 2), camera.Postition.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 3), camera.Postition.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 6), camera.Postition.z, 0.0001);

    camera.lookFree(std.math.pi / 2.0, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 1), camera.Forward.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), camera.Forward.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), camera.Forward.z, 0.0001);
}
