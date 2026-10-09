/* =====================================================================
   TP FINAL - BASE DE DATOS II
   Script 02: Data Warehouse "DW_Clinica" - MODELO ESTRELLA

   Hecho:       Fact_Turno       (grano: 1 fila = 1 turno)
   Dimensiones: Dim_Tiempo, Dim_Horario, Dim_Paciente,
                Dim_Profesional, Dim_Especialidad, Dim_Estado

   Ejecutar DESPUES del script 01.
   ===================================================================== */

USE master;
GO

IF DB_ID('DW_Clinica') IS NOT NULL
BEGIN
    ALTER DATABASE DW_Clinica SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE DW_Clinica;
END
GO

CREATE DATABASE DW_Clinica;
GO

USE DW_Clinica;
GO

/* ---------------------------------------------------------------------
   DIMENSIONES
   --------------------------------------------------------------------- */

-- Dimension Tiempo (una fila por dia). Clave inteligente AAAAMMDD.
CREATE TABLE Dim_Tiempo (
    sk_tiempo         INT          NOT NULL PRIMARY KEY,   -- 20250315
    fecha             DATE         NOT NULL,
    fecha_desc        VARCHAR(10)  NOT NULL,               -- '15/03/2025'
    anio              INT          NOT NULL,
    id_semestre       INT          NOT NULL,               -- 20251
    semestre_desc     VARCHAR(20)  NOT NULL,               -- 'S1 2025'
    id_trimestre      INT          NOT NULL,               -- 20251
    trimestre_desc    VARCHAR(20)  NOT NULL,               -- 'T1 2025'
    id_mes            INT          NOT NULL,               -- 202503
    mes               INT          NOT NULL,               -- 3
    nombre_mes        VARCHAR(20)  NOT NULL,               -- 'Marzo'
    mes_anio_desc     VARCHAR(20)  NOT NULL,               -- 'Marzo 2025'
    semana_anio       INT          NOT NULL,
    dia_mes           INT          NOT NULL,
    dia_semana        INT          NOT NULL,               -- 1 = Lunes ... 7 = Domingo
    nombre_dia        VARCHAR(20)  NOT NULL,
    es_fin_de_semana  VARCHAR(2)   NOT NULL                -- 'Si' / 'No'
);

-- Dimension Horario (franjas de 30 minutos). Clave HHMM.
CREATE TABLE Dim_Horario (
    sk_horario      INT          NOT NULL PRIMARY KEY,     -- 830 = 08:30
    hora            TIME         NOT NULL,
    hora_desc       VARCHAR(5)   NOT NULL,                 -- '08:30'
    hora_del_dia    INT          NOT NULL,                 -- 8
    franja_horaria  VARCHAR(20)  NOT NULL,                 -- 'Mañana'
    orden_franja    INT          NOT NULL
);

CREATE TABLE Dim_Paciente (
    sk_paciente       INT IDENTITY(1,1) PRIMARY KEY,
    id_paciente       INT          NOT NULL UNIQUE,        -- clave del sistema origen
    dni               VARCHAR(30)  NOT NULL,
    nombre_completo   VARCHAR(255) NOT NULL,
    sexo              VARCHAR(20)  NOT NULL,
    fecha_nacimiento  DATE         NOT NULL,
    edad              INT          NOT NULL,
    rango_etario      VARCHAR(30)  NOT NULL,
    obra_social       VARCHAR(100) NOT NULL,
    localidad         VARCHAR(100) NOT NULL
);

CREATE TABLE Dim_Profesional (
    sk_profesional   INT IDENTITY(1,1) PRIMARY KEY,
    id_profesional   INT          NOT NULL UNIQUE,
    dni              VARCHAR(30)  NOT NULL,
    nombre_completo  VARCHAR(255) NOT NULL,
    matricula        VARCHAR(50)  NOT NULL
);

CREATE TABLE Dim_Especialidad (
    sk_especialidad      INT IDENTITY(1,1) PRIMARY KEY,
    id_especialidad      INT          NOT NULL UNIQUE,
    nombre_especialidad  VARCHAR(255) NOT NULL
);

CREATE TABLE Dim_Estado (
    sk_estado      INT          NOT NULL PRIMARY KEY,      -- igual al codigo del origen
    estado         VARCHAR(20)  NOT NULL,
    tipo_estado    VARCHAR(20)  NOT NULL                   -- 'Abierto' / 'Cerrado'
);

/* ---------------------------------------------------------------------
   TABLA DE HECHOS
   --------------------------------------------------------------------- */
CREATE TABLE Fact_Turno (
    id_turno          INT NOT NULL PRIMARY KEY,            -- dimension degenerada
    sk_tiempo         INT NOT NULL REFERENCES Dim_Tiempo(sk_tiempo),
    sk_horario        INT NOT NULL REFERENCES Dim_Horario(sk_horario),
    sk_paciente       INT NOT NULL REFERENCES Dim_Paciente(sk_paciente),
    sk_profesional    INT NOT NULL REFERENCES Dim_Profesional(sk_profesional),
    sk_especialidad   INT NOT NULL REFERENCES Dim_Especialidad(sk_especialidad),
    sk_estado         INT NOT NULL REFERENCES Dim_Estado(sk_estado),
    -- Medidas
    cantidad_turnos   INT NOT NULL,     -- siempre 1
    turno_atendido    INT NOT NULL,     -- 1/0
    turno_cancelado   INT NOT NULL,     -- 1/0
    turno_ausente     INT NOT NULL,     -- 1/0
    turno_pendiente   INT NOT NULL,     -- 1/0
    edad_paciente     INT NOT NULL      -- edad al momento del turno
);
GO

