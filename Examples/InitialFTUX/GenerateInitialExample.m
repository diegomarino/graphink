// Original first-launch example; production model construction, serialization and rendering.
// All text and geometry come from layout.json so the content can be revised without code changes.
#import <Cocoa/Cocoa.h>
#import <OmniFoundation/OmniFoundation.h>
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphArchive.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <GraphSketcherModel/RSUndoerOwner.h>
#import <GraphSketcherModel/RSVertex.h>
#import <GraphSketcherModel/RSConnectLine.h>
#import <GraphSketcherModel/RSGroup.h>
#import <GraphSketcherModel/RSFill.h>
#import <GraphSketcherModel/RSTextLabel.h>
#import <GraphSketcherModel/RSDataMapper.h>
#import <GraphSketcherModel/RSGraphRenderer.h>
#import <GraphSketcherModel/RSGraphEditor.h>

static void Check(BOOL ok, NSString *message) {
    if (!ok) [NSException raise:@"ExampleCheckFailure" format:@"%@", message];
}
@interface ExampleOwner : NSObject <RSUndoerOwner>
@property(nonatomic, retain) NSUndoManager *undoManager;
@end
@implementation ExampleOwner
@synthesize undoManager = _undoManager;
- (id)init { if ((self = [super init])) { _undoManager = [[NSUndoManager alloc] init]; _undoManager.groupsByEvent = NO; } return self; }
- (void)undoerPerformedChange:(RSUndoer *)undoer {}
- (void)dealloc { [_undoManager release]; [super dealloc]; }
@end
@interface ExampleController : OFController
@end
@implementation ExampleController
- (BOOL)crashOnAssertionOrUnhandledException { return YES; }
- (void)handleFailureInMethod:(SEL)s object:(id)o file:(NSString *)f lineNumber:(int)n format:(NSString *)fmt arguments:(va_list)a {
    fprintf(stderr,"FATAL ASSERTION %s:%d\n",f.UTF8String,n); _Exit(3);
}
- (void)handleFailureInFunction:(NSString *)s file:(NSString *)f lineNumber:(int)n format:(NSString *)fmt arguments:(va_list)a {
    fprintf(stderr,"FATAL ASSERTION %s:%d\n",f.UTF8String,n); _Exit(3);
}
@end

static NSDictionary *Layout;
static NSColor *Named(NSString *name) {
    NSArray *c = Layout[@"palette"][name]; Check(c.count==3,[@"Unknown palette color " stringByAppendingString:name?:@"(nil)"]);
    return [NSColor colorWithSRGBRed:[c[0] doubleValue] green:[c[1] doubleValue] blue:[c[2] doubleValue] alpha:1];
}
static RSDataPoint DataPoint(NSArray *p) { Check(p.count==2,@"Point needs two coordinates"); return RSDataPointMake([p[0] doubleValue],[p[1] doubleValue]); }
static NSDictionary *TextAttributes(CGFloat size, BOOL bold, NSColor *color) {
    NSFont *font = [NSFont fontWithName:bold ? @"HelveticaNeue-Medium" : @"HelveticaNeue" size:size];
    Check(font != nil, @"Required system Helvetica Neue face unavailable; do not silently substitute");
    return @{NSFontAttributeName:font, NSForegroundColorAttributeName:color};
}
static RSTextLabel *Label(RSGraph *g, NSString *text, RSDataPoint at, CGFloat size, BOOL bold, NSColor *color) {
    RSTextLabel *label = [[[RSTextLabel alloc] initWithGraph:g identifier:nil
        attributedString:[[[NSAttributedString alloc] initWithString:text attributes:TextAttributes(size,bold,color)] autorelease]
        position:at rotation:0] autorelease];
    [g addLabel:label]; return label;
}
static RSVertex *Vertex(RSGraph *g, NSMutableDictionary *shared, RSDataPoint p, NSColor *color, CGFloat width, NSInteger shape) {
    NSString *key = [NSString stringWithFormat:@"%.8g,%.8g",p.x,p.y];
    RSVertex *v = shared ? shared[key] : nil;
    if (!v) {
        v = [[[RSVertex alloc] initWithGraph:g identifier:nil point:p width:width color:color shape:shape] autorelease];
        [g addVertex:v]; if (shared) shared[key] = v;
    }
    return v;
}
static RSGroup *Vertices(RSGraph *g, NSMutableDictionary *shared, NSArray *points, NSColor *color, CGFloat width, NSInteger shape) {
    NSMutableArray *vs = [NSMutableArray array];
    for (NSArray *p in points) [vs addObject:Vertex(g,shared,DataPoint(p),color,width,shape)];
    return [[[RSGroup alloc] initWithGraph:g byCopyingArray:vs] autorelease];
}
static RSConnectLine *Line(RSGraph *g, RSGroup *vertices, NSColor *color, CGFloat width, RSConnectType method) {
    RSConnectLine *line = [[[RSConnectLine alloc] initWithGraph:g identifier:nil vertices:vertices
        color:color width:width dash:0 slide:0.5 labelDistance:4] autorelease];
    line.connectMethod = method; [g addLine:line]; return line;
}
static NSInteger Shape(NSString *name) {
    if (!name || [name isEqual:@"none"]) return RS_NONE;
    if ([name isEqual:@"circle"]) return RS_CIRCLE;
    if ([name isEqual:@"hollow"]) return RS_HOLLOW;
    Check(NO,[@"Unknown shape " stringByAppendingString:name]); return RS_NONE;
}

