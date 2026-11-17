import BrievieUI
import Testing

@Suite struct LabelColorTests {
    @Test(arguments: ["grey", "blue", "teal", "green", "yellow", "orange", "red", "purple"])
    func everyPaletteKeyHasItsOwnColour(key: String) {
        #expect(LabelColor(key: key).rawValue == key)
    }

    @Test func unknownColorKeyIsGrey() {
        #expect(LabelColor(key: "magenta") == .grey)
        #expect(LabelColor(key: "") == .grey)
        #expect(LabelColor.color(forKey: "magenta") == LabelColor.color(forKey: "grey"))
        #expect(LabelColor.color(forKey: "blue") != LabelColor.color(forKey: "grey"))
    }
}
