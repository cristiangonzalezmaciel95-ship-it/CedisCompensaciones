CREATE OR ALTER PROCEDURE spObtenerOperacionesPorEspacio (
    @ID_Departamento INT
)
AS
BEGIN
    SELECT 
        o.ID_Registro,
        o.Tipo_Operacion,
        o.Fecha_Operacion,
        o.Concepto,
        o.Monto,
        u.Correo_Google AS Responsable -- <-- MODIFICADO: Usamos el correo que sí existe en tu tabla
    FROM Operacion_Compensaciones o
    INNER JOIN Usuarios u ON o.ID_Usuario = u.ID_Usuario
    WHERE o.ID_Departamento = @ID_Departamento AND o.Estatus = 1
    ORDER BY o.Fecha_Operacion DESC, o.Fecha_Registro DESC;
END
GO

CREATE OR ALTER PROCEDURE spInsertarOperacion (
    @ID_Departamento INT,
    @Correo_Google NVARCHAR(100),
    @Tipo_Operacion NVARCHAR(50),
    @Fecha_Operacion DATE,
    @Concepto NVARCHAR(255),
    @Monto DECIMAL(18, 2)
)
AS
BEGIN
    BEGIN TRY
        -- Obtenemos el ID del usuario a partir de su correo
        DECLARE @ID_Usuario INT;
        SELECT @ID_Usuario = ID_Usuario FROM Usuarios WHERE Correo_Google = @Correo_Google;

        IF @ID_Usuario IS NULL
        BEGIN
            RAISERROR('Usuario no encontrado.', 16, 1);
            RETURN;
        END

        -- Insertamos el registro
        INSERT INTO Operacion_Compensaciones (ID_Departamento, ID_Usuario, Tipo_Operacion, Fecha_Operacion, Concepto, Monto)
        VALUES (@ID_Departamento, @ID_Usuario, @Tipo_Operacion, @Fecha_Operacion, @Concepto, @Monto);

    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE spCrearEspacioConValidacion(
    @Nombre_Departamento NVARCHAR(100),
    @Contrasena_Area NVARCHAR(50),
    @Correo_Creador NVARCHAR(100),
    @Codigo_Union NVARCHAR(6)
)
AS
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION

        -- 1. Obtener el ID del usuario creador
        DECLARE @ID_Usuario INT;
        SELECT @ID_Usuario = ID_Usuario FROM Usuarios WHERE Correo_Google = @Correo_Creador;

        IF @ID_Usuario IS NULL
        BEGIN
            RAISERROR('El usuario no está registrado en el sistema.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- 2. VALIDAR: Que no exista ya un espacio con este mismo nombre donde ESTE USUARIO sea el Administrador (Rol 1)
        IF EXISTS (
            SELECT 1 
            FROM Cat_Departamentos d
            INNER JOIN Usuarios_Espacios ue ON d.ID_Departamento = ue.ID_Departamento
            WHERE d.Nombre_Departamento = @Nombre_Departamento 
              AND ue.ID_Usuario = @ID_Usuario 
              AND ue.ID_Rol = 1
              AND d.Estatus = 1
        )
        BEGIN
            RAISERROR('Ya tienes un proyecto creado con este nombre. Elige uno diferente.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- 3. Crear el Departamento
        INSERT INTO Cat_Departamentos (Nombre_Departamento, Contrasena_Area, Codigo_Union, Estatus)
        VALUES (@Nombre_Departamento, @Contrasena_Area, @Codigo_Union, 1);

        DECLARE @ID_Departamento INT = SCOPE_IDENTITY();

        -- 4. Asignarle el rol de Administrador Supremo (Rol 1) al creador
        INSERT INTO Usuarios_Espacios (ID_Usuario, ID_Departamento, ID_Rol, Fecha_Ingreso)
        VALUES (@ID_Usuario, @ID_Departamento, 1, GETDATE());

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH
END
GO


CREATE OR ALTER PROCEDURE spObtenerPasswordArea(
    @ID_Departamento INT,
    @Correo_Usuario NVARCHAR(100),
    @ContrasenaArea NVARCHAR(50) OUTPUT
)
AS
BEGIN
    -- Validar que el usuario sea el Administrador (Rol 1) de este departamento
    IF EXISTS(
        SELECT 1 FROM Usuarios_Espacios ue 
        INNER JOIN Usuarios u ON ue.ID_Usuario = u.ID_Usuario
        WHERE ue.ID_Departamento = @ID_Departamento AND u.Correo_Google = @Correo_Usuario AND ue.ID_Rol = 1
    )
    BEGIN
        SELECT @ContrasenaArea = Contrasena_Area 
        FROM Cat_Departamentos 
        WHERE ID_Departamento = @ID_Departamento;
    END
    ELSE
    BEGIN
        SET @ContrasenaArea = NULL;
    END
END
GO

-- 2. Aprobar solicitud y asignar rol
CREATE OR ALTER PROCEDURE spAceptarSolicitud(
    @ID_Solicitud INT,
    @ID_Rol INT
)
AS
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION
        
        DECLARE @ID_Usuario INT;
        DECLARE @ID_Departamento INT;

        -- Obtener datos de la solicitud
        SELECT @ID_Usuario = ID_Usuario, @ID_Departamento = ID_Departamento 
        FROM Solicitudes_Acceso WHERE ID_Solicitud = @ID_Solicitud AND Estatus = 'Pendiente';

        IF @ID_Usuario IS NULL
        BEGIN
            RAISERROR('La solicitud no existe o ya fue procesada.', 16, 1);
        END

        -- Insertar al usuario en el espacio con el rol seleccionado
        IF NOT EXISTS(SELECT 1 FROM Usuarios_Espacios WHERE ID_Usuario = @ID_Usuario AND ID_Departamento = @ID_Departamento)
        BEGIN
            INSERT INTO Usuarios_Espacios (ID_Usuario, ID_Departamento, ID_Rol, Fecha_Ingreso)
            VALUES (@ID_Usuario, @ID_Departamento, @ID_Rol, GETDATE());
        END

        -- Marcar como aprobada
        UPDATE Solicitudes_Acceso SET Estatus = 'Aprobado' WHERE ID_Solicitud = @ID_Solicitud;

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH
END
GO

-- 2. Aprobar solicitud y asignar rol
CREATE PROCEDURE spAceptarSolicitud(
    @ID_Solicitud INT,
    @ID_Rol INT
)
AS
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION
        
        DECLARE @ID_Usuario INT;
        DECLARE @ID_Departamento INT;

        -- Obtener datos de la solicitud
        SELECT @ID_Usuario = ID_Usuario, @ID_Departamento = ID_Departamento 
        FROM Solicitudes_Acceso WHERE ID_Solicitud = @ID_Solicitud AND Estatus = 'Pendiente';

        IF @ID_Usuario IS NULL
        BEGIN
            RAISERROR('La solicitud no existe o ya fue procesada.', 16, 1);
        END

        -- Insertar al usuario en el espacio con el rol seleccionado
        IF NOT EXISTS(SELECT 1 FROM Usuarios_Espacios WHERE ID_Usuario = @ID_Usuario AND ID_Departamento = @ID_Departamento)
        BEGIN
            INSERT INTO Usuarios_Espacios (ID_Usuario, ID_Departamento, ID_Rol, Fecha_Ingreso)
            VALUES (@ID_Usuario, @ID_Departamento, @ID_Rol, GETDATE());
        END

        -- Marcar como aprobada
        UPDATE Solicitudes_Acceso SET Estatus = 'Aprobado' WHERE ID_Solicitud = @ID_Solicitud;

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH
END
GO



-- 1. SP PARA ELIMINAR PROYECTO (Solo Admin Supremo con contraseña)
CREATE OR ALTER PROCEDURE spEliminarProyectoCompleto(
    @ID_Departamento INT,
    @ContrasenaProporcionada NVARCHAR(50),
    @Correo_Admin NVARCHAR(100),
    @Mensaje NVARCHAR(200) OUTPUT
)
AS
BEGIN
    BEGIN TRY
        -- A. Validar que el usuario sea el Super Admin de ese proyecto
        IF NOT EXISTS(
            SELECT 1 FROM Usuarios_Espacios ue 
            INNER JOIN Usuarios u ON ue.ID_Usuario = u.ID_Usuario
            WHERE ue.ID_Departamento = @ID_Departamento AND u.Correo_Google = @Correo_Admin AND ue.ID_Rol = 1
        )
        BEGIN
            RAISERROR('No tienes permisos de Administrador para eliminar este proyecto.', 16, 1);
            RETURN;
        END

        -- B. Validar contraseña maestra del área
        DECLARE @PassCorrecta NVARCHAR(50);
        SELECT @PassCorrecta = Contrasena_Area FROM Cat_Departamentos WHERE ID_Departamento = @ID_Departamento;
        
        IF @PassCorrecta != @ContrasenaProporcionada
        BEGIN
            RAISERROR('La contraseña maestra del espacio es incorrecta.', 16, 1);
            RETURN;
        END

        -- C. Borrar todos los rastros
        BEGIN TRANSACTION
            -- 1. Borrar Solicitudes Pendientes
            DELETE FROM Solicitudes_Acceso WHERE ID_Departamento = @ID_Departamento;
            -- 2. Borrar a todos los Participantes
            DELETE FROM Usuarios_Espacios WHERE ID_Departamento = @ID_Departamento;
            -- 3. Borrar el Departamento / Proyecto
            DELETE FROM Cat_Departamentos WHERE ID_Departamento = @ID_Departamento;
        COMMIT TRANSACTION

        SET @Mensaje = 'El proyecto y todos sus datos fueron eliminados permanentemente.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@Err, 16, 1);
    END CATCH
END
GO

-- 2. SP PARA DARSE DE BAJA (Usuarios Normales)
CREATE OR ALTER PROCEDURE spDarDeBajaUsuario(
    @ID_Departamento INT,
    @Correo_Google NVARCHAR(100)
)
AS
BEGIN
    DECLARE @ID_Usuario INT;
    SELECT @ID_Usuario = ID_Usuario FROM Usuarios WHERE Correo_Google = @Correo_Google;

    DELETE FROM Usuarios_Espacios WHERE ID_Usuario = @ID_Usuario AND ID_Departamento = @ID_Departamento;
END
GO

CREATE OR ALTER PROCEDURE spObtenerSolicitudesPendientes(
    @ID_Departamento INT
)
AS
BEGIN
    SELECT 
        s.ID_Solicitud,
        u.Correo_Google,
        s.Fecha_Solicitud
    FROM Solicitudes_Acceso s
    INNER JOIN Usuarios u ON s.ID_Usuario = u.ID_Usuario
    WHERE s.ID_Departamento = @ID_Departamento AND s.Estatus = 'Pendiente';
END
GO

CREATE OR ALTER PROCEDURE spRechazarSolicitud(
    @ID_Solicitud INT
)
AS
BEGIN
    BEGIN TRY
        -- Cambiamos el estatus para que ya no aparezca como pendiente
        UPDATE Solicitudes_Acceso 
        SET Estatus = 'Rechazado' 
        WHERE ID_Solicitud = @ID_Solicitud AND Estatus = 'Pendiente';
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH
END
GO
-- 1. Obtener solicitudes pendientes de un espacio
-- 1. Obtener solicitudes pendientes de un espacio
CREATE OR ALTER PROCEDURE spObtenerSolicitudesPendientes(
    @ID_Departamento INT
)
AS
BEGIN
    SELECT 
        s.ID_Solicitud,
        u.Correo_Google,
        s.Fecha_Solicitud
    FROM Solicitudes_Acceso s
    INNER JOIN Usuarios u ON s.ID_Usuario = u.ID_Usuario
    WHERE s.ID_Departamento = @ID_Departamento AND s.Estatus = 'Pendiente';
END
GO


-- 1. Procedimiento para listar los miembros de un departamento
CREATE PROCEDURE spObtenerMiembrosEspacio(
    @ID_Departamento INT
)
AS
BEGIN
    SELECT 
        u.ID_Usuario, 
        u.Correo_Google, 
        r.Nombre_Rol, 
        ue.Fecha_Ingreso,
        ue.ID_Rol
    FROM Usuarios_Espacios ue
    INNER JOIN Usuarios u ON ue.ID_Usuario = u.ID_Usuario
    INNER JOIN Cat_Roles r ON ue.ID_Rol = r.ID_Rol
    WHERE ue.ID_Departamento = @ID_Departamento;
END
GO

-- 2. Procedimiento para revocar el acceso a un usuario
CREATE PROCEDURE spQuitarAccesoEspacio(
    @ID_Usuario INT,
    @ID_Departamento INT
)
AS
BEGIN
    BEGIN TRY
        -- Verificamos que no sea el último Super Admin para no dejar huérfano el espacio
        DECLARE @TotalAdmins INT;
        SELECT @TotalAdmins = COUNT(*) FROM Usuarios_Espacios 
        WHERE ID_Departamento = @ID_Departamento AND ID_Rol = 1;

        DECLARE @RolAEliminar INT;
        SELECT @RolAEliminar = ID_Rol FROM Usuarios_Espacios 
        WHERE ID_Usuario = @ID_Usuario AND ID_Departamento = @ID_Departamento;

        IF @RolAEliminar = 1 AND @TotalAdmins <= 1
        BEGIN
            RAISERROR('No puedes eliminar al único Super Administrador del espacio.', 16, 1);
        END
        ELSE
        BEGIN
            DELETE FROM Usuarios_Espacios
            WHERE ID_Usuario = @ID_Usuario AND ID_Departamento = @ID_Departamento;
        END
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH
END
GO

ALTER PROCEDURE spCrearEspacioTrabajo(
    @Nombre_Departamento VARCHAR(100),
    @Contrasena_Area VARCHAR(255),
    @Correo_Creador VARCHAR(150)
)
AS
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION
        
        DECLARE @ID_Nuevo_Depto INT;
        DECLARE @ID_Usuario INT;
        DECLARE @NuevoCodigo VARCHAR(10);

        -- Generar un código aleatorio de 6 caracteres alfanuméricos
        SET @NuevoCodigo = UPPER(SUBSTRING(REPLACE(NEWID(), '-', ''), 1, 6));

        -- 1. Obtener el ID del usuario que está creando el espacio
        SET @ID_Usuario = (SELECT ID_Usuario FROM Usuarios WHERE Correo_Google = @Correo_Creador);

        -- 2. Crear el nuevo espacio con su código
        INSERT INTO Cat_Departamentos (Nombre_Departamento, Contrasena_Area, Estatus, Codigo_Union)
        VALUES (@Nombre_Departamento, @Contrasena_Area, 1, @NuevoCodigo);

        SET @ID_Nuevo_Depto = SCOPE_IDENTITY();

        -- 3. Vincular al creador con el Rol 1 (Super Admin)
        INSERT INTO Usuarios_Espacios (ID_Usuario, ID_Departamento, ID_Rol, Fecha_Ingreso)
        VALUES (@ID_Usuario, @ID_Nuevo_Depto, 1, GETDATE());

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION
        PRINT ERROR_MESSAGE();
    END CATCH
END
GO

CREATE PROCEDURE spSolicitarAcceso(
    @Correo_Google VARCHAR(150),
    @Codigo_Union VARCHAR(10)
)
AS
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION
        
        DECLARE @ID_Usuario INT;
        DECLARE @ID_Departamento INT;

        -- 1. Validar que el código exista
        SELECT @ID_Departamento = ID_Departamento FROM Cat_Departamentos 
        WHERE Codigo_Union = @Codigo_Union AND Estatus = 1;

        IF @ID_Departamento IS NULL
        BEGIN
            RAISERROR('El código de espacio no existe o está inactivo.', 16, 1);
        END

        -- 2. Obtener o registrar al usuario si es su primera vez en el sistema
        IF EXISTS(SELECT 1 FROM Usuarios WHERE Correo_Google = @Correo_Google)
        BEGIN
            SET @ID_Usuario = (SELECT ID_Usuario FROM Usuarios WHERE Correo_Google = @Correo_Google);
        END
        ELSE
        BEGIN
            INSERT INTO Usuarios (Correo_Google, Estatus) VALUES (@Correo_Google, 1);
            SET @ID_Usuario = SCOPE_IDENTITY();
        END

        -- 3. Validar si ya pertenece al espacio
        IF EXISTS(SELECT 1 FROM Usuarios_Espacios WHERE ID_Usuario = @ID_Usuario AND ID_Departamento = @ID_Departamento)
        BEGIN
            RAISERROR('Ya perteneces a este espacio de trabajo.', 16, 1);
        END

        -- 4. Validar si ya tiene una solicitud pendiente
        IF EXISTS(SELECT 1 FROM Solicitudes_Acceso WHERE ID_Usuario = @ID_Usuario AND ID_Departamento = @ID_Departamento AND Estatus = 'Pendiente')
        BEGIN
            RAISERROR('Ya enviaste una solicitud a este espacio. Espera a que un administrador la apruebe.', 16, 1);
        END

        -- 5. Registrar la solicitud
        INSERT INTO Solicitudes_Acceso (ID_Usuario, ID_Departamento, Estatus, Fecha_Solicitud)
        VALUES (@ID_Usuario, @ID_Departamento, 'Pendiente', GETDATE());

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH
END
GO

CREATE PROCEDURE spInvitarUsuario(
    @Correo_Invitado VARCHAR(150),
    @ID_Departamento INT,
    @ID_Rol INT
)
AS
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION
        
        DECLARE @ID_Usuario INT;

        -- 1. Verificar si el usuario ya existe en la base general (ha entrado antes)
        IF EXISTS(SELECT 1 FROM Usuarios WHERE Correo_Google = @Correo_Invitado)
        BEGIN
            SET @ID_Usuario = (SELECT ID_Usuario FROM Usuarios WHERE Correo_Google = @Correo_Invitado);
        END
        ELSE
        BEGIN
            -- Si es completamente nuevo, lo pre-registramos en el sistema
            INSERT INTO Usuarios (Correo_Google, Estatus) VALUES (@Correo_Invitado, 1);
            SET @ID_Usuario = SCOPE_IDENTITY();
        END

        -- 2. Verificar si ya está invitado o pertenece a este departamento
        IF EXISTS(SELECT 1 FROM Usuarios_Espacios WHERE ID_Usuario = @ID_Usuario AND ID_Departamento = @ID_Departamento)
        BEGIN
            RAISERROR('El usuario ya pertenece a este espacio de trabajo.', 16, 1);
        END
        ELSE
        BEGIN
            -- 3. Vincularlo al espacio con su Rol
            INSERT INTO Usuarios_Espacios (ID_Usuario, ID_Departamento, ID_Rol, Fecha_Ingreso)
            VALUES (@ID_Usuario, @ID_Departamento, @ID_Rol, GETDATE());
        END

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH
END

-- =========================================================================
-- REQUISITO 3: Procedimiento para Cambiar Contraseña del Área
-- =========================================================================
Create procedure spCambiarPasswordArea(
   @ID_Departamento int,
   @ContrasenaActual varchar(255),
   @NuevaContrasena varchar(255),
   @FilasAfectadas int output
)as
Begin
   begin Try
      Begin Transaction
      
      set @FilasAfectadas = 0
      declare @idAreaValida int
      set @idAreaValida = (select ID_Departamento from Cat_Departamentos where ID_Departamento = @ID_Departamento and Contrasena_Area = @ContrasenaActual)
      
      if @idAreaValida is not null
      begin
         update Cat_Departamentos set Contrasena_Area = @NuevaContrasena where ID_Departamento = @ID_Departamento
         set @FilasAfectadas = @@ROWCOUNT
         print 'La contraseña del área ha sido actualizada exitosamente'
      end
      else
      begin
          print 'La contraseña actual que proporcionaste no coincide con la base de datos'
      end
      
      Commit Transaction
   End Try
   Begin Catch
      RollBack Transaction
   end Catch
end
GO

CREATE PROCEDURE spCrearEspacioTrabajo(
    @Nombre_Departamento VARCHAR(100),
    @Contrasena_Area VARCHAR(255),
    @Correo_Creador VARCHAR(150)
)
AS
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION
        
        DECLARE @ID_Nuevo_Depto INT;
        DECLARE @ID_Usuario INT;

        -- 1. Obtener el ID del usuario que está creando el espacio
        SET @ID_Usuario = (SELECT ID_Usuario FROM Usuarios WHERE Correo_Google = @Correo_Creador);

        -- 2. Crear el nuevo espacio en Cat_Departamentos
        INSERT INTO Cat_Departamentos (Nombre_Departamento, Contrasena_Area, Estatus)
        VALUES (@Nombre_Departamento, @Contrasena_Area, 1);

        -- Obtener el ID generado para este nuevo departamento
        SET @ID_Nuevo_Depto = SCOPE_IDENTITY();

        -- 3. Vincular al creador con este espacio asignándole el Rol 1 (Super Admin)
        INSERT INTO Usuarios_Espacios (ID_Usuario, ID_Departamento, ID_Rol, Fecha_Ingreso)
        VALUES (@ID_Usuario, @ID_Nuevo_Depto, 1, GETDATE());

        PRINT 'Espacio creado y Super Administrador asignado correctamente.';

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION
        PRINT ERROR_MESSAGE();
    END CATCH
END

-- 6. Alta de Archivo de Google Drive
Create procedure spAltaArchivoDrive(
   @ID_Compensacion int,
   @GoogleDriveFileID varchar(250),
   @NombreArchivo varchar(255)
)as
Begin
   begin Try
      Begin Transaction
      
      declare @idNuevoArchivo int
      set @idNuevoArchivo = (select ID_Archivo from Archivos_Compensacion where Google_Drive_File_ID = @GoogleDriveFileID)
      
      if @idNuevoArchivo is null
      begin
         insert into Archivos_Compensacion (ID_Compensacion, Nombre_Archivo, Google_Drive_File_ID, Fecha_Generacion)
         values(@ID_Compensacion, @NombreArchivo, @GoogleDriveFileID, GETDATE())
         print 'El archivo '+ @NombreArchivo +' ha sido dado de alta exitosamente'
      end
      else
      begin
          print 'El archivo de Drive que pretendes registrar ya existe'
      end
      
      Commit Transaction
   End Try
   Begin Catch
      RollBack Transaction
   end Catch
end
GO

-- =========================================================================
-- REQUISITO 2: Procedimiento de Logueo (Para el espacio de trabajo protegido)
-- =========================================================================
Create procedure spValidarLogueoArea(
   @ID_Departamento int,
   @ContrasenaProporcionada varchar(255),
   @EsValido bit output
)as
Begin
   begin Try
      Begin Transaction
      
      set @EsValido = 0
      declare @idAreaValida int
      set @idAreaValida = (select ID_Departamento from Cat_Departamentos where ID_Departamento = @ID_Departamento and Contrasena_Area = @ContrasenaProporcionada)
      
      if @idAreaValida is not null
      begin
         set @EsValido = 1
         print 'Credenciales aceptadas. El área ha sido desbloqueada exitosamente'
      end
      else
      begin
          print 'La contraseña que pretendes usar es incorrecta para esta área'
      end
      
      Commit Transaction
   End Try
   Begin Catch
      RollBack Transaction
   end Catch
end
GO

-- 3. Baja Lógica de Póliza (Rechazar)
Create procedure spBajaPoliza(
   @ID_Registro int
)as
Begin
   begin Try
      Begin Transaction
      
      declare @idPolizaExistente int
      -- Solo podemos dar de baja si está pendiente o en revisión
      set @idPolizaExistente = (select ID_Registro from Polizas_Registro where ID_Registro = @ID_Registro and Estado_Compensacion IN ('Pendiente', 'En Revisión'))
      
      if @idPolizaExistente is not null
      begin
         -- Cambiamos el estado a Rechazada (Soft Delete)
         update Polizas_Registro set Estado_Compensacion = 'Rechazada' where ID_Registro = @ID_Registro
         print 'La póliza ha sido rechazada/dada de baja exitosamente'
      end
      else
      begin
          print 'La póliza que pretendes dar de baja no existe o ya está procesada'
      end
      
      Commit Transaction
   End Try
   Begin Catch
      RollBack Transaction
   end Catch
end
GO

-- 4. Alta de Compensación (Uniendo Faltante y Sobrante)
Create procedure spAltaCompensacion(
   @ID_Poliza_Faltante int,
   @ID_Poliza_Sobrante int,
   @ID_Usuario_Validador int,
   @Comentario_Resolucion varchar(MAX)
)as
Begin
   begin Try
      Begin Transaction
      
      declare @idCompensacionExistente int
      set @idCompensacionExistente = (select ID_Compensacion from Compensaciones_Realizadas where ID_Poliza_Faltante = @ID_Poliza_Faltante OR ID_Poliza_Sobrante = @ID_Poliza_Sobrante)
      
      if @idCompensacionExistente is null
      begin
         insert into Compensaciones_Realizadas (ID_Poliza_Faltante, ID_Poliza_Sobrante, ID_Usuario_Validador, Fecha_Validacion, Comentario_Resolucion)
         values(@ID_Poliza_Faltante, @ID_Poliza_Sobrante, @ID_Usuario_Validador, GETDATE(), @Comentario_Resolucion)
         
         -- Actualizamos el estatus de las dos pólizas (faltante y sobrante) a "Compensada"
         update Polizas_Registro set Estado_Compensacion = 'Compensada' where ID_Registro IN (@ID_Poliza_Faltante, @ID_Poliza_Sobrante)
         
         print 'La compensación ha sido dada de alta exitosamente'
      end
      else
      begin
          print 'Una de las pólizas que pretendes compensar ya tiene una compensación'
      end
      
      Commit Transaction
   End Try
   Begin Catch
      RollBack Transaction
   end Catch
end
GO

-- 5. Alta de Usuario (Para el administrador)
Create procedure spAltaUsuario(
   @Correo varchar(150),
   @Nombre varchar(150),
   @ID_Rol int,
   @ID_Departamento int
)as
Begin
   begin Try
      Begin Transaction
      
      declare @idNuevoUsuario int
      set @idNuevoUsuario = (select ID_Usuario from Usuarios where Correo_Google = @Correo)
      
      if @idNuevoUsuario is null
      begin
         insert into Usuarios (Correo_Google, Nombre_Completo, ID_Rol, ID_Departamento, Estatus)
         values(@Correo, @Nombre, @ID_Rol, @ID_Departamento, 1)
         print 'El usuario '+ @Nombre +' ha sido dado de alta exitosamente'
      end
      else
      begin
          print 'El usuario que pretendes dar de alta ya existe'
      end
      
      Commit Transaction
   End Try
   Begin Catch
      RollBack Transaction
   end Catch
end
GO


-- =========================================================================
-- REQUISITO 1: 6 Procedimientos Almacenados de Manipulación (CRUD Operativo)
-- =========================================================================

-- 1. Alta de Póliza
Create procedure spAltaPoliza(
   @Numero_Poliza int,
   @ID_Centro int,
   @Codigo_SKU int,
   @Tipo_Irregularidad varchar(20),
   @Cantidad int,
   @Costo_Total_Movimiento decimal(18,2),
   @Concepto_Original varchar(255),
   @Origen_Captura varchar(50),
   @ID_Usuario_Captura int
)as
Begin
   begin Try
      Begin Transaction
      
      declare @idNuevaPoliza int
      -- Validamos que no se registre el mismo número de póliza y SKU el mismo día por error
      set @idNuevaPoliza = (select top 1 ID_Registro from Polizas_Registro where Numero_Poliza = @Numero_Poliza and Codigo_SKU = @Codigo_SKU and CAST(Fecha_Registro as DATE) = CAST(GETDATE() as DATE))
      
      if @idNuevaPoliza is null
      begin
         insert into Polizas_Registro (Numero_Poliza, Fecha_Registro, ID_Centro, Codigo_SKU, Tipo_Irregularidad, Cantidad, Costo_Total_Movimiento, Concepto_Original, Estado_Compensacion, Origen_Captura, ID_Usuario_Captura)
         values(@Numero_Poliza, GETDATE(), @ID_Centro, @Codigo_SKU, @Tipo_Irregularidad, @Cantidad, @Costo_Total_Movimiento, @Concepto_Original, 'Pendiente', @Origen_Captura, @ID_Usuario_Captura)
         print 'La póliza número '+ CAST(@Numero_Poliza AS VARCHAR) +' ha sido dada de alta exitosamente'
      end
      else
      begin
          print 'La póliza que pretendes registrar ya existe en la base de datos'
      end
      
      Commit Transaction
   End Try
   Begin Catch
      RollBack Transaction
      print ERROR_MESSAGE()
   end Catch
end
GO

-- 2. Actualizar Póliza (Antes de que sea compensada)
Create procedure spActualizarPoliza(
   @ID_Registro int,
   @NuevoCosto decimal(18,2),
   @NuevoConcepto varchar(255)
)as
Begin
   begin Try
      Begin Transaction
      
      declare @idPolizaExistente int
      set @idPolizaExistente = (select ID_Registro from Polizas_Registro where ID_Registro = @ID_Registro)
      
      if @idPolizaExistente is not null
      begin
         update Polizas_Registro set Costo_Total_Movimiento = @NuevoCosto, Concepto_Original = @NuevoConcepto where ID_Registro = @ID_Registro
         print 'La póliza ha sido actualizada exitosamente'
      end
      else
      begin
          print 'La póliza que pretendes actualizar no existe en la base de datos'
      end
      
      Commit Transaction
   End Try
   Begin Catch
      RollBack Transaction
   end Catch
end
GO




CREATE OR ALTER PROCEDURE spInsertarOperacion (
    @ID_Departamento INT,
    @Correo_Google NVARCHAR(100),
    @Mes NVARCHAR(20),
    @Tienda_Bodega NVARCHAR(50),
    @Poliza NVARCHAR(50),
    @Fecha DATE,
    @Tipo NVARCHAR(50),
    @Cantidad INT,
    @Articulo NVARCHAR(150),
    @Marca_Dep NVARCHAR(50),
    @Modelo_Clase NVARCHAR(50),
    @Familia NVARCHAR(50),
    @Codigo NVARCHAR(50),
    @Vale NVARCHAR(50),
    @Precio_Unidad DECIMAL(18, 2),
    @Precio_Venta DECIMAL(18, 2),
    @Centro NVARCHAR(50),
    @Concepto NVARCHAR(255),
    @Comentarios NVARCHAR(MAX),
    @Poliza_Referencia NVARCHAR(100),
    @SKU NVARCHAR(100),
    @Autorizacion NVARCHAR(255)
)
AS
BEGIN
    BEGIN TRY
        DECLARE @ID_Usuario INT;
        SELECT @ID_Usuario = ID_Usuario FROM Usuarios WHERE Correo_Google = @Correo_Google;

        IF @ID_Usuario IS NULL
        BEGIN
            RAISERROR('Usuario no encontrado.', 16, 1);
            RETURN;
        END

        INSERT INTO Operacion_Compensaciones (
            ID_Departamento, ID_Usuario, Mes, Tienda_Bodega, Poliza, Fecha, Tipo, Cantidad, 
            Articulo, Marca_Dep, Modelo_Clase, Familia, Codigo, Vale, Precio_Unidad, Precio_Venta, 
            Centro, Concepto, Comentarios, Poliza_Referencia, SKU, Autorizacion
        )
        VALUES (
            @ID_Departamento, @ID_Usuario, @Mes, @Tienda_Bodega, @Poliza, @Fecha, @Tipo, @Cantidad, 
            @Articulo, @Marca_Dep, @Modelo_Clase, @Familia, @Codigo, @Vale, @Precio_Unidad, @Precio_Venta, 
            @Centro, @Concepto, @Comentarios, @Poliza_Referencia, @SKU, @Autorizacion
        );

    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH
END
GO


USE CEDIS_Compensaciones_DB;
GO

CREATE OR ALTER PROCEDURE spObtenerOperacionesPorEspacio (
    @ID_Departamento INT
)
AS
BEGIN
    SELECT 
        o.ID_Registro, o.Mes, o.Tienda_Bodega, o.Poliza, o.Fecha, o.Tipo, 
        o.Cantidad, o.Articulo, o.Marca_Dep, o.Modelo_Clase, o.Familia, 
        o.Codigo, o.Vale, o.Precio_Unidad, o.Precio_Venta, o.Centro, 
        o.Concepto, o.Comentarios, o.Poliza_Referencia, o.SKU, o.Autorizacion,
        u.Correo_Google AS Responsable
    FROM Operacion_Compensaciones o
    INNER JOIN Usuarios u ON o.ID_Usuario = u.ID_Usuario
    WHERE o.ID_Departamento = @ID_Departamento AND o.Estatus = 1
    ORDER BY o.Fecha DESC, o.ID_Registro DESC;
END
GO

USE CEDIS_Compensaciones_DB;
GO

CREATE OR ALTER TRIGGER trg_Auditoria_Operaciones
ON Operacion_Compensaciones
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Accion VARCHAR(50);

    -- Detectar qué tipo de acción se ejecutó
    IF EXISTS(SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted)
        SET @Accion = 'UPDATE';
    ELSE IF EXISTS(SELECT * FROM inserted)
        SET @Accion = 'INSERT';
    ELSE IF EXISTS(SELECT * FROM deleted)
        SET @Accion = 'DELETE';
    ELSE
        RETURN;

    -- 1. CASO INSERT: Se guarda el registro indicando que es nuevo
    IF @Accion = 'INSERT'
    BEGIN
        INSERT INTO Bitacora_Auditoria (ID_Usuario_Accion, Tabla_Afectada, ID_Registro_Afectado, Accion, Valor_Anterior)
        SELECT 
            i.ID_Usuario, 
            'Operacion_Compensaciones', 
            i.ID_Registro, 
            'INSERT', 
            'Nuevo registro. Creado en el sistema.'
        FROM inserted i;
    END

    -- 2. CASO UPDATE: Se guarda la versión vieja del registro (el de la tabla 'deleted')
    IF @Accion = 'UPDATE'
    BEGIN
        INSERT INTO Bitacora_Auditoria (ID_Usuario_Accion, Tabla_Afectada, ID_Registro_Afectado, Accion, Valor_Anterior)
        SELECT 
            i.ID_Usuario, 
            'Operacion_Compensaciones', 
            i.ID_Registro, 
            'UPDATE', 
            -- Transformamos la fila vieja a texto JSON para guardarla en Valor_Anterior
            (SELECT d2.* FROM deleted d2 WHERE d2.ID_Registro = i.ID_Registro FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        FROM inserted i;
    END

    -- 3. CASO DELETE: Se guarda cómo estaba el registro antes de desaparecer por completo
    IF @Accion = 'DELETE'
    BEGIN
        INSERT INTO Bitacora_Auditoria (ID_Usuario_Accion, Tabla_Afectada, ID_Registro_Afectado, Accion, Valor_Anterior)
        SELECT 
            d.ID_Usuario, 
            'Operacion_Compensaciones', 
            d.ID_Registro, 
            'DELETE', 
            (SELECT d3.* FROM deleted d3 WHERE d3.ID_Registro = d.ID_Registro FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        FROM deleted d;
    END
END
GO

USE CEDIS_Compensaciones_DB;
GO

CREATE OR ALTER PROCEDURE spObtenerOperacionesPorEspacio (
    @ID_Departamento INT
)
AS
BEGIN
    SELECT 
        o.ID_Registro, o.Mes, o.Tienda_Bodega, o.Poliza, o.Fecha, o.Tipo, 
        o.Cantidad, o.Articulo, o.Marca_Dep, o.Modelo_Clase, o.Familia, 
        o.Codigo, o.Vale, o.Precio_Unidad, o.Precio_Venta, o.Centro, 
        o.Concepto, o.Comentarios, o.Poliza_Referencia, o.SKU, o.Autorizacion,
        o.Fecha_Registro, -- <- IMPORTANTE: Agregamos la fecha de registro
        u.Correo_Google AS Responsable
    FROM Operacion_Compensaciones o
    INNER JOIN Usuarios u ON o.ID_Usuario = u.ID_Usuario
    WHERE o.ID_Departamento = @ID_Departamento AND o.Estatus = 1
    ORDER BY o.Fecha DESC, o.ID_Registro DESC;
END
GO


USE CEDIS_Compensaciones_DB;
GO

-- 1. PROCEDIMIENTO PARA ACTUALIZAR
CREATE OR ALTER PROCEDURE spActualizarOperacion (
    @ID_Registro INT,
    @ID_Departamento INT,
    @Mes NVARCHAR(20),
    @Tienda_Bodega NVARCHAR(50),
    @Poliza NVARCHAR(50),
    @Fecha DATE,
    @Tipo NVARCHAR(50),
    @Cantidad INT,
    @Articulo NVARCHAR(150),
    @Marca_Dep NVARCHAR(50),
    @Modelo_Clase NVARCHAR(50),
    @Familia NVARCHAR(50),
    @Codigo NVARCHAR(50),
    @Vale NVARCHAR(50),
    @Precio_Unidad DECIMAL(18, 2),
    @Precio_Venta DECIMAL(18, 2),
    @Centro NVARCHAR(50),
    @Concepto NVARCHAR(255),
    @Comentarios NVARCHAR(MAX),
    @Poliza_Referencia NVARCHAR(100),
    @SKU NVARCHAR(100),
    @Autorizacion NVARCHAR(255)
)
AS
BEGIN
    UPDATE Operacion_Compensaciones
    SET Mes = @Mes, Tienda_Bodega = @Tienda_Bodega, Poliza = @Poliza, Fecha = @Fecha, 
        Tipo = @Tipo, Cantidad = @Cantidad, Articulo = @Articulo, Marca_Dep = @Marca_Dep, 
        Modelo_Clase = @Modelo_Clase, Familia = @Familia, Codigo = @Codigo, Vale = @Vale, 
        Precio_Unidad = @Precio_Unidad, Precio_Venta = @Precio_Venta, Centro = @Centro, 
        Concepto = @Concepto, Comentarios = @Comentarios, Poliza_Referencia = @Poliza_Referencia, 
        SKU = @SKU, Autorizacion = @Autorizacion
    WHERE ID_Registro = @ID_Registro AND ID_Departamento = @ID_Departamento;
END
GO

-- 2. PROCEDIMIENTO PARA ELIMINAR (Manda a Estatus 0, pero la bitácora lo guarda)
CREATE OR ALTER PROCEDURE spEliminarOperacion (
    @ID_Registro INT,
    @ID_Departamento INT
)
AS
BEGIN
    UPDATE Operacion_Compensaciones
    SET Estatus = 0
    WHERE ID_Registro = @ID_Registro AND ID_Departamento = @ID_Departamento;
END
GO

USE CEDIS_Compensaciones_DB;
GO

CREATE OR ALTER PROCEDURE spEliminarOperacion (
    @ID_Registro INT,
    @ID_Departamento INT
)
AS
BEGIN
    -- Se elimina físicamente el registro de la tabla
    DELETE FROM Operacion_Compensaciones
    WHERE ID_Registro = @ID_Registro AND ID_Departamento = @ID_Departamento;
END
GO