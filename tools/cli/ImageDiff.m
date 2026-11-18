// ImageDiff A B [DIFF.png]: compare two raster images pixel by pixel (both drawn onto white, sRGB, 8 bits)
// and print one JSON line.
// ImageDiff --rasterize-pdf IN.pdf OUT.png [SCALE]: rasterize page 1 at SCALE × 72 DPI (default 1) exactly as
// Examples/Tools/GenerateCatalog.m and Examples/InitialFTUX made the example previews (DeviceRGB, white page), to
// compare drawing apart from the raster color space.
// Used by tools/cli/check-cli.py; not installed with the tools.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

static uint8_t *Pixels(NSString *path, size_t *width, size_t *height)
{
    CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)[NSURL fileURLWithPath:path], NULL);
    CGImageRef image = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
    if (source) CFRelease(source);
    if (!image) { fprintf(stderr, "ImageDiff: cannot read %s\n", path.UTF8String); exit(2); }
    *width = CGImageGetWidth(image); *height = CGImageGetHeight(image);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    uint8_t *pixels = calloc(*width * *height, 4);
    CGContextRef context = CGBitmapContextCreate(pixels, *width, *height, 8, *width * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, *width, *height));
    CGContextDrawImage(context, CGRectMake(0, 0, *width, *height), image);
    CGContextRelease(context); CGColorSpaceRelease(space); CGImageRelease(image);
    return pixels;
}

static int RasterizePDF(NSString *input, NSString *output, CGFloat scale)
{
    CGPDFDocumentRef pdf = CGPDFDocumentCreateWithURL((CFURLRef)[NSURL fileURLWithPath:input]);
    if (!pdf || CGPDFDocumentGetNumberOfPages(pdf) != 1) { fprintf(stderr, "ImageDiff: %s is not a one-page PDF\n", input.UTF8String); return 2; }
    CGPDFPageRef page = CGPDFDocumentGetPage(pdf, 1);
    CGRect box = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate(NULL, box.size.width * scale, box.size.height * scale, 8, 0, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextScaleCTM(bitmap, scale, scale);
    CGContextSetRGBFillColor(bitmap, 1, 1, 1, 1); CGContextFillRect(bitmap, CGRectMake(0, 0, box.size.width, box.size.height));
    CGContextDrawPDFPage(bitmap, page);
    CGImageRef image = CGBitmapContextCreateImage(bitmap);
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((CFURLRef)[NSURL fileURLWithPath:output], CFSTR("public.png"), 1, NULL);
    CGImageDestinationAddImage(destination, image, NULL);
    BOOL written = CGImageDestinationFinalize(destination);
    CFRelease(destination); CGImageRelease(image); CGContextRelease(bitmap); CGColorSpaceRelease(space); CGPDFDocumentRelease(pdf);
    return written ? 0 : 1;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if ((argc == 4 || argc == 5) && !strcmp(argv[1], "--rasterize-pdf")) return RasterizePDF(@(argv[2]), @(argv[3]), argc == 5 ? atof(argv[4]) : 1);
        if (argc < 3) { fputs("Usage: ImageDiff A B [DIFF.png]\n", stderr); return 2; }
        size_t aw, ah, bw, bh;
        uint8_t *a = Pixels(@(argv[1]), &aw, &ah), *b = Pixels(@(argv[2]), &bw, &bh);
        if (aw != bw || ah != bh) {
            printf("{\"sameSize\": false, \"a\": [%zu, %zu], \"b\": [%zu, %zu]}\n", aw, ah, bw, bh);
            return 1;
        }
        size_t n = aw * ah, any = 0, over16 = 0, over64 = 0; unsigned maximum = 0; double total = 0;
        uint8_t *diff = calloc(n, 4);
        for (size_t i = 0; i < n; i++) {
            unsigned d = 0;
            for (int c = 0; c < 3; c++) { unsigned v = abs((int)a[4*i+c] - (int)b[4*i+c]); if (v > d) d = v; total += v; }
            if (d) any++;
            if (d > 16) over16++;
            if (d > 64) over64++;
            if (d > maximum) maximum = d;
            // Differences in red on a faded copy of A.
            uint8_t gray = (uint8_t)(255 - (255 - a[4*i+1]) / 4);
            diff[4*i] = d > 16 ? 255 : gray; diff[4*i+1] = d > 16 ? 0 : gray; diff[4*i+2] = d > 16 ? 0 : gray; diff[4*i+3] = 255;
        }
        if (argc > 3) {
            CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef context = CGBitmapContextCreate(diff, aw, ah, 8, aw * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
            CGImageRef image = CGBitmapContextCreateImage(context);
            CGImageDestinationRef destination = CGImageDestinationCreateWithURL((CFURLRef)[NSURL fileURLWithPath:@(argv[3])], CFSTR("public.png"), 1, NULL);
            CGImageDestinationAddImage(destination, image, NULL);
            CGImageDestinationFinalize(destination);
            CFRelease(destination); CGImageRelease(image); CGContextRelease(context); CGColorSpaceRelease(space);
        }
        printf("{\"sameSize\": true, \"size\": [%zu, %zu], \"pixels\": %zu, \"differing\": %zu, \"over16\": %zu, \"over64\": %zu, "
               "\"maxChannelDiff\": %u, \"meanChannelDiff\": %.4f}\n", aw, ah, n, any, over16, over64, maximum, total / (3.0 * n));
        free(a); free(b); free(diff);
        return 0;
    }
}
