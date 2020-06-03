//
//  File.swift
//  
//
//  Created by Florian Kugler on 13-05-2020.
//

import Foundation

public enum TemplateValue: Hashable {
    case string(String)
    case rawHTML(String)
    case array([TemplateValue])
}

public struct EvaluationContext {
    public init(values: [String : TemplateValue] = [:]) {
        self.values = values
    }
    
    public var values: [String: TemplateValue]
}

public struct EvaluationError: Error, Hashable {
    public var range: Range<String.Index>
    public var reason: Reason
    
    public enum Reason: Hashable {
        case variableMissing(String)
        case expectedString
        case expectedHTMLConvertible
        case expectedArray
    }
}

extension TemplateValue {
    func toHtmlString(range: Range<String.Index>) throws -> String {
        switch self {
        case let .string(str): return str.escaped
        case let .rawHTML(html): return html
        case .array: throw EvaluationError(range: range, reason: .expectedHTMLConvertible)
        }

    }
}

extension EvaluationContext {
    public func evaluate(_ expr: AnnotatedExpression) throws -> TemplateValue {
        switch expr.expression {
        case .variable(name: let name):
            guard let value = values[name] else {
                throw EvaluationError(range: expr.range, reason: .variableMissing(name))
            }
            return value
        case .tag(let name, let attributes, let body):
            let bodyString = try body.map { expr in
                try self.evaluate(expr).toHtmlString(range: expr.range)
            }.joined()
            let attText = try attributes.isEmpty ? "" : " " + attributes.map { (key, value) in
                guard case let .string(valueText) = try evaluate(value) else {
                    throw EvaluationError(range: value.range, reason: .expectedString)
                }
                return "\(key)=\"\(valueText.attributeEscaped)\""
            }.joined(separator: " ")
            
            let result = "<\(name)\(attText)>\(bodyString)</\(name)>"
            return .rawHTML(result)
        case .for(variableName: let variableName, collection: let collection, body: let body):
            var result: String = ""
            guard case let .array(coll) = try evaluate(collection) else {
                throw EvaluationError(range: collection.range, reason: .expectedArray)
            }
            for el in coll {
                var childContext = self
                childContext.values[variableName] = el
                for b in body {
                    result += try childContext.evaluate(b).toHtmlString(range: b.range)
                }
            }
            return .rawHTML(result)
        }
    }
}

extension String {
    // todo verify that this is secure
    var escaped: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
    
    var attributeEscaped: String {
        replacingOccurrences(of: "\"", with: "&quot;")
    }
}
