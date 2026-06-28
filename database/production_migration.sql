-- ============================================================
-- PRODUCTION MIGRATION SCRIPT
-- ระบบแดชบอร์ดอัจฉริยะ — เทศบาลนครปากเกร็ด
-- วัตถุประสงค์: นำ sla_matrix (subcategory-level) ขึ้น production
-- ============================================================
-- ลำดับการรัน:
--   STEP 1 → สร้างตาราง sla_matrix
--   STEP 2 → INSERT ข้อมูล 96 แถว (subquery แทน hardcode UUID)
--   STEP 3 → Deprecate priority_levels.sla_resolution_time_min
--   STEP 4 → สร้าง/แทนที่ VIEW v_complaint_sla
--   STEP 5 → Backfill sla_tracking จาก complaints เดิม
--   STEP 6 → เพิ่ม Index เพื่อ performance
--   STEP 7 → Verification queries ตรวจสอบผล
-- ============================================================
-- ⚠️  รันใน Transaction เดียวกันทั้งหมด — ถ้า step ไหน error
--      จะ ROLLBACK ทั้งหมดอัตโนมัติ ไม่มีข้อมูลค้างกลางทาง
-- ============================================================

BEGIN;

-- ============================================================
-- STEP 1: สร้างตาราง sla_matrix
-- ============================================================
-- ทำไมต้องสร้างใหม่:
--   ตาราง priority_levels เดิมเก็บ SLA แบบ "flat" — CRITICAL ทุก
--   เรื่องได้เวลาเท่ากันหมด ซึ่งไม่สะท้อนความเป็นจริง เช่น
--   CRITICAL ถนน (ต้องใช้เครื่องจักร 3 วัน) vs CRITICAL ไฟฟ้า
--   (เปลี่ยนหลอด 4 ชั่วโมง) ควรได้ SLA ต่างกัน
--
-- โครงสร้าง sla_matrix:
--   PK: sla_matrix_id
--   FK: tenant_id → tenants
--   FK: subcategory_id → subcategories  (24 รายการ)
--   FK: priority_id → priority_levels   (4 ระดับ)
--   UNIQUE: (subcategory_id, priority_id) — ห้ามซ้ำ
--   sla_resolution_time_min: เวลาแก้ไขหน่วยนาที
-- ============================================================

CREATE TABLE IF NOT EXISTS sla_matrix (
    sla_matrix_id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL REFERENCES tenants(tenant_id),
    subcategory_id          UUID NOT NULL REFERENCES subcategories(subcategory_id),
    priority_id             UUID NOT NULL REFERENCES priority_levels(priority_id),
    sla_resolution_time_min INT  NOT NULL,
    rationale               TEXT,
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (subcategory_id, priority_id)
);

COMMENT ON TABLE sla_matrix IS
    'SLA resolution time แยกตามคู่ subcategory × priority (ละเอียดกว่า priority_levels เดิมที่ flat ต่อ priority)';

-- ============================================================
-- STEP 2: INSERT ข้อมูล 96 แถว (24 subcategory × 4 priority)
-- ============================================================
-- ทำไมใช้ subquery แทน hardcode UUID:
--   บน dev DB ใช้ dummy UUID (22222222-0001-...) ตรงกันพอดี
--   แต่ production DB ใช้ UUID จริงที่ PostgreSQL generate
--   เช่น a3f8c2d1-9b4e-4f7a-b812-... ซึ่งต่างกันโดยสิ้นเชิง
--
--   วิธี subquery: ค้นหา UUID ด้วย "รหัส" (code) ที่ตาย
--   ไม่ว่า DB จะ generate UUID ออกมาเป็นอะไร query นี้ก็ทำงาน
--   ได้ถูกต้องเสมอ
--
-- Pattern ที่ใช้:
--   (SELECT tenant_id FROM tenants WHERE tenant_code = 'PAKKREAT')
--   (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'INFRA_ROAD')
--   (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL')
--
-- ⚠️  ถ้า tenant_code ไม่ใช่ 'PAKKREAT' ใน production → แก้บรรทัด
--      tenant_code ให้ตรงก่อนรัน
-- ============================================================

INSERT INTO sla_matrix (tenant_id, subcategory_id, priority_id, sla_resolution_time_min, rationale)
VALUES

-- ==================== INFRA: โครงสร้างพื้นฐาน ====================

-- ถนนและทางเท้า (INFRA_ROAD)
-- งานก่อสร้างหนัก ต้องใช้เครื่องจักร → SLA นานที่สุดใน category
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'INFRA_ROAD'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    4320,   -- 3 วัน: กั้นเขตทันที แต่ซ่อมจริงต้องใช้เครื่องจักร
    'ถนนยุบ/ทรุดเสี่ยงอันตราย ต้องกั้นเขตทันที (response 15 นาที) แต่ซ่อมจริงต้องใช้เครื่องจักรหนัก ให้เวลา 3 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'INFRA_ROAD'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    7200,   -- 5 วัน
    'ถนน/ทางเท้าเสียหายระดับสูง ไม่อันตรายเฉียบพลัน ให้เวลา 5 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'INFRA_ROAD'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    14400,  -- 10 วัน
    'ถนน/ทางเท้าเสียหายทั่วไป ให้เวลา 10 วันตามรอบงานก่อสร้าง'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'INFRA_ROAD'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    21600,  -- 15 วัน
    'งานปรับปรุงถนน/ทางเท้าที่ไม่เร่งด่วน รวมในแผนรอบเดือน'
),

