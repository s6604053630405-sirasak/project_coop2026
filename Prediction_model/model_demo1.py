# ======================================================================================
# Complaint Risk Prediction Pipeline (FIXED VERSION)
# โมเดลประเมินความเสี่ยงของเรื่องร้องเรียน ณ "เวลายื่นเรื่อง" (intake-time scoring)
#
# Risk 3 มิติ (3 binary targets):
#   1) sla_breached  -> จาก sla_tracking.is_breached
#   2) was_rejected  -> จาก workflow_logs.action_type = 'REJECT'  (ของจริง ไม่ใช่ proxy)
#   3) was_reopened  -> จาก workflow_logs.action_type = 'REOPEN'  (ของจริง ไม่ใช่ proxy)
#
# แก้บั๊ก/จุดอ่อนหลักจากโน้ตบุ๊กเดิม (complaint_risk_prediction.ipynb):
#   - เดิม: ดึง audit_logs มาหา REOPEN แต่ไม่ได้ query ตารางนี้จาก DB เลย (TABLES list ไม่มี audit_logs) -> error
#   - เดิม: is_rejected ใช้ proxy "resolved_at เป็น null" ซึ่งผิด เพราะเคสที่ยังไม่เสร็จก็เป็น null เหมือนกัน
#           ความจริงระบบมี workflow_logs.action_type = 'REJECT' อยู่แล้ว ควรใช้ตรงนี้
#   - เดิม: cat_breach_rate_hist / dist_breach_rate_hist คำนวณจาก mean ของทั้ง df (รวมอนาคต) -> DATA LEAKAGE
#           เพราะ ณ เวลาที่เคสหนึ่งถูกยื่น เรายังไม่รู้ผลของเคสที่ยื่นทีหลัง
#   - เดิม: sla_response_time_min / sla_resolution_time_min ดึงจาก priority_levels ทั้งคู่
#           แต่ schema จริง priority_levels มีแค่ sla_response_time_min, ส่วน sla_resolution_time_min
#           ต้อง join จาก sla_matrix (subcategory_id + priority_id) ตามที่ออกแบบไว้จริงใน DB
#   - เดิม: train_test_split แบบ random stratify -> ใช้ข้อมูลอนาคตช่วย "ทำนาย" ข้อมูลอดีตได้ (เวลาปนกัน)
#           ควร split ตามเวลา (temporal split) ให้สอดคล้องกับการใช้งานจริง (ทำนายเคสใหม่ที่ยังไม่เกิด)
# ======================================================================================
 
import warnings
warnings.filterwarnings('ignore')
 
import numpy as np
import pandas as pd
from sqlalchemy import create_engine
from sklearn.cluster import DBSCAN
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.model_selection import StratifiedKFold
from sklearn.metrics import roc_auc_score, average_precision_score, classification_report
from imblearn.over_sampling import SMOTENC
from xgboost import XGBClassifier
import shap
import joblib
 
pd.set_option('display.max_columns', 60)
 
# ======================================================================================
# STEP 1) LOAD DATA FROM DATABASE
# ทำไม: ต้องดึงทุกตารางที่เกี่ยวกับ "เนื้อหาเคส", "เวลา/SLA", และ "ผลลัพธ์ของ workflow"
#       เพิ่ม workflow_logs (สำคัญที่สุด - ใช้สร้าง label REJECT/REOPEN ของจริง)
#       เพิ่ม complaint_files (ใช้สร้าง feature has_photo / evidence)
# ======================================================================================
db_connection = 'postgresql://postgres:220248@localhost:5432/complaint_system'
conn = create_engine(db_connection)
 
TABLES = [
    'complaints', 'categories', 'subcategories', 'priority_levels',
    'sla_matrix', 'sla_tracking', 'workflow_logs', 'complaint_files',
]
dfs = {}
for t in TABLES:
    dfs[t] = pd.read_sql(f"SELECT * FROM public.{t}", conn)
    print(f'{t:20s}: {len(dfs[t]):>7,} rows')
 
complaints    = dfs['complaints'].copy()
categories    = dfs['categories'].copy()
subcategories = dfs['subcategories'].copy()
priority_lvl  = dfs['priority_levels'].copy()
sla_matrix    = dfs['sla_matrix'].copy()
sla_tracking  = dfs['sla_tracking'].copy()
workflow_logs = dfs['workflow_logs'].copy()
complaint_files = dfs['complaint_files'].copy()
 
# --- type casting ---
for col in ['created_at', 'updated_at', 'resolved_at', 'closed_at', 'due_date']:
    complaints[col] = pd.to_datetime(complaints[col], errors='coerce')
 
