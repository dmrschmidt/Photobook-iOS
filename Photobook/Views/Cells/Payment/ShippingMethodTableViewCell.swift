//
//  ShippingMethodTableViewCell.swift
//  Shopify
//
//  Created by Jaime Landazuri on 11/08/2017.
//  Copyright © 2017 Kite.ly. All rights reserved.
//

class ShippingMethodTableViewCell: UITableViewCell {
    
    static let reuseIdentifier = NSStringFromClass(ShippingMethodTableViewCell.self).components(separatedBy: ".").last!
    
    @IBOutlet private weak var tickImageView: UIImageView!
    @IBOutlet private weak var methodLabel: UILabel!
    @IBOutlet private weak var deliveryTimeLabel: UILabel!
    @IBOutlet private weak var costLabel: UILabel!
    @IBOutlet weak var topSeparator: UIView!
    @IBOutlet weak var separatorLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var separator: UIView!
    
    var method: String? {
        didSet { methodLabel.text = method }
    }
    
    var deliveryTime: String? {
        didSet { deliveryTimeLabel.text = deliveryTime }
    }

    var cost: String? {
        didSet { costLabel.text = cost }
    }
    
    var ticked: Bool = false {
        didSet { tickImageView.alpha = ticked ? 1.0 : 0.0 }
    }
}

class ShippingMethodHeaderTableViewCell: UITableViewCell {
    
    static let reuseIdentifier = NSStringFromClass(ShippingMethodHeaderTableViewCell.self).components(separatedBy: ".").last!
    
    @IBOutlet weak var label: UILabel!
}
