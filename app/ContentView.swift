//
//  ContentView.swift
//  App
//
//  Created by Janardhan on 2026-03-21.
//

import SwiftUI

struct ContentView: View {
    @State private var query: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // --- HEADER ---
            VStack(spacing: 12) {
                HStack {
                    Text("PeerDrop")
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Button { } label: {
                        Image(systemName: "gear")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                
                searchBar
            }
            .padding(16)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // --- SCROLLABLE CONTENT ---
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Section 1: Active Devices
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ACTIVE DEVICES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                        
                        DeviceRow(name: "Galaxy S21", systemImage: "smartphone", status: "Ready")
                        DeviceRow(name: "iPhone 12", systemImage: "iphone", status: "Active")
                    }
                    
                    // Section 2: Quick Links
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RESOURCES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                        
                        ActionLink(title: "Set up Another Device...", icon: "plus.circle")
                        ActionLink(title: "Tell someone about PeerDrop", icon: "square.and.arrow.up")
                        ActionLink(title: "Support us ❤️", icon: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90")
                    }
                }
                .padding(16)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
    
    // Sub-component for Search Bar to keep body clean
    var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            TextField("Search by Peer ID", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}

// --- DEVICE ROW COMPONENT ---
struct DeviceRow: View {
    let name: String
    let systemImage: String
    let status: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Circular Icon Background
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                Text(status)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(10)
    }
}

// --- ACTION LINK COMPONENT ---
struct ActionLink: View {
    let title: String
    let icon: String
    
    var body: some View {
        Button(action: {}) {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Hover effect would go here
    }
}
