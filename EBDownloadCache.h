#import <Foundation/Foundation.h>
#import <EBPrimitives/EBPrimitives.h>
@class EBDownload;

typedef void (^EBDownloadCacheHandler)(EBDownload *download, id <NSObject> object);

@interface EBDownloadCache : EBTwoLevelCache

/* The queue on which handler blocks are executed. Nil (the default) signifies the main queue. */
@property(nonatomic, strong) dispatch_queue_t asyncHandlerQueue;

/* Controls whether reads from disk should be synchronous from within -downloadURL:. NO by default. */
@property(nonatomic) BOOL synchronousFromDisk;

/* ## Methods */
/* If an object exists in the memory cache (or the disk cache if `synchronousFromDisk` is YES) for the given URL, `handler`
   is executed synchronously within -downloadURL:, with `nil` for `download` along with the object, and -downloadURL:
   returns `nil`.
   
   Otherwise, the data is downloaded asynchronously from the URL (either from disk if it's cached there, or over the network) and
   `handler` is called on `asyncHandlerQueue`. */
- (EBDownload *)downloadURL: (NSURL *)url handler: (EBDownloadCacheHandler)handler;

@end