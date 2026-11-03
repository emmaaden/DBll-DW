# Presentación del TP: Data Warehouse de una clínica

Guion para la defensa del TP de Base de Datos II. Dura unos 15 minutos. Cada bloque tiene **qué mostrar**, **qué decir** y **cómo justificarlo**. Al final hay preguntas probables con respuesta corta y los números para tener a mano.

> Los textos entre comillas son una guía para decirlo con tus palabras, no para leerlos de memoria.

---

## Antes de empezar (checklist)

- [ ] Servicios corriendo: **SQL Server (MSSQLSERVER)** y **SQL Server Analysis Services (MSSQLSERVER)**.
- [ ] **No vuelvas a ejecutar el script 01** antes de presentar. Genera datos aleatorios (`NEWID()`), así que cambian todos los números de esta guía. Si lo ejecutás, después corré el 02, el 03 y reprocesá el cubo.
- [ ] Cubo procesado: en Visual Studio, clic derecho en el proyecto > **Process** > *Process Full*.
- [ ] Power BI abierto con `Clinica.pbix` y conexión en directo a `localhost` / `Cubo_Clinica`. Hacé clic en **Actualizar** para que tome los datos del cubo.
- [ ] Abiertos en pestañas: SSMS (scripts 01, 02 y 03), Visual Studio (cubo), Power BI y el diagrama estrella (`Diagrama_Estrella.svg`).

---

## 1. Introducción (1 minuto)

**Mostrar:** el esquema general.

```
Clinica (OLTP)  --ETL-->  DW_Clinica (estrella)  -->  Cubo OLAP (SSAS)  -->  Power BI
```

**Decir:**
> "Partimos de la base operativa de una clínica, que registra pacientes, profesionales y turnos. Esa base sirve para el día a día, pero no para analizar. Armamos un Data Warehouse con modelo estrella, lo cargamos con un ETL en SQL, construimos un cubo OLAP en Analysis Services con indicadores y lo consumimos desde Power BI."

**La pregunta de negocio:** ¿cuántos turnos se atienden, cuántos se pierden por ausencia o cancelación, y de qué depende?

---

## 2. Base operativa OLTP (1,5 minutos)

**Mostrar:** el DER (`DER - Sistema Clinica (1).png`) y el script `01_OLTP_Clinica.sql`.

**Decir:**
> "La base `Clinica` sigue el DER: Paciente, Profesional, Especialidad, la tabla intermedia Especialidad_Profesional (porque un profesional puede tener varias especialidades), Horario_Profesional, Turno, HistoriaClinica y Consulta. Generamos datos de prueba: 10 especialidades, 20 profesionales, 600 pacientes y unos 9.000 turnos entre 2024 y 2026."

**Detalle a mencionar: el cambio en `Turno`.**
> "Le agregamos a `Turno` la columna `id_especialidad`. Como un profesional puede tener más de una especialidad, el turno tiene que decir con cuál se atendió. Tiene una clave foránea compuesta `(id_especialidad, id_profesional)` hacia `Especialidad_Profesional`, así la base no deja cargar un turno con una especialidad que el profesional no tiene."

**Justificación:** sin ese dato, el DW tendría que adivinar la especialidad. La regla del lugar correcto: **un dato que falta se arregla en el origen, no se inventa en el ETL.**

**Si te preguntan por los estados:** 1 Pendiente, 2 Atendido, 3 Cancelado, 4 Ausente. Los turnos futuros quedan Pendientes.

**Si te preguntan por los datos:** los generamos con algunos patrones a propósito (más ausentismo en pacientes particulares, en jóvenes de 18 a 35 y en turnos antes de las 9, y una mejora en 2026) para que los indicadores muestren algo para analizar. Decilo con naturalidad: es un juego de datos de prueba.

---

## 3. Modelo estrella (3 minutos)

**Mostrar:** `Diagrama_Estrella.svg` y el script `02_DW_Clinica_Estrella.sql`.

**Decir:**
> "El proceso de negocio que analizamos es el **turno**. La tabla de hechos es `Fact_Turno` y su **grano es una fila por turno**. Alrededor hay seis dimensiones: Tiempo, Horario, Paciente, Profesional, Especialidad y Estado."

**Las medidas** son flags de 1 y 0, así que todas se pueden **sumar**:

