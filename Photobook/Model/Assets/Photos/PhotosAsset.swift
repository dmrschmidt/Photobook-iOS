//
//  PhotosAsset.swift
//  Photobook
//
//  Created by Konstadinos Karayannis on 08/11/2017.
//  Copyright © 2017 Kite.ly. All rights reserved.
//

import UIKit
import Photos

protocol AssetManager {
    func fetchAssets(withLocalIdentifiers identifiers: [String], options: PHFetchOptions?) -> PHAsset?
    func fetchAssets(in: AssetCollection, options: PHFetchOptions) -> PHFetchResult<PHAsset>
}

class DefaultAssetManager: AssetManager {
    func fetchAssets(withLocalIdentifiers identifiers: [String], options: PHFetchOptions?) -> PHAsset? {
        return PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: options).firstObject
    }
    
    func fetchAssets(in assetCollection: AssetCollection, options: PHFetchOptions) -> PHFetchResult<PHAsset> {
        return PHAsset.fetchAssets(in: assetCollection as! PHAssetCollection, options: options)
    }
}

/// Photo library resource that can be used in a Photobook
@objc public class PhotosAsset: NSObject, NSCoding, Asset {
    
    /// Photo library asset
    @objc internal(set) public var photosAsset: PHAsset {
        didSet {
            identifier = photosAsset.localIdentifier
        }
    }
    
    /// Identifier for the album where the asset is included
    @objc internal(set) public var albumIdentifier: String?
    
    var imageManager = PHImageManager.default()
    static var assetManager: AssetManager = DefaultAssetManager()
    
    var identifier: String! {
        didSet {
            if photosAsset.localIdentifier != identifier,
               let asset = PhotosAsset.assetManager.fetchAssets(withLocalIdentifiers: [identifier], options: PHFetchOptions()) {
                    photosAsset = asset
            }
        }
    }
    
    var date: Date? {
        return photosAsset.creationDate
    }

    var size: CGSize { return CGSize(width: photosAsset.pixelWidth, height: photosAsset.pixelHeight) }
    var uploadUrl: String?
    
    /// Init
    ///
    /// - Parameters:
    ///   - photosAsset: Photo library asset
    ///   - albumIdentifier: Identifier for the album where the asset is included
    @objc public init(_ photosAsset: PHAsset, albumIdentifier: String?) {
        self.photosAsset = photosAsset
        self.albumIdentifier = albumIdentifier
        identifier = photosAsset.localIdentifier
    }
    
    func image(size: CGSize, loadThumbnailFirst: Bool = true, progressHandler: ((Int64, Int64) -> Void)?, completionHandler: @escaping (UIImage?, Error?) -> Void) {
        
        // Request the image at the correct aspect ratio
        var imageSize = self.size.resizeAspectFill(size)
        
        let options = PHImageRequestOptions()
        options.deliveryMode = loadThumbnailFirst ? .opportunistic : .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        
        // Convert points to pixels
        imageSize = CGSize(width: imageSize.width * UIScreen.main.usableScreenScale(), height: imageSize.height * UIScreen.main.usableScreenScale())
        DispatchQueue.global(qos: .background).async {
            self.imageManager.requestImage(for: self.photosAsset, targetSize: imageSize, contentMode: .aspectFill, options: options) { (image, _) in
                DispatchQueue.main.async {
                    completionHandler(image, nil)
                }
            }
        }
    }
    
    func imageData(progressHandler: ((Int64, Int64) -> Void)?, completionHandler: @escaping (Data?, AssetDataFileExtension, Error?) -> Void) {
        
        if photosAsset.mediaType != .image {
            completionHandler(nil, .unsupported, AssetLoadingException.notFound)
            return
        }
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        
        self.imageManager.requestImageData(for: photosAsset, options: options, resultHandler: { imageData, dataUti, _, _ in
            guard let data = imageData, let dataUti = dataUti else {
                completionHandler(nil, .unsupported, AssetLoadingException.notFound)
                return
            }
            
            let fileExtension: AssetDataFileExtension
            if dataUti.contains(".png") {
                fileExtension = .png
            } else if dataUti.contains(".jpeg") {
                fileExtension = .jpg
            } else if dataUti.contains(".gif") {
                fileExtension = .gif
            } else {
                fileExtension = .unsupported
            }
            
            // Check that the image is either jpg, png or gif otherwise convert it to jpg. So no HEICs, TIFFs or RAWs get uploaded to the back end.
            if fileExtension == .unsupported {
                guard let ciImage = CIImage(data: data),
                    let jpegData = CIContext().jpegRepresentation(of: ciImage, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [kCGImageDestinationLossyCompressionQuality : 0.8])
                else {
                    completionHandler(nil, .unsupported, AssetLoadingException.unsupported)
                    return
                }
                completionHandler(jpegData, .jpg, nil)
            } else {
                completionHandler(imageData, fileExtension, nil)
            }
        })
    }
        
    @objc public func encode(with aCoder: NSCoder) {
        aCoder.encode(albumIdentifier, forKey: "albumIdentifier")
        aCoder.encode(identifier, forKey: "identifier")
        aCoder.encode(uploadUrl, forKey: "uploadUrl")
    }
    
    @objc public required convenience init?(coder aDecoder: NSCoder) {
        guard let assetId = aDecoder.decodeObject(of: NSString.self, forKey: "identifier") as String?,
              let albumIdentifier = aDecoder.decodeObject(of: NSString.self, forKey: "albumIdentifier") as String?,
              let asset = PhotosAsset.assetManager.fetchAssets(withLocalIdentifiers: [assetId], options: nil) else
            { return nil }
            
        self.init(asset, albumIdentifier: albumIdentifier)
        uploadUrl = aDecoder.decodeObject(of: NSString.self, forKey: "uploadUrl") as String?
    }
    
    static func photosAssets(from assets:[Asset]) -> [PHAsset] {
        var photosAssets = [PHAsset]()
        for asset in assets{
            guard let photosAsset = asset as? PhotosAsset else { continue }
            photosAssets.append(photosAsset.photosAsset)
        }
        
        return photosAssets
    }
    
    static func assets(from photosAssets: [PHAsset], albumId: String) -> [Asset] {
        var assets = [Asset]()
        for photosAsset in photosAssets {
            assets.append(PhotosAsset(photosAsset, albumIdentifier: albumId))
        }
        
        return assets
    }
    
    @objc public func wasRemoved(in changeInstance: PHChange) -> Bool {
        if let changeDetails = changeInstance.changeDetails(for: photosAsset),
            changeDetails.objectWasDeleted {
            return true
        }
        return false
    }
}
