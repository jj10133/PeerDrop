//
//  SectionHeader.swift
//  App
//
//  Created by Janardhan on 2026-03-25.
//

import SwiftUI

// MARK: - ActionLink

struct ActionLink: View {
    let title:  String
    let icon:   String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12))
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isHovering ? Color.primary.opacity(0.05) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
