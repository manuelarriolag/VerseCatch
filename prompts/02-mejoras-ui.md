# Mejoras a la UI

## Instrucciones obligatorias

- M0. Todas las instrucciones y tareas van referenciadas por un prefijo, el cual se convierte en el ID, como en este caso es M0, si alguna no tiene detente y reportalas para que las ajuste.
- M1. Marca las tareas y subtareas implementadas con [x] para que sean status done.
- M2. Agrega a este prompt cualquier decisión de alto impacto o riesgo como notas al final de este docoumento, anexando la fecha y hora en formato ISO (yyyy-MM-dd HH:mm).
- M3. Consultame cualquier duda o ambiguedad, no realices nada adicional de lo que venga aqui especificado.
- M4. Este prompt no está terminado, lo estaré ampliando con nuevas tareas (status pending) y tu ejecutarás solamente las tareas pendientes. Tambien es posible que agregue nuevas instrucciones.
- M5. Genera un archivo HANDOFF que pueda ser leido por otros agentes IA y alli ve colocando también lo mencionado en M2.
- M6. Considera que pueden existir subtareas, las cuales heredan el ID de la tarea antecesora, estan más indentadas y agregan nueva numeración basada en dígitos o letras. Por lo cual una tarea solamente se marca en done cuando todas sus subtareas ya estan en done.
- M7. En relación con M0, asegúrate que la numeración de los IDs (prefijos) se congruente, ya que no solo es un tema de secuencia, pues podría implicar una lógica de implementación incorrecta, además que define la prioridad y el orden que debe respetarse obligatoriamente. Si hay incongruencia, desorden o duplicados detente para que yo lo arregle.

## Mejoras en general

- [x] TG0. Inicia el archivo HANDOFF registrando los principales cambios aplicados en la nueva UI basada en wizard a nivel técnico.

- [x] TG1. Unifica los conceptos "referencia bíblica" y "cita bíblica" en todas los textos y mensajes, por "cita bíblica", incluso aquellas en plural o singular.

- [x] TG1.b. En escritorio, en el panel lateral, cambia los textos siguientes:
  - "Detectar ref." por "Detectar citas"
  - "Explorar ref." por "Explorar citas"

- [x] TG2. Implementa el manejo de versiones en la app y muestra la versión actual como parte del título de la app, por ejemplo: "Verse Catch v1.0", acorde con este lineamiento:
  - En escritorio, cambiar el texto del label "VerseCatch" en el panel lateral, y en el tìtulo de la ventana por el texto "Verse Catch v{app_version}".
  - En móvil, agrega un label con el texto "Verse Catch v{app_version}" por encima del panel superior (donde se muestra el paso activo), esto empujará todos los componentes hacia abajo, asegurate que no ocurra OVERFLOW en dispositivos pequeños como iPhone 17e.

- [x] TG3. Modifica los iconos del header que muestran el paso actual para que permita navegar directamente hacia el paso seleccionado.

- [x] TG3.fix. Agrega la siguiente regla de navegación al header, solo se pueden nevegar hacia pasos ya concluidos, es decir, aquellos que se usaron con el botón continuar, de esta forma evitamos que se omitan pasos.

- [x] TG4. Cambia el icono del botón "Nuevo escaneo" por uno que parezca "reset" o "ir al inicio", se me ocurre algo parecido a esto "|<-".

- [x] TG5. Estandariza los espaciados verticales entre títulos, subtítulos, botones y paneles para que en móvil y escritorio mantengan ritmo visual consistente sin saltos bruscos entre pasos.

- [x] TG6. Mejora la accesibilidad visual global de la UI aplicando contraste mínimo AA en textos, botones y chips; incluye estados hover/focus/disabled claramente distinguibles.

- [x] TG7. Agrega una preferencia "Reducir animaciones" para desactivar animaciones no críticas, y haz que esta preferencia persista entre sesiones.
  
## Paso 2. Obtener texto

- [x] T2.1. Si en el paso previo se eligió la opción "Elegir una imagen", se muestra la pantalla "Selecciona una imagen", aplica los siguientes cambios:
  - [x] T2.1.1. Si el usuario hace click/tap sobre el marco que tiene el texto "Sin imagen" que se ejecute la misma acción del botón "Elegir imagen".
  - [x] T2.1.2. Cuando ya se eligió una imagen, se reemplaza el marco que antes decia "Sin imagen" por la imagen selecionada, esto es correcto, ahora debemos mostrar la imágen completa con funciones para hacer zoom y mover la imagen que permitan visualizarla.
  - [x] T2.1.3. Como se describe en T2.1.2, hace falta un botón para continuar, ya que si el usuario llega a esta pantalla usando el botón "Atrás" ya no hay forma de continuar.

- [x] T2.2. Agrega un botón "Rotar" para girar la imagen seleccionada en incrementos de 90° (0°, 90°, 180°, 270°), y que el OCR use la orientación final elegida por el usuario.

