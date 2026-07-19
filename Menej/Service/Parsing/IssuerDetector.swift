//
//  IssuerDetector.swift
//  Menej
//
//  Issuer detection: fingerprint match against headers/logo text — see PRD §6 F1.
//

import Foundation

enum IssuerDetectionError: Error {
    case noMatch
}

protocol IssuerDetecting {
    func detectIssuer(fromText text: String, using rules: [IssuerRule]) throws -> Issuer
}

struct IssuerDetector: IssuerDetecting {
    func detectIssuer(fromText text: String, using rules: [IssuerRule]) throws -> Issuer {
        for rule in rules {
            let allPresent = rule.fingerprint.textContains.allSatisfy { needle in
                text.range(of: needle, options: .caseInsensitive) != nil
            }
            if allPresent, let issuer = Issuer(rawValue: rule.issuer) {
                return issuer
            }
        }
        throw IssuerDetectionError.noMatch
    }
}
