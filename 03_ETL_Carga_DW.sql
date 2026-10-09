/* =====================================================================
   TP FINAL - BASE DE DATOS II
   Script 03: ETL  (Clinica  -->  DW_Clinica)

   Crea el procedimiento dbo.sp_Cargar_DW y lo ejecuta.
   - Dimensiones: MERGE (SCD tipo 1: inserta nuevos, actualiza cambios)
   - Hechos:      recarga completa (el estado de un turno cambia con el
                  tiempo: Pendiente -> Atendido / Cancelado / Ausente)

   Decision de diseño: un profesional puede tener varias especialidades
   (relacion N:N) pero el turno no indica cual. Se toma la especialidad
   PRINCIPAL del profesional = la de menor id en Especialidad_Profesional.

   Se puede volver a ejecutar cuantas veces se quiera.
   ===================================================================== */

USE DW_Clinica;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Cargar_DW
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Hoy DATE = CAST(GETDATE() AS DATE);

    BEGIN TRY
        BEGIN TRANSACTION;

        /* ---------- Dim_Paciente ---------- */
        MERGE dbo.Dim_Paciente AS d
        USING (
            SELECT p.id,
                   p.dni,
                   p.apellido + ', ' + p.nombre AS nombre_completo,
                   ISNULL(NULLIF(LTRIM(RTRIM(p.sexo)), ''), 'Sin dato') AS sexo,
                   p.fechaNacimiento,
                   e.edad,
                   CASE WHEN e.edad <= 12 THEN '0-12 Niños'
                        WHEN e.edad <= 17 THEN '13-17 Adolescentes'
                        WHEN e.edad <= 35 THEN '18-35 Jóvenes'
                        WHEN e.edad <= 59 THEN '36-59 Adultos'
                        ELSE '60+ Adultos mayores' END AS rango_etario,
                   ISNULL(NULLIF(LTRIM(RTRIM(p.obra_social)), ''), 'Sin obra social') AS obra_social,
                   CASE WHEN CHARINDEX(',', p.direccion) > 0
                        THEN LTRIM(RTRIM(SUBSTRING(p.direccion, CHARINDEX(',', p.direccion) + 1, 255)))
                        ELSE 'Sin dato' END AS localidad
            FROM Clinica.dbo.Paciente p
            CROSS APPLY (SELECT DATEDIFF(YEAR, p.fechaNacimiento, @Hoy)
                              - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, p.fechaNacimiento, @Hoy), p.fechaNacimiento) > @Hoy
                                     THEN 1 ELSE 0 END AS edad) e
        ) AS s
        ON d.id_paciente = s.id
        WHEN MATCHED THEN UPDATE SET
            d.dni = s.dni, d.nombre_completo = s.nombre_completo, d.sexo = s.sexo,
            d.fecha_nacimiento = s.fechaNacimiento, d.edad = s.edad, d.rango_etario = s.rango_etario,
            d.obra_social = s.obra_social, d.localidad = s.localidad
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (id_paciente, dni, nombre_completo, sexo, fecha_nacimiento, edad, rango_etario, obra_social, localidad)
            VALUES (s.id, s.dni, s.nombre_completo, s.sexo, s.fechaNacimiento, s.edad, s.rango_etario, s.obra_social, s.localidad);

        /* ---------- Dim_Profesional ---------- */
        MERGE dbo.Dim_Profesional AS d
        USING (
            SELECT pr.ID, pr.dni, pr.apellido + ', ' + pr.nombre AS nombre_completo, pr.matricula
            FROM Clinica.dbo.Profesional pr
        ) AS s
        ON d.id_profesional = s.ID
        WHEN MATCHED THEN UPDATE SET
            d.dni = s.dni, d.nombre_completo = s.nombre_completo, d.matricula = s.matricula
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (id_profesional, dni, nombre_completo, matricula)
            VALUES (s.ID, s.dni, s.nombre_completo, s.matricula);

        /* ---------- Dim_Especialidad ---------- */
        MERGE dbo.Dim_Especialidad AS d
        USING (SELECT id, nombre FROM Clinica.dbo.Especialidad) AS s
        ON d.id_especialidad = s.id
        WHEN MATCHED THEN UPDATE SET d.nombre_especialidad = s.nombre
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (id_especialidad, nombre_especialidad) VALUES (s.id, s.nombre);

        /* ---------- Fact_Turno ---------- */
        TRUNCATE TABLE dbo.Fact_Turno;

        ;WITH EspPrincipal AS (
            SELECT id_profesional, MIN(id_especialidad) AS id_especialidad
            FROM Clinica.dbo.Especialidad_Profesional
            GROUP BY id_profesional
        )
        INSERT INTO dbo.Fact_Turno (id_turno, sk_tiempo, sk_horario, sk_paciente, sk_profesional,
                                    sk_especialidad, sk_estado, cantidad_turnos, turno_atendido,
                                    turno_cancelado, turno_ausente, turno_pendiente, edad_paciente)
        SELECT t.id,
               CONVERT(INT, CONVERT(CHAR(8), t.fecha, 112)),                            -- AAAAMMDD
               DATEPART(HOUR, t.hora) * 100 + (DATEPART(MINUTE, t.hora) / 30) * 30,     -- HHMM redondeado a 30'
               dp.sk_paciente,
               dpr.sk_profesional,
               de.sk_especialidad,
               t.estado,
               1,
               CASE WHEN t.estado = 2 THEN 1 ELSE 0 END,
               CASE WHEN t.estado = 3 THEN 1 ELSE 0 END,
               CASE WHEN t.estado = 4 THEN 1 ELSE 0 END,
               CASE WHEN t.estado = 1 THEN 1 ELSE 0 END,
               DATEDIFF(YEAR, dp.fecha_nacimiento, t.fecha)
                 - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, dp.fecha_nacimiento, t.fecha), dp.fecha_nacimiento) > t.fecha
                        THEN 1 ELSE 0 END
        FROM Clinica.dbo.Turno t
        JOIN dbo.Dim_Paciente     dp  ON dp.id_paciente     = t.id_paciente
        JOIN dbo.Dim_Profesional  dpr ON dpr.id_profesional = t.id_profesional
        JOIN EspPrincipal         ep  ON ep.id_profesional  = t.id_profesional
        JOIN dbo.Dim_Especialidad de  ON de.id_especialidad = ep.id_especialidad;

        COMMIT TRANSACTION;
        PRINT 'Carga del DW finalizada correctamente.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

