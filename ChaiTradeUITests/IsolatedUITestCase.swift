import XCTest

@MainActor class IsolatedUITestCase:XCTestCase {
    var testedApp:XCUIApplication?
    var session=""
    enum CheckFailure:Error{case failed}
    @discardableResult func launchClean(fixture:Bool=false,flags:[String]=[])->XCUIApplication{
        let app=XCUIApplication();session=UUID().uuidString
        app.launchArguments=["--uitest","--uitest-session",session]+(fixture ? ["--uitest-fixture"]:[])+flags
        testedApp=app;print("UI_TEST_SESSION",name,session);app.launch();return app
    }
    func capture(_ stage:String,includeHierarchy:Bool=true,snapshot:[String:Any]?=nil){
        guard let app=testedApp else{return}
        XCTContext.runActivity(named:stage+" · "+session){activity in
            let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=stage;shot.lifetime = .keepAlways;activity.add(shot)
            guard includeHierarchy else{
                if let snapshot,let data=try? JSONSerialization.data(withJSONObject:snapshot,options:.sortedKeys),let value=String(data:data,encoding:.utf8){let state=XCTAttachment(string:value);state.name="Synthetic account state";state.lifetime = .keepAlways;activity.add(state)}
                return
            }
            let hierarchy=app.debugDescription
            let tree=XCTAttachment(string:hierarchy);tree.name="Accessibility hierarchy";tree.lifetime = .keepAlways;activity.add(tree)
            // The hierarchy already contains the exact read-only probe. Reusing
            // that snapshot avoids two additional AX traversals behind a modal;
            // the retained 791fd10 conflict capture spent 27s on that duplicate read.
            let marker="identifier: 'uiTestState', label: '"
            var snapshot="Probe unavailable in captured hierarchy; hierarchy and database retained"
            if let line=hierarchy.split(whereSeparator:{$0.isNewline}).first(where:{$0.contains(marker)}),let start=line.range(of:marker),let end=line.lastIndex(of:"'"){
                let candidate=String(line[start.upperBound..<end])
                if let data=candidate.data(using:.utf8),let decoded=try? JSONSerialization.jsonObject(with:data),decoded is [String:Any]{snapshot=candidate}
            }
            let state=XCTAttachment(string:snapshot);state.name="Synthetic account state";state.lifetime = .keepAlways;activity.add(state)
        }
    }
    func check(_ condition:@autoclosure () throws ->Bool,_ message:String,file:StaticString=#filePath,line:UInt=#line)throws{
        guard try condition() else{capture("FAIL · "+message);XCTFail(message,file:file,line:line);throw CheckFailure.failed}
    }
    func state(_ app:XCUIApplication)throws->[String:Any]{
        let probe=app.staticTexts["uiTestState"].firstMatch
        let snapshot:XCUIElementSnapshot
        do{snapshot=try probe.snapshot()}
        catch{
            try check(probe.waitForExistence(timeout:5),"Missing read-only state probe")
            snapshot=try probe.snapshot()
        }
        // A single fresh native snapshot replaces separate exists/label AX
        // round trips. It reads the same probe; no model or financial action.
        return try XCTUnwrap(JSONSerialization.jsonObject(with:Data(snapshot.label.utf8)) as? [String:Any])
    }
    func ready(_ app:XCUIApplication)throws{
        try check(app.tabBars.buttons["總覽"].waitForExistence(timeout:30),"App did not become ready")
        let s=try state(app)
        try check(s["session"] as? String==session,"Wrong test directory")
        try check((s["orders"] as? [String])?.isEmpty==true,"Test inherited orders")
        try check((s["journals"] as? [[String:String]])?.isEmpty==true,"Test inherited journals")
        try check((s["watchlist"] as? [String])?.isEmpty==true,"Test inherited favorites")
        try check((s["fills"] as? [[String:String]])?.isEmpty==true,"Test inherited fills")
        try check((s["positions"] as? [String:String])?.isEmpty==true,"Test inherited positions")
        try check((s["cash"] as? [String:String])==["TWD":"100000"],"Fixture did not start from clean capital")
        capture("Clean baseline",includeHierarchy:false,snapshot:s)
    }
    private func finiteFrame(_ frame:CGRect)->Bool{
        !frame.isNull && !frame.isInfinite && frame.minX.isFinite && frame.minY.isFinite && frame.maxX.isFinite && frame.maxY.isFinite && frame.width.isFinite && frame.height.isFinite && frame.width>0 && frame.height>0
    }
    private func onScreen(_ frame:CGRect,_ screen:CGRect)->Bool{finiteFrame(frame) && screen.intersects(frame)}
    func reveal(_ element:XCUIElement,in app:XCUIApplication,identifier:String?=nil)throws{
        // Callers with an exact known query ID can avoid two preliminary AX
        // reads. Geometry still comes from the current native snapshot and the
        // actual queried element must pass the unchanged live hit test.
        let targetID=identifier ?? (element.exists ? element.identifier:"requested control")
        let isFooterAction=["openOrder","openSellOrder","submitOrder","saveJournal","enableContractTrading"].contains(targetID) || targetID.hasPrefix("closePosition-")
        func descendants(_ node:XCUIElementSnapshot)->[XCUIElementSnapshot]{
            [node]+node.children.flatMap{descendants($0)}
        }
        for attempt in 0...7{
            // One native snapshot supplies the geometry for this gesture. The
            // previous helper requested every bar, keyboard strip and frame
            // separately, spending 20s finding an already visible board button
            // in the retained 12bd page failure. Keep the same full-frame and
            // live hit-test requirements, keyboard exclusions and seven swipes.
            guard let snapshot=try? app.snapshot() else{
                if attempt==0{try revealWithIndividualQueries(element,in:app);return}
                try check(false,"Cannot obtain current geometry for: "+targetID);return
            }
            let nodes=descendants(snapshot),screen=snapshot.frame
            guard finiteFrame(screen) else{print("UI_REVEAL_INVALID_SCREEN",name,targetID,screen);try revealWithIndividualQueries(element,in:app,maximumGestures:7-attempt);return}
            // A dismissed order-kind sheet can remain in AX with CGRect.null.
            // Its infinite maxY is not the foreground navigation boundary.
            let navigation=nodes.last{$0.elementType == .navigationBar && onScreen($0.frame,screen)}
            let tabs=nodes.first{$0.elementType == .tabBar && onScreen($0.frame,screen)}
            let keyboard=nodes.first{$0.elementType == .keyboard && onScreen($0.frame,screen)}
            let top=navigation?.frame.maxY ?? screen.minY
            var bottom=screen.maxY
            if let tabs,app.tabBars.firstMatch.isHittable{bottom=min(bottom,tabs.frame.minY)}
            if let keyboard{
                var obstruction=keyboard.frame.minY
                for strip in nodes where ["SystemInputAssistantView","inputView"].contains(strip.identifier){
                    let rect=strip.frame
                    if onScreen(rect,screen),rect.minY>top{obstruction=min(obstruction,rect.minY)}
                }
                for bar in nodes where bar.elementType == .toolbar{
                    let rect=bar.frame
                    if onScreen(rect,screen),rect.width>=screen.width*0.6,rect.minY>top,rect.maxY<=keyboard.frame.minY+1,rect.maxY>=keyboard.frame.minY-180{obstruction=min(obstruction,rect.minY)}
                }
                bottom=min(bottom,obstruction)
            }
            if !isFooterAction{
                for footerID in ["orderActionBar","tradeActionBar"]{
                    if let footer=nodes.last(where:{$0.identifier==footerID && onScreen($0.frame,screen)}),app.otherElements[footerID].firstMatch.isHittable{bottom=min(bottom,footer.frame.minY);break}
                }
            }
            let viewport=CGRect(x:screen.minX,y:top,width:screen.width,height:max(1,bottom-top)).insetBy(dx:0,dy:2)
            guard finiteFrame(viewport),screen.contains(viewport) else{
                print("UI_REVEAL_INVALID_VIEWPORT",name,targetID,"screen",screen,"top",top,"bottom",bottom)
                try revealWithIndividualQueries(element,in:app,maximumGestures:7-attempt);return
            }
            // A unique stable identifier in this same native snapshot also gives
            // the target frame. Avoid two more cross-process AX reads; ambiguous
            // or unlabeled elements retain the original live lookup. The full
            // viewport check and the live hit test below are unchanged.
            let targets=targetID.isEmpty || targetID=="requested control" ? []:nodes.filter{$0.identifier==targetID}
            let frame:CGRect?
            if targets.count==1,finiteFrame(targets[0].frame){frame=targets[0].frame}
            else{let measured=element.exists ? element.frame:nil;frame=measured.flatMap{finiteFrame($0) ? $0:nil}}
            let contained=frame.map{viewport.contains($0)} ?? false
            let reachable=contained && element.isHittable
            if reachable{return}
            // Retain geometry in the console before another gesture. A timed-out
            // XCTest can lose its final attachment/movie; coordinates alone do
            // not expose editor contents or credentials.
            print("UI_REVEAL_GEOMETRY",name,targetID,"attempt",attempt,"target",String(describing:frame),"viewport",String(describing:viewport),"contained",contained,"hittable",reachable)
            guard attempt<7 else{break}
            let distance=frame.map{$0.midY-viewport.midY} ?? viewport.height*2
            let up=distance>0,far=abs(distance)>viewport.height*1.5
            let travel=far ? viewport.height*0.75:min(viewport.height*0.65,max(35,abs(distance)))
            let startY=up ? viewport.maxY-viewport.height*0.1:viewport.minY+viewport.height*0.1
            let base=app.coordinate(withNormalizedOffset:.zero)
            let start=base.withOffset(CGVector(dx:viewport.width*0.85,dy:startY-screen.minY))
            let end=base.withOffset(CGVector(dx:viewport.width*0.85,dy:startY-screen.minY+(up ? -travel:travel)))
            start.press(forDuration:0.1,thenDragTo:end,withVelocity:far ? .fast:.slow,thenHoldForDuration:0.1)
        }
        try check(false,"Control is not completely visible and reachable: "+targetID)
    }
    private func revealWithIndividualQueries(_ element:XCUIElement,in app:XCUIApplication,maximumGestures:Int=7)throws{
        let screen=app.frame,tabs=app.tabBars.firstMatch,keyboard=app.keyboards.firstMatch
        try check(finiteFrame(screen),"Live screen geometry is invalid; no pointer gesture sent")
        let keyboardAssistant=app.otherElements["SystemInputAssistantView"].firstMatch,keyboardInput=app.otherElements["inputView"].firstMatch
        var measuredKeyboard:CGRect?,keyboardOcclusion:CGFloat?
        // A presented sheet retains the underlying TabBar in the AX tree. Its frame
        // does not occlude the sheet; use the foreground navigation and hittable bars.
        let targetID=element.exists ? element.identifier:"requested control"
        // Hittable alone accepts partly exposed controls behind the pinned buy/sell bar.
        // Require the entire target inside the usable viewport before tapping it.
        let isFooterAction=["openOrder","openSellOrder","submitOrder","saveJournal","enableContractTrading"].contains(targetID) || targetID.hasPrefix("closePosition-")
        func usableViewport()->CGRect{
            let navigation=app.navigationBars.allElementsBoundByIndex.last{bar in let rect=bar.frame;return onScreen(rect,screen) && bar.isHittable}
            let top=navigation?.frame.maxY ?? screen.minY
            let tabFrame=tabs.exists && tabs.isHittable ? tabs.frame:nil
            var bottom=tabFrame.flatMap{onScreen($0,screen) ? $0.minY:nil} ?? screen.maxY
            if keyboard.exists,onScreen(keyboard.frame,screen){
                let frame=keyboard.frame
                if measuredKeyboard != frame{
                    measuredKeyboard=frame;var obstruction=frame.minY
                    for strip in [keyboardAssistant,keyboardInput] where strip.exists{let rect=strip.frame;if onScreen(rect,screen),rect.minY>top{obstruction=min(obstruction,rect.minY)}}
                    // The custom 48pt keyboard toolbar is above the prediction strip.
                    // Use its actual frame; otherwise swipes land on the Done button.
                    for bar in app.toolbars.allElementsBoundByIndex where bar.exists{let rect=bar.frame;if onScreen(rect,screen),rect.width>=screen.width*0.6,rect.minY>top,rect.maxY<=frame.minY+1,rect.maxY>=frame.minY-180{obstruction=min(obstruction,rect.minY)}}
                    keyboardOcclusion=obstruction
                }
                bottom=min(frame.minY,keyboardOcclusion ?? frame.minY)
            }
            if !isFooterAction{for id in ["orderActionBar","tradeActionBar"]{let footer=app.otherElements[id].firstMatch;if footer.exists,footer.isHittable,onScreen(footer.frame,screen){bottom=min(bottom,footer.frame.minY);break}}}
            return CGRect(x:screen.minX,y:top,width:screen.width,height:max(1,bottom-top)).insetBy(dx:0,dy:2)
        }
        for attempt in 0...maximumGestures{
            // Sample each AX property once per iteration. Keep the same complete
            // visibility/hit-test rules and at most seven gestures.
            let viewport=usableViewport(),exists=element.exists
            try check(finiteFrame(viewport) && screen.contains(viewport),"Live content geometry is invalid; no pointer gesture sent")
            let measured=exists ? element.frame:nil
            let frame=measured.flatMap{finiteFrame($0) ? $0:nil}
            if let frame,viewport.contains(frame),element.isHittable{return}
            guard attempt<maximumGestures else{break}
            // Large titles collapse while scrolling; both ends must remain inside
            // the current content area. A screen-relative downward swipe can start
            // in the SE navigation bar and never move the scroll view at all.
            let distance=frame.map{$0.midY-viewport.midY} ?? viewport.height*2
            let up=distance>0,far=abs(distance)>viewport.height*1.5
            let travel=far ? viewport.height*0.75:min(viewport.height*0.65,max(35,abs(distance)))
            let startY=up ? viewport.maxY-viewport.height*0.1:viewport.minY+viewport.height*0.1
            let base=app.coordinate(withNormalizedOffset:.zero)
            let start=base.withOffset(CGVector(dx:viewport.width*0.85,dy:startY-screen.minY))
            let end=base.withOffset(CGVector(dx:viewport.width*0.85,dy:startY-screen.minY+(up ? -travel:travel)))
            start.press(forDuration:0.1,thenDragTo:end,withVelocity:far ? .fast:.slow,thenHoldForDuration:0.1)
        }
        try check(false,"Control is not completely visible and reachable: "+targetID)
    }
    func journal(_ app:XCUIApplication)throws{
        app.tabBars.buttons["資產"].tap();let button=app.buttons["本機交易日誌"];try reveal(button,in:app,identifier:"openJournal");button.tap()
        try check(app.textViews["journalText"].waitForExistence(timeout:5),"Journal sheet missing")
    }
    func marketOrder(_ app:XCUIApplication)throws{
        app.tabBars.buttons["交易"].tap();let open=app.buttons["openOrder"];try reveal(open,in:app,identifier:"openOrder");open.tap()
        app.buttons["orderKind"].tap();app.buttons["市價"].tap()
    }
    func rapid(_ element:XCUIElement,count:Int=4){element.tap(withNumberOfTaps:count,numberOfTouches:1)}
    func waitUntil(_ message:String,timeout:TimeInterval=8,_ predicate:@escaping ()->Bool)throws{
        let deadline=Date().addingTimeInterval(timeout)
        while Date()<deadline{if predicate(){return};RunLoop.current.run(until:Date().addingTimeInterval(0.15))}
        try check(false,message)
    }
    func enterVerified(_ text:String,into element:XCUIElement)throws{
        element.tap()
        try check((element.value as? String ?? "").isEmpty,"Text editor did not start empty")
        // Inject the complete rapid input, then verify the entire exact value before
        // saving. Per-character automation round trips were consuming the 120s case
        // budget; persisted-text and idempotency assertions remain unchanged.
        element.typeText(text)
        // Retained source14 evidence shows the full text on screen 0.7s after
        // an AX read returned two characters short. Wait for delivery of the
        // single input event; never retype, accept a prefix or extend the case.
        let deadline=Date().addingTimeInterval(3)
        var actual=element.value as? String
        while actual != text,Date()<deadline{
            RunLoop.current.run(until:Date().addingTimeInterval(0.05))
            actual=element.value as? String
        }
        let detail:String
        if let actual{detail=String(reflecting:actual)}else{detail="<unavailable>"}
        try check(actual==text,"Keyboard input differs before any save. Actual: "+detail)
    }
    func finish(includeHierarchy:Bool=true){
        capture("final",includeHierarchy:includeHierarchy)
        guard let app=testedApp else{return}
        RunLoop.current.run(until:Date().addingTimeInterval(0.15))
        if app.state != .notRunning{app.terminate()}
    }
    func number(_ value:String)->NSDecimalNumber{NSDecimalNumber(string:value,locale:Locale(identifier:"en_US_POSIX"))}
}
