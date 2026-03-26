// FileTransfer.swift — Value type representing an in-progress file transfer.

import Foundation

struct FileTransfer: Identifiable, Equatable {
    let id:        String
    let peerId:    String      // noiseKey of the remote — mapped to discoveryKey via Worker
    let fileName:  String
    let fileSize:  Int64
    var progress:  Double      // 0.0 → 1.0
    let direction: Direction

    enum Direction: Equatable {
        case sending
        case receiving
    }

    var progressPercentage: Int { Int(progress * 100) }
    var isComplete:         Bool { progress >= 1.0 }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
