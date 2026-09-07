/*
 * WaifuCAD Cocoa/AppKit native front-end bridge (v1).
 *
 * Functional scope of this first bridge:
 *   - native NSWindow sized from the shared theme config;
 *   - Sections ribbon row plus a horizontally scrolling contextual command
 *     row rendered from the toolkit-neutral ribbon descriptors: project SVG
 *     icons from assets/icons/ above humanised command captions, matching
 *     the GTK4 compact ribbon conventions;
 *   - shared command console: every typed line and every ribbon click is
 *     submitted through the semantic SCL/journal path (submit_command /
 *     run_ribbon_command), never through direct model mutation;
 *   - model navigator rail listing displayable bodies with exact/preview
 *     status and bounds;
 *   - Metal-backed viewport (CAMetalLayer clear pass) with an isometric
 *     bounding-box wireframe overlay, axis triad and status text.
 *
 * SVG loading relies on NSImage's system SVG support (macOS 11+); when an
 * icon file is absent or undecodable the button gracefully degrades to its
 * caption, so the bridge never fails on missing art.
 *
 * Deliberately still TODO (tracked in AGENTS.MD): data-driven feature
 * dialogues, sketch creation/snapping interaction, Model Navigator parity
 * with GTK4 (reordering/properties), localisation-key lookup from
 * assets/locales/, and the dedicated Metal WaifuBRep renderer replacing the
 * bounds-wireframe overlay.
 *
 * Compile with clang -fobjc-arc against the macOS SDK; link
 * -framework Cocoa -framework Metal -framework QuartzCore (build.sh does).
 */

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import "wc_cocoa.h"

#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------ */
/* Bridge-wide state. The event loop runs on the D main thread inside  */
/* wc_cocoa_run, so plain statics are safe here.                       */
/* ------------------------------------------------------------------ */

static WcCocoaCallbacks g_callbacks;
static void *g_userData = NULL;

#define WC_COCOA_MAX_BODIES 256
static WcCocoaBodyRow g_bodies[WC_COCOA_MAX_BODIES];
static size_t g_bodyCount = 0;

static NSImage *g_themeImage = nil;
static BOOL g_hasMetal = NO;
static NSMutableDictionary *g_iconCache = nil;

static NSColor *WcBackgroundColour(void)
{
    return [NSColor colorWithCalibratedRed:0.07 green:0.07 blue:0.11 alpha:1.0];
}

static NSColor *WcRailColour(void)
{
    return [NSColor colorWithCalibratedRed:0.11 green:0.11 blue:0.16 alpha:1.0];
}

static NSColor *WcAccentColour(void)
{
    return [NSColor colorWithCalibratedRed:0.95 green:0.55 blue:0.75 alpha:1.0];
}

static NSColor *WcTextColour(void)
{
    return [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];
}

static void WcRefreshBodies(void)
{
    g_bodyCount = 0;
    if (g_callbacks.body_rows == NULL)
        return;
    size_t total = g_callbacks.body_rows(g_userData, g_bodies, WC_COCOA_MAX_BODIES);
    g_bodyCount = total < WC_COCOA_MAX_BODIES ? total : WC_COCOA_MAX_BODIES;
}

/* ------------------------------------------------------------------ */
/* Icon + caption helpers mirroring the GTK4 bridge conventions.       */
/* ------------------------------------------------------------------ */

/* Loads assets/icons/<name>.svg at a logical point size. Missing files or
 * undecodable art return nil; results (including misses) are cached. */
static NSImage *WcLoadIcon(const char *name, CGFloat size)
{
    if (name == NULL || name[0] == '\0')
        return nil;
    if (g_iconCache == nil)
        g_iconCache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%s@%d", name, (int)size];
    id cached = g_iconCache[key];
    if (cached != nil)
        return cached == [NSNull null] ? nil : cached;

    NSString *path = [NSString stringWithFormat:@"assets/icons/%s.svg", name];
    NSImage *image = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path])
    {
        image = [[NSImage alloc] initWithContentsOfFile:path];
        if (image != nil)
            image.size = NSMakeSize(size, size);
    }
    if (image != nil)
        g_iconCache[key] = image;
    else
        g_iconCache[key] = [NSNull null];
    return image;
}

/* Same contract as the GTK4 bridge's humanise_identifier(): keep the suffix
 * after the last dot, turn '_'/'-' into spaces and title-case each word. */
