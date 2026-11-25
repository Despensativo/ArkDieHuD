import Foundation

/// Self-contained offline HTML/CSS/JS live telemetry dashboard served over LAN/USB (:8787)
/// with automatic language detection (`en`, `pt-BR`, `es`) and manual toggle.
enum TelemetryWebDashboardHTML {
    static let indexHTML: String = """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ArkDieHuD — Live Telemetry</title>
<style>
  :root {
    --bg: #0b0d12;
    --card: #141821;
    --border: rgba(255,255,255,0.09);
    --text: #f3f5f8;
    --muted: #939bb0;
    --accent: #38bdf8;
    --green: #34d399;
    --yellow: #fbbf24;
    --orange: #fb923c;
    --red: #f87171;
    --purple: #a78bfa;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    padding: 20px;
    background: var(--bg);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
    font-variant-numeric: tabular-nums;
  }
  header {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    margin-bottom: 18px;
  }
  .brand {
    display: flex;
    align-items: center;
    gap: 10px;
    flex-wrap: wrap;
  }
  .dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: var(--green);
    box-shadow: 0 0 10px var(--green);
  }
  .dot.offline { background: var(--red); box-shadow: 0 0 10px var(--red); }
  h1 { margin: 0; font-size: 22px; letter-spacing: -0.02em; display: flex; align-items: center; gap: 6px; }
  .hud-tag {
    font-size: 13px;
    font-weight: 800;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    letter-spacing: 0.05em;
    padding: 2px 8px;
    border-radius: 999px;
    background: linear-gradient(90deg, rgba(34,211,238,0.18), rgba(52,211,153,0.18));
    border: 1px solid rgba(56,189,248,0.42);
    color: #34d399;
  }
  .pill {
    font-size: 12px;
    font-weight: 600;
    padding: 5px 10px;
    border-radius: 999px;
    background: rgba(56,189,248,0.14);
    color: var(--accent);
    border: 1px solid rgba(56,189,248,0.25);
  }
  .controls {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px;
  }
  .lang-group {
    display: inline-flex;
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow: hidden;
    background: var(--card);
  }
  .lang-group button {
    border: none;
    border-radius: 0;
    padding: 7px 9px;
    font-size: 12px;
    color: var(--muted);
  }
  .lang-group button.active {
    background: rgba(52,211,153,0.18);
    color: var(--green);
  }
  button, a.btn {
    background: var(--card);
    color: var(--text);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 7px 12px;
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    text-decoration: none;
  }
  button.active {
    background: rgba(56,189,248,0.18);
    border-color: var(--accent);
    color: var(--accent);
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(175px, 1fr));
    gap: 10px;
    margin-bottom: 18px;
  }
  .card {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 12px 14px;
  }
  .label { font-size: 12px; color: var(--muted); margin-bottom: 4px; }
  .val { font-size: 22px; font-weight: 700; line-height: 1.2; }
  .sub { font-size: 12px; color: var(--muted); margin-top: 4px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .charts {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(340px, 1fr));
    gap: 12px;
    margin-bottom: 18px;
  }
  .chart-card h2 {
    margin: 0 0 8px 0;
    font-size: 14px;
    color: var(--text);
    display: flex;
    justify-content: space-between;
    gap: 8px;
    flex-wrap: wrap;
  }
  .legend { font-size: 11px; color: var(--muted); font-weight: 500; }
  canvas { width: 100%; height: 210px; display: block; }
  table { width: 100%; border-collapse: collapse; font-size: 12px; }
  th, td { text-align: left; padding: 7px 8px; border-bottom: 1px solid var(--border); }
  th { color: var(--muted); font-weight: 600; }
</style>
</head>
<body>
<header>
  <div class="brand">
    <span id="liveDot" class="dot"></span>
    <svg width="28" height="28" viewBox="0 0 28 28" fill="none" aria-hidden="true">
      <rect x="2" y="2" width="24" height="24" rx="6" fill="#11161f" stroke="#525b6e" stroke-width="1.4"/>
      <rect x="6" y="6" width="16" height="16" rx="3" fill="#0b0f17" stroke="#2f3747" stroke-width="1"/>
      <path d="M5 14H10L12 10.5L14 18.5L16.2 12L18 14H23" stroke="url(#arkPulse)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <defs>
        <linearGradient id="arkPulse" x1="5" y1="14" x2="23" y2="14" gradientUnits="userSpaceOnUse">
          <stop stop-color="#22d3ee"/><stop offset="1" stop-color="#34d399"/>
        </linearGradient>
      </defs>
    </svg>
    <h1>ArkDie <span class="hud-tag">HuD</span></h1>
    <span id="routeBadge" class="pill">Connecting...</span>
    <span id="slaBadge" class="pill">--</span>
  </div>
  <div class="controls">
    <div class="lang-group" role="group" aria-label="Language">
      <button data-lang="en">EN</button>
      <button data-lang="pt-BR">PT</button>
      <button data-lang="es">ES</button>
    </div>
    <button data-win="900">15m</button>
    <button data-win="3600" class="active">1h</button>
    <button data-win="21600">6h</button>
    <button data-win="86400">24h</button>
    <a id="csvLink" class="btn" href="/api/csv?window=3600">Download CSV</a>
  </div>
</header>

<section class="grid" id="kpiGrid"></section>

<section class="charts">
  <div class="card chart-card">
    <h2>
      <span id="hwChartTitle">Silicon &amp; Power (CPU / GPU / Watts)</span>
      <span id="hwChartLegend" class="legend">Blue: CPU °C • Orange: GPU °C • Purple: W</span>
    </h2>
    <canvas id="hwChart"></canvas>
  </div>
  <div class="card chart-card">
    <h2>
      <span id="netChartTitle">Network &amp; Drops (Target / UDP / Router)</span>
      <span id="netChartLegend" class="legend">Blue: Target • Orange: UDP • Green: Router • Red: Drop</span>
    </h2>
    <canvas id="netChart"></canvas>
  </div>
</section>

<section class="card">
  <h2 id="incidentsTitle" style="margin:0 0 10px 0;font-size:14px;">Recent Network Incidents</h2>
  <table>
    <thead>
      <tr>
        <th id="thTime">Time</th>
        <th id="thType">Type</th>
        <th id="thDelta">Δ</th>
        <th id="thRoute">Route</th>
        <th id="thDetails">Details</th>
      </tr>
    </thead>
    <tbody id="incidentsBody">
      <tr><td colspan="5" style="color:var(--muted);">Waiting for events...</td></tr>
    </tbody>
  </table>
</section>

<script>
const I18N = {
  "en": {
    pageTitle: "ArkDieHuD — Live Telemetry",
    connecting: "Connecting...",
    direct: "Direct",
    downloadCSV: "Download CSV",
    hwTitle: "Silicon & Power (CPU / GPU / Watts)",
    hwLegend: "Blue: CPU °C • Orange: GPU °C • Purple: W",
    netTitle: "Network & Drops (Target / UDP / Router)",
    netLegend: "Blue: Target • Orange: UDP • Green: Router • Red: Drop",
    incidentsTitle: "Recent Network Incidents",
    thTime: "Time",
    thType: "Type",
    thDelta: "Δ",
    thRoute: "Route",
    thDetails: "Details",
    waitingEvents: "Waiting for events...",
    waitingSamples: "Waiting for enough samples...",
    noIncidents: "No incidents recorded yet.",
    cpuSilicon: "CPU Silicon",
    gpuSilicon: "GPU Silicon",
    cpuLoad: "CPU Load",
    cores: "cores",
    power: "Power",
    statePrefix: "State: ",
    ram: "Memory RAM",
    used: "used",
    battery: "Battery",
    charging: "Charging",
    onBattery: "On Battery",
    target: "Target",
    packetLoss: "Packet Loss",
    udpProbe: "UDP Probe",
    localRouter: "Local Router",
    gateway: "Gateway",
    downloadUp: "Download / Up",
    thermalStates: {
      "Nominal": "Nominal",
      "Fair": "Fair",
      "Serious": "Serious",
      "Critical": "Critical"
    },
    incidentKinds: {
      "Queda Externa / ISP": "External Drop / ISP",
      "Queda Local / Wi-Fi": "Local Drop / Wi-Fi",
      "Queda de Protocolo": "Protocol Drop",
      "Pacote Perdido": "Lost Packet",
      "Rajada de Perda": "Loss Burst",
      "Pico de Latência": "Latency Spike",
      "Troca de Rota / VPN": "Route / VPN Switch"
    }
  },
  "pt-BR": {
    pageTitle: "ArkDieHuD — Telemetria Ao Vivo",
    connecting: "Conectando...",
    direct: "Direto",
    downloadCSV: "Baixar CSV",
    hwTitle: "Silício e Energia (CPU / GPU / Watts)",
    hwLegend: "Azul: CPU °C • Laranja: GPU °C • Roxo: W",
    netTitle: "Rede e Drops (Alvo / UDP / Roteador)",
    netLegend: "Azul: Alvo • Laranja: UDP • Verde: Roteador • Vermelho: Drop",
    incidentsTitle: "Incidentes Recentes de Rede",
    thTime: "Hora",
    thType: "Tipo",
    thDelta: "Δ",
    thRoute: "Rota",
    thDetails: "Detalhes",
    waitingEvents: "Aguardando eventos...",
    waitingSamples: "Aguardando amostras suficientes...",
    noIncidents: "Nenhum incidente registrado ainda.",
    cpuSilicon: "Silício CPU",
    gpuSilicon: "Silício GPU",
    cpuLoad: "Carga CPU",
    cores: "cores",
    power: "Potência",
    statePrefix: "Estado: ",
    ram: "Memória RAM",
    used: "usado",
    battery: "Bateria",
    charging: "Carregando",
    onBattery: "Em uso",
    target: "Alvo",
    packetLoss: "Perda (Loss)",
    udpProbe: "Sonda UDP",
    localRouter: "Roteador Local",
    gateway: "Gateway",
    downloadUp: "Download / Up",
    thermalStates: {
      "Nominal": "Normal",
      "Fair": "Morno",
      "Serious": "Quente",
      "Critical": "Crítico"
    },
    incidentKinds: {}
  },
  "es": {
    pageTitle: "ArkDieHuD — Telemetría en Vivo",
    connecting: "Conectando...",
    direct: "Directo",
    downloadCSV: "Descargar CSV",
    hwTitle: "Silicio y Energía (CPU / GPU / Watts)",
    hwLegend: "Azul: CPU °C • Naranja: GPU °C • Púrpura: W",
    netTitle: "Red y Drops (Destino / UDP / Router)",
    netLegend: "Azul: Destino • Naranja: UDP • Verde: Router • Rojo: Drop",
    incidentsTitle: "Incidentes Recientes de Red",
    thTime: "Hora",
    thType: "Tipo",
    thDelta: "Δ",
    thRoute: "Ruta",
    thDetails: "Detalles",
    waitingEvents: "Esperando eventos...",
    waitingSamples: "Esperando suficientes muestras...",
    noIncidents: "Ningún incidente registrado aún.",
    cpuSilicon: "Silicio CPU",
    gpuSilicon: "Silicio GPU",
    cpuLoad: "Carga CPU",
    cores: "núcleos",
    power: "Potencia",
    statePrefix: "Estado: ",
    ram: "Memoria RAM",
    used: "usado",
    battery: "Batería",
    charging: "Cargando",
    onBattery: "En uso",
    target: "Destino",
    packetLoss: "Pérdida (Loss)",
    udpProbe: "Sonda UDP",
    localRouter: "Router Local",
    gateway: "Gateway",
    downloadUp: "Descarga / Subida",
    thermalStates: {
      "Nominal": "Nominal",
      "Fair": "Tibio",
      "Serious": "Alto",
      "Critical": "Crítico"
    },
    incidentKinds: {
      "Queda Externa / ISP": "Caída Externa / ISP",
      "Queda Local / Wi-Fi": "Caída Local / Wi-Fi",
      "Queda de Protocolo": "Caída de Protocolo",
      "Pacote Perdido": "Paquete Perdido",
      "Rajada de Perda": "Ráfaga de Pérdida",
      "Pico de Latência": "Pico de Latencia",
      "Troca de Rota / VPN": "Cambio de Ruta / VPN"
    }
  }
};

function detectLang() {
  const saved = localStorage.getItem("arkdiehud_lang");
  if (saved && I18N[saved]) return saved;
  const nav = (navigator.language || "en").toLowerCase();
  if (nav.startsWith("pt")) return "pt-BR";
  if (nav.startsWith("es")) return "es";
  return "en";
}

let currentLang = detectLang();
let selectedWindow = 3600;
let lastSnapshot = null;
let lastBuckets = null;
let lastIncidents = null;

function t() { return I18N[currentLang] || I18N["en"]; }

function applyStaticTranslations() {
  const s = t();
  document.documentElement.lang = currentLang;
  document.title = s.pageTitle;
  document.getElementById("csvLink").textContent = s.downloadCSV;
  document.getElementById("hwChartTitle").textContent = s.hwTitle;
  document.getElementById("hwChartLegend").textContent = s.hwLegend;
  document.getElementById("netChartTitle").textContent = s.netTitle;
  document.getElementById("netChartLegend").textContent = s.netLegend;
  document.getElementById("incidentsTitle").textContent = s.incidentsTitle;
  document.getElementById("thTime").textContent = s.thTime;
  document.getElementById("thType").textContent = s.thType;
  document.getElementById("thDelta").textContent = s.thDelta;
  document.getElementById("thRoute").textContent = s.thRoute;
  document.getElementById("thDetails").textContent = s.thDetails;
  if (!lastSnapshot) {
    document.getElementById("routeBadge").textContent = s.connecting;
  }
  document.querySelectorAll("button[data-lang]").forEach(b => {
    b.classList.toggle("active", b.dataset.lang === currentLang);
  });
}

const fmt = (v, d=1) => (v == null || !isFinite(v)) ? "--" : Number(v).toFixed(d);
const fmt0 = (v) => (v == null || !isFinite(v)) ? "--" : Math.round(v);

function tempColor(tVal) {
  if (tVal == null) return "var(--muted)";
  if (tVal >= 55) return "var(--red)";
  if (tVal >= 45) return "var(--orange)";
  if (tVal >= 38) return "var(--yellow)";
  return "var(--green)";
}

function pingColor(p, lost) {
  if (lost) return "var(--red)";
  if (p == null) return "var(--muted)";
  if (p <= 30) return "var(--green)";
  if (p <= 65) return "var(--accent)";
  if (p <= 110) return "var(--yellow)";
  return "var(--red)";
}

function renderKPIs(d) {
  const s = t();
  const cpuT = d.cpuTemperature ?? d.peakTemperature;
  const net = d.network || {};
  const memPct = d.memoryTotalBytes > 0 ? (d.memoryUsedBytes / d.memoryTotalBytes) * 100 : 0;
  const memGB = d.memoryUsedBytes / 1073741824;
  const lossPct = net.totalLossPercent || 0;
  const thm = (s.thermalStates && s.thermalStates[d.thermalState]) || d.thermalState || "--";

  const cards = [
    ["CPU Die", cpuT != null ? fmt(cpuT, 1) + "°C" : "--", d.cpuSensorName || s.cpuSilicon, tempColor(cpuT)],
    ["GPU Die", d.gpuTemperature != null ? fmt(d.gpuTemperature, 1) + "°C" : "--", d.gpuSensorName || s.gpuSilicon, tempColor(d.gpuTemperature)],
    [s.cpuLoad, fmt0(d.cpuTotalPercent) + "%", d.topology ? d.topology.totalCores + " " + s.cores : "CPU", d.cpuTotalPercent >= 85 ? "var(--red)" : "var(--accent)"],
    [s.power, d.estimatedWatts != null ? fmt(d.estimatedWatts, 1) + " W" : "--", s.statePrefix + thm, "var(--orange)"],
    [s.ram, fmt(memGB, 1) + " GB", fmt0(memPct) + "% " + s.used, memPct >= 85 ? "var(--red)" : "var(--accent)"],
    [s.battery, d.batteryPercent != null ? d.batteryPercent + "%" : "--", d.isCharging ? s.charging : s.onBattery, (d.batteryPercent ?? 100) <= 20 ? "var(--red)" : "var(--green)"],
    ["Ping / RTT", net.isLastProbeLost ? "DROP" : (net.pingMs != null ? fmt0(net.pingMs) + " ms" : "--"), net.target ? net.target.name : s.target, pingColor(net.pingMs, net.isLastProbeLost)],
    [s.packetLoss, net.isLastProbeLost ? "DROP!" : fmt(lossPct, 1) + "%", (net.totalLostCount || 0) + "p • 120s: " + fmt(net.lossPercent120s, 1) + "%", lossPct > 0 || net.isLastProbeLost ? "var(--red)" : "var(--green)"],
    [s.udpProbe, net.isUDPLastLost ? "DROP" : (net.udpPingMs != null ? fmt0(net.udpPingMs) + " ms" : "--"), (net.udpProbeHost || "1.1.1.1") + ":53", pingColor(net.udpPingMs, net.isUDPLastLost)],
    [s.localRouter, net.isGatewayLastProbeLost ? "DROP" : (net.gatewayPingMs != null ? fmt(net.gatewayPingMs, 1) + " ms" : "--"), net.gatewayHost || s.gateway, pingColor(net.gatewayPingMs, net.isGatewayLastProbeLost)],
    ["Jitter RFC", "±" + fmt(net.jitterMs, 1) + " ms", "P50 " + fmt0(net.p50Ms) + " • P99 " + fmt0(net.p99Ms), (net.jitterMs || 0) > 15 ? "var(--orange)" : "var(--green)"],
    [s.downloadUp, fmt((net.downloadBytesPerSec || 0) / 1024, 0) + " KB/s", "Up: " + fmt((net.uploadBytesPerSec || 0) / 1024, 0) + " KB/s", "var(--text)"]
  ];

  document.getElementById("kpiGrid").innerHTML = cards.map(([l, v, sub, c]) =>
    `<div class="card"><div class="label">${l}</div><div class="val" style="color:${c}">${v}</div><div class="sub">${sub}</div></div>`
  ).join("");

  const route = net.route || {};
  document.getElementById("routeBadge").textContent = (route.interfaceKind || "Wi-Fi") + (route.isVPNActive ? " + VPN" : " " + s.direct);
  document.getElementById("slaBadge").textContent = "P50 " + fmt0(net.p50Ms) + "ms • P95 " + fmt0(net.p95Ms) + "ms • P99 " + fmt0(net.p99Ms) + "ms";
}

function drawChart(canvasId, seriesList, buckets, dropField) {
  const s = t();
  const canvas = document.getElementById(canvasId);
  const dpr = window.devicePixelRatio || 1;
  const w = canvas.clientWidth;
  const h = canvas.clientHeight;
  canvas.width = w * dpr;
  canvas.height = h * dpr;
  const ctx = canvas.getContext("2d");
  ctx.scale(dpr, dpr);
  ctx.clearRect(0, 0, w, h);

  if (!buckets || buckets.length < 2) {
    ctx.fillStyle = "#939bb0";
    ctx.font = "13px -apple-system, sans-serif";
    ctx.fillText(s.waitingSamples, 16, h / 2);
    return;
  }

  const padL = 42, padR = 12, padT = 10, padB = 22;
  const plotW = w - padL - padR, plotH = h - padT - padB;
  let maxY = 10;
  for (const ser of seriesList) {
    for (const b of buckets) {
      const val = b[ser.key];
      if (val != null && val > maxY) maxY = val;
    }
  }
  maxY = maxY * 1.15;

  ctx.strokeStyle = "rgba(255,255,255,0.08)";
  ctx.lineWidth = 1;
  ctx.fillStyle = "#939bb0";
  ctx.font = "11px monospace";
  for (let i = 0; i <= 4; i++) {
    const y = padT + (plotH * i) / 4;
    ctx.beginPath(); ctx.moveTo(padL, y); ctx.lineTo(w - padR, y); ctx.stroke();
    ctx.fillText(Math.round(maxY * (1 - i / 4)), 4, y + 4);
  }

  if (dropField) {
    ctx.strokeStyle = "rgba(248,113,113,0.65)";
    ctx.lineWidth = 2;
    buckets.forEach((b, idx) => {
      if ((b[dropField] || 0) > 0) {
        const x = padL + (idx / (buckets.length - 1)) * plotW;
        ctx.beginPath(); ctx.moveTo(x, padT); ctx.lineTo(x, padT + plotH); ctx.stroke();
      }
    });
  }

  for (const ser of seriesList) {
    ctx.strokeStyle = ser.color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    let started = false;
    buckets.forEach((b, idx) => {
      const v = b[ser.key];
      if (v == null) { started = false; return; }
      const x = padL + (idx / (buckets.length - 1)) * plotW;
      const y = padT + plotH - (v / maxY) * plotH;
      if (!started) { ctx.moveTo(x, y); started = true; } else { ctx.lineTo(x, y); }
    });
    ctx.stroke();
  }
}

function renderAllCharts(buckets) {
  drawChart("hwChart", [
    { key: "maxCPUTemp", color: "#38bdf8" },
    { key: "maxGPUTemp", color: "#fb923c" },
    { key: "avgWatts", color: "#a78bfa" }
  ], buckets, null);
  drawChart("netChart", [
    { key: "maxPingMs", color: "#38bdf8" },
    { key: "maxUDPMs", color: "#fb923c" },
    { key: "maxGatewayMs", color: "#34d399" }
  ], buckets, "dropCount");
}

function renderIncidents(events) {
  const s = t();
  const tbody = document.getElementById("incidentsBody");
  if (!events || !events.length) {
    tbody.innerHTML = `<tr><td colspan="5" style="color:var(--muted);">${s.noIncidents}</td></tr>`;
    return;
  }
  tbody.innerHTML = events.slice(0, 30).map(ev => {
    const dt = new Date(ev.timestamp * 1000).toLocaleTimeString();
    const delta = ev.deltaSincePreviousDropSeconds != null ? "+" + Math.round(ev.deltaSincePreviousDropSeconds) + "s" : "--";
    const kind = (s.incidentKinds && s.incidentKinds[ev.kind]) || ev.kind;
    const route = String(ev.routeLabel || "").replace(/ Direto$/, " " + s.direct);
    return `<tr><td>${dt}</td><td>${kind}</td><td>${delta}</td><td>${route}</td><td>${ev.details}</td></tr>`;
  }).join("");
}

async function pollSnapshot() {
  try {
    const res = await fetch("/api/snapshot", { cache: "no-store" });
    if (!res.ok) throw new Error("http");
    const data = await res.json();
    lastSnapshot = data;
    document.getElementById("liveDot").classList.remove("offline");
    renderKPIs(data);
  } catch {
    document.getElementById("liveDot").classList.add("offline");
  }
}

async function pollHistoryAndIncidents() {
  try {
    const [hRes, iRes] = await Promise.all([
      fetch("/api/history?window=" + selectedWindow, { cache: "no-store" }),
      fetch("/api/incidents", { cache: "no-store" })
    ]);
    if (hRes.ok) {
      lastBuckets = await hRes.json();
      renderAllCharts(lastBuckets);
    }
    if (iRes.ok) {
      lastIncidents = await iRes.json();
      renderIncidents(lastIncidents);
    }
  } catch {}
}

document.querySelectorAll("button[data-lang]").forEach(btn => {
  btn.addEventListener("click", () => {
    const next = btn.dataset.lang;
    if (!I18N[next]) return;
    currentLang = next;
    localStorage.setItem("arkdiehud_lang", next);
    applyStaticTranslations();
    if (lastSnapshot) renderKPIs(lastSnapshot);
    if (lastBuckets) renderAllCharts(lastBuckets);
    if (lastIncidents) renderIncidents(lastIncidents);
  });
});

document.querySelectorAll("button[data-win]").forEach(btn => {
  btn.addEventListener("click", () => {
    document.querySelectorAll("button[data-win]").forEach(b => b.classList.remove("active"));
    btn.classList.add("active");
    selectedWindow = Number(btn.dataset.win);
    document.getElementById("csvLink").href = "/api/csv?window=" + selectedWindow;
    pollHistoryAndIncidents();
  });
});

applyStaticTranslations();
pollSnapshot();
pollHistoryAndIncidents();
setInterval(pollSnapshot, 1000);
setInterval(pollHistoryAndIncidents, 3000);
</script>
</body>
</html>
"""
}