-- ไฟฟ้าสาธารณะ (INFRA_LIGHT)
-- เปลี่ยนหลอด/ซ่อมจุดเดียว → เร็วกว่าถนนมาก
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'INFRA_LIGHT'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    240,    -- 4 ชั่วโมง: เปลี่ยนหลอดจุดเดียว ทำได้เร็ว
    'ไฟดับเสี่ยงอันตราย (เช่น จุดเปลี่ยว) แค่เปลี่ยนหลอด/ซ่อมจุดเดียว ทำได้เร็ว'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'INFRA_LIGHT'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    1440,   -- 1 วัน
    'ไฟดับหลายจุดในซอย ใช้เวลา 1 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'INFRA_LIGHT'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    4320,   -- 3 วัน
    'ไฟดับทั่วไป ตามรอบซ่อมปกติ 3 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'INFRA_LIGHT'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    10080,  -- 7 วัน
    'ข้อเสนอแนะเรื่องไฟสาธารณะ ไม่เร่งด่วน'
),

-- ระบบระบายน้ำ (INFRA_DRAIN)
-- ต้องขุด/ลอกท่อ → ปานกลาง
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'INFRA_DRAIN'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    1440,   -- 1 วัน: ต้องขุด/ลอกท่อ เร็วกว่าถนนแต่ช้ากว่าไฟฟ้า
    'น้ำท่วมขังจากท่อตัน เสี่ยงกระทบความเป็นอยู่ ต้องลอกท่อเร่งด่วน 1 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'INFRA_DRAIN'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    2880,   -- 2 วัน
    'ท่อระบายน้ำอุดตันระดับสูง ให้เวลา 2 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'INFRA_DRAIN'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    7200,   -- 5 วัน
    'ท่อระบายน้ำอุดตันทั่วไป ให้เวลา 5 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'INFRA_DRAIN'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    14400,  -- 10 วัน
    'งานปรับปรุงระบบระบายน้ำที่ไม่เร่งด่วน'
),

-- อาคารและสิ่งก่อสร้าง (INFRA_BUILDING)
-- ต้องตรวจโครงสร้าง + ขออนุมัติงบ → นานที่สุด
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'INFRA_BUILDING'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    2880,   -- 2 วัน: กั้นเขต + เชิญวิศวกรตรวจ
    'อาคารเสี่ยงถล่ม ต้องกั้นเขตทันทีและเชิญวิศวกรตรวจสอบ ให้เวลาประเมิน 2 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'INFRA_BUILDING'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    10080,  -- 7 วัน: รอขออนุมัติงบ
    'อาคารสาธารณะเสียหายระดับสูง ต้องขออนุมัติงบซ่อม ให้เวลา 7 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'INFRA_BUILDING'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    21600,  -- 15 วัน
    'อาคารเสียหายทั่วไป ให้เวลา 15 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'INFRA_BUILDING'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    30240,  -- 21 วัน
    'งานปรับปรุงอาคารที่ไม่เร่งด่วน ให้เวลา 21 วัน'
),

-- ==================== ENV: สิ่งแวดล้อมและสุขาภิบาล ====================

-- การจัดการขยะ (ENV_WASTE)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ENV_WASTE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    240,    -- 4 ชั่วโมง: ขยะอันตราย ใช้กำลังคน+รถ ทำได้เร็ว
    'ขยะอันตราย/สารเคมีรั่วไหล ใช้กำลังคน+รถเก็บ ทำได้เร็ว'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ENV_WASTE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    1440,
    'ขยะตกค้างปริมาณมาก จัดเก็บได้ภายใน 1 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ENV_WASTE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    4320,
    'การจัดการขยะทั่วไป ตามรอบเก็บปกติ'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ENV_WASTE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    10080,
    'ข้อเสนอแนะเรื่องการจัดการขยะ'
),

-- พื้นที่สีเขียว (ENV_GREEN)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ENV_GREEN'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    1440,   -- 1 วัน: กิ่งไม้หัก ต้องตัด/เก็บกู้
    'พื้นที่สีเขียวเสี่ยงอันตราย (เช่น กิ่งไม้หัก) ต้องตัด/เก็บกู้ ให้เวลา 1 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ENV_GREEN'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    2880,
    'พื้นที่สีเขียวเสียหายระดับสูง ให้เวลา 2 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ENV_GREEN'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    7200,
    'งานดูแลพื้นที่สีเขียวทั่วไป ให้เวลา 5 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ENV_GREEN'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    14400,
    'งานปรับปรุงภูมิทัศน์ที่ไม่เร่งด่วน'
),

