import UIKit
import TamilCore

/// Renders the actual key grid. Builds both the letters-layer and
/// numbers-layer button rows once at init and toggles visibility between
/// them on layer switch, rather than tearing down and rebuilding the view
/// hierarchy on every 123/ABC tap -- a real concern given the extension's
/// tight memory ceiling. Knows nothing about translation state or typing
/// logic beyond reporting taps; KeyboardViewController owns all of that.
final class KeyboardLayoutView: UIView {

    // Row count is fixed regardless of layer (3 key rows + 1 action row),
    // so switching layers never changes the view's height.
    static let height: CGFloat = 216

    private static let keyHeight: CGFloat = 44
    private static let rowSpacing: CGFloat = 8
    private static let actionButtonWidth: CGFloat = 60

    var onCharacter: ((Character) -> Void)?
    var onShiftTap: (() -> Void)?
    var onBackspaceDown: (() -> Void)?
    var onBackspaceUp: (() -> Void)?
    var onLayerToggleTap: (() -> Void)?
    var onTranslateTap: (() -> Void)?

    let globeButton = KeyButton(systemImageName: "globe")
    private let translateButton = KeyButton(title: "Translate", isProminent: true)
    private let translateSpinner = UIActivityIndicatorView(style: .medium)
    private let shiftButton = KeyButton(systemImageName: "shift")
    private let layerToggleButton = KeyButton(title: "123")

    private let lettersContainer = UIStackView()
    private let numbersContainer = UIStackView()

    private var backspaceRepeatTimer: Timer?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        buildLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Public state updates (driven by the view controller)

    func setLayer(_ layer: KeyboardEngine.Layer) {
        lettersContainer.isHidden = (layer != .letters)
        numbersContainer.isHidden = (layer != .numbers)
        layerToggleButton.setTitle(layer == .letters ? "123" : "ABC", for: .normal)
    }

    func setShiftHighlighted(_ highlighted: Bool) {
        shiftButton.backgroundColor = highlighted ? .systemGray2 : .secondarySystemBackground
    }

    func setGlobeVisible(_ visible: Bool) {
        globeButton.isHidden = !visible
    }

    func setTranslating(_ translating: Bool) {
        isUserInteractionEnabled = !translating
        alpha = translating ? 0.5 : 1.0

        translateButton.setTitle(translating ? nil : "Translate", for: .normal)
        if translating {
            translateSpinner.startAnimating()
        } else {
            translateSpinner.stopAnimating()
        }
    }

    // MARK: - Layout construction

    private func buildLayout() {
        let outer = UIStackView()
        outer.axis = .vertical
        outer.spacing = Self.rowSpacing
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        lettersContainer.axis = .vertical
        lettersContainer.spacing = Self.rowSpacing
        numbersContainer.axis = .vertical
        numbersContainer.spacing = Self.rowSpacing

        buildLettersLayer()
        buildNumbersLayer()
        numbersContainer.isHidden = true

        outer.addArrangedSubview(lettersContainer)
        outer.addArrangedSubview(numbersContainer)
        outer.addArrangedSubview(buildActionRow())
    }

