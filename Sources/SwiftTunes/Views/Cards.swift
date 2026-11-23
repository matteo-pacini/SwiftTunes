import SwiftUI
import TunesContract
import TunesPanel

// MARK: - Setup

struct SetupView: View {
    let card: SetupCard
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(verbatim: card.title).font(.system(size: 17, weight: .semibold))
            Text(verbatim: card.detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let progress = card.progress {
                ProgressView(value: progress).progressViewStyle(.linear)
            }
            if !card.rows.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(card.rows, id: \.label) { row in
                        GridRow {
                            Text(verbatim: row.label).foregroundStyle(.secondary)
                            Text(verbatim: row.value).gridColumnAlignment(.trailing).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
                .font(.system(size: 12))
            }
            HStack {
                Spacer()
                PushButton(control: card.button, prominent: card.kind != .downloading) { model.send(card.command) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Chooser

struct ChooserView: View {
    let card: ChooserCard
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let back = card.back {
                BackLink(control: back, action: model.backToPlayer)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: card.title).font(.system(size: 17, weight: .semibold))
                Spacer()
                Chip(text: card.chip)
            }
            if let strip = card.strip { Strip(text: strip) }
            if !card.empty.isEmpty {
                Text(verbatim: card.empty).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(card.cells, id: \.id) { cell in
                    GenreCell(cell: cell, model: model)
                }
                Button(action: model.addGenre) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: card.add.text).fontWeight(.medium).foregroundStyle(Color.accentColor).lineLimit(1)
                        Text(verbatim: " ").font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(card.add.help)
                .accessibilityLabel(Text(verbatim: card.add.help))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct GenreCell: View {
    let cell: ChooserCard.Cell
    let model: PanelModel
    @State private var hovered = false

    var body: some View {
        Button { model.pick(cell.id) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: cell.name).fontWeight(.medium).lineLimit(1).truncationMode(.tail)
                Text(verbatim: cell.sub).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(hovered ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                if cell.current {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(cell.pick.help)
        .accessibilityLabel(Text(verbatim: cell.pick.help))
        .overlay(alignment: .topTrailing) {
            if hovered {
                Button { model.editGenre(cell.id) } label: {
                    Image(systemName: "pencil").font(.system(size: 12)).foregroundStyle(.secondary).padding(6)
                }
                .buttonStyle(.plain)
                .help(cell.edit.help)
                .accessibilityLabel(Text(verbatim: cell.edit.help))
            }
        }
        .onHover { hovered = $0 }
    }
}

struct Chip: View {
    let text: String

    var body: some View {
        if !text.isEmpty {
            Text(verbatim: text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.6), in: Capsule())
        }
    }
}

// MARK: - Editor

struct EditorView: View {
    let card: EditorCard
    let model: PanelModel
    @FocusState private var focus: EditorField?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let ask = card.ask {
                AskView(ask: ask, model: model)
            } else {
                form
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 9) {
            BackLink(control: card.back, action: model.cancelEdit)
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: card.title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Spacer()
                Chip(text: card.chip)
            }
            FieldBox(field: card.name) {
                TextField(text: binding(.name)) { Text(verbatim: card.name.placeholder) }
                    .focused($focus, equals: .name)
            }
            FieldBox(field: card.caption) {
                TextField(text: binding(.caption), axis: .vertical) { Text(verbatim: card.caption.placeholder) }
                    .lineLimit(2...4)
                    .focused($focus, equals: .caption)
            }
            FieldBox(field: card.turns) {
                TextEditor(text: binding(.turns))
                    .font(.system(size: 12.5))
                    .frame(height: 64)
                    .scrollContentBackground(.hidden)
                    .focused($focus, equals: .turns)
                    .overlay(alignment: .topLeading) {
                        if card.values.turns.isEmpty {
                            Text(verbatim: card.turns.placeholder).foregroundStyle(.tertiary).padding(.leading, 5).allowsHitTesting(false)
                        }
                    }
            }
            HStack(alignment: .top, spacing: 10) {
                FieldBox(field: card.slowest) { tempo(.slowest) }
                FieldBox(field: card.fastest) { tempo(.fastest) }
            }
            if !card.tempoError.isEmpty {
                Text(verbatim: card.tempoError).font(.system(size: 11.5)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: card.hint).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if let delete = card.delete {
                    PushButton(control: delete, destructive: true, action: model.askDelete)
                }
                Spacer()
                PushButton(control: card.cancel, action: model.cancelEdit)
                    .keyboardShortcut(.cancelAction)
                PushButton(control: card.save, prominent: true, action: model.save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .disabled(card.loading)
        .onAppear { focus = .name }
    }

    private func tempo(_ field: EditorField) -> some View {
        HStack(spacing: 4) {
            TextField(text: binding(field)) { Text(verbatim: "") }
                .focused($focus, equals: field)
            Text(verbatim: "BPM").foregroundStyle(.secondary)
        }
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
}

/// A labelled box with its note, drawn red when it is wrong, its error
/// under it.
struct FieldBox<Content: View>: View {
    let field: EditorCard.Field
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(verbatim: field.label).font(.system(size: 10, weight: .semibold)).tracking(0.7)
                Spacer()
                Text(verbatim: field.side).font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            content
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(field.bad ? Color.red : Color.secondary.opacity(0.35), lineWidth: 1))
                .accessibilityLabel(Text(verbatim: field.label.capitalized))
            if !field.error.isEmpty {
                Text(verbatim: field.error).font(.system(size: 11.5)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AskView: View {
    let ask: EditorCard.Ask
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(verbatim: ask.title).font(.system(size: 17, weight: .semibold))
            Text(verbatim: ask.detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !ask.error.isEmpty {
                Text(verbatim: ask.error).font(.system(size: 11.5)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                PushButton(control: ask.keep, action: model.keepGenre).keyboardShortcut(.cancelAction)
                PushButton(control: ask.delete, destructive: true, action: model.deleteGenre)
            }
        }
    }
}

// MARK: - Share sheet

struct ShareView: View {
    let card: ShareCard
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            BackLink(control: card.back, action: model.closeShare)
            SectionHeading(title: "SHARE") {
                Text(verbatim: card.head).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: card.name).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                Text(verbatim: card.meta.isEmpty ? " " : card.meta).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(card.rows, id: \.title) { row in
                    ShareRow(row: row) { model.shareAction(row.action) }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct ShareRow: View {
    let row: ShareCard.Row
    let action: () -> Void
    @State private var hovered = false

    private var symbol: String {
        switch row.action {
        case .copyFile: "doc.on.doc"
        case .copyPath: "link"
        case .showInFinder: "folder"
        case .export: "square.and.arrow.up"
        case .keep: "star"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: row.title).fontWeight(.medium)
                    if !row.sub.isEmpty {
                        Text(verbatim: row.sub).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
                if let on = row.on {
                    Toggle(isOn: .constant(on)) { Text(verbatim: row.title) }
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.mini)
                        .allowsHitTesting(false)
                }
            }
            .padding(6)
            .background(hovered && row.control.enabled ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!row.control.enabled)
        .help(row.control.help)
        .accessibilityLabel(Text(verbatim: row.control.help))
        .onHover { hovered = $0 }
    }
}
