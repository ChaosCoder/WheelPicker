//
//  WheelPicker.swift
//  WheelPicker
//
//  Created by tokiensis on 2022/01/10.
//  Copyright © 2022 Wataku-City. All rights reserved.
//

import SwiftUI

public struct WheelPicker<DataSource: WheelPickerDataSource, Label: View>: View {
    public var selection: Binding<DataSource.T>
    public var dataSource: DataSource
    @ViewBuilder public var label: (DataSource.T?) -> Label
    
    @State private var translationHeight: CGFloat = .zero
    @State private var selectionOffset: Int = 0
    @State private var draggingStartOffset: Int?
    @State private var draggingStartTranslationHeight: CGFloat = .zero
    @State private var timer: Timer?
    @State private var timerRepeatCount = 0
    @State private var timerUpdateCount = 0
    @State private var firstDragGestureValue: DragGesture.Value?
    @State private var lastDragGestureValue: DragGesture.Value?
    @State private var lastDigreesTranslation: CGFloat = .zero
    @State private var lastFeedbackOffset = 0
    @State private var isFeedbackEnabled = false
    @State private var feedbackManager = FeedbackManager()
    private let height: CGFloat
    private let fontSize: CGFloat
    private let itemsPerWheelFront: Int
    private let frameLate: Double = 120
    
    public init(selection: Binding<DataSource.T>, dataSource: DataSource, itemHeight: CGFloat = 22, itemsPerWheelFront: Int = 9, @ViewBuilder label: @escaping (DataSource.T?) -> Label) {
        self.selection = selection
        self.dataSource = dataSource
        self.label = label
        self.fontSize = itemHeight
        self.itemsPerWheelFront = itemsPerWheelFront
        self.height = CGFloat(itemsPerWheelFront) * fontSize * 0.6
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<itemsPerWheelFront, id: \.self) { index in
                label(item(at: index, translationHeight: translationHeight))
                    .font(.system(size: fontSize))
                    .opacity(opacity(at: index, translationHeight: translationHeight))
                    .rotation3DEffect(
                        .degrees(rotationDigrees(at: index, translationHeight: translationHeight)),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: .center,
                        anchorZ: 15,
                        perspective: 0
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: itemHeight(at: index, translationHeight: translationHeight))
                    .onTapGesture {
                        guard translationHeight == .zero,
                              let item = item(at: index, translationHeight: .zero),
                              selection.wrappedValue != item else { return }
                        isFeedbackEnabled = false
                        selection.wrappedValue = item
                    }
            }
        }
        .offset(x: 0, y: itemsHeightDifference(translationHeight: translationHeight) * (translationHeight > 0 ? 2.0 : -2.0))
        .frame(height: height)
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if timer?.isValid ?? false {
                        timer?.invalidate()
                        self.timer = nil
                        translationHeight = translationHeight.truncatingRemainder(dividingBy: truncatingRemainder)
                        draggingStartOffset = selectionOffset
                        draggingStartTranslationHeight = translationHeight
                        return
                    }
                    if translationHeight == .zero {
                        draggingStartOffset = selectionOffset
                        draggingStartTranslationHeight = .zero
                        firstDragGestureValue = value
                    }
                    isFeedbackEnabled = true
                    lastDragGestureValue = value
                    translationHeight = reduce(translationHeight: value.translation.height)
                    updateSelection(from: translationHeight)
                }
                .onEnded { value in
                    guard let firstGestureValue = firstDragGestureValue,
                          let lastGestureValue = lastDragGestureValue else {
                        draggingStartOffset = nil
                        translationHeight = .zero
                        return
                    }
                    let initialTranslation = translationHeight
                    let timeFromFirstGesture = value.time.timeIntervalSince(firstGestureValue.time)
                    let timeFromLastGesture = value.time.timeIntervalSince(lastGestureValue.time)
                    let translationDiffernce = reduce(translationHeight:value.translation.height - lastGestureValue.translation.height)
                    let reducedPredictedEndTranslation = reduce(translationHeight: value.predictedEndTranslation.height)

                    let isInertialRotation = timeFromFirstGesture < 0.1 || (timeFromFirstGesture < 0.15 && reducedPredictedEndTranslation > height)
                    let isMinimumRotation = (abs(reducedPredictedEndTranslation) < height * 2 && abs(translationDiffernce) < 2.0) || abs(reducedPredictedEndTranslation) < height * 1.5 || timeFromLastGesture > 0.01

                    var animatingTranslation: CGFloat = .zero
                    if !isInertialRotation && isMinimumRotation {
                        let translationFromCurrentSelection = initialTranslation.truncatingRemainder(dividingBy: wheelStopResolution)
                        if translationFromCurrentSelection == 0 {
                            animatingTranslation = 0
                        } else if abs(translationFromCurrentSelection) < wheelStopResolution / 2 {
                            animatingTranslation = -translationFromCurrentSelection
                        } else {
                            animatingTranslation = (wheelStopResolution - abs(translationFromCurrentSelection)) * (translationFromCurrentSelection > 0 ? 1 : -1)
                        }
                    } else {
                        let maxAnimatingTranslation = height * 3
                        let endTranslation = value.predictedEndTranslation.height + draggingStartTranslationHeight
                        let adjustedEndTranslation = round(endTranslation / wheelStopResolution) * wheelStopResolution
                        animatingTranslation = min(max(adjustedEndTranslation - initialTranslation, -maxAnimatingTranslation), maxAnimatingTranslation)
                    }
                    animate(animatingTranslation: animatingTranslation, decelerationFrames: 120)
                }
        )
        .onChange(of: selection.wrappedValue) { value in
            if timer?.isValid ?? false {
                timer?.invalidate()
                timer = nil
                translationHeight = translationHeight.truncatingRemainder(dividingBy: truncatingRemainder)
                draggingStartTranslationHeight = translationHeight
            } else {
                draggingStartTranslationHeight = .zero
            }
            let translationOffset = dataSource.translationOffset(to: value, origin: selectionOffset)
            guard translationOffset != 0 else { return }
            let translationHeight = -CGFloat(translationOffset) * wheelStopResolution - draggingStartTranslationHeight
            draggingStartOffset = selectionOffset
            animate(animatingTranslation: translationHeight, decelerationFrames: 60)
        }
    }
}

