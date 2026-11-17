// Original synthetic examples and templates; production model construction, serialization and rendering.
// Same pipeline as the original lessons 01-03 generator, extended to the example catalog.
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

static NSColor *Ink(void) { return [NSColor colorWithSRGBRed:0.12 green:0.18 blue:0.24 alpha:1]; }
static NSColor *Blue(void) { return [NSColor colorWithSRGBRed:0.12 green:0.38 blue:0.66 alpha:1]; }
static NSColor *Teal(void) { return [NSColor colorWithSRGBRed:0.03 green:0.47 blue:0.39 alpha:1]; }
static NSColor *Orange(void) { return [NSColor colorWithSRGBRed:0.72 green:0.31 blue:0.08 alpha:1]; }
static NSColor *Purple(void) { return [NSColor colorWithSRGBRed:0.49 green:0.29 blue:0.62 alpha:1]; }
static NSDictionary *TextAttributes(CGFloat size, BOOL bold, NSColor *color) {
    NSFont *font = [NSFont fontWithName:bold ? @"HelveticaNeue-Medium" : @"HelveticaNeue" size:size];
    Check(font != nil, @"Required system Helvetica Neue face unavailable; do not silently substitute");
    return @{NSFontAttributeName:font, NSForegroundColorAttributeName:color};
}
static void StyleLabel(RSTextLabel *label, NSString *text, CGFloat size, BOOL bold, NSColor *color) {
    [label setAttributedString:[[[NSAttributedString alloc] initWithString:text attributes:TextAttributes(size,bold,color)] autorelease]];
}
static RSTextLabel *Label(RSGraph *g, NSString *text, double x, double y, CGFloat size, BOOL bold, NSColor *color) {
    RSTextLabel *label = [[[RSTextLabel alloc] initWithGraph:g identifier:nil
        attributedString:[[[NSAttributedString alloc] initWithString:text attributes:TextAttributes(size,bold,color)] autorelease]
        position:RSDataPointMake(x,y) rotation:0] autorelease];
    [g addLabel:label]; return label;
}
// Place page annotations in view points while preserving native data-coordinate labels.
static RSDataPoint ViewToData(RSGraph *g, CGFloat x, CGFloat y) {
    RSBorder b = g.whitespace;
    return RSDataPointMake(g.xAxis.min+(x-b.left)/(g.canvasSize.width-b.left-b.right)*(g.xAxis.max-g.xAxis.min),
                           g.yAxis.min+(y-b.bottom)/(g.canvasSize.height-b.bottom-b.top)*(g.yAxis.max-g.yAxis.min));
}
static RSTextLabel *PageLabel(RSGraph *g, NSString *text, CGFloat x, CGFloat y, CGFloat size, BOOL bold, NSColor *color) {
    RSDataPoint d = ViewToData(g,x,y);
    return Label(g,text,d.x,d.y,size,bold,color);
}
// Credits: one line per document, same corner and style everywhere (right-aligned, bottom of the page).
// Lessons and templates cite the concepts' sources; data charts add the inspiration and, for OECD, the sub-licence terms.
static NSString *CreditFor(NSString *stem) {
    NSString *pindyck = @"Concepts: Pindyck & Rubinfeld, Microeconomics 7e, ";
    NSString *inspired = @"Inspired by a chart by Jon González (@jongonzlz) · rebuilt from the official data";
    NSDictionary *credits = @{
        @"01-market-equilibrium":[pindyck stringByAppendingString:@"§2.1, §2.2"],
        @"02-demand-and-supply-shifts":[pindyck stringByAppendingString:@"§2.3"],
        @"03-tax-incidence-and-welfare":[pindyck stringByAppendingString:@"§9.1, §9.6"],
        @"04-binding-price-ceiling":[pindyck stringByAppendingString:@"§2.7, §9.1"],
        @"05-binding-price-floor":[pindyck stringByAppendingString:@"§9.2, §9.3"],
        @"06-monopoly":[pindyck stringByAppendingString:@"§10.1, §10.4"],
        @"07-cost-curves":[pindyck stringByAppendingString:@"§7.2"],
        @"08-budget-and-indifference":[pindyck stringByAppendingString:@"§3.1–3.3"],
        @"09-elasticity-along-demand":[pindyck stringByAppendingString:@"§2.4"],
        @"10-income-and-substitution-effects":[pindyck stringByAppendingString:@"§4.2"],
        @"11-isoquants-and-isocost":[pindyck stringByAppendingString:@"§6.3, §7.3"],
        @"12-competitive-firm-short-run":[pindyck stringByAppendingString:@"§8.4, §8.5"],
        @"13-import-tariff":[pindyck stringByAppendingString:@"§9.5"],
        @"14-monopsony":[pindyck stringByAppendingString:@"§10.5, §10.6"],
        @"15-third-degree-price-discrimination":[pindyck stringByAppendingString:@"§11.2"],
        @"16-cournot-duopoly":[pindyck stringByAppendingString:@"§12.2"],
        @"17-gains-from-trade":[pindyck stringByAppendingString:@"§16.4, §16.5"],
        @"18-negative-externality":[pindyck stringByAppendingString:@"§18.1, §18.2"],
        @"template-market-equilibrium":[pindyck stringByAppendingString:@"§2.1"],
        // Pindyck & Rubinfeld has no Lorenz curve: this template keeps its OpenStax source.
        @"template-lorenz-curve":@"Concepts: OpenStax, Principles of Microeconomics 3e, §15.4",
        @"template-production-possibilities":[pindyck stringByAppendingString:@"§16.4"],
        @"irpf-concentration-2024":inspired,
        @"house-prices-and-wages":inspired,
        @"tax-revenue-share-of-gdp":[inspired stringByAppendingString:@" · OECD terms: keep and pass on this acknowledgment"],
    };
    // Generic graph-type templates teach no sourced concept and carry no credit.
    NSSet *uncredited = [NSSet setWithObjects:@"template-function-plot",@"template-time-series",@"template-scatter-plot",
        @"template-bar-chart",@"template-log-scale",@"template-number-line",nil];
    Check(credits[stem]!=nil || [uncredited containsObject:stem],[@"No credit for " stringByAppendingString:stem]);
    return credits[stem];
}
static NSColor *CreditGray(void) { return [NSColor colorWithSRGBRed:0.36 green:0.41 blue:0.46 alpha:1]; }
static CGRect LabelRect(RSDataMapper *mapper, RSTextLabel *label) {
    CGPoint origin=[mapper convertToViewCoords:label.position];
    return CGRectMake(origin.x,origin.y,label.size.width,label.size.height);
}
static RSTextLabel *Credit(RSGraph *g, NSString *stem) {
    if (!CreditFor(stem)) return nil;
    RSTextLabel *label = PageLabel(g,CreditFor(stem),0,12,10,NO,CreditGray());
    label.position = ViewToData(g,1040-label.size.width,12);  // right edge 40 pt from the page edge, baseline strip below the footer
    RSDataMapper *mapper=[[[RSDataMapper alloc] initWithGraph:g] autorelease]; mapper.bounds=CGRectMake(0,0,g.canvasSize.width,g.canvasSize.height);
    CGRect credit=LabelRect(mapper,label);
    Check(credit.origin.x>=40,[@"Credit too long for one line: " stringByAppendingString:stem]);
    for (RSTextLabel *other in g.userLabels)
        if (other!=label) Check(!CGRectIntersectsRect(CGRectInset(credit,-2,-2),LabelRect(mapper,other)),[NSString stringWithFormat:@"Credit overlaps \"%@\" in %@",other.text,stem]);
    return label;
}
static RSVertex *ExamplePoint(RSGraph *g, NSMutableDictionary *points, double x, double y) {
    NSString *key = [NSString stringWithFormat:@"%.17g,%.17g",x,y];
    RSVertex *v = points[key];
    if (!v) {
        v = [[[RSVertex alloc] initWithGraph:g identifier:nil point:RSDataPointMake(x,y) width:1.8 color:Ink() shape:RS_NONE] autorelease];
        [g addVertex:v]; points[key] = v;
    }
    return v;
}
static RSGroup *Vertices(RSGraph *g, NSMutableDictionary *points, NSArray *coords) {
    NSMutableArray *vs = [NSMutableArray array];
    for (NSArray *p in coords) [vs addObject:ExamplePoint(g,points,[p[0] doubleValue],[p[1] doubleValue])];
    return [[[RSGroup alloc] initWithGraph:g byCopyingArray:vs] autorelease];
}
static RSConnectLine *Line(RSGraph *g, NSMutableDictionary *points, NSArray *coords, NSColor *color, CGFloat width, NSInteger dash) {
    RSConnectLine *line = [[[RSConnectLine alloc] initWithGraph:g identifier:nil vertices:Vertices(g,points,coords)
        color:color width:width dash:dash slide:0.5 labelDistance:4] autorelease];
    line.connectMethod = RSConnectStraight; [g addLine:line]; return line;
}
static void Guide(RSGraph *g, NSMutableDictionary *p, NSArray *coords) {
    Line(g,p,coords,[NSColor colorWithSRGBRed:.50 green:.55 blue:.60 alpha:1],1,2);
}
static void ExampleMarker(RSGraph *g, NSMutableDictionary *p, double x, double y) { ExamplePoint(g,p,x,y).shape = RS_CIRCLE; }
static void ShadedFill(RSGraph *g, NSMutableDictionary *p, NSArray *coords, NSColor *color, CGFloat alpha) {
    RSFill *fill = [[[RSFill alloc] initWithGraph:g identifier:nil vertexGroup:Vertices(g,p,coords)
        color:[color colorWithAlphaComponent:alpha] placement:CGPointMake(.5,.5)] autorelease];
    [g addFill:fill];
}
static void Fill(RSGraph *g, NSMutableDictionary *p, NSArray *coords, NSColor *color) { ShadedFill(g,p,coords,color,.17); }
// A standalone point (not on any line), e.g. a scatter observation or a labelled position.
static RSVertex *LonePoint(RSGraph *g, double x, double y, NSInteger shape, CGFloat width, NSColor *color) {
    RSVertex *v = [[[RSVertex alloc] initWithGraph:g identifier:nil point:RSDataPointMake(x,y) width:width color:color shape:shape] autorelease];
    [g addVertex:v]; return v;
}
// Sample a formula on [a,b] at multiples of step, always including both ends and any extra x values.
// Curves stay straight-connected samples: smoothing must not invent extrema or crossings.
static NSArray *Sampled(double a, double b, double step, NSArray *extra, double (^f)(double)) {
    NSMutableSet *xs = [NSMutableSet setWithObjects:@(a),@(b),nil];
    for (double x=ceil(a/step-1e-9)*step; x<=b+1e-9; x+=step) [xs addObject:@(round(x/step)*step)];
    for (NSNumber *x in extra) [xs addObject:x];
    NSMutableArray *coords = [NSMutableArray array];
    for (NSNumber *x in [xs.allObjects sortedArrayUsingSelector:@selector(compare:)])
        if (x.doubleValue >= a-1e-9 && x.doubleValue <= b+1e-9) [coords addObject:@[x,@(f(x.doubleValue))]];
    return coords;
}

