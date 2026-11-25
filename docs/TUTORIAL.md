<p align="center">
  <strong>English</strong> | <a href="TUTORIAL.pt-BR.md">Português (BR)</a> | <a href="TUTORIAL.es.md">Español</a>
</p>

# ArkDieHuD — Complete Step-by-Step Tutorial

Welcome to **ArkDieHuD**. This guide walks you through installing the app (even with a **free Apple ID**), configuring the floating **Picture-in-Picture (`PiP`)** overlay, diagnosing network drops with **Dual-Probe (`ICMP + UDP + TCP`)**, viewing the **24-hour SQLite history**, and running the **PC/Mac Live Web Monitor (`:8787`)** cleanly over games.

---

## 1. Requirements & Free Apple ID Installation

- **Device:** iPad or iPhone running **iPadOS 17+ / iOS 17+** (Apple Silicon recommended for full CPU/GPU die thermals).
- **Developer Mode:** Required on iPadOS to run sideloaded or Xcode-signed builds.

### Enable Developer Mode on iPad
1. Open **Settings → Privacy & Security → Developer Mode**.
2. Toggle **Developer Mode** ON, restart your iPad when prompted, and confirm after reboot.
   *(If Developer Mode does not appear yet, plug your iPad into a Mac/PC running Xcode or Sideloadly once — iPadOS reveals it automatically.)*

