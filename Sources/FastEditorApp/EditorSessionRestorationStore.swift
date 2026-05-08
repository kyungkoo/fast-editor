import FastEditorModels
import Foundation

struct EditorSessionRestorationStore {
    private let key = "FastEditor.EditorSessionRestoration.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> EditorSessionRestorationState? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(EditorSessionRestorationState.self, from: data)
    }

    func save(_ state: EditorSessionRestorationState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
