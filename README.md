# Complaint Dashboard API — คู่มือทีม Dashboard

## 🚀 วิธีรัน

```bash
# 1. ติดตั้ง dependencies
pip install -r requirements.txt

# 2. รัน API
uvicorn main:app --reload --port 8000

# 3. เปิด Swagger Docs
http://localhost:8000/docs
```

---

## 📋 API Endpoints

| Method | Endpoint | ใช้สำหรับ |
|--------|----------|-----------|
| GET | `/api/dashboard/kpi` | KPI Cards (Total, Open, SLA%) |
| GET | `/api/dashboard/trend?days=30` | Line Chart รายวัน |
| GET | `/api/dashboard/category` | Pie / Donut Chart |
| GET | `/api/dashboard/area` | Heatmap / Bar Chart |
| GET | `/api/dashboard/sla?days=30` | SLA KPI |
| GET | `/api/dashboard/ai-insight` | AI Insight Card |
| GET | `/api/dashboard/complaints?page=1&limit=20` | ตาราง Complaint |

---

## 📦 ตัวอย่าง Response

### GET /api/dashboard/kpi
```json
{
  "date": "2026-05-12",
  "total_complaints": 1250,
  "open_cases": 125,
  "in_progress_cases": 225,
  "resolved_cases": 625,
  "closed_cases": 275,
  "sla_delay_cases": 94,
  "sla_on_time_percentage": 92.5
}
```

### GET /api/dashboard/trend?days=7
```json
[
  { "date": "2026-05-06", "count": 42, "resolved": 28, "open": 5 },
  { "date": "2026-05-07", "count": 38, "resolved": 24, "open": 4 },
  ...
]
```

### GET /api/dashboard/category
```json
[
  { "category_id": 3, "category_name": "ถนน", "count": 250, "percentage": 20.0 },
  { "category_id": 1, "category_name": "น้ำประปา", "count": 225, "percentage": 18.0 },
  ...
]
```

### GET /api/dashboard/sla?days=7
```json
[
  {
    "date": "2026-05-12",
    "total_cases": 135,
    "on_time_cases": 125,
    "breached_cases": 10,
    "avg_response_hours": 4.25,
    "avg_resolution_hours": 22.10,
    "sla_percentage": 92.5
  }
]
```

### GET /api/dashboard/ai-insight
```json
[
  { "type": "TREND",     "priority": "HIGH",   "message": "เรื่องร้องเรียนประเภท 'ถนน' เพิ่มขึ้น 18%" },
  { "type": "RISK_AREA", "priority": "HIGH",   "message": "เขต A มีความเสี่ยงสูง" },
  { "type": "RECOMMEND", "priority": "MEDIUM", "message": "ควรเพิ่มเจ้าหน้าที่ทีมโครงสร้างพื้นฐาน" }
]
```

---

## 🗄️ Mock Data SQL (PostgreSQL)

ไฟล์ `mock_data.sql` ใช้รันใน PostgreSQL หลังจากสร้างตาราง 12 ตารางแล้ว:

```bash
psql -U postgres -d complaint_system -f mock_data.sql
```

จะได้ข้อมูลทั้งหมด:
- **2,000 complaints** พร้อม sla_tracking, ai_analysis, workflow_logs, notifications
- **Summary Tables** พร้อมใช้: daily_complaint_summary, category_summary, sla_summary, ai_insight_summary

---

## 🔧 API Contract (ตกลงกับ Data Team)

| Field | Type | รูปแบบ |
|-------|------|--------|
| date | string | `YYYY-MM-DD` |
| timestamp | string | `YYYY-MM-DDTHH:MM:SS` |
| percentage | float | `92.5` (ไม่ใส่ %) |
| empty list | array | `[]` |
| null field | null | `null` |

---

## 📌 หมายเหตุ

- API นี้เป็น **Mock** — ข้อมูลสร้างจาก algorithm ไม่ได้ดึงจาก DB จริง
- เมื่อ Data Team เชื่อม PostgreSQL แล้ว ให้แทนที่ mock functions ด้วย SQL query จาก Summary Tables
- ดู `main.py` ส่วน `# MOCK DATA GENERATORS` เพื่อเข้าใจ field ที่ต้องตรงกัน
