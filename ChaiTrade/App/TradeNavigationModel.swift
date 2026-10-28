import SwiftUI
import ChaiTradeCore

struct TradeHandoff:Identifiable {
    let id=UUID()
    let product:TradeProduct
    let context:AccountContext
    let side:Side
    let openForm:Bool
    let board:TradingBoard
    let closingPosition:Position?
}
extension AppModel {
    var tradeInstrument:Instrument?{guard let product=tradeWorkspace?.product else{return nil};return state?.instruments.first{product.matches($0)}}
    func restoreTradeWorkspace(){
        tradeSaveTask?.cancel();tradeDirty=false;pendingTrade=nil;tradeFormRequest=nil;tradeClosingPosition=nil;tradeSession=UUID();marketPaths=[:]
        if let saved=state?.productPreferences?.tradeWorkspace{tradeWorkspace=saved}
        else if let i=selected,i.asset != .index,let context{tradeWorkspace=TradeWorkspace(accountID:context.accountID,instrument:i)}
        else{tradeWorkspace=nil}
    }
    func browseProduct(_ i:Instrument){
        if market != i.market{switchMarket(i.market)}
        tab=1
        if marketPaths[i.market]?.last != i.id{marketPaths[i.market,default:[]].append(i.id)}
        focusProduct(i)
        editBrowsing(i.market){value in value.selectedID=i.id;value.recent.removeAll{$0==i.id};value.recent.insert(i.id,at:0);value.recent=Array(value.recent.prefix(30))}
    }
    func requestTrade(_ i:Instrument,side:Side,openForm:Bool,board:TradingBoard?=nil,closingPosition:Position?=nil){
        guard let context,i.asset != .index else{return}
        let intent=TradeHandoff(product:TradeProduct(i),context:context,side:side,openForm:openForm,board:i.usesTaiwanBoards ? (board ?? .oddLot):.regular,closingPosition:closingPosition)
        if let saved=tradeWorkspace,saved.editor != nil,(saved.product != intent.product || saved.side != side || saved.board != intent.board || closingPosition != nil){pendingTrade=intent;return}
        applyTrade(intent)
    }
    func applyTrade(_ intent:TradeHandoff){
        guard context==intent.context,let i=state?.instruments.first(where:{intent.product.matches($0)}) else{pendingTrade=nil;return}
        let same=tradeWorkspace?.product==intent.product && tradeWorkspace?.side==intent.side && tradeWorkspace?.board==intent.board && intent.closingPosition==nil
        if !same{tradeWorkspace=TradeWorkspace(accountID:intent.context.accountID,instrument:i,side:intent.side,revision:(tradeWorkspace?.revision ?? 0)+1);tradeWorkspace?.board=intent.board;tradeSession=UUID();saveTradeSoon()}
        editBrowsing(i.market){value in value.recent.removeAll{$0==i.id};value.recent.insert(i.id,at:0);value.recent=Array(value.recent.prefix(30))}
        pendingTrade=nil;tab=2;focusTradeProduct(i)
        if intent.openForm{tradeClosingPosition=intent.closingPosition;tradeFormRequest=UUID()}
    }
    func discardAndApplyTrade(){guard let pendingTrade else{return};applyTrade(pendingTrade)}
    func updateTradeEditor(_ editor:TradeEditor,instrument:Instrument,context:AccountContext,session:UUID){
        guard self.context==context,tradeSession==session,var workspace=tradeWorkspace,workspace.product.matches(instrument),workspace.editor != editor else{return}
        workspace.editor=editor;workspace.side=editor.side;workspace.board=instrument.usesTaiwanBoards && editor.unit=="股" ? .oddLot:.regular;workspace.revision+=1;tradeWorkspace=workspace;saveTradeSoon()
    }
    func clearTradeEditor(session:UUID){
        guard tradeSession==session,var saved=tradeWorkspace else{return}
        saved.editor=nil;saved.revision+=1;tradeWorkspace=saved;tradeSession=UUID();saveTradeSoon()
    }
    func saveTradeSoon(){
        tradeDirty=true;tradeSaveTask?.cancel()
        tradeSaveTask=Task{do{try await Task.sleep(for:.milliseconds(250))}catch{return};await flushTradeWorkspace()}
    }
    func flushTradeWorkspace()async{
        guard tradeDirty,let workspace=tradeWorkspace,let context,let engine else{return};tradeDirty=false
        do{try await engine.saveTradeWorkspace(workspace,context:context)}catch{guard self.context==context else{return};tradeDirty=true;notice="交易草稿尚未保存，請稍後重試"}
    }
    func focusTradeProduct(_ i:Instrument){
        focusProduct(i)
        if let board=tradeWorkspace?.board,board != selectedBoard{changeBoard(board)}
    }
    func focusActivePage(){
        if tab==2,let i=tradeInstrument{focusTradeProduct(i)}
        else if tab==1,let id=marketPaths[market]?.last,let i=state?.instruments.first(where:{$0.id==id}){focusProduct(i)}
    }
}
