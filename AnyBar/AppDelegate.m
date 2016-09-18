//
//  AppDelegate.m
//  AnyBar
//
//  Created by Nikita Prokopov on 14/02/15.
//  Copyright (c) 2015 Nikita Prokopov. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate()

@property (weak, nonatomic) IBOutlet NSWindow *window;
@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) GCDAsyncUdpSocket *udpSocket;
@property (assign, nonatomic) GCDAsyncUdpSocket *udpSendSocket;
@property (strong, nonatomic) NSString *imageName;
@property (assign, nonatomic) BOOL dark;
@property (assign, nonatomic) int udpPort;
@property (assign, nonatomic) int udpResponsePort;
@property (assign, nonatomic) NSString *flowTitle;

@end

@implementation AppDelegate

NSImage* TintImage(NSImage *baseImage, CGFloat r, CGFloat g, CGFloat b)
{
    return [NSImage imageWithSize:NSMakeSize(19, 19) flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        CGContextRef ctx = [NSGraphicsContext.currentContext CGContext];
        CGContextSetRGBFillColor(ctx, r, g, b, 1);
        CGContextSetBlendMode(ctx, kCGBlendModeSourceAtop);
        [baseImage drawInRect:dstRect];
        CGContextFillRect(ctx, dstRect);
        return YES;
    }];
}

- (NSImage *)dotForHex:(NSString *)hexStr
{
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"#[0-9a-fA-F]{6}" options:0 error:NULL];
        NSTextCheckingResult *match = [regex firstMatchInString:hexStr options:0 range:NSMakeRange(0, [hexStr length])];
    if (match) {
        UInt32 hexInt = 0;
        NSScanner *scanner = [NSScanner scannerWithString:[hexStr substringFromIndex:1]];
        [scanner scanHexInt:&hexInt];
        CGFloat r = ((CGFloat)((hexInt & 0xFF0000) >> 16))/255;
        CGFloat g = ((CGFloat)((hexInt & 0x00FF00) >>  8))/255;
        CGFloat b = ((CGFloat)((hexInt & 0x0000FF)      ))/255;
        return TintImage([NSImage imageNamed:@"black"], r, g, b);
    }
    return nil;
}

-(void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    _flowTitle = [self readStringFromEnvironmentVariable:@"ANYBAR_TITLE" usingDefault:@"unavailable"];
    _udpPort = -1;
    _imageName = @"white";
    self.statusItem = [self initializeStatusBarItem];
    [self refreshDarkMode];

    @try {
        _udpPort = [self getUdpPort:@"ANYBAR_PORT" withDefault:@"1738"];
        _udpSocket = [self initializeUdpSocket: _udpPort];
    }
    @catch(NSException *ex) {
        NSLog(@"Error: %@: %@", ex.name, ex.reason);
        _statusItem.image = [NSImage imageNamed:@"exclamation@2x.png"];
    }
    @finally {
        NSString *flowTitle = [NSString stringWithFormat:@"Title: %@", _flowTitle];
        NSString *portTitle = [NSString stringWithFormat:@"UDP port: %@", _udpPort >= 0 ? [NSNumber numberWithInt:_udpPort] : @"unavailable"];
        NSString *quitTitle = @"Quit";
        
        NSMenu *menu = [[NSMenu alloc] init];
        
        SEL action = nil;
        [[NSValue valueWithPointer:nil] getValue:&action];
        [menu addItemWithTitle:flowTitle action:action keyEquivalent:@""];
        
        SEL actionTwo = nil;
        [[NSValue valueWithPointer:nil] getValue:&actionTwo];
        [menu addItemWithTitle:portTitle action:actionTwo keyEquivalent:@""];
        
        SEL actionThree = nil;
        [[NSValue valueWithPointer:@selector(terminate:)] getValue:&actionThree];
        [menu addItemWithTitle:quitTitle action:actionThree keyEquivalent:@""];
        
        _statusItem.menu = menu;
    }

    NSDistributedNotificationCenter *center = [NSDistributedNotificationCenter defaultCenter];
    [center addObserver: self
               selector: @selector(refreshDarkMode)
                   name: @"AppleInterfaceThemeChangedNotification"
                 object: nil];
}

-(void)applicationWillTerminate:(NSNotification *)aNotification {
    [self shutdownUdpSocket: _udpSocket];
    _udpSocket = nil;

    [[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
    _statusItem = nil;
}

-(int) getUdpPort:(NSString*)variableName withDefault:(NSString*)defaultPort {
    int port = [self readIntFromEnvironmentVariable:variableName usingDefault:defaultPort];

    if (port < 0 || port > 65535) {
        @throw([NSException exceptionWithName:@"Argument Exception"
                            reason:[NSString stringWithFormat:@"UDP Port range is invalid: %d", port]
                            userInfo:@{@"argument": [NSNumber numberWithInt:port]}]);

    }

    return port;
}

- (void)refreshDarkMode {
    NSString *osxMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"];
    if ([osxMode isEqualToString:@"Dark"])
        self.dark = YES;
    else
        self.dark = NO;
    [self setImage:_imageName];
}

-(GCDAsyncUdpSocket*)initializeUdpSocket:(int)port {
    NSError *error = nil;
    GCDAsyncUdpSocket *udpSocket = [[GCDAsyncUdpSocket alloc]
                                    initWithDelegate:self
                                    delegateQueue:dispatch_get_main_queue()];

    [udpSocket bindToPort:port error:&error];
    if (error) {
        @throw([NSException exceptionWithName:@"UDP Exception"
                            reason:[NSString stringWithFormat:@"Binding to %d failed", port]
                            userInfo:@{@"error": error}]);
    }

    [udpSocket beginReceiving:&error];
    if (error) {
        @throw([NSException exceptionWithName:@"UDP Exception"
                            reason:[NSString stringWithFormat:@"Receiving from %d failed", port]
                            userInfo:@{@"error": error}]);
    }

    return udpSocket;
}

-(void)shutdownUdpSocket:(GCDAsyncUdpSocket*)sock {
    if (sock != nil) {
        [sock close];
    }
}

-(void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)data
      fromAddress:(NSData *)address withFilterContext:(id)filterContext {
    [self processUdpSocketMsg:sock withData:data fromAddress:address];
}

-(NSImage*)tryImage:(NSString *)path {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:path])
        return [[NSImage alloc] initWithContentsOfFile:path];
    else
        return nil;
}

