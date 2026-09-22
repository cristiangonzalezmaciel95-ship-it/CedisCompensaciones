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



-- 1. Creamos la tabla puente para manejar múltiples espacios y roles
CREATE TABLE Usuarios_Espacios (
    ID_Relacion INT IDENTITY(1,1) PRIMARY KEY,
    ID_Usuario INT NOT NULL,
    ID_Departamento INT NOT NULL, -- (El Espacio de Trabajo)
    ID_Rol INT NOT NULL,          -- (Super Admin, Editor, etc., en ESTE espacio)
    Fecha_Ingreso DATETIME DEFAULT GETDATE(),
    CONSTRAINT FK_Rel_Usuario FOREIGN KEY (ID_Usuario) REFERENCES Usuarios(ID_Usuario),
    CONSTRAINT FK_Rel_Depto FOREIGN KEY (ID_Departamento) REFERENCES Cat_Departamentos(ID_Departamento),
    CONSTRAINT FK_Rel_Rol FOREIGN KEY (ID_Rol) REFERENCES Cat_Roles(ID_Rol)
);
GO

-- 2. Borramos las limitantes de la tabla Usuarios original
ALTER TABLE Usuarios DROP CONSTRAINT FK_Usuarios_Rol;
ALTER TABLE Usuarios DROP CONSTRAINT FK_Usuarios_Depto;
ALTER TABLE Usuarios DROP COLUMN ID_Rol;
ALTER TABLE Usuarios DROP COLUMN ID_Departamento;
GO








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


-- Insertamos un departamento y un rol temporal para cumplir las llaves foráneas
INSERT INTO Cat_Departamentos (Nombre_Departamento, Estatus) VALUES ('Sistemas', 1);
INSERT INTO Cat_Roles (Nombre_Rol) VALUES ('Administrador');
INSERT INTO Cat_Roles (Nombre_Rol) VALUES ('Validador');

-- INSERTA TU CORREO DE GOOGLE AQUÍ
INSERT INTO Usuarios (Correo_Google, Nombre_Completo, ID_Rol, ID_Departamento, Estatus) 
VALUES ('cristiangonzalezmaciel95@gmail.com', 'Cristian Gonzalez Maciel', 1, 1, 1);

-- =========================================================================
-- PREPARACIÓN: Agregar la columna de contraseña para el Espacio de Trabajo
-- =========================================================================
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[Cat_Departamentos]') AND name = 'Contrasena_Area')
BEGIN
    ALTER TABLE Cat_Departamentos ADD Contrasena_Area VARCHAR(255) DEFAULT '12345';
END







select*from Cat_Departamentos
select*from Cat_Roles
Select*from Usuarios

select*from Bitacora_Auditoria
select*from Usuarios_Espacios
select*from Usuarios
select*from Archivos_Compensacion
select*from Compensaciones_Realizadas
select*from  Operacion_Compensaciones


ALTER TABLE Usuarios ALTER COLUMN Nombre_Completo NVARCHAR(150) NULL;
GO


-- 1. Agregamos el Código de Unión a los espacios existentes
ALTER TABLE Cat_Departamentos 
ADD Codigo_Union VARCHAR(10) NULL;
GO

-- 2. Le ponemos un código aleatorio a los espacios que ya habías creado para que no fallen
UPDATE Cat_Departamentos
SET Codigo_Union = SUBSTRING(REPLACE(NEWID(), '-', ''), 1, 6)
WHERE Codigo_Union IS NULL;
GO

-- 3. Hacemos que el código sea obligatorio de ahora en adelante y no se repita
ALTER TABLE Cat_Departamentos 
ALTER COLUMN Codigo_Union VARCHAR(10) NOT NULL;
GO
ALTER TABLE Cat_Departamentos 
ADD CONSTRAINT UQ_CodigoUnion UNIQUE (Codigo_Union);
GO

