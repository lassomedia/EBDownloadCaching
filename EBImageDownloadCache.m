#import "EBImageDownloadCache.h"
#import <ImageIO/ImageIO.h>
#import <EBFoundation/EBFoundation.h>

static const NSUInteger kMaxEBDataInMemorySize = 5 * 1024 * 1024; // 5MB

@implementation EBImageDownloadCache

- (instancetype)initWithMemoryCache: (NSCache *)memoryCache diskCache: (EBDiskCache *)diskCache
{
    [memoryCache setTotalCostLimit:kMaxEBDataInMemorySize];
    
    NSValueTransformer *transformer = [EBBlockValueTransformer newWithForwardBlock: ^id(id data)
        {
                /* We have to use NSCParameterAssert, because NSParameterAssert maintains a strong reference to `self`! */
                NSCParameterAssert(data && [data isKindOfClass: [NSData class]]);
            
            id imageSource = CFBridgingRelease(CGImageSourceCreateWithData((__bridge CFDataRef)data, nil));
                EBAssertOrRecover(imageSource, return nil);
            
            id image = CFBridgingRelease(CGImageSourceCreateImageAtIndex((__bridge CGImageSourceRef)imageSource, 0, nil));
                EBAssertOrRecover(image, return nil);
            
            return image;
        }];
    
    return [super initWithMemoryCache: memoryCache diskCache: diskCache transformer: transformer];
}

- (instancetype)initWithMemoryCache: (NSCache *)memoryCache diskCache: (EBDiskCache *)diskCache transformer: (NSValueTransformer *)transformer
{
    EBRaise(@"%@ cannot be initialized via %@!", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    return nil;
}

@end