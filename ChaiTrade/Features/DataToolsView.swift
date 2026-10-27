import SwiftUI
import ChaiTradeCore

struct DataToolsView:View{
    @EnvironmentObject var model:AppModel
    var body:some View{List{
        Section("匯出本機資料"){
            Button("匯出成交 CSV"){Task{await model.export(kind:"CSV")}}
            Button("匯出完整委託 CSV"){Task{await model.export(kind:"orders")}}
            Button("匯出資金帳本 CSV"){Task{await model.export(kind:"ledger")}}
            Button("匯出 JSON"){Task{await model.export(kind:"JSON")}}
            NavigationLink("資料備份／還原"){DataBackupView()}
        }
        Section{NavigationLink("帳務、交割與市場事件"){AccountingToolsView()}}
        Section("最近資金帳本"){
            ForEach(Array((model.state?.ledger ?? []).suffix(40).enumerated()),id:\.offset){_,entry in HStack{VStack(alignment:.leading){Text(entry.account).font(.caption);Text(entry.currency).font(.caption2).foregroundStyle(.secondary)};Spacer();Text(MarketText.number(entry.amount)).font(.caption.monospaced())}}
        }
    }.navigationTitle("資料工具")}
}
