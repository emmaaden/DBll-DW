# TP Final Base de Datos II: Cubo OLAP + Indicadores + Tablero en Power BI

**Integrantes:** Juan Pablo Carini, Carlos Emmanuel Denis
**Entrega:** 28/10/2026 a carina.cozzolino@um.edu.ar

## Qué hay en esta carpeta

| Archivo | Para qué sirve |
|---|---|
| `DER - Sistema Clinica (1).png` | DER original (base transaccional) |
| `01_OLTP_Clinica.sql` | Crea la base **Clinica** (según el DER) y la llena con datos de prueba |
| `02_DW_Clinica_Estrella.sql` | Crea el Data Warehouse **DW_Clinica** con el **modelo estrella** |
| `03_ETL_Carga_DW.sql` | Procedimiento `sp_Cargar_DW` que pasa los datos de Clinica al DW |
| `04_Calculos_e_Indicadores_MDX.txt` | Medidas calculadas, **KPIs** y consultas MDX para el cubo |
| `Diagrama_Estrella.drawio` | Diagrama estrella editable (abrir en https://app.diagrams.net) |
| `Diagrama_Estrella.svg` | El mismo diagrama, para insertar en Word |

El flujo completo es el siguiente:

```
Clinica (OLTP)  --ETL-->  DW_Clinica (estrella)  -->  Cubo OLAP (SSAS, Visual Studio)  -->  Power BI
   script 01               scripts 02 y 03              paso 4 y archivo 04                  paso 6
```

---

## Paso 0: Instalar el software (una sola vez)

1. **SQL Server 2022 Developer** (gratis): https://www.microsoft.com/es-es/sql-server/sql-server-downloads
   - Elegí la instalación **Personalizada (Custom)**. La básica no instala Analysis Services.
   - En *Feature Selection* marcá **Database Engine Services** y **Analysis Services**.
   - En *Analysis Services Configuration*:
     - **Server Mode: `Multidimensional and Data Mining Mode`** (importante: el cubo clásico es multidimensional).
     - Botón **Add Current User** para quedar como administrador de SSAS.
   - En *Database Engine Configuration*, también **Add Current User**.
2. **SSMS** (SQL Server Management Studio): https://aka.ms/ssmsfullsetup
3. **Visual Studio 2022 Community**. Después de instalarlo: *Extensiones > Administrar extensiones*, buscar
   **"Microsoft Analysis Services Projects 2022"**, instalar y reiniciar Visual Studio.
4. **Power BI Desktop** (Microsoft Store o https://powerbi.microsoft.com/desktop).

---

## Paso 1: Crear la base transaccional

En SSMS conectate a `localhost` (Database Engine, autenticación de Windows), abrí `01_OLTP_Clinica.sql` y ejecutá con **F5**.

Al final muestra cuántas filas tiene cada tabla (~600 pacientes, ~9.000 turnos, ~6.000 consultas).

> **Decisión que tomamos sobre el DER:** `Turno.estado` es un `int`, así que definimos los códigos
> **1 = Pendiente, 2 = Atendido, 3 = Cancelado, 4 = Ausente**. La dirección se guarda como
> `"Calle 123, Localidad"` para poder analizar por localidad. En `Consulta` corregimos el nombre
> `ID_HistoriaClincia` a `ID_HistoriaClinica`.

---

## Paso 2: El diagrama estrella (lo que piden antes del cubo)

Abrí `Diagrama_Estrella.drawio` en https://app.diagrams.net (Archivo > Abrir) para verlo o editarlo, y
exportalo como PNG desde *Archivo > Exportar como*. El `.svg` se puede insertar directo en Word.

### Cómo explicarlo en el informe

**Proceso de negocio analizado:** la gestión de **turnos** de la clínica.

**Tabla de hechos `Fact_Turno`.** Su **grano** es *una fila por cada turno*.

| Medida | Significado | Agregación |
|---|---|---|
| `cantidad_turnos` | siempre 1 | Suma: total de turnos |
| `turno_atendido` | 1 si se atendió | Suma: cantidad de atendidos |
| `turno_cancelado` | 1 si se canceló | Suma: cantidad de cancelados |
| `turno_ausente` | 1 si el paciente no vino | Suma: cantidad de ausentes |
| `turno_pendiente` | 1 si todavía no ocurrió | Suma: cantidad de pendientes |
| `edad_paciente` | edad del paciente el día del turno | Suma, que se usa para calcular la edad promedio |

`id_turno` es una **dimensión degenerada**, es decir, el número de turno sin una tabla propia.

**Dimensiones**, todas en relación 1 a N con el hecho:

| Dimensión | Viene de | Para analizar por... |
|---|---|---|
| `Dim_Tiempo` | `Turno.fecha` | Año > Semestre > Trimestre > Mes > Día, día de la semana |
| `Dim_Horario` | `Turno.hora` | hora del día, franja (Mañana / Mediodía / Tarde) |
| `Dim_Paciente` | `Paciente` | sexo, rango etario, obra social, localidad |
| `Dim_Profesional` | `Profesional` | profesional, matrícula |
| `Dim_Especialidad` | `Especialidad` (+ `Especialidad_Profesional`) | especialidad |
| `Dim_Estado` | `Turno.estado` | Pendiente / Atendido / Cancelado / Ausente |

**Decisiones de diseño, para defender en la presentación:**
- Las dimensiones usan **claves subrogadas** (`sk_...`) independientes de los ids del sistema origen, que se guardan aparte (`id_paciente`, etc.).
- `Dim_Tiempo` y `Dim_Horario` se generan por script. No salen del sistema origen.
- Un profesional puede tener **varias especialidades** (N:N en el DER), pero el turno no dice cuál. Por eso el ETL asigna la **especialidad principal** del profesional (la de menor id). Así el modelo queda como estrella pura, sin tabla puente.
- `HistoriaClinica` y `Consulta` **no forman parte** de esta estrella porque `Consulta` no tiene profesional ni turno. Si quisieran, podrían ser una segunda tabla de hechos (constelación).
- Las dimensiones se cargan con **SCD tipo 1** (si cambia un dato se sobrescribe).

---

## Paso 3: Crear el DW y cargarlo (ETL)

En SSMS ejecutá, en este orden:
1. `02_DW_Clinica_Estrella.sql`: crea las tablas, carga Tiempo / Horario / Estado y da permiso de lectura a SSAS.
2. `03_ETL_Carga_DW.sql`: crea `sp_Cargar_DW`, lo ejecuta y muestra los indicadores por año calculados en SQL.
   Esos números los vamos a usar después para comprobar que el cubo calcula bien.

Para ver el diagrama dentro de SSMS: en `DW_Clinica` hacé click derecho en *Database Diagrams* > *New Database Diagram* y agregá todas las tablas.

---

## Paso 4: Crear el cubo OLAP en Visual Studio

### 4.1 Proyecto
*Crear proyecto* > **Analysis Services Multidimensional Project** > nombre `Cubo_Clinica`.

### 4.2 Data Source (origen de datos)
Solution Explorer > click derecho en **Data Sources** > *New Data Source*:
- *New...* > Server name `localhost` > Windows Authentication > base **DW_Clinica** > OK.
- *Impersonation Information*: **Use the service account**.
- Nombre: `DW_Clinica`.

### 4.3 Data Source View
Click derecho en **Data Source Views** > *New Data Source View* > elegí `DW_Clinica` > pasá las **7 tablas** (`Fact_Turno` y las 6 `Dim_`) a la derecha > Finish.
Tenés que ver la estrella con las relaciones ya detectadas (salen de las FK).

### 4.4 Dimensiones
Click derecho en **Dimensions** > *New Dimension* > *Use an existing table*. Repetí el proceso para cada una:

| Tabla | Key column | Name column | Nombre final de la dimensión | Atributos para marcar |
|---|---|---|---|---|
| Dim_Tiempo | `sk_tiempo` | `fecha_desc` | **Tiempo** | anio, id_semestre, id_trimestre, id_mes, nombre_mes, nombre_dia |
| Dim_Horario | `sk_horario` | `hora_desc` | **Horario** | hora_del_dia, franja_horaria |
| Dim_Paciente | `sk_paciente` | `nombre_completo` | **Paciente** | sexo, rango_etario, obra_social, localidad |
| Dim_Profesional | `sk_profesional` | `nombre_completo` | **Profesional** | matricula |
| Dim_Especialidad | `sk_especialidad` | `nombre_especialidad` | **Especialidad** | (ninguno) |
| Dim_Estado | `sk_estado` | `estado` | **Estado** | tipo_estado |

En la **última pantalla del asistente** escribí el nombre final (por ejemplo **Tiempo**, no "Dim Tiempo"), porque las fórmulas MDX usan esos nombres.

Después abrí cada dimensión (doble click) y renombrá los atributos para que se lean bien (F2 sobre el atributo):
- **Paciente:** `Obra Social`, `Sexo`, `Rango Etario`, `Localidad`. El atributo clave se renombra a `Paciente`.
- **Especialidad:** el atributo clave se renombra a `Especialidad`.
- **Estado:** el atributo clave se renombra a `Estado`.
- **Profesional:** el atributo clave se renombra a `Profesional`.

#### Jerarquía de Tiempo (la más importante)
En la dimensión **Tiempo**:
1. Para cada atributo, en *Properties* configurá **KeyColumns** y **NameColumn** así:

   | Atributo (renombrar a) | KeyColumns | NameColumn |
   |---|---|---|
   | **Año** | anio | anio |
   | **Semestre** | id_semestre | semestre_desc |
   | **Trimestre** | id_trimestre | trimestre_desc |
   | **Mes** | id_mes | mes_anio_desc |
   | **Fecha** (el atributo clave) | sk_tiempo | fecha_desc |
   | **Nombre Dia** | dia_semana | nombre_dia |
   | **Nombre Mes** | mes | nombre_mes |

   (Para cambiar KeyColumns: click en los "..." de la propiedad > elegir la columna. Para NameColumn, lo mismo.)
   Dejá **OrderBy = Key** en todos, así los meses quedan en orden Enero, Febrero... y no alfabético.
2. Arrastrá al panel **Hierarchies**, en este orden: Año, Semestre, Trimestre, Mes, Fecha. Renombrá la jerarquía a **Calendario**.
3. Pestaña **Attribute Relationships**: tienen que quedar Fecha > Mes > Trimestre > Semestre > Año.
   Si no aparecen, click derecho > *New Attribute Relationship* y crealas. Esto evita el aviso del triángulo amarillo y mejora el rendimiento.
4. (Opcional) En las propiedades de la dimensión poné `Type = Time`.

Hacé lo mismo en **Horario** con una jerarquía `Franja > Hora` (atributo franja_horaria: KeyColumns `orden_franja`, NameColumn `franja_horaria`).

### 4.5 Cubo
Click derecho en **Cubes** > *New Cube* > *Use existing tables*:
- Measure group table: **Fact_Turno**.
- Medidas: marcá `cantidad_turnos`, `turno_atendido`, `turno_cancelado`, `turno_ausente`, `turno_pendiente`, `edad_paciente`. Desmarcá *Fact Turno Count*.
- Dimensiones: las 6 existentes.
- Nombre del cubo: **Clinica**.

En la pestaña **Cube Structure** renombrá las medidas (F2) **exactamente** así:

| Columna | Nombre de la medida |
|---|---|
| cantidad_turnos | **Cantidad Turnos** |
| turno_atendido | **Turnos Atendidos** |
| turno_cancelado | **Turnos Cancelados** |
| turno_ausente | **Turnos Ausentes** |
| turno_pendiente | **Turnos Pendientes** |
| edad_paciente | **Suma Edad** |

Dale a las medidas `FormatString = #,##0`.

### 4.6 Cálculos y KPIs
- Pestaña **Calculations** > botón **Script View** > pegá la **PARTE A** de `04_Calculos_e_Indicadores_MDX.txt` debajo de `CALCULATE;`.
- Pestaña **KPIs** > *New KPI* > cargá los 4 KPIs de la **PARTE B** del mismo archivo (Name, Value, Goal, Status, Trend).

### 4.7 Deploy y procesamiento
1. Click derecho en el proyecto > *Properties* > *Deployment* > Server: `localhost`.
2. Click derecho en el proyecto > **Deploy**. Hace el deploy y procesa el cubo.
3. Pestaña **Browser** del cubo: arrastrá medidas y dimensiones para probar. En la pestaña **KPIs** > *Browser view* ves los semáforos.
4. Compará con la consulta del final del script 03: las tasas por año tienen que dar igual.

Para probar MDX: en SSMS conectate a **Analysis Services** `localhost` > base `Base de datos ll` > *New Query* > *MDX* y ejecutá la **PARTE C**.

> Si cambian datos en `Clinica`: ejecutá `EXEC DW_Clinica.dbo.sp_Cargar_DW;` y después reprocesá el cubo (click derecho > *Process*).

---

## Paso 5: Los indicadores (explicación para el informe)

| # | Indicador | Fórmula | Meta | Semáforo |
|---|---|---|---|---|
| 1 | **Tasa de Asistencia** | Atendidos / Turnos cerrados* | ≥ 75 % | Verde ≥ 75 % · Amarillo 65-75 % · Rojo < 65 % |
| 2 | **Tasa de Ausentismo** | Ausentes / Turnos cerrados | ≤ 10 % | Verde ≤ 10 % · Amarillo 10-15 % · Rojo > 15 % |
| 3 | **Tasa de Cancelación** | Cancelados / Turnos cerrados | ≤ 12 % | Verde ≤ 12 % · Amarillo 12-18 % · Rojo > 18 % |
| 4 | **Crecimiento de la demanda** | (Turnos − Turnos mismo período año anterior) / Turnos año anterior | ≥ +10 % | Verde ≥ 10 % · Amarillo 0-10 % · Rojo < 0 % |

\* *Turnos cerrados* = Atendidos + Cancelados + Ausentes. Los pendientes se excluyen porque todavía no se sabe cómo terminan.

**Por qué importan:**
- **Asistencia** mide qué parte de la agenda se convierte en atención real (aprovechamiento de los profesionales).
- **Ausentismo** es el turno que se pierde sin aviso, el problema más caro porque el horario queda vacío y nadie más lo puede usar.
- **Cancelación**, si es alta, indica problemas de agenda. Si se avisa con tiempo, el horario se puede reasignar.
- **Crecimiento** muestra si la clínica gana demanda y sirve para planificar si hacen falta más profesionales.

Se pueden analizar **por cualquier dimensión**: por obra social, rango etario, especialidad, profesional, franja horaria, mes, etc.

**Hallazgos que deberían aparecer con los datos de prueba** (sirven para la conclusión):
- Los pacientes **Particulares** (sin obra social) tienen el ausentismo más alto (~20 %).
- El rango **18-35 Jóvenes** falta más que el resto.
- Los turnos **antes de las 9:00** tienen más ausentismo.
- En **2026** el ausentismo baja (se puede plantear como efecto de los recordatorios de turno).
- La cantidad de turnos crece año a año.

---

## Paso 6: Tablero de comando en Power BI

### 6.1 Conectarse al cubo
Power BI Desktop > *Obtener datos* > **Base de datos de SQL Server Analysis Services** >
Servidor `localhost`, Base de datos `Base de datos ll` > **Conectar en directo** > elegí el cubo **Clinica**.
Vas a ver las medidas, la carpeta *Indicadores*, los KPIs y las dimensiones del cubo.

### 6.2 Diseño sugerido

**Página 1: Resumen**
- Fila superior, 4 **tarjetas**: Cantidad Turnos · Tasa Asistencia · Tasa Ausentismo · Tasa Cancelacion.
- 3 **medidores (Gauge)**: valor = la tasa; *Valor de destino* = la meta (0,75 / 0,10 / 0,12). Usá el objetivo del KPI si aparece en la lista de campos.
- **Gráfico de líneas y columnas**: eje = Tiempo.Calendario (Mes) · columnas = Cantidad Turnos · línea = Tasa Ausentismo.
- **Barras horizontales**: Cantidad Turnos por Especialidad.
- **Anillo**: Cantidad Turnos por Estado.
- **Segmentaciones (slicers)**: Año, Especialidad, Obra Social, Sexo.

**Página 2: Análisis del ausentismo**
- Barras: Tasa Ausentismo por Obra Social, otra por Rango Etario y otra por Franja Horaria.
- Matriz: filas = Profesional, columnas = Año, valores = Tasa Asistencia, con **formato condicional**
  (*Formato condicional > Color de fondo > Reglas*: rojo < 0,65, amarillo < 0,75, verde ≥ 0,75).
  Así se reproduce el semáforo del KPI.

**Página 3: Demanda**
- Columnas agrupadas: Cantidad Turnos y Turnos Año Anterior por Mes.
- Tarjeta / KPI visual: Variacion Interanual.
- Mapa de calor (matriz): Día de la semana × Hora, con valores = Cantidad Turnos.

Consejos: usá un título por página, los mismos colores en todo el tablero (verde/amarillo/rojo solo para semáforos) y poné el logo de la UM.

### 6.3 Alternativa si el cubo da problemas: conectar Power BI al DW con DAX
*Obtener datos > SQL Server* > `localhost` / `DW_Clinica` > **Importar** las 7 tablas. Power BI arma la estrella sola. Medidas DAX:

```DAX
Cantidad Turnos   = SUM(Fact_Turno[cantidad_turnos])
Turnos Cerrados   = SUM(Fact_Turno[turno_atendido]) + SUM(Fact_Turno[turno_cancelado]) + SUM(Fact_Turno[turno_ausente])
Tasa Asistencia   = DIVIDE(SUM(Fact_Turno[turno_atendido]),  [Turnos Cerrados])
Tasa Ausentismo   = DIVIDE(SUM(Fact_Turno[turno_ausente]),   [Turnos Cerrados])
Tasa Cancelacion  = DIVIDE(SUM(Fact_Turno[turno_cancelado]), [Turnos Cerrados])
Turnos Año Anterior =
    CALCULATE([Cantidad Turnos], SAMEPERIODLASTYEAR(Dim_Tiempo[fecha]))
Variacion Interanual = DIVIDE([Cantidad Turnos] - [Turnos Año Anterior], [Turnos Año Anterior])
```
(Para `SAMEPERIODLASTYEAR`, marcá `Dim_Tiempo` como *tabla de fechas* con la columna `fecha`.)
Igual, la consigna pide el cubo, así que lo ideal es conectarse al cubo (6.1).

---

## Problemas comunes

| Error | Solución |
|---|---|
| Al hacer Deploy: *Login failed for user 'NT Service\MSSQLServerOLAPService'* | Volvé a ejecutar el final del script 02 (bloque de permisos). En el Data Source, *Impersonation* = *Use the service account*. |
| *Cannot connect to localhost* al hacer Deploy | SSAS no está instalado o está en modo **Tabular**. Reinstalá la feature en modo Multidimensional. En `services.msc` revisá que *SQL Server Analysis Services* esté iniciado. |
| *Attribute key cannot be found* al procesar | Reejecutá `sp_Cargar_DW` y procesá con *Process Full*. |
| Error de clave duplicada en Mes/Trimestre | Revisá que KeyColumns sea `id_mes` / `id_trimestre` (que incluyen el año), no `mes`. |
| Error de sintaxis MDX "member not found" | Algún nombre no coincide (medida, dimensión o jerarquía). Revisá los nombres del paso 4.4 y 4.5. |
| Acentos raros (Ã©) en los datos | Abrí el .sql en SSMS con *File > Open* (no copiar y pegar desde otro editor). |

---

## Qué entregar (checklist)

- [ ] Informe (Word/PDF) con: introducción, DER, **diagrama estrella** y su explicación (paso 2), descripción del ETL, estructura del cubo (capturas de dimensiones, jerarquía Calendario, medidas), **indicadores** (tabla del paso 5), capturas del **tablero** y conclusiones (hallazgos del paso 5).
- [ ] Scripts `.sql` (01, 02, 03).
- [ ] Proyecto de Visual Studio (`Base de datos ll`: la carpeta `C:\Users\emma2\source\repos\Base de datos ll` completa en .zip).
EPOSBASE DE DATOS LL` COMPLETA EN .ZIP).
- [ ] Archivo de Power BI (`.pbix`).
