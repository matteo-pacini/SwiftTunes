import SwiftUI
import TunesContract
import TunesPanel

// MARK: - Setup

struct SetupView: View {
    let card: SetupCard
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: card.title).font(.system(size: 20, weight: .bold, design: .rounded))
            Text(verbatim: card.detail).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !card.models.isEmpty {
                VStack(spacing: 0) {
                    ForEach(card.models, id: \.id) { choice in
                        if choice.id != card.models.first?.id { Divider() }
                        ChoiceRow(choice: choice, model: model)
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 13))
                Text(verbatim: card.modelsNote).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let progress = card.progress {
                ProgressView(value: progress).progressViewStyle(.linear)
            }
            if !card.rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(card.rows.enumerated()), id: \.offset) { i, row in
                        if i > 0 { Divider() }
                        HStack {
                            Text(verbatim: row.label).foregroundStyle(.secondary)
                            Spacer()
                            Text(verbatim: row.value).contentTransition(.numericText())
                        }
                        .font(.system(size: 12.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 13))
            }
            HStack {
                Spacer()
                Button { model.send(card.command) } label: { Text(verbatim: card.button.text) }
                    .buttonStyle(card.kind == .downloading ? AnyPrimitiveButtonStyle(.glass) : AnyPrimitiveButtonStyle(.glassProminent))
                    .helped(card.button)
            }
        }
    }
}

/// One model on the first run: the round mark, the name and variant, the
/// suggestion, the sizes. A click chooses it.
struct ChoiceRow: View {
    let choice: SetupCard.Choice
    let model: PanelModel
    @State private var hovered = false

    var body: some View {
        Button { model.send(choice.command) } label: {
            HStack(spacing: 10) {
                Image(systemName: choice.chosen ? "largecircle.fill.circle" : "circle").font(.system(size: 14))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(verbatim: choice.name).font(.system(size: 12.5, weight: .semibold))
                        Text(verbatim: choice.variant).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if !choice.tag.isEmpty { Pill(text: choice.tag) }
                    }
                    Text(verbatim: choice.sub).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(hovered ? Color.primary.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .helped(choice.control)
        .onHover { hovered = $0 }
    }
}

/// A button style chosen at run time.
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

// MARK: - Music models

struct ModelsView: View {
    let card: ModelsCard
    let model: PanelModel

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    BackLink(control: card.back, action: model.backToPlayer)
                    Spacer()
                    Caps(text: card.label)
                }
                Text(verbatim: card.title).font(.system(size: 20, weight: .bold, design: .rounded))
                Text(verbatim: card.detail).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !card.rows.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(card.rows, id: \.id) { row in
                            if row.id != card.rows.first?.id { Divider() }
                            ModelRow(row: row, model: model)
                        }
                    }
                    .glassEffect(.regular, in: .rect(cornerRadius: 13))
                }
                Text(verbatim: card.footnote).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One model: the tick, the name and variant, its sizes or its download,
/// its buttons.
struct ModelRow: View {
    let row: ModelsCard.Row
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(row.ticked ? 1 : 0)
                    .accessibilityHidden(!row.ticked)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(verbatim: row.name).font(.system(size: 12.5, weight: .semibold))
                        Text(verbatim: row.variant).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(verbatim: row.sub).font(.system(size: 11.5)).foregroundStyle(.secondary).contentTransition(.numericText())
                }
                Spacer(minLength: 0)
                ForEach(row.buttons, id: \.control.text) { button in
                    Button { model.press(button) } label: { Text(verbatim: button.control.text) }
                        .buttonStyle(button.kind == .download || button.kind == .resume ? AnyPrimitiveButtonStyle(.glassProminent) : AnyPrimitiveButtonStyle(.glass))
                        .controlSize(.small)
                        .disabled(!button.control.enabled)
                        .helped(button.control)
                }
            }
            if let progress = row.progress {
                ProgressView(value: progress).progressViewStyle(.linear)
            }
            if !row.error.isEmpty {
                Text(verbatim: row.error).font(.system(size: 11.5)).foregroundStyle(Tone.red.color).fixedSize(horizontal: false, vertical: true)
            }
        }
        .groupedRow()
    }
}

// MARK: - Chooser

struct ChooserView: View {
    let card: ChooserCard
    let model: PanelModel
    let space: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let back = card.back {
                BackLink(control: back, action: model.backToPlayer)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: card.title).font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                Pill(text: card.chip)
            }
            if let strip = card.strip { Strip(text: strip) }
            if !card.empty.isEmpty {
                ContentUnavailableView {
                    Label { Text(verbatim: card.empty) } icon: { Image(systemName: "music.note.list") }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(card.cells, id: \.id) { cell in
                    GenreTile(cell: cell, palette: model.palette(ofGenre: cell.id), model: model, space: space)
                }
                Button(action: model.addGenre) {
                    Text(verbatim: card.add.text)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 74)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                        .contentShape(.rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .helped(card.add)
            }
        }
    }
}