### Option A: Sideloadly + `.ipa` (Easiest & Simplest — Recommended, Windows or Mac, No Xcode)
1. Download [`ArkDieHuD-unsigned.ipa`](https://github.com/Despensativo/ArkDieHuD/releases/latest/download/ArkDieHuD-unsigned.ipa) from **[GitHub Releases](https://github.com/Despensativo/ArkDieHuD/releases)**.
2. Open **[Sideloadly](https://sideloadly.io/)** (~80 MB, works on Windows & Mac), connect your iPad/iPhone via USB, enter your **free Apple ID**, and drop `ArkDieHuD-unsigned.ipa`.
3. On the device, go to **Settings → General → VPN & Device Management**, tap your Apple ID profile, and tap **Trust**.

### Option B: SideStore / AltStore Classic Official Source (Auto-Updates & Auto-Refresh)
1. In **SideStore** or **AltStore Classic** on your iPad/iPhone, go to **Sources → +** and add:
   ```text
   https://raw.githubusercontent.com/Despensativo/ArkDieHuD/main/altstore-source.json
   ```
2. Tap **ArkDieHuD** → **GET** (uses any **free Apple ID**, valid 7 days and auto-refreshed by SideStore/AltStore Classic).

> **Important (Brazil, EU & Japan):** On [altstore.io](https://altstore.io/), use **AltStore Classic** (via AltServer) or **SideStore** — **not AltStore PAL**. AltStore PAL only installs Apple-notarized marketplace packages (ADP) and cannot install `.ipa` files or apps using private `IOHID` die thermal sensors / private PiP controls.

### Option C: Guided 1-Command Installer on Mac (`./install.sh`)
If you already have Xcode installed on a Mac:
```bash
git clone https://github.com/Despensativo/ArkDieHuD.git
cd ArkDieHuD
./install.sh
```
The wizard checks Xcode, finds your connected iPad (USB or Wi-Fi), detects your Apple ID signing certificate (works with **free Personal Team** or paid Developer account), creates your local gitignored `Examples/Config/LocalSigning.xcconfig`, builds, installs, and launches ArkDieHuD automatically.

> *(Note: Xcode is only required if compiling from source on macOS. End users on Windows/Mac should use **Option A** or **Option B** with the pre-built `.ipa`. Because Apple requires personal device signing for Developer Mode / `IOHID` sensors, `.ipa` files cannot be pre-signed for everyone.)*

---

## 2. Floating PiP HUD & Custom Metrics

1. Open **ArkDieHuD** on your iPad.
2. In the **Floating HUD (PiP)** card, choose your **HUD Layout**:
   - **Gamer Bar (1 Transparent Line):** Ultra-slim horizontal bar ideal for top/bottom screen edges during PUBG, CODM, Genshin, etc.
   - **Gamer Overlay (2 Lines):** Splits Hardware on line 1 and Network on line 2.
   - **Compact Grid:** Mini cards with color thresholds and fill bars.
   - **Detailed:** Full telemetry cards + live ranking of hottest thermal sensors.
3. Tap **Customize Metrics** to pick any subset of the **12 metrics** (`CPU °C`, `GPU °C`, `CPU Load`, `RAM`, `Watts`, `Battery`, `Thermal State`, `Ping`, `UDP 53`, `Router`, `Jitter`, `Packet Loss`) or pick a 1-tap preset (*Gamer*, *Competitive Net*, *Ultra Minimal*, *Show All*).
4. Tap **Overlay on Screen (PiP)**, then switch to your game. Drag the HUD pill to any corner or pinch to resize it.
   *(Tip: **Slide Over Mode** lets you keep a full telemetry drawer accessible by swiping from the right edge of the screen.)*

---

## 3. Competitive Network Diagnostics (Dual-Probe + Multi-Protocol)

Tap **Network & Packet Log** (or the **Ping / Packet Loss** tile) to open the full network analyzer.

### How to Read Dual-Probe Results
- **Simultaneous Mode (`ICMP + UDP + TCP`)** probes your external server over three protocols at **1 Hz**, **in parallel with your Local Router (Gateway)**:
  - **Both Local Router & External Target drop:** Problem is your **Wi-Fi signal or local router**.
  - **Local Router stays ~1–3 ms (`0%` loss) while External Target drops:** Problem is your **ISP route, CGNAT, or VPN**.
  - **Only UDP (`:53`) drops while ICMP/TCP remain stable:** Sign of **UDP NAT/CGNAT congestion or QoS throttling** (directly causes rubberbanding in UDP games like PUBG).
  - **Only ICMP drops while UDP/TCP stay stable:** Server simply rate-limits ICMP ping; actual gameplay traffic is fine.
- **Cycle Detector:** Tracks the interval (`Δ +93s`, etc.) between drops to spot periodic ISP micro-disconnections.
- **Export:** Tap the Share icon in the top bar to save a raw chronological `.csv` report.

---

## 4. 24-Hour SQLite History & Unified CSV

1. Make sure **Record telemetry logs (24h)** is enabled in the main card.
2. Open **24h Telemetry & Logs** to switch between **15m | 1h | 6h | 24h** windows across **Thermal**, **Power & RAM**, and **Network**.
3. Data is flushed to **SQLite WAL** every 15 seconds (and immediately when backgrounding) and entries older than 24h are pruned automatically.
4. Tap **Export CSV** to share a unified second-by-second spreadsheet containing both hardware sensors and network telemetry.

---

## 5. PC / Mac Live Monitor (`:8787`) & Stealth PiP

Want to see CPU/GPU thermals, Watts, latency charts, and packet drops on a second monitor (**PC / Mac / Laptop**) while keeping your iPad screen **completely clear**?

1. On your iPad inside **ArkDieHuD**, toggle ON **Monitor on PC/Mac (no screen PiP)**.
2. **Option 1 — Over Wi-Fi (Same Network):**
   Open `http://<IPAD_IP>:8787` (shown right inside the card with a **Copy URL** button) in any desktop/mobile browser.
3. **Option 2 — Over USB Cable (Zero Wi-Fi Dependency):**
   ```bash
   brew install libimobiledevice   # Mac (one-time)
   iproxy 8787 8787
   ```
   Then open **`http://127.0.0.1:8787`** on your Mac/PC browser.

### Stealth PiP Mode (Recommended When Using In-Game Mic / Voice Chat)
iPadOS aggressively suspends background apps if another app captures the microphone (like PUBG Voice Chat) and no active PiP window is present. To prevent suspension without blocking your view:
1. Keep **Stealth PiP (hide at screen edge)** enabled.
2. Tap **Overlay on Screen (PiP)** — a tiny `268×44` pill (`● ARKDIEHUD • PC | ... | Drag to edge to hide & stay active`) appears.
3. **Drag the pill past the left or right edge of the iPad screen** until it tucks away cleanly off-screen.
4. Your game screen stays 100% unobstructed, your in-game mic works normally, and your PC/Mac `:8787` dashboard + 24h SQLite logger stay alive with auto-recovery on audio interruptions!

---

## 6. Bonus: Live FPS on ANY Game or App with Apple Metal Performance HUD

Combine **ArkDieHuD** with Apple's native GPU FPS counter (`MTL_HUD_ENABLED=1`) using `./launch_metal_hud.sh` on your Mac — or grab the **Mac (1-click command) / Windows (`.bat`) Metal HUD Launcher** directly from the **PC/Mac Web Dashboard (`:8787`)** inside ArkDieHuD (on Windows: requires Python 3 + Apple Devices/iTunes USB driver, run `.bat` as Administrator):

1. **Interactive Menu (Zero Setup):**
   ```bash
   ./launch_metal_hud.sh
   ```
   Lists every user app on your iPad; just type its number and press Enter.

2. **Quick Search by Name:**
   ```bash
   ./launch_metal_hud.sh genshin     # Finds and launches Genshin Impact
   ./launch_metal_hud.sh cod         # Finds and launches Call of Duty Mobile
   ./launch_metal_hud.sh capcut      # Works on creative/video apps too
   ```

3. **Find Exact Bundle ID & Launch Directly:**
   ```bash
   ./launch_metal_hud.sh --list
   ./launch_metal_hud.sh --bundle com.example.yourgame
   ```

4. **Save Your Own 1-Word Shortcuts (Manually or Using an AI Assistant):**
   Open `launch_metal_hud.sh` and add your favorite games to `CUSTOM_SHORTCUTS`:
   ```python
   CUSTOM_SHORTCUTS = {
       "genshin": ("Genshin Impact", "com.miHoYo.GenshinImpact"),
       # ...
   }
   ```
   > **Using an AI coding assistant?** Paste this prompt:
   > *"Run `./launch_metal_hud.sh --list`, find my installed games/apps, and add 1-word shortcuts for them into `CUSTOM_SHORTCUTS` inside `launch_metal_hud.sh`."*

See [METAL_HUD_GUIDE.md](METAL_HUD_GUIDE.md) for device pairing troubleshooting.

> **Tip — Keep Apple Metal HUD 100% Invisible on Screen (`:8787` Web Only) or Restore Opacity:**
> 1. On your iPad/iPhone, open **Settings → Developer → Graphics HUD** and keep **Show Graphics HUD** turned **OFF**.
> 2. **To remove on-screen opacity (stays 100% invisible even after switching apps):** drag **HUD Opacity** all the way down to **0%** in Settings and select **`Invisible (Web Only)`** on `:8787` (keep Terminal / `.bat` open while playing to stream live FPS).
> 3. **To check or show on screen again:** raise **HUD Opacity** back to **100%** in Settings and switch to **`Opacity: 100%`** on `:8787`.

---

## 7. Automatic 3-Language Support (`EN` / `PT-BR` / `ES`)

- **iPad App & PiP:** Automatically follows your iPadOS system language (**English**, **Portuguese BR**, or **Spanish**). To force a specific language just for ArkDieHuD on iPadOS, open **Settings → ArkDieHuD → Language**.
- **PC/Mac Web Dashboard (`:8787`):** Automatically detects your browser's language (`navigator.language`) and includes a quick **`EN | PT | ES`** switcher in the top toolbar.
