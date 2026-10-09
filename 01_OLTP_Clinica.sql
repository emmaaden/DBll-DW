/* =====================================================================
   TP FINAL - BASE DE DATOS II
   Script 01: Base transaccional (OLTP) "Clinica" + datos de prueba
   Basado en el DER "Sistema Clinica"
   Integrantes: Juan Pablo Carini, Carlos Emmanuel Denis

   Ejecutar completo en SSMS (F5). Tarda unos segundos.
   Genera: 10 especialidades, 20 profesionales, 600 pacientes,
           ~9.000 turnos (2024 a 2026) y las consultas de los turnos atendidos.

   Codigos de Turno.estado (definidos por el grupo):
       1 = Pendiente   2 = Atendido   3 = Cancelado   4 = Ausente
   ===================================================================== */

USE master;
GO

IF DB_ID('Clinica') IS NOT NULL
BEGIN
    ALTER DATABASE Clinica SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Clinica;
END
GO

CREATE DATABASE Clinica;
GO

USE Clinica;
GO

/* ---------------------------------------------------------------------
   1. TABLAS (segun el DER)
   --------------------------------------------------------------------- */
CREATE TABLE Paciente (
    id               INT IDENTITY(1,1) PRIMARY KEY,
    dni              VARCHAR(30)  NOT NULL,
    nombre           VARCHAR(255) NOT NULL,
    apellido         VARCHAR(255) NOT NULL,
    password         VARCHAR(255) NOT NULL,
    direccion        VARCHAR(255) NULL,      -- formato: 'Calle 123, Localidad'
    telefono         VARCHAR(255) NULL,
    fechaNacimiento  DATE         NOT NULL,
    email            VARCHAR(255) NULL,
    obra_social      VARCHAR(255) NULL,
    sexo             VARCHAR(255) NULL
);

CREATE TABLE Profesional (
    ID         INT IDENTITY(1,1) PRIMARY KEY,
    nombre     VARCHAR(255) NOT NULL,
    apellido   VARCHAR(255) NOT NULL,
    dni        VARCHAR(30)  NOT NULL,
    password   VARCHAR(255) NOT NULL,
    email      VARCHAR(255) NULL,
    telefono   VARCHAR(255) NULL,
    matricula  VARCHAR(255) NOT NULL
);

CREATE TABLE Especialidad (
    id      INT IDENTITY(1,1) PRIMARY KEY,
    nombre  VARCHAR(255) NOT NULL
);

CREATE TABLE Especialidad_Profesional (
    id_especialidad  INT NOT NULL REFERENCES Especialidad(id),
    id_profesional   INT NOT NULL REFERENCES Profesional(ID),
    CONSTRAINT PK_Especialidad_Profesional PRIMARY KEY (id_especialidad, id_profesional)
);

CREATE TABLE Horario_Profesional (
    id              INT IDENTITY(1,1),
    id_profesional  INT  NOT NULL REFERENCES Profesional(ID),
    dia_semana      INT  NOT NULL,           -- 1 = Lunes ... 7 = Domingo
    hora_inicio     TIME NOT NULL,
    hora_fin        TIME NOT NULL,
    CONSTRAINT PK_Horario_Profesional PRIMARY KEY (id, id_profesional)
);

CREATE TABLE Turno (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    id_paciente     INT  NOT NULL REFERENCES Paciente(id),
    id_profesional  INT  NOT NULL REFERENCES Profesional(ID),
    hora            TIME NOT NULL,
    fecha           DATE NOT NULL,
    estado          INT  NOT NULL,           -- 1 Pendiente, 2 Atendido, 3 Cancelado, 4 Ausente
    descripcion     VARCHAR(255) NULL
);

CREATE TABLE HistoriaClinica (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    id_paciente     INT  NOT NULL UNIQUE REFERENCES Paciente(id),
    Fecha_Apertura  DATE NOT NULL
);