-- ความสะอาดทั่วไป (ENV_CLEAN)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ENV_CLEAN'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    240,
    'ความสะอาดเร่งด่วน (เช่น สิ่งปฏิกูลกีดขวาง) ทำได้เร็ว'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ENV_CLEAN'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    1440,
    'ความสะอาดทั่วไประดับสูง ให้เวลา 1 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ENV_CLEAN'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    4320,
    'งานความสะอาดทั่วไป ตามรอบปกติ'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ENV_CLEAN'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    10080,
    'ข้อเสนอแนะด้านความสะอาด'
),

-- สัตว์รบกวน (ENV_ANIMAL)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ENV_ANIMAL'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    480,    -- 8 ชั่วโมง: จับ/ควบคุมสัตว์อันตราย
    'สัตว์รบกวนที่เป็นอันตราย (เช่น สุนัขดุ) ต้องจับ/ควบคุมเร่งด่วน ให้เวลา 8 ชม.'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ENV_ANIMAL'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    2880,
    'สัตว์รบกวนระดับสูง ให้เวลา 2 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ENV_ANIMAL'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    7200,
    'สัตว์รบกวนทั่วไป ให้เวลา 5 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ENV_ANIMAL'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    14400,
    'ข้อเสนอแนะเรื่องสัตว์รบกวน'
),

-- ==================== HEALTH: สาธารณสุขและมลพิษ ====================

-- เหตุรำคาญทางเสียง (HEALTH_NOISE)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'HEALTH_NOISE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    480,    -- ต้องตรวจวัด + สั่งระงับ
    'เหตุรำคาญทางเสียงรุนแรง ต้องตรวจวัด+สั่งระงับ ให้เวลา 8 ชม.'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'HEALTH_NOISE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    1440,
    'เหตุรำคาญทางเสียงระดับสูง ให้เวลา 1 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'HEALTH_NOISE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    4320,
    'เหตุรำคาญทางเสียงทั่วไป ให้เวลา 3 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'HEALTH_NOISE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    10080,
    'ข้อเสนอแนะเรื่องเสียงรบกวน'
),

-- มลพิษทางอากาศและน้ำ (HEALTH_POLLUTION)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'HEALTH_POLLUTION'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    720,    -- 12 ชั่วโมง: ต้องประสานหน่วยตรวจวัดก่อน
    'มลพิษทางอากาศ/น้ำเฉียบพลัน ต้องประสานหน่วยตรวจวัดคุณภาพก่อนดำเนินการ ให้เวลา 12 ชม.'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'HEALTH_POLLUTION'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    2880,
    'มลพิษระดับสูง ต้องรอผลตรวจ ให้เวลา 2 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'HEALTH_POLLUTION'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    7200,
    'มลพิษทั่วไป ให้เวลา 5 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'HEALTH_POLLUTION'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    14400,
    'ข้อเสนอแนะด้านมลพิษ'
),

-- การควบคุมโรค (HEALTH_DISEASE)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'HEALTH_DISEASE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    480,    -- พบแหล่งเพาะพันธุ์ยุง เร่งด่วน
    'การควบคุมโรคเร่งด่วน (เช่น พบแหล่งเพาะพันธุ์ยุง) ให้เวลา 8 ชม.'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'HEALTH_DISEASE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    1440,
    'การควบคุมโรคระดับสูง ให้เวลา 1 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'HEALTH_DISEASE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    4320,
    'การควบคุมโรคทั่วไป ให้เวลา 3 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'HEALTH_DISEASE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    10080,
    'ข้อเสนอแนะด้านควบคุมโรค'
),

-- อาหารและตลาด (HEALTH_FOOD)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'HEALTH_FOOD'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    480,    -- อาหารไม่ปลอดภัย → ตรวจสอบ+สั่งปิดทันที
    'อาหารไม่ปลอดภัยเสี่ยงอันตรายเฉียบพลัน ต้องตรวจสอบ+สั่งปิดทันที ให้เวลา 8 ชม.'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'HEALTH_FOOD'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    1440,
    'ปัญหาอาหาร/ตลาดระดับสูง ให้เวลา 1 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'HEALTH_FOOD'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    4320,
    'ปัญหาอาหาร/ตลาดทั่วไป ให้เวลา 3 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'HEALTH_FOOD'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    10080,
    'ข้อเสนอแนะด้านอาหารและตลาด'
),

-- ==================== ORDER: ความเป็นระเบียบเรียบร้อย ====================

-- การจราจรและท้องถนน (ORDER_TRAFFIC)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ORDER_TRAFFIC'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    240,    -- อุบัติเหตุ/อันตรายจราจร ต้องระงับเหตุทันที
    'อุบัติเหตุ/อันตรายจราจรเฉียบพลัน ต้องระงับเหตุทันที 4 ชม.'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ORDER_TRAFFIC'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    1440,
    'ปัญหาจราจรระดับสูง ให้เวลา 1 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ORDER_TRAFFIC'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    4320,
    'ปัญหาจราจรทั่วไป ให้เวลา 3 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ORDER_TRAFFIC'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    10080,
    'ข้อเสนอแนะด้านจราจร'
),

