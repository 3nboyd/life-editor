import Foundation

public enum TitleAlignment:String,Codable,CaseIterable,Sendable {
    case left,center,right
}

/// Spacing is measured in canvas points, like font size. Optional on TitleStyle
/// so older documents retain the original Core Text defaults byte for byte.
public struct TitleTypography:Codable,Equatable,Sendable {
    public var alignment:TitleAlignment
    public var letterSpacing:Double
    public var lineSpacing:Double
    public init(alignment:TitleAlignment = .center,letterSpacing:Double = 0,lineSpacing:Double = 0) {
        self.alignment=alignment;self.letterSpacing=letterSpacing;self.lineSpacing=lineSpacing
    }
    public var isValid:Bool {
        letterSpacing.isFinite && lineSpacing.isFinite && (-20...100).contains(letterSpacing) && (0...512).contains(lineSpacing)
    }
}
