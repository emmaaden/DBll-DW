# Guía de estudio: Data Warehouse y ETL

Nov 1, 2026 · @Emma

## 1. Panorama del trabajo

El TP toma los datos de turnos de una clínica, los pasa a un Data Warehouse con modelo estrella, arma un cubo OLAP encima y muestra los indicadores en Power BI. La idea central: **la base de la clínica sirve para operar; el DW y el cubo sirven para analizar.**

El recorrido de los datos, en orden de ejecución:

1. **`01_OLTP_Clinica.sql`** crea la base operativa `Clinica` según el DER y la llena con datos de prueba (unos 600 pacientes, 9.000 turnos y 6.000 consultas).
2. **`02_DW_Clinica_Estrella.sql`** crea la base `DW_Clinica`: 6 dimensiones y 1 tabla de hechos. También carga las dimensiones fijas (Tiempo, Horario, Estado) y le da permiso de lectura a Analysis Services.
3. **`03_ETL_Carga_DW.sql`** crea el procedimiento `sp_Cargar_DW`, que copia y transforma los datos de `Clinica` al DW. Al final muestra los indicadores por año calculados en SQL.
4. **Proyecto `Cubo_Clinica` (Visual Studio, SSAS multidimensional)**: lee el DW y arma el cubo `Clinica` con sus dimensiones, jerarquías y medidas.
5. **`04_Calculos_e_Indicadores_MDX.txt`**: las medidas calculadas, los 4 KPIs y consultas MDX de prueba que se cargan en el cubo.
6. **`Clinica.pbix` (Power BI)**: el tablero de comando conectado en vivo al cubo.

| Archivo | Qué contiene | Herramienta |
| --- | --- | --- |
| `DER - Sistema Clinica (1).png` | El modelo entidad-relación original | (imagen) |
| `01_OLTP_Clinica.sql` | Base transaccional + datos de prueba | SSMS |
| `02_DW_Clinica_Estrella.sql` | Estructura del DW + dimensiones fijas | SSMS |
| `03_ETL_Carga_DW.sql` | Procedimiento de carga `sp_Cargar_DW` | SSMS |
| `03_ETL_Explicacion.md` | Explicación del ETL bloque por bloque | (texto) |
| `04_Calculos_e_Indicadores_MDX.txt` | Miembros calculados, KPIs, consultas MDX | Visual Studio / SSMS |
| `Diagrama_Estrella.drawio` / `.svg` | Dibujo del modelo estrella | diagrams.net |
| `Cubo_Clinica/` | Proyecto del cubo OLAP | Visual Studio |
| `Clinica.pbix` | Tablero de comando | Power BI Desktop |

**Proceso de negocio analizado:** la gestión de turnos. Se quiere saber cuántos turnos hay, cuántos se atienden, cuántos se cancelan y cuántos se pierden porque el paciente no vino, mirado por fecha, horario, paciente, profesional y especialidad.

## 2. Conceptos base que te van a preguntar

Si entendés estos conceptos, el resto del TP se explica solo. Cada uno tiene su ejemplo dentro del proyecto.

### OLTP vs. Data Warehouse

|  | OLTP (`Clinica`) | Data Warehouse (`DW_Clinica`) |
| --- | --- | --- |
| Para qué sirve | Operar el día a día: dar un turno, registrar una consulta | Analizar y tomar decisiones |
| Operaciones típicas | Muchos INSERT/UPDATE chicos | Pocas consultas grandes que suman miles de filas |
| Diseño | Normalizado (3FN), muchas tablas, sin redundancia | Desnormalizado (estrella), pocas tablas, con redundancia a propósito |
| Datos | Estado actual | Historia, preparada para comparar períodos |
| Ejemplo del TP | `Turno.estado = 4` | `Dim_Estado.estado = 'Ausente'` y `turno_ausente = 1` |

**Por qué no analizar directo sobre el OLTP:** las consultas analíticas son pesadas y frenarían el sistema que usa la clínica. Además el OLTP no tiene año, trimestre, franja horaria ni rango etario: habría que calcularlos en cada consulta.

### ETL

**E**xtract, **T**ransform, **L**oad: extraer los datos del origen, transformarlos (limpiar, calcular, traducir códigos) y cargarlos en el DW. En el TP es el procedimiento `sp_Cargar_DW`.

### Modelo estrella

Una tabla de **hechos** en el centro, rodeada de tablas de **dimensiones**, cada una unida al hecho por una clave foránea (relación 1 a N). Se llama estrella por la forma del dibujo.

- **Estrella:** las dimensiones se conectan solo al hecho, nunca entre sí. Menos JOINs, consultas más rápidas y más fáciles de entender.
- **Copo de nieve (snowflake):** una dimensión se normaliza en varias tablas (por ejemplo, Profesional → Especialidad). El TP **no** lo usa: Especialidad cuelga directo del hecho.
- **Constelación:** varias tablas de hechos que comparten dimensiones. Sería el caso si se agregara una `Fact_Consulta`.

### Tabla de hechos

Guarda los **eventos medibles** del negocio: en el TP, cada turno. Tiene dos tipos de columnas: claves foráneas a las dimensiones y **medidas** (números que se suman).

**Grano:** qué representa una fila. En `Fact_Turno` el grano es **una fila = un turno**. Es la primera decisión del diseño; todo lo demás depende de ella.

### Dimensiones

Responden al «por qué cosa» quiero ver los números: por mes, por obra social, por especialidad. Tienen atributos descriptivos (texto) y, a veces, jerarquías.

**Jerarquía:** niveles de detalle dentro de una dimensión. En Tiempo: Año > Semestre > Trimestre > Mes > Fecha. Permite subir (*roll-up*) y bajar (*drill-down*) de nivel.

### Claves subrogadas (sk\_)

Una **clave subrogada** es una clave propia del DW, sin significado de negocio (`sk_paciente`, generada con `IDENTITY`). La clave del sistema origen (`id_paciente`) se guarda aparte y se llama **clave natural** o de negocio.

Sirven para que el DW no dependa de los ids del origen: si el origen cambia o se integran dos sistemas con ids repetidos, el DW sigue funcionando. También son la base para una SCD tipo 2, donde un mismo paciente puede tener varias filas.

### Dimensión degenerada

Un dato que está en el hecho pero no tiene tabla de dimensión propia. En el TP: `id_turno`. Sirve para identificar el turno, pero no tiene atributos que justifiquen una tabla.

