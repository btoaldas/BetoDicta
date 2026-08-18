# Hallazgos conocidos aplazados a 0.51.1

De la revisión del release 0.51.0 (10 confirmados). Los de severidad alta y
media se corrigieron antes de publicar. Quedan:

- `cargarExplorador` recorre dos veces el árbol completo de la bitácora en cada
  refresco (una por transcripciones, otra por documentos). Con meses de
  historial la pestaña tarda; conviene un solo recorrido con dos filtros.
- Los diccionarios `huellaPrevia`/`ultimaEscritura` de ContinuoPantalla se
  mutan desde main y desde el executor del Task de captura. La carrera era
  benigna con valores simples; con diccionarios conviene confinarlos.

Sigue vigente lo listado en PENDIENTES-0.50.1.md que no se haya corregido.
