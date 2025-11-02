import Foundation

public enum LocalizationKeys {
    public enum Error {
        public static let validation = "error.validation"
        public static let maxAttempts = "error.max_attempts"
        public static let invalidMobile = "error.invalid_mobile"
        public static let otpExpired = "error.otp_expired"
        public static let notFound = "error.not_found"
        public static let alreadyExists = "error.already_exists"
        public static let unauthenticated = "error.unauthenticated"
        public static let permissionDenied = "error.permission_denied"
        public static let preconditionFailed = "error.precondition_failed"
        public static let conflict = "error.conflict"
        public static let resourceExhausted = "error.resource_exhausted"
        public static let serviceUnavailable = "error.service_unavailable"
        public static let dependencyUnavailable = "error.dependency_unavailable"
        public static let deadlineExceeded = "error.deadline_exceeded"
        public static let cancelled = "error.cancelled"
        public static let `internal` = "error.internal"
        public static let databaseUnavailable = "error.database_unavailable"
        public static let serverUnavailable = "error.server_unavailable"
    }
    public enum Authentication {
        public enum SignUp {
            public enum MobileVerification {
                public static let title = "Authentication.SignUp.MobileVerification.Title"
                public static let description = "Authentication.SignUp.MobileVerification.Description"
                public static let hint = "Authentication.SignUp.MobileVerification.Hint"
                public static let watermark = "Authentication.SignUp.MobileVerification.Watermark"
                public static let button = "Authentication.SignUp.MobileVerification.Button"
            }

            public enum VerificationCodeEntry {
                public static let title = "Authentication.SignUp.VerificationCodeEntry.Title"
                public static let description = "Authentication.SignUp.VerificationCodeEntry.Description"
                public static let hint = "Authentication.SignUp.VerificationCodeEntry.Hint"
                public static let errorInvalidCode = "Authentication.SignUp.VerificationCodeEntry.Error_InvalidCode"
                public static let buttonVerify = "Authentication.SignUp.VerificationCodeEntry.Button.Verify"
                public static let buttonResend = "Authentication.SignUp.VerificationCodeEntry.Button.Resend"
            }

            public enum NicknameInput {
                public static let title = "Authentication.SignUp.NicknameInput.Title"
                public static let description = "Authentication.SignUp.NicknameInput.Description"
                public static let hint = "Authentication.SignUp.NicknameInput.Hint"
                public static let watermark = "Authentication.SignUp.NicknameInput.Watermark"
                public static let button = "Authentication.SignUp.NicknameInput.Button"
            }

            public enum PasswordConfirmation {
                public static let title = "Authentication.SignUp.PasswordConfirmation.Title"
                public static let description = "Authentication.SignUp.PasswordConfirmation.Description"
                public static let passwordPlaceholder = "Authentication.SignUp.PasswordConfirmation.PasswordPlaceholder"
                public static let passwordHint = "Authentication.SignUp.PasswordConfirmation.PasswordHint"
                public static let verifyPasswordPlaceholder = "Authentication.SignUp.PasswordConfirmation.VerifyPasswordPlaceholder"
                public static let verifyPasswordHint = "Authentication.SignUp.PasswordConfirmation.VerifyPasswordHint"
                public static let errorPasswordMismatch = "Authentication.SignUp.PasswordConfirmation.Error_PasswordMismatch"
                public static let button = "Authentication.SignUp.PasswordConfirmation.Button"
            }

            public enum PassPhase {
                public static let title = "Authentication.SignUp.PassPhase.Title"
                public static let description = "Authentication.SignUp.PassPhase.Description"
                public static let hint = "Authentication.SignUp.PassPhase.Hint"
                public static let watermark = "Authentication.SignUp.PassPhase.Watermark"
                public static let button = "Authentication.SignUp.PassPhase.Button"
            }
        }

        public enum SignIn {
            public static let title = "Authentication.SignIn.Title"
            public static let welcome = "Authentication.SignIn.Welcome"
            public static let mobilePlaceholder = "Authentication.SignIn.MobilePlaceholder"
            public static let mobileHint = "Authentication.SignIn.MobileHint"
            public static let passwordPlaceholder = "Authentication.SignIn.PasswordPlaceholder"
            public static let passwordHint = "Authentication.SignIn.PasswordHint"
            public static let accountRecovery = "Authentication.SignIn.AccountRecovery"
            public static let `continue` = "Authentication.SignIn.Continue"
        }