// Options for the graph-type templates: grid lines, logarithmic y axis, a lone x axis (number line), square plot area,
// category labels instead of numeric x ticks.
enum { OptGrid = 1, OptLogY = 2, OptNumberLine = 4, OptSquare = 8, OptCategories = 16 };
typedef struct { const char *stem; BOOL isTemplate; double xMax, yMax, xStep, yStep; const char *xTitle, *yTitle; double xMin, yMin; int options; } DocumentSpec;
static const DocumentSpec Documents[] = {
    {"04-binding-price-ceiling",NO,14,16,2,2,"Quantity Q (units per week)","Price P (dollars per unit)"},
    {"05-binding-price-floor",NO,14,16,2,2,"Quantity Q (units per week)","Price P (dollars per unit)"},
    {"06-monopoly",NO,14,16,2,2,"Quantity Q (units per week)","$/Q (dollars per unit)"},
    {"07-cost-curves",NO,7,90,1,10,"Output q (units per week)","Cost (dollars per unit of output)"},
    {"08-budget-and-indifference",NO,13,10,2,2,"Food F (units per week)","Clothing C (units per week)"},
    // Lessons 09-18 (2026-11-16): one concept each from Pindyck & Rubinfeld 7e, in its notation, with original models and numbers.
    {"09-elasticity-along-demand",NO,14,16,2,2,"Quantity Q (units per week)","Price P (dollars per unit)"},
    {"10-income-and-substitution-effects",NO,13,10,2,2,"Food F (units per week)","Clothing C (units per week)"},
    {"11-isoquants-and-isocost",NO,20,12,2,2,"Labor L (hours per week)","Capital K (machine-hours per week)"},
    {"12-competitive-firm-short-run",NO,7,90,1,10,"Output q (units per week)","Price and cost (dollars per unit)"},
    {"13-import-tariff",NO,14,16,2,2,"Quantity Q (units per week)","Price P (dollars per unit)"},
    {"14-monopsony",NO,14,16,2,2,"Quantity Q (units per week)","$/Q (dollars per unit)"},
    {"15-third-degree-price-discrimination",NO,16,16,2,2,"Quantity Q (units per week)","$/Q (dollars per unit)"},
    {"16-cournot-duopoly",NO,14,14,2,2,"Firm 2's output Q2 (units per week)","Firm 1's output Q1 (units per week)"},
    {"17-gains-from-trade",NO,10,16,2,2,"Food F (units per week)","Clothing C (units per week)"},
    {"18-negative-externality",NO,14,16,2,2,"Quantity Q (units per week)","Price P (dollars per unit)"},
    // Templates, in New From menu order. Placeholder data is illustrative only.
    {"template-function-plot",YES,10,10,2,2,"x","y",-10,-10,OptGrid},
    {"template-time-series",YES,2025,100,5,20,"Year","Value",2010,0},
    {"template-scatter-plot",YES,10,10,2,2,"Variable X","Variable Y"},
    {"template-bar-chart",YES,6,100,1,20,"Category","Value",0,0,OptCategories},
    {"template-log-scale",YES,9,1000,1,10,"Period","Value (log scale)",0,1,OptLogY},
    {"template-number-line",YES,5,1,1,1,"x","y (hidden)",-5,-1,OptNumberLine},
    {"template-market-equilibrium",YES,14,16,2,2,"Quantity Q (units per week)","Price P (dollars per unit)"},
    {"template-lorenz-curve",YES,100,100,20,20,"Cumulative share of population (%)","Cumulative share of income (%)",0,0,OptSquare},
    {"template-production-possibilities",YES,10,10,2,2,"Good X (units)","Good Y (units)"},
    // Data charts: values come from Examples/Data/prepare.py output, passed as the second argument.
    {"irpf-concentration-2024",NO,100,100,10,10,"Cumulative share of returns, ranked by taxable base (%)","Cumulative share (%)"},
    {"house-prices-and-wages",NO,2026,180,2,20,"Year (quarters as decimal years)","Real index (2015 = 100)",2008},
    {"tax-revenue-share-of-gdp",NO,2025,40,5,5,"Year","Total tax revenue (% of GDP)",1965},
};
// Templates keep their axis titles at least this far from the page edge: the kept Supply and Demand template's margin.
static const CGFloat TitleMargin = 58;
static NSDictionary *DataInputs;
static const NSUInteger DocumentCount = sizeof(Documents)/sizeof(Documents[0]);

