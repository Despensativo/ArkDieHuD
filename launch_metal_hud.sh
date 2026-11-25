#!/usr/bin/env python3
"""
Launcher para executar aplicativos e jogos no iPad/iPhone físico com o
Apple Metal Performance HUD oficial ativado (MTL_HUD_ENABLED=1).

Detecta automaticamente o iPad pareado via `xcrun devicectl` ou aceita
`--device <UDID>` / variável `METAL_HUD_DEVICE_ID`.
"""

import json
import os
import subprocess
import sys


PRIORITY_APPS = [
    ("com.tencent.igfit", "PUBGM FLASH"),
    ("com.tencent.ig", "PUBG MOBILE"),
    ("com.blackmagic-design.DaVinciResolveiPad", "DaVinci Resolve"),
]

HUD_PRESETS = {
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
) -> dict[str, str]:
    env: dict[str, str] = {"MTL_HUD_ENABLED": "1"}
    raw_elements = elements
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


def format_hud_summary(hud_env: dict[str, str]) -> str:
    parts = [f"{k}={v}" for k, v in hud_env.items() if k != "MTL_HUD_ENABLED"]
    return " | ".join(parts) if parts else "padrão completo Apple"


def launch_app(device_id: str, name: str, bundle_id: str, hud_env: dict[str, str]) -> None:
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
        print("📊 O Metal Performance HUD oficial da Apple (FPS / GPU / Frame Time) já está ativo na tela!\n")


def print_help() -> None:
    print(
        """Uso: ./launch_metal_hud.sh [OPÇÕES] [ATALHO_OU_BUSCA]

Opções:
  --help, -h             Exibe este guia de uso e exemplos
  --devices              Lista os iPads/iPhones físicos pareados e mostra o padrão detectado
  --device <UDID>        Força o lançamento em um UDID específico (ou defina METAL_HUD_DEVICE_ID)
  --list                 Lista todos os apps/jogos instalados no iPad com seus Bundle IDs exatos
  --bundle <BUNDLE_ID>   Inicia diretamente qualquer app pelo Bundle ID (ex: com.miHoYo.GenshinImpact)
  --preset <NOME>        Preset: fps-gpu, minimal, fps-only, full
  --elements <CSV>       Métricas MTL_HUD_ELEMENTS (ex: fps,gputime,fpsgraph,frameintervalgraph)
  --align <POS>          Posição: topleft, topright, topcenter, bottomleft, bottomright, ...
  --scale <0.0-1.0>      Tamanho do HUD (ex: 0.14, 0.18, 0.22)

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


def parse_args(argv: list[str]) -> tuple[bool, bool, bool, str | None, str | None, str | None, str | None, str | None, str | None, str | None]:
    show_help = False
    show_devices = False
    list_apps = False
    cli_device = None
    cli_bundle = None
    cli_preset = None
    cli_elements = None
    cli_align = None
    cli_scale = None
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
        else:
            positional = arg.lower().strip()
        i += 1

    return show_help, show_devices, list_apps, cli_device, cli_bundle, cli_preset, cli_elements, cli_align, cli_scale, positional


def main() -> None:
    show_help, show_devices, list_apps, cli_device, cli_bundle, cli_preset, cli_elements, cli_align, cli_scale, arg = parse_args(sys.argv[1:])

    if show_help:
        print_help()
        return

    if show_devices:
        print_devices()
        return

    hud_env = build_hud_env(cli_preset, cli_elements, cli_align, cli_scale)
    device_id, device_label = resolve_device_id(cli_device)
    print(f"🎯 Alvo detectado: {device_label}")

    if cli_bundle:
        launch_app(device_id, cli_bundle, cli_bundle, hud_env)
        return

    if not list_apps and arg and arg in CUSTOM_SHORTCUTS:
        name, bundle_id = CUSTOM_SHORTCUTS[arg]
        launch_app(device_id, name, bundle_id, hud_env)
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
            )
            return
        matched = [
            a
            for a in all_apps
            if arg in a.get("name", "").lower() or arg in a.get("bundleIdentifier", "").lower()
        ]
        if matched:
            target = matched[0]
            launch_app(device_id, target.get("name", arg), target.get("bundleIdentifier", ""))
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
    launch_app(device_id, target.get("name", "App"), target.get("bundleIdentifier", ""))


if __name__ == "__main__":
    main()