| Medida | Qué vale |
|---|---|
| `cantidad_turnos` | siempre 1 |
| `turno_atendido` / `turno_cancelado` / `turno_ausente` / `turno_pendiente` | 1 si el turno está en ese estado, si no 0 |
| `edad_paciente` | edad el día del turno (se suma para sacar el promedio) |

**Decisiones de diseño y cómo justificarlas:**

| Decisión | Por qué |
|---|---|
| Grano = 1 turno | Es el nivel más detallado. Desde ahí se puede agregar a cualquier nivel; al revés no se puede |
| Modelo estrella (no copo de nieve) | Menos JOINs, consultas más simples y rápidas. Las dimensiones están desnormalizadas a propósito |
| Claves subrogadas (`sk_...`) | Independizan el DW de los ids del origen. El id original se guarda aparte (`id_paciente`, etc.) |
| `Dim_Tiempo` con clave `AAAAMMDD` | Se genera por script, cubre 2024-2027 (1.461 días). La clave se calcula desde la fecha sin JOIN |
| `Dim_Horario` en franjas de 30 minutos | 48 filas. Permite analizar por hora y por franja (Mañana, Mediodía, Tarde) |
| `id_turno` en el hecho | Es una **dimensión degenerada**: identifica el turno pero no tiene tabla propia |
| Flags 1/0 en vez de un texto de estado | Se pueden sumar, y las tasas salen dividiendo sumas |
| `HistoriaClinica` y `Consulta` afuera | No tienen profesional ni turno. Podrían ser otra tabla de hechos (constelación) |

---

## 4. ETL (3 minutos)

**Mostrar:** `03_ETL_Carga_DW.sql`, el procedimiento `dbo.sp_Cargar_DW`.

**Decir:**
> "El ETL es un procedimiento almacenado. Primero carga las dimensiones y después los hechos, porque el hecho necesita las claves subrogadas de las dimensiones. Todo corre dentro de una transacción con TRY/CATCH: o se carga todo o no se carga nada."

**Las tres partes:**

1. **Dimensiones con `MERGE` (SCD tipo 1).** Si el paciente es nuevo, lo inserta. Si ya existe, actualiza sus datos y sobrescribe los viejos.
   - En la transformación: nombre completo, edad y rango etario, obra social vacía → "Sin obra social", localidad sacada de la dirección.
2. **Hechos con `TRUNCATE` + `INSERT`.**
   > "Recargamos la tabla de hechos completa porque **el estado de un turno cambia**: un turno pendiente después pasa a atendido, cancelado o ausente. Reconstruirla asegura que cada turno tenga su estado actual."
3. **Especialidad del turno.** Se toma directo de `Turno.id_especialidad`.
   > "Antes el turno no tenía especialidad y el ETL asumía la de menor id del profesional. Eso contaba mal los turnos de los dos profesionales con dos especialidades: los de Cardiología de Ferreyra y los de Pediatría de Castillo quedaban como Clínica Médica. Lo corregimos en el origen agregando la columna al turno."

**Justificaciones clave:**

| Pregunta | Respuesta |
|---|---|
| ¿Por qué `MERGE` en las dimensiones y no `TRUNCATE`? | `Fact_Turno` tiene FK hacia las dimensiones, y además se perderían las claves subrogadas ya asignadas |
| ¿Por qué SCD 1 y no SCD 2? | No se pidió historia de cambios. Con SCD 2 se podría analizar con la obra social que el paciente tenía en cada momento |
| ¿Se puede ejecutar varias veces? | Sí, es idempotente: las dimensiones no se duplican y el hecho se rearma |
| ¿Cómo verifican que no se pierden turnos? | Se compara `COUNT(*)` de `Clinica.dbo.Turno` (9.025) con `Fact_Turno` (9.025) |

**Mostrar en vivo (opcional):** la consulta de verificación del final del script 03, que da las tasas por año.

---

## 5. Cubo OLAP en Analysis Services (3 minutos)

**Mostrar:** Visual Studio, proyecto `Cubo_Clinica`, cubo `Clinica`.

**Decir:**
> "El cubo lee el DW. Tiene un grupo de medidas con las sumas de la tabla de hechos y las seis dimensiones. En la dimensión Tiempo armamos la jerarquía **Calendario**: Año › Semestre › Trimestre › Mes › Fecha."