static RSGraph *BaseGraph(RSUndoer *undoer, DocumentSpec d) {
    RSGraph *g = [[[RSGraph alloc] initWithIdentifier:nil undoer:undoer] autorelease]; [g setupDefault];
    // Lessons keep the delivered page layout; templates drop the side notes and footer space.
    g.canvasSize = CGSizeMake(1080,800); g.whitespace = d.isTemplate ? RSMakeBorder(60,70,120,120) : RSMakeBorder(150,290,190,110);
    g.autoMaintainsWhitespace = NO;
    if (d.options & OptSquare) {
        CGFloat side = g.canvasSize.height-60-120; g.whitespace = RSMakeBorder(60,(g.canvasSize.width-side)/2,120,(g.canvasSize.width-side)/2);
    }
    g.backgroundColor = NSColor.whiteColor;
    if (d.options & OptLogY) [g.yAxis setAxisType:RSAxisTypeLogarithmic];
    [g setAxisRangesXMin:d.xMin xMax:d.xMax yMin:d.yMin yMax:d.yMax];
    for (RSAxis *axis in @[g.xAxis,g.yAxis]) {
        double step = axis==g.xAxis ? d.xStep : d.yStep;
        // Axes cross at the origin unless a range starts above zero (years, log scale): then they sit on the edges.
        axis.placement = (d.xMin>0 || d.yMin>0) ? RSEdgePlacement : RSOriginPlacement; axis.width = 1.5; axis.color = Ink(); axis.shape = RS_NONE;
        axis.displayTicks = YES; axis.displayTickLabels = YES; axis.displayGrid = (d.options & OptGrid) != 0; axis.displayTitle = YES;
        axis.userSpacing = step; axis.spacing = step; axis.titleDistance = 24;
    }
    if (d.options & OptNumberLine) {
        g.yAxis.displayAxis = NO; g.yAxis.displayTicks = NO; g.yAxis.displayTickLabels = NO; g.yAxis.displayTitle = NO;
        g.xAxis.displayTitle = NO;  // the title would sit at the page bottom, far from a line drawn through the middle
        // A short page centred on the line: the content needs about 140 pt of height, not 800.
        g.canvasSize = CGSizeMake(1080,300); g.whitespace = RSMakeBorder(58,90,42,90);
    }
    if (d.options & OptCategories) {
        g.xAxis.displayTicks = NO; g.xAxis.displayTickLabels = NO; g.xAxis.titleDistance = 44;  // room for the category labels
    }
    StyleLabel(g.xAxis.title,@(d.xTitle),15,YES,Ink());
    StyleLabel(g.yAxis.title,@(d.yTitle),15,YES,Ink());
    return g;
}
static RSGraph *MakeGraph(RSUndoer *undoer, DocumentSpec d) {
    RSGraph *g = BaseGraph(undoer,d);
    if (d.isTemplate && !(d.options & OptSquare) && d.xMin >= 0 && d.yMin >= 0) {
        // Axes on the plot edges: wide tick labels (1000 on the log axis) push the plot area in, not the titles out.
        // Measured on a scratch copy: laying out tick labels creates label objects, which would renumber the document.
        ExampleOwner *owner=[[[ExampleOwner alloc] init] autorelease]; RSUndoer *scratchUndoer=[[[RSUndoer alloc] initWithOwner:owner] autorelease];
        [owner.undoManager disableUndoRegistration]; RSGraph *scratch=BaseGraph(scratchUndoer,d);
        RSDataMapper *mapper=[[[RSDataMapper alloc] initWithGraph:scratch] autorelease]; mapper.bounds=CGRectMake(0,0,scratch.canvasSize.width,scratch.canvasSize.height);
        RSGraphRenderer *renderer=[[[RSGraphRenderer alloc] initWithMapper:mapper] autorelease];
        [renderer positionAxisTickLabels]; RSBorder ticks=[renderer tickLabelWhitespaceBorder], b=g.whitespace;
        if (g.yAxis.displayTitle)
            b.left = MAX(b.left,TitleMargin+g.yAxis.title.size.height+g.yAxis.titleDistance+ticks.left);
        if (g.xAxis.displayTitle)
            b.bottom = MAX(b.bottom,TitleMargin+g.xAxis.title.size.height+g.xAxis.titleDistance+ticks.bottom);
        [scratch invalidate];
        if (b.left != g.whitespace.left || b.bottom != g.whitespace.bottom) g.whitespace = b;
    }
    return g;
}
// Drawn in the credit's pale gray (2026-11-16): it qualifies the page rather than teaching from it.
static NSString *const PaleNote = @"Manually authored geometry and values; edits do not recalculate the economics.";
static void Header(RSGraph *g, NSString *title, NSString *subtitle, NSString *assumptions) {
    PageLabel(g,title,110,730,29,YES,Ink());
    PageLabel(g,subtitle,110,696,16,NO,Ink());
    PageLabel(g,@"SYNTHETIC TEACHING MODEL",110,77,11,YES,Ink());
    PageLabel(g,PaleNote,110,53,13,NO,CreditGray());
    PageLabel(g,assumptions,110,31,12,NO,Ink());
}
// Data charts carry the source credit required by the publisher's reuse terms in a small label.
static void DataHeader(RSGraph *g, NSString *title, NSString *subtitle, NSString *credit, NSString *notes, BOOL derived) {
    PageLabel(g,title,110,730,29,YES,Ink());
    PageLabel(g,subtitle,110,696,16,NO,Ink());
    PageLabel(g,derived ? @"OFFICIAL DATA, OUR CALCULATIONS" : @"OFFICIAL DATA, VALUES AS PUBLISHED",110,77,11,YES,Ink());
    PageLabel(g,credit,110,53,12,NO,Ink());
    PageLabel(g,notes,110,31,12,NO,Ink());
}
static NSArray *Columns(NSArray *rows, NSUInteger x, NSUInteger y) {
    NSMutableArray *coords = [NSMutableArray array];
    for (NSArray *r in rows) [coords addObject:@[r[x],r[y]]];
    return coords;
}
static NSString *Pct(double v) { return [NSString stringWithFormat:@"%.1f%%",v]; }
static void Compose(RSGraph *g, NSString *stem) {
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    if ([stem isEqual:@"04-binding-price-ceiling"]) {
        Header(g,@"Binding Price Ceiling",@"Draw a legal maximum below equilibrium. Measure the shortage.",
            @"Divisible good · efficient rationing · no black market, queues or enforcement costs");
        Fill(g,p,@[@[@6,@5],@[@6,@8],@[@8,@6]],Purple());
        Line(g,p,@[@[@0,@14],@[@6,@8],@[@8,@6],@[@9,@5],@[@14,@0]],Blue(),2.6,0);
        Line(g,p,@[@[@0,@2],@[@6,@5],@[@8,@6],@[@14,@9]],Teal(),2.6,0);
        Line(g,p,@[@[@0,@5],@[@6,@5],@[@9,@5],@[@14,@5]],Orange(),2.6,0);
        Guide(g,p,@[@[@6,@0],@[@6,@5],@[@6,@8]]); Guide(g,p,@[@[@9,@0],@[@9,@5]]); Guide(g,p,@[@[@0,@6],@[@8,@6]]);
        ExampleMarker(g,p,6,5); ExampleMarker(g,p,9,5); ExampleMarker(g,p,8,6);
        Label(g,@"D",12.5,1.4,18,YES,Blue()); Label(g,@"S",12.4,8.9,18,YES,Teal());
        Label(g,@"Pmax = $5",10.3,5.3,15,YES,Orange());
        Label(g,@"E (8, 6)",8.35,6.55,14,YES,Ink());
        Label(g,@"Excess demand = 3",6.45,4.05,14,YES,Orange());
        Label(g,@"Q1 = 6",6.15,.35,13,YES,Ink()); Label(g,@"Q2 = 9",9.15,.35,13,YES,Ink());
        Label(g,@"DWL = 3",3.4,6.35,15,YES,Purple()); Guide(g,p,@[@[@4.95,@6.6],@[@6.6,@6.6]]);
        PageLabel(g,@"PRICE CEILING Pmax = $5",828,620,12,YES,Ink());
        PageLabel(g,@"Q1 = 6  /  Q2 = 9\nExcess demand = 3",828,553,20,YES,Ink());
        PageLabel(g,@"Pmax = $5 < P0 = $6: it binds.\nSellers offer only Q1 = 6;\nbuyers want Q2 = 9.",828,463,14,NO,Ink());
        PageLabel(g,@"LOST GAINS FROM TRADE",828,389,12,YES,Ink());
        PageLabel(g,@"Trades fall from Q0 = 8 to Q1 = 6.\nDWL = ½ · 3 · 2 = $3/week\nif the highest-value\nbuyers get the 6 units.",828,300,14,NO,Ink());
        PageLabel(g,@"TRY MODIFY\nDrag Pmax to $7.\nAbove P0, it does not bind.",828,191,13,NO,Ink());
        PageLabel(g,@"Queues or random rationing\ncan lose more than DWL.",828,126,13,YES,Ink());
    } else if ([stem isEqual:@"05-binding-price-floor"]) {
        Header(g,@"Binding Price Floor",@"Draw a legal minimum above equilibrium. Measure the excess supply.",
            @"Divisible good · no government purchases · only the 6 units sold are produced, by the lowest-cost sellers");
        Fill(g,p,@[@[@6,@5],@[@6,@8],@[@8,@6]],Purple());
        Line(g,p,@[@[@0,@14],@[@6,@8],@[@8,@6],@[@14,@0]],Blue(),2.6,0);
        Line(g,p,@[@[@0,@2],@[@6,@5],@[@8,@6],@[@12,@8],@[@14,@9]],Teal(),2.6,0);
        Line(g,p,@[@[@0,@8],@[@6,@8],@[@12,@8],@[@14,@8]],Orange(),2.6,0);
        Guide(g,p,@[@[@6,@0],@[@6,@5],@[@6,@8]]); Guide(g,p,@[@[@12,@0],@[@12,@8]]); Guide(g,p,@[@[@0,@6],@[@8,@6]]);
        ExampleMarker(g,p,6,8); ExampleMarker(g,p,12,8); ExampleMarker(g,p,8,6);
        Label(g,@"D",12.5,1.4,18,YES,Blue()); Label(g,@"S",13.2,9.6,18,YES,Teal());
        Label(g,@"Pmin = $8",.4,8.3,15,YES,Orange());
        Label(g,@"E (8, 6)",8.35,6.55,14,YES,Ink());
        Label(g,@"Excess supply = 6",7.3,8.4,14,YES,Orange());
        Label(g,@"Q1 = 6",6.15,.35,13,YES,Ink()); Label(g,@"Q2 = 12",12.15,.35,13,YES,Ink());
        Label(g,@"DWL = 3",3.4,6.35,15,YES,Purple()); Guide(g,p,@[@[@4.95,@6.6],@[@6.6,@6.6]]);
        PageLabel(g,@"PRICE FLOOR Pmin = $8",828,620,12,YES,Ink());
        PageLabel(g,@"Q1 = 6  /  Q2 = 12\nExcess supply = 6",828,553,20,YES,Ink());
        PageLabel(g,@"Pmin = $8 > P0 = $6: it binds.\nBuyers purchase only Q1 = 6;\nsellers would offer Q2 = 12.",828,463,14,NO,Ink());
        PageLabel(g,@"LOST GAINS FROM TRADE",828,389,12,YES,Ink());
        PageLabel(g,@"Trades fall from Q0 = 8 to Q1 = 6.\nDWL = ½ · 3 · 2 = $3/week\nif only the lowest-cost\nsellers produce.",828,300,14,NO,Ink());
        PageLabel(g,@"TRY MODIFY\nDrag Pmin to $5.\nBelow P0, it does not bind.",828,191,13,NO,Ink());
        PageLabel(g,@"Unsold output or government\npurchases can lose more.",828,126,13,YES,Ink());
    } else if ([stem isEqual:@"06-monopoly"]) {
        Header(g,@"Monopoly Output and Price",@"Choose quantity where MR = MC, then read price from demand.",
            @"Single-price monopolist · constant MC = ATC = $2 · no fixed cost, entry, price discrimination or externalities");
        Fill(g,p,@[@[@0,@8],@[@0,@14],@[@6,@8]],Blue());
        Fill(g,p,@[@[@0,@2],@[@6,@2],@[@6,@8],@[@0,@8]],Orange());
        Fill(g,p,@[@[@6,@2],@[@6,@8],@[@12,@2]],Purple());
        Line(g,p,@[@[@0,@14],@[@6,@8],@[@12,@2],@[@14,@0]],Blue(),2.6,0);
        Line(g,p,@[@[@0,@14],@[@6,@2],@[@7,@0]],Teal(),2.6,0);
        Line(g,p,@[@[@0,@2],@[@6,@2],@[@12,@2],@[@14,@2]],Orange(),2.6,0);
        Guide(g,p,@[@[@6,@0],@[@6,@2],@[@6,@8]]); Guide(g,p,@[@[@12,@0],@[@12,@2]]);
        ExampleMarker(g,p,6,8); ExampleMarker(g,p,6,2); ExampleMarker(g,p,12,2);
        Label(g,@"D = AR",13.0,1.25,15,YES,Blue()); Label(g,@"MR",7.2,.35,16,YES,Teal());
        Label(g,@"MC = ATC",9.0,1.25,15,YES,Orange());
        Label(g,@"Pm = 8",6.35,8.5,14,YES,Ink()); Label(g,@"MR = MC",4.15,1.2,13,YES,Ink());
        Label(g,@"Qc = 12, Pc = 2",12.15,2.4,13,YES,Ink());
        Label(g,@"CS = 18",3.0,8.35,17,YES,Blue()); Label(g,@"Profit = 36",.8,4.6,17,YES,Orange());
        Label(g,@"DWL = 18",6.6,3.0,15,YES,Purple());
        PageLabel(g,@"MR = MC, THEN DEMAND",828,620,12,YES,Ink());
        PageLabel(g,@"Qm = 6\nPm = $8",828,551,24,YES,Ink());
        PageLabel(g,@"MR = 14 − 2Q = 2 at Q = 6.\nPrice comes from demand,\nP = 14 − Q, not from MR.",828,463,14,NO,Ink());
        PageLabel(g,@"WELFARE ($/WEEK)",828,389,12,YES,Ink());
        PageLabel(g,@"Competition: Qc = 12, CS = 72\nMonopoly: CS 18 + profit 36\nDWL = 72 − 54 = 18",828,318,14,NO,Ink());
        PageLabel(g,@"TRY FILL\nSelect the profit rectangle.\nIt is a transfer, not DWL.",828,211,13,NO,Ink());
        PageLabel(g,@"MR is drawn only for Q ≤ 7,\nwhere it is not negative.",828,142,13,YES,Ink());
    } else if ([stem isEqual:@"07-cost-curves"]) {
        Header(g,@"Marginal and Average Cost",@"MC crosses AVC and ATC at their minimum points.",
            @"Short-run firm · fixed cost $32 · curves sampled every 0.25 units of output and joined by straight segments");
        NSArray *mins = @[@2,@3,@4];
        Line(g,p,Sampled(1,7,.25,mins,^(double q){ return 32/q+24-6*q+q*q; }),Blue(),2.6,0);
        Line(g,p,Sampled(1,7,.25,mins,^(double q){ return 24-6*q+q*q; }),Teal(),2.6,0);
        Line(g,p,Sampled(1,7,.25,mins,^(double q){ return 24-12*q+3*q*q; }),Orange(),2.6,0);
        ExampleMarker(g,p,2,12); ExampleMarker(g,p,3,15); ExampleMarker(g,p,4,24);
        Label(g,@"MC",5.0,55,18,YES,Orange()); Label(g,@"ATC",5.9,32,18,YES,Blue()); Label(g,@"AVC",5.6,15.5,18,YES,Teal());
        Label(g,@"(2, 12)",1.7,7.5,13,YES,Ink()); Label(g,@"(3, 15)",2.75,9.4,13,YES,Ink()); Label(g,@"(4, 24)",3.35,27.5,13,YES,Ink());
        PageLabel(g,@"ONE TOTAL COST, THREE CURVES",828,620,12,YES,Ink());
        PageLabel(g,@"TC = 32 + 24q − 6q² + q³",828,580,15,YES,Ink());
        PageLabel(g,@"MC = 24 − 12q + 3q²\nAVC = 24 − 6q + q²\nATC = 32/q + AVC",828,500,14,NO,Ink());
        PageLabel(g,@"WHERE THEY MEET",828,430,12,YES,Ink());
        PageLabel(g,@"MC is lowest at (2, 12).\nMC = AVC at AVC's\nminimum (3, 15).\nMC = ATC at ATC's\nminimum (4, 24).",828,318,14,NO,Ink());
        PageLabel(g,@"ATC − AVC = 32/q,\naverage fixed cost.",828,258,13,YES,Ink());
        PageLabel(g,@"TRY DATA\nEdit a sampled point.\nCompare straight and\ncurved connections.",828,150,13,NO,Ink());
    } else if ([stem isEqual:@"08-budget-and-indifference"]) {
        Header(g,@"Budget Line and Indifference Curves",@"Find the highest indifference curve the budget can reach.",
            @"Divisible goods · U = FC is ordinal, not dollars · curves sampled every 0.25 and joined by straight segments");
        Fill(g,p,@[@[@0,@0],@[@12,@0],@[@0,@8]],Blue());
        NSArray *colors = @[Teal(),Blue(),Purple()];
        for (NSUInteger i=0;i<3;i++) {
            double k = 12*(i+1);
            Line(g,p,Sampled(k/10,12,.25,@[@6],^(double x){ return k/x; }),colors[i],i==1 ? 2.6 : 2.0,i==2 ? 2 : 0);
        }
        Line(g,p,@[@[@0,@8],@[@6,@4],@[@12,@0]],Ink(),2.6,0);
        Guide(g,p,@[@[@0,@4],@[@6,@4]]); Guide(g,p,@[@[@6,@0],@[@6,@4]]);
        ExampleMarker(g,p,6,4);
        Label(g,@"Budget",.25,8.3,14,YES,Ink());
        Label(g,@"U1 = 12",12.1,.8,13,YES,Teal()); Label(g,@"U2 = 24",12.1,1.8,13,YES,Blue()); Label(g,@"U3 = 36",12.1,2.8,13,YES,Purple());
        Label(g,@"E (6, 4)",6.2,4.3,14,YES,Ink());
        Label(g,@"Affordable set",.5,1.2,15,YES,Blue());
        PageLabel(g,@"BEST AFFORDABLE BUNDLE",828,620,12,YES,Ink());
        PageLabel(g,@"F* = 6\nC* = 4",828,551,24,YES,Ink());
        PageLabel(g,@"Income I = $24/week\nPF = $2, PC = $3\nBudget: 2F + 3C = 24\nPreferences: U = FC",828,445,14,NO,Ink());
        PageLabel(g,@"TANGENCY",828,389,12,YES,Ink());
        PageLabel(g,@"MRS = C/F = 4/6 = 2/3\nPrice ratio PF/PC = 2/3\nU3 = 36 lies beyond\nthe budget line.",828,300,14,NO,Ink());
        PageLabel(g,@"TRY DRAW\nAdd a bundle on the line.\nWhich curve passes\nthrough it?",828,190,13,NO,Ink());
        PageLabel(g,@"The shaded area is not\nconsumer surplus.",828,126,13,YES,Ink());
    } else if ([stem isEqual:@"09-elasticity-along-demand"]) {
        Header(g,@"Elasticity Along a Linear Demand",@"One slope, many elasticities: Ep = (ΔQ/ΔP)(P/Q) changes along the line.",
            @"Linear demand P = 14 − Q, so ΔQ/ΔP = −1 everywhere · point elasticity Ep = −P/Q · total revenue R = P · Q");
        Fill(g,p,@[@[@0,@0],@[@7,@0],@[@7,@7],@[@0,@7]],Blue());
        Line(g,p,@[@[@0,@14],@[@4,@10],@[@7,@7]],Orange(),2.6,0);
        Line(g,p,@[@[@7,@7],@[@10,@4],@[@14,@0]],Teal(),2.6,0);
        ExampleMarker(g,p,4,10); ExampleMarker(g,p,7,7); ExampleMarker(g,p,10,4);
        Label(g,@"Ep = −2.5",4.3,10.35,14,YES,Ink()); Label(g,@"Ep = −1",7.3,7.35,14,YES,Ink()); Label(g,@"Ep = −0.4",10.3,4.35,14,YES,Ink());
        Label(g,@"Elastic: |Ep| > 1",1.6,13.6,15,YES,Orange()); Label(g,@"Inelastic: |Ep| < 1",8.4,.9,15,YES,Teal());
        Label(g,@"R = P · Q = 49",1.6,3.2,15,YES,Blue());
        PageLabel(g,@"POINT ELASTICITY",828,620,12,YES,Ink());
        PageLabel(g,@"Ep = −P / Q",828,575,24,YES,Ink());
        PageLabel(g,@"ΔQ/ΔP = −1 on the whole line,\nbut P/Q falls as Q rises:\nEp = −10/4 = −2.5 at Q = 4\nEp = −7/7 = −1 at Q = 7\nEp = −4/10 = −0.4 at Q = 10",828,455,14,NO,Ink());
        PageLabel(g,@"TOTAL REVENUE",828,415,12,YES,Ink());
        PageLabel(g,@"R = P · Q is largest where\n|Ep| = 1: Q = 7, R = $49.\nWhere |Ep| > 1, a lower\nprice raises revenue.",828,330,14,NO,Ink());
        PageLabel(g,@"TRY MODIFY\nDrag the shaded corner\nalong D. Is R ever above 49?",828,200,13,NO,Ink());
        PageLabel(g,@"Slope and elasticity\nare not the same thing.",828,126,13,YES,Ink());
    } else if ([stem isEqual:@"10-income-and-substitution-effects"]) {
        Header(g,@"Income and Substitution Effects",@"Split a price fall into a move along U1 and a move to U2.",
            @"U = FC is ordinal · I = $24/week · PC = $3 · PF falls from $8 to $2 · curves sampled every 0.25, straight segments");
        Line(g,p,Sampled(.625,12,.25,@[@1.5,@3],^(double f){ return 6/f; }),Teal(),2.4,0);
        Line(g,p,Sampled(2.4,12,.25,@[@6],^(double f){ return 24/f; }),Blue(),2.6,0);
        Line(g,p,@[@[@0,@8],@[@1.5,@4],@[@3,@0]],Ink(),2.6,0);
        Line(g,p,@[@[@0,@8],@[@6,@4],@[@12,@0]],Ink(),2.6,0);
        Line(g,p,@[@[@0,@4],@[@3,@2],@[@6,@0]],Orange(),2,2);
        Guide(g,p,@[@[@1.5,@0],@[@1.5,@4]]); Guide(g,p,@[@[@3,@0],@[@3,@2]]); Guide(g,p,@[@[@6,@0],@[@6,@4]]);
        ExampleMarker(g,p,1.5,4); ExampleMarker(g,p,3,2); ExampleMarker(g,p,6,4);
        Label(g,@"A",1.05,4.2,15,YES,Ink()); Label(g,@"D",3.2,2.2,15,YES,Ink()); Label(g,@"B",6.2,4.25,15,YES,Ink());
        Label(g,@"U1 = 6",12.1,.6,13,YES,Teal()); Label(g,@"U2 = 24",12.1,2.05,13,YES,Blue());
        Label(g,@"PF = $8",3.15,.3,13,YES,Ink()); Label(g,@"PF = $2",10.5,1.3,13,YES,Ink());
        Label(g,@"Compensated: 2F + 3C = 12",3.4,2.75,13,YES,Orange());
        PageLabel(g,@"A PRICE FALL, TWO EFFECTS",828,620,12,YES,Ink());
        PageLabel(g,@"Substitution +1.5\nIncome +3\nTotal effect +4.5",828,532,18,YES,Ink());
        PageLabel(g,@"A → D: along U1, to the new\nprice ratio PF/PC = 2/3.\nD → B: the higher real income\nfrom cheaper food.",828,430,14,NO,Ink());
        PageLabel(g,@"HOW D IS FOUND",828,389,12,YES,Ink());
        PageLabel(g,@"Shift the new budget line in\nuntil it touches U1: 2F + 3C = 12.\nAt the new prices the consumer\nneeds only $12 to stay on U1.",828,300,14,NO,Ink());
        PageLabel(g,@"TRY DRAW\nDraw the budget for PF = $4.\nIts tangency is (3, 4).",828,190,13,NO,Ink());
        PageLabel(g,@"Food is a normal good: both\neffects point the same way.",828,126,13,YES,Ink());
    } else if ([stem isEqual:@"11-isoquants-and-isocost"]) {
        Header(g,@"Isoquants and Isocost Lines",@"Produce q1 = 32 at minimum cost: where the isoquant touches an isocost line.",
            @"q = LK (a synthetic production function) · w = $2 per hour · r = $4 per machine-hour · isoquant sampled every 0.25");
        Line(g,p,Sampled(2.75,20,.25,@[@4,@8,@16],^(double l){ return 32/l; }),Blue(),2.6,0);
        Line(g,p,@[@[@0,@6],@[@12,@0]],Teal(),2,2);
        Line(g,p,@[@[@0,@8],@[@8,@4],@[@16,@0]],Teal(),2.6,0);
        Line(g,p,@[@[@0,@10],@[@4,@8],@[@16,@2],@[@20,@0]],Teal(),2,2);
        Line(g,p,@[@[@0,@0],@[@8,@4],@[@20,@10]],Purple(),2,0);
        Guide(g,p,@[@[@8,@0],@[@8,@4]]); Guide(g,p,@[@[@0,@4],@[@8,@4]]);
        ExampleMarker(g,p,8,4); ExampleMarker(g,p,4,8); ExampleMarker(g,p,16,2);
        Label(g,@"q1 = 32",3.1,11.2,15,YES,Blue());
        Label(g,@"C0 = $24",.15,4.6,13,YES,Teal()); Label(g,@"C1 = $32",12.2,.5,13,YES,Teal()); Label(g,@"C2 = $40",16.6,2.85,13,YES,Teal());
        Label(g,@"A (8, 4)",7.6,4.75,14,YES,Ink()); Label(g,@"(4, 8)",4.4,8.25,13,YES,Ink()); Label(g,@"(16, 2)",14.9,1.0,13,YES,Ink());
        Label(g,@"Expansion path",15.0,8.3,14,YES,Purple());
        PageLabel(g,@"LEAST-COST INPUTS",828,620,12,YES,Ink());
        PageLabel(g,@"L* = 8\nK* = 4",828,551,24,YES,Ink());
        PageLabel(g,@"MRTS = MPL/MPK = K/L = 1/2\nw/r = 2/4 = 1/2\nC = wL + rK = 16 + 16 = $32",828,463,14,NO,Ink());
        PageLabel(g,@"OTHER WAYS TO MAKE q1",828,415,12,YES,Ink());
        PageLabel(g,@"(4, 8) and (16, 2) also make 32\nbut cost $40: the isocost C2\ncuts the isoquant there.\nC0 = $24 cannot reach q1.",828,330,14,NO,Ink());
        PageLabel(g,@"TRY MODIFY\nRaise w to $8: the tangency\nmoves to (4, 8), cost $64.",828,200,13,NO,Ink());
        PageLabel(g,@"The expansion path is\nK = L/2 while w/r = 1/2.",828,126,13,YES,Ink());
    } else if ([stem isEqual:@"12-competitive-firm-short-run"]) {
        Header(g,@"A Competitive Firm in the Short Run",@"Produce where P = MC, as long as P covers minimum AVC.",
            @"Price taker · P = AR = MR = $39 · costs of Marginal and Average Cost: fixed cost $32 · curves sampled every 0.25, straight segments");
        Fill(g,p,@[@[@0,@25.4],@[@5,@25.4],@[@5,@39],@[@0,@39]],Purple());
        NSArray *points = @[@2,@3,@4,@5];
        Line(g,p,Sampled(1,7,.25,points,^(double q){ return 32/q+24-6*q+q*q; }),Blue(),2.6,0);
        Line(g,p,Sampled(1,7,.25,points,^(double q){ return 24-6*q+q*q; }),Teal(),2.6,0);
        Line(g,p,Sampled(1,7,.25,points,^(double q){ return 24-12*q+3*q*q; }),Orange(),2.6,0);
        Line(g,p,@[@[@0,@39],@[@5,@39],@[@7,@39]],Ink(),2.6,0);
        Guide(g,p,@[@[@5,@0],@[@5,@25.4]]);
        ExampleMarker(g,p,5,39); ExampleMarker(g,p,5,25.4); ExampleMarker(g,p,3,15);
        Label(g,@"P = AR = MR = $39",5.25,40.5,14,YES,Ink());
        Label(g,@"MC",6.25,62,18,YES,Orange()); Label(g,@"ATC",6.35,27,18,YES,Blue()); Label(g,@"AVC",6.35,17,18,YES,Teal());
        Label(g,@"π = $68",.3,31,16,YES,Purple());
        Label(g,@"q* = 5",5.1,3,13,YES,Ink()); Label(g,@"25.4",5.12,22.2,13,YES,Ink());
        Label(g,@"Shutdown (3, 15)",2.1,7.5,13,YES,Ink());
        PageLabel(g,@"P = MC, IF P ≥ MIN AVC",828,620,12,YES,Ink());
        PageLabel(g,@"q* = 5\nπ = $68",828,551,24,YES,Ink());
        PageLabel(g,@"MC = 24 − 12q + 3q² = 39\nat q = 5 (q² − 4q − 5 = 0).\nATC(5) = 32/5 + 19 = 25.4\nπ = (39 − 25.4) · 5 = 68",828,445,14,NO,Ink());
        PageLabel(g,@"SHORT-RUN SUPPLY",828,400,12,YES,Ink());
        PageLabel(g,@"Below P = $15, the minimum\nof AVC, the firm shuts down.\nAbove it, the supply curve\nis MC.",828,315,14,NO,Ink());
        PageLabel(g,@"TRY MODIFY\nDrag P to $24: q* = 4,\nP = ATC and π = 0.",828,200,13,NO,Ink());
        PageLabel(g,@"Same costs as Marginal\nand Average Cost.",828,126,13,YES,Ink());
    } else if ([stem isEqual:@"13-import-tariff"]) {
        Header(g,@"An Import Tariff",@"A $1 tariff raises the home price from Pw to Pw + T. Fill the areas A, B, C, D.",
            @"Small country: the world price Pw = $3 does not change · D: P = 14 − Q · S: P = 2 + Q/2 · tariff T = $1 per unit");
        Fill(g,p,@[@[@0,@3],@[@2,@3],@[@4,@4],@[@0,@4]],Teal());
        Fill(g,p,@[@[@2,@3],@[@4,@3],@[@4,@4]],Purple());
        Fill(g,p,@[@[@4,@3],@[@10,@3],@[@10,@4],@[@4,@4]],Orange());
        Fill(g,p,@[@[@10,@3],@[@11,@3],@[@10,@4]],Purple());
        Line(g,p,@[@[@0,@14],@[@8,@6],@[@10,@4],@[@11,@3],@[@14,@0]],Blue(),2.6,0);
        Line(g,p,@[@[@0,@2],@[@2,@3],@[@4,@4],@[@8,@6],@[@14,@9]],Teal(),2.6,0);
        Line(g,p,@[@[@0,@3],@[@2,@3],@[@4,@3],@[@10,@3],@[@11,@3],@[@14,@3]],Ink(),2,2);
        Line(g,p,@[@[@0,@4],@[@4,@4],@[@10,@4],@[@14,@4]],Orange(),2.6,0);
        Guide(g,p,@[@[@2,@0],@[@2,@3]]); Guide(g,p,@[@[@4,@0],@[@4,@3]]); Guide(g,p,@[@[@10,@0],@[@10,@3]]); Guide(g,p,@[@[@11,@0],@[@11,@3]]);
        ExampleMarker(g,p,2,3); ExampleMarker(g,p,11,3); ExampleMarker(g,p,4,4); ExampleMarker(g,p,10,4); ExampleMarker(g,p,8,6);
        Label(g,@"D",12.5,1.4,18,YES,Blue()); Label(g,@"S",12.4,8.9,18,YES,Teal());
        Label(g,@"Pw = $3",12.15,2.35,13,YES,Ink()); Label(g,@"Pw + T = $4",11.6,4.3,13,YES,Orange());
        Label(g,@"P0 = 6",7.55,6.65,13,YES,Ink());
        Label(g,@"A",.9,3.25,14,YES,Teal()); Label(g,@"B",3.35,3.12,12,YES,Purple()); Label(g,@"D",6.7,3.25,14,YES,Orange()); Label(g,@"C",10.12,3.12,12,YES,Purple());
        Label(g,@"Qs = 2",1.1,.35,12,YES,Ink()); Label(g,@"Q′s = 4",4.1,.35,12,YES,Ink());
        Label(g,@"Q′d = 10",8.65,.35,12,YES,Ink()); Label(g,@"Qd = 11",11.1,.35,12,YES,Ink());
        PageLabel(g,@"TARIFF T = $1",828,620,12,YES,Ink());
        PageLabel(g,@"Imports 9 → 6\nRevenue D = $6",828,553,20,YES,Ink());
        PageLabel(g,@"At Pw = $3: home firms make\nQs = 2, buyers want Qd = 11.\nAt Pw + T = $4: Q′s = 4, Q′d = 10.",828,463,14,NO,Ink());
        PageLabel(g,@"WELFARE ($/WEEK)",828,415,12,YES,Ink());
        PageLabel(g,@"ΔCS = −(A + B + C + D) = −10.5\nΔPS = A = 3\nRevenue D = 6\nDWL = B + C = 1 + 0.5 = 1.5",828,320,14,NO,Ink());
        PageLabel(g,@"TRY FILL\nRecolor D: under a quota of 6\nit goes to licence holders.",828,200,13,NO,Ink());
        PageLabel(g,@"A quota of 6 units gives\nthe same $4 home price.",828,126,13,YES,Ink());
    } else if ([stem isEqual:@"14-monopsony"]) {
        Header(g,@"The Monopsonist Buyer",@"A single buyer stops where marginal expenditure equals marginal value.",
            @"One buyer · supply = average expenditure AE: P = 2 + Q/2 · marginal value MV (the buyer's demand): 14 − Q");
        Fill(g,p,@[@[@0,@5],@[@6,@5],@[@6,@6],@[@0,@6]],Orange());
        Fill(g,p,@[@[@6,@5],@[@6,@8],@[@8,@6]],Purple());
        Line(g,p,@[@[@0,@14],@[@6,@8],@[@8,@6],@[@14,@0]],Blue(),2.6,0);
        Line(g,p,@[@[@0,@2],@[@6,@5],@[@8,@6],@[@14,@9]],Teal(),2.6,0);
        Line(g,p,@[@[@0,@2],@[@6,@8],@[@12,@14]],Orange(),2.6,0);
        Guide(g,p,@[@[@6,@0],@[@6,@5]]); Guide(g,p,@[@[@8,@0],@[@8,@6]]);
        ExampleMarker(g,p,6,8); ExampleMarker(g,p,6,5); ExampleMarker(g,p,8,6);
        Label(g,@"MV",13.2,1.3,17,YES,Blue()); Label(g,@"S = AE",12.4,9.4,16,YES,Teal()); Label(g,@"ME",11.7,12.4,17,YES,Orange());
        Label(g,@"ME = MV",3.4,8.2,13,YES,Ink());
        Label(g,@"P*m = 5",6.2,4.2,13,YES,Ink()); Label(g,@"Pc = 6, Qc = 8",10.2,5.4,13,YES,Ink()); Guide(g,p,@[@[@10.1,@5.65],@[@8.2,@5.95]]);
        Label(g,@"Q*m = 6",6.1,.35,12,YES,Ink()); Label(g,@"Qc = 8",8.1,.35,12,YES,Ink());
        Label(g,@"DWL = 3",8.6,7.6,14,YES,Purple());
        Label(g,@"Transfer = 6",1.2,5.2,13,YES,Orange());
        PageLabel(g,@"ONE BUYER: ME = MV",828,620,12,YES,Ink());
        PageLabel(g,@"Q*m = 6\nP*m = $5",828,551,24,YES,Ink());
        PageLabel(g,@"Total expenditure (2 + Q/2) · Q,\nso ME = 2 + Q lies above AE.\nME = MV: 2 + Q = 14 − Q, Q = 6.\nThe price comes from AE.",828,445,14,NO,Ink());
        PageLabel(g,@"VS. COMPETITIVE BUYING",828,400,12,YES,Ink());
        PageLabel(g,@"Competition: Qc = 8, Pc = $6.\nSellers lose 6 + 1 = 7;\nthe buyer gains 6 − 2 = 4.\nDWL = 1 + 2 = 3.",828,315,14,NO,Ink());
        PageLabel(g,@"TRY FILL\nSplit the DWL at P = 6:\nsellers' 1, the buyer's 2.",828,200,13,NO,Ink());
        PageLabel(g,@"Same curves as Binding Price\nCeiling; now the buyer sets Q.",828,126,13,YES,Ink());
    } else if ([stem isEqual:@"15-third-degree-price-discrimination"]) {
        Header(g,@"Third-Degree Price Discrimination",@"Two groups, one MC: set MR1 = MR2 = MC, then read each price from its demand.",
            @"Constant MC = $2 · D1: P1 = 14 − Q1 · D2: P2 = 8 − Q2/2 · no resale between the two groups");
        Line(g,p,@[@[@0,@14],@[@6,@8],@[@14,@0]],Blue(),2.6,0);
        Line(g,p,@[@[@0,@14],@[@6,@2],@[@7,@0]],Blue(),2,2);
        Line(g,p,@[@[@0,@8],@[@6,@5],@[@16,@0]],Purple(),2.6,0);
        Line(g,p,@[@[@0,@8],@[@6,@2],@[@8,@0]],Purple(),2,2);
        Line(g,p,@[@[@0,@14],@[@3,@8],@[@12,@2],@[@15,@0]],Teal(),2,0);
        Line(g,p,@[@[@0,@2],@[@6,@2],@[@12,@2],@[@16,@2]],Orange(),2.6,0);
        Guide(g,p,@[@[@6,@0],@[@6,@2],@[@6,@5],@[@6,@8]]); Guide(g,p,@[@[@12,@0],@[@12,@2]]);
        Guide(g,p,@[@[@0,@8],@[@6,@8]]); Guide(g,p,@[@[@0,@5],@[@6,@5]]);
        ExampleMarker(g,p,6,8); ExampleMarker(g,p,6,5); ExampleMarker(g,p,6,2); ExampleMarker(g,p,12,2);
        Label(g,@"D1 = AR1",11.0,3.6,14,YES,Blue()); Label(g,@"MR1",6.9,.9,14,YES,Blue());
        Label(g,@"D2 = AR2",13.3,2.4,14,YES,Purple()); Label(g,@"MR2",8.2,.35,14,YES,Purple());
        Label(g,@"MRT",3.3,8.3,14,YES,Teal()); Label(g,@"MC",1.0,2.3,15,YES,Orange());
        Label(g,@"P1 = 8",.25,8.3,13,YES,Ink()); Label(g,@"P2 = 5",.25,5.3,13,YES,Ink());
        Label(g,@"Q1 = Q2 = 6",4.0,.35,12,YES,Ink()); Label(g,@"QT = 12",10.5,.35,12,YES,Ink());
        PageLabel(g,@"TWO MARKETS, ONE MC",828,620,12,YES,Ink());
        PageLabel(g,@"P1 = $8,  Q1 = 6\nP2 = $5,  Q2 = 6",828,553,20,YES,Ink());
        PageLabel(g,@"MR1 = 14 − 2Q1 = 2 → Q1 = 6\nMR2 = 8 − Q2 = 2 → Q2 = 6\nMRT, the horizontal sum,\nmeets MC at QT = 12.",828,445,14,NO,Ink());
        PageLabel(g,@"ELASTICITY AND PRICE",828,400,12,YES,Ink());
        PageLabel(g,@"E1 = −8/6 ≈ −1.33\nE2 = −2 · 5/6 ≈ −1.67\nP1/P2 = (1 + 1/E2)/(1 + 1/E1)\n= 0.4/0.25 = 1.6 = 8/5",828,300,14,NO,Ink());
        PageLabel(g,@"TRY MODIFY\nRaise MC to $4: Q1 = 5, P1 = $9;\nQ2 = 4, P2 = $6.",828,190,13,NO,Ink());
        PageLabel(g,@"The less elastic group\npays the higher price.",828,126,13,YES,Ink());
    } else if ([stem isEqual:@"16-cournot-duopoly"]) {
        Header(g,@"Cournot Duopoly",@"Each firm's best output given the other's: the reaction curves cross at the equilibrium.",
            @"Two identical firms · market demand P = 14 − Q, Q = Q1 + Q2 · MC = $2 for both · no fixed cost");
        Line(g,p,@[@[@0,@6],@[@4,@4],@[@12,@0]],Blue(),2.6,0);
        Line(g,p,@[@[@6,@0],@[@4,@4],@[@0,@12]],Teal(),2.6,0);
        Line(g,p,@[@[@0,@6],@[@3,@3],@[@6,@0]],Orange(),2,2);
        Line(g,p,@[@[@0,@12],@[@6,@6],@[@12,@0]],Purple(),2,2);
        ExampleMarker(g,p,4,4); ExampleMarker(g,p,3,3); ExampleMarker(g,p,6,6);
        Label(g,@"Q*1(Q2)",8.0,.4,14,YES,Blue());
        Label(g,@"Q*2(Q1)",1.5,11.2,14,YES,Teal());
        Label(g,@"Cournot equilibrium (4, 4)",4.35,4.3,13,YES,Ink());
        Label(g,@"Collusion curve",.25,1.2,13,YES,Orange()); Label(g,@"(3, 3)",2.0,2.65,12,YES,Ink());
        Label(g,@"Competitive equilibrium (P = MC; π = 0)",6.35,6.3,13,YES,Purple());
        PageLabel(g,@"BEST RESPONSE TO EACH OTHER",828,620,12,YES,Ink());
        PageLabel(g,@"Q1 = Q2 = 4\nP = $6",828,551,24,YES,Ink());
        PageLabel(g,@"Firm 1's profit (12 − Q1 − Q2) · Q1\npeaks on its reaction curve\nQ*1(Q2) = 6 − Q2/2. Firm 2's,\nQ*2(Q1), is symmetric.",828,445,14,NO,Ink());
        PageLabel(g,@"THREE OUTCOMES",828,400,12,YES,Ink());
        PageLabel(g,@"Collusion: Q = 6, P = $8, π = 18 each\nCournot: Q = 8, P = $6, π = 16 each\nCompetition: Q = 12, P = $2, π = 0",828,315,14,NO,Ink());
        PageLabel(g,@"TRY DRAW\nStart at Q1 = 12, Q2 = 0 and\nalternate best responses.",828,200,13,NO,Ink());
        PageLabel(g,@"Same demand and MC as\nMonopoly Output and Price.",828,126,13,YES,Ink());
    } else if ([stem isEqual:@"17-gains-from-trade"]) {
        Header(g,@"The Gains from Trade",@"Trade at world prices lets a country consume outside its production possibilities frontier.",
            @"PPF: C = 12 − F²/4, so MRT = F/2 · U = FC is ordinal · world price ratio PF/PC = 3 · curves sampled every 0.25");
        Line(g,p,Sampled(0,sqrt(48),.25,@[@4,@6],^(double f){ return MAX(0,12-f*f/4); }),Blue(),2.6,0);
        Line(g,p,Sampled(2,10,.25,@[@4],^(double f){ return 32/f; }),Teal(),2.2,0);
        Line(g,p,Sampled(2.5,10,.25,@[@3.5],^(double f){ return 36.75/f; }),Purple(),2.2,0);
        Line(g,p,@[@[@1.5,@13],@[@4,@8],@[@6.5,@3]],[NSColor colorWithSRGBRed:.50 green:.55 blue:.60 alpha:1],1.6,2);
        Line(g,p,@[@[@2.5,@13.5],@[@3.5,@10.5],@[@6,@3],@[@7,@0]],Orange(),2.6,0);
        Guide(g,p,@[@[@3.5,@10.5],@[@3.5,@3],@[@6,@3]]);
        ExampleMarker(g,p,4,8); ExampleMarker(g,p,6,3); ExampleMarker(g,p,3.5,10.5);
        Label(g,@"A",3.6,7.2,15,YES,Ink()); Label(g,@"B",6.2,3.25,15,YES,Ink()); Label(g,@"D",3.7,10.75,15,YES,Ink());
        Label(g,@"PPF",1.0,10.6,16,YES,Blue()); Label(g,@"U1 = 32",8.6,2.4,13,YES,Teal()); Label(g,@"U2 = 36.75",8.6,4.85,13,YES,Purple());
        Label(g,@"Pre-trade prices",.2,14.4,13,YES,Ink()); Label(g,@"World prices",3.6,13.4,13,YES,Orange());
        Label(g,@"Imports 7.5",1.95,6.0,13,YES,Ink()); Label(g,@"Exports 2.5",3.7,1.9,13,YES,Ink());
        PageLabel(g,@"OPENING TO TRADE",828,620,12,YES,Ink());
        PageLabel(g,@"Exports 2.5 F\nImports 7.5 C",828,553,20,YES,Ink());
        PageLabel(g,@"Before trade: A = (4, 8), where\nMRT = 2 = MRS on U1 = 32.\nAt world PF/PC = 3 the country\nproduces B = (6, 3): MRT = 3.",828,445,14,NO,Ink());
        PageLabel(g,@"CONSUMING BEYOND THE PPF",828,400,12,YES,Ink());
        PageLabel(g,@"Income at world prices:\n3 · 6 + 3 = 21 units of C.\nIt consumes D = (3.5, 10.5)\non U2, outside the PPF.",828,315,14,NO,Ink());
        PageLabel(g,@"TRY MODIFY\nSet PF/PC = 1: produce (2, 11),\nconsume (6.5, 6.5).",828,200,13,NO,Ink());
        PageLabel(g,@"Not everyone gains: clothing\nproducers lose at home.",828,126,13,YES,Ink());
    } else if ([stem isEqual:@"18-negative-externality"]) {
        Header(g,@"A Negative Externality",@"The market ignores the marginal external cost MEC and produces too much.",
            @"D: P = 14 − Q · private cost S = MC: P = 2 + Q/2 · constant MEC = $3 per unit · MSC = MC + MEC");
        Fill(g,p,@[@[@6,@8],@[@8,@9],@[@8,@6]],Purple());
        Line(g,p,@[@[@0,@14],@[@6,@8],@[@8,@6],@[@14,@0]],Blue(),2.6,0);
        Line(g,p,@[@[@0,@2],@[@6,@5],@[@8,@6],@[@11,@7.5],@[@14,@9]],Teal(),2.6,0);
        Line(g,p,@[@[@0,@5],@[@6,@8],@[@8,@9],@[@11,@10.5],@[@14,@12]],Orange(),2.6,0);
        Guide(g,p,@[@[@6,@0],@[@6,@5],@[@6,@8]]); Guide(g,p,@[@[@8,@0],@[@8,@6]]); Guide(g,p,@[@[@11,@7.5],@[@11,@10.5]]);
        ExampleMarker(g,p,8,6); ExampleMarker(g,p,6,8);
        Label(g,@"D",12.5,1.4,18,YES,Blue()); Label(g,@"S = MC",12.4,7.65,16,YES,Teal()); Label(g,@"MSC",12.6,12.4,16,YES,Orange());
        Label(g,@"MEC = $3",11.2,8.8,13,YES,Ink());
        Label(g,@"P* = 8",.25,8.3,13,YES,Ink()); Label(g,@"P1 = 6",.25,6.3,13,YES,Ink());
        Guide(g,p,@[@[@0,@8],@[@6,@8]]); Guide(g,p,@[@[@0,@6],@[@8,@6]]);
        Label(g,@"Q* = 6",6.1,.35,12,YES,Ink()); Label(g,@"Q1 = 8",8.1,.35,12,YES,Ink());
        Label(g,@"DWL = 3",8.6,7.55,14,YES,Purple());
        PageLabel(g,@"PRIVATE VS. SOCIAL COST",828,620,12,YES,Ink());
        PageLabel(g,@"Market Q1 = 8\nEfficient Q* = 6",828,553,20,YES,Ink());
        PageLabel(g,@"Each unit costs third parties\nMEC = $3. Buyers and sellers\nignore it and trade where\nD = MC.",828,445,14,NO,Ink());
        PageLabel(g,@"THE FIX",828,400,12,YES,Ink());
        PageLabel(g,@"A $3 tax per unit makes sellers\nface MSC: Q* = 6, buyers pay\nP* = $8, as in Tax Incidence.\nDWL = ½ · 3 · 2 = $3/week.",828,315,14,NO,Ink());
        PageLabel(g,@"TRY MODIFY\nRaise MEC to $6:\nQ* = 4 and P* = $10.",828,200,13,NO,Ink());
        PageLabel(g,@"A constant MEC per unit\nis a simplification.",828,126,13,YES,Ink());
    } else if ([stem isEqual:@"irpf-concentration-2024"]) {
        NSDictionary *irpf = DataInputs[@"irpf"]; NSArray *pts = irpf[@"points"]; NSDictionary *t = irpf[@"totals"];
        DataHeader(g,@"Income Tax Concentration in Spain, 2024",@"Returns ranked by taxable base: cumulative shares of the base and of the tax due.",
            @"Fuente: AEAT, Estadística de los declarantes del IRPF 2024 (actualizada el 01/07/2026); elaboración propia.",
            @"Territorio de Régimen Fiscal Común (excludes País Vasco and Navarra) · returns filed, not all residents · 10 AEAT brackets",YES);
        NSArray *base = Columns(pts,0,1), *tax = Columns(pts,0,2);
        // Diagonal-to-base area, then the base-to-tax band; both share the curves' own vertices.
        NSArray *baseBack = [[base reverseObjectEnumerator] allObjects], *taxBack = [[tax reverseObjectEnumerator] allObjects];
        Fill(g,p,[@[@[@0,@0],@[@100,@100]] arrayByAddingObjectsFromArray:[baseBack subarrayWithRange:NSMakeRange(1,baseBack.count-2)]],Blue());
        Fill(g,p,[base arrayByAddingObjectsFromArray:[taxBack subarrayWithRange:NSMakeRange(1,taxBack.count-2)]],Orange());
        Line(g,p,@[@[@0,@0],@[@100,@100]],[NSColor colorWithSRGBRed:.50 green:.55 blue:.60 alpha:1],1.4,2);
        Line(g,p,base,Blue(),2.6,0); Line(g,p,tax,Orange(),2.6,0);
        NSArray *mid = pts[5], *top = pts[7];
        Guide(g,p,@[@[mid[0],@0],@[mid[0],mid[2]],@[mid[0],mid[1]]]);
        ExampleMarker(g,p,[mid[0] doubleValue],[mid[1] doubleValue]); ExampleMarker(g,p,[mid[0] doubleValue],[mid[2] doubleValue]);
        Label(g,@"Equal shares",12,30,13,YES,Ink());
        Label(g,@"Taxable base",63,47,15,YES,Blue()); Label(g,@"Tax due",76,22,15,YES,Orange());
        Label(g,[Pct([mid[1] doubleValue]) stringByAppendingString:@" of base"],38.5,17,13,YES,Blue());
        Label(g,[Pct([mid[2] doubleValue]) stringByAppendingString:@" of tax"],53,2,13,YES,Orange());
        PageLabel(g,@"SPAIN, PERSONAL INCOME TAX 2024",828,620,12,YES,Ink());
        PageLabel(g,[NSString stringWithFormat:@"%.1f million returns\n€%.0f bn taxable base\n€%.0f bn tax due",
            [t[@"returns"] doubleValue]/1e6,[t[@"base"] doubleValue]/1e9,[t[@"tax"] doubleValue]/1e9],828,540,15,YES,Ink());
        PageLabel(g,@"BASE UP TO €21,000",828,470,12,YES,Ink());
        PageLabel(g,[NSString stringWithFormat:@"%@ of returns\n%@ of the taxable base\n%@ of the tax due",
            Pct([mid[0] doubleValue]),Pct([mid[1] doubleValue]),Pct([mid[2] doubleValue])],828,405,14,NO,Ink());
        PageLabel(g,@"BASE ABOVE €60,000",828,350,12,YES,Ink());
        PageLabel(g,[NSString stringWithFormat:@"%@ of returns\n%@ of the taxable base\n%@ of the tax due",
            Pct(100-[top[0] doubleValue]),Pct(100-[top[1] doubleValue]),Pct(100-[top[2] doubleValue])],828,285,14,NO,Ink());
        PageLabel(g,@"The tax curve lies below the\nbase curve: the tax is progressive.\nNegative bases in the first bracket\nput the base curve just below 0.",828,170,13,NO,Ink());
        PageLabel(g,@"TRY FILL\nRecolor the band between\nthe two curves.",828,112,13,NO,Ink());
    } else if ([stem isEqual:@"house-prices-and-wages"]) {
        NSDictionary *h = DataInputs[@"housing"]; NSArray *pts = h[@"points"];
        DataHeader(g,@"House Prices and Wages in Real Terms, Spain",@"Both deflated by consumer prices, four-quarter moving averages, 2015 = 100.",
            @"Elaboración propia con datos extraídos del sitio web del INE: www.ine.es (IPV, ETCL, IPC; últimos datos 2025T4 y 2025M12).",
            @"House prices: IPV general index · wages: ETCL total wage cost per worker and month · deflator: CPI general index",YES);
        Line(g,p,@[@[@2008,@100],@[@2026,@100]],[NSColor colorWithSRGBRed:.50 green:.55 blue:.60 alpha:1],1,2);
        Line(g,p,Columns(pts,0,1),Blue(),2.6,0); Line(g,p,Columns(pts,0,2),Teal(),2.6,0);
        NSArray *first = pts.firstObject, *last = pts.lastObject; NSArray *low = first;
        for (NSArray *r in pts) if ([r[1] doubleValue] < [low[1] doubleValue]) low = r;
        for (NSArray *r in @[first,low,last]) ExampleMarker(g,p,[r[0] doubleValue],[r[1] doubleValue]);
        ExampleMarker(g,p,[last[0] doubleValue],[last[2] doubleValue]);
        Label(g,@"House prices",2009.2,163,15,YES,Blue()); Label(g,@"Wages",2016,84,15,YES,Teal());
        Label(g,@"2015 = 100",2019.4,101.5,12,NO,Ink());
        Label(g,[NSString stringWithFormat:@"%.1f",[last[1] doubleValue]],2024.6,148,13,YES,Blue());
        Label(g,[NSString stringWithFormat:@"%.1f",[last[2] doubleValue]],2024.6,85,13,YES,Teal());
        Label(g,[NSString stringWithFormat:@"%.1f",[low[1] doubleValue]],[low[0] doubleValue]-.6,[low[1] doubleValue]-14,13,YES,Blue());
        PageLabel(g,@"REAL INDICES, 2015 = 100",828,620,12,YES,Ink());
        PageLabel(g,[NSString stringWithFormat:@"House prices %.1f\nWages %.1f\nin 2025 Q4",[last[1] doubleValue],[last[2] doubleValue]],828,540,18,YES,Ink());
        PageLabel(g,[NSString stringWithFormat:@"From %.1f in 2008 Q4 to a\nlow of %.1f in %.0f Q%.0f.",[first[1] doubleValue],[low[1] doubleValue],
            floor([low[0] doubleValue]),([low[0] doubleValue]-floor([low[0] doubleValue]))*4+1],828,470,14,NO,Ink());
        PageLabel(g,@"HOW THEY ARE BUILT",828,370,12,YES,Ink());
        PageLabel(g,@"Each quarter ÷ CPI (mean of\nits three monthly values), then\na four-quarter moving average,\nrebased to the 2015 average.\nQuarters as decimal years:\n2025.75 is 2025 Q4.",828,270,13,NO,Ink());
        PageLabel(g,@"The wage series includes\nextra payments, hence the\nmoving average.",828,190,13,NO,Ink());
        PageLabel(g,@"TRY DATA\nPaste a newer quarter and\nextend the lines.",828,112,13,NO,Ink());
    } else if ([stem isEqual:@"tax-revenue-share-of-gdp"]) {
        NSArray *pts = DataInputs[@"revenue"][@"points"];
        g.xAxis.displayGrid = YES; g.yAxis.displayGrid = YES;  // grid lines help read the yearly values
        DataHeader(g,@"Tax Revenue as a Share of GDP, Spain 1965–2024",@"All levels of government, social security contributions included, as % of GDP.",
            @"OECD (2025), Revenue Statistics in OECD member countries - Comparative tax revenues, OECD Data Explorer (accessed on 15 November 2026):",
            @"https://sdmx.oecd.org/public/rest/data/OECD.CTP.TPS,DSD_REV_COMP_OECD@DF_RSOECD,2.0/ESP.TAX_REV.S13._T._T.PT_B1GQ.A",NO);
        Line(g,p,pts,Blue(),2.6,0);
        NSArray *first = pts.firstObject, *last = pts.lastObject, *high = first, *low = first;
        for (NSArray *r in pts) {
            if ([r[1] doubleValue] > [high[1] doubleValue]) high = r;
            if ([r[1] doubleValue] < [low[1] doubleValue]) low = r;
        }
        NSArray *(^year)(NSInteger) = ^(NSInteger y){ for (NSArray *r in pts) if ([r[0] integerValue]==y) return r; return (NSArray *)nil; };
        NSArray *y2007 = year(2007), *y2009 = year(2009);
        for (NSArray *r in @[low,y2007,y2009,high,last]) ExampleMarker(g,p,[r[0] doubleValue],[r[1] doubleValue]);
        NSString *(^Value)(NSArray *) = ^(NSArray *r){ return [NSString stringWithFormat:@"%.1f%% in %@",[r[1] doubleValue],r[0]]; };
        Label(g,Value(low),1966.5,10.5,13,YES,Ink()); Label(g,Value(y2007),1998.2,38.0,13,YES,Ink());
        Label(g,Value(y2009),2006.0,25.8,13,YES,Ink()); Label(g,Value(high),2012.6,39.0,13,YES,Ink());
        Label(g,Value(last),2017.6,31.0,13,YES,Ink());
        PageLabel(g,@"SPAIN, TOTAL TAX REVENUE",828,620,12,YES,Ink());
        PageLabel(g,[NSString stringWithFormat:@"%.1f%% of GDP in %@\nfrom %.1f%% in %@",[last[1] doubleValue],last[0],[first[1] doubleValue],first[0]],828,555,18,YES,Ink());
        PageLabel(g,[NSString stringWithFormat:@"Highest: %.1f%% in %@\nLowest: %.1f%% in %@\nFrom 2007 to 2009 it fell\n%.1f points.",[high[1] doubleValue],high[0],[low[1] doubleValue],low[0],
            [y2007[1] doubleValue]-[y2009[1] doubleValue]],828,430,14,NO,Ink());
        PageLabel(g,@"WHAT IS INCLUDED",828,370,12,YES,Ink());
        PageLabel(g,@"Taxes of central, regional\nand local government plus\nsocial security contributions,\nOECD classification.",828,280,13,NO,Ink());
        PageLabel(g,@"TRY DATA\nAdd another country\nas a second line.",828,170,13,NO,Ink());
        PageLabel(g,@"Redistributions must keep\nthis OECD acknowledgment.",828,112,12,YES,Ink());
    } else if ([stem isEqual:@"template-market-equilibrium"]) {
        Line(g,p,@[@[@0,@14],@[@8,@6],@[@14,@0]],Blue(),2.6,0);
        Line(g,p,@[@[@0,@2],@[@8,@6],@[@14,@9]],Teal(),2.6,0);
        Label(g,@"D",12.5,1.4,18,YES,Blue()); Label(g,@"S",12.4,8.9,18,YES,Teal());
    } else if ([stem isEqual:@"template-function-plot"]) {
        // f(x) = (x³ − 75x)/50: one turn in each half, extrema at (−5, 5) and (5, −5), zeros at 0 and ±√75.
        Line(g,p,Sampled(-10,10,.25,nil,^(double x){ return (x*x*x-75*x)/50; }),Blue(),2.6,0);
        Label(g,@"f(x)",7.3,1.2,18,YES,Blue());
        // The axes cross at the origin, so titles placed outside the plot area would sit at the page edge, far from
        // them: name each axis at its end instead (x right of the x axis, y above the y axis), and drop the title space.
        g.xAxis.displayTitle = NO; g.yAxis.displayTitle = NO; g.whitespace = RSMakeBorder(60,70,60,70);
        RSDataMapper *mapper=[[[RSDataMapper alloc] initWithGraph:g] autorelease]; mapper.bounds=CGRectMake(0,0,g.canvasSize.width,g.canvasSize.height);
        RSTextLabel *x=Label(g,@"x",10,0,15,YES,Ink()), *y=Label(g,@"y",0,10,15,YES,Ink());
        CGPoint end=[mapper convertToViewCoords:RSDataPointMake(10,0)];
        x.position=ViewToData(g,end.x+12,end.y-x.size.height/2);
        end=[mapper convertToViewCoords:RSDataPointMake(0,10)];
        y.position=ViewToData(g,end.x-y.size.width/2,end.y+12);
    } else if ([stem isEqual:@"template-time-series"]) {
        NSArray *values=@[@42,@45,@44,@48,@51,@53,@52,@56,@59,@61,@47,@52,@58,@62,@65];
        NSMutableArray *coords=[NSMutableArray array];
        for (NSUInteger i=0;i<values.count;i++) [coords addObject:@[@(2010+i),values[i]]];
        Line(g,p,coords,Blue(),2.6,0);
        for (NSArray *c in coords) ExampleMarker(g,p,[c[0] doubleValue],[c[1] doubleValue]);
        Guide(g,p,@[@[@2020,@0],@[@2020,@88]]);
        Label(g,@"Event",2020.3,84,14,YES,Ink());
        Label(g,@"Series A",2022.6,70,16,YES,Blue());
    } else if ([stem isEqual:@"template-scatter-plot"]) {
        NSArray *xs=@[@.8,@1.2,@1.7,@2.1,@2.6,@3,@3.4,@3.9,@4.3,@4.8,@5.2,@5.6,@6.1,@6.5,@7,@7.4,@7.9,@8.3,@8.8,@9.2];
        NSArray *noise=@[@.6,@-.5,@.3,@-.8,@.9,@-.2,@.4,@-.7,@.1,@.8,@-.6,@.2,@-.9,@.5,@-.3,@.7,@-.4,@.6,@-.8,@.3];
        for (NSUInteger i=0;i<xs.count;i++) {
            double x=[xs[i] doubleValue]; LonePoint(g,x,round((1.5+.7*x+[noise[i] doubleValue])*100)/100,RS_CIRCLE,4,Blue());
        }
        // Graphink does not compute fits: this straight line was placed by eye and is labelled as such.
        Line(g,p,@[@[@.5,@1.85],@[@9.5,@8.15]],Orange(),2,2);
        Label(g,@"Series A",1.2,4.2,16,YES,Blue());
        Label(g,@"Trend line drawn by hand\n(not a computed fit)",6.6,2.2,13,YES,Orange());
    } else if ([stem isEqual:@"template-bar-chart"]) {
        NSArray *values=@[@40,@65,@30,@80,@55];
        RSDataMapper *mapper=[[[RSDataMapper alloc] initWithGraph:g] autorelease]; mapper.bounds=CGRectMake(0,0,g.canvasSize.width,g.canvasSize.height);
        for (NSUInteger i=0;i<values.count;i++) {
            double c=i+1, v=[values[i] doubleValue];
            ShadedFill(g,p,@[@[@(c-.3),@0],@[@(c-.3),@(v)],@[@(c+.3),@(v)],@[@(c+.3),@0]],Blue(),.8);
            RSTextLabel *name=Label(g,[NSString stringWithFormat:@"Category %lu",(unsigned long)i+1],c,0,14,NO,Ink());
            CGPoint at=[mapper convertToViewCoords:RSDataPointMake(c,0)];
            name.position=ViewToData(g,at.x-name.size.width/2,at.y-28);
        }
    } else if ([stem isEqual:@"template-log-scale"]) {
        // Series A doubles every period (1.5 × 2^t): on a log axis constant growth is a straight line.
        NSMutableArray *coords=[NSMutableArray array];
        for (int t=0;t<=9;t++) [coords addObject:@[@(t),@(1.5*pow(2,t))]];
        Line(g,p,coords,Blue(),2.6,0);
        for (NSArray *c in coords) ExampleMarker(g,p,[c[0] doubleValue],[c[1] doubleValue]);
        Label(g,@"Series A",7.4,420,16,YES,Blue());
        Label(g,@"Constant growth rate:\na straight line on a log scale",.4,300,13,NO,Ink());
    } else if ([stem isEqual:@"template-number-line"]) {
        // The interval [−2, 3): closed (filled) at −2, open (hollow) at 3.
        RSConnectLine *interval=Line(g,p,@[@[@-2,@0],@[@3,@0]],Orange(),5,0);
        RSVertex *closed=interval.vertices.elements[0], *open=interval.vertices.elements[1];
        closed.shape=RS_CIRCLE; closed.width=5; closed.color=Orange();
        open.shape=RS_HOLLOW; open.width=5; open.color=Orange();
        Label(g,@"[−2, 3)   −2 ≤ x < 3",-.95,.56,18,YES,Orange());
        Label(g,@"closed",-2.3,-.62,13,NO,Ink()); Label(g,@"open",2.8,-.62,13,NO,Ink());
    } else if ([stem isEqual:@"template-lorenz-curve"]) {
        // Placeholder Lorenz curve L(p) = p²/100 (Gini 1/3); the fill is the area between it and equality. Sampled
        // every 2 (about 12 pt per segment, like the function plot): every 5 showed facets where it bends most, at 0.
        NSArray *lorenz=Sampled(0,100,2,nil,^(double x){ return x*x/100; });
        ShadedFill(g,p,lorenz,Blue(),.17);
        Line(g,p,@[@[@0,@0],@[@100,@100]],Ink(),1.5,0);
        Line(g,p,lorenz,Blue(),2.6,0);
        // Along the diagonal, clear of the corner where the curve, the fill and equality meet.
        Label(g,@"Line of equality",44,56,15,YES,Ink()).rotation=45;
        Label(g,@"Lorenz curve",62,26,15,YES,Blue());
    } else if ([stem isEqual:@"template-production-possibilities"]) {
        // Placeholder frontier: quarter ellipse (x/9)² + (y/8)² = 1, concave to the origin. Sampled every 2.5° of the
        // ellipse angle (even spacing along the curve, also where it turns steep), plus point A at cos θ = 0.6.
        NSMutableArray *frontier=[NSMutableArray array];
        for (int tenths=900;tenths>=0;tenths-=25) {
            double t=tenths/10.0*M_PI/180; [frontier addObject:@[@(tenths==900 ? 0 : 9*cos(t)),@(tenths==0 ? 0 : 8*sin(t))]];
            if (tenths==550) [frontier addObject:@[@5.4,@6.4]];  // 55° > θ_A ≈ 53.13° > 52.5°, so x order is kept
        }
        Line(g,p,frontier,Blue(),2.6,0);
        ExampleMarker(g,p,5.4,6.4);
        LonePoint(g,3,3,RS_CIRCLE,1.8,Ink()); LonePoint(g,8,7,RS_CIRCLE,1.8,Ink());
        Label(g,@"A  Efficient",5.6,6.75,14,YES,Ink());
        Label(g,@"B  Inefficient",3.2,3.25,14,YES,Ink());
        Label(g,@"C  Unattainable",7.3,7.3,14,YES,Ink());
        Label(g,@"PPF",1.2,8.2,16,YES,Blue());
    } else Check(NO,[@"Unknown document " stringByAppendingString:stem]);
}

