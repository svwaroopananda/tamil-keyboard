import UIKit

/// A single key. Centralizes styling (light/dark via semantic colors,
/// rounded corners, press-highlight) in one place instead of repeating it
/// at every call site -- there are ~40+ of these on screen at once.
final class KeyButton: UIButton {
    init(title: String? = nil, systemImageName: String? = nil, isProminent: Bool = false) {
        super.init(frame: .zero)
        configure(title: title, systemImageName: systemImageName, isProminent: isProminent)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure(title: nil, systemImageName: nil, isProminent: false)
    }

    private func configure(title: String?, systemImageName: String?, isProminent: Bool) {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 5
        titleLabel?.font = .systemFont(ofSize: 16)

        if let title {
            setTitle(title, for: .normal)
        }
        if let systemImageName {
            setImage(UIImage(systemName: systemImageName), for: .normal)
        }

        applyColors(isProminent: isProminent)

        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    private func applyColors(isProminent: Bool) {
        tintColor = .label
        setTitleColor(.label, for: .normal)
        backgroundColor = isProminent ? .systemBlue : .secondarySystemBackground
        if isProminent {
            setTitleColor(.white, for: .normal)
            tintColor = .white
        }
    }

    @objc private func touchDown() {
        alpha = 0.6
    }

    @objc private func touchUp() {
        alpha = 1.0
    }
}
