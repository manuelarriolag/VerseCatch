# Prompt de implementación — Animación OCR futurista

## Objetivo

Implementar en la app Flutter **Verse Catch** una animación visual que simule un proceso avanzado de escaneo OCR sobre la fotografía capturada.

El OCR real **ya funciona correctamente** y no debe modificarse salvo que sea necesario para coordinar visualmente su estado.

La animación es exclusivamente visual: debe mostrarse como una capa transparente sobre la fotografía y hacer que el usuario perciba que la imagen está siendo analizada y que el texto está siendo reconocido.

## Instrucciones muy importantes
- Las acciones aqui mencionadas se deben ejecutar sobre el "Paso 2. Obtener texto", como efecto de presionar el boton Continuar.
- El "Paso 3. Revisar texto" es donde convergen todas las fuentes de información (escribir texto, importar archivo, seleccionar imagen y tomar fotografía), por lo cual no debe romperse el flujo a partir de otras fuentes. En este caso, la animación debe ocurrir como resultado de "seleccionar una imagen" o "tomar fotografía", ya que en ambos casos se ejecuta el OCR para obtener el texto de ambas fuentes.
- Al final debes ampliar/agregar las pruebas unitarias necesarias para validar los criterios de aceptación aqui detallados. Marca completadas los criterios que ya tengan sus pruebas pasadas en verde.

---

## 1. Resultado esperado

Al presionar **Continuar**:

1. Mantener visible la fotografía.
2. Iniciar inmediatamente la animación OCR.
3. Ejecutar el OCR real en paralelo.
4. La animación debe durar **como mínimo aproximadamente 6 segundos**, aunque el OCR real termine antes.
5. Si el OCR tarda más de 6 segundos, la animación debe continuar/repetirse hasta que el OCR termine.
6. Cuando ambos procesos hayan terminado:
   - mostrar brevemente un estado de finalización;
   - hacer un fade-out de aproximadamente 300-500 ms;
   - continuar al siguiente paso de la aplicación.

No reemplazar la fotografía por un spinner o pantalla de loading.

---

## 2. Concepto visual

El estilo debe ser:

> **Futuristic OCR Scanner / Document Intelligence**

Debe sentirse tecnológico, elegante y profesional, pero sobrio.

La fotografía debe seguir siendo el elemento visual dominante.

Evitar:

- interfaces tipo videojuego;
- demasiados paneles;
- exceso de texto;
- animaciones exageradas;
- colores muy saturados;
- grandes overlays opacos;
- elementos que oculten la fotografía.

La sensación buscada es similar a un sistema profesional de visión artificial/document intelligence.

---

## 3. Elementos visuales

### 3.1 Marco de escaneo

Mostrar cuatro esquinas luminosas alrededor del área de la fotografía.

Características:

- líneas finas;
- bordes redondeados;
- color azul/cian;
- glow muy sutil;
- transparencia;
- no utilizar un rectángulo completamente cerrado.

Debe parecer que el sistema ha identificado el área que va a procesar.

### 3.2 Línea de escaneo

Elemento principal de la animación.

Una línea horizontal luminosa debe recorrer la fotografía de arriba hacia abajo.

Debe:

- desplazarse suavemente;
- tener un pequeño glow;
- tener un halo vertical/translúcido;
- no ocultar el contenido;
- regresar posteriormente a la parte superior.

No usar una barra de progreso convencional como elemento principal.

La línea debe dar la sensación de que realmente está "leyendo" la fotografía.

### 3.3 Detección de regiones de texto

Mientras la línea atraviesa la fotografía, deben aparecer pequeñas cajas alrededor de diferentes líneas de texto.

Características:

- bordes muy finos;
- transparencia;
- color {{MAIN_COLOR}};
- pequeña luminosidad;
- aparición progresiva;
- desaparición después de que el scanner pasa;
- no deben aparecer todas simultáneamente.


Nota: MAIN_COLOR equivale a "cian/azul", pero debe ser una configuración o variable que pueda modificarse con facilidad.

La posición debe ser relativa al área visual de la imagen, no absoluta respecto a toda la pantalla.

### 3.4 Partículas / procesamiento

Agregar pequeñas partículas luminosas alrededor de la línea de escaneo.

Deben:

- ser muy pequeñas;
- moverse ligeramente;
- tener baja opacidad;
- utilizar el mismo color del scanner;
- dar sensación de procesamiento.

No utilizar demasiadas. Aproximadamente 10-15 partículas simultáneas son suficientes.

---

## 4. HUD de OCR

Agregar un pequeño panel translúcido.

Conceptualmente:

┌─────────────────────────────┐
│ ● Verse Catch               │
│   Analizando texto...       │
│ ███████████░░░░░░░░         │
└─────────────────────────────┘

Características:

- fondo negro/transparente;
- blur/translucencia si es posible;
- borde fino;
- esquinas redondeadas;
- color principal cian;
- tamaño pequeño;
- no debe cubrir información importante de la fotografía.

Estados sugeridos:

- `Preparando imagen...`
- `Analizando texto...`
- `Reconociendo citas bíblicas...`
- `Extrayendo texto...`
- `Texto identificado ✓`

