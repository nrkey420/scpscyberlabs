using CyberLabPlatform.Core.Enums;
using CyberLabPlatform.Core.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

namespace CyberLabPlatform.Web.Data;

public class CyberLabDbContext(DbContextOptions<CyberLabDbContext> options) : DbContext(options)
{
    public DbSet<LabTemplate> LabTemplates => Set<LabTemplate>();
    public DbSet<LabSession> LabSessions => Set<LabSession>();
    public DbSet<VMInstance> VmInstances => Set<VMInstance>();
    public DbSet<LabObjective> LabObjectives => Set<LabObjective>();
    public DbSet<StudentLabAssignment> StudentLabAssignments => Set<StudentLabAssignment>();
    public DbSet<StudentProgress> StudentProgress => Set<StudentProgress>();
    public DbSet<ActivityLog> ActivityLogs => Set<ActivityLog>();
    public DbSet<SystemConfig> SystemConfigs => Set<SystemConfig>();
    public DbSet<ResourceQuota> ResourceQuotas => Set<ResourceQuota>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // LabTemplate
        modelBuilder.Entity<LabTemplate>(entity =>
        {
            entity.ToTable("lab_templates");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("template_id");
            entity.Property(e => e.Name).HasColumnName("name").HasMaxLength(255).IsRequired();
            entity.Property(e => e.Description).HasColumnName("description");
            entity.Property(e => e.Version).HasColumnName("version").HasMaxLength(50).HasDefaultValue("1.0.0");
            entity.Property(e => e.GitCommitHash).HasColumnName("category").HasMaxLength(100);
            entity.Property(e => e.DifficultyLevel).HasColumnName("difficulty_level")
                .HasConversion(new EnumToStringConverter<DifficultyLevel>())
                .HasMaxLength(20);
            entity.Property(e => e.EstimatedDurationMinutes).HasColumnName("estimated_duration");
            entity.Property(e => e.VmDefinitions).HasColumnName("vm_definitions").HasColumnType("jsonb").IsRequired();
            entity.Property(e => e.NetworkTopology).HasColumnName("network_topology").HasColumnType("jsonb");
            entity.Property(e => e.Objectives).HasColumnName("resource_requirements").HasColumnType("jsonb");
            entity.Property(e => e.IsActive).HasColumnName("is_active").HasDefaultValue(true);
            entity.Property(e => e.CreatedBy).HasColumnName("created_by").HasMaxLength(255);
            entity.Property(e => e.CreatedAt).HasColumnName("created_at").HasDefaultValueSql("NOW()");
            entity.Property(e => e.UpdatedAt).HasColumnName("updated_at").HasDefaultValueSql("NOW()");

            entity.HasIndex(e => e.DifficultyLevel).HasDatabaseName("idx_lab_templates_difficulty");
            entity.HasIndex(e => e.IsActive).HasDatabaseName("idx_lab_templates_active");
            entity.HasIndex(e => e.CreatedBy).HasDatabaseName("idx_lab_templates_created_by");
        });

        // LabSession
        modelBuilder.Entity<LabSession>(entity =>
        {
            entity.ToTable("lab_sessions");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("session_id");
            entity.Property(e => e.TemplateId).HasColumnName("template_id");
            entity.Property(e => e.InstructorId).HasColumnName("created_by").HasMaxLength(255);
            entity.Property(e => e.ClassName).HasColumnName("session_name").HasMaxLength(255);
            entity.Property(e => e.StartTime).HasColumnName("started_at").HasDefaultValueSql("NOW()");
            entity.Property(e => e.ScheduledEndTime).HasColumnName("expires_at");
            entity.Property(e => e.ActualEndTime).HasColumnName("stopped_at");
            entity.Property(e => e.Status).HasColumnName("status")
                .HasConversion(new EnumToStringConverter<LabStatus>())
                .HasMaxLength(30);
            entity.Property(e => e.TimeoutMinutes).HasColumnName("metadata").HasColumnType("jsonb");
            entity.Property(e => e.CreatedAt).HasColumnName("created_at").HasDefaultValueSql("NOW()");

            // Ignored columns mapped through metadata JSONB or configuration
            entity.Ignore(e => e.MaxDurationMinutes);
            entity.Ignore(e => e.InactivityTimeoutMinutes);

            entity.HasOne(e => e.Template).WithMany().HasForeignKey(e => e.TemplateId);

            entity.HasIndex(e => e.TemplateId).HasDatabaseName("idx_lab_sessions_template");
            entity.HasIndex(e => e.Status).HasDatabaseName("idx_lab_sessions_status");
            entity.HasIndex(e => e.InstructorId).HasDatabaseName("idx_lab_sessions_created_by");
            entity.HasIndex(e => e.ScheduledEndTime).HasDatabaseName("idx_lab_sessions_expires_at");
        });

