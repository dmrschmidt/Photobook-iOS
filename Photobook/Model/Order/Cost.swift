//
//  Cost.swift
//  Shopify
//
//  Created by Konstadinos Karayannis on 13/07/2017.
//  Copyright © 2017 Kite.ly. All rights reserved.
//

import UIKit
import PassKit

class LineItem: NSObject, NSSecureCoding {
    
    static var supportsSecureCoding = true
    
    let id: Int
    let name: String
    let cost: Decimal
    let formattedCost: String
    
    init(id: Int, name: String, cost: Decimal, formattedCost: String) {
        self.id = id
        self.name = name
        self.cost = cost
        self.formattedCost = formattedCost
    }
    
    required convenience init?(coder aDecoder: NSCoder) {
        guard
            let id = aDecoder.decodeInteger(forKey: "productId") as Int?,
            let name = aDecoder.decodeObject(of: NSString.self, forKey: "name") as String?,
            let cost = aDecoder.decodeObject(of: NSDecimalNumber.self, forKey: "cost") as Decimal?,
            let formattedCost = aDecoder.decodeObject(of: NSString.self, forKey: "formattedCost") as String?
            else { return nil }
        
        self.init(id: id, name: name, cost: cost, formattedCost: formattedCost)
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(id, forKey: "productId")
        aCoder.encode(name, forKey: "name")
        aCoder.encode(cost, forKey: "cost")
        aCoder.encode(formattedCost, forKey: "formattedCost")
    }
}

class Cost: NSObject, NSSecureCoding {
    
    static var supportsSecureCoding = false
    
    var orderHash: Int
    let lineItems: [LineItem]?
    let shippingMethods: [ShippingMethod]?
    let promoDiscount: String?
    let promoCodeInvalidReason: String?
    
    init(hash: Int, lineItems: [LineItem]?, shippingMethods: [ShippingMethod]?, promoDiscount: String?, promoCodeInvalidReason: String?){
        self.orderHash = hash
        self.lineItems = lineItems
        self.shippingMethods = shippingMethods
        self.promoDiscount = promoDiscount
        self.promoCodeInvalidReason = promoCodeInvalidReason
    }
    
    required convenience init?(coder aDecoder: NSCoder) {
        guard
            let orderHash = aDecoder.decodeInteger(forKey: "orderHash") as Int?,
            let lineItems = aDecoder.decodeObject(forKey: "lineItems") as? [LineItem]?,
            let shippingMethods = aDecoder.decodeObject(forKey: "shippingMethods") as? [ShippingMethod]?
            else { return nil }
        
        let promoDiscount = aDecoder.decodeObject(of: NSString.self, forKey: "promoDiscount") as String?
        let promoCodeInvalidReason = aDecoder.decodeObject(of: NSString.self, forKey: "promoCodeInvalidReason") as String?
        
        self.init(hash: orderHash, lineItems: lineItems, shippingMethods: shippingMethods, promoDiscount: promoDiscount, promoCodeInvalidReason: promoCodeInvalidReason)
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(orderHash, forKey: "orderHash")
        aCoder.encode(lineItems, forKey: "lineItems")
        aCoder.encode(shippingMethods, forKey: "shippingMethods")
        aCoder.encode(promoDiscount, forKey: "promoDiscount")
        aCoder.encode(promoCodeInvalidReason, forKey: "promoCodeInvalidReason")
    }
    
    func shippingMethod(id method: Int?) -> ShippingMethod? {
        guard method != nil, method! > 0, let methods = shippingMethods, methods.count > 0 else { return nil }
        
        for aMethod in methods {
            if aMethod.id == method { return aMethod }
        }
        return nil
    }
    
    
    static func parseDetails(dictionary: [String : Any]) -> Cost? {
        guard let lineItemsDictionary = dictionary["line_items"] as? [[String: Any]],
              let shippingMethodsDictionary = dictionary["shipping_methods"] as? [[String: Any]] else { return nil }
        
        var shippingMethods = [ShippingMethod]()
        for shippingMethodDictionary in shippingMethodsDictionary {
            if let shippingMethod = ShippingMethod.parse(dictionary: shippingMethodDictionary) {
                shippingMethods.append(shippingMethod)
            }
        }
        
        var promoDiscount: String?
        var promoInvalidMessage: String?
        
        if let promoCode = dictionary["promo_code"] as? [String: Any] {
            if let invalidMessage = promoCode["invalid_message"] as? String { promoInvalidMessage = invalidMessage }
            if let discount = promoCode["discount"] as? [String: Any],
                let amount = discount["amount"] as? String,
                let discountAmount = Decimal(string:amount),
                discountAmount > 0,
                let currency = discount["currency"] as? String
            {
                promoDiscount = discountAmount.formattedCost(currencyCode: currency)
            }
        }
        
        var lineItems = [LineItem]()
        for item in lineItemsDictionary {
            guard
                let id = item["variant_id"] as? Int,
                let name = item["description"] as? String,
                let costDictionary = item["cost"] as? [String: Any],
                let amount = costDictionary["amount"] as? String,
                let cost = Decimal(string: amount),
                let currency = costDictionary["currency"] as? String
                else { return nil }
            
            let formattedCost = cost.formattedCost(currencyCode: currency)
            let lineItem = LineItem(id: id, name: name, cost: cost, formattedCost: formattedCost)
            lineItems.append(lineItem)
        }
        
        return Cost(hash: 0, lineItems: lineItems, shippingMethods: shippingMethods, promoDiscount: promoDiscount, promoCodeInvalidReason: promoInvalidMessage)
    }
    
    /// Create an array of PKPaymentSummaryItem from the order's lineItems and add item for total
    ///
    /// - Parameter payTo: A string that shows the user whom they are paying.
    /// - Returns: an array of PKPaymentSummaryItem that's appropriate for Apple Pay 
    func summaryItemsForApplePay(payTo: String, shippingMethodId: Int) -> [PKPaymentSummaryItem]{
        guard
            let lineItems = self.lineItems,
            let totalCost = self.shippingMethod(id: shippingMethodId)?.totalCost as NSDecimalNumber?
            else { return [PKPaymentSummaryItem]() }
        
        var summaryItems = [PKPaymentSummaryItem]()
        for item in lineItems{
            summaryItems.append(PKPaymentSummaryItem(label: item.name, amount: item.cost as NSDecimalNumber))
        }
        
        summaryItems.append(PKPaymentSummaryItem(label: payTo, amount: totalCost))
        
        return summaryItems
    }
}