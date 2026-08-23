// DictusKeyboard/TextProxyIdentity.h
// Reads UITextDocumentProxy.documentIdentifier without trapping. See the .m.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DictusTextProxyIdentity : NSObject

/// The identifier of the document `proxy` is editing, or nil when the host has not
/// established an input session yet.
+ (nullable NSUUID *)documentIdentifierOf:(id<UITextDocumentProxy>)proxy;

@end

NS_ASSUME_NONNULL_END
