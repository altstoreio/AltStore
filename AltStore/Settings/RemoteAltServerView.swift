//
//  RemoteAltServerView.swift
//  AltStore
//
//  Created by Caroline Moore on 5/26/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import SwiftUI

import AltStoreCore

struct RemoteAltServerView: View
{
    @State
    private var availableServers: [AnisetteServer]? = UserDefaults.standard.anisetteServers
    
    @State
    private var isLoading = true
    
    @State
    private var preferredURL: URL? = UserDefaults.shared.preferredAnisetteServerURL
    
    @State
    private var customURLText: String = ""
    
    @State
    private var isShowingError = false
    
    @State
    private var errorMessage = ""
    
    @State
    private var isVPNConnected = false

    @State
    private var isShowingClearConfirmation = false
    
    @Environment(\.dismiss)
    private var dismiss

    private var localizedTitle: String { String(localized: "Remote AltServer") }

    var body: some View {
        List {
            Section {
                LabeledContent("AltServer") {
                    HStack {
                        Text("Paired")
                        Image(systemName: "circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                    }
                }

                LabeledContent("VPN") {
                    HStack {
                        Text(isVPNConnected ? "Connected" : "Not Connected")
                        Image(systemName: "circle.fill")
                            .font(.caption)
                            .foregroundStyle(isVPNConnected ? Color.green : Color.secondary)
                            .accessibilityHidden(true)
                    }
                }
            } header: {
                Text("Status")
            } footer: {
                Text("This is a placeholder that should communicate Remote AltServer needs a Wi-Fi connection in addition to VPN.")
            }
            
            if let availableServers
            {
                Section("Popular") {
                    ForEach(availableServers) { server in
                        SwiftUI.Button {
                            Task { await selectServer(url: server.url) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(server.url.host ?? "")
                                    
                                    Text(server.name)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if server.url == preferredURL
                                {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(.rect) // Expand tap target to the full row.
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            else if isLoading
            {
                Section("Popular") {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }

            Section("Custom") {
                HStack {
                    TextField("https://", text: $customURLText)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit {
                            Task { await submitCustom() }
                        }

                    if isCustomSelected
                    {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
            
            Section {
                SwiftUI.Button(role: .destructive) {
                    isShowingClearConfirmation = true
                } label: {
                    Text("Clear Remote AltServer")
                        .frame(maxWidth: .infinity)
                }
                .confirmationDialog("Are you sure you want to clear Remote AltServer?", isPresented: $isShowingClearConfirmation, titleVisibility: .visible) {
                    SwiftUI.Button("Clear", role: .destructive) {
                        clearRemoteAltServer()
                    }
                } message: {
                    Text("You'll need to pair with your computer again to set it back up.")
                }
            }
        }
        .navigationTitle(localizedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadServers() }
        .refreshable { await loadServers() }
        .task { await monitorVPNStatus() }
        .alert("Couldn't select server", isPresented: $isShowingError) {
            SwiftUI.Button("OK", role: .cancel) { }
        } message: { Text(errorMessage) }
    }

    private var isCustomSelected: Bool
    {
        guard let preferredURL, let availableServers else { return false }
        return !availableServers.contains { $0.url == preferredURL }
    }
}

private extension RemoteAltServerView
{
    func loadServers() async
    {
        isLoading = true
        defer { isLoading = false }

        do
        {
            availableServers = try await AnisetteServerManager.shared.fetchServers()
        }
        catch
        {
            // Keep showing cached servers (if any).
            Logger.sideload.error("Failed to load anisette servers: \(error.localizedDescription, privacy: .public)")
        }

        // If preferred URL isn't in the list, it's the user's custom server.
        if let preferredURL, availableServers?.contains(where: { $0.url == preferredURL }) != true
        {
            customURLText = preferredURL.absoluteString.replacingOccurrences(of: "\(preferredURL.scheme ?? "")://", with: "") // Remove scheme for display
        }
    }

    // Pings the server, then makes it the preferred server. Leaves selection unchanged if it's unreachable.
    func selectServer(url: URL) async
    {
        guard url != preferredURL else { return }

        do
        {
            try await AnisetteServerManager.shared.validate(url)
        }
        catch
        {
            errorMessage = error.localizedDescription
            isShowingError = true
            return
        }

        UserDefaults.shared.preferredAnisetteServerURL = url
        preferredURL = url

        // Clear the custom field when selecting a known server.
        if availableServers?.contains(where: { $0.url == url }) == true
        {
            customURLText = ""
        }
    }

    func submitCustom() async
    {
        var input = customURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        
        if !input.hasPrefix("http://") && !input.hasPrefix("https://")
        {
            input = "https://\(input)"
        }
        
        guard let url = URL(string: input) else
        {
            errorMessage = String(localized: "The provided URL is invalid.")
            isShowingError = true
            return
        }

        await selectServer(url: url)
    }
    
    func monitorVPNStatus() async
    {
        while true
        {
            isVPNConnected = await AppManager.shared.isReachableOnDevice()
            
            do
            {
                try await Task.sleep(for: .seconds(2)) // Often enough to feel live without spamming the check.
            }
            catch
            {
                break // View disappeared, so we can stop monitoring.
            }
        }
    }
    
    func clearRemoteAltServer()
    {
        UserDefaults.standard.prefersRemoteAltServer = false
        Keychain.shared.devicePairingFile = nil
        
        dismiss() // Return to Settings
    }
}

extension RemoteAltServerView
{
    static func makeViewController() -> UIHostingController<some View>
    {
        let view = RemoteAltServerView()

        let hostingController = UIHostingController(rootView: view)
        hostingController.navigationItem.largeTitleDisplayMode = .never
        hostingController.navigationItem.title = view.localizedTitle
        return hostingController
    }
}

#Preview {
    NavigationStack {
        RemoteAltServerView()
    }
}