-- หาบเร่แผงลอย (ORDER_VENDOR)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ORDER_VENDOR'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    1440,   -- ต้องแจ้งเตือนตามขั้นตอนกฎหมายก่อน
    'หาบเร่กีดขวางทางจราจรอันตราย ต้องแจ้งเตือนตามขั้นตอนกฎหมายก่อน ให้เวลา 1 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ORDER_VENDOR'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    2880,
    'หาบเร่แผงลอยผิดที่ระดับสูง ให้เวลา 2 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ORDER_VENDOR'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    7200,
    'หาบเร่แผงลอยทั่วไป ให้เวลา 5 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ORDER_VENDOR'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    10080,
    'ข้อเสนอแนะด้านหาบเร่แผงลอย'
),

-- สัตว์จรจัด (ORDER_STRAY)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ORDER_STRAY'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    480,
    'สัตว์จรจัดอันตราย (เช่น สุนัขดุ) ต้องจับ/ควบคุมเร่งด่วน ให้เวลา 8 ชม.'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ORDER_STRAY'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    2880,
    'สัตว์จรจัดระดับสูง ให้เวลา 2 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ORDER_STRAY'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    7200,
    'สัตว์จรจัดทั่วไป ให้เวลา 5 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ORDER_STRAY'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    14400,
    'ข้อเสนอแนะด้านสัตว์จรจัด'
),

-- ป้ายผิดกฎหมาย (ORDER_SIGN)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ORDER_SIGN'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    1440,   -- ต้องแจ้งเจ้าของตามกฎหมายก่อน
    'ป้ายผิดกฎหมายเสี่ยงอันตราย (เช่น ป้ายล้ม) ต้องรื้อถอนเร่งด่วนแต่ต้องแจ้งเจ้าของก่อนตามกฎหมาย'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ORDER_SIGN'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    4320,
    'ป้ายผิดกฎหมายระดับสูง ต้องผ่านขั้นตอนแจ้งเตือนตามกฎหมาย ให้เวลา 3 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ORDER_SIGN'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    10080,
    'ป้ายผิดกฎหมายทั่วไป ให้เวลา 7 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'ORDER_SIGN'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    14400,
    'ข้อเสนอแนะด้านป้ายโฆษณา'
),

-- ==================== SOCIAL: สวัสดิการสังคม ====================

-- เบี้ยยังชีพและสวัสดิการ (SOCIAL_WELFARE)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'SOCIAL_WELFARE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    480,
    'กรณีเบี้ยยังชีพฉุกเฉิน (ผู้สูงอายุ/ผู้พิการขาดรายได้เร่งด่วน) ให้เวลา 8 ชม.'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'SOCIAL_WELFARE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    4320,
    'ปัญหาเบี้ยยังชีพระดับสูง ต้องตรวจสอบสิทธิ์ ให้เวลา 3 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'SOCIAL_WELFARE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    10080,
    'ปัญหาเบี้ยยังชีพทั่วไป ต้องผ่านขั้นตอนเอกสาร ให้เวลา 7 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'SOCIAL_WELFARE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    14400,
    'ข้อเสนอแนะด้านสวัสดิการ'
),

-- ศูนย์พัฒนาเด็กเล็ก (SOCIAL_CHILD)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'SOCIAL_CHILD'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    480,    -- เด็กในอันตราย → เร่งด่วนสูง
    'เด็กในศูนย์พัฒนาเด็กเล็กตกอยู่ในอันตราย ต้องเข้าช่วยเหลือทันที ให้เวลา 8 ชม.'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'SOCIAL_CHILD'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    2880,
    'ปัญหาศูนย์พัฒนาเด็กเล็กระดับสูง ให้เวลา 2 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'SOCIAL_CHILD'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    7200,
    'ปัญหาศูนย์พัฒนาเด็กเล็กทั่วไป ให้เวลา 5 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'SOCIAL_CHILD'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    14400,
    'ข้อเสนอแนะด้านศูนย์พัฒนาเด็กเล็ก'
),

-- กิจกรรมชุมชน (SOCIAL_COMMUNITY)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'SOCIAL_COMMUNITY'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    1440,
    'กิจกรรมชุมชนที่มีความเสี่ยงด้านความปลอดภัยเร่งด่วน ให้เวลา 1 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'SOCIAL_COMMUNITY'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    4320,
    'ปัญหากิจกรรมชุมชนระดับสูง ให้เวลา 3 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'SOCIAL_COMMUNITY'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    10080,
    'ปัญหากิจกรรมชุมชนทั่วไป ให้เวลา 7 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'SOCIAL_COMMUNITY'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    14400,
    'ข้อเสนอแนะด้านกิจกรรมชุมชน'
),

-- อาชีพและรายได้ (SOCIAL_JOB)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'SOCIAL_JOB'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    1440,
    'ปัญหาอาชีพ/รายได้เร่งด่วน (เช่น ถูกเลิกจ้างฉับพลัน) ให้เวลา 1 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'SOCIAL_JOB'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    4320,
    'ปัญหาอาชีพ/รายได้ระดับสูง ให้เวลา 3 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'SOCIAL_JOB'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    10080,
    'ปัญหาอาชีพ/รายได้ทั่วไป ให้เวลา 7 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'SOCIAL_JOB'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    14400,
    'ข้อเสนอแนะด้านอาชีพและรายได้'
),

