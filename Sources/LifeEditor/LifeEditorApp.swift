import SwiftUI
import AppKit

@main
struct LifeEditorApp: App {
    @NSApplicationDelegateAdaptor(EditorAppDelegate.self) private var appDelegate
    @StateObject private var store = EditorStore()
    var body: some Scene {
        Window("Life Editor", id:"main") {
            WorkspaceView(store: store)
                .frame(minWidth: 1000, minHeight: 650)
                .preferredColorScheme(.dark)
                .background(WindowGuard(store:store))
                .onAppear { appDelegate.store = store;store.findRecovery() }
                .onOpenURL { store.openProject($0) }
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { store.newProject() }.keyboardShortcut("n")
                Button("Open…") { store.openProject() }.keyboardShortcut("o")
                Menu("Open Recent"){
                    ForEach(store.recentProjects,id:\.self){url in Button(url.deletingPathExtension().lastPathComponent){store.openProject(url)}}
                }.disabled(store.recentProjects.isEmpty)
                Menu("Recover"){
                    ForEach(store.recoverable){snapshot in Button(snapshot.name){store.restoreRecovery(snapshot)}}
                }.disabled(store.recoverable.isEmpty)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { store.save() }.keyboardShortcut("s")
                Button("Save As…") { store.save(as:true) }.keyboardShortcut("s",modifiers:[.command,.shift])
                Button("Duplicate",action:store.duplicateProject)
                Button("Revert to Saved",action:store.revertProject).disabled(!store.canRevert)
                Button("Collect Media…"){store.collectMedia()}
                Button("Relink Media…"){store.relinkMedia()}
                Divider()
                Button("Caption"){store.addManualCaption()}
                Button("Import SRT…"){store.importCaptions()}
                Button("Export SRT…"){store.exportCaptions()}
            }
            CommandGroup(replacing:.pasteboard){
                Button("Cut"){store.cutSelection()}.keyboardShortcut("x").disabled(store.selectedIDs.isEmpty)
                Button("Copy"){store.copySelection()}.keyboardShortcut("c").disabled(store.selectedIDs.isEmpty)
                Button("Paste"){store.pasteSelection()}.keyboardShortcut("v")
                Button("Select All"){store.selectAll()}.keyboardShortcut("a")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { store.undo() }.keyboardShortcut("z").disabled(!store.canUndo)
                Button("Redo") { store.redo() }.keyboardShortcut("z",modifiers:[.command,.shift]).disabled(!store.canRedo)
            }
            CommandMenu("Clip") {
                Button("Import…") { store.importMedia() }.keyboardShortcut("i")
                Button("Split") { store.split() }.keyboardShortcut("b")
                Button("Insert Copies"){store.previewPlacement(.insertCopies(clipIDs:store.selectedIDs,at:store.playheadTime),title:"Insert")}.keyboardShortcut("i",modifiers:[.command,.shift]).disabled(store.selectedIDs.isEmpty)
                Button("Overwrite Copies"){store.previewPlacement(.overwriteCopies(clipIDs:store.selectedIDs,at:store.playheadTime),title:"Overwrite")}.keyboardShortcut("o",modifiers:[.command,.shift]).disabled(store.selectedIDs.isEmpty)
                Button("Group"){store.apply(.group(clipIDs:store.selectedIDs))}.keyboardShortcut("g").disabled(store.selectedIDs.count<2)
                Button("Ungroup"){store.apply(.ungroup(clipIDs:store.selectedIDs))}.keyboardShortcut("g",modifiers:[.command,.shift])
                Button("Detach Audio"){store.detachAudio()}
                Button("Link"){store.apply(.link(clipIDs:store.selectedIDs))}.disabled(store.selectedIDs.count<2)
                Button("Unlink"){store.apply(.detach(clipIDs:store.selectedIDs))}
                Button("Duplicate"){if let clip=store.selectedClip {store.apply(.duplicate(clipID:clip.id,to:clip.end))}}.keyboardShortcut("d")
                Button("Ripple Delete"){if let id=store.selection {store.apply(.rippleDelete(clipID:id))}}.keyboardShortcut(.delete,modifiers:[.shift])
                Button("Delete") { store.deleteSelection() }.keyboardShortcut(.delete,modifiers:[])
                Button("Marker") { store.addMarker() }.keyboardShortcut("m",modifiers:[])
                Button("Snapping") { store.snapping.toggle() }.keyboardShortcut("n",modifiers:[])
            }
            CommandMenu("Cameras") {
                ForEach(1...9,id:\.self){number in
                    Button("Camera \(number)"){
                        guard NSApp.currentEvent?.isARepeat != true,store.visibleAngles.indices.contains(number-1) else{return}
                        store.chooseAngle(store.visibleAngles[number-1].id)
                    }.keyboardShortcut(KeyEquivalent(Character(String(number))),modifiers:[]).disabled(store.panel != .multicam || !store.visibleAngles.indices.contains(number-1))
                }
            }
            CommandMenu("Playback") {
                Button("Play / Pause") { store.togglePlayback() }.keyboardShortcut(.space,modifiers:[])
                Button("Previous Frame") { store.step(-1) }.keyboardShortcut(.leftArrow,modifiers:[])
                Button("Next Frame") { store.step(1) }.keyboardShortcut(.rightArrow,modifiers:[])
                Button("Viewer Focus") { store.focused.toggle() }.keyboardShortcut("f",modifiers:[.command,.shift])
            }
        }
        Settings { PreferencesView().environmentObject(store) }
    }
}

struct PreferencesView: View {
    @EnvironmentObject var store:EditorStore
    @AppStorage("showSafeAreaDefault") var safe = false
    @AppStorage("cacheBudgetGB") var budget=10.0
    var body: some View {
        Form {
            Toggle("Safe areas in new windows",isOn:$safe)
            HStack{Text("Cache");Spacer();Text(ByteCountFormatter.string(fromByteCount:store.cacheBytes,countStyle:.file)).monospacedDigit()}
            HStack{Text("Budget");Slider(value:$budget,in:1...100,step:1);Text("\(Int(budget)) GB").monospacedDigit()}
            Button("Clean Caches"){store.clearCaches()}.disabled(store.playing || store.exporting || store.busy || store.preparing)
        }.padding(24).frame(width:380).onAppear{store.refreshCacheUsage()}
    }
}
