//
//  PowerControlProtocol.swift
//  Glance
//
//  Created by Gaty on 11/11/2026.
//

import Foundation
import Security

/// The helper accepts one boolean. It cannot execute a supplied command, choose a file, or
/// change another power preference. Both peers require the same signing team and exact identity.
@objc(GlancePowerControlProtocol)
public protocol PowerControlProtocol {
    func setLowPowerMode(_ enabled: Bool, reply: @escaping (Int32) -> Void)
}

public enum PowerControlIdentity {
    public static let app = "dev.vibe.Glance"
    public static let helper = "dev.vibe.Glance.PowerControl"
    public static let plist = helper + ".plist"

    public static func requirement(for identifier: String) -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var signedCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &signedCode) == errSecSuccess, let signedCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(signedCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
            let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
            !team.isEmpty, team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
            [app, helper].contains(identifier)
        else { return nil }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
}

public enum PowerControlCommand {
    public enum Source { case battery, adapter }

    public static func arguments(enabled: Bool, source: Source) -> [String] {
        [source == .battery ? "-b" : "-c", "lowpowermode", enabled ? "1" : "0"]
    }
}