-- ==================== GOV: การบริการและธรรมาภิบาล ====================

-- พฤติกรรมการบริการ (GOV_SERVICE)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'GOV_SERVICE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    240,    -- พฤติกรรมร้ายแรง/ทุจริต ต้องตอบเร็ว
    'พฤติกรรมการบริการร้ายแรง (เช่น ทุจริต) ต้องตอบสนองเร็ว 4 ชม.'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'GOV_SERVICE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    1440,
    'พฤติกรรมการบริการระดับสูง ให้เวลา 1 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'GOV_SERVICE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    4320,
    'พฤติกรรมการบริการทั่วไป ให้เวลา 3 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'GOV_SERVICE'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    10080,
    'ข้อเสนอแนะด้านพฤติกรรมการบริการ'
),

-- ระบบดิจิทัลและการติดต่อ (GOV_DIGITAL)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'GOV_DIGITAL'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    240,    -- ระบบล่มกระทบประชาชนจำนวนมาก
    'ระบบดิจิทัลล่มกระทบบริการประชาชนจำนวนมาก ต้องแก้ไขเร่งด่วน 4 ชม.'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'GOV_DIGITAL'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    1440,
    'ปัญหาระบบดิจิทัลระดับสูง ให้เวลา 1 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'GOV_DIGITAL'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    4320,
    'ปัญหาระบบดิจิทัลทั่วไป ให้เวลา 3 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'GOV_DIGITAL'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    10080,
    'ข้อเสนอแนะด้านระบบดิจิทัล'
),

-- ความโปร่งใส (GOV_TRANSPARENCY)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'GOV_TRANSPARENCY'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    240,
    'ปัญหาความโปร่งใสร้ายแรง ต้องตอบสนองเร็ว 4 ชม.'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'GOV_TRANSPARENCY'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    1440,
    'ปัญหาความโปร่งใสระดับสูง ให้เวลา 1 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'GOV_TRANSPARENCY'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    4320,
    'ปัญหาความโปร่งใสทั่วไป ให้เวลา 3 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'GOV_TRANSPARENCY'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    10080,
    'ข้อเสนอแนะด้านความโปร่งใส'
),

-- ข้อเสนอแนะทั่วไป (GOV_FEEDBACK)
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'GOV_FEEDBACK'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'CRITICAL'),
    240,
    'ข้อเสนอแนะทั่วไปที่ถูกตั้งเป็น CRITICAL ผิดปกติ ให้เวลา 4 ชม.'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'GOV_FEEDBACK'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'HIGH'),
    1440,
    'ข้อเสนอแนะทั่วไประดับสูง ให้เวลา 1 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'GOV_FEEDBACK'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'MEDIUM'),
    4320,
    'ข้อเสนอแนะทั่วไป ให้เวลา 3 วัน'
),
(
    (SELECT tenant_id FROM tenants WHERE tenant_code = 'BMA'),
    (SELECT subcategory_id FROM subcategories WHERE subcategory_code = 'GOV_FEEDBACK'),
    (SELECT priority_id FROM priority_levels WHERE priority_code = 'LOW'),
    10080,
    'ข้อเสนอแนะทั่วไปลำดับต่ำสุด ให้เวลา 7 วัน'
)
;

-- ============================================================
-- STEP 3: Deprecate priority_levels.sla_resolution_time_min
-- ============================================================
-- ทำไมต้อง SET NULL:
--   คอลัมน์นี้เก็บค่า SLA แบบ flat เดิม เช่น CRITICAL = 240 นาที
--   ทุก subcategory ซึ่งไม่ถูกต้องอีกต่อไป ถ้าปล่อยไว้และ
--   นักพัฒนาคนอื่น (หรือตัวเองอีก 3 เดือนข้างหน้า) เผลอ query
--   คอลัมน์นี้โดยตรง จะได้ค่าผิดแต่ดูเหมือนถูก ซึ่งอันตรายกว่า
--   ได้ NULL เพราะ NULL ทำให้รู้ทันทีว่าต้อง JOIN sla_matrix แทน
--
-- response_time_min ยังใช้ได้ปกติ → ไม่แตะ
-- ============================================================

UPDATE priority_levels
SET
    sla_resolution_time_min = NULL,
    updated_at              = CURRENT_TIMESTAMP;

COMMENT ON COLUMN priority_levels.sla_resolution_time_min IS
    '[DEPRECATED] ใช้ sla_matrix.sla_resolution_time_min แทน (แยกตาม subcategory × priority ละเอียดกว่า)';

-- ============================================================
-- STEP 4: สร้าง/แทนที่ VIEW v_complaint_sla
-- ============================================================
-- VIEW นี้เป็น "จุดเดียว" ที่ทุก query ควรใช้คำนวณ SLA
-- รวม response SLA (จาก priority_levels) และ
-- resolution SLA (จาก sla_matrix ใหม่) ไว้ในที่เดียว
--
-- คอลัมน์สำคัญ:
--   sla_response_time_min    → เวลาตอบสนองครั้งแรก (คง priority_levels)
--   sla_resolution_time_min  → เวลาแก้ไขสำเร็จ (ใหม่ จาก sla_matrix)
--   actual_resolution_min    → เวลาจริงที่ใช้แก้ไข (นาที)
--   is_resolution_breached   → TRUE = เกิน SLA, FALSE = อยู่ใน SLA, NULL = ยังไม่ resolved
-- ============================================================

