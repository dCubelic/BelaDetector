//
//  ViewController.swift
//  BelaDetector
//
//  Created by Dominik Cubelic on 03/08/2019.
//  Copyright © 2019 Dominik Cubelic. All rights reserved.
//

import CoreMedia
import UIKit

public protocol BelaDetectorViewControllerDelegate: class {
    func belaDetectorViewControllerDidFinishScanning(_ belaDetectorViewController: BelaDetectorViewController, points: Int)
}

public class BelaDetectorViewController: UIViewController {
    
    @IBOutlet private weak var videoPreview: UIView!
    @IBOutlet private weak var detectedCardsView: DetectedCardsView!
    @IBOutlet private weak var closeButton: UIButton!
    @IBOutlet private weak var resetButton: UIButton!
    @IBOutlet private weak var doneButton: UIButton!
    @IBOutlet private weak var plusTenButton: UIButton!
    @IBOutlet private weak var betaView: UIView!
    @IBOutlet private weak var flashlightButton: UIButton!
    
    private var resizedPixelBufffer: CVPixelBuffer?
    private let ciContext = CIContext()
    private let videoCapture = VideoCapture()
    private let semaphore = DispatchSemaphore(value: 2)
    private let detectorModel = BelaModel()
    private var cardSet: Set<BelaCard> = Set()
    private var resilienceArray = ResilienceArray<BelaCard>(size: 7)
    private var trumpSuitPicker: TrumpSuitPickerViewController?
    private var flashOn = false {
        didSet {
            flashlightButton.setImage(UIImage(named: flashOn ? "flashlight-on" : "flashlight-off", in: Bundle.frameworkBundle, compatibleWith: nil), for: .normal)
        }
    }
    
    public weak var delegate: BelaDetectorViewControllerDelegate?
    
    override public var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    public static func instantiateFromStoryboard() -> BelaDetectorViewController {
        return UIStoryboard.main.instantiateViewController(ofType: BelaDetectorViewController.self)
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        closeButton.layer.cornerRadius = closeButton.frame.height / 2
        resetButton.layer.cornerRadius = resetButton.frame.height / 2
        doneButton.layer.cornerRadius = doneButton.frame.height / 2
        plusTenButton.layer.cornerRadius = plusTenButton.frame.height / 2
        betaView.layer.cornerRadius = betaView.frame.height / 2
        flashlightButton.layer.cornerRadius = flashlightButton.frame.height / 2
        
        detectedCardsView.delegate = self
        detectedCardsView.set(trumpSuit: .hearts)
        
        // For Fastlane screenshots
        #if targetEnvironment(simulator)
        let imageView = UIImageView(frame: view.bounds)
        imageView.image = UIImage(named: "mock", in: Bundle.frameworkBundle, compatibleWith: nil)
        imageView.contentMode = .scaleAspectFill
        videoPreview.addSubview(imageView)
        detectedCardsView.reset()
        for card in [BelaCard.queenOfClubs, .nineOfSpades, .aceOfClubs, .kingOfHearts, .sevenOfClubs, .queenOfHearts, .nineOfDiamonds, .eightOfDiamonds] {
            detectedCardsView.add(card: card)
        }
        detectedCardsView.set(trumpSuit: .spades)
        #else
        setupCamera()
        showTrumpSuitPicker()
        #endif
        
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        videoCapture.stop()
    }
    
