import Foundation

/// Splits a line of JVM options the way HMCL's own build does, so what you type
/// here behaves the same as what HMCL passes itself.
///
/// Mirrors `parseToolOptions` in HMCL's `HMCL/build.gradle.kts`. Quotes group
/// rather than delimit, so `"a b"c` is the single argument `a bc`.
///
/// One deliberate difference: HMCL throws on an unmatched quote. This field is
/// edited live, and half-typed input is normal, so the rest of the line is taken
/// literally instead.
public enum JavaOptions {
    /// Nothing here is validated or filtered. `-jar` will break the launch, and
    /// that is the caller's business.
    public static func parse(_ text: String) -> [String] {
        let characters = Array(text)
        var arguments: [String] = []
        var current = ""
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character.isWhitespace {
                if !current.isEmpty {
                    arguments.append(current)
                    current = ""
                }
                while index < characters.count, characters[index].isWhitespace {
                    index += 1
                }
                continue
            }

            if character == "\"" || character == "'" {
                index += 1
                while index < characters.count {
                    let next = characters[index]
                    index += 1
                    if next == character { break }
                    current.append(next)
                }
                continue
            }

            current.append(character)
            index += 1
        }

        if !current.isEmpty {
            arguments.append(current)
        }
        return arguments
    }
}
