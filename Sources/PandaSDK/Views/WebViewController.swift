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
import NVActivityIndicatorView

class WebViewController: UIViewController, WKScriptMessageHandler {
    
    var viewModel: WebViewModel!
    var onFailedAfterTimeout: (() -> Void)?
    
    var url: URLComponents?
    
    private lazy var webview: WKWebView = {
        let webview = WebViewController.createWebView(bounds: view.bounds,
                                                      config: getWKWebViewConfiguration())
        webview.navigationDelegate = self
        webview.scrollView.delegate = self
        view.addSubview(webview)
        NSLayoutConstraint.activate([
            webview.topAnchor.constraint(equalTo: view.topAnchor),
            webview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        return webview
    }()
    
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let loading = UIActivityIndicatorView(style: .gray)
        loading.hidesWhenStopped = true
        view.addSubview(loading)
        loading.translatesAutoresizingMaskIntoConstraints = false
        loading.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        loading.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        return loading
    }()
    
    internal func loadPage(html: String? = nil) {
        perform(#selector(failedAfterTimeout), with: nil, afterDelay: 3.0)
        loadingIndicator.startAnimating()
        _ = view // calles viewDidLoad
        webview.alpha = 0
        
        print("Panda // start loading html \(Date().timeIntervalSince1970) \(Date())")
        
        if let html = html {
            load(html: html, baseURL: url?.url)
            return
        }
        guard let url = url?.url else { return }
        
        if url.isFileURL {
            load(local: url)
        } else {
            load(url: url)
        }
        
        trackLocationChanges()
    }
    
    private func load(url: URL) {
        webview.load(URLRequest(url: url))
    }
    
    private func load(html: String, baseURL: URL?) {
        let html = replaceProductInfo(html: html)
        webview.loadHTMLString(html, baseURL: baseURL)
    }
    
    private func load(local url: URL) {
        webview.configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        webview.loadFileURL(url, allowingReadAccessTo: url)
    }
    
    deinit {
        onFinishLoad()
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(failedAfterTimeout), object: nil)
    }
    
    private func getWKWebViewConfiguration() -> WKWebViewConfiguration {
        let userController = WKUserContentController()
        userController.add(ScriptMessageHandlerWeakProxy(handler: self), name: "locationChanges")
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
        print("JavaScript is sending a message \(message)")
        
        if message.name == "weekly_offer" {
            print("JavaScript is sending a message \(message.body)")
            viewModel?.onPurchase(message.name, "js-code", self)
        }
        if message.name == "locationChanges" {
            print("JavaScript is sending a message \(message.body)")
            
        }
        if let data = message.body as? [String: String],
            let name = data["name"], let email = data["email"] {
            showUser(email: email, name: name)
        }
    }
    
    private func showUser(email: String, name: String) {
        let userDescription = "\(email) \(name)"
        let alertController = UIAlertController(
           title: "User",
           message: userDescription,
           preferredStyle: .alert
        )
        alertController.addAction(
            UIAlertAction(title: "OK", style: .default)
        )
        present(alertController, animated: true)
    }
    
    private func trackLocationChanges() {
        let js = """
                        function listener() {
                            window.webkit.messageHandlers.locationChanges.postMessage(window.location)
                        }
                        window.addEventListener('popstate', listener);
                """
        webview.evaluateJavaScript(js) { (result, error) in
            if let res = result {
                print("location changed to \(res)")
            }
        }
    }
    
    func webviewDidFinishNavigation() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(failedAfterTimeout), object: nil)
        webview.alpha = 1
        loadingIndicator.stopAnimating()
        print("Panda // html did load \(Date().timeIntervalSince1970) \(Date())")
    }
    
    @objc private func failedAfterTimeout() {
        print("🚨 Timeout error")
        onFinishLoad()
        loadingIndicator.stopAnimating()
        guard let timeoutCallback = onFailedAfterTimeout else {
            viewModel?.dismiss?(false, self)
            return
        }
        timeoutCallback()
    }
    
    internal func onStartLoad() {
        let activityData = ActivityData()
        NVActivityIndicatorPresenter.sharedInstance.startAnimating(activityData, nil)
    }

    internal func onFinishLoad() {
        NVActivityIndicatorPresenter.sharedInstance.stopAnimating(nil)
    }
    
    internal func showInternetConnectionAlert() {
        let alert = UIAlertController(title: "Connection error", message: "Please, check you internet connection and try again", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Dismiss", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    static func createWebView(bounds: CGRect, config: WKWebViewConfiguration) -> WKWebView {
        let webview = WKWebView(frame: bounds, configuration: config)
        webview.translatesAutoresizingMaskIntoConstraints = false
        webview.allowsLinkPreview = false
        webview.allowsBackForwardNavigationGestures = false
        webview.isOpaque = false
        webview.backgroundColor = UIColor.clear
        webview.scrollView.layer.masksToBounds = false
        webview.scrollView.contentInsetAdjustmentBehavior = .never
        webview.scrollView.isMultipleTouchEnabled = false
        webview.scrollView.isScrollEnabled = true
        webview.scrollView.bounces = true
        webview.scrollView.alwaysBounceVertical = false
        webview.scrollView.isOpaque = false
        webview.scrollView.backgroundColor = UIColor.clear
        return webview
    }
    
}

