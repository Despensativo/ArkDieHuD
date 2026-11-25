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

### Opção A: Instalar `.ipa` via Sideloadly (Mais Fácil e Simples — Recomendado, Windows ou Mac, Sem Xcode)
1. Baixe [`ArkDieHuD-unsigned.ipa`](https://github.com/Despensativo/ArkDieHuD/releases/latest/download/ArkDieHuD-unsigned.ipa) na aba **[Releases](https://github.com/Despensativo/ArkDieHuD/releases)**.
2. Abra o **[Sideloadly](https://sideloadly.io/)** (~80 MB, funciona no Windows e no Mac), conecte o iPad/iPhone, informe seu **Apple ID gratuito** e arraste o `ArkDieHuD-unsigned.ipa`.
3. No aparelho, vá em **Ajustes → Geral → Gestão de VPN e Dispositivo**, toque no seu Apple ID e em **Confiar**.

### Opção B: Catálogo Oficial no SideStore / AltStore Classic (Atualiza e Renova Sozinho)
1. No **SideStore** ou **AltStore Classic** do iPad/iPhone, vá em **Sources → +** e adicione:
   ```text
   https://raw.githubusercontent.com/Despensativo/ArkDieHuD/main/altstore-source.json
   ```
2. Toque em **ArkDieHuD → GET** (usa qualquer **Apple ID gratuito**, com renovação automática dos 7 dias).

> **Importante (Brasil, UE e Japão):** No site [altstore.io](https://altstore.io/), baixe o **AltStore Classic** (via AltServer) ou use o **SideStore** — **não use o AltStore PAL**. O AltStore PAL aceita apenas pacotes notarizados pela Apple (ADP) e bloqueia arquivos `.ipa` comuns e APIs privadas (`IOHID` de temperatura do silício e controles internos do PiP).

### Opção C: Instalador Automático no Mac (`./install.sh`)
Se você usa Mac e tem Xcode instalado:
```bash
git clone https://github.com/Despensativo/ArkDieHuD.git
cd ArkDieHuD
./install.sh
```
O assistente verifica tudo sozinho: detecta o iPad conectado, encontra sua conta Apple gratuita ou paga no Xcode, gera seu `Examples/Config/LocalSigning.xcconfig` local (ignorado pelo Git), compila, instala e abre o app no iPad.

> *(Dica: você **não precisa** baixar o Xcode inteiro de ~10 GB só para usar o ArkDieHuD — use a **Opção A** ou **Opção B** com o `.ipa` pronto. Como a Apple exige assinatura vinculada ao aparelho do usuário para APIs `IOHID` em Modo Desenvolvedor, não é possível distribuir um `.ipa` pré-assinado universal.)*

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

## 6. Bônus: FPS Real em QUALQUER Jogo ou App com Apple Metal HUD

Você pode abrir **qualquer jogo ou aplicativo instalado no iPhone/iPad** com o contador oficial da Apple (`MTL_HUD_ENABLED=1`) usando o script `./launch_metal_hud.sh` no Mac — ou pegar o **Launcher Mac (comando 1-clique) / Windows (`.bat`)** diretamente dentro do **Painel Web `:8787`** do próprio ArkDieHuD (no Windows: requer Python 3 + driver USB Dispositivos Apple/iTunes e rodar o `.bat` como Administrador):

1. **Menu Interativo (Sem configurar nada):**
   ```bash
   ./launch_metal_hud.sh
   ```
   Lista todos os aplicativos do seu iPad; basta digitar o número do app que você quer monitorar.

2. **Busca Rápida por Nome:**
   ```bash
   ./launch_metal_hud.sh genshin     # Busca e abre Genshin Impact
   ./launch_metal_hud.sh cod         # Busca e abre Call of Duty Mobile
   ./launch_metal_hud.sh capcut      # Funciona também em apps de edição/vídeo
   ```

3. **Descobrir o Bundle ID exato e abrir direto:**
   ```bash
   ./launch_metal_hud.sh --list
   ./launch_metal_hud.sh --bundle com.exemplo.seujogo
   ```

4. **Salvar seus próprios atalhos (Manualmente ou pedindo para uma IA):**
   Edite o dicionário `CUSTOM_SHORTCUTS` no topo de `launch_metal_hud.sh`:
   ```python
   CUSTOM_SHORTCUTS = {
       "genshin": ("Genshin Impact", "com.miHoYo.GenshinImpact"),
       # ...
   }
   ```
   > **Quer pedir para uma IA ajustar para você?** Cole este prompt:
   > *"Rode `./launch_metal_hud.sh --list`, veja meus jogos/apps instalados no iPad e adicione atalhos de 1 palavra para eles em `CUSTOM_SHORTCUTS` dentro do `launch_metal_hud.sh`."*

Consulte [METAL_HUD_GUIDE.md](METAL_HUD_GUIDE.md) para detalhes de pareamento.

> **Importante — Modo Desenvolvedor + Deixar o Metal HUD Pequeno ou Invisível mesmo ao sair e voltar do jogo:**
> 1. **Pré-requisito obrigatório:** ative **Ajustes → Privacidade e Segurança → Modo Desenvolvedor** no iPad/iPhone (reinicie se solicitado).
> 2. Em **Ajustes → Desenvolvedor → HUD Metal**, mantenha **Mostrar HUD de Desempenho do Metal** **desativado**, ative **Registrar Desempenho do Metal**, arraste **Escala** para o **mínimo** e em **Métricas** deixe ligado **apenas `FPS`** (assim, mesmo se você sair e voltar do jogo, ele continua pequeno e só com FPS em vez de voltar gigante!).
> 3. **Opacidade (Visível vs Só Web `:8787`):** deixe **Opacidade** em **100%** para ver o mini FPS na tela; ou arraste **Opacidade** até **0%** + escolha **`Invisível (Só Web)`** no painel `:8787` para ocultar da tela e acompanhar o FPS apenas pelo navegador (para voltar a ver, basta subir para **100%** nos Ajustes).

---

## 7. Suporte Automático a 3 Idiomas (`PT-BR` / `EN` / `ES`)

- **App iPad e PiP:** detecta automaticamente o idioma do iPadOS (**Português BR**, **Inglês** ou **Espanhol**). Você também pode escolher outro idioma só para o app em **Ajustes → ArkDieHuD → Idioma**.
- **Painel Web no PC/Mac (`:8787`):** detecta automaticamente o idioma do navegador e traz botões rápidos **`EN | PT | ES`** no topo direito.