        public enum PasswordRecovery {
            public enum Reset {
                public static let title = "Authentication.PasswordRecovery.Reset.Title"
                public static let description = "Authentication.PasswordRecovery.Reset.Description"
                public static let newPasswordPlaceholder = "Authentication.PasswordRecovery.Reset.NewPasswordPlaceholder"
                public static let newPasswordHint = "Authentication.PasswordRecovery.Reset.NewPasswordHint"
                public static let confirmPasswordPlaceholder = "Authentication.PasswordRecovery.Reset.ConfirmPasswordPlaceholder"
                public static let confirmPasswordHint = "Authentication.PasswordRecovery.Reset.ConfirmPasswordHint"
                public static let button = "Authentication.PasswordRecovery.Reset.Button"
            }
        }
    }
    public enum MobileVerification {
        public enum Error {
            public static let mobileAlreadyRegistered = "MobileVerification.Error.MobileAlreadyRegistered"
        }

        public static let availableForRegistration = "mobile_available_for_registration"
        public static let incompleteRegistrationContinue = "mobile_incomplete_registration_continue"
        public static let takenActiveAccount = "mobile_taken_active_account"
        public static let takenInactiveAccount = "mobile_taken_inactive_account"
        public static let dataCorruptionContactSupport = "mobile_data_corruption_contact_support"
        public static let availableOnThisDevice = "mobile_available_on_this_device"
    }
    public enum Verification {
        public enum Error {
            public static let invalidOtpCode = "Verification.Error.InvalidOtpCode"
            public static let noSession = "Verification.Error.NoSession"
            public static let sessionExpired = "Verification.Error.SessionExpired"
            public static let noActiveSession = "Verification.Error.NoActiveSession"
            public static let maxAttemptsReached = "Verification.Error.MaxAttemptsReached"
            public static let verificationFailed = "Verification.Error.VerificationFailed"
            public static let sessionNotFound = "Verification.Error.SessionNotFound"
            public static let globalRateLimitExceeded = "Verification.Error.GlobalRateLimitExceeded"
        }

        public enum Info {
            public static let redirecting = "Verification.Info.Redirecting"
            public static let redirectingInSeconds = "Verification.Info.RedirectingInSeconds"
        }
    }
    public enum Validation {

        public static let mobileNumberRequired = "ValidationErrors.MobileNumber.Required"
        public static let mobileNumberInvalid = "ValidationErrors.MobileNumber.Invalid"
        public static let mobileNumberTooShort = "ValidationErrors.MobileNumber.TooShort"
        public static let mobileNumberTooLong = "ValidationErrors.MobileNumber.TooLong"

        public static let emailRequired = "ValidationErrors.Email.Required"
        public static let emailInvalid = "ValidationErrors.Email.Invalid"

        public static let passwordRequired = "ValidationErrors.Password.Required"
        public static let passwordTooShort = "ValidationErrors.Password.TooShort"
        public static let passwordTooLong = "ValidationErrors.Password.TooLong"
        public static let passwordNoUppercase = "ValidationErrors.Password.NoUppercase"
        public static let passwordNoLowercase = "ValidationErrors.Password.NoLowercase"
        public static let passwordNoDigit = "ValidationErrors.Password.NoDigit"
        public static let passwordNoSpecialChar = "ValidationErrors.Password.NoSpecialChar"
        public static let passwordContainsSpaces = "ValidationErrors.Password.ContainsSpaces"
        public static let passwordNeedsUppercase = "ValidationErrors.Password.NeedsUppercase"
        public static let passwordNeedsLowercase = "ValidationErrors.Password.NeedsLowercase"
        public static let passwordNeedsDigit = "ValidationErrors.Password.NeedsDigit"
        public static let passwordNeedsSpecial = "ValidationErrors.Password.NeedsSpecialChar"

        public static let secureKeyRequired = "ValidationErrors.SecureKey.Required"
        public static let secureKeyTooShort = "ValidationErrors.SecureKey.TooShort"
        public static let secureKeyTooLong = "ValidationErrors.SecureKey.TooLong"
        public static let secureKeyNeedsUppercase = "ValidationErrors.SecureKey.NeedsUppercase"
        public static let secureKeyNeedsLowercase = "ValidationErrors.SecureKey.NeedsLowercase"
        public static let secureKeyNeedsDigit = "ValidationErrors.SecureKey.NeedsDigit"
        public static let secureKeyNeedsSpecial = "ValidationErrors.SecureKey.NeedsSpecialChar"

        public static let passwordConfirmRequired = "ValidationErrors.PasswordConfirm.Required"
        public static let passwordsDoNotMatch = "ValidationErrors.PasswordConfirm.DoesNotMatch"