extension WebViewController: UIScrollViewDelegate {
   func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
      scrollView.pinchGestureRecognizer?.isEnabled = false
   }
}

extension WebViewController: WKNavigationDelegate {
    
    @discardableResult
    private func processSalesAction(from url: URL) -> Bool {
        guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return true }
        guard let action = urlComponents.queryItems?.first(where: { $0.name == "type" })?.value else { return true }
        
        switch action {
        case "purchase":
            onStartLoad()
            let productID = urlComponents.queryItems?.first(where: { $0.name == "product_id" })?.value
            viewModel?.onPurchase(productID, url.lastPathComponent, self)
            return false
        case "restore":
            onStartLoad()
            viewModel?.onRestorePurchase?(self)
            return false
        case "dismiss":
            onFinishLoad()
            viewModel?.dismiss?(true, self)
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
        default:
            break
        }
        return true
    }
    
    private func processSurveyAction(from url: URL) {
        guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true) else {return}
        guard let action = urlComponents.queryItems?.first(where: { $0.name == "type" })?.value else {return}
        
        switch action {
        case "survey":
            let answer = urlComponents.queryItems?.first(where: { $0.name == "answer" })?.value ?? "-1"
            viewModel?.onSurvey?(answer, "")
        case "feedback_sent":
            let feedback = urlComponents.queryItems?.first(where: { $0.name == "feedback_text" })?.value
            viewModel?.onFeedback?(feedback, "")
            fallthrough
        case "dismiss":
            onFinishLoad()
            viewModel?.dismiss?(true, self)
        default:
            break
        }
    }
    
    func process(navigationAction: WKNavigationAction) -> Bool {
        if let url = navigationAction.request.url {
            let lastComponent = url.lastPathComponent
            
            switch lastComponent {
            case "subscription",
                 "billing_issue":
                processSalesAction(from: url)
                return false
            case "feedback":
                processSurveyAction(from: url)
                return true
            case "subscriptions":
                processSurveyAction(from: url)
                return true
            case "upsale":
                return processSalesAction(from: url)
            case "dismiss":
                onFinishLoad()
                viewModel?.dismiss?(true, self)
                return false
            default:
                return true
            }
        }
        return true
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if process(navigationAction: navigationAction) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("WebViewController // didFinish loading: \(String(describing: webView.url?.absoluteString))")
        webviewDidFinishNavigation()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("WebViewController // Did fail navigation: \(String(describing: webView.url?.absoluteString)), error: \(error)")
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
    
    @objc
    private func replaceProductInfo(html: String) -> String {
        var html = html
        
        if let product = viewModel?.product {
            html = html.updatedProductInfo(product: product)
        }
        
        guard let panda = (Panda.shared as? Panda) else { return html }
        
        for product in panda.appStoreClient.products.values {
            html = html.updatedTrialDuration(product: product)
            html = html.updatedProductPrice(product: product)
            html = html.updatedProductDuration(product: product)
            html = html.updatedProductIntroductoryPrice(product: product)
            html = html.updatedProductIntroductoryDuration(product: product)
        }
        
        return html
    }
}
