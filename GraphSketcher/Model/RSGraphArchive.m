#import "RSGraphArchive.h"
#import <AppKit/NSBitmapImageRep.h>
#import <OmniUnzip/OUUnzipArchive.h>
#import <OmniUnzip/OUUnzipEntry.h>
#import <OmniUnzip/OUZipArchive.h>
#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLCursor.h>
#import <OmniAppKit/NSColor-OAExtensions.h>
#import <OmniAppKit/OAColorSpaceManager.h>
#import <libxml/tree.h>
#import <zlib.h>
#include <sys/stat.h>
#include <errno.h>

static NSString * const ControlNS=@"urn:graphink:document:1";
static NSString * const NativeNS=@"http://www.omnigroup.com/namespace/OmniGraphSketcher/v1";
static NSString * const TypesNS=@"http://schemas.openxmlformats.org/package/2006/content-types";
static NSString * const RelsNS=@"http://schemas.openxmlformats.org/package/2006/relationships";
static NSString * const RelsType=@"application/vnd.openxmlformats-package.relationships+xml";
static NSString * const ControlType=@"application/vnd.graphink.document+xml";
static NSString * const GraphType=@"application/vnd.graphink.native-graph+xml";
static NSString * const DocumentRole=@"urn:graphink:relationships:document";
static NSString * const GraphRole=@"urn:graphink:relationships:graph";
static NSString * const PreviewRole=@"urn:graphink:relationships:preview";
static NSUInteger const PartLimit=64*1024*1024,PackageLimit=128*1024*1024;

