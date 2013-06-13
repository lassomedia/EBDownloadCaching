// TODO
// - add the ability to download synchronously from disk cache
// - add a 'handlerQueue' property (that defaults to the main queue), where handler blocks are enqueued. this should allow us to remove the checks for sync/async in handler blocks, since we'll know that the blocks are always called on the main thread by default.

#import "EBDownloadCache.h"
#import <libkern/OSAtomic.h>
#import <pthread.h>
#import <EBFoundation/EBFoundation.h>
#import <EBPrimitives/EBPrimitives.h>
#import "EBDownload.h"

@interface EBCacheDownload : EBDownload
{
    @public
    NSURL *_remoteURL;
    EBDownloadCacheHandler _handler;
    BOOL _downloadingFromDiskCache;
}

@end

@implementation EBCacheDownload
@end

@implementation EBDownloadCache

#pragma mark - Creation -
- (id)initWithMemoryCache: (NSCache *)memoryCache diskCache: (EBDiskCache *)diskCache
{
        NSParameterAssert(memoryCache);
        NSParameterAssert(diskCache);
    
    if (!(self = [super init]))
        return nil;
    
    _memoryCache = memoryCache;
    _diskCache = diskCache;
    
    return self;
}

- (id)init
{
    EBRaise(@"%@ cannot be initialized via %@!", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    return nil;
}

#pragma mark - Methods -
- (EBDownload *)downloadURL: (NSURL *)url handler: (EBDownloadCacheHandler)handler
{
        NSParameterAssert(url);
    
    id <NSObject> object = nil;
    
        /* ## Check if the memory cache has an object for 'url', short-circuiting if one exists. */
        object = [_memoryCache objectForKey: url];
        if (object)
        {
            if (handler)
                handler(nil, object);
            
            return nil;
        }
    
    /* ## An object doesn't exist in-memory for 'url', so check the disk cache for an object matching 'url'. */
    NSURL *localURL = [_diskCache startAccessForKey: [url absoluteString]];
    EBCacheDownload *download = [[EBCacheDownload alloc] initWithURL: EBValueOrFallback(localURL, url)
        handler: ^(EBDownload *download)
        {
                NSParameterAssert(download);
            [self handleDownload: (EBCacheDownload *)download];
        }];
    
        /* Something's screwed if we couldn't create our download. */
        EBAssertOrBail(download);
    
//    #warning debug
//    if (!localURL)
//        NSLog(@"DOWNLOADING FROM WEB");
    
    download->_remoteURL = url;
    download->_handler = handler;
    download->_downloadingFromDiskCache = (bool)localURL;
    [download start];
    
    return download;
}

- (id <NSObject>)cachedObjectForURL: (NSURL *)url
{
        NSParameterAssert(url);
    
    id <NSObject> object = [_memoryCache objectForKey: url];
        /* If _memoryCache already had an object for 'url', just return it! */
        if (object)
            return object;
    
    NSData *data = [_diskCache dataForKey: [url absoluteString]];
        EBConfirmOrPerform(data, return nil);
    
    object = [self transformData: data];
        EBAssertOrRecover(object, return nil);
    
    [_memoryCache setObject: object forKey: url];
    return object;
}

#pragma mark - Subclass Methods -
- (id <NSObject>)transformData: (NSData *)data
{
    return data;
}

#pragma mark - Private Methods -
- (void)handleDownload: (EBCacheDownload *)download
{
        NSParameterAssert(download);
    
    id <NSObject> object = nil;
    EBTry:
    {
        if (download->_downloadingFromDiskCache)
            [_diskCache finishAccess];
        
            /* ## Verify that the download's still valid */
            EBConfirmOrPerform([download valid], goto EBFinish);
            /* ## */
        
        EBDownloadState downloadState = [download state];
        NSData *data = [download data];
            /* Sanity-check our download's state. We checked whether the download was still valid above, so it's
               impossible that it's in the Cancelled state, therefore it must either be Succeeded or Failed when
               we get here. */
            EBAssertOrBail((downloadState == EBDownloadStateSucceeded && data) || (downloadState == EBDownloadStateFailed && !data));
        
        if (downloadState == EBDownloadStateSucceeded)
        {
            object = [self transformData: data];
                EBAssertOrRecover(object, EBNoOp);
        }
        
//        #warning DK: debug
//        NSLog(@"FINISHED DOWNLOAD FOR URL: %@", [download url]);
        
        /* If we successfully created an object from the data, store the object in _memoryCache, and its underlying data in _diskCache. (If we
           failed to create an object from the data, we'll throw the data out.) */
        if (object)
        {
            NSURL *remoteURL = download->_remoteURL;
            [_memoryCache setObject: object forKey: remoteURL];
            
            /* If the download wasn't from the disk cache already, store the data in the disk cache in the background. */
            if (!download->_downloadingFromDiskCache)
            {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),
                    ^{
                        [_diskCache setData: data forKey: [remoteURL absoluteString]];
                    });
            }
        }
    }
    
    EBFinish:
    {
        /* Finally, callout to the download's handler, if it has one. */
        if (download->_handler)
            download->_handler(download, object);
    }
}

@end