CREATE TABLE Consulta (
    id                  INT IDENTITY(1,1) PRIMARY KEY,
    ID_HistoriaClinica  INT NOT NULL REFERENCES HistoriaClinica(id),
    Sintomas            VARCHAR(255) NULL,
    Tratamiento         VARCHAR(255) NULL,
    Diagnostico         VARCHAR(255) NULL,
    Fecha               DATE NOT NULL
);
GO

/* ---------------------------------------------------------------------
   2. DATOS DE PRUEBA
   (todo en un solo lote porque usa variables de tabla)
   --------------------------------------------------------------------- */
SET NOCOUNT ON;

DECLARE @Hoy DATE = CAST(GETDATE() AS DATE);

-- 2.1 Especialidades -------------------------------------------------
INSERT INTO Especialidad (nombre) VALUES
 ('Clínica Médica'), ('Pediatría'), ('Cardiología'), ('Dermatología'), ('Ginecología'),
 ('Traumatología'), ('Oftalmología'), ('Neurología'), ('Psiquiatría'), ('Odontología');

-- 2.2 Profesionales ---------------------------------------------------
INSERT INTO Profesional (nombre, apellido, dni, password, email, telefono, matricula) VALUES
 ('Laura',     'Ferreyra',  '22145678', 'hash_demo_123', 'lferreyra@clinica.com',  '261-4001001', 'MP-10234'),
 ('Martín',    'Quiroga',   '23567890', 'hash_demo_123', 'mquiroga@clinica.com',   '261-4001002', 'MP-10567'),
 ('Silvina',   'Lucero',    '24890123', 'hash_demo_123', 'slucero@clinica.com',    '261-4001003', 'MP-10891'),
 ('Andrés',    'Videla',    '25123456', 'hash_demo_123', 'avidela@clinica.com',    '261-4001004', 'MP-11023'),
 ('Carolina',  'Ponce',     '26456789', 'hash_demo_123', 'cponce@clinica.com',     '261-4001005', 'MP-11345'),
 ('Gustavo',   'Moyano',    '27789012', 'hash_demo_123', 'gmoyano@clinica.com',    '261-4001006', 'MP-11678'),
 ('Verónica',  'Arenas',    '28012345', 'hash_demo_123', 'varenas@clinica.com',    '261-4001007', 'MP-11901'),
 ('Ricardo',   'Correa',    '29345678', 'hash_demo_123', 'rcorrea@clinica.com',    '261-4001008', 'MP-12234'),
 ('Paola',     'Ojeda',     '30678901', 'hash_demo_123', 'pojeda@clinica.com',     '261-4001009', 'MP-12567'),
 ('Hernán',    'Funes',     '31901234', 'hash_demo_123', 'hfunes@clinica.com',     '261-4001010', 'MP-12890'),
 ('Mariela',   'Castillo',  '22234567', 'hash_demo_123', 'mcastillo@clinica.com',  '261-4001011', 'MP-13123'),
 ('Sebastián', 'Ibáñez',    '23678901', 'hash_demo_123', 'sibanez@clinica.com',    '261-4001012', 'MP-13456'),
 ('Natalia',   'Vargas',    '24901234', 'hash_demo_123', 'nvargas@clinica.com',    '261-4001013', 'MP-13789'),
 ('Fernando',  'Miranda',   '25234567', 'hash_demo_123', 'fmiranda@clinica.com',   '261-4001014', 'MP-14012'),
 ('Andrea',    'Navarro',   '26567890', 'hash_demo_123', 'anavarro@clinica.com',   '261-4001015', 'MP-14345'),
 ('Jorge',     'Sosa',      '27890123', 'hash_demo_123', 'jsosa@clinica.com',      '261-4001016', 'MP-14678'),
 ('Cecilia',   'Montenegro','28123456', 'hash_demo_123', 'cmontenegro@clinica.com','261-4001017', 'MP-14901'),
 ('Alejandro', 'Paez',      '29456789', 'hash_demo_123', 'apaez@clinica.com',      '261-4001018', 'MP-15234'),
 ('Lorena',    'Bustos',    '30789012', 'hash_demo_123', 'lbustos@clinica.com',    '261-4001019', 'MP-15567'),
 ('Diego',     'Morales',   '31012345', 'hash_demo_123', 'dmorales@clinica.com',   '261-4001020', 'MP-15890');

