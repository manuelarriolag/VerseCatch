# Organizacion del refactor de main.dart

## Objetivo

Documentar como quedo organizada la aplicacion despues de separar `lib/main.dart` en modulos por responsabilidad.

## Resumen

Antes: un solo archivo con UI, estado, parsing, servicios API, persistencia y utilidades.

Ahora: una libreria principal (`lib/main.dart`) que orquesta imports y `part`, y cinco archivos en `lib/src`.

## Estructura resultante

```text
lib/
  main.dart
  src/
    core.dart
    legacy_home_page.dart
    data_store.dart
    bible_and_text.dart
    wizard.dart
  widgets/
    ocr_scan_overlay.dart
```

## Responsabilidad por archivo

### 1) lib/main.dart

- Punto de entrada de la libreria.
- Contiene `main()` (bootstrap de Flutter y arranque de la app).
- Mantiene los imports compartidos.
- Declara los `part` que componen la libreria completa.
- Solo contiene logica de arranque/orquestacion.

### 2) lib/src/core.dart

- Tipos base (`InputSource`, typedefs de lookup/picker/OCR).
- Constantes globales y configuracion por `dart-define`.
- Validaciones de integridad de alias biblicos.
- Builders de texto de salida (contenido exportable/clipboard).
- Configuracion general de `VerseCatchApp`.

### 3) lib/src/legacy_home_page.dart

- Pantalla legacy (`VerseCatchHomePage`) y su estado.
- Flujos de entrada por texto, archivo, imagen y camara.
- UI auxiliar legacy (preview, historia, tarjetas, paneles).
- Componentes visuales acoplados a esa experiencia.

### 4) lib/src/data_store.dart

- Modelos de datos persistidos:
  - `CaptureRecord`
  - `ExportHistoryItem`
  - `BibleVersionOption`
- Capa de persistencia SQLite:
  - `VerseCaptureStore`
  - SQL de creacion y claves de settings
- Reglas de lectura/escritura de preferencias y historial.

### 5) lib/src/bible_and_text.dart

- Extraccion y deteccion de citas biblicas:
  - `extractVerseReferences`
  - `extractVerseMatches`
- Normalizacion de libros/capitulos/versiculos.
- Integracion con API de YouVersion:
  - `lookupBibleTextFromYouVersion`
  - parseo de payload y manejo de errores
- Utilidades de formateo y limpieza de texto.

### 6) lib/src/wizard.dart

- Flujo principal actual por pasos (Wizard UI).
- Estado, transiciones y acciones de cada paso.
- Componentes internos de cada etapa:
  - seleccion de fuente
  - adquisicion de contenido
  - revision de texto
  - deteccion de referencias
  - exploracion de referencias
  - finalizacion/export
- Integracion con OCR overlay y preferencias de salida.

## Criterio de separacion aplicado

Se aplico separacion por responsabilidad (SRP), agrupando por dominio funcional:

- Entry point y arranque -> `main.dart`
- Constantes globales y configuracion base -> `core.dart`
- Persistencia -> `data_store.dart`
- Dominio biblico y parsing -> `bible_and_text.dart`
- UI legacy -> `legacy_home_page.dart`
- UI wizard -> `wizard.dart`

## Beneficios obtenidos

- Menor complejidad cognitiva por archivo.
- Navegacion mas rapida en el codigo.
- Refactors futuros mas seguros por modulo.
- Menor riesgo de conflictos de merge en `main.dart`.
- Facilita pruebas y aislamiento de cambios.

## Reglas para evolucion futura

1. Evitar volver a concentrar logica en `lib/main.dart`.
2. Si un bloque nuevo es de dominio biblico/parsing, ubicarlo en `bible_and_text.dart`.
3. Si es persistencia/configuracion local, ubicarlo en `data_store.dart`.
4. Si es UI del flujo por pasos, ubicarlo en `wizard.dart`.
5. Si crece demasiado un modulo, dividirlo en nuevos `part` tematicos.

## Nota tecnica

La separacion actual usa `part/part of` para minimizar riesgo y mantener compatibilidad inmediata.
Un siguiente paso opcional es migrar gradualmente a imports explicitos entre librerias para lograr encapsulamiento mas estricto y limites de modulo aun mas claros.
