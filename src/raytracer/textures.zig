// REFERENCIA: https://chatgpt.com/share/e/6af3b993-6a88-83e8-ae86-e10cc7bb94db

const std = @import("std");
const rl = @import("raylib");

pub const Texture = struct {
    width: usize,
    height: usize,
    data: []rl.Vector3,
    allocator: std.mem.Allocator,

    pub fn load(
        allocator: std.mem.Allocator,
        io: std.Io,
        path: []const u8,
    ) !Texture {
        // Leemos los bytes del archivo.
        const bytes = try std.Io.Dir.cwd().readFileAlloc(
            io,
            path,
            allocator,
            .limited(256 * 1024 * 1024),
        );
        defer allocator.free(bytes);

        var position: usize = 0;

        // La cabecera contiene: P6, ancho, alto y máximo.
        const format = try nextToken(bytes, &position);
        if (!std.mem.eql(u8, format, "P6")) {
            return error.UnsupportedPpmFormat;
        }

        const width = try std.fmt.parseInt(
            usize,
            try nextToken(bytes, &position),
            10,
        );
        const height = try std.fmt.parseInt(
            usize,
            try nextToken(bytes, &position),
            10,
        );
        const maximum = try std.fmt.parseInt(
            usize,
            try nextToken(bytes, &position),
            10,
        );

        if (width == 0 or height == 0) {
            return error.InvalidDimensions;
        }
        if (maximum != 255) {
            return error.UnsupportedColorDepth;
        }

        // P6 separa la cabecera de los píxeles con un whitespace.
        // No debemos saltar todos los espacios: un píxel podría
        // contener un byte cuyo valor coincida con un espacio.
        if (position >= bytes.len or
            !std.ascii.isWhitespace(bytes[position]))
        {
            return error.InvalidPpmHeader;
        }
        position += 1;

        const pixel_count = try std.math.mul(usize, width, height);
        const byte_count = try std.math.mul(usize, pixel_count, 3);

        if (bytes.len - position < byte_count) {
            return error.IncompletePixelData;
        }

        const data = try allocator.alloc(rl.Vector3, pixel_count);
        errdefer allocator.free(data);

        // Convertimos cada grupo RGB a un Vector3 normalizado.
        for (data, 0..) |*pixel, i| {
            const offset = position + i * 3;

            pixel.* = .{
                .x = @as(f32, @floatFromInt(bytes[offset])) / 255.0,
                .y = @as(f32, @floatFromInt(bytes[offset + 1])) / 255.0,
                .z = @as(f32, @floatFromInt(bytes[offset + 2])) / 255.0,
            };
        }

        return .{
            .width = width,
            .height = height,
            .data = data,
            .allocator = allocator,
        };
    }

    pub fn sample(
        self: Texture,
        uv: rl.Vector2,
    ) rl.Vector3 {
        const wrapped_u = uv.x - @floor(uv.x);
        const wrapped_v = uv.y - @floor(uv.y);

        const x: usize = @intFromFloat(
            wrapped_u * @as(f32, @floatFromInt(self.width)),
        );

        const y: usize = @intFromFloat(
            (1.0 - wrapped_v) *
                @as(f32, @floatFromInt(self.height - 1)),
        );

        return self.data[y * self.width + x];
    }

    /// Convierte una dirección 3D en coordenadas equirectangulares para
    /// muestrear una imagen panorámica usada como fondo.
    pub fn sampleDirection(
        self: Texture,
        direction: rl.Vector3,
    ) rl.Vector3 {
        const normalized = direction.normalize();
        const u = 0.5 + std.math.atan2(
            normalized.z,
            normalized.x,
        ) / (2.0 * std.math.pi);
        const v = 0.5 + std.math.asin(
            @max(-1.0, @min(1.0, normalized.y)),
        ) / std.math.pi;

        return self.sample(.{ .x = u, .y = v });
    }

    pub fn deinit(self: *Texture) void {
        self.allocator.free(self.data);
        self.* = undefined;
    }
};

// Lee una palabra de la cabecera.
// Ignora espacios y comentarios que comienzan con '#'.
fn nextToken(bytes: []const u8, position: *usize) ![]const u8 {
    while (position.* < bytes.len) {
        const byte = bytes[position.*];

        if (std.ascii.isWhitespace(byte)) {
            position.* += 1;
        } else if (byte == '#') {
            while (position.* < bytes.len and
                bytes[position.*] != '\n')
            {
                position.* += 1;
            }
        } else {
            break;
        }
    }

    const start = position.*;

    while (position.* < bytes.len) {
        const byte = bytes[position.*];

        if (std.ascii.isWhitespace(byte) or byte == '#') {
            break;
        }

        position.* += 1;
    }

    if (start == position.*) {
        return error.UnexpectedEndOfHeader;
    }

    return bytes[start..position.*];
}