static NSString *WcHumanise(const char *identifier)
{
    if (identifier == NULL)
        return @"";
    const char *source = identifier;
    for (const char *scan = identifier; *scan != '\0'; ++scan)
        if (*scan == '.')
            source = scan + 1;
    NSMutableString *output = [NSMutableString string];
    BOOL wordStart = YES;
    for (const char *cursor = source; *cursor != '\0'; ++cursor)
    {
        char ch = *cursor;
        if (ch == '_' || ch == '-')
        {
            [output appendString:@" "];
            wordStart = YES;
            continue;
        }
        if (wordStart && ch >= 'a' && ch <= 'z')
            ch = (char)(ch - 'a' + 'A');
        char piece[2] = { ch, '\0' };
        [output appendString:[NSString stringWithUTF8String:piece]];
        wordStart = NO;
    }
    return output;
}

/* ------------------------------------------------------------------ */
/* Ribbon background view: dark fill plus the Nightcore art top-right. */
/* ------------------------------------------------------------------ */

@interface WcRibbonView : NSView
@end

@implementation WcRibbonView
- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    [WcRailColour() setFill];
    NSRectFill(self.bounds);
    NSRect separator = NSMakeRect(0, 0, self.bounds.size.width, 2);
    [WcAccentColour() setFill];
    NSRectFill(separator);
    if (g_themeImage != nil)
    {
        CGFloat height = 88.0;
        NSRect target = NSMakeRect(self.bounds.size.width - height - 8, 6, height, height);
        [g_themeImage drawInRect:target
                        fromRect:NSZeroRect
                       operation:NSCompositingOperationSourceOver
                        fraction:0.9];
    }
}
@end

/* ------------------------------------------------------------------ */
/* Metal viewport: CAMetalLayer clear pass themed to the background.   */
/* Falls back to a plain AppKit fill when no Metal device exists.      */
/* ------------------------------------------------------------------ */

@interface WcMetalView : NSView
{
    id<MTLCommandQueue> _queue;
    BOOL _metal;
}
@end

@implementation WcMetalView

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self != nil)
    {
        self.wantsLayer = YES;
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device != nil)
        {
            _queue = [device newCommandQueue];
            CAMetalLayer *layer = [CAMetalLayer layer];
            layer.device = device;
            layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
            layer.framebufferOnly = YES;
            self.layer = layer;
            _metal = YES;
            g_hasMetal = YES;
        }
    }
    return self;
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    if (_metal && self.window != nil)
    {
        CAMetalLayer *layer = (CAMetalLayer *)self.layer;
        layer.contentsScale = self.window.backingScaleFactor;
    }
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    if (!_metal)
    {
        [WcBackgroundColour() setFill];
        NSRectFill(self.bounds);
        return;
    }
    CAMetalLayer *layer = (CAMetalLayer *)self.layer;
    CGFloat scale = layer.contentsScale > 0.0 ? layer.contentsScale : 1.0;
    CGSize size = CGSizeMake(self.bounds.size.width * scale, self.bounds.size.height * scale);
    if (size.width < 1.0 || size.height < 1.0)
        return;
    layer.drawableSize = size;
    id<CAMetalDrawable> drawable = [layer nextDrawable];
    if (drawable == nil)
        return;
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    NSColor *background = WcBackgroundColour();
    pass.colorAttachments[0].clearColor = MTLClearColorMake(background.redComponent,
                                                            background.greenComponent,
                                                            background.blueComponent,
                                                            1.0);
    id<MTLCommandBuffer> buffer = [_queue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
    [encoder endEncoding];
    [buffer presentDrawable:drawable];
    [buffer commit];
}

@end

/* ------------------------------------------------------------------ */
/* Overlay view: isometric bounding-box wireframes, axis triad, hints. */
/* ------------------------------------------------------------------ */

@interface WcOverlayView : NSView
@end

typedef struct WcPoint2 { CGFloat x; CGFloat y; } WcPoint2;

static WcPoint2 WcProjectIso(double x, double y, double z)
{
    WcPoint2 result;
    result.x = (CGFloat)((x - y) * 0.8660254037844386);
    result.y = (CGFloat)(z - (x + y) * 0.5);
    return result;
}

@implementation WcOverlayView

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self != nil)
        self.wantsLayer = YES;
    return self;
}

