import AppKit
import Carbon

@main enum AppearanceEventTests {
    static func main() {
        // Validate the System Events protocol without sending a command.
        for dark in [false, true] {
            let event = AppearanceService.event(dark: dark)
            precondition(event.eventClass == kAECoreSuite && event.eventID == kAESetData)
            precondition(event.paramDescriptor(forKeyword: keyAEData)?.booleanValue == dark)
            let mode = event.paramDescriptor(forKeyword: keyDirectObject)!
            precondition(mode.descriptorType == typeObjectSpecifier)
            precondition(mode.forKeyword(AEKeyword(keyAEDesiredClass))?.typeCodeValue == typeProperty)
            precondition(mode.forKeyword(AEKeyword(keyAEKeyForm))?.enumCodeValue == OSType(formPropertyID))
            precondition(mode.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue == 0x74686d65)
            let container = mode.forKeyword(AEKeyword(keyAEContainer))!
            precondition(container.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue == 0x61707270)
        }
        let read = AppearanceService.event()
        precondition(read.eventID == kAEGetData && read.paramDescriptor(forKeyword: keyAEData) == nil)
        var nativeReads = 0
        for target in [false, true] {
            precondition(AppearanceService.confirmDark(target, localRead: { target }, nativeRead: {
                nativeReads += 1
                return !target
            }))
        }
        precondition(nativeReads == 0, "Converged system preference should avoid redundant native queries")
        precondition(AppearanceService.confirmDark(true, localRead: { false }, nativeRead: {
            nativeReads += 1
            return true
        }))
        precondition(nativeReads == 1)
        precondition(!AppearanceService.confirmDark(true, localRead: { false }, nativeRead: { false }))
        precondition(AppearanceService.confirmDark(true, localRead: { false }, nativeRead: { nil }),
                     "Unavailable confirmation preserves successful set-reply semantics")
        print("ok: event grammar; local confirmation skips native query; mismatch uses original fallback/error semantics; no commands sent")
    }
}
