@testable import KsApi
@testable import Library
import Prelude
import ReactiveExtensions_TestHelpers
import ReactiveSwift
import XCTest

internal final class SignupViewModelTests: TestCase {
  fileprivate let vm: SignupViewModelType = SignupViewModel()
  fileprivate let emailTextFieldBecomeFirstResponder = TestObserver<(), Never>()
  fileprivate let isSignupButtonEnabled = TestObserver<Bool, Never>()
  fileprivate let logIntoEnvironment = TestObserver<AccessTokenEnvelope, Never>()
  fileprivate let logIntoEnvironmentAndShowEmailVerification = TestObserver<AccessTokenEnvelope, Never>()
  fileprivate let nameTextFieldBecomeFirstResponder = TestObserver<(), Never>()
  fileprivate let passwordTextFieldBecomeFirstResponder = TestObserver<(), Never>()
  fileprivate let postNotification = TestObserver<Notification.Name, Never>()
  fileprivate let setWeeklyNewsletterState = TestObserver<Bool, Never>()
  fileprivate let showError = TestObserver<String, Never>()

  override func setUp() {
    super.setUp()

    self.vm.outputs.emailTextFieldBecomeFirstResponder
      .observe(self.emailTextFieldBecomeFirstResponder.observer)
    self.vm.outputs.isSignupButtonEnabled.observe(self.isSignupButtonEnabled.observer)
    self.vm.outputs.logIntoEnvironment.observe(self.logIntoEnvironment.observer)
    self.vm.outputs.logIntoEnvironmentAndShowEmailVerification
      .observe(self.logIntoEnvironmentAndShowEmailVerification.observer)
    self.vm.outputs.nameTextFieldBecomeFirstResponder.observe(self.nameTextFieldBecomeFirstResponder.observer)
    self.vm.outputs.passwordTextFieldBecomeFirstResponder
      .observe(self.passwordTextFieldBecomeFirstResponder.observer)
    self.vm.outputs.postNotification.map { $0.name }.observe(self.postNotification.observer)
    self.vm.outputs.setWeeklyNewsletterState.observe(self.setWeeklyNewsletterState.observer)
    self.vm.outputs.showError.observe(self.showError.observer)
  }

  // Tests a standard flow for signing up.
  func testSignupFlow() {
    self.nameTextFieldBecomeFirstResponder.assertDidNotEmitValue()
    self.emailTextFieldBecomeFirstResponder.assertDidNotEmitValue()
    self.passwordTextFieldBecomeFirstResponder.assertDidNotEmitValue()

    self.vm.inputs.viewDidLoad()

    self.setWeeklyNewsletterState.assertValues([false], "Unselected when view loads.")
    self.isSignupButtonEnabled.assertValues([false], "Disabled when view loads.")
    self.nameTextFieldBecomeFirstResponder
      .assertValueCount(1, "Name field is first responder when view loads.")
    self.emailTextFieldBecomeFirstResponder.assertDidNotEmitValue("Not first responder when view loads.")
    self.passwordTextFieldBecomeFirstResponder.assertDidNotEmitValue("Not first responder when view loads.")

    self.vm.inputs.nameChanged("Native Squad")
    self.vm.inputs.nameTextFieldReturn()
    self.isSignupButtonEnabled.assertValues([false], "Disable while form is incomplete.")
    self.nameTextFieldBecomeFirstResponder.assertValueCount(1, "Does not emit again.")
    self.emailTextFieldBecomeFirstResponder.assertValueCount(1, "First responder after editing name.")
    self.passwordTextFieldBecomeFirstResponder
      .assertDidNotEmitValue("Not first responder after editing name.")

    self.vm.inputs.emailChanged("therealnativesquad@gmail.com")
    self.vm.inputs.emailTextFieldReturn()
    self.isSignupButtonEnabled.assertValues([false], "Disabled while form is incomplete.")
    self.nameTextFieldBecomeFirstResponder.assertValueCount(1, "Does not emit again.")
    self.emailTextFieldBecomeFirstResponder.assertValueCount(1, "Does not emit again.")
    self.passwordTextFieldBecomeFirstResponder.assertValueCount(1, "First responder after editing email.")

    self.vm.inputs.passwordChanged("0773rw473rm3l0n")
    self.isSignupButtonEnabled.assertValues([false, true], "Enabled when form is valid.")

    self.vm.inputs.signupButtonPressed()
    self.logIntoEnvironment.assertDidNotEmitValue("Does not immediately emit after signup button is pressed.")

    XCTAssertEqual(["Signup Submit Button Clicked"], self.trackingClient.events)

    self.scheduler.advance()

    self.logIntoEnvironment
      .assertValueCount(
        1,
        "Log into environment without showing email verification because feature flag is false (not set)."
      )
    self.logIntoEnvironmentAndShowEmailVerification.assertValueCount(0, "Did not show email verification.")
    self.postNotification.assertDidNotEmitValue("Does not emit until environment logged in.")

    self.vm.inputs.environmentLoggedIn()

    self.scheduler.advance()

    self.postNotification.assertValues(
      [.ksr_sessionStarted],
      "Notification posted after scheduler advances."
    )
  }

