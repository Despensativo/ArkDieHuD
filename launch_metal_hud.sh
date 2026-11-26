#!/usr/bin/env python3
"""
Launcher para executar aplicativos e jogos no iPad/iPhone físico com o
Apple Metal Performance HUD oficial ativado (MTL_HUD_ENABLED=1).

Detecta automaticamente o iPad pareado via `xcrun devicectl` ou aceita
`--device <UDID>` / variável `METAL_HUD_DEVICE_ID`.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request


PRIORITY_APPS = [
    ("com.tencent.igfit", "PUBGM FLASH"),
    ("com.tencent.ig", "PUBG MOBILE"),
    ("com.blackmagic-design.DaVinciResolveiPad", "DaVinci Resolve"),
]

HUD_PRESETS = {
    "fps-tiny": "fps",
    "fps-gpu": "fps,gputime,fpsgraph,frameintervalgraph",
    "minimal": "fps,gputime",
    "fps-only": "fps,fpsgraph",
    "full": "",
}

METAL_HUD_LINE_RE = re.compile(r"metal-HUD:\s*(\d+),([0-9.]+),([0-9.]+)")
SYSLOG_TIME_RE = re.compile(r"(\d{2}):(\d{2}):(\d{2})\.(\d{3,6})")

VALID_ALIGNMENTS = {
    "topleft",
    "topcenter",
    "topright",
    "centerleft",
    "centered",
    "centerright",
    "bottomleft",
    "bottomcenter",
    "bottomright",
}

# Custom 1-word CLI shortcuts -> ("Display Name", "com.bundle.identifier").
# Users or AI assistants can add any app discovered via `./launch_metal_hud.sh --list`.
CUSTOM_SHORTCUTS: dict[str, tuple[str, str]] = {
    "pubg": ("PUBG MOBILE", "com.tencent.ig"),
    "pubgm": ("PUBG MOBILE", "com.tencent.ig"),
    "global": ("PUBG MOBILE", "com.tencent.ig"),
    "flash": ("PUBGM FLASH", "com.tencent.igfit"),
    "fit": ("PUBGM FLASH", "com.tencent.igfit"),
    "pubgflash": ("PUBGM FLASH", "com.tencent.igfit"),
    "pubgmflash": ("PUBGM FLASH", "com.tencent.igfit"),
    "davinci": ("DaVinci Resolve", "com.blackmagic-design.DaVinciResolveiPad"),
    "resolve": ("DaVinci Resolve", "com.blackmagic-design.DaVinciResolveiPad"),
    # Examples — uncomment or add any app from `./launch_metal_hud.sh --list`:
    # "genshin": ("Genshin Impact", "com.miHoYo.GenshinImpact"),
    # "cod": ("Call of Duty Mobile", "com.activision.callofduty.shooter"),
}


def parse_devicectl_json(stdout: str) -> dict:
    json_start = stdout.find("{")
    if json_start == -1:
        return {}
    try:
        return json.loads(stdout[json_start:])
    except json.JSONDecodeError:
        return {}


def list_physical_devices() -> list[dict]:
    cmd = ["xcrun", "devicectl", "list", "devices", "--json-output", "-"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    data = parse_devicectl_json(res.stdout)
    devices = data.get("result", {}).get("devices", [])

    physical = []
    for dev in devices:
        hw = dev.get("hardwareProperties", {})
        conn = dev.get("connectionProperties", {})
        props = dev.get("deviceProperties", {})
        if hw.get("reality") != "physical":
            continue
        if conn.get("pairingState") != "paired":
            continue

        udid = hw.get("udid") or dev.get("identifier") or ""
        if not udid:
            continue

        name = props.get("name", "Dispositivo iOS/iPadOS")
        product = hw.get("productType", "")
        transport = conn.get("transportType", "")
        is_ipad = "ipad" in product.lower() or "ipad" in name.lower()
        is_connected = conn.get("tunnelState") == "connected"
        is_wired = transport == "wired"

        physical.append(
            {
                "udid": udid,
                "name": name,
                "productType": product,
                "tunnelState": conn.get("tunnelState", "unknown"),
                "transport": transport or "unknown",
                "is_ipad": is_ipad,
                "is_connected": is_connected,
                "is_wired": is_wired,
            }
        )

    physical.sort(
        key=lambda d: (
            0 if d["is_connected"] else 1,
            0 if d["is_wired"] else 1,
            0 if d["is_ipad"] else 1,
            d["name"].lower(),
        )
    )
    return physical


def resolve_device_id(cli_device: str | None) -> tuple[str, str]:
    if cli_device:
        return cli_device, cli_device

    env_device = os.environ.get("METAL_HUD_DEVICE_ID", "").strip()
    if env_device:
        return env_device, env_device

    devices = list_physical_devices()
    if not devices:
        print("⚠️  Nenhum iPad/iPhone físico pareado encontrado via `xcrun devicectl`.")
        print("👉 Conecte o cabo USB-C ou Wi-Fi, confie no Mac e tente novamente.")
        sys.exit(1)

    selected = devices[0]
    return selected["udid"], f'{selected["name"]} ({selected["productType"] or "iOS"})'


def get_installed_apps(device_id: str) -> list[dict]:
    cmd = [
        "xcrun",
        "devicectl",
        "device",
        "info",
        "apps",
        "--device",
        device_id,
        "--include-all-apps",
        "--json-output",
        "-",
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    data = parse_devicectl_json(res.stdout)
    apps = data.get("result", {}).get("apps", [])
    user_apps = [
        a for a in apps if not a.get("bundleIdentifier", "").startswith("com.apple.")
    ]
    return sorted(user_apps, key=lambda x: x.get("name", "").lower())


def build_hud_env(
    preset: str | None,
    elements: str | None,
    align: str | None,
    scale: str | None,
    stream_web: str | None = None,
    opacity: str | None = None,
) -> dict[str, str]:
    env: dict[str, str] = {"MTL_HUD_ENABLED": "1"}
    effective_preset = preset.lower().strip() if preset else None
    raw_elements = elements

    if raw_elements is None and effective_preset:
        raw_elements = HUD_PRESETS.get(effective_preset)

    if stream_web:
        env["MTL_HUD_LOG_ENABLED"] = "1"
        if raw_elements is None and not effective_preset:
            raw_elements = HUD_PRESETS["fps-tiny"]
            if not scale:
                scale = "0.14"

    if effective_preset == "fps-tiny" and not scale:
        scale = "0.14"

    if raw_elements:
        cleaned = ",".join(
            part for part in (p.strip().lower() for p in raw_elements.split(","))
            if part.isalpha()
        )
        if cleaned:
            env["MTL_HUD_ELEMENTS"] = cleaned

    if align:
        cand = align.strip().lower()
        if cand in VALID_ALIGNMENTS:
            env["MTL_HUD_ALIGNMENT"] = cand

    if scale:
        try:
            val = float(scale.strip())
            if 0.0 < val <= 1.0:
                env["MTL_HUD_SCALE"] = f"{val:g}"
        except ValueError:
            pass

    if opacity is not None and opacity.strip() != "":
        try:
            val = float(opacity.strip())
            if 0.0 <= val <= 1.0:
                env["MTL_HUD_OPACITY"] = f"{val:g}"
        except ValueError:
            pass
    return env


def format_hud_summary(hud_env: dict[str, str]) -> str:
    parts = [f"{k}={v}" for k, v in hud_env.items() if k != "MTL_HUD_ENABLED"]
    return " | ".join(parts) if parts else "padrão completo Apple"


def find_tool(name: str) -> str | None:
    for cand in (
        shutil.which(name),
        f"/opt/homebrew/bin/{name}",
        f"/usr/local/bin/{name}",
    ):
        if cand and os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return None


def list_usbmux_udids(idevice_id_bin: str | None, network: bool = False) -> list[str]:
    if not idevice_id_bin:
        return []
    cmd = [idevice_id_bin, "-l", "-n"] if network else [idevice_id_bin, "-l"]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
    except Exception:
        return []
    if res.returncode != 0:
        return []
    return [line.strip() for line in res.stdout.splitlines() if line.strip()]


OSTRACE_SNIPPET = (
    "import sys, threading, time\n"
    "from pymobiledevice3.lockdown import create_using_tcp, create_using_usbmux\n"
    "from pymobiledevice3.services.os_trace import OsTraceService\n"
    "host = sys.argv[1]\n"
    "udid = sys.argv[2] or None\n"
    "def connect_ld():\n"
    "    try:\n"
    "        return create_using_usbmux(serial=udid) if udid else create_using_usbmux()\n"
    "    except Exception:\n"
    "        if host:\n"
    "            return create_using_tcp(hostname=host, identifier=udid)\n"
    "        raise\n"
    "locked_pid = -1\n"
    "while True:\n"
    "    svc = OsTraceService(connect_ld())\n"
    "    last_hud = [time.monotonic()]\n"
    "    closed = [False]\n"
    "    def watchdog(bound_svc, cur_pid):\n"
    "        while not closed[0] and cur_pid > 0:\n"
    "            time.sleep(5.0)\n"
    "            if not closed[0] and (time.monotonic() - last_hud[0]) > 15.0:\n"
    "                try:\n"
    "                    bound_svc.close()\n"
    "                except Exception:\n"
    "                    pass\n"
    "                break\n"
    "    if locked_pid > 0:\n"
    "        threading.Thread(target=watchdog, args=(svc, locked_pid), daemon=True).start()\n"
    "    switched_pid = False\n"
    "    try:\n"
    "        for entry in svc.syslog(pid=locked_pid):\n"
    "            msg = getattr(entry, 'message', '') or ''\n"
    "            if 'metal-HUD:' in msg:\n"
    "                last_hud[0] = time.monotonic()\n"
    "                ts = getattr(entry, 'timestamp', None)\n"
    "                tstr = ts.strftime('%H:%M:%S.%f') if ts else '00:00:00.000000'\n"
    "                print(f'{tstr} {msg}', flush=True)\n"
    "                if locked_pid == -1:\n"
    "                    ep = getattr(entry, 'pid', -1)\n"
    "                    if isinstance(ep, int) and ep > 0:\n"
    "                        locked_pid = ep\n"
    "                        switched_pid = True\n"
    "                        break\n"
    "    except KeyboardInterrupt:\n"
    "        break\n"
    "    except Exception:\n"
    "        if not switched_pid:\n"
    "            locked_pid = -1\n"
    "            time.sleep(1.0)\n"
    "    finally:\n"
    "        closed[0] = True\n"
    "        try:\n"
    "            svc.close()\n"
    "        except Exception:\n"
    "            pass\n"
)


def python_has_pymobiledevice3(py_bin: str) -> bool:
    try:
        res = subprocess.run(
            [py_bin, "-c", "import pymobiledevice3"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return res.returncode == 0
    except Exception:
        return False


def find_pymobiledevice3_python() -> str | None:
    candidates: list[str] = [
        sys.executable,
        os.path.expanduser("~/.arkdiehud-venv/bin/python3"),
        os.path.expanduser("~/.sidejit/bin/python3"),
    ]
    pmd_cli = find_tool("pymobiledevice3")
    if pmd_cli:
        cli_dir = os.path.dirname(pmd_cli)
        for py_name in ("python3", "python"):
            candidates.append(os.path.join(cli_dir, py_name))
        try:
            with open(pmd_cli, "r", encoding="utf-8", errors="ignore") as f:
                first_line = f.readline().strip()
            if first_line.startswith("#!"):
                shebang_py = first_line[2:].strip().split()[0]
                if os.path.basename(shebang_py).lower().startswith("python"):
                    candidates.append(shebang_py)
        except Exception:
            pass

    seen = set()
    for cand in candidates:
        if not cand or cand in seen:
            continue
        seen.add(cand)
        if os.path.isfile(cand) and os.access(cand, os.X_OK) and python_has_pymobiledevice3(cand):
            return cand
    return None


def pick_venv_base_python() -> str:
    for name in ("python3.14", "python3.13", "python3.12", "python3.11"):
        found = find_tool(name)
        if found:
            return found
    return sys.executable


def ensure_pymobiledevice3_python() -> str | None:
    existing = find_pymobiledevice3_python()
    if existing:
        return existing

    venv_dir = os.path.expanduser("~/.arkdiehud-venv")
    venv_py = os.path.join(venv_dir, "bin", "python3")
    if os.path.isfile(venv_py) and os.access(venv_py, os.X_OK) and python_has_pymobiledevice3(venv_py):
        return venv_py

    base_py = pick_venv_base_python()
    print(f"📦 Instalando pymobiledevice3 em {venv_dir} (apenas na primeira vez)...")
    try:
        subprocess.run([base_py, "-m", "venv", venv_dir], check=True, timeout=60)
        subprocess.run(
            [venv_py, "-m", "pip", "install", "--quiet", "pymobiledevice3"],
            check=True,
            timeout=180,
        )
    except Exception as exc:
        print(f"⚠️  Falha ao instalar pymobiledevice3 automaticamente: {exc}")
        return None

    return venv_py if python_has_pymobiledevice3(venv_py) else None


def resolve_syslog_command(udid: str, stream_web_url: str = "") -> list[str] | None:
    pmd_py = ensure_pymobiledevice3_python()
    if pmd_py:
        raw_host = urllib.parse.unquote((urllib.parse.urlparse(stream_web_url).hostname or "").strip())
        tcp_host = "" if raw_host in ("localhost", "127.0.0.1", "::1") else raw_host
        return [pmd_py, "-u", "-c", OSTRACE_SNIPPET, tcp_host, udid]

    syslog_bin = find_tool("idevicesyslog")
    idevice_id_bin = find_tool("idevice_id")
    if syslog_bin:
        if not idevice_id_bin:
            return [syslog_bin, "-u", udid]
        usb_udids = list_usbmux_udids(idevice_id_bin, network=False)
        if udid in usb_udids:
            return [syslog_bin, "-u", udid]
        net_udids = list_usbmux_udids(idevice_id_bin, network=True)
        if udid in net_udids:
            return [syslog_bin, "-n", "-u", udid]
    return None


def parse_syslog_seconds(line: str) -> float:
    m = SYSLOG_TIME_RE.search(line)
    if not m:
        return time.monotonic()
    hh, mm, ss, frac = m.groups()
    return int(hh) * 3600 + int(mm) * 60 + int(ss) + float("0." + frac)


def post_metal_hud_sample(
    endpoint_url: str,
    fps: float,
    frame_time_ms: float,
    vram_mb: float,
    ram_mb: float,
    game_name: str,
    bundle_id: str,
) -> None:
    payload = json.dumps(
        {
            "fps": fps,
            "frameTimeMs": frame_time_ms,
            "vramMB": vram_mb,
            "ramMB": ram_mb,
            "gameName": game_name,
            "bundleId": bundle_id,
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        endpoint_url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=2.0) as resp:
            resp.read()
    except Exception:
        pass


def stream_metal_hud_to_web(
    udid: str,
    app_name: str,
    bundle_id: str,
    stream_web_url: str,
    max_seconds: float | None = None,
) -> None:
    endpoint = stream_web_url.rstrip("/") + "/api/metal-hud"
    cmd = resolve_syslog_command(udid, stream_web_url)
    if not cmd:
        print("\n⚠️  Não foi possível capturar o syslog do iPhone/iPad para enviar FPS ao painel Web.")
        print("Como liberar o envio de FPS em tempo real:")
        print("  1) Conecte o iPhone/iPad pelo cabo USB no Mac (mais estável), OU")
        print("  2) No Finder com o cabo conectado 1 vez, marque: 'Mostrar este iPad/iPhone quando estiver na rede Wi-Fi' (habilita idevicesyslog -n sem fio), OU")
        print("  3) Instale o pymobiledevice3: python3 -m pip install pymobiledevice3")
        print("✅ O Metal HUD no aparelho continua ativo normalmente.")
        return

    print(f"📡 Transmitindo FPS + VRAM + RAM para {endpoint} (Control+C para encerrar)")
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
    )
    timer = None
    if max_seconds and max_seconds > 0:
        timer = threading.Timer(max_seconds, proc.terminate)
        timer.daemon = True
        timer.start()

    prev_frame: int | None = None
    prev_ts: float | None = None
    recent_err_lines: list[str] = []
    try:
        if proc.stdout is None:
            return
        for raw_line in proc.stdout:
            if "metal-HUD:" not in raw_line:
                stripped = raw_line.strip()
                if stripped:
                    recent_err_lines.append(stripped)
                    if len(recent_err_lines) > 5:
                        recent_err_lines.pop(0)
                continue
            m = METAL_HUD_LINE_RE.search(raw_line)
            if not m:
                continue
            frame_num = int(m.group(1))
            vram_mb = float(m.group(2))
            ram_mb = float(m.group(3))
            ts = parse_syslog_seconds(raw_line)

            if prev_frame is not None and prev_ts is not None:
                dt = ts - prev_ts
                if dt < -43200:
                    dt += 86400
                delta_frames = frame_num - prev_frame
                if delta_frames > 0 and 0.2 <= dt <= 10.0:
                    fps = min(240.0, round(delta_frames / dt, 1))
                    frame_ms = round(1000.0 / fps, 2) if fps > 0 else 0.0
                    print(
                        f"  🎮 {app_name}: {fps:.1f} FPS | {frame_ms:.1f} ms | VRAM {vram_mb:.1f} MB | RAM {ram_mb:.1f} MB",
                        flush=True,
                    )
                    post_metal_hud_sample(endpoint, fps, frame_ms, vram_mb, ram_mb, app_name, bundle_id)

            prev_frame = frame_num
            prev_ts = ts
        rc = proc.wait()
        if rc != 0 and prev_frame is None and recent_err_lines:
            print(f"⚠️  Ponte syslog encerrou (código {rc}): {recent_err_lines[-1]}")
    except KeyboardInterrupt:
        print("\n⏹️ Transmissão encerrada.")
    finally:
        if timer is not None:
            timer.cancel()
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()


def launch_app(
    device_id: str,
    name: str,
    bundle_id: str,
    hud_env: dict[str, str],
    stream_web: str | None = None,
    stream_seconds: float | None = None,
) -> None:
    print(f"\n🚀 Iniciando {name} ({bundle_id}) com o Apple Metal HUD ({format_hud_summary(hud_env)})...")
    cmd = [
        "xcrun",
        "devicectl",
        "device",
        "process",
        "launch",
        "-e",
        json.dumps(hud_env),
        "--device",
        device_id,
        "--terminate-existing",
        bundle_id,
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    output = res.stdout + res.stderr
    if "Locked" in output:
        print("⚠️  O dispositivo está BLOQUEADO com a tela apagada.")
        print("👉 Desbloqueie a tela e tente novamente!")
        sys.exit(1)
    elif res.returncode != 0 or "ERROR" in output:
        print("❌ Erro ao iniciar:")
        print(output.strip())
        sys.exit(1)
    else:
        print(f"✅ {name} iniciado com sucesso no dispositivo!")
        if hud_env.get("MTL_HUD_OPACITY") == "0":
            print("👻 Modo Invisível ativo na tela (MTL_HUD_OPACITY=0).")
            print(
                "💡 Para continuar 100% invisível ao sair/voltar do jogo: ative Ajustes -> Privacidade e Segurança -> Modo Desenvolvedor, abra Ajustes -> Desenvolvedor -> HUD Metal (Mostrar HUD desligado) e arraste Opacidade para 0%.\n"
            )
        else:
            print("📊 O Metal Performance HUD oficial da Apple já está ativo na tela! (Dica: em Ajustes -> Desenvolvedor -> HUD Metal, deixe Escala mínima + só FPS em Métricas + Registrar Desempenho ligado para continuar pequeno ao sair/voltar do jogo).\n")
        if stream_web:
            stream_metal_hud_to_web(device_id, name, bundle_id, stream_web, stream_seconds)


def print_help() -> None:
    print(
        """Uso: ./launch_metal_hud.sh [OPÇÕES] [ATALHO_OU_BUSCA]

