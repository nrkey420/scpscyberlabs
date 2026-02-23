using CyberLabPlatform.Core.Interfaces;
using CyberLabPlatform.Web.BackgroundJobs;
using CyberLabPlatform.Web.Data;
using CyberLabPlatform.Web.Hubs;
using CyberLabPlatform.Web.Services;
using AspNetCoreRateLimit;
using Hangfire;
using Hangfire.PostgreSql;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Identity.Web;
using Serilog;

Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(new ConfigurationBuilder()
        .AddJsonFile("appsettings.json")
        .AddJsonFile($"appsettings.{Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production"}.json", optional: true)
        .Build())
    .Enrich.FromLogContext()
    .CreateBootstrapLogger();

try
{
    Log.Information("Starting CyberLab Platform");

    var builder = WebApplication.CreateBuilder(args);

    // Serilog
    builder.Host.UseSerilog((context, services, configuration) => configuration
        .ReadFrom.Configuration(context.Configuration)
        .ReadFrom.Services(services)
        .Enrich.FromLogContext());

    // Entra ID Authentication
    builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
        .AddMicrosoftIdentityWebApi(builder.Configuration.GetSection("AzureAd"));

    // Authorization policies
    builder.Services.AddAuthorizationBuilder()
        .AddPolicy("SystemAdministrator", policy =>
            policy.RequireRole("SystemAdministrator"))
        .AddPolicy("Instructor", policy =>
            policy.RequireRole("SystemAdministrator", "Instructor"))
        .AddPolicy("Student", policy =>
            policy.RequireRole("SystemAdministrator", "Instructor", "Student"));

    // EF Core with PostgreSQL
    builder.Services.AddDbContext<CyberLabDbContext>(options =>
        options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

    // SignalR
    builder.Services.AddSignalR();

    // Hangfire
    builder.Services.AddHangfire(config => config
        .SetDataCompatibilityLevel(CompatibilityLevel.Version_180)
        .UseSimpleAssemblyNameTypeSerializer()
        .UseRecommendedSerializerSettings()
        .UsePostgreSqlStorage(options =>
            options.UseNpgsqlConnection(builder.Configuration.GetConnectionString("HangfireConnection"))));
    builder.Services.AddHangfireServer();

    // CORS for React dev server
    var allowedOrigins = builder.Configuration.GetSection("AllowedCorsOrigins").Get<string[]>() ?? ["http://localhost:3000"];
    builder.Services.AddCors(options =>
    {
        options.AddPolicy("ReactDev", policy =>
            policy.WithOrigins(allowedOrigins)
                .AllowAnyHeader()
                .AllowAnyMethod()
                .AllowCredentials());
    });

    // Swagger / OpenAPI
    builder.Services.AddEndpointsApiExplorer();
    builder.Services.AddSwaggerGen(options =>
    {
        options.SwaggerDoc("v1", new Microsoft.OpenApi.Models.OpenApiInfo
        {
            Title = "CyberLab Platform API",
            Version = "v1",
            Description = "REST API for the CyberLab Orchestration Platform"
        });
    });

    // Rate limiting
    builder.Services.AddMemoryCache();
    builder.Services.Configure<IpRateLimitOptions>(builder.Configuration.GetSection("IpRateLimiting"));
    builder.Services.AddInMemoryRateLimiting();
    builder.Services.AddSingleton<IRateLimitConfiguration, RateLimitConfiguration>();

    // Health checks
    builder.Services.AddHealthChecks()
        .AddNpgSql(builder.Configuration.GetConnectionString("DefaultConnection")!, name: "postgresql")
        .AddDbContextCheck<CyberLabDbContext>(name: "efcore");

    // Controllers
    builder.Services.AddControllers();

    // Application services
    builder.Services.AddScoped<ILabOrchestrationService, LabOrchestrationService>();
    builder.Services.AddScoped<IResourceManagerService, ResourceManagerService>();
    builder.Services.AddScoped<IGamificationService, GamificationService>();
    builder.Services.AddScoped<IActivityLoggingService, ActivityLoggingService>();
    builder.Services.AddScoped<IReportingService, ReportingService>();
    builder.Services.AddScoped<IEntraIdService, EntraIdService>();

    // Background jobs
    builder.Services.AddScoped<InactivityTimeoutJob>();
    builder.Services.AddScoped<SessionCleanupJob>();
    builder.Services.AddScoped<HealthCheckJob>();

    // Database seeder
    builder.Services.AddScoped<DatabaseSeeder>();

    var app = builder.Build();

    // Seed database
    using (var scope = app.Services.CreateScope())
    {
        var dbContext = scope.ServiceProvider.GetRequiredService<CyberLabDbContext>();
        await dbContext.Database.MigrateAsync();

        var seeder = scope.ServiceProvider.GetRequiredService<DatabaseSeeder>();
        await seeder.SeedAsync();
    }

    // Middleware pipeline
    if (app.Environment.IsDevelopment())
    {
        app.UseSwagger();
        app.UseSwaggerUI();
    }

    app.UseSerilogRequestLogging();
    app.UseIpRateLimiting();
    app.UseCors("ReactDev");
    app.UseAuthentication();
    app.UseAuthorization();

    // Map endpoints
    app.MapControllers();
    app.MapHub<LabActivityHub>("/hubs/lab-activity");
    app.MapHangfireDashboard("/hangfire", new Hangfire.DashboardOptions
    {
        Authorization = [new HangfireDashboardAuthorizationFilter()]
    });
    app.MapHealthChecks("/health");

    // Schedule recurring Hangfire jobs
    RecurringJob.AddOrUpdate<InactivityTimeoutJob>(
        "inactivity-timeout-check",
        job => job.CheckInactiveVMsAsync(),
        "*/5 * * * *");

    RecurringJob.AddOrUpdate<SessionCleanupJob>(
        "session-cleanup",
        job => job.CleanupExpiredSessionsAsync(),
        "*/15 * * * *");

    RecurringJob.AddOrUpdate<HealthCheckJob>(
        "system-health-check",
        job => job.RunHealthCheckAsync(),
        "*/10 * * * *");

    // Static files for React SPA with fallback
    app.UseStaticFiles();
    app.MapFallbackToFile("index.html");

    await app.RunAsync();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application terminated unexpectedly");
}
finally
{
    await Log.CloseAndFlushAsync();
}

// Required for WebApplicationFactory<Program> in integration tests
public partial class Program { }

/// <summary>
/// Hangfire dashboard authorization filter - restricts access to SystemAdministrator role.
/// </summary>
public class HangfireDashboardAuthorizationFilter : Hangfire.Dashboard.IDashboardAuthorizationFilter
{
    public bool Authorize(Hangfire.Dashboard.DashboardContext context)
    {
        if (context is not Hangfire.AspNetCore.AspNetCoreDashboardContext aspNetCoreContext)
        {
            return false;
        }

        var httpContext = aspNetCoreContext.HttpContext;
        return httpContext.User.Identity?.IsAuthenticated == true
            && httpContext.User.IsInRole("SystemAdministrator");
    }
}

public partial class Program;
