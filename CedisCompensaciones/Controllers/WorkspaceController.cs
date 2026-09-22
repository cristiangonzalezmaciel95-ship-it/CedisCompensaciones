using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.AspNetCore.Authorization;
using System.Data;
using System.Security.Claims; 
using System.Net;
using System.Net.Mail;

namespace CedisCompensaciones.Controllers
{
    [Authorize] 
    public class WorkspaceController : Controller
    {
        private readonly string _cadenaConexion;

        public WorkspaceController(IConfiguration configuracion)
        {
            _cadenaConexion = configuracion.GetConnectionString("ConexionSQL")!;
        }

        public IActionResult Hub()
        {
            var correoActual = User.FindFirstValue(ClaimTypes.Email);
            var misEspacios = new List<Dictionary<string, string>>();

            using (SqlConnection con = new SqlConnection(_cadenaConexion))
            {
                con.Open();
                string query = @"
                    SELECT 
                        d.ID_Departamento, 
                        d.Nombre_Departamento, 
                        r.Nombre_Rol,
                        d.Codigo_Union 
                    FROM Usuarios_Espacios ue
                    INNER JOIN Usuarios u ON ue.ID_Usuario = u.ID_Usuario
                    INNER JOIN Cat_Departamentos d ON ue.ID_Departamento = d.ID_Departamento
                    INNER JOIN Cat_Roles r ON ue.ID_Rol = r.ID_Rol
                    WHERE u.Correo_Google = @correo AND d.Estatus = 1";
                using (SqlCommand cmd = new SqlCommand(query, con))
                {
                    cmd.Parameters.AddWithValue("@correo", correoActual);
                    using (SqlDataReader reader = cmd.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            var espacio = new Dictionary<string, string>();
                            espacio["ID"] = reader["ID_Departamento"].ToString()!;
                            espacio["Nombre"] = reader["Nombre_Departamento"].ToString()!;
                            espacio["Rol"] = reader["Nombre_Rol"].ToString()!;
                            espacio["Codigo"] = reader["Codigo_Union"].ToString()!;
                            misEspacios.Add(espacio);
                        }
                    }
                }
            }

            return View(misEspacios);
        }

        public IActionResult CrearEspacio()
        {
            return View();
        }