// Builds the graph and records, per layout ID, the objects to check and probe.
static RSGraph *MakeGraph(RSUndoer *undoer, NSMutableDictionary *byID, NSMutableArray *segments) {
    RSGraph *g = [[[RSGraph alloc] initWithIdentifier:nil undoer:undoer] autorelease]; [g setupDefault];
    NSArray *canvas = Layout[@"canvas"]; NSDictionary *w = Layout[@"whitespace"]; NSDictionary *axes = Layout[@"axes"];
    g.canvasSize = CGSizeMake([canvas[0] doubleValue],[canvas[1] doubleValue]);
    g.whitespace = RSMakeBorder([w[@"top"] doubleValue],[w[@"right"] doubleValue],[w[@"bottom"] doubleValue],[w[@"left"] doubleValue]);
    g.autoMaintainsWhitespace = NO; g.backgroundColor = NSColor.whiteColor;
    [g setAxisRangesXMin:[axes[@"x"][0] doubleValue] xMax:[axes[@"x"][1] doubleValue] yMin:[axes[@"y"][0] doubleValue] yMax:[axes[@"y"][1] doubleValue]];
    for (RSAxis *axis in @[g.xAxis,g.yAxis]) {
        axis.placement = RSOriginPlacement; axis.width = 1.5; axis.color = Named(@"ink"); axis.shape = RS_NONE;
        axis.displayTicks = YES; axis.displayTickLabels = YES; axis.displayGrid = NO; axis.displayTitle = NO;
        axis.userSpacing = [axes[@"spacing"] doubleValue]; axis.spacing = axis.userSpacing;
    }
    NSMutableDictionary *shared = [NSMutableDictionary dictionary];
    for (NSDictionary *o in Layout[@"objects"]) {
        NSString *kind = o[@"kind"], *ident = o[@"id"]; Check(ident && !byID[ident],[@"Missing or duplicate layout id " stringByAppendingString:ident?:@"(nil)"]);
        if ([kind isEqual:@"label"]) {
            byID[ident] = Label(g,o[@"text"],DataPoint(o[@"at"]),[o[@"size"] doubleValue],[o[@"bold"] boolValue],Named(o[@"color"]));
        } else if ([kind isEqual:@"curve"] || [kind isEqual:@"line"]) {
            RSGroup *vs = Vertices(g,shared,o[@"points"],Named(o[@"color"]),[o[@"pointWidth"] doubleValue],Shape(o[@"shape"]));
            byID[ident] = Line(g,vs,Named(o[@"color"]),[o[@"width"] doubleValue],[kind isEqual:@"curve"] ? RSConnectCurved : RSConnectStraight);
            NSArray *pts = o[@"points"]; for (NSUInteger i=1;i<pts.count;i++) [segments addObject:@[ident,pts[i-1],pts[i],kind]];
        } else if ([kind isEqual:@"fill"]) {
            RSGroup *vs = Vertices(g,shared,o[@"points"],Named(@"ink"),1.8,RS_NONE);
            RSFill *fill = [[[RSFill alloc] initWithGraph:g identifier:nil vertexGroup:vs
                color:[Named(o[@"color"]) colorWithAlphaComponent:[o[@"alpha"] doubleValue]] placement:CGPointMake(.5,.5)] autorelease];
            [g addFill:fill]; byID[ident] = fill;
            NSArray *pts = o[@"points"]; for (NSUInteger i=0;i<pts.count;i++) [segments addObject:@[ident,pts[i],pts[(i+1)%pts.count],kind]];
        } else if ([kind isEqual:@"target"]) {
            // A small hollow marker with its number; clicking it with Draw/Fill snaps to the marker.
            RSDataPoint at = DataPoint(o[@"at"]); NSColor *color = Named(o[@"color"]);
            byID[ident] = Vertex(g,nil,at,color,5,RS_HOLLOW);
            byID[[ident stringByAppendingString:@".number"]] = Label(g,o[@"number"],RSDataPointMake(at.x+.17,at.y+.1),12,YES,color);
        } else if ([kind isEqual:@"arrow"]) {
            NSColor *guide = Named(@"guide"); NSArray *pts = @[o[@"from"],o[@"to"]];
            RSConnectLine *arrow = Line(g,Vertices(g,nil,pts,guide,1.4,RS_NONE),guide,1.4,RSConnectStraight);
            arrow.endVertex.shape = RS_ARROW; byID[ident] = arrow;
            [segments addObject:@[ident,pts[0],pts[1],kind]];
        } else Check(NO,[@"Unknown layout kind " stringByAppendingString:kind?:@"(nil)"]);
    }
    return g;
}