### SCD (dimensión lentamente cambiante)

Qué hacer cuando cambia un dato de una dimensión, por ejemplo la obra social de un paciente.

| Tipo | Qué hace | Historia | En el TP |
| --- | --- | --- | --- |
| SCD 0 | Nunca cambia el valor | Se queda el original | No |
| SCD 1 | Sobrescribe el valor viejo | Se pierde | **Sí** (los MERGE) |
| SCD 2 | Agrega una fila nueva con fechas de vigencia | Se conserva completa | No (sería la mejora) |
| SCD 3 | Agrega una columna «valor anterior» | Solo el cambio anterior | No |

### Medidas aditivas y no aditivas

- **Aditiva:** se puede sumar por cualquier dimensión. Ejemplo: `cantidad_turnos`, `turno_ausente`.
- **No aditiva:** sumarla da un número sin sentido. Ejemplo: una tasa o un promedio. Sumar el 10 % de enero y el 12 % de febrero no da el ausentismo del bimestre.

Por eso el DW guarda solo medidas aditivas y las tasas se calculan en el cubo como **cociente de sumas** (ausentes ÷ cerrados). Lo mismo con la edad promedio: se guarda la suma de edades y se divide por la cantidad de turnos.

### OLAP y cubo

Un **cubo OLAP** precalcula las sumas de las medidas para todas las combinaciones de dimensiones. Así una consulta como «ausentismo por obra social en 2025» responde al instante. Operaciones típicas:

- **Roll-up / drill-down:** subir o bajar en una jerarquía (de Año a Mes y al revés).
- **Slice:** fijar un valor de una dimensión (solo 2025).
- **Dice:** fijar valores en varias dimensiones (2025 + Cardiología + OSDE).
- **Pivot:** rotar filas y columnas del resultado.

El TP usa **SSAS multidimensional** (SQL Server Analysis Services). Las consultas al cubo se escriben en **MDX**.

## 3. El modelo estrella del proyecto (script 02)

`DW_Clinica` tiene **1 tabla de hechos (`Fact_Turno`) y 6 dimensiones**. Todas las dimensiones se unen al hecho con una relación 1 a N por su clave `sk_`.

&#91;embedded content: modelo estrella de DW\_Clinica · 1 hecho, 6 dimensiones\]

Las dimensiones nunca se conectan entre sí: todas pasan por `Fact_Turno`. Eso es lo que la hace estrella y no copo de nieve.

### Del DER al modelo estrella

| Tabla del OLTP | Qué pasa en el DW |
| --- | --- |
| `Turno` | Se convierte en **`Fact_Turno`** (cada turno es un hecho) |
| `Turno.fecha` | Se convierte en **`Dim_Tiempo`** |
| `Turno.hora` | Se convierte en **`Dim_Horario`** |
| `Turno.estado` | Se convierte en **`Dim_Estado`** + las medidas bandera |
| `Paciente` | **`Dim_Paciente`** (sin dni, password, email ni teléfono) |
| `Profesional` | **`Dim_Profesional`** (sin dni, password, email ni teléfono) |
| `Especialidad` + `Especialidad_Profesional` | **`Dim_Especialidad`** (se elige la especialidad principal) |
| `Horario_Profesional` | No se usa: es la agenda, no un hecho que se mida |
| `HistoriaClinica`, `Consulta` | No se usan: `Consulta` no tiene profesional ni turno |

### Fact\_Turno (el centro de la estrella)

**Grano:** una fila por turno. Clave primaria: `id_turno` (dimensión degenerada).

| Columna | Tipo | Qué es | Para qué sirve |
| --- | --- | --- | --- |
| `id_turno` | PK | Número de turno del origen | Identificar el turno; no tiene tabla propia |
| `sk_tiempo` | FK | Fecha del turno | Unir con `Dim_Tiempo` |
| `sk_horario` | FK | Hora redondeada a 30 min | Unir con `Dim_Horario` |
| `sk_paciente` | FK | Paciente | Unir con `Dim_Paciente` |
| `sk_profesional` | FK | Profesional | Unir con `Dim_Profesional` |
| `sk_especialidad` | FK | Especialidad principal | Unir con `Dim_Especialidad` |
| `sk_estado` | FK | Estado del turno | Unir con `Dim_Estado` |
| `cantidad_turnos` | Medida | Siempre 1 | Sumada = total de turnos |
| `turno_atendido` | Medida | 1 si se atendió | Sumada = atendidos |
| `turno_cancelado` | Medida | 1 si se canceló | Sumada = cancelados |
| `turno_ausente` | Medida | 1 si el paciente no vino | Sumada = ausentes |
| `turno_pendiente` | Medida | 1 si todavía no ocurrió | Sumada = pendientes |
| `edad_paciente` | Medida | Edad el día del turno | Sumada y dividida = edad promedio |

**Por qué medidas bandera (1/0):** el cubo solo sabe sumar rápido. Con un 1 en la columna del estado, sumar `turno_ausente` da la cantidad de ausentes sin escribir un filtro. Y las tasas salen dividiendo dos sumas.

### Dim\_Tiempo

Una fila por día, del 01/01/2024 al 31/12/2027 (1.461 filas). **Se genera por script**, no sale del origen.

| Columna | Ejemplo | Para qué |
| --- | --- | --- |
| `sk_tiempo` (PK) | `20250315` | Clave «inteligente» AAAAMMDD |
| `fecha` / `fecha_desc` | 2025-03-15 / `15/03/2025` | Nivel Fecha de la jerarquía |
| `anio` | 2025 | Nivel Año |
| `id_semestre` / `semestre_desc` | 20251 / `S1 2025` | Nivel Semestre |
| `id_trimestre` / `trimestre_desc` | 20251 / `T1 2025` | Nivel Trimestre |
| `id_mes` / `mes_anio_desc` | 202503 / `Marzo 2025` | Nivel Mes |
| `mes`, `nombre_mes` | 3, `Marzo` | Comparar meses entre años |
| `semana_anio`, `dia_mes` | 11, 15 | Detalle |
| `dia_semana`, `nombre_dia` | 6, `Sábado` | Analizar por día de la semana |
| `es_fin_de_semana` | `Si` | Filtrar fines de semana |

**Clave importante:** `id_mes` y `id_trimestre` incluyen el año (202503, no 3). Si no, «Marzo 2024» y «Marzo 2025» serían el mismo miembro y la jerarquía fallaría con clave duplicada.

