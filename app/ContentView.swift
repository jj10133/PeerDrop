//
//  ContentView.swift
//  App
//
//  Created by Janardhan on 2026-03-21.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var worker: Worker
    
    @State private var isTargeted = false
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
                        
                        
                        ForEach(worker.activeDevices) { device in
                            DeviceRow(device: device)
                                .onDrop(of: [.fileURL, .folder], isTargeted: $isTargeted) { providers in
                                    handleDrop(providers: providers, for: device)
                                }
                            // Optional: Visual feedback when dragging over
                                .opacity(isTargeted ? 0.6 : 1.0)
                        }
                    }
                    
                    // Section 2: Quick Links
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RESOURCES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                        
                        ActionLink(title: "Set up Another Device...", icon: "plus.circle")
                        ActionLink(title: "Tell someone about PeerDrop", icon: "square.and.arrow.up")
                        ActionLink(title: "Support us", icon: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90")
                    }
                }
                .padding(16)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
    
    private func handleDrop(providers: [NSItemProvider], for device: PeerDevice) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (urlData, error) in
                if let data = urlData as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    print("Dropping \(url.lastPathComponent) onto \(device.name)")
                    
                    // Trigger your Worklet transfer here:
                    // worker.worklet.send(file: url, to: device.id)
                }
            }
        }
        return true
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
    let device: PeerDevice
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: device.systemImage)
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 13, weight: .medium))
                Text(device.status)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.2), lineWidth: 0.5)
        )
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
