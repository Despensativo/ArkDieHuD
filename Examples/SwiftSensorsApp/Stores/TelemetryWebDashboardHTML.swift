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
  .hud-checks {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    margin-bottom: 10px;
  }
  .hud-chk {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    font-size: 11px;
    font-weight: 600;
    color: var(--text);
    background: #0d121c;
    border: 1px solid var(--border);
    border-radius: 999px;
    padding: 4px 9px;
    cursor: pointer;
    user-select: none;
  }
  .hud-chk input { accent-color: var(--accent); cursor: pointer; margin: 0; }
  select.hud-sel {
    background: var(--card);
    color: var(--text);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 6px 10px;
    font-size: 12px;
    font-weight: 600;
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

<section class="card chart-card" id="fpsChartCard" style="display:none;margin-bottom:18px;">
  <h2>
    <span id="fpsChartTitle">Game FPS History (Avg / Min)</span>
    <span id="fpsChartLegend" class="legend">Green: Avg FPS • Orange: Min FPS</span>
  </h2>
  <div id="fpsExplainer" style="font-size:11px;color:var(--muted);margin:-2px 0 8px 0;">FPS = frames per second (higher = smoother) • ms/frame = time per frame (lower = smoother)</div>
  <canvas id="fpsChart"></canvas>
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

<section class="card" style="margin-top:14px;">
  <h2 id="metalHudTitle" style="margin:0 0 6px 0;font-size:14px;">Apple Metal FPS HUD Launcher (Mac &amp; Windows)</h2>
  <p id="metalHudDesc" style="margin:0 0 12px 0;font-size:12px;color:var(--muted);">
    Enable Apple's official real-time FPS / GPU / Frame Time overlay inside any game or app on your iPhone/iPad (works over Wi-Fi or USB on macOS; USB on Windows).
  </p>
  <div class="controls" style="margin-bottom:10px;">
    <button type="button" class="active" data-hud-preset="fps-tiny" id="presetFpsTinyBtn">Ultra Compact (FPS Only)</button>
    <button type="button" data-hud-preset="fps-gpu" id="presetFpsGpuBtn">FPS + GPU + Graphs</button>
    <button type="button" data-hud-preset="minimal" id="presetMinimalBtn">Minimal (FPS + GPU)</button>
    <button type="button" data-hud-preset="full" id="presetFullBtn">Apple Full</button>
    <select id="hudAlignSelect" class="hud-sel" aria-label="HUD Position">
      <option value="topright" selected>Top Right</option>
      <option value="topleft">Top Left</option>
      <option value="topcenter">Top Center</option>
      <option value="bottomright">Bottom Right</option>
      <option value="bottomleft">Bottom Left</option>
      <option value="bottomcenter">Bottom Center</option>
      <option value="centerleft">Center Left</option>
      <option value="centerright">Center Right</option>
      <option value="centered">Center</option>
    </select>
    <select id="hudScaleSelect" class="hud-sel" aria-label="HUD Scale">
      <option value="">Size: Default</option>
      <option value="0.14" selected>Size: Compact (0.14)</option>
      <option value="0.18">Size: Small (0.18)</option>
      <option value="0.22">Size: Medium (0.22)</option>
      <option value="0.28">Size: Large (0.28)</option>
    </select>
    <select id="hudOpacitySelect" class="hud-sel" aria-label="HUD Opacity">
      <option value="" id="optOpacity100" selected>Opacity: 100%</option>
      <option value="0.6" id="optOpacity60">Opacity: 60%</option>
      <option value="0.3" id="optOpacity30">Opacity: 30%</option>
      <option value="0" id="optOpacity0">Invisible (Web Only)</option>
    </select>
  </div>
  <div class="hud-checks" role="group" aria-label="Metal HUD Metrics">
    <label class="hud-chk"><input type="checkbox" data-hud-el="fps" checked> FPS</label>
    <label class="hud-chk"><input type="checkbox" data-hud-el="gputime"> GPU ms</label>
    <label class="hud-chk"><input type="checkbox" data-hud-el="fpsgraph"> FPS Graph</label>
    <label class="hud-chk"><input type="checkbox" data-hud-el="frameintervalgraph"> Frame Graph</label>
    <label class="hud-chk"><input type="checkbox" data-hud-el="gputimeline"> GPU Timeline</label>
    <label class="hud-chk"><input type="checkbox" data-hud-el="memory"> RAM</label>
    <label class="hud-chk"><input type="checkbox" data-hud-el="thermal"> Thermal</label>
    <label class="hud-chk"><input type="checkbox" data-hud-el="shaders"> Shaders</label>
    <label class="hud-chk"><input type="checkbox" data-hud-el="device"> GPU Name</label>
  </div>
  <div class="hud-checks">
    <label class="hud-chk" style="border-color:rgba(52,211,153,0.4);color:var(--green);">
      <input type="checkbox" id="hudStreamWebToggle" checked>
      <span id="hudStreamWebLabel">Stream FPS to Web Monitor + 24h Log</span>
    </label>
  </div>
  <div class="controls" style="margin-bottom:10px;">
    <button id="copyMacCmdBtn" type="button" style="border-color:var(--accent);color:var(--accent);">Copy Mac Command (1-Click)</button>
    <a id="dlWinBtn" class="btn" style="border-color:var(--green);color:var(--green);" href="/download/metal-hud-windows.bat" download>Windows (.bat)</a>
    <a id="dlPyBtn" class="btn" href="/download/arkdiehud_metal_hud.py" download>Python Script (.py)</a>
  </div>
  <pre id="macCmdPreview" style="margin:0 0 10px 0;padding:8px 10px;border-radius:8px;background:#090c12;border:1px solid var(--border);font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;color:var(--accent);overflow-x:auto;user-select:all;"></pre>
  <p id="metalHudHint" style="margin:0;font-size:11px;color:var(--muted);line-height:1.45;">
    macOS: click Copy Mac Command, paste into Terminal and press Enter (no Gatekeeper or chmod prompts; works over Wi-Fi or USB). Windows: download Windows (.bat), install Python 3 + Apple Devices/iTunes USB driver, and right-click -&gt; Run as Administrator.
  </p>
  <details id="hudOpacityGuideDetails" open style="margin-top:10px;padding:10px 12px;border-radius:8px;background:rgba(56,189,248,0.05);border:1px solid rgba(56,189,248,0.22);font-size:11.5px;line-height:1.5;">
    <summary id="hudOpacityGuideTitle" style="cursor:pointer;font-weight:600;color:var(--accent);">Step-by-step: Developer Mode &amp; keeping HUD tiny or hidden</summary>
    <div id="hudGuideDevStep" style="margin-top:8px;color:var(--text);">1. Prerequisite — enable Developer Mode: on iPad/iPhone open Settings → Privacy &amp; Security → Developer Mode (restart if prompted; required for Developer menu &amp; launcher).</div>
    <div id="hudGuideBaseStep" style="margin-top:5px;color:var(--text);font-weight:500;">2. Open Settings → Developer → Metal HUD (keep "Show Metal Performance HUD" OFF — iOS/iPadOS still reuses these settings when returning to a game):</div>
    <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:8px;margin-top:8px;">
      <div style="padding:8px 10px;border-radius:7px;background:rgba(56,189,248,0.07);border:1px solid rgba(56,189,248,0.25);">
        <div id="hudShowCardTitle" style="font-weight:600;color:var(--accent);margin-bottom:4px;">Keep tiny on screen (stays mini after switching)</div>
        <div id="hudShowLine1" style="color:var(--text);">• Drag Scale to minimum (left) and turn ON Log Metal Performance.</div>
        <div id="hudShowLine2" style="color:var(--text);">• Under Metrics, disable all except FPS so it never comes back huge.</div>
        <div id="hudShowLine3" style="color:var(--muted);font-size:11px;margin-top:3px;">Keep Opacity at 100% in Settings (to check/restore visibility anytime).</div>
      </div>
      <div style="padding:8px 10px;border-radius:7px;background:rgba(16,185,129,0.07);border:1px solid rgba(16,185,129,0.25);">
        <div id="hudHideCardTitle" style="font-weight:600;color:var(--green);margin-bottom:4px;">Hide on screen (view FPS on Web :8787 only)</div>
        <div id="hudHideLine1" style="color:var(--text);">• In Settings → Metal HUD, drag Opacity all the way left to 0%.</div>
        <div id="hudHideLine2" style="color:var(--text);">• Above, choose Invisible (Web Only) and launch via the command.</div>
        <div id="hudHideNote" style="color:var(--muted);font-size:11px;margin-top:3px;">Stays 100% invisible even after leaving and returning to the game.</div>
      </div>
    </div>
    <div id="hudStreamTip" style="margin-top:8px;color:var(--muted);font-size:11px;">Tip: keep Terminal (Mac) or the .bat window (Windows) open while playing so live FPS updates here (Control+C to stop).</div>
  </details>
</section>

<script>
const I18N = {
  "en": {
    pageTitle: "ArkDieHuD — Live Telemetry",
    connecting: "Connecting...",
    direct: "Direct",
    realLink: "Real Link",
    downloadCSV: "Download CSV",
    metalHudTitle: "Apple Metal FPS HUD Launcher (Mac & Windows)",
    metalHudDesc: "Enable Apple's official real-time FPS / GPU / Frame Time overlay inside any game or app on your iPhone/iPad (works over Wi-Fi or USB on macOS; USB on Windows).",
    presetFpsTiny: "Ultra Compact (FPS Only)",
    presetFpsGpu: "FPS + GPU + Graphs",
    presetMinimal: "Minimal (FPS + GPU)",
    presetFull: "Apple Full",
    optOpacity100: "Opacity: 100%",
    optOpacity60: "Opacity: 60%",
    optOpacity30: "Opacity: 30%",
    optOpacity0: "Invisible (Web Only)",
    streamWebLabel: "Stream FPS to Web Monitor + 24h Log",
    fpsWaitingHint: "Run --stream-web launcher",
    gameFPS: "Game FPS",
    gameVRAMRAM: "Game VRAM / RAM",
    fpsChartTitle: "Game FPS History (Avg / Min)",
    fpsChartLegend: "Green: Avg FPS • Orange: Min FPS",
    avgLabel: "Avg",
    minLabel: "Min",
    maxLabel: "Max",
    copyMacCmd: "Copy Mac Command (1-Click)",
    copiedMacCmd: "Copied! Paste in Terminal",
    dlWinBtn: "Windows (.bat)",
    dlPyBtn: "Python Script (.py)",
    metalHudHint: "macOS: click Copy Mac Command, paste into Terminal and press Enter (no Gatekeeper or chmod prompts; works over Wi-Fi or USB). Windows: download Windows (.bat), install Python 3 + Apple Devices/iTunes USB driver, and right-click -> Run as Administrator.",
    hudOpacityGuideTitle: "Step-by-step: Developer Mode & keeping HUD tiny or hidden",
    hudGuideDevStep: "1. Prerequisite — enable Developer Mode: on iPad/iPhone open Settings → Privacy & Security → Developer Mode (restart if prompted; required for Developer menu & launcher).",
    hudGuideBaseStep: "2. Open Settings → Developer → Metal HUD (keep 'Show Metal Performance HUD' OFF — iOS/iPadOS still reuses these settings when returning to a game):",
    hudShowCardTitle: "Keep tiny on screen (stays mini after switching)",
    hudShowLine1: "• Drag Scale to minimum (left) and turn ON Log Metal Performance.",
    hudShowLine2: "• Under Metrics, disable all except FPS so it never comes back huge.",
    hudShowLine3: "Keep Opacity at 100% in Settings (to check/restore visibility anytime).",
    hudHideCardTitle: "Hide on screen (view FPS on Web :8787 only)",
    hudHideLine1: "• In Settings → Metal HUD, drag Opacity all the way left to 0%.",
    hudHideLine2: "• Above, choose Invisible (Web Only) and launch via the command.",
    hudHideNote: "Stays 100% invisible even after leaving and returning to the game.",
    hudStreamTip: "Tip: keep Terminal (Mac) or the .bat window (Windows) open while playing so live FPS updates here (Control+C to stop).",
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
    download: "Download",
    upload: "Upload",
    totalData: "Total Data (DL+UL)",
    totalLabel: "Session",
    msPerFrame: "ms/frame",
    fpsSmooth: "Smooth",
    fpsStable: "Stable",
    fpsDrop: "Drop / Lag",
    fpsExplainer: "FPS = frames per second (higher = smoother) • ms/frame = time per frame (lower = smoother)",
    nowLabel: "Now",
    minDropsLabel: "Min (drops)",
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
    realLink: "Link Real",
    downloadCSV: "Baixar CSV",
    metalHudTitle: "Launcher Apple Metal FPS HUD (Mac e Windows)",
    metalHudDesc: "Ative o contador oficial da Apple (FPS / GPU / Frame Time) dentro de qualquer jogo ou app no iPhone/iPad (funciona via Wi-Fi ou USB no macOS; USB no Windows).",
    presetFpsTiny: "Ultra Compacto (Só FPS)",
    presetFpsGpu: "FPS + GPU + Gráficos",
    presetMinimal: "Mínimo (FPS + GPU)",
    presetFull: "Completo Apple",
    optOpacity100: "Opacidade: 100%",
    optOpacity60: "Opacidade: 60%",
    optOpacity30: "Opacidade: 30%",
    optOpacity0: "Invisível (Só Web)",
    streamWebLabel: "Enviar FPS ao Painel Web + Log 24h",
    fpsWaitingHint: "Aguardando --stream-web",
    gameFPS: "FPS do Jogo",
    gameVRAMRAM: "VRAM / RAM do Jogo",
    fpsChartTitle: "Histórico de FPS do Jogo (Média / Mín)",
    fpsChartLegend: "Verde: FPS Médio • Laranja: FPS Mínimo",
    avgLabel: "Méd",
    minLabel: "Mín",
    maxLabel: "Máx",
    copyMacCmd: "Copiar Comando Mac (1 Clique)",
    copiedMacCmd: "Copiado! Cole no Terminal",
    dlWinBtn: "Windows (.bat)",
    dlPyBtn: "Script Python (.py)",
    metalHudHint: "macOS: clique em Copiar Comando Mac, cole no Terminal e aperte Enter (sem bloqueio do Gatekeeper nem chmod; funciona via Wi-Fi ou USB). Windows: baixe Windows (.bat), tenha Python 3 + driver USB Dispositivos Apple/iTunes e clique com botão direito -> Executar como Administrador.",
    hudOpacityGuideTitle: "Passo a passo: ativar Modo Desenvolvedor e manter HUD pequeno ou invisível",
    hudGuideDevStep: "1. Pré-requisito — ative o Modo Desenvolvedor: no iPad/iPhone abra Ajustes → Privacidade e Segurança → Modo Desenvolvedor (reinicie se pedir; sem isso o menu e o launcher não funcionam).",
    hudGuideBaseStep: "2. Abra Ajustes → Desenvolvedor → HUD Metal (mantenha 'Mostrar HUD de Desempenho do Metal' DESATIVADO; mesmo desligado, o iOS usa os ajustes abaixo ao sair e voltar para o jogo):",
    hudShowCardTitle: "Deixar pequeno na tela (não volta gigante ao sair/voltar)",
    hudShowLine1: "• Arraste Escala ao mínimo (esquerda) e ative Registrar Desempenho do Metal.",
    hudShowLine2: "• Em Métricas, deixe só FPS ligado (desative o resto).",
    hudShowLine3: "Deixe Opacidade em 100% nos Ajustes (e use para checar ou restaurar quando quiser).",
    hudHideCardTitle: "Ocultar da tela (ver FPS só aqui na Web)",
    hudHideLine1: "• Em Ajustes → HUD Metal, arraste Opacidade até 0% (óculos claro à esquerda).",
    hudHideLine2: "• No seletor acima, escolha Invisível (Só Web) e inicie pelo comando.",
    hudHideNote: "Fica 100% invisível mesmo se você sair e voltar para o jogo.",
    hudStreamTip: "Dica: mantenha o Terminal (Mac) ou janela .bat (Windows) aberto enquanto joga para o FPS atualizar ao vivo (Control+C para parar).",
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
    download: "Download",
    upload: "Upload",
    totalData: "Total de Dados (DL+UL)",
    totalLabel: "Sessão",
    msPerFrame: "ms/quadro",
    fpsSmooth: "Fluido",
    fpsStable: "Estável",
    fpsDrop: "Queda / Travando",
    fpsExplainer: "FPS = quadros por segundo (maior = melhor) • ms/quadro = tempo por quadro (menor = mais liso)",
    nowLabel: "Agora",
    minDropsLabel: "Mín (quedas)",
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
    realLink: "Enlace Real",
    downloadCSV: "Descargar CSV",
    metalHudTitle: "Launcher Apple Metal FPS HUD (Mac y Windows)",
    metalHudDesc: "Activa el contador oficial de Apple (FPS / GPU / Frame Time) dentro de cualquier juego o app en tu iPhone/iPad (funciona por Wi-Fi o USB en macOS; USB en Windows).",
    presetFpsTiny: "Ultra Compacto (Solo FPS)",
    presetFpsGpu: "FPS + GPU + Gráficos",
    presetMinimal: "Mínimo (FPS + GPU)",
    presetFull: "Completo Apple",
    optOpacity100: "Opacidad: 100%",
    optOpacity60: "Opacidad: 60%",
    optOpacity30: "Opacidad: 30%",
    optOpacity0: "Invisible (Solo Web)",
    streamWebLabel: "Enviar FPS al Monitor Web + Log 24h",
    fpsWaitingHint: "Esperando --stream-web",
    gameFPS: "FPS del Juego",
    gameVRAMRAM: "VRAM / RAM del Juego",
    fpsChartTitle: "Historial de FPS del Juego (Prom / Mín)",
    fpsChartLegend: "Verde: FPS Prom • Naranja: FPS Mín",
    avgLabel: "Prom",
    minLabel: "Mín",
    maxLabel: "Máx",
    copyMacCmd: "Copiar Comando Mac (1 Clic)",
    copiedMacCmd: "¡Copiado! Pega en Terminal",
    dlWinBtn: "Windows (.bat)",
    dlPyBtn: "Script Python (.py)",
    metalHudHint: "macOS: pulsa Copiar Comando Mac, pega en Terminal y presiona Enter (sin bloqueo de Gatekeeper ni chmod; funciona por Wi-Fi o USB). Windows: descarga Windows (.bat), instala Python 3 + driver USB Apple Devices/iTunes y clic derecho -> Ejecutar como Administrador.",
    hudOpacityGuideTitle: "Paso a paso: activar Modo Desarrollador y mantener el HUD pequeño o invisible",
    hudGuideDevStep: "1. Requisito previo — activa el Modo Desarrollador: en iPad/iPhone abre Ajustes → Privacidad y Seguridad → Modo de Desarrollador (reinicia si lo pide; necesario para el menú y el launcher).",
    hudGuideBaseStep: "2. Abre Ajustes → Desarrollador → HUD de Metal (mantén 'Mostrar HUD de rendimiento de Metal' DESACTIVADO; aunque esté apagado, iOS aplica estos ajustes al salir/volver al juego):",
    hudShowCardTitle: "Mantener pequeño en pantalla (sigue mini al cambiar de app)",
    hudShowLine1: "• Baja Escala al mínimo (izquierda) y activa Registrar rendimiento de Metal.",
    hudShowLine2: "• En Métricas, deja solo FPS activado para que no vuelva gigante.",
    hudShowLine3: "Deja Opacidad al 100% en Ajustes (para revisar o volver a verlo cuando quieras).",
    hudHideCardTitle: "Ocultar en pantalla (ver FPS solo en Web)",
    hudHideLine1: "• En Ajustes → HUD de Metal, baja Opacidad al 0% (izquierda).",
    hudHideLine2: "• Arriba, elige Invisible (Solo Web) y abre el juego con el comando.",
    hudHideNote: "Permanece 100% invisible incluso al salir y volver al juego.",
    hudStreamTip: "Consejo: mantén abierta la Terminal (Mac) o ventana .bat (Windows) mientras juegas para actualizar el FPS en vivo (Control+C para detener).",
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
    download: "Descarga",
    upload: "Subida",
    totalData: "Datos Totales (DL+UL)",
    totalLabel: "Sesión",
    msPerFrame: "ms/cuadro",
    fpsSmooth: "Fluido",
    fpsStable: "Estable",
    fpsDrop: "Caída / Lag",
    fpsExplainer: "FPS = cuadros por segundo (mayor = mejor) • ms/cuadro = tiempo por cuadro (menor = más fluido)",
    nowLabel: "Ahora",
    minDropsLabel: "Mín (caídas)",
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

const HUD_PRESET_MAP = {
  "fps-tiny": ["fps"],
  "fps-gpu": ["fps", "gputime", "fpsgraph", "frameintervalgraph"],
  "minimal": ["fps", "gputime"],
  "full": []
};

function getSelectedHudParams() {
  const els = Array.from(document.querySelectorAll("input[data-hud-el]:checked"))
    .map(cb => cb.dataset.hudEl);
  const alignEl = document.getElementById("hudAlignSelect");
  const scaleEl = document.getElementById("hudScaleSelect");
  const opacityEl = document.getElementById("hudOpacitySelect");
  const streamEl = document.getElementById("hudStreamWebToggle");
  return {
    elements: els.join(","),
    align: alignEl ? alignEl.value : "",
    scale: scaleEl ? scaleEl.value : "",
    opacity: opacityEl ? opacityEl.value : "",
    streamWeb: Boolean(streamEl && streamEl.checked)
  };
}

function getMacLaunchCommand() {
  const p = getSelectedHudParams();
  let cmd = "curl -fsSL " + window.location.origin + "/download/arkdiehud_metal_hud.py -o /tmp/arkdiehud_metal_hud.py && python3 /tmp/arkdiehud_metal_hud.py";
  if (p.elements) cmd += " --elements " + p.elements;
  if (p.align) cmd += " --align " + p.align;
  if (p.scale) cmd += " --scale " + p.scale;
  if (p.opacity !== "") cmd += " --opacity " + p.opacity;
  if (p.streamWeb) cmd += " --stream-web " + window.location.origin;
  return cmd;
}

const HUD_PREFS_KEY = "arkdiehud_metal_hud_v1";

function saveMetalHUDPrefs(p) {
  try {
    localStorage.setItem(HUD_PREFS_KEY, JSON.stringify({
      elements: p.elements,
      align: p.align,
      scale: p.scale,
      opacity: p.opacity,
      streamWeb: Boolean(p.streamWeb)
    }));
  } catch (e) {}
}

function loadMetalHUDPrefs() {
  try {
    const raw = localStorage.getItem(HUD_PREFS_KEY);
    if (!raw) return;
    const saved = JSON.parse(raw);
    if (saved && typeof saved.elements === "string") {
      const wanted = new Set(saved.elements.split(",").map(x => x.trim()).filter(Boolean));
      document.querySelectorAll("input[data-hud-el]").forEach(cb => {
        cb.checked = wanted.has(cb.dataset.hudEl);
      });
    }
    const alignEl = document.getElementById("hudAlignSelect");
    if (alignEl && typeof saved.align === "string") alignEl.value = saved.align;
    const scaleEl = document.getElementById("hudScaleSelect");
    if (scaleEl && typeof saved.scale === "string") scaleEl.value = saved.scale;
    const opacityEl = document.getElementById("hudOpacitySelect");
    if (opacityEl && typeof saved.opacity === "string") opacityEl.value = saved.opacity;
    const streamEl = document.getElementById("hudStreamWebToggle");
    if (streamEl && typeof saved.streamWeb === "boolean") streamEl.checked = saved.streamWeb;
  } catch (e) {}
  syncHudPresetButtons();
}

function updateMetalHUDControls() {
  const p = getSelectedHudParams();
  saveMetalHUDPrefs(p);
  document.getElementById("macCmdPreview").textContent = getMacLaunchCommand();
  const qp = new URLSearchParams();
  if (p.elements) qp.set("elements", p.elements);
  if (p.align) qp.set("align", p.align);
  if (p.scale) qp.set("scale", p.scale);
  if (p.opacity !== "") qp.set("opacity", p.opacity);
  if (p.streamWeb) qp.set("streamWeb", "1");
  const qs = qp.toString();
  document.getElementById("dlWinBtn").href = "/download/metal-hud-windows.bat" + (qs ? "?" + qs : "");
  if (p.opacity === "0") {
    const det = document.getElementById("hudOpacityGuideDetails");
    if (det) det.open = true;
  }
}

function syncHudPresetButtons() {
  const checked = Array.from(document.querySelectorAll("input[data-hud-el]:checked"))
    .map(cb => cb.dataset.hudEl)
    .sort()
    .join(",");
  document.querySelectorAll("button[data-hud-preset]").forEach(btn => {
    const presetList = (HUD_PRESET_MAP[btn.dataset.hudPreset] || []).slice().sort().join(",");
    btn.classList.toggle("active", checked === presetList);
  });
}

function applyStaticTranslations() {
  const s = t();
  document.documentElement.lang = currentLang;
  document.title = s.pageTitle;
  document.getElementById("csvLink").textContent = s.downloadCSV;
  document.getElementById("metalHudTitle").textContent = s.metalHudTitle;
  document.getElementById("metalHudDesc").textContent = s.metalHudDesc;
  document.getElementById("presetFpsTinyBtn").textContent = s.presetFpsTiny;
  document.getElementById("presetFpsGpuBtn").textContent = s.presetFpsGpu;
  document.getElementById("presetMinimalBtn").textContent = s.presetMinimal;
  document.getElementById("presetFullBtn").textContent = s.presetFull;
  document.getElementById("optOpacity100").textContent = s.optOpacity100;
  document.getElementById("optOpacity60").textContent = s.optOpacity60;
  document.getElementById("optOpacity30").textContent = s.optOpacity30;
  document.getElementById("optOpacity0").textContent = s.optOpacity0;
  document.getElementById("hudStreamWebLabel").textContent = s.streamWebLabel;
  document.getElementById("copyMacCmdBtn").textContent = s.copyMacCmd;
  updateMetalHUDControls();
  document.getElementById("dlWinBtn").textContent = s.dlWinBtn;
  document.getElementById("dlPyBtn").textContent = s.dlPyBtn;
  document.getElementById("metalHudHint").textContent = s.metalHudHint;
  document.getElementById("hudOpacityGuideTitle").textContent = s.hudOpacityGuideTitle;
  document.getElementById("hudGuideDevStep").textContent = s.hudGuideDevStep;
  document.getElementById("hudGuideBaseStep").textContent = s.hudGuideBaseStep;
  document.getElementById("hudShowCardTitle").textContent = s.hudShowCardTitle;
  document.getElementById("hudShowLine1").textContent = s.hudShowLine1;
  document.getElementById("hudShowLine2").textContent = s.hudShowLine2;
  document.getElementById("hudShowLine3").textContent = s.hudShowLine3;
  document.getElementById("hudHideCardTitle").textContent = s.hudHideCardTitle;
  document.getElementById("hudHideLine1").textContent = s.hudHideLine1;
  document.getElementById("hudHideLine2").textContent = s.hudHideLine2;
  document.getElementById("hudHideNote").textContent = s.hudHideNote;
  document.getElementById("hudStreamTip").textContent = s.hudStreamTip;
  document.getElementById("hwChartTitle").textContent = s.hwTitle;
  document.getElementById("hwChartLegend").textContent = s.hwLegend;
  document.getElementById("netChartTitle").textContent = s.netTitle;
  document.getElementById("netChartLegend").textContent = s.netLegend;
  document.getElementById("fpsChartTitle").textContent = s.fpsChartTitle;
  document.getElementById("fpsExplainer").textContent = s.fpsExplainer;
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

function formatSpeed(bps) {
  const v = Number(bps || 0);
  if (v >= 1048576) return fmt(v / 1048576, 1) + " MB/s";
  if (v >= 1024) return fmt0(v / 1024) + " KB/s";
  return fmt0(v) + " B/s";
}

function formatBytes(bytes) {
  const b = Number(bytes || 0);
  if (b >= 1073741824) return fmt(b / 1073741824, 2) + " GB";
  if (b >= 1048576) return fmt(b / 1048576, 1) + " MB";
  if (b >= 1024) return fmt0(b / 1024) + " KB";
  return fmt0(b) + " B";
}

function fpsStatus(fps, s) {
  if (fps >= 55) return { label: s.fpsSmooth, color: "var(--green)" };
  if (fps >= 28) return { label: s.fpsStable, color: "var(--yellow)" };
  return { label: s.fpsDrop, color: "var(--red)" };
}

function renderKPIs(d) {
  const s = t();
  const cpuT = d.cpuTemperature ?? d.peakTemperature;
  const net = d.network || {};
  const memPct = d.memoryTotalBytes > 0 ? (d.memoryUsedBytes / d.memoryTotalBytes) * 100 : 0;
  const memGB = d.memoryUsedBytes / 1073741824;
  const lossPct = net.totalLossPercent || 0;
  const thm = (s.thermalStates && s.thermalStates[d.thermalState]) || d.thermalState || "--";
  const dlSession = net.sessionDownloadBytes || 0;
  const ulSession = net.sessionUploadBytes || 0;
  const totSession = dlSession + ulSession;
  const fStat = d.gameFPS != null ? fpsStatus(d.gameFPS, s) : null;

  const cards = [
    ...(d.gameFPS != null ? [
      [s.gameFPS, fmt(d.gameFPS, 1) + " FPS", `${fStat.label} • ${fmt(d.gameFrameTimeMs, 1)} ${s.msPerFrame}`, fStat.color],
      [s.gameVRAMRAM, fmt(d.gameVRAMMB, 1) + " MB", `${d.gameName || "Metal"} • RAM ${fmt0(d.gameRAMMB)} MB`, "var(--accent)"]
    ] : [
      [s.gameFPS, "-- FPS", s.fpsWaitingHint, "var(--muted)"]
    ]),
    ["CPU Die", cpuT != null ? fmt(cpuT, 1) + "°C" : "--", d.cpuSensorName || s.cpuSilicon, tempColor(cpuT)],
    ...(d.gpuTemperature != null ? [["GPU Die", fmt(d.gpuTemperature, 1) + "°C", d.gpuSensorName || s.gpuSilicon, tempColor(d.gpuTemperature)]] : []),
    [s.cpuLoad, fmt0(d.cpuTotalPercent) + "%", d.topology ? d.topology.totalCores + " " + s.cores : "CPU", d.cpuTotalPercent >= 85 ? "var(--red)" : "var(--accent)"],
    [s.power, d.estimatedWatts != null ? fmt(d.estimatedWatts, 1) + " W" : "--", s.statePrefix + thm, "var(--orange)"],
    [s.ram, fmt(memGB, 1) + " GB", fmt0(memPct) + "% " + s.used, memPct >= 85 ? "var(--red)" : "var(--accent)"],
    [s.battery, d.batteryPercent != null ? d.batteryPercent + "%" : "--", d.isCharging ? s.charging : s.onBattery, (d.batteryPercent ?? 100) <= 20 ? "var(--red)" : "var(--green)"],
    ["Ping / RTT", net.isLastProbeLost ? "DROP" : (net.pingMs != null ? fmt0(net.pingMs) + " ms" : "--"), net.target ? net.target.name : s.target, pingColor(net.pingMs, net.isLastProbeLost)],
    [s.packetLoss, net.isLastProbeLost ? "DROP!" : fmt(lossPct, 1) + "%", (net.totalLostCount || 0) + "p • 120s: " + fmt(net.lossPercent120s, 1) + "%", lossPct > 0 || net.isLastProbeLost ? "var(--red)" : "var(--green)"],
    [s.udpProbe, net.isUDPLastLost ? "DROP" : (net.udpPingMs != null ? fmt0(net.udpPingMs) + " ms" : "--"), (net.udpProbeHost || "1.1.1.1") + ":53", pingColor(net.udpPingMs, net.isUDPLastLost)],
    [s.localRouter, net.isGatewayLastProbeLost ? "DROP" : (net.gatewayPingMs != null ? fmt(net.gatewayPingMs, 1) + " ms" : "--"), net.gatewayHost || s.gateway, pingColor(net.gatewayPingMs, net.isGatewayLastProbeLost)],
    ["Jitter RFC", "±" + fmt(net.jitterMs, 1) + " ms", "P50 " + fmt0(net.p50Ms) + " • P99 " + fmt0(net.p99Ms), (net.jitterMs || 0) > 15 ? "var(--orange)" : "var(--green)"],
    [s.download, formatSpeed(net.downloadBytesPerSec), `${s.totalLabel}: ${formatBytes(dlSession)}`, "var(--green)"],
    [s.upload, formatSpeed(net.uploadBytesPerSec), `${s.totalLabel}: ${formatBytes(ulSession)}`, "var(--accent)"],
    [s.totalData, formatBytes(totSession), `↓ ${formatBytes(dlSession)} • ↑ ${formatBytes(ulSession)}`, "var(--text)"]
  ];

  document.getElementById("kpiGrid").innerHTML = cards.map(([l, v, sub, c]) =>
    `<div class="card"><div class="label">${l}</div><div class="val" style="color:${c}">${v}</div><div class="sub">${sub}</div></div>`
  ).join("");

  const route = net.route || {};
  const ifaceSuffix = route.activeInterfaceName ? ` (${route.activeInterfaceName})` : "";
  const vpnSuffix = route.isVPNActive
    ? (route.isBypassingVPN ? ` + VPN (${s.realLink})` : " + VPN")
    : " " + s.direct;
  document.getElementById("routeBadge").textContent = (route.interfaceKind || "Wi-Fi") + ifaceSuffix + vpnSuffix;
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

function drawFPSChart(buckets) {
  const s = t();
  const fpsCard = document.getElementById("fpsChartCard");
  let active = (buckets || []).filter(b => b.avgGameFPS != null && isFinite(b.avgGameFPS));
  if (active.length === 0 && lastSnapshot && lastSnapshot.gameFPS != null) {
    active = [{
      timestamp: Date.now() / 1000,
      avgGameFPS: lastSnapshot.gameFPS,
      minGameFPS: lastSnapshot.gameFPS
    }];
  }

  fpsCard.style.display = active.length > 0 ? "block" : "none";
  if (active.length === 0) return;

  document.getElementById("fpsChartTitle").textContent = s.fpsChartTitle;
  document.getElementById("fpsExplainer").textContent = s.fpsExplainer;
  const avgVals = active.map(b => b.avgGameFPS);
  const minVals = active.map(b => b.minGameFPS != null ? b.minGameFPS : b.avgGameFPS);
  const avgFPS = avgVals.reduce((a, b) => a + b, 0) / avgVals.length;
  const minFPS = Math.min(...minVals);
  const maxFPS = Math.max(...avgVals);
  const nowPrefix = (lastSnapshot && lastSnapshot.gameFPS != null)
    ? `${s.nowLabel}: ${fmt(lastSnapshot.gameFPS, 1)} (${fmt(lastSnapshot.gameFrameTimeMs, 1)} ${s.msPerFrame}) • `
    : "";
  document.getElementById("fpsChartLegend").textContent =
    `${nowPrefix}${s.fpsChartLegend} • ${s.avgLabel} ${fmt(avgFPS, 1)} / ${s.minDropsLabel} ${fmt(minFPS, 1)} / ${s.maxLabel} ${fmt(maxFPS, 1)} FPS`;

  const canvas = document.getElementById("fpsChart");
  const dpr = window.devicePixelRatio || 1;
  const w = canvas.clientWidth;
  const h = canvas.clientHeight;
  if (w <= 0 || h <= 0) return;
  canvas.width = w * dpr;
  canvas.height = h * dpr;
  const ctx = canvas.getContext("2d");
  ctx.scale(dpr, dpr);
  ctx.clearRect(0, 0, w, h);

  const padL = 48, padR = 14, padT = 12, padB = 24;
  const plotW = w - padL - padR, plotH = h - padT - padB;
  const peakData = Math.max(maxFPS, lastSnapshot && lastSnapshot.gameFPS != null ? lastSnapshot.gameFPS : 0);
  const maxY = Math.max(35, Math.ceil((peakData * 1.15) / 10) * 10);

  // Background guide lines at 30 / 60 / 120 FPS
  const targets = maxY >= 100 ? [30, 60, 120] : [30, 60];
  ctx.font = "11px monospace";
  targets.forEach(refFPS => {
    if (refFPS > maxY) return;
    const y = padT + plotH - (refFPS / maxY) * plotH;
    ctx.save();
    ctx.setLineDash([4, 4]);
    ctx.strokeStyle = refFPS >= 60 ? "rgba(52,211,153,0.28)" : "rgba(250,204,21,0.28)";
    ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(padL, y); ctx.lineTo(w - padR, y); ctx.stroke();
    ctx.restore();
    ctx.fillStyle = refFPS >= 60 ? "#34d399" : "#facc15";
    ctx.fillText(String(refFPS), 4, y + 4);
  });

  // Base 0 line & top ceiling label
  ctx.strokeStyle = "rgba(255,255,255,0.08)";
  ctx.lineWidth = 1;
  ctx.beginPath(); ctx.moveTo(padL, padT + plotH); ctx.lineTo(w - padR, padT + plotH); ctx.stroke();
  ctx.fillStyle = "#939bb0";
  ctx.fillText("0", 4, padT + plotH + 3);
  ctx.fillText(String(Math.round(maxY)), 4, padT + 9);

  const xFor = idx => active.length === 1 ? padL + plotW * 0.5 : padL + (idx / (active.length - 1)) * plotW;

  if (active.length === 1) {
    const x = xFor(0);
    const yAvg = padT + plotH - (active[0].avgGameFPS / maxY) * plotH;
    ctx.fillStyle = "#34d399";
    ctx.beginPath(); ctx.arc(x, yAvg, 5, 0, Math.PI * 2); ctx.fill();
  } else {
    // Min FPS (orange dashed)
    ctx.save();
    ctx.setLineDash([3, 3]);
    ctx.strokeStyle = "#fb923c";
    ctx.lineWidth = 1.8;
    ctx.beginPath();
    active.forEach((b, idx) => {
      const v = b.minGameFPS != null ? b.minGameFPS : b.avgGameFPS;
      const x = xFor(idx);
      const y = padT + plotH - (v / maxY) * plotH;
      if (idx === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    });
    ctx.stroke();
    ctx.restore();

    // Avg FPS (solid green)
    ctx.strokeStyle = "#34d399";
    ctx.lineWidth = 2.4;
    ctx.beginPath();
    active.forEach((b, idx) => {
      const x = xFor(idx);
      const y = padT + plotH - (b.avgGameFPS / maxY) * plotH;
      if (idx === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    });
    ctx.stroke();
  }

  // X-axis clock timestamps (start / mid / end)
  ctx.fillStyle = "#939bb0";
  ctx.font = "10px monospace";
  const fmtTime = ts => new Date(ts * 1000).toLocaleTimeString();
  if (active.length === 1) {
    const lbl = fmtTime(active[0].timestamp);
    ctx.fillText(lbl, Math.max(padL, xFor(0) - 24), padT + plotH + 15);
  } else {
    const firstLbl = fmtTime(active[0].timestamp);
    const midIdx = Math.floor(active.length / 2);
    const midLbl = fmtTime(active[midIdx].timestamp);
    const lastLbl = fmtTime(active[active.length - 1].timestamp);
    ctx.fillText(firstLbl, padL, padT + plotH + 15);
    if (active.length >= 4) {
      ctx.fillText(midLbl, padL + plotW * 0.5 - 24, padT + plotH + 15);
    }
    ctx.fillText(lastLbl, Math.max(padL + 60, w - padR - 54), padT + plotH + 15);
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
  drawFPSChart(buckets);
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
    if (data && data.gameFPS != null) {
      drawFPSChart(lastBuckets);
    }
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

document.getElementById("copyMacCmdBtn").addEventListener("click", async () => {
  const cmd = getMacLaunchCommand();
  try {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(cmd);
    } else {
      throw new Error("fallback");
    }
  } catch {
    const ta = document.createElement("textarea");
    ta.value = cmd;
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    document.execCommand("copy");
    document.body.removeChild(ta);
  }
  const btn = document.getElementById("copyMacCmdBtn");
  btn.textContent = t().copiedMacCmd;
  setTimeout(() => { btn.textContent = t().copyMacCmd; }, 2500);
});

document.querySelectorAll("button[data-hud-preset]").forEach(btn => {
  btn.addEventListener("click", () => {
    const presetName = btn.dataset.hudPreset;
    const allowed = new Set(HUD_PRESET_MAP[presetName] || []);
    document.querySelectorAll("input[data-hud-el]").forEach(cb => {
      cb.checked = allowed.has(cb.dataset.hudEl);
    });
    const scaleSel = document.getElementById("hudScaleSelect");
    if (scaleSel) {
      scaleSel.value = presetName === "fps-tiny" ? "0.14" : "";
    }
    syncHudPresetButtons();
    updateMetalHUDControls();
  });
});

document.querySelectorAll("input[data-hud-el]").forEach(cb => {
  cb.addEventListener("change", () => {
    syncHudPresetButtons();
    updateMetalHUDControls();
  });
});

document.getElementById("hudStreamWebToggle").addEventListener("change", updateMetalHUDControls);
document.getElementById("hudAlignSelect").addEventListener("change", updateMetalHUDControls);
document.getElementById("hudScaleSelect").addEventListener("change", updateMetalHUDControls);
document.getElementById("hudOpacitySelect").addEventListener("change", updateMetalHUDControls);

loadMetalHUDPrefs();
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