### Dim\_Horario

48 filas, una por cada media hora del día. También **generada por script**.

| Columna | Ejemplo | Para qué |
| --- | --- | --- |
| `sk_horario` (PK) | `830` | Clave HHMM (08:30) |
| `hora`, `hora_desc` | 08:30, `08:30` | Mostrar la hora |
| `hora_del_dia` | 8 | Agrupar por hora |
| `franja_horaria` | `Mañana` | Madrugada (0-5), Mañana (6-11), Mediodía (12-13), Tarde (14-19), Noche (20-23) |
| `orden_franja` | 2 | Ordenar las franjas en orden lógico y no alfabético |

### Dim\_Paciente

| Columna | Origen | Para qué |
| --- | --- | --- |
| `sk_paciente` (PK) | `IDENTITY` del DW | Clave subrogada |
| `id_paciente` (UNIQUE) | `Paciente.id` | Clave natural, para que el ETL encuentre al paciente |
| `nombre_completo` | apellido + nombre | Mostrar |
| `sexo` | `Paciente.sexo` limpio | Analizar por sexo |
| `fecha_nacimiento`, `edad` | `fechaNacimiento` | Edad actual |
| `rango_etario` | Calculado de la edad | Analizar por grupo de edad |
| `obra_social` | `Paciente.obra_social` | Analizar por obra social |
| `localidad` | Parte de `direccion` después de la coma | Analizar por localidad |

### Dim\_Profesional

`sk_profesional` (PK, IDENTITY), `id_profesional` (clave natural), `nombre_completo` y `matricula`.

### Dim\_Especialidad

`sk_especialidad` (PK, IDENTITY), `id_especialidad` (clave natural) y `nombre_especialidad`. Son 10 especialidades (Clínica Médica, Pediatría, Cardiología, etc.).

### Dim\_Estado

4 filas fijas. La `sk_estado` es igual al código del origen, así el ETL no necesita buscarla.

| sk\_estado | estado | tipo\_estado |
| --- | --- | --- |
| 1 | Pendiente | Abierto |
| 2 | Atendido | Cerrado |
| 3 | Cancelado | Cerrado |
| 4 | Ausente | Cerrado |

`tipo_estado` separa los turnos que ya terminaron (Cerrado) de los que todavía no (Abierto). Es la base de las tasas.

### Las dos claves de las dimensiones fijas

- **Tiempo y Horario usan claves inteligentes** (20250315, 830): el ETL las calcula directo desde la fecha y la hora, sin hacer un JOIN.
- **Paciente, Profesional y Especialidad usan IDENTITY**: el ETL hace un JOIN por la clave natural para obtener la `sk_`.

### El permiso para Analysis Services

Al final del script 02 se crea un login para `NT Service\MSSQLServerOLAPService` y se le da el rol `db_datareader`. El cubo lee el DW con esa cuenta de servicio; sin el permiso, el procesamiento falla con *Login failed*.

## 4. El ETL paso a paso (script 03)

Todo el ETL es un solo procedimiento, `dbo.sp_Cargar_DW`, que carga primero las 3 dimensiones con `MERGE` y después rearma la tabla de hechos desde cero. Lee directo de `Clinica.dbo...` y escribe en `DW_Clinica.dbo...` (las dos bases están en el mismo servidor).

### 4.1 El esqueleto: transacción + TRY/CATCH

```sql
CREATE OR ALTER PROCEDURE dbo.sp_Cargar_DW AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Hoy DATE = CAST(GETDATE() AS DATE);
    BEGIN TRY
        BEGIN TRANSACTION;
        -- 1) Dim_Paciente     (MERGE)
        -- 2) Dim_Profesional  (MERGE)
        -- 3) Dim_Especialidad (MERGE)
        -- 4) Fact_Turno       (TRUNCATE + INSERT)
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
```

| Pieza | Qué hace | Por qué |
| --- | --- | --- |
| `CREATE OR ALTER` | Crea el procedimiento o lo reemplaza si ya existe | Poder correr el script varias veces sin error |
| `SET NOCOUNT ON` | No muestra «N filas afectadas» | Salida más limpia y un poco más rápida |
| `@Hoy` | Guarda la fecha de hoy | Calcular la edad actual del paciente |
| `BEGIN TRANSACTION` / `COMMIT` | Agrupa toda la carga en una sola unidad | **Todo o nada**: nunca queda un DW a medio cargar |
| `ROLLBACK` en el CATCH | Si algo falla, deshace todo | El DW queda como estaba antes |
| `THROW` | Vuelve a lanzar el error original | Que el usuario vea qué falló |

**Idempotencia:** el procedimiento se puede ejecutar todas las veces que quieras y el resultado es el mismo. Las dimensiones no se duplican (MERGE) y los hechos se rearman (TRUNCATE).

**El orden importa:** primero dimensiones, después hechos. Para insertar un turno hacen falta las `sk_` de paciente, profesional y especialidad, que recién existen cuando las dimensiones están cargadas.

### 4.2 Dim\_Paciente con MERGE

`MERGE` compara una tabla destino con un origen y decide fila por fila qué hacer:

```sql
MERGE dbo.Dim_Paciente AS d          -- destino
USING ( SELECT ... FROM Clinica.dbo.Paciente p ... ) AS s   -- origen ya transformado
ON d.id_paciente = s.id              -- se comparan por la clave natural
WHEN MATCHED THEN UPDATE SET ...     -- ya existe: se pisan los datos (SCD 1)
WHEN NOT MATCHED BY TARGET THEN INSERT ...;  -- no existe: se inserta
```

La `sk_paciente` no se inserta: la genera sola el `IDENTITY`.

**Transformaciones que hace el SELECT del origen:**

| Campo DW | Transformación | Ejemplo |
| --- | --- | --- |
| `nombre_completo` | `apellido + ', ' + nombre` | «Pérez, Juan» |
| `sexo` | `LTRIM(RTRIM())` y si queda vacío o NULL → `'Sin dato'` | `' '` → «Sin dato» |
| `edad` | Edad exacta a hoy (ver abajo) | 25 |
| `rango_etario` | `CASE` sobre la edad | «18-35 Jóvenes» |
| `obra_social` | Vacío o NULL → `'Sin obra social'` | «OSDE» |
| `localidad` | Lo que viene después de la primera coma de `direccion` | «San Martín 123, Godoy Cruz» → «Godoy Cruz» |

