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
        let screen=app.frame,navigation=app.navigationBars.firstMatch,tabs=app.tabBars.firstMatch,keyboard=app.keyboards.firstMatch
        let top=navigation.exists ? navigation.frame.maxY:screen.minY
        var bottom=keyboard.exists ? keyboard.frame.minY:(tabs.exists ? tabs.frame.minY:screen.maxY)
        // Hittable alone accepts partly exposed controls behind the pinned buy/sell bar.
        // Require the entire target inside the usable viewport before tapping it.
        if !["openOrder","openSellOrder","submitOrder","saveJournal"].contains(element.identifier){
            let footer=app.otherElements["tradeActionBar"].firstMatch
            if footer.exists{bottom=min(bottom,footer.frame.minY)}
        }
        let viewport=CGRect(x:screen.minX,y:top,width:screen.width,height:max(1,bottom-top)).insetBy(dx:1,dy:2)
        func visible()->Bool{element.exists && viewport.contains(element.frame) && element.isHittable}
        for _ in 0..<7{
            if visible(){return}
            if element.exists{
                // Large text can move a control above the viewport after a long swipe.
                // Follow its real frame back toward the visible middle instead of
                // continuing to scroll past it. The original seven-gesture bound stays.
                let frame=element.frame,up=frame.midY>viewport.midY
                if frame.minY>screen.maxY+screen.height/2{app.swipeUp();continue}
                if frame.maxY<screen.minY-screen.height/2{app.swipeDown();continue}
                let start=app.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:up ? 0.65:0.35))
                let end=app.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:up ? 0.40:0.60))
                start.press(forDuration:0.1,thenDragTo:end)
            }else{app.swipeUp(velocity:.slow)}
        }
        try check(visible(),"Control is not completely visible and reachable: "+element.identifier)
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
        var expected=""
        for character in text{
            element.typeText(String(character));expected.append(character)
            try check(element.value as? String==expected,"Keyboard input differs before any save")
        }
    }
    func finish(){
        capture("final")
        guard let app=testedApp else{return}
        RunLoop.current.run(until:Date().addingTimeInterval(0.15))
        if app.state != .notRunning{app.terminate()}
    }
    func number(_ value:String)->NSDecimalNumber{NSDecimalNumber(string:value,locale:Locale(identifier:"en_US_POSIX"))}
}
