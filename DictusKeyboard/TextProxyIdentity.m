// DictusKeyboard/TextProxyIdentity.m
//
// The ObjC shim `KeyboardLifecycleProbe` said this property would need.
//
// `UIInputViewController.h` declares `documentIdentifier` as `NSUUID *` with **no
// nullability annotation**, and the header carries no `NS_ASSUME_NONNULL_BEGIN`. So
// Swift imports it as a non-optional `UUID` while ObjC is free to return nil — and it
// does return nil before the host input session is established. Reading it from Swift
// traps in the bridge, which crashed the extension on every launch on PR #282's first
// device build. The compiler cannot help there: optional chaining on a non-optional is
// a *compile error*, so there is no way to guard the read in Swift.
//
// ObjC has no such problem: a nil object is a value. This file is the whole fix — it
// reads the property where nil is representable and hands Swift an Optional.
//
// #361 decision 7 is what made the read necessary. The keyboard now owns the tail of a
// dictation, and the measurement on 2026-08-23 found that an extension dismissed
// mid-generation is not killed but *suspended*: one generation resumed and completed
// forty-four minutes later. Without an identity check, that result would be typed into
// whatever document held focus at that moment. This is how the keyboard asks whether
// the field in front of the user is still the one the dictation came from.
#import "TextProxyIdentity.h"

@implementation DictusTextProxyIdentity

+ (nullable NSUUID *)documentIdentifierOf:(id<UITextDocumentProxy>)proxy {
    if (proxy == nil) {
        return nil;
    }
    // Guarded rather than assumed: the property is iOS 11+ on the protocol, but the
    // object behind a proxy is supplied by the host process, and a selector check
    // costs nothing on a path that runs twice per dictation.
    if (![proxy respondsToSelector:@selector(documentIdentifier)]) {
        return nil;
    }
    return proxy.documentIdentifier;
}

@end