static BOOL Fail(NSError **error,NSString *reason,BOOL unsupported)
{
    if (error) *error=[NSError errorWithDomain:@"GraphinkPackage" code:unsupported?2:1 userInfo:@{NSLocalizedDescriptionKey:unsupported?@"Unsupported Graphink package profile.":@"Invalid Graphink package.",NSLocalizedFailureReasonErrorKey:reason}];
    return NO;
}
static uint16_t U16(const uint8_t *b,NSUInteger p) { return (uint16_t)(b[p]|((uint16_t)b[p+1]<<8)); }
static uint32_t U32(const uint8_t *b,NSUInteger p) { return (uint32_t)U16(b,p)|((uint32_t)U16(b,p+2)<<16); }
static BOOL ZIPPrefix(NSData *data) { const uint8_t *b=data.bytes; return data.length>=2 && b[0]=='P' && b[1]=='K'; }
static BOOL Range(NSUInteger start,NSUInteger count,NSUInteger length) { return start<=length && count<=length-start; }
static BOOL SafeName(NSString *name)
{
    if (!name.length || [name hasPrefix:@"/"] || [name hasSuffix:@"/"] || [name containsString:@"\\"] || [name containsString:@"%"] || [name containsString:@":"] || [name containsString:@"?"] || [name containsString:@"#"]) return NO;
    for (NSString *segment in [name componentsSeparatedByString:@"/"]) if (!segment.length || [segment hasSuffix:@"."]) return NO;
    if ([name isEqual:@"[Content_Types].xml"]) return YES;
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/"];
    return [name rangeOfCharacterFromSet:allowed.invertedSet].location==NSNotFound;
}
// Deliberately ZIP32/noninterleaved only. Validate EOCD, every central/local pair and ranges before lookup/patching.
static NSArray *PhysicalEntries(NSData *data,NSError **error)
{
    const uint8_t *b=data.bytes; NSUInteger n=data.length;
    if (n<22 || n>PackageLimit) { Fail(error,@"Archive exceeds the v1 size limit or has no complete EOCD.",YES); return nil; }
    NSUInteger end=n-22;
    if (U32(b,end)!=0x06054b50 || U16(b,end+20)!=0 || U16(b,end+4)!=0 || U16(b,end+6)!=0) { Fail(error,@"Only single-volume ZIP32 without archive comments is supported.",YES); return nil; }
    NSUInteger count=U16(b,end+10),position=U32(b,end+16),size=U32(b,end+12),total=0;
    if (count==0xffff || U16(b,end+8)!=count || !Range(position,size,end) || position+size!=end) { Fail(error,@"Invalid or unsupported central directory/ZIP64 layout.",NO); return nil; }
    NSMutableArray *entries=[NSMutableArray array]; NSMutableSet *names=[NSMutableSet set];
    for (NSUInteger i=0;i<count;i++) {
        if (!Range(position,46,end) || U32(b,position)!=0x02014b50) { Fail(error,@"Truncated central directory.",NO); return nil; }
        NSUInteger nameLength=U16(b,position+28),extra=U16(b,position+30),comment=U16(b,position+32),local=U32(b,position+42);
        uint16_t flags=U16(b,position+8),method=U16(b,position+10),version=U16(b,position+6);
        NSUInteger compressed=U32(b,position+20),plain=U32(b,position+24); uint32_t crc=U32(b,position+16);
        if (!Range(position+46,nameLength+extra+comment,end)) { Fail(error,@"Truncated ZIP filename/metadata.",NO); return nil; }
        if (extra || comment || U16(b,position+34) || flags || (method!=0 && method!=8) || (version!=20 && !(version==10 && method==0)) || compressed==UINT32_MAX || plain==UINT32_MAX || plain>PartLimit || plain>PackageLimit-total) { Fail(error,@"ZIP flags, compression, extra fields, ZIP64 or size exceed the documented v1 reader subset.",YES); return nil; }
        NSData *nameData=[data subdataWithRange:NSMakeRange(position+46,nameLength)];
        NSString *name=[[[NSString alloc] initWithData:nameData encoding:NSASCIIStringEncoding] autorelease];
        if (!name || memchr(nameData.bytes,0,nameData.length) || !SafeName(name)) { Fail(error,@"Invalid or unsupported OPC part name.",NO); return nil; }
        NSString *key=name.lowercaseString;
        if ([names containsObject:key]) { Fail(error,@"Duplicate or OPC-equivalent part names.",NO); return nil; }
        for (NSString *seen in names) if ([seen hasPrefix:[key stringByAppendingString:@"/"]] || [key hasPrefix:[seen stringByAppendingString:@"/"]]) { Fail(error,@"A part name is a prefix of another part.",NO); return nil; }
        [names addObject:key];
        if (!Range(local,30,end) || U32(b,local)!=0x04034b50 || U16(b,local+4)!=version || U16(b,local+6)!=flags || U16(b,local+8)!=method || U32(b,local+10)!=U32(b,position+12) || U32(b,local+14)!=crc || U32(b,local+18)!=compressed || U32(b,local+22)!=plain || U16(b,local+26)!=nameLength || U16(b,local+28)!=0 || !Range(local+30,nameLength+compressed,end) || memcmp(b+local+30,nameData.bytes,nameLength)) { Fail(error,@"Local/central ZIP records disagree or are truncated.",NO); return nil; }
        if (method==0 && (plain!=compressed || flags)) { Fail(error,@"Stored entry sizes disagree.",NO); return nil; }
        NSUInteger external=U32(b,position+38),kind=(external>>16)&S_IFMT;
        if ((kind && kind!=S_IFREG) || (external & 0x10)) { Fail(error,@"Only regular file entries are supported.",YES); return nil; }
        [entries addObject:@{@"name":name,@"central":@(position),@"local":@(local),@"end":@(local+30+nameLength+compressed),@"size":@(plain),@"crc":@(crc)}];
        total+=plain; position+=46+nameLength+extra+comment;
    }
    if (position!=end) { Fail(error,@"Unexpected central-directory records.",NO); return nil; }
    NSArray *ordered=[entries sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *c){return [a[@"local"] compare:c[@"local"]];}];
    NSUInteger next=0,central=U32(b,end+16);
    for (NSDictionary *entry in ordered) { if ([entry[@"local"] unsignedIntegerValue]!=next || [entry[@"end"] unsignedIntegerValue]>central) { Fail(error,@"Overlapping, interleaved or unaccounted ZIP data.",NO); return nil; } next=[entry[@"end"] unsignedIntegerValue]; }
    if (next!=central) { Fail(error,@"Unexpected ZIP data before central directory.",NO); return nil; }
    return entries;
}
static NSXMLDocument *XML(NSData *data,NSError **error)
{
    NSXMLDocument *doc=[[[NSXMLDocument alloc] initWithData:data options:NSXMLNodeLoadExternalEntitiesNever error:error] autorelease];
    if (!doc || doc.DTD) { Fail(error,@"Malformed XML or unsupported DTD.",NO); return nil; } return doc;
}
static BOOL Element(NSXMLElement *e,NSString *name,NSString *ns,NSArray *attributes,NSError **error)
{
    if (e.kind!=NSXMLElementKind || ![e.localName isEqual:name] || ![e.URI?:@"" isEqual:ns]) return Fail(error,@"Unexpected XML element or namespace.",YES);
    for (NSXMLNode *a in e.attributes) if (a.URI.length || ![attributes containsObject:a.name]) return Fail(error,@"Unsupported XML attribute.",YES);
    return YES;
}
static NSArray *Children(NSXMLElement *e,NSError **error)
{
    NSMutableArray *children=[NSMutableArray array];
    for (NSXMLNode *n in e.children) {
        if (n.kind==NSXMLElementKind) [children addObject:n];
        else if (n.kind!=NSXMLCommentKind && !(n.kind==NSXMLTextKind && ![n.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length)) { Fail(error,@"Unsupported XML content.",YES); return nil; }
    }
    return children;
}
static NSString *Attr(NSXMLElement *e,NSString *name) { return [e attributeForName:name].stringValue; }
static NSString *Resolve(NSString *target,NSString *source,NSError **error)
{
    if (!target.length || [target hasPrefix:@"/"] || [target rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/"].invertedSet].location!=NSNotFound) { Fail(error,@"Unsupported internal relationship URI.",YES); return nil; }
    NSMutableArray *segments=[NSMutableArray arrayWithArray:source.length?[[source stringByDeletingLastPathComponent] componentsSeparatedByString:@"/"]:@[]];
    if (segments.count==1 && ![segments[0] length]) [segments removeAllObjects];
    for (NSString *segment in [target componentsSeparatedByString:@"/"]) {
        if ([segment isEqual:@"."]) continue;
        if ([segment isEqual:@".."]) { if (!segments.count) { Fail(error,@"Relationship escapes the package root.",NO); return nil; } [segments removeLastObject]; }
        else { if (!segment.length) { Fail(error,@"Empty URI segment.",NO); return nil; } [segments addObject:segment]; }
    }
    return [[segments componentsJoinedByString:@"/"] lowercaseString];
}
static NSDictionary *Relationships(NSData *data,NSString *source,NSArray *roles,NSError **error)
{
    NSXMLDocument *doc=XML(data,error); NSXMLElement *root=doc.rootElement;
    if (!doc || !Element(root,@"Relationships",RelsNS,@[],error)) return nil;
    NSArray *children=Children(root,error); if (!children) return nil;
    NSMutableDictionary *result=[NSMutableDictionary dictionary]; NSMutableSet *ids=[NSMutableSet set];
    for (NSXMLElement *rel in children) {
        if (!Element(rel,@"Relationship",RelsNS,@[@"Id",@"Type",@"Target",@"TargetMode"],error)) return nil;
        NSArray *nested=Children(rel,error); if (!nested) return nil;
        if (nested.count) { Fail(error,@"Relationships cannot contain elements.",YES); return nil; }
        NSString *identifier=Attr(rel,@"Id"),*type=Attr(rel,@"Type"),*mode=Attr(rel,@"TargetMode");
        if (!identifier.length || xmlValidateNCName((const xmlChar *)identifier.UTF8String,0) || [ids containsObject:identifier] || !type.length || result[type]) { Fail(error,@"Invalid/duplicate relationship Id or role.",NO); return nil; }
        if (![roles containsObject:type] || (mode && ![mode isEqual:@"Internal"])) { Fail(error,@"Unsupported relationship role or external target.",YES); return nil; }
        NSString *target=Resolve(Attr(rel,@"Target"),source,error); if (!target) return nil;
        [ids addObject:identifier]; result[type]=target;
    }
    return result;
}
static BOOL ContentTypes(NSData *data,BOOL preview,NSError **error)
{
    NSXMLDocument *doc=XML(data,error); if (!doc || !Element(doc.rootElement,@"Types",TypesNS,@[],error)) return NO;
    NSArray *children=Children(doc.rootElement,error); if (!children) return NO;
    NSMutableDictionary *expected=[NSMutableDictionary dictionaryWithDictionary:@{@"/graphink/document.xml":ControlType,@"/contents.xml":GraphType}]; if (preview) expected[@"/preview.pdf"]=@"application/pdf";
    NSMutableSet *seen=[NSMutableSet set]; BOOL rels=NO;
    for (NSXMLElement *child in children) {
        if ([child.localName isEqual:@"Default"]) {
            if (!Element(child,@"Default",TypesNS,@[@"Extension",@"ContentType"],error)) return NO;
            if (rels || ![Attr(child,@"Extension").lowercaseString isEqual:@"rels"] || ![Attr(child,@"ContentType") isEqual:RelsType]) return Fail(error,@"Unsupported/duplicate default content type.",YES); rels=YES;
        } else {
            if (!Element(child,@"Override",TypesNS,@[@"PartName",@"ContentType"],error)) return NO;
            NSString *name=Attr(child,@"PartName").lowercaseString;
            if (!name || !expected[name] || ![expected[name] isEqual:Attr(child,@"ContentType")] || [seen containsObject:name]) return Fail(error,@"Missing, duplicate or unsupported content type mapping.",NO);
            [seen addObject:name];
        }
        NSArray *nested=Children(child,error); if (!nested || nested.count) return Fail(error,@"Content type entries cannot contain elements.",NO);
    }
    return (rels && seen.count==expected.count) || Fail(error,@"Required content type mapping is missing.",NO);
}

static NSColor *ReadColor(NSXMLElement *element,NSError **error)
{
    NSArray *allowed=@[@"w",@"r",@"g",@"b",@"h",@"s",@"v",@"c",@"m",@"y",@"k",@"a",@"space",@"catalog",@"name",@"archive",@"tiff",@"png"];
    if (!Element(element,@"color",@"",allowed,error)) return nil;
    NSArray *children=Children(element,error); if (!children) return nil;
    if (children.count) { Fail(error,@"Native color cannot contain child elements.",NO); return nil; }
    for (NSString *key in @[@"w",@"r",@"g",@"b",@"h",@"s",@"v",@"c",@"m",@"y",@"k",@"a"]) {
        NSString *value=Attr(element,key); if (!value) continue;
        NSScanner *scanner=[NSScanner scannerWithString:value]; double number;
        if (![scanner scanDouble:&number] || !scanner.isAtEnd || !isfinite(number) || ([key isEqual:@"a"] && (number<0 || number>1))) { Fail(error,@"Invalid native color component.",NO); return nil; }
    }
    NSString *space=Attr(element,@"space");
    if (space && ![OAColorSpaceManager colorSpaceForName:space]) { Fail(error,@"Unsupported native color space.",YES); return nil; }
    BOOL representation=NO;
    NSString *archive=Attr(element,@"archive");
    if (archive) {
        NSData *data=[[[NSData alloc] initWithBase64EncodedString:archive options:0] autorelease]; NSColor *color=nil;
        @try { if (data.length) color=[NSKeyedUnarchiver unarchivedObjectOfClass:NSColor.class fromData:data error:error]; } @catch (NSException *exception) { color=nil; }
        if (!color) { Fail(error,@"Invalid native color archive.",NO); return nil; } representation=YES;
    }
    for (NSString *key in @[@"png",@"tiff"]) if (Attr(element,key)) {
        NSData *data=[[[NSData alloc] initWithBase64EncodedString:Attr(element,key) options:0] autorelease];
        NSBitmapImageRep *bitmap=data.length?[NSBitmapImageRep imageRepWithData:data]:nil;
        if (!bitmap || bitmap.pixelsWide<=0 || bitmap.pixelsHigh<=0) { Fail(error,@"Invalid native pattern color.",NO); return nil; } representation=YES;
    }
    if (Attr(element,@"catalog") || Attr(element,@"name")) {
        if (!Attr(element,@"catalog") || !Attr(element,@"name") || ![NSColor colorWithCatalogName:Attr(element,@"catalog") colorName:Attr(element,@"name")]) { Fail(error,@"Unavailable native catalog color.",YES); return nil; } representation=YES;
    }
    if (Attr(element,@"w")) representation=YES;
    for (NSArray *tuple in @[@[@"r",@"g",@"b"],@[@"c",@"m",@"y",@"k"],@[@"h",@"s"]]) {
        BOOL any=NO,all=YES;
        for (NSString *key in tuple) { any|=Attr(element,key)!=nil; all&=Attr(element,key)!=nil; }
        if ([tuple[0] isEqual:@"h"]) all&=Attr(element,@"v")!=nil || Attr(element,@"b")!=nil;
        // b alone may be the HSV brightness component.
        if ([tuple[0] isEqual:@"r"] && Attr(element,@"h") && !Attr(element,@"r") && !Attr(element,@"g")) any=NO;
        if (any && !all) { Fail(error,@"Incomplete native color tuple.",NO); return nil; }
        representation|=all;
    }
    if (!representation) { Fail(error,@"Native color has no valid representation.",NO); return nil; }
    NSData *data=[element.XMLString dataUsingEncoding:NSUTF8StringEncoding];
    OFXMLDocument *doc=[[[OFXMLDocument alloc] initWithData:data whitespaceBehavior:nil error:error] autorelease];
    if (!doc) return nil;
    OFXMLCursor *cursor=[[[OFXMLCursor alloc] initWithDocument:doc] autorelease];
    return [NSColor colorFromXML:cursor];
}
static NSDictionary *Control(NSData *data,NSError **error)
{
    NSXMLDocument *doc=XML(data,error); NSXMLElement *root=doc.rootElement;
    if (!doc || !Element(root,@"document",ControlNS,@[@"version",@"required-features"],error)) return nil;
    if (![Attr(root,@"version") isEqual:@"1"] || !Attr(root,@"required-features")) { Fail(error,@"Unsupported or missing document version/features.",YES); return nil; }
    NSMutableSet *features=[NSMutableSet set];
    for (NSString *token in [Attr(root,@"required-features") componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (!token.length) continue;
        if (![token isEqual:@"creation-defaults-v1"]) { Fail(error,@"Unknown required document feature.",YES); return nil; }
        if ([features containsObject:token]) { Fail(error,@"Duplicate required feature.",NO); return nil; } [features addObject:token];
    }
    NSArray *children=Children(root,error); if (!children) return nil;
    if (children.count<1 || children.count>2) { Fail(error,@"Expected payload and optional creation-defaults.",YES); return nil; }
    NSXMLElement *payload=children[0];
    if (!Element(payload,@"payload",ControlNS,@[@"format",@"version"],error)) return nil;
    if (![Attr(payload,@"format") isEqual:@"native-graph-xml"] || ![Attr(payload,@"version") isEqual:@"1"]) { Fail(error,@"Unsupported native payload format/version.",YES); return nil; }
    NSArray *nested=Children(payload,error); if (!nested) return nil;
    if (nested.count) { Fail(error,@"Payload descriptor cannot contain elements.",YES); return nil; }
    if ((children.count==2)!=(features.count==1)) { Fail(error,@"Creation defaults and required feature disagree.",NO); return nil; }
    NSMutableDictionary *defaults=[NSMutableDictionary dictionary];
    if (children.count==2) {
        NSXMLElement *values=children[1];
        if (!Element(values,@"creation-defaults",ControlNS,@[@"version",@"font-name"],error)) return nil;
        if (![Attr(values,@"version") isEqual:@"1"]) { Fail(error,@"Unsupported creation defaults version.",YES); return nil; }
        NSString *font=Attr(values,@"font-name");
        if (font) { if (![font stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) { Fail(error,@"Empty native font name.",NO); return nil; } defaults[@"font-name"]=font; }
        NSArray *colors=Children(values,error); if (!colors) return nil; NSInteger previous=-1;
        NSArray *keys=@[@"line-color",@"fill-color",@"text-color"];
        for (NSXMLElement *wrapper in colors) {
            NSUInteger index=[keys indexOfObject:wrapper.localName];
            if (index==NSNotFound || (NSInteger)index<=previous || !Element(wrapper,keys[index],ControlNS,@[],error)) { Fail(error,@"Unknown, duplicate or out-of-order creation color.",YES); return nil; }
            previous=index; NSArray *color=Children(wrapper,error); if (!color) return nil;
            if (color.count!=1) { Fail(error,@"Expected one native color.",NO); return nil; }
            NSColor *value=ReadColor(color[0],error); if (!value) return nil; defaults[keys[index]]=value;
        }
    }
    return defaults;
}
static BOOL PDFPreview(NSData *data,NSError **error)
{
    return (data.length>=5 && memcmp(data.bytes,"%PDF-",5)==0) || Fail(error,@"Preview part is not a PDF.",NO);
}
static BOOL NativePayload(NSData *data,NSError **error)
{
    NSXMLDocument *doc=XML(data,error); if (!doc) return NO;
    NSXMLElement *root=doc.rootElement;
    if (![root.localName isEqual:@"document"] || ![root.URI isEqual:NativeNS]) return Fail(error,@"Unsupported native graph payload namespace.",YES);
    NSUInteger graphs=0;
    for (NSXMLNode *node in root.children) if (node.kind==NSXMLElementKind) {
        if ([node.localName isEqual:@"model"]) return Fail(error,@"Pasteboard models are not document payloads.",NO);
        if ([node.localName isEqual:@"graph"] && [node.URI isEqual:NativeNS]) graphs++;
    }
    return graphs==1 || Fail(error,@"Native document requires exactly one graph.",NO);
}
static NSXMLElement *Node(NSString *name,NSString *ns,NSDictionary *attributes)
{
    NSXMLElement *element=[NSXMLElement elementWithName:name URI:ns];
    for (NSString *key in attributes) [element addAttribute:[NSXMLNode attributeWithName:key stringValue:attributes[key]]];
    return element;
}
static NSData *ControlData(NSDictionary *defaults,NSError **error)
{
    NSXMLElement *root=Node(@"g:document",ControlNS,@{@"version":@"1",@"required-features":defaults.count?@"creation-defaults-v1":@""});
    [root addNamespace:[NSXMLNode namespaceWithName:@"g" stringValue:ControlNS]];
    [root addChild:Node(@"g:payload",ControlNS,@{@"format":@"native-graph-xml",@"version":@"1"})];
    if (defaults.count) {
        NSMutableDictionary *attributes=[NSMutableDictionary dictionaryWithObject:@"1" forKey:@"version"];
        if (defaults[@"font-name"]) attributes[@"font-name"]=defaults[@"font-name"];
        NSXMLElement *values=Node(@"g:creation-defaults",ControlNS,attributes); [root addChild:values];
        for (NSString *key in @[@"line-color",@"fill-color",@"text-color"]) if (defaults[key]) {
            OFXMLDocument *colorDoc=[[[OFXMLDocument alloc] initWithRootElementName:@"holder" namespaceURL:nil whitespaceBehavior:nil stringEncoding:kCFStringEncodingUTF8 error:error] autorelease];
            if (!colorDoc) return nil;
            [defaults[key] appendXML:colorDoc];
            NSData *colorData=[colorDoc xmlData:error]; if (!colorData) return nil;
            NSXMLDocument *parsed=XML(colorData,error); if (!parsed) return nil;
            NSXMLElement *color=[parsed.rootElement elementsForName:@"color"].firstObject;
            if (!color) { Fail(error,@"Unable to encode native color.",NO); return nil; }
            [color retain]; [color detach];
            NSXMLElement *wrapper=Node([@"g:" stringByAppendingString:key],ControlNS,@{}); [wrapper addChild:color]; [color release]; [values addChild:wrapper];
        }
    }
    return [[[[NSXMLDocument alloc] initWithRootElement:root] autorelease] XMLData];
}

static NSData *ReadFile(NSURL *url,NSError **error)
{
    NSFileHandle *handle=[NSFileHandle fileHandleForReadingFromURL:url error:error]; if (!handle) return nil;
    @try {
        struct stat metadata;
        if (fstat(handle.fileDescriptor,&metadata)!=0) { if (error) *error=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]; return nil; }
        if (!S_ISREG(metadata.st_mode)) { Fail(error,@"A graph document must be a regular file.",NO); return nil; }
        NSData *prefix=[handle readDataUpToLength:4 error:error]; if (!prefix) return nil;
        BOOL zip=ZIPPrefix(prefix);
        if (!zip) {
            // Preserve the legacy raw-XML contract; the new archive limit applies to ZIP input.
            if (![handle seekToOffset:0 error:error]) return nil;
            return [handle readDataToEndOfFileAndReturnError:error];
        }
        if ((uint64_t)metadata.st_size>PackageLimit) { Fail(error,@"ZIP exceeds the 128 MiB v1 archive limit.",YES); return nil; }
        NSMutableData *result=[NSMutableData dataWithData:prefix];
        while (YES) {
            // The extra byte detects growth after fstat without allocating an unbounded snapshot.
            NSUInteger request=MIN((NSUInteger)1024*1024,PackageLimit+1-result.length);
            NSData *chunk=[handle readDataUpToLength:request error:error]; if (!chunk) return nil;
            if (!chunk.length) return result;
            [result appendData:chunk];
            if (result.length>PackageLimit) { Fail(error,@"ZIP exceeds the 128 MiB v1 archive limit.",YES); return nil; }
        }
    } @finally { [handle closeAndReturnError:NULL]; }
}

@implementation RSGraphArchive
+ (NSData *)normalizeProducedZIP:(NSData *)data error:(NSError **)error
{
    NSArray *entries=PhysicalEntries(data,error); if (!entries) return nil;
    NSMutableData *result=[[data mutableCopy] autorelease]; uint8_t *bytes=result.mutableBytes;
    for (NSDictionary *entry in entries) {
        NSUInteger central=[entry[@"central"] unsignedIntegerValue];
        bytes[central+5]=0; memset(bytes+central+38,0,4);
    }
    return PhysicalEntries(result,error)?result:nil;
}
 + (NSDictionary *)readURL:(NSURL *)url error:(NSError **)error
{
    if (!url.isFileURL) { Fail(error,@"Graph documents require a local file URL.",NO); return nil; }
    NSData *bytes=ReadFile(url,error); if (!bytes) return nil;
    BOOL zip=ZIPPrefix(bytes);
    if (!zip) return @{@"xml":bytes,@"encoding":@(RSGraphArchiveLegacyXML)};
    OUUnzipArchive *archive=[[[OUUnzipArchive alloc] initWithPath:nil data:(id)bytes description:url.path error:error] autorelease];
    if (!archive) { Fail(error,@"Invalid or unsupported ZIP directory; the package was not decoded.",NO); return nil; }
    BOOL recognized=NO;
    for (OUUnzipEntry *entry in archive.entries) {
        NSString *name=entry.name.lowercaseString;
        if ([name isEqual:@"[content_types].xml"] || [name isEqual:@"_rels/.rels"] || [name isEqual:@"graphink/document.xml"]) recognized=YES;
    }
    if (!recognized) {
        NSUInteger inspected=0;
        for (OUUnzipEntry *entry in archive.entries) {
            NSString *extension=entry.name.pathExtension.lowercaseString;
            if (![extension isEqual:@"xml"] && ![extension isEqual:@"rels"]) continue;
            if (entry.uncompressedSize>PartLimit || entry.uncompressedSize>PackageLimit-inspected) { Fail(error,@"XML package recognition exceeds v1 reader limits.",YES); return nil; }
            inspected+=entry.uncompressedSize;
            NSData *part=[archive dataForEntry:entry error:error]; if (!part) return nil;
            NSXMLDocument *document=XML(part,NULL); NSXMLElement *root=document.rootElement;
            if ([root.URI isEqual:ControlNS]) recognized=YES;
            // Roles/media types are XML semantics, not arbitrary annotation text containing a URI.
            if ([root.URI isEqual:RelsNS] || [root.URI isEqual:TypesNS]) for (NSXMLNode *node in root.children) {
                if (node.kind!=NSXMLElementKind) continue; NSXMLElement *element=(id)node;
                if (([element.URI isEqual:RelsNS] && [Attr(element,@"Type") isEqual:DocumentRole]) || ([element.URI isEqual:TypesNS] && [Attr(element,@"ContentType") isEqual:ControlType])) recognized=YES;
            }
            if (recognized) break;
        }
    }
    if (!recognized) {
        OUUnzipEntry *entry=[archive entryNamed:@"contents.xml"];
        if (!entry) { Fail(error,@"Legacy ZIP has no contents.xml.",NO); return nil; }
        NSData *xml=[archive dataForEntry:entry error:error]; if (!xml) return nil;
        NSMutableDictionary *result=[NSMutableDictionary dictionaryWithDictionary:@{@"xml":xml,@"encoding":@(RSGraphArchiveLegacyZIP)}];
        OUUnzipEntry *preview=[archive entryNamed:@"preview.pdf"];
        if (preview) { NSData *pdf=[archive dataForEntry:preview error:error]; if (!pdf) return nil; result[@"preview"]=pdf; }
        return result;
    }
    NSArray *physical=PhysicalEntries(bytes,error); if (!physical) return nil;
    NSMutableDictionary *entries=[NSMutableDictionary dictionary];
    for (OUUnzipEntry *entry in archive.entries) entries[entry.name]=entry;
    if (entries.count!=physical.count) { Fail(error,@"ZIP entry enumeration disagrees with central directory.",NO); return nil; }
    NSMutableSet *expected=[NSMutableSet setWithArray:@[@"[Content_Types].xml",@"_rels/.rels",@"graphink/document.xml",@"graphink/_rels/document.xml.rels",@"contents.xml"]];
    BOOL preview=entries[@"preview.pdf"]!=nil; if (preview) [expected addObject:@"preview.pdf"];
    NSMutableDictionary *parts=[NSMutableDictionary dictionary];
    for (NSDictionary *record in physical) {
        NSString *name=record[@"name"]; OUUnzipEntry *entry=entries[name];
        if (!entry || ![expected containsObject:name]) { Fail(error,@"Unknown or noncanonical package part is outside the v1 profile.",YES); return nil; }
        NSUInteger central=[record[@"central"] unsignedIntegerValue]; const uint8_t *raw=bytes.bytes;
        if (raw[central+5]!=0 || U32(raw,central+38)!=0) { Fail(error,@"ZIP producer mapping is outside the OPC v1 subset.",YES); return nil; }
        NSUInteger local=[record[@"local"] unsignedIntegerValue],start=local+30+U16(raw,local+26),compressed=U32(raw,central+20),plain=[record[@"size"] unsignedIntegerValue];
        NSMutableData *part=[NSMutableData dataWithLength:plain];
        if (U16(raw,central+10)==0) { if (plain) memcpy(part.mutableBytes,raw+start,plain); }
        else {
            // One sentinel byte detects streams expanding beyond their declared size.
            [part setLength:plain+1]; z_stream stream={0}; stream.next_in=(Bytef *)(raw+start); stream.avail_in=(uInt)compressed; stream.next_out=part.mutableBytes; stream.avail_out=(uInt)part.length;
            int initialized=inflateInit2(&stream,-MAX_WBITS),status=initialized==Z_OK?inflate(&stream,Z_FINISH):initialized;
            BOOL valid=status==Z_STREAM_END && stream.total_out==plain && stream.total_in==compressed;
            if (initialized==Z_OK) inflateEnd(&stream);
            if (!valid) { Fail(error,@"Invalid or oversized Deflate stream.",NO); return nil; } [part setLength:plain];
        }
        if (part.length!=[record[@"size"] unsignedIntegerValue] || (uint32_t)crc32(0,part.bytes,(uInt)part.length)!=[record[@"crc"] unsignedIntValue]) { Fail(error,@"ZIP data CRC/size does not match the directory.",NO); return nil; }
        parts[name]=part;
    }
    if (parts.count!=expected.count) { Fail(error,@"Required package parts are missing.",NO); return nil; }
    if (preview && !PDFPreview(parts[@"preview.pdf"],error)) return nil;
    if (!ContentTypes(parts[@"[Content_Types].xml"],preview,error)) return nil;
    NSDictionary *root=Relationships(parts[@"_rels/.rels"],@"",@[DocumentRole],error);
    if (!root) return nil;
    if (root.count!=1 || ![root[DocumentRole] isEqual:@"graphink/document.xml"]) { Fail(error,@"Required document relationship is missing or inconsistent.",NO); return nil; }
    NSDictionary *rels=Relationships(parts[@"graphink/_rels/document.xml.rels"],@"graphink/document.xml",@[GraphRole,PreviewRole],error);
    if (!rels) return nil;
    if (rels.count!=(preview?2u:1u) || ![rels[GraphRole] isEqual:@"contents.xml"] || (preview && ![rels[PreviewRole] isEqual:@"preview.pdf"])) { Fail(error,@"Payload/preview relationships disagree with package parts.",NO); return nil; }
    NSDictionary *defaults=Control(parts[@"graphink/document.xml"],error); if (!defaults) return nil;
    if (!NativePayload(parts[@"contents.xml"],error)) return nil;
    NSMutableDictionary *result=[NSMutableDictionary dictionaryWithDictionary:@{@"xml":parts[@"contents.xml"],@"defaults":defaults,@"encoding":@(RSGraphArchiveOPC)}];
    if (preview) result[@"preview"]=parts[@"preview.pdf"];
    return result;
}
+ (BOOL)writeXML:(NSData *)xml defaults:(NSDictionary *)defaults preview:(NSData *)preview encoding:(RSGraphArchiveEncoding)encoding toURL:(NSURL *)url error:(NSError **)error
{
    if (!url.isFileURL || !xml) return Fail(error,@"Cannot save without XML and a local file URL.",NO);
    if (encoding==RSGraphArchiveLegacyXML) return [xml writeToURL:url options:NSDataWritingAtomic error:error];
    if (encoding!=RSGraphArchiveLegacyZIP && encoding!=RSGraphArchiveOPC) return Fail(error,@"Unsupported document save encoding.",YES);
    NSMutableDictionary *parts=[NSMutableDictionary dictionaryWithObject:xml forKey:@"contents.xml"];
    if (preview) parts[@"preview.pdf"]=preview;
    if (encoding==RSGraphArchiveOPC) {
        if (preview && !PDFPreview(preview,error)) return NO;
        if (!NativePayload(xml,error)) return NO;
        NSData *control=ControlData(defaults,error); if (!control || !Control(control,error)) return NO;
        parts[@"graphink/document.xml"]=control;
        NSXMLElement *types=Node(@"Types",TypesNS,@{}); [types addNamespace:[NSXMLNode namespaceWithName:@"" stringValue:TypesNS]];
        [types addChild:Node(@"Default",TypesNS,@{@"Extension":@"rels",@"ContentType":RelsType})];
        NSMutableDictionary *mapping=[NSMutableDictionary dictionaryWithDictionary:@{@"/graphink/document.xml":ControlType,@"/contents.xml":GraphType}]; if (preview) mapping[@"/preview.pdf"]=@"application/pdf";
        for (NSString *name in [mapping.allKeys sortedArrayUsingSelector:@selector(compare:)]) [types addChild:Node(@"Override",TypesNS,@{@"PartName":name,@"ContentType":mapping[name]})];
        parts[@"[Content_Types].xml"]=[[[[NSXMLDocument alloc] initWithRootElement:types] autorelease] XMLData];
        NSXMLElement *root=Node(@"Relationships",RelsNS,@{}); [root addNamespace:[NSXMLNode namespaceWithName:@"" stringValue:RelsNS]];
        [root addChild:Node(@"Relationship",RelsNS,@{@"Id":@"rDocument",@"Type":DocumentRole,@"Target":@"graphink/document.xml"})];
        parts[@"_rels/.rels"]=[[[[NSXMLDocument alloc] initWithRootElement:root] autorelease] XMLData];
        NSXMLElement *rels=Node(@"Relationships",RelsNS,@{}); [rels addNamespace:[NSXMLNode namespaceWithName:@"" stringValue:RelsNS]];
        [rels addChild:Node(@"Relationship",RelsNS,@{@"Id":@"rGraph",@"Type":GraphRole,@"Target":@"../contents.xml"})];
        if (preview) [rels addChild:Node(@"Relationship",RelsNS,@{@"Id":@"rPreview",@"Type":PreviewRole,@"Target":@"../preview.pdf"})];
        parts[@"graphink/_rels/document.xml.rels"]=[[[[NSXMLDocument alloc] initWithRootElement:rels] autorelease] XMLData];
    }
    NSURL *stage=[[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:[@".graphink-save-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    BOOL success=NO;
    @try {
        OUZipArchive *archive=[[[OUZipArchive alloc] initWithPath:stage.path error:error] autorelease]; if (!archive) return NO;
        BOOL appended=YES;
        for (NSString *name in [parts.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            if (![archive appendEntryNamed:name fileType:NSFileTypeRegular contents:parts[name] date:nil error:error]) { appended=NO; break; }
        }
        NSError *closeError=nil; BOOL closed=[archive close:&closeError];
        if (!appended) return NO;
        if (!closed) { if (error) *error=closeError; return NO; }
        if (encoding==RSGraphArchiveOPC) {
            NSData *raw=[NSData dataWithContentsOfURL:stage options:0 error:error]; if (!raw) return NO;
            NSData *normalized=[self normalizeProducedZIP:raw error:error]; if (!normalized || ![normalized writeToURL:stage options:0 error:error]) return NO;
            if (![self readURL:stage error:error]) return NO;
        }
        // Same-directory rename atomically replaces the target only after complete validation.
        if (rename(stage.fileSystemRepresentation,url.fileSystemRepresentation)!=0) { if (error) *error=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]; return NO; }
        success=YES;
    } @finally {
        if (!success) [[NSFileManager defaultManager] removeItemAtURL:stage error:NULL];
    }
    return success;
}
@end
