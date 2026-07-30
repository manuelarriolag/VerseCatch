# Mejoras a la UI

## Instrucciones obligatorias

- M0. Todas las instrucciones y tareas van referenciadas por un prefijo, el cual se convierte en el ID, como en este caso es M0, si alguna no tiene detente y reportalas para que las ajuste.
- M1. Marca las tareas y subtareas implementadas con [x] para que sean status done.
- M2. Agrega a este prompt cualquier decisión de alto impacto o riesgo como notas al final de este docoumento, anexando la fecha y hora en formato ISO (yyyy-MM-dd HH:mm).
- M3. Consultame cualquier duda o ambiguedad, no realices nada adicional de lo que venga aqui especificado.
- M4. Este prompt no está terminado, lo estaré ampliando con nuevas tareas (status pending) y tu ejecutarás solamente las tareas pendientes. Tambien es posible que agregue nuevas instrucciones.
- M5. Genera un archivo HANDOFF que pueda ser leido por otros agentes IA y alli ve colocando también lo mencionado en M2.
- M6. Considera que pueden existir subtareas, las cuales heredan el ID de la tarea antecesora, estan más indentadas y agregan nueva numeración basada en dígitos o letras. Por lo cual una tarea solamente se marca en done cuando todas sus subtareas ya estan en done.
- M0. En relación con M0, asegúrate que la numeración de los IDs (prefijos) se congruente, ya que no solo es un tema de secuencia, pues podría implicar una lógica de implementación incorrecta, además que define la prioridad y el orden que debe respetarse obligatoriamente. Si hay incongruencia, desorden o duplicados detente para que yo lo arregle.

## Mejoras en general

- [x] TG0. Inicia el archivo HANDOFF registrando los principales cambios aplicados en la nueva UI basada en wizard a nivel técnico.

- [x] TG1. Unifica los conceptos "referencia bíblica" y "cita bíblica" en todas los textos y mensajes, por "cita bíblica", incluso aquellas en plural o singular.

- [x] TG1.b. En escritorio, en el panel lateral, cambia los textos siguientes:
  - "Detectar ref." por "Detectar citas"
  - "Explorar ref." por "Explorar citas"

- [x] TG2. Implementa el manejo de versiones en la app y muestra la versión actual como parte del título de la app, por ejemplo: "Verse Catch v1.0", acorde con este lineamiento:
  - En escritorio, cambiar el texto del label "VerseCatch" en el panel lateral, y en el tìtulo de la ventana por el texto "Verse Catch v{app_version}".
  - En móvil, agrega un label con el texto "Verse Catch v{app_version}" por encima del panel superior (donde se muestra el paso activo), esto empujará todos los componentes hacia abajo, asegurate que no ocurra OVERFLOW en dispositivos pequeños como iPhone 17e.

## Paso 3. Revisar texto

- [x] T3.1. Quiero que el texto reconocido por el OCR (o el que haya pegado o escrito el usuario), muestre resaltadas en color magenta las citas bìblicas encontradas, pero este paso 3 no sustituye al paso 4, solo es un previo que ayudará al usuario a identificar visualmente las citas y si detecta alguna no resaltada que pueda ajustarla.
- [x] T3.2. En la parte superior de la pantalla un botón preview (donde estan los headers y alineado la derecha), para que ejecute de nuevo la detección de las citas bìblicas, pero antes considera:
  - El resaltado solo ocurre al ingresar a esta pantalla o al ejecutar el botón preview.
  - No resaltar mientras se esta escribiendo.
- [x] T3.3. En la parte inferior hay un total de caracteres, agrega el total de refs resaltadas sin que esto desborde el espacio disponible en dispositivos pequeños como el iPhone 17e.
- [x] T3.4. Quita el texto del botón "Preview", deja solamente el icono.
- [x] T3.5. Coloca un split entre el panel de preview y el panel de texto, considerando que el split funcione bien para móvil y escritorio.

