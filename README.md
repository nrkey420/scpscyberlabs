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
