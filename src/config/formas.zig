const Forma = @import("../formas/formas.zig").Forma;
const Material = @import("../raytracer/raytracer.zig").Material;
const Texture = @import("../raytracer/textures.zig").Texture;
const Mesh = @import("../formas/modelos/mesh.zig").Mesh;
const V3FromColor = @import("../raytracer/raytracer.zig").V3FromColor;
const htmlColor = @import("../raytracer/cute_colors.zig").htmlColor;

pub const floor_texture_path = "assets/plane/textures/hinoki_planks_disp_4k.png";
pub const model_texture_path = "assets/koala/colormap.png";
// Modelo extraído de https://kenney.nl/assets/cube-pets
pub const model_path = "assets/koala/Untitled.obj";

pub fn modelMaterial(model_texture: *const Texture) Material {
    return Material{
        .Texture = model_texture,
        // Conserva el color de la textura incluso fuera de la luz directa.
        .Ambient = 0.6,

        // La textura define el color; blanco no la modifica.
        .Color = V3FromColor(htmlColor("#fff")),

        .Propiedades = .{
            .Albedo = 0.4,
            .Especular = 0.0,
            .Reflectividad = 0.0,
            .Transparencia = 0.0,
        },

        // No influye mientras Propiedades.Especular sea 0.
        .Especular = 1000,

        // Tampoco influye mientras Transparencia sea 0.
        .Refractive_index = 1.0,
    };
}

// Los recursos prestados deben vivir mientras se renderiza la escena.
pub fn create(mesh: Mesh, model_material: Material, floor_texture: *const Texture) [2]Forma {
    //ESPEJO:
    //const espejo = Material{
    //    .Color = V3FromColor(htmlColor("#fff")),
    //    .Propiedades = .{
    //        .Albedo = 0, // albedo es la capacidad de dispersión de la luz
    //        .Especular = 1,
    //        .Reflectividad = 0.9,
    //        .Transparencia = 0,
    //    },
    //    .Especular = 100,
    //    .Refractive_index = 0,
    // };

    // Plano
    const floor_material = Material{
        .Color = V3FromColor(htmlColor("#fff")),
        .Texture = floor_texture,

        // Propiedes extraidas de  https://www.lifeder.com/propiedades-opticas-materiales/ y https://gemini.com
        .Propiedades = .{
            .Albedo = 0.4,
            .Especular = 0.5,
            .Reflectividad = 0.1,
            .Transparencia = 0,
        },

        .Especular = 100,
        .Refractive_index = 1.5,
    };

    // VIDRIO:
    //const vidrio = Material{
    //    .Color = V3FromColor(htmlColor("#aaa")),
    //    .Propiedades = .{
    //        .Albedo = 0,
    //        .Especular = 0.5,
    //        .Reflectividad = 0.1,
    //       .Transparencia = 0.8,
    //   },
    //   .Especular = 125,
    //   .Refractive_index = 1.5,
    //};

    // DIAMANTE:
    //const diamante = Material{
    //   .Color = V3FromColor(htmlColor("#aaa")),
    //   .Propiedades = .{
    //       .Albedo = 0,
    //       .Especular = 0.5,
    //       .Reflectividad = 0.1,
    //       .Transparencia = 0.8,
    //   },
    //   .Refractive_index = 2.417,
    //   .Especular = 125,
    //};

    // MARMOL:
    //const marmol = Material{
    //    .Color = V3FromColor(htmlColor("#66664c")),
    //    .Propiedades = .{
    //        .Albedo = 0.4,
    //        .Especular = 0.3,
    //        .Reflectividad = 0,
    //        .Transparencia = 0,
    //    },
    //    .Especular = 10,
    //    .Refractive_index = 0,
    //};

    return .{

        // Modelo 3D:
        .{
            .Model = .{
                .mesh = mesh,
                .position = .{ .x = 0, .y = -5, .z = 0 }, // El origen del koala está en su base.
                .scale = 20,
                .bounding_sphere = .{
                    // Esfera invisible en coordenadas de la escena: encierra al koala.
                    .center = .{ .x = 0, .y = 10, .z = 0 },
                    .radius = 30,
                    .material = model_material,
                },
            },
        },
        //.{ .Sphere = .{
        //    .center = .{ .x = 10, .y = 0, .z = -40 },
        //    .radius = 5,
        //    .material = espejo,
        //} },
        //.{ .Sphere = .{
        //    .center = .{ .x = 12.5, .y = 0, .z = -60 },
        //    .radius = 5,
        //    .material = .{
        //        .Color = V3FromColor(htmlColor("#fff")),
        //        .Propiedades = .{
        //            .Albedo = 0.9,
        //            .Especular = 0.1,
        //            .Reflectividad = 0,
        //            .Transparencia = 0,
        //        },
        //        .Especular = 10,
        //        .Refractive_index = 0,
        //    },
        //} },

        // Plano:

        .{ .Plane = .{
            .p_0 = .{ .x = 0, .y = -5, .z = 0 },
            .normal = .{ .x = 0, .y = 1, .z = 0 },

            .u_axis = .{ .x = 1, .y = 0, .z = 0 },
            .v_axis = .{ .x = 0, .y = 0, .z = 1 },

            .u_size = 10,
            .v_size = 10,

            .material = floor_material,
        } }, //,

        //.{ .Sphere = .{
        //    .center = .{ .x = 0, .y = 0, .z = 0 },
        //    .radius = 5,
        //    .material = marmol,
        //} },
        //.{ .Sphere = .{
        //    .center = .{ .x = 22, .y = 0, .z = -45 },
        //    .radius = 5,
        //    .material = espejo,
        //} },
        //.{ .Sphere = .{
        //    .center = .{ .x = -25, .y = 0, .z = -40 },
        //    .radius = 5,
        //    .material = vidrio,
        //} },
        //.{ .Sphere = .{
        //    .center = .{ .x = -37, .y = 0, .z = -40 },
        //    .radius = 5,
        //    .material = diamante,
        //} },
    };
}