        // VMInstance
        modelBuilder.Entity<VMInstance>(entity =>
        {
            entity.ToTable("vm_instances");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("vm_instance_id");
            entity.Property(e => e.SessionId).HasColumnName("session_id");
            entity.Property(e => e.StudentId).HasColumnName("role").HasMaxLength(100);
            entity.Property(e => e.VmName).HasColumnName("vm_name").HasMaxLength(255).IsRequired();
            entity.Property(e => e.HyperVVMId).HasColumnName("hyperv_vm_id");
            entity.Property(e => e.IpAddress).HasColumnName("ip_address").HasMaxLength(45);
            entity.Property(e => e.Credentials).HasColumnName("credentials").HasColumnType("jsonb");
            entity.Property(e => e.VmType).HasColumnName("os_type").HasMaxLength(100);
            entity.Property(e => e.Status).HasColumnName("status")
                .HasConversion(new EnumToStringConverter<VMStatus>())
                .HasMaxLength(30);
            entity.Property(e => e.CreatedAt).HasColumnName("created_at").HasDefaultValueSql("NOW()");
            entity.Property(e => e.LastActivity).HasColumnName("updated_at");
            entity.Ignore(e => e.IsShared);

            entity.HasOne(e => e.Session).WithMany(s => s.VmInstances).HasForeignKey(e => e.SessionId).OnDelete(DeleteBehavior.Cascade);

            entity.HasIndex(e => e.SessionId).HasDatabaseName("idx_vm_instances_session");
            entity.HasIndex(e => e.HyperVVMId).HasDatabaseName("idx_vm_instances_hyperv_id");
            entity.HasIndex(e => e.Status).HasDatabaseName("idx_vm_instances_status");
        });

        // LabObjective
        modelBuilder.Entity<LabObjective>(entity =>
        {
            entity.ToTable("lab_objectives");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("objective_id");
            entity.Property(e => e.TemplateId).HasColumnName("template_id");
            entity.Property(e => e.ObjectiveOrder).HasColumnName("objective_order");
            entity.Property(e => e.Title).HasColumnName("title").HasMaxLength(255).IsRequired();
            entity.Property(e => e.Description).HasColumnName("description");
            entity.Property(e => e.FlagValue).HasColumnName("validation_script");
            entity.Property(e => e.Points).HasColumnName("points").HasDefaultValue(10);
            entity.Property(e => e.Hint).HasColumnName("hints").HasColumnType("jsonb");
            entity.Property(e => e.CreatedAt).HasColumnName("created_at").HasDefaultValueSql("NOW()");

            entity.HasOne(e => e.Template).WithMany().HasForeignKey(e => e.TemplateId).OnDelete(DeleteBehavior.Cascade);

            entity.HasIndex(e => e.TemplateId).HasDatabaseName("idx_objectives_template");
            entity.HasIndex(e => new { e.TemplateId, e.ObjectiveOrder }).HasDatabaseName("idx_objectives_order");
        });

        // StudentLabAssignment
        modelBuilder.Entity<StudentLabAssignment>(entity =>
        {
            entity.ToTable("student_lab_assignments");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("assignment_id");
            entity.Property(e => e.SessionId).HasColumnName("session_id");
            entity.Property(e => e.StudentId).HasColumnName("student_id").HasMaxLength(255).IsRequired();
            entity.Property(e => e.StudentEmail).HasColumnName("feedback");
            entity.Property(e => e.StudentName).HasColumnName("status").HasMaxLength(30);
            entity.Property(e => e.EnrolledAt).HasColumnName("assigned_at").HasDefaultValueSql("NOW()");
            entity.Property(e => e.FirstAccess).HasColumnName("started_at");
            entity.Property(e => e.TotalConnectionTimeSeconds).HasColumnName("score");

            entity.HasOne(e => e.Session).WithMany(s => s.StudentAssignments).HasForeignKey(e => e.SessionId).OnDelete(DeleteBehavior.Cascade);

            entity.HasIndex(e => e.SessionId).HasDatabaseName("idx_assignments_session");
            entity.HasIndex(e => e.StudentId).HasDatabaseName("idx_assignments_student");
        });

