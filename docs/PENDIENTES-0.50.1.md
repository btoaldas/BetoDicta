# Hallazgos conocidos aplazados a 0.50.1

De la revisión de código y seguridad del release 0.50.0 (37 confirmados). Los
3 críticos y las 7 altas se corrigieron ANTES de publicar. Estos 20 de
severidad media/baja quedan documentados y pendientes:

## Media
- Carrera de datos benigna en el tap de ContinuoAudio (conversor/buffersVistos entre hilo de audio y cola).
- Reconfigurar en ráfaga desde los sliders reinicia el stack de grabación decenas de veces por arrastre (falta debounce).
- Con micrófono no disponible y bitácora activa, el vigía de 400 ms del listener fuerza remontajes sin tregua.
- Rutinas simultáneas: la segunda recibe «tanda en curso» y genera su documento sin esperar material fresco.
- ContinuoPantalla: estado compartido entre main y el executor del Task (benigno, mismo patrón que el tap).
- Inyección de prompt vía contenido capturado (una web en pantalla puede «hablarle» a la IA del resumen). Mitigación parcial: el aviso al modelo ya distingue canales.
- Secretos visibles en pantalla acaban en el índice y pueden viajar en el prompt (falta lista de exclusión por defecto: gestores de claves, bancos).
- Modo Tarea (preexistente, destapado por la review): verbos sueltos crean tareas por error.
- Recordatorio periódico de tareas activado por defecto sin toggle visible (preexistente).
- Rutinas/resumen arman el material del día en el hilo principal (mover a fondo).

## Baja
- pmset síncrono en main en cada tic con «solo con corriente».
- El audio del sistema no se rearma tras didStopWithError (muere hasta reconfigurar).
- dictadoOcupado lee estado de main desde la cola del lote sin salto.
- applicationWillTerminate no espera el cierre de la bitácora (lo cubre el rescate de huérfanos).
- guardar() de documentos: check-then-write sin exclusión (colisión en el mismo segundo).
- Purga automática solo al arrancar; en sesiones largas no se re-aplica.
- Trozos < 16 KB quedan fuera de índice/purga (huérfanos milimétricos).
- rescatarHuerfanos puede indexar el trozo aún abierto con metadatos provisionales.
- Purga no atómica si un borrado físico falla (texto del índice se pierde primero).
- Router global por IA (preexistente): hasta ~30 s de latencia en manos libres sin plan determinista.