**El truco `ISNULL(NULLIF(LTRIM(RTRIM(x)), ''), 'Sin dato')`**, de adentro hacia afuera:

1. `LTRIM(RTRIM(x))` saca los espacios de los costados.
2. `NULLIF(..., '')` convierte el texto vacío en NULL.
3. `ISNULL(..., 'Sin dato')` reemplaza el NULL por «Sin dato».

Así, NULL, `''` y `'   '` terminan todos en «Sin dato». **Por qué:** en el cubo y en Power BI un vacío aparece como un miembro en blanco que confunde. Con nombre se puede filtrar y contar.

**Cálculo de la edad exacta:**

```sql
CROSS APPLY (SELECT DATEDIFF(YEAR, p.fechaNacimiento, @Hoy)
                  - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, p.fechaNacimiento, @Hoy), p.fechaNacimiento) > @Hoy
                         THEN 1 ELSE 0 END AS edad) e
```

`DATEDIFF(YEAR, ...)` solo resta los años del calendario, sin mirar si ya pasó el cumpleaños. La fórmula suma esos años a la fecha de nacimiento: si el resultado cae después de hoy, todavía no cumplió y resta 1.

Ejemplo: nació el 20/11/2000, hoy es 28/10/2026. `DATEDIFF` da 26, pero el 20/11/2026 todavía no llegó: la edad es **25**.

`CROSS APPLY` calcula la edad una sola vez y la deja disponible como columna `e.edad`, que se usa dos veces (en `edad` y en `rango_etario`) sin repetir la fórmula.

**Rangos etarios:** 0-12 Niños, 13-17 Adolescentes, 18-35 Jóvenes, 36-59 Adultos, 60+ Adultos mayores.

**Localidad:** `CHARINDEX(',', direccion)` busca la posición de la coma y `SUBSTRING` toma lo que sigue. Por eso en el script 01 se decidió guardar la dirección como «Calle 123, Localidad».

### 4.3 Dim\_Profesional y Dim\_Especialidad

El mismo patrón `MERGE` (SCD 1), más simple:

- **Profesional:** `nombre_completo` = «Apellido, Nombre», `matricula` tal cual. Se compara por `id_profesional`.
- **Especialidad:** `nombre` → `nombre_especialidad`. Se compara por `id_especialidad`.

Tiempo, Horario y Estado **no están en el ETL**: son dimensiones fijas que ya cargó el script 02 y no dependen de los datos de la clínica.

### 4.4 Fact\_Turno: TRUNCATE + INSERT

**Por qué recarga completa:** el estado de un turno cambia con el tiempo (Pendiente → Atendido, Cancelado o Ausente). Rearmar la tabla entera asegura que cada turno tenga su estado actual. Con 9.000 filas la recarga tarda nada.

**Por qué no se hace lo mismo con las dimensiones:** `Fact_Turno` tiene claves foráneas que las apuntan, y SQL Server no deja hacer `TRUNCATE` de una tabla referenciada por una FK. Además se perderían las `sk_` ya asignadas.

**Paso 1, la especialidad principal (CTE):**

```sql
WITH EspPrincipal AS (
    SELECT id_profesional, MIN(id_especialidad) AS id_especialidad
    FROM Clinica.dbo.Especialidad_Profesional
    GROUP BY id_profesional
)
```

Un profesional puede tener varias especialidades (por ejemplo, Laura Ferreyra tiene Clínica Médica y Cardiología), pero el turno no dice cuál. Se toma la de menor id para que cada turno tenga **exactamente una** especialidad.

**Paso 2, el INSERT de cada turno:**

| Columna | Cómo se calcula |
| --- | --- |
| `id_turno` | `t.id` tal cual |
| `sk_tiempo` | `CONVERT(INT, CONVERT(CHAR(8), t.fecha, 112))`: el estilo 112 da `'20250315'` y se pasa a entero |
| `sk_horario` | `DATEPART(HOUR) * 100 + (DATEPART(MINUTE) / 30) * 30`: hora en HHMM redondeada hacia abajo a la media hora |
| `sk_paciente` | JOIN a `Dim_Paciente` por `id_paciente` |
| `sk_profesional` | JOIN a `Dim_Profesional` por `id_profesional` |
| `sk_especialidad` | JOIN a `EspPrincipal` y después a `Dim_Especialidad` |
| `sk_estado` | `t.estado` tal cual (coincide con la PK de `Dim_Estado`) |
| `cantidad_turnos` | `1` |
| banderas | `CASE WHEN t.estado = 2 THEN 1 ELSE 0 END`, y así con 3, 4 y 1 |
| `edad_paciente` | Misma fórmula de edad, pero contra `t.fecha` en lugar de hoy |

**Redondeo de la hora**, con división entera:

| Hora | Cálculo | `sk_horario` |
| --- | --- | --- |
| 08:00 | 8×100 + (0/30)×30 | 800 |
| 08:47 | 8×100 + (47/30)×30 = 800 + 1×30 | 830 |
| 14:29 | 14×100 + (29/30)×30 = 1400 + 0×30 | 1400 |

Así cualquier hora cae en una de las 48 filas de `Dim_Horario`.

**Dos edades distintas, a propósito:**

- `Dim_Paciente.edad` = edad **hoy**. Describe al paciente.
- `Fact_Turno.edad_paciente` = edad **el día del turno**. Es la correcta para analizar el pasado: un paciente que hoy tiene 36 tenía 34 en un turno de 2024.

### 4.5 Ejecución y verificación

Después de crear el procedimiento, el script:

1. Lo ejecuta con `EXEC dbo.sp_Cargar_DW;`.
2. Cuenta las filas de cada tabla cargada.
3. Calcula los indicadores por año en SQL puro: turnos, atendidos, cancelados, ausentes, pendientes y los 3 porcentajes.

Esa última consulta sirve de **control cruzado**: las tasas por año del cubo tienen que dar exactamente lo mismo. Los porcentajes se calculan sobre `turnos - pendientes` y `NULLIF(..., 0)` evita dividir por cero.

### 4.6 Limitaciones conocidas (conviene decirlas antes de que te pregunten)