- (BOOL)isOpaque
{
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSRect rect = self.bounds;
    if (!g_hasMetal)
    {
        [WcBackgroundColour() setFill];
        NSRectFill(rect);
    }

    NSDictionary *hintAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12],
        NSForegroundColorAttributeName : [WcTextColour() colorWithAlphaComponent:0.75]
    };

    if (g_bodyCount == 0)
    {
        NSString *hint = @"No bodies yet — type Ruby-like .wcs SCL below, for example:\n"
                         @"box(:body, 80.mm, 50.mm, 10.mm)";
        NSSize hintSize = [hint sizeWithAttributes:hintAttributes];
        [hint drawAtPoint:NSMakePoint((rect.size.width - hintSize.width) * 0.5,
                                      (rect.size.height - hintSize.height) * 0.5)
           withAttributes:hintAttributes];
        return;
    }

    /* Fit all projected corner bounds plus the world origin into the view. */
    BOOL haveBounds = NO;
    CGFloat minX = 0, minY = 0, maxX = 0, maxY = 0;
    for (size_t body = 0; body < g_bodyCount; ++body)
    {
        const double *b = g_bodies[body].bounds;
        for (int corner = 0; corner < 8; ++corner)
        {
            double x = (corner & 1) ? b[3] : b[0];
            double y = (corner & 2) ? b[4] : b[1];
            double z = (corner & 4) ? b[5] : b[2];
            WcPoint2 projected = WcProjectIso(x, y, z);
            if (!haveBounds)
            {
                minX = maxX = projected.x;
                minY = maxY = projected.y;
                haveBounds = YES;
            }
            else
            {
                if (projected.x < minX) minX = projected.x;
                if (projected.x > maxX) maxX = projected.x;
                if (projected.y < minY) minY = projected.y;
                if (projected.y > maxY) maxY = projected.y;
            }
        }
    }
    WcPoint2 origin = WcProjectIso(0, 0, 0);
    if (origin.x < minX) minX = origin.x;
    if (origin.x > maxX) maxX = origin.x;
    if (origin.y < minY) minY = origin.y;
    if (origin.y > maxY) maxY = origin.y;

    CGFloat margin = 32.0;
    CGFloat spanX = maxX - minX;
    CGFloat spanY = maxY - minY;
    if (spanX < 1.0e-6) spanX = 1.0;
    if (spanY < 1.0e-6) spanY = 1.0;
    CGFloat scale = (rect.size.width - 2 * margin) / spanX;
    CGFloat scaleByHeight = (rect.size.height - 2 * margin) / spanY;
    if (scaleByHeight < scale) scale = scaleByHeight;
    if (scale <= 0.0) scale = 1.0;
    CGFloat centreX = rect.size.width * 0.5 - ((minX + maxX) * 0.5) * scale;
    CGFloat centreY = rect.size.height * 0.5 - ((minY + maxY) * 0.5) * scale;

    /* Axis triad first so bodies draw over it. */
    double axisWorld = 0.0;
    for (size_t body = 0; body < g_bodyCount; ++body)
    {
        const double *b = g_bodies[body].bounds;
        double dx = b[3] - b[0], dy = b[4] - b[1], dz = b[5] - b[2];
        double largest = dx > dy ? dx : dy;
        if (dz > largest) largest = dz;
        if (largest > axisWorld) axisWorld = largest;
    }
    axisWorld = axisWorld > 0.0 ? axisWorld * 0.35 : 10.0;
    NSColor *axisColours[3] = {
        [NSColor colorWithCalibratedRed:0.90 green:0.30 blue:0.30 alpha:0.9],
        [NSColor colorWithCalibratedRed:0.35 green:0.80 blue:0.40 alpha:0.9],
        [NSColor colorWithCalibratedRed:0.40 green:0.55 blue:0.95 alpha:0.9]
    };
    const char *axisNames[3] = { "X", "Y", "Z" };
    double axisVectors[3][3] = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } };
    for (int axis = 0; axis < 3; ++axis)
    {
        WcPoint2 tip = WcProjectIso(axisVectors[axis][0] * axisWorld,
                                    axisVectors[axis][1] * axisWorld,
                                    axisVectors[axis][2] * axisWorld);
        [axisColours[axis] setStroke];
        NSBezierPath *one = [NSBezierPath bezierPath];
        [one setLineWidth:1.5];
        [one moveToPoint:NSMakePoint(origin.x * scale + centreX, origin.y * scale + centreY)];
        [one lineToPoint:NSMakePoint(tip.x * scale + centreX, tip.y * scale + centreY)];
        [one stroke];
        NSString *label = [NSString stringWithUTF8String:axisNames[axis]];
        [label drawAtPoint:NSMakePoint(tip.x * scale + centreX + 3, tip.y * scale + centreY + 3)
            withAttributes:@{ NSFontAttributeName : [NSFont boldSystemFontOfSize:10],
                              NSForegroundColorAttributeName : axisColours[axis] }];
    }

    /* Body wireframes: solid for exact WaifuBRep geometry, dashed amber for
       preview-only bodies, matching the exact/preview-only status policy. */
    NSDictionary *labelAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:10],
        NSForegroundColorAttributeName : [WcTextColour() colorWithAlphaComponent:0.85]
    };
    for (size_t body = 0; body < g_bodyCount; ++body)
    {
        const double *b = g_bodies[body].bounds;
        BOOL exact = g_bodies[body].exact != 0;
        NSColor *colour = exact ? [WcTextColour() colorWithAlphaComponent:0.9]
                                : [NSColor colorWithCalibratedRed:1.0 green:0.7 blue:0.2 alpha:0.9];
        [colour setStroke];
        static const int edges[12][2] = {
            { 0, 1 }, { 1, 3 }, { 3, 2 }, { 2, 0 },
            { 4, 5 }, { 5, 7 }, { 7, 6 }, { 6, 4 },
            { 0, 4 }, { 1, 5 }, { 2, 6 }, { 3, 7 }
        };
        WcPoint2 corners[8];
        for (int corner = 0; corner < 8; ++corner)
        {
            double x = (corner & 1) ? b[3] : b[0];
            double y = (corner & 2) ? b[4] : b[1];
            double z = (corner & 4) ? b[5] : b[2];
            corners[corner] = WcProjectIso(x, y, z);
        }
        for (int edge = 0; edge < 12; ++edge)
        {
            NSBezierPath *segment = [NSBezierPath bezierPath];
            [segment setLineWidth:exact ? 1.4 : 1.1];
            if (!exact)
            {
                CGFloat pattern[2] = { 4.0, 3.0 };
                [segment setLineDash:pattern count:2 phase:0.0];
            }
            [segment moveToPoint:NSMakePoint(corners[edges[edge][0]].x * scale + centreX,
                                             corners[edges[edge][0]].y * scale + centreY)];
            [segment lineToPoint:NSMakePoint(corners[edges[edge][1]].x * scale + centreX,
                                             corners[edges[edge][1]].y * scale + centreY)];
            [segment stroke];
        }
        NSString *name = g_bodies[body].name != NULL
            ? [NSString stringWithUTF8String:g_bodies[body].name]
            : @"(unnamed)";
        WcPoint2 labelAnchor = corners[6]; /* top corner (+x,+y,+z) */
        [name drawAtPoint:NSMakePoint(labelAnchor.x * scale + centreX + 4,
                                      labelAnchor.y * scale + centreY + 4)
           withAttributes:labelAttributes];
    }

    NSString *footer = [NSString stringWithFormat:@"bodies: %zu   projection: isometric   renderer: Metal clear + bounds overlay (WaifuBRep renderer pending)",
                        g_bodyCount];
    [footer drawAtPoint:NSMakePoint(8, 6) withAttributes:hintAttributes];
}

