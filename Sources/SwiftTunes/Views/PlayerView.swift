import SwiftUI
import TunesContract
import TunesPanel

/// NOW PLAYING as the hero, UP NEXT as a list, COMPOSER as a glass bar.
struct PlayerView: View {
    let card: PlayerCard
    let model: PanelModel

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 14) {
                if let strip = card.strip { Strip(text: strip) }
                Hero(now: card.now, model: model)
                UpNext(next: card.next, palette: card.palette, model: model)
                if let making = card.making { MakingBlock(making: making, palette: card.palette, model: model) }
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
            if let rename = now.rename {
                RenameField(field: rename, model: model)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    name
                    if !now.badge.isEmpty {
                    Text(verbatim: "★").font(.system(size: 13)).foregroundStyle(.secondary)
                        .accessibilityLabel(Text(verbatim: now.badge))
                        .help(now.badge)
                    }
                }
            }
            if !now.meta.isEmpty {
                Text(verbatim: now.meta).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var name: some View {
        let text = Text(verbatim: now.title)
            .font(.system(size: 25, weight: .bold, design: .rounded))
            .foregroundStyle(now.titleTone.color)
            .lineLimit(2)
            .multilineTextAlignment(.center)
        if let control = now.titleControl {
            Button(action: model.beginRename) { text }
                .buttonStyle(.plain)
                .helped(control)
        } else {
            text
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

/// UP NEXT: at most three rows, read top to bottom in play order.
struct UpNext: View {
    let next: PlayerCard.Next
    let palette: Palette
    let model: PanelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Caps(text: "UP NEXT")
                Spacer()
                Text(verbatim: next.head).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            ForEach(next.rows, id: \.id) { row in
                UpNextRow(row: row, palette: palette, model: model)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let more = next.more {
                Button(action: model.openQueue) {
                    Text(verbatim: more.text)
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .helped(more)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.2), value: next.rows.map(\.id))
    }
}

/// BEING MADE: the job and the places not started.
struct MakingBlock: View {
    let making: PlayerCard.Making
    let palette: Palette
    let model: PanelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Caps(text: "BEING MADE")
                Spacer()
                Text(verbatim: making.head).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            ForEach(making.rows, id: \.id) { row in
                UpNextRow(row: row, palette: palette, model: model)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.2), value: making.rows.map(\.id))
    }
}

/// Everything that will play this round, numbered, in a scrolling list,
/// with BEING MADE under it.
struct QueueView: View {
    let card: QueueCard
    let model: PanelModel

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    BackLink(control: card.back, action: model.backToPlayer)
                    Spacer()
                    Caps(text: card.label)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: card.title).font(.system(size: 20, weight: .bold, design: .rounded))
                    Spacer()
                    Text(verbatim: card.head).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(card.rows, id: \.id) { row in
                            UpNextRow(row: row, palette: card.palette, model: model)
                        }
                        if let last = card.last {
                            Text(verbatim: last).font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.top, 4)
                        }
                    }
                }
                .frame(maxHeight: 340)
                .fixedSize(horizontal: false, vertical: true)
                if let making = card.making { MakingBlock(making: making, palette: card.palette, model: model) }
            }
        }
    }
}

struct UpNextRow: View {
    let row: PlayerCard.Row
    let palette: Palette
    let model: PanelModel
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            if row.kind == .tune {
                Text(verbatim: row.number)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 14)
            }
            art.frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(verbatim: row.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    if row.star { Text(verbatim: "★").font(.system(size: 10)).foregroundStyle(.secondary) }
                    if !row.tag.isEmpty {
                        Text(verbatim: row.tag.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: .rect(cornerRadius: 4))
                    }
                }
                if !row.sub.isEmpty {
                    Text(verbatim: row.sub).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .foregroundStyle(row.kind == .placeholder ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            Spacer(minLength: 0)
            if hovered && (row.playNow != nil || row.share != nil || row.scrap != nil) {
                actions
            } else if row.kind == .tune && !row.right.isEmpty {
                Text(verbatim: row.right).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background {
            if row.kind == .placeholder {
                RoundedRectangle(cornerRadius: 11).strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .glassEffect(row.kind == .placeholder ? .identity : .regular, in: .rect(cornerRadius: 11))
        .opacity(row.dim ? 0.5 : 1)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var art: some View {
        switch row.kind {
        case .tune: ArtworkView(artwork: row.artwork, palette: palette, corner: 7)
        case .job: ArtworkView(artwork: nil, palette: palette, stage: row.stage, corner: 7)
        case .placeholder:
            RoundedRectangle(cornerRadius: 7).strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    private var actions: some View {
        HStack(spacing: 5) {
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

/// The playing tune's name as a text field, with a tick and a cross, and
/// the sentence under it.
struct RenameField: View {
    let field: PlayerCard.RenameField
    let model: PanelModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                TextField(text: Binding(get: { field.text }, set: model.typeName), prompt: Text(verbatim: "")) {
                    Text(verbatim: field.save.help)
                }
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .focused($focused)
                .onSubmit(model.saveRename)
                .onExitCommand(perform: model.cancelRename)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .rect(cornerRadius: 10))
                RoundButton(symbol: "checkmark", control: field.save, size: 28, action: model.saveRename)
                RoundButton(symbol: "xmark", control: field.cancel, size: 28, action: model.cancelRename)
            }
            if !field.error.isEmpty {
                Text(verbatim: field.error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Tone.red.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { focused = true }
    }
}