- **Turnos sin especialidad se pierden sin aviso.** Los JOIN son internos (INNER). Si un profesional no tiene especialidad, sus turnos no entran. Control: comparar `COUNT(*)` de `Clinica.dbo.Turno` y de `Fact_Turno`.
- **Fechas fuera de 2024-2027 rompen la carga.** `Dim_Tiempo` solo cubre ese rango; la FK falla y la transacción entera se deshace.
- **Las bajas no se borran.** Los MERGE no tienen `WHEN NOT MATCHED BY SOURCE`. Un paciente borrado en el origen sigue en el DW, lo que en general es deseable (se conserva la historia).
- **No hay historial.** Con SCD 1, si un paciente cambia de obra social, todos sus turnos viejos pasan a la nueva. La mejora sería SCD 2.

## 5. Decisiones de diseño y cómo defenderlas

Cada decisión tiene una alternativa que se descartó. Si te preguntan «¿por qué así?», respondé con la columna de la derecha.

| Decisión | Alternativa descartada | Por qué se eligió |
| --- | --- | --- |
| Proceso analizado: **turnos** | Consultas médicas | El turno tiene todas las dimensiones (paciente, profesional, fecha, hora, estado). `Consulta` no tiene profesional ni turno |
| Grano: **1 fila = 1 turno** | Una fila por día y profesional (resumen) | El grano más fino permite cualquier agregación después; un resumen no se puede «desarmar» |
| **Modelo estrella** | Copo de nieve | Menos JOINs, más rápido y más claro para el usuario. La redundancia en un DW es aceptable porque casi no se escribe |
| **Claves subrogadas** `sk_` | Usar los ids del origen | El DW no depende del sistema origen y queda preparado para SCD 2 |
| Tiempo y Horario **generados por script** | Sacar las fechas de los turnos | Hay una fila para cada día aunque no haya turnos, y se agregan atributos (semestre, día de semana, franja) que el origen no tiene |
| Claves inteligentes AAAAMMDD y HHMM | IDENTITY también en Tiempo y Horario | El ETL calcula la clave con una fórmula, sin JOIN, y la clave se lee a simple vista |
| **Especialidad principal** = menor id | Tabla puente (bridge) para la relación N:N | El turno no indica la especialidad. Con una sola por turno el modelo queda como estrella pura y no se cuentan turnos dos veces |
| `Dim_Estado` con `sk` = código del origen | IDENTITY | Son 4 valores fijos; así el ETL copia el código directo |
| **Medidas bandera 1/0** | Filtrar por estado en cada consulta | Cada estado se cuenta con una simple suma; las tasas salen de dividir sumas |
| Guardar **suma de edad**, no el promedio | Guardar el promedio | El promedio no es aditivo. Suma ÷ cantidad da el promedio correcto en cualquier nivel |
| **SCD tipo 1** en dimensiones | SCD tipo 2 | Más simple y suficiente para el TP. Costo: se pierde la historia de cambios |
| **Recarga completa** de hechos | Carga incremental | Los estados cambian con el tiempo y el volumen es chico (unas 9.000 filas) |
| «Sin dato» / «Sin obra social» en vacíos | Dejar NULL | En el cubo y en Power BI los NULL aparecen como miembros en blanco |
| Tasas sobre **turnos cerrados** | Sobre el total de turnos | Un pendiente todavía no se sabe cómo termina; meterlo bajaría todas las tasas |
| Cubo **multidimensional** (SSAS) | Modelo tabular | Es lo que pide la consigna: cubo clásico con jerarquías, MDX y KPIs |

### La última decisión: quitar el DNI de las dimensiones

En el último commit se sacó la columna `dni` de `Dim_Paciente` y `Dim_Profesional`. Tampoco pasan al DW `password`, `email` ni `telefono`.

Argumentos para defenderlo:

1. **No aporta al análisis.** Nadie agrupa ni filtra turnos por DNI. Un DW lleva solo los atributos que sirven para analizar.
2. **Para identificar ya está la clave natural.** `id_paciente` e `id_profesional` permiten volver al registro del origen si hiciera falta.
3. **Minimización de datos personales.** El DW lo consultan más personas que el sistema operativo. Cuantos menos datos sensibles copie, menos riesgo (en Argentina rige la Ley 25.326 de Protección de Datos Personales, y los datos de salud son datos sensibles).
4. **Menos columnas = cubo más liviano.** Cada atributo que se procesa en el cubo ocupa espacio y tiempo de procesamiento.

## 6. Para qué sirve: cubo, indicadores y tablero

El DW por sí solo es una base de datos bien ordenada. El valor aparece cuando el cubo `Clinica` responde preguntas de negocio al instante y Power BI las muestra en un tablero.

### 6.1 Cómo se arma el cubo (Visual Studio, proyecto `Cubo_Clinica`)

| Paso | Qué se hace | Para qué |
| --- | --- | --- |
| Data Source | Conexión a `DW_Clinica` con la cuenta de servicio | Que el cubo pueda leer el DW |
| Data Source View | Se eligen las 7 tablas; las relaciones salen de las FK | Ver la estrella dentro del proyecto |
| Dimensiones | Tiempo, Horario, Paciente, Profesional, Especialidad, Estado | Los ejes por los que se analiza |
| Jerarquía Calendario | Año > Semestre > Trimestre > Mes > Fecha | Drill-down y comparar períodos |
| Attribute Relationships | Fecha → Mes → Trimestre → Semestre → Año | Mejor rendimiento y sin advertencias |
| Cubo y medidas | `Fact_Turno` como grupo de medidas, 6 medidas renombradas | Los números que se suman |
| Calculations | Los 7 miembros calculados (Parte A del archivo 04) | Tasas y comparaciones |
| KPIs | Los 4 KPIs (Parte B) | Semáforos y tendencias |
| Deploy + Process | Se publica en SSAS `localhost` y se precalcula | Que el cubo quede consultable |

**KeyColumns y NameColumn:** cada atributo tiene una clave (para identificarlo y ordenarlo) y un nombre (para mostrarlo). Mes usa `id_mes` (202503) como clave y `mes_anio_desc` («Marzo 2025») como nombre. Con `OrderBy = Key` los meses salen en orden cronológico y no alfabético.

**Medidas físicas del cubo:** Cantidad Turnos, Turnos Atendidos, Turnos Cancelados, Turnos Ausentes, Turnos Pendientes y Suma Edad. Todas con agregación Suma.

### 6.2 Miembros calculados (MDX, Parte A)

Un **miembro calculado** es una medida que no está guardada: se calcula con una fórmula en el momento de la consulta, para la combinación de dimensiones que estés mirando.