  func testSignupFlow_IsEmailVerifiedTrue_EmailVerificationFeatureFlagEnabled() {
    let config = .template
      |> Config.lens.features .~ [Feature.emailVerificationFlow.rawValue: true]
    let user = .template
      |> User.lens.isEmailVerified .~ true
    let signupResponse = AccessTokenEnvelope(accessToken: "deadbeef", user: user)

    withEnvironment(apiService: MockService(signupResponse: signupResponse), config: config) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.emailChanged("nativesquad@kickstarter.com")
      self.vm.inputs.nameChanged("Native Squad")
      self.vm.inputs.passwordChanged("0773rw473rm3l0n")
      self.vm.inputs.signupButtonPressed()

      self.showError.assertDidNotEmitValue()

      self.scheduler.advance()

      self.logIntoEnvironment.assertValueCount(1, "Logged into environment.")
      self.logIntoEnvironmentAndShowEmailVerification
        .assertValueCount(0, "Should not show email verificaton.")
      self.vm.inputs.passwordTextFieldReturn()
      self.showError.assertValueCount(0, "Should not show error.")
    }
  }

  func testSignupFlow_IsEmailVerifiedTrue_EmailVerificationFeatureFlagDisabled() {
    let config = .template
      |> Config.lens.features .~ [Feature.emailVerificationFlow.rawValue: false]
    let user = .template
      |> User.lens.isEmailVerified .~ true
    let signupResponse = AccessTokenEnvelope(accessToken: "deadbeef", user: user)

    withEnvironment(apiService: MockService(signupResponse: signupResponse), config: config) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.emailChanged("nativesquad@kickstarter.com")
      self.vm.inputs.nameChanged("Native Squad")
      self.vm.inputs.passwordChanged("0773rw473rm3l0n")
      self.vm.inputs.signupButtonPressed()

      self.showError.assertDidNotEmitValue()

      self.scheduler.advance()

      self.logIntoEnvironment.assertValueCount(1, "Logged into environment.")
      self.logIntoEnvironmentAndShowEmailVerification
        .assertValueCount(0, "Should not show email verificaton.")
      self.vm.inputs.passwordTextFieldReturn()
      self.showError.assertValueCount(0, "Should not show error.")
    }
  }

  func testSignupFlow_IsEmailVerifiedFalse_EmailVerificationFeatureFlagEnabled() {
    let config = .template
      |> Config.lens.features .~ [Feature.emailVerificationFlow.rawValue: true]
    let user = .template
      |> User.lens.isEmailVerified .~ false
    let signupResponse = AccessTokenEnvelope(accessToken: "deadbeef", user: user)

    withEnvironment(apiService: MockService(signupResponse: signupResponse), config: config) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.emailChanged("nativesquad@kickstarter.com")
      self.vm.inputs.nameChanged("Native Squad")
      self.vm.inputs.passwordChanged("0773rw473rm3l0n")
      self.vm.inputs.signupButtonPressed()

      self.showError.assertDidNotEmitValue()

      self.scheduler.advance()

      self.logIntoEnvironment.assertValueCount(0, "Did not log into environment.")
      self.logIntoEnvironmentAndShowEmailVerification
        .assertValueCount(1, "Logged into environment and showed email verification.")
      self.vm.inputs.passwordTextFieldReturn()
      self.showError.assertValueCount(0, "Should not show error.")
    }
  }

  func testSignupFlow_IsEmailVerifiedFalse_EmailVerificationFeatureFlagDisabled() {
    let config = .template
      |> Config.lens.features .~ [Feature.emailVerificationFlow.rawValue: false]
    let user = .template
      |> User.lens.isEmailVerified .~ false
    let signupResponse = AccessTokenEnvelope(accessToken: "deadbeef", user: user)

    withEnvironment(apiService: MockService(signupResponse: signupResponse), config: config) {
      self.vm.inputs.viewDidLoad()
      self.vm.inputs.emailChanged("nativesquad@kickstarter.com")
      self.vm.inputs.nameChanged("Native Squad")
      self.vm.inputs.passwordChanged("0773rw473rm3l0n")
      self.vm.inputs.signupButtonPressed()

      self.showError.assertDidNotEmitValue()

      self.scheduler.advance()

      self.logIntoEnvironment.assertValueCount(1, "Logged into environment..")
      self.logIntoEnvironmentAndShowEmailVerification
        .assertValueCount(0, "Did not show email verification.")
      self.vm.inputs.passwordTextFieldReturn()
      self.showError.assertValueCount(0, "Should not show error.")
    }
  }

  func testBecomeFirstResponder() {
    self.vm.inputs.viewDidLoad()
    self.nameTextFieldBecomeFirstResponder.assertValueCount(1, "Name starts as first responder.")
    self.emailTextFieldBecomeFirstResponder.assertDidNotEmitValue("Not first responder yet.")
    self.passwordTextFieldBecomeFirstResponder.assertDidNotEmitValue("Not first responder yet.")

    self.vm.inputs.nameTextFieldReturn()
    self.nameTextFieldBecomeFirstResponder.assertValueCount(1, "Does not emit another value.")
    self.emailTextFieldBecomeFirstResponder.assertValueCount(1, "Email becomes first responder.")
    self.passwordTextFieldBecomeFirstResponder.assertDidNotEmitValue("Not first responder yet.")

    self.vm.inputs.emailTextFieldReturn()
    self.nameTextFieldBecomeFirstResponder.assertValueCount(1, "Does not emit another value.")
    self.emailTextFieldBecomeFirstResponder.assertValueCount(1, "Does not emit another value.")
    self.passwordTextFieldBecomeFirstResponder.assertValueCount(1, "Password becomes first responder.")

    self.vm.inputs.passwordTextFieldReturn()
    self.nameTextFieldBecomeFirstResponder.assertValueCount(1, "Does not emit another value.")
    self.emailTextFieldBecomeFirstResponder.assertValueCount(1, "Does not emit another value.")
    self.passwordTextFieldBecomeFirstResponder.assertValueCount(1, "Does not emit another value.")
  }

  func testSetWeeklyNewsletterStateFalseOnViewDidLoad() {
    self.setWeeklyNewsletterState.assertDidNotEmitValue("Should not emit until view loads")

    self.withEnvironment(config: Config.deConfig) {
      self.vm.inputs.viewDidLoad()
      self.setWeeklyNewsletterState.assertValues([false], "False by default for non-US users.")
    }
  }

  func testShowError() {
    let error = "Password is too short (minimum is 6 characters)"
    let errorEnvelope = ErrorEnvelope(
      errorMessages: [error],
      ksrCode: nil,
      httpCode: 422,
      exception: nil
    )

    self.withEnvironment(apiService: MockService(signupError: errorEnvelope)) {
      self.vm.inputs.viewDidLoad()

      self.vm.inputs.emailChanged("nativesquad@kickstarter.com")
      self.vm.inputs.nameChanged("Native Squad")
      self.vm.inputs.passwordChanged("!")
      self.vm.inputs.signupButtonPressed()

      self.showError.assertDidNotEmitValue("Should not emit until scheduler advances.")

      self.scheduler.advance()
      self.logIntoEnvironment.assertValueCount(0, "Should not login.")
      self.showError.assertValues([error], "Signup error.")

      self.vm.inputs.passwordTextFieldReturn()
      self.showError.assertValueCount(1)

      scheduler.advance()
      self.showError.assertValues([error, error], "Signup error.")
    }
  }

  func testWeeklyNewsletterChanged() {
    self.vm.inputs.viewDidLoad()

    self.vm.inputs.weeklyNewsletterChanged(true)
    XCTAssertEqual(
      ["Subscribed To Newsletter", "Signup Newsletter Toggle"],
      self.trackingClient.events
    )
    XCTAssertEqual(
      [true],
      self.trackingClient.properties.compactMap { $0["send_newsletters"] as? Bool }
    )

    self.vm.inputs.weeklyNewsletterChanged(false)
    XCTAssertEqual(
      [
        "Subscribed To Newsletter", "Signup Newsletter Toggle",
        "Unsubscribed From Newsletter", "Signup Newsletter Toggle"
      ],
      self.trackingClient.events
    )
    XCTAssertEqual(
      [true, false],
      self.trackingClient.properties.compactMap { $0["send_newsletters"] as? Bool }
    )
  }
}