**Detalles técnicos:**
- Los niveles usan claves que incluyen el año (`id_mes` = 202503, `id_trimestre` = 20251). Si se usara solo `mes`, marzo 2024 y marzo 2025 serían el mismo miembro y daría error de clave duplicada.
- Las **relaciones de atributos** (Fecha → Mes → Trimestre → Semestre → Año) hacen que SSAS agregue bien y más rápido.

**Medidas calculadas (MDX)**, en la carpeta *Indicadores*:

| Medida | Fórmula |
|---|---|
| Turnos Cerrados | atendidos + cancelados + ausentes |
| Tasa Asistencia | atendidos / cerrados |
| Tasa Ausentismo | ausentes / cerrados |
| Tasa Cancelación | cancelados / cerrados |
| Edad Promedio | suma de edades / cantidad de turnos |
| Turnos Año Anterior | `ParallelPeriod` sobre el nivel Año |
| Variación Interanual | (turnos − año anterior) / año anterior |

> "Las tasas se calculan sobre los turnos **cerrados**, sin los pendientes, porque de un turno pendiente todavía no sabemos si el paciente va a venir. Y se calculan en el cubo, no en el ETL, porque **un porcentaje no se puede sumar**: hay que dividir las sumas en cada nivel."

**KPIs** (valor, meta, semáforo y tendencia):

| KPI | Meta | Verde | Amarillo | Rojo |
|---|---|---|---|---|
| Asistencia | ≥ 75 % | ≥ 75 % | 65-75 % | < 65 % |
| Ausentismo | ≤ 10 % | ≤ 10 % | 10-15 % | > 15 % |
| Cancelación | ≤ 12 % | ≤ 12 % | 12-18 % | > 18 % |
| Crecimiento Demanda | ≥ +10 % | ≥ 10 % | 0-10 % | < 0 % |

Asistencia y Ausentismo además tienen **tendencia** (flecha), que compara con el período anterior. En Ausentismo la flecha sube cuando el valor baja, porque bajar es bueno.

**Mostrar en vivo (opcional):** la pestaña *Browser* del cubo, o en SSMS una consulta de la Parte C de `04_Calculos_e_Indicadores_MDX.txt`.

---

## 6. Tablero en Power BI (2 minutos)

**Mostrar:** `Clinica.pbix`.

**Decir:**
> "Power BI se conecta al cubo en **conexión en directo**: no copia los datos, consulta el cubo cada vez. Así usa las mismas medidas y KPIs que definimos en Analysis Services, y la lógica de negocio queda en un solo lugar."

Recorré las visualizaciones: tarjetas con los KPIs, la evolución por mes, los turnos por especialidad, el ausentismo por obra social y los filtros (año, especialidad, obra social, sexo).

**Si aparece 2027 vacío:** la dimensión Tiempo llega hasta 2027 pero no hay turnos ese año. Filtralo en el tablero.

---

## 7. Hallazgos y conclusiones (1,5 minutos)

Con los datos actuales:

| Año | Turnos | Asistencia | Ausentismo | Cancelación |
|---|---|---|---|---|
| 2024 | 1.914 | 76,2 % | 12,4 % | 11,4 % |
| 2025 | 3.219 | 75,5 % | 12,3 % | 12,2 % |
| 2026 | 3.892 | 79,9 % | 9,2 % | 10,9 % |

**Para decir:**
- **La demanda crece:** +68,2 % en 2025 y +20,9 % en 2026. El KPI Crecimiento Demanda está en verde.
- **El ausentismo bajó en 2026** de 12,3 % a 9,2 % y entró en la meta del 10 %. Por ejemplo, se lo puede atribuir a recordatorios de turno.
- **Obra social:** los pacientes **particulares** faltan mucho más (19,2 %) que los de PAMI (8,1 %) u OSDE (9,3 %).
- **Edad:** los jóvenes de 18 a 35 tienen el ausentismo más alto (16,3 %).
- **Horario:** los turnos antes de las 9 tienen 14,1 % de ausentismo, contra 10,5 % en el resto.

**Conclusión:**
> "El DW permite ver de dónde salen las ausencias, cosa que la base operativa no muestra a simple vista. Una acción concreta sería reforzar los recordatorios para pacientes particulares, jóvenes y turnos de primera hora."

