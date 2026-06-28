// ================================================================
// App.js — Smart Complaint Dashboard (Dark Sidebar Edition)
// ระบบร้องเรียน · National Telecom Public Company Limited
// Design: Dark Sidebar + NT Yellow accent — เชื่อม FastAPI
// ================================================================
import "./App.css";
import ntLogo from "./01_NT-Logo.png";
import { useState, useEffect, useCallback, useMemo } from "react";
import axios from "axios";
import {
  LineChart, Line, BarChart, Bar, AreaChart, Area,
  PieChart, Pie, Cell,
  ResponsiveContainer,
  XAxis, YAxis, CartesianGrid,
  Tooltip, Legend, ReferenceLine,
} from "recharts";

// ── Config ─────────────────────────────────────────────────────
const API = "http://localhost:8000";

// ── NT Corporate Color System ──────────────────────────────────
// (kept as a JS object too — charts/SVGs need real color strings,
//  not CSS variables, since recharts/SVG attrs don't resolve var())
const COLOR = {
  primary:   "#FFD500",
  primary2:  "#E6BC00",
  primaryLt: "#FFFBCC",
  dark:      "#3F4444",
  sidebar:   "#1E2127",
  mid:       "#A7A8AA",
  silver:    "#C8C9C7",
  green:     "#00875A",
  amber:     "#E67E00",
  red:       "#D32F2F",
  purple:    "#6B4EAD",
  blue:      "#3b82f6",
  gray:      "#64748B",
  border:    "#E8EAEC",
  bg:        "#F5F5F5",
  card:      "#FFFFFF",
  text:      "#1A1C1E",
  muted:     "#6B6E72",
};

const PIE_COLORS = ["#FFD500", "#3F4444", "#00875A", "#E67E00", "#6B4EAD", "#A7A8AA"];

const STATUS_COLORS = {
  PENDING:     "#eab308",
  IN_PROGRESS: "#3b82f6",
  PAUSED:      "#6b7280",
  REJECTED:    "#f87171",
  RESOLVED:    "#22c55e",
  CLOSED:      "#8b5cf6",
};

function slaColor(pct) {
  if (pct >= 90) return COLOR.green;
  if (pct >= 75) return COLOR.amber;
  return COLOR.red;
}

// risk score 0-100 → color (higher = worse, opposite of slaColor)
function riskColor(pct) {
  if (pct >= 60) return COLOR.red;
  if (pct >= 30) return COLOR.amber;
  return COLOR.green;
}

// ================================================================
// HOOK: ดึงข้อมูลจาก FastAPI
// ================================================================
function useApi(endpoint, params = {}) {
  const [data,    setData]    = useState(null);
  const [loading, setLoading] = useState(true);
  const [error,   setError]   = useState(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await axios.get(`${API}${endpoint}`, { params });
      setData(res.data);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [endpoint, JSON.stringify(params)]);

  useEffect(() => { fetchData(); }, [fetchData]);
  return { data, loading, error, refetch: fetchData };
}

// ================================================================
// SHARED COMPONENTS
// ================================================================

// Loading Skeleton
function Skeleton({ height = 200 }) {
  return <div className="skeleton" style={{ height }} />;
}

// Card wrapper
function Card({ children, className = "", style = {} }) {
  return (
    <div className={`card ${className}`} style={style}>
      {children}
    </div>
  );
}

// Card Title with yellow left-bar
function CardTitle({ children, sub }) {
  return (
    <div className="card-title-wrap">
      <div className="card-title">
        <span className="card-title-bar" />
        {children}
      </div>
      {sub && <div className="card-title-sub">{sub}</div>}
    </div>
  );
}

// KPI Card
function KPICard({ label, value, iconBg, iconColor, accentColor, delta, sub }) {
  const isUp = delta > 0;
  return (
    <div className="kpi-card" style={{ "--accent": accentColor }}>
      <div className="kpi-card-accent" />
      <div className="kpi-card-head">
        <span className="kpi-card-label">{label}</span>
        <span className="kpi-card-icon" style={{ "--icon-bg": iconBg, "--icon-color": iconColor }}>
          {/* icon slot — ใส่ emoji หรือ SVG ได้ */}
        </span>
      </div>
      <div className="kpi-card-value">{value ?? "—"}</div>
      {sub && <div className="kpi-card-sub">{sub}</div>}
      {delta !== undefined && (
        <div className={`kpi-card-delta ${isUp ? "is-up" : "is-down"}`}>
          {isUp ? "▲" : "▼"} {Math.abs(delta)}% จากเดือนก่อน
        </div>
      )}
    </div>
  );
}

// Badge
function Badge({ label, color = COLOR.gray }) {
  return (
    <span
      className="badge"
      style={{ "--badge-bg": color + "22", "--badge-color": color, "--badge-border": color + "40" }}
    >{label}</span>
  );
}

