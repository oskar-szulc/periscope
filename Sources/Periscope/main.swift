import Foundation
import AppKit

// Placeholder until CLI commands are wired up in Task 7
AppRunner.run {
    await MainActor.run {
        let engine = BrowserEngine()
        Task {
            do {
                let (title, url) = try await engine.navigate(
                    to: URL(string: "https://example.com")!)
                print("Navigated to: \(title ?? "(untitled)")")
                print("URL: \(url)")
            } catch {
                print("Error: \(error)")
            }
            engine.close()
            NSApp.terminate(nil)
        }
    }
}
