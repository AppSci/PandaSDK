//
//  WebViewController.swift
//  Panda
//
//  Created by Kuts on 01.07.2020.
//  Copyright © 2020 Kuts. All rights reserved.
//

import Foundation
import UIKit
import Foundation
import WebKit
import StoreKit

final class WebViewController: UIViewController, WKScriptMessageHandler {
    
    var viewModel: WebViewModel! {
        didSet {
            bindVM(viewModel)
        }
    }
    var onPurchaseCmpld: (() -> Void)?
    var isAutoDismissable: Bool = true
    
    private lazy var wv: WKWebView = {
        let config = getWKWebViewConfiguration()
        let wv = WKWebView(frame: view.bounds, configuration: config)
        if viewModel.screenData.id.string == "69c444b9-42c5-473a-a22a-873879b7f3ae" || viewModel.screenData.id.string == "89a4b8c2-cb7b-45a5-a8df-f5a8ffd32618" {
            wv.addObserver(self, forKeyPath: #keyPath(WKWebView.isLoading), options: .new, context: nil)
        } else {
            wv.navigationDelegate = self
        }
        view.addSubview(wv)
        wv.allowsLinkPreview = false
        wv.allowsBackForwardNavigationGestures = false
        wv.scrollView.layer.masksToBounds = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.isMultipleTouchEnabled = false
        wv.scrollView.isScrollEnabled = true
        wv.scrollView.bounces = true
        wv.scrollView.delegate = self
        wv.isOpaque = false
        wv.scrollView.isOpaque = false
        wv.backgroundColor = UIColor.clear
        wv.scrollView.backgroundColor = UIColor.clear
        wv.scrollView.alwaysBounceVertical = false
        wv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: view.topAnchor),
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        return wv
    }()
    
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let loading = UIActivityIndicatorView(style: .medium)
        loading.hidesWhenStopped = true
        view.addSubview(loading)
        loading.translatesAutoresizingMaskIntoConstraints = false
        loading.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        loading.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        return loading
    }()
    
    internal func loadPage(html: String? = nil) {
        /// if after 15 seconds webview not appeared, then fail
        pandaLog("start loading html \(Date().timeIntervalSince1970) \(Date())")
        let timeout = viewModel.payload?.pageLoadingTimeout ?? 3.0

        perform(#selector(failedByTimeOut), with: nil, afterDelay: timeout)

        loadingIndicator.startAnimating()
        _ = view // trigger viewdidload
        wv.alpha = 0
        
        if let html = html {
            load(
                html: html,
                baseURL: html.contains(Constants.oldDismiss) // We are still using old panda screens that do not yet use JS dismiss functions, so we need to check whether it is the old screen or the new
                ? nil
                : URL(fileURLWithPath: Bundle.main.bundlePath)
            )
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "loading", !wv.isLoading {
            handleScreenDidLoad()
            didFinishLoading(nil)
        }
    }
    
    private func load(html: String, baseURL: URL?) {
        wv.loadHTMLString(html, baseURL: baseURL)
    }
    
    deinit {
        onFinishLoad()
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(failedByTimeOut), object: nil)
    }
    
    private func getWKWebViewConfiguration() -> WKWebViewConfiguration {
        let userController = WKUserContentController()
        
        PandaJSMessagesNames.allCases.forEach {
            userController.add(ScriptMessageHandlerWeakProxy(handler: self),
                               name: $0.rawValue)
        }
        
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .audio
        configuration.userContentController = userController
        return configuration
    }
    
    func userContentController(
       _ userContentController: WKUserContentController,
       didReceive message: WKScriptMessage
    ) {
        pandaLog("JavaScript messageHandler: `\(message.name)` is sending a message:")
        
        if message.name == PandaJSMessagesNames.onPurchase.rawValue {
            if let data = message.body as? [String: String] {

                if let pandaID = data["pandaID"] {
                    viewModel?.onApplePayPurchase(
                        pandaID,
                        "WKScriptMessage",
                        viewModel?.screenData.id.string ?? "",
                        viewModel?.screenData.name ?? "",
                        self
                    )
                } else if let productID = data["productID"] {
                    onStartLoad()
                    viewModel?.onPurchase(
                        productID,
                        "WKScriptMessage",
                        self,
                        viewModel?.screenData.id.string ?? "",
                        viewModel?.screenData.name ?? "",
                        data["course"]
                    )

                    if let urlString = data["url"],
                       let url = URL(string: urlString),
                       let type = data["type"],
                       type == "external" {
                        onPurchaseCmpld = {
                            UIApplication.shared.open(url)
                        }
                    }

                    if let type = data["type"],
                       type == "moveNext" {
                        isAutoDismissable = false
                        onPurchaseCmpld = { [weak self] in
                            self?.moveNext()
                        }
                    }
                }
            }
        }

        if message.name == PandaJSMessagesNames.logHandler.rawValue {
            pandaLog("LOG: \(message.body)")
        }
                
        if message.name == PandaJSMessagesNames.onCustomEventSent.rawValue,
           let data = message.body as? [String: String] {
            handleAndSendCustomEventIfPossible(with: data)
        }
        
        if message.name == PandaJSMessagesNames.onTutorsHowOfferWorks.rawValue,
           let data = message.body as? [String: String],
           let destination = data["destination"] {
            viewModel?.onTutorsHowOfferWorks?(
                viewModel?.screenData.id.string ?? "",
                destination
            )
        }
        
        if message.name == PandaJSMessagesNames.onRedirect.rawValue,
           let data = message.body as? [String: String],
           let urlString = data["url"],
           let type = data["type"],
           let url = URL(string: urlString),
           type == "external" {
            if viewModel?.screenData.id.string == "5077a1da-092c-4ab8-a41f-0a3966a4b326" {
                viewModel?.onSupportUkraineAnyButtonTap?()
            }
            if viewModel?.screenData.id.string == "b7627ad6-b5b2-4255-afe6-71842b1f46ec" {
                if let destination = data["destination"]  {
                    viewModel?.onDontHaveApplePay?(
                        viewModel?.screenData.id.string ?? "",
                        destination
                    )
                }
            }
            if viewModel?.screenData.id.string == "b0bff24a-a023-4a02-95a7-20b6af6e59cc" {
                UIApplication.shared.open(url)
                viewModel?.onFreeForUkraineButtonTap?(true)
                onFinishLoad()
                return
            }

            UIApplication.shared.open(url)
            onFinishLoad()
            isAutoDismissable = true
            viewModel?.dismiss?(true, self, nil, nil)
        }
        
        if message.name == PandaJSMessagesNames.loadPricing.rawValue,
           let data = message.body as? [[String : String]] {
            let productIds = data.map { value in
                return value["productId"] ?? ""
            }
            viewModel?.onPricesLoaded?(
                productIds,
                self
            )
        }

        if message.name == PandaJSMessagesNames.onRestore.rawValue {
            viewModel?.onRestorePurchase?(
                self,
                viewModel?.screenData.id.string ?? "",
                viewModel?.screenData.name ?? ""
            )
        }

        if message.name == PandaJSMessagesNames.onDismiss.rawValue {
            onFinishLoad()
            viewModel?.dismiss?(
                true,
                self,
                viewModel?.screenData.id.string ?? "",
                viewModel?.screenData.name ?? ""
            )
        }

        if message.name == PandaJSMessagesNames.onBillingIssue.rawValue {
            viewModel?.onBillingIssue?(self)
        }

        if message.name == PandaJSMessagesNames.onTerms.rawValue {
            viewModel?.onTerms?()
        }

        if message.name == PandaJSMessagesNames.onPolicy.rawValue {
            viewModel?.onPolicy?()
        }

        if message.name == PandaJSMessagesNames.onSubscriptionTerms.rawValue {
            viewModel?.onSubscriptionTerms?()
        }
    }

    private func handleAndSendCustomEventIfPossible(with data: [String: String]) {
        guard let name = data["name"] else {
            pandaLog("No name for custom event!")
            return
        }
        
        let parameters = data.filter { $0.key != "name" }
        viewModel?.onCustomEvent?(name, parameters)
    }
    
    private func setPayload() {
        guard let payload = viewModel.payload?.data else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        guard let json = String(data: data, encoding: .utf8) else { return }
        
        let js = """
                    setPayload(\(json));
                 """
        wv.evaluateJavaScript(js) { (result, error) in
            if let e = error {
                pandaLog("error: \(e)")
            }
            if let res = result {
                pandaLog("payload \(res)")
            }
        }
    }

    private func moveNext() {
        let js = """
                    moveNext();
                 """
        wv.evaluateJavaScript(js) { [weak self] (result, error) in
            guard let self = self else {
                return
            }
            if let e = error {
                pandaLog("error: \(e)")
            } else if self.viewModel?.screenData.id.string == "89a4b8c2-cb7b-45a5-a8df-f5a8ffd32618"  {
                self.viewModel?.onDidFinishLoading?(self.viewModel?.screenData.id.string, "Tutors-Phone-Collection-v2-Schedule", (self.viewModel?.payload?.data?["course"] as? String))

            }
            if let res = result {
                pandaLog("res \(res)")
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        viewModel?.onViewWillAppear?(
            viewModel?.screenData.id.string ?? "",
            viewModel?.screenData.name ?? ""
        )
    }
    
    override func viewDidAppear(_ animated: Bool) {
        viewModel?.onViewDidAppear?(
            viewModel?.screenData.id.string ?? "",
            viewModel?.screenData.name ?? "",
            (viewModel?.payload?.data?["course"] as? String)
        )
    }
    
    func didFinishLoading(_ url: URL?) {
        guard let url = url else {
            viewModel?.onDidFinishLoading?(viewModel?.screenData.id.string, viewModel?.screenData.name, (viewModel?.payload?.data?["course"] as? String))
            return
        }
        let urlComps = URLComponents(url: url, resolvingAgainstBaseURL: true)
        let screenID = urlComps?.queryItems?.first(where: { $0.name == "screen_id" })?.value ?? viewModel?.screenData.id.string
        let screenName = urlComps?.queryItems?.first(where: { $0.name == "screen_name" })?.value ?? viewModel?.screenData.name
        viewModel?.onDidFinishLoading?(screenID, screenName, (viewModel?.payload?.data?["course"] as? String))
    }
    
    func handleScreenDidLoad() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(failedByTimeOut), object: nil)
        
        setPayload()
        wv.alpha = 1
        loadingIndicator.stopAnimating()
        
        pandaLog("html did load \(Date().timeIntervalSince1970) \(Date())")
    }
    
    func hideTrial() {
        wv.evaluateJavaScript(Constants.hideTrialJSFunctionName) { [weak self] _, error in
            if let error = error {
                pandaLog(error.localizedDescription)
            }
            self?.wv.alpha = 1
            self?.loadingIndicator.stopAnimating()
        }
    }
    
    @objc private func failedByTimeOut() {
        pandaLog("🚨 Timeout error \(Date().timeIntervalSince1970) \(Date())")
        onFinishLoad()
        loadingIndicator.stopAnimating()
        viewModel.webViewControllerDidFailLoadingHTML(self)
    }
    
    internal func onStartLoad() {
        viewModel.onStartLoadingIndicator?()
    }

    internal func onFinishLoad() {
        viewModel.onFinishLoadingIndicator?()
    }
    
    internal func tryAutoDismiss() {
        guard isAutoDismissable else { return }
        dismiss(animated: true, completion: nil)
    }
    
    internal func onPurchaseCompleted() {
        onPurchaseCmpld?()
        onPurchaseCmpld = nil
    }
    
    internal func showInternetConnectionAlert() {
        let alert = UIAlertController(title: "Connection error",
                                      message: "Please, check you internet connection and try again",
                                      preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Dismiss", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    private func bindVM(_ viewModel: WebViewModel) {
        viewModel.onScreenDataUpdate = { [weak self] in
            self?.loadPage(html: $0.html)
        }
    }
}

extension WebViewController: UIScrollViewDelegate {
   func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
      scrollView.pinchGestureRecognizer?.isEnabled = false
   }
}