// SLA Half-circle Gauge (SVG — kept inline since it's a pure data-driven drawing)
function SLAGauge({ pct = 0, size = 180 }) {
  const r    = (size / 2) - 18;
  const circ = Math.PI * r;
  const fill = (pct / 100) * circ;
  const cx   = size / 2;
  const cy   = size / 2 + 10;
  const col  = slaColor(pct);
  const lbl  = pct >= 90 ? "ดีเยี่ยม" : pct >= 75 ? "พอใช้" : "ต้องปรับปรุง";
  return (
    <svg width={size} height={size * 0.62} role="img" aria-label={`SLA ${pct}%`}>
      <path d={`M${cx-r},${cy} A${r},${r} 0 0 1 ${cx+r},${cy}`}
        fill="none" stroke={COLOR.border} strokeWidth={13} strokeLinecap="round" />
      <path d={`M${cx-r},${cy} A${r},${r} 0 0 1 ${cx+r},${cy}`}
        fill="none" stroke={col} strokeWidth={13} strokeLinecap="round"
        strokeDasharray={`${fill} ${circ}`}
        style={{ transition: "stroke-dasharray .8s ease" }} />
      <text x={cx} y={cy - 22} textAnchor="middle"
        style={{ fontSize: 24, fontWeight: 700, fill: col }}>{pct}%</text>
      <text x={cx} y={cy - 6} textAnchor="middle"
        style={{ fontSize: 11, fontWeight: 600, fill: col }}>{lbl}</text>
      <text x={cx - r} y={cy + 14} textAnchor="middle"
        style={{ fontSize: 9, fill: COLOR.muted }}>0</text>
      <text x={cx + r} y={cy + 14} textAnchor="middle"
        style={{ fontSize: 9, fill: COLOR.muted }}>100</text>
    </svg>
  );
}

// SLA Progress Bar row
function SLABar({ name, pct }) {
  const col = slaColor(pct);
  return (
    <div className="sla-bar-row">
      <span className="sla-bar-label">{name || "ไม่ระบุ"}</span>
      <div className="sla-bar-track">
        <div className="sla-bar-fill" style={{ "--pct": `${pct}%`, "--fill": col }} />
      </div>
      <span className="sla-bar-pct" style={{ "--fill": col }}>{pct}%</span>
    </div>
  );
}

// Recharts custom tooltip
const ChartTip = ({ active, payload, label }) => {
  if (!active || !payload?.length) return null;
  return (
    <div className="chart-tooltip">
      <div className="chart-tooltip-label">{label || "—"}</div>
      {payload.map(p => (
        <div key={p.name} className="chart-tooltip-row" style={{ color: p.color }}>
          {p.name}: <b>{p.value?.toLocaleString()}</b>
        </div>
      ))}
    </div>
  );
};

// Small legend row used above several charts
function ChartLegend({ items }) {
  return (
    <div className="chart-legend">
      {items.map(([label, color, dashed]) => (
        <span key={label} className="chart-legend-item">
          <span
            className="chart-legend-dot"
            style={{ "--dot": color, ...(dashed ? { backgroundImage: "none", border: `1px dashed ${color}`, background: "transparent" } : {}) }}
          />
          {label}
        </span>
      ))}
    </div>
  );
}

// Alert row
function AlertItem({ alert }) {
  const dotColor = { high: COLOR.red, medium: COLOR.amber, info: COLOR.blue };
  const col = dotColor[alert?.level] || COLOR.gray;
  return (
    <div className="alert-item">
      <span className="alert-dot" style={{ "--dot": col }} />
      <div className="alert-message">{alert?.message || "ไม่มีข้อความ"}</div>
      {alert?.time && <span className="alert-time">{alert.time}</span>}
    </div>
  );
}

// ================================================================
// SIDEBAR
// ================================================================
const SIDEBAR_NAV = [
  { id: "executive",  label: "Executive",  icon: "📊" },
  { id: "analytics",  label: "Analytics",  icon: "📈" },
  { id: "sla",        label: "SLA",        icon: "🎯" },
  { id: "prediction", label: "Prediction", icon: "🔮" },
];

function Sidebar({ page, setPage, alertCount = 0 }) {
  return (
    <aside className="sidebar">
      {/* Logo */}
      <div className="sidebar-header">
        <div className="sidebar-brand">
          <div className="sidebar-logo">
            <img src={ntLogo} alt="NT" />
          </div>
          <div>
            <div className="sidebar-brand-name">Smart Complaint</div>
            <div className="sidebar-brand-sub">National Telecom</div>
          </div>
        </div>
      </div>

      {/* Nav */}
      <div className="sidebar-nav">
        <div className="sidebar-section-label">Dashboard</div>

        {SIDEBAR_NAV.map(n => {
          const active = page === n.id;
          return (
            <button
              key={n.id}
              onClick={() => setPage(n.id)}
              className={`sidebar-nav-item ${active ? "is-active" : ""}`}
            >
              <span className="sidebar-nav-icon">{n.icon}</span>
              {n.label}
            </button>
          );
        })}

        <div className="sidebar-divider" />

        <div className="sidebar-section-label">ระบบ</div>

        {[
          { label: "แจ้งเตือน", icon: "🔔", badge: alertCount },
          { label: "รายงาน",   icon: "📄" },
          { label: "ตั้งค่า",   icon: "⚙️" },
        ].map(item => (
          <div key={item.label} className="sidebar-system-item">
            <span className="sidebar-nav-icon">{item.icon}</span>
            {item.label}
            {item.badge > 0 && <span className="sidebar-system-badge">{item.badge}</span>}
          </div>
        ))}
      </div>

      {/* User */}
      <div className="sidebar-user">
        <div className="sidebar-user-avatar">ผบ</div>
        <div className="sidebar-user-info">
          <div className="sidebar-user-name">ผู้บริหาร</div>
          <div className="sidebar-user-role">Admin · NT</div>
        </div>
      </div>
    </aside>
  );
}