static NSArray *IDs(RSGraph *g, NSArray *elements) {
    NSMutableArray *ids = [NSMutableArray array]; for (id e in elements) [ids addObject:[g identiferForObject:e]]; return ids;
}
static NSArray *Color(NSColor *c) {
    c = [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; Check(c!=nil,@"Color must convert to sRGB");
    return @[@(c.redComponent),@(c.greenComponent),@(c.blueComponent),@(c.alphaComponent)];
}
static NSDictionary *AxisSnapshot(RSGraph *g, RSAxis *axis) {
    NSMutableDictionary *ticks=[NSMutableDictionary dictionary];
    for (NSString *key in axis.userLabelsDictionary) ticks[key]=[g identiferForObject:axis.userLabelsDictionary[key]];
    return @{@"id":[g identiferForObject:axis],@"min":@(axis.min),@"max":@(axis.max),@"title":[g identiferForObject:axis.title],
        @"ticks":ticks,@"spacing":@(axis.spacing),@"userSpacing":@(axis.userSpacing),@"placement":@(axis.placement),
        @"width":@(axis.width),@"color":Color(axis.color),@"displayTicks":@(axis.displayTicks),@"displayTickLabels":@(axis.displayTickLabels),
        @"displayTitle":@(axis.displayTitle),@"displayGrid":@(axis.displayGrid)};
}
static NSDictionary *Snapshot(RSGraph *g) {
    NSMutableDictionary *objects = [NSMutableDictionary dictionary];
    for (RSVertex *v in g.Vertices) objects[[g identiferForObject:v]] = @{@"kind":@"vertex",@"x":@(v.position.x),@"y":@(v.position.y),@"shape":@(v.shape),@"width":@(v.width),@"color":Color(v.color)};
    for (RSConnectLine *l in g.Lines) objects[[g identiferForObject:l]] = @{@"kind":@"line",@"vertices":IDs(g,l.vertices.elements),@"method":@(l.connectMethod),@"width":@(l.width),@"dash":@(l.dash),@"color":Color(l.color)};
    for (RSFill *f in g.Fills) objects[[g identiferForObject:f]] = @{@"kind":@"fill",@"vertices":IDs(g,f.vertices.elements),@"color":Color(f.color)};
    for (RSTextLabel *t in g.allLabels) {
        NSFont *font = [[t attributedString] attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        objects[[g identiferForObject:t]] = @{@"kind":@"label",@"text":t.text,@"x":@(t.position.x),@"y":@(t.position.y),@"rotation":@(t.rotation),@"font":font.fontName,@"size":@(font.pointSize),@"color":Color(t.color),@"owner":t.owner ? [g identiferForObject:t.owner] : @""};
    }
    NSMutableDictionary *defaults = [NSMutableDictionary dictionaryWithDictionary:g.creationDefaults];
    for (NSString *key in @[@"line-color",@"text-color",@"fill-color"]) defaults[key]=Color(defaults[key]);
    return @{@"defaults":defaults,@"objects":objects,@"canvas":@[@(g.canvasSize.width),@(g.canvasSize.height)],@"whitespace":@[@(g.whitespace.top),@(g.whitespace.right),@(g.whitespace.bottom),@(g.whitespace.left)],@"autoWhitespace":@(g.autoMaintainsWhitespace),@"background":Color(g.backgroundColor),@"axes":@[AxisSnapshot(g,g.xAxis),AxisSnapshot(g,g.yAxis)],@"fillCount":@(g.Fills.count)};
}
static void JSON(id data, NSString *path) {
    NSError *e=nil; NSData *bytes=[NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&e];
    Check(bytes && [bytes writeToFile:path options:NSDataWritingWithoutOverwriting error:&e], [NSString stringWithFormat:@"Write JSON %@: %@",path,e]);
}
// Evaluate what the native "curved" connection would draw through each sampled line (never saved).
static NSArray *CurvedProbe(RSGraph *g) {
    NSMutableArray *lines = [NSMutableArray array];
    RSDataMapper *mapper=[[[RSDataMapper alloc] initWithGraph:g] autorelease]; mapper.bounds=CGRectMake(0,0,g.canvasSize.width,g.canvasSize.height);
    for (RSConnectLine *l in g.Lines) {
        NSUInteger n = l.vertexCount; if (n < 6) continue;
        l.connectMethod = RSConnectCurved; [mapper resetCurveCache];
        NSMutableArray *points = [NSMutableArray array];
        for (NSUInteger i=0;i<=(n-1)*40;i++) {
            RSDataPoint d=[mapper convertToDataCoords:[mapper locationOnCurve:l atTime:(CGFloat)i/((n-1)*40)]];
            [points addObject:@[@(d.x),@(d.y)]];
        }
        l.connectMethod = RSConnectStraight; [mapper resetCurveCache];
        [lines addObject:@{@"line":[g identiferForObject:l],@"points":points}];
    }
    return lines;
}
static NSData *Render(RSGraph *g, NSString *stem) {
    NSMutableData *data=[NSMutableData data]; CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((CFMutableDataRef)data);
    CGRect box=CGRectMake(0,0,g.canvasSize.width,g.canvasSize.height);
    CGContextRef context=CGPDFContextCreate(consumer,&box,NULL); Check(context!=NULL,@"Create PDF context");
    CGPDFContextBeginPage(context,NULL); [NSGraphicsContext saveGraphicsState];
    @try {
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:context flipped:NO]];
        RSDataMapper *mapper=[[[RSDataMapper alloc] initWithGraph:g] autorelease]; mapper.bounds=box;
        RSGraphRenderer *renderer=[[[RSGraphRenderer alloc] initWithMapper:mapper] autorelease];
        [renderer positionAllAxisLabels];
        for (RSTextLabel *label in g.userLabels) {
            CGPoint origin=[mapper convertToViewCoords:label.position];
            Check(CGRectContainsRect(box,CGRectMake(origin.x,origin.y,label.size.width,label.size.height)),
                [@"Label clipped by canvas: " stringByAppendingString:label.text]);
        }
        // Template axis titles keep TitleMargin from every page edge (the y title is drawn rotated 90° about its origin).
        if ([stem.lastPathComponent hasPrefix:@"template-"])
            for (RSAxis *axis in @[g.xAxis,g.yAxis]) {
                if (!axis.displayTitle) continue;
                CGPoint origin=[mapper convertToViewCoords:axis.title.position]; CGSize size=axis.title.size;
                CGRect title=axis==g.yAxis ? CGRectMake(origin.x-size.height,origin.y,size.height,size.width) : CGRectMake(origin.x,origin.y,size.width,size.height);
                Check(CGRectContainsRect(CGRectInset(box,TitleMargin-.5,TitleMargin-.5),title),
                    [NSString stringWithFormat:@"Axis title \"%@\" closer than %g pt to the page edge: %@",axis.title.text,TitleMargin,NSStringFromRect(title)]);
                printf("TITLE example=%s axis=%s left=%.1f bottom=%.1f right=%.1f top=%.1f\n",stem.lastPathComponent.UTF8String,axis==g.xAxis ? "x" : "y",
                    CGRectGetMinX(title),CGRectGetMinY(title),box.size.width-CGRectGetMaxX(title),box.size.height-CGRectGetMaxY(title));
            }
        [renderer drawBackgroundWithColor:g.backgroundColor]; [renderer drawAllGraphElementsExcept:nil];
    } @finally { [NSGraphicsContext restoreGraphicsState]; }
    CGPDFContextEndPage(context); CGPDFContextClose(context); CGContextRelease(context); CGDataConsumerRelease(consumer);
    Check([data writeToFile:[stem stringByAppendingString:@".pdf"] atomically:NO],@"Write real PDF");
    // Rasterize the actual PDF, not a separately drawn approximation.
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((CFDataRef)data); CGPDFDocumentRef pdf=CGPDFDocumentCreateWithProvider(provider);
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap=CGBitmapContextCreate(NULL,box.size.width,box.size.height,8,0,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    Check(bitmap && CGPDFDocumentGetNumberOfPages(pdf)==1,@"Rasterize one-page native PDF");
    CGContextSetRGBFillColor(bitmap,1,1,1,1); CGContextFillRect(bitmap,box); CGContextDrawPDFPage(bitmap,CGPDFDocumentGetPage(pdf,1));
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
// Render, save through the production OPC writer, reopen twice, then probe point/label/fill edits with undo.
// `verify` sees both reopened graphs before they are released.
static void Deliver(RSGraph *g, ExampleOwner *owner, RSUndoer *undoer, NSString *stem, void (^verify)(RSGraph *again, RSGraph *twice)) {
    NSData *pdf=Render(g,stem); JSON(Snapshot(g),[stem stringByAppendingString:@"-before.json"]);
    Save(g,[stem stringByAppendingString:@".graphink"],pdf); NSError *e=nil; NSInteger encoding=-1;
    RSGraph *again=[RSGraph graphFromURL:[NSURL fileURLWithPath:[stem stringByAppendingString:@".graphink"]] type:RSGraphFileType undoer:undoer encoding:&encoding error:&e]; Check(again!=nil && encoding==RSGraphArchiveOPC,[NSString stringWithFormat:@"Reopen authored OPC graph: %@",e]);
    JSON(Snapshot(again),[stem stringByAppendingString:@"-reopen.json"]);
    Save(again,[stem stringByAppendingString:@"-roundtrip.graphink"],pdf); encoding=-1;
    RSGraph *twice=[RSGraph graphFromURL:[NSURL fileURLWithPath:[stem stringByAppendingString:@"-roundtrip.graphink"]] type:RSGraphFileType undoer:undoer encoding:&encoding error:&e]; Check(twice!=nil && encoding==RSGraphArchiveOPC,[NSString stringWithFormat:@"Second native OPC reopen: %@",e]);
    JSON(Snapshot(twice),[stem stringByAppendingString:@"-roundtrip.json"]);
    JSON(CurvedProbe(twice),[stem stringByAppendingString:@"-curved-probe.json"]);
    if (verify) verify(again,twice);
    RSGraphEditor *editor=[[[RSGraphEditor alloc] initWithGraph:again undoer:undoer] autorelease];
    [owner.undoManager enableUndoRegistration]; [undoer endRepetitiveUndo]; RSVertex *v=again.Vertices[0]; RSDataPoint original=v.position;
    [owner.undoManager beginUndoGrouping]; [editor changeX:original.x+.25 forElement:v]; [owner.undoManager endUndoGrouping]; [undoer endRepetitiveUndo];
    Check(v.position.x==original.x+.25,@"Native point edit"); [owner.undoManager undo]; Check(v.position.x==original.x,@"Native point edit undo");
    RSTextLabel *text=again.userLabels.lastObject; NSString *old=[[text.text copy] autorelease];
    [owner.undoManager beginUndoGrouping]; text.text=@"Editability probe"; [owner.undoManager endUndoGrouping]; [undoer endRepetitiveUndo];
    Check([text.text isEqual:@"Editability probe"],@"Native label edit"); [owner.undoManager undo]; Check([text.text isEqual:old],@"Native label undo");
    if (again.Fills.count) {
        RSFill *f=again.Fills[0]; NSColor *oldColor=f.color;
        [owner.undoManager beginUndoGrouping]; f.color=Purple(); [owner.undoManager endUndoGrouping]; [undoer endRepetitiveUndo];
        Check([f.color isEqual:Purple()],@"Native fill color edit"); [owner.undoManager undo]; Check([f.color isEqual:oldColor],@"Native fill color undo");
    }
    [owner.undoManager removeAllActions]; [twice invalidate]; [editor invalidate];
}
// Snapshot with one label removed, to compare a credited document with its original.
static NSDictionary *Without(NSDictionary *snapshot, NSString *labelID) {
    NSMutableDictionary *copy=[[snapshot mutableCopy] autorelease], *objects=[[snapshot[@"objects"] mutableCopy] autorelease];
    [objects removeObjectForKey:labelID]; copy[@"objects"]=objects; return copy;
}
// Pindyck & Rubinfeld notation for lessons 01-03 (2026-11-16): old text -> new text, label by label. Only the text of
// these labels changes; fonts, colors, positions of user labels and all geometry stay as delivered.
static NSDictionary *Relabels(NSString *stem) {
    NSDictionary *axes = @{@"Quantity Q (units/week)":@"Quantity Q (units per week)",@"Price P ($/unit)":@"Price P (dollars per unit)"};
    NSMutableDictionary *map = [NSMutableDictionary dictionaryWithDictionary:axes];
    [map addEntriesFromDictionary:@{
        @"01-market-equilibrium":@{@"01  /  Draw two curves. Label the point where they meet.":@"Draw two curves. Label the point where they meet.",@"Q* = 8\nP* = $6":@"Q0 = 8\nP0 = $6"},
        @"02-demand-and-supply-shifts":@{@"02  /  Modify one curve. Compare with the original equilibrium.":@"Modify one curve. Compare with the original equilibrium.",@"D0":@"D",@"D1":@"D′",@"S0":@"S",@"S1":@"S′",
            @"D1 = 17 − Q; keep S0\nED = (10, $7)\nHigher willingness to pay":@"D′: P = 17 − Q; keep S\nED = (10, $7)\nHigher willingness to pay",
            @"S1 = 5 + Q/2; keep D0\nES = (6, $8)\nHigher input costs":@"S′: P = 5 + Q/2; keep D\nES = (6, $8)\nHigher input costs"},
        @"03-tax-incidence-and-welfare":@{@"03  /  Fill the gains, transfers and lost trades.":@"Fill the gains, transfers and lost trades.",@"Pc = 8":@"Pb = 8",@"Pp = 5":@"Ps = 5",@"Qt = 6\nPc = $8  /  Pp = $5":@"Q1 = 6\nPb = $8  /  Ps = $5",
            @"Buyers bear $2 per unit.\nSellers bear $1 per unit.\nSellers remit the tax.":@"Buyers bear Pb − P0 = $2.\nSellers bear P0 − Ps = $1.\nSellers remit t = Pb − Ps."},
    }[stem]];
    return map;
}
static void Recolor(RSTextLabel *label, NSColor *color) {
    NSMutableDictionary *attributes = [[[label.attributedString attributesAtIndex:0 effectiveRange:NULL] mutableCopy] autorelease];
    attributes[NSForegroundColorAttributeName] = color;
    [label setAttributedString:[[[NSAttributedString alloc] initWithString:label.text attributes:attributes] autorelease]];
}
static void Relabel(RSTextLabel *label, NSString *text) {
    NSDictionary *attributes = [label.attributedString attributesAtIndex:0 effectiveRange:NULL];
    [label setAttributedString:[[[NSAttributedString alloc] initWithString:text attributes:attributes] autorelease]];
}
// Snapshot with the given labels' text, color and position left out (axis titles are re-centred when their text changes).
static NSDictionary *WithoutText(NSDictionary *snapshot, NSSet *labelIDs) {
    NSMutableDictionary *copy=[[snapshot mutableCopy] autorelease], *objects=[[snapshot[@"objects"] mutableCopy] autorelease];
    for (NSString *labelID in labelIDs) {
        NSMutableDictionary *label=[[objects[labelID] mutableCopy] autorelease];
        [label removeObjectsForKeys:@[@"text",@"x",@"y",@"color"]]; objects[labelID]=label;
    }
    copy[@"objects"]=objects; return copy;
}
// Lessons 01-03 come from the earlier Examples/Microeconomics generator, which pins older sources and products.
// Add only the credit label and the Relabels() text changes to the delivered documents read through the production reader;
// everything else must stay equal.
static int CreditLessons(NSString *originals, NSString *output) {
    NSArray *stems=@[@"01-market-equilibrium",@"02-demand-and-supply-shifts",@"03-tax-incidence-and-welfare"];
    for (NSString *name in stems) {
        ExampleOwner *owner=[[[ExampleOwner alloc] init] autorelease]; RSUndoer *undoer=[[[RSUndoer alloc] initWithOwner:owner] autorelease];
        [owner.undoManager disableUndoRegistration]; NSError *e=nil; NSInteger encoding=-1;
        NSString *source=[[originals stringByAppendingPathComponent:name] stringByAppendingString:@".graphink"];
        RSGraph *g=[RSGraph graphFromURL:[NSURL fileURLWithPath:source] type:RSGraphFileType undoer:undoer encoding:&encoding error:&e];
        Check(g!=nil && encoding==RSGraphArchiveOPC && g.creationDefaults!=nil,[NSString stringWithFormat:@"Read delivered lesson %@: %@",name,e]);
        NSDictionary *original=Snapshot(g); NSString *stem=[output stringByAppendingPathComponent:name];
        JSON(original,[stem stringByAppendingString:@"-original.json"]);
        NSDictionary *relabels=Relabels(name); NSMutableDictionary *expected=[NSMutableDictionary dictionary];
        for (RSTextLabel *label in g.allLabels) {
            NSString *text=relabels[label.text]; if (!text) continue;
            expected[[g identiferForObject:label]]=text; Relabel(label,text);
        }
        Check(expected.count==relabels.count,[@"Every relabel applies to exactly one label: " stringByAppendingString:name]);
        NSString *noteID=nil;
        for (RSTextLabel *label in g.userLabels) if ([label.text isEqual:PaleNote]) { Check(noteID==nil,@"One pale note"); noteID=[g identiferForObject:label]; Recolor(label,CreditGray()); }
        Check(noteID!=nil && !expected[noteID],[@"Pale note found once, not relabeled: " stringByAppendingString:name]);
        NSSet *changed=[[NSSet setWithArray:expected.allKeys] setByAddingObject:noteID]; original=WithoutText(original,changed);
        NSUInteger labels=g.userLabels.count; RSTextLabel *credit=Credit(g,name); NSString *creditID=[g identiferForObject:credit];
        Check(g.userLabels.count==labels+1 && ![original[@"objects"] objectForKey:creditID],@"Credit is one new label");
        Check([WithoutText(Without(Snapshot(g),creditID),changed) isEqual:original],[@"Credit and relabels changed other content: " stringByAppendingString:name]);
        Deliver(g,owner,undoer,stem,^(RSGraph *again, RSGraph *twice){
            for (RSGraph *reopened in @[again,twice]) {
                NSDictionary *snapshot=Snapshot(reopened);
                Check([snapshot[@"objects"][creditID][@"text"] isEqual:CreditFor(name)],@"Credit label survives save and reopen");
                Check([WithoutText(Without(snapshot,creditID),changed) isEqual:original],[@"Credited lesson differs from its original beyond the credit and relabels: " stringByAppendingString:name]);
                for (NSString *labelID in expected) Check([snapshot[@"objects"][labelID][@"text"] isEqual:expected[labelID]],@"Relabel survives save and reopen");
                Check([snapshot[@"objects"][noteID][@"text"] isEqual:PaleNote] && [snapshot[@"objects"][noteID][@"color"] isEqual:Color(CreditGray())],@"Pale note keeps its text and gets the credit gray");
            }
        });
        [g invalidate];
        printf("PASS credited=%s native-reopens=2 equal-to-original-plus-credit edits-and-undo=passed\n",name.UTF8String);
    }
    printf("COMPLETE credited=%lu failed=0\n",(unsigned long)stems.count); return 0;
}
int main(int argc,const char **argv) {
    @autoreleasepool { @try {
        [NSColor setIgnoresAlpha:NO]; OFController *controller=[OFController sharedController]; [controller didInitialize]; [controller startedRunning];
        if (argc==4 && !strcmp(argv[1],"--credit-lessons")) {
            int status=CreditLessons(@(argv[2]),@(argv[3]));
            Check([controller requestTermination]==OFControllerTerminateNow,@"Controller termination"); [controller willTerminate]; return status;
        }
        Check(argc==3,@"Expected new output directory and prepared data JSON"); NSString *output=@(argv[1]);
        NSError *dataError=nil; DataInputs=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[2])] options:0 error:&dataError];
        Check([DataInputs isKindOfClass:NSDictionary.class],[NSString stringWithFormat:@"Read prepared data: %@",dataError]);
        for (NSUInteger i=0;i<DocumentCount;i++) {
            DocumentSpec d=Documents[i]; NSString *name=@(d.stem);
            ExampleOwner *owner=[[[ExampleOwner alloc] init] autorelease]; RSUndoer *undoer=[[[RSUndoer alloc] initWithOwner:owner] autorelease];
            [owner.undoManager disableUndoRegistration]; RSGraph *g=MakeGraph(undoer,d); Compose(g,name); Credit(g,name);
            g.creationDefaults=@{@"font-name":@"HelveticaNeue",@"line-color":Ink(),@"text-color":Ink(),@"fill-color":[Ink() colorWithAlphaComponent:.17]};
            Deliver(g,owner,undoer,[output stringByAppendingPathComponent:name],nil); [g invalidate];
            printf("PASS example=%s native-reopens=2 edits-and-undo=passed\n",d.stem);
        }
        Check([controller requestTermination]==OFControllerTerminateNow,@"Controller termination"); [controller willTerminate];
        printf("COMPLETE examples=%lu failed=0\n",(unsigned long)DocumentCount); return 0;
    } @catch(NSException *e) { fprintf(stderr,"FAIL %s\n",e.description.UTF8String); return 1; } }
}
