//
//  PhotobookManager.swift
//  Photobook
//
//  Created by Jaime Landazuri on 17/11/2017.
//  Copyright © 2017 Kite.ly. All rights reserved.
//

import Foundation

enum PhotobookAPIError: Error {
    case missingPhotobookInfo
    case couldNotBuildCreationParameters
    case couldNotSaveTempImageData
}

class PhotobookAPIManager {
    
    var apiKey: String? {
        didSet {
            guard let apiKey = apiKey else { return }
            headers = ["Authorization": "ApiKey \(apiKey)"]
        }
    }
    
    static let imageUploadIdentifierPrefix = "PhotobookAPIManager-AssetUploader-"
    private var headers: [String: String]?
    
    struct EndPoints {
        static let products = "/ios/get_initial_data"
        static let summary = "/ios/summary"
        static let applyUpsell = "/ios/upsell.apply"
        static let createPdf = "/ios/generate_photobook_pdf"
        static let imageUpload = "/upload/"
    }

    private var apiClient = APIClient.shared
    
    #if DEBUG
    convenience init(apiClient: APIClient) {
        self.init()
        self.apiClient = apiClient
    }
    #endif
    
    /// Requests the information about photobook products and layouts from the API
    ///
    /// - Parameter completionHandler: Closure to be called when the request completes
    func requestPhotobookInfo(_ completionHandler:@escaping ([PhotobookTemplate]?, [Layout]?, [UpsellOption]?, Error?) -> ()) {

        apiClient.get(context: .photobook, endpoint: EndPoints.products, parameters: nil, headers: headers) { (jsonData, error) in
            
            if jsonData == nil, error != nil {
                completionHandler(nil, nil, nil, error!)
                return
            }
            
            guard
                let photobooksData = jsonData as? [String: AnyObject],
                let productsData = photobooksData["products"] as? [[String: AnyObject]],
                let layoutsData = photobooksData["layouts"] as? [[String: AnyObject]]
            else {
                completionHandler(nil, nil, nil, APIClientError.parsing)
                return
            }
            
            // Parse layouts
            var tempLayouts = [Layout]()
            for layoutDictionary in layoutsData {
                if let layout = Layout.parse(layoutDictionary) {
                    tempLayouts.append(layout)
                }
            }
            
            if tempLayouts.isEmpty {
                print("PhotobookAPIManager: parsing layouts failed")
                completionHandler(nil, nil, nil, APIClientError.parsing)
                return
            }
            
            // Parse photobook products
            var tempPhotobooks = [PhotobookTemplate]()
            
            for photobookDictionary in productsData {
                if let photobook = PhotobookTemplate.parse(photobookDictionary) {
                    tempPhotobooks.append(photobook)
                }
            }
            
            if tempPhotobooks.isEmpty {
                print("PhotobookAPIManager: parsing photobook products failed")
                completionHandler(nil, nil, nil, APIClientError.parsing)
                return
            }
            // Sort products by cover width
            tempPhotobooks.sort(by: { return $0.coverSize.width < $1.coverSize.width })
            
            completionHandler(tempPhotobooks, tempLayouts, nil, nil)
        }
    }
    
    /// Creates a PDF representation of current photobook. Two PDFs for cover and pages are provided as a URL.
    /// Note that those get generated asynchronously on the server and when the server returns 200 the process might still fail, affecting the placement of orders using them
    ///
    /// - Parameters:
    ///   - photobook: Photobook product to use for creating the PDF
    ///   - completionHandler: Closure to be called with PDF URLs if successful, or an error if it fails
    func createPdf(withPhotobook photobook: PhotobookProduct, completionHandler: @escaping (_ urls: [String]?, _ error: Error?) -> Void) {
        apiClient.post(context: .photobook, endpoint: "ios/generate_pdf", parameters: photobook.pdfParameters(), headers: headers) { (response, error) in
            guard let response = response as? [String:Any], let coverUrl = response["coverUrl"] as? String, let insideUrl = response["insideUrl"] as? String else {
                completionHandler(nil, error)
                return
            }
            print(insideUrl)
            completionHandler([coverUrl, insideUrl], nil)
        }
    }
    
}
