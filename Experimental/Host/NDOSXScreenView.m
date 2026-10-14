#import "SDL_uikitopenglview.h"
#import "SDL_uikitappdelegate.h"
#import "NDOSXHost.h"
#import "DPSettings.h"

@interface NDOSXDisplayLinkTarget : NSObject
@property(nonatomic, weak) NDOSXScreenView *view;
- (void)tick:(CADisplayLink *)link;
@end
@interface NDOSXScreenView ()
@property(nonatomic, strong) CADisplayLink *displayLink;
@property(nonatomic, strong) UIImage *currentImage;
@property(nonatomic) CGPoint previousPoint;
@property(nonatomic) BOOL dragging;
@property(nonatomic) BOOL stopped;
- (void)presentFrame;
@end
@implementation NDOSXDisplayLinkTarget
- (void)tick:(CADisplayLink *)link { [self.view presentFrame]; }
@end
@implementation NDOSXScreenView
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.blackColor;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(engineStopped:) name:@"NDOSXEngineStopped" object:nil];
        self.layer.contentsGravity=kCAGravityResize;
        UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [self addGestureRecognizer:pan];
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
        [tap requireGestureRecognizerToFail:pan];[self addGestureRecognizer:tap];
        UITapGestureRecognizer *right=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rightTap:)];
        right.numberOfTouchesRequired=2;[self addGestureRecognizer:right];
        UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hold:)];
        hold.minimumPressDuration=0.4;[self addGestureRecognizer:hold];
    }
    return self;
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self.displayLink invalidate];self.displayLink=nil;
    if(self.window && !self.stopped) {
        NDOSXDisplayLinkTarget *target=[NDOSXDisplayLinkTarget new];target.view=self;
        self.displayLink=[CADisplayLink displayLinkWithTarget:target selector:@selector(tick:)];
        [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}
- (void)dealloc {[self.displayLink invalidate];[[NSNotificationCenter defaultCenter] removeObserver:self];}
- (void)engineStopped:(NSNotification *)notification {
    self.stopped=YES;
    [self.displayLink invalidate];self.displayLink=nil;self.userInteractionEnabled=NO;
    UILabel *status=[[UILabel alloc] initWithFrame:self.bounds];
    status.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    status.text=@"Session stopped — close and reopen nDOS-X";
    status.textColor=UIColor.whiteColor;status.backgroundColor=[UIColor colorWithWhite:0 alpha:0.8];
    status.textAlignment=NSTextAlignmentCenter;status.numberOfLines=0;[self addSubview:status];
    UIViewController *controller=self.window.rootViewController;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"nDOS-X stopped" message:@"Close and reopen the app to start another session. Shut down a booted operating system before closing the emulator." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    if(!controller.presentedViewController)[controller presentViewController:alert animated:YES completion:nil];
}
- (void)presentFrame {
    UIImage *image=ndos_x_take_frame();if(!image)return;
    self.currentImage=image;self.layer.contents=(__bridge id)image.CGImage;
    if(!CGSizeEqualToSize(self.bounds.size,image.size)) {
        self.bounds=(CGRect){CGPointZero,image.size};[self.delegate onResize:image.size];
    }
}
- (void)pan:(UIPanGestureRecognizer *)gesture {
    CGPoint point=[gesture translationInView:self];
    if(gesture.state==UIGestureRecognizerStateBegan)self.previousPoint=CGPointZero;
    [self sendMouseMotion:0 x:point.x-self.previousPoint.x y:point.y-self.previousPoint.y];self.previousPoint=point;
}
- (void)tap:(UITapGestureRecognizer *)gesture {
    if([DPSettings shared].tapAsClick){[self sendMouseEvent:0 left:YES down:YES];[self sendMouseEvent:0 left:YES down:NO];}
}
- (void)rightTap:(UITapGestureRecognizer *)gesture {[self sendMouseEvent:0 left:NO down:YES];[self sendMouseEvent:0 left:NO down:NO];}
- (void)hold:(UILongPressGestureRecognizer *)gesture {
    CGPoint point=[gesture locationInView:self];
    if(gesture.state==UIGestureRecognizerStateBegan){self.dragging=YES;self.previousPoint=point;[self sendMouseEvent:0 left:YES down:YES];[self.mouseHoldDelegate onHold:point];}
    else if(gesture.state==UIGestureRecognizerStateChanged){[self sendMouseMotion:0 x:point.x-self.previousPoint.x y:point.y-self.previousPoint.y];self.previousPoint=point;[self.mouseHoldDelegate onHoldMoved:point];}
    else {self.dragging=NO;[self sendMouseEvent:0 left:YES down:NO];[self.mouseHoldDelegate cancelHold:point];}
}
- (void)cancelEmulatorTouches {self.dragging=NO;ndos_x_release_inputs();[self.mouseHoldDelegate cancelHold:CGPointZero];}
- (void)sendMouseEvent:(int)index left:(BOOL)left down:(BOOL)down {ndos_x_send_mouse_button(left?1:3,down);}
- (void)sendMouseMotion:(int)index x:(CGFloat)x y:(CGFloat)y {ndos_x_send_mouse_motion(x*(1+2*[DPSettings shared].mouseSpeed),y*(1+2*[DPSettings shared].mouseSpeed));}
- (void)sendMouseCoordinate:(int)index x:(CGFloat)x y:(CGFloat)y { /* Initial experiment uses a relative guest mouse. */ }
- (UIImage *)capture {return self.currentImage;}
- (BOOL)resize:(CGSize)size {return YES;}
@end
@implementation NDOSXUIKitDelegate
- (void)applicationDidFinishLaunching:(UIApplication *)application { /* UIKit remains owned by nDOS. */ }
@end