Opções:
  --help, -h             Exibe este guia de uso e exemplos
  --devices              Lista os iPads/iPhones físicos pareados e mostra o padrão detectado
  --device <UDID>        Força o lançamento em um UDID específico (ou defina METAL_HUD_DEVICE_ID)
  --list                 Lista todos os apps/jogos instalados no iPad com seus Bundle IDs exatos
  --bundle <BUNDLE_ID>   Inicia diretamente qualquer app pelo Bundle ID (ex: com.miHoYo.GenshinImpact)
  --preset <NOME>        Preset: fps-tiny, fps-gpu, minimal, fps-only, full
  --elements <CSV>       Métricas MTL_HUD_ELEMENTS (ex: fps,gputime,fpsgraph,frameintervalgraph)
  --align <POS>          Posição: topleft, topright, topcenter, bottomleft, bottomright, ...
  --scale <0.0-1.0>      Tamanho do HUD (ex: 0.14, 0.18, 0.22)
  --opacity <0.0-1.0>    Opacidade do HUD (0 = invisivel na tela, envia FPS so ao Web)
  --stream-web <URL>     Lê metal-HUD do syslog e envia FPS/VRAM/RAM ao servidor :8787
  --stream-seconds <N>   Encerra transmissão após N segundos (opcional)

Atalhos rápidos e busca:
  flash | fit            PUBGM FLASH (com.tencent.igfit)
  pubg | global          PUBG MOBILE (com.tencent.ig)
  davinci | resolve      DaVinci Resolve (com.blackmagic-design.DaVinciResolveiPad)
  <termo>                Busca automaticamente por nome ou Bundle ID (ex: genshin, cod, capcut)

