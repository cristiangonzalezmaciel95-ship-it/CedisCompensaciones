-- 1. CREACIÓN DE LA BASE DE DATOS
CREATE DATABASE CEDIS_Compensaciones_DB;
GO

USE CEDIS_Compensaciones_DB;
GO

-- ==========================================
-- MÓDULO 1: SEGURIDAD Y CONFIGURACIÓN
-- ==========================================

CREATE TABLE Cat_Departamentos (
    ID_Departamento INT IDENTITY(1,1) PRIMARY KEY,
    Nombre_Departamento VARCHAR(100) NOT NULL,
    Estatus BIT DEFAULT 1 -- 1: Activo, 0: Inactivo
);

CREATE TABLE Cat_Roles (
    ID_Rol INT IDENTITY(1,1) PRIMARY KEY,
    Nombre_Rol VARCHAR(50) NOT NULL
);

CREATE TABLE Usuarios (
    ID_Usuario INT IDENTITY(1,1) PRIMARY KEY,
    Correo_Google VARCHAR(150) UNIQUE NOT NULL,
    Nombre_Completo VARCHAR(150) NOT NULL,
    ID_Rol INT,
    ID_Departamento INT,
    Estatus BIT DEFAULT 1,
    CONSTRAINT FK_Usuarios_Rol FOREIGN KEY (ID_Rol) REFERENCES Cat_Roles(ID_Rol),
    CONSTRAINT FK_Usuarios_Depto FOREIGN KEY (ID_Departamento) REFERENCES Cat_Departamentos(ID_Departamento)
);

-- ==========================================
-- MÓDULO 2: CATÁLOGOS OPERATIVOS
-- ==========================================

CREATE TABLE Cat_Centros_Bodegas (
    ID_Centro INT PRIMARY KEY, -- Sin IDENTITY porque se usará el número real (Ej: 200307)
    Numero_Tienda_Bodega INT NOT NULL,
    Tipo_Ubicacion VARCHAR(50) NOT NULL
);

CREATE TABLE Cat_Productos (
    Codigo_SKU INT PRIMARY KEY, -- Sin IDENTITY porque se usará el SKU real (Ej: 935131)
    Articulo VARCHAR(150) NOT NULL,
    Marca_Dep INT,
    Modelo_Clase INT,
    Familia INT,
    Precio_Unidad DECIMAL(18,2) NOT NULL
);

-- ==========================================
-- MÓDULO 3: TRANSACCIONAL Y OPERACIÓN
-- ==========================================

CREATE TABLE Polizas_Registro (
    ID_Registro INT IDENTITY(1,1) PRIMARY KEY,
    Numero_Poliza INT NOT NULL,
    Fecha_Registro DATE NOT NULL,
    ID_Centro INT NOT NULL,
    Codigo_SKU INT NOT NULL,
    Tipo_Irregularidad VARCHAR(20) NOT NULL,
    Cantidad INT NOT NULL,
    Costo_Total_Movimiento DECIMAL(18,2) NOT NULL,
    Valor_Vale DECIMAL(18,2) DEFAULT 0,
    Concepto_Original VARCHAR(255),
    Comentarios_Seguimientos VARCHAR(MAX),
    Estado_Compensacion VARCHAR(50) DEFAULT 'Pendiente',
    Origen_Captura VARCHAR(50) NOT NULL,
    ID_Usuario_Captura INT,
    CONSTRAINT FK_Polizas_Centro FOREIGN KEY (ID_Centro) REFERENCES Cat_Centros_Bodegas(ID_Centro),
    CONSTRAINT FK_Polizas_Producto FOREIGN KEY (Codigo_SKU) REFERENCES Cat_Productos(Codigo_SKU),
    CONSTRAINT FK_Polizas_Usuario FOREIGN KEY (ID_Usuario_Captura) REFERENCES Usuarios(ID_Usuario),
    CONSTRAINT CHK_TipoIrregularidad CHECK (Tipo_Irregularidad IN ('Faltante', 'Sobrante')),
    CONSTRAINT CHK_EstadoCompensacion CHECK (Estado_Compensacion IN ('Pendiente', 'Compensada', 'Rechazada', 'En Revisión')),
    CONSTRAINT CHK_OrigenCaptura CHECK (Origen_Captura IN ('Manual', 'Automatizada'))
);

CREATE TABLE Compensaciones_Realizadas (
    ID_Compensacion INT IDENTITY(1,1) PRIMARY KEY,
    ID_Poliza_Faltante INT NOT NULL,
    ID_Poliza_Sobrante INT NOT NULL,
    ID_Usuario_Validador INT NOT NULL,
    Fecha_Validacion DATETIME DEFAULT GETDATE(),
    Comentario_Resolucion VARCHAR(MAX),
    CONSTRAINT FK_Compensacion_Faltante FOREIGN KEY (ID_Poliza_Faltante) REFERENCES Polizas_Registro(ID_Registro),
    CONSTRAINT FK_Compensacion_Sobrante FOREIGN KEY (ID_Poliza_Sobrante) REFERENCES Polizas_Registro(ID_Registro),
    CONSTRAINT FK_Compensacion_Usuario FOREIGN KEY (ID_Usuario_Validador) REFERENCES Usuarios(ID_Usuario)
);

-- ==========================================
-- MÓDULO 4: ALMACENAMIENTO (CLOUD)
-- ==========================================

CREATE TABLE Archivos_Compensacion (
    ID_Archivo INT IDENTITY(1,1) PRIMARY KEY,
    ID_Compensacion INT NOT NULL UNIQUE, -- UNIQUE garantiza la relación 1 a 1
    Nombre_Archivo VARCHAR(255) NOT NULL,
    Google_Drive_File_ID VARCHAR(250) NOT NULL,
    Fecha_Generacion DATETIME DEFAULT GETDATE(),
    CONSTRAINT FK_Archivos_Compensacion FOREIGN KEY (ID_Compensacion) REFERENCES Compensaciones_Realizadas(ID_Compensacion)
);

-- ==========================================
-- MÓDULO 5: AUDITORÍA Y TRAZABILIDAD
-- ==========================================

CREATE TABLE Log_Ejecucion_Extraccion (
    ID_Ejecucion INT IDENTITY(1,1) PRIMARY KEY,
    ID_Usuario_Ejecutor INT NOT NULL,
    Fecha_Inicio_Ejecucion DATETIME DEFAULT GETDATE(),
    Fecha_Fin_Ejecucion DATETIME,
    Cantidad_Correos_Leidos INT DEFAULT 0,
    Registros_Nuevos_Insertados INT DEFAULT 0,
    Estatus_Resultado VARCHAR(50),
    CONSTRAINT FK_Log_Usuario FOREIGN KEY (ID_Usuario_Ejecutor) REFERENCES Usuarios(ID_Usuario)
);

CREATE TABLE Bitacora_Auditoria (
    ID_Bitacora INT IDENTITY(1,1) PRIMARY KEY,
    ID_Usuario_Accion INT NOT NULL,
    Tabla_Afectada VARCHAR(50) NOT NULL,
    ID_Registro_Afectado INT NOT NULL,
    Accion VARCHAR(50) NOT NULL,
    Valor_Anterior VARCHAR(MAX),
    Fecha_Accion DATETIME DEFAULT GETDATE(),
    CONSTRAINT FK_Bitacora_Usuario FOREIGN KEY (ID_Usuario_Accion) REFERENCES Usuarios(ID_Usuario)
);
GO

PRINT 'Base de datos CEDIS_Compensaciones_DB y tablas creadas con éxito.';