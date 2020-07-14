
## Panda SDK

Panda SDK is a lightweight open-source Swift library to easily integrate purchase screens into your app without coding.

Visit our website for details: https://app.panda.boosters.company/

## Features

👍 Integrating subscriptions using our SDK is very easy.<br/>Panda takes care of a subscription purchase flow. Integrate SDK in just a few lines of code.

🎨 Create subscription purchase screens without coding - just use html.<br/>You don't need to develop purchase screens. So easy!

## SDK Requirements

Panda SDK requires minimum iOS 11.2, Xcode 10 and Swift 4.2. 

## Installation

Panda SDK can be installed via CocoaPods, Swift Package Manager or manually.

##### Install via CocoaPods

Add the following line to your Podfile:

```ruby
pod 'PandaSDK'
```

And then run in the Terminal:

```ruby
pod install
```
##### Install via SPM (Swift Package Manager)

Add dependecy with the following URL:

```
https://github.com/AppSci/PandaSDK
```

#### Manual Installation

Copy all files in `Source` folder to your project.

## Initialize Panda SDK

To set up Panda SDK you will need API Key. [Register](https://app.panda.boosters.company/) your app in Panda Web and get your API key.

```swift
import PandaSDK

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
	
  Panda.configure(token: "YOUR_API_KEY", isDebug: true) { (result) in
      print("Configured: \(result)")
  }

  // the rest of your code
  return true
}

```

#### Working with Screens from Panda
For getting screen from Panda Web you should use 

```swift
func getScreen(screenId: String?, callback: ((Result<UIViewController, Error>) -> Void)?)
```

If you wanna prefetch screen to ensure that it will be ready before displaying it, you can use 

```swift
func prefetchScreen(screenId: String?)
```

We recommend you prefetch screen right after Panda SDK is configured:

```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // Override point for customization after application launch.
    Panda.configure(token: YOUR_SDK_TOKEN, isDebug: true) { (result) in
        print("Configured: \(result)")
        if configured {
            Panda.shared.prefetchScreen(screenId: YOUR_SCREEN_ID)
        }
    }
    return true
}
```

You can use Default screen in case of any errors - e.g. no inet connection - if you want, you can embed "Default.html" screen in bundle - name is critical  - it should be named exactly "Default.html" - we will use it for displaying this screen in case of any errors


## Plist structure

To have all set, you need to add this info in your `PandaSDK-Info.plist` - you can create it by your own or download  `PandaSDK-Info.plist` from Example - structure of `PandaSDK-Info.plist` is crutial, please, add 

| Plist property   | value                                        |                                                    |
|------------------|----------------------------------------------|----------------------------------------------------|
| BILLING_URL      | https://apps.apple.com/account/billing       | add your URL for Billing page or leave it as it is |
| POLICY_URL       | https://policy.com                           | add your URL for Policy & Privacy page             |
| TERMS_URL        | https://terms.html                           | add your URL for Terms & Conditions page           |
| SERVER_URL       | https://sdk-api.panda.boosters.company       | URL of Panda Server - please, do not remove         |
| SERVER_URL_DEBUG | https://sdk-api.panda-stage.boosters.company | Debug URL of Panda Server - please, do not remove   |
| productIds       | Array                                        | Array of your Purchase product ids                 |


## Handle Subscriptions

Panda SDK provides a set of methods to manage subscriptions. 

### Fetch Products

Panda SDK automatically fetches SKProduct objects upon launch. Products identifiers must be added in "PandaSDK-Info.plist". You can download example for .plist from Example app in Source code.

### Make a Purchase

To make a purchase - you are creating html with products_ids for Purchases - Panda SDK upon clicking on concreate button or view gets this product_id for purchase & you just need to implement callbacks for successful purchase or error :

```swift
var onPurchase: ((String) -> Void)? { get set }
var onError: ((Error) -> Void)? { get set }
```

### Restore Purchases

 Restore Purchase is called when user tap on `Restore purchase` button on html screen. You can handle this restore by implementing this callback
 Returns product_id for Restore Purchase

```swift
var onRestorePurchase: ((String) -> Void)? { get set }
```

Basically it just sends App Store Receipt to AppStore .

### Skipping Purchase Process
You can allow your users to skip all purchase process - when user tap cross on Screen, you can allow user to go futher into your app - this callback is called 

```swift
var onDismiss: (() -> Void)? { get set }
```

## Having troubles?

If you have any questions or troubles with SDK integration feel free to contact us. We are online.

*Like Panda? Place a star at the top 😊*