## Paso 5. Explorar citas
- [x] T5.1. Alinear a la derecha el botón copy.
- [x] T5.2. El cuado de texto donde se muestran las citas debe expandirse para ocupar todo el alto y ancho disponible (dock) sin margen y bordes.
- [x] T5.3. Hay una barra de navegación en la parte inferior, en dispositivos pequeños se muestra el texto en multiples líneas imposible de leer, dale un ancho mínimo suficiente para mostrar 2 dígitos por cada elemento, por ejemplo: "{nn} de {NN}".

## Paso 6. Guardar
- [x] T6.1. Agrega un checkbox que permita incluir el texto bíblico de todas las citas encontradas, el valor de este checkbox debe persistirse entre sesiones.
- [x] T6.2. Renombra la opción "Compartir resultado" por "Copiar resultado escaneado".
- [x] T6.3. Si esta activo incluir el texto bíblico aplica los siguientes cambios:
    - [x] T6.3.1. Modifica todas las opciones de guardado/copiado/compartir/exportar para que incluyan el texto bíblico siguiendo las reglas utilizadas en el botón copy (del paso 5).
    - [x] T6.3.2. Dale animación al proceso de exportar, ya que la obtenciòn del texto bíblico puede tardar mucho.
    - [x] T6.3.3. Si falla la obtención del texto bíblico, asegurate de mostrar un mensaje humanizado al principio, seguido del detalle técnico del fallo pero con letras muteadas y más pequeñas.
    - [x] T6.3.4. El API del datastore remoto tiene rate limit (los cuales varian cuando la app es productiva, es decir, más largos o más bajos según la demanda o bien por su status, que pueden ser: development o live), por tanto, necesitamos que la obtención de los textos bíblicos nunca supere el rate limit, para ello inventate un algoritmo que invoque los requests de manera aleatoria y que no se desborde.
    - [x] T6.3.5. Dale animación al proceso de copiar citas y copiar resultados, ya que la obtención del texto bíblico puede tardar mucho.
    - [x] T6.3.6. Modifica todas las opciones de copiado/compartir/exportar para que marquen la acción como terminada, como lo hace actualmente guardar en historial.
- [x] T6.4. Modifica el exportar texto mostrando un diálogo que le permita al usuario seleccionar la carpeta destino y el nombre del archivo, acorde con estos criterios:
    - [x] T6.4.1. Por defecto será la carpeta "Downloads" o "Descargas" del dispositivo o la previamente almacenada. NO FUNCIONA BIEN!!
    - [x] T6.4.2. El nombre de la carpeta destino (sin el nombre del archivo), se debe persistir entre sesiones y se convierte en la carpeta por defecto para nuevos intentos de exportar. FALTA PROBAR
- [x] T6.5 Modifica el proceso de 'copiar citas' para que solamente incluya las Citas bíblicas encontradas y el texto bìblico si la opción incluir texto esta seleccionada, actualiza el texto descriptivo de esta acción.
- [x] T6.6 Modifica el proceso de 'copiar resultado escaneado' para que solamente incluya el texto escaneado y el texto bìblico si la opción incluir texto esta seleccionada, actualiza el texto descriptivo de esta acción. NOTA: Este proceso no esta funcionando actualmente, no copia nada al portapapeles.
- [x] T6.7. Acorde con T6.3.5 y T6.3.6, agrega mas detalles que permita ver si esta avanzando o no el proceso de obtención del texto bíblico, por ejemplo: "(1 de 8)" o lo que mejor convenga. Añade un icono cancelar, para que el usuario pueda interrumpir. Por último, despliega el tiempo que se llevó (en minutos o segundos) el proceso completo por debajo del icono done.


## Notas de alto impacto / riesgo
- 2026-07-29 00:00: Se decidió mantener el resaltado únicamente en la vista previa del paso 3 y no durante la edición en vivo para evitar interferir con la escritura.
- 2026-07-29 00:00: Se decidió usar un estilo magenta suave con fondo claro para que las citas resaltadas sean visibles sin saturar la interfaz.

