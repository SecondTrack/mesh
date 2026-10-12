#import "QRScannerViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import "MeshTheme.h"
#import "MeshControls.h"
#import "MeshPopup.h"
#import "MeshL10n.h"
#import "MeshQRDecoder.h"
#import "MeshSplitCode.h"

@interface QRScannerViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>
@end

@implementation QRScannerViewController {
    AVCaptureSession *_session;
    AVCaptureVideoDataOutput *_output;
    dispatch_queue_t _queue;
    MeshQRDecoder *_decoder;   // nur auf _queue benutzt
    int _frameSkip;
    volatile BOOL _done;   // Kamera-Queue: kein weiteres Bild dekodieren
    BOOL _finished;        // Main-Thread: Scanner ist geschlossen
    MeshSplitCode *_split; // nur auf _queue: sammelt "1/2" und "2/2" eines geteilten iPod-Codes
    UILabel *_hint;
}

- (void)loadView {
    [self mesh_useFullScreenLayout];
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = [UIColor blackColor];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _queue = dispatch_queue_create("mesh.qr", NULL);
    [self startCamera];
    [self buildOverlay];
}

- (void)startCamera {
    _session = [[AVCaptureSession alloc] init];

    AVCaptureDevice *dev = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *err = nil;
    AVCaptureDeviceInput *in = [AVCaptureDeviceInput deviceInputWithDevice:dev error:&err];
    if (!in) { [self fail:L(@"No camera available")]; return; }
    if ([_session canAddInput:in]) [_session addInput:in];
    // 720p, wo die Kamera es kann (iPod 4 hinten): dichte Codes (Mesh-Code mit Signal-Paket, 61 Module)
    // bekommen so gut doppelt so viele Pixel je Modul; ausgewertet wird nur das mittlere Quadrat.
    _session.sessionPreset = [_session canSetSessionPreset:AVCaptureSessionPreset1280x720] ? AVCaptureSessionPreset1280x720
                                                                                          : AVCaptureSessionPreset640x480;

    AVCaptureVideoDataOutput *out = [[AVCaptureVideoDataOutput alloc] init];
    out.videoSettings = @{ (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA) };
    out.alwaysDiscardsLateVideoFrames = YES;
    [out setSampleBufferDelegate:self queue:_queue];
    _output = out;
    if ([_session canAddOutput:out]) [_session addOutput:out];

    AVCaptureVideoPreviewLayer *prev = [AVCaptureVideoPreviewLayer layerWithSession:_session];
    prev.frame = self.view.bounds;
    prev.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer addSublayer:prev];

    [_session startRunning];
}

- (void)buildOverlay {
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    // Zielrahmen (Mint)
    CGFloat box = 200;
    UIView *frame = [[UIView alloc] initWithFrame:CGRectMake((W-box)/2, (H-box)/2, box, box)];
    frame.backgroundColor = [UIColor clearColor];
    frame.layer.borderColor = [MeshTheme accent].CGColor; frame.layer.borderWidth = 3;
    frame.layer.cornerRadius = [MeshTheme cardRadius];
    [self.view addSubview:frame];

    UILabel *hint = _hint = [[UILabel alloc] initWithFrame:CGRectMake(20, (H-box)/2 - 40, W-40, 24)];
    hint.text = L(@"Hold the npub QR in the frame"); hint.textColor = [MeshTheme ink];
    hint.textAlignment = NSTextAlignmentCenter; hint.font = [MeshTheme bodyFont];
    hint.backgroundColor = [UIColor clearColor];
    [self.view addSubview:hint];

    [self.view addSubview:[MeshControls primaryButtonWithFrame:CGRectMake(20, H - 120, W - 40, 44) title:L(@"Paste code") target:self action:@selector(tapManual)]];
    [self.view addSubview:[MeshControls secondaryButtonWithFrame:CGRectMake(20, H - 66, W - 40, 46) title:L(@"Cancel") target:self action:@selector(tapCancel)]];
}

- (void)tapCancel { [self stopAndDismissWith:nil]; }

- (void)tapManual {
    if (_finished) return;
    _finished = YES;
    _done = YES;
    [_session stopRunning];
    void (^cb)(void) = self.onManual;
    [self mesh_dismissAnimated:YES];
    if (cb) cb();
}

- (void)fail:(NSString *)msg {
    [MeshPopup info:msg];
}

#pragma mark - Frames

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    if (_done) return;
    if ((_frameSkip++ % 4) != 0) return;   // nicht jeden Frame (iPod4 ist langsam)

    if (!_decoder) _decoder = [[MeshQRDecoder alloc] init];
    NSString *payload = [_decoder decodePixelBuffer:CMSampleBufferGetImageBuffer(sampleBuffer)];
    if (!payload) return;
    if ([MeshSplitCode isPart:payload]) {   // geteilter iPod-Code: erst weiter, wenn beide Teile da sind
        if (!_split) _split = [[MeshSplitCode alloc] init];
        NSString *full = [_split add:payload];
        if (!full) {
            NSInteger n = _split.lastPart;
            dispatch_async(dispatch_get_main_queue(), ^{
                _hint.text = n == 1 ? L(@"Part 1/2 ✓ – now show part 2") : L(@"Part 2/2 ✓ – now show part 1");
                _hint.textColor = [MeshTheme accent];
            });
            return;
        }
        payload = full;
    }
    _done = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ [self stopAndDismissWith:payload]; });
}

// Nur einmal: Ein Bild, das gerade erkannt wurde, darf nach "Abbrechen" keinen Kontakt mehr anlegen.
- (void)stopAndDismissWith:(NSString *)payload {
    if (_finished) return;
    _finished = YES;
    _done = YES;
    [_session stopRunning];
    void (^cb)(NSString *) = self.onScan;
    [self mesh_dismissAnimated:YES];
    if (payload && cb) cb(payload);
}

// Erst die Kamera stoppen und die Queue leerlaufen lassen, sonst greift ein Bild, das gerade
// verarbeitet wird, auf den Decoder zu, während er freigegeben wird.
- (void)dealloc {
    [_session stopRunning];
    [_output setSampleBufferDelegate:nil queue:NULL];
    if (_queue) { dispatch_sync(_queue, ^{}); mesh_dispatch_release(_queue); }
}

@end
