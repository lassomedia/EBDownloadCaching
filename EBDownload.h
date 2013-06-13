#import <Foundation/Foundation.h>
@class EBDownload;

typedef enum : NSUInteger
{
    EBDownloadStateIdle,        /* Transient (changes upon call to -start) */
    EBDownloadStateActive,      /* Transient (changes when the download finishes successfully, fails, or is invalidated) */
    EBDownloadStateSucceeded,   /* Permanent, data != nil */
    EBDownloadStateFailed,      /* Permanent, data == nil */
    EBDownloadStateCancelled    /* Permanent, data == nil; occurs when download is invalidated while in the Active state */
} EBDownloadState;

typedef void (^EBDownloadHandler)(EBDownload *download);

@interface EBDownload : NSObject

/* ## Creation */

/* Designated initializer; -start must be called to initiate the download. */
- (id)initWithURL: (NSURL *)url handler: (EBDownloadHandler)handler;

/* Convenience wrapper -- calls -initWithURL:handler:, followed by -start. */
+ (id)downloadURL: (NSURL *)url handler: (EBDownloadHandler)handler;

/* ## Properties */
@property(readonly) NSURL *url;
@property(readonly) EBDownloadHandler handler;

@property(readonly) EBDownloadState state;
@property(readonly) NSData *data; /* Non-nil if state == Succeeded, nil otherwise. */
@property(readonly) BOOL valid; /* NO if -invalidate has been called, otherwise YES. */

/* ## Methods */

/* If -start is called, the handler block is guaranteed to be called. */
- (void)start;
- (void)invalidate; /* Simply sets the receiver's `valid` property to NO. If the receiver notices the invalidation before the download is complete, the receiver's state will transition to Cancelled. */

@end