---

## Preguntas probables

**1. ¿Qué diferencia hay entre OLTP y un Data Warehouse?**
El OLTP está normalizado y optimizado para muchas escrituras chicas (sacar un turno). El DW está desnormalizado y optimizado para leer y agregar muchos datos (analizar). Además el DW guarda historia y se carga periódicamente.

**2. ¿Por qué estrella y no copo de nieve?**
Menos JOINs y consultas más simples. El costo es repetir datos en las dimensiones, que en un DW es aceptable porque se lee mucho más de lo que se escribe.

**3. ¿Qué es el grano?**
Lo que representa una fila del hecho. Acá, un turno. Se define primero porque todo lo demás depende de eso.

**4. ¿Qué es una clave subrogada y para qué sirve?**
Es un id propio del DW (`sk_paciente`), sin significado de negocio. Independiza el DW del sistema origen y permite SCD tipo 2 si hiciera falta.

**5. ¿Qué es una dimensión degenerada?**
Un atributo que está en el hecho pero no tiene tabla propia: `id_turno`.

**6. ¿Qué es SCD tipo 1? ¿Y tipo 2?**
Tipo 1: se sobrescribe el valor viejo, no se guarda historia (lo que usamos). Tipo 2: se agrega una fila nueva con fechas de vigencia, y se conserva la historia.

**7. ¿Por qué los porcentajes no están en la tabla de hechos?**
Porque no son aditivos: sumar porcentajes da cualquier cosa. Se guardan los conteos (flags 1/0) y el cubo divide las sumas en cada nivel.

**8. ¿Por qué excluyen los pendientes de las tasas?**
Porque todavía no se sabe si el paciente va a venir. Incluirlos bajaría la asistencia de forma artificial, sobre todo en el año en curso.

**9. Un profesional tiene varias especialidades. ¿Cómo lo resolvieron?**
Agregamos `id_especialidad` al turno en el origen, con FK compuesta a `Especialidad_Profesional`. El ETL la toma directo. Las alternativas eran suponer una especialidad principal (contaba mal los turnos) o una tabla puente (complica el modelo y puede contar un turno dos veces).

**10. ¿Por qué recargan entera la tabla de hechos?**
Porque el estado de los turnos cambia. Con 9.000 filas la recarga completa tarda segundos. Con millones de filas convendría una carga incremental (por fecha de modificación).

**11. ¿Qué pasa si el ETL falla a la mitad?**
Está en una transacción con TRY/CATCH: hace ROLLBACK y el DW queda como estaba. El THROW muestra el error.

**12. ¿Para qué está la jerarquía Calendario?**
Para hacer drill-down (año → trimestre → mes → día) y para funciones como `ParallelPeriod`, que necesitan saber qué es "el mismo período del año anterior".

**13. ¿Qué es un KPI en SSAS?**
Un indicador con cuatro partes: valor, meta, estado (semáforo: 1, 0, −1) y tendencia (flecha). Se define en MDX dentro del cubo.

**14. ¿Por qué conexión en directo en Power BI y no importar?**
Para usar las medidas y KPIs del cubo sin reescribirlos en DAX, y para tener una sola fuente de verdad. Si se importara, habría que copiar los datos y recalcular todo en Power BI.

**15. ¿Qué mejorarías?**
Carga incremental del hecho, SCD 2 en Paciente (cambios de obra social), una segunda tabla de hechos con las consultas (constelación) y programar el ETL y el procesamiento del cubo con SQL Server Agent.

---

## Si algo falla en vivo

| Problema | Qué hacer |
|---|---|
| Power BI no conecta | Revisá que el servicio de Analysis Services esté corriendo. Servidor `localhost`, base `Cubo_Clinica` |
| El cubo no procesa (*Login failed for user NT Service\MSSQLServerOLAPService*) | Volvé a ejecutar el script 02: al final le da permiso de lectura a esa cuenta |
| MDX con error *member not found* | Algún nombre no coincide. El nivel del año se llama `Año`: `[Tiempo].[Calendario].[Año]` |
| Los números no coinciden con esta guía | Se volvió a ejecutar el script 01 (datos aleatorios). Usá los números que muestra el tablero |
