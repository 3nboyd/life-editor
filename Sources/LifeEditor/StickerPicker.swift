import SwiftUI

struct StickerPicker:View {
    @ObservedObject var store:EditorStore
    var dismiss:()->Void
    @State private var custom=""
    private let emoji=["😀","❤️","🔥","✨","🎵","🎸","🎓","👏"]
    var body:some View {
        VStack(spacing:12){
            Button{dismiss();store.importImageSticker()}label:{Label("Image…",systemImage:"photo.badge.plus").frame(maxWidth:.infinity)}
                .help("Import an image sticker").accessibilityLabel("Import image sticker").disabled(store.busy)
            Divider()
            LazyVGrid(columns:Array(repeating:GridItem(.fixed(42)),count:4),spacing:8){
                ForEach(emoji,id:\.self){value in
                    Button{store.addEmojiSticker(value);dismiss()}label:{Text(value).font(.system(size:26)).frame(width:40,height:40)}
                        .buttonStyle(.plain).help("Add \(value)").accessibilityLabel("Add \(value) emoji")
                }
            }
            HStack{
                TextField("Emoji",text:$custom).textFieldStyle(.roundedBorder).frame(width:144)
                    .help("Type or paste emoji · Control Command Space opens the system picker")
                    .onSubmit{insertCustom()}
                Button(action:insertCustom){Image(systemName:"plus").frame(width:28,height:28)}
                    .buttonStyle(.plain).help("Add emoji").accessibilityLabel("Add custom emoji")
                    .disabled(custom.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
        }.padding(14)
    }
    private func insertCustom(){store.addEmojiSticker(custom);dismiss()}
}