static NSArray *IDs(RSGraph *g, NSArray *elements) {
    NSMutableArray *ids = [NSMutableArray array]; for (id e in elements) [ids addObject:[g identiferForObject:e]]; return ids;
}
static NSArray *Color(NSColor *c) {
    c = [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; Check(c!=nil,@"Color must convert to sRGB");
    return @[@(c.redComponent),@(c.greenComponent),@(c.blueComponent),@(c.alphaComponent)];
}
static NSDictionary *AxisSnapshot(RSGraph *g, RSAxis *axis) {
    return @{@"id":[g identiferForObject:axis],@"min":@(axis.min),@"max":@(axis.max),@"spacing":@(axis.spacing),@"userSpacing":@(axis.userSpacing),
        @"placement":@(axis.placement),@"width":@(axis.width),@"color":Color(axis.color),@"displayTicks":@(axis.displayTicks),
        @"displayTickLabels":@(axis.displayTickLabels),@"displayTitle":@(axis.displayTitle),@"displayGrid":@(axis.displayGrid)};
}
static NSDictionary *Snapshot(RSGraph *g) {
    NSMutableDictionary *objects = [NSMutableDictionary dictionary];
    for (RSVertex *v in g.Vertices) objects[[g identiferForObject:v]] = @{@"kind":@"vertex",@"x":@(v.position.x),@"y":@(v.position.y),@"shape":@(v.shape),@"width":@(v.width),@"color":Color(v.color)};
    for (RSConnectLine *l in g.Lines) objects[[g identiferForObject:l]] = @{@"kind":@"line",@"vertices":IDs(g,l.vertices.elements),@"method":@(l.connectMethod),@"width":@(l.width),@"dash":@(l.dash),@"color":Color(l.color)};
    for (RSFill *f in g.Fills) objects[[g identiferForObject:f]] = @{@"kind":@"fill",@"vertices":IDs(g,f.vertices.elements),@"color":Color(f.color)};
    for (RSTextLabel *t in g.userLabels) {
        NSFont *font = [[t attributedString] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        objects[[g identiferForObject:t]] = @{@"kind":@"label",@"text":t.text,@"x":@(t.position.x),@"y":@(t.position.y),@"rotation":@(t.rotation),@"font":font.fontName,@"size":@(font.pointSize),@"color":Color(t.color)};
    }
    NSMutableDictionary *defaults = [NSMutableDictionary dictionaryWithDictionary:g.creationDefaults];
    for (NSString *key in @[@"line-color",@"text-color",@"fill-color"]) defaults[key]=Color(defaults[key]);
    return @{@"defaults":defaults,@"objects":objects,@"canvas":@[@(g.canvasSize.width),@(g.canvasSize.height)],@"whitespace":@[@(g.whitespace.top),@(g.whitespace.right),@(g.whitespace.bottom),@(g.whitespace.left)],@"autoWhitespace":@(g.autoMaintainsWhitespace),@"background":Color(g.backgroundColor),@"axes":@[AxisSnapshot(g,g.xAxis),AxisSnapshot(g,g.yAxis)],@"fillCount":@(g.Fills.count)};
}
static void JSON(id data, NSString *path) {
    NSError *e=nil; NSData *bytes=[NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&e];
    Check(bytes && [bytes writeToFile:path options:NSDataWritingWithoutOverwriting error:&e], [NSString stringWithFormat:@"Write JSON %@: %@",path,e]);
}
static BOOL SegmentHitsRect(CGPoint a, CGPoint b, CGRect r) {
    for (NSUInteger i=0;i<=64;i++) { CGFloat t=i/64.0; if (CGRectContainsPoint(r,CGPointMake(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t))) return YES; }
    return NO;
}
// Labels stay inside the canvas, never overlap each other, and no straight segment or marker crosses a label.
static NSDictionary *CheckClearances(RSGraph *g, RSDataMapper *mapper, NSDictionary *byID, NSArray *segments) {
    CGRect canvas=CGRectMake(0,0,g.canvasSize.width,g.canvasSize.height); NSMutableDictionary *rects=[NSMutableDictionary dictionary];
    for (NSString *ident in byID) {
        RSTextLabel *label=byID[ident]; if (![label isKindOfClass:[RSTextLabel class]]) continue;
        CGPoint origin=[mapper convertToViewCoords:label.position]; CGRect r=CGRectMake(origin.x,origin.y,label.size.width,label.size.height);
        Check(CGRectContainsRect(canvas,r),[@"Label clipped by canvas: " stringByAppendingString:ident]);
        rects[ident]=[NSValue valueWithRect:r];
        if (getenv("FTUX_DEBUG")) fprintf(stderr,"RECT %s x=%.1f y=%.1f w=%.1f h=%.1f\n",ident.UTF8String,r.origin.x,r.origin.y,r.size.width,r.size.height);
    }
    NSArray *keys=[rects.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSUInteger i=0;i<keys.count;i++) for (NSUInteger j=i+1;j<keys.count;j++)
        Check(!CGRectIntersectsRect(CGRectInset([rects[keys[i]] rectValue],-2,-2),[rects[keys[j]] rectValue]),[NSString stringWithFormat:@"Labels overlap: %@ / %@",keys[i],keys[j]]);
    for (NSArray *s in segments) {
        CGPoint a=[mapper convertToViewCoords:DataPoint(s[1])], b=[mapper convertToViewCoords:DataPoint(s[2])];
        for (NSString *k in keys) Check(!SegmentHitsRect(a,b,CGRectInset([rects[k] rectValue],-3,-3)),[NSString stringWithFormat:@"%@ crosses label %@",s[0],k]);
    }
    // Arrows cross no line, curve (approximated by its control polygon) or other arrow, and keep clear of visible markers.
    for (NSArray *s in segments) {
        if (![s[3] isEqual:@"arrow"]) continue;
        CGPoint a=[mapper convertToViewCoords:DataPoint(s[1])], b=[mapper convertToViewCoords:DataPoint(s[2])];
        for (NSArray *t in segments) {
            if (t==s || [t[3] isEqual:@"fill"]) continue;
            CGPoint c=[mapper convertToViewCoords:DataPoint(t[1])], d=[mapper convertToViewCoords:DataPoint(t[2])];
            CGFloat d1=(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x), d2=(b.x-a.x)*(d.y-a.y)-(b.y-a.y)*(d.x-a.x);
            CGFloat d3=(d.x-c.x)*(a.y-c.y)-(d.y-c.y)*(a.x-c.x), d4=(d.x-c.x)*(b.y-c.y)-(d.y-c.y)*(b.x-c.x);
            Check(!(d1*d2<0 && d3*d4<0),[NSString stringWithFormat:@"%@ crosses %@",s[0],t[0]]);
        }
        for (RSVertex *v in g.Vertices) {
            if (v.shape==RS_NONE || v.shape==RS_ARROW) continue;
            CGPoint c=[mapper convertToViewCoords:v.position]; CGFloat len2=(b.x-a.x)*(b.x-a.x)+(b.y-a.y)*(b.y-a.y);
            CGFloat t=MAX(0,MIN(1,((c.x-a.x)*(b.x-a.x)+(c.y-a.y)*(b.y-a.y))/len2));
            Check(hypot(a.x+t*(b.x-a.x)-c.x,a.y+t*(b.y-a.y)-c.y)>=14,[NSString stringWithFormat:@"%@ passes too close to a marker",s[0]]);
        }
    }
    for (RSVertex *v in g.Vertices) {
        if (v.shape==RS_NONE || v.shape==RS_ARROW) continue;
        CGPoint c=[mapper convertToViewCoords:v.position]; CGRect marker=CGRectMake(c.x-6,c.y-6,12,12);
        for (NSString *k in keys) Check(!CGRectIntersectsRect(marker,[rects[k] rectValue]),[@"Marker overlaps label " stringByAppendingString:k]);
    }
    NSMutableDictionary *out=[NSMutableDictionary dictionary];
    for (NSString *k in keys) { CGRect r=[rects[k] rectValue]; out[k]=@[@(r.origin.x),@(r.origin.y),@(r.size.width),@(r.size.height)]; }
    return out;
}
static NSData *Render(RSGraph *g, NSString *stem, NSDictionary *byID, NSArray *segments, NSDictionary **outRects) {
    NSMutableData *data=[NSMutableData data]; CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((CFMutableDataRef)data);
    CGRect box=CGRectMake(0,0,g.canvasSize.width,g.canvasSize.height);
    CGContextRef context=CGPDFContextCreate(consumer,&box,NULL); Check(context!=NULL,@"Create PDF context");
    CGPDFContextBeginPage(context,NULL); [NSGraphicsContext saveGraphicsState];
    @try {
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:context flipped:NO]];
        RSDataMapper *mapper=[[[RSDataMapper alloc] initWithGraph:g] autorelease]; mapper.bounds=box;
        RSGraphRenderer *renderer=[[[RSGraphRenderer alloc] initWithMapper:mapper] autorelease];
        [renderer positionAllAxisLabels];
        *outRects=CheckClearances(g,mapper,byID,segments);
        [renderer drawBackgroundWithColor:g.backgroundColor]; [renderer drawAllGraphElementsExcept:nil];
    } @finally { [NSGraphicsContext restoreGraphicsState]; }
    CGPDFContextEndPage(context); CGPDFContextClose(context); CGContextRelease(context); CGDataConsumerRelease(consumer);
    Check([data writeToFile:[stem stringByAppendingString:@".pdf"] atomically:NO],@"Write real PDF");
    // Rasterize the actual PDF at 2x, not a separately drawn approximation.
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((CFDataRef)data); CGPDFDocumentRef pdf=CGPDFDocumentCreateWithProvider(provider);
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap=CGBitmapContextCreate(NULL,box.size.width*2,box.size.height*2,8,0,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    Check(bitmap && CGPDFDocumentGetNumberOfPages(pdf)==1,@"Rasterize one-page native PDF");
    CGContextScaleCTM(bitmap,2,2); CGContextSetRGBFillColor(bitmap,1,1,1,1); CGContextFillRect(bitmap,box); CGContextDrawPDFPage(bitmap,CGPDFDocumentGetPage(pdf,1));
    CGImageRef image=CGBitmapContextCreateImage(bitmap); NSBitmapImageRep *rep=[[[NSBitmapImageRep alloc] initWithCGImage:image] autorelease];
    Check([[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[stem stringByAppendingString:@".png"] atomically:NO],@"Write PDF raster");
    CGImageRelease(image); CGContextRelease(bitmap); CGColorSpaceRelease(space); CGPDFDocumentRelease(pdf); CGDataProviderRelease(provider);
    return data;
}
static void Save(RSGraph *g, NSString *path, NSData *pdf) {
    NSError *e=nil; Check(![[NSFileManager defaultManager] fileExistsAtPath:path],@"Refuse output overwrite");
    NSData *xml=[g generateXMLOfType:RSGraphFileType frame:CGRectZero error:&e]; Check(xml!=nil,[NSString stringWithFormat:@"Native XML: %@",e]);
    Check([pdf length]>=5 && memcmp(pdf.bytes,"%PDF-",5)==0,@"Require real rendered preview");
    Check([RSGraphArchive writeXML:xml defaults:g.creationDefaults preview:pdf encoding:RSGraphArchiveOPC toURL:[NSURL fileURLWithPath:path] error:&e],[NSString stringWithFormat:@"Production OPC save: %@",e]);
}
static RSGraph *Reopen(NSString *path, RSUndoer *undoer) {
    NSError *e=nil; NSInteger encoding=-1;
    RSGraph *g=[RSGraph graphFromURL:[NSURL fileURLWithPath:path] type:RSGraphFileType undoer:undoer encoding:&encoding error:&e];
    Check(g!=nil && encoding==RSGraphArchiveOPC,[NSString stringWithFormat:@"Native OPC reopen %@: %@",path,e]); return g;
}
static id Find(NSArray *elements, BOOL (^match)(id)) { for (id e in elements) if (match(e)) return e; return nil; }

int main(int argc,const char **argv) {
    @autoreleasepool { @try {
        Check(argc==3,@"Expected layout.json and a new output directory");
        NSData *layoutData=[NSData dataWithContentsOfFile:@(argv[1])]; Check(layoutData!=nil,@"Read layout.json");
        NSError *e=nil; Layout=[[NSJSONSerialization JSONObjectWithData:layoutData options:0 error:&e] retain]; Check([Layout isKindOfClass:[NSDictionary class]],[NSString stringWithFormat:@"Parse layout: %@",e]);
        NSString *output=@(argv[2]);
        [NSColor setIgnoresAlpha:NO]; OFController *controller=[OFController sharedController]; [controller didInitialize]; [controller startedRunning];
        ExampleOwner *owner=[[[ExampleOwner alloc] init] autorelease]; RSUndoer *undoer=[[[RSUndoer alloc] initWithOwner:owner] autorelease];
        [owner.undoManager disableUndoRegistration];
        NSMutableDictionary *byID=[NSMutableDictionary dictionary]; NSMutableArray *segments=[NSMutableArray array];
        RSGraph *g=MakeGraph(undoer,byID,segments);
        NSColor *ink=Named(@"ink");
        g.creationDefaults=@{@"font-name":@"HelveticaNeue",@"line-color":ink,@"text-color":ink,@"fill-color":[ink colorWithAlphaComponent:.17]};
        NSString *stem=[output stringByAppendingPathComponent:@"welcome-to-graphink"]; NSDictionary *rects=nil;
        NSData *pdf=Render(g,stem,byID,segments,&rects); JSON(rects,[stem stringByAppendingString:@"-label-rects.json"]);
        JSON(Snapshot(g),[stem stringByAppendingString:@"-before.json"]);
        Save(g,[stem stringByAppendingString:@".graphink"],pdf);
        RSGraph *again=Reopen([stem stringByAppendingString:@".graphink"],undoer); JSON(Snapshot(again),[stem stringByAppendingString:@"-reopen.json"]);
        Save(again,[stem stringByAppendingString:@"-roundtrip.graphink"],pdf);
        RSGraph *twice=Reopen([stem stringByAppendingString:@"-roundtrip.graphink"],undoer); JSON(Snapshot(twice),[stem stringByAppendingString:@"-roundtrip.json"]);

        // Every arrow survives as a native line whose end vertex is an arrowhead on that line.
        NSUInteger arrows=0;
        for (RSConnectLine *l in again.Lines) if (l.endVertex.shape==RS_ARROW) { arrows++; Check([l.endVertex arrowParentIsLine:l],@"Reopened arrowhead belongs to its line"); }
        NSUInteger expectedArrows=0; for (NSDictionary *o in Layout[@"objects"]) if ([o[@"kind"] isEqual:@"arrow"]) expectedArrows++;
        Check(arrows==expectedArrows && arrows>0,@"Every arrow reopens with its arrowhead");

        RSGraphEditor *editor=[[[RSGraphEditor alloc] initWithGraph:again undoer:undoer] autorelease];
        [owner.undoManager enableUndoRegistration]; [undoer endRepetitiveUndo];
        // Moving the shared line vertex carries the fill corner along; undo restores both.
        RSFill *fill=again.Fills.firstObject; Check(fill!=nil,@"Fill reopened");
        RSConnectLine *line=Find(again.Lines,^BOOL(RSConnectLine *l){ return l.connectMethod==RSConnectStraight && l.endVertex.shape!=RS_ARROW; });
        RSVertex *shared=line.endVertex; Check([fill.vertices.elements containsObject:shared],@"Fill corner is the line's vertex");
        RSDataPoint original=shared.position;
        [owner.undoManager beginUndoGrouping]; [editor changeX:original.x-.5 forElement:shared]; [owner.undoManager endUndoGrouping]; [undoer endRepetitiveUndo];
        Check(shared.position.x==original.x-.5,@"Native shared-vertex edit"); [owner.undoManager undo]; Check(shared.position.x==original.x,@"Native shared-vertex undo");
        RSConnectLine *curve=Find(again.Lines,^BOOL(RSConnectLine *l){ return l.connectMethod==RSConnectCurved; });
        RSVertex *v=curve.vertices.elements[1]; original=v.position;
        [owner.undoManager beginUndoGrouping]; [editor changeX:original.x+.25 forElement:v]; [owner.undoManager endUndoGrouping]; [undoer endRepetitiveUndo];
        Check(v.position.x==original.x+.25,@"Native curve point edit"); [owner.undoManager undo]; Check(v.position.x==original.x,@"Native curve point undo");
        RSTextLabel *text=again.userLabels.lastObject; NSString *old=[[text.text copy] autorelease];
        [owner.undoManager beginUndoGrouping]; text.text=@"Editability probe"; [owner.undoManager endUndoGrouping]; [undoer endRepetitiveUndo];
        Check([text.text isEqual:@"Editability probe"],@"Native label edit"); [owner.undoManager undo]; Check([text.text isEqual:old],@"Native label undo");
        NSColor *oldColor=fill.color;
        [owner.undoManager beginUndoGrouping]; fill.color=Named(@"purple"); [owner.undoManager endUndoGrouping]; [undoer endRepetitiveUndo];
        Check([fill.color isEqual:Named(@"purple")],@"Native fill color edit"); [owner.undoManager undo]; Check([fill.color isEqual:oldColor],@"Native fill color undo");
        [owner.undoManager removeAllActions]; [twice invalidate]; [g invalidate]; [editor invalidate];
        printf("PASS example=welcome-to-graphink native-reopens=2 arrows=%lu labels=%lu edits-and-undo=passed\n",(unsigned long)arrows,(unsigned long)rects.count);
        Check([controller requestTermination]==OFControllerTerminateNow,@"Controller termination"); [controller willTerminate];
        puts("COMPLETE examples=1 failed=0"); return 0;
    } @catch(NSException *e) { fprintf(stderr,"FAIL %s\n",e.description.UTF8String); return 1; } }
}
