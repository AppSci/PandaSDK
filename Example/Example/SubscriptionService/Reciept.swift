/// Copyright (c) 2018 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit

enum ReceiptStatus: String {
  case validationSuccess = "This receipt is valid."
  case noReceiptPresent = "A receipt was not found on this device."
  case unknownFailure = "An unexpected failure occurred during verification."
  case unknownReceiptFormat = "The receipt is not in PKCS7 format."
  case invalidPKCS7Signature = "Invalid PKCS7 Signature."
  case invalidPKCS7Type = "Invalid PKCS7 Type."
  case invalidAppleRootCertificate = "Public Apple root certificate not found."
  case failedAppleSignature = "Receipt not signed by Apple."
  case unexpectedASN1Type = "Unexpected ASN1 Type."
  case missingComponent = "Expected component was not found."
  case invalidBundleIdentifier = "Receipt bundle identifier does not match application bundle identifier."
  case invalidVersionIdentifier = "Receipt version identifier does not match application version."
  case invalidHash = "Receipt failed hash check."
  case invalidExpired = "Receipt has expired."
}

struct Certificate {
    let url: URL?
    let root: Bool
}

extension Certificate {
    static func `default`() -> Certificate {
        return Certificate(url: Bundle.main.url(forResource: "AppleIncRootCertificate", withExtension: "cer"), root: true)
    }
}

public class Receipt {
  var receiptStatus: ReceiptStatus?
  var bundleIdString: String?
  var bundleVersionString: String?
  var bundleIdData: Data?
  var hashData: Data?
  var opaqueData: Data?
  var expirationDate: Date?
  var receiptCreationDate: Date?
  var originalAppVersion: String?
  var inAppReceipts: [IAPReceipt] = []

  static public func isReceiptPresent() -> Bool {
    if let receiptUrl = Bundle.main.appStoreReceiptURL,
      let canReach = try? receiptUrl.checkResourceIsReachable(),
      canReach {
      return true
    }
    
    return false
  }
  
  init(certificate: Certificate = .default()) {
    guard let payload = loadReceipt() else {
        return
    }
    
    guard validateSigning(payload, certificate: certificate) else {
      return
    }
    
    readReceipt(payload)
    
    validateReceipt()
  }
  
  private func loadReceipt() -> UnsafeMutablePointer<PKCS7>? {
    // Load the receipt into a Data object
    guard
      let receiptUrl = Bundle.main.appStoreReceiptURL,
      let receiptData = try? Data(contentsOf: receiptUrl)
      else {
        receiptStatus = .noReceiptPresent
        return nil
    }
    
    // 1
    let receiptBIO = BIO_new(BIO_s_mem())
    let receiptBytes: [UInt8] = .init(receiptData)
    BIO_write(receiptBIO, receiptBytes, Int32(receiptData.count))
    // 2
    let receiptPKCS7 = d2i_PKCS7_bio(receiptBIO, nil)

    BIO_free(receiptBIO)
    // 3
    guard receiptPKCS7 != nil else {
      receiptStatus = .unknownReceiptFormat
      return nil
    }
    
    // Check that the container has a signature
    guard OBJ_obj2nid(receiptPKCS7!.pointee.type) == NID_pkcs7_signed else {
      receiptStatus = .invalidPKCS7Signature
      return nil
    }
    
    // Check that the container contains data
    let receiptContents = receiptPKCS7!.pointee.d.sign.pointee.contents
    guard OBJ_obj2nid(receiptContents?.pointee.type) == NID_pkcs7_data else {
      receiptStatus = .invalidPKCS7Type
      return nil
    }
    
    return receiptPKCS7
  }
  
  private func validateSigning(_ receipt: UnsafeMutablePointer<PKCS7>?, certificate: Certificate) -> Bool {
    guard
      let rootCertUrl = certificate.url,
      let rootCertData = try? Data(contentsOf: rootCertUrl)
      else {
        receiptStatus = .invalidAppleRootCertificate
        return false
    }
    
    let rootCertBio = BIO_new(BIO_s_mem())
    let rootCertBytes: [UInt8] = .init(rootCertData)
    BIO_write(rootCertBio, rootCertBytes, Int32(rootCertData.count))
    let rootCertX509 = d2i_X509_bio(rootCertBio, nil)
    BIO_free(rootCertBio)
    
    // 1
    let store = X509_STORE_new()
    X509_STORE_add_cert(store, rootCertX509)
    
    // 2
    OPENSSL_init_crypto(UInt64(OPENSSL_INIT_ADD_ALL_DIGESTS), nil)
    
    // 3
    let verificationResult = PKCS7_verify(receipt, nil, store, nil, nil, certificate.root ? 0 : PKCS7_NOCHAIN)
    guard verificationResult == 1  else {
      receiptStatus = .failedAppleSignature
      return false
    }
    
    return true
  }
  
