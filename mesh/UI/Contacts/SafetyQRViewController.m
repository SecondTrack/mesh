#import "SafetyQRViewController.h"
#import "MeshScreen.h"
#import "MeshPageHeader.h"
#import "MeshControls.h"
#import "MeshTheme.h"
#import "MeshQR.h"
#import "MeshL10n.h"

@implementation SafetyQRViewController {
    NSString *_payload, *_name;
}

- (instancetype)initWithPayload:(NSString *)payload peerName:(NSString *)name {
    if ((self = [super init])) { _payload = [payload copy]; _name = [name copy]; }
    return self;
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width;
    UIScrollView *page = [self mesh_addPageTitled:L(@"Safety number")];
    CGFloat side = W - 64, y = 24;
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(32 - 10, y - 10, side + 20, side + 20)];
    card.backgroundColor = [UIColor whiteColor];
    card.layer.cornerRadius = [MeshTheme codeRadius];
    [page addSubview:card];
    UIImageView *qr = [[UIImageView alloc] initWithFrame:CGRectMake(10, 10, side, side)];
    qr.image = [MeshQR imageForString:_payload sizePx:side * 2 module:[MeshTheme bg] background:[UIColor whiteColor]];
    qr.layer.magnificationFilter = kCAFilterNearest;
    [card addSubview:qr];
    y += side + 30;
    UILabel *hint = [MeshControls labelWithFrame:CGRectMake(24, y, W - 48, 70) font:[MeshTheme previewFont] color:[MeshTheme muted]];
    hint.numberOfLines = 0;
    hint.textAlignment = NSTextAlignmentCenter;
    hint.text = LF(@"Let %@ scan this code in their profile of you. Then scan the code of %@.", _name, _name);
    [page addSubview:hint];
    page.contentSize = CGSizeMake(W, y + 90);
}

@end
