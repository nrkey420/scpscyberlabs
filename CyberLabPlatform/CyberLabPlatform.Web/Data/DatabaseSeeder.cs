using System.Text.Json;
using CyberLabPlatform.Core.Enums;
using CyberLabPlatform.Core.Models;
using Microsoft.EntityFrameworkCore;

namespace CyberLabPlatform.Web.Data;

public class DatabaseSeeder(CyberLabDbContext context, ILogger<DatabaseSeeder> logger)
{
    public async Task SeedAsync()
    {
        try
        {
            if (await context.LabTemplates.AnyAsync())
            {
                logger.LogInformation("Database already seeded, skipping");
                return;
            }

            logger.LogInformation("Seeding database with initial data");

            await SeedLabTemplatesAsync();
            await SeedSystemConfigAsync();
            await SeedResourceQuotasAsync();

            await context.SaveChangesAsync();
            logger.LogInformation("Database seeding completed successfully");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error seeding database");
            throw;
        }
    }

    private async Task SeedLabTemplatesAsync()
    {
        var templates = new List<LabTemplate>
        {
            new()
            {
                Id = Guid.NewGuid(),
                Name = "Introduction to Network Scanning",
                Description = "Learn basic network reconnaissance using Nmap and Netcat. Students scan target machines, identify open ports, and enumerate services.",
                Version = "1.0.0",
                DifficultyLevel = DifficultyLevel.Beginner,
                EstimatedDurationMinutes = 60,
                VmDefinitions = JsonSerializer.Serialize(new[]
                {
                    new { name = "kali-attacker", os = "Kali Linux 2024", ram_mb = 2048, vcpu = 2, disk_gb = 30, role = "attacker" },
                    new { name = "target-web", os = "Ubuntu Server 22.04", ram_mb = 1024, vcpu = 1, disk_gb = 20, role = "target" }
                }),
                NetworkTopology = JsonSerializer.Serialize(new { type = "isolated", subnet = "10.0.1.0/24", switch_name = "LabSwitch-Scanning" }),
                Objectives = JsonSerializer.Serialize(new { max_ram_mb = 3072, max_vcpu = 3, max_disk_gb = 50 }),
                IsActive = true,
                CreatedBy = "system",
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            },
            new()
            {
                Id = Guid.NewGuid(),
                Name = "Web Application Exploitation",
                Description = "Practice OWASP Top 10 vulnerabilities against a purposely vulnerable web application including SQL injection, XSS, and CSRF.",
                Version = "1.0.0",
                DifficultyLevel = DifficultyLevel.Intermediate,
                EstimatedDurationMinutes = 120,
                VmDefinitions = JsonSerializer.Serialize(new[]
                {
                    new { name = "kali-attacker", os = "Kali Linux 2024", ram_mb = 2048, vcpu = 2, disk_gb = 30, role = "attacker" },
                    new { name = "dvwa-target", os = "Ubuntu Server 22.04", ram_mb = 2048, vcpu = 2, disk_gb = 30, role = "target" }
                }),
                NetworkTopology = JsonSerializer.Serialize(new { type = "isolated", subnet = "10.0.2.0/24", switch_name = "LabSwitch-WebApp" }),
                Objectives = JsonSerializer.Serialize(new { max_ram_mb = 4096, max_vcpu = 4, max_disk_gb = 60 }),
                IsActive = true,
                CreatedBy = "system",
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            },
            new()
            {
                Id = Guid.NewGuid(),
                Name = "Active Directory Penetration Testing",
                Description = "Compromise an Active Directory environment through enumeration, Kerberoasting, lateral movement, and privilege escalation.",
                Version = "1.0.0",
                DifficultyLevel = DifficultyLevel.Advanced,
                EstimatedDurationMinutes = 240,
                VmDefinitions = JsonSerializer.Serialize(new[]
                {
                    new { name = "kali-attacker", os = "Kali Linux 2024", ram_mb = 2048, vcpu = 2, disk_gb = 30, role = "attacker" },
                    new { name = "dc01", os = "Windows Server 2022", ram_mb = 4096, vcpu = 2, disk_gb = 60, role = "domain_controller" },
                    new { name = "workstation01", os = "Windows 11", ram_mb = 2048, vcpu = 2, disk_gb = 40, role = "workstation" }
                }),
                NetworkTopology = JsonSerializer.Serialize(new { type = "isolated", subnet = "10.0.3.0/24", switch_name = "LabSwitch-AD" }),
                Objectives = JsonSerializer.Serialize(new { max_ram_mb = 8192, max_vcpu = 6, max_disk_gb = 130 }),
                IsActive = true,
                CreatedBy = "system",
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            },
            new()
            {
                Id = Guid.NewGuid(),
                Name = "Incident Response and Forensics",
                Description = "Investigate a compromised Linux server. Analyze logs, identify indicators of compromise, and perform memory forensics.",
                Version = "1.0.0",
                DifficultyLevel = DifficultyLevel.Intermediate,
                EstimatedDurationMinutes = 90,
                VmDefinitions = JsonSerializer.Serialize(new[]
                {
                    new { name = "analyst-workstation", os = "Ubuntu Desktop 22.04", ram_mb = 4096, vcpu = 2, disk_gb = 50, role = "analyst" },
                    new { name = "compromised-server", os = "Ubuntu Server 20.04", ram_mb = 2048, vcpu = 2, disk_gb = 40, role = "evidence" }
                }),
                NetworkTopology = JsonSerializer.Serialize(new { type = "isolated", subnet = "10.0.4.0/24", switch_name = "LabSwitch-IR" }),
                Objectives = JsonSerializer.Serialize(new { max_ram_mb = 6144, max_vcpu = 4, max_disk_gb = 90 }),
                IsActive = true,
                CreatedBy = "system",
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            },
            new()
            {
                Id = Guid.NewGuid(),
                Name = "Firewall and IDS Configuration",
                Description = "Configure iptables firewall rules and Snort IDS signatures to protect a network against common attacks.",
                Version = "1.0.0",
                DifficultyLevel = DifficultyLevel.Beginner,
                EstimatedDurationMinutes = 75,
                VmDefinitions = JsonSerializer.Serialize(new[]
                {
                    new { name = "firewall-vm", os = "Ubuntu Server 22.04", ram_mb = 2048, vcpu = 2, disk_gb = 30, role = "firewall" },
                    new { name = "internal-server", os = "Ubuntu Server 22.04", ram_mb = 1024, vcpu = 1, disk_gb = 20, role = "internal" },
                    new { name = "attacker-vm", os = "Kali Linux 2024", ram_mb = 2048, vcpu = 2, disk_gb = 30, role = "attacker" }
                }),
                NetworkTopology = JsonSerializer.Serialize(new { type = "multi-segment", subnets = new[] { "10.0.5.0/24", "10.0.6.0/24" }, switch_name = "LabSwitch-FW" }),
                Objectives = JsonSerializer.Serialize(new { max_ram_mb = 5120, max_vcpu = 5, max_disk_gb = 80 }),
                IsActive = true,
                CreatedBy = "system",
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            }
        };

        await context.LabTemplates.AddRangeAsync(templates);
    }

