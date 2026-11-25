// graphink: create and export Graphink documents without opening the app.
// It ships at Graphink.app/Contents/Helpers/graphink and in graphink-cli.zip (the same layout), and uses the
// app's frameworks (rpath @executable_path/../Frameworks) and the style fonts of the bundle that contains it.
#import "GraphinkCLI.h"

static void Usage(FILE *out)
{
    fputs("Usage: graphink render INPUT -o OUTPUT.{pdf,svg,png,jpg,tiff} [--dpi N | --scale N] [--force] [--info]\n"
          "       graphink create SPEC.json -o OUTPUT.graphink [--force]\n"
          "       graphink --version\n"
          "       graphink help [render|create]\n"
          "\n"
          "  render  draw a document the way File > Export does\n"
          "  create  build a document from a JSON spec with Graphink's own model\n"
          "\n"
          "Exit status: 0 success, 1 read/spec/render/write failure, 2 invalid arguments.\n", out);
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        NSString *command = argc > 1 ? @(argv[1]) : nil;
        if ([command isEqual:@"render"]) return GICRenderMain(argc - 1, argv + 1);
        if ([command isEqual:@"create"]) return GICCreateMain(argc - 1, argv + 1);
        if ([command isEqual:@"--version"] && argc == 2) {
            printf("graphink %s\n", GICVersion().UTF8String);
            return GICExitOK;
        }
        if ([command isEqual:@"help"] || [command isEqual:@"-h"] || [command isEqual:@"--help"]) {
            NSString *topic = argc > 2 ? @(argv[2]) : nil;
            if (argc > 3) { Usage(stderr); return GICExitUsage; }
            if (!topic) Usage(stdout);
            else if ([topic isEqual:@"render"]) GICRenderUsage(stdout);
            else if ([topic isEqual:@"create"]) GICCreateUsage(stdout);
            else { fprintf(stderr, "graphink: no help for %s\n\n", topic.UTF8String); Usage(stderr); return GICExitUsage; }
            return GICExitOK;
        }
        if (command) fprintf(stderr, "graphink: unknown command %s\n\n", command.UTF8String);
        Usage(stderr);
        return GICExitUsage;
    }
}
