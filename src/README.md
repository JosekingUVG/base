# Guía de interacción de clases y métodos en src

Este documento explica cómo se conectan los archivos y funciones del programa dentro de `src`, especialmente en el raytracer que se ejecuta desde `main.zig`.

## 1. Visión general

El programa principal sigue este flujo:

1. `main.zig` crea un `Framebuffer`, prepara materiales y esferas, crea una `Camera`, define luces y entra en el bucle principal.
2. En cada frame:
   - actualiza la posición y orientación de la cámara según las teclas `W`, `A`, `S`, `D`,
   - llama a `render(...)`,
   - luego llama a `framebuffer.swap_buffers()` para dibujar el resultado en la ventana.
3. `render(...)` genera un rayo por cada pixel de la pantalla.
4. Cada rayo es evaluado por `cast_ray(...)`.
5. `cast_ray(...)` recorre las formas (`Forma`), usa `Forma.intersect(...)` y, si hay colisión, obtiene información del punto de impacto.
6. Con ese `Intersect`, calcula el color final combinando:
   - reflexión,
   - transparencia/refracción,
   - iluminación por luces,
   - material del objeto.
7. El resultado se envía al `Framebuffer` para dibujarse en pantalla.

---

## 2. Archivo por archivo

### `main.zig`

Es el archivo principal del programa y actúa como orquestador general.

#### Funciones principales

- `main()`: crea el entorno, define materiales, 객체, luces, cámara y controla el loop principal.

- `render(target, objects, lights, camera)`:
  - recorre cada pixel del framebuffer,
  - construye la dirección del rayo a partir de la cámara y el FOV,
  - llama a `cast_ray(...)`,
  - convierte el color resultante a `rl.Color` y lo escribe con `target.set_pixel(...)`.

- `refract(incident, normal, refractive_index)`:
  - calcula una dirección refractada usando la normal y el índice de refracción.
  - devuelve `null` cuando ocurre reflexión total interna.

- `cast_ray(origin, direction, objects, lights, max_recursion)`:
  - busca la intersección más cercana entre el origen del rayo y todas las formas,
  - usa un z-buffer (`z_buffer`) para conservar la intersección más cercana,
  - si hay impacto, calcula el color resultante,
  - combina reflexión, transparencia y luces,
  - devuelve un `rl.Vector3` con el color final.

- `obscured(origin, light, objects)`:
  - debería verificar si un punto está bloqueado por otra forma antes de recibir luz,
  - actualmente está incompleto y siempre retorna `false`.

#### Cómo interactúa con el resto

- Importa `Framebuffer`, `Forma`, `Camera`, `Light`, `Material`, `Intersect` y utilidades auxiliares.
- Crea objetos del tipo `Forma` con `Sphere`.
- Delegando la búsqueda de colisiones a `Forma.intersect(...)`.
- Usa `Camera` para mover la perspectiva y generar direcciones de rayo.
- Usa `Light` y `Material` para calcular iluminación y propiedades visuales.

---

### `camera.zig`

Define la estructura `Camera`.

#### `Camera` estructura

Campos principales:

- `Postition`: posición de la cámara.
- `Forward`: dirección hacia donde apunta la cámara.
- `Right`: eje derecho de la cámara.
- `Up`: eje vertical de la cámara.

#### Métodos

- `init(position, target)`: crea una cámara con posición inicial y apunta hacia el target.

- `lookAt(target)`: recalcula `Forward`, `Right` y `Up` usando vectores y producto cruz.

#### Cómo interactúa con el resto

- `main.zig` crea una cámara y actualiza su posición a medida que el usuario mueve la vista.
- `render(...)` usa `camera.Right`, `camera.Up`, `camera.Forward` para transformar los rayos del espacio de pantalla al espacio del mundo.

---

### `framebuffer.zig`

Define `Framebuffer`, la clase que representa el buffer de imagen de la aplicación.

#### Estructura

- `width`, `height`: tamaño de la imagen.
- `color_buff`: `rl.Image`, que almacena los píxeles en CPU.
- `background_color`: color de fondo.
- `current_color`: color actual usado al dibujar.
- `texture`: textura cargada en GPU para mostrar en pantalla.

#### Métodos

- `init(width, height, background_color, draw_color)`: crea un framebuffer con colores iniciales.

- `clear()`: limpia el buffer y libera la textura si existe.

- `set_pixel(x, y)`: dibuja un pixel usando `current_color`.

- `set_background_color(color)`: cambia el color de fondo.

- `set_current_color(color)`: cambia el color usado para dibujar.

- `render_to_file(filename)`: exporta la imagen a archivo.

- `swap_buffers()`:
  - hace `beginDrawing` / `endDrawing`,
  - carga la imagen a una textura,
  - dibuja la textura en pantalla,
  - guarda la textura para limpiarla en el siguiente frame.

#### Cómo interactúa con el resto

- `main.zig` usa `Framebuffer.init(...)` para crear el buffer principal.
- `render(...)` escribe en `target` mediante `target.set_current_color(...)` y `target.set_pixel(...)`.
- `main.zig` luego invoca `framebuffer.swap_buffers()` para mostrar el frame.

---

### `formas.zig`

Define la unión `Forma`, que puede contener distintas formas geométricas.

#### `Forma`

- Actualmente soporta únicamente `Sphere`.

#### Método

- `intersect(self, origin, direction)`:
  - dispara el cálculo de intersección según el tipo concreto de forma,
  - en el caso actual, delega a `Sphere.intersect(...)`.

#### Cómo interactúa con el resto