- [x] T2.3. Agrega una opción "Recortar" (crop) previa al OCR con una interfaz simple de selección rectangular, útil para ignorar ruido fuera del texto principal.

- [x] T2.4. En la pantalla "Recortar imagen" aplica las siguientes mejoras:
  - [x] T2.4.1. Reemplaza los controles de recorte por acciones que puedan realizarze con el mouse o los dedos (gestos).
  - [x] T2.4.2. En dispositivos pequeños como iPhone 17e haz que la imagen previa ocupe todo el espacio disponible, pero sin ocultar los botónes, en cuyo caso, reacomoda los botones cambiando el tamaño y la posición, incluso considera convertir los botones en toolbar o botónes que solo tengan iconos, quiza el único botón que puede mantenerse con menos cambios es el boton "continuar" para no perder consistencia visual.

## Paso 3. Revisar texto

- [x] T3.1. Quiero que el texto reconocido por el OCR (o el que haya pegado o escrito el usuario), muestre resaltadas en color magenta las citas bìblicas encontradas, pero este paso 3 no sustituye al paso 4, solo es un previo que ayudará al usuario a identificar visualmente las citas y si detecta alguna no resaltada que pueda ajustarla.
- [x] T3.2. En la parte superior de la pantalla un botón preview (donde estan los headers y alineado la derecha), para que ejecute de nuevo la detección de las citas bìblicas, pero antes considera:
  - El resaltado solo ocurre al ingresar a esta pantalla o al ejecutar el botón preview.
  - No resaltar mientras se esta escribiendo.
- [x] T3.3. En la parte inferior hay un total de caracteres, agrega el total de refs resaltadas sin que esto desborde el espacio disponible en dispositivos pequeños como el iPhone 17e.
- [x] T3.4. Quita el texto del botón "Preview", deja solamente el icono.
- [x] T3.5. Coloca un split entre el panel de preview y el panel de texto, considerando que el split funcione bien para móvil y escritorio. DEPRECADO
- [x] T3.6. Modifica este paso (Revisar texto) para que funcione de la siguiente manera:
  - [x] T3.6.1. No deben mostrarse al mismo tiempo la vista previa y el cuadro de texto para editar, de esta forma deberán separarse claramente el modo vista previa del modo editar. Por defecto, al ingresar a este paso se debe mostrar el modo vista previa.
  - [x] T3.6.2. El botón actual "vista previa" debe intercambiarse por "editar", acorde con el modo que este activado y una vez presionado debe hacer el toogle del modo e intercambiar el título del botón. Por ejemplo el botón debe decir "Vista Previa" si el modo activo es editar, y debe decir "Editar" si el modo activo es vista previa.

- [x] T3.7. Agrega un mini panel de ayuda en modo edición (colapsable) con ejemplos de formatos válidos de citas bíblicas para reducir errores de escritura.

- [x] T3.8. En modo vista previa, agrega navegación rápida entre citas detectadas (anterior/siguiente) y haz que cada salto haga scroll automático al fragmento correspondiente.
- [x] T3.9. En relación con T3.8, cuando ocurra el scroll tambien haz que la cita activa en la navegación rápida se resalte en un color distinto a las otras citas bíblicas (consistente con el tema activo).

## Paso 5. Explorar citas
- [x] T5.1. Alinear a la derecha el botón copy.
- [x] T5.2. El cuado de texto donde se muestran las citas debe expandirse para ocupar todo el alto y ancho disponible (dock) sin margen y bordes.
- [x] T5.3. Hay una barra de navegación en la parte inferior, en dispositivos pequeños se muestra el texto en multiples líneas imposible de leer, dale un ancho mínimo suficiente para mostrar 2 dígitos por cada elemento, por ejemplo: "{nn} de {NN}".
- [x] T5.4. Cuando se navega usando el avanzar y retroceder haz que el chip activo de la parte inferior haga scroll horizontal para que se pueda visualizar, ya que cuando estan oculto el chip activo no se muestra.
- [x] T5.5. Al hacer click/tap sobre un chip inferior, desplaza automáticamente el carrusel y enfoca la cita seleccionada; además, resalta visualmente el chip activo con mayor contraste.
- [x] T5.6. Agrega una opción para alternar entre vista "Una cita por pantalla" y "Lista compacta", manteniendo el índice de cita activa al cambiar de modo.
- [x] T5.7. No funciona correctamente T5.4, el scroll si ocurre pero el chip no se muestra completamente, a veces parcialmente y a veces nada.
- [x] T5.8. En relación con T5.6, agrega en la lista compacta el indice de la cita como prefijo, por ejemplo: (4 de 11) {{CITA}}
- [x] T5.9. La vista por defecto debe ser lista compacta.
- [x] T5.10. No cambies el el icono de la vista activa, con el resaltado es suficiente.
- [x] T5.11. Mejora el borde de los chips inferiores ya que el redondeado se ve irregular.
- [x] T6. Aplica los siguientes cambios a la UI del paso 5 Explorar citas. Apoyate en el archivo "prompts/cambios al paso 5 - explorar citas.png" como una guí visual.
  - [x] T6.1. Mover el alternador de vista  hacia arriba y cambiar el texto.
  - [x] T6.2. Mover a la derecha el selector de version bíblica.
  - [x] T6.3. Coloca el botón copiar adentro del panel visualizar texto bíblico, y cambia el tooltip del botón por "Copiar texto".
  - [x] T6.4. Coloca un borde fuerte con efecto de sombreado al rededor del panel visualizar texto bíblico
  - [x] T6.4b. Cambia el sombreado actual por un sombreado interno.

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

