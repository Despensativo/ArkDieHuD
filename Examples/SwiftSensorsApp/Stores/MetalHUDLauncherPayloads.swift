import Foundation

/// Self-hosted macOS / Windows Metal HUD launcher scripts served directly from
/// ArkDieHuD's built-in `:8787` web dashboard (`TelemetryWebServer`).
enum MetalHUDLauncherPayloads {
    static var macCommandScript: String {
        self.crossPlatformPythonScript
    }

    static func windowsBatchScript(
        serverHost: String?,
        elements: String? = nil,
        align: String? = nil,
        scale: String? = nil
    ) -> String {
        let sanitizedHost = self.sanitizeHost(serverHost)
        let pyURL = "http://\(sanitizedHost)/download/arkdiehud_metal_hud.py"
        var extraArgs: [String] = []
        if let cleanElements = self.sanitizeElements(elements) {
            extraArgs.append("--elements \(cleanElements)")
        }
        if let cleanAlign = self.sanitizeAlign(align) {
            extraArgs.append("--align \(cleanAlign)")
        }
        if let cleanScale = self.sanitizeScale(scale) {
            extraArgs.append("--scale \(cleanScale)")
        }
        let argsSuffix = extraArgs.isEmpty ? "" : " " + extraArgs.joined(separator: " ")

        let lines = [
            "@echo off",
            "chcp 65001 >nul",
            "title ArkDieHuD - Apple Metal FPS HUD (Windows)",
            "",
            "net session >nul 2>&1",
            "if %errorlevel% neq 0 (",
            "    echo Solicitando permissao de Administrador para o tunel USB iOS 17+...",
            "    powershell -NoProfile -Command \"Start-Process -FilePath '%~f0' -Verb RunAs\"",
            "    exit /b",
            ")",
            "",
            "cd /d \"%~dp0\"",
            "set \"PY_CMD=\"",
            "py -3 --version >nul 2>&1 && set \"PY_CMD=py -3\"",
            "if not defined PY_CMD (",
            "    python --version >nul 2>&1 && set \"PY_CMD=python\"",
            ")",
            "if not defined PY_CMD (",
            "    echo [ERRO] Python 3 nao encontrado no PATH.",
            "    echo Instale em https://www.python.org/downloads/ marcando 'Add python.exe to PATH'.",
            "    pause",
            "    exit /b 1",
            ")",
            "",
            "echo Baixando launcher atualizado do ArkDieHuD...",
            "curl.exe -fsSL \"\(pyURL)\" -o \"%~dp0arkdiehud_metal_hud.py\" || (",
            "    curl.exe -fsSL \"https://raw.githubusercontent.com/Despensativo/ArkDieHuD/main/Scripts/arkdiehud_metal_hud.py\" -o \"%~dp0arkdiehud_metal_hud.py\"",
            ")",
            "if not exist \"%~dp0arkdiehud_metal_hud.py\" (",
            "    echo [ERRO] Nao foi possivel baixar arkdiehud_metal_hud.py.",
            "    pause",
            "    exit /b 1",
            ")",
            "",
            "%PY_CMD% -m pymobiledevice3 version >nul 2>&1",
            "if %errorlevel% neq 0 (",
            "    echo Instalando pymobiledevice3...",
            "    %PY_CMD% -m pip install --upgrade pymobiledevice3",
            ")",
            "",
            "%PY_CMD% \"%~dp0arkdiehud_metal_hud.py\" --pause\(argsSuffix)",
            "pause",
        ]
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func sanitizeHost(_ rawHost: String?) -> String {
        guard let rawHost else { return "127.0.0.1:8787" }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-:[]")
        let filtered = String(rawHost.unicodeScalars.filter { allowed.contains($0) })
        return filtered.isEmpty ? "127.0.0.1:8787" : filtered
    }

    private static func sanitizeElements(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz,")
        let filtered = String(raw.lowercased().unicodeScalars.filter { allowed.contains($0) })
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: ",")
        return filtered.isEmpty ? nil : filtered
    }

