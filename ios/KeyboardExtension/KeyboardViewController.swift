import UIKit

class KeyboardViewController: UIInputViewController {

    private let inputTextView = UITextView()
    private let translateButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let nextKeyboardButton = UIButton(type: .system)

    // Simulator shares the Mac's network stack, so localhost correctly
    // reaches the Express server running on the host machine. This will
    // need to become the Mac's LAN IP (or a deployed URL) for testing on
    // a physical device.
    private let backendURL = URL(string: "http://localhost:3000/translate")!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewWillLayoutSubviews() {
        nextKeyboardButton.isHidden = !needsInputModeSwitchKey
        super.viewWillLayoutSubviews()
    }

    private func setupUI() {
        view.backgroundColor = .systemGray6

        inputTextView.font = .systemFont(ofSize: 16)
        inputTextView.layer.cornerRadius = 8
        inputTextView.layer.borderWidth = 1
        inputTextView.layer.borderColor = UIColor.systemGray4.cgColor
        inputTextView.autocorrectionType = .no
        inputTextView.translatesAutoresizingMaskIntoConstraints = false

        translateButton.setTitle("Translate", for: .normal)
        translateButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        translateButton.backgroundColor = .systemBlue
        translateButton.setTitleColor(.white, for: .normal)
        translateButton.layer.cornerRadius = 8
        translateButton.translatesAutoresizingMaskIntoConstraints = false
        translateButton.addTarget(self, action: #selector(translateTapped), for: .touchUpInside)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // Apple requires every custom keyboard to offer a way back to the
        // system keyboard (or the next one in the user's list). This
        // button doesn't implement that logic itself -- it just calls
        // handleInputModeList(from:with:), which UIInputViewController
        // already provides: tap cycles to the next keyboard, long-press
        // shows the full picker, matching stock keyboard behavior.
        nextKeyboardButton.setImage(UIImage(systemName: "globe"), for: .normal)
        nextKeyboardButton.tintColor = .label
        nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        nextKeyboardButton.addTarget(
            self,
            action: #selector(handleInputModeList(from:with:)),
            for: .allTouchEvents
        )

        view.addSubview(inputTextView)
        view.addSubview(translateButton)
        view.addSubview(statusLabel)
        view.addSubview(nextKeyboardButton)

        NSLayoutConstraint.activate([
            // Keyboard extensions size their own view -- there's no
            // storyboard/window controlling height, so we fix one
            // explicitly. Too tall and iOS will clip or reject the layout.
            view.heightAnchor.constraint(equalToConstant: 240),

            nextKeyboardButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            nextKeyboardButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            nextKeyboardButton.widthAnchor.constraint(equalToConstant: 28),
            nextKeyboardButton.heightAnchor.constraint(equalToConstant: 28),

            inputTextView.topAnchor.constraint(equalTo: nextKeyboardButton.bottomAnchor, constant: 8),
            inputTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            inputTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            inputTextView.heightAnchor.constraint(equalToConstant: 100),

            translateButton.topAnchor.constraint(equalTo: inputTextView.bottomAnchor, constant: 8),
            translateButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            translateButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            translateButton.heightAnchor.constraint(equalToConstant: 44),

            statusLabel.topAnchor.constraint(equalTo: translateButton.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
        ])
    }

    @objc private func translateTapped() {
        // hasFullAccess reflects whether the user has granted our keyboard
        // Full Access in Settings. Without it, the URLSession call below
        // would fail at the sandbox level -- checking first lets us show
        // a clear message instead of a confusing network error.
        guard hasFullAccess else {
            statusLabel.text = "Enable \"Allow Full Access\" for this keyboard in Settings to use translation."
            return
        }

        let englishText = inputTextView.text ?? ""
        guard !englishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        translateButton.isEnabled = false
        statusLabel.text = "Translating..."

        var request = URLRequest(url: backendURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": englishText])

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleResponse(data: data, error: error)
            }
        }.resume()
    }

    private func handleResponse(data: Data?, error: Error?) {
        translateButton.isEnabled = true

        if let error = error {
            statusLabel.text = "Network error: \(error.localizedDescription)"
            return
        }

        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            statusLabel.text = "Unexpected response from server."
            return
        }

        if let tamil = json["tamil"] as? String {
            textDocumentProxy.insertText(tamil)
            inputTextView.text = ""
            statusLabel.text = ""
        } else if let errorMessage = json["error"] as? String {
            statusLabel.text = errorMessage
        } else {
            statusLabel.text = "Unexpected response from server."
        }
    }
}