workflow_logs['action_datetime'] = pd.to_datetime(workflow_logs['action_datetime'], errors='coerce')
sla_tracking['is_breached'] = sla_tracking['is_breached'].map({'t': True, 'f': False, True: True, False: False})
complaints['latitude']  = pd.to_numeric(complaints['latitude'], errors='coerce')
complaints['longitude'] = pd.to_numeric(complaints['longitude'], errors='coerce')
 
# ======================================================================================
# STEP 2) BUILD TARGET LABELS — ใช้ของจริงจาก workflow_logs ไม่ใช้ proxy
# ทำไม: workflow_logs.action_type มีค่า REJECT / REOPEN ตรงตัวอยู่แล้ว (chk_action_type constraint)
#       การคำนวณ proxy จาก resolved_at เป็น null ผิดหลักการ เพราะปนกับเคสที่ "ยังไม่เสร็จ" (เช่น PENDING)
# ======================================================================================
reject_ids  = set(workflow_logs.loc[workflow_logs['action_type'] == 'REJECT',  'complaint_id'])
reopen_ids  = set(workflow_logs.loc[workflow_logs['action_type'] == 'REOPEN',  'complaint_id'])
 
sla_breach_label = (
    sla_tracking.groupby('complaint_id')['is_breached']
    .any()
    .rename('sla_breached')
)
 
df = complaints.merge(sla_breach_label, on='complaint_id', how='left')
df['sla_breached'] = df['sla_breached'].fillna(False).astype(int)
df['was_rejected'] = df['complaint_id'].isin(reject_ids).astype(int)
df['was_reopened'] = df['complaint_id'].isin(reopen_ids).astype(int)
 
print('\nTarget rates:')
print('  SLA breach rate :', df['sla_breached'].mean())
print('  Reject rate     :', df['was_rejected'].mean())
print('  Reopen rate     :', df['was_reopened'].mean())
 
# ======================================================================================
# STEP 3) MERGE LOOKUPS (category / subcategory / priority / SLA target)
# ทำไม sla_resolution_time_min ต้องมาจาก sla_matrix (subcategory_id + priority_id):
#   จาก schema จริง priority_levels มีเฉพาะ "sla_response_time_min" (เวลาตอบรับ)
#   ส่วน "เวลาที่ต้องแก้ให้เสร็จ" ถูกกำหนดละเอียดระดับ subcategory x priority ใน sla_matrix
#   (ดูตัวอย่าง: ถนนยุบ+CRITICAL=3วัน แต่ถนนยุบ+LOW=15วัน) — ถ้าใช้ค่าจาก priority_levels เพียวๆ
#   จะสูญข้อมูล "ความหนักของงาน" ที่ sla_matrix ให้ไว้ และจะทำให้ feature สำคัญที่สุดผิด
# ======================================================================================
df = df.merge(categories[['category_id', 'category_name', 'category_code']], on='category_id', how='left')
df = df.merge(subcategories[['subcategory_id', 'subcategory_name', 'subcategory_code']], on='subcategory_id', how='left')
df = df.merge(priority_lvl[['priority_id', 'priority_name', 'priority_code', 'sla_response_time_min']],
              on='priority_id', how='left')
df = df.merge(
    sla_matrix[['subcategory_id', 'priority_id', 'sla_resolution_time_min']],
    on=['subcategory_id', 'priority_id'], how='left'
)
 
# --- evidence / media feature ---
file_counts = complaint_files.groupby('complaint_id').size().rename('file_count')
df = df.join(file_counts, on='complaint_id')
df['file_count'] = df['file_count'].fillna(0)
df['has_photo']  = (df['file_count'] > 0).astype(int)
 
# ======================================================================================
# STEP 4) GEOGRAPHIC CLUSTERING (DBSCAN) — สอดคล้องกับ pipeline SLA breach ที่ทำไว้แล้ว
# ทำไมต้องใช้ DBSCAN แทนการใช้ district อย่างเดียว:
#   district เป็นเขตการปกครอง ซึ่งอาจกว้างเกินจริง (ปัญหาจริงกระจุกตัวเฉพาะบางจุด/บางซอย)
#   DBSCAN จาก lat/long จะรวมกลุ่ม "พื้นที่ปัญหาซ้ำซาก" (hotspot) ที่ตัด district ไม่ตรงกับขอบเขตจริง
#   ใช้ eps ~250m (แปลงจาก degree คร่าวๆ) เพราะเป็น scale ของซอย/ถนนในเขตเมือง
# ======================================================================================
geo_mask = df['latitude'].notna() & df['longitude'].notna()
df['geo_cluster'] = -1
if geo_mask.sum() > 0:
    coords = df.loc[geo_mask, ['latitude', 'longitude']].values
    db = DBSCAN(eps=0.0025, min_samples=8).fit(coords)   # eps ~250m ในกรุงเทพฯ
    df.loc[geo_mask, 'geo_cluster'] = db.labels_
 
