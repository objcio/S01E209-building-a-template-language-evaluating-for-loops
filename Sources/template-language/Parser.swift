public indirect enum Expression<R>: Hashable where R: Hashable {
    case variable(name: String)
    case tag(name: String, attributes: [String: R] = [:], body: [R] = [])
    case `for`(variableName: String, collection: R, body: [R])
}

public struct AnnotatedExpression: Hashable {
    public var expression: Expression<AnnotatedExpression>
    public var range: Range<String.Index>
}

extension AnnotatedExpression {
    public var simple: SimpleExpression {
        SimpleExpression(expression: expression.map { $0.simple })
    }
}

public struct SimpleExpression: Hashable, CustomStringConvertible {
    public init(expression: Expression<SimpleExpression>) {
        self.expression = expression
    }
    
    public var expression: Expression<SimpleExpression>
    
    public var description: String {
        "\(expression)"
    }
}

extension SimpleExpression {
    public static func variable(name: String) -> Self {
        return SimpleExpression(expression: .variable(name: name))
    }

    public static func tag(name: String, attributes: [String: Self] = [:], body: [Self] = []) -> Self {
        return SimpleExpression(expression: .tag(name: name, attributes: attributes, body: body))
    }
    
    public static func `for`(variableName: String, collection: Self, body: [Self]) -> Self {
        return  SimpleExpression(expression: .for(variableName: variableName, collection: collection, body: body))
    }
}

extension Expression {
    func map<B>(_ transform: (R) -> B) -> Expression<B> {
        switch self {
        case .variable(name: let name): return .variable(name: name)
        case let .tag(name: name, attributes: attributes, body: body):
            return .tag(name: name, attributes: attributes.mapValues(transform), body: body.map(transform))
        case let .for(variableName: variableName, collection: collection, body: body):
            return .for(variableName: variableName, collection: transform(collection), body: body.map(transform))
        }
    }
}

public struct ParseError: Error, Hashable {
    public enum Reason: Hashable {
        case expected(String)
        case expectedClosingTag(String)
        case expectedIdentifier
        case expectedTagName
        case expectedAttributeName
        case unexpectedRemainder
    }
    public var reason: Reason
    public var offset: String.Index
}

extension String {
    public func parse() throws -> AnnotatedExpression {
        var remainder = self[...]
        return try remainder.parse()
    }
}

extension Substring {
    mutating func remove(prefix: String) -> Bool {
        guard hasPrefix(prefix) else { return false }
        removeFirst(prefix.count)
        return true
    }
    
    mutating func skipWS() {
        while first?.isWhitespace == true {
            removeFirst()
        }
    }

    func err(_ reason: ParseError.Reason) -> ParseError {
        ParseError(reason: reason, offset: startIndex)
    }
    
    mutating func parse() throws -> AnnotatedExpression {
        let expressionStart = startIndex
        if remove(prefix: "{") {
            skipWS()
            return try parseStatementOrExpression()
        } else if remove(prefix: "<") {
            let name = try parseTagName()
            var attributes: [String: AnnotatedExpression] = [:]
            while !isEmpty {
                skipWS()
                guard !remove(prefix: ">") else { break }
                guard first?.isAttributeName == true else { throw err(.expected("Attribute or >")) }
                let attributeName = try parseAttributeName()
                try remove(expecting: "=")
                try remove(expecting: "{")
                skipWS()
                let attributeValue = try parseExpression()
                skipWS()
                try remove(expecting: "}")
                attributes[attributeName] = attributeValue
            }
            let closingTag = "</\(name)>"
            var body: [AnnotatedExpression] = []
            while !remove(prefix: closingTag) {
                guard !isEmpty else {
                    throw err(.expectedClosingTag(name))
                }
                body.append(try parse())
            }
            let end = startIndex
            return AnnotatedExpression(expression: .tag(name: name, attributes: attributes, body: body), range: expressionStart..<end)
        } else {
            throw err(.unexpectedRemainder)
        }
    }
    
    mutating func parseStatementOrExpression() throws -> AnnotatedExpression {
        let startIdx = startIndex
        let result = try parseExpression()
        guard case .variable("for") = result.expression else {
            skipWS()
            try remove(expecting: "}")
            return result
        }
        skipWS()
        let variableName = try parseIdentifier()
        skipWS()
        try remove(expectingKeyword: "in")
        skipWS()
        let collection = try parseExpression()
        skipWS()
        try remove(expecting: "}")
        var body: [AnnotatedExpression] = []
        while !isEmpty {
            let part = try parse()
            if case .variable("end") = part.expression {
                break
            }
            body.append(part)
        }
        return AnnotatedExpression(expression: .for(variableName: variableName, collection: collection, body: body), range: startIdx..<startIndex)
    }
    
    mutating func parseExpression() throws -> AnnotatedExpression {
        let start = startIndex
        let name = try parseIdentifier()
        let end = startIndex
        return AnnotatedExpression(expression: .variable(name: name), range: start..<end)
    }
    
    mutating func remove(expecting: String) throws {
        guard remove(prefix: expecting) else {
            throw err(.expected(expecting))
        }
    }
    
    mutating func remove(expectingKeyword keyword: String) throws {
        let start = startIndex
        let name = try parseIdentifier()
        guard name == keyword else {
            throw ParseError(reason: .expected(keyword), offset: start)
        }
    }
    
    mutating func remove(while cond: (Element) -> Bool) -> SubSequence {
        var current = startIndex
        while current < endIndex, cond(self[current]) {
            formIndex(after: &current)
        }
        let result = self[startIndex..<current]
        self = self[current...]
        return result
    }

    mutating func parseTagName() throws -> String {
        let result = remove(while: { $0.isTagName })
        guard !result.isEmpty else { throw err(.expectedTagName) }
        return String(result)
    }
    
    mutating func parseAttributeName() throws -> String {
        let result = remove(while: { $0.isAttributeName })
        guard !result.isEmpty else { throw err(.expectedAttributeName) }
        return String(result)
    }

    mutating func parseIdentifier() throws -> String {
        let result = remove(while: { $0.isIdentifier })
        guard !result.isEmpty else { throw err(.expectedIdentifier) }
        return String(result)
    }
}

extension Character {
    var isIdentifier: Bool {
        isLetter
    }

    var isTagName: Bool {
        isLetter
    }
    
    var isAttributeName: Bool {
        isLetter
    }
}
