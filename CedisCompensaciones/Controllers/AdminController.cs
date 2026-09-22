using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.AspNetCore.Authorization;

namespace CedisCompensaciones.Controllers
{
    // Solo los que hayan iniciado sesión podrán intentar entrar aquí
    [Authorize] 
    public class AdminController : Controller
    {
        private readonly string _cadenaConexion;

        public AdminController(IConfiguration configuracion)
        {
            _cadenaConexion = configuracion.GetConnectionString("ConexionSQL")!;
        }

        // 1. Mostrar la pantalla de accesos (Como Google Drive)
        public IActionResult Accesos()
        {
            // Aquí idealmente validarías si el usuario actual tiene ID_Rol = 1 (Admin)
            // Si no es admin, lo rebotas. Por ahora, mostraremos la vista.
            
            var listaUsuarios = new List<Dictionary<string, string>>();

            using (SqlConnection con = new SqlConnection(_cadenaConexion))
            {
                con.Open();
                // Traemos a los usuarios y sus roles
                string query = @"SELECT U.ID_Usuario, U.Correo_Google, U.Nombre_Completo, U.Estatus, R.Nombre_Rol 
                                 FROM Usuarios U 
                                 LEFT JOIN Cat_Roles R ON U.ID_Rol = R.ID_Rol";
                                 
                using (SqlCommand cmd = new SqlCommand(query, con))
                using (SqlDataReader reader = cmd.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        var usr = new Dictionary<string, string>();
                        usr["ID"] = reader["ID_Usuario"].ToString()!;
                        usr["Correo"] = reader["Correo_Google"].ToString()!;
                        usr["Nombre"] = reader["Nombre_Completo"].ToString()!;
                        usr["Rol"] = reader["Nombre_Rol"].ToString()!;
                        usr["Estatus"] = reader["Estatus"].ToString()!; // 1 = Activo, 0 = Sin acceso
                        listaUsuarios.Add(usr);
                    }
                }
            }

            // Enviamos la lista al HTML
            return View(listaUsuarios); 
        }

        // 2. Método para DAR ACCESO (Agregar un nuevo correo)
        [HttpPost]
        public IActionResult ConcederAcceso(string correo, string nombre, int idRol)
        {
            using (SqlConnection con = new SqlConnection(_cadenaConexion))
            {
                con.Open();
                // Por defecto le damos ID_Departamento = 1 y Estatus = 1 (Activo)
                string query = "INSERT INTO Usuarios (Correo_Google, Nombre_Completo, ID_Rol, ID_Departamento, Estatus) VALUES (@correo, @nombre, @rol, 1, 1)";
                using (SqlCommand cmd = new SqlCommand(query, con))
                {
                    cmd.Parameters.AddWithValue("@correo", correo);
                    cmd.Parameters.AddWithValue("@nombre", nombre);
                    cmd.Parameters.AddWithValue("@rol", idRol);
                    cmd.ExecuteNonQuery();
                }
            }
            return RedirectToAction("Accesos");
        }

        // 3. Método para QUITAR ACCESO (Revocar)
        [HttpPost]
        public IActionResult RevocarAcceso(int idUsuario, int nuevoEstatus)
        {
            using (SqlConnection con = new SqlConnection(_cadenaConexion))
            {
                con.Open();
                // Actualizamos el estatus (0 = bloqueado, 1 = activo)
                string query = "UPDATE Usuarios SET Estatus = @estatus WHERE ID_Usuario = @id";
                using (SqlCommand cmd = new SqlCommand(query, con))
                {
                    cmd.Parameters.AddWithValue("@estatus", nuevoEstatus);
                    cmd.Parameters.AddWithValue("@id", idUsuario);
                    cmd.ExecuteNonQuery();
                }
            }
            return RedirectToAction("Accesos");
        }
    }
}