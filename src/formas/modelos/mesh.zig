const std = @import("std");
const rl = @import("raylib");

const Material = @import("../raytracer/raytracer.zig").Material;
const Triangle = @import("triangles.zig").Triangle;
const Vertex = @import("triangles.zig").Vertex;

pub const Mesh = struct {
    triangles: []Triangle,
    allocator: std.mem.Allocator,

    pub const LoadError = error{
        InvalidVertex,
        InvalidTextureCoordinate,
        InvalidNormal,
        InvalidFace,
        InvalidIndex,
        EmptyMesh,
    };

    const ObjIndex = struct {
        position: usize,
        uv: ?usize,
        normal: ?usize,
    };

    /// Carga el subconjunto de OBJ que necesita el raytracer:
    ///
    /// - `v`: posiciones
    /// - `vt`: coordenadas UV
    /// - `vn`: normales
    /// - `f`: caras
    ///
    /// Las caras con más de tres vértices se triangulan en abanico.
    /// El material se copia a cada triángulo generado.
    pub fn loadObj(
        allocator: std.mem.Allocator,
        path: []const u8,
        material: Material,
    ) !Mesh {
        const source = try std.fs.cwd().readFileAlloc(
            allocator,
            path,
            64 * 1024 * 1024,
        );
        defer allocator.free(source);

        return loadObjFromMemory(allocator, source, material);
    }

    /// Variante útil para pruebas: interpreta un OBJ que ya está en memoria.
    pub fn loadObjFromMemory(
        allocator: std.mem.Allocator,
        source: []const u8,
        material: Material,
    ) !Mesh {
        var positions: std.ArrayList(rl.Vector3) = .empty;
        defer positions.deinit(allocator);

        var uvs: std.ArrayList(rl.Vector2) = .empty;
        defer uvs.deinit(allocator);

        var normals: std.ArrayList(rl.Vector3) = .empty;
        defer normals.deinit(allocator);

        var triangles: std.ArrayList(Triangle) = .empty;
        errdefer triangles.deinit(allocator);

        var face: std.ArrayList(ObjIndex) = .empty;
        defer face.deinit(allocator);

        var lines = std.mem.splitScalar(u8, source, '\n');
        while (lines.next()) |untrimmed_line| {
            const line = std.mem.trim(u8, untrimmed_line, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;

            var words = std.mem.tokenizeAny(u8, line, " \t");
            const command = words.next() orelse continue;

            if (std.mem.eql(u8, command, "v")) {
                try positions.append(allocator, .{
                    .x = try parseFloat(words.next() orelse return LoadError.InvalidVertex),
                    .y = try parseFloat(words.next() orelse return LoadError.InvalidVertex),
                    .z = try parseFloat(words.next() orelse return LoadError.InvalidVertex),
                });
            } else if (std.mem.eql(u8, command, "vt")) {
                try uvs.append(allocator, .{
                    .x = try parseFloat(words.next() orelse return LoadError.InvalidTextureCoordinate),
                    .y = try parseFloat(words.next() orelse return LoadError.InvalidTextureCoordinate),
                });
            } else if (std.mem.eql(u8, command, "vn")) {
                const normal = rl.Vector3{
                    .x = try parseFloat(words.next() orelse return LoadError.InvalidNormal),
                    .y = try parseFloat(words.next() orelse return LoadError.InvalidNormal),
                    .z = try parseFloat(words.next() orelse return LoadError.InvalidNormal),
                };
                try normals.append(allocator, normal.normalize());
            } else if (std.mem.eql(u8, command, "f")) {
                face.clearRetainingCapacity();

                while (words.next()) |vertex_text| {
                    if (vertex_text[0] == '#') break;
                    try face.append(
                        allocator,
                        try parseObjIndex(
                            vertex_text,
                            positions.items.len,
                            uvs.items.len,
                            normals.items.len,
                        ),
                    );
                }

                if (face.items.len < 3) return LoadError.InvalidFace;

                // (0, 1, 2), (0, 2, 3), (0, 3, 4), ...
                for (1..face.items.len - 1) |i| {
                    try triangles.append(
                        allocator,
                        makeTriangle(
                            face.items[0],
                            face.items[i],
                            face.items[i + 1],
                            positions.items,
                            uvs.items,
                            normals.items,
                            material,
                        ),
                    );
                }
            }
        }

        if (triangles.items.len == 0) return LoadError.EmptyMesh;

        return .{
            .triangles = try triangles.toOwnedSlice(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Mesh) void {
        self.allocator.free(self.triangles);
        self.* = undefined;
    }

    fn parseFloat(text: []const u8) !f32 {
        return std.fmt.parseFloat(f32, text);
    }

    fn parseObjIndex(
        text: []const u8,
        position_count: usize,
        uv_count: usize,
        normal_count: usize,
    ) !ObjIndex {
        var parts = std.mem.splitScalar(u8, text, '/');

        const position_text = parts.next() orelse return LoadError.InvalidFace;
        const uv_text = parts.next();
        const normal_text = parts.next();

        // Un elemento de una cara solamente puede ser v, v/vt o v/vt/vn.
        if (parts.next() != null) return LoadError.InvalidFace;

        return .{
            .position = try resolveIndex(position_text, position_count),
            .uv = if (uv_text) |value|
                if (value.len == 0) null else try resolveIndex(value, uv_count)
            else
                null,
            .normal = if (normal_text) |value|
                if (value.len == 0) null else try resolveIndex(value, normal_count)
            else
                null,
        };
    }

    /// OBJ usa índices positivos desde 1 e índices negativos desde el final.
    fn resolveIndex(text: []const u8, count: usize) !usize {
        if (text.len == 0) return LoadError.InvalidIndex;

        const raw = std.fmt.parseInt(i64, text, 10) catch {
            return LoadError.InvalidIndex;
        };

        if (raw == 0) return LoadError.InvalidIndex;

        const resolved: i64 = if (raw > 0)
            raw - 1
        else
            @as(i64, @intCast(count)) + raw;

        if (resolved < 0 or resolved >= @as(i64, @intCast(count))) {
            return LoadError.InvalidIndex;
        }

        return @intCast(resolved);
    }

    fn makeTriangle(
        a_index: ObjIndex,
        b_index: ObjIndex,
        c_index: ObjIndex,
        positions: []const rl.Vector3,
        uvs: []const rl.Vector2,
        normals: []const rl.Vector3,
        material: Material,
    ) Triangle {
        const a_position = positions[a_index.position];
        const b_position = positions[b_index.position];
        const c_position = positions[c_index.position];

        // Si el OBJ no incluye `vn`, usamos una normal plana para la cara.
        const face_normal = b_position
            .subtract(a_position)
            .crossProduct(c_position.subtract(a_position))
            .normalize();

        return .{
            .a = makeVertex(a_index, a_position, uvs, normals, face_normal),
            .b = makeVertex(b_index, b_position, uvs, normals, face_normal),
            .c = makeVertex(c_index, c_position, uvs, normals, face_normal),
            .material = material,
        };
    }

    fn makeVertex(
        index: ObjIndex,
        position: rl.Vector3,
        uvs: []const rl.Vector2,
        normals: []const rl.Vector3,
        fallback_normal: rl.Vector3,
    ) Vertex {
        return .{
            .position = position,
            .uv = if (index.uv) |i| uvs[i] else .zero(),
            .normal = if (index.normal) |i| normals[i] else fallback_normal,
        };
    }
};