        // StudentProgress
        modelBuilder.Entity<StudentProgress>(entity =>
        {
            entity.ToTable("student_progress");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("progress_id");
            entity.Property(e => e.SessionId).HasColumnName("assignment_id");
            entity.Property(e => e.StudentId).HasColumnName("status").HasMaxLength(30);
            entity.Property(e => e.ObjectiveId).HasColumnName("objective_id");
            entity.Property(e => e.CompletedAt).HasColumnName("completed_at");
            entity.Property(e => e.FlagSubmitted).HasColumnName("evidence").HasColumnType("jsonb");
            entity.Property(e => e.PointsAwarded).HasColumnName("points_earned");
            entity.Property(e => e.AttemptNumber).HasColumnName("attempts").HasDefaultValue(0);

            entity.HasOne(e => e.Session).WithMany().HasForeignKey(e => e.SessionId);
            entity.HasOne(e => e.Objective).WithMany().HasForeignKey(e => e.ObjectiveId).OnDelete(DeleteBehavior.Cascade);

            entity.HasIndex(e => e.SessionId).HasDatabaseName("idx_progress_assignment");
            entity.HasIndex(e => e.ObjectiveId).HasDatabaseName("idx_progress_objective");
        });

        // ActivityLog
        modelBuilder.Entity<ActivityLog>(entity =>
        {
            entity.ToTable("activity_logs");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("log_id").UseIdentityAlwaysColumn();
            entity.Property(e => e.SessionId).HasColumnName("session_id");
            entity.Property(e => e.StudentId).HasColumnName("student_id").HasMaxLength(255);
            entity.Property(e => e.VmId).HasColumnName("vm_instance_id");
            entity.Property(e => e.Timestamp).HasColumnName("logged_at").HasDefaultValueSql("NOW()");
            entity.Property(e => e.EventType).HasColumnName("action").HasMaxLength(100).IsRequired();
            entity.Property(e => e.EventDetails).HasColumnName("details").HasColumnType("jsonb");
            entity.Property(e => e.IpAddress).HasColumnName("ip_address").HasMaxLength(45);

            entity.HasOne(e => e.Session).WithMany().HasForeignKey(e => e.SessionId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.VmInstance).WithMany().HasForeignKey(e => e.VmId).OnDelete(DeleteBehavior.SetNull);

            entity.HasIndex(e => e.SessionId).HasDatabaseName("idx_activity_session");
            entity.HasIndex(e => e.VmId).HasDatabaseName("idx_activity_vm");
            entity.HasIndex(e => e.StudentId).HasDatabaseName("idx_activity_student");
            entity.HasIndex(e => e.EventType).HasDatabaseName("idx_activity_action");
            entity.HasIndex(e => e.Timestamp).HasDatabaseName("idx_activity_logged_at");
            entity.HasIndex(e => new { e.SessionId, e.Timestamp }).HasDatabaseName("idx_activity_session_time");
        });

        // SystemConfig
        modelBuilder.Entity<SystemConfig>(entity =>
        {
            entity.ToTable("system_config");
            entity.HasKey(e => e.Key);
            entity.Property(e => e.Key).HasColumnName("config_key").HasMaxLength(255);
            entity.Property(e => e.Value).HasColumnName("config_value").IsRequired();
            entity.Property(e => e.Description).HasColumnName("description");
            entity.Property(e => e.UpdatedAt).HasColumnName("updated_at").HasDefaultValueSql("NOW()");
            entity.Property(e => e.UpdatedBy).HasColumnName("updated_by").HasMaxLength(255);
        });

        // ResourceQuota
        modelBuilder.Entity<ResourceQuota>(entity =>
        {
            entity.ToTable("resource_quotas");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("quota_id");
            entity.Property(e => e.Role).HasColumnName("role_name").HasMaxLength(100).IsRequired();
            entity.Property(e => e.MaxConcurrentVms).HasColumnName("max_vms_per_session").HasDefaultValue(5);
            entity.Property(e => e.MaxRamGb).HasColumnName("max_ram_mb").HasDefaultValue(8192);
            entity.Property(e => e.MaxVcpu).HasColumnName("max_vcpus").HasDefaultValue(4);
            entity.Property(e => e.MaxSessionDurationMinutes).HasColumnName("max_disk_gb").HasDefaultValue(100);

            entity.HasIndex(e => e.Role).IsUnique().HasDatabaseName("idx_quotas_role");
        });
    }
}
