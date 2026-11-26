<p align="center">
  <a href="TUTORIAL.md">English</a> | <a href="TUTORIAL.pt-BR.md">Português (BR)</a> | <strong>Español</strong>
</p>

# ArkDieHuD — Tutorial Completo Paso a Paso

Bienvenido a **ArkDieHuD**. Esta guía explica cómo instalar la app (incluso con un **Apple ID gratuito**), configurar el **HUD flotante (`PiP`)** sobre juegos, diagnosticar caídas con la **Sonda Doble (`ICMP + UDP + TCP`)**, consultar el **historial de 24h** y usar el **Panel Web en PC/Mac (`:8787`)** sin tapar la pantalla.

---

## 1. Requisitos e Instalación con Apple ID Gratuito

- **Dispositivo:** iPad o iPhone con **iPadOS 17+ / iOS 17+** (Apple Silicon recomendado para sensores térmicos de CPU/GPU).
- **Modo Desarrollador:** necesario para ejecutar compilaciones personales.

### Activar el Modo Desarrollador en iPad
1. Ve a **Ajustes → Privacidad y Seguridad → Modo de Desarrollador**.
2. Actívalo, reinicia el iPad cuando se solicite y confirma al encender.

### Opción A: Instalar `.ipa` con Sideloadly (Más Fácil y Sencillo — Recomendado, Windows o Mac, Sin Xcode)
1. Descarga [`ArkDieHuD-unsigned.ipa`](https://github.com/Despensativo/ArkDieHuD/releases/latest/download/ArkDieHuD-unsigned.ipa) desde **[Releases](https://github.com/Despensativo/ArkDieHuD/releases)**.
2. Abre **[Sideloadly](https://sideloadly.io/)** (Windows/Mac), conecta tu iPad/iPhone, introduce tu **Apple ID gratuito** e instala `ArkDieHuD-unsigned.ipa`.
3. En el dispositivo, ve a **Ajustes → General → Gestión de VPN y Dispositivos** y toca **Confiar**.

### Opción B: Fuente Oficial SideStore / AltStore Classic (Actualizaciones y Renovación Automática)
1. En **SideStore** o **AltStore Classic**, ve a **Sources → +** y añade:
   ```text
   https://raw.githubusercontent.com/Despensativo/ArkDieHuD/main/altstore-source.json
   ```
2. Toca **ArkDieHuD → GET** (funciona con cualquier **Apple ID gratuito**).

> **Importante (UE, Japón y Brasil):** En [altstore.io](https://altstore.io/), usa **AltStore Classic** (vía AltServer) o **SideStore** — **no AltStore PAL**. AltStore PAL solo instala paquetes notarizados por Apple (ADP) y no admite archivos `.ipa` sin firmar ni APIs privadas (`IOHID` de temperatura del silicio ni controles internos de PiP).

### Opción C: Asistente Automático en Mac (`./install.sh`)
Si usas Mac con Xcode:
```bash
git clone https://github.com/Despensativo/ArkDieHuD.git
cd ArkDieHuD
./install.sh
```
Detecta tu iPad, tu cuenta Apple gratuita o de pago, compila, instala y abre la app automáticamente.

> *(Nota: NO necesitas instalar Xcode completo solo para usar la app; usa las Opciones A o B. La firma personal es obligatoria por Apple para ejecutar sensores privados `IOHID` en Modo Desarrollador.)*

---

## 2. HUD Flotante (PiP) y Métricas Personalizables

1. Abre **ArkDieHuD** y en **HUD Flotante (PiP)** elige tu diseño: *Barra Gamer*, *Overlay Gamer*, *Cuadrícula Compacta* o *Detallado*.
2. Toca **Personalizar Métricas** para activar/desactivar cualquiera de las **12 métricas** o usar uno de los **4 perfiles rápidos**.
3. Pulsa **Superponer en Pantalla (PiP)** y cambia a tu juego. Puedes arrastrarlo a cualquier borde o cambiar su tamaño con dos dedos.

---

## 3. Diagnóstico de Red (Sonda Doble y Multiprotocolo)

Toca **Red y Registro de Paquetes**:
- **Router Local y Destino Externo caen a la vez:** problema en tu **Wi-Fi o router local**.
- **Router Local estable (~1–3 ms) y Destino Externo cae:** problema en tu **ISP, CGNAT o VPN**.
- **Solo UDP (`:53`) pierde paquetes mientras ICMP/TCP siguen estables:** saturación UDP en **NAT/CGNAT o QoS** (afecta directamente a juegos como PUBG).

---

## 4. Historial 24h en SQLite WAL y CSV Unificado

Activa **Grabar logs de telemetría (24h)** para guardar métricas cada 15s, consultar gráficos de **15m | 1h | 6h | 24h** y exportar un CSV unificado (Hardware + Red).

---

## 5. Monitor en PC/Mac (`:8787`) + Modo PiP Discreto

1. Activa **Monitorear en PC/Mac (sin PiP en pantalla)**.
2. Abre `http://<IP_DEL_IPAD>:8787` en tu navegador vía Wi-Fi o **adaptador de red USB-C Ethernet** (con **Usar adaptador de red USB (LAN)** activado por defecto), o usa cable USB:
   ```bash
   iproxy 8787 8787   # abre http://127.0.0.1:8787
   ```
   - **Toggles de Seguridad IPv6 (desactivados por defecto):** tanto **Permitir IPv6 en el Panel Web** como **Usar IPv6 en sondas de red** vienen en **OFF** para no abrir `:8787` en IPv6 pública salvo que los actives manualmente.
3. Si usas chat de voz/micrófono en juegos, mantén activado **PiP discreto (ocultar en el borde)**, abre el PiP y **arrastra la píldora hacia el borde lateral** para dejar la pantalla limpia mientras el monitor en PC sigue activo.

---

## 6. Bonus: FPS Reales en CUALQUIER Juego o App con Apple Metal HUD

Puedes lanzar **cualquier juego o app instalado en tu iPhone/iPad** con el contador nativo de Apple (`MTL_HUD_ENABLED=1`) usando `./launch_metal_hud.sh` en Mac — u obtener el **Launcher para Mac (comando de 1 clic) / Windows (`.bat`)** directamente desde el **Panel Web `:8787`** integrado en ArkDieHuD (en Windows: requiere Python 3 + driver USB Apple Devices/iTunes y ejecutar el `.bat` como Administrador):

1. **Menú interactivo (sin configurar nada):** `./launch_metal_hud.sh`
2. **Búsqueda por nombre:** `./launch_metal_hud.sh genshin` o `./launch_metal_hud.sh cod`
3. **Listar Bundle IDs y lanzar directo:**
   ```bash
   ./launch_metal_hud.sh --list
   ./launch_metal_hud.sh --bundle com.ejemplo.tujuego
   ```
4. **Guardar tus propios atajos (manualmente o con una IA):** edita `CUSTOM_SHORTCUTS` al inicio de `launch_metal_hud.sh`. Si usas una IA, pídele: *"Ejecuta `./launch_metal_hud.sh --list` y añade mis juegos en `CUSTOM_SHORTCUTS` dentro de `launch_metal_hud.sh`."*

> **Importante — Modo Desarrollador + Mantener el Metal HUD Pequeño (o Invisible) incluso al salir y volver al juego:**
> 1. **Requisito obligatorio:** activa **Ajustes → Privacidad y Seguridad → Modo de Desarrollador** en tu iPad/iPhone (reinicia si lo solicita).
> 2. En **Ajustes → Desarrollador → HUD de Metal**, mantén **Mostrar HUD de rendimiento de Metal** **desactivado**, activa **Registrar rendimiento de Metal**, baja **Escala** al **mínimo** y en **Métricas** deja activo **solo `FPS`** (así, aunque salgas y vuelvas al juego, seguirá pequeño en lugar de volver gigante).
> 3. **Opacidad (Visible vs Solo Web `:8787`):** deja **Opacidad** al **100%** para ver el mini FPS en pantalla; o bájala al **0%** y elige **`Invisible (Solo Web)`** en `:8787` para ocultarlo en pantalla mientras el FPS sigue en vivo en tu navegador (sube de nuevo al **100%** para revisarlo o volver a verlo).

---

## 7. Detección Automática de 3 Idiomas (`ES` / `PT-BR` / `EN`)

- **App iPad y PiP:** se adapta automáticamente al idioma del sistema (puedes cambiarlo por app en **Ajustes → ArkDieHuD → Idioma**).
- **Panel Web en PC/Mac (`:8787`):** detecta `navigator.language` automáticamente e incluye botones **`EN | PT | ES`** en la cabecera.