private extension WheelPicker {
    func item(at index: Int, translationHeight: CGFloat) -> DataSource.T? {
        let itemOffset: Int
        let offset = index - Int(Double(itemsPerWheelFront) / 2.0)
        itemOffset = selectionOffset + offset
        return dataSource.item(at: itemOffset)
    }
    
    var wheelStopResolution: Double {
        Double(height) / Double(itemsPerWheelFront - 1)
    }
    
    func degrees(_ index: Int) -> Double {
        (Double(index) * truncatingRemainder) - 90 // -90 ~ 90
    }
    
    var truncatingRemainder: Double {
        180.0 / Double(itemsPerWheelFront - 1)
    }
    
    func rotationDigrees(at index: Int, translationHeight: CGFloat) -> Double {
        let digrees = degrees(index)
        let offset = digreesTranslation(from: translationHeight).truncatingRemainder(dividingBy: truncatingRemainder)
        return (360 + digrees + offset).truncatingRemainder(dividingBy: 360)
    }
    
    func itemHeight(at index: Int, translationHeight: CGFloat) -> CGFloat {
        let digrees = degrees(index)
        let offset = digreesTranslation(from: translationHeight).truncatingRemainder(dividingBy: truncatingRemainder)
        let ratio = (90 - abs(digrees + offset)) / 90
        return max(fontSize * CGFloat(ratio), 0)
    }
    
    func opacity(at index: Int, translationHeight: CGFloat) -> Double {
        let digrees = degrees(index)
        let offset = digreesTranslation(from: translationHeight).truncatingRemainder(dividingBy: truncatingRemainder)
        let translatedDigrees = abs(digrees + offset)
        if translatedDigrees < 20 {
            return (translatedDigrees / -40) + 1
        } else {
            return (90 - translatedDigrees) / 140
        }
    }
    
    func digreesTranslation(from translationHeight: CGFloat) -> Double {
        let translation = Double(translationHeight / height) * 180
        return dataSource.limitDigreesTranslation(translation, draggingStartOffset: draggingStartOffset)
    }
    
