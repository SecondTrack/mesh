#import "MeshTextViewer.h"
#import "MeshScreen.h"
#import "MeshPageHeader.h"
#import "MeshTheme.h"
#import "MeshText.h"

@implementation MeshTextViewer {
    NSString *_title, *_text;
}

- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text {
    if ((self = [super init])) { _title = [title copy]; _text = [text copy]; }
    return self;
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height, top = [MeshPageHeader height];
    [self.view addSubview:[[MeshPageHeader alloc] initWithWidth:W title:MeshStripInvisible(_title) target:self back:@selector(close)]];
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, top, W, H - top)];
    tv.editable = NO;
    tv.dataDetectorTypes = UIDataDetectorTypeNone;   // keine Links, Telefonnummern, Adressen
    tv.backgroundColor = [MeshTheme bg];
    tv.textColor = [MeshTheme ink];
    tv.font = [MeshTheme bodyFont];
    tv.text = MeshStripInvisible(_text);
    [self.view addSubview:tv];
}

- (void)close { [self mesh_dismissAnimated:YES]; }

@end