    override public func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        resizePreviewLayer()
    }
    
    private func setupCamera() {
        CVPixelBufferCreate(nil, BelaModel.width, BelaModel.height, kCVPixelFormatType_32BGRA, nil, &resizedPixelBufffer)
        
        videoCapture.delegate = self
        videoCapture.fps = 50
        videoCapture.setup(sessionPreset: .hd1280x720) { success in
            if success {
                if let previewLayer = self.videoCapture.previewLayer {
                    self.videoPreview.layer.addSublayer(previewLayer)
                    self.resizePreviewLayer()
                }
                
                self.videoCapture.start()
            }
        }
    }
    
    private func resizePreviewLayer() {
        videoCapture.previewLayer?.frame = videoPreview.bounds
    }
    
    private func predict(pixelBuffer: CVPixelBuffer) {
        guard let resizedPixelBuffer = resizedPixelBufffer else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let sx = CGFloat(BelaModel.width) / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let sy = CGFloat(BelaModel.height) / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let scaleTransform = CGAffineTransform(scaleX: sx, y: sy)
        let scaledImage = ciImage.transformed(by: scaleTransform)
        
        ciContext.render(scaledImage, to: resizedPixelBuffer)
        
        let predictions = detectorModel.predict(image: resizedPixelBuffer)

        resilienceArray.add(items: predictions.map { $0.card })

        for prediction in predictions {
            if resilienceArray.numberOfOccurences(item: prediction.card) >= 5 { // if recognized correctly
                let (inserted, _) = cardSet.insert(prediction.card)
                if inserted { // if seen first time
                    detectedCardsView.add(card: prediction.card)
                }
            }
        }
        
        semaphore.signal()
    }
    
    private func calculateScore(cards: Set<BelaCard>, trumpSuit: BelaSuit) -> Int {
        var score = 0
        for card in cards {
            score += card.points(trumpSuit: trumpSuit)
        }
        return score
    }

    @IBAction private func closeAction(_ sender: Any) {
        videoCapture.turnTorch(on: false)
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction private func resetAction(_ sender: Any) {
        cardSet.removeAll(keepingCapacity: true)
        plusTenButton.setTitle("+10", for: .normal)
        detectedCardsView.reset()
        showTrumpSuitPicker()
    }
    
    @IBAction private func doneAction(_ sender: Any) {
        videoCapture.turnTorch(on: false)
        delegate?.belaDetectorViewControllerDidFinishScanning(self, points: detectedCardsView.points)
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction private func plusTenAction(_ sender: Any) {
        detectedCardsView.plusTen.toggle()
        plusTenButton.setTitle(detectedCardsView.plusTen ? "-10" : "+10", for: .normal)
    }
    
    @IBAction private func flashlightAction(_ sender: Any) {
        flashOn.toggle()
        videoCapture.turnTorch(on: flashOn)
    }
}

extension BelaDetectorViewController: VideoCaptureDelegate {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        guard let pixelBuffer = pixelBuffer else { return }
        
        semaphore.wait()
        
        DispatchQueue.global().async {
            self.predict(pixelBuffer: pixelBuffer)
        }
    }
}

extension BelaDetectorViewController: DetectedCardsViewDelegate {
    private func removeTrumpSuitPicker() {
        trumpSuitPicker?.view.removeFromSuperview()
        trumpSuitPicker?.removeFromParent()
        trumpSuitPicker?.didMove(toParent: nil)
        
        trumpSuitPicker = nil
    }
    
    private func showTrumpSuitPicker() {
        guard trumpSuitPicker == nil else { return }
        
        let vc = UIStoryboard.main.instantiateViewController(ofType: TrumpSuitPickerViewController.self)
        vc.delegate = self
        trumpSuitPicker = vc
        
        addChild(vc)
        view.addSubview(vc.view)
        vc.didMove(toParent: self)
        
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        vc.view.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        vc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32).isActive = true
        vc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32).isActive = true
    }
    
    func detectedCardsViewDidRequestTrumpSuitChange(_ detectedCardsView: DetectedCardsView) {
        if trumpSuitPicker != nil {
            removeTrumpSuitPicker()
            return
        }
        
        showTrumpSuitPicker()
    }
    
    func detectedCardsViewDidRemoveCard(_ card: BelaCard) {
        cardSet.remove(card)
    }
}

extension BelaDetectorViewController: TrumpSuitPickerViewControllerDelegate {
    func trumpSuitPickerViewControllerDidChoose(trumpSuitPickerViewController: TrumpSuitPickerViewController, trumpSuit: BelaSuit) {
        detectedCardsView.set(trumpSuit: trumpSuit)

        removeTrumpSuitPicker()
    }
}
