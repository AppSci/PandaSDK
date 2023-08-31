//
//  ScreenData.swift
//  
//
//  Created by Denys Danyliuk on 12.09.2023.
//

import Foundation

struct ScreenData: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case html = "screen_html"
    }
    
    let id: ID<ScreenData>
    let name: String
    let html: String
    
    init(
        id: ID<ScreenData>,
        name: String,
        html: String
    ) {
        self.id = id
        self.name = name
        self.html = html
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = .init(string: try container.decode(String.self, forKey: .id))
        self.name = try container.decode(String.self, forKey: .name)
        self.html = try container.decode(String.self, forKey: .html)
    }
}

extension ScreenData {
    static let unknown = ScreenData(id: .unknown, name: "unknown", html: "unknown")
    static var `default`: ScreenData? = {
        guard let fileURL = Bundle.main.url(forResource: "PandaSDK-Default", withExtension: "html"),
              let fileContents = try? String(contentsOf: fileURL) else {
                  pandaLog("Cannot find default screen html")
                  return nil
        }
        return .init(id: .default, name: "default", html: fileContents)
    }()
}

extension ID where T == ScreenData {
    static let unknown: Self = .init(string: "unknown")
    static let `default`: Self = .init(string: "default")
}