# ======================================================================================
# STEP 5) TIME-BASED FEATURES
# ทำไม: ภาระงาน/พฤติกรรมเจ้าหน้าที่ต่างกันตามช่วงเวลา เช่น เคสที่ยื่นวันศุกร์เย็น/เสาร์-อาทิตย์
#       กว่าจะมีคนเริ่มทำงานจริงคือวันทำการถัดไป -> เสี่ยง breach สูงกว่าโดยธรรมชาติ
# ======================================================================================
df['hour_of_day']      = df['created_at'].dt.hour
df['day_of_week']      = df['created_at'].dt.dayofweek
df['is_weekend']       = (df['day_of_week'] >= 5).astype(int)
df['is_working_hours'] = df['hour_of_day'].between(8, 17).astype(int)
df['month']            = df['created_at'].dt.month
 
# ======================================================================================
# STEP 6) POINT-IN-TIME HISTORICAL RISK FEATURES (แก้ DATA LEAKAGE หลักของโน้ตบุ๊กเดิม)
# หลักการ: สำหรับเคสที่ถูกยื่นในเวลา t เราจะคำนวณ "อัตราความเสี่ยงในอดีต" ของ category/subcategory/
#          district/geo_cluster โดยใช้เฉพาะเคสที่ created_at < t เท่านั้น (expanding, shift(1))
#          ทำไมสำคัญมาก: ถ้าใช้ mean ของทั้งชุดข้อมูล (รวมเคสในอนาคต) โมเดลจะ "แอบรู้" ผลลัพธ์ที่ยังไม่
#          เกิดขึ้นจริง ทำให้ตอน production ความแม่นยำจะตกฮวบ เพราะข้อมูลอนาคตจริงไม่มีให้ใช้
# วิธีทำ: sort by created_at -> groupby key -> cumulative sum/count ของ target ที่ "ก่อนแถวนี้" (shift)
# ======================================================================================
df = df.sort_values('created_at').reset_index(drop=True)
 
def add_point_in_time_rate(frame, key, target, new_col, min_history=5, global_fallback=None):
    """
    คำนวณอัตราความเสี่ยงสะสม 'ก่อนหน้า' ของกลุ่ม key สำหรับ target ที่กำหนด
    min_history: ถ้ากลุ่มนั้นยังมีประวัติน้อยกว่าค่านี้ ให้ใช้ global rate ของข้อมูลที่ผ่านมาแทน
                 (กันปัญหาเคสแรกๆของหมวดใหม่ ไม่มีประวัติให้อ้างอิงเลย)
    """
    grp = frame.groupby(key)[target]
    cum_sum   = grp.cumsum() - frame[target]          # sum ของ target ก่อนแถวนี้ (ไม่รวมตัวเอง)
    cum_count = grp.cumcount()                        # จำนวนเคสก่อนหน้าในกลุ่มนี้ (ไม่รวมตัวเอง)
    rate = cum_sum / cum_count.replace(0, np.nan)
 
    # global fallback แบบ point-in-time เช่นกัน (อัตราเฉลี่ยรวมทุกกลุ่ม ณ ก่อนแถวนี้)
    global_cum_sum   = frame[target].cumsum() - frame[target]
    global_cum_count = np.arange(len(frame))
    global_rate = global_cum_sum / np.where(global_cum_count == 0, np.nan, global_cum_count)
 
    rate = rate.where(cum_count >= min_history, global_rate)
    frame[new_col] = rate.fillna(frame[target].mean())  # บรรทัดแรกสุดของข้อมูลทั้งหมด fallback เป็น mean รวม
    return frame
 
for target in ['sla_breached', 'was_rejected', 'was_reopened']:
    df = add_point_in_time_rate(df, 'category_id',    target, f'cat_{target}_rate_hist')
    df = add_point_in_time_rate(df, 'subcategory_id',  target, f'subcat_{target}_rate_hist')
    df = add_point_in_time_rate(df, 'district',        target, f'dist_{target}_rate_hist')
    df = add_point_in_time_rate(df, 'geo_cluster',     target, f'geo_{target}_rate_hist')
 