@end

/* ------------------------------------------------------------------ */
/* Controller: window, ribbon rows, console, navigator, actions.       */
/* ------------------------------------------------------------------ */

#define WC_RIBBON_HEIGHT 100.0
#define WC_CONSOLE_HEIGHT 44.0
#define WC_COMMAND_BUTTON_WIDTH 58.0
#define WC_COMMAND_BUTTON_HEIGHT 46.0

@interface WcAppDelegate : NSObject <NSApplicationDelegate, NSTextFieldDelegate>
@property (strong) NSWindow *window;
@property (strong) WcRibbonView *ribbonView;
@property (strong) NSView *viewportContainer;
@property (strong) WcMetalView *metalView;
@property (strong) WcOverlayView *overlayView;
@property (strong) NSScrollView *navigatorScroll;
@property (strong) NSTextView *navigatorView;
@property (strong) NSView *consoleBar;
@property (strong) NSTextField *commandField;
@property (strong) NSTextField *statusLabel;
@property (strong) NSScrollView *commandScroll;
@property (strong) NSMutableArray<NSView *> *ribbonControls;
@property (strong) NSMutableArray<NSString *> *sectionIds;
@property (strong) NSMutableArray<NSString *> *commandIds;
@end

static WcAppDelegate *g_delegate = nil;

static void WcSetStatus(NSString *text)
{
    if (g_delegate != nil && g_delegate.statusLabel != nil)
        g_delegate.statusLabel.stringValue = text;
}

@implementation WcAppDelegate

