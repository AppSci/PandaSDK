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
    var onFailedByTimeOut: (() -> Void)?
    
    var url: URLComponents?
    
    private lazy var wv: WKWebView = {
        let config = getWKWebViewConfiguration()
        let wv = WKWebView(frame: view.bounds, configuration: config)
        wv.navigationDelegate = self
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
        let loading = UIActivityIndicatorView(style: .gray)
        loading.hidesWhenStopped = true
        view.addSubview(loading)
        loading.translatesAutoresizingMaskIntoConstraints = false
        loading.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        loading.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        return loading
    }()
    
    internal func loadPage(html: String? = nil) {
        /// if after 15 seconds webview not appeared, then fail
        perform(#selector(failedByTimeOut), with: nil, afterDelay: 3.0)
        loadingIndicator.startAnimating()
        _ = view // trigger viewdidload
        wv.alpha = 0
        
        print("SubscriptionBooster // start loading html \(Date().timeIntervalSince1970) \(Date())")
        
        
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
        wv.load(URLRequest(url: url))
    }
    
    private func load(html: String, baseURL: URL?) {
        wv.loadHTMLString(html as String, baseURL: baseURL)
    }
    
    private func load(local url: URL) {
        wv.configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        wv.loadFileURL(url, allowingReadAccessTo: url)
    }
    
    deinit {
        onFinishLoad()
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(failedByTimeOut), object: nil)
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
            viewModel?.onPurchase(message.name, "js-code")
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
        wv.evaluateJavaScript(js) { (result, error) in
            if let res = result {
                print("location changed to \(res)")
            }
        }
    }
    
    func handleScreenDidLoad() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(failedByTimeOut), object: nil)
        
        wv.alpha = 1
        loadingIndicator.stopAnimating()
        print("SubscriptionBooster // html did load \(Date().timeIntervalSince1970) \(Date())")
    }
    
    @objc private func failedByTimeOut() {
        print("🚨 Timeout error")
        onFinishLoad()
        loadingIndicator.stopAnimating()
        if let f = onFailedByTimeOut {
            f()
        } else {
            viewModel?.dismiss?(false, self)
        }
    }
    
    internal func onStartLoad() {
        let activityData = ActivityData()
        NVActivityIndicatorPresenter.sharedInstance.startAnimating(activityData, nil)
    }

    internal func onFinishLoad() {
        NVActivityIndicatorPresenter.sharedInstance.stopAnimating(nil)
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
        
        switch action {
        case "purchase":
            onStartLoad()
            let productID = urlComps.queryItems?.first(where: { $0.name == "product_id" })?.value
            viewModel?.onPurchase(productID, url.lastPathComponent)
            return false
        case "restore":
            onStartLoad()
            viewModel?.onRestorePurchase?()
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
        case "post_feedback":
            // handlePostFeedbackTapped(urlComps: urlComps)
            break
        default:
            break
        }
        return true
    }
    
    private func handleSurvey(url: URL) {
        guard let urlComps = URLComponents(url: url, resolvingAgainstBaseURL: true) else {return}
        guard let action = urlComps.queryItems?.first(where: { $0.name == "type" })?.value else {return}
        
        switch action {
        case "survey":
            let answer = urlComps.queryItems?.first(where: { $0.name == "answer" })?.value ?? "-1"
            viewModel?.onSurvey?(answer)
        case "dismiss":
            onFinishLoad()
            viewModel?.dismiss?(true, self)
        default:
            break
        }
    }
    
    func handleNavigationAction(navigationAction: WKNavigationAction) -> Bool {
        
        if let url = navigationAction.request.url {
            let lastComponent = url.lastPathComponent
            
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
            case "feedback_sent",
                 "dismiss":
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
        if handleNavigationAction(navigationAction: navigationAction) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("WebViewController // didFinish loading: \(String(describing: webView.url?.absoluteString))")
        handleScreenDidLoad()
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