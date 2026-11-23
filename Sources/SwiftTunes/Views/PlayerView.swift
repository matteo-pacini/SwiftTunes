import SwiftUI
import TunesContract
import TunesPanel

/// NOW PLAYING, UP NEXT and COMPOSER, separated by hairlines.
struct PlayerView: View {
    let card: PlayerCard
    let model: PanelModel

    var body: some View {
        VStack(spacing: 0) {
            if let strip = card.strip {
                Strip(text: strip).padding(.horizontal, 14).padding(.top, 10)
            }
            NowSection(now: card.now, model: model).padding(.horizontal, 14).padding(.vertical, 12)
            Divider()
            NextSection(next: card.next, model: model).padding(.horizontal, 14).padding(.vertical, 12)
            Divider()
            ComposerSection(composer: card.composer, model: model).padding(.horizontal, 14).padding(.vertical, 12)
        }
    }
}

struct NowSection: View {
    let now: PlayerCard.Now
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(title: "NOW PLAYING") {
                if !now.suffix.isEmpty {
                    Text(verbatim: now.suffix).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Button(action: model.openChooser) {
                    Text(verbatim: "\(now.genre.text) ⌄").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(now.genre.help)
                .accessibilityLabel(Text(verbatim: "\(now.genre.help): \(now.genre.text)"))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: now.title)
                        .font(.system(size: now.wave == nil ? 15 : 17, weight: .semibold))
                        .foregroundStyle(now.titleTone.color)
                        .lineLimit(2)
                    if !now.badge.isEmpty {
                        Text(verbatim: now.badge).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
                if !now.meta.isEmpty {
                    Text(verbatim: now.meta).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            if let wave = now.wave {
                WaveformView(wave: wave, seek: model.seek(fraction:))
            }
            if let time = now.time {
                HStack {
                    Text(verbatim: time.left)
                    Spacer()
                    Text(verbatim: time.right)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                IconButton(symbol: now.showsPause ? "pause.fill" : "play.fill", control: now.playPause, wide: true, action: model.playPause)
                IconButton(symbol: "forward.end.fill", control: now.next, action: model.next)
                Spacer(minLength: 0)
                IconButton(symbol: "shuffle", control: now.shuffle, action: model.shuffle)
                IconButton(symbol: "repeat", control: now.repeat, action: model.cycleRepeat)
                IconButton(symbol: "square.and.arrow.up", control: now.share) { model.openShare(now.shareRequest) }
                IconButton(symbol: "trash", control: now.scrap) { model.send(now.scrapCommand) }
            }
        }
    }
}

/// 78 bars; a click seeks to that point.
struct WaveformView: View {
    let wave: PlayerCard.Wave
    let seek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let n = wave.levels.count
                guard n > 0 else { return }
                let gap = 1.5
                let w = max(0.5, (size.width - gap * Double(n - 1)) / Double(n))
                for (i, level) in wave.levels.enumerated() {
                    let h = max(2, (level * size.height).rounded())
                    let rect = CGRect(x: Double(i) * (w + gap), y: (size.height - h) / 2, width: w, height: h)
                    let style: Color = i < wave.played ? .accentColor : .secondary.opacity(0.35)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(style))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { point in
                seek(geo.size.width > 0 ? point.x / geo.size.width : 0)
            }
        }
        .frame(height: 30)
        .help(wave.help)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: wave.help))
        .accessibilityAddTraits(.isButton)
    }
}

struct NextSection: View {
    let next: PlayerCard.Next
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeading(title: "UP NEXT") {
                Text(verbatim: next.head).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            .padding(.bottom, 5)
            ForEach(next.rows, id: \.id) { row in
                QueueRow(row: row, model: model)
            }
        }
    }
}

/// One row of UP NEXT. The pointer over it shows what it offers.
struct QueueRow: View {
    let row: PlayerCard.Row
    let model: PanelModel
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: row.number)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(verbatim: row.name)
                        .fontWeight(row.kind == .placeholder ? .regular : .medium)
                        .foregroundStyle(row.kind == .placeholder ? AnyShapeStyle(.tertiary) : AnyShapeStyle(row.nameTone.color))
                        .lineLimit(1)
                    if row.star {
                        Text(verbatim: "★").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if !row.tag.isEmpty {
                        Text(verbatim: row.tag.uppercased())
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 1))
                    }
                }
                if !row.sub.isEmpty {
                    Text(verbatim: row.sub).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                if let bar = row.bar {
                    ProgressView(value: bar).progressViewStyle(.linear).tint(Tone.cyan.color).controlSize(.mini)
                }
            }
            Spacer(minLength: 0)
            if hovered && (row.playNow != nil || row.share != nil || row.scrap != nil) {
                HStack(spacing: 4) {
                    if let c = row.playNow {
                        IconButton(symbol: "play.fill", control: c) { model.send(row.playNowCommand) }
                    }
                    if let c = row.share {
                        IconButton(symbol: "square.and.arrow.up", control: c) { model.openShare(row.shareRequest) }
                    }
                    if let c = row.scrap {
                        IconButton(symbol: "trash", control: c) { model.send(row.scrapCommand) }
                    }
                }
                .controlSize(.small)
            } else if !row.right.isEmpty {
                Text(verbatim: row.right).font(.system(size: 11.5)).foregroundStyle(row.rightTone.color)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(hovered && row.kind != .placeholder ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .opacity(row.dim ? 0.5 : 1)
        .onHover { hovered = $0 }
    }
}

struct ComposerSection: View {
    let composer: PlayerCard.Composer
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(title: "COMPOSER") {
                Text(verbatim: composer.label).font(.system(size: 11.5)).foregroundStyle(composer.labelTone.color)
                Toggle(isOn: Binding(get: { composer.on }, set: { _ in model.toggleComposer() })) {
                    Text(verbatim: composer.toggle.help)
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .tint(composer.labelTone == .orange ? .orange : composer.labelTone == .red ? .red : .green)
                .help(composer.toggle.help)
                .accessibilityLabel(Text(verbatim: composer.toggle.help))
            }
            ForEach(Array(composer.lines.enumerated()), id: \.offset) { i, line in
                let last = i == composer.lines.count - 1
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        (Text(verbatim: line.pre) + Text(verbatim: line.em).bold() + Text(verbatim: line.post))
                            .font(.system(size: i == 0 ? 13 : 11.5))
                            .foregroundStyle(i == 0 ? Tone.normal.color : line.tone.color)
                            .fixedSize(horizontal: false, vertical: true)
                        if !line.right.isEmpty {
                            Text(verbatim: line.right).font(.system(size: 11.5)).foregroundStyle(line.rightTone.color)
                        }
                    }
                    Spacer(minLength: 0)
                    if last, let retry = composer.retry {
                        PushButton(control: retry, action: model.retry)
                    }
                }
            }
        }
    }
}
