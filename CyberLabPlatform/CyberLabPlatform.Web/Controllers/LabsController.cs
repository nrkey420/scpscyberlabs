using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CyberLabPlatform.Web.Controllers;

[Authorize]
public class LabsController : Controller
{
    [HttpGet("/")]
    [HttpGet("/labs")]
    [HttpGet("/labs/{**slug}")]
    public IActionResult Index()
    {
        return File("index.html", "text/html");
    }
}