# ---- volume / workload proxy (ก่อนหน้าเท่านั้น) ----
# ทำไม: จำนวนเคสสะสมในกลุ่มเดียวกันที่ "เคยมีมาก่อน" สะท้อนภาระงานของทีมที่รับผิดชอบพื้นที่/ประเภทนั้น
#       ยิ่งมีเคสสะสมมาก ยิ่งมีโอกาส backlog สูง -> breach สูงตามไปด้วย
df['cat_volume_hist']  = df.groupby('category_id').cumcount()
df['dist_volume_hist'] = df.groupby('district').cumcount()
 
# ======================================================================================
# STEP 7) TEXT / DETAIL FEATURES
# ทำไม: ai_analysis (sentiment) ในระบบยังมีข้อมูลน้อยมาก (เก็บได้ ~8 แถวจากเคสนับหมื่น) จึงยังใช้เป็น
#       feature หลักไม่ได้ตอนนี้ ใช้ proxy ง่ายๆจากความยาวข้อความ/มีรายละเอียดเสริมหรือไม่แทน
# ======================================================================================
df['detail_len']            = df['detail'].fillna('').str.len()
df['has_additional_detail'] = df['additional_detail'].notna().astype(int)
df['has_location_text']     = df['location_text'].notna().astype(int)
df['has_coordinates']       = (df['latitude'].notna() & df['longitude'].notna()).astype(int)
 
# ======================================================================================
# STEP 8) FINAL FEATURE SET
# ======================================================================================
CAT_FEATURES = ['category_code', 'subcategory_code', 'priority_code', 'district', 'geo_cluster']
 
NUM_FEATURES = [
    'hour_of_day', 'day_of_week', 'is_weekend', 'is_working_hours', 'month',
    'sla_response_time_min', 'sla_resolution_time_min',
    'detail_len', 'has_additional_detail', 'has_location_text', 'has_coordinates',
    'has_photo', 'file_count',
    'cat_volume_hist', 'dist_volume_hist',
] + [f'{lvl}_{t}_rate_hist' for lvl in ['cat', 'subcat', 'dist', 'geo']
                              for t in ['sla_breached', 'was_rejected', 'was_reopened']]
 
ALL_FEATURES = CAT_FEATURES + NUM_FEATURES
TARGETS = ['sla_breached', 'was_rejected', 'was_reopened']
 
model_df = df[ALL_FEATURES + TARGETS + ['created_at', 'complaint_id']].copy()
for c in CAT_FEATURES:
    model_df[c] = model_df[c].fillna('UNKNOWN').astype(str)
for c in NUM_FEATURES:
    model_df[c] = model_df[c].fillna(model_df[c].median())
 
# ======================================================================================
# STEP 9) TEMPORAL TRAIN/TEST SPLIT (ไม่ใช่ random) — เพื่อจำลองการใช้งานจริง
# ทำไม: โมเดลต้อง "ทำนายเคสในอนาคต" จากข้อมูลในอดีต ถ้า split แบบ random stratify เหมือนเดิม
#       เคสในอนาคตบางส่วนจะหลุดไปอยู่ train set แล้วช่วยทำนายเคสในอดีตที่อยู่ test set ได้ ซึ่งไม่ตรงกับ
#       สถานการณ์จริงเลย (สอดคล้องกับแนวทางที่ใช้ใน sla_breach_prediction pipeline หลักแล้ว)
# ======================================================================================
model_df = model_df.sort_values('created_at').reset_index(drop=True)
split_idx = int(len(model_df) * 0.8)
train_df, test_df = model_df.iloc[:split_idx].copy(), model_df.iloc[split_idx:].copy()
print(f'\nTrain: {train_df.shape[0]:,} (until {train_df["created_at"].max()})')
print(f'Test : {test_df.shape[0]:,}  (from {test_df["created_at"].min()})')
 
# ======================================================================================
# STEP 10) ENCODE CATEGORICALS (LabelEncoder + handle-unknown สำหรับ test ที่มีค่าใหม่)
# ทำไมใช้ LabelEncoder ไม่ใช่ OneHot ตรงนี้: เพราะจะใช้ SMOTENC ต่อ (ต้องระบุ index ของ
# categorical columns แบบ integer-encoded) และ XGBoost รับ integer category ได้ตรงๆอยู่แล้ว
# ======================================================================================
encoders = {}
for c in CAT_FEATURES:
    le = LabelEncoder()
    train_df[c] = le.fit_transform(train_df[c])
    encoders[c] = le
    # ค่าใหม่ใน test ที่ไม่เคยเห็นตอน train -> map เป็น class พิเศษ (กันโมเดล error)
    known = set(le.classes_)
    test_df[c] = test_df[c].apply(lambda v: v if v in known else 'UNKNOWN')
    if 'UNKNOWN' not in known:
        le.classes_ = np.append(le.classes_, 'UNKNOWN')
    test_df[c] = le.transform(test_df[c])
 
