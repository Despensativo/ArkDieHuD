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

# 2) Atalhos diretos de exemplo (editáveis em `CUSTOM_SHORTCUTS`)
./launch_metal_hud.sh flash     # PUBGM FLASH (com.tencent.igfit)
./launch_metal_hud.sh pubg      # PUBG MOBILE (com.tencent.ig)
./launch_metal_hud.sh davinci   # DaVinci Resolve iPad

# 3) Buscar QUALQUER app por nome ou abrir direto pelo Bundle ID
./launch_metal_hud.sh capcut
./launch_metal_hud.sh --list                     # Lista todos os apps + Bundle IDs
./launch_metal_hud.sh --bundle com.exemplo.app   # Inicia pelo Bundle ID exato

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
- **Via Wi-Fi ou Placa de Rede USB-C Ethernet (mesma rede LAN):** abra `http://<IP_DO_IPAD>:8787` em qualquer navegador do Windows/Linux/Mac para acompanhar todos os sensores, gráficos de CPU/GPU/Watts, latência ICMP/UDP/Roteador, drops e baixar o CSV — sem exibir o PiP por cima do jogo. *(Os toggles **Usar adaptador de rede USB (LAN)** [ligado por padrão] e **Permitir IPv6 no Painel Web** / **Usar IPv6 nas sondas de rede** [desligados por padrão por segurança] ficam disponíveis no app.)*
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

## 6. Passo a Passo: Ativar Modo Desenvolvedor e Manter o HUD Pequeno (ou Invisível Só Web `:8787`) ao Sair e Voltar do Jogo

Por padrão no iOS/iPadOS, se você sair de um jogo para outro app e voltar, o sistema recria a camada gráfica usando as preferências nativas salvas em **Ajustes → Desenvolvedor → HUD Metal** (*Settings → Developer → Metal HUD / Graphics HUD*) — **mesmo quando a chave `Mostrar HUD de Desempenho do Metal` está desativada**.

Configurar esses ajustes uma única vez evita que o HUD volte gigante com todos os gráficos na tela e garante que ele funcione corretamente com o `:8787`:

### Passo 1 — Pré-requisito obrigatório: Ativar o Modo Desenvolvedor
1. No iPad/iPhone, abra **Ajustes → Privacidade e Segurança → Modo Desenvolvedor** (*Settings → Privacy & Security → Developer Mode*).
2. Ative a chave, toque para **reiniciar** quando solicitado e confirme após ligar.
   *(Sem o Modo Desenvolvedor ativo, o menu **Desenvolvedor → HUD Metal** não aparece e os launchers não conseguem iniciar jogos com Metal HUD.)*

### Passo 2 — Configurar o `HUD Metal` nativo (para continuar pequeno mesmo saindo/voltando do jogo)
Abra **Ajustes → Desenvolvedor → HUD Metal**:
1. **`Mostrar HUD de Desempenho do Metal`**: mantenha **Desativado** *(assim o HUD não aparece em apps comuns, apenas nos jogos iniciados pelo launcher — mas o iPadOS continuará respeitando suas escolhas abaixo quando o jogo voltar do segundo plano)*.
2. **`Registrar Desempenho do Metal`**: deixe **Ativado** para facilitar o registro de desempenho/logs de FPS.
3. **`Localização`**: escolha o canto desejado (ex.: **Superior Direita**).
4. **`Escala`**: arraste o controle deslizante para o **mínimo (esquerda)** para que o contador fique pequeno e discreto.
5. **`Métricas`**: desligue as demais chaves e deixe ativado **apenas `FPS`** (ou apenas as que quiser ver na tela, ex.: `FPS` + `Tempo da GPU`).
   > Resultado: mesmo quando você sair do jogo e voltar, o iPadOS manterá apenas o contador pequeno de **FPS** no canto escolhido!

### Passo 3 — Escolher entre HUD Pequeno na Tela ou 100% Invisível (`Opacidade`)
- **Para ver só o mini FPS na tela:** em **Ajustes → Desenvolvedor → HUD Metal**, mantenha **Opacidade** em **100%** (ícone preenchido à direita) e use **`Ultra Compacto (Só FPS)`** no painel `:8787`.
- **Para ocultar 100% da tela (ver FPS só no navegador `:8787`):**
  1. Em **Ajustes → Desenvolvedor → HUD Metal**, arraste **Opacidade** até **0%** (ícone vazio à esquerda).
  2. No painel Web **`:8787`**, selecione **`Invisível (Só Web)`** (ou passe `--opacity 0` no comando) e mantenha a janela do Terminal / `.bat` aberta durante a partida (`Control+C` para encerrar).
  3. **Para checar ou voltar a ver na tela depois:** suba a **Opacidade** nos Ajustes para **100%** e mude para **`Opacidade: 100%`** no painel `:8787`.

---

## 7. Solução de Problemas

- **`O iPad está BLOQUEADO com a tela apagada` (`Locked`):** O iPadOS bloqueia abertura remota de apps com a tela travada. Desbloqueie o iPad e rode o comando novamente.
- **`Nenhum iPad/iPhone físico pareado encontrado`:** Rode `./launch_metal_hud.sh --devices` e verifique se o iPad aparece com cabo conectado ou pareamento Wi-Fi ativo no Xcode (*Window > Devices and Simulators*).
- **O Metal HUD não apareceu em um jogo específico:** O jogo já estava rodando sem a flag; o script usa `--terminate-existing` para reiniciá-lo com `MTL_HUD_ENABLED=1`. Se o processo resistir, feche o jogo manualmente na multitarefa e execute o script de novo.