- (void)buildUiWithConfig:(const WcCocoaWindowConfig *)config
{
    CGFloat width = config->width > 0 ? (CGFloat)config->width : 1024.0;
    CGFloat height = config->height > 0 ? (CGFloat)config->height : 768.0;
    NSString *title = config->title != NULL ? [NSString stringWithUTF8String:config->title] : @"WaifuCAD";

    NSRect contentRect = NSMakeRect(0, 0, width, height);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    self.window = [[NSWindow alloc] initWithContentRect:contentRect
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    [self.window setTitle:title];
    [self.window setBackgroundColor:WcBackgroundColour()];
    [self.window setContentMinSize:NSMakeSize(800, 600)];

    self.ribbonControls = [NSMutableArray array];
    self.sectionIds = [NSMutableArray array];
    self.commandIds = [NSMutableArray array];

    /* Ribbon strip across the top: sections row + scrolling command row. */
    NSRect ribbonFrame = NSMakeRect(0, height - WC_RIBBON_HEIGHT, width, WC_RIBBON_HEIGHT);
    self.ribbonView = [[WcRibbonView alloc] initWithFrame:ribbonFrame];
    self.ribbonView.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self.window.contentView addSubview:self.ribbonView];

    NSImage *brandIcon = WcLoadIcon("waifucad", 26);
    if (brandIcon != nil)
    {
        NSImageView *brandView = [[NSImageView alloc] initWithFrame:NSMakeRect(8, 66, 26, 26)];
        brandView.image = brandIcon;
        brandView.imageScaling = NSImageScaleProportionallyDown;
        brandView.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
        [self.ribbonView addSubview:brandView];
    }

    NSTextField *brand = [NSTextField labelWithString:@"WaifuCAD"];
    brand.font = [NSFont boldSystemFontOfSize:13];
    brand.textColor = WcAccentColour();
    brand.frame = NSMakeRect(brandIcon != nil ? 38 : 10, 70, 100, 18);
    brand.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    [self.ribbonView addSubview:brand];

    /* Horizontally scrolling contextual command row (GTK4 compact parity). */
    NSRect commandScrollFrame = NSMakeRect(4, 2, width - 8, 60);
    self.commandScroll = [[NSScrollView alloc] initWithFrame:commandScrollFrame];
    self.commandScroll.hasHorizontalScroller = YES;
    self.commandScroll.hasVerticalScroller = NO;
    self.commandScroll.borderType = NSNoBorder;
    self.commandScroll.backgroundColor = WcRailColour();
    self.commandScroll.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.ribbonView addSubview:self.commandScroll];

    /* Viewport: Metal surface plus transparent overlay, in a container. */
    CGFloat middleTop = height - WC_RIBBON_HEIGHT - 4;
    CGFloat middleHeight = middleTop - WC_CONSOLE_HEIGHT;
    if (middleHeight < 40) middleHeight = 40;
    NSRect viewportFrame = NSMakeRect(4, WC_CONSOLE_HEIGHT + 4, width - 240, middleHeight);
    self.viewportContainer = [[NSView alloc] initWithFrame:viewportFrame];
    self.viewportContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.window.contentView addSubview:self.viewportContainer];

    self.metalView = [[WcMetalView alloc] initWithFrame:self.viewportContainer.bounds];
    self.metalView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.viewportContainer addSubview:self.metalView];

    self.overlayView = [[WcOverlayView alloc] initWithFrame:self.viewportContainer.bounds];
    self.overlayView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.viewportContainer addSubview:self.overlayView];

    /* Model navigator rail on the right. */
    NSRect navigatorFrame = NSMakeRect(width - 228, WC_CONSOLE_HEIGHT + 4, 224, middleHeight);
    self.navigatorScroll = [[NSScrollView alloc] initWithFrame:navigatorFrame];
    self.navigatorScroll.hasVerticalScroller = YES;
    self.navigatorScroll.autoresizingMask = NSViewMinXMargin | NSViewHeightSizable;
    self.navigatorScroll.borderType = NSBezelBorder;
    self.navigatorScroll.backgroundColor = WcRailColour();
    NSTextView *navigator = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, navigatorFrame.size.width - 16, navigatorFrame.size.height)];
    navigator.autoresizingMask = NSViewWidthSizable;
    navigator.editable = NO;
    navigator.selectable = YES;
    navigator.richText = NO;
    navigator.backgroundColor = WcRailColour();
    navigator.textColor = WcTextColour();
    navigator.font = [NSFont fontWithName:@"Menlo" size:11] ?: [NSFont systemFontOfSize:11];
    navigator.textContainerInset = NSMakeSize(6, 6);
    self.navigatorView = navigator;
    self.navigatorScroll.documentView = navigator;
    [self.window.contentView addSubview:self.navigatorScroll];

    /* Shared command console bar along the bottom. */
    NSRect consoleFrame = NSMakeRect(0, 0, width, WC_CONSOLE_HEIGHT);
    self.consoleBar = [[NSView alloc] initWithFrame:consoleFrame];
    self.consoleBar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.window.contentView addSubview:self.consoleBar];

    NSTextField *prompt = [NSTextField labelWithString:@"Command:"];
    prompt.font = [NSFont boldSystemFontOfSize:12];
    prompt.textColor = WcTextColour();
    prompt.frame = NSMakeRect(10, 13, 76, 18);
    prompt.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    [self.consoleBar addSubview:prompt];

    self.commandField = [NSTextField textFieldWithString:@""];
    self.commandField.placeholderString = @"box(:body, 80.mm, 50.mm, 10.mm)";
    self.commandField.font = [NSFont fontWithName:@"Menlo" size:12] ?: [NSFont systemFontOfSize:12];
    self.commandField.frame = NSMakeRect(92, 10, width - 92 - 300, 24);
    self.commandField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.commandField.delegate = self;
    [self.consoleBar addSubview:self.commandField];

    self.statusLabel = [NSTextField labelWithString:@"Ready"];
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = [WcTextColour() colorWithAlphaComponent:0.8];
    self.statusLabel.frame = NSMakeRect(width - 296, 13, 288, 18);
    self.statusLabel.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [self.consoleBar addSubview:self.statusLabel];

    /* Minimal main menu so standard editing key equivalents work. */
    NSMenu *mainMenu = [[NSMenu alloc] init];
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"Quit WaifuCAD" action:@selector(terminate:) keyEquivalent:@"q"];
    appMenuItem.submenu = appMenu;
    [mainMenu addItem:appMenuItem];
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editMenuItem.submenu = editMenu;
    [mainMenu addItem:editMenuItem];
    [NSApp setMainMenu:mainMenu];

    [self rebuildRibbon];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.commandField];
}

