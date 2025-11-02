import EcliptixCore
import Foundation
import GRPCCore

public enum RPCServiceType: String {
    case registerDevice = "RegisterAppDevice"
    case validateMobileNumber = "ValidateMobileNumber"
    case checkMobileAvailability = "CheckMobileNumberAvailability"
    case registrationInit = "RegistrationInit"
    case registrationComplete = "RegistrationComplete"
    case verifyOtp = "VerifyOtp"
    case signInInit = "SignInInitRequest"
    case signInComplete = "SignInCompleteRequest"
    case logout = "Logout"
    case restoreSecureChannel = "RestoreSecureChannel"
}

open class BaseRPCService {
    internal let channelManager: GRPCChannelManager
    public init(channelManager: GRPCChannelManager) {
        self.channelManager = channelManager
    }

}
