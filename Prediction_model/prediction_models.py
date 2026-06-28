"""
Prediction Models — Smart Complaint Management System
======================================================
Module 1: พยากรณ์จำนวนเรื่องร้องเรียน  → Prophet (Time Series)
Module 3: Hotspot พื้นที่เสี่ยง         → DBSCAN (Clustering) + Random Forest

วิธีใช้:
  python prediction_models.py

ต้องการ:
  pip install prophet scikit-learn pandas numpy matplotlib seaborn
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import warnings
warnings.filterwarnings("ignore")

# ============================================================
# MOCK DATA — จำลองข้อมูลจากฐานข้อมูล
# ในระบบจริงเปลี่ยนเป็น query PostgreSQL
# ============================================================

def load_complaints_from_db():
    """
    ในระบบจริงใช้:
        import psycopg2
        conn = psycopg2.connect("postgresql://user:pass@host/complaint_system")
        df = pd.read_sql(query, conn)

    Query ที่ใช้:
        SELECT
            DATE(c.created_at)   AS date,
            c.category_id,
            cat.category_code,
            c.district,
            c.latitude,
            c.longitude,
            COUNT(*)             AS total,
            SUM(CASE WHEN s.is_breached THEN 1 ELSE 0 END) AS breached
        FROM complaints c
        JOIN categories cat ON c.category_id = cat.category_id
        LEFT JOIN sla_tracking s ON c.complaint_id = s.complaint_id
        WHERE c.tenant_id = '00000000-0000-0000-0000-000000000001'
          AND c.created_at >= NOW() - INTERVAL '12 months'
        GROUP BY DATE(c.created_at), c.category_id, cat.category_code,
                 c.district, c.latitude, c.longitude
    """
    np.random.seed(42)
    dates = pd.date_range("2025-01-01", "2026-05-28", freq="D")

    # จำลองฤดูกาล: ฝนตก (พ.ค.–ต.ค.) → เรื่องเยอะขึ้น
    seasonal = 1 + 0.4 * np.sin(2 * np.pi * (pd.DatetimeIndex(dates).month - 5) / 12)
    # วันหยุด (เสาร์-อาทิตย์) → เรื่องน้อยลง
    weekday_effect = np.where(pd.DatetimeIndex(dates).dayofweek >= 5, 0.6, 1.0)
    base = 18
    counts = np.random.poisson(base * seasonal * weekday_effect)

    daily_df = pd.DataFrame({"ds": dates, "y": counts})
    return daily_df


def load_complaint_locations():
    """
    Query พิกัด GPS สำหรับ Hotspot:
        SELECT latitude, longitude, district,
               cat.category_code, c.created_at
        FROM complaints c
        JOIN categories cat ON c.category_id = cat.category_id
        WHERE c.tenant_id = '00000000-0000-0000-0000-000000000001'
          AND c.latitude IS NOT NULL
          AND c.created_at >= NOW() - INTERVAL '6 months'
    """
    np.random.seed(42)
    n = 1500

    # เขต/ตำบลในปากเกร็ด + พิกัดโดยประมาณ
    districts = {
        "ปากเกร็ด":     (13.9167, 100.4958, 0.25),
        "บางพลับ":      (13.9000, 100.4833, 0.15),
        "บ้านใหม่":     (13.8833, 100.5000, 0.12),
        "คลองพระอุดม":  (13.9333, 100.5167, 0.10),
        "ท่าอิฐ":       (13.8667, 100.4667, 0.10),
        "บางตลาด":      (13.9500, 100.4833, 0.08),
        "อ้อมเกร็ด":    (13.9167, 100.5333, 0.10),
        "คลองเกลือ":    (13.8833, 100.5333, 0.10),
    }

    rows = []
    for district, (lat, lng, weight) in districts.items():
        n_dist = int(n * weight)
        lats = np.random.normal(lat, 0.01, n_dist)
        lngs = np.random.normal(lng, 0.01, n_dist)
        cats = np.random.choice(
            ["INFRA_ROAD","INFRA_DRAIN","ENV_WASTE","ORDER_TRAFFIC","HEALTH_NOISE"],
            n_dist,
            p=[0.30, 0.25, 0.20, 0.15, 0.10]
        )
        for la, lo, ca in zip(lats, lngs, cats):
            rows.append({"latitude": la, "longitude": lo,
                         "district": district, "category_code": ca})

    return pd.DataFrame(rows)


def load_holidays():
    """วันหยุดนักขัตฤกษ์ไทย 2025–2026"""
    return pd.to_datetime([
        "2025-01-01","2025-02-12","2025-04-06","2025-04-13",
        "2025-04-14","2025-04-15","2025-05-01","2025-05-05",
        "2025-06-03","2025-07-28","2025-08-12","2025-10-13",
        "2025-10-23","2025-12-05","2025-12-10","2025-12-31",
        "2026-01-01","2026-04-06","2026-04-13","2026-04-14",
        "2026-04-15","2026-05-01","2026-05-04",
    ])

# ============================================================
# MODULE 3: Hotspot พื้นที่เสี่ยง
# ============================================================
# ทำไมถึงเลือก DBSCAN + Random Forest?
#
# DBSCAN (หา Cluster พิกัด GPS):
#   - ไม่ต้องกำหนดจำนวน cluster ล่วงหน้า (ไม่รู้ว่ามีกี่จุด)
#   - จับ cluster รูปร่างอิสระได้ (ปัญหาไม่ได้กระจุกตัวเป็นวงกลม)
#   - ตรวจ outlier ได้ (จุดที่โดดเดี่ยวไม่นับเป็น hotspot)
#
# Random Forest (ทำนาย risk score รายพื้นที่):
#   - จัดการ feature หลายชนิดได้ (ตัวเลข, category, วันที่)
#   - ไม่ต้อง normalize ข้อมูล
#   - อธิบาย feature importance ได้ — บอกได้ว่า "อะไรทำให้เสี่ยง"
#   - ทนต่อ outlier และ missing data
# ============================================================

def run_module3_hotspot():
    print("\n" + "="*60)
    print("MODULE 3: Hotspot พื้นที่เสี่ยง (DBSCAN + Random Forest)")
    print("="*60)

    from sklearn.cluster import DBSCAN
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import classification_report
    from sklearn.preprocessing import LabelEncoder

    # โหลดข้อมูลพิกัด
    df = load_complaint_locations()
    print(f"  ข้อมูลพิกัดที่ใช้: {len(df):,} จุด")

    # ----------------------------------------------------------
    # STEP 1: DBSCAN — หา cluster ของจุดร้องเรียน
    # ----------------------------------------------------------
    print("\n  [STEP 1] DBSCAN Clustering...")

    coords = df[["latitude", "longitude"]].values

    # eps=0.005 ≈ 500 เมตร, min_samples=10 = ต้องมีอย่างน้อย 10 จุดจึงเป็น cluster
    db = DBSCAN(
        eps=0.005,
        min_samples=10,
        metric="haversine",  # คำนวณระยะทางบนพื้นผิวโลก (แม่นยำกว่า euclidean)
        algorithm="ball_tree"
    ).fit(np.radians(coords))  # haversine ต้องการ radians

    df["cluster"] = db.labels_
    # cluster = -1 คือ noise (จุดโดดเดี่ยว ไม่ใช่ hotspot)

    n_clusters  = len(set(db.labels_)) - (1 if -1 in db.labels_ else 0)
    n_noise     = (db.labels_ == -1).sum()
    n_hotspot   = (db.labels_ != -1).sum()

    print(f"  พบ cluster (hotspot): {n_clusters} จุด")
    print(f"  จุดที่อยู่ใน hotspot: {n_hotspot:,} ({n_hotspot/len(df)*100:.1f}%)")
    print(f"  จุดกระจัดกระจาย    : {n_noise:,} ({n_noise/len(df)*100:.1f}%)")

    # สรุปแต่ละ cluster
    if n_clusters > 0:
        print(f"\n  Top Hotspot Clusters:")
        print(f"  {'Cluster':>8} {'จำนวนเรื่อง':>12} {'ปัญหาหลัก':<20} {'ละติจูด':>10} {'ลองจิจูด':>10}")
        print(f"  {'-'*65}")

        cluster_summary = df[df["cluster"] != -1].groupby("cluster").agg(
            count=("cluster", "count"),
            lat=("latitude", "mean"),
            lng=("longitude", "mean"),
            top_cat=("category_code", lambda x: x.value_counts().index[0])
        ).sort_values("count", ascending=False).head(5)

        for cid, row in cluster_summary.iterrows():
            print(f"  {cid:>8} {row['count']:>12,} {row['top_cat']:<20} "
                  f"{row['lat']:>10.4f} {row['lng']:>10.4f}")

    # ----------------------------------------------------------
    # STEP 2: Random Forest — ทำนาย risk level รายพื้นที่
    # ----------------------------------------------------------
    print("\n  [STEP 2] Random Forest — Risk Score...")

    # สร้าง features รายเขต
    le_cat = LabelEncoder()
    le_dist = LabelEncoder()
    df["cat_encoded"]  = le_cat.fit_transform(df["category_code"])
    df["dist_encoded"] = le_dist.fit_transform(df["district"])
    df["is_hotspot"]   = (df["cluster"] != -1).astype(int)  # target

    # สร้าง feature รายเขต (aggregate)
    district_features = df.groupby("district").agg(
        total_complaints  = ("district", "count"),
        hotspot_ratio     = ("is_hotspot", "mean"),
        unique_categories = ("category_code", "nunique"),
        infra_ratio = ("category_code", lambda x: (x == "INFRA_DRAIN").mean()),
        noise_ratio = ("category_code", lambda x: (x == "HEALTH_NOISE").mean()),
    ).reset_index()

    # สร้าง risk label: HIGH ถ้า hotspot_ratio > 0.7, MEDIUM > 0.5, LOW อื่นๆ
    district_features["risk_label"] = pd.cut(
        district_features["hotspot_ratio"],
        bins=[-0.01, 0.5, 0.7, 1.01],
        labels=["LOW", "MEDIUM", "HIGH"]
    )

    # ถ้าข้อมูลน้อยเกินไปให้ข้ามการ train
    if len(district_features) < 4:
        print("  ข้อมูลไม่เพียงพอสำหรับ train (ต้องการอย่างน้อย 4 เขต)")
    else:
        feature_cols = ["total_complaints","hotspot_ratio",
                        "unique_categories","infra_ratio","noise_ratio"]
        X = district_features[feature_cols]
        y = district_features["risk_label"]

        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.3, random_state=42
        )

        rf = RandomForestClassifier(
            n_estimators=100,
            max_depth=4,           # ไม่ลึกเกินไป ป้องกัน overfit (ข้อมูลน้อย)
            min_samples_leaf=1,
            random_state=42,
            class_weight="balanced"  # ชดเชยถ้า class ไม่ balance
        )
        rf.fit(X_train, y_train)

        # Feature importance — อธิบายว่าอะไรทำให้เสี่ยง
        print(f"\n  Feature Importance (อะไรทำให้พื้นที่เสี่ยง):")
        importances = pd.Series(rf.feature_importances_, index=feature_cols)
        for feat, imp in importances.sort_values(ascending=False).items():
            bar = "█" * int(imp * 30)
            print(f"  {feat:<25} {bar:<30} {imp:.3f}")

        # ทำนาย risk ทุกเขต
        district_features["predicted_risk"] = rf.predict(X)
        print(f"\n  Risk Level รายเขต (ผลพยากรณ์):")
        print(f"  {'เขต':<20} {'เรื่องทั้งหมด':>14} {'Risk':>8}")
        print(f"  {'-'*45}")
        risk_order = {"HIGH": 0, "MEDIUM": 1, "LOW": 2}
        sorted_dist = district_features.sort_values(
            "predicted_risk", key=lambda x: x.map(risk_order)
        )
        for _, row in sorted_dist.iterrows():
            emoji = {"HIGH": "🔴", "MEDIUM": "🟡", "LOW": "🟢"}.get(
                str(row["predicted_risk"]), "⚪")
            print(f"  {row['district']:<20} {row['total_complaints']:>14,} "
                  f"{emoji} {row['predicted_risk']:>6}")

    return df, district_features


# ============================================================
# MAIN
# ============================================================

if __name__ == "__main__":
    print("\n🚀 Smart Complaint Prediction System")
    print(f"   เวลาที่รัน: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    # รัน Module 3
    location_df, district_df = run_module3_hotspot()

    print("\n" + "="*60)
    print("✅ เสร็จสิ้น — นำผลลัพธ์ไปแสดงบน Dashboard ได้เลย")
    print("="*60)
    print("""
  ขั้นตอนต่อไป:
  1. เชื่อมต่อ PostgreSQL จริงแทน mock data
  2. ตั้ง schedule รัน script นี้ทุกคืน (pg_cron หรือ APScheduler)
  3. บันทึกผลลัพธ์ลงตาราง prediction_results
  4. Frontend ดึงข้อมูลจาก /api/dashboard/prediction
    """)