    private func buildLettersLayer() {
        lettersContainer.addArrangedSubview(characterRow("qwertyuiop"))
        lettersContainer.addArrangedSubview(characterRow("asdfghjkl"))

        let row3 = UIStackView()
        row3.axis = .horizontal
        row3.spacing = 4
        row3.distribution = .fillEqually
        row3.heightAnchor.constraint(equalToConstant: Self.keyHeight).isActive = true

        shiftButton.addTarget(self, action: #selector(shiftTapped), for: .touchUpInside)
        row3.addArrangedSubview(shiftButton)
        for character in "zxcvbnm" {
            row3.addArrangedSubview(characterButton(character))
        }
        row3.addArrangedSubview(backspaceButton())

        lettersContainer.addArrangedSubview(row3)
    }

    private func buildNumbersLayer() {
        numbersContainer.addArrangedSubview(characterRow("1234567890"))
        numbersContainer.addArrangedSubview(characterRow("-/:;()$&@\""))

        let row3 = UIStackView()
        row3.axis = .horizontal
        row3.spacing = 4
        row3.distribution = .fillEqually
        row3.heightAnchor.constraint(equalToConstant: Self.keyHeight).isActive = true

        for character in ".,?!'" {
            row3.addArrangedSubview(characterButton(character))
        }
        row3.addArrangedSubview(backspaceButton())

        numbersContainer.addArrangedSubview(row3)
    }

    private func buildActionRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 4
        row.heightAnchor.constraint(equalToConstant: Self.keyHeight).isActive = true

        layerToggleButton.addTarget(self, action: #selector(layerToggleTapped), for: .touchUpInside)
        layerToggleButton.widthAnchor.constraint(equalToConstant: Self.actionButtonWidth).isActive = true
        row.addArrangedSubview(layerToggleButton)

        globeButton.widthAnchor.constraint(equalToConstant: Self.actionButtonWidth).isActive = true
        row.addArrangedSubview(globeButton)

        let spaceButton = characterButton(" ", title: "space")
        spaceButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spaceButton)

        translateButton.addTarget(self, action: #selector(translateTapped), for: .touchUpInside)
        translateButton.widthAnchor.constraint(equalToConstant: 90).isActive = true
        translateSpinner.hidesWhenStopped = true
        translateSpinner.color = .white
        translateSpinner.translatesAutoresizingMaskIntoConstraints = false
        translateButton.addSubview(translateSpinner)
        NSLayoutConstraint.activate([
            translateSpinner.centerXAnchor.constraint(equalTo: translateButton.centerXAnchor),
            translateSpinner.centerYAnchor.constraint(equalTo: translateButton.centerYAnchor),
        ])
        row.addArrangedSubview(translateButton)

        let returnButton = characterButton("\n", title: "Return", isProminent: true)
        returnButton.widthAnchor.constraint(equalToConstant: Self.actionButtonWidth).isActive = true
        row.addArrangedSubview(returnButton)

        return row
    }

    private func characterRow(_ characters: String) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 4
        row.distribution = .fillEqually
        row.heightAnchor.constraint(equalToConstant: Self.keyHeight).isActive = true
        for character in characters {
            row.addArrangedSubview(characterButton(character))
        }
        return row
    }

    private func characterButton(_ character: Character, title: String? = nil, isProminent: Bool = false) -> KeyButton {
        let button = KeyButton(title: title ?? String(character), isProminent: isProminent)
        button.addAction(UIAction { [weak self] _ in
            self?.onCharacter?(character)
        }, for: .touchUpInside)
        return button
    }

    private func backspaceButton() -> KeyButton {
        let button = KeyButton(systemImageName: "delete.left")
        button.addTarget(self, action: #selector(backspaceTouchDown), for: .touchDown)
        button.addTarget(self, action: #selector(backspaceTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return button
    }

    // MARK: - Actions

    @objc private func shiftTapped() {
        onShiftTap?()
    }

    @objc private func layerToggleTapped() {
        onLayerToggleTap?()
    }

    @objc private func translateTapped() {
        onTranslateTap?()
    }

    @objc private func backspaceTouchDown() {
        onBackspaceDown?()

        // Timer must be added in .common run loop mode, not the default --
        // touch tracking runs in .tracking/.common territory, and a
        // default-mode timer can stall exactly while a finger is held down.
        let timer = Timer(timeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.startFastBackspaceRepeat()
        }
        RunLoop.current.add(timer, forMode: .common)
        backspaceRepeatTimer = timer
    }

    private func startFastBackspaceRepeat() {
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.onBackspaceDown?()
        }
        RunLoop.current.add(timer, forMode: .common)
        backspaceRepeatTimer = timer
    }

    @objc private func backspaceTouchUp() {
        backspaceRepeatTimer?.invalidate()
        backspaceRepeatTimer = nil
        onBackspaceUp?()
    }
}
