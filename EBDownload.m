// TODO
// We should remove EBDownload's handling of threading and make it a subclass of NSOperation, so it can be put in any queue it wants to be in.

#import "EBDownload.h"
#import <libkern/OSAtomic.h>
#import <sys/stat.h>
#import <EBFoundation/EBFoundation.h>
#import <EBPrimitives/EBPrimitives.h>
#if EBTargetOSX /* On OS X, we use the system's curl implementation and headers. */
#import <curl/curl.h>
#elif EBTargetIOS /* On iOS, we provide our own curl implementation and headers. */
#import "curl/curl.h"
#endif

@implementation EBDownload
{
    EBDownloadState _state;
    NSData *_data;
    BOOL _valid;
    OSSpinLock _lock;
}

static EBConcurrentQueue *gDownloadQueue = nil;

#pragma mark - Creation -
+ (void)initialize
{
    static dispatch_once_t initToken = 0;
    dispatch_once(&initToken,
        ^{
            NSUInteger processorCount = [[NSProcessInfo processInfo] processorCount];
            NSUInteger concurrentOperationLimit = (processorCount <= 1 ? 6 : 32);
            dispatch_queue_priority_t priority = (processorCount <= 1 ? DISPATCH_QUEUE_PRIORITY_BACKGROUND : DISPATCH_QUEUE_PRIORITY_DEFAULT);
            
            gDownloadQueue = [[EBConcurrentQueue alloc] initWithConcurrentOperationLimit: concurrentOperationLimit priority: priority];
        });
}

- (id)initWithURL: (NSURL *)url handler: (EBDownloadHandler)handler
{
        /* We don't require a handler (in case the we're performing the download for side-effects.) */
        NSParameterAssert(url);
    
    if (!(self = [super init]))
        return nil;
    
    _url = url;
    _handler = handler;
    
    _state = EBDownloadStateIdle;
    _data = nil;
    _valid = YES;
    _lock = OS_SPINLOCK_INIT;
    
    return self;
}

+ (id)downloadURL: (NSURL *)url handler: (EBDownloadHandler)handler
{
    EBDownload *download = [[[self class] alloc] initWithURL: url handler: handler];
    [download start];
    return download;
}

#pragma mark - Accessors -
- (EBDownloadState)state
{
    EBDownloadState result = 0;
    OSSpinLockLock(&_lock);
        result = _state;
    OSSpinLockUnlock(&_lock);
    return result;
}

- (NSData *)data
{
    NSData *result = nil;
    OSSpinLockLock(&_lock);
        result = _data;
    OSSpinLockUnlock(&_lock);
    return result;
}

- (BOOL)valid
{
    BOOL result = NO;
    OSSpinLockLock(&_lock);
        result = _valid;
    OSSpinLockUnlock(&_lock);
    return result;
}

#pragma mark - Methods -
- (void)start
{
    OSSpinLockLock(&_lock);
            EBAssertOrBail(_state == EBDownloadStateIdle);
        _state = EBDownloadStateActive;
    OSSpinLockUnlock(&_lock);
    
//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),
    [gDownloadQueue enqueueBlock:
        ^{
//            #warning debug
//            NSLog(@"DOWNLOADING url: %@", _url);
            
            if ([_url isFileURL])
                [self performLocalDownload];
            
            else
                [self performRemoteDownload];
            
            if (_handler)
                _handler(self);
        }
    ];
//    );
}

- (void)invalidate
{
    OSSpinLockLock(&_lock);
        _valid = NO;
    OSSpinLockUnlock(&_lock);
}

#pragma mark - Private Methods -
static size_t curlHandleData(char *data, size_t dataSize, size_t dataCount, NSMutableData *mutableData)
{
        NSCParameterAssert(mutableData);
        EBConfirmOrPerform(data, return 0);
    
    size_t dataLength = (dataSize * dataCount);
        EBConfirmOrPerform(dataLength, return 0);
    
    [mutableData appendBytes: data length: dataLength];
    return dataLength;
}

