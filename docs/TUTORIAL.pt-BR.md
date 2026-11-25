<p align="center">
  <a href="TUTORIAL.md">English</a> | <strong>Português (BR)</strong> | <a href="TUTORIAL.es.md">Español</a>
</p>

# ArkDieHuD — Tutorial Passo a Passo Completo

Bem-vindo ao **ArkDieHuD**. Este guia explica do zero como instalar o aplicativo (inclusive com **Apple ID gratuito**), configurar o **HUD flutuante (`PiP`)** sobre jogos, diagnosticar quedas de internet com a **Sonda Dupla (`ICMP + UDP + TCP`)**, consultar o **histórico de 24h** e usar o **Painel Web no PC/Mac (`:8787`)** com tela limpa.

---

## 1. Pré-requisitos e Instalação com Apple ID Gratuito

- **Dispositivo:** iPad ou iPhone com **iPadOS 17+ / iOS 17+** (Apple Silicon recomendado para leitura completa dos sensores de die CPU/GPU).
- **Modo Desenvolvedor:** necessário para rodar apps instalados via Xcode ou Sideloadly.

### Ativar o Modo Desenvolvedor no iPad
1. Abra **Ajustes → Privacidade e Segurança → Modo Desenvolvedor**.
2. Ative a chave, reinicie o iPad quando solicitado e confirme após ligar.
   *(Se a opção não aparecer ainda, conecte o iPad uma vez ao Mac/PC com Xcode ou Sideloadly aberto — o iPadOS libera o menu automaticamente.)*

