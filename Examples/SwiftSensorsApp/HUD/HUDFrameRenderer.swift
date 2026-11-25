import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import UIKit

/// High-DPI CoreGraphics renderer that draws TelemetrySnapshot directly into an
/// IOSurface-backed CVPixelBuffer -> CMSampleBuffer for Picture-in-Picture overlay.
enum HUDFrameRenderer {
    private static let scale: CGFloat = 2.0

    static func makeSampleBuffer(
        snapshot: TelemetrySnapshot,
        mode: HUDLayoutMode,
        config: TelemetryVisibilityConfig = .gamerDefault,
        pulseOn: Bool,
        pcStealthMode: Bool = false
    ) -> CMSampleBuffer? {
        let size = pcStealthMode
            ? HUDMetricBuilder.pcStealthCanvasSize
            : HUDMetricBuilder.canvasSize(for: mode, config: config)
        let pixelWidth = Int(size.width * scale)
        let pixelHeight = Int(size.height * scale)

        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
        ]

        var pixelBufferOut: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            pixelWidth,
            pixelHeight,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBufferOut
        )
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let cgContext = CGContext(
            data: baseAddress,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        cgContext.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        cgContext.translateBy(x: 0, y: CGFloat(pixelHeight))
        cgContext.scaleBy(x: scale, y: -scale)

        UIGraphicsPushContext(cgContext)
        let bounds = CGRect(origin: .zero, size: size)
        if pcStealthMode {
            drawPCStealthPiP(in: bounds, snapshot: snapshot, pulseOn: pulseOn)
        } else {
            switch mode {
            case .gamerBar:
                drawGamerBar(in: bounds, snapshot: snapshot, config: config, pulseOn: pulseOn)
            case .gamerMini:
                drawGamerMini(in: bounds, snapshot: snapshot, config: config, pulseOn: pulseOn)
            case .compact:
                drawCompactHUD(in: bounds, snapshot: snapshot, config: config, pulseOn: pulseOn)
            case .detailed:
                drawDetailedHUD(in: bounds, snapshot: snapshot, config: config, pulseOn: pulseOn)
            }
        }
        UIGraphicsPopContext()

        var formatDescOut: CMVideoFormatDescription?
        let descStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescOut
        )
        guard descStatus == noErr, let formatDesc = formatDescOut else {
            return nil
        }

        let nowHostTime = CMClockGetTime(CMClockGetHostTimeClock())
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 1),
            presentationTimeStamp: nowHostTime,
            decodeTimeStamp: .invalid
        )

        var sampleBufferOut: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBufferOut
        )
        guard sampleStatus == noErr, let sampleBuffer = sampleBufferOut else {
            return nil
        }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        return sampleBuffer
    }

    // MARK: - Stealth PC Keep-Alive PiP (Ocultável na Borda)

    private static func drawPCStealthPiP(
        in rect: CGRect,
        snapshot: TelemetrySnapshot,
        pulseOn: Bool
    ) {
        drawTranslucentPill(in: rect, cornerRadius: 10, bgAlpha: 0.72)

        let dotColor = pulseOn
            ? UIColor(red: 0.22, green: 0.95, blue: 0.55, alpha: 1.0)
            : UIColor(red: 0.16, green: 0.58, blue: 0.35, alpha: 1.0)
        dotColor.setFill()
        UIBezierPath(ovalIn: CGRect(x: rect.minX + 10, y: rect.minY + 10.5, width: 6, height: 6)).fill()

        drawText(
            "ARKDIEHUD • PC",
            in: CGRect(x: rect.minX + 20, y: rect.minY + 7, width: 112, height: 14),
            font: .systemFont(ofSize: 9.5, weight: .heavy),
            color: UIColor(white: 0.94, alpha: 1.0)
        )

        let endpointText: String
        if let ip = snapshot.network.route.localIPv4 {
            endpointText = "\(ip):8787"
        } else {
            endpointText = L10n.tr("PORT :8787")
        }
        drawText(
            endpointText,
            in: CGRect(x: rect.minX + 132, y: rect.minY + 7, width: rect.width - 142, height: 14),
            font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .bold),
            color: UIColor(red: 0.20, green: 0.88, blue: 0.70, alpha: 1.0),
            alignment: .right
        )

        drawText(
            L10n.tr("Drag to edge to hide & stay active"),
            in: CGRect(x: rect.minX + 10, y: rect.minY + 23, width: rect.width - 20, height: 14),
            font: .systemFont(ofSize: 9.5, weight: .medium),
            color: UIColor(white: 0.76, alpha: 1.0)
        )
    }

    // MARK: - Mode 1: Gamer Bar (1 Linha Transparente Ultra-Compacta)

    private static func drawGamerBar(
        in rect: CGRect,
        snapshot: TelemetrySnapshot,
        config: TelemetryVisibilityConfig,
        pulseOn: Bool
    ) {
        drawTranslucentPill(in: rect, cornerRadius: 8, bgAlpha: 0.62)

        let items = HUDMetricBuilder.inlineMetrics(from: snapshot, config: config)
        var currentX: CGFloat = 8
        let dotColor = pulseOn
            ? UIColor(red: 0.22, green: 0.95, blue: 0.55, alpha: 1.0)
            : UIColor(red: 0.16, green: 0.58, blue: 0.35, alpha: 1.0)
        UIColor.clear.setStroke()
        dotColor.setFill()
        UIBezierPath(ovalIn: CGRect(x: currentX, y: rect.midY - 3, width: 6, height: 6)).fill()
        currentX += 11

        let requiredCompact = Self.measureInlineWidth(items: items, labelSize: 9.0, valueSize: 12.5)
        let compactScale = (currentX + requiredCompact) > (rect.width - 6)
        let labelFontSize: CGFloat = compactScale ? 8.0 : 9.0
        let valueFontSize: CGFloat = compactScale ? 11.0 : 12.5
        let itemY = rect.minY + (compactScale ? 8 : 7)

        for (index, item) in items.enumerated() {
            if index > 0 {
                currentX = drawDivider(at: currentX, in: rect)
            }
            if currentX >= rect.maxX - 18 { break }
            currentX = drawStatInline(
                x: currentX,
                y: itemY,
                label: item.label,
                value: item.value,
                valueColor: item.color,
                labelFontSize: labelFontSize,
                valueFontSize: valueFontSize
            )
        }
    }

    // MARK: - Mode 2: Gamer Mini (2 Linhas de Overlay)

    private static func drawGamerMini(
        in rect: CGRect,
        snapshot: TelemetrySnapshot,
        config: TelemetryVisibilityConfig,
        pulseOn: Bool
    ) {
        drawTranslucentPill(in: rect, cornerRadius: 9, bgAlpha: 0.65)

        let allItems = HUDMetricBuilder.inlineMetrics(from: snapshot, config: config)
        var row1 = allItems.filter { !$0.isNetwork }
        var row2 = allItems.filter { $0.isNetwork }

        if row1.isEmpty || row2.isEmpty {
            let split = (allItems.count + 1) / 2
            row1 = Array(allItems.prefix(split))
            row2 = Array(allItems.dropFirst(split))
        }

        var x1: CGFloat = 10
        let y1: CGFloat = rect.minY + 7
        let dotColor = pulseOn
            ? UIColor(red: 0.22, green: 0.95, blue: 0.55, alpha: 1.0)
            : UIColor(red: 0.16, green: 0.58, blue: 0.35, alpha: 1.0)
        dotColor.setFill()
        UIBezierPath(ovalIn: CGRect(x: x1, y: y1 + 5, width: 5.5, height: 5.5)).fill()
        x1 += 10

        let compactR1 = (x1 + Self.measureInlineWidth(items: row1, labelSize: 9.0, valueSize: 12.5)) > (rect.width - 8)
        for (idx, item) in row1.enumerated() {
            if idx > 0 {
                x1 = drawDivider(at: x1, in: CGRect(x: 0, y: y1, width: 0, height: 18))
            }
            if x1 >= rect.maxX - 18 { break }
            x1 = drawStatInline(
                x: x1,
                y: y1,
                label: item.label,
                value: item.value,
                valueColor: item.color,
                labelFontSize: compactR1 ? 8.0 : 9.0,
                valueFontSize: compactR1 ? 11.0 : 12.5
            )
        }

        var x2: CGFloat = 10
        let y2: CGFloat = rect.minY + 30
        let compactR2 = (x2 + Self.measureInlineWidth(items: row2, labelSize: 9.0, valueSize: 12.5)) > (rect.width - 8)
        for (idx, item) in row2.enumerated() {
            if idx > 0 {
                x2 = drawDivider(at: x2, in: CGRect(x: 0, y: y2, width: 0, height: 18))
            }
            if x2 >= rect.maxX - 18 { break }
            x2 = drawStatInline(
                x: x2,
                y: y2,
                label: item.label,
                value: item.value,
                valueColor: item.color,
                labelFontSize: compactR2 ? 8.0 : 9.0,
                valueFontSize: compactR2 ? 11.0 : 12.5
            )
        }
    }

    // MARK: - Mode 3: Compact Grid (Grade Dinâmica Responsiva)

    private static func drawCompactHUD(
        in rect: CGRect,
        snapshot: TelemetrySnapshot,
        config: TelemetryVisibilityConfig,
        pulseOn: Bool
    ) {
        drawTranslucentPill(in: rect, cornerRadius: 10, bgAlpha: 0.65)
        drawHeader(in: CGRect(x: 12, y: 7, width: rect.width - 24, height: 18), snapshot: snapshot, pulseOn: pulseOn)

        let cards = Array(HUDMetricBuilder.cardMetrics(from: snapshot, config: config).prefix(12))
        let pad: CGFloat = 10
        let gap: CGFloat = 6
        let startY: CGFloat = 28
        let rows = max(1, Int(ceil(Double(cards.count) / 4.0)))
        let totalHeight = rect.height - startY - 8
        let rowHeight = (totalHeight - CGFloat(rows - 1) * gap) / CGFloat(rows)

        for row in 0..<rows {
            let startIdx = row * 4
            let endIdx = min(startIdx + 4, cards.count)
            let rowCards = Array(cards[startIdx..<endIdx])
            let cols = CGFloat(rowCards.count)
            let tileW = (rect.width - pad * 2 - gap * (cols - 1)) / cols
            let y = startY + CGFloat(row) * (rowHeight + gap)

            for (col, card) in rowCards.enumerated() {
                let x = pad + CGFloat(col) * (tileW + gap)
                drawMiniCard(
                    in: CGRect(x: x, y: y, width: tileW, height: rowHeight),
                    label: card.label,
                    value: card.value,
                    subtitle: truncate(card.subtitle, maxLength: cols <= 2 ? 24 : 14),
                    accent: card.accent,
                    progress: card.progress
                )
            }
        }
    }

    // MARK: - Mode 4: Detailed HUD (Completo com Ranking Térmico)

    private static func drawDetailedHUD(
        in rect: CGRect,
        snapshot: TelemetrySnapshot,
        config: TelemetryVisibilityConfig,
        pulseOn: Bool
    ) {
        drawTranslucentPill(in: rect, cornerRadius: 12, bgAlpha: 0.68)
        drawHeader(in: CGRect(x: 14, y: 9, width: rect.width - 28, height: 18), snapshot: snapshot, pulseOn: pulseOn)

        let pad: CGFloat = 12
        let gap: CGFloat = 8
        let topY: CGFloat = 32
        let topH: CGFloat = 62

        let topCards = Array(HUDMetricBuilder.cardMetrics(from: snapshot, config: config).prefix(3))
        let cols = CGFloat(max(1, topCards.count))
        let tileW = (rect.width - pad * 2 - gap * (cols - 1)) / cols

        for (idx, card) in topCards.enumerated() {
            let x = pad + CGFloat(idx) * (tileW + gap)
            drawMiniCard(
                in: CGRect(x: x, y: topY, width: tileW, height: topH),
                label: card.label,
                value: card.value,
                subtitle: truncate(card.subtitle, maxLength: cols == 1 ? 32 : 20),
                accent: card.accent,
                progress: card.progress
            )
        }

        let panelY: CGFloat = topY + topH + 8
        let panelH: CGFloat = rect.height - panelY - 10
        let showThermalsPanel = config.showCPUTemp || config.showGPUTemp || config.showThermalState
        let detailRows = HUDMetricBuilder.detailRows(from: snapshot, config: config)
        let showRightPanel = !detailRows.isEmpty || !showThermalsPanel

        if showThermalsPanel && showRightPanel {
            let leftW: CGFloat = (rect.width - pad * 2 - gap) * 0.55
            let rightW: CGFloat = (rect.width - pad * 2 - gap) - leftW
            drawThermalRankingBox(in: CGRect(x: pad, y: panelY, width: leftW, height: panelH), snapshot: snapshot)
            drawDetailRowsBox(
                in: CGRect(x: pad + leftW + gap, y: panelY, width: rightW, height: panelH),
                rows: detailRows
            )
        } else if showThermalsPanel {
            drawThermalRankingBox(in: CGRect(x: pad, y: panelY, width: rect.width - pad * 2, height: panelH), snapshot: snapshot)
        } else {
            drawDetailRowsBox(in: CGRect(x: pad, y: panelY, width: rect.width - pad * 2, height: panelH), rows: detailRows)
        }
    }

    private static func drawThermalRankingBox(in leftRect: CGRect, snapshot: TelemetrySnapshot) {
        drawPanelBox(in: leftRect)
        drawText(
            L10n.tr("THERMAL SENSORS"),
            in: CGRect(x: leftRect.minX + 8, y: leftRect.minY + 6, width: leftRect.width - 16, height: 12),
            font: .systemFont(ofSize: 8.5, weight: .bold),
            color: UIColor(white: 0.65, alpha: 1.0)
        )

        let sensors = Array(snapshot.topThermalSensors.prefix(4))
        let rowStartY = leftRect.minY + 20
        let rowStep: CGFloat = 19
        for (idx, sensor) in sensors.enumerated() {
            let y = rowStartY + CGFloat(idx) * rowStep
            drawText(
                truncate(sensor.name, maxLength: 24),
                in: CGRect(x: leftRect.minX + 8, y: y, width: leftRect.width - 64, height: 15),
                font: .monospacedSystemFont(ofSize: 10, weight: .medium),
                color: UIColor(white: 0.88, alpha: 1.0)
            )
            drawText(
                String(format: "%.1f°C", sensor.temperature),
                in: CGRect(x: leftRect.maxX - 54, y: y, width: 46, height: 15),
                font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .bold),
                color: HUDMetricBuilder.temperatureColor(sensor.temperature),
                alignment: .right
            )
        }
    }

    private static func drawDetailRowsBox(in rightRect: CGRect, rows: [HUDSystemRowMetric]) {
        drawPanelBox(in: rightRect)
        drawText(
            L10n.tr("ACTIVE METRICS"),
            in: CGRect(x: rightRect.minX + 8, y: rightRect.minY + 6, width: rightRect.width - 16, height: 12),
            font: .systemFont(ofSize: 8.5, weight: .bold),
            color: UIColor(white: 0.65, alpha: 1.0)
        )

        let rowStartY = rightRect.minY + 20
        let rowStep: CGFloat = 19
        for (idx, row) in rows.prefix(4).enumerated() {
            let y = rowStartY + CGFloat(idx) * rowStep
            drawText(
                row.label,
                in: CGRect(x: rightRect.minX + 8, y: y, width: 78, height: 15),
                font: .systemFont(ofSize: 10, weight: .medium),
                color: UIColor(white: 0.70, alpha: 1.0)
            )
            drawText(
                row.value,
                in: CGRect(x: rightRect.minX + 86, y: y, width: rightRect.width - 94, height: 15),
                font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .bold),
                color: row.color,
                alignment: .right
            )
        }
    }

    // MARK: - Helper Drawing Primitives

    private static func measureInlineWidth(items: [HUDInlineMetric], labelSize: CGFloat, valueSize: CGFloat) -> CGFloat {
        let labelFont = UIFont.systemFont(ofSize: labelSize, weight: .bold)
        let valFont = UIFont.monospacedDigitSystemFont(ofSize: valueSize, weight: .bold)
        var total: CGFloat = 0
        for (idx, item) in items.enumerated() {
            if idx > 0 { total += 7 }
            let lw = (item.label as NSString).size(withAttributes: [.font: labelFont]).width
            let vw = (item.value as NSString).size(withAttributes: [.font: valFont]).width
            total += lw + 4 + vw + 6
        }
        return total
    }

    private static func drawTranslucentPill(in rect: CGRect, cornerRadius: CGFloat, bgAlpha: CGFloat) {
        let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: cornerRadius)
        UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: bgAlpha).setFill()
        path.fill()

        UIColor(white: 1.0, alpha: 0.16).setStroke()
        path.lineWidth = 0.8
        path.stroke()
    }

    private static func drawPanelBox(in rect: CGRect) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 7)
        UIColor(white: 1.0, alpha: 0.06).setFill()
        path.fill()
        UIColor(white: 1.0, alpha: 0.08).setStroke()
        path.lineWidth = 0.6
        path.stroke()
    }

    private static func drawStatInline(
        x: CGFloat,
        y: CGFloat,
        label: String,
        value: String,
        valueColor: UIColor,
        labelFontSize: CGFloat = 9,
        valueFontSize: CGFloat = 12.5
    ) -> CGFloat {
        let labelFont = UIFont.systemFont(ofSize: labelFontSize, weight: .bold)
        let labelColor = UIColor(white: 0.60, alpha: 1.0)
        let labelAttr: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: labelColor]
        let labelSize = (label as NSString).size(withAttributes: labelAttr)
        (label as NSString).draw(at: CGPoint(x: x, y: y + 3), withAttributes: labelAttr)

        let valX = x + labelSize.width + 4
        let valFont = UIFont.monospacedDigitSystemFont(ofSize: valueFontSize, weight: .bold)
        let valAttr: [NSAttributedString.Key: Any] = [.font: valFont, .foregroundColor: valueColor]
        let valSize = (value as NSString).size(withAttributes: valAttr)
        (value as NSString).draw(at: CGPoint(x: valX, y: y + 1), withAttributes: valAttr)

        return valX + valSize.width + 6
    }

    private static func drawDivider(at x: CGFloat, in rect: CGRect) -> CGFloat {
        let divRect = CGRect(x: x, y: rect.midY - 6, width: 1, height: 12)
        UIColor(white: 1.0, alpha: 0.18).setFill()
        UIBezierPath(rect: divRect).fill()
        return x + 7
    }

    private static func drawMiniCard(
        in rect: CGRect,
        label: String,
        value: String,
        subtitle: String,
        accent: UIColor,
        progress: Double
    ) {
        drawPanelBox(in: rect)

        drawText(
            label,
            in: CGRect(x: rect.minX + 6, y: rect.minY + 5, width: rect.width - 12, height: 11),
            font: .systemFont(ofSize: 8, weight: .bold),
            color: UIColor(white: 0.60, alpha: 1.0)
        )

        drawText(
            value,
            in: CGRect(x: rect.minX + 6, y: rect.minY + 16, width: rect.width - 12, height: 18),
            font: .monospacedDigitSystemFont(ofSize: 15, weight: .bold),
            color: accent
        )

        drawText(
            subtitle,
            in: CGRect(x: rect.minX + 6, y: rect.maxY - 20, width: rect.width - 12, height: 11),
            font: .systemFont(ofSize: 8, weight: .medium),
            color: UIColor(white: 0.70, alpha: 1.0)
        )

        let barRect = CGRect(x: rect.minX + 6, y: rect.maxY - 7, width: rect.width - 12, height: 3)
        let clamped = CGFloat(min(1.0, max(0.04, progress)))
        UIColor(white: 1.0, alpha: 0.10).setFill()
        UIBezierPath(roundedRect: barRect, cornerRadius: 1.5).fill()

        let fillRect = CGRect(x: barRect.minX, y: barRect.minY, width: barRect.width * clamped, height: barRect.height)
        accent.setFill()
        UIBezierPath(roundedRect: fillRect, cornerRadius: 1.5).fill()
    }

    private static func drawHeader(in rect: CGRect, snapshot: TelemetrySnapshot, pulseOn: Bool) {
        let dotColor = pulseOn
            ? UIColor(red: 0.22, green: 0.95, blue: 0.55, alpha: 1.0)
            : UIColor(red: 0.16, green: 0.58, blue: 0.35, alpha: 1.0)
        let dotRect = CGRect(x: rect.minX, y: rect.midY - 2.5, width: 5.5, height: 5.5)
        dotColor.setFill()
        UIBezierPath(ovalIn: dotRect).fill()

        drawText(
            "ARKDIEHUD",
            in: CGRect(x: rect.minX + 9, y: rect.minY + 2, width: 100, height: 14),
            font: .systemFont(ofSize: 9.5, weight: .heavy),
            color: UIColor(white: 0.85, alpha: 1.0)
        )

        let timeStr = timeFormatter.string(from: snapshot.timestamp)
        drawText(
            timeStr,
            in: CGRect(x: rect.maxX - 60, y: rect.minY + 2, width: 60, height: 14),
            font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
            color: UIColor(white: 0.65, alpha: 1.0),
            alignment: .right
        )
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static func truncate(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength - 1)) + "…"
    }
}
