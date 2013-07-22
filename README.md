EBDownloadCaching is a framework that includes several classes that implement performant HTTP downloading and caching; the various components are described below.

## EBDownload

EBDownload is a class encapsulating a single-use download from a HTTP/HTTPS URL. EBDownload offers performant downloading by using [libcurl](http://curl.haxx.se) under the hood, and provides a simple block-based interface to supply the resulting download data and status. Clients can use EBDownload directly to easily download the contents of URLs, or alternatively use the caching classes described below to add a layer of caching and avoid downloading data unnecessarily.

An EBDownload instance can be used safely from multiple threads simultaneously.

## EBDownloadCache

EBDownloadCache provides caching functionality for the data retrieved by an EBDownload, supporting two levels of caching: in-memory caching using NSCache, and on-disk caching using EBDiskCache.

## EBImageDownloadCache

EBImageDownloadCache is a simple subclass of EBDownloadCache that stores CGImages in its in-memory cache, instead of raw data.

## Requirements

- Mac OS 10.8 or iOS 6. (Earlier platforms have not been tested.)

## Integration

1. Integrate [EBFoundation](https://github.com/davekeck/EBFoundation) into your project.
2. Integrate [EBPrimitives](https://github.com/davekeck/EBPrimitives) into your project.
3. Drag EBDownloadCaching.xcodeproj into your project's file hierarchy.
4. In your target's "Build Phases" tab:
    * Add EBDownloadCaching as a dependency ("Target Dependencies" section)
    * Link against libEBDownloadCaching.a ("Link Binary With Libraries" section)
    * Link against Security.framework
    * Link against libz.dylib
    * For products targeting OS X: link against libcurl.dylib
    * For products targeting iOS: link against ImageIO.framework
5. Add `#import <EBDownloadCaching/EBDownloadCaching.h>` to your source files.

## Credits

EBDownloadCaching was created for [Lasso](http://las.so).

## License

EBDownloadCaching is available under the MIT license; see the LICENSE file for more information.