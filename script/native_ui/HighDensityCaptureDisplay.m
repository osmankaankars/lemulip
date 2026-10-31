// Development-only display fixture. Never linked into Lemulip or distributed.
// CoreGraphics virtual-display selectors are undocumented; availability and
// actual mode density are checked at runtime. No TCC, SIP, root, or entitlement
// changes. The test pattern is also used by Chromium's macOS display tests:
// https://chromium.googlesource.com/chromium/src/+/HEAD/ui/display/mac/test/virtual_display_util_mac.mm
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface NSObject (CaptureDisplaySelectors)
- (id)initWithDescriptor:(id)descriptor;
- (id)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)rate;
- (BOOL)applySettings:(id)settings;
- (unsigned int)displayID;
@end

static void save(NSDictionary *record, NSString *directory) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:[directory stringByAppendingPathComponent:@"virtual-display.json"] atomically:YES];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        NSMutableDictionary *record = [@{@"status": @"unavailable", @"privateTestAPI": @YES,
            @"physicalDisplay": @NO, @"changesProduct": @NO, @"upscalesScreenshot": @NO} mutableCopy];
        CGDirectDisplayID displays[16]; uint32_t count = 0;
        if (CGGetActiveDisplayList(16, displays, &count) != kCGErrorSuccess) { save(record, directory); return 0; }
        NSMutableArray *originals = [NSMutableArray array];
        for (uint32_t i=0; i<count; i++) {
            CGRect frame = CGDisplayBounds(displays[i]);
            [originals addObject:@{@"id": @(displays[i]), @"x": @(frame.origin.x), @"y": @(frame.origin.y)}];
        }
        id virtualDisplay = nil;
        BOOL configured = NO;
        @try {
            Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
            Class displayClass = NSClassFromString(@"CGVirtualDisplay");
            Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
            Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
            if (!descriptorClass || !displayClass || !modeClass || !settingsClass) { save(record, directory); return 0; }
            id descriptor = [[descriptorClass alloc] init];
            NSDictionary *values = @{@"name": @"Lemulip Capture Fixture", @"vendorID": @735,
                @"productID": @20, @"serialNum": @12023, @"serialNumber": @12023,
                @"maxPixelsWide": @2560, @"maxPixelsHigh": @1800,
                @"sizeInMillimeters": [NSValue valueWithSize:NSMakeSize(295, 207)],
                @"redPrimary": [NSValue valueWithPoint:NSMakePoint(0.64,0.33)],
                @"greenPrimary": [NSValue valueWithPoint:NSMakePoint(0.30,0.60)],
                @"bluePrimary": [NSValue valueWithPoint:NSMakePoint(0.15,0.06)],
                @"whitePoint": [NSValue valueWithPoint:NSMakePoint(0.3127,0.3290)],
                @"queue": dispatch_get_main_queue()};
            [descriptor setValuesForKeysWithDictionary:values];
            virtualDisplay = [[displayClass alloc] initWithDescriptor:descriptor];
            if (!virtualDisplay) { record[@"status"] = @"creation-unavailable"; save(record, directory); return 0; }
            id settings = [[settingsClass alloc] init];
            id mode = [[modeClass alloc] initWithWidth:1280 height:900 refreshRate:60.0];
            [settings setValue:@1 forKey:@"hiDPI"];
            [settings setValue:@[mode] forKey:@"modes"];
            if (![virtualDisplay applySettings:settings]) { record[@"status"] = @"mode-rejected"; save(record, directory); return 0; }
            CGDirectDisplayID created = [virtualDisplay displayID];
            record[@"displayID"] = @(created);
            CGDisplayConfigRef config;
            if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess) { save(record, directory); return 0; }
            CGError error = CGConfigureDisplayOrigin(config, created, 0, 0);
            for (NSDictionary *old in originals) {
                if (error == kCGErrorSuccess) error = CGConfigureDisplayOrigin(config, [old[@"id"] unsignedIntValue],
                    [old[@"x"] intValue] + 1280, [old[@"y"] intValue]);
            }
            if (error == kCGErrorSuccess) error = CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
            else CGCancelDisplayConfiguration(config);
            configured = error == kCGErrorSuccess;
            record[@"configurationResult"] = @(error);
            NSDate *until = [NSDate dateWithTimeIntervalSinceNow:2];
            [[NSRunLoop currentRunLoop] runUntilDate:until];
            CGDisplayModeRef current = CGDisplayCopyDisplayMode(created);
            if (current) {
                size_t w=CGDisplayModeGetWidth(current), h=CGDisplayModeGetHeight(current);
                size_t pw=CGDisplayModeGetPixelWidth(current), ph=CGDisplayModeGetPixelHeight(current);
                record[@"logicalSize"]=@[@(w),@(h)]; record[@"pixelSize"]=@[@(pw),@(ph)];
                record[@"status"] = configured && pw==w*2 && ph==h*2 ? @"native-2x-mode" : @"density-not-confirmed";
                CGDisplayModeRelease(current);
            }
            save(record, directory);
            if ([record[@"status"] isEqual:@"native-2x-mode"]) {
                [@"ready" writeToFile:[directory stringByAppendingPathComponent:@"virtual-display.ready"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
                NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:900];
                while ([deadline timeIntervalSinceNow] > 0 && ![[NSFileManager defaultManager] fileExistsAtPath:[directory stringByAppendingPathComponent:@"virtual-display.stop"]]) {
                    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
                }
            }
        } @catch (NSException *exception) {
            record[@"status"] = @"unsupported-test-api";
            record[@"exception"] = exception.name;
            save(record, directory);
        } @finally {
            if (configured) {
                CGDisplayConfigRef config;
                if (CGBeginDisplayConfiguration(&config) == kCGErrorSuccess) {
                    for (NSDictionary *old in originals) CGConfigureDisplayOrigin(config, [old[@"id"] unsignedIntValue], [old[@"x"] intValue], [old[@"y"] intValue]);
                    CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
                }
            }
            virtualDisplay = nil;
        }
    }
    return 0;
}
