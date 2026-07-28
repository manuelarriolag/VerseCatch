# VerseCatch

VerseCatch es una app móvil para detectar citas biblicas dentro de texto escrito, texto importado, imagenes de galeria y fotos tomadas con la camara del dispositivo. El sistema ejecuta OCR con ML Kit, resalta las referencias encontradas y guarda un historial local de escaneos.

## Caracteristicas del sistema

- **Entrada de texto manual**: permite pegar o escribir texto directamente.
- **Carga de archivos de texto**: admite archivos `.txt` y `.md`.
- **Carga de imagenes**: permite seleccionar una imagen desde el dispositivo para extraer texto con OCR.
- **Captura con camara**: abre una pantalla de captura para tomar una foto y procesarla.
- **Preprocesamiento de imagenes para OCR**:
  - recorte centrado de la imagen;
  - conversion a escala de grises;
  - redimensionamiento cuando la imagen es pequena para mejorar la lectura.
- **Reconocimiento de texto con Google ML Kit** sobre alfabeto latino.
- **Deteccion de referencias biblicas** dentro del texto reconocido o escrito.
- **Soporte para texto OCR ruidoso**: tolera separadores como `:`, `.`, `,` o espacios entre capitulo y versiculo.
- **Continuaciones de referencias**: detecta casos como `Rom 4:1-12, 10:1-13`.
- **Resaltado visual dentro del texto**: las referencias detectadas se colorean dentro del campo principal.
- **Seleccion de referencias detectadas**: cada referencia aparece como chip interactivo para activar su resaltado y mostrar un texto bíblico breve asociado.
- **Historial local de escaneos**: guarda texto reconocido, fecha y referencias detectadas cuando la feature flag `kEnableHistoryFeature` está habilitada.
- **Persistencia en SQLite**: el historial se almacena localmente en `versecatch.db` cuando la feature flag `kEnableHistoryFeature` está habilitada.
- **Mensajes de error visibles en UI** para fallos de lectura de archivos, OCR o captura.

## Stack tecnico

- **Flutter**
- **Dart** `^3.12.2`
- **camera**
- **google_mlkit_text_recognition**
- **sqflite**
- **file_picker**
- **image**
- **path / path_provider**

## Plataformas soportadas en este repositorio

El repositorio contiene configuracion para:

- **Android**
- **iOS**

## Requisitos para desarrollo local

Antes de ejecutar el proyecto, instala:

1. **Flutter SDK** en canal estable.
2. **Dart SDK** compatible con el proyecto (incluido con Flutter).
3. **Xcode** si vas a desarrollar para iOS.
4. **Android Studio** y/o **Android SDK** si vas a desarrollar para Android.
5. Un **emulador** o **dispositivo fisico**.

Recomendacion de verificacion inicial:

```bash
flutter doctor
```

## Configuracion de API YouVersion

El texto bíblico se consulta de forma remota usando la API de YouVersion.

Ejecuta la app con tu App Key:

```bash
flutter run \
  --dart-define=YOUVERSION_APP_KEY=<TU_APP_KEY> \
  --dart-define=YOUVERSION_BIBLE_VERSION_ID=128
```

En la UI puedes cambiar la versión desde el selector del panel "Biblical text".
La selección se persiste localmente en SQLite (`versecatch.db`) y se reutiliza al abrir la app.
Opciones soportadas:

- `128` — `NVI-S` — Nueva Versión Internacional 2025
- `103` — `NBLA` — Nueva Biblia de las Américas
- `127` — `NTV` — Nueva Traducción Viviente
- `149` — `RVR1960` — Reina Valera 1960
- `3291` — `VBL` — Biblia Libre

Opcionalmente puedes cambiar el host base:

```bash
--dart-define=YOUVERSION_API_BASE_URL=https://api.youversion.com
```

Tambien puedes cargar todas las variables desde archivo:

```bash
flutter run --dart-define-from-file=env.dev.json
```

Ejemplo de `env.dev.json` / `env.release.json`:

```json
{
  "YOUVERSION_APP_KEY": "TU_APP_KEY",
  "YOUVERSION_BIBLE_VERSION_ID": "128",
  "YOUVERSION_API_BASE_URL": "https://api.youversion.com"
}
```

## Crear un ambiente local para desarrollo

### 1. Clonar el repositorio

```bash
git clone <URL_DEL_REPOSITORIO>
cd VerseCatch
```

### 2. Obtener dependencias

```bash
flutter pub get
```

### 3. Verificar dispositivos disponibles

```bash
flutter devices
```

