import SwiftUI
import UIKit

/// Observe drags across the real navigation bar, including its empty space.
/// A SwiftUI gesture on the title alone can lose the drag to UIKit's sheet pan
/// while a text field owns the keyboard. The observer never cancels other touches.
struct OrderDismissTitle:UIViewRepresentable{
    var enabled:Bool
    var onDismiss:@MainActor ()->Void

    func makeCoordinator()->Coordinator{Coordinator()}
    func makeUIView(context:Context)->TitleLabel{
        let label=TitleLabel();label.text="模擬下單"
        label.font = .preferredFont(forTextStyle:.headline)
        label.adjustsFontForContentSizeCategory=true;label.textAlignment = .center
        label.isAccessibilityElement=true;label.accessibilityHint="向下拖曳可取消尚未送出的委託"
        label.hierarchyChanged={ [weak coordinator=context.coordinator] view in coordinator?.attach(from:view) }
        return label
    }
    func updateUIView(_ view:TitleLabel,context:Context){
        context.coordinator.onDismiss=onDismiss
        context.coordinator.pan.isEnabled=enabled
        context.coordinator.attach(from:view)
    }
    static func dismantleUIView(_ view:TitleLabel,coordinator:Coordinator){
        view.hierarchyChanged=nil;coordinator.detach();coordinator.onDismiss=nil
    }
    @MainActor final class TitleLabel:UILabel{
        var hierarchyChanged:((UIView)->Void)?
        override func didMoveToWindow(){super.didMoveToWindow();hierarchyChanged?(self)}
        override func didMoveToSuperview(){super.didMoveToSuperview();hierarchyChanged?(self)}
        override func layoutSubviews(){super.layoutSubviews();hierarchyChanged?(self)}
    }
    @MainActor final class Coordinator:NSObject,UIGestureRecognizerDelegate{
        weak var navigationBar:UINavigationBar?
        var onDismiss:(@MainActor ()->Void)?
        private var requested=false
        lazy var pan:UIPanGestureRecognizer={
            let recognizer=UIPanGestureRecognizer(target:self,action:#selector(dragged(_:)))
            recognizer.delegate=self;recognizer.maximumNumberOfTouches=1
            recognizer.cancelsTouchesInView=false
            recognizer.delaysTouchesBegan=false;recognizer.delaysTouchesEnded=false
            return recognizer
        }()
        func attach(from view:UIView){
            guard view.window != nil else{detach();return}
            var ancestor=view.superview
            while let current=ancestor{
                if let bar=current as? UINavigationBar{
                    guard navigationBar !== bar else{return}
                    detach();navigationBar=bar;bar.addGestureRecognizer(pan);return
                }
                ancestor=current.superview
            }
        }
        func detach(){navigationBar?.removeGestureRecognizer(pan);navigationBar=nil;requested=false}
        func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldRecognizeSimultaneouslyWith otherGestureRecognizer:UIGestureRecognizer)->Bool{true}
        @objc private func dragged(_ recognizer:UIPanGestureRecognizer){
            if recognizer.state == .began{requested=false}
            guard !requested,recognizer.isEnabled,recognizer.state == .changed || recognizer.state == .ended else{return}
            let distance=recognizer.translation(in:navigationBar)
            guard distance.y>=24,abs(distance.x)<distance.y else{return}
            requested=true;onDismiss?()
        }
    }
}