- [x] T6.8. Agrega una vista previa del contenido final antes de exportar/copiar/compartir, con pestañas para "Texto escaneado", "Citas detectadas" y "Resultado final".

- [x] T6.9. Agrega validaciones previas al exportar (nombre vacío, caracteres inválidos, carpeta inaccesible) con mensajes claros y acción de corrección directa.

- [x] T6.10. Agrega un historial de las últimas 5 exportaciones (fecha/hora, formato y ruta destino) para facilitar reintentos rápidos.


## Notas de alto impacto / riesgo
- 2026-07-29 00:00: Se decidió mantener el resaltado únicamente en la vista previa del paso 3 y no durante la edición en vivo para evitar interferir con la escritura.
- 2026-07-29 00:00: Se decidió usar un estilo magenta suave con fondo claro para que las citas resaltadas sean visibles sin saturar la interfaz.
- 2026-08-08 20:13: Se decidió permitir navegación directa a cualquiera de los seis pasos desde los indicadores de móvil y escritorio, conservando el contenido y estado capturados; al entrar en Explorar citas se recarga el texto bíblico cuando existe una cita activa.
- 2026-08-08 20:22: Se restringió la navegación directa del header a los pasos ya concluidos mediante el flujo normal; esta regla sustituye la navegación irrestricta registrada a las 20:13 y evita omitir pasos futuros. "Nuevo escaneo" limpia también el registro de pasos concluidos.
- 2026-08-09 11:16: Se separó la selección de imagen del procesamiento OCR: elegir o cambiar una imagen conserva al usuario en el paso 2 para previsualizarla con zoom y desplazamiento, y el OCR solo inicia al presionar "Continuar".
- 2026-08-12 15:40: Se incorporó una preferencia persistente de "Reducir animaciones" que fuerza duraciones cero en transiciones no críticas de OCR/detección y feedback visual, priorizando accesibilidad en usuarios sensibles al movimiento.
- 2026-08-12 15:40: Se decidió ejecutar el OCR sobre la orientación y recorte definidos por el usuario en Paso 2 (rotación 90° y crop normalizado), para reducir ruido y mejorar precisión antes del reconocimiento.
- 2026-08-12 15:40: Se incorporó una vista previa obligatoria por pestañas para copiar/exportar (texto escaneado, citas detectadas y resultado final), con validaciones proactivas de exportación e historial de últimas 5 exportaciones con reintento rápido.
- 2026-08-12 16:09: En Paso 3 se distinguió visualmente la cita activa durante la navegación rápida usando colores del tema activo (primaryContainer/onPrimaryContainer), manteniendo un estilo secundario para las demás coincidencias.
- 2026-08-12 16:16: Se reemplazó el cálculo aproximado de scroll horizontal de chips en Paso 5 por un ajuste basado en medición real de render (keys + RenderBox), garantizando que el chip activo quede completamente visible dentro del viewport.
- 2026-08-12 16:26: En Paso 5 se estableció la vista compacta como predeterminada, agregando prefijo de índice por cita en formato "(n de N)"; además se desactivó el icono de selección del segmentado para no alterar el icono activo y se refinó el contorno de chips inferiores con forma y densidad consistente.
- 2026-08-12 17:09: En Paso 5 se reordenó la cabecera priorizando el alternador de vista en la parte superior (renombrado a "Tarjeta" y "Lista"), se movió el selector de versión bíblica al extremo derecho, se integró el botón de copiar dentro del panel de texto bíblico con tooltip "Copiar texto" y se aplicó un borde fuerte con sombreado al panel para enfatizar su jerarquía visual.
- 2026-08-12 17:12: En Paso 5 se sustituyó el sombreado externo del panel de texto bíblico por sombreado interno para mantener énfasis de contenedor sin proyectar halo externo, mejorando la limpieza visual del bloque en layouts compactos.
- 2026-08-19 14:31: Se rediseñó la pantalla "Recortar imagen" para reemplazar sliders por gestos directos (arrastre del área y ajuste por esquinas) y se adaptó el diálogo a pantallas pequeñas priorizando la vista previa en altura sin ocultar acciones, manteniendo "Continuar" como acción principal.

