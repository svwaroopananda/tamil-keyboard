import UIKit
import TamilCore

class KeyboardViewController: UIInputViewController {

    private static let messageBarHeight: CGFloat = 24

    private var engine = KeyboardEngine()
    private let translationClient = TranslationClient()

    // VC-level flag purely for immediate, synchronous UI feedback (disabling
    // the key view the instant Translate is tapped) -- separate from, and
    // in addition to, TranslationClient's own actor-internal in-flight
    // guard, which remains the actual correctness backstop. Same
    // "UI disables eagerly, package enforces definitively" pattern used
    // elsewhere in this codebase.
    private var isTranslating = false

    private let layoutView = KeyboardLayoutView()
    private let messageLabel = UILabel()
    private var messageDismissWorkItem: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        wireCallbacks()
    }

    override func viewWillLayoutSubviews() {
        layoutView.setGlobeVisible(needsInputModeSwitchKey)
        super.viewWillLayoutSubviews()
    }

    // A courtesy notification from the system that the document may have
    // changed -- not guaranteed to fire for every host app (some
    // WebView-backed text fields don't fire it reliably), so this is only
    // a soft signal that resets stale tracking promptly. The authoritative
    // check happens again, synchronously, right before the translate flow
    // actually deletes/inserts anything.
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        _ = engine.prepareTranslateRequest(documentContextBeforeInput: textDocumentProxy.documentContextBeforeInput)
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemGray6

        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 1
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(messageLabel)
        view.addSubview(layoutView)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: Self.messageBarHeight + KeyboardLayoutView.height),

            messageLabel.topAnchor.constraint(equalTo: view.topAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            messageLabel.heightAnchor.constraint(equalToConstant: Self.messageBarHeight),

            layoutView.topAnchor.constraint(equalTo: messageLabel.bottomAnchor),
            layoutView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            layoutView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            layoutView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        layoutView.globeButton.addTarget(
            self,
            action: #selector(handleInputModeList(from:with:)),
            for: .allTouchEvents
        )
    }

    private func wireCallbacks() {
        layoutView.onCharacter = { [weak self] character in
            self?.type(character)
        }
        layoutView.onShiftTap = { [weak self] in
            self?.toggleShift()
        }
        layoutView.onBackspaceDown = { [weak self] in
            self?.backspace()
        }
        layoutView.onLayerToggleTap = { [weak self] in
            self?.toggleLayer()
        }
        layoutView.onTranslateTap = { [weak self] in
            Task { await self?.translateTapped() }
        }
    }

    // MARK: - Typing (every key types directly into the host app's field)

    private func type(_ character: Character) {
        let inserted = engine.type(character)
        textDocumentProxy.insertText(String(inserted))
    }

    private func toggleShift() {
        engine.toggleShift()
        layoutView.setShiftHighlighted(engine.shiftState == .shiftedOnce)
    }

    private func backspace() {
        engine.backspace()
        textDocumentProxy.deleteBackward()
    }

    private func toggleLayer() {
        let newLayer: KeyboardEngine.Layer = (engine.layer == .letters) ? .numbers : .letters
        engine.switchLayer(to: newLayer)
        layoutView.setLayer(newLayer)
    }

    // MARK: - Translate

    private func translateTapped() async {
        guard !isTranslating else { return }

        guard hasFullAccess else {
            showMessage("Enable \"Allow Full Access\" for this keyboard in Settings to use translation.")
            return
        }

        let availability = engine.prepareTranslateRequest(
            documentContextBeforeInput: textDocumentProxy.documentContextBeforeInput
        )

        let textToTranslate: String
        switch availability {
        case .ready(let text):
            textToTranslate = text
        case .nothingToTranslate:
            showMessage("Type something to translate.")
            return
        case .tooLong:
            showMessage("Message too long to translate.")
            return
        case .contextUnavailable:
            showMessage("Translation isn't available in this text field.")
            return
        }

        isTranslating = true
        layoutView.setTranslating(true)

        do {
            let tamil = try await translationClient.translate(textToTranslate)
            replaceTrackedEnglish(withTamil: tamil, expecting: textToTranslate)
        } catch {
            showMessage(friendlyMessage(for: error))
        }

        isTranslating = false
        layoutView.setTranslating(false)
    }

    // Re-validates, synchronously and authoritatively, right before
    // mutating anything -- textDidChange alone isn't trusted, since it
    // doesn't fire reliably for every host app.
    private func replaceTrackedEnglish(withTamil tamil: String, expecting expectedEnglish: String) {
        let availability = engine.prepareTranslateRequest(
            documentContextBeforeInput: textDocumentProxy.documentContextBeforeInput
        )

        guard case .ready(let currentText) = availability, currentText == expectedEnglish else {
            showMessage("Text changed, please try again.")
            return
        }

        for _ in expectedEnglish {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(tamil)
        engine.resetAfterTranslation()
    }

    private func friendlyMessage(for error: Error) -> String {
        guard let translationError = error as? TranslationError else {
            return "Something went wrong. Please try again."
        }

        switch translationError {
        case .emptyInput:
            return "Type something to translate."
        case .backendUnreachable:
            return "Can't reach the translation server. Check it's running."
        case .unexpectedStatusCode(_, let message):
            return message ?? "Translation failed. Please try again."
        case .malformedResponse:
            return "Got an unexpected response. Please try again."
        case .requestInFlight:
            return "Still translating, one sec..."
        }
    }

    private func showMessage(_ text: String) {
        messageDismissWorkItem?.cancel()

        messageLabel.text = text
        messageLabel.alpha = 0
        UIView.animate(withDuration: 0.15) {
            self.messageLabel.alpha = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.3) {
                self?.messageLabel.alpha = 0
            }
        }
        messageDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }
}