  private func readReceipt(_ receiptPKCS7: UnsafeMutablePointer<PKCS7>?) {
    // Get a pointer to the start and end of the ASN.1 payload
    let receiptSign = receiptPKCS7?.pointee.d.sign
    let octets = receiptSign?.pointee.contents.pointee.d.data
    var ptr = UnsafePointer(octets?.pointee.data)
    let end = ptr!.advanced(by: Int(octets!.pointee.length))
    
    var type: Int32 = 0
    var xclass: Int32 = 0
    var length: Int = 0
    
    ASN1_get_object(&ptr, &length, &type, &xclass, ptr!.distance(to: end))
    guard type == V_ASN1_SET else {
      receiptStatus = .unexpectedASN1Type
      return
    }

    // 1
    while ptr! < end {
      // 2
      ASN1_get_object(&ptr, &length, &type, &xclass, ptr!.distance(to: end))
      guard type == V_ASN1_SEQUENCE else {
        receiptStatus = .unexpectedASN1Type
        return
      }
      
      // 3
      guard let attributeType = readASN1Integer(ptr: &ptr, maxLength: length) else {
        receiptStatus = .unexpectedASN1Type
        return
      }
      
      // 4
      guard let _ = readASN1Integer(ptr: &ptr, maxLength: ptr!.distance(to: end)) else {
        receiptStatus = .unexpectedASN1Type
        return
      }
      
      // 5
      ASN1_get_object(&ptr, &length, &type, &xclass, ptr!.distance(to: end))
      guard type == V_ASN1_OCTET_STRING else {
        receiptStatus = .unexpectedASN1Type
        return
      }
      
      switch attributeType {
      case 2: // The bundle identifier
        var stringStartPtr = ptr
        bundleIdString = readASN1String(ptr: &stringStartPtr, maxLength: length)
        bundleIdData = readASN1Data(ptr: ptr!, length: length)
        
      case 3: // Bundle version
        var stringStartPtr = ptr
        bundleVersionString = readASN1String(ptr: &stringStartPtr, maxLength: length)
        
      case 4: // Opaque value
        let dataStartPtr = ptr!
        opaqueData = readASN1Data(ptr: dataStartPtr, length: length)
        
      case 5: // Computed GUID (SHA-1 Hash)
        let dataStartPtr = ptr!
        hashData = readASN1Data(ptr: dataStartPtr, length: length)
        
      case 12: // Receipt Creation Date
        var dateStartPtr = ptr
        receiptCreationDate = readASN1Date(ptr: &dateStartPtr, maxLength: length)
        
      case 17: // IAP Receipt
        var iapStartPtr = ptr
        let parsedReceipt = IAPReceipt(with: &iapStartPtr, payloadLength: length)
        if let newReceipt = parsedReceipt {
          inAppReceipts.append(newReceipt)
        }
        
      case 19: // Original App Version
        var stringStartPtr = ptr
        originalAppVersion = readASN1String(ptr: &stringStartPtr, maxLength: length)
        
      case 21: // Expiration Date
        var dateStartPtr = ptr
        expirationDate = readASN1Date(ptr: &dateStartPtr, maxLength: length)
        
      default: // Ignore other attributes in receipt
        print("Not processing attribute type: \(attributeType)")
      }
      
      // Advance pointer to the next item
      ptr = ptr!.advanced(by: length)
    }
  }
  
  private func validateReceipt() {
    guard
      let idString = bundleIdString,
      let version = bundleVersionString,
      let _ = opaqueData,
      let hash = hashData
      else {
        receiptStatus = .missingComponent
        return
    }
    
    // Check the bundle identifier
    guard let appBundleId = Bundle.main.bundleIdentifier else {
      receiptStatus = .unknownFailure
      return
    }
    
    guard idString == appBundleId else {
      receiptStatus = .invalidBundleIdentifier
      return
    }
    
    // Check the version
    guard let appVersionString =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
      receiptStatus = .unknownFailure
      return
    }
    guard version == appVersionString else {
      receiptStatus = .invalidVersionIdentifier
      return
    }
    
    // Check the GUID hash
    let guidHash = computeHash()
    guard hash == guidHash else {
      receiptStatus = .invalidHash
      return
    }
    
    // Check the expiration attribute if it's present
    let currentDate = Date()
    if let expirationDate = expirationDate {
      if expirationDate < currentDate {
        receiptStatus = .invalidExpired
        return
      }
    }
    
    // All checks passed so validation is a success
    receiptStatus = .validationSuccess
  }
  
  private func getDeviceIdentifier() -> Data {
    let device = UIDevice.current
    var uuid = device.identifierForVendor!.uuid
    let addr = withUnsafePointer(to: &uuid) { (p) -> UnsafeRawPointer in
      UnsafeRawPointer(p)
    }
    let data = Data(bytes: addr, count: 16)
    return data
  }
  
  private func computeHash() -> Data {
    let identifierData = getDeviceIdentifier()
    var ctx = SHA_CTX()
    SHA1_Init(&ctx)
    
    let identifierBytes: [UInt8] = .init(identifierData)
    SHA1_Update(&ctx, identifierBytes, identifierData.count)
    
    let opaqueBytes: [UInt8] = .init(opaqueData!)
    SHA1_Update(&ctx, opaqueBytes, opaqueData!.count)
    
    let bundleBytes: [UInt8] = .init(bundleIdData!)
    SHA1_Update(&ctx, bundleBytes, bundleIdData!.count)
    
    var hash: [UInt8] = .init(repeating: 0, count: 20)
    SHA1_Final(&hash, &ctx)
    return Data(bytes: hash, count: 20)
  }
}