extension WebViewController: WKNavigationDelegate {
    @discardableResult
    private func handleAction(url: URL) -> Bool {
        guard let urlComps = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return true }
        guard let action = urlComps.queryItems?.first(where: { $0.name == "type" })?.value else { return true }

        let screenID = urlComps.queryItems?.first(where: { $0.name == "screen_id" })?.value ?? viewModel?.screenData.id.string ?? ""
        let screenName = urlComps.queryItems?.first(where: { $0.name == "screen_name" })?.value ?? viewModel?.screenData.name ?? ""

        switch action {
        case "purchase":
            let productID = urlComps.queryItems?.first(where: { $0.name == "product_id" })?.value
            let course = urlComps.queryItems?.first(where: { $0.name == "course" })?.value

            if let pandaID = urlComps.queryItems?.first(where: { $0.name == "pandaID"})?.value {
                viewModel?.onApplePayPurchase(
                    pandaID,
                    url.lastPathComponent,
                    viewModel?.screenData.id.string ?? "",
                    viewModel?.screenData.name ?? "",
                    self
                )
            } else {
                onStartLoad()
                viewModel?.onPurchase(
                    productID,
                    url.lastPathComponent,
                    self,
                    screenID,
                    screenName,
                    course
                )
            }

            return false
        case "restore":
            viewModel?.onRestorePurchase?(
                self,
                screenID,
                screenName
            )
            return false
        case "dismiss":
            onFinishLoad()
            viewModel?.dismiss?(
                true,
                self,
                screenID,
                screenName
            )
            return false
        case "billing_issue":
            viewModel?.onBillingIssue?(self)
            return false
        case "terms":
            viewModel?.onTerms?()
            return false
        case "policy":
            viewModel?.onPolicy?()
            return false
        case "subscription_terms":
            viewModel?.onSubscriptionTerms?()
            return false
        default:
            break
        }
        return true
    }
    
    private func handleSurvey(url: URL) {
        guard let urlComps = URLComponents(url: url, resolvingAgainstBaseURL: true) else {return}
        guard let action = urlComps.queryItems?.first(where: { $0.name == "type" })?.value else {return}
        
        let screenID = urlComps.queryItems?.first(where: { $0.name == "screen_id" })?.value ?? viewModel?.screenData.id.string ?? ""
        let screenName = urlComps.queryItems?.first(where: { $0.name == "screen_name" })?.value ?? viewModel?.screenData.name ?? ""
        
        switch action {
        case "dismiss":
            onFinishLoad()
            viewModel?.dismiss?(
                true,
                self,
                screenID,
                screenName
            )
        default:
            break
        }
    }
    
    func handleNavigationAction(navigationAction: WKNavigationAction) -> Bool {
        
        if let url = navigationAction.request.url {
            let lastComponent = url.lastPathComponent

            let urlComps = URLComponents(url: url, resolvingAgainstBaseURL: true)
            let screenID = urlComps?.queryItems?.first(where: { $0.name == "screen_id" })?.value ?? viewModel?.screenData.id.string ?? ""
            let screenName = urlComps?.queryItems?.first(where: { $0.name == "screen_name" })?.value ?? viewModel?.screenData.name ?? ""
            
            switch lastComponent {
            case "subscription",
                 "billing_issue":
                handleAction(url: url)
                return false
            case "feedback":
                handleSurvey(url: url)
                return true
            case "subscriptions":
                handleSurvey(url: url)
                return true
            case "upsale":
                return handleAction(url: url)
            case "dismiss":
                onFinishLoad()
                viewModel?.dismiss?(
                    true,
                    self,
                    screenID,
                    screenName
                )
                return false
            default:
                break
            }
        }

        if let url = navigationAction.request.url,
            let urlComps = URLComponents(url: url, resolvingAgainstBaseURL: true),
            let destination = urlComps.queryItems?.first(where: { $0.name == "destination" })?.value,
            destination == "feedback" {
            handleSurvey(url: url)
            return true
        }
        
        return true
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if handleNavigationAction(navigationAction: navigationAction) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pandaLog("WebViewController // didFinish loading: \(String(describing: webView.url))")
        didFinishLoading(webView.url)
        handleScreenDidLoad()
        fillProductInfoWithJS()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        pandaLog("WebViewController // Did fail navigation: \(String(describing: webView.url?.absoluteString)), error: \(error)")
    }
}

