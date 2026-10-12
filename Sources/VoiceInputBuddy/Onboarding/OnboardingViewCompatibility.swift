import AppKit
import Combine
import CoreBluetooth
import BuddyRemoteUI
import BuddyRemoteCore
import SwiftUI

extension View {
    func onboardingFocusEffectDisabled() -> some View {
        modifier(OnboardingView.OnboardingFocusEffectDisabledModifier())
    }
}