- (void)performLocalDownload
{
        EBAssertOrBail(_url);
        EBAssertOrBail([_url isFileURL]);
    
    int fd = -1;
    void *bytes = nil;
    NSData *data = nil;
    BOOL valid = NO;
    
    EBTry:
    {
            /* ## Verify again that we haven't been invalidated */
            EBConfirmOrPerform(valid = [self valid], goto EBFinish);
            /* ## */
        
        const char *path = [[_url path] UTF8String];
            EBAssertOrRecover(path, goto EBFinish);
        
        /* Open the file */
        do
        {
            fd = open(path, (O_RDONLY | O_NONBLOCK));
                EBAssertOrRecover(fd >= 0 || errno == EINTR, goto EBFinish);
        } while (fd < 0);
        
            /* ## Verify again that we haven't been invalidated */
            EBConfirmOrPerform(valid = [self valid], goto EBFinish);
            /* ## */
        
        /* Get the file size */
        struct stat fileInfo;
        int fstatResult = fstat(fd, &fileInfo);
            EBAssertOrRecover(!fstatResult, goto EBFinish);
            /* Verify that fileInfo.st_size >= 0 so that we can safely cast it to an unsigned type (uintmax_t). */
            EBAssertOrRecover(fileInfo.st_size >= 0, goto EBFinish);
            /* Verify that fileInfo.st_size can safely fit in a size_t */
            EBAssertOrRecover(EBValueInRange(0, (uintmax_t)SIZE_T_MAX, (uintmax_t)fileInfo.st_size), goto EBFinish);
            
            /* ## Verify again that we haven't been invalidated */
            EBConfirmOrPerform(valid = [self valid], goto EBFinish);
            /* ## */
        
        size_t fileSize = (size_t)fileInfo.st_size;
        /* File size > 0 */
        if (fileSize)
        {
            /* Allocate space to put the file in memory */
            bytes = malloc(fileSize);
                EBAssertOrRecover(bytes, goto EBFinish);
            
                /* ## Verify again that we haven't been invalidated */
                EBConfirmOrPerform(valid = [self valid], goto EBFinish);
                /* ## */
            
            /* Read the entire file into 'bytes' */
            size_t bytesRead = 0;
            do
            {
                ssize_t readResult = read(fd, bytes + bytesRead, EBMin(getpagesize(), fileSize - bytesRead));
                    EBAssertOrRecover(readResult > 0 || (readResult < 0 && (errno == EAGAIN || errno == EINTR)), goto EBFinish);
                
                if (readResult > 0)
                    bytesRead += readResult;
                
                /* ## Verify again that we haven't been invalidated */
                EBConfirmOrPerform(valid = [self valid], goto EBFinish);
                /* ## */
            } while (bytesRead < fileSize);
            
            /* Create our NSData wrapper around 'bytes' */
            data = [NSData dataWithBytesNoCopy: bytes length: fileSize freeWhenDone: YES];
                EBAssertOrRecover(data, goto EBFinish);
        }
        
        /* File size == 0 */
        else
        {
            data = [NSData new];
                EBAssertOrRecover(data, goto EBFinish);
        }
    }
    
    EBFinish:
    {
        if (!data)
        {
            free(bytes),
            bytes = nil;
        }
        
        if (fd >= 0)
        {
            int closeResult = close(fd);
            fd = -1;
            
                EBAssertOrRecover(!closeResult, EBNoOp);
        }
        
        [self updateStateWithData: data cancelled: !valid];
    }
}