        [HttpPost]
        public IActionResult EnviarSolicitudUnion(string codigoUnion)
        {
            var correoActual = User.FindFirstValue(ClaimTypes.Email);
            // Capturamos tu nombre de Google, si no existe manda "Usuario Pendiente"
            var nombreActual = User.FindFirstValue(ClaimTypes.Name) ?? "Usuario Pendiente"; 
            var correosAdmins = new List<string>();
            string nombreEspacio = "";

            try
            {
                using (SqlConnection con = new SqlConnection(_cadenaConexion))
                {
                    con.Open();
                    using (SqlCommand cmd = new SqlCommand("spSolicitarAcceso", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@Correo_Google", correoActual);
                        cmd.Parameters.AddWithValue("@Codigo_Union", codigoUnion.Trim().ToUpper());
                        cmd.ExecuteNonQuery();
                    }

                    string queryAdmin = @"
                        SELECT u.Correo_Google, d.Nombre_Departamento
                        FROM Usuarios_Espacios ue
                        INNER JOIN Usuarios u ON ue.ID_Usuario = u.ID_Usuario
                        INNER JOIN Cat_Departamentos d ON ue.ID_Departamento = d.ID_Departamento
                        WHERE d.Codigo_Union = @Codigo AND ue.ID_Rol = 1 AND d.Estatus = 1";
                    
                    using (SqlCommand cmdAdmin = new SqlCommand(queryAdmin, con))
                    {
                        cmdAdmin.Parameters.AddWithValue("@Codigo", codigoUnion.Trim().ToUpper());
                        using (SqlDataReader reader = cmdAdmin.ExecuteReader())
                        {
                            while (reader.Read())
                            {
                                nombreEspacio = reader["Nombre_Departamento"].ToString()!;
                                correosAdmins.Add(reader["Correo_Google"].ToString()!);
                            }
                        }
                    }
                }

                string linkPlataforma = Url.Action("Hub", "Workspace", null, Request.Scheme)!;

                foreach(var adminEmail in correosAdmins)
                {
                    EnviarCorreoNotificacionSolicitud(adminEmail, correoActual!, nombreEspacio, linkPlataforma);
                }

                TempData["MensajeExito"] = "Solicitud enviada. El administrador ha sido notificado.";
            }
            catch (Exception ex)
            {
                TempData["ErrorWorkspace"] = ex.Message;
            }

            return RedirectToAction("Hub");
        }

        private void EnviarCorreoNotificacionSolicitud(string correoAdmin, string correoSolicitante, string nombreEspacio, string linkAcceso)
        {
            try
            {
                string miCorreo = "cristiangonzalezmaciel95@gmail.com"; 
                string miPasswordApp = "vcut tgvw hrru lhmp"; 

                MailMessage mail = new MailMessage();
                mail.From = new MailAddress(miCorreo, "Sistema CEDIS");
                mail.To.Add(correoAdmin);
                mail.Subject = $"Nueva solicitud de acceso: {nombreEspacio}";
                mail.IsBodyHtml = true;

                mail.Body = $@"
                    <div style='font-family: Arial, sans-serif; max-width: 600px; padding: 20px; border: 1px solid #dadce0; border-radius: 8px;'>
                        <h3 style='color: #1a73e8; margin-top: 0;'>Alguien quiere unirse a tu espacio</h3>
                        <p>El usuario <strong>{correoSolicitante}</strong> ha ingresado el código de tu departamento <strong>{nombreEspacio}</strong> y está esperando tu aprobación.</p>
                        
                        <div style='text-align: center; margin: 30px 0;'>
                            <a href='{linkAcceso}' style='background-color: #1a73e8; color: white; padding: 12px 24px; text-decoration: none; border-radius: 4px; font-weight: bold; display: inline-block;'>
                                Abrir Sistema CEDIS
                            </a>
                        </div>
                        
                        <p style='color: #5f6368; font-size: 13px;'>Selecciona tu espacio en el Hub, ingresa tu contraseña y ve a la sección de 'Invitar Usuarios' para aceptar o rechazar la solicitud.</p>
                    </div>";

                SmtpClient smtp = new SmtpClient("smtp.gmail.com", 587)
                {
                    Credentials = new NetworkCredential(miCorreo, miPasswordApp),
                    EnableSsl = true
                };
                smtp.Send(mail);
            }
            catch (Exception) { }
        }

        [HttpPost]
        public IActionResult GuardarNuevoEspacio(string nombreDepartamento, string contrasenaArea, string codigoUnion)
        {
            var correoCreador = User.FindFirstValue(ClaimTypes.Email);
            // Capturamos tu nombre de Google, si no existe manda "Usuario Creador"
            var nombreActual = User.FindFirstValue(ClaimTypes.Name) ?? "Usuario Creador"; 

            try
            {
                string codigoFinal = string.IsNullOrEmpty(codigoUnion) ? "CEDIS1" : codigoUnion.Trim().ToUpper();

                using (SqlConnection con = new SqlConnection(_cadenaConexion))
                {
                    using (SqlCommand cmd = new SqlCommand("spCrearEspacioConValidacion", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@Nombre_Departamento", nombreDepartamento.Trim());
                        cmd.Parameters.AddWithValue("@Contrasena_Area", contrasenaArea);
                        cmd.Parameters.AddWithValue("@Correo_Creador", correoCreador);
                        
                        cmd.Parameters.AddWithValue("@Codigo_Union", codigoFinal);

                        con.Open();
                        cmd.ExecuteNonQuery();
                    }
                }

                TempData["MensajeExito"] = $"El espacio '{nombreDepartamento}' fue creado exitosamente. Ya eres Super Administrador.";
            }
            catch (Exception ex)
            {
                if (ex.Message.Contains("Ya tienes un proyecto creado con este nombre"))
                {
                    TempData["ErrorWorkspace"] = $"No se pudo crear el proyecto. Ya tienes otro espacio creado con el nombre '{nombreDepartamento}'.";
                }
                else
                {
                    TempData["ErrorWorkspace"] = "Ocurrió un error inesperado al intentar crear el espacio: " + ex.Message;
                }
            }

            return RedirectToAction("Hub");
        }

        [HttpPost]
        public IActionResult EliminarProyecto(int idDepartamento, string contrasenaConfirmacion)
        {
            var correoActual = User.FindFirstValue(ClaimTypes.Email);
            try
            {
                using (SqlConnection con = new SqlConnection(_cadenaConexion))
                {
                    using (SqlCommand cmd = new SqlCommand("spEliminarProyectoCompleto", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@ID_Departamento", idDepartamento);
                        cmd.Parameters.AddWithValue("@ContrasenaProporcionada", contrasenaConfirmacion);
                        cmd.Parameters.AddWithValue("@Correo_Admin", correoActual);
                        
                        var outParam = new SqlParameter("@Mensaje", SqlDbType.NVarChar, 200) { Direction = ParameterDirection.Output };
                        cmd.Parameters.Add(outParam);
                        
                        con.Open();
                        cmd.ExecuteNonQuery();
                        
                        TempData["MensajeExito"] = outParam.Value.ToString();
                    }
                }
            }
            catch (Exception ex)
            {
                TempData["ErrorWorkspace"] = ex.Message;
            }
            return RedirectToAction("Hub");
        }

        [HttpPost]
        public IActionResult DarDeBaja(int idDepartamento)
        {
            var correoActual = User.FindFirstValue(ClaimTypes.Email);
            try
            {
                using (SqlConnection con = new SqlConnection(_cadenaConexion))
                {
                    using (SqlCommand cmd = new SqlCommand("spDarDeBajaUsuario", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@ID_Departamento", idDepartamento);
                        cmd.Parameters.AddWithValue("@Correo_Google", correoActual);
                        
                        con.Open();
                        cmd.ExecuteNonQuery();
                        
                        TempData["MensajeExito"] = "Te has dado de baja del proyecto exitosamente.";
                    }
                }
            }
            catch (Exception ex)
            {
                TempData["ErrorWorkspace"] = ex.Message;
            }
            return RedirectToAction("Hub");
        }

        public IActionResult UnirseEspacio()
        {
            return Content("Aquí irá la pantalla para UNIRSE a un espacio.");
        }

        [HttpPost]
        public IActionResult VerContrasena(int idDepartamento)
        {
            var correoActual = User.FindFirstValue(ClaimTypes.Email);
            string contrasena = "";

            try
            {
                using (SqlConnection con = new SqlConnection(_cadenaConexion))
                {
                    using (SqlCommand cmd = new SqlCommand("spObtenerPasswordArea", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@ID_Departamento", idDepartamento);
                        cmd.Parameters.AddWithValue("@Correo_Usuario", correoActual);

                        var outParam = new SqlParameter("@ContrasenaArea", SqlDbType.NVarChar, 50) { Direction = ParameterDirection.Output };
                        cmd.Parameters.Add(outParam);

                        con.Open();
                        cmd.ExecuteNonQuery();

                        contrasena = outParam.Value?.ToString() ?? "";
                    }
                }

                if (!string.IsNullOrEmpty(contrasena))
                {
                    TempData["MensajeExito"] = $"La contraseña maestra de este espacio es: {contrasena}";
                }
                else
                {
                    TempData["ErrorWorkspace"] = "No tienes permisos de administrador para ver esta contraseña.";
                }
            }
            catch (Exception ex)
            {
                TempData["ErrorWorkspace"] = ex.Message;
            }

            return RedirectToAction("Hub");
        }

        public IActionResult AccesoSeguro(int idDepartamento = 1)
        {
            ViewBag.ID_Depto = idDepartamento;
            return View();
        }

        [HttpPost]
        public IActionResult ValidarWorkspace(int idDepartamento, string contrasena)
        {
            bool esValido = false;

            using (SqlConnection con = new SqlConnection(_cadenaConexion))
            {
                using (SqlCommand cmd = new SqlCommand("spValidarLogueoArea", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.AddWithValue("@ID_Departamento", idDepartamento);
                    cmd.Parameters.AddWithValue("@ContrasenaProporcionada", contrasena);
                    
                    var outParam = new SqlParameter("@EsValido", SqlDbType.Bit) { Direction = ParameterDirection.Output };
                    cmd.Parameters.Add(outParam);

                    con.Open();
                    cmd.ExecuteNonQuery();
                    esValido = (bool)outParam.Value;
                }
            }

            if (esValido)
            {
                TempData["WorkspaceDesbloqueado"] = true;
                return RedirectToAction("Operacion", new { idDepto = idDepartamento });
            }

            TempData["ErrorWorkspace"] = "Contraseña de área incorrecta. Inténtalo de nuevo.";
            return RedirectToAction("Hub"); 
        }

        public IActionResult CambiarSeguridad(int idDepartamento = 1)
        {
            ViewBag.ID_Depto = idDepartamento;
            ViewBag.EsAdmin = true; 
            return View();
        }

        [HttpPost]
        public IActionResult EjecutarCambioPassword(int idDepartamento, string passActual, string passNueva)
        {
            int filasAfectadas = 0;

            using (SqlConnection con = new SqlConnection(_cadenaConexion))
            {
                using (SqlCommand cmd = new SqlCommand("spCambiarPasswordArea", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.AddWithValue("@ID_Departamento", idDepartamento);
                    cmd.Parameters.AddWithValue("@ContrasenaActual", passActual);
                    cmd.Parameters.AddWithValue("@NuevaContrasena", passNueva);
                    
                    var outParam = new SqlParameter("@FilasAfectadas", SqlDbType.Int) { Direction = ParameterDirection.Output };
                    cmd.Parameters.Add(outParam);

                    con.Open();
                    cmd.ExecuteNonQuery();
                    filasAfectadas = (int)outParam.Value;
                }
            }

            if (filasAfectadas > 0)
            {
                TempData["ExitoPass"] = "Contraseña de seguridad actualizada correctamente.";
            }
            else
            {
                TempData["ErrorPass"] = "La contraseña actual no coincide.";
            }

            return RedirectToAction("CambiarSeguridad", new { idDepartamento = idDepartamento });
        }

        public IActionResult Operacion(int idDepto)
        {
            if (TempData["WorkspaceDesbloqueado"] == null)
            {
                TempData["ErrorWorkspace"] = "Debes ingresar la contraseña para acceder.";
                return RedirectToAction("Hub");
            }
            TempData.Keep("WorkspaceDesbloqueado");

            var correoActual = User.FindFirstValue(ClaimTypes.Email);
            int rolEnEspacio = 0;
            string nombreEspacio = "";
            var listaOperaciones = new List<Dictionary<string, string>>();

            using (SqlConnection con = new SqlConnection(_cadenaConexion))
            {
                con.Open();
                string queryRol = @"
                    SELECT ue.ID_Rol, d.Nombre_Departamento 
                    FROM Usuarios_Espacios ue
                    INNER JOIN Usuarios u ON ue.ID_Usuario = u.ID_Usuario
                    INNER JOIN Cat_Departamentos d ON ue.ID_Departamento = d.ID_Departamento
                    WHERE u.Correo_Google = @correo AND ue.ID_Departamento = @idDepto";
                
                using (SqlCommand cmd = new SqlCommand(queryRol, con))
                {
                    cmd.Parameters.AddWithValue("@correo", correoActual);
                    cmd.Parameters.AddWithValue("@idDepto", idDepto);
                    using (SqlDataReader reader = cmd.ExecuteReader())
                    {
                        if (reader.Read())
                        {
                            rolEnEspacio = Convert.ToInt32(reader["ID_Rol"]);
                            nombreEspacio = reader["Nombre_Departamento"].ToString()!;
                        }
                    }
                }

                using (SqlCommand cmdOps = new SqlCommand("spObtenerOperacionesPorEspacio", con))
                {
                    cmdOps.CommandType = CommandType.StoredProcedure;
                    cmdOps.Parameters.AddWithValue("@ID_Departamento", idDepto);
                    using (SqlDataReader readerOps = cmdOps.ExecuteReader())
                    {
                        while (readerOps.Read())
                        {
                            var op = new Dictionary<string, string>();
                            for (int i = 0; i < readerOps.FieldCount; i++)
                            {
                                op[readerOps.GetName(i)] = readerOps.IsDBNull(i) ? "" : readerOps.GetValue(i).ToString()!;
                            }
                            listaOperaciones.Add(op);
                        }
                    }
                }
            }

            ViewBag.ID_Depto = idDepto;
            ViewBag.NombreEspacio = nombreEspacio;
            ViewBag.EsAdmin = (rolEnEspacio == 1); 
            
            return View(listaOperaciones);
        }

        [HttpPost]
        public IActionResult InsertarOperacion(IFormCollection form)
        {
            int idDepto = Convert.ToInt32(form["idDepartamento"]);
            var correoActual = User.FindFirstValue(ClaimTypes.Email);

            try
            {
                using (SqlConnection con = new SqlConnection(_cadenaConexion))
                {
                    using (SqlCommand cmd = new SqlCommand("spInsertarOperacion", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@ID_Departamento", idDepto);
                        cmd.Parameters.AddWithValue("@Correo_Google", correoActual);
                        
                        cmd.Parameters.AddWithValue("@Mes", form["Mes"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Tienda_Bodega", form["Tienda_Bodega"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Poliza", form["Poliza"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Fecha", string.IsNullOrEmpty(form["Fecha"]) ? DateTime.Now : Convert.ToDateTime(form["Fecha"]));
                        cmd.Parameters.AddWithValue("@Tipo", form["Tipo"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Cantidad", string.IsNullOrEmpty(form["Cantidad"]) ? 0 : Convert.ToInt32(form["Cantidad"]));
                        cmd.Parameters.AddWithValue("@Articulo", form["Articulo"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Marca_Dep", form["Marca_Dep"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Modelo_Clase", form["Modelo_Clase"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Familia", form["Familia"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Codigo", form["Codigo"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Vale", form["Vale"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Precio_Unidad", string.IsNullOrEmpty(form["Precio_Unidad"]) ? 0 : Convert.ToDecimal(form["Precio_Unidad"]));
                        cmd.Parameters.AddWithValue("@Precio_Venta", string.IsNullOrEmpty(form["Precio_Venta"]) ? 0 : Convert.ToDecimal(form["Precio_Venta"]));
                        cmd.Parameters.AddWithValue("@Centro", form["Centro"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Concepto", form["Concepto"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Comentarios", form["Comentarios"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Poliza_Referencia", form["Poliza_Referencia"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@SKU", form["SKU"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Autorizacion", form["Autorizacion"].ToString() ?? "");

                        con.Open();
                        cmd.ExecuteNonQuery();
                    }
                }
                TempData["MensajeExito"] = "Operación registrada correctamente.";
            }
            catch (Exception ex)
            {
                TempData["ErrorWorkspace"] = "Error al guardar: " + ex.Message;
            }

            return RedirectToAction("Operacion", new { idDepto = idDepto });
        }
    
        [HttpPost]
        public IActionResult ActualizarOperacion(IFormCollection form)
        {
            int idDepto = Convert.ToInt32(form["idDepartamento"]);
            int idRegistro = Convert.ToInt32(form["idRegistro"]);

            try
            {
                using (SqlConnection con = new SqlConnection(_cadenaConexion))
                {
                    using (SqlCommand cmd = new SqlCommand("spActualizarOperacion", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@ID_Registro", idRegistro);
                        cmd.Parameters.AddWithValue("@ID_Departamento", idDepto);
                        
                        cmd.Parameters.AddWithValue("@Mes", form["Mes"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Tienda_Bodega", form["Tienda_Bodega"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Poliza", form["Poliza"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Fecha", string.IsNullOrEmpty(form["Fecha"]) ? DateTime.Now : Convert.ToDateTime(form["Fecha"]));
                        cmd.Parameters.AddWithValue("@Tipo", form["Tipo"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Cantidad", string.IsNullOrEmpty(form["Cantidad"]) ? 0 : Convert.ToInt32(form["Cantidad"]));
                        cmd.Parameters.AddWithValue("@Articulo", form["Articulo"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Marca_Dep", form["Marca_Dep"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Modelo_Clase", form["Modelo_Clase"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Familia", form["Familia"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Codigo", form["Codigo"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Vale", form["Vale"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Precio_Unidad", string.IsNullOrEmpty(form["Precio_Unidad"]) ? 0 : Convert.ToDecimal(form["Precio_Unidad"]));
                        cmd.Parameters.AddWithValue("@Precio_Venta", string.IsNullOrEmpty(form["Precio_Venta"]) ? 0 : Convert.ToDecimal(form["Precio_Venta"]));
                        cmd.Parameters.AddWithValue("@Centro", form["Centro"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Concepto", form["Concepto"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Comentarios", form["Comentarios"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Poliza_Referencia", form["Poliza_Referencia"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@SKU", form["SKU"].ToString() ?? "");
                        cmd.Parameters.AddWithValue("@Autorizacion", form["Autorizacion"].ToString() ?? "");

                        con.Open();
                        cmd.ExecuteNonQuery();
                    }
                }
                TempData["MensajeExito"] = "Operación actualizada correctamente.";
            }
            catch (Exception ex)
            {
                TempData["ErrorWorkspace"] = "Error al actualizar: " + ex.Message;
            }

            return RedirectToAction("Operacion", new { idDepto = idDepto });
        }

        [HttpPost]
        public IActionResult EliminarOperacion(int idRegistro, int idDepartamento)
        {
            try
            {
                using (SqlConnection con = new SqlConnection(_cadenaConexion))
                {
                    using (SqlCommand cmd = new SqlCommand("spEliminarOperacion", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@ID_Registro", idRegistro);
                        cmd.Parameters.AddWithValue("@ID_Departamento", idDepartamento);
                        
                        con.Open();
                        cmd.ExecuteNonQuery();
                    }
                }
                TempData["MensajeExito"] = "El registro ha sido eliminado del área de trabajo.";
            }
            catch (Exception ex)
            {
                TempData["ErrorWorkspace"] = "Error al eliminar: " + ex.Message;
            }

            return RedirectToAction("Operacion", new { idDepto = idDepartamento });
        }
    
        public IActionResult InvitarUsuarios(int idDepartamento)
        {
            ViewBag.ID_Depto = idDepartamento;
            ViewBag.EsAdmin = true; 

            var listaMiembros = new List<Dictionary<string, string>>();
            var listaSolicitudes = new List<Dictionary<string, string>>();

            using (SqlConnection con = new SqlConnection(_cadenaConexion))
            {
                con.Open();
                using (SqlCommand cmd = new SqlCommand("spObtenerMiembrosEspacio", con))
                {
                    cmd.CommandType = CommandType.StoredProcedure;
                    cmd.Parameters.AddWithValue("@ID_Departamento", idDepartamento);
                    using (SqlDataReader reader = cmd.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            var miembro = new Dictionary<string, string>();
                            miembro["ID_Usuario"] = reader["ID_Usuario"].ToString()!;
                            miembro["Correo"] = reader["Correo_Google"].ToString()!;
                            miembro["Rol"] = reader["Nombre_Rol"].ToString()!;
                            miembro["Fecha"] = Convert.ToDateTime(reader["Fecha_Ingreso"]).ToString("dd/MM/yyyy");
                            listaMiembros.Add(miembro);
                        }
                    }
                }

                using (SqlCommand cmdSol = new SqlCommand("spObtenerSolicitudesPendientes", con))
                {
                    cmdSol.CommandType = CommandType.StoredProcedure;
                    cmdSol.Parameters.AddWithValue("@ID_Departamento", idDepartamento);
                    using (SqlDataReader readerSol = cmdSol.ExecuteReader())
                    {
                        while (readerSol.Read())
                        {
                            var sol = new Dictionary<string, string>();
                            sol["ID_Solicitud"] = readerSol["ID_Solicitud"].ToString()!;
                            sol["Correo"] = readerSol["Correo_Google"].ToString()!;
                            sol["Fecha"] = Convert.ToDateTime(readerSol["Fecha_Solicitud"]).ToString("dd/MM/yyyy HH:mm");
                            listaSolicitudes.Add(sol);
                        }
                    }
                }
            }

            ViewBag.Miembros = listaMiembros;
            ViewBag.Solicitudes = listaSolicitudes;
            return View();
        }

        [HttpPost]
        public IActionResult AceptarSolicitud(int idSolicitud, int idRol, int idDepartamento)
        {
            try
            {
                using (SqlConnection con = new SqlConnection(_cadenaConexion))
                {
                    using (SqlCommand cmd = new SqlCommand("spAceptarSolicitud", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@ID_Solicitud", idSolicitud);
                        cmd.Parameters.AddWithValue("@ID_Rol", idRol);
                        con.Open();
                        cmd.ExecuteNonQuery();
                    }
                }
                TempData["ExitoInvitacion"] = "Solicitud aprobada y usuario agregado al equipo.";
            }
            catch (Exception ex)
            {
                TempData["ErrorInvitacion"] = ex.Message;
            }

            return RedirectToAction("InvitarUsuarios", new { idDepartamento = idDepartamento });
        }

        [HttpPost]
        public IActionResult RechazarSolicitud(int idSolicitud, int idDepartamento)
        {
            try
            {
                using (SqlConnection con = new SqlConnection(_cadenaConexion))
                {
                    using (SqlCommand cmd = new SqlCommand("spRechazarSolicitud", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@ID_Solicitud", idSolicitud);
                        con.Open();
                        cmd.ExecuteNonQuery();
                    }
                }
                TempData["ExitoInvitacion"] = "La solicitud ha sido rechazada y eliminada de la lista.";
            }
            catch (Exception ex)
            {
                TempData["ErrorInvitacion"] = ex.Message;
            }

            return RedirectToAction("InvitarUsuarios", new { idDepartamento = idDepartamento });
        }

        [HttpPost]
        public IActionResult QuitarAcceso(int idDepartamento, int idUsuario)
        {
            try
            {
                using (SqlConnection con = new SqlConnection(_cadenaConexion))
                {
                    using (SqlCommand cmd = new SqlCommand("spQuitarAccesoEspacio", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@ID_Usuario", idUsuario);
                        cmd.Parameters.AddWithValue("@ID_Departamento", idDepartamento);

                        con.Open();
                        cmd.ExecuteNonQuery();
                    }
                }
                TempData["ExitoInvitacion"] = "Acceso revocado correctamente.";
            }
            catch (Exception ex)
            {
                TempData["ErrorInvitacion"] = ex.Message;
            }

            return RedirectToAction("InvitarUsuarios", new { idDepartamento = idDepartamento });
        }

        [HttpPost]
        public IActionResult ProcesarInvitacion(int idDepartamento, string correoInvitado, int idRol)
        {
            try
            {
                string nombreEspacio = "";
                string contrasenaEspacio = "";
                string nombreRol = idRol == 2 ? "Editor / Supervisor" : "Visualizador";

                using (SqlConnection con = new SqlConnection(_cadenaConexion))
                {
                    using (SqlCommand cmd = new SqlCommand("spInvitarUsuario", con))
                    {
                        cmd.CommandType = CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@Correo_Invitado", correoInvitado);
                        
                        
                        cmd.Parameters.AddWithValue("@ID_Departamento", idDepartamento);
                        cmd.Parameters.AddWithValue("@ID_Rol", idRol);

                        con.Open();
                        cmd.ExecuteNonQuery();
                    }

                    string queryInfo = "SELECT Nombre_Departamento, Contrasena_Area FROM Cat_Departamentos WHERE ID_Departamento = @ID_Departamento";
                    using (SqlCommand cmdInfo = new SqlCommand(queryInfo, con))
                    {
                        cmdInfo.Parameters.AddWithValue("@ID_Departamento", idDepartamento);
                        using (SqlDataReader reader = cmdInfo.ExecuteReader())
                        {
                            if (reader.Read())
                            {
                                nombreEspacio = reader["Nombre_Departamento"].ToString()!;
                                contrasenaEspacio = reader["Contrasena_Area"].ToString()!;
                            }
                        }
                    }
                }

                EnviarCorreoInvitacion(correoInvitado, nombreEspacio, contrasenaEspacio, nombreRol);
                TempData["ExitoInvitacion"] = $"Invitación y contraseña enviadas a {correoInvitado} exitosamente.";
            }
            catch (Exception ex)
            {
                TempData["ErrorInvitacion"] = ex.Message;
            }

            return RedirectToAction("InvitarUsuarios", new { idDepartamento = idDepartamento });
        }

        private void EnviarCorreoInvitacion(string correoDestino, string nombreEspacio, string contrasena, string rol)
        {
            try
            {
                string miCorreo = "cristiangonzalezmaciel95@gmail.com"; 
                string miPasswordApp = "vcut tgvw hrru lhmp"; 

                MailMessage mail = new MailMessage();
                mail.From = new MailAddress(miCorreo, "Sistema CEDIS Compensaciones");
                mail.To.Add(correoDestino);
                mail.Subject = $"Invitación al Espacio de Trabajo: {nombreEspacio}";
                mail.IsBodyHtml = true;

                mail.Body = $@"
                    <div style='font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; border: 1px solid #dadce0; border-radius: 8px; overflow: hidden;'>
                        <div style='background-color: #202124; padding: 20px; text-align: center; color: white;'>
                            <h2 style='margin: 0;'>Sistema CEDIS</h2>
                        </div>
                        <div style='padding: 30px; color: #3c4043;'>
                            <h3 style='color: #1a73e8; margin-top: 0;'>¡Has sido invitado a colaborar!</h3>
                            <p>Se te ha otorgado acceso al espacio <strong>{nombreEspacio}</strong> con el rol de <strong>{rol}</strong>.</p>
                            
                            <div style='background-color: #f8f9fa; padding: 20px; border-radius: 8px; text-align: center; margin: 25px 0; border: 1px dashed #dadce0;'>
                                <p style='margin: 0 0 10px 0; font-size: 14px; color: #5f6368;'>Tu llave maestra de acceso es:</p>
                                <h2 style='margin: 0; color: #d93025; letter-spacing: 3px; font-size: 24px;'>{contrasena}</h2>
                            </div>
                            
                            <p style='font-size: 14px; color: #5f6368;'>Ingresa a la plataforma utilizando tu cuenta de Google. Selecciona este trabajo en tu Hub e introduce la contraseña cuando el sistema te la solicite.</p>
                        </div>
                    </div>";

                SmtpClient smtp = new SmtpClient("smtp.gmail.com", 587);
                smtp.Credentials = new NetworkCredential(miCorreo, miPasswordApp);
                smtp.EnableSsl = true;
                smtp.Send(mail);
            }
            catch (Exception)
            {
                throw new Exception("El usuario fue registrado en el espacio, pero hubo un error de configuración al intentar enviar el correo con la contraseña.");
            }
        }
    }
}