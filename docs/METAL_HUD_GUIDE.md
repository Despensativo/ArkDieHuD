# Guia do Apple Metal Performance HUD (`launch_metal_hud.sh`)

O script [`launch_metal_hud.sh`](../launch_metal_hud.sh), localizado na raiz do repositório `swift-sensors`, inicia qualquer jogo ou aplicativo no iPad/iPhone físico com a variável oficial **`MTL_HUD_ENABLED=1`** da Apple — ativando na tela o overlay nativo de **FPS em tempo real**, tempo de frame (`ms`), carga/tempo de GPU, resolução de renderização e memória do processo.

---

## 1. Como ele complementa o SwiftSensorsApp

O iPadOS não permite que um aplicativo comum leia o FPS, o clock da CPU/GPU ou o % global da GPU de outro app em execução. Combinar os dois overlays resolve isso com dados 100% reais:

| Ferramenta | Métricas Reais Exibidas | Como roda sobre o jogo |
| :--- | :--- | :--- |
| **Apple Metal HUD** (`launch_metal_hud.sh`) | **FPS real**, frame time (`ms`), GPU time, resolução e RAM do jogo | Injetado diretamente no processo do jogo pela Apple (`devicectl`) |
| **SwiftSensorsApp** (HUD PiP / Slide Over) | **CPU °C**, **GPU °C** (`IOHID`), **Watts (W)**, **RAM global**, **Ping / ICMP / UDP / Roteador / Loss**, **Jitter** e **Log SQLite 24h** | Janela **Picture-in-Picture (PiP)** arrastável ou gaveta **Slide Over** |

---

## 2. Pré-requisitos

1. **No Mac:** Xcode instalado (`xcrun devicectl` funcionando) e repositório em `swift-sensors`.
2. **No iPad:**
   - **Modo Desenvolvedor** ativado (*Ajustes > Privacidade e Segurança > Modo Desenvolvedor*).
   - iPad conectado ao Mac via cabo USB-C ou Wi-Fi na mesma rede e pareado ("Confiar neste computador").
   - **Tela desbloqueada** no momento em que você executar o script no Terminal.

---

## 3. Comandos Principais

Execute a partir da raiz do repositório `swift-sensors`:

```bash
# 1) Menu interativo com todos os jogos/apps instalados no iPad
./launch_metal_hud.sh

# 2) Atalhos diretos para jogos/apps populares
./launch_metal_hud.sh flash     # PUBGM FLASH (com.tencent.igfit)
./launch_metal_hud.sh pubg      # PUBG MOBILE (com.tencent.ig)
./launch_metal_hud.sh davinci   # DaVinci Resolve iPad

# 3) Buscar qualquer app por nome ou bundle identifier
./launch_metal_hud.sh capcut

# 4) Inspecionar dispositivos pareados e ajuda
./launch_metal_hud.sh --devices
./launch_metal_hud.sh --help

# 5) Selecionar um dispositivo específico manualmente (opcional)
./launch_metal_hud.sh --device <UDID_DO_IPAD> flash
METAL_HUD_DEVICE_ID=<UDID_DO_IPAD> ./launch_metal_hud.sh flash
```

Por padrão, o script detecta automaticamente via `xcrun devicectl list devices --json-output -` o primeiro **iPad físico pareado** disponível, sem exigir edição manual de UDID no código.

---

## 4. Fluxo Recomendado Antes da Partida

1. Desbloqueie o iPad e abra o **SwiftSensorsApp**.
2. Em **HUD Flutuante (PiP)**, escolha o layout desejado (*Barra Gamer*, *Overlay Gamer*, *Grid Compacto* ou *Detalhado*), ajuste os toggles em **Personalizar Métricas** e confirme que **Gravar logs de telemetria (24h)** está ligado.
3. Toque em **Sobrepor na Tela (PiP)** e arraste a barra para a borda superior/lateral.
4. No Mac, rode:
   ```bash
   ./launch_metal_hud.sh flash
   ```
5. O jogo abrirá com o **Apple Metal Performance HUD (FPS)** no canto e a **Barra Gamer PiP** exibindo temperatura do silício, Watts, RAM, Ping, UDP, Roteador e Perda simultaneamente.

---

## 5. Monitorar no PC/Mac Sem PiP na Tela + Puxar Logs SQLite 24h

### A) Painel Web Ao Vivo (`http://<IP_DO_IPAD>:8787`) — Sem Overlay PiP

No **ArkDieHuD** (iPad), ative **Monitorar no PC/Mac (sem PiP na tela)**:
- **Via Wi-Fi (mesma rede):** abra `http://<IP_DO_IPAD>:8787` em qualquer navegador do Windows/Linux/Mac para acompanhar todos os sensores, gráficos de CPU/GPU/Watts, latência ICMP/UDP/Roteador, drops e baixar o CSV — sem exibir o PiP por cima do jogo.
- **Via Cabo USB:** faça o túnel da porta `8787` e acesse localmente em `http://127.0.0.1:8787`:
  ```bash
  # Instalar uma vez no Mac (libimobiledevice) ou usar ferramenta equivalente no Windows
  brew install libimobiledevice
  iproxy 8787 8787
  ```

### B) Puxar o Banco SQLite 24h via `devicectl`

Além de exportar o CSV direto pelo botão de compartilhamento dentro de **Logs e Telemetria 24h** no iPad ou pelo botão **Baixar CSV** no painel web, você pode copiar o banco completo (`SwiftSensors_Telemetry_24h.sqlite`) para o Mac:

```bash
xcrun devicectl device copy from \
  --device <UDID_DO_IPAD> \
  --domain-type appDataContainer \
  --domain-identifier com.cristianark.SwiftSensorsApp \
  --source Documents/SwiftSensors_Telemetry_24h.sqlite \
  --destination ./ArkDieHuD_Telemetry_24h.sqlite
```

---

## 6. Solução de Problemas

- **`O iPad está BLOQUEADO com a tela apagada` (`Locked`):** O iPadOS bloqueia abertura remota de apps com a tela travada. Desbloqueie o iPad e rode o comando novamente.
- **`Nenhum iPad/iPhone físico pareado encontrado`:** Rode `./launch_metal_hud.sh --devices` e verifique se o iPad aparece com cabo conectado ou pareamento Wi-Fi ativo no Xcode (*Window > Devices and Simulators*).
- **O Metal HUD não apareceu em um jogo específico:** O jogo já estava rodando sem a flag; o script usa `--terminate-existing` para reiniciá-lo com `MTL_HUD_ENABLED=1`. Se o processo resistir, feche o jogo manualmente na multitarefa e execute o script de novo.