### Opção A: Instalar o `.ipa` pronto via Sideloadly / AltStore / SideStore (Sem precisar de Mac/Xcode)
1. Baixe o arquivo `ArkDieHuD-unsigned.ipa` na aba **[Releases](https://github.com/Despensativo/ArkDieHuD/releases)**.
2. Abra o **Sideloadly** (Windows/Mac) ou **AltStore / SideStore**.
3. Conecte o iPad, informe seu **Apple ID gratuito** e arraste o `ArkDieHuD-unsigned.ipa`.
4. No iPad, vá em **Ajustes → Geral → Gestão de VPN e Dispositivo**, toque no seu Apple ID e em **Confiar**.

### Opção B: Compilar do zero no Xcode (Personal Team gratuito)
1. Clone o repositório e, se quiser assinar com sua equipe local, crie `Examples/Config/LocalSigning.xcconfig` (já ignorado pelo Git):
   ```xcconfig
   DEVELOPMENT_TEAM = SEU_TEAM_ID
   PRODUCT_BUNDLE_IDENTIFIER = com.seunome.ArkDieHuD
   ```
   Ou gere o `.ipa` direto pelo Terminal:
   ```bash
   ./Scripts/export-ipa.sh
   # Saída: dist/ArkDieHuD-unsigned.ipa
   ```
2. Abra `Examples/SwiftSensorsApp.xcodeproj`, selecione seu iPad e aperte **Cmd + R**.

---

## 2. Configurando o HUD Flutuante (PiP) e as Métricas

1. Abra o **ArkDieHuD** no iPad.
2. No card **HUD Flutuante (PiP)**, escolha o **Layout do HUD**:
   - **Barra Gamer (1 Linha Transparente):** barra fina ideal para borda superior/inferior em jogos (PUBG, CODM, etc.).
   - **Overlay Gamer (2 Linhas):** separa Hardware na linha 1 e Rede na linha 2.
   - **Grid Compacto:** mini-cards com barras de carga e cores térmicas.
   - **Detalhado:** cards principais + ranking em tempo real dos sensores mais quentes.
3. Toque em **Personalizar Métricas** para ligar/desligar qualquer uma das **12 métricas** (`CPU °C`, `GPU °C`, `Carga CPU`, `RAM`, `Watts`, `Bateria`, `Estado Térmico`, `Ping`, `UDP 53`, `Roteador`, `Jitter`, `Perda`) ou escolha 1 dos **4 perfis rápidos**.
4. Toque em **Sobrepor na Tela (PiP)** e abra seu jogo — você pode arrastar a barra para qualquer canto ou fazer gesto de pinça para redimensionar.
   *(Dica: o **Modo Slide Over** permite deixar um painel completo escondido na lateral direita da tela.)*

---

## 3. Diagnóstico de Rede (Sonda Dupla & Multi-Protocolo)

Toque em **Rede e Log de Pacotes** (ou no card **Ping / Perda**) para investigar lag e micro-quedas.

### Como interpretar os sinais
- **Modo Simultâneo (`ICMP + UDP + TCP`)** sonda o servidor externo a cada **1 segundo** em paralelo com seu **Roteador Local (Gateway)**:
  - **Roteador Local e Alvo Externo caem juntos:** falha no **sinal Wi-Fi ou no próprio roteador**.
  - **Roteador Local segue em ~1–3 ms (`0%` perda) e só o Alvo Externo cai:** falha na **rota da operadora (ISP), CGNAT ou VPN**.
  - **Só a sonda UDP (`:53`) perde pacotes enquanto ICMP/TCP seguem normais:** gargalo **NAT/CGNAT ou QoS em UDP** (causa teleporte/"desync" em jogos como PUBG).
  - **Só ICMP falha enquanto UDP/TCP estão estáveis:** o servidor limita resposta de ping comum — não afeta a partida.
- **Detector de Ciclos:** calcula automaticamente o intervalo (`Δ +93s`, etc.) entre quedas para identificar micro-cortes periódicos do provedor.
- **Exportar:** toque em **Exportar CSV** para salvar o relatório cronológico completo.

---

## 4. Histórico Persistente de 24h (SQLite WAL)

1. Deixe ligado **Gravar logs de telemetria (24h)** no card principal.
2. Entre em **Logs e Telemetria 24h** e alterne as janelas **15m | 1h | 6h | 24h** nas abas **Térmico**, **Energia & RAM** e **Rede**.
3. O banco **SQLite WAL** grava lotes a cada 15s (e faz flush ao ir para segundo plano), removendo automaticamente dados com mais de 24h.
4. Toque em **Exportar CSV** para baixar uma planilha única com hardware + rede segundo a segundo.

---

## 5. Monitorar no PC/Mac (`:8787`) Sem PiP na Tela + Modo Stealth

Quer acompanhar temperatura, Watts, ping, UDP e quedas em outro monitor (**PC Windows, Linux ou Mac**) deixando a tela do iPad **100% limpa**?

1. No **ArkDieHuD** (iPad), ative **Monitorar no PC/Mac (sem PiP na tela)**.
2. **Via Wi-Fi (mesma rede):**
   Abra o endereço `http://<IP_DO_IPAD>:8787` (exibido no card com botão **Copiar URL**) no navegador do seu PC/Mac.
3. **Via Cabo USB (sem depender do Wi-Fi):**
   ```bash
   brew install libimobiledevice   # Mac (instalar uma vez)
   iproxy 8787 8787
   ```
   E acesse **`http://127.0.0.1:8787`** no navegador.

### Modo PiP Discreto (Essencial se você usa Microfone / Call no Jogo)
O iPadOS pode suspender apps em segundo plano quando o jogo ativa o microfone (como o chat de voz do PUBG) se não houver nenhuma janela PiP aberta. Para evitar isso sem poluir sua tela:
1. Mantenha ligado **PiP discreto (ocultar na borda)**.
2. Toque em **Sobrepor na Tela (PiP)** — abrirá uma pílula mínima (`● ARKDIEHUD • PC | ... | Arraste p/ borda p/ ocultar e manter ativo`).
3. **Arraste essa pílula para fora da borda lateral da tela do iPad** até ela ficar oculta na beirada.
4. O jogo fica com a tela 100% livre, seu microfone funciona normalmente e o painel no PC (`:8787`) + gravação 24h continuam ativos com auto-recuperação!

---

## 6. Bônus: FPS Real com Apple Metal Performance HUD

Para ver **FPS em tempo real** e Frame Time junto com a telemetria do ArkDieHuD, conecte o iPad ao Mac e rode:

```bash
./launch_metal_hud.sh flash     # Abre PUBGM FLASH com Metal HUD
./launch_metal_hud.sh pubg      # Abre PUBG MOBILE com Metal HUD
./launch_metal_hud.sh           # Menu interativo com todos os apps do iPad
```

Consulte [METAL_HUD_GUIDE.md](METAL_HUD_GUIDE.md) para detalhes de pareamento.

---

## 7. Suporte Automático a 3 Idiomas (`PT-BR` / `EN` / `ES`)

- **App iPad e PiP:** detecta automaticamente o idioma do iPadOS (**Português BR**, **Inglês** ou **Espanhol**). Você também pode escolher outro idioma só para o app em **Ajustes → ArkDieHuD → Idioma**.
- **Painel Web no PC/Mac (`:8787`):** detecta automaticamente o idioma do navegador e traz botões rápidos **`EN | PT | ES`** no topo direito.