CREATE OR REPLACE VIEW v_complaint_sla AS
SELECT
    c.complaint_id,
    c.complaint_no,
    c.tenant_id,
    c.category_id,
    c.subcategory_id,
    c.priority_id,
    c.created_at,
    c.resolved_at,
    c.closed_at,
    c.current_status_id,
    c.district,

    -- Response SLA: ยังอิง priority_levels (เวลาตอบสนองครั้งแรก)
    pl.priority_code,
    pl.priority_name,
    pl.sla_response_time_min,

    -- Resolution SLA: อิง sla_matrix (ละเอียดระดับ subcategory)
    sm.sla_resolution_time_min,
    sm.rationale AS sla_rationale,

    -- เวลาจริงที่ใช้แก้ไข (นาที) — NULL ถ้ายังไม่ resolved
    EXTRACT(EPOCH FROM (c.resolved_at - c.created_at)) / 60.0
        AS actual_resolution_min,

    -- ตรวจสอบว่าเกิน SLA หรือไม่
    --   NULL  = ยังไม่ resolved ยังตัดสินไม่ได้
    --   TRUE  = resolved แล้วแต่เกินเวลา SLA
    --   FALSE = resolved ภายใน SLA
    CASE
        WHEN c.resolved_at IS NULL THEN NULL
        WHEN sm.sla_resolution_time_min IS NULL THEN NULL  -- ไม่มี SLA กำหนด
        WHEN EXTRACT(EPOCH FROM (c.resolved_at - c.created_at)) / 60.0
             > sm.sla_resolution_time_min THEN TRUE
        ELSE FALSE
    END AS is_resolution_breached,

    -- เวลาที่เหลือก่อนครบ SLA (นาที) — ถ้าติดลบ = เกิน SLA แล้ว
    CASE
        WHEN c.resolved_at IS NOT NULL THEN NULL  -- จบแล้ว ไม่ต้องนับ
        WHEN sm.sla_resolution_time_min IS NULL THEN NULL
        ELSE sm.sla_resolution_time_min
             - EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - c.created_at)) / 60.0
    END AS remaining_sla_min

FROM complaints c
JOIN priority_levels pl
    ON c.priority_id = pl.priority_id
LEFT JOIN sla_matrix sm
    ON  c.subcategory_id = sm.subcategory_id
    AND c.priority_id    = sm.priority_id
    AND sm.is_active     = TRUE;

COMMENT ON VIEW v_complaint_sla IS
    'จุดรวม SLA ทั้งหมดต่อเคส: response SLA (priority_levels) + resolution SLA (sla_matrix subcategory×priority) ทุก query ที่เกี่ยวกับ SLA ควรใช้ VIEW นี้';

-- ============================================================
-- STEP 5: Backfill ตาราง sla_tracking
-- ============================================================
-- ทำไมต้อง backfill:
--   sla_tracking ปัจจุบันไม่มีข้อมูลเลย (0 แถว)
--   แต่ complaints มี 5,200 แถวที่ควรมี SLA tracking
--   การ backfill ทำให้ dashboard แสดง SLA history ย้อนหลังได้
--
-- Logic:
--   แต่ละ complaint → insert 2 แถวใน sla_tracking:
--     แถว 1: RESPONSE SLA  — วัดเวลาตอบสนองครั้งแรก
--     แถว 2: RESOLUTION SLA — วัดเวลาแก้ไขสำเร็จ
--
--   due_time  = created_at + target_minutes
--   is_breached:
--     RESPONSE  → ถ้า assigned_user_id ถูก set ใน workflow_logs
--                  แต่ระบบนี้ไม่มี first_response_at ตรงๆ
--                  → ใช้ resolved_at แทนเพื่อ simplicity
--     RESOLUTION → resolved_at > due_time
-- ============================================================