// ================================================================
// PAGE 1: Executive Dashboard
// ================================================================
function ExecutivePage({ dates }) {
  const { data: kpi,   loading: kl } = useApi("/api/kpi",         dates);
  const { data: trend, loading: tl } = useApi("/api/trend",       dates);
  const { data: cats,  loading: cl } = useApi("/api/by-category", dates);
  const { data: areas, loading: al } = useApi("/api/by-area",     dates);
  const { data: sla,   loading: sl } = useApi("/api/sla",         dates);
  const { data: alerts }             = useApi("/api/alerts");

  const safeTrend  = Array.isArray(trend)  ? trend : [];
  const safeCats   = Array.isArray(cats)   ? cats.map(c => ({ ...c, name: c.name || "ไม่ระบุ" })) : [];
  const safeAreas  = Array.isArray(areas)  ? areas.map(a => ({ ...a, district: a.district || "ไม่ระบุ" })) : [];
  const safeAlerts = Array.isArray(alerts) ? alerts : [];

  const kpiDefs = kpi ? [
    { label: "เรื่องทั้งหมด",  value: kpi.total?.toLocaleString(),    accentColor: COLOR.primary, iconBg: "#FFFBCC", delta: 12.5 },
    { label: "รอดำเนินการ",   value: kpi.open_total,                  accentColor: COLOR.amber,   iconBg: "#FFF3E0", delta: 8.3  },
    { label: "แก้ไขแล้ว",     value: kpi.resolved?.toLocaleString(),  accentColor: COLOR.green,   iconBg: "#E8F5E9", delta: 15.7 },
    { label: "ปิดเรื่อง",      value: kpi.closed?.toLocaleString(),    accentColor: COLOR.purple,  iconBg: "#EDE7F6" },
    { label: "SLA สำเร็จ",    value: kpi.sla_pct + "%",               accentColor: COLOR.green,   iconBg: "#E8F5E9", sub: "เป้าหมาย ≥ 90%" },
    { label: "เฉลี่ย (ชม.)",   value: kpi.avg_hours,                   accentColor: COLOR.primary, iconBg: "#FFFBCC", sub: "เวลาแก้ไขเฉลี่ย" },
  ] : [];

  return (
    <div className="page-stack">

      {/* KPI Row */}
      <div className="grid-kpi-6">
        {kl
          ? Array(6).fill(0).map((_, i) => <Card key={i}><Skeleton height={78} /></Card>)
          : kpiDefs.map((k, i) => <KPICard key={i} {...k} />)
        }
      </div>

      {/* Trend + SLA Gauge */}
      <div className="grid-2-1">
        <Card>
          <CardTitle sub="รับใหม่ / แก้ไขแล้ว / เสี่ยง SLA">แนวโน้มรายวัน</CardTitle>
          <ChartLegend items={[["รับใหม่", COLOR.primary], ["แก้ไขแล้ว", COLOR.green], ["เสี่ยง SLA", COLOR.red]]} />
          {tl ? <Skeleton height={190} /> : (
            <ResponsiveContainer width="100%" height={190}>
              <LineChart data={safeTrend}>
                <CartesianGrid strokeDasharray="3 3" stroke={COLOR.border} />
                <XAxis dataKey="date" tick={{ fontSize: 10 }} interval={6} />
                <YAxis tick={{ fontSize: 10 }} />
                <Tooltip content={<ChartTip />} />
                <Line type="monotone" dataKey="new_cases"  name="รับใหม่"
                  stroke={COLOR.primary} strokeWidth={2.5} dot={false} />
                <Line type="monotone" dataKey="done_cases" name="แก้ไขแล้ว"
                  stroke={COLOR.green} strokeWidth={2} dot={false} strokeDasharray="5 3" />
                <Line type="monotone" dataKey="at_risk"    name="เสี่ยง SLA"
                  stroke={COLOR.red} strokeWidth={1.5} dot={false} />
              </LineChart>
            </ResponsiveContainer>
          )}
        </Card>

        <Card className="card--centered">
          <CardTitle>SLA Performance</CardTitle>
          {sl ? <Skeleton height={130} /> : (
            <>
              <SLAGauge pct={sla?.summary?.sla_pct || 0} size={190} />
              <div className="stat-tile-grid">
                {[
                  { l: "ตามกำหนด", v: sla?.summary?.on_time?.toLocaleString(),  col: COLOR.green },
                  { l: "เกิน SLA",  v: sla?.summary?.breached?.toLocaleString(), col: COLOR.red   },
                ].map((s, i) => (
                  <div key={i} className="stat-tile" style={{ "--tint": s.col + "12", "--fg": s.col }}>
                    <div className="stat-tile-label">{s.l}</div>
                    <div className="stat-tile-value">{s.v ?? "—"}</div>
                  </div>
                ))}
              </div>
            </>
          )}
        </Card>
      </div>

      {/* Pie + Area Bar + Alerts */}
      <div className="grid-1-1-1">
        <Card>
          <CardTitle sub="6 หมวดหมู่หลัก">สัดส่วนตามหมวดหมู่</CardTitle>
          {cl ? <Skeleton height={180} /> : (
            <>
              <ResponsiveContainer width="100%" height={170}>
                <PieChart>
                  <Pie data={safeCats} dataKey="total" nameKey="name"
                    cx="50%" cy="50%" outerRadius={68} innerRadius={38}>
                    {safeCats.map((c, i) => (
                      <Cell key={i} fill={c.color || PIE_COLORS[i % PIE_COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip formatter={(v, n) => [v.toLocaleString() + " เรื่อง", n || "ไม่ระบุ"]} />
                </PieChart>
              </ResponsiveContainer>
              <div className="pie-legend">
                {safeCats.map((c, i) => (
                  <div key={i} className="pie-legend-row">
                    <span className="pie-legend-dot" style={{ "--dot": c.color || PIE_COLORS[i % PIE_COLORS.length] }} />
                    <span className="pie-legend-name">{c.name}</span>
                    <span className="pie-legend-value">{c.total?.toLocaleString()}</span>
                  </div>
                ))}
              </div>
            </>
          )}
        </Card>

        <Card>
          <CardTitle sub="10 เขต">เรื่องแยกตามพื้นที่</CardTitle>
          {al ? <Skeleton height={260} /> : (
            <ResponsiveContainer width="100%" height={260}>
              <BarChart data={safeAreas} layout="vertical">
                <CartesianGrid strokeDasharray="3 3" stroke={COLOR.border} horizontal={false} />
                <XAxis type="number" tick={{ fontSize: 10 }} />
                <YAxis type="category" dataKey="district" tick={{ fontSize: 10 }} width={66} />
                <Tooltip content={<ChartTip />} />
                <Bar dataKey="total" name="เรื่องทั้งหมด" radius={[0, 4, 4, 0]}>
                  {safeAreas.map((_, i) => (
                    <Cell key={i}
                      fill={i === 0 ? COLOR.primary : COLOR.dark}
                      opacity={i === 0 ? 1 : Math.max(0.35, 0.85 - i * 0.06)} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          )}
        </Card>

        <Card>
          <CardTitle>แจ้งเตือนสำคัญ</CardTitle>
          {safeAlerts.length > 0
            ? safeAlerts.map((a, i) => <AlertItem key={i} alert={a} />)
            : <div className="alert-empty">✅ ไม่มีการแจ้งเตือน</div>
          }

          <div className="status-summary">
            <div className="status-summary-title">สรุปสถานะทั้งหมด</div>
            {Object.entries(STATUS_COLORS).map(([k, c]) => (
              <div key={k} className="status-summary-row">
                <span className="status-summary-key">
                  <span className="status-summary-dot" style={{ "--dot": c }} />
                  {k}
                </span>
              </div>
            ))}
          </div>
        </Card>
      </div>
    </div>
  );
}

// ================================================================
// PAGE 2: Analytics Dashboard
// ================================================================
function AnalyticsPage({ dates }) {
  const { data: cats,   loading: cl } = useApi("/api/by-category", dates);
  const { data: areas,  loading: al } = useApi("/api/by-area",     dates);
  const { data: wf,     loading: wl } = useApi("/api/workflow",    dates);
  const { data: recent }              = useApi("/api/recent", { limit: 10 });

  const safeCats   = Array.isArray(cats)   ? cats.map(c => ({ ...c, name: c.name || "ไม่ระบุ" })) : [];
  const safeAreas  = Array.isArray(areas)  ? areas  : [];
  const safeWf     = Array.isArray(wf)     ? wf     : [];
  const safeRecent = Array.isArray(recent) ? recent : [];

  const wfColors = [COLOR.primary, COLOR.dark, COLOR.green, COLOR.amber, COLOR.mid, COLOR.purple];

  return (
    <div className="page-stack">

      {/* SLA Bars */}
      <div className="grid-1-1">
        <Card>
          <CardTitle sub="% SLA สำเร็จ">SLA รายหมวดหมู่</CardTitle>
          {cl ? <Skeleton /> : safeCats.map((c, i) => (
            <SLABar key={i} name={c.name} pct={c.total > 0 ? Math.round(c.done / c.total * 100) : 0} />
          ))}
        </Card>

        <Card>
          <CardTitle sub="% ปิดเรื่องสำเร็จ">Closure Rate รายเขต</CardTitle>
          {al ? <Skeleton /> : safeAreas.map((a, i) => (
            <SLABar key={i} name={a.district} pct={a.closure_rate || 0} />
          ))}
        </Card>
      </div>

      {/* Stacked Bar + Workflow */}
      <div className="grid-2-1">
        <Card>
          <CardTitle sub="จำนวนเรื่องทั้งหมด แยกตามหมวดหมู่">เรื่องร้องเรียนตามหมวดหมู่</CardTitle>
          <ChartLegend items={[["แก้ไขแล้ว", COLOR.green], ["ค้างอยู่", COLOR.amber]]} />
          {cl ? <Skeleton height={210} /> : (
            <ResponsiveContainer width="100%" height={210}>
              <BarChart data={safeCats}>
                <CartesianGrid strokeDasharray="3 3" stroke={COLOR.border} vertical={false} />
                <XAxis dataKey="name" tick={{ fontSize: 10 }}
                  tickFormatter={v => v?.length > 9 ? v.slice(0, 9) + "…" : v || "ไม่ระบุ"} />
                <YAxis tick={{ fontSize: 10 }} />
                <Tooltip content={<ChartTip />} />
                <Bar dataKey="done" name="แก้ไขแล้ว" stackId="a" fill={COLOR.green} />
                <Bar dataKey="open" name="ค้างอยู่"   stackId="a" fill={COLOR.amber} radius={[4,4,0,0]} />
              </BarChart>
            </ResponsiveContainer>
          )}
        </Card>

        <Card>
          <CardTitle sub="จำนวน action ทั้งหมด">Workflow Funnel</CardTitle>
          {wl ? <Skeleton /> : (
            <div className="page-stack" style={{ gap: 10 }}>
              {safeWf.map((w, i) => (
                <div key={i}>
                  <div className="funnel-row-head">
                    <span style={{ color: COLOR.muted }}>{w.label}</span>
                    <span style={{ fontWeight: 600, color: COLOR.text }}>{w.count?.toLocaleString()}</span>
                  </div>
                  <div className="funnel-track">
                    <div
                      className="funnel-fill"
                      style={{ "--pct": `${(w.count / (safeWf[0]?.count || 1)) * 100}%`, "--fill": wfColors[i % wfColors.length] }}
                    />
                  </div>
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>

      {/* Recent complaints table */}
      <Card>
        <CardTitle sub="10 เรื่องล่าสุด">รายการเรื่องร้องเรียน</CardTitle>
        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                {["เลขที่","วันที่","เขต","หมวด","รายละเอียด","สถานะ","Priority"].map(h => (
                  <th key={h}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {safeRecent.map((r, i) => (
                <tr key={i}>
                  <td className="cell-mono">{r.no}</td>
                  <td className="cell-nowrap">{r.created_at ? r.created_at.slice(0, 10) : "—"}</td>
                  <td>{r.district}</td>
                  <td><Badge label={r.category} color={r.cat_color || COLOR.gray} /></td>
                  <td className="cell-truncate">{r.detail}</td>
                  <td><Badge label={r.status} color={STATUS_COLORS[r.status_code] || COLOR.gray} /></td>
                  <td><Badge label={r.priority} color={r.priority_color || COLOR.gray} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  );
}

// ================================================================
// PAGE 3: SLA Dashboard
// ================================================================
function SLAPage({ dates }) {
  const { data: sla,   loading: sl } = useApi("/api/sla",      dates);
  const { data: kpi }                = useApi("/api/kpi",      dates);
  const { data: areas, loading: al } = useApi("/api/by-area",  dates);

  const safeAreas    = Array.isArray(areas) ? areas : [];
  const safePriority = sla && Array.isArray(sla.by_priority) ? sla.by_priority : [];

  return (
    <div className="page-stack">

      {/* Gauge + Priority */}
      <div className="grid-1-2">
        <Card className="card--centered">
          <div style={{ width: "100%" }}>
            <CardTitle>SLA ภาพรวม</CardTitle>
          </div>
          {sl ? <Skeleton height={140} /> : (
            <>
              <SLAGauge pct={sla?.summary?.sla_pct || 0} size={200} />
              <div className="stat-tile-grid">
                {[
                  { l: "ตามกำหนด",       v: sla?.summary?.on_time,   col: COLOR.green   },
                  { l: "เกิน SLA",        v: sla?.summary?.breached,  col: COLOR.red     },
                  { l: "เวลาเฉลี่ย (ชม.)", v: sla?.summary?.avg_hours, col: COLOR.primary },
                  { l: "ทั้งหมด",          v: kpi?.total,              col: COLOR.purple  },
                ].map((s, i) => (
                  <div key={i} className="stat-tile" style={{ "--tint": s.col + "12", "--fg": s.col }}>
                    <div className="stat-tile-label">{s.l}</div>
                    <div className="stat-tile-value">{s.v ?? "—"}</div>
                  </div>
                ))}
              </div>
            </>
          )}
        </Card>

        <Card>
          <CardTitle sub="แยกตาม Priority">SLA ตาม Priority</CardTitle>
          {sl ? <Skeleton /> : (
            <div>
              {safePriority.map((p, i) => (
                <div key={i} className="priority-row">
                  <div className="priority-row-head">
                    <span className="priority-row-name">
                      <span className="priority-dot" style={{ "--dot": p.color }} />
                      <span style={{ fontWeight: 500, color: COLOR.text }}>{p.name}</span>
                      <span style={{ fontSize: 10.5, color: COLOR.muted }}>
                        (target: {p.target_min < 60 ? p.target_min + " นาที" : Math.round(p.target_min / 60) + " ชม."})
                      </span>
                    </span>
                    <span className="priority-row-pct" style={{ color: slaColor(p.sla_pct) }}>{p.sla_pct}%</span>
                  </div>
                  <div className="priority-row-body">
                    <div className="priority-track">
                      <div className="priority-fill" style={{ "--pct": `${p.sla_pct}%`, "--fill": slaColor(p.sla_pct) }} />
                    </div>
                    <span className="priority-count">{p.on_time}/{p.total}</span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>

      {/* Area cards */}
      <Card>
        <CardTitle sub="% Closure Rate แยกตาม 10 เขต">SLA รายพื้นที่</CardTitle>
        {al ? <Skeleton height={100} /> : (
          <div className="grid-area-cards">
            {safeAreas.map((a, i) => {
              const col = slaColor(a.closure_rate || 0);
              return (
                <div key={i} className="area-card" style={{ "--tint": col + "10", "--border-c": col + "40" }}>
                  <div className="area-card-name">{a.district}</div>
                  {[
                    ["ทั้งหมด", a.total?.toLocaleString(), COLOR.text],
                    ["ค้างอยู่", a.open, COLOR.amber],
                  ].map(([l, v, c]) => (
                    <div key={l} className="area-card-row">
                      <span>{l}</span>
                      <span className="area-card-row-value" style={{ color: c }}>{v}</span>
                    </div>
                  ))}
                  <div className="area-card-footer" style={{ "--border-c": col + "30" }}>
                    <span style={{ color: COLOR.muted }}>Closure Rate</span>
                    <span style={{ fontWeight: 700, color: col }}>{a.closure_rate}%</span>
                  </div>
                  <div className="area-card-track">
                    <div className="area-card-fill" style={{ "--pct": `${a.closure_rate}%`, "--fill": col }} />
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </Card>
    </div>
  );
}

// ================================================================
// PAGE 4: Prediction Dashboard (NEW)
// คาดการณ์ปริมาณเรื่องร้องเรียนล่วงหน้า + insight สำหรับวางแผนรับมือ
// ใช้ผลลัพธ์จากโมเดล Prophet (forecast เชิงเวลา) และ XGBoost
// (คาดการณ์ความเสี่ยงเกิน SLA) ฝั่ง backend
//
// Endpoint ที่คาดหวัง (ให้ทีม backend อ้างอิงตอน implement):
//   GET /api/forecast?horizon=7|30|90
//     → { history:[{date,total}], forecast:[{date,predicted,lower,upper}],
//         next_total, trend_pct, model:{name,mape,trained_at} }
//   GET /api/forecast/category-risk?horizon=7|30|90
//     → [{ name, predicted, breach_risk, color }]
//   GET /api/forecast/area-risk?horizon=7|30|90
//     → [{ district, predicted, risk_level }]   // risk_level: low|medium|high
//   GET /api/forecast/insights?horizon=7|30|90
//     → [{ type: "trend"|"category"|"area"|"staffing", severity: "info"|"warning"|"critical", title, message }]
// ================================================================
const HORIZONS = [
  { id: 7,  label: "7 วัน" },
  { id: 30, label: "30 วัน" },
  { id: 90, label: "90 วัน" },
];

const INSIGHT_ICON = { trend: "📈", category: "🗂️", area: "📍", staffing: "👥" };
const INSIGHT_TINT = {
  info:     { bg: COLOR.blue + "12",  icon: COLOR.blue + "22"  },
  warning:  { bg: COLOR.amber + "12", icon: COLOR.amber + "22" },
  critical: { bg: COLOR.red + "12",   icon: COLOR.red + "22"   },
};

function ForecastChart({ history, forecast, loading }) {
  // ผสานข้อมูลจริง (history) กับค่าพยากรณ์ (forecast) ให้อยู่บนแกนเวลาเดียวกัน
  // เพื่อวาดเป็นกราฟต่อเนื่อง พร้อมแถบช่วงความเชื่อมั่น (confidence interval)
  const merged = useMemo(() => {
    const h = (history || []).map(d => ({ date: d.date, actual: d.total }));
    const f = (forecast || []).map(d => ({
      date: d.date, predicted: d.predicted, band: [d.lower, d.upper],
    }));
    return [...h, ...f];
  }, [history, forecast]);

  const splitIndex = (history || []).length;

  if (loading) return <Skeleton height={230} />;

  return (
    <div className="forecast-chart-zone">
      <ResponsiveContainer width="100%" height={230}>
        <AreaChart data={merged}>
          <CartesianGrid strokeDasharray="3 3" stroke={COLOR.border} />
          <XAxis dataKey="date" tick={{ fontSize: 10 }} interval={Math.max(1, Math.floor(merged.length / 10))} />
          <YAxis tick={{ fontSize: 10 }} />
          <Tooltip content={<ChartTip />} />
          {/* แถบความเชื่อมั่น (confidence band) ของช่วงพยากรณ์ */}
          <Area type="monotone" dataKey="band" name="ช่วงความเชื่อมั่น"
            stroke="none" fill={COLOR.primary} fillOpacity={0.18} />
          {/* เส้นข้อมูลจริง */}
          <Line type="monotone" dataKey="actual" name="ข้อมูลจริง"
            stroke={COLOR.dark} strokeWidth={2.2} dot={false} />
          {/* เส้นพยากรณ์ */}
          <Line type="monotone" dataKey="predicted" name="พยากรณ์"
            stroke={COLOR.primary2} strokeWidth={2.2} strokeDasharray="6 4" dot={false} />
          {splitIndex > 0 && (
            <ReferenceLine x={merged[splitIndex - 1]?.date} stroke={COLOR.muted} strokeDasharray="2 2" />
          )}
        </AreaChart>
      </ResponsiveContainer>
      <div className="forecast-divider-label">◀ ข้อมูลจริง &nbsp;|&nbsp; พยากรณ์ ▶</div>
    </div>
  );
}

function InsightCard({ insight }) {
  const tint = INSIGHT_TINT[insight.severity] || INSIGHT_TINT.info;
  return (
    <div className="insight-card" style={{ "--tint": tint.bg, "--border-c": tint.bg }}>
      <span className="insight-icon" style={{ "--icon-bg": tint.icon }}>
        {INSIGHT_ICON[insight.type] || "💡"}
      </span>
      <div className="insight-body">
        <div className="insight-title">{insight.title}</div>
        <div className="insight-text">{insight.message}</div>
      </div>
    </div>
  );
}

function PredictionPage() {
  const [horizon, setHorizon] = useState(30);

  const { data: forecast, loading: fl } = useApi("/api/forecast",              { horizon });
  const { data: catRisk,  loading: crl } = useApi("/api/forecast/category-risk", { horizon });
  const { data: areaRisk, loading: arl } = useApi("/api/forecast/area-risk",      { horizon });
  const { data: insights, loading: il }  = useApi("/api/forecast/insights",       { horizon });

  const safeCatRisk  = Array.isArray(catRisk)  ? catRisk  : [];
  const safeAreaRisk = Array.isArray(areaRisk) ? areaRisk : [];
  const safeInsights = Array.isArray(insights) ? insights : [];

  const riskLevelLabel = { low: "ต่ำ", medium: "ปานกลาง", high: "สูง" };
  const riskLevelColor = { low: COLOR.green, medium: COLOR.amber, high: COLOR.red };

  const kpiDefs = forecast ? [
    {
      label: `คาดการณ์ ${horizon} วันข้างหน้า`, value: forecast.next_total?.toLocaleString(),
      accentColor: COLOR.primary, iconBg: "#FFFBCC", sub: "จำนวนเรื่องร้องเรียนรวม",
    },
    {
      label: "แนวโน้มเทียบช่วงก่อน", value: (forecast.trend_pct > 0 ? "+" : "") + forecast.trend_pct + "%",
      accentColor: forecast.trend_pct >= 0 ? COLOR.amber : COLOR.green,
      iconBg: forecast.trend_pct >= 0 ? "#FFF3E0" : "#E8F5E9",
      sub: forecast.trend_pct >= 0 ? "ปริมาณเพิ่มขึ้น" : "ปริมาณลดลง",
    },
    {
      label: "หมวดที่เสี่ยงสูงสุด", value: safeCatRisk[0]?.name || "—",
      accentColor: COLOR.red, iconBg: "#FDECEA",
      sub: safeCatRisk[0] ? `เสี่ยงเกิน SLA ${safeCatRisk[0].breach_risk}%` : undefined,
    },
    {
      label: "ความแม่นยำโมเดล", value: forecast.model?.mape ? `${forecast.model.mape}% MAPE` : "—",
      accentColor: COLOR.purple, iconBg: "#EDE7F6",
      sub: forecast.model?.name || "Prophet",
    },
  ] : [];

  return (
    <div className="page-stack">

      {/* Horizon selector */}
      <div className="filter-bar" style={{ borderRadius: 10, border: `0.5px solid ${COLOR.border}` }}>
        <span className="filter-label">🔮 ช่วงเวลาพยากรณ์ล่วงหน้า:</span>
        <div className="horizon-toggle">
          {HORIZONS.map(h => (
            <button
              key={h.id}
              onClick={() => setHorizon(h.id)}
              className={`horizon-toggle-btn ${horizon === h.id ? "is-active" : ""}`}
            >{h.label}</button>
          ))}
        </div>
        <span style={{ marginLeft: "auto" }} className="confidence-note">
          <span className="confidence-swatch" />
          แถบสีเหลืองคือช่วงความเชื่อมั่นของการพยากรณ์
        </span>
      </div>

      {/* KPI Row */}
      <div className="grid-1-1-1-1">
        {fl
          ? Array(4).fill(0).map((_, i) => <Card key={i}><Skeleton height={78} /></Card>)
          : kpiDefs.map((k, i) => <KPICard key={i} {...k} />)
        }
      </div>

      {/* Main forecast chart */}
      <Card>
        <CardTitle sub={`พยากรณ์ปริมาณเรื่องร้องเรียนรวม ด้วยโมเดล ${forecast?.model?.name || "Prophet"}`}>
          แนวโน้มและการพยากรณ์
        </CardTitle>
        <ForecastChart history={forecast?.history} forecast={forecast?.forecast} loading={fl} />
        <div className="model-info-bar">
          <span className="model-info-chip">โมเดล: <b>&nbsp;{forecast?.model?.name || "Prophet"}</b></span>
          <span className="model-info-chip">ความแม่นยำ (MAPE): <b>&nbsp;{forecast?.model?.mape ?? "—"}%</b></span>
          <span className="model-info-chip">เทรนล่าสุด: <b>&nbsp;{forecast?.model?.trained_at || "—"}</b></span>
        </div>
      </Card>

      {/* Category risk + Area risk */}
      <div className="grid-1-1">
        <Card>
          <CardTitle sub="ความเสี่ยงเกิน SLA ตามหมวดหมู่ (จากโมเดล XGBoost)">พยากรณ์ความเสี่ยงรายหมวดหมู่</CardTitle>
          {crl ? <Skeleton /> : (
            <div className="table-wrap risk-table">
              <table className="data-table">
                <thead>
                  <tr>{["หมวดหมู่", "คาดการณ์ (เรื่อง)", "ความเสี่ยงเกิน SLA"].map(h => <th key={h}>{h}</th>)}</tr>
                </thead>
                <tbody>
                  {safeCatRisk.map((c, i) => (
                    <tr key={i}>
                      <td>
                        <Badge label={c.name} color={c.color || PIE_COLORS[i % PIE_COLORS.length]} />
                      </td>
                      <td>{c.predicted?.toLocaleString()}</td>
                      <td>
                        <span className="risk-meter-track">
                          <span className="risk-meter-fill" style={{ "--pct": `${c.breach_risk}%`, "--fill": riskColor(c.breach_risk) }} />
                        </span>
                        <span style={{ fontWeight: 600, color: riskColor(c.breach_risk) }}>{c.breach_risk}%</span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>

        <Card>
          <CardTitle sub="ปริมาณคาดการณ์รายเขต เรียงจากเสี่ยงมากไปน้อย">พยากรณ์ความเสี่ยงรายพื้นที่</CardTitle>
          {arl ? <Skeleton /> : (
            <div className="grid-area-cards">
              {safeAreaRisk.map((a, i) => {
                const col = riskLevelColor[a.risk_level] || COLOR.gray;
                return (
                  <div key={i} className="area-card" style={{ "--tint": col + "10", "--border-c": col + "40" }}>
                    <div className="area-card-name">{a.district}</div>
                    <div className="area-card-row">
                      <span>คาดการณ์</span>
                      <span className="area-card-row-value" style={{ color: COLOR.text }}>
                        {a.predicted?.toLocaleString()} เรื่อง
                      </span>
                    </div>
                    <div className="area-card-footer" style={{ "--border-c": col + "30" }}>
                      <span style={{ color: COLOR.muted }}>ระดับความเสี่ยง</span>
                      <span style={{ fontWeight: 700, color: col }}>{riskLevelLabel[a.risk_level] || "—"}</span>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </Card>
      </div>

      {/* Insights / recommendations */}
      <Card>
        <CardTitle sub="ข้อเสนอแนะสำหรับวางแผนกำลังคนและทรัพยากรล่วงหน้า">
          Insight สำหรับการวางแผนรับมือ
        </CardTitle>
        {il ? <Skeleton height={140} /> : (
          <div className="insight-list">
            {safeInsights.length > 0
              ? safeInsights.map((ins, i) => <InsightCard key={i} insight={ins} />)
              : <div className="alert-empty">✅ ไม่มีข้อเสนอแนะเพิ่มเติมในช่วงเวลานี้</div>
            }
          </div>
        )}
      </Card>
    </div>
  );
}

// ================================================================
// MAIN APP
// ================================================================
const PAGE_TITLE = {
  executive:  "Executive Dashboard",
  analytics:  "Analytics Dashboard",
  sla:        "SLA Dashboard",
  prediction: "Prediction Dashboard",
};

const DATE_PRESETS = [
  { l: "เดือนนี้", s: "2025-06-01", e: "2025-06-30" },
  { l: "ปีนี้",    s: "2025-01-01", e: "2025-12-31" },
  { l: "ทั้งหมด",  s: "2025-01-01", e: "2025-12-31" },
];

export default function App() {
  const [page,  setPage]  = useState("executive");
  const [dates, setDates] = useState({ start_date: "2025-01-01", end_date: "2025-12-31" });

  const { data: alerts } = useApi("/api/alerts");
  const alertCount = Array.isArray(alerts) ? alerts.filter(a => a.level === "high").length : 0;

  return (
    <div className="app-shell">
      <Sidebar page={page} setPage={setPage} alertCount={alertCount} />

      <div className="main-column">

        {/* Top bar */}
        <header className="topbar">
          <h1 className="topbar-title">{PAGE_TITLE[page]}</h1>
          <span className="live-dot" />
          <span className="live-label">Live</span>
          <span className="date-range-badge">📅 {dates.start_date} – {dates.end_date}</span>
        </header>

        <div className="accent-stripe" />

        {/* Filter bar — ซ่อนสำหรับหน้า Prediction เพราะใช้ตัวเลือกช่วงพยากรณ์ของตัวเองแทน */}
        {page !== "prediction" && (
          <div className="filter-bar">
            <span className="filter-label">📅 ช่วงเวลา:</span>

            {DATE_PRESETS.map(d => {
              const active = dates.start_date === d.s && dates.end_date === d.e;
              return (
                <button
                  key={d.l}
                  onClick={() => setDates({ start_date: d.s, end_date: d.e })}
                  className={`filter-preset-btn ${active ? "is-active" : ""}`}
                >{d.l}</button>
              );
            })}

            <span className="filter-label filter-label--gap">วันที่เริ่ม:</span>
            <input
              type="date" value={dates.start_date} className="filter-date-input"
              onChange={e => setDates(d => ({ ...d, start_date: e.target.value }))}
            />
            <span className="filter-label">ถึง:</span>
            <input
              type="date" value={dates.end_date} className="filter-date-input"
              onChange={e => setDates(d => ({ ...d, end_date: e.target.value }))}
            />
          </div>
        )}

        {/* Page content */}
        <main className="main-content">
          {page === "executive"  && <ExecutivePage  dates={dates} />}
          {page === "analytics"  && <AnalyticsPage   dates={dates} />}
          {page === "sla"        && <SLAPage         dates={dates} />}
          {page === "prediction" && <PredictionPage />}
        </main>

        {/* Footer */}
        <footer className="app-footer">
          <span className="footer-mark">nt</span>
          Smart Complaint Management System · National Telecom Public Company Limited
        </footer>
      </div>
    </div>
  );
}