    // 回転中にitemの高さが減少するので、回転体全体の高さが変わらないように差分を加えて補正する
    func itemsHeightDifference(translationHeight: CGFloat) -> CGFloat {
        let defaultItemsHeight = (0..<itemsPerWheelFront).reduce(.zero) {
            $0 + itemHeight(at: $1, translationHeight: 0)
        }
        let itemsHeight = (0..<itemsPerWheelFront).reduce(.zero) {
            $0 + itemHeight(at: $1, translationHeight: translationHeight)
        }
        return defaultItemsHeight - itemsHeight
    }
    
    func reduce(translationHeight: CGFloat) -> CGFloat {
        translationHeight * 0.6 + draggingStartTranslationHeight
    }
    
    func updateSelection(from translationHeight: Double, round rnd: Bool = false) {
        let digreesOffset = digreesTranslation(from: translationHeight)
        if let draggingStartOffset = draggingStartOffset {
            let indexOffset: Int
            if rnd {
                indexOffset = -Int(round(digreesOffset / truncatingRemainder))
            } else {
                indexOffset = -Int(digreesOffset / truncatingRemainder)
            }
            let newSelectionOffset = draggingStartOffset + indexOffset
            let digreesDifference = abs(lastDigreesTranslation - digreesOffset)
            let remainder = abs(digreesOffset.truncatingRemainder(dividingBy: truncatingRemainder))
            let isFeedbackAllowed = digreesDifference > 0.8 || remainder < 1.0 || remainder > 17.0
            if isFeedbackEnabled, newSelectionOffset != lastFeedbackOffset, isFeedbackAllowed {
                feedbackManager.generateFeedback()
                lastFeedbackOffset = newSelectionOffset
            }
            lastDigreesTranslation = digreesOffset
            selectionOffset = newSelectionOffset
        }
    }
    
    func updateSelectionBinding() {
        guard let newSelectionItem = dataSource.item(at: selectionOffset) else { return }
        selection.wrappedValue = newSelectionItem
    }
    
    func animate(animatingTranslation: CGFloat, decelerationFrames: Double) {
        guard animatingTranslation != 0 else {
            draggingStartOffset = nil
            translationHeight = .zero
            return
        }
        let deceleration = -max(abs(animatingTranslation), height) / CGFloat(decelerationFrames * decelerationFrames)
        let decelerateFrames = Int(round(sqrt(abs(animatingTranslation / -deceleration))))
        let initialSpeed = -deceleration * CGFloat(decelerateFrames)

        let maxTranslationLimit = dataSource.maxTranslation(draggingStartOffset: draggingStartOffset)
        let minTranslationLimit = dataSource.minTranslation(draggingStartOffset: draggingStartOffset)
        let translationRange = minTranslationLimit...maxTranslationLimit

        guard initialSpeed != 0 else {
            draggingStartOffset = nil
            translationHeight = .zero
            return
        }
        timerRepeatCount = decelerateFrames + abs(Int(round(animatingTranslation / initialSpeed) / 2))
        timerUpdateCount = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1 / frameLate, repeats: true) { timer in
            guard timerUpdateCount < timerRepeatCount, translationRange.contains(translationHeight) else {
                timer.invalidate()
                self.timer = nil
                updateSelection(from: translationHeight, round: true)
                updateSelectionBinding()
                draggingStartOffset = nil
                translationHeight = .zero
                isFeedbackEnabled = false
                return
            }
            let remainingFrames = timerRepeatCount - timerUpdateCount
            if remainingFrames > decelerateFrames {
                translationHeight += CGFloat(initialSpeed) * (animatingTranslation > 0 ? 1 : -1)
            } else {
                let deceleratedCount = decelerateFrames - remainingFrames + 1
                let prevDeceleratedCount = max(deceleratedCount - 1, 0)
                let translation = initialSpeed * CGFloat(deceleratedCount) + ((deceleration * pow(CGFloat(deceleratedCount), 2)) / 2)
                let prevFrameTranslation = initialSpeed * CGFloat(prevDeceleratedCount) + ((deceleration * pow(CGFloat(prevDeceleratedCount), 2)) / 2)
                translationHeight += (translation - prevFrameTranslation) * (animatingTranslation > 0 ? 1 : -1)
            }
            updateSelection(from: translationHeight)
            timerUpdateCount += 1
        }
    }
}