class ScriptMessageHandlerWeakProxy: NSObject, WKScriptMessageHandler {
    weak var handler: WKScriptMessageHandler?
    init(handler: WKScriptMessageHandler) {
        self.handler = handler
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        handler?.userContentController(userContentController, didReceive: message)
    }
}

extension WebViewController {

    private func fillProductInfoWithJS() {
        if let product = viewModel.product {
            replace(string: "{{product_title}}", with: product.displayName)
            replace(string: "{{product_id}}", with: product.id)
            
            let introInfo = {
                if let offer = product.subscription?.introductoryOffer {
                    let isTrial = offer.paymentMode == .freeTrial
                    return "Try \(offer.period.unitDescription) for \(isTrial ? "Free" : "\(offer.displayPrice)")."
                } else {
                    return ""
                }
            }()
            replace(string: "{{introductionary_information}}", with: introInfo)
            
            let pricingInfo = {
                if let subscription = product.subscription {
                    let subscriptionPeriod = subscription.subscriptionPeriod
                    
                    let periodNumber = subscriptionPeriod.value
                    if periodNumber == 0 && subscriptionPeriod.unit == .day {
                        /// set string for Lifetime
                        return "for \(product.displayPrice) lifetime"
                    } else {
                        /// set thenString for subscription
                        return "then \(product.displayPrice) per \(subscriptionPeriod.unitDescription)"
                    }
                    
                } else {
                    /// set string for Lifetime
                    return "for \(product.displayPrice) lifetime"
                }
            }()
            replace(string: "{{product_pricing_terms}}", with: pricingInfo)
        }
    }
    