-- 4. Creamos la tabla de Solicitudes (La "sala de espera")
CREATE TABLE Solicitudes_Acceso (
    ID_Solicitud INT IDENTITY(1,1) PRIMARY KEY,
    ID_Usuario INT NOT NULL FOREIGN KEY REFERENCES Usuarios(ID_Usuario),
    ID_Departamento INT NOT NULL FOREIGN KEY REFERENCES Cat_Departamentos(ID_Departamento),
    Estatus VARCHAR(20) DEFAULT 'Pendiente', -- Puede ser 'Pendiente', 'Aprobado', 'Rechazado'
    Fecha_Solicitud DATETIME DEFAULT GETDATE()
);
GO








CREATE TABLE Operacion_Compensaciones (
    ID_Registro INT IDENTITY(1,1) PRIMARY KEY,
    ID_Departamento INT NOT NULL,
    ID_Usuario INT NOT NULL, -- Quien registró la operación
    Tipo_Operacion NVARCHAR(50) NOT NULL, -- Valores: 'Póliza', 'Faltante', 'Sobrante'
    Fecha_Operacion DATE NOT NULL, -- La fecha del movimiento
    Concepto NVARCHAR(255) NOT NULL, -- Descripción del movimiento
    Monto DECIMAL(18, 2) NOT NULL, -- Cantidad de dinero
    Fecha_Registro DATETIME DEFAULT GETDATE(),
    Estatus BIT DEFAULT 1, -- 1 = Activo, 0 = Eliminado (Borrado lógico)
    
    -- Llaves foráneas para mantener la integridad relacional
    CONSTRAINT FK_Operacion_Departamento FOREIGN KEY (ID_Departamento) REFERENCES Cat_Departamentos(ID_Departamento),
    CONSTRAINT FK_Operacion_Usuario FOREIGN KEY (ID_Usuario) REFERENCES Usuarios(ID_Usuario)
);
GO


USE CEDIS_Compensaciones_DB;
GO

-- Si ya existe la tabla (de la prueba anterior), la borramos para crear la buena
IF OBJECT_ID('Operacion_Compensaciones', 'U') IS NOT NULL 
    DROP TABLE Operacion_Compensaciones;
GO

CREATE TABLE Operacion_Compensaciones (
    ID_Registro INT IDENTITY(1,1) PRIMARY KEY,
    ID_Departamento INT NOT NULL,
    ID_Usuario INT NOT NULL, 
    
    -- DATOS DEL EXCEL
    Mes NVARCHAR(20),
    Tienda_Bodega NVARCHAR(50),
    Poliza NVARCHAR(50),
    Fecha DATE NOT NULL,
    Tipo NVARCHAR(50) NOT NULL, -- faltante, sobrante, etc.
    Cantidad INT NOT NULL,
    Articulo NVARCHAR(150),
    Marca_Dep NVARCHAR(50),
    Modelo_Clase NVARCHAR(50),
    Familia NVARCHAR(50),
    Codigo NVARCHAR(50),
    Vale NVARCHAR(50),
    Precio_Unidad DECIMAL(18, 2),
    Precio_Venta DECIMAL(18, 2),
    Centro NVARCHAR(50),
    Concepto NVARCHAR(255),
    Comentarios NVARCHAR(MAX),
    Poliza_Referencia NVARCHAR(100),
    SKU NVARCHAR(100),
    Autorizacion NVARCHAR(255),
    
    -- CONTROL INTERNO DEL SISTEMA
    Fecha_Registro DATETIME DEFAULT GETDATE(),
    Estatus BIT DEFAULT 1, -- 1 = Activo, 0 = Eliminado lógico
    
    CONSTRAINT FK_Operacion_Departamento FOREIGN KEY (ID_Departamento) REFERENCES Cat_Departamentos(ID_Departamento),
    CONSTRAINT FK_Operacion_Usuario FOREIGN KEY (ID_Usuario) REFERENCES Usuarios(ID_Usuario)
);
GO





