//
//  ProductManager.swift
//  Photobook
//
//  Created by Jaime Landazuri on 22/11/2017.
//  Copyright © 2017 Kite.ly. All rights reserved.
//

import UIKit

enum ProductColor: String, Codable {
    case white, black
}

// Structure containing the user's photobok details to save them to disk
struct PhotobookBackUp: Codable {
    var product: Photobook
    var coverColor: ProductColor
    var pageColor: ProductColor
    var productLayouts: [ProductLayout]
}

/// Manages the user's photobook; Storing, retrieving and uploading when necessary
class ProductManager {

    // Notification keys
    static let pendingUploadStatusUpdated = Notification.Name("ProductManagerPendingUploadStatusUpdated")
    static let shouldRetryUploadingImages = Notification.Name("ProductManagerShouldRetryUploadingImages")
    static let finishedPhotobookCreation = Notification.Name("ProductManagerFinishedPhotobookCreation")
    
    private struct Storage {
        static let photobookDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!.appending("/Photobook/")
        static let photobookBackUpFile = photobookDirectory.appending("Photobook.dat")
    }
    
    static let shared = ProductManager()
    
    private lazy var apiManager: PhotobookAPIManager = {
        let manager = PhotobookAPIManager()
        manager.delegate = self
        return manager
    }()
    
    #if DEBUG
    convenience init(apiManager: PhotobookAPIManager) {
        self.init()
        self.apiManager = apiManager
    }
    
    var storageFile: String { return Storage.photobookBackUpFile }
    #endif

    // Public info about photobook products
    private(set) var products: [Photobook]?

    // List of all available layouts
    private(set) var layouts: [Layout]?
    
    // Current photobook
    var product: Photobook?
    var coverColor: ProductColor = .white
    var pageColor: ProductColor = .white
    var productLayouts = [ProductLayout]()
    
    // TODO: Spine
    
    /// Requests the photobook details so the user can start building their photobook
    ///
    /// - Parameter completion: Completion block with an optional error
    func initialise(completion:@escaping (Error?)->()) {
        apiManager.requestPhotobookInfo { [weak welf = self] (photobooks, layouts, error) in
            guard error == nil else {
                completion(error!)
                return
            }
            
            welf?.products = photobooks
            welf?.layouts = layouts
            
            completion(nil)
        }
    }
    
    func setPhotobook(_ photobook: Photobook, withAssets assets: [Asset]) {
        guard
            let coverLayouts = coverLayouts(for: photobook),
            coverLayouts.count > 0,
            let layouts = layouts(for: photobook),
            layouts.count > 0
        else {
            print("ProductManager: Missing layouts for selected photobook")
            return
        }

        var unusedAssets = assets

        var portraitLayouts = layouts.filter { !$0.isLandscape() && !$0.isEmptyLayout() && !$0.isDoubleLayout }
        var landscapeLayouts = layouts.filter { $0.isLandscape() && !$0.isEmptyLayout() && !$0.isDoubleLayout }
        
        // First photobook
        // TODO: Check if the minimum number of pages are met. Create empty pages that the user will have to assign
        // assets to. Take into account that the first and last pages should be empty.
        if product == nil {
            var tempLayouts = [ProductLayout]()

            var currentPortraitLayout = 0
            var currentLandscapeLayout = 0

            // Use first photo for the cover
            let productLayoutAsset = ProductLayoutAsset()
            productLayoutAsset.asset = unusedAssets.remove(at: 0)
            let productLayout = ProductLayout(layout: coverLayouts.first!, productLayoutAsset: productLayoutAsset)
            tempLayouts.append(productLayout)
            
            // Loop through the remaining assets
            for asset in unusedAssets {
                // FIXME: Logic TBC
                let productLayoutAsset = ProductLayoutAsset()
                productLayoutAsset.asset = asset

                var layout: Layout
                if asset.isLandscape {
                    layout = landscapeLayouts[currentLandscapeLayout]
                    currentLandscapeLayout = currentLandscapeLayout < landscapeLayouts.count - 1 ? currentLandscapeLayout + 1 : 0
                } else {
                    layout = portraitLayouts[currentPortraitLayout]
                    currentPortraitLayout = currentPortraitLayout < portraitLayouts.count - 1 ? currentPortraitLayout + 1 : 0
                }
                let productLayout = ProductLayout(layout: layout, productLayoutAsset: productLayoutAsset)
                tempLayouts.append(productLayout)
            }
            
            productLayouts = tempLayouts
            product = photobook
            return
        }
        
        // Switching products
        for pageLayout in productLayouts {
            // Match layouts from the current product to the new one
            var newLayout = layouts.first { $0.category == pageLayout.layout.category }
            if newLayout == nil {
                // Should not happen but to be safe, pick the first layout
                newLayout = layouts.first
            }
            pageLayout.layout = newLayout
        }
    }
    
