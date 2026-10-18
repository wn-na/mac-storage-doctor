import Foundation

/// Cache copies of manifests describe dependencies, not user workspaces.
public enum ProjectDiscoveryPolicy {
    public static let excludedComponents: Set<String> = [
        ".npm", ".gradle", ".cocoapods", ".pub-cache", ".pnpm-store", ".yarn", ".m2",
        "node_modules", "Pods", ".git", ".build", ".dart_tool", "DerivedData", ".Trash"
    ]
    public static func isExcluded(_ url: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        if components.contains(where: { excludedComponents.contains($0) || $0.hasSuffix(".app") }) { return true }
        let managedPaths = [["Library", "Caches"], ["Library", "Android", "sdk"], ["Library", "Developer", "CoreSimulator"]]
        for path in managedPaths where components.count >= path.count {
            for index in 0...(components.count - path.count) {
                if Array(components[index..<(index + path.count)]) == path { return true }
            }
        }
        for key in ["NPM_CONFIG_CACHE", "npm_config_cache", "GRADLE_USER_HOME", "PUB_CACHE", "YARN_CACHE_FOLDER", "PNPM_HOME"] {
            guard let path = environment[key], path.hasPrefix("/"), path != "/" else { continue }
            let root = URL(fileURLWithPath: path).standardizedFileURL.path
            if url.standardizedFileURL.path == root || url.standardizedFileURL.path.hasPrefix(root + "/") { return true }
        }
        return false
    }
    public static func removeCachedProjects(from report: ScanReport) -> ScanReport {
        var result = report
        result.projects = ProjectClassifier.group(report.projects.filter { !isExcluded($0.root) })
        result.artifacts = report.artifacts.filter { artifact in
            guard let project = artifact.projectID else { return true } // Keep shared cache measurements.
            return !isExcluded(URL(fileURLWithPath: project))
        }
        return result
    }
}