    private static func sanitizeAlign(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        let filtered = String(raw.lowercased().unicodeScalars.filter { allowed.contains($0) })
        return filtered.isEmpty ? nil : filtered
    }

    private static func sanitizeScale(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789.")
        let filtered = String(raw.unicodeScalars.filter { allowed.contains($0) })
        guard let num = Double(filtered), num > 0.0, num <= 1.0 else { return nil }
        return filtered
    }

    static let crossPlatformPythonScript: String = ##"""
#!/usr/bin/env python3
"""
ArkDieHuD — Apple Metal Performance HUD Launcher (macOS / Windows / Linux)
Ativa o contador oficial da Apple (MTL_HUD_ENABLED=1) em qualquer app ou jogo
no iPhone/iPad (FPS, GPU e Frame Time) via `xcrun devicectl` (macOS, Wi-Fi/USB)
ou `pymobiledevice3` (Windows/Linux ou Mac sem Xcode).
"""

import atexit
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from typing import Dict, List, Optional, Tuple


PRIORITY_APPS = [
    ("com.tencent.igfit", "PUBGM FLASH"),
    ("com.tencent.ig", "PUBG MOBILE"),
    ("com.blackmagic-design.DaVinciResolveiPad", "DaVinci Resolve"),
]

HUD_PRESETS: Dict[str, str] = {
    "fps-gpu": "fps,gputime,fpsgraph,frameintervalgraph",
    "minimal": "fps,gputime",
    "fps-only": "fps,fpsgraph",
    "full": "",
}

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

CUSTOM_SHORTCUTS: Dict[str, Tuple[str, str]] = {
    "pubg": ("PUBG MOBILE", "com.tencent.ig"),
    "pubgm": ("PUBG MOBILE", "com.tencent.ig"),
    "global": ("PUBG MOBILE", "com.tencent.ig"),
    "flash": ("PUBGM FLASH", "com.tencent.igfit"),
    "fit": ("PUBGM FLASH", "com.tencent.igfit"),
    "pubgflash": ("PUBGM FLASH", "com.tencent.igfit"),
    "pubgmflash": ("PUBGM FLASH", "com.tencent.igfit"),
    "davinci": ("DaVinci Resolve", "com.blackmagic-design.DaVinciResolveiPad"),
    "resolve": ("DaVinci Resolve", "com.blackmagic-design.DaVinciResolveiPad"),
}


def build_hud_env(
    preset: Optional[str],
    elements: Optional[str],
    align: Optional[str],
    scale: Optional[str],
) -> Dict[str, str]:
    env: Dict[str, str] = {"MTL_HUD_ENABLED": "1"}
    raw_elements: Optional[str] = elements
    if raw_elements is None and preset:
        raw_elements = HUD_PRESETS.get(preset.lower().strip())
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
    return env


def format_hud_summary(hud_env: Dict[str, str]) -> str:
    parts = [f"{k}={v}" for k, v in hud_env.items() if k != "MTL_HUD_ENABLED"]
    return " | ".join(parts) if parts else "padrao completo Apple"


def setup_pause_if_needed(force_pause: bool) -> None:
    is_command = os.path.basename(__file__).lower().endswith(".command")
    if not (force_pause or is_command):
        return

    def _wait() -> None:
        try:
            input("\nPressione ENTER para fechar...")
        except (KeyboardInterrupt, EOFError):
            pass

