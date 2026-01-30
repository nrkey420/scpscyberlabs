-- CyberLab Orchestration Platform - PostgreSQL Schema
-- Full initialization script with tables, indexes, and seed data

BEGIN;

-- =============================================================================
-- TABLES
-- =============================================================================

CREATE TABLE lab_templates (
    template_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                VARCHAR(255) NOT NULL,
    description         TEXT,
    version             VARCHAR(50) NOT NULL DEFAULT '1.0.0',
    category            VARCHAR(100),
    difficulty_level    VARCHAR(20) CHECK (difficulty_level IN ('beginner','intermediate','advanced','expert')),
    estimated_duration  INTERVAL,
    vm_definitions      JSONB NOT NULL,
    network_topology    JSONB,
    resource_requirements JSONB,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_by          VARCHAR(255),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE lab_sessions (
    session_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id         UUID NOT NULL REFERENCES lab_templates(template_id),
    session_name        VARCHAR(255),
    status              VARCHAR(30) NOT NULL DEFAULT 'provisioning'
                        CHECK (status IN ('provisioning','running','paused','stopping','stopped','failed','expired','cleaned_up')),
    started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ,
    stopped_at          TIMESTAMPTZ,
    virtual_switch_name VARCHAR(255),
    created_by          VARCHAR(255),
    error_message       TEXT,
    metadata            JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE vm_instances (
    vm_instance_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id          UUID NOT NULL REFERENCES lab_sessions(session_id) ON DELETE CASCADE,
    hyperv_vm_id        UUID,
    vm_name             VARCHAR(255) NOT NULL,
    role                VARCHAR(100),
    status              VARCHAR(30) NOT NULL DEFAULT 'creating'
                        CHECK (status IN ('creating','starting','running','paused','saved','stopping','stopped','failed','deleted')),
    os_type             VARCHAR(100),
    parent_disk_path    TEXT,
    differencing_disk_path TEXT,
    ram_mb              INT NOT NULL,
    vcpu_count          INT NOT NULL,
    ip_address          INET,
    mac_address         MACADDR,
    credentials         JSONB,
    boot_order          INT DEFAULT 0,
    started_at          TIMESTAMPTZ,
    stopped_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE student_lab_assignments (
    assignment_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id          UUID NOT NULL REFERENCES lab_sessions(session_id) ON DELETE CASCADE,
    student_id          VARCHAR(255) NOT NULL,
    assigned_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    score               NUMERIC(5,2),
    status              VARCHAR(30) NOT NULL DEFAULT 'assigned'
                        CHECK (status IN ('assigned','in_progress','completed','expired','withdrawn')),
    feedback            TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE lab_objectives (
    objective_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id         UUID NOT NULL REFERENCES lab_templates(template_id) ON DELETE CASCADE,
    title               VARCHAR(255) NOT NULL,
    description         TEXT,
    objective_order     INT NOT NULL DEFAULT 0,
    points              INT NOT NULL DEFAULT 10,
    validation_type     VARCHAR(50) CHECK (validation_type IN ('manual','automatic','script')),
    validation_script   TEXT,
    hints               JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE student_progress (
    progress_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id       UUID NOT NULL REFERENCES student_lab_assignments(assignment_id) ON DELETE CASCADE,
    objective_id        UUID NOT NULL REFERENCES lab_objectives(objective_id) ON DELETE CASCADE,
    status              VARCHAR(30) NOT NULL DEFAULT 'not_started'
                        CHECK (status IN ('not_started','in_progress','completed','skipped')),
    points_earned       INT DEFAULT 0,
    attempts            INT DEFAULT 0,
    completed_at        TIMESTAMPTZ,
    evidence            JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (assignment_id, objective_id)
);

CREATE TABLE activity_logs (
    log_id              BIGSERIAL PRIMARY KEY,
    session_id          UUID REFERENCES lab_sessions(session_id) ON DELETE SET NULL,
    vm_instance_id      UUID REFERENCES vm_instances(vm_instance_id) ON DELETE SET NULL,
    student_id          VARCHAR(255),
    action              VARCHAR(100) NOT NULL,
    details             JSONB,
    severity            VARCHAR(20) NOT NULL DEFAULT 'info'
                        CHECK (severity IN ('debug','info','warning','error','critical')),
    source              VARCHAR(100),
    ip_address          INET,
    logged_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE system_config (
    config_key          VARCHAR(255) PRIMARY KEY,
    config_value        TEXT NOT NULL,
    description         TEXT,
    data_type           VARCHAR(30) NOT NULL DEFAULT 'string'
                        CHECK (data_type IN ('string','integer','boolean','json','interval')),
    is_sensitive        BOOLEAN NOT NULL DEFAULT FALSE,
    updated_by          VARCHAR(255),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE resource_quotas (
    quota_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_name           VARCHAR(100) NOT NULL UNIQUE,
    max_concurrent_sessions INT NOT NULL DEFAULT 1,
    max_vms_per_session INT NOT NULL DEFAULT 5,
    max_ram_mb          INT NOT NULL DEFAULT 8192,
    max_vcpus           INT NOT NULL DEFAULT 4,
    max_disk_gb         INT NOT NULL DEFAULT 100,
    max_session_duration INTERVAL NOT NULL DEFAULT INTERVAL '4 hours',
    description         TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- INDEXES
-- =============================================================================

-- lab_templates
CREATE INDEX idx_lab_templates_category ON lab_templates(category);
CREATE INDEX idx_lab_templates_difficulty ON lab_templates(difficulty_level);
CREATE INDEX idx_lab_templates_active ON lab_templates(is_active);
CREATE INDEX idx_lab_templates_created_by ON lab_templates(created_by);

-- lab_sessions
CREATE INDEX idx_lab_sessions_template ON lab_sessions(template_id);
CREATE INDEX idx_lab_sessions_status ON lab_sessions(status);
CREATE INDEX idx_lab_sessions_created_by ON lab_sessions(created_by);
CREATE INDEX idx_lab_sessions_expires_at ON lab_sessions(expires_at);
CREATE INDEX idx_lab_sessions_started_at ON lab_sessions(started_at);

-- vm_instances
CREATE INDEX idx_vm_instances_session ON vm_instances(session_id);
CREATE INDEX idx_vm_instances_hyperv_id ON vm_instances(hyperv_vm_id);
CREATE INDEX idx_vm_instances_status ON vm_instances(status);

-- student_lab_assignments
CREATE INDEX idx_assignments_session ON student_lab_assignments(session_id);
CREATE INDEX idx_assignments_student ON student_lab_assignments(student_id);
CREATE INDEX idx_assignments_status ON student_lab_assignments(status);
CREATE INDEX idx_assignments_student_status ON student_lab_assignments(student_id, status);

-- lab_objectives
CREATE INDEX idx_objectives_template ON lab_objectives(template_id);
CREATE INDEX idx_objectives_order ON lab_objectives(template_id, objective_order);

-- student_progress
CREATE INDEX idx_progress_assignment ON student_progress(assignment_id);
CREATE INDEX idx_progress_objective ON student_progress(objective_id);
CREATE INDEX idx_progress_status ON student_progress(status);

-- activity_logs
CREATE INDEX idx_activity_session ON activity_logs(session_id);
CREATE INDEX idx_activity_vm ON activity_logs(vm_instance_id);
CREATE INDEX idx_activity_student ON activity_logs(student_id);
CREATE INDEX idx_activity_action ON activity_logs(action);
CREATE INDEX idx_activity_severity ON activity_logs(severity);
CREATE INDEX idx_activity_logged_at ON activity_logs(logged_at);
CREATE INDEX idx_activity_session_time ON activity_logs(session_id, logged_at);

-- resource_quotas
CREATE INDEX idx_quotas_role ON resource_quotas(role_name);

-- =============================================================================
-- SEED DATA: system_config
-- =============================================================================

INSERT INTO system_config (config_key, config_value, description, data_type, is_sensitive) VALUES
('vm_storage_path',        'C:\CyberLab\VMs',           'Base path for VM differencing disks',              'string',   FALSE),
('template_storage_path',  'C:\CyberLab\Templates',     'Base path for template parent disks',              'string',   FALSE),
('max_total_ram_gb',       '115',                        'Total RAM available for lab VMs in GB',            'integer',  FALSE),
('max_total_vcpus',        '22',                         'Total vCPUs available for lab VMs',                'integer',  FALSE),
('default_session_timeout','04:00:00',                   'Default session expiration interval',              'interval', FALSE),
('inactivity_timeout',     '00:30:00',                   'VM inactivity timeout before auto-pause',          'interval', FALSE),
('cleanup_interval',       '00:15:00',                   'Interval between expired session cleanup runs',    'interval', FALSE),
('resource_overhead_pct',  '10',                         'Percentage of overhead reserved on resources',     'integer',  FALSE),
('heartbeat_timeout_sec',  '300',                        'Seconds to wait for VM heartbeat after start',     'integer',  FALSE),
('snapshot_enabled',       'true',                       'Whether snapshot creation is enabled',             'boolean',  FALSE),
('max_snapshots_per_vm',   '5',                          'Maximum checkpoints per VM instance',              'integer',  FALSE),
('log_retention_days',     '90',                         'Days to retain activity logs',                     'integer',  FALSE),
('platform_version',       '1.0.0',                      'Current platform version',                         'string',   FALSE),
('admin_email',            'admin@cyberlab.local',       'Administrator notification email',                 'string',   FALSE),
('db_connection_string',   'Host=localhost;Database=cyberlab;', 'PostgreSQL connection string',               'string',   TRUE);

-- =============================================================================
-- SEED DATA: resource_quotas for 3 roles
-- =============================================================================

INSERT INTO resource_quotas (role_name, max_concurrent_sessions, max_vms_per_session, max_ram_mb, max_vcpus, max_disk_gb, max_session_duration, description) VALUES
('student',    1,  4,   8192,  4,   50,  INTERVAL '4 hours',  'Default quota for students'),
('instructor', 3,  8,  32768, 12,  200,  INTERVAL '12 hours', 'Quota for instructors and teaching assistants'),
('admin',      5, 16,  65536, 22,  500,  INTERVAL '24 hours', 'Unrestricted quota for platform administrators');

COMMIT;