INSERT INTO sla_tracking (
    complaint_id,
    sla_type,
    sla_name,
    start_time,
    due_time,
    target_minutes,
    resolution_time_minutes,
    is_breached,
    breached_at,
    breached_reason,
    sla_status,
    is_active
)
SELECT
    -- ========== แถวที่ 1: RESPONSE SLA ==========
    c.complaint_id,
    'RESPONSE'                                  AS sla_type,
    'SLA ตอบสนองครั้งแรก (' || pl.priority_name || ')' AS sla_name,
    c.created_at                                AS start_time,
    c.created_at + (pl.sla_response_time_min || ' minutes')::INTERVAL
                                                AS due_time,
    pl.sla_response_time_min                    AS target_minutes,

    -- เวลาจริงที่ใช้ก่อน resolved (นาทีแบบ decimal)
    CASE
        WHEN c.resolved_at IS NOT NULL THEN
            ROUND(EXTRACT(EPOCH FROM (c.resolved_at - c.created_at)) / 60.0, 2)
        ELSE NULL
    END                                         AS resolution_time_minutes,

    -- is_breached: resolved หลัง due_time หรือยัง pending เกิน due_time
    CASE
        WHEN c.resolved_at IS NOT NULL THEN
            c.resolved_at > (c.created_at + (pl.sla_response_time_min || ' minutes')::INTERVAL)
        WHEN c.resolved_at IS NULL THEN
            CURRENT_TIMESTAMP > (c.created_at + (pl.sla_response_time_min || ' minutes')::INTERVAL)
        ELSE FALSE
    END                                         AS is_breached,

    -- breached_at: เวลาที่ครบ due_time (ถ้า breach)
    CASE
        WHEN c.resolved_at IS NOT NULL
         AND c.resolved_at > (c.created_at + (pl.sla_response_time_min || ' minutes')::INTERVAL)
        THEN c.created_at + (pl.sla_response_time_min || ' minutes')::INTERVAL
        WHEN c.resolved_at IS NULL
         AND CURRENT_TIMESTAMP > (c.created_at + (pl.sla_response_time_min || ' minutes')::INTERVAL)
        THEN c.created_at + (pl.sla_response_time_min || ' minutes')::INTERVAL
        ELSE NULL
    END                                         AS breached_at,

    CASE
        WHEN c.resolved_at IS NOT NULL
         AND c.resolved_at > (c.created_at + (pl.sla_response_time_min || ' minutes')::INTERVAL)
        THEN 'ใช้เวลาเกินกว่า SLA response time กำหนด'
        ELSE NULL
    END                                         AS breached_reason,

    CASE
        WHEN c.resolved_at IS NOT NULL THEN
            CASE WHEN c.resolved_at > (c.created_at + (pl.sla_response_time_min || ' minutes')::INTERVAL)
                 THEN 'BREACHED' ELSE 'ON_TIME' END
        ELSE 'PENDING'
    END                                         AS sla_status,
    TRUE                                        AS is_active

FROM complaints c
JOIN priority_levels pl ON c.priority_id = pl.priority_id

UNION ALL

SELECT
    -- ========== แถวที่ 2: RESOLUTION SLA ==========
    c.complaint_id,
    'RESOLUTION'                                AS sla_type,
    'SLA แก้ไขสำเร็จ (' || sub.subcategory_name || ' / ' || pl.priority_name || ')' AS sla_name,
    c.created_at                                AS start_time,
    c.created_at + (sm.sla_resolution_time_min || ' minutes')::INTERVAL
                                                AS due_time,
    sm.sla_resolution_time_min                  AS target_minutes,

    CASE
        WHEN c.resolved_at IS NOT NULL THEN
            ROUND(EXTRACT(EPOCH FROM (c.resolved_at - c.created_at)) / 60.0, 2)
        ELSE NULL
    END                                         AS resolution_time_minutes,

    CASE
        WHEN c.resolved_at IS NOT NULL THEN
            c.resolved_at > (c.created_at + (sm.sla_resolution_time_min || ' minutes')::INTERVAL)
        WHEN c.resolved_at IS NULL THEN
            CURRENT_TIMESTAMP > (c.created_at + (sm.sla_resolution_time_min || ' minutes')::INTERVAL)
        ELSE FALSE
    END                                         AS is_breached,

    CASE
        WHEN c.resolved_at IS NOT NULL
         AND c.resolved_at > (c.created_at + (sm.sla_resolution_time_min || ' minutes')::INTERVAL)
        THEN c.created_at + (sm.sla_resolution_time_min || ' minutes')::INTERVAL
        WHEN c.resolved_at IS NULL
         AND CURRENT_TIMESTAMP > (c.created_at + (sm.sla_resolution_time_min || ' minutes')::INTERVAL)
        THEN c.created_at + (sm.sla_resolution_time_min || ' minutes')::INTERVAL
        ELSE NULL
    END                                         AS breached_at,

    CASE
        WHEN c.resolved_at IS NOT NULL
         AND c.resolved_at > (c.created_at + (sm.sla_resolution_time_min || ' minutes')::INTERVAL)
        THEN 'ใช้เวลาเกินกว่า SLA resolution time ของ subcategory นี้'
        ELSE NULL
    END                                         AS breached_reason,

    CASE
        WHEN c.resolved_at IS NOT NULL THEN
            CASE WHEN c.resolved_at > (c.created_at + (sm.sla_resolution_time_min || ' minutes')::INTERVAL)
                 THEN 'BREACHED' ELSE 'ON_TIME' END
        ELSE 'PENDING'
    END                                         AS sla_status,
    TRUE                                        AS is_active

FROM complaints c
JOIN priority_levels pl  ON c.priority_id    = pl.priority_id
JOIN sla_matrix sm       ON c.subcategory_id = sm.subcategory_id
                        AND c.priority_id    = sm.priority_id
                        AND sm.is_active     = TRUE
JOIN subcategories sub   ON c.subcategory_id = sub.subcategory_id
;