        public static let otpRequired = "ValidationErrors.OTP.Required"
        public static let otpInvalid = "ValidationErrors.OTP.Invalid"
        public static let otpInvalidLength = "ValidationErrors.OTP.InvalidLength"

        public static let usernameRequired = "ValidationErrors.Username.Required"
        public static let usernameTooShort = "ValidationErrors.Username.TooShort"
        public static let usernameTooLong = "ValidationErrors.Username.TooLong"
        public static let usernameInvalidChars = "ValidationErrors.Username.InvalidChars"
        public static let usernameInvalidStart = "ValidationErrors.Username.InvalidStart"

        public static let deviceNameRequired = "ValidationErrors.DeviceName.Required"
        public static let deviceNameTooShort = "ValidationErrors.DeviceName.TooShort"
        public static let deviceNameTooLong = "ValidationErrors.DeviceName.TooLong"
    }
    public enum ValidationErrors {
        public enum MobileNumber {
            public static let mustStartWithCountryCode = "ValidationErrors.MobileNumber.MustStartWithCountryCode"
            public static let containsNonDigits = "ValidationErrors.MobileNumber.ContainsNonDigits"
            public static let incorrectLength = "ValidationErrors.MobileNumber.IncorrectLength"
            public static let cannotBeEmpty = "ValidationErrors.MobileNumber.CannotBeEmpty"
            public static let required = "ValidationErrors.MobileNumber.Required"
        }

        public enum SecureKey {
            public static let required = "ValidationErrors.SecureKey.Required"
            public static let minLength = "ValidationErrors.SecureKey.MinLength"
            public static let maxLength = "ValidationErrors.SecureKey.MaxLength"
            public static let noSpaces = "ValidationErrors.SecureKey.NoSpaces"
            public static let noUppercase = "ValidationErrors.SecureKey.NoUppercase"
            public static let noLowercase = "ValidationErrors.SecureKey.NoLowercase"
            public static let noDigit = "ValidationErrors.SecureKey.NoDigit"
            public static let tooSimple = "ValidationErrors.SecureKey.TooSimple"
            public static let tooCommon = "ValidationErrors.SecureKey.TooCommon"
            public static let sequentialPattern = "ValidationErrors.SecureKey.SequentialPattern"
            public static let repeatedChars = "ValidationErrors.SecureKey.RepeatedChars"
            public static let lacksDiversity = "ValidationErrors.SecureKey.LacksDiversity"
            public static let containsAppName = "ValidationErrors.SecureKey.ContainsAppName"
            public static let invalidCredentials = "ValidationErrors.SecureKey.InvalidCredentials"
            public static let nonEnglishLetters = "ValidationErrors.SecureKey.NonEnglishLetters"
            public static let noSpecialChar = "ValidationErrors.SecureKey.NoSpecialChar"
        }

        public enum VerifySecureKey {
            public static let doesNotMatch = "ValidationErrors.VerifySecureKey.DoesNotMatch"
        }

        public enum PasswordStrength {
            public static let invalid = "ValidationErrors.PasswordStrength.Invalid"
            public static let veryWeak = "ValidationErrors.PasswordStrength.VeryWeak"
            public static let weak = "ValidationErrors.PasswordStrength.Weak"
            public static let good = "ValidationErrors.PasswordStrength.Good"
            public static let strong = "ValidationErrors.PasswordStrength.Strong"
            public static let veryStrong = "ValidationErrors.PasswordStrength.VeryStrong"
        }

        public static let mobileNumberIdentifierRequired = "ValidationErrors.MobileNumberIdentifier.Required"
        public static let deviceIdentifierRequired = "ValidationErrors.DeviceIdentifier.Required"
        public static let sessionIdentifierRequired = "ValidationErrors.SessionIdentifier.Required"
        public static let membershipIdentifierRequired = "ValidationErrors.MembershipIdentifier.Required"
    }
    public enum ValidationWarnings {
        public enum SecureKey {
            public static let nonLatinLetter = "ValidationWarnings.SecureKey.NonLatinLetter"
            public static let invalidCharacter = "ValidationWarnings.SecureKey.InvalidCharacter"
            public static let multipleCharacters = "ValidationWarnings.SecureKey.MultipleCharacters"
        }
    }
    public enum ResponseErrors {
        public enum MobileNumber {
            public static let accountAlreadyRegistered = "ResponseErrors.MobileNumber.AccountAlreadyRegistered"
            public static let unexpectedMembershipStatus = "ResponseErrors.MobileNumber.UnexpectedMembershipStatus"
        }

