#import "ProfileEditViewController.h"
#import "MeshScreen.h"
#import "MeshAvatarView.h"
#import "MeshPopup.h"
#import "MeshTheme.h"
#import "MeshPageHeader.h"
#import "MeshSession.h"
#import "MeshL10n.h"
#import "MeshImageCodec.h"
#import "MeshCaps.h"
#import "MeshControls.h"
#import "MeshProfile.h"
#import "MeshImagePicker.h"

@implementation ProfileEditViewController {
    UITextField *_name;
    UITextField *_about;
    MeshAvatarView *_avatar;   // zeigt das noch nicht gespeicherte Bild als Vorschau
    MeshProfile *_profile;  // wird bearbeitet, gespeichert erst mit "Speichern"
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width;

    // Header
    MeshPageHeader *header = [[MeshPageHeader alloc] initWithWidth:W title:L(@"Edit profile") target:self back:@selector(mesh_goBack)];
    UIButton *save = [UIButton buttonWithType:UIButtonTypeCustom];
    save.frame = CGRectMake(W - 76, [MeshTheme topInset] + 8, 66, 30);
    [save setTitle:L(@"Save") forState:UIControlStateNormal];
    [save setTitleColor:[MeshTheme accent] forState:UIControlStateNormal];
    save.titleLabel.font = [MeshTheme nameFont];
    [save addTarget:self action:@selector(tapSave) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:save];
    [self.view addSubview:header];

    _profile = [[MeshSession shared] profile];
    NSString *pk = [[MeshSession shared] myPubkeyHex] ?: @"";

    // Avatar mit Kamera-Plakette; beides antippen wählt ein Bild
    CGFloat y = [MeshPageHeader height] + 24, av = 96;
    _avatar = [[MeshAvatarView alloc] initWithFrame:CGRectMake((W-av)/2, y, av, av) source:MeshAvatarPreview];
    _avatar.pubkey = pk;
    [self.view addSubview:_avatar];
    [self showPicture];
    UIButton *cam = [MeshAvatarView badgeWithGlyph:@"camera" diameter:36 forAvatarFrame:_avatar.frame];
    cam.userInteractionEnabled = YES;
    [cam addTarget:self action:@selector(pickImage) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:cam];
    // Tippen aufs Bild -> auch wählen
    UIButton *avTap = [UIButton buttonWithType:UIButtonTypeCustom];
    avTap.frame = CGRectMake((W-av)/2, y, av, av);
    [avTap addTarget:self action:@selector(pickImage) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:avTap];
    y += av + 26;

    y = [self addLabel:L(@"NAME") at:y width:W];
    _name = [MeshControls fieldWithFrame:CGRectMake(16, y, W - 32, 46) placeholder:L(@"e.g. Anna") mono:NO delegate:self];
    _name.text = _profile.name; [self.view addSubview:_name]; y += 62;

    y = [self addLabel:L(@"ABOUT") at:y width:W];
    _about = [MeshControls fieldWithFrame:CGRectMake(16, y, W - 32, 46) placeholder:L(@"Short description") mono:NO delegate:self];
    _about.text = _profile.about; [self.view addSubview:_about]; y += 62;
}

- (CGFloat)addLabel:(NSString *)text at:(CGFloat)y width:(CGFloat)W {
    [self.view addSubview:[MeshControls sectionLabelWithFrame:CGRectMake(18, y, W - 36, 16) text:text]];
    return y + 22;
}

- (void)showPicture { _avatar.picture = _profile.picture; }

- (void)pickImage {
    [self.view endEditing:YES];
    BOOL cam = [MeshCaps hasCamera];
    NSArray *opts = cam ? @[L(@"Camera"), L(@"Photo Library")] : @[L(@"Photo Library")];
    [MeshPopup sheet:L(@"Profile picture") options:opts destructiveIndex:-1 handler:^(NSInteger idx) {
        if (idx < 0) return;
        UIImagePickerControllerSourceType src = (cam && idx == 0)
            ? UIImagePickerControllerSourceTypeCamera : UIImagePickerControllerSourceTypePhotoLibrary;
        [MeshImagePicker pickFrom:self source:src done:^(UIImage *image) {
            self->_profile.picture = [MeshImageCodec pictureFromJPEG:[MeshImageCodec jpegForAvatar:image]];
            [self showPicture];
        }];
    }];
}

- (void)tapSave {
    _profile.name = _name.text ?: @"";
    _profile.about = _about.text ?: @"";
    [[MeshSession shared] saveProfile:_profile];
    [self mesh_goBack];
}
- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return NO; }

// Unter iOS 4 sind Delegates unsafe_unretained, hier selbst lösen.
- (void)dealloc { _name.delegate = nil; _about.delegate = nil; }

@end
