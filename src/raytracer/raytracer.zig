const rl = @import("raylib");
const Texture = @import("textures.zig").Texture;

pub fn V3FromColor(src: rl.Color) rl.Vector3 {
    const x: f32 = @floatFromInt(src.r);
    const y: f32 = @floatFromInt(src.g);
    const z: f32 = @floatFromInt(src.b);
    return .{ .x = x / 255, .y = y / 255, .z = z / 255 };
}

pub fn V3ToColor(color: rl.Vector3) rl.Color {
    const r: u8 = @intFromFloat(@max(0, @min(255, color.x * 255)));
    const g: u8 = @intFromFloat(@max(0, @min(255, color.y * 255)));
    const b: u8 = @intFromFloat(@max(0, @min(255, color.z * 255)));
    return .{ .r = r, .g = g, .b = b, .a = 0xff };
}

pub const Light = struct {
    Color: rl.Vector3,
    Position: rl.Vector3,
    Intensity: f32,
};

pub const Material = struct {
    //xyz como rgb, pero reducimos conversiones primero haciendo mate en f32 y luego convertimos de regreso a u8
    Color: rl.Vector3,
    Especular: f32,
    Refractive_index: f32,
    Texture: ?*const Texture = null,
    // Luz ambiental neutra aproximada; 0 conserva la iluminacion directa.
    Ambient: f32 = 0,
    // proporciones, de 0 a 1, de cuanto refleja y cuanto deja pasar la luz
    Propiedades: struct {
        Albedo: f32,
        Especular: f32,
        Reflectividad: f32,
        Transparencia: f32,
    },

    pub fn surfaceColor(
        self: Material,
        uv: rl.Vector2,
    ) rl.Vector3 {
        if (self.Texture) |texture| {
            return texture.sample(uv);
        }

        return self.Color;
    }
};

pub const Intersect = struct {
    Material: Material,
    Distancia: f32,
    Normal: rl.Vector3,
    Punto: rl.Vector3,
    UV: rl.Vector2,
};