| Medida | Fórmula | Formato |
| --- | --- | --- |
| Turnos Cerrados | Atendidos + Cancelados + Ausentes | `#,##0` |
| Tasa Asistencia | Atendidos ÷ Cerrados | `0.0%` |
| Tasa Ausentismo | Ausentes ÷ Cerrados | `0.0%` |
| Tasa Cancelacion | Cancelados ÷ Cerrados | `0.0%` |
| Edad Promedio | Suma Edad ÷ Cantidad Turnos | `0.0` |
| Turnos Año Anterior | Cantidad Turnos en el mismo período del año anterior | `#,##0` |
| Variacion Interanual | (Turnos − Año Anterior) ÷ Año Anterior | `0.0%` |

Ejemplo de sintaxis:

```sql
CREATE MEMBER CURRENTCUBE.[Measures].[Tasa Ausentismo]
 AS IIF([Measures].[Turnos Cerrados] = 0, NULL,
        [Measures].[Turnos Ausentes] / [Measures].[Turnos Cerrados]),
FORMAT_STRING = "0.0%", VISIBLE = 1, DISPLAY_FOLDER = 'Indicadores';
```

- `CURRENTCUBE` = el cubo donde se define.
- `IIF(cond, a, b)` = si la condición se cumple, devuelve `a`; si no, `b`. Acá evita dividir por cero devolviendo NULL (celda vacía).
- `DISPLAY_FOLDER` = carpeta «Indicadores» que aparece en Power BI.

**ParallelPeriod**, la función del año anterior:

```sql
([Measures].[Cantidad Turnos],
 ParallelPeriod([Tiempo].[Calendario].[Año], 1, [Tiempo].[Calendario].CurrentMember))
```

`CurrentMember` es el período que se está mirando (por ejemplo, Marzo 2025). `ParallelPeriod(nivel Año, 1, ...)` devuelve el miembro en la misma posición un año antes: Marzo 2024. La tupla `(medida, miembro)` lee la cantidad de turnos de ese miembro. Funciona igual a nivel Año, Trimestre o Mes.

### 6.3 Los 4 KPIs (Parte B)

Un **KPI** en SSAS tiene 4 partes: **Value** (el valor actual), **Goal** (la meta), **Status** (semáforo: 1 verde, 0 amarillo, −1 rojo) y **Trend** (flecha: sube, igual, baja).

| KPI | Valor | Meta | Verde | Amarillo | Rojo | Mejor si... |
| --- | --- | --- | --- | --- | --- | --- |
| Asistencia | Tasa Asistencia | 75 % | ≥ 75 % | 65-75 % | < 65 % | sube |
| Ausentismo | Tasa Ausentismo | 10 % | ≤ 10 % | 10-15 % | > 15 % | baja |
| Cancelacion | Tasa Cancelacion | 12 % | ≤ 12 % | 12-18 % | > 18 % | baja |
| Crecimiento Demanda | Variacion Interanual | +10 % | ≥ 10 % | 0-10 % | < 0 % | sube |

**Status**, ejemplo de Ausentismo:

```sql
CASE
    WHEN IsEmpty(KPIValue("Ausentismo")) THEN NULL
    WHEN KPIValue("Ausentismo") <= KPIGoal("Ausentismo") THEN 1   -- verde
    WHEN KPIValue("Ausentismo") <= 0.15 THEN 0                    -- amarillo
    ELSE -1                                                         -- rojo
END
```

**Trend** compara el valor actual con `CurrentMember.PrevMember` (el período anterior del mismo nivel: el mes anterior, el año anterior). En Ausentismo la lógica está invertida: si el valor **baja**, la flecha sube, porque bajar es bueno.

**Por qué importa cada indicador:**

- **Asistencia:** qué parte de la agenda se convierte en atención real. Mide el aprovechamiento de los profesionales.
- **Ausentismo:** el turno perdido sin aviso. Es el más caro: el horario queda vacío y nadie más lo puede usar.
- **Cancelación:** si es alta, indica problemas de agenda. Con aviso previo el horario se puede reasignar.
- **Crecimiento de la demanda:** si la clínica gana pacientes. Sirve para planificar si hacen falta más profesionales. Conviene mirarlo por mes o trimestre porque 2026 todavía no terminó.

### 6.4 Consultas MDX de prueba (Parte C)

Estructura básica de una consulta MDX:

```sql
SELECT { medidas } ON COLUMNS,
       miembros de una dimensión ON ROWS
FROM [Clinica]
WHERE ( filtro );   -- el "slicer": corta el cubo
```

| Consulta | Qué responde | Función MDX clave |
| --- | --- | --- |
| 1 | Turnos y las 3 tasas por año | `[Tiempo].[Calendario].[Año].MEMBERS` |
| 2 | Ausentismo por obra social, de peor a mejor | `ORDER(..., BDESC)` |
| 3 | Turnos por especialidad × estado en 2025 | `WHERE ([Año].&[2025], ...)` |
| 4 | Valor, meta y estado de los KPIs por año | `KPIValue`, `KPIGoal`, `KPIStatus` |

Diferencias con SQL para tenerlas a mano: en MDX no hay `GROUP BY` (las dimensiones en filas y columnas ya agrupan), `WHERE` no filtra filas sino que fija una coordenada del cubo, y `&[2025]` busca el miembro por su clave.

### 6.5 El tablero de Power BI (`Clinica.pbix`)

Power BI se conecta **en vivo** al cubo (Analysis Services, «Conectar en directo»). No copia los datos: cada visual le hace una consulta al cubo, que ya tiene las medidas, la carpeta Indicadores y los KPIs.

| Página | Visuales | Pregunta que responde |
| --- | --- | --- |
| 1. Resumen | 4 tarjetas, 3 medidores con meta, líneas y columnas por mes, barras por especialidad, anillo por estado, segmentadores | ¿Cómo estamos en general? |
| 2. Ausentismo | Barras por obra social, rango etario y franja; matriz profesional × año con formato condicional | ¿Quién falta y cuándo? |
| 3. Demanda | Turnos vs. año anterior por mes, variación interanual, mapa de calor día × hora | ¿Crece la demanda y cuándo se concentra? |

**Hallazgos esperados con los datos de prueba** (sirven para la conclusión):

