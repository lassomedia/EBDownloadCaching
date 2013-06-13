#import <Foundation/Foundation.h>
@class EBDownload;
@class EBDiskCache;

typedef void (^EBDownloadCacheHandler)(EBDownload *download, id <NSObject> object);

@interface EBDownloadCache : NSObject

/* ## Creation */
- (id)initWithMemoryCache: (NSCache *)memoryCache diskCache: (EBDiskCache *)diskCache;

/* ## Properties */
@property(nonatomic, readonly) NSCache *memoryCache;
@property(nonatomic, readonly) EBDiskCache *diskCache;

/* ## Methods */
/* If an object exists in memoryCache for the given URL, this method calls the block synchronously with the object (and with
   'download' argument to the block being nil), and returns nil.
   
   If data exists in diskCache, an EBDownload object is started for the local URL in diskCache.
   
   Otherwise, the data is downloaded from 'url'.
   
   'handler' is always called, even if the download was invalidated. Clients should check the EBDownload's 'valid' state
   within the handler if clients use EBDownload's -invalidate method to cancel downloads. */
- (EBDownload *)downloadURL: (NSURL *)url handler: (EBDownloadCacheHandler)handler;

/* First checks memoryCache for a matching object, returning it if one exists. If an object doesnt exist in memoryCache,
   checks diskCache for matching data. If data exists for 'url', this method synchronously reads the data from disk, creates
   an object from the data (via -transformDataForDownload:), places it in memoryCache, and returns the object. */
- (id <NSObject>)cachedObjectForURL: (NSURL *)url;

/* ## Subclass Methods */
/* Subclasses should override this method to transform the supplied data into an object, or return nil on failure. */
- (id <NSObject>)transformData: (NSData *)data;

@end