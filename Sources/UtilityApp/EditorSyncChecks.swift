import AppKit
import WebKit
import UtilityCore

/// Scripted integration checks in the real WebKit renderer, without desktop automation.
@MainActor enum EditorSyncChecks {
    static func run(_ editor:EditorController) async throws {
        var lines=["# Navigation test","","Intro with **formatting** and 文件 😀.",""]
        var headings:[Int]=[]
        for i in 1...80 {headings.append(lines.count);lines += ["## Section \(i)","","Paragraph \(i): text with *emphasis* and Unicode 文件 😀.","","- List item \(i)",""]}
        let fence=lines.count
        lines += ["```swift","let first = \"😀\"","let second = 2","```",""]
        let table=lines.count
        lines += ["| Name | Value |","|---|---|","| alpha | 42 |",""]
        let math=lines.count
        lines += ["$$","\\frac{1}{2} + 1","$$","","[External link](https://example.com)",""]
        let original=lines.joined(separator:"\n"),saved=editor.savedText
        editor.text.string=original;editor.text.setSelectedRange(NSRange(location:0,length:0));editor.render()
        try await waitForRender(editor)
        func js(_ code:String) async throws ->Any? {do {return try await editor.web.evaluateJavaScript(code)} catch {throw UtilityError.message("Editor navigation JavaScript (\(code.prefix(120))): \(error.localizedDescription)")}}
        func stateStart() async throws ->Int? {(try await js("sourceNavigationState().start")) as? Int}
        func click(_ selector:String) async throws {
            let encoded=String(data:try JSONSerialization.data(withJSONObject:[selector]),encoding:.utf8)!
            _=try await js("""
            (()=>{getSelection().removeAllRanges();const el=document.querySelector(\(encoded)[0]);if(!el)throw Error('Missing source target');el.scrollIntoView({block:'center'});const r=el.getBoundingClientRect();el.dispatchEvent(new MouseEvent('click',{bubbles:true,clientX:r.left+10,clientY:r.top+8}));return true})()
            """)
            try await Task.sleep(nanoseconds:150_000_000)
        }
        // The native selection delegate should follow the caret into an off-screen section.
        let target=headings[69]
        editor.text.setSelectedRange(NSRange(location:SourceLineMap(original).utf16Offset(forLine:target),length:0))
        try await Task.sleep(nanoseconds:180_000_000)
        guard try await stateStart()==target,(try await js("window.scrollY")) as? Double ?? 0 > 500 else {throw UtilityError.message("Source caret did not reveal the matching off-screen preview section")}
        try await click("#preview h2[data-source-start='\(headings[9])']")
        guard SourceLineMap(editor.text.string).line(atUTF16Offset:editor.text.selectedRange().location)==headings[9],editor.text.selectedRange().length==0,editor.window.firstResponder === editor.text else {throw UtilityError.message("Preview click did not move the source caret/focus")}
        try await click("#preview tr[data-source-start='\(table+2)'] td")
        guard SourceLineMap(original).line(atUTF16Offset:editor.text.selectedRange().location)==table+2 else {throw UtilityError.message("Table-row click did not reveal its source row")}
        try await click("#preview [data-source-start='\(math)'] .katex")
        guard SourceLineMap(original).line(atUTF16Offset:editor.text.selectedRange().location)==math else {throw UtilityError.message("Equation click did not reveal its source block")}
        // Use actual DOM character rectangles for a click inside the second fenced-code line.
        _=try await js("""
        (()=>{getSelection().removeAllRanges();const pre=document.querySelector("#preview pre[data-source-start='\(fence)']");pre.scrollIntoView({block:'center'});const code=pre.querySelector('code'),node=code.firstChild,index=node.textContent.indexOf('second');const range=document.createRange();range.setStart(node,index);range.setEnd(node,index+1);const r=range.getBoundingClientRect();code.dispatchEvent(new MouseEvent('click',{bubbles:true,clientX:r.left+1,clientY:r.top+r.height/2}));return true})()
        """)
        try await Task.sleep(nanoseconds:150_000_000)
        let codeRange=SourceLineMap(original).contentRange(forLine:fence+2)
        guard NSLocationInRange(editor.text.selectedRange().location,codeRange),editor.text.selectedRange().location>codeRange.location else {throw UtilityError.message("Code preview click did not locate its source line/column")}
        // Selecting text in the preview must remain a copy/selection gesture.
        let before=editor.text.selectedRange()
        _=try await js("""
        (()=>{const el=document.querySelector('#preview h2');const r=document.createRange();r.selectNodeContents(el);getSelection().removeAllRanges();getSelection().addRange(r);el.dispatchEvent(new MouseEvent('click',{bubbles:true}));return true})()
        """)
        try await Task.sleep(nanoseconds:100_000_000)
        guard editor.text.selectedRange()==before else {throw UtilityError.message("Preview text selection unexpectedly moved the editor")}
        _=try await js("getSelection().removeAllRanges();true")
        let oldRevision=editor.renderedGeneration
        editor.text.insertText("\n",replacementRange:NSRange(location:0,length:0))
        let afterEdit=editor.text.selectedRange()
        _=try await js("window.webkit.messageHandlers.sourceNavigation.postMessage({line:30,column:0,revision:\(oldRevision)});true")
        try await Task.sleep(nanoseconds:80_000_000)
        guard editor.text.selectedRange()==afterEdit else {throw UtilityError.message("Stale preview navigation jumped after an edit")}
        try await waitForRender(editor)
        guard editor.renderedGeneration>oldRevision,(try await js("Number(document.querySelector('#preview h1').dataset.sourceStart)")) as? Int == 1 else {throw UtilityError.message("Source map did not refresh after inserting a line")}
        try await click("#preview h2[data-source-start='\(headings[19]+1)']")
        guard SourceLineMap(editor.text.string).line(atUTF16Offset:editor.text.selectedRange().location)==headings[19]+1 else {throw UtilityError.message("Preview navigation used stale line positions after editing")}
        let valid=editor.text.selectedRange()
        _=try await js("window.webkit.messageHandlers.sourceNavigation.postMessage({line:999999,column:0,revision:\(editor.renderedGeneration)});true")
        try await Task.sleep(nanoseconds:80_000_000)
        guard editor.text.selectedRange()==valid,editor.text.string=="\n"+original,editor.savedText==saved else {throw UtilityError.message("Navigation changed document contents or accepted an invalid source line")}
        // No active-navigation decoration should appear in PDF output.
        let cleanPDF=try await editor.web.callAsyncJavaScript("await beginPDF();try{return [...document.querySelectorAll('#pdf-host .source-active')].every(el=>getComputedStyle(el).outlineStyle==='none')}finally{endPDF()}",arguments:[:],in:nil,contentWorld:.page)
        guard cleanPDF as? Bool == true else {throw UtilityError.message("Source-navigation decoration leaked into PDF export")}
    }
    static func waitForRender(_ editor:EditorController) async throws {
        for _ in 0..<100 {
            if editor.renderedSource==editor.text.string,editor.renderedGeneration==editor.renderGeneration {return}
            try await Task.sleep(nanoseconds:20_000_000)
        }
        throw UtilityError.message("Editor source-mapped preview did not finish rendering")
    }
}