- (void)rebuildRibbon
{
    /* Sections row: persistent Sections/Mods tabs first, then Section chips. */
    for (NSView *control in self.ribbonControls)
        [control removeFromSuperview];
    [self.ribbonControls removeAllObjects];
    [self.sectionIds removeAllObjects];
    [self.commandIds removeAllObjects];

    NSFont *regular = [NSFont systemFontOfSize:10];
    NSFont *bold = [NSFont boldSystemFontOfSize:10];
    CGFloat rowY = 66.0;
    CGFloat x = 142.0;

    WcCocoaSectionEntry sections[32];
    size_t sectionTotal = g_callbacks.section_entries != NULL
        ? g_callbacks.section_entries(g_userData, sections, 32)
        : 0;
    if (sectionTotal > 32)
        sectionTotal = 32;
    for (size_t i = 0; i < sectionTotal; ++i)
    {
        NSString *sectionId = sections[i].id != NULL ? [NSString stringWithUTF8String:sections[i].id] : @"";
        NSButton *button = [NSButton buttonWithTitle:WcHumanise([sectionId UTF8String])
                                              target:self
                                              action:@selector(onSectionClicked:)];
        button.bezelStyle = NSBezelStyleRounded;
        button.font = sections[i].active ? bold : regular;
        button.tag = (NSInteger)i;
        NSImage *icon = WcLoadIcon(sections[i].icon, 16);
        if (icon != nil)
        {
            button.image = icon;
            button.imagePosition = NSImageLeft;
            button.imageScaling = NSImageScaleProportionallyDown;
        }
        CGSize natural = [[button cell] cellSize];
        CGFloat buttonWidth = natural.width + 14;
        if (buttonWidth < 72) buttonWidth = 72;
        if (buttonWidth > 150) buttonWidth = 150;
        button.frame = NSMakeRect(x, rowY, buttonWidth, 26);
        button.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
        [[button cell] setLineBreakMode:NSLineBreakByTruncatingTail];
        button.toolTip = sectionId;
        [self.ribbonView addSubview:button];
        [self.ribbonControls addObject:button];
        [self.sectionIds addObject:sectionId];
        x += buttonWidth + 5;
    }

    /* Persistent Mods tab: the registry has no Mod tabs yet, so it renders
       disabled exactly like a planned command. */
    NSButton *mods = [NSButton buttonWithTitle:@"Mods" target:nil action:NULL];
    mods.bezelStyle = NSBezelStyleRounded;
    mods.font = regular;
    mods.enabled = NO;
    NSImage *modsIcon = WcLoadIcon("tab_mods", 16);
    if (modsIcon != nil)
    {
        mods.image = modsIcon;
        mods.imagePosition = NSImageLeft;
        mods.imageScaling = NSImageScaleProportionallyDown;
    }
    CGSize modsNatural = [[mods cell] cellSize];
    CGFloat modsWidth = modsNatural.width + 14;
    if (modsWidth < 72) modsWidth = 72;
    mods.frame = NSMakeRect(x, rowY, modsWidth, 26);
    mods.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    mods.toolTip = @"Mods ribbon tab (no Mods registered)";
    [self.ribbonView addSubview:mods];
    [self.ribbonControls addObject:mods];

    /* Contextual command row inside the horizontal scroller: icon above a
       humanised caption, grouped by ribbon tab with tab markers. */
    WcCocoaRibbonCommand commands[64];
    size_t commandTotal = g_callbacks.ribbon_commands != NULL
        ? g_callbacks.ribbon_commands(g_userData, commands, 64)
        : 0;
    if (commandTotal > 64)
        commandTotal = 64;

    NSView *document = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 64, 47)];
    CGFloat docX = 6.0;
    NSString *currentTab = nil;
    NSFont *tabFont = [NSFont boldSystemFontOfSize:8];
    for (size_t i = 0; i < commandTotal; ++i)
    {
        NSString *tabId = commands[i].tab_id != NULL ? [NSString stringWithUTF8String:commands[i].tab_id] : @"";
        if (currentTab == nil || ![currentTab isEqualToString:tabId])
        {
            if (currentTab != nil)
            {
                NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(docX, 6, 1, 34)];
                divider.boxType = NSBoxSeparator;
                [document addSubview:divider];
                docX += 7.0;
            }
            currentTab = tabId;
            NSImage *tabIcon = WcLoadIcon(commands[i].tab_icon, 12);
            if (tabIcon != nil)
            {
                NSImageView *tabImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(docX, 32, 12, 12)];
                tabImageView.image = tabIcon;
                tabImageView.imageScaling = NSImageScaleProportionallyDown;
                [document addSubview:tabImageView];
                docX += 15.0;
            }
            NSTextField *tabLabel = [NSTextField labelWithString:WcHumanise([tabId UTF8String])];
            tabLabel.font = tabFont;
            tabLabel.textColor = WcAccentColour();
            [tabLabel sizeToFit];
            CGFloat labelWidth = tabLabel.frame.size.width + 2;
            tabLabel.frame = NSMakeRect(docX, 34, labelWidth, 11);
            [document addSubview:tabLabel];
            docX += labelWidth + 4.0;
        }

        NSString *commandId = commands[i].id != NULL ? [NSString stringWithUTF8String:commands[i].id] : @"";
        NSString *caption = WcHumanise([commandId UTF8String]);
        NSButton *button = [NSButton buttonWithTitle:caption target:self action:@selector(onCommandClicked:)];
        button.bezelStyle = NSBezelStyleRounded;
        button.font = [NSFont systemFontOfSize:8];
        button.tag = (NSInteger)i;
        button.enabled = commands[i].planned == 0;
        NSImage *icon = WcLoadIcon(commands[i].icon, 20);
        if (icon != nil)
        {
            button.image = icon;
            button.imagePosition = NSImageAbove;
            button.imageScaling = NSImageScaleProportionallyDown;
        }
        [[button cell] setLineBreakMode:NSLineBreakByTruncatingTail];
        CGSize natural = [[button cell] cellSize];
        CGFloat buttonWidth = natural.width + 10;
        if (buttonWidth < WC_COMMAND_BUTTON_WIDTH) buttonWidth = WC_COMMAND_BUTTON_WIDTH;
        if (buttonWidth > 104) buttonWidth = 104;
        button.frame = NSMakeRect(docX, 0, buttonWidth, WC_COMMAND_BUTTON_HEIGHT);
        NSString *tooltip = commands[i].label != NULL
            ? [NSString stringWithFormat:@"%@\n%@", caption, commandId]
            : commandId;
        button.toolTip = tooltip;
        [document addSubview:button];
        [self.commandIds addObject:commandId];
        docX += buttonWidth + 4.0;
    }

    NSRect documentFrame = NSMakeRect(0, 0, docX + 8, 47);
    document.frame = documentFrame;
    self.commandScroll.documentView = document;
    [self.commandScroll.contentView scrollToPoint:NSMakePoint(0, 0)];
    [self.commandScroll reflectScrolledClipView:self.commandScroll.contentView];
}

