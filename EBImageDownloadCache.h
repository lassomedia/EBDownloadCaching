#import <Foundation/Foundation.h>
#import <EBDownloadCaching/EBDownloadCache.h>

/* This class supplies CGImageRefs to the handler. */
@interface EBImageDownloadCache : EBDownloadCache
/* ## Creation */
/* Designated initializer */
- (instancetype)initWithMemoryCache: (NSCache *)memoryCache diskCache: (EBDiskCache *)diskCache;
@end