import SwiftUI
import ChaiTradeCore

struct ChartAmendConfirm: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let intent: ChartAmendment
    var body: some View {
        Form{
            Text("拖曳只產生改單意圖，確認後才由本機引擎重新檢查資金、數量與級距。").font(.footnote)
            LabeledContent("商品",value:intent.order.request.instrumentID)
            LabeledContent("原價格",value:(intent.order.request.price ?? intent.order.request.trigger)?.description ?? "未提供")
            LabeledContent("新價格（已依商品最小跳動量化）",value:intent.price.description)
            Button("確認改單"){Task{guard let engine=model.engine,let context=model.context else{return};await model.run{
                try await engine.amend(id:intent.order.id,quantity:intent.order.request.quantity,price:intent.order.request.price == nil ? nil:intent.price,trigger:intent.order.request.price == nil ? intent.price:nil,time:model.now,context:context)
            };if model.error == nil{dismiss()}}}
        }.navigationTitle("圖表改單確認").toolbar{Button("取消"){dismiss()}}
    }
}