-- 2.3 Especialidad de cada profesional (2 profesionales por especialidad)
INSERT INTO Especialidad_Profesional (id_especialidad, id_profesional)
SELECT ((p.ID - 1) % 10) + 1, p.ID
FROM Profesional p;

-- Algunos profesionales tienen una segunda especialidad (relacion N a N)
INSERT INTO Especialidad_Profesional (id_especialidad, id_profesional) VALUES
 (3, 1),    -- Laura Ferreyra: Clínica Médica + Cardiología
 (2, 11);   -- Mariela Castillo: Clínica Médica + Pediatría

-- 2.4 Horarios: cada profesional atiende 3 dias (impares a la mañana, pares a la tarde)
INSERT INTO Horario_Profesional (id_profesional, dia_semana, hora_inicio, hora_fin)
SELECT p.ID,
       d.dia,
       CASE WHEN p.ID % 2 = 1 THEN CAST('08:00' AS TIME) ELSE CAST('14:00' AS TIME) END,
       CASE WHEN p.ID % 2 = 1 THEN CAST('13:00' AS TIME) ELSE CAST('20:00' AS TIME) END
FROM Profesional p
CROSS APPLY (VALUES (((p.ID - 1) % 5) + 1),
                    (((p.ID + 1) % 5) + 1),
                    (((p.ID + 2) % 5) + 1)) AS d(dia);

-- 2.5 Pacientes -------------------------------------------------------
DECLARE @Nombres TABLE (n INT IDENTITY(1,1), nombre VARCHAR(50), sexo VARCHAR(20));
INSERT INTO @Nombres (nombre, sexo) VALUES
 ('Juan','Masculino'),('Carlos','Masculino'),('Martín','Masculino'),('Lucas','Masculino'),
 ('Mateo','Masculino'),('Santiago','Masculino'),('Diego','Masculino'),('Pablo','Masculino'),
 ('Facundo','Masculino'),('Nicolás','Masculino'),('Agustín','Masculino'),('Tomás','Masculino'),
 ('Federico','Masculino'),('Gonzalo','Masculino'),('Matías','Masculino'),('Joaquín','Masculino'),
 ('Franco','Masculino'),('Ignacio','Masculino'),('Emiliano','Masculino'),('Ramiro','Masculino'),
 ('María','Femenino'),('Lucía','Femenino'),('Sofía','Femenino'),('Valentina','Femenino'),
 ('Camila','Femenino'),('Martina','Femenino'),('Florencia','Femenino'),('Julieta','Femenino'),
 ('Agustina','Femenino'),('Carolina','Femenino'),('Paula','Femenino'),('Micaela','Femenino'),
 ('Victoria','Femenino'),('Ana','Femenino'),('Laura','Femenino'),('Gabriela','Femenino'),
 ('Natalia','Femenino'),('Romina','Femenino'),('Daniela','Femenino'),('Milagros','Femenino');

DECLARE @Apellidos TABLE (n INT IDENTITY(1,1), apellido VARCHAR(50));
INSERT INTO @Apellidos (apellido) VALUES
 ('González'),('Rodríguez'),('Gómez'),('Fernández'),('López'),('Díaz'),('Martínez'),('Pérez'),
 ('García'),('Sánchez'),('Romero'),('Sosa'),('Torres'),('Álvarez'),('Ruiz'),('Ramírez'),
 ('Flores'),('Benítez'),('Acosta'),('Medina'),('Herrera'),('Suárez'),('Aguirre'),('Giménez'),
 ('Gutiérrez'),('Pereyra'),('Molina'),('Castro'),('Ortiz'),('Silva');