- (void)performRemoteDownload
{
        EBAssertOrBail(_url);
        EBAssertOrBail([[_url scheme] caseInsensitiveCompare: @"http"] == NSOrderedSame || [[_url scheme] caseInsensitiveCompare: @"https"] == NSOrderedSame);
    
    CURLM *curlMultiHandle = nil;
    CURL *curlEasyHandle = nil;
    BOOL removeEasyHandle = NO;
    NSData *data = nil;
    BOOL valid = NO;
    
    EBTry:
    {
            /* ## Verify again that we haven't been invalidated */
            EBConfirmOrPerform(valid = [self valid], goto EBFinish);
            /* ## */
        
        curlMultiHandle = curl_multi_init();
            EBAssertOrRecover(curlMultiHandle, goto EBFinish);
        
        curlEasyHandle = curl_easy_init();
            EBAssertOrRecover(curlEasyHandle, goto EBFinish);
        
        const char *url = [[_url absoluteString] UTF8String];
            EBAssertOrRecover(url, goto EBFinish);
        
        CURLcode curlResult = curl_easy_setopt(curlEasyHandle, CURLOPT_URL, url);
            EBAssertOrRecover(curlResult == CURLE_OK, goto EBFinish);
        
        curlResult = curl_easy_setopt(curlEasyHandle, CURLOPT_FOLLOWLOCATION, (long)YES);
            EBAssertOrRecover(curlResult == CURLE_OK, goto EBFinish);
        
        curlResult = curl_easy_setopt(curlEasyHandle, CURLOPT_WRITEFUNCTION, curlHandleData);
            EBAssertOrRecover(curlResult == CURLE_OK, goto EBFinish);
        
        NSMutableData *mutableData = [NSMutableData new];
        curlResult = curl_easy_setopt(curlEasyHandle, CURLOPT_WRITEDATA, mutableData);
            EBAssertOrRecover(curlResult == CURLE_OK, goto EBFinish);
        
        CURLMcode curlMultiResult = curl_multi_add_handle(curlMultiHandle, curlEasyHandle);
            EBAssertOrRecover(curlMultiResult == CURLE_OK, goto EBFinish);
        
        /* Necessary so we know whether to remove the easy handle during cleanup. */
        removeEasyHandle = YES;
        
        /* ## Poll for the transfer to complete, or to be interrupted by -invalidate. */
        for (;;)
        {
                /* ## Verify again that we haven't been invalidated */
                EBConfirmOrPerform(valid = [self valid], goto EBFinish);
                /* ## */
            
            int activeCurlHandleCount = 0;
            curlMultiResult = curl_multi_perform(curlMultiHandle, &activeCurlHandleCount);
                EBAssertOrRecover(curlMultiResult == CURLE_OK, goto EBFinish);
            
                /* If we no longer have any active curl handles, then our download is probably complete, so we'll break. */
                if (activeCurlHandleCount <= 0)
                    break;
            
                /* ## Verify again that we haven't been invalidated */
                EBConfirmOrPerform(valid = [self valid], goto EBFinish);
                /* ## */
            
            usleep(1000);
        }
        
        int remainingMessageCount = 0;
        CURLMsg *curlMessage = curl_multi_info_read(curlMultiHandle, &remainingMessageCount);
            EBAssertOrRecover(curlMessage, goto EBFinish);
            EBAssertOrRecover(curlMessage->easy_handle == curlEasyHandle, goto EBFinish);
            EBAssertOrRecover(curlMessage->msg == CURLMSG_DONE, goto EBFinish);
            EBAssertOrRecover(curlMessage->data.result == CURLE_OK, goto EBFinish);
        
        data = mutableData;
    }
    
    EBFinish:
    {
        if (removeEasyHandle)
        {
            CURLcode curlResult = curl_multi_remove_handle(curlMultiHandle, curlEasyHandle);
                EBAssertOrRecover(curlResult == CURLE_OK, EBNoOp);
            
            removeEasyHandle = NO;
        }
        
        if (curlEasyHandle)
        {
            curl_easy_cleanup(curlEasyHandle);
            curlEasyHandle = nil;
        }
        
        if (curlMultiHandle)
        {
            CURLMcode curlMultiResult = curl_multi_cleanup(curlMultiHandle);
                EBAssertOrRecover(curlMultiResult == CURLE_OK, EBNoOp);
            
            curlMultiHandle = nil;
        }
        
        [self updateStateWithData: data cancelled: !valid];
    }
}

- (void)updateStateWithData: (NSData *)data cancelled: (BOOL)cancelled
{
    OSSpinLockLock(&_lock);
            /* We can only be in the Downloading state here! */
            EBAssertOrBail(_state == EBDownloadStateActive);
        
        /* If we have data then we succeeded, plain and simple. */
        if (data)
        {
            _state = EBDownloadStateSucceeded;
            _data = data;
        }
        
        /* If we don't have data, then our state depends on whether the download was cancelled. (If we weren't cancelled,
           and we don't have data, then the download failed.) */
        else
            _state = (cancelled ? EBDownloadStateCancelled : EBDownloadStateFailed);
    OSSpinLockUnlock(&_lock);
}

@end