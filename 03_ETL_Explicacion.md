# Explicación del ETL — `03_ETL_Carga_DW.sql`

El script lleva los datos de la base operativa **`Clinica`** (script 01) al data warehouse **`DW_Clinica`** (modelo estrella del script 02). Hace las tres fases de un ETL:

- **E**xtrae los datos de `Clinica`.
- **T**ransforma los datos dentro del mismo `SELECT`.
- **C**arga (Load) el resultado en `DW_Clinica`.

---

## Índice

1. [Estructura general](#1-estructura-general)
2. [Dim_Paciente](#2-dim_paciente)
3. [Dim_Profesional](#3-dim_profesional)
4. [Dim_Especialidad](#4-dim_especialidad)
5. [Dimensiones fijas (no están en el ETL)](#5-dimensiones-fijas-no-están-en-el-etl)
6. [Fact_Turno](#6-fact_turno)
7. [Ejecución y verificación](#7-ejecución-y-verificación)
8. [Detalles a tener en cuenta](#8-detalles-a-tener-en-cuenta)

---

## 1. Estructura general

El script crea el procedimiento almacenado **`dbo.sp_Cargar_DW`**. Al final lo ejecuta y corre dos consultas de verificación.

Dentro del procedimiento:

- **`@Hoy`** guarda la fecha actual. Se usa para calcular la edad del paciente.
- **Todo corre dentro de una transacción con `TRY/CATCH`.** Se carga todo o no se carga nada. Si algo falla, el `ROLLBACK` deja el DW como estaba, y el `THROW` muestra el error original.
- **Se puede ejecutar todas las veces que se quiera.** Las dimensiones se actualizan sin duplicarse y la tabla de hechos se vuelve a armar desde cero.

```sql
BEGIN TRY
    BEGIN TRANSACTION;
    -- 1) Dim_Paciente      (MERGE)
    -- 2) Dim_Profesional   (MERGE)
    -- 3) Dim_Especialidad  (MERGE)
    -- 4) Fact_Turno        (TRUNCATE + INSERT)
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
```

**El orden importa:** primero se cargan las **dimensiones** y después los **hechos**. Para guardar un turno, el ETL necesita las claves sustitutas (`sk_...`) de paciente, profesional y especialidad, y esas claves recién existen una vez cargadas las dimensiones.

---

## 2. Dim_Paciente

Usa un `MERGE` que compara cada paciente del origen con el DW a través de `id_paciente` (la clave del sistema origen):

- **Si ya existe** (`WHEN MATCHED`), actualiza sus datos.
- **Si no existe** (`WHEN NOT MATCHED BY TARGET`), lo inserta. `sk_paciente` lo genera solo el `IDENTITY`.

Esto es una **SCD tipo 1** (dimensión lentamente cambiante de tipo 1): cuando un dato cambia, se pisa el valor viejo y no queda historial. Por ejemplo, si un paciente cambia de obra social, en el DW queda solo la nueva.

### Transformaciones

| Campo en el DW | Cómo se calcula |
|---|---|
| `nombre_completo` | `apellido + ', ' + nombre`, por ejemplo "Pérez, Juan" |
| `sexo` | Recorta espacios con `LTRIM`/`RTRIM`. Si queda vacío o es NULL, pone `'Sin dato'` |
| `fecha_nacimiento` | Se copia tal cual |
| `edad` | Edad exacta a hoy (ver abajo) |
| `rango_etario` | Agrupa la edad en rangos (ver abajo) |
| `obra_social` | Si está vacía, pone `'Sin obra social'` |
| `localidad` | La saca de `direccion`: toma lo que viene **después de la primera coma**. "Av. Mitre 123, Quilmes" da "Quilmes". Si no hay coma, pone `'Sin dato'` |

### Cálculo de la edad

```sql
CROSS APPLY (SELECT DATEDIFF(YEAR, p.fechaNacimiento, @Hoy)
                  - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, p.fechaNacimiento, @Hoy), p.fechaNacimiento) > @Hoy
                         THEN 1 ELSE 0 END AS edad) e
```

`DATEDIFF(YEAR, ...)` solo resta años; no sabe si ya pasó el cumpleaños. Por eso la fórmula le suma esa diferencia de años a la fecha de nacimiento. Si el resultado cae después de hoy, todavía no cumplió, y le resta 1.

> Ejemplo: nació el 20/11/2000 y hoy es 28/10/2026.
> `DATEDIFF(YEAR)` = 26, pero el 20/11/2026 todavía no llegó, entonces la edad es **25**.

El `CROSS APPLY` permite calcular la edad una sola vez y reusarla en `edad` y en `rango_etario`.

### Rangos etarios

| Edad | Rango |
|---|---|
| 0 a 12 | `0-12 Niños` |
| 13 a 17 | `13-17 Adolescentes` |
| 18 a 35 | `18-35 Jóvenes` |
| 36 a 59 | `36-59 Adultos` |
| 60 o más | `60+ Adultos mayores` |

### ¿Por qué reemplazar vacíos por "Sin dato"?

Es una práctica común en un DW. En el cubo y en Power BI los vacíos aparecen como un miembro con nombre ("Sin dato", "Sin obra social") en lugar de un valor en blanco, y se pueden filtrar y contar como cualquier otro valor.

---

## 3. Dim_Profesional

Es el mismo `MERGE` tipo 1, más simple:

- `nombre_completo` = "Apellido, Nombre"
- `matricula` se copia tal cual

```sql
MERGE dbo.Dim_Profesional AS d
USING (
    SELECT pr.ID, pr.apellido + ', ' + pr.nombre AS nombre_completo, pr.matricula
    FROM Clinica.dbo.Profesional pr
) AS s
ON d.id_profesional = s.ID
WHEN MATCHED THEN UPDATE SET ...
WHEN NOT MATCHED BY TARGET THEN INSERT ...
```

---

## 4. Dim_Especialidad

Otro `MERGE`. Copia `id` → `id_especialidad` y `nombre` → `nombre_especialidad`.

---

## 5. Dimensiones fijas (no están en el ETL)

`Dim_Tiempo`, `Dim_Horario` y `Dim_Estado` **no se cargan en el ETL** porque son **dimensiones fijas**: ya las carga el script 02 y no dependen de los datos de la clínica.

| Dimensión | Contenido | Clave |
|---|---|---|
| `Dim_Tiempo` | Un día por fila, del 01/01/2024 al 31/12/2027 | `AAAAMMDD` (ej. `20250315`) |
| `Dim_Horario` | 48 franjas de 30 minutos | `HHMM` (ej. `830` = 08:30) |
| `Dim_Estado` | 1 Pendiente, 2 Atendido, 3 Cancelado, 4 Ausente | Igual al código del origen |

---

## 6. Fact_Turno

### Recarga completa

Primero hace `TRUNCATE TABLE dbo.Fact_Turno` y después la vuelve a llenar. El motivo es que **el estado de un turno cambia con el tiempo**: un turno cargado como "Pendiente" después pasa a "Atendido", "Cancelado" o "Ausente". Reconstruir la tabla entera garantiza que cada turno tenga su estado actual.

> Las dimensiones no se pueden truncar así porque `Fact_Turno` tiene claves foráneas que las referencian. Por eso con ellas se usa `MERGE`.

### Especialidad del turno (`Turno.id_especialidad`)

En el origen, un profesional puede tener **varias especialidades** (relación N:N en `Especialidad_Profesional`). Por eso la tabla `Turno` guarda **con qué especialidad se atendió** el paciente, y el ETL la toma directo de ahí:

```sql
JOIN dbo.Dim_Especialidad de ON de.id_especialidad = t.id_especialidad
```

En el OLTP, `Turno.id_especialidad` tiene una **FK compuesta** `(id_especialidad, id_profesional)` → `Especialidad_Profesional`. Así la base no deja guardar un turno con una especialidad que el profesional no tiene.

> Antes el turno no tenía especialidad y el ETL suponía la "principal" del profesional (la de menor id). Con eso, los turnos de Cardiología de Laura Ferreyra y los de Pediatría de Mariela Castillo quedaban contados como Clínica Médica. Ahora cada turno queda en su especialidad real.

### Cómo se arma cada fila

**Grano:** 1 fila = 1 turno.

| Columna | De dónde sale |
|---|---|
| `id_turno` | El id del turno en el origen. Es una **dimensión degenerada**: un dato del hecho que no tiene tabla propia |
| `sk_tiempo` | La fecha convertida al entero `AAAAMMDD` con el estilo 112. 15/03/2025 → `20250315`, que es la PK de `Dim_Tiempo` |
| `sk_horario` | La hora **redondeada para abajo a la media hora**, en formato `HHMM` (ver abajo) |
| `sk_paciente` | `JOIN` a `Dim_Paciente` por `id_paciente` |
| `sk_profesional` | `JOIN` a `Dim_Profesional` por `id_profesional` |
| `sk_especialidad` | `JOIN` a `Dim_Especialidad` por `Turno.id_especialidad` |
| `sk_estado` | El código de estado tal cual (la PK de `Dim_Estado` es igual al código del origen) |
| `cantidad_turnos` | Siempre `1`. Al sumarla da el total de turnos |
| `turno_atendido` | `1` si estado = 2, si no `0` |
| `turno_cancelado` | `1` si estado = 3, si no `0` |
| `turno_ausente` | `1` si estado = 4, si no `0` |
| `turno_pendiente` | `1` si estado = 1, si no `0` |
| `edad_paciente` | La edad **a la fecha del turno** (no a hoy) |

### Redondeo de la hora

```sql
DATEPART(HOUR, t.hora) * 100 + (DATEPART(MINUTE, t.hora) / 30) * 30
```

| Hora del turno | Cálculo | `sk_horario` |
|---|---|---|
| 08:00 | `8*100 + (0/30)*30` | `800` |
| 08:47 | `8*100 + (47/30)*30` = `800 + 1*30` | `830` |
| 14:29 | `14*100 + (29/30)*30` = `1400 + 0*30` | `1400` |

Como `/` entre enteros es división entera, `47/30` da `1` y `29/30` da `0`. Así cualquier hora cae en una de las 48 filas de `Dim_Horario`.

### Medidas tipo bandera (1/0)

Cada turno tiene un `1` en la columna de su estado y `0` en las demás. Sumarlas da cuántos turnos hay de cada estado, sin necesidad de filtrar:

| id_turno | estado | cantidad | atendido | cancelado | ausente | pendiente |
|---|---|---|---|---|---|---|
| 101 | Atendido | 1 | 1 | 0 | 0 | 0 |
| 102 | Ausente | 1 | 0 | 0 | 1 | 0 |
| 103 | Pendiente | 1 | 0 | 0 | 0 | 1 |
| **Total** | | **3** | **1** | **0** | **1** | **1** |

### Dos edades distintas, a propósito

- **`Dim_Paciente.edad`** es la edad **actual**. Sirve para describir al paciente hoy.
- **`Fact_Turno.edad_paciente`** es la edad **que tenía cuando fue al turno**. Es la correcta para analizar, por ejemplo, la edad promedio de quienes se atendieron en 2024.

---

## 7. Ejecución y verificación

Después de crear el procedimiento, el script:

1. **Ejecuta la carga** con `EXEC dbo.sp_Cargar_DW;`.
2. **Cuenta las filas** de `Dim_Paciente`, `Dim_Profesional`, `Dim_Especialidad` y `Fact_Turno`, para ver que se cargaron.
3. **Calcula los indicadores por año** directamente en SQL. Son los mismos que después calcula el cubo, así que sirven para comparar resultados:

| Indicador | Fórmula |
|---|---|
| Turnos | `SUM(cantidad_turnos)` |
| Atendidos / Cancelados / Ausentes / Pendientes | `SUM` de cada bandera |
| % Asistencia | `atendidos / (turnos - pendientes) * 100` |
| % Ausentismo | `ausentes / (turnos - pendientes) * 100` |
| % Cancelación | `cancelados / (turnos - pendientes) * 100` |

Los porcentajes se calculan **sobre los turnos ya resueltos** (`turnos - pendientes`), porque un turno pendiente todavía no se sabe si va a ser asistencia o ausencia. `NULLIF(..., 0)` evita la división por cero.

---

## 8. Detalles a tener en cuenta

Esto no son errores del script; son consecuencias de cómo está armado, y conviene conocerlas para la defensa del TP.

- **Los `JOIN` son internos.** Si un turno no encontrara su paciente, profesional o especialidad en las dimensiones, no entraría a `Fact_Turno` y el script no mostraría ningún error. Con las FK del OLTP (`Turno.id_especialidad` es `NOT NULL` y tiene FK) no debería pasar, pero para comprobarlo se compara:

  ```sql
  SELECT COUNT(*) FROM Clinica.dbo.Turno;
  SELECT COUNT(*) FROM DW_Clinica.dbo.Fact_Turno;
  ```

- **Las fechas tienen que estar entre 2024 y 2027.** `Dim_Tiempo` solo cubre ese rango. Un turno fuera de él hace fallar la clave foránea, y la transacción entera se deshace.

- **Las bajas no se borran.** Los `MERGE` no tienen `WHEN NOT MATCHED BY SOURCE`. Si se elimina un paciente en el origen, sigue en `Dim_Paciente`. En un DW esto suele ser lo deseado, porque se conserva la historia.

- **No hay historial de cambios.** Al ser SCD tipo 1, si se pidiera analizar con la obra social que tenía el paciente en cada momento, haría falta una SCD tipo 2 (una fila nueva por cada cambio, con fechas de vigencia).
