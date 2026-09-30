import UIKit

// Placeholder onboarding screen. Its whole job is telling the user how
// to enable the keyboard and grant Full Access -- the host app doesn't
// otherwise participate in translation.
class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = """
        To use Tamil Keyboard:

        1. Go to Settings > General > Keyboard > Keyboards
        2. Tap "Add New Keyboard..." and choose Tamil Keyboard
        3. Tap Tamil Keyboard again and enable "Allow Full Access"

        Full Access is required because the keyboard sends your typed text to our translation server.
        """
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
