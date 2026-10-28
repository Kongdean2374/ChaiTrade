import SwiftUI
import UIKit

/// UIKit owns the active edit buffer. Quote/list publications must never replace
/// characters that have arrived before SwiftUI's next binding reconciliation.
struct StableSearchField:UIViewRepresentable {
    @Binding var text:String
    @Binding var editing:Bool
    let prompt:String
    let identifier:String
    let doneTitle:String
    func makeCoordinator()->Coordinator{Coordinator(self)}
    func makeUIView(context:Context)->UITextField{
        let field=UITextField();field.delegate=context.coordinator
        field.autocapitalizationType = .none;field.autocorrectionType = .no
        field.returnKeyType = .search;field.clearButtonMode = .never
        field.accessibilityIdentifier=identifier
        field.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        field.setContentHuggingPriority(.required,for:.vertical)
        field.addTarget(context.coordinator,action:#selector(Coordinator.changed(_:)),for:.editingChanged)
        let toolbar=UIToolbar();toolbar.sizeToFit()
        toolbar.items=[UIBarButtonItem(barButtonSystemItem:.flexibleSpace,target:nil,action:nil),UIBarButtonItem(title:doneTitle,style:.done,target:context.coordinator,action:#selector(Coordinator.finish))]
        field.inputAccessoryView=toolbar;context.coordinator.field=field
        return field
    }
    func updateUIView(_ field:UITextField,context:Context){
        context.coordinator.parent=self;if field.placeholder != prompt{field.placeholder=prompt}
        let traits=UITraitCollection(preferredContentSizeCategory:contentSize(context.environment.dynamicTypeSize))
        let font=UIFont.preferredFont(forTextStyle:.body,compatibleWith:traits)
        if field.font != font{field.font=font}
        field.textColor = .label
        if !editing,field.isFirstResponder{
            context.coordinator.synchronizing=true
            field.resignFirstResponder()
            context.coordinator.synchronizing=false
        }
        // Explicit clear/market changes end editing first. During an active edit,
        // neither a quote publication nor IME composition may rewrite UIKit text.
        if !field.isFirstResponder,field.markedTextRange==nil,field.text != text{field.text=text}
    }
    func sizeThatFits(_ proposal:ProposedViewSize,uiView:UITextField,context:Context)->CGSize?{
        CGSize(width:proposal.width ?? uiView.intrinsicContentSize.width,height:max(44,(uiView.font?.lineHeight ?? 20)+12))
    }
    private func contentSize(_ size:DynamicTypeSize)->UIContentSizeCategory{
        switch size{
        case .xSmall:return .extraSmall
        case .small:return .small
        case .medium:return .medium
        case .large:return .large
        case .xLarge:return .extraLarge
        case .xxLarge:return .extraExtraLarge
        case .xxxLarge:return .extraExtraExtraLarge
        case .accessibility1:return .accessibilityMedium
        case .accessibility2:return .accessibilityLarge
        case .accessibility3:return .accessibilityExtraLarge
        case .accessibility4:return .accessibilityExtraExtraLarge
        case .accessibility5:return .accessibilityExtraExtraExtraLarge
        @unknown default:return .large
        }
    }
    final class Coordinator:NSObject,UITextFieldDelegate {
        var parent:StableSearchField
        weak var field:UITextField?
        var synchronizing=false
        init(_ parent:StableSearchField){self.parent=parent}
        @objc func changed(_ field:UITextField){
            guard !synchronizing,field.markedTextRange==nil else{return}
            let value=field.text ?? "";if parent.text != value{parent.text=value}
        }
        func textFieldDidBeginEditing(_ textField:UITextField){if !parent.editing{parent.editing=true}}
        func textFieldDidEndEditing(_ textField:UITextField){
            changed(textField);if parent.editing{parent.editing=false}
        }
        func textFieldShouldReturn(_ textField:UITextField)->Bool{finish();return true}
        @objc func finish(){field?.resignFirstResponder();parent.editing=false}
    }
}
