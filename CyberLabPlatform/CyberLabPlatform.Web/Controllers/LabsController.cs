using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CyberLabPlatform.Web.Controllers;

public class LabsController : Controller
{
    [AllowAnonymous]
    [HttpGet("/")]
    [HttpGet("/labs")]
    [HttpGet("/labs/{**slug}")]
    public IActionResult Index()
    {
        return File("index.html", "text/html");
    }
}
