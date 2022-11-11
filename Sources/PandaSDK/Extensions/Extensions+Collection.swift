//
//  File.swift
//  
//
//  Created by Nick Nick  on 11/10/22.
//

import Foundation

extension Collection where Iterator.Element == [String: Any] {
    func toJSONString(options: JSONSerialization.WritingOptions = .fragmentsAllowed) -> String {
    if let array = self as? [[String: Any]],
       let data = try? JSONSerialization.data(withJSONObject: array, options: options),
       let str = String(data: data, encoding: String.Encoding.utf8) {
      return str
    }
    return "[]"
  }
}