        public enum Common {
            public static let timeoutExceeded = "ResponseErrors.Common.TimeoutExceeded"
        }
    }
    public enum Registration {
        public enum Error {
            public static let failed = "Registration.Error.Failed"
        }
    }
    public enum Welcome {
        public static let signInButton = "Welcome.SignInButton"
        public static let createAccountButton = "Welcome.CreateAccountButton"
    }
    public enum Footer {
        public static let privacyPolicy = "Footer.PrivacyPolicy"
        public static let termsOfService = "Footer.TermsOfService"
        public static let support = "Footer.Support"
        public static let agreementText = "Footer.AgreementText"
        public static let copyright = "Footer.Copyright"
    }
    public enum Navigation {
        public static let back = "Navigation.Back"
        public static let close = "Navigation.Close"
        public static let minimize = "Navigation.Minimize"
        public static let maximize = "Navigation.Maximize"
    }
    public enum Common {
        public static let loading = "Common.Loading"
        public static let error = "Common.Error"
        public static let success = "Common.Success"
        public static let cancel = "Common.Cancel"
        public static let unexpectedError = "Common.UnexpectedError"
        public static let ok = "Common.Ok"
        public static let noInternetConnection = "Common.NoInternetConnection"
        public static let checkConnection = "Common.CheckConnection"
    }
    public enum NetworkNotification {
        public enum NoInternet {
            public static let title = "NetworkNotification.NoInternet.Title"
            public static let description = "NetworkNotification.NoInternet.Description"
        }

        public enum CheckingInternet {
            public static let title = "NetworkNotification.CheckingInternet.Title"
            public static let description = "NetworkNotification.CheckingInternet.Description"
        }

        public enum InternetRestored {
            public static let title = "NetworkNotification.InternetRestored.Title"
            public static let description = "NetworkNotification.InternetRestored.Description"
        }

        public enum Connected {
            public static let title = "NetworkNotification.Connected.Title"
            public static let description = "NetworkNotification.Connected.Description"
        }

        public enum Connecting {
            public static let title = "NetworkNotification.Connecting.Title"
            public static let description = "NetworkNotification.Connecting.Description"
            public static let handshake = "NetworkNotification.Connecting.Handshake"
            public static let internetRestored = "NetworkNotification.Connecting.InternetRestored"
            public static let manualRetry = "NetworkNotification.Connecting.ManualRetry"
        }

        public enum Reconnecting {
            public static let title = "NetworkNotification.Reconnecting.Title"
            public static let description = "NetworkNotification.Reconnecting.Description"
        }

        public enum ServerNotResponding {
            public static let title = "NetworkNotification.ServerNotResponding.Title"
            public static let description = "NetworkNotification.ServerNotResponding.Description"
        }

        public enum ServerShuttingDown {
            public static let title = "NetworkNotification.ServerShuttingDown.Title"
            public static let description = "NetworkNotification.ServerShuttingDown.Description"
        }

        public enum ServerShutdown {
            public static let title = "NetworkNotification.ServerShutdown.Title"
            public static let description = "NetworkNotification.ServerShutdown.Description"
        }

        public enum Disconnected {
            public static let title = "NetworkNotification.Disconnected.Title"
            public static let description = "NetworkNotification.Disconnected.Description"
            public static let reason = "NetworkNotification.Disconnected.Reason"
            public static let rpcFailure = "NetworkNotification.Disconnected.RpcFailure"
            public static let handshakeFailed = "NetworkNotification.Disconnected.HandshakeFailed"
        }

        public enum RetriesExhausted {
            public static let title = "NetworkNotification.RetriesExhausted.Title"
            public static let description = "NetworkNotification.RetriesExhausted.Description"
            public static let withCount = "NetworkNotification.RetriesExhausted.WithCount"
        }

        public enum ServerReconnected {
            public static let title = "NetworkNotification.ServerReconnected.Title"
            public static let description = "NetworkNotification.ServerReconnected.Description"
        }

        public enum Recovering {
            public static let title = "NetworkNotification.Recovering.Title"
            public static let description = "NetworkNotification.Recovering.Description"
            public static let withCountdown = "NetworkNotification.Recovering.WithCountdown"
            public static let attempt = "NetworkNotification.Recovering.Attempt"
        }

        public enum Button {
            public static let retry = "NetworkNotification.Button.Retry"
        }

        public static let retryButton = "NetworkNotification.RetryButton"
        public static let dismissButton = "NetworkNotification.DismissButton"
    }
    public enum LanguageDetection {
        public static let title = "LanguageDetection.Title"
        public static let prompt = "LanguageDetection.Prompt"

        public enum Button {
            public static let confirm = "LanguageDetection.Button.Confirm"
            public static let decline = "LanguageDetection.Button.Decline"
        }
    }
}
