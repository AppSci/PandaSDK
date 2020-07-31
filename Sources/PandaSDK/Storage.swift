//
//  Storage.swift
//  Panda
//
//  Created by Kuts on 02.07.2020.
//  Copyright © 2020 Kuts. All rights reserved.
//

import Foundation

protocol StorageProtocol {
    associatedtype Element
    var store: (_ data: Element) -> Void { get }
    var fetch: () -> Element? { get }
    var clear: () -> Void { get }
}

struct Storage<Element>: StorageProtocol {
    let store: (Element) -> Void
    let fetch: () -> Element?
    let clear: () -> Void
}


extension StorageProtocol {

    func map<T>(
        store map: @escaping (T) throws -> Element,
        fetch pullback: @escaping (Element) throws -> T
    ) -> Storage<T> {
        return Storage<T>(
            store: { [store] value in
                do {
                    store(try map(value))
                } catch {
                    print("failed to map while storing \(value)")
                }
            },
            fetch: { [fetch] in
                do {
                    return try fetch().map(pullback)
                } catch {
                    print("failed to map while reading \(T.self)")
                    return nil
                }
            },
            clear: clear
        )
    }
}

extension Storage {

    static func userDefaults(_ userDefaults: UserDefaults, key: String) -> Storage {
        return Storage(
            store: { value in
                userDefaults.set(value, forKey: key)
            },
            fetch: {
                userDefaults.object(forKey: key) as? Element
            },
            clear: {
                userDefaults.removeObject(forKey: key)
            }
        )
    }
}

extension Storage where Element == Data {
    static func keychain(service: String, key: String) -> Storage {
        return Storage (store: { KeyChainAccess.save(service: service, key: key, data: $0)},
                        fetch: { KeyChainAccess.load(service: service, key: key) },
                        clear: { KeyChainAccess.clear(service: service, key: key) })
    }

}

extension Storage where Element: Codable {

    static func codableUserDefaults(
        userDefaults: UserDefaults = .standard,
        key: String,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) -> Storage {
        return Storage<Data>.userDefaults(userDefaults, key: key).map(
            store: encoder.encode,
            fetch: { try decoder.decode(Element.self, from: $0) }
        )
    }

    static func codableKeychain(
        service: String,
        key: String,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) -> Storage {
        return Storage<Data>.keychain(service: service, key: key).map(
            store: encoder.encode,
            fetch: { try decoder.decode(Element.self, from: $0) }
        )
    }
}

class CodableStorageFactory<T: Codable> {

    static func userDefaults() -> Storage<T> {
        return Storage.codableUserDefaults(
            userDefaults: UserDefaults(suiteName: "group.com.panda")!,
            key: String(describing: T.self)
        )
    }
    
    static func keychain() -> Storage<T> {
        return Storage.codableKeychain(
            service: "group.com.panda",
            key: String(describing: T.self)
        )
    }

}
