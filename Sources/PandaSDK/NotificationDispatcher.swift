//
//  NotificationDispatcher.swift
//  PandaSDK
//
//  Created by Kuts on 21.07.2020.
//

import Foundation

class NotificationDispatcher: NSObject {
    
    var onApplicationDidBecomeActive: (() -> Void)? {
        didSet {
            callApplicationDidBecomeActive()
        }
    }
    private var shouldCallApplicationDidBecomeActive: Bool = false
    
    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    @objc func applicationDidBecomeActive(_ notification: Notification) {
        shouldCallApplicationDidBecomeActive = true
        callApplicationDidBecomeActive()
    }
    
    func callApplicationDidBecomeActive() {
        guard let handler = onApplicationDidBecomeActive, shouldCallApplicationDidBecomeActive else { return }
        shouldCallApplicationDidBecomeActive = false
        handler()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
}