-- ============================================================
-- STEP 6: เพิ่ม Index เพื่อ performance
-- ============================================================
-- ทำไมต้อง index:
--   complaints 5,200 แถว JOIN sla_matrix ทุกครั้งที่ dashboard โหลด
--   composite index บน (subcategory_id, priority_id) ทำให้
--   PostgreSQL ใช้ index scan แทน sequential scan → เร็วขึ้น 10-50x
--   สำหรับ dataset ขนาดนี้
-- ============================================================

-- Index หลัก: JOIN key ของ sla_matrix
CREATE INDEX IF NOT EXISTS idx_sla_matrix_sub_pri
    ON sla_matrix (subcategory_id, priority_id)
    WHERE is_active = TRUE;

-- Index สำหรับ filter tenant
CREATE INDEX IF NOT EXISTS idx_sla_matrix_tenant
    ON sla_matrix (tenant_id);

-- Index สำหรับ sla_tracking ที่ query บ่อย
CREATE INDEX IF NOT EXISTS idx_sla_tracking_complaint
    ON sla_tracking (complaint_id, sla_type);

CREATE INDEX IF NOT EXISTS idx_sla_tracking_breach
    ON sla_tracking (is_breached, sla_status)
    WHERE is_active = TRUE;

-- ============================================================
-- STEP 7: Verification — ตรวจสอบผลหลัง migrate
-- ============================================================

-- 7.1 ตรวจ sla_matrix ครบ 96 คู่ (ถ้า return 0 แถว = ดี)
SELECT
    'missing_sla_matrix_rows' AS check_name,
    COUNT(*) AS count,
    CASE WHEN COUNT(*) = 0 THEN '✓ PASS' ELSE '✗ FAIL — ขาด SLA บางคู่' END AS result
FROM subcategories sub
CROSS JOIN priority_levels pl
LEFT JOIN sla_matrix sm
    ON sub.subcategory_id = sm.subcategory_id
   AND pl.priority_id     = sm.priority_id
WHERE sm.sla_matrix_id IS NULL;

-- 7.2 ตรวจ priority_levels.sla_resolution_time_min เป็น NULL ครบ
SELECT
    'deprecated_column_nulled' AS check_name,
    COUNT(*) FILTER (WHERE sla_resolution_time_min IS NOT NULL) AS still_has_value,
    CASE WHEN COUNT(*) FILTER (WHERE sla_resolution_time_min IS NOT NULL) = 0
         THEN '✓ PASS' ELSE '✗ FAIL' END AS result
FROM priority_levels;

-- 7.3 ตรวจ sla_tracking backfill (ควรได้ 5200 × 2 = 10,400 แถว)
SELECT
    'sla_tracking_backfill' AS check_name,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE sla_type = 'RESPONSE')   AS response_rows,
    COUNT(*) FILTER (WHERE sla_type = 'RESOLUTION') AS resolution_rows,
    CASE WHEN COUNT(*) = 10400 THEN '✓ PASS' ELSE '⚠ CHECK — ควรได้ 10400' END AS result
FROM sla_tracking;

-- 7.4 ตัวอย่างผล v_complaint_sla 5 แถวแรก
SELECT
    complaint_no,
    district,
    priority_code,
    sla_response_time_min,
    sla_resolution_time_min,
    ROUND(actual_resolution_min::numeric, 0) AS actual_min,
    is_resolution_breached,
    ROUND(remaining_sla_min::numeric, 0)     AS remaining_min
FROM v_complaint_sla
ORDER BY created_at;

-- 7.5 สรุป SLA breach rate รายหมวด
SELECT
    sub.subcategory_name,
    pl.priority_name,
    COUNT(*)                                                    AS total,
    COUNT(*) FILTER (WHERE v.is_resolution_breached = TRUE)    AS breached,
    COUNT(*) FILTER (WHERE v.is_resolution_breached = FALSE)   AS on_time,
    ROUND(
        COUNT(*) FILTER (WHERE v.is_resolution_breached = TRUE)::numeric
        / NULLIF(COUNT(*) FILTER (WHERE v.is_resolution_breached IS NOT NULL), 0) * 100,
        1
    )                                                           AS breach_pct
FROM v_complaint_sla v
JOIN subcategories sub ON v.subcategory_id = sub.subcategory_id
JOIN priority_levels pl ON v.priority_id   = pl.priority_id
GROUP BY sub.subcategory_name, pl.priority_name, pl.display_order
ORDER BY pl.display_order, breach_pct DESC NULLS LAST;

COMMIT;

-- ============================================================
-- หมายเหตุสำคัญสำหรับ FastAPI (main.py)
-- ============================================================
-- หลัง migrate แล้ว endpoint ที่ต้องอัปเดต:
--
-- ❌ เดิม (อย่าใช้อีก):
--   SELECT sla_resolution_time_min FROM priority_levels WHERE ...
--
-- ✓ ใหม่ (ใช้แทน):
--   SELECT sla_resolution_time_min, is_resolution_breached,
--          remaining_sla_min
--   FROM v_complaint_sla
--   WHERE complaint_id = $1
--
-- ✓ สำหรับ Dashboard SLA summary:
--   SELECT * FROM v_complaint_sla
--   WHERE tenant_id = $1
--     AND is_resolution_breached IS NOT NULL
-- ============================================================
