# Aprendizados Históricos (`swift-sensors`)

## [AL-PROJ-001] `idevicesyslog` (`syslog_relay`) não entrega linhas `metal-HUD:` no iPadOS 27+
- **Sintoma:** Com cabo USB conectado, `idevicesyslog -u <UDID>` fica bloqueado sem emitir eventos `os_log` (`metal-HUD:`), impedindo o envio de FPS ao vivo para `/api/metal-hud`.
- **Causa-raiz:** Nas versões recentes do iOS/iPadOS (17–27+), logs unificados `os_log` do Metal Performance HUD trafegam pelo serviço `com.apple.os_trace_relay` e não pelo legado `com.apple.syslog_relay`.
- **Solução permanente:** Em `resolve_syslog_command`, priorizar sempre `pymobiledevice3.services.os_trace.OsTraceService` tentando `create_using_usbmux` primeiro (USB/Wi-Fi Sync) e `create_using_tcp` em seguida (Wi-Fi LAN direto), deixando `idevicesyslog` apenas como último recurso quando `pymobiledevice3` não puder ser usado.

## [AL-PROJ-002] Opacidade nativa do `Graphics HUD` em Ajustes sobrevive ao minimizar/voltar ao jogo
- **Sintoma:** Variáveis `MTL_HUD_ELEMENTS`, `MTL_HUD_SCALE` e `MTL_HUD_OPACITY` injetadas via `devicectl` são descartadas quando jogos Unreal/Metal recriam a `CAMetalLayer` ao retornar do background, exibindo o HUD completo da Apple.
- **Causa-raiz:** Ao recriar a camada gráfica após background/foreground, o Metal Performance HUD lê as preferências globais salvas em `Ajustes -> Desenvolvedor -> Graphics HUD`, incluindo o controle deslizante `HUD Opacity / Opacidade`, mesmo quando `Show Graphics HUD` está desligado.
- **Solução permanente:** Para manter o HUD 100% invisível na tela durante toda a sessão (inclusive trocando de app) enquanto `MTL_HUD_LOG_ENABLED=1` envia FPS ao `:8787`, manter `Show Graphics HUD` desligado e arrastar `HUD Opacity` para `0%` nos Ajustes do iPad/iPhone; para voltar a ver o HUD na tela, restaurar `HUD Opacity` para `100%`.
