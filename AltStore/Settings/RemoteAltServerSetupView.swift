//
//  RemoteAltServerSetupView.swift
//  AltStore
//
//  Created by Caroline Moore on 8/13/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import SwiftUI

import AltStoreCore

extension RemoteAltServerSetupView
{
    enum Step
    {
        case welcome
        case pairWithComputer
        case pairOnDevice
        case installVPN
        case finish
    }
    
    enum PairingState
    {
        case idle
        case waiting
        case paired
    }
    
    private static func makePlan() -> [Step]
    {
        var plan: [Step] = [.welcome]
        
        if Keychain.shared.devicePairingFile == nil && AppManager.shared.bundledPairingFile() == nil
        {
            if #available(iOS 27, *)
            {
                plan.append(.pairOnDevice)
            }
            else
            {
                plan.append(.pairWithComputer)
            }
        }
        
        plan.append(.installVPN)
        plan.append(.finish)
        
        return plan
    }
}

struct RemoteAltServerSetupView: View
{
    let plan: [Step]
    
    let completionHandler: () -> Void
    
    @State
    private var currentStep: Step = .welcome
    
    @State
    private var pairingState: PairingState = .idle
    
    @State
    private var pairingAttempt: Int = 0

    @State
    private var isShowingError = false

    @State
    private var errorMessage = ""
    
    @Environment(\.dismiss)
    private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                switch currentStep
                {
                case .welcome: welcomeStep
                case .pairWithComputer: pairWithComputerStep
                case .pairOnDevice: pairOnDeviceStep
                case .installVPN: installVPNStep
                case .finish: finishStep
                }
            }
            .toolbar {
                if #available(iOS 26, *)
                {
                    SwiftUI.Button(role: .close) {
                        dismiss()
                    }
                }
                else
                {
                    SwiftUI.Button("Cancel") {
                        dismiss()
                    }
                    .tint(Color(.altPrimary))
                }
            }
            // Incrementing pairingAttempt restarts this task, cancelling any active pairing attempt before starting a new one.
            .task(id: pairingAttempt) {
                guard pairingAttempt > 0 else { return } // Only pair after a tap.
                await pair()
            }
            .alert("Unable to Pair", isPresented: $isShowingError) {
                SwiftUI.Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sensoryFeedback(.success, trigger: pairingState) { _, newValue in newValue == .paired }
        }
    }
    
    func advance()
    {
        guard currentStep != plan.last else { return completionHandler() }
        
        withAnimation {
            if let index = plan.firstIndex(of: currentStep)
            {
                currentStep = plan[index + 1]
            }
            else
            {
                // The current step should always be in the plan, but default to 'Finish' in case of an issue.
                currentStep = .finish
            }
        }
    }
    
    func pair() async
    {
        do
        {
            pairingState = .waiting
            
            if #available(iOS 27, *), plan.contains(.pairOnDevice)
            {
                try await AppManager.shared.pairDevice()
            }
            else
            {
                try await self.waitForPairingFile()
            }
            
            // Pairing can finish while the user is in the Settings app or behind a system prompt, so wait until they can see the result.
            if UIApplication.shared.applicationState != .active
            {
                for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification)
                {
                    try await Task.sleep(for: .seconds(0.2))
                    break
                }
            }
            
            pairingState = .paired
            
            try await Task.sleep(for: .seconds(1)) // Brief pause so the user registers 'Paired' before moving on.
            advance()
        }
        catch is CancellationError { }
        catch
        {
            pairingState = .idle
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }
    
    // Fetches a pairing file from AltServer, retrying until this device is plugged into a computer.
    func waitForPairingFile(retryInterval: Duration = .seconds(2)) async throws
    {
        while true
        {
            try Task.checkCancellation()
            
            do
            {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    AppManager.shared.fetchPairingFile { result in
                        continuation.resume(with: result)
                    }
                }
                return
            }
            catch ~OperationError.Code.serverNotFound, ~OperationError.Code.wiredConnectionRequired
            {
                // No wired AltServer connection yet, so keep waiting.
                try await Task.sleep(for: retryInterval)
            }
        }
    }
}

private extension RemoteAltServerSetupView
{
// MARK: - Welcome
    
    var welcomeStep: some View {
        HeroPage(title: "Remote AltServer",
                 subtitle: "Use AltStore without a computer. Set up once, then sideload from anywhere.") {
            Image("LogoRecessed")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 200, maxHeight: 200)
                .background {
                    // Signal rings that fade as they expand (masked so they dissolve before reaching the title).
                    ZStack {
                        ForEach(1..<4) { ring in
                            Circle()
                                .stroke(Color(.altSecondary).opacity(0.5 / Double(ring)), lineWidth: 1.5)
                                .scaleEffect(1 + Double(ring) * 0.4)
                        }
                    }
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0.5), .init(color: .clear, location: 0.75)], startPoint: .top, endPoint: .bottom)
                            .scaleEffect(2.5)
                    }
                }
        } content: {
            GlassBadge(content: Text("Takes about 2 minutes."), color: Color(.altSecondary))
        } buttons: {
            SwiftUI.Button("Begin Setup") { advance() }
        }
    }
    