/* ---------------------------------------------------------------------
   CARGA DE DIMENSIONES FIJAS (Tiempo, Horario, Estado)
   --------------------------------------------------------------------- */

-- Dim_Tiempo: 01/01/2024 a 31/12/2027
;WITH Dias AS (
    SELECT TOP (DATEDIFF(DAY, '20240101', '20271231') + 1)
           DATEADD(DAY, CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS INT) - 1,
                   CAST('20240101' AS DATE)) AS fecha
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO Dim_Tiempo
SELECT CONVERT(INT, CONVERT(CHAR(8), d.fecha, 112)),
       d.fecha,
       CONVERT(VARCHAR(10), d.fecha, 103),
       YEAR(d.fecha),
       YEAR(d.fecha) * 10 + s.semestre,
       'S' + CAST(s.semestre AS VARCHAR(1)) + ' ' + CAST(YEAR(d.fecha) AS VARCHAR(4)),
       YEAR(d.fecha) * 10 + DATEPART(QUARTER, d.fecha),
       'T' + CAST(DATEPART(QUARTER, d.fecha) AS VARCHAR(1)) + ' ' + CAST(YEAR(d.fecha) AS VARCHAR(4)),
       YEAR(d.fecha) * 100 + MONTH(d.fecha),
       MONTH(d.fecha),
       m.nombre_mes,
       m.nombre_mes + ' ' + CAST(YEAR(d.fecha) AS VARCHAR(4)),
       DATEPART(ISO_WEEK, d.fecha),
       DAY(d.fecha),
       x.dsem,
       CHOOSE(x.dsem, 'Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'),
       CASE WHEN x.dsem >= 6 THEN 'Si' ELSE 'No' END
FROM Dias d
CROSS APPLY (SELECT DATEDIFF(DAY, CAST('19000101' AS DATE), d.fecha) % 7 + 1 AS dsem) x  -- 01/01/1900 fue lunes
CROSS APPLY (SELECT CASE WHEN MONTH(d.fecha) <= 6 THEN 1 ELSE 2 END AS semestre) s
CROSS APPLY (SELECT CHOOSE(MONTH(d.fecha), 'Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio',
                           'Agosto','Septiembre','Octubre','Noviembre','Diciembre') AS nombre_mes) m;

-- Dim_Horario: 48 franjas de 30 minutos
;WITH Slots AS (
    SELECT TOP (48) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS INT) - 1 AS n
    FROM sys.all_objects
)
INSERT INTO Dim_Horario (sk_horario, hora, hora_desc, hora_del_dia, franja_horaria, orden_franja)
SELECT (n / 2) * 100 + (n % 2) * 30,
       DATEADD(MINUTE, n * 30, CAST('00:00' AS TIME)),
       RIGHT('0' + CAST(n / 2 AS VARCHAR(2)), 2) + ':' + CASE WHEN n % 2 = 0 THEN '00' ELSE '30' END,
       n / 2,
       CASE WHEN n / 2 < 6  THEN 'Madrugada'
            WHEN n / 2 < 12 THEN 'Mañana'
            WHEN n / 2 < 14 THEN 'Mediodía'
            WHEN n / 2 < 20 THEN 'Tarde'
            ELSE 'Noche' END,
       CASE WHEN n / 2 < 6  THEN 1
            WHEN n / 2 < 12 THEN 2
            WHEN n / 2 < 14 THEN 3
            WHEN n / 2 < 20 THEN 4
            ELSE 5 END
FROM Slots;

-- Dim_Estado
INSERT INTO Dim_Estado (sk_estado, estado, tipo_estado) VALUES
 (1, 'Pendiente', 'Abierto'),
 (2, 'Atendido',  'Cerrado'),
 (3, 'Cancelado', 'Cerrado'),
 (4, 'Ausente',   'Cerrado');
GO

/* ---------------------------------------------------------------------
   PERMISO PARA ANALYSIS SERVICES
   El cubo lee el DW con la cuenta del servicio de SSAS. Sin esto, al
   procesar el cubo aparece "Login failed for user NT Service\MSSQLServerOLAPService".
   (Si instalaste una instancia con nombre, el servicio es NT Service\MSOLAP$NOMBRE)
   --------------------------------------------------------------------- */
BEGIN TRY
    IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'NT Service\MSSQLServerOLAPService')
        CREATE LOGIN [NT Service\MSSQLServerOLAPService] FROM WINDOWS;

    IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'NT Service\MSSQLServerOLAPService')
        CREATE USER [NT Service\MSSQLServerOLAPService] FOR LOGIN [NT Service\MSSQLServerOLAPService];

    ALTER ROLE db_datareader ADD MEMBER [NT Service\MSSQLServerOLAPService];
    PRINT 'Permiso de lectura otorgado al servicio de Analysis Services.';
END TRY
BEGIN CATCH
    PRINT 'No se pudo dar permiso a SSAS (¿esta instalado Analysis Services?): ' + ERROR_MESSAGE();
END CATCH;
GO

SELECT 'Dim_Tiempo' AS tabla, COUNT(*) AS filas FROM Dim_Tiempo
UNION ALL SELECT 'Dim_Horario', COUNT(*) FROM Dim_Horario
UNION ALL SELECT 'Dim_Estado',  COUNT(*) FROM Dim_Estado;
GO