DECLARE @Calles TABLE (n INT IDENTITY(1,1), calle VARCHAR(50));
INSERT INTO @Calles (calle) VALUES
 ('San Martín'),('Belgrano'),('Las Heras'),('Colón'),('Mitre'),('Sarmiento'),('Rivadavia'),
 ('España'),('Patricias Mendocinas'),('Godoy Cruz'),('Perú'),('Chile'),('Paso de los Andes'),
 ('Emilio Civit'),('Arístides Villanueva');

DECLARE @Localidades TABLE (n INT IDENTITY(1,1), localidad VARCHAR(50));
INSERT INTO @Localidades (localidad) VALUES
 ('Ciudad de Mendoza'),('Godoy Cruz'),('Guaymallén'),('Las Heras'),('Maipú'),('Luján de Cuyo');

-- Lista ponderada (OSEP y OSDE aparecen mas veces). PAMI se asigna segun la edad.
DECLARE @ObrasSociales TABLE (n INT IDENTITY(1,1), obra VARCHAR(50));
INSERT INTO @ObrasSociales (obra) VALUES
 ('OSEP'),('OSEP'),('OSEP'),('OSDE'),('OSDE'),('Swiss Medical'),('Galeno'),('Medifé'),
 ('Particular'),('Particular');

-- Valores aleatorios materializados primero (NEWID() se evalua una vez por fila)
IF OBJECT_ID('tempdb..#P') IS NOT NULL DROP TABLE #P;
SELECT TOP (600)
       ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i,
       ABS(CHECKSUM(NEWID())) % 40 + 1          AS r_nombre,
       ABS(CHECKSUM(NEWID())) % 30 + 1          AS r_apellido,
       ABS(CHECKSUM(NEWID())) % 15 + 1          AS r_calle,
       ABS(CHECKSUM(NEWID())) % 6  + 1          AS r_localidad,
       ABS(CHECKSUM(NEWID())) % 10 + 1          AS r_os,
       ABS(CHECKSUM(NEWID())) % 100             AS r_pami,
       ABS(CHECKSUM(NEWID())) % (86 * 365) + 180 AS r_dias_edad,
       ABS(CHECKSUM(NEWID())) % 9000 + 100      AS r_altura,
       ABS(CHECKSUM(NEWID())) % 40              AS r_dni,
       ABS(CHECKSUM(NEWID())) % 10000000        AS r_tel
INTO #P
FROM sys.all_objects a CROSS JOIN sys.all_objects b;

INSERT INTO Paciente (dni, nombre, apellido, password, direccion, telefono,
                      fechaNacimiento, email, obra_social, sexo)
SELECT CAST(20000000 + p.i * 50 + p.r_dni AS VARCHAR(30)),
       n.nombre,
       a.apellido,
       'hash_demo_123',
       c.calle + ' ' + CAST(p.r_altura AS VARCHAR(10)) + ', ' + l.localidad,
       '261-' + RIGHT('0000000' + CAST(p.r_tel AS VARCHAR(7)), 7),
       DATEADD(DAY, -p.r_dias_edad, CAST('20261001' AS DATE)),
       'paciente' + CAST(p.i AS VARCHAR(10)) + '@mail.com',
       CASE WHEN p.r_dias_edad >= 65 * 365 AND p.r_pami < 70 THEN 'PAMI' ELSE o.obra END,
       n.sexo
FROM #P p
JOIN @Nombres       n ON n.n = p.r_nombre
JOIN @Apellidos     a ON a.n = p.r_apellido
JOIN @Calles        c ON c.n = p.r_calle
JOIN @Localidades   l ON l.n = p.r_localidad
JOIN @ObrasSociales o ON o.n = p.r_os
ORDER BY p.i;

