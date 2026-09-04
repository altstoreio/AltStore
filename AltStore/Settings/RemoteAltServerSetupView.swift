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
        
        // Relies on the fact that sign-in is required before this view is shown, so nil
        // definitely means "no pairing file" — not "bundled file we can't decrypt yet".
        if AppManager.shared.devicePairingFile == nil
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
            .task(id: pairingAttempt) {
                guard pairingAttempt > 0 else { return } // Only pair after a tap.
                
                do
                {
                    pairingState = .waiting
                    
                    if #available(iOS 27, *), plan.contains(.pairOnDevice)
                    {
                        try await AppManager.shared.pairDevice()
                    }
                    else
                    {
                        try await AppManager.shared.waitForPairingFile()
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
                catch ~PairError.Code.timedOut
                {
                    pairingState = .idle
                    errorMessage = String(localized: "Pairing was interrupted. Please try again.")
                    isShowingError = true
                }
                catch
                {
                    pairingState = .idle
                    errorMessage = error.localizedDescription
                    isShowingError = true
                }
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
        // If we're on the last step, return complete.
        guard let index = plan.firstIndex(of: currentStep), index + 1 < plan.count else { return completionHandler() }
        
        withAnimation {
            currentStep = plan[index + 1]
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
                // Don't overwrite the seeded value from a preview.
                guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
                
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

// MARK: - Page Layouts

private struct HeroPage<Graphic: View, Content: View, Buttons: View>: View
{
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    
    @ViewBuilder
    let graphic: () -> Graphic
    
    @ViewBuilder
    let content: () -> Content
    
    @ViewBuilder
    let buttons: () -> Buttons
    
    var body: some View {
        VStack(spacing: 30) {
            graphic()
                .background {
                    ZStack {
                        Circle()
                            .fill(Color(.altLight).opacity(0.6))
                            .frame(width: 300, height: 300)
                            .blur(radius: 100)
                        
                        Circle()
                            .fill(Color(.altSecondary).opacity(0.2))
                            .frame(width: 250, height: 250)
                            .blur(radius: 100)
                    }
                }
                .accessibilityHidden(true)
            
            VStack(alignment: .center, spacing: 6) {
                Text(title)
                    .font(.title.bold())
                
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)
            .multilineTextAlignment(.center)
            .layoutPriority(1)
            
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .bottomButtonBar(buttons: {
            buttons()
        })
        .transition(.push(from: .trailing))
    }
}

private struct StepPage<Graphic: View, Accessory: View, Buttons: View>: View
{
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    
    @ViewBuilder
    let graphic: () -> Graphic
    
    @ViewBuilder
    let accessory: () -> Accessory
    
    @ViewBuilder
    let buttons: () -> Buttons
    
    var body: some View {
        ViewThatFits(in: .vertical) {
            // Everything fits: content takes priority and graphic fills remaining space.
            VStack(spacing: 30) {
                graphic()
                    .frame(idealHeight: 0, maxHeight: .infinity, alignment: .center)
                    .accessibilityHidden(true)
                
                content
            }
            
            // Text alone overflows: content scrolls, graphic is hidden.
            ScrollView {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .bottomButtonBar(buttons: {
            buttons()
        })
        .transition(.push(from: .trailing))
    }
    
    private var content: some View {
        VStack(spacing: 15) {
            VStack(alignment: .center, spacing: 4) {
                Text(title)
                    .font(.title.bold())

                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 50)
            .multilineTextAlignment(.center)

            accessory()
        }
    }
}

// MARK: - Components

private struct PairingButton: View
{
    let state: RemoteAltServerSetupView.PairingState
    let idleTitle: LocalizedStringKey
    let waitingTitle: LocalizedStringKey
    let action: () -> Void
    
    private var title: LocalizedStringKey {
        switch state
        {
        case .idle: idleTitle
        case .waiting: waitingTitle
        case .paired: "Paired"
        }
    }
    
    var body: some View {
        SwiftUI.Button(action: action) {
            HStack(spacing: 8) {
                if state == .waiting
                {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.regular)
                }
                if state == .paired
                {
                    Image(systemName: "checkmark")
                }
                
                Text(title)
                    .contentTransition(.opacity)
            }
            .bold()
        }
        .tint(state == .paired ? .green : Color(.altPrimary))
        .disabled(state == .waiting)
        .allowsHitTesting(state != .paired) // Prevents interaction during confirmation state
        .animation(.default, value: state)
    }
}

private struct GlassBadge: View
{
    let content: Text
    let color: Color
    
    var body: some View {
        if #available(iOS 26, *)
        {
            content
                .font(.footnote.bold())
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(color.opacity(0.1)), in: .capsule)
        }
        else
        {
            content
                .font(.footnote.bold())
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(color.opacity(0.1), in: .capsule)
        }
    }
}

private struct BottomButtonBar<Buttons: View>: ViewModifier
{
    let buttons: Buttons
    
    func body(content: Content) -> some View
    {
        if #available(iOS 26, *)
        {
            content.safeAreaBar(edge: .bottom, spacing: 40) {
                VStack(spacing: 10) {
                    buttons
                }
                .bold()
                .tint(Color(.altPrimary))
                .controlSize(.large)
                .padding(.horizontal, 34)
                .buttonStyle(.glassProminent)
                .buttonSizing(.flexible)
            }
        }
        else
        {
            content.safeAreaInset(edge: .bottom, spacing: 40) {
                VStack(spacing: 10) {
                    buttons
                }
                .bold()
                .tint(Color(.altPrimary))
                .controlSize(.large)
                .padding(.horizontal, 34)
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private extension View
{
    func bottomButtonBar<Buttons: View>(@ViewBuilder buttons: () -> Buttons) -> some View
    {
        modifier(BottomButtonBar(buttons: buttons()))
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
