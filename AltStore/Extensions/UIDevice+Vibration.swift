//
//  UIDevice+Vibration.swift
//  AltStore
//
//  Created by Riley Testut on 9/1/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

import AudioToolbox
import CoreHaptics

private extension SystemSoundID
{
    static let pop = SystemSoundID(1520)
    static let cancelled = SystemSoundID(1521)
    static let tryAgain = SystemSoundID(1102)
}

extension UIDevice
{
    enum VibrationPattern
    {
        case success
        case error
    }
}

extension UIDevice
{
    var isVibrationSupported: Bool {
        return CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    func vibrate(pattern: VibrationPattern)
    {
        guard self.isVibrationSupported else { return }
        
        switch pattern
        {
        case .success: AudioServicesPlaySystemSound(.tryAgain)
        case .error: AudioServicesPlaySystemSound(.cancelled)
        }
    }
}
