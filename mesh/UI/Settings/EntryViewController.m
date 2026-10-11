#import "EntryViewController.h"
#import "MeshScreen.h"
#import "MeshTheme.h"
#import "MeshControls.h"
#import "MeshPageHeader.h"
#import "MeshL10n.h"

static const CGFloat kFieldHeight = 44;

@implementation EntryViewController {
    NSString *_title, *_text;
    UIScrollView *_scroll;
    UITextField *_field, *_again;
    UILabel *_error;
}

- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text {
    if ((self = [super init])) { _title = [title copy]; _text = [text copy]; _saveTitle = L(@"Save"); }
    return self;
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width, inner = W - 32;
    _scroll = [self mesh_addPageTitled:_title];
    CGFloat y = 16;

    if (self.status.length) {
        UILabel *st = [MeshControls labelWithFrame:CGRectMake(20, y, W - 40, 18) font:[MeshTheme labelFont] color:[MeshTheme accent]];
        st.text = self.status;
        [_scroll addSubview:st];
        y += 24;
    }
    CGFloat h = [_text sizeWithFont:[MeshTheme previewFont] constrainedToSize:CGSizeMake(W - 40, 600)
                      lineBreakMode:NSLineBreakByWordWrapping].height;
    UILabel *text = [MeshControls labelWithFrame:CGRectMake(20, y, W - 40, h) font:[MeshTheme previewFont] color:[MeshTheme muted]];
    text.text = _text;
    text.numberOfLines = 0;
    [_scroll addSubview:text];
    y += h + 18;

    if (!self.fieldless) {
        _field = [self addFieldAt:y placeholder:self.placeholder];
        y += kFieldHeight + 10;
        if (self.repeat) {
            _again = [self addFieldAt:y placeholder:L(@"Repeat")];
            y += kFieldHeight + 10;
        }
    }
    _error = [MeshControls labelWithFrame:CGRectMake(20, y, W - 40, 18) font:[MeshTheme timeFont] color:[MeshTheme danger]];
    [_scroll addSubview:_error];
    y += 24;

    [_scroll addSubview:[MeshControls primaryButtonWithFrame:CGRectMake(16, y, inner, kFieldHeight) title:self.saveTitle target:self action:@selector(save)]];
    y += kFieldHeight + 10;
    if (self.removeTitle) {
        UIButton *remove = [MeshControls secondaryButtonWithFrame:CGRectMake(16, y, inner, kFieldHeight) title:self.removeTitle target:self action:@selector(remove)];
        [remove setTitleColor:[MeshTheme danger] forState:UIControlStateNormal];
        [_scroll addSubview:remove];
        y += kFieldHeight + 10;
    }
    _scroll.contentSize = CGSizeMake(W, y + 10);
}

- (UITextField *)addFieldAt:(CGFloat)y placeholder:(NSString *)placeholder {
    UITextField *f = [MeshControls fieldWithFrame:CGRectMake(16, y, self.view.bounds.size.width - 32, kFieldHeight)
                                      placeholder:placeholder mono:YES delegate:self];
    f.secureTextEntry = self.secure;
    if ([f respondsToSelector:@selector(setSpellCheckingType:)]) f.spellCheckingType = UITextSpellCheckingTypeNo;   // ab iOS 5
    f.returnKeyType = UIReturnKeyDone;
    [_scroll addSubview:f];
    return f;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clear)
                                                 name:UIApplicationWillResignActiveNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)clear { _field.text = @""; _again.text = @""; }

// Sichere Felder leeren sich sonst beim Weitertippen nach einem Fokuswechsel.
- (BOOL)textField:(UITextField *)tf shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)s {
    if (!tf.secureTextEntry) return YES;
    tf.text = [tf.text stringByReplacingCharactersInRange:range withString:s];
    return NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    if (tf == _field && _again) [_again becomeFirstResponder]; else [self save];
    return NO;
}

- (void)endEditing { [self.view endEditing:YES]; }   // Tastatur und Einrückung regelt MeshScreen

- (void)save {
    if (_again && ![_again.text isEqualToString:_field.text ?: @""]) { _error.text = L(@"Entries don't match"); return; }
    [self endEditing];
    NSString *failed = self.onSave ? self.onSave(_field.text ?: @"") : nil;
    _error.text = failed ?: @"";
    if (failed) [self clear];
}

- (void)remove {
    [self endEditing];
    if (self.onRemove) self.onRemove();
}

@end