    private func replace(string: String, with info: String) {
        let js = """
                        document.body.innerHTML = document.body.innerHTML.replace(/\(string)/g, "\(info)");
                """
        wv.evaluateJavaScript(js) { (result, error) in
            if let _ = result {
                // print("replace(string: '\(string)', with info: '\(info)') \(res)")
            }
        }
    }
    
    func sendLocalizedPrices(products: [Product]) {
        let localizedPricesToSend = products.map { product -> [String : Any] in
            var localizedPriceInfo = [String: Any]()
            var value = product.price
            var roundedValue = Decimal()
            NSDecimalRound(&roundedValue, &value, 2, .bankers)
            let micros = roundedValue * Decimal(1_000_000)
            localizedPriceInfo["productId"] = product.id
            localizedPriceInfo["priceAmountMicros"] =  micros
            localizedPriceInfo["priceCurrencyCode"] = product.priceFormatStyle.currencyCode
            return localizedPriceInfo
        }
        
        let localizedPricesToSendJSON = localizedPricesToSend.toJSONString()
        let jsFunction = "pricingLoaded(\(localizedPricesToSendJSON))"
        
        DispatchQueue.main.async {
            self.wv.evaluateJavaScript(jsFunction) { (result, error) in
                if let error = error {
                    pandaLog("\(error)")
                }
                if let result = result {
                    pandaLog("\(result)")
                }
            }
        }
    }
}

extension WebViewController {
    private enum PandaJSMessagesNames: String, CaseIterable {
        case onPurchase
        case logHandler
        case onLessonFeedbackSent
        case loadPricing
        case onCustomEventSent
        case onRedirect
        case onRestore
        case onTutorsHowOfferWorks
        case onDismiss
        case onBillingIssue
        case onTerms
        case onPolicy
        case onSubscriptionTerms
    }

    private enum Constants {
        static let hideTrialJSFunctionName = "removeTrialUi()"
        static let oldDismiss = "dismiss?type=dismiss"
    }
}