---

## 5. Progreso

El HUD puede mostrar una barra pequeña de progreso.

Importante:

El porcentaje mostrado es **puramente visual**. No debe representar necesariamente el progreso real del OCR.

Puede recorrer visualmente:

```text
18%
32%
47%
68%
84%
100%
```

aunque el OCR real esté ejecutándose de manera independiente.

---

## 6. Timeline recomendado

Un ciclo completo debe durar aproximadamente **6 segundos**.

### 0.0 - 0.5 s

Entrada del scanner:

- aparecen las esquinas;
- aparece el HUD;
- aumenta suavemente la opacidad.

Estado:

`Preparando imagen...`

### 0.5 - 2.0 s

La línea de escaneo comienza a desplazarse.

Primera detección de regiones.

Estado:

`Analizando texto...`

### 2.0 - 4.0 s

La línea continúa recorriendo la fotografía.

Aparecen diferentes cajas sobre líneas de texto.

Partículas visibles.

Estado:

`Reconociendo citas bíblicas...`

### 4.0 - 5.2 s

Segunda pasada / procesamiento intensivo.

Aumentar ligeramente la actividad de cajas y partículas.

Estado:

`Extrayendo citas bíblicas...`

### 5.2 - 5.8 s

Completar visualmente el procesamiento.

HUD:

`Citas bíblicas identificadas ✓`

Progreso:

`100%`

### 5.8 - 6.2 s

Pequeña pausa de confirmación.

Después realizar fade-out de aproximadamente:

`300-500 ms`

---

## 7. Coordinación con OCR real

Implementar dos estados independientes:

```dart
bool isScanning = false;
bool ocrFinished = false;
```

La animación visual debe tener un tiempo mínimo:

```dart
const minimumScanDuration = Duration(seconds: 6);
```

Conceptualmente:

```dart
final animationStart = DateTime.now();

setState(() {
  isScanning = true;
  ocrFinished = false;
});

final ocrFuture = executeOcr();

final ocrResult = await ocrFuture;

final elapsed = DateTime.now().difference(animationStart);

final remaining = minimumScanDuration - elapsed;

if (remaining > Duration.zero) {
  await Future.delayed(remaining);
}

setState(() {
  ocrFinished = true;
});

// Mostrar "Texto identificado ✓"
// Esperar aproximadamente 300-500 ms

await Future.delayed(
  const Duration(milliseconds: 400),
);

setState(() {
  isScanning = false;
});

// Continuar al siguiente paso
```

Ejemplos:

Si OCR tarda 2 segundos:

```text
OCR = 2 s
Animación = 6 s
```

Si OCR tarda 8 segundos:

```text
OCR = 8 s
Animación = 8 s
```

Nunca detener la animación antes de los 6 segundos.

---

## 8. Arquitectura Flutter

No utilizar GIF ni video.

Implementar con:

- `AnimationController`
- `CustomPainter`
- `AnimatedBuilder`
- `Stack`
- `IgnorePointer`

Arquitectura:

```text
Stack
│
├── Image.file(...)
│
└── OcrScanOverlay
     │
     ├── Scanner frame
     ├── Scan beam
     ├── Text detection boxes
     ├── Particles
     └── OCR HUD
```

El widget debe ser independiente de la lógica OCR.

---

## 9. Widget esperado

Crear:

```text
ocr_scan_overlay.dart
```

Con una API similar a:

```dart
OcrScanOverlay(
  active: true,
  duration: const Duration(seconds: 6),
)
```

Parámetros sugeridos:

```dart
final bool active;
final Duration duration;
final Color tint;
final bool showHud;
```

Color predeterminado {{MAIN_COLOR}}:

```dart
const Color(0xFF72D9FF)
```

Debe poder cambiarse fácilmente.

---

## 10. Integración con la fotografía

La vista previa debe utilizar un `Stack`.

Ejemplo:

```dart
Stack(
  fit: StackFit.expand,
  children: [
    Image.file(
      imageFile,
      fit: BoxFit.contain,
    ),

    if (isScanning)
      const OcrScanOverlay(
        active: true,
      ),
  ],
)
```

El overlay debe:

- ocupar exactamente el área de la fotografía;
- no modificar el `Image`;
- no interceptar eventos;
- utilizar `IgnorePointer`;
- funcionar con diferentes tamaños de pantalla;
- funcionar con diferentes relaciones de aspecto.

---

## 11. Responsive design

No utilizar posiciones absolutas basadas en el tamaño de un iPhone específico.

Las posiciones deben calcularse proporcionalmente, por ejemplo:

```dart
size.width * 0.16
size.height * 0.28
```

El widget debe funcionar correctamente en:

- iPhone;
- Android;
- pantallas pequeñas;
- pantallas grandes;
- diferentes orientaciones si la aplicación las soporta.

---

## 12. Rendimiento

La animación debe ser fluida.

Objetivo:

```text
60 FPS
```

Evitar:

