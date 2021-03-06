//: A Cocoa based Playground to experiment with crowd prediction

import AppKit
import Cartography
import CrowdCountApiMac
import PlaygroundSupport
import Promises

let nibFile = NSNib.Name("MyView")
var topLevelObjects: NSArray?

Bundle.main.loadNibNamed(nibFile, owner: nil, topLevelObjects: &topLevelObjects)

let views = (topLevelObjects as! [Any]).filter { $0 is NSView }
let topView = views[0] as! NSView

// Hardcoded to match MyView.xib
let stackView = topView.subviews[0] as! NSStackView
let imageWell = stackView.subviews[1] as! NSImageView
let predictionLabel = stackView.subviews[2] as! NSTextField

typealias ObserverCallback = (NSImage) -> Void
class ImageObserver: NSObject {
    var callback: ObserverCallback
    init(_ callback: @escaping ObserverCallback) {
        self.callback = callback
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        let newImage = change![NSKeyValueChangeKey.newKey] as! NSImage
        self.callback(newImage)
    }
}

func nslabel(_ label: String) -> NSTextField { return NSTextField(labelWithString: label) }

func nsimage(_ prediction: FriendlyPrediction) -> NSView {
    var image: NSImage?
    Duration.measure("multiarray to grayscale") {
        image = prediction.densityMap.copy().normalize().image(offset: 0, scale: 255)
        drawBoundingBoxes(image!, prediction.boundingBoxes)
    }

    return NSImageView(image: image!.flipVertically())
}

func drawBoundingBoxes(_ image: NSImage, _ boundingBoxes: [CGRect]) {
    // Map the bounding boxes to density map dimensions 225 x 168
    let xfactor = CGFloat(FriendlyPredictor.DensityMapWidth)
    let yfactor = CGFloat(FriendlyPredictor.DensityMapHeight)
    image.lockFocus()
    NSColor.white.set()
    for bb in boundingBoxes {
        let rect = NSRect(x: bb.minX * xfactor, y: bb.minY*yfactor, width: (bb.maxX-bb.minX)*xfactor, height: (bb.maxY-bb.minY)*yfactor)
        __NSFrameRectWithWidth(rect, 2)
    }
    image.unlockFocus()
}

func generatePredictionGrid(_ predictions: [FriendlyPrediction]) -> NSGridView {
    let headers: [[NSView]] = [[nslabel("Strategy"), nslabel("Duration (s)"), nslabel("Count")]]
    let labels = predictions.map { prediction -> [NSView] in
        let label = nslabel(prediction.name)
        let duration = nslabel(String.init(format: "%f", prediction.duration))
        let count = nslabel(String.init(format: "%f", prediction.count))
        return [label, duration, count]
    }

    let images = predictions.map { prediction -> [NSView] in
        print("mounting image for...", prediction.name)
        return [nsimage(prediction)]
    }

    let zipped = zip(labels, images)
    let reduced: [[NSView]] = zipped.reduce([[NSView]]()) { acc, entry in
        acc + [entry.0, entry.1]    // convert from tuples to array
    }

    let gridView = NSGridView(views: headers + reduced)
    gridView.translatesAutoresizingMaskIntoConstraints = false
    gridView.setContentHuggingPriority(NSLayoutConstraint.Priority(600), for: .horizontal)
    gridView.setContentHuggingPriority(NSLayoutConstraint.Priority(600), for: .vertical)

    stackView.addArrangedSubview(gridView)
    constrain(gridView) { gv in
        align(leading: gv, gv.superview!)
        align(trailing: gv, gv.superview!)
        gv.height >= 600
    }
    return gridView
}

func generateClassificationGrid(_ classification: FriendlyClassification) -> NSGridView {
    predictionLabel.stringValue = "Winning Classification: " + classification.classification
    print("Probabilities", classification.probabilities)
    let labels: [[NSView]] = classification.probabilities.map { tuple -> [NSView] in
        let (key, value) = tuple
        return [NSTextField(labelWithString: key), NSTextField(labelWithString: String.init(reflecting: value))]
    }
    let gridView = NSGridView(views: labels)
    gridView.translatesAutoresizingMaskIntoConstraints = false
    gridView.setContentHuggingPriority(NSLayoutConstraint.Priority(600), for: .horizontal)
    gridView.setContentHuggingPriority(NSLayoutConstraint.Priority(600), for: .vertical)

    stackView.addArrangedSubview(gridView)
    constrain(gridView) { gv in
        align(leading: gv, gv.superview!)
        align(trailing: gv, gv.superview!)
    }
    return gridView
}

func removeFromPlayground(_ view: NSView?) {
    if view != nil {
        stackView.removeArrangedSubview(view!)
        view!.removeFromSuperview()
    }
}

var predictionGrid: NSGridView?, classificationGrid: NSGridView?
let predictor = FriendlyPredictor()
let observer = ImageObserver({ image in
    predictionLabel.stringValue = "Predicting..."
    removeFromPlayground(predictionGrid)
    removeFromPlayground(classificationGrid)

    all(
        predictor.predictAllPromise(image: image, on: .global()),
        predictor.classifyPromise(image: image, on: .global())
    ).then(on: .main) { predictions, classification in
        classificationGrid = generateClassificationGrid(classification)
        predictionGrid = generatePredictionGrid(predictions)
        topView.updateConstraintsForSubtreeIfNeeded()
    }
})

imageWell.addObserver(observer, forKeyPath: "image", options: NSKeyValueObservingOptions.new, context: nil)

// Present the view in Playground
PlaygroundPage.current.liveView = topView
