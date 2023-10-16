//
//  ConfiguredPanda+WebViewModel.swift
//
//
//  Created by Denys Danyliuk on 06.09.2023.
//

import StoreKit

extension Panda {
    func createViewModel(screenData: ScreenData, productID: String? = nil, payload: PandaPayload? = nil) -> WebViewModel {
        let viewModel = WebViewModel(screenData: screenData, payload: payload)
        let entryPoint = payload?.entryPoint

        if let productID = productID {
            Task {
                do {
                    let product = try await appStoreService.getProduct(with: productID)
                    viewModel.product = product
                } catch {
                    pandaLog("\(error.localizedDescription)")
                }
            }
        }
        
        viewModel.onTerms = openTerms
        viewModel.onPolicy = openPolicy
        viewModel.onSubscriptionTerms = openSubscriptionTerms

        viewModel.onApplePayPurchase = { [applePayPaymentHandler, weak self] pandaID, source, screenId, screenName, view in
            self?.onApplePayPurchase(
                applePayPaymentHandler: applePayPaymentHandler,
                pandaID: pandaID,
                source: source,
                screenId: screenId,
                screenName: screenName,
                view: view
            )
        }
        viewModel.onPurchase = { [weak self] productID, source, _, screenID, screenName, course in
            self?.onPurchase(productID: productID, source: source, screenID: screenID, screenName: screenName, course: course)
        }
        viewModel.onRestorePurchase = { [appStoreService] _, screenId, screenName in
            pandaLog("Restore")
            Task {
                try await appStoreService.restore()
            }
        }
        viewModel.onCustomEvent = { [weak self] eventName, eventParameters in
            self?.send(event: .customEvent(name: eventName, parameters: eventParameters))
        }
        viewModel.onPricesLoaded = { [appStoreService] productIDs, view in
            Task {
                do {
                    let products = try await appStoreService.getProducts(with: productIDs)
                    await view.sendLocalizedPrices(products: products)
                    if await appStoreService.hideTrial(for: products) {
                        print("[TRIAL] hiding trial")
                        await view.hideTrial()
                    }
                } catch {
                    pandaLog("Failed to fetch AppStore products, \(error)")
                }
            }
        }
        viewModel.onBillingIssue = { view in
            pandaLog("onBillingIssue")
            self.openBillingIssue()
            view.dismiss(animated: true, completion: nil)
        }
        viewModel.dismiss = { [weak self] status, view, screenId, screenName in
            pandaLog("Dismiss")
            if let screenID = screenId, let name = screenName {
                self?.trackClickDismiss(screenId: screenID, screenName: name, source: entryPoint)
            }
            view.tryAutoDismiss()
            self?.onDismiss?()
        }
        viewModel.onViewWillAppear = { [weak self] screenId, screenName in
            pandaLog("onViewWillAppear \(String(describing: screenName)) \(String(describing: screenId))")
            self?.send(event: .screenWillShow(screenId: screenId ?? "", screenName: screenName ?? "", source: entryPoint))
        }
        viewModel.onViewDidAppear = { [weak self] screenId, screenName, course in
            pandaLog("onViewDidAppear \(String(describing: screenName)) \(String(describing: screenId))")
            self?.send(event: .screenShowed(screenId: screenId ?? "", screenName: screenName ?? "", source: entryPoint, course: course))
        }
        viewModel.onDidFinishLoading = { [weak self] screenId, screenName, course in
            pandaLog("onDidFinishLoading \(String(describing: screenName)) \(String(describing: screenId))")
            self?.send(event: .screenLoaded(screenId: screenId ?? "", screenName: screenName ?? "", source: entryPoint))
        }
        viewModel.onSupportUkraineAnyButtonTap = { [weak self] in
            self?.send(event: .onSupportUkraineAnyButtonTap)
        }
        viewModel.onDontHaveApplePay = { [weak self] screenID, destination in
            self?.send(event: .onDontHaveApplePay(screenId: screenID ?? "", source: entryPoint, destination: destination))
        }
        viewModel.onTutorsHowOfferWorks = { [weak self] screenID, destination in
            self?.send(event: .onTutorsHowOfferWorks(screenId: screenID ?? "", source: entryPoint, destination: destination))
        }
        viewModel.onStartLoadingIndicator = { [weak self] in
            self?.send(event: .onStartLoading)
        }
        viewModel.onFinishLoadingIndicator = { [weak self] in
            self?.send(event: .onFinishLoading)
        }
        viewModel.onFreeForUkraineButtonTap = { [weak self] result in
            self?.send(event: .trackOpenLink(link: "Free for Ukraine", result: result.description))
        }
        return viewModel
    }
    
