import SwiftUI
import AppKit
import UtilityCore
import UniformTypeIdentifiers

struct ClipboardView: View {
    @ObservedObject var model = AppModel.shared
    @State var query = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clipboard history").font(.title2.bold())
            Toggle("Record clipboard history", isOn: Binding(get:{model.recording},set:{model.setRecording($0)}))
            Text("Copy an entry, then paste with ⌘V.").font(.caption).foregroundStyle(.secondary)
            TextField("Search history", text: $query)
            List {
                ForEach(model.clips.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }.sorted { $0.pinned && !$1.pinned }) { clip in
                    HStack {
                        if let data = clip.png, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit().frame(width: 90,height: 70) }
                        Text(clip.text).lineLimit(3).textSelection(.enabled); Spacer()
                        Button { if let i = model.clips.firstIndex(where: { $0.id == clip.id }) { model.clips[i].pinned.toggle(); model.persist() } } label: { Image(systemName: clip.pinned ? "pin.fill" : "pin") }
                        Button("Copy") { model.copy(clip) }
                    }.padding(.vertical, 4)
                }
            }
            HStack { Text("\(model.clips.count) entries").font(.caption); Spacer(); Button("Clear unpinned") { model.clips.removeAll { !$0.pinned }; model.persist() }; Button("Clear all") { model.clips = []; model.persist() } }
        }.padding(20).utilityStyle()
    }
}