    atexit.register(_wait)


def parse_json_payload(stdout: str) -> object:
    obj_idx = stdout.find("{")
    arr_idx = stdout.find("[")
    starts = [idx for idx in (obj_idx, arr_idx) if idx != -1]
    if not starts:
        return {}
    try:
        return json.loads(stdout[min(starts) :])
    except json.JSONDecodeError:
        return {}


def has_devicectl() -> bool:
    if platform.system() != "Darwin" or not shutil.which("xcrun"):
        return False
    res = subprocess.run(
        ["xcrun", "--find", "devicectl"],
        capture_output=True,
        text=True,
    )
    return res.returncode == 0


def devicectl_list_physical_devices() -> List[dict]:
    cmd = ["xcrun", "devicectl", "list", "devices", "--json-output", "-"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    data = parse_json_payload(res.stdout)
    if not isinstance(data, dict):
        return []
    devices = data.get("result", {}).get("devices", [])

    physical: List[dict] = []
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


def devicectl_get_apps(device_id: str) -> List[dict]:
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
    data = parse_json_payload(res.stdout)
    if not isinstance(data, dict):
        return []
    apps = data.get("result", {}).get("apps", [])
    user_apps = [
        a for a in apps if not a.get("bundleIdentifier", "").startswith("com.apple.")
    ]
    return sorted(user_apps, key=lambda x: x.get("name", "").lower())


def devicectl_launch(device_id: str, name: str, bundle_id: str, hud_env: Dict[str, str]) -> None:
    print(f"\n[>>] Iniciando {name} ({bundle_id}) com Apple Metal HUD ({format_hud_summary(hud_env)})...")
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
        print("[!] O dispositivo está BLOQUEADO com a tela apagada.")
        print("-> Desbloqueie a tela e tente novamente!")
        sys.exit(1)
    if res.returncode != 0 or "ERROR" in output:
        print("[ERRO] Erro ao iniciar:")
        print(output.strip())
        sys.exit(1)
    print(f"[OK] {name} iniciado com sucesso!")
    print("[HUD] Apple Metal Performance HUD (FPS / GPU / Frame Time) ativo na tela.\n")


def ensure_pymobiledevice3() -> bool:
    check = subprocess.run(
        [sys.executable, "-m", "pymobiledevice3", "version"],
        capture_output=True,
        text=True,
    )
    if check.returncode == 0:
        return True

    print("[!] Pacote 'pymobiledevice3' não encontrado neste Python.")
    try:
        ans = input("-> Deseja instalar automaticamente agora via pip? [S/n]: ").strip().lower()
    except (KeyboardInterrupt, EOFError):
        return False
    if ans in ("", "s", "sim", "y", "yes"):
        inst = subprocess.run(
            [sys.executable, "-m", "pip", "install", "--upgrade", "pymobiledevice3"]
        )
        return inst.returncode == 0
    return False


def pmd_tunneld_reachable() -> bool:
    try:
        with urllib.request.urlopen("http://127.0.0.1:49151/", timeout=1.5) as resp:
            return resp.status < 500
    except Exception:
        return False


def pmd_get_apps(cli_device: Optional[str]) -> List[dict]:
    cmd = [sys.executable, "-m", "pymobiledevice3", "apps", "list", "--type", "User"]
    if cli_device:
        cmd.extend(["--udid", cli_device])
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print("[ERRO] Não foi possível listar os apps via pymobiledevice3.")
        print(res.stderr.strip() or res.stdout.strip())
        print("-> No Windows: conecte o cabo USB, desbloqueie o aparelho, confirme 'Confiar'")
        print("   e verifique se o app 'Dispositivos Apple' (ou iTunes) está instalado.")
        return []

    data = parse_json_payload(res.stdout)
    apps: List[dict] = []
    if isinstance(data, dict):
        for bundle_id, info in data.items():
            if bundle_id.startswith("com.apple."):
                continue
            display_name = bundle_id
            if isinstance(info, dict):
                display_name = (
                    info.get("CFBundleDisplayName")
                    or info.get("CFBundleName")
                    or info.get("CFBundleExecutable")
                    or bundle_id
                )
            apps.append({"name": str(display_name), "bundleIdentifier": str(bundle_id)})
    return sorted(apps, key=lambda x: x.get("name", "").lower())


def pmd_env_args(hud_env: Dict[str, str]) -> List[str]:
    args: List[str] = []
    for key, val in hud_env.items():
        args.extend(["--env", key, val])
    return args


def pmd_launch_with_tunnel(
    name: str,
    bundle_id: str,
    cli_device: Optional[str],
    hud_env: Dict[str, str],
) -> None:
    print(f"\n[>>] Iniciando {name} ({bundle_id}) via pymobiledevice3 ({format_hud_summary(hud_env)})...")

    if pmd_tunneld_reachable():
        mount_cmd = [sys.executable, "-m", "pymobiledevice3", "mounter", "auto-mount", "--tunnel", ""]
        launch_cmd = [
            sys.executable,
            "-m",
            "pymobiledevice3",
            "developer",
            "dvt",
            "launch",
            bundle_id,
            "--tunnel",
            cli_device or "",
            *pmd_env_args(hud_env),
            "--kill-existing",
        ]
        subprocess.run(mount_cmd, capture_output=True, text=True)
        res = subprocess.run(launch_cmd, capture_output=True, text=True)
        if res.returncode != 0:
            print("[ERRO] Erro ao abrir app via tunneld:")
            print((res.stdout + "\n" + res.stderr).strip())
            sys.exit(1)
        print(f"[OK] {name} iniciado com Apple Metal HUD!")
        return

    print("[USB] Abrindo túnel iOS 17+ (pode exigir terminal como Administrador no Windows)...")
    tunnel_cmd = [sys.executable, "-m", "pymobiledevice3", "remote", "start-tunnel"]
    if cli_device:
        tunnel_cmd.extend(["--udid", cli_device])

    proc = subprocess.Popen(
        tunnel_cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    rsd_host: Optional[str] = None
    rsd_port: Optional[str] = None
    captured: List[str] = []

    try:
        deadline = time.time() + 20.0
        while time.time() < deadline and proc.poll() is None:
            if proc.stdout is None:
                break
            line = proc.stdout.readline()
            if not line:
                time.sleep(0.1)
                continue
            captured.append(line.strip())

            m_inline = re.search(r"--rsd\s+(\S+)\s+(\d+)", line)
            if m_inline:
                rsd_host, rsd_port = m_inline.group(1), m_inline.group(2)
                break

            m_addr = re.search(r"RSD Address:\s*(\S+)", line)
            if m_addr:
                rsd_host = m_addr.group(1)
            m_port = re.search(r"RSD Port:\s*(\d+)", line)
            if m_port:
                rsd_port = m_port.group(1)
            if rsd_host and rsd_port:
                break

        if not (rsd_host and rsd_port):
            print("[ERRO] Não foi possível estabelecer o túnel iOS 17+ (RSD).")
            if captured:
                print("\n".join(captured[-10:]))
            print("-> No Windows: clique com o botão direito no .bat -> Executar como Administrador.")
            print("   Confira também se o Modo Desenvolvedor está ativo no iPhone/iPad.")
            sys.exit(1)

        subprocess.run(
            [
                sys.executable,
                "-m",
                "pymobiledevice3",
                "mounter",
                "auto-mount",
                "--rsd",
                rsd_host,
                rsd_port,
            ],
            capture_output=True,
            text=True,
        )

        launch_cmd = [
            sys.executable,
            "-m",
            "pymobiledevice3",
            "developer",
            "dvt",
            "launch",
            bundle_id,
            "--rsd",
            rsd_host,
            rsd_port,
            *pmd_env_args(hud_env),
            "--kill-existing",
        ]
        res = subprocess.run(launch_cmd, capture_output=True, text=True)
        if res.returncode != 0:
            print("[ERRO] Erro ao iniciar com Metal HUD:")
            print((res.stdout + "\n" + res.stderr).strip())
            sys.exit(1)

        time.sleep(2.0)
        print(f"[OK] {name} iniciado com sucesso!")
        print("[HUD] Apple Metal Performance HUD (FPS / GPU / Frame Time) ativo na tela.\n")
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()


def order_apps(apps: List[dict]) -> List[dict]:
    priority_ids = [bid for bid, _ in PRIORITY_APPS]
    priority_apps = [a for a in apps if a.get("bundleIdentifier") in priority_ids]
    other_apps = [a for a in apps if a.get("bundleIdentifier") not in priority_ids]
    ordered_priority: List[dict] = []
    for pid in priority_ids:
        match = next((a for a in priority_apps if a.get("bundleIdentifier") == pid), None)
        if match:
            ordered_priority.append(match)
    return ordered_priority + other_apps


def pick_and_launch(
    all_apps: List[dict],
    arg: Optional[str],
    launcher_fn,
) -> None:
    if arg:
        exact = next(
            (a for a in all_apps if a.get("bundleIdentifier", "").lower() == arg),
            None,
        )
        if exact:
            launcher_fn(exact.get("name", arg), exact.get("bundleIdentifier", arg))
            return
        matched = [
            a
            for a in all_apps
            if arg in a.get("name", "").lower() or arg in a.get("bundleIdentifier", "").lower()
        ]
        if matched:
            target = matched[0]
            launcher_fn(target.get("name", arg), target.get("bundleIdentifier", ""))
            return
        print(f"[!] Nenhum aplicativo correspondente a '{arg}'. Exibindo lista completa:")

    print("\n[APPS] Aplicativos Disponíveis no Dispositivo:")
    print("------------------------------------------------------------------")
    for idx, app in enumerate(all_apps, 1):
        name = app.get("name", "Sem Nome")
        bundle_id = app.get("bundleIdentifier", "")
        star = " * (JOGO)" if "tencent" in bundle_id else ""
        print(f"  [{idx:2d}] {name:<24} ({bundle_id}){star}")
    print("------------------------------------------------------------------")

    try:
        choice = input("-> Escolha o número do app (ou aperte ENTER para o item [1]): ").strip()
    except (KeyboardInterrupt, EOFError):
        print("\nCancelado.")
        return

    if not choice:
        idx = 0
    else:
        try:
            idx = int(choice) - 1
            if idx < 0 or idx >= len(all_apps):
                print("[ERRO] Opção fora do intervalo.")
                return
        except ValueError:
            print("[ERRO] Entrada inválida.")
            return

    target = all_apps[idx]
    launcher_fn(target.get("name", "App"), target.get("bundleIdentifier", ""))


def print_help() -> None:
    print(
        """Uso: arkdiehud_metal_hud.py [OPÇÕES] [ATALHO_OU_BUSCA]

Opções:
  --help, -h             Exibe este guia de uso
  --devices              Lista dispositivos pareados (macOS devicectl)
  --device <UDID>        Força um UDID específico (ou defina METAL_HUD_DEVICE_ID)
  --list                 Lista todos os apps/jogos com Bundle IDs
  --bundle <BUNDLE_ID>   Inicia diretamente pelo Bundle ID
  --preset <NOME>        Preset: fps-gpu, minimal, fps-only, full
  --elements <CSV>       Métricas MTL_HUD_ELEMENTS (ex: fps,gputime,fpsgraph,frameintervalgraph)
  --align <POS>          Posição: topleft, topright, topcenter, bottomleft, bottomright, ...
  --scale <0.0-1.0>      Tamanho do HUD (ex: 0.14, 0.18, 0.22)
  --pause                Aguarda ENTER antes de fechar"""
    )


def main() -> None:
    show_help = False
    show_devices = False
    list_apps = False
    force_pause = False
    cli_device: Optional[str] = None
    cli_bundle: Optional[str] = None
    cli_preset: Optional[str] = None
    cli_elements: Optional[str] = None
    cli_align: Optional[str] = None
    cli_scale: Optional[str] = None
    positional: Optional[str] = None

    argv = sys.argv[1:]
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("-h", "--help"):
            show_help = True
        elif arg == "--devices":
            show_devices = True
        elif arg == "--list":
            list_apps = True
        elif arg == "--pause":
            force_pause = True
        elif arg == "--bundle" and i + 1 < len(argv):
            cli_bundle = argv[i + 1].strip()
            i += 1
        elif arg.startswith("--bundle="):
            cli_bundle = arg.split("=", 1)[1].strip()
        elif arg == "--device" and i + 1 < len(argv):
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
        else:
            positional = arg.lower().strip()
        i += 1

    setup_pause_if_needed(force_pause)

    if show_help:
        print_help()
        return

    hud_env = build_hud_env(cli_preset, cli_elements, cli_align, cli_scale)
    env_device = os.environ.get("METAL_HUD_DEVICE_ID", "").strip()
    target_device = cli_device or env_device or None

    if has_devicectl():
        devices = devicectl_list_physical_devices()
        if show_devices:
            if not devices:
                print("[!] Nenhum dispositivo físico pareado encontrado.")
                return
            print("[APPS] Dispositivos Físicos Pareados (conectados primeiro):")
            for idx, dev in enumerate(devices):
                badge = " [SELECIONADO POR PADRÃO]" if idx == 0 else ""
                kind = "iPad" if dev["is_ipad"] else "iPhone"
                print(
                    f"  • {dev['name']} ({kind}, {dev['productType']}, {dev['transport']}) | tunnel={dev['tunnelState']} | UDID={dev['udid']}{badge}"
                )
            return

        if not target_device:
            if not devices:
                print("[!] Nenhum iPad/iPhone pareado encontrado via devicectl.")
                print("-> Conecte via Wi-Fi ou USB-C, desbloqueie a tela e tente novamente.")
                sys.exit(1)
            selected = devices[0]
            target_device = selected["udid"]
            label = f"{selected['name']} ({selected['productType'] or 'iOS'}, {selected['transport']}, tunnel={selected['tunnelState']})"
        else:
            label = target_device

        print(f"[ALVO] Alvo detectado: {label}")

        if cli_bundle:
            devicectl_launch(target_device, cli_bundle, cli_bundle, hud_env)
            return
        if not list_apps and positional and positional in CUSTOM_SHORTCUTS:
            name, bundle_id = CUSTOM_SHORTCUTS[positional]
            devicectl_launch(target_device, name, bundle_id, hud_env)
            return

        print("[...] Carregando lista de jogos e aplicativos instalados...")
        apps = order_apps(devicectl_get_apps(target_device))
        if not apps:
            print("[!] Nenhum aplicativo de usuário encontrado ou o dispositivo está indisponível.")
            sys.exit(1)

        if list_apps:
            for idx, app in enumerate(apps, 1):
                print(f"  [{idx:2d}] {app.get('name', 'Sem Nome'):<26} {app.get('bundleIdentifier', '')}")
            return

        pick_and_launch(
            apps,
            positional,
            lambda n, b: devicectl_launch(target_device, n, b, hud_env),
        )
        return

    # Fallback multiplataforma: Windows, Linux ou macOS sem Xcode (pymobiledevice3)
    if not ensure_pymobiledevice3():
        print("[ERRO] Instale o Python 3 com `pip install pymobiledevice3` e tente novamente.")
        sys.exit(1)

    if cli_bundle:
        pmd_launch_with_tunnel(cli_bundle, cli_bundle, target_device, hud_env)
        return
    if not list_apps and positional and positional in CUSTOM_SHORTCUTS:
        name, bundle_id = CUSTOM_SHORTCUTS[positional]
        pmd_launch_with_tunnel(name, bundle_id, target_device, hud_env)
        return

    print("[...] Listando jogos e aplicativos instalados no dispositivo...")
    apps = order_apps(pmd_get_apps(target_device))
    if not apps:
        sys.exit(1)

    if list_apps:
        for idx, app in enumerate(apps, 1):
            print(f"  [{idx:2d}] {app.get('name', 'Sem Nome'):<26} {app.get('bundleIdentifier', '')}")
        return

    pick_and_launch(
        apps,
        positional,
        lambda n, b: pmd_launch_with_tunnel(n, b, target_device, hud_env),
    )


if __name__ == "__main__":
    main()
"""##
}
