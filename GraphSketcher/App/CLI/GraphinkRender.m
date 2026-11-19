// graphink render: draw a Graphink document to PDF, PNG, JPEG or TIFF with File ▸ Export's own functions.
// The input is only read; nothing is saved back to it.
#import "GraphinkCLI.h"
#import "RSPageGeometry.h"

void GICRenderUsage(FILE *out)
{
    fputs("Usage: graphink render INPUT -o OUTPUT [--dpi N | --scale N] [--force]\n"
          "       graphink render INPUT --info [--dpi N | --scale N]\n"
          "\n"
          "Draws INPUT (.graphink, or a GraphSketcher .ograph) the way File > Export does.\n"
          "The OUTPUT extension picks the format: .pdf (vector, page = canvas), or .png, .jpg/.jpeg,\n"
          ".tif/.tiff (raster).\n"
          "\n"
          "  -o, --output PATH  file to write; an existing file is refused unless --force\n"
          "  --dpi N            raster resolution, 1-1200 (default 72: one pixel per point);\n"
          "                     the export panel offers 72, 144, 150 and 300\n"
          "  --scale N          the same as --dpi 72*N (--scale 2 = 144 DPI)\n"
          "  --force            replace OUTPUT if it exists (never INPUT or a directory)\n"
          "  --info             print the canvas size and pixel size, then exit\n"
          "\n"
          "Exit status: 0 written, 1 read/render/write failure, 2 invalid arguments.\n", out);
}

// A positive finite number and nothing else ("72", "1.5"); not "", "abc", "72abc", "0", "-2" or "inf".
static BOOL ParsePositive(const char *text, double *value)
{
    char *end = NULL;
    errno = 0;
    *value = strtod(text, &end);
    return end != text && *end == '\0' && errno == 0 && isfinite(*value) && *value > 0;
}

int GICRenderMain(int argc, const char *argv[])
{
    @autoreleasepool {
        NSString *input = nil, *output = nil; double dpi = 72, scale = 1; BOOL dpiGiven = NO, scaleGiven = NO, force = NO, info = NO;
        for (int i = 1; i < argc; i++) {
            NSString *arg = @(argv[i]);
            BOOL hasValue = i + 1 < argc;
            if ([arg isEqual:@"-h"] || [arg isEqual:@"--help"]) { GICRenderUsage(stdout); return GICExitOK; }
            else if (([arg isEqual:@"-o"] || [arg isEqual:@"--output"]) && hasValue) output = @(argv[++i]);
            else if (([arg isEqual:@"--dpi"] || [arg isEqual:@"--scale"]) && hasValue) {
                BOOL isDPI = [arg isEqual:@"--dpi"];
                if (!ParsePositive(argv[++i], isDPI ? &dpi : &scale)) {
                    fprintf(stderr, "graphink render: %s needs a positive number, not '%s'\n", argv[i - 1], argv[i]);
                    return GICExitUsage;
                }
                if (isDPI) dpiGiven = YES; else scaleGiven = YES;
            }
            else if ([arg isEqual:@"--force"]) force = YES;
            else if ([arg isEqual:@"--info"]) info = YES;
            else if (![arg hasPrefix:@"-"] && !input) input = arg;
            else { fprintf(stderr, "graphink render: unexpected argument %s\n\n", argv[i]); GICRenderUsage(stderr); return GICExitUsage; }
        }
        if (!input || (!output && !info)) { GICRenderUsage(stderr); return GICExitUsage; }
        if (dpiGiven && scaleGiven) { fputs("graphink render: pass --dpi or --scale, not both\n", stderr); return GICExitUsage; }
        if (scaleGiven) dpi = 72 * scale;
        if (!(dpi >= 1 && dpi <= 1200)) { fputs("graphink render: the resolution must be 1-1200 DPI\n", stderr); return GICExitUsage; }
        NSDictionary *types = @{@"pdf":@"com.adobe.pdf", @"png":@"public.png", @"jpg":@"public.jpeg", @"jpeg":@"public.jpeg", @"tif":@"public.tiff", @"tiff":@"public.tiff"};
        NSString *type = output ? types[output.pathExtension.lowercaseString] : nil;
        if (output && !type) { fprintf(stderr, "graphink render: unknown output type .%s (use .pdf, .png, .jpg or .tiff)\n", output.pathExtension.UTF8String); return GICExitUsage; }

        int status = GICExitOK;
        GICDocument *document = nil;
        @try {
            GICStart();
            document = [GICDocument documentWithContentsOfFile:input];
            CGSize points = document.graph.canvasSize, pixels = RSRasterPixelSize(points, dpi);
            if (info) {
                printf("%s: canvas %.0f × %.0f pt; raster %.0f × %.0f px at %g DPI\n", input.UTF8String, points.width, points.height, pixels.width, pixels.height, dpi);
            } else {
                BOOL pdf = [type isEqual:@"com.adobe.pdf"];
                NSData *data = pdf ? GICPDFData(document) : GICRasterData(document, dpi, type);
                GICWrite(data, output, force, input);
                if (pdf) printf("wrote %s (PDF, %.0f × %.0f pt)\n", output.UTF8String, points.width, points.height);
                else printf("wrote %s (%.0f × %.0f px at %g DPI)\n", output.UTF8String, pixels.width, pixels.height, dpi);
            }
        } @catch (NSException *exception) {
            fprintf(stderr, "graphink render: %s\n", exception.reason.UTF8String);
            status = GICExitFailure;
        } @finally {
            [document invalidate];
            GICStop();
        }
        return status;
    }
}