- crear widgets innecesariamente durante cada frame;
- múltiples `AnimationController`;
- imágenes adicionales;
- assets de video;
- operaciones costosas dentro de `paint()`;
- llamadas de red;
- procesamiento OCR dentro del painter.

Todo el efecto debe ser generado localmente por Flutter.

---

## 13. Diseño visual

El diseño actual de Verse Catch utiliza principalmente un azul/púrpura similar a:

```text
#5864A0
```

El scanner puede utilizar un azul/cian más luminoso:

```text
#72D9FF
```

pero con baja opacidad.

La animación debe sentirse como una extensión del diseño actual y no como un componente visual completamente diferente.

---

## 14. Transparencia

La fotografía debe permanecer claramente visible.

Regla aproximada:

```text
Fotografía       100%
Scanner overlay   10-40%
```

No utilizar un fondo sólido.

Los elementos luminosos deben utilizar transparencia, por ejemplo:

```dart
color.withOpacity(...)
```

o la API equivalente recomendada por la versión de Flutter utilizada.

---

## 15. Accesibilidad

La animación es decorativa.

No debe transmitir información crítica únicamente mediante color.

El estado real del OCR debe mantenerse disponible para lectores de pantalla si corresponde.

Si existe un texto accesible, utilizar `Semantics` de ser necesario:

```text
"Procesando imagen mediante OCR"
```

---

## 16. Manejo de estados

Definir claramente:

```text
IDLE
 ↓
SCANNING
 ↓
OCR_COMPLETE
 ↓
EXITING
 ↓
NEXT_STEP
```

Se puede utilizar:

```dart
enum OcrVisualState {
  idle,
  scanning,
  completed,
  exiting,
}
```

El resultado real del OCR debe permanecer en una variable independiente.

---

## 17. Manejo de errores

Si el OCR falla:

1. detener la animación después del mínimo de 6 segundos;
2. no mostrar `Texto identificado ✓`;
3. mostrar un estado de error apropiado;
4. permitir al usuario reintentar.

Ejemplo:

```text
⚠ No fue posible reconocer el texto

Intentar nuevamente
```

La implementación visual no debe ocultar ni reemplazar el manejo de errores existente.

---

## 18. Entregables

Implementar:

```text
lib/
└── widgets/
    └── ocr_scan_overlay.dart
```

Y modificar la pantalla actual para:

1. mostrar el overlay;
2. iniciar la animación al pulsar `Continuar`;
3. ejecutar el OCR real;
4. garantizar mínimo 6 segundos de animación;
5. mostrar estado de finalización;
6. hacer fade-out;
7. continuar al paso `Revisar texto`.

---

## 19. Restricciones importantes

### NO

- usar GIF;
- usar video;
- agregar paquetes innecesarios;
- modificar el algoritmo OCR existente;
- bloquear el hilo principal;
- cubrir completamente la fotografía;
- agregar una pantalla independiente de loading;
- utilizar una animación genérica de `CircularProgressIndicator`.

### SÍ

- usar `CustomPainter`;
- usar `AnimationController`;
- mantener la fotografía visible;
- utilizar transparencia;
- crear una animación visual de 6 segundos;
- repetir mientras el OCR real siga procesando;
- cerrar elegantemente la animación;
- mantener el código modular.

---

## 20. Resultado UX esperado

El usuario debe percibir:

> "La aplicación está leyendo visualmente el documento."

No debe percibir:

> "La aplicación está esperando que termine un proceso."

La animación debe convertir una espera técnica de OCR en una experiencia visual intencional.

---

## 21. Referencia visual

Usar como referencia conceptual:

```text
┌─────────────────────────────────────┐
│  ┌─                              ─┐ │
│                                     │
│      fotografía del documento       │
│                                     │
│  ────────────────────────────────   │
│          ↑ scan beam                │
│                                     │
│    ┌──────────────────────────┐     │
│    │ línea de texto detectada │     │
│    └──────────────────────────┘     │
│                                     │
│           ┌─────────────────┐       │
│           │ ● OCR           │       │
│           │ Analizando...   │       │
│           │ ███████░░░      │       │
│           └─────────────────┘       │
│                                     │
│  └─                              ─┘ │
└─────────────────────────────────────┘
```

La implementación final debe ser visualmente elegante, discreta y consistente con Verse Catch.

---

## 22. Criterios de aceptación

- [x] El usuario pulsa `Continuar`.
- [x] La animación aparece inmediatamente sobre la fotografía.
- [x] La fotografía continúa visible.
- [ ] Se observa claramente la línea de escaneo.
- [ ] Aparecen regiones de texto detectadas.
- [x] Existe un HUD discreto de OCR.
- [x] La animación dura mínimo 6 segundos.
- [x] Si el OCR tarda más, la animación continúa.
- [x] Si el OCR termina antes, la animación no termina prematuramente.
- [ ] Al finalizar aparece `Texto identificado ✓`.
- [ ] Se realiza un fade-out suave.
- [ ] Se continúa al paso siguiente.
- [x] No se agregan dependencias innecesarias.
- [ ] La animación mantiene un rendimiento fluido.
- [ ] La solución funciona con diferentes tamaños de fotografía/pantalla.