- Los pacientes **Particulares** (sin obra social) tienen el ausentismo más alto, cerca del 20 %.
- El rango **18-35 Jóvenes** falta más que el resto.
- Los turnos **antes de las 9:00** tienen más ausentismo.
- En **2026** el ausentismo baja (se puede plantear como efecto de los recordatorios de turno).
- La cantidad de turnos crece año a año.

Estos patrones están generados a propósito en el script 01. Si te preguntan, es legítimo decirlo: los datos son de prueba y se diseñaron para que el análisis muestre algo.

**Si el cubo falla:** la alternativa es importar las 7 tablas del DW en Power BI y crear las mismas medidas en DAX (`DIVIDE`, `CALCULATE`, `SAMEPERIODLASTYEAR`). Pero la consigna pide el cubo.

## 7. Preguntas probables con respuesta modelo

Practicá respondiendo en voz alta antes de leer la respuesta. Están ordenadas de lo más general a lo más específico.

### Conceptos

**1. ¿Qué diferencia hay entre la base `Clinica` y `DW_Clinica`?** `Clinica` es OLTP: normalizada, pensada para registrar turnos y consultas día a día. `DW_Clinica` es un DW desnormalizado en estrella, pensado para leer y agregar grandes volúmenes sin afectar al sistema operativo.

**2. ¿Cuál es el grano de la tabla de hechos?** Una fila por turno. Es el nivel más detallado posible, así cualquier agregación (por mes, por profesional, por obra social) se puede calcular después.

**3. ¿Por qué estrella y no copo de nieve?** Porque cada consulta necesita un solo JOIN por dimensión, es más rápido y más fácil de entender. La redundancia no es un problema porque el DW se carga una vez y se lee muchas.

**4. ¿Qué es una clave subrogada y por qué la usan?** Es una clave propia del DW sin significado de negocio (`sk_paciente`, IDENTITY). Independiza al DW de los ids del origen y permite tener varias versiones de un mismo paciente si se pasara a SCD 2.

**5. ¿Qué es `id_turno` en la tabla de hechos?** Una dimensión degenerada: un identificador que vive en el hecho pero no tiene tabla de dimensión porque no tiene atributos propios.

**6. ¿Qué tipo de SCD usan y qué implica?** Tipo 1: si cambia un dato se sobrescribe. Implica que no hay historia: si un paciente cambia de obra social, sus turnos viejos aparecen con la nueva. Para conservar la historia haría falta SCD 2 (una fila por versión con fechas de vigencia y la `sk_` nueva en los hechos).

**7. ¿Qué diferencia hay entre una medida aditiva y una no aditiva? Dé un ejemplo del TP.** La aditiva se puede sumar por cualquier dimensión (`cantidad_turnos`). La no aditiva no (la tasa de ausentismo o la edad promedio). Por eso se guarda la suma de edades y la tasa se calcula en el cubo como cociente de sumas.

### Modelo

**8. ¿Por qué `Dim_Tiempo` no sale de los datos de la clínica?** Se genera por script con todos los días de 2024 a 2027. Así no hay huecos (días sin turnos también existen) y se agregan atributos que el origen no tiene: semestre, trimestre, día de la semana, fin de semana.

**9. ¿Por qué `id_mes` vale 202503 y no 3?** Porque el miembro Mes tiene que ser único dentro de la jerarquía. Con 3, Marzo 2024 y Marzo 2025 serían el mismo miembro y SSAS daría error de clave duplicada.

**10. Un profesional puede tener varias especialidades. ¿Cómo lo resolvieron?** El turno no indica la especialidad, así que el ETL asigna la especialidad principal (la de menor id) con la CTE `EspPrincipal`. Así cada turno tiene una sola especialidad, el modelo queda en estrella pura y no se duplican turnos. La alternativa sería una tabla puente.

**11. ¿Por qué `HistoriaClinica` y `Consulta` no están en el DW?** Porque el proceso analizado son los turnos y `Consulta` no tiene profesional ni turno asociado. Podrían ser una segunda tabla de hechos que comparta dimensiones (constelación).

**12. ¿Por qué sacaron el DNI?** No sirve para analizar, la identificación ya la da la clave natural (`id_paciente`) y es un dato personal que conviene no replicar (minimización de datos).

**13. ¿Para qué sirven las columnas `turno_atendido`, `turno_ausente`, etc.?** Son banderas 1/0. Sumarlas da cuántos turnos hay de cada estado sin filtrar, y dividirlas da las tasas. El cubo es muy rápido sumando.

### ETL

**14. ¿Qué hace `MERGE`?** Compara destino y origen por una clave (`id_paciente`). Si existe, actualiza (`WHEN MATCHED`); si no existe, inserta (`WHEN NOT MATCHED BY TARGET`). Es la implementación de SCD 1 en una sola sentencia.

**15. ¿Por qué los hechos se borran y recargan y las dimensiones no?** Los hechos cambian de estado con el tiempo y son pocos, así que rearmarlos es simple y seguro. Las dimensiones no se pueden truncar porque las referencian FKs, y se perderían las `sk_` asignadas.

**16. ¿Qué pasa si el ETL falla a la mitad?** Nada queda a medias. Todo corre en una transacción: el CATCH hace `ROLLBACK` y el DW vuelve al estado anterior; `THROW` muestra el error.

**17. ¿Se puede ejecutar el ETL dos veces?** Sí, es idempotente. MERGE no duplica dimensiones y TRUNCATE + INSERT rearma los hechos. El resultado es el mismo.

**18. ¿Por qué hay dos edades?** `Dim_Paciente.edad` es la edad actual (describe al paciente). `Fact_Turno.edad_paciente` es la edad el día del turno, la correcta para analizar el pasado.

**19. ¿Cómo se calcula `sk_horario`?** `hora × 100 + (minutos / 30) × 30` con división entera. 08:47 da 830. Así cualquier hora cae en una de las 48 medias horas de `Dim_Horario`.

**20. ¿Qué limitaciones tiene el ETL?** Turnos de profesionales sin especialidad se pierden por el INNER JOIN; fechas fuera de 2024-2027 rompen la FK; no hay historial (SCD 1); las bajas del origen no se borran.

### Cubo e indicadores

**21. ¿Por qué las tasas se calculan sobre turnos cerrados y no sobre el total?** Porque un turno pendiente todavía no se sabe si va a ser atendido, cancelado o ausente. Incluirlo bajaría artificialmente las tres tasas.