    private async Task SeedSystemConfigAsync()
    {
        if (await context.SystemConfigs.AnyAsync())
            return;

        var configs = new List<SystemConfig>
        {
            new() { Key = "vm_storage_path", Value = @"C:\CyberLab\VMs", Description = "Base path for VM differencing disks", UpdatedBy = "system", UpdatedAt = DateTime.UtcNow },
            new() { Key = "template_storage_path", Value = @"C:\CyberLab\Templates", Description = "Base path for template parent disks", UpdatedBy = "system", UpdatedAt = DateTime.UtcNow },
            new() { Key = "max_total_ram_gb", Value = "115", Description = "Total RAM available for lab VMs in GB", UpdatedBy = "system", UpdatedAt = DateTime.UtcNow },
            new() { Key = "max_total_vcpus", Value = "22", Description = "Total vCPUs available for lab VMs", UpdatedBy = "system", UpdatedAt = DateTime.UtcNow },
            new() { Key = "default_session_timeout", Value = "04:00:00", Description = "Default session expiration interval", UpdatedBy = "system", UpdatedAt = DateTime.UtcNow },
            new() { Key = "inactivity_timeout", Value = "00:30:00", Description = "VM inactivity timeout before auto-pause", UpdatedBy = "system", UpdatedAt = DateTime.UtcNow },
            new() { Key = "resource_overhead_pct", Value = "10", Description = "Percentage of overhead reserved on resources", UpdatedBy = "system", UpdatedAt = DateTime.UtcNow },
            new() { Key = "snapshot_enabled", Value = "true", Description = "Whether snapshot creation is enabled", UpdatedBy = "system", UpdatedAt = DateTime.UtcNow },
            new() { Key = "max_snapshots_per_vm", Value = "5", Description = "Maximum checkpoints per VM instance", UpdatedBy = "system", UpdatedAt = DateTime.UtcNow },
            new() { Key = "log_retention_days", Value = "90", Description = "Days to retain activity logs", UpdatedBy = "system", UpdatedAt = DateTime.UtcNow },
            new() { Key = "platform_version", Value = "1.0.0", Description = "Current platform version", UpdatedBy = "system", UpdatedAt = DateTime.UtcNow }
        };

        await context.SystemConfigs.AddRangeAsync(configs);
    }

    private async Task SeedResourceQuotasAsync()
    {
        if (await context.ResourceQuotas.AnyAsync())
            return;

        var quotas = new List<ResourceQuota>
        {
            new() { Id = Guid.NewGuid(), Role = "student", MaxConcurrentVms = 4, MaxRamGb = 8192, MaxVcpu = 4, MaxSessionDurationMinutes = 240 },
            new() { Id = Guid.NewGuid(), Role = "instructor", MaxConcurrentVms = 8, MaxRamGb = 32768, MaxVcpu = 12, MaxSessionDurationMinutes = 720 },
            new() { Id = Guid.NewGuid(), Role = "admin", MaxConcurrentVms = 16, MaxRamGb = 65536, MaxVcpu = 22, MaxSessionDurationMinutes = 1440 }
        };

        await context.ResourceQuotas.AddRangeAsync(quotas);
    }
}