    private func onApplePayPurchase(
        applePayPaymentHandler: ApplePayPaymentHandler,
        pandaID: String?,
        source: String,
        screenId: String,
        screenName: String,
        view: WebViewController
    ) {
        guard
            let pandaID = pandaID
        else {
            pandaLog("Missing productId with source: \(source)")
            return
        }
        viewControllerForApplePayPurchase = view

        pandaLog("purchaseStarted: \(pandaID) \(screenName) \(screenId)")
        send(event: .purchaseStarted(screenId: screenId, screenName: screenName, productId: pandaID, source: entryPoint))

        networkClient.getBillingPlan(
            with: pandaID,
            callback: { [weak self] result in
                switch result {
                case let .success(billingPlan):
                    applePayPaymentHandler.startPayment(
                        with: billingPlan.getLabelForApplePayment(),
                        price: billingPlan.getPrice(),
                        currency: billingPlan.currency,
                        billingID: billingPlan.id,
                        countryCode: billingPlan.countryCode,
                        productID: billingPlan.productID,
                        screenID: screenId
                    )
                case let .failure(error):
                    self?.onError?(error)
                    self?.send(event: .purchaseError(error: error, source: self?.entryPoint))
                    pandaLog("Failed get billingPlan Error: \(error)")
                }
            }
        )
    }
    
    private func onPurchase(productID: String?, source: String, screenID: String, screenName: String, course: String?) {
        guard let productID = productID else {
            pandaLog("Missing productId with source: \(source)")
            return
        }
        pandaLog("purchaseStarted: \(productID) \(screenName) \(screenID)")
        send(event: .purchaseStarted(screenId: screenID, screenName: screenName, productId: productID, source: entryPoint))
        
        Task { [weak self] in
            guard let self = self else {
                return
            }
            let source = PaymentSource(
                screenId: screenID,
                screenName: screenName,
                course: course
            )
            try? await self.purchase(productID: productID, paymentSource: source)
        }
    }
    
    func onAppStoreServiceVerify() async {
        do {
            let result = try await appStoreService.verifyTransaction(user: user, source: nil)
            send(event: .updateStatuses)
        } catch {
            pandaLog("\(error)")
        }
    }
    
    @MainActor
    func onError(error: Error) {
        viewControllers.forEach { $0.value?.onFinishLoad() }
        onError?(Errors.appStoreReceiptError(error))
        send(event: .purchaseError(error: error, source: self.entryPoint))
    }
    
    @MainActor
    func onCancel() {
        viewControllers.forEach { $0.value?.onFinishLoad() }
    }
    
    @MainActor
    func onVerified(product: Product, source: PaymentSource) {
        viewControllers.forEach({ $0.value?.onPurchaseCompleted()})
        viewControllers.forEach { $0.value?.onFinishLoad() }
        viewControllers.forEach({ $0.value?.tryAutoDismiss()})
        onPurchase?(product)
        onSuccessfulPurchase?()
        send(
            event: .successfulPurchase(
                screenId: source.screenId,
                screenName: source.screenName,
                product: product,
                source: entryPoint,
                course: source.course
            )
        )
        send(event: .updateStatuses)
    }
}