struct GenreTile: View {
    let cell: ChooserCard.Cell
    let palette: Palette
    let model: PanelModel
    let space: Namespace.ID
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.5)) { model.pick(cell.id) }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Spacer(minLength: 0)
                Text(verbatim: cell.name).font(.system(size: 13.5, weight: .bold, design: .rounded)).lineLimit(1)
                Text(verbatim: cell.sub).font(.system(size: 11)).opacity(0.75).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .background {
                Backdrop(palette: palette)
                    .environment(\.colorScheme, .dark)
                    .matchedGeometryEffect(id: cell.id, in: space)
            }
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                if cell.current { RoundedRectangle(cornerRadius: 14).strokeBorder(.white, lineWidth: 2.5) }
            }
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .helped(cell.pick)
        .overlay(alignment: .topTrailing) {
            if hovered {
                Button { model.editGenre(cell.id) } label: {
                    Image(systemName: "pencil").font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .padding(5)
                .helped(cell.edit)
            }
        }
        .onHover { hovered = $0 }
    }
}

// MARK: - Editor

struct EditorView: View {
    let card: EditorCard
    let model: PanelModel
    @FocusState private var focus: EditorField?

    var body: some View {
        if let ask = card.ask {
            AskView(ask: ask, model: model)
        } else {
            form
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BackLink(control: card.back, action: model.cancelEdit)
                Spacer()
                if !card.chip.isEmpty { Pill(text: card.chip) }
            }
            Text(verbatim: card.title).font(.system(size: 20, weight: .bold, design: .rounded)).lineLimit(1)
            // Grouped rows drawn by hand: a grouped form is a SwiftUI
            // scrolling list, and in the popover those block the main thread
            // in the renderer's surface allocation (CAContext
            // waitForCommitId), stalling main-actor work for seconds.
            VStack(spacing: 0) {
                row(card.name, .name) {
                    TextField(text: binding(.name), prompt: Text(verbatim: card.name.placeholder)) { Text(verbatim: card.name.label) }
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .focused($focus, equals: .name)
                }
                Divider()
                row(card.caption, .caption) {
                    TextField(text: binding(.caption), prompt: Text(verbatim: card.caption.placeholder), axis: .vertical) { Text(verbatim: card.caption.label) }
                        .labelsHidden()
                        .lineLimit(1...4)
                        .multilineTextAlignment(.trailing)
                        .focused($focus, equals: .caption)
                }
                Divider()
                // Variations run to 120 characters a line: the box takes the
                // row's whole width under its label, not the right-hand half.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: card.turns.label)
                        Spacer()
                        Text(verbatim: card.turns.side).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    PlainTextEditor(text: card.values.turns, fontSize: 12.5, label: card.turns.label) { text, _ in
                        if text != card.values.turns { model.type(.turns, text) }
                    }
                        .frame(height: 64)
                        .overlay(alignment: .topLeading) {
                            if card.values.turns.isEmpty {
                                Text(verbatim: card.turns.placeholder).foregroundStyle(.tertiary).padding(.leading, 5).allowsHitTesting(false)
                            }
                        }
                    if !card.turns.error.isEmpty { error(card.turns.error) }
                }
                .groupedRow()
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(verbatim: "Tempo")
                        Spacer()
                        tempo(.slowest, card.slowest)
                        Text(verbatim: "to").foregroundStyle(.secondary)
                        tempo(.fastest, card.fastest)
                        Text(verbatim: "BPM").foregroundStyle(.secondary)
                    }
                    if !card.tempoError.isEmpty { error(card.tempoError) }
                }
                .groupedRow()
                Divider()
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: card.singing.label)
                        Text(verbatim: card.singing.sub).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle(isOn: Binding(get: { card.singing.on }, set: { _ in model.toggleSung() })) { Text(verbatim: card.singing.label) }
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                }
                .groupedRow()
                Divider()
                HStack {
                    Text(verbatim: card.coloursLabel)
                    Spacer()
                    ForEach(0..<card.colours.count, id: \.self) { i in
                        ColorPicker(selection: colour(i), supportsOpacity: false) { Text(verbatim: "\(card.coloursLabel) \(i + 1)") }
                            .labelsHidden()
                            .controlSize(.small)
                    }
                }
                .groupedRow()
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .glassEffect(.regular, in: .rect(cornerRadius: 13))
            Text(verbatim: card.hint).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if let delete = card.delete {
                    Button(role: .destructive, action: model.askDelete) {
                        Text(verbatim: delete.text).foregroundStyle(Tone.red.color).fontWeight(.semibold)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!delete.enabled)
                    .helped(delete)
                }
                Spacer()
                Button(action: model.cancelEdit) { Text(verbatim: card.cancel.text) }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                    .helped(card.cancel)
                Button(action: model.save) { Text(verbatim: card.save.text) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!card.save.enabled)
                    .helped(card.save)
            }
        }
        .disabled(card.loading)
        .onAppear { focus = .name }
    }

    private func row<C: View>(_ field: EditorCard.Field, _ which: EditorField, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: field.label)
                    if !field.side.isEmpty { Text(verbatim: field.side).font(.system(size: 10.5)).foregroundStyle(.secondary) }
                }
                .fixedSize()
                Spacer(minLength: 0)
                content()
            }
            .accessibilityLabel(Text(verbatim: field.label))
            if !field.error.isEmpty { error(field.error) }
        }
        .groupedRow()
    }

    private func error(_ text: String) -> some View {
        Text(verbatim: text).font(.system(size: 11.5)).foregroundStyle(Tone.red.color).fixedSize(horizontal: false, vertical: true)
    }

    private func tempo(_ which: EditorField, _ field: EditorCard.Field) -> some View {
        TextField(text: binding(which), prompt: Text(verbatim: "")) { Text(verbatim: field.label) }
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 44)
            .focused($focus, equals: which)
            .padding(.horizontal, 4)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(field.bad ? Tone.red.color : .clear))
            .accessibilityLabel(Text(verbatim: field.label))
    }

    private func binding(_ field: EditorField) -> Binding<String> {
        Binding(
            get: {
                switch field {
                case .name: card.values.name
                case .caption: card.values.caption
                case .turns: card.values.turns
                case .slowest: card.values.slowest
                case .fastest: card.values.fastest
                }
            },
            set: { model.type(field, $0) }
        )
    }

    private func colour(_ i: Int) -> Binding<Color> {
        Binding(
            get: { (RGB(hex: card.colours[i]) ?? RGB(0, 0, 0)).color },
            set: { model.pickColour(i, hex: RGB($0).hex, shown: card.colours) }
        )
    }
}