### 4. Ejecutar la aplicacion en local

```bash
flutter run
```

Si quieres elegir un dispositivo especifico:

```bash
flutter run -d <device_id>
```

## Compilacion release (sin VSCode/Xcode abiertos)

Compila con `--dart-define` o `--dart-define-from-file` porque estas variables se leen en build time.

### macOS

```bash
flutter build macos --release --dart-define-from-file=env.release.json
```

Artefacto generado:

- `build/macos/Build/Products/Release/VerseCatch.app`

Ejecutar app compilada:

```bash
open build/macos/Build/Products/Release/VerseCatch.app
```

Copiar app en /Applications:

```bash
cp -R build/macos/Build/Products/Release/versecatch.app /Applications/
open /Applications/versecatch.app
```

### Android (APK)

```bash
flutter build apk --release --dart-define-from-file=env.release.json
```

Artefacto generado:

- `build/app/outputs/flutter-apk/app-release.apk`

Instalar en dispositivo conectado:

```bash
flutter install
```

O instalar manualmente:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### Android (AAB para Play Store)

```bash
flutter build appbundle --release --dart-define-from-file=env.release.json
```

Artefacto generado:

- `build/app/outputs/bundle/release/app-release.aab`

### iOS (IPA)

```bash
flutter build ipa --release --dart-define-from-file=env.release.json
```

Artefacto generado:

- `build/ios/ipa/*.ipa`

Instalacion/distribucion:

- subir a TestFlight/App Store Connect con Transporter o Xcode Organizer;
- para instalar directo en dispositivo iOS se requiere firma/provisioning validos.

## Configuracion adicional por plataforma

### Android

El proyecto ya declara el permiso de camara en:

- `android/app/src/main/AndroidManifest.xml`

Para desarrollo local:

1. abre un emulador Android o conecta un dispositivo;
2. acepta los permisos de camara cuando la app los solicite.

### iOS

El proyecto ya declara descripciones de permisos en:

- `ios/Runner/Info.plist`

Incluye permisos para:

- camara;
- acceso a fototeca.

Para desarrollo local en iOS:

1. abre un simulador o conecta un iPhone;
2. si compilas por primera vez en macOS, ejecuta:

```bash
cd ios
pod install
cd ..
```

> Nota: la camara real puede requerir un dispositivo fisico para probar el flujo completo de captura.


## Resumen rápido de artefactos
### macOS app:
build/macos/Build/Products/Release/VerseCatch.app
Ejecutar: open build/macos/Build/Products/Release/VerseCatch.app

### Android APK:
build/app/outputs/flutter-apk/app-release.apk
Instalar: adb install -r build/app/outputs/flutter-apk/app-release.apk

### Android AAB (Play Store):
build/app/outputs/bundle/release/app-release.aab

### iOS IPA:
build/ios/ipa/*.ipa
Subida típica: TestFlight/App Store Connect (Transporter/Xcode Organizer)

## Flujo funcional de la app

1. El usuario selecciona la fuente de entrada:
   - texto;
   - imagen;
   - camara.
2. Si la entrada es imagen o foto, VerseCatch prepara la imagen antes del OCR.
3. ML Kit extrae el texto.
4. El sistema analiza el texto y detecta referencias biblicas.
5. Las referencias encontradas se:
   - muestran como chips interactivos;
   - resaltan dentro del texto fuente.
6. El usuario puede guardar el resultado en el historial local.

## Estructura principal

- `lib/main.dart`: UI principal, OCR, camara, deteccion de referencias e historial.
- `test/widget_test.dart`: pruebas de interfaz y de extraccion de referencias.
- `pubspec.yaml`: dependencias y configuracion del proyecto.

## Ejecutar pruebas locales

### Pruebas automatizadas

Ejecuta todas las pruebas unitarias y de widgets:

```bash
flutter test
```

### Analisis estatico

Ejecuta el analizador de Dart/Flutter:

```bash
flutter analyze
```

## Cobertura actual de pruebas

Actualmente las pruebas verifican:

- que la pantalla principal de VerseCatch renderiza correctamente;
- que el selector de fuente y el campo de texto existen;
- que las referencias se actualizan al escribir texto;
- que la funcion de extraccion detecta referencias biblicas validas;
- que la extraccion tolera separadores ruidosos provenientes de OCR.

## Notas de uso

- El historial se guarda localmente en la base de datos SQLite del dispositivo.
- La funcion de OCR depende de la calidad de la imagen capturada o seleccionada.
- El flujo de camara requiere permisos del sistema operativo.