**22. ¿Qué es un miembro calculado?** Una medida que no está guardada en el cubo: se calcula con una fórmula MDX para cada celda que se consulta. Ejemplo: `Tasa Ausentismo = Ausentes / Cerrados`.

**23. ¿Qué hace `ParallelPeriod`?** Devuelve el mismo período un año antes (Marzo 2025 → Marzo 2024). Se usa para «Turnos Año Anterior» y la variación interanual.

**24. ¿Qué partes tiene un KPI?** Value (valor), Goal (meta), Status (semáforo 1 / 0 / −1) y Trend (flecha, comparando con `PrevMember`).

**25. ¿Para qué sirven las Attribute Relationships?** Le dicen a SSAS que cada Fecha pertenece a un Mes, cada Mes a un Trimestre, etc. Mejora el procesamiento y las agregaciones, y elimina la advertencia del triángulo amarillo.

**26. ¿Cómo comprobaron que el cubo calcula bien?** Comparando las tasas por año del cubo (consulta MDX 1) con la consulta SQL del final del script 03. Tienen que coincidir.

**27. ¿Qué hay que hacer si cambian los datos de la clínica?** Ejecutar `EXEC DW_Clinica.dbo.sp_Cargar_DW;` y después reprocesar el cubo (Process). Power BI, al estar en conexión directa, muestra los datos nuevos.

**28. ¿Qué conclusiones sacaron?** Los pacientes particulares, los de 18 a 35 años y los turnos antes de las 9:00 tienen más ausentismo. En 2026 el ausentismo baja y la demanda crece año a año. Acciones posibles: recordatorios, evitar turnos muy temprano para jóvenes, sobreturnos en franjas con mucho ausentismo.

### Preguntas trampa

**29. ¿Por qué no guardaron directamente la tasa de ausentismo en el DW?** Porque no es aditiva: el promedio de tasas mensuales no da la tasa anual. Guardando las banderas, el cubo calcula la tasa correcta en cualquier nivel.

**30. Si un turno de 2024 pasa de Pendiente a Atendido, ¿el DW se entera?** Sí, en la próxima ejecución del ETL, porque `Fact_Turno` se rearma completa con el estado actual de cada turno.

## 8. Repaso de último momento y glosario

### Las 10 ideas que no te pueden faltar

1. **Flujo:** Clinica (OLTP) → ETL `sp_Cargar_DW` → DW\_Clinica (estrella) → cubo SSAS `Clinica` → Power BI.
2. **Proceso de negocio:** turnos. **Grano:** 1 fila = 1 turno.
3. **Estrella:** `Fact_Turno` + 6 dimensiones (Tiempo, Horario, Paciente, Profesional, Especialidad, Estado).
4. **Medidas:** cantidad (siempre 1), 4 banderas 1/0 por estado y la edad al día del turno.
5. **Claves:** subrogadas `sk_` con IDENTITY; inteligentes AAAAMMDD y HHMM en Tiempo y Horario; `id_turno` es dimensión degenerada.
6. **ETL:** transacción con TRY/CATCH; MERGE (SCD 1) para dimensiones; TRUNCATE + INSERT para hechos; idempotente.
7. **Especialidad principal:** la de menor id, para resolver la N:N sin tabla puente.
8. **Tasas sobre turnos cerrados** (atendidos + cancelados + ausentes); los pendientes se excluyen.
9. **4 KPIs:** Asistencia ≥ 75 %, Ausentismo ≤ 10 %, Cancelación ≤ 12 %, Crecimiento ≥ 10 %.
10. **Control:** las tasas del cubo coinciden con la consulta SQL del final del script 03.

### Números para recordar

| Dato | Valor |
| --- | --- |
| Pacientes | \~600 |
| Profesionales | 20 |
| Especialidades | 10 |
| Turnos | \~9.000 |
| Filas de `Dim_Tiempo` | 1.461 (2024-2027) |
| Filas de `Dim_Horario` | 48 (medias horas) |
| Estados | 4 (1 Pendiente, 2 Atendido, 3 Cancelado, 4 Ausente) |
| Miembros calculados | 7 |
| KPIs | 4 |

### Glosario

| Término | Definición corta |
| --- | --- |
| OLTP | Sistema transaccional, para operar el día a día |
| OLAP | Procesamiento analítico, para consultar y agregar |
| Data Warehouse | Base integrada e histórica preparada para el análisis |
| ETL | Extraer, transformar y cargar datos del origen al DW |
| Modelo estrella | Hecho en el centro, dimensiones alrededor unidas solo al hecho |
| Copo de nieve | Estrella con dimensiones normalizadas en varias tablas |
| Constelación | Varias tablas de hechos que comparten dimensiones |
| Tabla de hechos | Eventos medibles del negocio, con FKs y medidas |
| Dimensión | Contexto descriptivo para analizar los hechos |
| Grano | Qué representa una fila de la tabla de hechos |
| Medida | Valor numérico que se agrega (suma, cuenta) |
| Medida aditiva | Se puede sumar por cualquier dimensión |
| Clave subrogada | Clave propia del DW sin significado de negocio |
| Clave natural | Clave del sistema origen (`id_paciente`) |
| Dimensión degenerada | Atributo en el hecho sin tabla propia (`id_turno`) |
| SCD | Estrategia para manejar cambios en las dimensiones |
| Jerarquía | Niveles de una dimensión (Año > ... > Fecha) |
| Roll-up / Drill-down | Subir o bajar de nivel en una jerarquía |
| Slice / Dice | Filtrar por un valor de una dimensión / por varias |
| Cubo | Estructura con agregaciones precalculadas por dimensiones |
| SSAS | SQL Server Analysis Services, el motor del cubo |
| MDX | Lenguaje de consulta de cubos multidimensionales |
| Miembro calculado | Medida definida por fórmula, no almacenada |
| KPI | Indicador con valor, meta, estado y tendencia |
| Tupla | Coordenada del cubo: `(medida, miembro)` |
| `CurrentMember` | El miembro que se está mirando en la celda actual |
| `PrevMember` | El miembro anterior del mismo nivel |
| `ParallelPeriod` | El mismo período en un año (u otro nivel) anterior |
| MERGE | Sentencia SQL que inserta o actualiza en un solo paso |
| CTE (`WITH`) | Consulta con nombre que se usa dentro de otra |
| `CROSS APPLY` | Calcula una expresión por fila y la deja como columna |
| Idempotente | Ejecutarlo varias veces da el mismo resultado |