- `main.zig` declara un arreglo `[]Forma` llamado `spheres`.
- `cast_ray(...)` itera sobre cada `Forma` y ejecuta `object.intersect(...)`.
- Esto permite que el raytracer trabaje con una colección uniforme de formas aunque cada una pueda tener su propia lógica de colisión.

---

### `sphere.zig`

Implementa la geometría de la esfera y su cálculo de intersección.

#### `Sphere` estructura

Campos:

- `center`: centro de la esfera.
- `radius`: radio.
- `material`: material asociado.

#### Método

- `intersect(self, origin, direction)`:
  - calcula la ecuación de intersección entre el rayo y la esfera,
  - usa el discriminante para saber si el rayo golpea la esfera,
  - si sí, calcula:
    - `Distancia`,
    - `Punto`,
    - `Normal`,
    - `Material`.

#### Cómo interactúa con el resto

- `Forma.intersect(...)` llama a este método.
- El `Intersect` devuelto se usa en `cast_ray(...)` para decidir si la esfera es el hit más cercano y con qué material interactuar.

---

### `raytracer.zig`

Contiene las estructuras de datos compartidas del raytracer.

#### `Light`

Representa una fuente de luz con:

- `Color`: tint de la luz,
- `Position`: posición,
- `Intensity`: intensidad.

#### `Material`

Representa las propiedades visuales de un objeto. Campos:

- `Color`: color base del material.
- `Especular`: intensidad especular.
- `Refractive_index`: índice de refracción.
- `Propiedades`:
  - `Albedo`
  - `Especular`
  - `Reflectividad`
  - `Transparencia`

#### `Intersect`

Información devuelta por una intersección:

- `Material`
- `Distancia`
- `Normal`
- `Punto`

#### Funciones auxiliares

- `V3FromColor(src)`: convierte `rl.Color` a un `rl.Vector3` en rango `0..1`.
- `V3ToColor(color)`: convierte un `rl.Vector3` a `rl.Color` en rango `0..255`.

#### Cómo interactúa con el resto

- `main.zig` usa `Material` para construir cada esfera.
- `Sphere.intersect(...)` devuelve un `Intersect` con el `Material` asociado.
- `cast_ray(...)` usa `Intersect.Material`, `Intersect.Normal`, `Intersect.Punto` y `Intersect.Distancia` para colorear y decidir reflejos/refracciones.

---

### `cute_colors.zig`

Define una función utilitaria para convertir códigos hexadecimales HTML (`#RRGGBB`, `#RGB`, `#RRGGBBAA`, `#RGBA`) a `rl.Color`.

#### Función

- `htmlColor(comptime html)`:
  - valida el formato,
  - decodifica el valor hexadecimal en tiempo de compilación,
  - devuelve un `rl.Color`.

#### Cómo interactúa con el resto

- `main.zig` usa `htmlColor(...)` para definir colores rápidos de materiales y luces.
- Después, esos colores se convierten con `V3FromColor(...)` para usarlos como vectores RGB en el cálculo del raytracer.

---

## 3. Flujo completo de una imagen

### Carga inicial

`main.zig` hace lo siguiente:

1. crea un `Framebuffer`,
2. define materiales (`espejo`, `vidrio`, `diamante`, `marmol`),
3. crea una lista de esferas con esas propiedades,
4. prepara luces,
5. crea una `Camera`,
6. entra al loop principal.

### Cada frame

1. `main.zig` actualiza la cámara según teclas.
2. `render(...)` recorre todos los píxeles.
3. Para cada píxel:
   - genera una dirección de rayo a partir de la cámara,
   - llama a `cast_ray(...)`.
4. `cast_ray(...)`:
   - recorre `objects` (`Forma`),
   - pregunta por `object.intersect(...)`,
   - conserva el hit más cercano,
   - si hay impacto, calcula color con materiales/luces
5. `render(...)` escribe el color en el framebuffer.
6. `main.zig` llama a `swap_buffers()` para mostrar el resultado.

---

## 4. Puntos clave del diseño

### Uniones y polimorfismo

La estructura `Forma` es una unión. Esto permite que el código haga una llamada uniforme a `intersect(...)`, pero cada forma puede implementar su propia lógica interna. En este proyecto solo hay `Sphere`, pero la estructura está preparada para crecer.

### Separación de responsabilidades

- `Camera`: orientación y perspectiva.
- `Framebuffer`: representación del buffer de imagen.
- `Forma`/`Sphere`: geometría y colisiones.
- `Material`, `Light`: propiedades visuales.
- `main.zig`: orquestación del flujo completo.

### Lo que está aún incompleto o simplificado

Hay varias partes del programa que actualmente están sin terminar o con valores temporales:

- `obscured(...)` siempre devuelve `false`, por lo que las sombras no se calculan realmente.
- `cast_ray(...)` usa direcciones fijas para reflexión y refracción en ciertos puntos (`rl.Vector3{ .x = 0, .y = 1, .z = 0 }`), en lugar de calcularlas de forma geométrica correcta.
- `view_direction`, `light_dir`, `reflection_dir` se declaran pero no se usan de manera efectiva.

Esto significa que el raytracer funciona como una base estructural, pero aún no tiene un pipeline completo de iluminación física y sombras.

---

## 5. Resumen corto

Si lo resumimos en una sola frase:

`main.zig` prepara la escena, `Camera` define cómo se ve, `Forma`/`Sphere` resuelven intersecciones, `Material` y `Light` definen el color final, y `Framebuffer` dibuja cada frame en pantalla.