Dica de personalização (manual ou via IA):
  1) Rode `./launch_metal_hud.sh --list` para descobrir o Bundle ID de qualquer jogo/app.
  2) Adicione em `CUSTOM_SHORTCUTS` no topo de `launch_metal_hud.sh` ou passe `--bundle <ID>`.

Sem argumentos: lista todos os apps do iPad para escolha numérica interativa."""
    )


def print_devices() -> None:
    devices = list_physical_devices()
    if not devices:
        print("⚠️  Nenhum dispositivo físico pareado encontrado.")
        return

    print("📱 Dispositivos Físicos Pareados (conectados primeiro):")
    for idx, dev in enumerate(devices):
        badge = " [SELECIONADO POR PADRÃO]" if idx == 0 else ""
        kind = "iPad" if dev["is_ipad"] else "iPhone"
        print(
            f"  • {dev['name']} ({kind}, {dev['productType']}, {dev['transport']}) | tunnel={dev['tunnelState']} | UDID={dev['udid']}{badge}"
        )


def parse_args(argv: list[str]) -> tuple[bool, bool, bool, str | None, str | None, str | None, str | None, str | None, str | None, str | None, str | None, float | None, str | None]:
    show_help = False
    show_devices = False
    list_apps = False
    cli_device = None
    cli_bundle = None
    cli_preset = None
    cli_elements = None
    cli_align = None
    cli_scale = None
    cli_opacity = None
    cli_stream_web = None
    cli_stream_seconds = None
    positional = None

    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("-h", "--help"):
            show_help = True
        elif arg == "--devices":
            show_devices = True
        elif arg == "--list":
            list_apps = True
        elif arg == "--bundle":
            if i + 1 >= len(argv):
                print("❌ Faltou informar o Bundle ID após --bundle.")
                sys.exit(2)
            cli_bundle = argv[i + 1].strip()
            i += 1
        elif arg.startswith("--bundle="):
            cli_bundle = arg.split("=", 1)[1].strip()
        elif arg == "--device":
            if i + 1 >= len(argv):
                print("❌ Faltou informar o UDID após --device.")
                sys.exit(2)
            cli_device = argv[i + 1].strip()
            i += 1
        elif arg.startswith("--device="):
            cli_device = arg.split("=", 1)[1].strip()
        elif arg == "--preset" and i + 1 < len(argv):
            cli_preset = argv[i + 1].strip()
            i += 1
        elif arg.startswith("--preset="):
            cli_preset = arg.split("=", 1)[1].strip()
        elif arg == "--elements" and i + 1 < len(argv):
            cli_elements = argv[i + 1].strip()
            i += 1
        elif arg.startswith("--elements="):
            cli_elements = arg.split("=", 1)[1].strip()
        elif arg == "--align" and i + 1 < len(argv):
            cli_align = argv[i + 1].strip()
            i += 1
        elif arg.startswith("--align="):
            cli_align = arg.split("=", 1)[1].strip()
        elif arg == "--scale" and i + 1 < len(argv):
            cli_scale = argv[i + 1].strip()
            i += 1
        elif arg.startswith("--scale="):
            cli_scale = arg.split("=", 1)[1].strip()
        elif arg == "--opacity" and i + 1 < len(argv):
            cli_opacity = argv[i + 1].strip()
            i += 1
        elif arg.startswith("--opacity="):
            cli_opacity = arg.split("=", 1)[1].strip()
        elif arg == "--stream-web" and i + 1 < len(argv):
            cli_stream_web = argv[i + 1].strip()
            i += 1
        elif arg.startswith("--stream-web="):
            cli_stream_web = arg.split("=", 1)[1].strip()
        elif arg == "--stream-seconds" and i + 1 < len(argv):
            try:
                cli_stream_seconds = float(argv[i + 1].strip())
            except ValueError:
                cli_stream_seconds = None
            i += 1
        elif arg.startswith("--stream-seconds="):
            try:
                cli_stream_seconds = float(arg.split("=", 1)[1].strip())
            except ValueError:
                cli_stream_seconds = None
        else:
            positional = arg.lower().strip()
        i += 1

    return show_help, show_devices, list_apps, cli_device, cli_bundle, cli_preset, cli_elements, cli_align, cli_scale, cli_opacity, cli_stream_web, cli_stream_seconds, positional


def main() -> None:
    show_help, show_devices, list_apps, cli_device, cli_bundle, cli_preset, cli_elements, cli_align, cli_scale, cli_opacity, cli_stream_web, cli_stream_seconds, arg = parse_args(sys.argv[1:])

    if show_help:
        print_help()
        return

    if show_devices:
        print_devices()
        return

    hud_env = build_hud_env(cli_preset, cli_elements, cli_align, cli_scale, cli_stream_web, cli_opacity)
    device_id, device_label = resolve_device_id(cli_device)
    print(f"🎯 Alvo detectado: {device_label}")

    if cli_bundle:
        launch_app(device_id, cli_bundle, cli_bundle, hud_env, cli_stream_web, cli_stream_seconds)
        return

    if not list_apps and arg and arg in CUSTOM_SHORTCUTS:
        name, bundle_id = CUSTOM_SHORTCUTS[arg]
        launch_app(device_id, name, bundle_id, hud_env, cli_stream_web, cli_stream_seconds)
        return

    print("🔍 Carregando lista de jogos e aplicativos instalados...")
    apps = get_installed_apps(device_id)
    if not apps:
        print("⚠️  Nenhum aplicativo de usuário encontrado ou o dispositivo está indisponível.")
        sys.exit(1)

    priority_ids = [bid for bid, _ in PRIORITY_APPS]
    priority_apps = [a for a in apps if a.get("bundleIdentifier") in priority_ids]
    other_apps = [a for a in apps if a.get("bundleIdentifier") not in priority_ids]

    ordered_priority = []
    for pid in priority_ids:
        match = next((a for a in priority_apps if a.get("bundleIdentifier") == pid), None)
        if match:
            ordered_priority.append(match)

    all_apps = ordered_priority + other_apps

    if list_apps:
        print("\n📱 Aplicativos e Bundle IDs Instalados no Dispositivo:")
        print("------------------------------------------------------------------")
        for idx, app in enumerate(all_apps, 1):
            name = app.get("name", "Sem Nome")
            bundle_id = app.get("bundleIdentifier", "")
            print(f"  [{idx:2d}] {name:<26} {bundle_id}")
        print("------------------------------------------------------------------")
        print("👉 Use `./launch_metal_hud.sh --bundle <BUNDLE_ID>` ou adicione em `CUSTOM_SHORTCUTS`.\n")
        return

    if arg:
        exact_bundle = next(
            (a for a in all_apps if a.get("bundleIdentifier", "").lower() == arg),
            None,
        )
        if exact_bundle:
            launch_app(
                device_id,
                exact_bundle.get("name", arg),
                exact_bundle.get("bundleIdentifier", arg),
                hud_env,
                cli_stream_web,
                cli_stream_seconds,
            )
            return
        matched = [
            a
            for a in all_apps
            if arg in a.get("name", "").lower() or arg in a.get("bundleIdentifier", "").lower()
        ]
        if matched:
            target = matched[0]
            launch_app(
                device_id,
                target.get("name", arg),
                target.get("bundleIdentifier", ""),
                hud_env,
                cli_stream_web,
                cli_stream_seconds,
            )
            return
        print(f"⚠️  Nenhum aplicativo correspondente a '{arg}'. Exibindo lista completa:")

    print("\n📱 Aplicativos Disponíveis no Dispositivo:")
    print("------------------------------------------------------------------")
    for idx, app in enumerate(all_apps, 1):
        name = app.get("name", "Sem Nome")
        bundle_id = app.get("bundleIdentifier", "")
        star = " ⭐ (JOGO)" if "tencent" in bundle_id else ""
        print(f"  [{idx:2d}] {name:<22} ({bundle_id}){star}")
    print("------------------------------------------------------------------")

    try:
        choice = input("👉 Escolha o número do app (ou aperte ENTER para o item [1]): ").strip()
    except (KeyboardInterrupt, EOFError):
        print("\nCancelado.")
        return

    if not choice:
        idx = 0
    else:
        try:
            idx = int(choice) - 1
            if idx < 0 or idx >= len(all_apps):
                print("❌ Opção fora do intervalo.")
                return
        except ValueError:
            print("❌ Entrada inválida.")
            return

    target = all_apps[idx]
    launch_app(
        device_id,
        target.get("name", "App"),
        target.get("bundleIdentifier", ""),
        hud_env,
        cli_stream_web,
        cli_stream_seconds,
    )


if __name__ == "__main__":
    main()
