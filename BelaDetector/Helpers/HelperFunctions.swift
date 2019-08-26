//
//  HelperFunctions.swift
//  BelaDetector
//
//  Created by Dominik Cubelic on 03/08/2019.
//  Copyright © 2019 Dominik Cubelic. All rights reserved.
//

import Accelerate
import CoreML
import Foundation
import UIKit

//swiftlint:disable comma
let anchors: [[Float]] = [[116,90,  156,198,  373,326], [30,61,  62,45,  59,119], [10,13,  16,30,  33,23]]

public func sigmoid(_ x: Float) -> Float {
    return 1 / (1 + exp(-x))
}

public func softmax(_ x: [Float]) -> [Float] {
    var x = x
    let len = vDSP_Length(x.count)
    
    // Find the maximum value in the input array.
    var max: Float = 0
    vDSP_maxv(x, 1, &max, len)
    
    // Subtract the maximum from all the elements in the array.
    // Now the highest value in the array is 0.
    max = -max
    vDSP_vsadd(x, 1, &max, &x, 1, len)
    
    // Exponentiate all the elements in the array.
    var count = Int32(x.count)
    vvexpf(&x, x, &count)
    
    // Compute the sum of all exponentiated values.
    var sum: Float = 0
    vDSP_sve(x, 1, &sum, len)
    
    // Divide each element by the sum. This normalizes the array contents
    // so that they all add up to 1.
    vDSP_vsdiv(x, 1, &sum, &x, 1, len)
    
    return x
}

extension Array where Element: Comparable {
    /**
     Returns the index and value of the largest element in the array.
     */
    public func argmax() -> (Int, Element) {
        precondition(!self.isEmpty)
        var maxIndex = 0
        var maxValue = self[0]
        for i in 1..<self.count where self[i] > maxValue {
            maxValue = self[i]
            maxIndex = i
        }

        return (maxIndex, maxValue)
    }
}

func buffer(from image: UIImage) -> CVPixelBuffer? {
    let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
    var pxBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(image.size.width), Int(image.size.height), kCVPixelFormatType_32ARGB, attrs, &pxBuffer)
    guard status == kCVReturnSuccess, let pixelBuffer = pxBuffer else {
        return nil
    }
    
    CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
    let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
    
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: pixelData, width: Int(image.size.width), height: Int(image.size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
    
    context.translateBy(x: 0, y: image.size.height)
    context.scaleBy(x: 1.0, y: -1.0)
    
    UIGraphicsPushContext(context)
    image.draw(in: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
    UIGraphicsPopContext()
    CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
    
    return pixelBuffer
}

func nonMaxSuppression(boxes: [BelaPrediction], limit: Int, threshold: Float) -> [BelaPrediction] {
    
    // Do an argsort on the confidence scores, from high to low.
    let sortedIndices = boxes.indices.sorted { boxes[$0].confidence > boxes[$1].confidence }
    
    var selected: [BelaPrediction] = []
    var active = [Bool](repeating: true, count: boxes.count)
    var numActive = active.count
    
    // The algorithm is simple: Start with the box that has the highest score.
    // Remove any remaining boxes that overlap it more than the given threshold
    // amount. If there are any boxes left (i.e. these did not overlap with any
    // previous boxes), then repeat this procedure, until no more boxes remain
    // or the limit has been reached.
    outer: for i in 0 ..< boxes.count where active[i] {
        let boxA = boxes[sortedIndices[i]]
        
        selected.append(boxA)
        if selected.count >= limit { break }
        
        for j in i + 1 ..< boxes.count where active[j] {
            let boxB = boxes[sortedIndices[j]]
            if IOU(a: boxA.rect, b: boxB.rect) > threshold {
                active[j] = false
                numActive -= 1
                if numActive <= 0 { break outer }
            }
        }
    }
    
    return selected
}

/**
 Computes intersection-over-union overlap between two bounding boxes.
 */
public func IOU(a: CGRect, b: CGRect) -> Float {
    let areaA = a.width * a.height
    if areaA <= 0 { return 0 }
    
    let areaB = b.width * b.height
    if areaB <= 0 { return 0 }
    
    let intersectionMinX = max(a.minX, b.minX)
    let intersectionMinY = max(a.minY, b.minY)
    let intersectionMaxX = min(a.maxX, b.maxX)
    let intersectionMaxY = min(a.maxY, b.maxY)
    let intersectionArea = max(intersectionMaxY - intersectionMinY, 0) *
        max(intersectionMaxX - intersectionMinX, 0)
    
    return Float(intersectionArea / (areaA + areaB - intersectionArea))
}