// MARK: - Pair With Computer
    
    var pairWithComputerStep: some View {
        StepPage(title: "Connect to Computer", subtitle: "Plug this device into your computer with a cable, then open AltServer.") {
            Image("ConnectGraphic")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 500)
        } accessory: {
            GlassBadge(content: Text("Tap 'Trust' when prompted."), color: Color(.altSecondary))
        } buttons: {
            PairingButton(state: pairingState, idleTitle: "Pair with AltServer", waitingTitle: "Connecting to AltServer…") {
                pairingAttempt += 1
            }
        }
    }
    
// MARK: - Pair On Device
    
    var pairOnDeviceStep: some View {
        StepPage(title: "Pair in Settings", subtitle: "Go to Privacy & Security > Developer Mode, then tap 'Pair with AltStore'.") {
            Image("PairOnDeviceGraphic")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 580)
        } accessory: {
            GlassBadge(content: Text("Enter passcode when prompted."), color: Color(.altSecondary))
        } buttons: {
            PairingButton(state: pairingState, idleTitle: "Open Settings", waitingTitle: "Waiting to Pair…") {
                pairingAttempt += 1
            }
        }
    }
    
// MARK: - Install VPN
    
    var installVPNStep: some View {
        InstallVPNStep(advance: advance)
    }
    
    struct InstallVPNStep: View
    {
        let advance: () -> Void
        
        @State
        private var isVPNConnected: Bool
        
        @Environment(\.openURL)
        private var openURL
        
        init(isVPNConnected: Bool = false, advance: @escaping () -> Void)
        {
            self._isVPNConnected = State(initialValue: isVPNConnected)
            self.advance = advance
        }
        
        var body: some View {
            StepPage(title: "Install LocalDevVPN", subtitle: "Remote AltServer requires LocalDevVPN to sideload apps.") {
                Image("LocalDevVPN")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 330)
            } accessory: {
                if isVPNConnected
                {
                    GlassBadge(content: Text("\(Image(systemName: "circle.fill")) Connected"), color: .green)
                }
            } buttons: {
                if isVPNConnected
                {
                    SwiftUI.Button("Continue") { advance() }
                }
                else
                {
                    SwiftUI.Button("Get LocalDevVPN") { openURL(URL(string: "https://apps.apple.com/app/id6755608044")!) }
                    
                    if #available(iOS 26, *)
                    {
                        SwiftUI.Button("Not Now") { advance() }
                            .buttonStyle(.glass)
                    }
                    else
                    {
                        SwiftUI.Button("Not Now") { advance() }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .animation(.default, value: isVPNConnected)
            .task {
                isVPNConnected = await OnDeviceClient.isReachable()
                
                // Check VPN status whenever the user comes back to the app.
                // didBecomeActive rather than willEnterForeground because it also fires when Control Center is dismissed.
                for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification)
                {
                    isVPNConnected = await OnDeviceClient.isReachable()
                }
            }
        }
    }
    
// MARK: - Setup Complete
    
    var finishStep: some View {
        HeroPage(title: "Setup Complete", subtitle: "Remote AltServer needs two things whenever you sideload:") {
            Image("FinishGraphic")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 15) {
                    Image(systemName: "wifi")
                        .font(.title2.bold())
                        .foregroundStyle(Color(.altSecondary))
                        .frame(width: 36)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wi-Fi")
                            .font(.headline)
                        
                        Text("Your device reaches AltServer over Wi-Fi, so keep it turned on.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(alignment: .top, spacing: 15) {
                    Image(systemName: "powerplug.fill")
                        .font(.title2.bold())
                        .foregroundStyle(Color(.altSecondary))
                        .frame(width: 36)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VPN")
                            .font(.headline)
                        
                        Text("Connect to LocalDevVPN while sideloading apps.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 50)
            .layoutPriority(1)
        } buttons: {
            SwiftUI.Button("Finish") { advance() }
        }
    }
}

extension RemoteAltServerSetupView
{
    @MainActor
    static func makeViewController(completionHandler: @escaping () -> Void) -> UIHostingController<some View>
    {
        let view = RemoteAltServerSetupView(plan: makePlan(), completionHandler: completionHandler)
        
        let hostingController = UIHostingController(rootView: view)
        hostingController.isModalInPresentation = true
        return hostingController
    }
}

// MARK: - Previews

private struct SetupPreview: View
{
    let plan: [RemoteAltServerSetupView.Step]
    
    var body: some View {
        Color(uiColor: .altPrimary)
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                RemoteAltServerSetupView(plan: plan) { }
//                .environment(\.dynamicTypeSize, .accessibility3)
            }
    }
}

#Preview("Computer Pairing") {
    SetupPreview(plan: [.welcome, .pairWithComputer, .installVPN, .finish])
}

#Preview("On-Device Pairing") {
    SetupPreview(plan: [.welcome, .pairOnDevice, .installVPN, .finish])
}

#Preview("Bundled File") {
    SetupPreview(plan: [.welcome, .installVPN, .finish])
}

#Preview("Bookends") {
    SetupPreview(plan: [.welcome, .finish])
}

#Preview("VPN Connected") {
    RemoteAltServerSetupView.InstallVPNStep(isVPNConnected: true) { }
}