    private func coverLayouts(for photobook: Photobook) -> [Layout]? {
        guard let layouts = layouts else { return nil }
        return layouts.filter { photobook.coverLayouts.contains($0.id) }
    }
    
    private func layouts(for photobook: Photobook) -> [Layout]? {
        guard let layouts = layouts else { return nil }
        return layouts.filter { photobook.layouts.contains($0.id) }
    }
    
    /// Sets one of the available layouts for a page number
    ///
    /// - Parameters:
    ///   - layout: The layout to use
    ///   - page: The page index in the photobook
    func setLayout(_ layout: Layout, forPage page: Int) {
        productLayouts[page].layout = layout
    }
    
    /// Sets an asset as the content of one of the containers of a page in the photobook
    ///
    /// - Parameters:
    ///   - asset: The image asset to use
    ///   - page: The page index in the photbook
    func setAsset(_ asset: Asset, forPage page: Int) {
        productLayouts[page].asset = asset
    }
    
    /// Sets copy as the content of one of the containers of a page in the photobook
    ///
    /// - Parameters:
    ///   - text: The copy to use
    ///   - page: The page index in the photbook
    func setText(_ text: String, forPage page: Int) {
        productLayouts[page].text = text
    }
    
    /// Initiates the uploading of the user's photobook
    ///
    /// - Parameter completionHandler: Executed when the uploads are on the way or failed to initiate them. The Int parameter provides the total upload count.
    func startPhotobookUpload(_ completionHandler: (Int, Error?) -> Void) {
        self.saveUserPhotobook()
        apiManager.uploadPhotobook(completionHandler)
    }
    
    /// Loads the user's photobook details from disk
    ///
    /// - Parameter completionHandler: Closure called on completion
    func loadUserPhotobook(_ completionHandler: @escaping () -> Void) {
        guard let unarchivedData = NSKeyedUnarchiver.unarchiveObject(withFile: Storage.photobookBackUpFile) as? Data else {
            print("ProductManager: failed to unarchive product")
            return
        }
        guard let unarchivedProduct = try? PropertyListDecoder().decode([String: Any].self, from: unarchivedData) else {
            print("ProductManager: decoding of product failed")
            return
        }
        
        if let product = unarchivedProduct["product"] as? Photobook,
           let coverColor = unarchivedProduct["coverColor"] as? ProductColor,
           let pageColor = unarchivedProduct["pageColor"] as? ProductColor,
           let productLayouts = unarchivedProduct["productLayouts"] as? [ProductLayout] {
                self.product = product
                self.coverColor = coverColor
                self.pageColor = pageColor
                self.productLayouts = productLayouts
        }
        apiManager.restoreUploads(completionHandler)
    }
    
    
    /// Saves the user's photobook details to disk
    func saveUserPhotobook() {
        guard let product = product else { return }
        
        let rootObject = PhotobookBackUp(product: product, coverColor: coverColor, pageColor: pageColor, productLayouts: productLayouts)
        
        guard let data = try? PropertyListEncoder().encode(rootObject) else {
            fatalError("ProductManager: encoding of product failed")
        }
        
        if !FileManager.default.fileExists(atPath: Storage.photobookDirectory) {
            do {
                try FileManager.default.createDirectory(atPath: Storage.photobookDirectory, withIntermediateDirectories: false, attributes: nil)
            } catch {
                print("ProductManager: could not save photobook")
            }
        }
        
        let saved = NSKeyedArchiver.archiveRootObject(data, toFile: Storage.photobookBackUpFile)
        if !saved {
            print("ProductManager: failed to archive product")
        }
    }
}

extension ProductManager: PhotobookAPIManagerDelegate {

    func didFinishUploading(asset: Asset) {
        let info: [String: Any] = [ "asset": asset, "pending": apiManager.pendingUploads ]
        NotificationCenter.default.post(name: ProductManager.pendingUploadStatusUpdated, object: info)
    }
    
    func didFailUpload(_ error: Error) {
        if let error = error as? PhotobookAPIError {
            switch error {
            case .missingPhotobookInfo:
                fatalError("ProductManager: incorrect or missing photobook info")
            case .couldNotSaveTempImage:
                let info = [ "pending": apiManager.pendingUploads ]
                NotificationCenter.default.post(name: ProductManager.pendingUploadStatusUpdated, object: info)
                
                NotificationCenter.default.post(name: ProductManager.shouldRetryUploadingImages, object: nil)
            case .couldNotBuildCreationParameters:
                fatalError("PhotobookManager: could not build PDF creation request parameters")
            }
        } else if let _ = error as? APIClientError {
            // Connection / server errors are handled by the system. This can only be a parsing error.
            fatalError("ProductManager: could not parse upload response")
        }
    }
    
    func didFinishCreatingPdf(error: Error?) {
        NotificationCenter.default.post(name: ProductManager.finishedPhotobookCreation, object: nil)
    }
}