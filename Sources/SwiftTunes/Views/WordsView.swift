import SwiftUI
import TunesContract
import TunesPanel

/// The sheet asking for one tune sung with the user's words.
struct WordsView: View {
    let card: WordsCard
    let model: PanelModel

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    BackLink(control: card.back, action: model.closeWords)
                    Spacer()
                    Caps(text: card.label)
                }
                Text(verbatim: card.title).font(.system(size: 20, weight: .bold, design: .rounded)).lineLimit(1)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(Array(card.inserts.enumerated().prefix(3)), id: \.offset) { i, insert in insertButton(i, insert) }
                    }
                    HStack(spacing: 6) {
                        ForEach(Array(card.inserts.enumerated().dropFirst(3)), id: \.offset) { i, insert in insertButton(i, insert) }
                    }
                }
                PlainTextEditor(text: card.text, caret: card.caret, fontSize: 13, label: card.label, changed: model.typeWords)
                    .frame(height: 190)
                    .padding(8)
                    .glassEffect(.regular, in: .rect(cornerRadius: 13))
                if !card.wordsError.isEmpty { error(card.wordsError) }
                HStack {
                    Text(verbatim: card.counter)
                    Spacer()
                    Text(verbatim: card.counterRight)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                HStack {
                    Text(verbatim: card.nameLabel).foregroundStyle(.secondary)
                    Spacer()
                    TextField(text: Binding(get: { card.name }, set: model.typeWordsName), prompt: Text(verbatim: "")) {
                        Text(verbatim: card.nameLabel)
                    }
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .fixedSize()
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
                }
                .font(.system(size: 12.5))
                if !card.nameError.isEmpty { error(card.nameError) }
                Text(verbatim: card.note).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !card.refused.isEmpty { error(card.refused) }
                HStack(spacing: 8) {
                    Spacer()
                    Button(action: model.closeWords) { Text(verbatim: card.cancel.text) }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                        .disabled(!card.cancel.enabled)
                        .helped(card.cancel)
                    Button(action: model.composeWords) { Text(verbatim: card.compose.text) }
                        .buttonStyle(.glassProminent)
                        .disabled(!card.compose.enabled)
                        .helped(card.compose)
                }
            }
        }
    }

    private func insertButton(_ i: Int, _ insert: Control) -> some View {
        Button { model.insertMark(i) } label: {
            Text(verbatim: insert.text).font(.system(size: 12, weight: .medium)).fixedSize().padding(.horizontal, 9).padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .disabled(!insert.enabled)
        .helped(insert)
    }

    private func error(_ text: String) -> some View {
        Text(verbatim: text).font(.system(size: 11.5)).foregroundStyle(Tone.red.color).fixedSize(horizontal: false, vertical: true)
    }
}
