# Mejoras a la animación del OCR

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

- [x] TG1. Ajusta el marco que se pinta sobre la vista previa, necesitamos que se muestre dentro de la imagen de la vista previa, es decir, asegurate de que la animación se muestre encima y dentro de la imagen, no sobre el cuadro de la vista previa.
- [x] TG2. Modifica la fuente de las leyendas de status que se muestran debajo del botón "Continuar" para que parezcan muteadas. 
- [x] TG3. Extiende la animación para que incluya el proceso que ejecuta la detección de las citas bíblicas, es decir, el OCR actualmente es la parte que extrae el texto de imagenes o fotografías, sin embargo ha una dificultad y necesito que me hagas algunas sugerencias. La dificultad es la siguiente:
  - El OCR solo se lanza si el usuario elije "seleccionar una imagen" o "tomar fotografía", pero todas las fuentes deben concluir en el "Paso 4 - Detectar citas", por lo cual necesito opciones para que siga siendo consistencia la experiencia de usuario, a mi se me ocurre agregar una pantalla temporal que muestre una imagen dummy para que se ejecute la animación de la detección de citas (sin OCR), pero deseo saber tus sugerencias.
- [x] TG4. Cambia el color principal (MAIN_COLOR) de la animación por algo naranja ya que en fondos blancos no se alcanza a notar el actual.
- [x] TG5. Modifica el ancho de las cajas de la animación, para que ocupen el 85% del marco generado por el OCR,
- [x] TG6. Además de las cajas de la animación, agrega  tres opciones de animación que se muestren en forma aleatoria, nunca todas al mismo tiempo, posiblemente partículas grandes y pequeñas pulsantes (como respirando), rayos que atraviezan y las que consideres adecuadas.
- [x] TG7. Durante la animación si estoy utilizando una imagen recortada, o que tiene un alto muy pequeño se desborda el overlay que muestra el progreso del OCR. Se corrigió haciendo el HUD responsivo por tamaño disponible (modo compacto/ultracompacto y ocultación en altura extrema) para evitar overflow.


## Notas de alto impacto / riesgo

- 2026-08-11 18:32: Para garantizar que el marco OCR quede dentro de la imagen real (y no del contenedor), se cambió el render de la vista previa para calcular el área efectiva de la imagen con relación de aspecto y dibujar el overlay dentro de esa superficie; como mitigación de parpadeo inicial se añadió un fallback temporal mientras se resuelve el tamaño fuente.
- 2026-08-11 18:44: Se unificó la tipografía de las leyendas de estado debajo del botón "Continuar" con un estilo visual más tenue (color y peso reducidos) para que se perciban como mensajes de apoyo y no como foco primario de la pantalla.
- 2026-08-11 18:47: Se adoptó la opción 1 para TG3: reutilizar la animación de escaneo en el Paso 3 (Revisar texto) durante la detección de citas bíblicas para todas las fuentes, evitando pantallas dummy y manteniendo consistencia visual hasta la transición al Paso 4.
- 2026-08-12 15:12: Se cambió el MAIN_COLOR por un naranja de mayor contraste para mejorar legibilidad del marco, línea de escaneo y HUD sobre fondos claros sin alterar la estructura de la animación.
- 2026-08-13 14:47: Las cajas de detección del overlay OCR se normalizaron para ocupar 85% del ancho del marco interno, conservando variación vertical y visibilidad progresiva para mejorar consistencia visual entre imágenes con diferentes proporciones.
- 2026-08-13 14:47: Se incorporaron tres efectos ambientales exclusivos y aleatorios por sesión de escaneo (partículas pulsantes, rayos de cruce y nodos orbitales), evitando sobrecarga visual por superposición y manteniendo una sola variante activa a la vez.
- 2026-08-19 16:15: Se hizo responsivo el HUD del overlay OCR para imágenes de baja altura (especialmente recortadas), con densidades adaptativas y ocultación bajo umbral mínimo de espacio para eliminar desbordes verticales sin mover el marco de escaneo.
