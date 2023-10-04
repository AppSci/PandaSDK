//
//  WebViewModel.swift
//  Panda
//
//  Created by Kuts on 01.07.2020.
//  Copyright © 2020 Kuts. All rights reserved.
//

import Foundation
import StoreKit

protocol WebViewModelProtocol {
    var onPurchase: ((_ product: String?, _ source: String, _ viewController: WebViewController, _ screenId: String, _ screenName: String, _ course: String?) -> Void)!  { get set }
    var onApplePayPurchase: ((_ pandaID: String?, _ source: String, _ screenId: String, _ screenName: String, _ viewController: WebViewController) -> Void)! { get set }
    var onViewWillAppear: ((_ screenId: String?, _ screenName: String?) -> Void)? { get set }
    var onViewDidAppear: ((_ screenId: String?, _ screenName: String?, _ course: String?) -> Void)? { get set }
    var onDidFinishLoading: ((_ screenId: String?, _ screenName: String?, _ course: String?) -> Void)? { get set }
    var onBillingIssue: ((_ viewController: WebViewController) -> Void)? { get set }
    var onRestorePurchase: ((_ viewController: WebViewController, _ screenId: String?, _ screenName: String?) -> Void)? { get set }
    var onTerms: (() -> Void)? { get set }
    var onDontHaveApplePay: ((_ screenID: String?, _ destination: String?) -> Void)? { get set }
    var onTutorsHowOfferWorks: ((_ screenID: String?, _ destination: String?) -> Void)? { get set }
    var onPricesLoaded: ((_ productIds: [String], _ viewController: WebViewController) -> Void)? { get set }
    var onPolicy: (() -> Void)? { get set }
    var onSubscriptionTerms: (() -> Void)? { get set }
    var onCustomEvent: ((_ name: String, _ parameters: [String: String]) -> Void)? { get set }
    var dismiss: ((_ success: Bool, _ viewController: WebViewController, _ screenId: String?, _ screenName: String?) -> Void)? { get set }
    var onScreenDataUpdate: ((ScreenData) -> Void)? { get set }

    var onSupportUkraineAnyButtonTap: (() -> Void)? { get set }
    
    var onStartLoadingIndicator: (() -> Void)? { get set }
    var onFinishLoadingIndicator: (() -> Void)? { get set }

    func webViewControllerDidFailLoadingHTML(_ webViewController: WebViewController)
}

final class WebViewModel: WebViewModelProtocol {

    // MARK: - Properties
    @objc var onPurchase: ((_ product: String?, _ source: String, _ viewController: WebViewController, _ screenId: String, _ screenName: String, _ course: String?) -> Void)!
    @objc var onApplePayPurchase: ((String?, String, String, String, WebViewController) -> Void)!
    var onViewWillAppear: ((_ screenId: String?, _ screenName: String?) -> Void)?
    var onViewDidAppear: ((_ screenId: String?, _ screenName: String?, _ course: String?) -> Void)?
    var onDidFinishLoading: ((_ screenId: String?, _ screenName: String?, _ course: String?) -> Void)?
    var onBillingIssue: ((_ viewController: WebViewController) -> Void)?
    var onRestorePurchase: ((_ viewController: WebViewController, _ screenId: String?, _ screenName: String?) -> Void)?
    var onTerms: (() -> Void)?
    var onDontHaveApplePay: ((_ screenID: String?, _ destination: String?) -> Void)?
    var onTutorsHowOfferWorks: ((_ screenID: String?, _ destination: String?) -> Void)?
    var onPricesLoaded: ((_ productIds: [String], _ viewController: WebViewController) -> Void)?
    var onPolicy: (() -> Void)?
    var onSubscriptionTerms: (() -> Void)?
    var onCustomEvent: ((_ name: String, _ parameters: [String: String]) -> Void)?
    var dismiss: ((_ success: Bool, _ viewController: WebViewController, _ screenId: String?, _ screenName: String?) -> Void)?
    var onScreenDataUpdate: ((ScreenData) -> Void)?

    var onSupportUkraineAnyButtonTap: (() -> Void)?
    
    var onStartLoadingIndicator: (() -> Void)?
    var onFinishLoadingIndicator: (() -> Void)?
    
    private(set) var screenData: ScreenData {
        didSet {
            onScreenDataUpdate?(screenData)
        }
    }
    var product: Product?
    let payload: PandaPayload?

    // MARK: - Init
    init(screenData: ScreenData, payload: PandaPayload? = nil) {
        self.screenData = screenData
        self.payload = payload
        setupObserver()
        setupApplePayObserver()
    }
    
    // MARK: - Public
    func webViewControllerDidFailLoadingHTML(_ webViewController: WebViewController) {
        guard (screenData.id != .default && screenData.id != .unknown),
        let defaultScreenData = ScreenData.default else {
            dismiss?(false, webViewController, nil, nil)
            return
        }
        reloadWithDefaultScreenData(defaultScreenData)
    }
}

// MARK: - Private
extension WebViewModel {
    private func setupObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(getter: onPurchase),
            name: NSNotification.Name(rawValue: "SubscriptionBooster.onPurchase"),
            object: nil
        )
    }
    
    private func setupApplePayObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(getter: onApplePayPurchase),
            name: NSNotification.Name(rawValue: "SubscriptionBooster.onPurchase"),
            object: nil
        )
    }
    
    private func reloadWithDefaultScreenData(_ screenData: ScreenData) {
        self.screenData = screenData
    }
}
