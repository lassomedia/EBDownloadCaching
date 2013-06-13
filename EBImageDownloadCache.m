#import "EBImageDownloadCache.h"
#import <ImageIO/ImageIO.h>
#import <EBFoundation/EBFoundation.h>

@implementation EBImageDownloadCache

- (id <NSObject>)transformData: (NSData *)data
{
        NSParameterAssert(data);
    
    id imageSource = CFBridgingRelease(CGImageSourceCreateWithData((__bridge CFDataRef)data, nil));
        EBAssertOrRecover(imageSource, return nil);
    
    id image = CFBridgingRelease(CGImageSourceCreateImageAtIndex((__bridge CGImageSourceRef)imageSource, 0, nil));
        EBAssertOrRecover(image, return nil);
    
    return image;
}

@end