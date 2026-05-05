// ReceivedFilesView.swift — Shows files received into ~/Documents/PeerDrop
// Tapping a file opens it with QuickLook for preview or share.

import SwiftUI
import QuickLook

struct ReceivedFilesView: View {
    @State private var files:         [ReceivedFile] = []
    @State private var previewURL:    URL?           = nil
    @State private var showingShare:  Bool           = false
    @State private var shareURL:      URL?           = nil
    @State private var isLoading:     Bool           = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if files.isEmpty {
                    emptyState
                } else {
                    fileList
                }
            }
            .navigationTitle("Received")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        loadFiles()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .quickLookPreview($previewURL)
        .sheet(isPresented: $showingShare) {
            if let url = shareURL {
                ShareSheet(url: url)
            }
        }
        .onAppear { loadFiles() }
        .onReceive(NotificationCenter.default.publisher(
            for: .transferDidComplete)
        ) { _ in loadFiles() }
    }

    // MARK: - File list

    var fileList: some View {
        List {
            ForEach(files) { file in
                FileRow(file: file)
                    .contentShape(Rectangle())
                    .onTapGesture { previewURL = file.url }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            delete(file)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            shareURL     = file.url
                            showingShare = true
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(.blue)
                    }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty state

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("No received files")
                .font(.title3).fontWeight(.semibold)
            Text("Files sent to you will appear here.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Load files

    func loadFiles() {
        isLoading = true
        Task {
            let downloadDir = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/PeerDrop")

            var result: [ReceivedFile] = []
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: downloadDir,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .contentTypeKey],
                options: .skipsHiddenFiles
            ) {
                result = contents.compactMap { url in
                    let attrs = try? url.resourceValues(
                        forKeys: [.creationDateKey, .fileSizeKey])
                    return ReceivedFile(
                        url:       url,
                        name:      url.lastPathComponent,
                        size:      attrs?.fileSize ?? 0,
                        createdAt: attrs?.creationDate ?? Date()
                    )
                }
                .sorted { $0.createdAt > $1.createdAt }  // newest first
            }

            await MainActor.run {
                files     = result
                isLoading = false
            }
        }
    }

    // MARK: - Delete

    func delete(_ file: ReceivedFile) {
        try? FileManager.default.removeItem(at: file.url)
        files.removeAll { $0.id == file.id }
    }
}

// MARK: - ReceivedFile model

struct ReceivedFile: Identifiable {
    let id        = UUID()
    let url:       URL
    let name:      String
    let size:      Int
    let createdAt: Date

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var formattedDate: String {
        let f        = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: createdAt, relativeTo: Date())
    }

    var icon: String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo"
        case "mp4", "mov", "avi", "mkv":                  return "video"
        case "mp3", "aac", "wav", "flac", "m4a":          return "music.note"
        case "pdf":                                        return "doc.richtext"
        case "zip", "tar", "gz", "rar":                   return "archivebox"
        case "doc", "docx":                               return "doc.text"
        case "xls", "xlsx":                               return "tablecells"
        case "ppt", "pptx":                               return "rectangle.on.rectangle"
        default:                                           return "doc"
        }
    }
}

// MARK: - File row

struct FileRow: View {
    let file: ReceivedFile

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: file.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(file.formattedSize)
                    Text("·")
                    Text(file.formatedDate)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
    
    // Fix typo accessible from both
    var formatedDate: String { file.formattedDate }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}