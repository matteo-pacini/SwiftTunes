import SwiftUI
import TunesContract
import TunesPanel

/// NOW PLAYING as the hero, UP NEXT as a shelf, COMPOSER as a glass bar.
struct PlayerView: View {
    let card: PlayerCard
    let model: PanelModel

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 14) {
                if let strip = card.strip { Strip(text: strip) }
                Hero(now: card.now, model: model)
                Shelf(next: card.next, palette: card.palette, model: model)
                ComposerBar(composer: card.composer, model: model)
            }
        }
    }
}

struct Hero: View {
    let now: PlayerCard.Now
    let model: PanelModel
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Caps(text: now.label)
                Spacer()
                Button(action: model.openChooser) {
                    HStack(spacing: 5) {
                        Text(verbatim: now.genre.text)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .helped(now.genre)
            }
            if let wave = now.wave {
                title
                SeekableWave(wave: wave, seek: model.seek(fraction:))
                if let time = now.time {
                    HStack {
                        Text(verbatim: time.left).contentTransition(.numericText())
                        Spacer()
                        Text(verbatim: time.right)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, -6)
                    .animation(reduceMotion ? nil : .default, value: time.left)
                }
            } else if let stage = now.forming {
                title
                DotWave(levels: [], forming: stage, dot: .primary.opacity(0.3), lit: .primary)
                    .frame(height: 60)
                    .accessibilityHidden(true)
            } else {
                ContentUnavailableView {
                    Text(verbatim: now.title).font(.system(size: 19, weight: .bold, design: .rounded))
                } description: {
                    if !now.meta.isEmpty { Text(verbatim: now.meta).font(.system(size: 12.5)) }
                }
                .padding(.vertical, -8)
            }
            controls
        }
    }

    private var title: some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: now.title)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(now.titleTone.color)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if !now.badge.isEmpty {
                    Text(verbatim: "★").font(.system(size: 13)).foregroundStyle(.secondary)
                        .accessibilityLabel(Text(verbatim: now.badge))
                        .help(now.badge)
                }
            }
            if !now.meta.isEmpty {
                Text(verbatim: now.meta).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            RoundButton(symbol: "shuffle", control: now.shuffle, action: model.shuffle)
            RoundButton(symbol: now.repeatsOne ? "repeat.1" : "repeat", control: now.repeat, action: model.cycleRepeat)
            Button(action: model.playPause) {
                Image(systemName: now.showsPause ? "pause.fill" : "play.fill")
                    .font(.system(size: 21, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    .frame(width: 52, height: 52)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.primary).interactive(), in: .circle)
            .glassEffectID("main", in: glass)
            .disabled(!now.playPause.enabled)
            .opacity(now.playPause.enabled ? 1 : 0.38)
            .helped(now.playPause)
            RoundButton(symbol: "forward.end.fill", control: now.next, action: model.next)
            RoundButton(symbol: "square.and.arrow.up", control: now.share) { model.openShare(now.shareRequest) }
            RoundButton(symbol: "trash", control: now.scrap) { model.send(now.scrapCommand) }
        }
        .animation(reduceMotion ? nil : .smooth, value: now.showsPause)
    }
}

/// UP NEXT: at most three cards.
struct Shelf: View {
    let next: PlayerCard.Next
    let palette: Palette
    let model: PanelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Caps(text: "UP NEXT")
                Spacer()
                Text(verbatim: next.head).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            if !next.rows.isEmpty {
                HStack(spacing: 8) {
                    ForEach(next.rows, id: \.id) { row in
                        ShelfCard(row: row, palette: palette, model: model)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.2), value: next.rows.map(\.id))
            }
        }
    }
}

struct ShelfCard: View {
    let row: PlayerCard.Row
    let palette: Palette
    let model: PanelModel
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            art
                .frame(height: 54)
                .overlay(alignment: .topLeading) {
                    if !row.tag.isEmpty {
                        Text(verbatim: row.tag.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: .rect(cornerRadius: 4))
                            .padding(6)
                    }
                }
                .overlay {
                    if hovered { actions }
                }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(verbatim: row.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    if row.star { Text(verbatim: "★").font(.system(size: 10)).foregroundStyle(.secondary) }
                }
                Text(verbatim: line).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .foregroundStyle(row.kind == .placeholder ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if row.kind == .placeholder {
                RoundedRectangle(cornerRadius: 13).strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .glassEffect(row.kind == .placeholder ? .identity : .regular, in: .rect(cornerRadius: 13))
        .opacity(row.dim ? 0.5 : 1)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
    }

    private var line: String {
        [row.sub, row.kind == .tune ? row.right : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder private var art: some View {
        switch row.kind {
        case .tune: ArtworkView(artwork: row.artwork, palette: palette)
        case .job: ArtworkView(artwork: nil, palette: palette, stage: row.stage)
        case .placeholder:
            RoundedRectangle(cornerRadius: 9).strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            if let c = row.playNow { RoundButton(symbol: "play.fill", control: c, size: 26) { model.send(row.playNowCommand) } }
            if let c = row.share { RoundButton(symbol: "square.and.arrow.up", control: c, size: 26) { model.openShare(row.shareRequest) } }
            if let c = row.scrap { RoundButton(symbol: "trash", control: c, size: 26) { model.send(row.scrapCommand) } }
        }
    }
}

/// COMPOSER: the label, the state as a pill, the switch; the lines under it.
struct ComposerBar: View {
    let composer: PlayerCard.Composer
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Caps(text: "COMPOSER")
                Spacer()
                if let pill = composer.pill { Pill(text: pill) }
                Toggle(isOn: Binding(get: { composer.on }, set: { _ in model.toggleComposer() })) {
                    Text(verbatim: composer.toggle.help)
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(composer.labelTone == .orange ? Tone.orange.color : composer.labelTone == .red ? Tone.red.color : .green)
                .helped(composer.toggle)
            }
            ForEach(Array(composer.lines.enumerated()), id: \.offset) { i, line in
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Text(verbatim: line.pre))\(Text(verbatim: line.em).bold())\(Text(verbatim: line.post))")
                        .font(.system(size: i == 0 ? 13 : 11.5))
                        .foregroundStyle(i == 0 ? Tone.normal.color : line.tone == .dim ? Tone.soft.color : line.tone.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if i == composer.lines.count - 1, let retry = composer.retry {
                        Button(action: model.retry) { Text(verbatim: retry.text) }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .helped(retry)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 15))
    }
}
