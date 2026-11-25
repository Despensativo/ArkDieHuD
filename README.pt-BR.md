<p align="center">
  <img src="Media/arkdiehud_github_banner.png" alt="ArkDieHuD — Banner de Telemetria Apple Silicon e Rede" width="100%">
</p>

<p align="center">
  <a href="README.md">English</a> | <strong>Português (BR)</strong> | <a href="README.es.md">Español</a>
</p>

# ArkDieHuD

[![Compatibilidade](https://img.shields.io/badge/Plataforma-iPadOS%2017%2B-black)](https://swift.org/platforms/)
[![Versão do Swift](https://img.shields.io/badge/Swift-5.0%20%2F%206.0-orange)](https://swift.org)
[![Idiomas](https://img.shields.io/badge/Idiomas-PT--BR%20%7C%20EN%20%7C%20ES-38bdf8)](docs/TUTORIAL.pt-BR.md)
[![Licença: MIT](https://img.shields.io/badge/Licen%C3%A7a-MIT-34D399)](LICENSE)

**ArkDieHuD** é uma suíte completa de telemetria física em tempo real para **Apple Silicon (iPadOS & iOS)** construída sobre o motor `SwiftSensors` (`IOHID` + kernel `Mach`), com HUD flutuante Picture-in-Picture (`PiP`), gaveta **Slide Over**, Sonda Dupla Multi-Protocolo (**`ICMP + UDP DNS 53 + TCP`**), gravação contínua de **24h em SQLite WAL** e servidor web local (**`:8787`**) para acompanhar tudo pelo PC ou Mac **sem ocupar a tela do jogo**.

> **Novo por aqui?** Leia o **[Tutorial Passo a Passo Completo (PT-BR)](docs/TUTORIAL.pt-BR.md)** · **[Tutorial (EN)](docs/TUTORIAL.md)** · **[Tutorial (ES)](docs/TUTORIAL.es.md)**

---

## Principais Recursos

- **Sensores Físicos Reais (`IOHID` + `Mach`):** temperatura direta do die da CPU (`PMU tdie`) e GPU (`PMU2 tdie`), trilhos de tensão/corrente, potência estimada (`W`), carga de CPU, RAM + margem Jetsam e estado térmico do iPadOS — zero estimativas inventadas.
- **HUD Flutuante PiP + Personalização Total:** 4 layouts dinâmicos (*Barra Gamer*, *Overlay Gamer*, *Grid Compacto*, *Detalhado*) e **12 toggles independentes** com 4 perfis de 1 toque. Ajusta largura/altura sem tremer e também conta com modo **Slide Over**.
- **Rede Competitiva (Sonda Dupla & Multi-Protocolo):** ping nativo `SOCK_DGRAM` **ICMP**, sonda real **UDP (DNS 53)** e **TCP** rodando em paralelo contra o **Roteador Local (Gateway)** para diferenciar quedas do Wi-Fi de quedas do provedor/CGNAT, com `P50/P95/P99`, Jitter RFC 3550, detector de ciclos e log cronológico de 1 hora.
- **Histórico Persistente 24h (SQLite WAL):** gravação em lote a cada 15s com limpeza automática > 24h, gráficos agregados (`15m | 1h | 6h | 24h`) e exportação CSV unificada (Hardware + Rede).
- **Monitor no PC/Mac Sem PiP na Tela (`:8787`):** painel web offline servido direto do iPad via Wi-Fi ou cabo USB (`iproxy 8787 8787`), além de modo **PiP Discreto** (*Arraste p/ borda p/ ocultar e manter ativo*) para manter a coleta ativa mesmo em jogos com chat de voz.
- **Suporte Automático a 3 Idiomas (`pt-BR` / `en` / `es`):** detecção automática pelo idioma do iPadOS em todas as telas, HUD PiP e permissões, e detecção automática no painel web do PC (com seletor rápido `EN | PT | ES`).
- **Pronto para Apple ID Gratuito:** entitlements limpos para Personal Team no Xcode ou sideload via `ArkDieHuD-unsigned.ipa` na aba [Releases](https://github.com/Despensativo/ArkDieHuD/releases).

---

## Screenshots Reais no iPad

<table>
  <tr>
    <td width="50%">
      <img src="Media/screenshots/dashboard_live.png" alt="Painel Principal ArkDieHuD" width="100%">
      <p align="center"><em>Painel Principal + Faixa Ao Vivo e Preview PiP</em></p>
    </td>
    <td width="50%">
      <img src="Media/screenshots/pip_and_metal_hud.png" alt="PiP sobre PUBG + Metal HUD" width="100%">
      <p align="center"><em>Barra Gamer PiP + Apple Metal FPS HUD rodando sobre PUBG</em></p>
    </td>
  </tr>
  <tr>
    <td width="50%">
      <img src="Media/screenshots/logs_24h.png" alt="Histórico 24h SQLite WAL" width="100%">
      <p align="center"><em>Gráficos Persistentes 24h (SQLite WAL) e Exportação CSV</em></p>
    </td>
    <td width="50%">
      <img src="Media/screenshots/pc_stealth_pip.png" alt="PiP Discreto para Monitor PC" width="100%">
      <p align="center"><em>Pílula Stealth do Monitor PC (:8787) — Arraste para a borda</em></p>
    </td>
  </tr>
</table>

---

## Início Rápido

```bash
# 1) Clonar o repositório
git clone https://github.com/Despensativo/ArkDieHuD.git
cd ArkDieHuD

# 2) Gerar .ipa para conta Apple gratuita (Sideloadly / AltStore / SideStore)
./Scripts/export-ipa.sh

# 3) Opcional: Abrir QUALQUER jogo ou app no iPad com Apple Metal FPS HUD
./launch_metal_hud.sh                         # Menu interativo (todos os apps instalados)
./launch_metal_hud.sh <nome_do_app>           # Busca por nome (ex: genshin, cod, pubg, capcut)
./launch_metal_hud.sh --list                  # Lista todos os apps e seus Bundle IDs
./launch_metal_hud.sh --bundle <bundle.id>    # Inicia direto pelo Bundle ID exato
# Dica: salve atalhos fixos em `CUSTOM_SHORTCUTS` dentro de `launch_metal_hud.sh` (ou peça para sua IA ajustar).

# 4) Opcional: Túnel USB para ver o painel do PC em http://127.0.0.1:8787
iproxy 8787 8787
```

### Assinatura Local no Xcode (Opcional)

Team IDs pessoais não ficam salvos no Git. Crie localmente o arquivo `Examples/Config/LocalSigning.xcconfig` (já ignorado no `.gitignore`):

```xcconfig
DEVELOPMENT_TEAM = SEU_TEAM_ID
PRODUCT_BUNDLE_IDENTIFIER = com.seunome.ArkDieHuD
```

Depois abra `Examples/SwiftSensorsApp.xcodeproj` e clique em **Run**.

---

## Documentação e Guias

| Guia / Script | Finalidade | Link |
| :--- | :--- | :--- |
| **Tutorial Passo a Passo** | Instalação gratuita, PiP, Sonda Dupla, Logs 24h, Monitor PC e Metal HUD | [PT-BR](docs/TUTORIAL.pt-BR.md) · [EN](docs/TUTORIAL.md) · [ES](docs/TUTORIAL.es.md) |
| **Guia Apple Metal HUD** | Como parear e abrir jogos com `MTL_HUD_ENABLED=1` | [docs/METAL_HUD_GUIDE.md](docs/METAL_HUD_GUIDE.md) |
| **Mapa de Arquitetura** | Camadas SwiftUI, PiP CoreGraphics, `SwiftSensors`, `IOKit` e SQLite | [docs/ARCHITECTURE_MAP.md](docs/ARCHITECTURE_MAP.md) |
| **Identidade Visual** | Ícone Silicon Die, tipografia e paleta oficial | [DESIGN.md](DESIGN.md) |
| **Gerador de `.ipa`** | Compila `Release` e empacota `dist/ArkDieHuD-unsigned.ipa` | [Scripts/export-ipa.sh](Scripts/export-ipa.sh) |

---

## ☕ Apoie o Desenvolvimento

Se o **ArkDieHuD** te economizou tempo ou te ajudou a diagnosticar hardware e quedas de rede no seu iPad, sinta-se à vontade para apoiar o desenvolvimento. Qualquer valor incentiva novas pesquisas em Apple Silicon, testes e ferramentas abertas!

<p align="left">
  <a href="https://www.buymeacoffee.com/despensativo" target="_blank">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="42">
  </a>
</p>

<details>
  <summary>🇧🇷 <b>Apoiar via Pix (Brasil) — QR Code &amp; Copia e Cola</b></summary>
  <br>

  <p align="left">
    <img src="Media/pix_qr.png" alt="Pix QR Code" width="200" style="border-radius: 8px; background: white; padding: 8px;" />
  </p>

  **Pix Copia e Cola:**
```text
00020101021126580014br.gov.bcb.pix01368e4ae808-3a54-4b91-bd4a-0e4249cd37875204000053039865802BR5917HEDSON C DA SILVA6013APARECIDA DE 62070503***6304BE1E
```

  > **Titular:** Hedson C da Silva  
  > **Chave Aleatória:** `8e4ae808-3a54-4b91-bd4a-0e4249cd3787`

</details>

---

## Nota sobre APIs Privadas e Créditos

- Este projeto utiliza APIs privadas `IOKit` / `IOHID` para acessar sensores internos reais do hardware. Destina-se a diagnóstico local, benchmarking e builds pessoais em Modo Desenvolvedor (não para App Store).
- Bindings base originalmente derivados de [`trymirai/swift-sensors`](https://github.com/trymirai/swift-sensors) sob licença MIT. Consulte [LICENSE](LICENSE).
