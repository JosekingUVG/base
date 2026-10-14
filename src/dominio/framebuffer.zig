const std = @import("std");
const rl = @import("raylib");

pub const Framebuffer = struct {
    width: i32,
    height: i32,
    color_buff: rl.Image,
    background_color: rl.Color,
    current_color: rl.Color,
    texture: ?rl.Texture = null,

    pub fn init(width: i32, height: i32, background_color: ?rl.Color, draw_color: ?rl.Color) Framebuffer {
        const bg_color = background_color orelse rl.Color.black;
        const color = draw_color orelse rl.Color.white;
        return .{
            .color_buff = rl.genImageColor(width, height, bg_color),
            .width = width,
            .height = height,
            .background_color = bg_color,
            .current_color = color,
        };
    }

    pub fn clear(self: *Framebuffer) void {
        @memset(self.pixels(), self.background_color);
    }

    pub fn deinit(self: *Framebuffer) void {
        if (self.texture) |texture| rl.unloadTexture(texture);
        rl.unloadImage(self.color_buff);
        self.texture = null;
    }

    // genImageColor crea una imagen RGBA8 contigua. No cambiar su formato.
    // En paralelo, cada trabajador debe tener filas exclusivas.
    pub fn pixels(self: *const Framebuffer) []rl.Color {
        std.debug.assert(self.color_buff.format == .uncompressed_r8g8b8a8);
        const data: [*]rl.Color = @ptrCast(@alignCast(self.color_buff.data));
        return data[0 .. @as(usize, @intCast(self.width)) * @as(usize, @intCast(self.height))];
    }

    pub fn set_pixel(self: *Framebuffer, x: i32, y: i32) !void {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) return error.BadCoordinates;
        self.pixels()[@as(usize, @intCast(y)) * @as(usize, @intCast(self.width)) + @as(usize, @intCast(x))] = self.current_color;
    }

    pub fn set_background_color(self: *Framebuffer, color: rl.Color) void {
        self.background_color = color;
    }

    pub fn set_current_color(self: *Framebuffer, color: rl.Color) void {
        self.current_color = color;
    }

    pub fn render_to_file(self: Framebuffer, filename: []const u8) !void {
        if (!self.color_buff.exportToFile(@ptrCast(filename))) return error.CouldntWriteFile;
    }

    pub fn swap_buffers(self: *Framebuffer, image_changed: bool) !void {
        // Transferimos la imagen a la GPU únicamente cuando recalculamos rayos.
        if (self.texture) |texture| {
            if (image_changed) rl.updateTexture(texture, self.color_buff.data);
        } else {
            self.texture = try rl.loadTextureFromImage(self.color_buff);
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        // Raylib maneja los conceptos de Image y Texture
        // En esencia son lo mismo, un buffer de color, o imagen.
        // Pero Image está en la RAM, mientras que Texture está en la VRAM.
        // (La RAM del CPU vs la del GPU)
        // Para que la GPU pueda operar sobre una imagen, esta tiene que estar en la VRAM.
        // En este caso, solo estamos cargando a la GPU la imagen que dibujamos para poder mostrarla.
        rl.drawTexture(self.texture.?, 0, 0, .white);

        // endDrawing presenta la textura. La conservamos para los siguientes
        // fotogramas y actualizamos sus datos cuando cambió la imagen.
    }
};