-- 2.6 Turnos ----------------------------------------------------------
-- Semanas desde el lunes 01/01/2024 (156 semanas = hasta fin de 2026).
-- POWER(...,0.7) hace que haya mas turnos en los años recientes (crecimiento).
IF OBJECT_ID('tempdb..#T') IS NOT NULL DROP TABLE #T;
SELECT TOP (9500)
       ABS(CHECKSUM(NEWID())) % 600 + 1  AS id_paciente,
       ABS(CHECKSUM(NEWID())) % 20  + 1  AS id_profesional,
       ABS(CHECKSUM(NEWID())) % 3        AS idx_horario,
       CAST(FLOOR(156 * POWER(RAND(CHECKSUM(NEWID())), 0.7)) AS INT) AS semana,
       ABS(CHECKSUM(NEWID())) % 12       AS slot,
       ABS(CHECKSUM(NEWID())) % 100      AS r_estado,
       ABS(CHECKSUM(NEWID())) % 5        AS r_desc
INTO #T
FROM sys.all_objects a CROSS JOIN sys.all_objects b;

;WITH H AS (
    SELECT id_profesional, dia_semana, hora_inicio,
           ROW_NUMBER() OVER (PARTITION BY id_profesional ORDER BY dia_semana) - 1 AS idx,
           DATEDIFF(MINUTE, hora_inicio, hora_fin) / 30 AS cant_slots
    FROM Horario_Profesional
),
Base AS (   -- el turno cae en un dia y horario en que el profesional atiende
    SELECT t.id_paciente, t.id_profesional,
           DATEADD(DAY, t.semana * 7 + (h.dia_semana - 1), CAST('20240101' AS DATE)) AS fecha,
           DATEADD(MINUTE, 30 * (t.slot % h.cant_slots), h.hora_inicio)            AS hora,
           t.r_estado, t.r_desc
    FROM #T t
    JOIN H h ON h.id_profesional = t.id_profesional AND h.idx = t.idx_horario
),
SinDuplicados AS (  -- un solo turno por profesional / fecha / hora
    SELECT b.*,
           ROW_NUMBER() OVER (PARTITION BY b.id_profesional, b.fecha, b.hora ORDER BY b.id_paciente) AS rn
    FROM Base b
),
ConDatos AS (
    SELECT s.id_paciente, s.id_profesional, s.fecha, s.hora, s.r_estado, s.r_desc,
           p.obra_social,
           DATEDIFF(YEAR, p.fechaNacimiento, s.fecha) AS edad
    FROM SinDuplicados s
    JOIN Paciente p ON p.id = s.id_paciente
    WHERE s.rn = 1
)
INSERT INTO Turno (id_paciente, id_profesional, hora, fecha, estado, descripcion)
SELECT c.id_paciente, c.id_profesional, c.hora, c.fecha,
       CASE WHEN c.fecha > @Hoy                    THEN 1   -- futuro: Pendiente
            WHEN c.r_estado < u.umbral_aus         THEN 4   -- Ausente
            WHEN c.r_estado < u.umbral_aus + 12    THEN 3   -- Cancelado
            ELSE 2                                          -- Atendido
       END,
       CHOOSE(c.r_desc + 1, 'Primera consulta', 'Control', 'Seguimiento',
                            'Lectura de estudios', 'Urgencia programada')
FROM ConDatos c
-- El ausentismo depende de algunos factores para que los indicadores muestren algo interesante:
CROSS APPLY (SELECT 9
                  + CASE WHEN c.obra_social = 'Particular'  THEN 10 ELSE 0 END
                  + CASE WHEN c.edad BETWEEN 18 AND 35      THEN 6  ELSE 0 END
                  + CASE WHEN c.hora < CAST('09:00' AS TIME) THEN 4 ELSE 0 END
                  - CASE WHEN YEAR(c.fecha) = 2026          THEN 4  ELSE 0 END  -- mejora 2026 (recordatorios)
             AS umbral_aus) u
ORDER BY c.fecha, c.hora;

-- 2.7 Historias clinicas (una por paciente) ----------------------------
INSERT INTO HistoriaClinica (id_paciente, Fecha_Apertura)
SELECT p.id, COALESCE(MIN(t.fecha), CAST('20240101' AS DATE))
FROM Paciente p
LEFT JOIN Turno t ON t.id_paciente = p.id
GROUP BY p.id;

