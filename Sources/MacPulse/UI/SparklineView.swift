import AppKit

/// 簡易折線圖（sparkline）。固定容量的環狀 buffer，繪製時自動正規化到 [0, maxValue]。
final class SparklineView: NSView {
    var lineColor: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    var fillColor: NSColor = NSColor.controlAccentColor.withAlphaComponent(0.18) {
        didSet { needsDisplay = true }
    }

    /// 若為 nil 則用 buffer 內目前最大值動態 scale；給定值則固定 scale。
    var fixedMaxValue: Double?

    private(set) var capacity: Int
    private var samples: [Double] = []

    /// 改變 buffer 容量；若舊資料比新容量多會丟掉最舊的樣本。
    func setCapacity(_ newCapacity: Int) {
        let n = max(2, newCapacity)
        guard n != capacity else { return }
        capacity = n
        if samples.count > n {
            samples.removeFirst(samples.count - n)
        }
        needsDisplay = true
    }

    init(capacity: Int = 60, frame: NSRect = .zero) {
        self.capacity = capacity
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 4
    }

    required init?(coder: NSCoder) {
        self.capacity = 60
        super.init(coder: coder)
    }

    func append(_ value: Double) {
        samples.append(max(0, value))
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        guard rect.width > 0, rect.height > 0 else { return }

        // 背景
        NSColor.quaternaryLabelColor.withAlphaComponent(0.25).setFill()
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
        bg.fill()

        guard samples.count >= 2 else { return }

        let maxV: Double = {
            if let fixed = fixedMaxValue { return max(fixed, 0.0001) }
            let dynamic = samples.max() ?? 1
            return max(dynamic, 0.0001)
        }()

        let stepX = rect.width / CGFloat(capacity - 1)
        let baseX = rect.minX + CGFloat(capacity - samples.count) * stepX

        let line = NSBezierPath()
        let area = NSBezierPath()

        for (i, v) in samples.enumerated() {
            let x = baseX + CGFloat(i) * stepX
            let normalized = CGFloat(min(v / maxV, 1))
            let y = rect.minY + normalized * rect.height
            let pt = NSPoint(x: x, y: y)
            if i == 0 {
                line.move(to: pt)
                area.move(to: NSPoint(x: x, y: rect.minY))
                area.line(to: pt)
            } else {
                line.line(to: pt)
                area.line(to: pt)
            }
        }

        // 收尾 area path 回到底部
        if let lastX = samples.indices.last.map({ baseX + CGFloat($0) * stepX }) {
            area.line(to: NSPoint(x: lastX, y: rect.minY))
            area.close()
        }

        fillColor.setFill()
        area.fill()

        lineColor.setStroke()
        line.lineWidth = 1.4
        line.lineJoinStyle = .round
        line.stroke()
    }
}
