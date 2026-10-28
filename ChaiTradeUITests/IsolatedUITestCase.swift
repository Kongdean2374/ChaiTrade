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
    func capture(_ stage:String){
        guard let app=testedApp else{return}
        XCTContext.runActivity(named:stage+" · "+session){activity in
            let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=stage;shot.lifetime = .keepAlways;activity.add(shot)
            let tree=XCTAttachment(string:app.debugDescription);tree.name="Accessibility hierarchy";tree.lifetime = .keepAlways;activity.add(tree)
            let probe=app.staticTexts["uiTestState"].firstMatch
            let state=XCTAttachment(string:probe.exists ? probe.label:"Probe unavailable; hierarchy and database retained");state.name="Synthetic account state";state.lifetime = .keepAlways;activity.add(state)
        }
    }
    func check(_ condition:@autoclosure () throws ->Bool,_ message:String,file:StaticString=#filePath,line:UInt=#line)throws{
        guard try condition() else{capture("FAIL · "+message);XCTFail(message,file:file,line:line);throw CheckFailure.failed}
    }
    func state(_ app:XCUIApplication)throws->[String:Any]{
        let probe=app.staticTexts["uiTestState"].firstMatch
        try check(probe.exists || probe.waitForExistence(timeout:5),"Missing read-only state probe")
        return try XCTUnwrap(JSONSerialization.jsonObject(with:Data(probe.label.utf8)) as? [String:Any])
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
        capture("Clean baseline")
    }
    func reveal(_ element:XCUIElement,in app:XCUIApplication)throws{
        let screen=app.frame,navigation=app.navigationBars.allElementsBoundByIndex.last,tabs=app.tabBars.firstMatch,keyboard=app.keyboards.firstMatch
        let keyboardAssistant=app.otherElements["SystemInputAssistantView"].firstMatch,keyboardInput=app.otherElements["inputView"].firstMatch
        let keyboardToolbars=app.toolbars.allElementsBoundByIndex
        var measuredKeyboard:CGRect?,keyboardOcclusion:CGFloat?
        // A presented sheet retains the underlying TabBar in the AX tree. Its frame
        // does not occlude the sheet; use the foreground navigation and hittable bars.
        let tabBottom=tabs.exists && tabs.isHittable ? tabs.frame.minY:screen.maxY
        let targetID=element.exists ? element.identifier:"requested control"
        // Hittable alone accepts partly exposed controls behind the pinned buy/sell bar.
        // Require the entire target inside the usable viewport before tapping it.
        let footer=app.otherElements[app.buttons["submitOrder"].exists ? "orderActionBar":"tradeActionBar"].firstMatch
        let hasFooter = !["openOrder","openSellOrder","submitOrder","saveJournal","enableContractTrading"].contains(targetID) && footer.exists && footer.isHittable
        func usableViewport()->CGRect{
            let top=navigation?.frame.maxY ?? screen.minY
            var bottom=tabBottom
            if keyboard.exists{
                let frame=keyboard.frame
                if measuredKeyboard != frame{
                    measuredKeyboard=frame;var obstruction=frame.minY
                    for strip in [keyboardAssistant,keyboardInput] where strip.exists{let rect=strip.frame;if rect.height>0,rect.minY>top{obstruction=min(obstruction,rect.minY)}}
                    // The custom 48pt keyboard toolbar is above the prediction strip.
                    // Use its actual frame; otherwise swipes land on the Done button.
                    for bar in keyboardToolbars where bar.exists{let rect=bar.frame;if rect.width>=screen.width*0.6,rect.minY>top,rect.maxY<=frame.minY+1,rect.maxY>=frame.minY-180{obstruction=min(obstruction,rect.minY)}}
                    keyboardOcclusion=obstruction
                }
                bottom=min(frame.minY,keyboardOcclusion ?? frame.minY)
            }
            if hasFooter{bottom=min(bottom,footer.frame.minY)}
            return CGRect(x:screen.minX,y:top,width:screen.width,height:max(1,bottom-top)).insetBy(dx:0,dy:2)
        }
        for attempt in 0...7{
            // Sample each AX property once per iteration. Keep the same complete
            // visibility/hit-test rules and at most seven gestures.
            let viewport=usableViewport(),exists=element.exists
            let frame=exists ? element.frame:nil
            if let frame,viewport.contains(frame),element.isHittable{return}
            guard attempt<7 else{break}
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
        app.tabBars.buttons["資產"].tap();let button=app.buttons["本機交易日誌"];try reveal(button,in:app);button.tap()
        try check(app.textViews["journalText"].waitForExistence(timeout:5),"Journal sheet missing")
    }
    func marketOrder(_ app:XCUIApplication)throws{
        app.tabBars.buttons["交易"].tap();let open=app.buttons["openOrder"];try reveal(open,in:app);open.tap()
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
        try check(element.value as? String==text,"Keyboard input differs before any save")
    }
    func finish(){
        capture("final")
        guard let app=testedApp else{return}
        RunLoop.current.run(until:Date().addingTimeInterval(0.15))
        if app.state != .notRunning{app.terminate()}
    }
    func number(_ value:String)->NSDecimalNumber{NSDecimalNumber(string:value,locale:Locale(identifier:"en_US_POSIX"))}
}
