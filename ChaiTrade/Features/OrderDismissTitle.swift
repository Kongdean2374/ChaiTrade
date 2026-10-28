import SwiftUI
import UIKit

/// Own the observer from the order content's controller, rather than a toolbar
/// title whose SwiftUI hosting view may live outside UINavigationBar's subtree.
struct OrderNavigationDismissObserver:UIViewControllerRepresentable{
    @EnvironmentObject private var model:AppModel
    var enabled:Bool
    var onDismiss:@MainActor ()->Void

    func makeUIViewController(context:Context)->Controller{Controller()}
    func updateUIViewController(_ controller:Controller,context:Context){
        controller.onDismiss=onDismiss
        #if DEBUG
        controller.onDiagnostic={message in
            guard UITestSupport.session != nil,model.uiTestOrderDismissDiagnostics.last != message else{return}
            model.uiTestOrderDismissDiagnostics=Array((model.uiTestOrderDismissDiagnostics+[message]).suffix(20))
        }
        #endif
        controller.update(enabled:enabled)
    }
    static func dismantleUIViewController(_ controller:Controller,coordinator:()){
        controller.detach();controller.onDismiss=nil
        #if DEBUG
        controller.onDiagnostic=nil
        #endif
    }
    @MainActor final class Controller:UIViewController,UIGestureRecognizerDelegate{
        private weak var navigationBar:UINavigationBar?
        private weak var gestureHost:UIView?
        private var enabled=false
        private var requested=false
        var onDismiss:(@MainActor ()->Void)?
        #if DEBUG
        var onDiagnostic:((String)->Void)?
        #endif
        private lazy var pan:UIPanGestureRecognizer={
            let recognizer=UIPanGestureRecognizer(target:self,action:#selector(dragged(_:)))
            recognizer.delegate=self;recognizer.maximumNumberOfTouches=1
            recognizer.cancelsTouchesInView=false
            recognizer.delaysTouchesBegan=false;recognizer.delaysTouchesEnded=false
            return recognizer
        }()
        override func loadView(){let anchor=UIView();anchor.backgroundColor = .clear;anchor.isUserInteractionEnabled=false;view=anchor}
        override func didMove(toParent parent:UIViewController?){super.didMove(toParent:parent);attach()}
        override func viewDidAppear(_ animated:Bool){super.viewDidAppear(animated);attach()}
        override func viewDidLayoutSubviews(){super.viewDidLayoutSubviews();attach()}
        override func viewWillDisappear(_ animated:Bool){detach();super.viewWillDisappear(animated)}
        func update(enabled:Bool){
            self.enabled=enabled
            if pan.isEnabled != enabled{pan.isEnabled=enabled}
            attach()
        }
        private func attach(){
            guard isViewLoaded,view.window != nil else{return}
            guard let owner=navigationController else{record("waiting for order navigation controller");return}
            let bar=owner.navigationBar;let host:UIView=owner.view
            guard bar.window === view.window else{return}
            guard gestureHost !== host || navigationBar !== bar else{return}
            detach();navigationBar=bar;gestureHost=host;host.addGestureRecognizer(pan)
            record("attached to order navigation controller")
        }
        func detach(){gestureHost?.removeGestureRecognizer(pan);gestureHost=nil;navigationBar=nil;requested=false}
        func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldReceive touch:UITouch)->Bool{
            guard enabled,let host=gestureHost,let bar=navigationBar,!bar.isHidden else{return false}
            // Observe through the controller's common ancestor, but only accept
            // gestures beginning in the visible navigation bar. Form scrolling,
            // keyboard input and ordinary buttons keep their native behavior.
            return bar.convert(bar.bounds,to:host).contains(touch.location(in:host))
        }
        func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldRecognizeSimultaneouslyWith otherGestureRecognizer:UIGestureRecognizer)->Bool{true}
        @objc private func dragged(_ recognizer:UIPanGestureRecognizer){
            if recognizer.state == .began{requested=false;record("navigation pan began")}
            guard enabled,!requested,recognizer.state == .changed || recognizer.state == .ended else{return}
            let distance=recognizer.translation(in:gestureHost)
            if distance.y>=24,abs(distance.x)<distance.y{
                requested=true;record("navigation pan requested cancel");onDismiss?()
            }else if recognizer.state == .ended{record("navigation pan ended without cancel: \(Int(distance.x)),\(Int(distance.y))")}
        }
        private func record(_ value:String){
            #if DEBUG
            onDiagnostic?(value)
            #endif
        }
    }
}
