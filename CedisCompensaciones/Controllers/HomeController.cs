using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Google;
using Microsoft.AspNetCore.Authentication.Cookies;
using System.Security.Claims;
using Microsoft.Data.SqlClient;

namespace CedisCompensaciones.Controllers
{
    public class HomeController : Controller
    {
        private readonly string _cadenaConexion;

        public HomeController(IConfiguration configuracion)
        {
            _cadenaConexion = configuracion.GetConnectionString("ConexionSQL")!;
        }

       // 1. La pantalla inicial limpia (Solo iniciar sesión)
        public IActionResult Login()
        {
            return View();
        }

        // 2. Disparador de Google
        public IActionResult LoginConGoogle()
        {
            var properties = new AuthenticationProperties { RedirectUri = Url.Action("Index") };
            return Challenge(properties, GoogleDefaults.AuthenticationScheme);
        }

        // 3. El cerebro que decide a dónde mandar al usuario después de Google
        public IActionResult Index()
        {
            if (User.Identity != null && User.Identity.IsAuthenticated)
            {
                var correo = User.FindFirstValue(ClaimTypes.Email);
                var nombre = User.FindFirstValue(ClaimTypes.Name);

                using (SqlConnection con = new SqlConnection(_cadenaConexion))
                {
                    con.Open();
                    
                    // Verificar si ya está registrado en el sistema general
                    bool existe = false;
                    using (SqlCommand cmdCheck = new SqlCommand("SELECT 1 FROM Usuarios WHERE Correo_Google = @correo", con))
                    {
                        cmdCheck.Parameters.AddWithValue("@correo", correo);
                        existe = cmdCheck.ExecuteScalar() != null;
                    }

                    // Si es nuevo, lo agregamos como un Usuario Base (Sin rol ni espacio aún)
                    if (!existe)
                    {
                        using (SqlCommand cmdInsert = new SqlCommand("INSERT INTO Usuarios (Correo_Google, Nombre_Completo, Estatus) VALUES (@correo, @nombre, 1)", con))
                        {
                            cmdInsert.Parameters.AddWithValue("@correo", correo);
                            cmdInsert.Parameters.AddWithValue("@nombre", nombre);
                            cmdInsert.ExecuteNonQuery();
                        }
                    }
                }
                
                // Todos pasan al Hub visual
                return RedirectToAction("Hub", "Workspace");
            }
            return RedirectToAction("Login");
        }
      public async Task<IActionResult> Salir()
        {
            // Borra la sesión actual
            await HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
            return RedirectToAction("Login");
        }

        public async Task<IActionResult> CambiarCuenta()
        {
            // 1. Borramos la sesión actual del navegador
            await HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
            
            // 2. Preparamos el redireccionamiento hacia Google
            var properties = new AuthenticationProperties { RedirectUri = Url.Action("Index") };
            
            // 3. LA MAGIA: Forzamos a Google a mostrar el selector de cuentas
            properties.SetParameter("prompt", "select_account");
            
            return Challenge(properties, GoogleDefaults.AuthenticationScheme);
        }
    }   
}