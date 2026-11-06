import LoquiShared
import SwiftUI
import UIKit

/// Solo interfaccia: l'audio e i modelli stanno nell'app. Questo target non contiene codice di rete
/// e non linka i motori: lo verifica `scripts/verify-keyboard-privacy.sh`.
@objc(KeyboardViewController)
final class KeyboardViewController: UIInputViewController {
    private lazy var model = KeyboardModel(controller: self)

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: KeyboardView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.heightAnchor.constraint(equalToConstant: 216),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.didAppear()
    }

    override func textWillChange(_ textInput: (any UITextInput)?) {
        super.textWillChange(textInput)
        model.showsGlobe = needsInputModeSwitchKey
    }
}
