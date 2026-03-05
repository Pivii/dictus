// DictusKeyboard/KeyboardViewController.swift
import UIKit
import SwiftUI
import DictusCore

class KeyboardViewController: UIInputViewController {

    private var hostingController: UIHostingController<KeyboardRootView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        #if DEBUG
        let result = AppGroupDiagnostic.run()
        if #available(iOS 14.0, *) {
            DictusLogger.keyboard.debug(
                "Diagnostic: canWrite=\(result.canWrite) canRead=\(result.canRead)"
            )
        }
        #endif

        let rootView = KeyboardRootView(controller: self)
        let hosting = UIHostingController(rootView: rootView)

        // Critical: retain the hosting controller or it gets deallocated
        self.hostingController = hosting

        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        // Remove default background so the keyboard blends with host app
        hosting.view.backgroundColor = .clear

        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Darwin observers cleaned up by KeyboardState deinit
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Future: react to cursor position changes, return key type, etc.
    }
}
