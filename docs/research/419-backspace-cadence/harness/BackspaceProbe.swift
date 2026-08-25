// BackspaceProbe -- the measurement harness for issue #419.
//
// A one-screen iOS app whose only job is to report, on a monotonic millisecond clock,
// every text mutation a keyboard issues into it -- INCLUDING a delete that deletes
// nothing because the field is already empty. That last case is invisible to the
// accessibility tree, and it is the question #419 has to answer: does Apple's keyboard
// keep ticking in an emptied field?
//
// Simulator only, and deliberately outside the Xcode project: it is a measuring
// instrument, not a product target.
//
// Build:
//   mkdir -p /tmp/BackspaceProbe.app
//   cp Info.plist /tmp/BackspaceProbe.app/
//   xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios17.0-simulator \
//       -parse-as-library BackspaceProbe.swift -o /tmp/BackspaceProbe.app/BackspaceProbe
//   codesign -s - --force /tmp/BackspaceProbe.app
//
// Run:
//   xcrun simctl install <udid> /tmp/BackspaceProbe.app
//   xcrun simctl launch  <udid> solutions.pivi.backspaceprobe -probeText "..."
//   xcrun simctl get_app_container <udid> solutions.pivi.backspaceprobe data
//   -> Documents/probe.log

import UIKit

enum ProbeLog {
    private static let url: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("probe.log")
    }()

    static func reset() {
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }

    /// Milliseconds on a monotonic clock. `systemUptime` does not jump with the wall
    /// clock, and the whole measurement is inter-event deltas.
    static func nowMs() -> Double {
        ProcessInfo.processInfo.systemUptime * 1000.0
    }

    static func log(_ line: String) {
        let stamped = String(format: "%.1f\t%@\n", nowMs(), line)
        guard let data = stamped.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? stamped.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// Every mutation path a keyboard can take into a text view, instrumented.
final class ProbeTextView: UITextView {
    /// The keyboard calls this on the first responder for each delete it issues, and it
    /// calls it even when there is nothing left to delete. That is the point of the
    /// subclass: an emptied field still logs a line per tick.
    override func deleteBackward() {
        let before = text.count
        ProbeLog.log("deleteBackward.in\tlen=\(before)")
        super.deleteBackward()
        ProbeLog.log("deleteBackward.out\tlen=\(text.count)\tdeleted=\(before - text.count)")
    }

    override func insertText(_ textToInsert: String) {
        ProbeLog.log("insertText\ttext=\(textToInsert.debugDescription)\tlen=\(text.count)")
        super.insertText(textToInsert)
    }

    /// A word deletion could arrive as one ranged replacement rather than as a burst of
    /// deleteBackward calls. Logging both is what tells the two shapes apart.
    override func replace(_ range: UITextRange, withText replacementText: String) {
        let start = offset(from: beginningOfDocument, to: range.start)
        let end = offset(from: beginningOfDocument, to: range.end)
        ProbeLog.log("replace\trange=\(start)..<\(end)\ttext=\(replacementText.debugDescription)")
        super.replace(range, withText: replacementText)
    }
}

/// A secure field, for the one case a context-based "is there anything to delete"
/// rule can get wrong: iOS withholds `documentContextBeforeInput` from a keyboard
/// extension here at all times, so an empty context does NOT mean an empty document.
/// `-secureField 1` focuses this instead of the text view.
final class ProbeSecureField: UITextField {
    override func deleteBackward() {
        let before = (text ?? "").count
        ProbeLog.log("secure.deleteBackward.in\tlen=\(before)")
        super.deleteBackward()
        ProbeLog.log("secure.deleteBackward.out\tlen=\((text ?? "").count)\tdeleted=\(before - (text ?? "").count)")
    }
}

final class ProbeViewController: UIViewController, UITextViewDelegate {
    /// The control arm. `-plainField 1` swaps the instrumented subclass for a stock
    /// `UITextView`, so a result can be checked against a field that overrides nothing.
    /// The delegate callbacks still fire, and "how long does the hold take to empty the
    /// field" is measurable in both arms -- which is what tells you whether overriding
    /// `deleteBackward` changed the keyboard's behaviour or merely observed it.
    private let textView: UITextView = UserDefaults.standard.bool(forKey: "plainField")
        ? UITextView()
        : ProbeTextView()
    private let secureField = ProbeSecureField()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        textView.delegate = self
        textView.font = .systemFont(ofSize: 17)
        // Autocorrection and the smart-punctuation substitutions would mutate the text
        // on their own schedule and contaminate the timeline.
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.accessibilityIdentifier = "probeField"
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.heightAnchor.constraint(equalToConstant: 240)
        ])

        // Only mounted when asked for. A secure field present in the hierarchy is a
        // candidate explanation for iOS declining to offer third-party keyboards to
        // this app at all, so it must not be there by default.
        guard UserDefaults.standard.bool(forKey: "secureField") else { return }
        secureField.isSecureTextEntry = true
        secureField.borderStyle = .roundedRect
        secureField.accessibilityIdentifier = "probeSecureField"
        secureField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(secureField)
        NSLayoutConstraint.activate([
            secureField.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 16),
            secureField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            secureField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let seed = UserDefaults.standard.string(forKey: "probeText") ?? "hello world"
        textView.text = seed
        textView.selectedRange = NSRange(location: seed.count, length: 0)
        ProbeLog.log("seeded\tlen=\(seed.count)\ttext=\(seed.debugDescription)")
        if UserDefaults.standard.bool(forKey: "secureField") {
            secureField.text = seed
            secureField.becomeFirstResponder()
            ProbeLog.log("firstResponder\tfield=secure\tvalue=\(secureField.isFirstResponder)")
        } else {
            textView.becomeFirstResponder()
            // `-selectAll 1` builds the exact state that reverted the previous attempt
            // at this guard: a selection anchored at offset 0, which leaves the host
            // reporting an empty before-context while a real deletion is pending (#419).
            if UserDefaults.standard.bool(forKey: "selectAll") {
                textView.selectedRange = NSRange(location: 0, length: seed.count)
                ProbeLog.log("selectedAll\trange=0..<\(seed.count)")
            }
            ProbeLog.log("firstResponder\tfield=text\tvalue=\(textView.isFirstResponder)")
        }
    }

    func textView(_ textView: UITextView,
                  shouldChangeTextIn range: NSRange,
                  replacementText text: String) -> Bool {
        ProbeLog.log("shouldChange\tloc=\(range.location)\tlen=\(range.length)\trepl=\(text.debugDescription)")
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        ProbeLog.log("didChange\tlen=\(textView.text.count)\ttail=\(String(textView.text.suffix(28)).debugDescription)")
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        ProbeLog.reset()
        ProbeLog.log("launch")
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ProbeViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