struct AskView: View {
    let ask: EditorCard.Ask
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: ask.title).font(.system(size: 20, weight: .bold, design: .rounded))
            Text(verbatim: ask.detail).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !ask.error.isEmpty {
                Text(verbatim: ask.error).font(.system(size: 11.5)).foregroundStyle(Tone.red.color).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                Button(action: model.keepGenre) { Text(verbatim: ask.keep.text) }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                    .disabled(!ask.keep.enabled)
                    .helped(ask.keep)
                Button(role: .destructive, action: model.deleteGenre) {
                    Text(verbatim: ask.delete.text).foregroundStyle(Tone.red.color)
                }
                .buttonStyle(.glass)
                .disabled(!ask.delete.enabled)
                .helped(ask.delete)
            }
        }
    }
}

// MARK: - Share sheet

struct ShareView: View {
    let card: ShareCard
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BackLink(control: card.back, action: model.closeShare)
                Spacer()
                Caps(text: "SHARE")
            }
            HStack(spacing: 12) {
                picture
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: card.name).font(.system(size: 19, weight: .bold, design: .rounded)).lineLimit(2)
                    Text(verbatim: card.meta.isEmpty ? " " : card.meta).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(verbatim: card.hint).font(.system(size: 11.5)).foregroundStyle(.tertiary).padding(.top, 2)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(card.rows.enumerated()), id: \.offset) { i, row in
                    if i > 0 { Divider().padding(.horizontal, 12) }
                    ShareRow(row: row, file: card.file, model: model)
                }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 13))
        }
    }

    @ViewBuilder private var picture: some View {
        let art = ArtworkView(artwork: card.artwork, palette: Decide.palette(model.snapshot), corner: 14)
            .frame(width: 74, height: 74)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        if let file = card.file {
            art.draggable(file) {
                ArtworkView(artwork: card.artwork, palette: Decide.palette(model.snapshot), corner: 14).frame(width: 74, height: 74)
            }
            .helped(Control(help: card.hint))
        } else {
            art
        }
    }
}

struct ShareRow: View {
    let row: ShareCard.Row
    let file: URL?
    let model: PanelModel
    @State private var hovered = false

    var body: some View {
        if row.action == .share, let file {
            ShareLink(item: file) { label }
                .buttonStyle(.plain)
                .disabled(!row.control.enabled)
                .helped(row.control)
                .onHover { hovered = $0 }
        } else if let on = row.on {
            HStack {
                text
                Spacer(minLength: 0)
                Toggle(isOn: Binding(get: { on }, set: { _ in model.shareAction(row.action) })) { Text(verbatim: row.title) }
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(!row.control.enabled)
                    .helped(row.control)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } else {
            Button { model.shareAction(row.action) } label: { label }
                .buttonStyle(.plain)
                .disabled(!row.control.enabled)
                .helped(row.control)
                .onHover { hovered = $0 }
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: row.title).font(.system(size: 12.5))
            if !row.sub.isEmpty {
                Text(verbatim: row.sub).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            }
        }
    }

    private var label: some View {
        HStack {
            text
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(hovered && row.control.enabled ? Color.primary.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .opacity(row.control.enabled ? 1 : 0.5)
    }
}

extension View {
    /// The padding of one row in a glass group.
    func groupedRow() -> some View {
        padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
    }
}