-(NSString*)bundledImagePath:(NSString *)name {
    return [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
}

-(NSString*)homedirImagePath:(NSString *)name {
    return [NSString stringWithFormat:@"%@/%@/%@.png", NSHomeDirectory(), @".AnyBar", name];
}

-(void)respond {
    int udpResponseSocket = [self getUdpPort:@"ANYBAR_RESPONSE_PORT" withDefault:@"3500"];
    GCDAsyncUdpSocket *udpSendSocket = [[GCDAsyncUdpSocket alloc]
                                    initWithDelegate:self
                                    delegateQueue:dispatch_get_main_queue()];
    NSData *data = [[NSString stringWithFormat:@"Hello"] dataUsingEncoding:NSUTF8StringEncoding];
                    
    [udpSendSocket sendData:data toHost:@"localhost" port:udpResponseSocket withTimeout:-1 tag:1];
}

-(void)setImage:(NSString*) name {

    NSImage *image = nil;
    if (_dark)
        image = [self tryImage:[self bundledImagePath:[name stringByAppendingString:@"_alt@2x"]]];
    if (!image)
        image = [self tryImage:[self bundledImagePath:[name stringByAppendingString:@"@2x"]]];
    if (_dark && !image)
        image = [self tryImage:[self homedirImagePath:[name stringByAppendingString:@"_alt"]]];
    if (_dark && !image)
        image = [self tryImage:[self homedirImagePath:[name stringByAppendingString:@"_alt@2x"]]];
    if (!image)
        image = [self tryImage:[self homedirImagePath:[name stringByAppendingString:@"@2x"]]];
    if (!image)
        image = [self tryImage:[self homedirImagePath:name]];
    if (!image)
        image = [self dotForHex:name];
    if (!image) {
        if (_dark)
            image = [self tryImage:[self bundledImagePath:@"question_alt@2x"]];
        else
            image = [self tryImage:[self bundledImagePath:@"question@2x"]];
        NSLog(@"Cannot find image '%@'", name);
    }

    _statusItem.image = image;
    _imageName = name;
}

-(void)processUdpSocketMsg:(GCDAsyncUdpSocket *)sock withData:(NSData *)data
    fromAddress:(NSData *)address {
    NSString *msg = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if ([msg isEqualToString:@"quit"])
        [[NSApplication sharedApplication] terminate:nil];
    else if ([msg isEqualToString:@"ping"])
        [self respond];
    else
        [self setImage:msg];
}

-(NSStatusItem*) initializeStatusBarItem {
    NSStatusItem *statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    statusItem.alternateImage = [NSImage imageNamed:@"black_alt@2x.png"];
    statusItem.highlightMode = YES;
    return statusItem;
}

-(NSString*) readStringFromEnvironmentVariable:(NSString*)envVariable usingDefault:(NSString*)defStr {
    NSString *envStr = [[[NSProcessInfo processInfo] environment] objectForKey:envVariable];
    if (!envStr) {
        envStr = defStr;
    }
    return envStr;
}

-(int) readIntFromEnvironmentVariable:(NSString*) envVariable usingDefault:(NSString*) defStr {
    int intVal = -1;

    NSString *envStr = [[[NSProcessInfo processInfo]
                         environment] objectForKey:envVariable];
    if (!envStr) {
        envStr = defStr;
    }

    NSNumberFormatter *nFormatter = [[NSNumberFormatter alloc] init];
    nFormatter.numberStyle = NSNumberFormatterDecimalStyle;
    NSNumber *number = [nFormatter numberFromString:envStr];

    if (!number) {
        @throw([NSException exceptionWithName:@"Argument Exception"
                            reason:[NSString stringWithFormat:@"Parsing integer from %@ failed", envStr]
                            userInfo:@{@"argument": envStr}]);

    }

    intVal = [number intValue];

    return intVal;
}

-(id) osaImageBridge {
    NSLog(@"OSA Event: %@ - %@", NSStringFromSelector(_cmd), _imageName);

    return _imageName;
}


-(void) setOsaImageBridge:(id)imgName {
    NSLog(@"OSA Event: %@ - %@", NSStringFromSelector(_cmd), imgName);

    _imageName = (NSString *)imgName;

    [self setImage:_imageName];
}

@end

