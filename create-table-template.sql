CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm"; 

-- SECTION 1: ORGANIZATION & ACCESS CONTROL1

CREATE TABLE tenants (
    tenant_id     UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_code   VARCHAR(50)  NOT NULL UNIQUE,
    tenant_name   VARCHAR(255) NOT NULL,
    type          VARCHAR(50),
    address       TEXT,
    logo_url      TEXT,
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE roles (
    role_id        UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id      UUID         NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    role_name      VARCHAR(100) NOT NULL,
    role_code      VARCHAR(50)  NOT NULL,
    description    TEXT,
    is_system_role BOOLEAN      NOT NULL DEFAULT FALSE,
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (tenant_id, role_code)
);


CREATE TABLE permissions (
    permission_id   UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    permission_code VARCHAR(100) NOT NULL UNIQUE,
    permission_name VARCHAR(255) NOT NULL,
    module          VARCHAR(100),
    description     TEXT,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE role_permissions (
    role_id       UUID NOT NULL REFERENCES roles(role_id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES permissions(permission_id) ON DELETE CASCADE,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE users (
    user_id        UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id      UUID         NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    line_user_id   VARCHAR(100) NOT NULL,
    username       VARCHAR(100) NOT NULL,
    title_name varchar(50) NOT NULL,
    first_name varchar(255),
    last_name varchar(255),
    password_hash  VARCHAR(255),
    display_name   VARCHAR(255),
    email          VARCHAR(255),
    phone_number   VARCHAR(20),
    citizen_type  VARCHAR(20) DEFAULT 'ประชาชน',
    role_id        UUID         REFERENCES roles(role_id),
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE,
    last_login_at  TIMESTAMP,
    created_at     TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMP    NOT NULL DEFAULT NOW(),
);

CREATE TABLE staff_credentials (
    user_id       UUID         PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    username      VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    must_change   BOOLEAN      NOT NULL DEFAULT FALSE,
    last_changed  TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TABLE departments (
    department_id        UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id            UUID         NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    parent_department_id UUID         REFERENCES departments(department_id),
    department_name      VARCHAR(255) NOT NULL,
    department_code      VARCHAR(50),
    description          TEXT,
    is_active            BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at           TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_departments (
    user_id       UUID    NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    department_id UUID    NOT NULL REFERENCES departments(department_id) ON DELETE CASCADE,
    is_primary    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, department_id)
);

CREATE TABLE user_sessions (
    session_id UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id    UUID        NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    device     VARCHAR(255),
    ip_address VARCHAR(45),
    login_at   TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    logout_at  TIMESTAMP,
    is_active  BOOLEAN     NOT NULL DEFAULT TRUE
);

-- SECTION 2: CHANNELS & LINE LIFF

CREATE TABLE channels (
    channel_id   UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id    UUID         NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    channel_code VARCHAR(50)  NOT NULL,
    channel_name VARCHAR(100) NOT NULL,
    config       JSONB,
    is_active    BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (tenant_id, channel_code)
);

CREATE TABLE liff_sessions (
    session_id   UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    line_user_id VARCHAR(100) NOT NULL,
    tenant_id    UUID         REFERENCES tenants(tenant_id),
    current_step INT          NOT NULL DEFAULT 1,
    draft_data   JSONB,
    expires_at   TIMESTAMP    NOT NULL DEFAULT (NOW() + INTERVAL '2 hours'),
    created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- SECTION 3: COMPLAINT CLASSIFICATION

CREATE TABLE categories (
    category_id   UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID         NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    category_name VARCHAR(255) NOT NULL,
    category_code VARCHAR(50)  NOT NULL,
    description   TEXT,
    icon_url      TEXT,
    color_code    VARCHAR(20),
    display_order INT          NOT NULL DEFAULT 0,
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (tenant_id, category_code)
);

CREATE TABLE subcategories (
    subcategory_id   UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    category_id      UUID         NOT NULL REFERENCES categories(category_id) ON DELETE CASCADE,
    tenant_id        UUID         NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    subcategory_name VARCHAR(255) NOT NULL,
    subcategory_code VARCHAR(50)  NOT NULL,
    description      TEXT,
    icon_url         TEXT,
    display_order    INT          NOT NULL DEFAULT 0,
    is_active        BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (tenant_id, subcategory_code)
);

CREATE TABLE priority_levels (
    priority_id             UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID        NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    priority_name           VARCHAR(100) NOT NULL,
    priority_code           VARCHAR(20)  NOT NULL,
    color_code              VARCHAR(20),
    sla_response_time_min   INT,
    sla_resolution_time_min INT,
    display_order           INT         NOT NULL DEFAULT 0,
    is_active               BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (tenant_id, priority_code)
);

-- SECTION 4: TEAM & STATUSES

CREATE TABLE status_master (
    status_id     UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID         NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    status_name   VARCHAR(100) NOT NULL,
    status_code   VARCHAR(50)  NOT NULL,
    description   TEXT,
    color_code    VARCHAR(20),
    is_final      BOOLEAN      NOT NULL DEFAULT FALSE,
    display_order INT          NOT NULL DEFAULT 0,
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (tenant_id, status_code)
);

CREATE TABLE teams (
    team_id        UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id      UUID         NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    department_id  UUID         REFERENCES departments(department_id),
    team_name      VARCHAR(255) NOT NULL,
    team_code      VARCHAR(100),
    description    TEXT,
    parent_team_id UUID         REFERENCES teams(team_id),
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE team_members (
    team_member_id        UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    team_id      UUID         NOT NULL REFERENCES teams(team_id) ON DELETE CASCADE,
    user_id      UUID         NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    role_in_team VARCHAR(100),
    created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
    UNIQUE (team_id, user_id)
);

CREATE TABLE complaints(
    complaint_id     UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
    complaint_no     VARCHAR(50)   NOT NULL UNIQUE,
    tenant_id        UUID          NOT NULL REFERENCES tenants(tenant_id),
    channel_id       UUID          REFERENCES channels(channel_id),
    user_id          UUID          REFERENCES users(user_id),
    category_id      UUID          REFERENCES categories(category_id),
    subcategory_id   UUID          REFERENCES subcategories(subcategory_id),
    priority_id      UUID          REFERENCES priority_levels(priority_id),
    latitude         DECIMAL(10,7),
    longitude        DECIMAL(10,7),
    district         varchar(100) NOT NULL,
    province         varchar(100),
    location_text    TEXT,
    geocoded_at      TIMESTAMP,
    location_accuracy DECIMAL(8,2),
    current_status_id UUID         REFERENCES status_master(status_id),
    assigned_team_id UUID          REFERENCES teams(team_id),
    assigned_user_id UUID          REFERENCES users(user_id),
    is_public_view   BOOLEAN       NOT NULL DEFAULT TRUE,
    due_date         TIMESTAMP,
    resolved_at      TIMESTAMP,
    closed_at        TIMESTAMP,
    created_at       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    detail           VARCHAR(300),
    additional_detail VARCHAR(100)
);

CREATE TABLE complaint_files (
    file_id      UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    complaint_id UUID         NOT NULL REFERENCES complaints(complaint_id) ON DELETE CASCADE,
    file_type    VARCHAR(50),
    file_name    VARCHAR(255) NOT NULL,
    file_path    TEXT         NOT NULL,
    file_url     TEXT,
    file_size    BIGINT,
    mime_type    VARCHAR(100),
    uploaded_by  UUID         REFERENCES users(user_id),
    is_primary   BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE complaint_feedback (
    feedback_id    UUID      PRIMARY KEY DEFAULT uuid_generate_v4(),
    complaint_id   UUID      NOT NULL REFERENCES complaints(complaint_id) ON DELETE CASCADE,
    user_id        UUID      REFERENCES users(user_id),
    score_overall  SMALLINT  NOT NULL CHECK (score_overall BETWEEN 1 AND 5),
    comment        TEXT,
    feedback_round SMALLINT  NOT NULL DEFAULT 1,
    trigger_event  VARCHAR(50),
    submitted_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- SECTION 6: WORKFLOW LOGS & SLA TRACKING

CREATE TABLE workflow_logs (
    workflow_log_id  UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    complaint_id     UUID         NOT NULL REFERENCES complaints(complaint_id) ON DELETE CASCADE,
    from_status_id   UUID         REFERENCES status_master(status_id),
    to_status_id     UUID         NOT NULL REFERENCES status_master(status_id),
    action_type      VARCHAR(100) NOT NULL,
    action_by        UUID         REFERENCES users(user_id),
    action_role_id   UUID         REFERENCES roles(role_id),
    action_note      TEXT,
    action_datetime  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ip_address       VARCHAR(45),
    pending_reason   VARCHAR(100),
    assigned_team_id UUID REFERENCES teams(team_id),
    assigned_user    UUID REFERENCES users(user_id),

    CONSTRAINT chk_action_type CHECK (
        action_type IN ('SUBMIT','ASSIGNED','RESOLVE','CLOSE','REJECT','REOPEN')),
    -- pending_reason ต้องมีค่าเมื่อ action_type = PAUSED
    CONSTRAINT chk_pending_reason CHECK (
        (action_type = 'PAUSED' AND pending_reason IS NOT NULL)
        OR action_type != 'PAUSED'
    ),
    -- assigned_team_id ต้องมีค่าเมื่อ action_type = ASSIGNED
    CONSTRAINT chk_assigned_team CHECK (
        (action_type = 'ASSIGNED' AND assigned_team_id IS NOT NULL)
        OR action_type != 'ASSIGNED'
    )
);

-- ── index เพื่อเพิ่มประสิทธิภาพ query ────────────────────────
-- ค้นหา log ของ complaint หนึ่งๆ บ่อยที่สุด
CREATE INDEX idx_workflow_logs_complaint_id
    ON workflow_logs (complaint_id);

-- filter ตาม action_type เช่น ดูเฉพาะ ASSIGNED หรือ REJECTED
CREATE INDEX idx_workflow_logs_action_type
    ON workflow_logs (action_type);

-- filter ตามช่วงเวลา สำหรับ dashboard และ report
CREATE INDEX idx_workflow_logs_action_datetime
    ON workflow_logs (action_datetime DESC);

-- ค้นหาว่าเจ้าหน้าที่คนนี้ทำอะไรบ้าง
CREATE INDEX idx_workflow_logs_action_by
    ON workflow_logs (action_by);
    
-- สิ่งที่เปลี่ยนจาก DDL เดิมที่ส่งมา
-- รายการ	DDL เดิม	ฉบับแก้ไข
-- ON DELETE CASCADE	ไม่มี	เพิ่มใน complaint_id เมื่อลบ complaint ลบ log ด้วย
-- to_status_id	NULL ได้	NOT NULL เพราะทุก action ต้องรู้ว่าไปสถานะไหน
-- chk_action_type	ไม่มี	จำกัด 7 ค่าที่ถูกต้องเท่านั้น
-- chk_pending_reason	ไม่มี	บังคับใส่เหตุผลเมื่อ PAUSED
-- chk_assigned_team	ไม่มี	บังคับใส่ทีมเมื่อ ASSIGNED
-- index	ไม่มี	เพิ่ม 4 index สำหรับ query ที่ใช้บ่อย 


CREATE TABLE sla_tracking (
    sla_id                  UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    complaint_id            UUID         NOT NULL REFERENCES complaints(complaint_id) ON DELETE CASCADE,
    sla_type                VARCHAR(50)  NOT NULL,
    sla_name                VARCHAR(255),
    start_time              TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    due_time                TIMESTAMP,
    target_minutes          INT,
    response_time_minutes   INT,
    resolution_time_minutes INT,
    is_breached             BOOLEAN      NOT NULL DEFAULT FALSE,
    breached_at             TIMESTAMP,
    breached_reason         TEXT,
    sla_status              VARCHAR(20)
        GENERATED ALWAYS AS (
            CASE WHEN is_breached THEN 'BREACHED' ELSE 'ON_TIME' END
        ) STORED,                                                
    is_active               BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (complaint_id, sla_type)
);

-- SECTION 7: AI & ANALYTICS

CREATE TABLE ai_analysis (
    analysis_id      UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
    complaint_id     UUID          NOT NULL REFERENCES complaints(complaint_id) ON DELETE CASCADE,
    model_version    VARCHAR(50),
    category_id      UUID          REFERENCES categories(category_id),
    subcategory_id   UUID          REFERENCES subcategories(subcategory_id),
    priority_id      UUID          REFERENCES priority_levels(priority_id),
    sentiment_score  DECIMAL(5,2),
    sentiment_label  VARCHAR(20),
    trend_score      DECIMAL(5,2),
    risk_score       DECIMAL(5,2),
    confidence_score DECIMAL(5,2),
    recommendation   TEXT,
    keywords         JSONB,
    analyzed_at      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    analyzed_by      VARCHAR(50)
);

CREATE TABLE ai_keywords (
    keyword_id   UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    complaint_id UUID         NOT NULL REFERENCES complaints(complaint_id) ON DELETE CASCADE,
    analysis_id  UUID         REFERENCES ai_analysis(analysis_id) ON DELETE CASCADE,
    keyword      VARCHAR(255) NOT NULL,
    weight       DECIMAL(5,2)
);

CREATE TABLE ai_feedback (
    feedback_id             UUID      PRIMARY KEY DEFAULT uuid_generate_v4(),
    analysis_id             UUID      NOT NULL REFERENCES ai_analysis(analysis_id) ON DELETE CASCADE,
    confirmed_by            UUID      REFERENCES users(user_id),
    confirmed_at            TIMESTAMP,
    is_correct              BOOLEAN,
    correct_main_category   UUID      REFERENCES categories(category_id),
    correct_sub_category    UUID      REFERENCES subcategories(subcategory_id),
    correct_priority_id     UUID      REFERENCES priority_levels(priority_id),
    comment                 TEXT
);

-- SECTION 7: NOTIFICATION & COMMUNICATION

CREATE TABLE notification_templates (
    template_id   UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID         NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    template_code VARCHAR(100) NOT NULL,
    channel       VARCHAR(50)  NOT NULL,
    title         VARCHAR(255),
    message       TEXT         NOT NULL,
    variables     JSONB,
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (tenant_id, template_code, channel)
);

CREATE TABLE notifications (
    notification_id   UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id         UUID         NOT NULL REFERENCES tenants(tenant_id),
    complaint_id      UUID         REFERENCES complaints(complaint_id) ON DELETE SET NULL,
    user_id           UUID         REFERENCES users(user_id) ON DELETE SET NULL,
    channel           VARCHAR(50)  NOT NULL,
    notification_type VARCHAR(50),
    title             VARCHAR(255),
    message           TEXT,
    data              JSONB,
    is_read           BOOLEAN      NOT NULL DEFAULT FALSE,
    send_status       VARCHAR(50),
    sent_at           TIMESTAMP,
    read_at           TIMESTAMP,
    created_at        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- SECTION 8: SYSTEM & INFRASTRUCTURE

CREATE TABLE system_configs (
    config_id    UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id    UUID         NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    config_group VARCHAR(100) NOT NULL,
    config_key   VARCHAR(255) NOT NULL,
    config_value TEXT,
    description  TEXT,
    is_encrypted BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (tenant_id, config_key)
);

CREATE TABLE system_settings (
    setting_id    UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID         NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    setting_key   VARCHAR(100) NOT NULL,
    setting_value TEXT,
    setting_type  VARCHAR(50),
    is_public     BOOLEAN      NOT NULL DEFAULT FALSE,
    is_editable   BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (tenant_id, setting_key)
);

CREATE TABLE api_logs (
    log_id           UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id        UUID         REFERENCES tenants(tenant_id),
    method           VARCHAR(10)  NOT NULL,
    endpoint         VARCHAR(255) NOT NULL,
    request_time     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    response_time_ms INT,
    status_code      INT,
    ip_address       VARCHAR(45),
    user_agent       VARCHAR(255),
    request_body     JSONB,
    response_body    JSONB
);

CREATE TABLE tenant_usage (
    usage_id          UUID    PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id         UUID    NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    usage_date        DATE    NOT NULL,
    total_complaints  INT     NOT NULL DEFAULT 0,
    total_users       INT     NOT NULL DEFAULT 0,
    storage_used      BIGINT  NOT NULL DEFAULT 0,
    ai_analysis_count INT     NOT NULL DEFAULT 0,
    UNIQUE (tenant_id, usage_date)
);

CREATE TABLE integrations (
    integration_id   UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id        UUID         NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    integration_type VARCHAR(100) NOT NULL,
    endpoint_url     TEXT,
    version          VARCHAR(50),
    is_active        BOOLEAN      NOT NULL DEFAULT TRUE,
    last_sync        TIMESTAMP,
    metadata         JSONB,
    created_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE audit_logs (
    audit_id    UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID         NOT NULL REFERENCES tenants(tenant_id),
    user_id     UUID         REFERENCES users(user_id),
    action      VARCHAR(100) NOT NULL,
    entity_type VARCHAR(100) NOT NULL,
    entity_id   UUID,
    old_values  JSONB,
    new_values  JSONB,
    ip_address  VARCHAR(45),
    user_agent  VARCHAR(255),
    created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- SECTION 8: Summary Table

CREATE TABLE daily_complaint_summary (
    summary_id         UUID    PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id          UUID    NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    summary_date       DATE    NOT NULL,
    total_complaints   INT     NOT NULL DEFAULT 0,
    open_cases         INT     NOT NULL DEFAULT 0,
    in_progress_cases  INT     NOT NULL DEFAULT 0,
    resolved_cases     INT     NOT NULL DEFAULT 0,
    closed_cases       INT     NOT NULL DEFAULT 0,
    sla_breached_cases INT     NOT NULL DEFAULT 0,
    avg_resolution_hours NUMERIC(8,2) DEFAULT 0,
    line_liff_cases    INT     NOT NULL DEFAULT 0,
    updated_at         TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, summary_date)
);

CREATE TABLE category_summary (
    summary_id        UUID    PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id         UUID    NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    summary_date      DATE    NOT NULL,
    category_id       UUID    NOT NULL REFERENCES categories(category_id) ON DELETE CASCADE,
    category_name     VARCHAR(255),
    total_cases       INT     NOT NULL DEFAULT 0,
    open_cases        INT     NOT NULL DEFAULT 0,
    closed_cases      INT     NOT NULL DEFAULT 0,
    avg_resolution_hours NUMERIC(8,2) DEFAULT 0,
    updated_at        TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, summary_date, category_id)
);

CREATE TABLE area_summary (
    summary_id        UUID    PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id         UUID    NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    summary_date      DATE    NOT NULL,
    district          VARCHAR(100) NOT NULL,
    province          VARCHAR(100) NOT NULL DEFAULT 'กรุงเทพมหานคร',
    total_cases       INT     NOT NULL DEFAULT 0,
    open_cases        INT     NOT NULL DEFAULT 0,
    sla_breach_cases  INT     NOT NULL DEFAULT 0,
    risk_score        NUMERIC(8,4) DEFAULT 0,
    updated_at        TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, summary_date, district, province)
);

CREATE TABLE sla_summary (
    summary_id            UUID    PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id             UUID    NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    summary_date          DATE    NOT NULL,
    total_cases           INT     NOT NULL DEFAULT 0,
    on_time_cases         INT     NOT NULL DEFAULT 0,
    breached_cases        INT     NOT NULL DEFAULT 0,
    avg_response_hours    NUMERIC(8,2) DEFAULT 0,
    avg_resolution_hours  NUMERIC(8,2) DEFAULT 0,
    sla_percentage        NUMERIC(5,2) DEFAULT 0,
    updated_at            TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, summary_date)
);

CREATE TABLE ai_insight_summary (
    summary_id      UUID    PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID    NOT NULL REFERENCES tenants(tenant_id) ON DELETE CASCADE,
    summary_date    DATE    NOT NULL,
    insight_type    VARCHAR(50) NOT NULL,
    insight_message TEXT,
    priority_level  VARCHAR(20),
    generated_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, summary_date, insight_type)
);

-- InDex
CREATE INDEX idx_users_tenant ON users(tenant_id);
CREATE INDEX idx_users_line_user_id ON users(tenant_id, line_user_id);
CREATE INDEX idx_liff_sessions_line_user ON liff_sessions(tenant_id, line_user_id);
CREATE INDEX idx_liff_sessions_expires ON liff_sessions(expires_at);
CREATE INDEX idx_complaints_tenant ON complaints(tenant_id);
CREATE INDEX idx_complaints_user ON complaints(user_id);
CREATE INDEX idx_complaints_category ON complaints(category_id);
CREATE INDEX idx_complaints_status ON complaints(current_status_id);
CREATE INDEX idx_complaints_team ON complaints(assigned_team_id);
CREATE INDEX idx_complaints_created ON complaints(tenant_id, created_at DESC);
CREATE INDEX idx_complaints_date ON complaints(tenant_id, DATE(created_at));
-- สำหรับ Heatmap (ค้นหาตาม district)
CREATE INDEX idx_complaints_district ON complaints(tenant_id, district);
-- สำหรับ Full Text Search (ค้นหาเนื้อหาเรื่อง)
CREATE INDEX idx_complaints_detail_fts ON complaints USING GIN (to_tsvector('thai', COALESCE(title,'') || ' ' || COALESCE(detail,'')));
-- complaint_files
CREATE INDEX idx_files_complaint ON complaint_files(complaint_id);
 
-- workflow_logs
CREATE INDEX idx_workflow_complaint ON workflow_logs(complaint_id);
CREATE INDEX idx_workflow_datetime ON workflow_logs(action_datetime DESC);
 
-- sla_tracking
CREATE INDEX idx_sla_complaint ON sla_tracking(complaint_id);
 
-- ai_analysis
CREATE INDEX idx_ai_complaint ON ai_analysis(complaint_id);
CREATE INDEX idx_ai_analyzed ON ai_analysis(analyzed_at DESC);
 
-- notifications
CREATE INDEX idx_notif_user ON notifications(user_id, is_read);
CREATE INDEX idx_notif_complaint ON notifications(complaint_id);
 
-- audit_logs
CREATE INDEX idx_audit_tenant ON audit_logs(tenant_id, created_at DESC);
CREATE INDEX idx_audit_entity ON audit_logs(entity_type, entity_id);
 
-- summary tables (สำหรับ Dashboard query)
CREATE INDEX idx_daily_summary_date ON daily_complaint_summary(tenant_id, summary_date DESC);
CREATE INDEX idx_category_summary_date ON category_summary(tenant_id, summary_date DESC);
CREATE INDEX idx_area_summary_date ON area_summary(tenant_id, summary_date DESC);
CREATE INDEX idx_sla_summary_date ON sla_summary(tenant_id, summary_date DESC);

-- TRIGGERS — อัปเดต updated_at อัตโนมัติ

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
 
-- ติด trigger กับทุกตารางที่มี updated_at
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
 
CREATE TRIGGER trg_complaints_updated_at
    BEFORE UPDATE ON complaints
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
 
CREATE TRIGGER trg_categories_updated_at
    BEFORE UPDATE ON categories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
 
CREATE TRIGGER trg_subcategories_updated_at
    BEFORE UPDATE ON subcategories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
 
CREATE TRIGGER trg_teams_updated_at
    BEFORE UPDATE ON teams
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
 
CREATE TRIGGER trg_sla_tracking_updated_at
    BEFORE UPDATE ON sla_tracking
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
 
CREATE TRIGGER trg_liff_sessions_updated_at
    BEFORE UPDATE ON liff_sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