- (void)refreshNavigator
{
    NSMutableString *text = [NSMutableString stringWithString:@"Model\n─────\n"];
    if (g_bodyCount == 0)
    {
        [text appendString:@"(no bodies yet)\n"];
    }
    for (size_t i = 0; i < g_bodyCount; ++i)
    {
        const WcCocoaBodyRow *row = &g_bodies[i];
        [text appendFormat:@"%s [%s]\n  %.1f × %.1f × %.1f mm\n",
                           row->name != NULL ? row->name : "(unnamed)",
                           row->exact ? "exact" : "preview",
                           row->bounds[3] - row->bounds[0],
                           row->bounds[4] - row->bounds[1],
                           row->bounds[5] - row->bounds[2]];
    }
    [text appendString:@"\nSections ribbon above;\nRuby-like .wcs SCL below.\nGetters: get_feature_*\n"];
    self.navigatorView.string = text;
}

- (void)onSectionClicked:(NSButton *)sender
{
    if (sender.tag < 0 || (size_t)sender.tag >= self.sectionIds.count)
        return;
    NSString *sectionId = self.sectionIds[(NSUInteger)sender.tag];
    int result = g_callbacks.choose_section != NULL
        ? g_callbacks.choose_section(g_userData, [sectionId UTF8String])
        : 10;
    if (result == 0)
    {
        [self rebuildRibbon];
        WcSetStatus([NSString stringWithFormat:@"Section: %@", WcHumanise([sectionId UTF8String])]);
    }
    else
        WcSetStatus([NSString stringWithFormat:@"Section %@ unavailable (%d)", sectionId, result]);
}