cat_idx = [ALL_FEATURES.index(c) for c in CAT_FEATURES]  # index สำหรับ SMOTENC
 
# ======================================================================================
# STEP 11) TRAIN ONE XGBOOST MODEL PER TARGET + SHAP
# ทำไมแยกโมเดลต่อ target (ไม่รวมเป็น risk score เดียวตั้งแต่แรก):
#   breach / reject / reopen มีสาเหตุคนละแบบ (เช่น reject สัมพันธ์กับคุณภาพข้อมูล/ขอบเขตงาน
#   ส่วน breach สัมพันธ์กับภาระงาน/SLA target) แยกโมเดลทำให้ SHAP อธิบายแต่ละ risk ได้ตรงประเด็น
#   แล้วค่อยรวมเป็น composite risk_score ตอนทำ dashboard (ทำได้ง่ายกว่าการรวมตั้งแต่ label)
# ======================================================================================
results = {}
for target in TARGETS:
    X_train, y_train = train_df[ALL_FEATURES], train_df[target]
    X_test,  y_test  = test_df[ALL_FEATURES],  test_df[target]
 
    # SMOTENC: สร้างตัวอย่างสังเคราะห์เฉพาะ "เคสส่วนน้อย" (เช่น reject ~5% reopen ~7%)
    # ใช้ NC (Nominal+Continuous) เพราะ features เรามีทั้ง category code และตัวเลขผสมกัน
    sm = SMOTENC(categorical_features=cat_idx, random_state=42, k_neighbors=5)
    X_res, y_res = sm.fit_resample(X_train, y_train)
 
    model = XGBClassifier(
        n_estimators=300, learning_rate=0.05, max_depth=6,
        eval_metric='logloss', random_state=42, n_jobs=-1,
    )
    model.fit(X_res, y_res)
 
    proba = model.predict_proba(X_test)[:, 1]
    pred  = (proba >= 0.5).astype(int)
 
    results[target] = {
        'model': model,
        'auc': roc_auc_score(y_test, proba),
        'ap':  average_precision_score(y_test, proba),
        'proba': proba,
    }
    print(f'\n=== {target} ===  AUC={results[target]["auc"]:.4f}  AP={results[target]["ap"]:.4f}')
    print(classification_report(y_test, pred, target_names=['No', 'Yes']))
 
    explainer = shap.TreeExplainer(model)
    results[target]['shap_values'] = explainer.shap_values(X_test.iloc[:500])
    results[target]['explainer'] = explainer
 
# ======================================================================================
# STEP 12) COMPOSITE RISK SCORE + DASHBOARD EXPORT
# ทำไมใช้ weighted-max แทน average เฉยๆ: ถ้าเคสมีโอกาส reject สูงมาก (เช่น 90%) แต่ breach/reopen ต่ำ
# การเฉลี่ยตรงๆจะ "เจือจาง" สัญญาณเตือนนั้นลง ทั้งที่ในทางปฏิบัติแค่มิติเดียวร้ายแรงก็ต้องเฝ้าระวังแล้ว
# จึงให้ risk_score = ค่าเฉลี่ยถ่วงน้ำหนัก breach หนักสุด (กระทบ SLA โดยตรง) ผสมกับ max ของอีกสองมิติ
# ======================================================================================
test_df['risk_breach'] = results['sla_breached']['proba']
test_df['risk_reject']  = results['was_rejected']['proba']
test_df['risk_reopen']  = results['was_reopened']['proba']
test_df['risk_score'] = (
    0.5 * test_df['risk_breach'] +
    0.5 * test_df[['risk_reject', 'risk_reopen']].max(axis=1)
)
test_df['risk_tier'] = pd.cut(test_df['risk_score'], [-1, 0.4, 0.7, 2], labels=['LOW', 'MEDIUM', 'HIGH'])
 
print('\nRisk tier distribution (test set):')
print(test_df['risk_tier'].value_counts())
 
# ======================================================================================
# STEP 13) SAVE ARTIFACTS FOR HANDOFF (model.pkl style, ตามแนวทางที่ใช้กับ SLA breach model)
# ======================================================================================
joblib.dump({t: results[t]['model'] for t in TARGETS}, 'complaint_risk_models.pkl')
joblib.dump(encoders, 'complaint_risk_label_encoders.pkl')
print('\n✅ Saved: complaint_risk_models.pkl, complaint_risk_label_encoders.pkl')