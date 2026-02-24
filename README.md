# SCPS CyberLab Orchestration Platform

A cybersecurity lab orchestration system for Seminole County Public Schools, enabling instructors to deploy virtual lab environments for cybersecurity education and students to access them through a browser-based interface.

## Architecture

- **Backend**: ASP.NET Core 8.0 with PostgreSQL, SignalR, Hangfire
- **Frontend**: React 18 + TypeScript + TailwindCSS + Shadcn/ui
- **VM Orchestration**: PowerShell module on Windows Server 2022 / Hyper-V
- **Console Access**: Apache Guacamole (Docker) for browser-based VM access
- **Authentication**: Microsoft Entra ID (Azure AD) with OAuth 2.0 / OpenID Connect

## Project Structure

```
├── CyberLabPlatform/                    # .NET Solution
│   ├── CyberLabPlatform.Web/            # ASP.NET Core web application
│   │   ├── Controllers/                 # REST API controllers
│   │   ├── Hubs/                        # SignalR real-time hubs
│   │   ├── Services/                    # Business logic services
│   │   ├── BackgroundJobs/              # Hangfire background jobs
│   │   ├── Data/                        # EF Core DbContext & seeder
│   │   └── ClientApp/                   # React frontend (Vite)
│   ├── CyberLabPlatform.Core/           # Shared models, interfaces, enums
│   ├── CyberLabPlatform.Infrastructure/ # PowerShell executor, Guacamole, Email
│   └── CyberLabPlatform.Tests/          # Unit & integration tests
├── PowerShell/                          # Hyper-V orchestration module
├── Database/                            # PostgreSQL schema & seed data
├── Docker/                              # Guacamole docker-compose
├── Templates/                           # Lab template JSON definitions
└── Docs/                                # System & user documentation
```

## Lab Templates

1. **Red Team / Blue Team Cyber Range** - Full attack lifecycle with defensive monitoring
2. **Web Application Penetration Testing** - OWASP Top 10 hands-on practice
3. **SOC Analyst Training** - Security monitoring and incident response
4. **Network Attack & Defense** - Network security fundamentals
5. **Malware Analysis Sandbox** - Static and dynamic malware analysis

## Quick Start

See [System Administrator Guide](Docs/SystemAdminGuide.md) for full installation instructions.

```bash
# 1. Set up PostgreSQL
psql -U postgres -f Database/init.sql

# 2. Deploy Guacamole
cd Docker && docker-compose up -d

# 3. Build and run
cd CyberLabPlatform
dotnet restore && dotnet build
cd CyberLabPlatform.Web/ClientApp && npm install && npm run build
cd ../../
dotnet run --project CyberLabPlatform.Web
```

## Capacity

- 2 concurrent classes, 15 students each
- 24 logical processors (22 usable), 128 GB RAM (115 GB usable)
- 2.5 TB local VM storage

## Documentation

- [System Administrator Guide](Docs/SystemAdminGuide.md)
- [Instructor Manual](Docs/InstructorManual.md)
- [Student Quick Start](Docs/StudentQuickStart.md)
- Lab Scenario Guides in `Docs/LabGuide-*.md`


## IIS Startup Troubleshooting (PostgreSQL auth `28P01`)

If IIS logs show:

- `Npgsql.PostgresException ... 28P01: password authentication failed for user "cyberlab_app"`
- app exits at startup during `dbContext.Database.MigrateAsync()`

then the published app is using a PostgreSQL username/password that does not match the server.

### Verify/update app connection strings

The web app reads `ConnectionStrings:DefaultConnection` and `ConnectionStrings:HangfireConnection` (from `appsettings*.json` and environment overrides).

For IIS, prefer overriding via environment variables on the site/app pool:

- `ConnectionStrings__DefaultConnection`
- `ConnectionStrings__HangfireConnection`

### Verify database user credentials in PostgreSQL

Run on PostgreSQL:

```sql
ALTER USER cyberlab_app WITH PASSWORD 'YOUR_REAL_PASSWORD';
```

or create if missing:

```sql
CREATE ROLE cyberlab_app LOGIN PASSWORD 'YOUR_REAL_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE cyberlab TO cyberlab_app;
```

### Quick connection test from host

```bash
psql "Host=localhost;Port=5432;Database=cyberlab;Username=cyberlab_app;Password=YOUR_REAL_PASSWORD"
```

If this fails, IIS startup will fail for the same reason.

