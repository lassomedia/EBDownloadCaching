#import "EBDownloadCache.h"
#import <libkern/OSAtomic.h>
#import <pthread.h>
#import <EBFoundation/EBFoundation.h>
#import "EBDownload.h"

@interface EBCacheDownload : EBDownload
{
    @public
    NSString *_key;
    EBDownloadCacheHandler _handler;
    BOOL _fromDiskCache;
}

@end

@implementation EBCacheDownload
@end

@implementation EBDownloadCache

#pragma mark - Methods -
- (EBDownload *)downloadURL: (NSURL *)url handler: (EBDownloadCacheHandler)handler
{
        NSParameterAssert(url);
        NSParameterAssert(handler);
    
    NSString *urlString = [url absoluteString];
        EBAssertOrRecover(urlString, return nil);
    
    id <NSObject> object = (_synchronousFromDisk ? [self objectForKey: urlString] : [[self memoryCache] objectForKey: urlString]);
        if (object)
        {
            handler(nil, object);
            return nil;
        }
    
    /* If we get here, we don't have an object, either because no in-memory object exists for the key, and if
       _synchronousFromDisk is YES, no on-disk data exists either. */
    
    /* Only if _synchronousFromDisk == NO are we going to ask the disk cache for an already-downloaded copy of the URL. If
       _synchronousFromDisk == YES, we already consulted the disk cache (above), and since we're still executing, we know
       the disk cache returned nothing for the URL. */
    NSURL *localURL = (!_synchronousFromDisk ? [[self diskCache] startAccessForKey: urlString] : nil);
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
    
    download->_key = urlString;
    download->_handler = handler;
    download->_fromDiskCache = (bool)localURL;
    [download start];
    
    return download;
}

#pragma mark - Private Methods -
- (void)handleDownload: (EBCacheDownload *)download
{
        NSParameterAssert(download);
    
    id <NSObject> object = nil;
    EBTry:
    {
        /* If we're downloading from disk, we need to balance our -startAccessForKey: call made in downloadURL:. */
        if (download->_fromDiskCache)
            [[self diskCache] finishAccess];
        
            /* ## Verify that the download's still valid. If it's been invalidated, we'll skip generating the object from the data. */
            EBConfirmOrPerform([download valid], goto EBFinish);
            /* ## */
        
        EBDownloadState downloadState = [download state];
        NSData *data = [download data];
            /* Verify that our state is coherent or something's seriously wrong */
            EBAssertOrBail((downloadState == EBDownloadStateSucceeded && data) || downloadState == EBDownloadStateFailed || downloadState == EBDownloadStateCancelled);
            /* Verify that we succeeded (and therefore that we have data) */
            EBConfirmOrPerform(downloadState == EBDownloadStateSucceeded, goto EBFinish);
        
        /* Convert the data to an object */
        object = [[self transformer] transformedValue: data];
            EBAssertOrRecover(object, goto EBFinish);
        
        /* Put the object in our memory cache */
        [[self memoryCache] setObject: object forKey: download->_key cost: [data length]];
        
        /* If the download wasn't from the disk cache, store the data in the disk cache in the background. */
        if (!download->_fromDiskCache)
        {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),
                ^{
                    [[self diskCache] setData: data forKey: download->_key];
                });
        }
    }
    
    EBFinish:
    {
        /* Call the download's handler on the appropriate queue. */
        dispatch_async(EBValueOrFallback(_asyncHandlerQueue, dispatch_get_main_queue()),
            ^{
                download->_handler(download, object);
            });
    }
}

@end