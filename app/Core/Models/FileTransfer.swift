// FileTransfer.swift — Value type representing an in-progress file or directory transfer.

import Foundation

struct FileTransfer: Identifiable, Equatable {
    let id:          String
    let peerId:      String       // noiseKey of the remote peer
    let fileName:    String       // file name or directory name
    let fileSize:    Int64        // bytes (total for directories)
    var progress:    Double       // 0.0 → 1.0
    let direction:   Direction
    let isDirectory: Bool         // true when transferring a folder
    let fileCount:   Int          // number of files inside (0 for plain files)

    enum Direction: Equatable {
        case sending
        case receiving
    }

    var progressPercentage: Int  { Int(progress * 100) }
    var isComplete:         Bool { progress >= 1.0 }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// Human-readable description shown as the subtitle in transfer rows
    var subtitle: String {
        if isDirectory {
            let noun = fileCount == 1 ? "file" : "files"
            return "\(fileCount) \(noun) · \(formattedSize)"
        }
        return formattedSize
    }
}