/* Ejecutar la carga */
EXEC dbo.sp_Cargar_DW;
GO

/* ---------------------------------------------------------------------
   VERIFICACION: filas por tabla y una consulta de ejemplo sobre la estrella
   --------------------------------------------------------------------- */
SELECT 'Dim_Paciente' AS tabla, COUNT(*) AS filas FROM dbo.Dim_Paciente
UNION ALL SELECT 'Dim_Profesional',  COUNT(*) FROM dbo.Dim_Profesional
UNION ALL SELECT 'Dim_Especialidad', COUNT(*) FROM dbo.Dim_Especialidad
UNION ALL SELECT 'Fact_Turno',       COUNT(*) FROM dbo.Fact_Turno;

-- Indicadores por año (lo mismo que despues calcula el cubo)
SELECT t.anio,
       SUM(f.cantidad_turnos)  AS turnos,
       SUM(f.turno_atendido)   AS atendidos,
       SUM(f.turno_cancelado)  AS cancelados,
       SUM(f.turno_ausente)    AS ausentes,
       SUM(f.turno_pendiente)  AS pendientes,
       CAST(100.0 * SUM(f.turno_atendido)  / NULLIF(SUM(f.cantidad_turnos - f.turno_pendiente), 0) AS DECIMAL(5,1)) AS pct_asistencia,
       CAST(100.0 * SUM(f.turno_ausente)   / NULLIF(SUM(f.cantidad_turnos - f.turno_pendiente), 0) AS DECIMAL(5,1)) AS pct_ausentismo,
       CAST(100.0 * SUM(f.turno_cancelado) / NULLIF(SUM(f.cantidad_turnos - f.turno_pendiente), 0) AS DECIMAL(5,1)) AS pct_cancelacion
FROM dbo.Fact_Turno f
JOIN dbo.Dim_Tiempo t ON t.sk_tiempo = f.sk_tiempo
GROUP BY t.anio
ORDER BY t.anio;
GO