- (void)onCommandClicked:(NSButton *)sender
{
    if (sender.tag < 0 || (size_t)sender.tag >= self.commandIds.count)
        return;
    NSString *commandId = self.commandIds[(NSUInteger)sender.tag];
    int result = g_callbacks.run_ribbon_command != NULL
        ? g_callbacks.run_ribbon_command(g_userData, [commandId UTF8String])
        : 10;
    WcRefreshBodies();
    [self.overlayView setNeedsDisplay:YES];
    [self.metalView setNeedsDisplay:YES];
    [self refreshNavigator];
    WcSetStatus(result == 0
        ? [NSString stringWithFormat:@"%@: OK", WcHumanise([commandId UTF8String])]
        : [NSString stringWithFormat:@"%@: SCL error %d", WcHumanise([commandId UTF8String]), result]);
}

- (void)submitConsoleLine
{
    NSString *text = self.commandField.stringValue;
    if (text.length == 0)
        return;
    char *line = strdup([text UTF8String]);
    int result = 10;
    if (line != NULL)
    {
        if (g_callbacks.submit_command != NULL)
            result = g_callbacks.submit_command(g_userData, line);
        free(line);
    }
    self.commandField.stringValue = @"";
    WcRefreshBodies();
    [self.overlayView setNeedsDisplay:YES];
    [self.metalView setNeedsDisplay:YES];
    [self refreshNavigator];
    WcSetStatus(result == 0
        ? [NSString stringWithFormat:@"OK: %@", text]
        : [NSString stringWithFormat:@"SCL error %d: %@", result, text]);
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    (void)control;
    (void)textView;
    if (commandSelector == @selector(insertNewline:))
    {
        [self submitConsoleLine];
        return YES;
    }
    return NO;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

@end

/* ------------------------------------------------------------------ */
/* C ABI entry points.                                                 */
/* ------------------------------------------------------------------ */

int wc_cocoa_native_available(void)
{
    return 1;
}

int wc_cocoa_run(const WcCocoaWindowConfig *config,
                 const WcCocoaCallbacks *callbacks,
                 void *user_data)
{
    if (config == NULL || callbacks == NULL || callbacks->submit_command == NULL)
        return 10;

    g_callbacks = *callbacks;
    g_userData = user_data;
    g_themeImage = nil;
    if (config->navigator_background != NULL)
    {
        NSString *path = [NSString stringWithUTF8String:config->navigator_background];
        if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path])
            g_themeImage = [[NSImage alloc] initByReferencingFile:path];
    }

    @autoreleasepool
    {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        WcAppDelegate *delegate = [[WcAppDelegate alloc] init];
        g_delegate = delegate;
        [NSApp setDelegate:delegate];
        [delegate buildUiWithConfig:config];

        WcRefreshBodies();
        [delegate refreshNavigator];
        WcSetStatus(@"Ready — Ruby-like .wcs SCL");

        [NSApp activateIgnoringOtherApps:YES];
        [NSApp run];
    }
    return 0;
}
