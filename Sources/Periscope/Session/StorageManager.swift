import Foundation

enum StorageManager {
    static func injectionScript(for storage: PersistedStorage) -> String {
        storage.localStorage.map { key, value in
            let k = key.replacingOccurrences(of: "'", with: "\\'")
            let v = value.replacingOccurrences(of: "'", with: "\\'")
            return "localStorage.setItem('\(k)', '\(v)');"
        }.joined(separator: "\n")
    }

    static func extractionScript() -> String {
        """
        (function() {
            var result = {};
            for (var i = 0; i < localStorage.length; i++) {
                var key = localStorage.key(i);
                result[key] = localStorage.getItem(key);
            }
            return JSON.stringify(result);
        })();
        """
    }
}
