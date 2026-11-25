# Aprendizados Históricos (`swift-sensors`)

## [AL-PROJ-001] `idevicesyslog` (`syslog_relay`) não entrega linhas `metal-HUD:` no iPadOS 27+
- **Sintoma:** Com cabo USB conectado, `idevicesyslog -u <UDID>` fica bloqueado sem emitir eventos `os_log` (`metal-HUD:`), impedindo o envio de FPS ao vivo para `/api/metal-hud`.
- **Causa-raiz:** Nas versões recentes do iOS/iPadOS (17–27+), logs unificados `os_log` do Metal Performance HUD trafegam pelo serviço `com.apple.os_trace_relay` e não pelo legado `com.apple.syslog_relay`.
- **Solução permanente:** Em `resolve_syslog_command`, priorizar sempre `pymobiledevice3.services.os_trace.OsTraceService` tentando `create_using_usbmux` primeiro (USB/Wi-Fi Sync) e `create_using_tcp` em seguida (Wi-Fi LAN direto), deixando `idevicesyslog` apenas como último recurso quando `pymobiledevice3` não puder ser usado.