-- 2.8 Consultas (una por cada turno atendido) -------------------------
DECLARE @Diag TABLE (id_especialidad INT, k INT, sintomas VARCHAR(255),
                     diagnostico VARCHAR(255), tratamiento VARCHAR(255));
INSERT INTO @Diag VALUES
 (1,0,'Fiebre y dolor de garganta','Faringitis','Antibiótico y reposo'),
 (1,1,'Cansancio y cefalea','Hipertensión leve','Control de presión y dieta'),
 (2,0,'Tos y congestión','Bronquiolitis','Nebulizaciones'),
 (2,1,'Control de crecimiento','Niño sano','Control en 6 meses'),
 (3,0,'Palpitaciones','Arritmia leve','Holter y betabloqueantes'),
 (3,1,'Dolor de pecho al esfuerzo','Angina estable','Estudio ergométrico'),
 (4,0,'Manchas en la piel','Dermatitis','Crema con corticoide'),
 (4,1,'Lunar con cambios','Nevo atípico','Biopsia'),
 (5,0,'Control anual','Control ginecológico normal','PAP y ecografía'),
 (5,1,'Dolor abdominal bajo','Quiste ovárico','Ecografía de control'),
 (6,0,'Dolor de rodilla','Esguince','Inmovilización y kinesiología'),
 (6,1,'Dolor lumbar','Lumbalgia','Antiinflamatorios y reposo'),
 (7,0,'Visión borrosa','Miopía','Anteojos'),
 (7,1,'Ojo rojo','Conjuntivitis','Gotas antibióticas'),
 (8,0,'Dolor de cabeza frecuente','Migraña','Analgésicos y diario de cefaleas'),
 (8,1,'Mareos','Vértigo posicional','Maniobras de reposición'),
 (9,0,'Insomnio','Trastorno de ansiedad','Psicoterapia'),
 (9,1,'Desánimo persistente','Episodio depresivo','Psicoterapia y medicación'),
 (10,0,'Dolor de muela','Caries','Arreglo dental'),
 (10,1,'Sangrado de encías','Gingivitis','Limpieza dental');

;WITH EspPrincipal AS (
    SELECT id_profesional, MIN(id_especialidad) AS id_especialidad
    FROM Especialidad_Profesional
    GROUP BY id_profesional
)
INSERT INTO Consulta (ID_HistoriaClinica, Sintomas, Tratamiento, Diagnostico, Fecha)
SELECT hc.id, d.sintomas, d.tratamiento, d.diagnostico, t.fecha
FROM Turno t
JOIN HistoriaClinica hc ON hc.id_paciente = t.id_paciente
JOIN EspPrincipal    ep ON ep.id_profesional = t.id_profesional
JOIN @Diag           d  ON d.id_especialidad = ep.id_especialidad AND d.k = t.id % 2
WHERE t.estado = 2
ORDER BY t.fecha;

DROP TABLE #P;
DROP TABLE #T;
GO

/* ---------------------------------------------------------------------
   3. VERIFICACION
   --------------------------------------------------------------------- */
SELECT 'Especialidad' AS tabla, COUNT(*) AS filas FROM Especialidad
UNION ALL SELECT 'Profesional',              COUNT(*) FROM Profesional
UNION ALL SELECT 'Especialidad_Profesional', COUNT(*) FROM Especialidad_Profesional
UNION ALL SELECT 'Horario_Profesional',      COUNT(*) FROM Horario_Profesional
UNION ALL SELECT 'Paciente',                 COUNT(*) FROM Paciente
UNION ALL SELECT 'Turno',                    COUNT(*) FROM Turno
UNION ALL SELECT 'HistoriaClinica',          COUNT(*) FROM HistoriaClinica
UNION ALL SELECT 'Consulta',                 COUNT(*) FROM Consulta;

SELECT estado, COUNT(*) AS cantidad
FROM Turno
GROUP BY estado
ORDER BY estado;
GO
