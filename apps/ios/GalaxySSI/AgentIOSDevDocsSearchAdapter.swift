import Foundation

enum AgentIOSDevDocsSearchAdapter {
  static let entry = AgentIOSJSONWebSearchAdapter.Entry(id: "devdocs", title: "DevDocs", vertical: .docs,
    template: "local://devdocs", authority: 0.9)
  private struct Document {
    let title: String
    let slug: String
    let aliases: [String]
  }
  private static let documents: [Document] = [
    .init(title: "React", slug: "react", aliases: ["react", "reactjs"]),
    .init(title: "Vue", slug: "vue~3", aliases: ["vue", "vuejs"]),
    .init(title: "Angular", slug: "angular", aliases: ["angular"]),
    .init(title: "Svelte", slug: "svelte", aliases: ["svelte"]),
    .init(title: "TypeScript", slug: "typescript", aliases: ["typescript", "ts"]),
    .init(title: "JavaScript", slug: "javascript", aliases: ["javascript", "js", "ecmascript"]),
    .init(title: "Node.js", slug: "node", aliases: ["node", "nodejs", "node.js"]),
    .init(title: "Python", slug: "python~3.13", aliases: ["python", "python3"]),
    .init(title: "Go", slug: "go", aliases: ["golang"]),
    .init(title: "Rust", slug: "rust", aliases: ["rust"]),
    .init(title: "CSS", slug: "css", aliases: ["css"]),
    .init(title: "HTML", slug: "html", aliases: ["html"]),
    .init(title: "HTTP", slug: "http", aliases: ["http"]),
    .init(title: "PostgreSQL", slug: "postgresql~17", aliases: ["postgresql", "postgres"]),
    .init(title: "SQLite", slug: "sqlite", aliases: ["sqlite"]),
    .init(title: "Redis", slug: "redis", aliases: ["redis"]),
    .init(title: "Docker", slug: "docker", aliases: ["docker"]),
    .init(title: "Git", slug: "git", aliases: ["git"]),
    .init(title: "Bash", slug: "bash", aliases: ["bash", "shell"]),
    .init(title: "nginx", slug: "nginx", aliases: ["nginx"]),
    .init(title: "webpack", slug: "webpack~5", aliases: ["webpack"]),
    .init(title: "Tailwind CSS", slug: "tailwindcss", aliases: ["tailwind", "tailwindcss"])
  ]

  static func search(_ query: String, limit: Int) -> [AgentIOSPublicSearchParser.Hit] {
    guard limit > 0 else { return [] }
    let normalized = String(query.prefix(4096)).lowercased()
    let matches = documents.filter { doc in
      doc.aliases.contains { alias in
        normalized.range(of: "(^|[^a-z0-9])" + NSRegularExpression.escapedPattern(for: alias) + "([^a-z0-9]|$)",
          options: .regularExpression) != nil
      }
    }
    let tokens = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 3 }
    let selected = matches.isEmpty ? documents.filter { doc in
      tokens.contains { doc.title.lowercased().contains($0) || doc.slug.contains($0) }
    } : matches
    return selected.prefix(min(limit, 100)).map { doc in
      .init(title: doc.title + " documentation", url: "https://devdocs.io/" + doc.slug,
        excerpt: "Offline DevDocs index match for " + doc.title + ".", retrievalStatus: "local_index_reference")
    }
  }
}
