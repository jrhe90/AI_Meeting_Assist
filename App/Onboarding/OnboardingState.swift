import Foundation
import Observation
import SharedKit

/// Persists the one-shot "user finished the wizard" flag.
public enum OnboardingFlag {
    private static let key = "onboardingCompleted"

    public static var isCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Steps the wizard walks through. Order matters for `next` / `previous`.
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome
    case microphone
    case screenRecording
    case done

    public var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }
}

@MainActor
@Observable
public final class OnboardingViewModel {
    public var step: OnboardingStep = .welcome
    public var micStatus: PermissionStatus
    public var screenStatus: PermissionStatus
    public var isRequesting: Bool = false

    public init() {
        self.micStatus = PermissionChecker.microphoneStatus()
        self.screenStatus = PermissionChecker.screenRecordingStatus()
    }

    public func advance() {
        if let next = step.next { step = next }
    }

    public func requestMicrophone() async {
        isRequesting = true
        defer { isRequesting = false }
        micStatus = await PermissionChecker.requestMicrophone()
    }

    public func requestScreenRecording() {
        isRequesting = true
        defer { isRequesting = false }
        screenStatus = PermissionChecker.requestScreenRecording()
    }

    public func finish() {
        OnboardingFlag.isCompleted = true
        Log.app.info("Onboarding marked complete.")
    }
}
