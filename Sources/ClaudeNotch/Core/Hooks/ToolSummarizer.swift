import Foundation

struct ToolSummary: Equatable, Sendable {
    let displayToolName: String
    let headline: String
    let summary: String
    let detail: String?
}

enum ToolSummarizer {
    static let displayLimit: Int = 20_000
    static let summaryLimit: Int = 200

    /// "mcp__github__create_issue" -> "github · create_issue"
    static func displayName(for toolName: String) -> String {
        if toolName.hasPrefix("mcp__") {
            let parts: [String] = toolName.components(separatedBy: "__")
            if parts.count >= 3 {
                let rest: String = parts[2...].joined(separator: "__")
                return parts[1] + " · " + rest
            }
        }
        return toolName
    }

    static func summarize(toolName: String, toolInput: JSONValue) -> ToolSummary {
        let display: String = displayName(for: toolName)
        let input: JSONValue = toolInput

        func text(_ key: String) -> String? {
            guard let s = input[key]?.stringValue, !s.isEmpty else { return nil }
            return s
        }

        var headline: String = "Claude wants to use"
        var summary: String? = nil
        var detail: String? = nil

        switch toolName {
        case "Bash":
            headline = "Claude wants to run"
            if let cmd = text("command") {
                summary = firstLine(cmd)
                detail = truncate(cmd, limit: displayLimit)
            }
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            headline = "Claude wants to edit"
            if let path = text("file_path") ?? text("notebook_path") {
                summary = path
                detail = path
            }
        case "Read":
            if let path = text("file_path") { summary = path; detail = path }
        case "WebFetch":
            if let url = text("url") { summary = url }
        case "WebSearch":
            if let q = text("query") { summary = q }
        case "Grep", "Glob":
            if let p = text("pattern") { summary = p }
        case "Task":
            if let d = text("description") { summary = d }
        default:
            break
        }

        if detail == nil, !isEmptyInput(input) {
            detail = truncate(input.prettyString(), limit: displayLimit)
        }
        if summary == nil {
            summary = isEmptyInput(input) ? display : input.compactString()
        }
        let finalSummary: String = truncate(firstLine(summary ?? display) ?? display, limit: summaryLimit)
        return ToolSummary(displayToolName: display, headline: headline, summary: finalSummary, detail: detail)
    }

    /// Short activity text for a running tool ("Running Bash").
    static func activityText(toolName: String) -> String {
        switch toolName {
        case "AskUserQuestion": return "Asking a question"
        case "Read": return "Reading files"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return "Editing files"
        case "Grep", "Glob": return "Searching"
        case "WebFetch", "WebSearch": return "Browsing the web"
        case "Task": return "Running subagent"
        default: return "Running " + displayName(for: toolName)
        }
    }

    /// `tool_name + "|" + tool_input.compactString()`
    static func fingerprint(toolName: String, toolInput: JSONValue) -> String {
        return toolName + "|" + toolInput.compactString()
    }

    /// First non-empty line of `text`, trimmed.
    static func firstLine(_ text: String) -> String? {
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    static func truncate(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "…"
    }

    private static func isEmptyInput(_ input: JSONValue) -> Bool {
        switch input {
        case .null: return true
        case .object(let o): return o.isEmpty
        default: return false
        }
    }

    /// Parses AskUserQuestion's tool_input. Returns nil if malformed / empty / more than 4 questions.
    static func parseQuestions(toolInput: JSONValue) -> QuestionRequest? {
        guard let rawQuestions = toolInput["questions"]?.arrayValue else { return nil }
        if rawQuestions.isEmpty || rawQuestions.count > 4 { return nil }
        var prompts: [QuestionPrompt] = []
        for raw in rawQuestions {
            guard let q = raw["question"]?.stringValue, !q.isEmpty else { return nil }
            guard let rawOptions = raw["options"]?.arrayValue, !rawOptions.isEmpty else { return nil }
            var options: [QuestionOption] = []
            for ro in rawOptions {
                if let label = ro.stringValue, !label.isEmpty {
                    options.append(QuestionOption(label: label, description: nil))
                } else if let label = ro["label"]?.stringValue, !label.isEmpty {
                    options.append(QuestionOption(label: label, description: ro["description"]?.stringValue))
                } else {
                    return nil
                }
            }
            let header: String? = raw["header"]?.stringValue
            let multi: Bool = raw["multiSelect"]?.boolValue ?? false
            prompts.append(QuestionPrompt(question: q, header: header, options: options, multiSelect: multi))
        }
        return QuestionRequest(questions: prompts)
    }
}
