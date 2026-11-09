import Foundation

public enum ExportFiles {
    public static func stem(_ filename:String,extension ext:String)->String {
        let name=filename.trimmingCharacters(in:.whitespacesAndNewlines)
        let base=name.lowercased().hasSuffix("."+ext.lowercased()) ? String(name.dropLast(ext.count+1)):name
        let clean=base.replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:":",with:"_")
        guard !clean.isEmpty,clean != ".",clean != ".." else {return "Untitled"};return clean
    }
    public static func pdf(_ pages:[AssemblyPage],directory:URL,filename:String,size:ImagePageSize = .image,margin:Double=0)throws->URL {
        let work=FileManager.default.temporaryDirectory.appendingPathComponent("utility-export-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:work)}
        let temporary=work.appendingPathComponent("result.pdf")
        try PDFAssembly.write(pages,to:temporary,size:size,margin:margin)
        try Task.checkCancellation()
        return try FileServices.commit(temporary,to:directory,baseName:stem(filename,extension:"pdf"))
    }
}
