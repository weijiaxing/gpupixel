/*
 * GPUPixelDemo
 *
 * Created by PixPark on 2021/6/24.
 * Copyright © 2021 PixPark. All rights reserved.
 */

#import "VideoFilterController.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import "FilterToolbarView.h"
#import "ImageFilterController.h"
#import "ImageConverter.h"
#import "VideoCapturer.h"

#import <gpupixel/gpupixel.h>

using namespace gpupixel;

@interface VideoFilterController () <VCVideoCapturerDelegate,
                                     FilterToolbarViewDelegate,
                                     PHPickerViewControllerDelegate,
                                     UINavigationControllerDelegate,
                                     UIImagePickerControllerDelegate,
                                     UIGestureRecognizerDelegate> {
  std::shared_ptr<SourceRawData> _sourceRawData;
  std::shared_ptr<SinkRawData> _sinkRawData;
  std::shared_ptr<SinkView> _gpuPixelView;
  std::shared_ptr<BeautyFaceFilter> _beautyFaceFilter;
  std::shared_ptr<FaceReshapeFilter> _faceReshapeFilter;
  std::shared_ptr<LipstickFilter> _lipstickFilter;
  std::shared_ptr<BlusherFilter> _blusherFilter;
  std::shared_ptr<WhiteBalanceFilter> _whiteBalanceFilter;
  std::shared_ptr<SaturationFilter> _saturationFilter;
  std::shared_ptr<FaceStickerFilter> _faceStickerFilter;
  std::shared_ptr<FaceDetector> _faceDetector;

  std::vector<float> _latestLandmarks;
}

// Engine & Capture
@property(nonatomic, strong) VideoCapturer* videoCapturer;
@property(nonatomic, strong) UIView* renderView;

// Top Bar
@property(nonatomic, strong) UIView* topBarView;
@property(nonatomic, strong) UIButton* switchCameraButton;
@property(nonatomic, strong) UIButton* flashButton;
@property(nonatomic, strong) UIButton* resetButton;

// Floating Badges
@property(nonatomic, strong) UILabel* faceStatusBadge;
@property(nonatomic, strong) UIButton* compareButton;

// Bottom Panel
@property(nonatomic, strong) UIView* bottomPanelContainer;
@property(nonatomic, strong) UIView* modeSwitchTrack;
@property(nonatomic, strong) UIButton* modePhotoBtn;
@property(nonatomic, strong) UIButton* modeVideoBtn;
@property(nonatomic, strong) UIView* modeSelectedIndicator;

// Shutter Row
@property(nonatomic, strong) UIView* shutterRow;
@property(nonatomic, strong) UIButton* albumButton;
@property(nonatomic, strong) UIButton* shutterButton;
@property(nonatomic, strong) UIView* shutterInnerCircle;
@property(nonatomic, strong) UIView* beautyWandSatellite;
@property(nonatomic, strong) UIButton* beautyWandButton;
@property(nonatomic, strong) UIView* beautyBadgeDot;
@property(nonatomic, strong) UIButton* flipCameraButton;

// Bottom Navigation Bar (Memories | Camera | Chats)
@property(nonatomic, strong) UIView* bottomNav;
@property(nonatomic, strong) UIButton* navMemoriesBtn;
@property(nonatomic, strong) UIView* navCameraContainer;
@property(nonatomic, strong) UILabel* navCameraLabel;
@property(nonatomic, strong) UIView* navCameraIndicator;
@property(nonatomic, strong) UIButton* navCameraBtn;
@property(nonatomic, strong) UIButton* navChatsBtn;

// Collapsible Beauty Panel
@property(nonatomic, strong) FilterToolbarView* filterToolbarView;

// State flags
@property(nonatomic, assign) BOOL isPanelCollapsed;
@property(nonatomic, assign) BOOL isVideoMode;
@property(nonatomic, assign) BOOL isComparing;
@property(nonatomic, assign) BOOL isCapturingPhoto;
@property(nonatomic, assign) BOOL hasFaceDetected;

@end

@implementation VideoFilterController

#pragma mark - Life cycle

- (void)viewDidLoad {
  [super viewDidLoad];
  [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
  self.view.backgroundColor = [UIColor blackColor];
  self.navigationController.navigationBarHidden = YES;
  [[UIApplication sharedApplication] setIdleTimerDisabled:YES];

  self.isPanelCollapsed = YES;
  self.isVideoMode = NO;
  self.isComparing = NO;

  [self setupGPUPixel];
  [self setupUI];
  [self loadLatestAlbumThumbnail];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  self.navigationController.navigationBarHidden = YES;
  [self checkCameraPermissionAndStart];
}

- (void)checkCameraPermissionAndStart {
  AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
  if (status == AVAuthorizationStatusAuthorized) {
    [self.videoCapturer startCapture];
  } else if (status == AVAuthorizationStatusNotDetermined) {
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (granted) {
          [self.videoCapturer startCapture];
        } else {
          [self showCameraPermissionAlert];
        }
      });
    }];
  } else {
    [self showCameraPermissionAlert];
  }
}

- (void)showCameraPermissionAlert {
  UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"需要相机权限"
                                                                 message:@"请在系统“设置”中允许访问相机，以体验实时美颜滤镜效果。"
                                                          preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
  [self.videoCapturer stopCapture];
  [super viewWillDisappear:animated];
}

- (void)dealloc {
  [self destroyGPUPixel];
}

- (void)destroyGPUPixel {
  self.videoCapturer.delegate = nil;
  [self.videoCapturer stopCapture];
  self.videoCapturer = nil;

  _beautyFaceFilter = nullptr;
  _faceReshapeFilter = nullptr;
  _lipstickFilter = nullptr;
  _blusherFilter = nullptr;
  _whiteBalanceFilter = nullptr;
  _saturationFilter = nullptr;
  _faceStickerFilter = nullptr;
  _faceDetector = nullptr;
  _gpuPixelView = nullptr;
  _sinkRawData = nullptr;
  _sourceRawData = nullptr;
}

#pragma mark - Setup GPUPixel

- (void)setupGPUPixel {
  // Attach GPU surface directly to root view like original demo
  _gpuPixelView = SinkView::Create((__bridge void*)self.view);
  _sourceRawData = SourceRawData::Create();

  _lipstickFilter = LipstickFilter::Create();
  _blusherFilter = BlusherFilter::Create();
  _faceReshapeFilter = FaceReshapeFilter::Create();
  _beautyFaceFilter = BeautyFaceFilter::Create();
  _whiteBalanceFilter = WhiteBalanceFilter::Create();
  _saturationFilter = SaturationFilter::Create();
  _faceStickerFilter = FaceStickerFilter::Create();
  _faceDetector = FaceDetector::Create();
  _sinkRawData = SinkRawData::Create();

  // Filter Pipeline:
  // Connect explicitly to avoid dynamic_cast cross-cast null pointer failures across framework boundary
  std::shared_ptr<Source> currentSource = _sourceRawData;
  if (_lipstickFilter && currentSource) {
    currentSource->AddSink(_lipstickFilter);
    currentSource = _lipstickFilter;
  }
  if (_blusherFilter && currentSource) {
    currentSource->AddSink(_blusherFilter);
    currentSource = _blusherFilter;
  }
  if (_faceReshapeFilter && currentSource) {
    currentSource->AddSink(_faceReshapeFilter);
    currentSource = _faceReshapeFilter;
  }
  if (_beautyFaceFilter && currentSource) {
    currentSource->AddSink(_beautyFaceFilter);
    currentSource = _beautyFaceFilter;
  }
  if (_whiteBalanceFilter && currentSource) {
    currentSource->AddSink(_whiteBalanceFilter);
    currentSource = _whiteBalanceFilter;
  }
  if (_saturationFilter && currentSource) {
    currentSource->AddSink(_saturationFilter);
    currentSource = _saturationFilter;
  }
  if (_faceStickerFilter && currentSource) {
    currentSource->AddSink(_faceStickerFilter);
    currentSource = _faceStickerFilter;
  }
  if (_gpuPixelView && currentSource) {
    currentSource->AddSink(_gpuPixelView);
  }

  if (_faceStickerFilter && _sinkRawData) {
    _faceStickerFilter->AddSink(_sinkRawData);
  } else if (_beautyFaceFilter && _sinkRawData) {
    _beautyFaceFilter->AddSink(_sinkRawData);
  }

  // Setup video capturer
  VCVideoCapturerParam* param = [[VCVideoCapturerParam alloc] init];
  param.frameRate = 30;
  param.sessionPreset = AVCaptureSessionPresetHigh;
  param.pixelsFormatType = kCVPixelFormatType_32BGRA;
  param.devicePosition = AVCaptureDevicePositionFront;
  param.videoOrientation = AVCaptureVideoOrientationPortrait;

  _videoCapturer = [[VideoCapturer alloc] initWithCaptureParam:param error:nil];
  _videoCapturer.delegate = self;
}

#pragma mark - Setup UI

- (void)setupUI {
  [self setupTopBar];
  [self setupFloatingWidgets];
  [self setupBottomPanel];
  [self setupBeautyPanel];
  [self applyInitialFilterParameters];

  [self.view bringSubviewToFront:self.faceStatusBadge];
  [self.view bringSubviewToFront:self.compareButton];
  [self.view bringSubviewToFront:self.topBarView];
  [self.view bringSubviewToFront:self.bottomPanelContainer];
  [self.view bringSubviewToFront:self.filterToolbarView];

  // Outside tap gesture to dismiss beauty panel (matches Android viewfinder tap)
  UITapGestureRecognizer* outsideTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleOutsideTap:)];
  outsideTap.delegate = self;
  outsideTap.cancelsTouchesInView = NO;
  [self.view addGestureRecognizer:outsideTap];
}

- (void)setupTopBar {
  _topBarView = [[UIView alloc] init];
  _topBarView.translatesAutoresizingMaskIntoConstraints = NO;
  _topBarView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
  [self.view addSubview:_topBarView];

  // 1. Switch Camera Button
  _switchCameraButton = [UIButton buttonWithType:UIButtonTypeCustom];
  _switchCameraButton.translatesAutoresizingMaskIntoConstraints = NO;
  _switchCameraButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
  _switchCameraButton.layer.cornerRadius = 22.0;
  _switchCameraButton.layer.masksToBounds = YES;
  UIImage* switchIcon = [UIImage imageNamed:@"ic_switch_camera"];
  if (!switchIcon) switchIcon = [UIImage systemImageNamed:@"camera.rotate.fill"];
  [_switchCameraButton setImage:switchIcon forState:UIControlStateNormal];
  _switchCameraButton.tintColor = [UIColor whiteColor];
  [_switchCameraButton addTarget:self action:@selector(onSwitchCameraTapped) forControlEvents:UIControlEventTouchUpInside];
  [_topBarView addSubview:_switchCameraButton];

  // 2. Flashlight Button
  _flashButton = [UIButton buttonWithType:UIButtonTypeCustom];
  _flashButton.translatesAutoresizingMaskIntoConstraints = NO;
  _flashButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
  _flashButton.layer.cornerRadius = 22.0;
  _flashButton.layer.masksToBounds = YES;
  UIImage* flashIcon = [UIImage imageNamed:@"ic_flash_off"];
  if (!flashIcon) flashIcon = [UIImage systemImageNamed:@"bolt.slash.fill"];
  [_flashButton setImage:flashIcon forState:UIControlStateNormal];
  _flashButton.tintColor = [UIColor whiteColor];
  [_flashButton addTarget:self action:@selector(onFlashTapped) forControlEvents:UIControlEventTouchUpInside];
  [_topBarView addSubview:_flashButton];

  // 3. Reset Button
  _resetButton = [UIButton buttonWithType:UIButtonTypeCustom];
  _resetButton.translatesAutoresizingMaskIntoConstraints = NO;
  _resetButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
  _resetButton.layer.cornerRadius = 18.0;
  _resetButton.layer.borderWidth = 1.0;
  _resetButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
  [_resetButton setTitle:@" 重置" forState:UIControlStateNormal];
  [_resetButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
  _resetButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  UIImage* resetIcon = [UIImage imageNamed:@"ic_reset"];
  if (!resetIcon) resetIcon = [UIImage systemImageNamed:@"arrow.counterclockwise"];
  [_resetButton setImage:resetIcon forState:UIControlStateNormal];
  _resetButton.tintColor = [UIColor whiteColor];
  _resetButton.contentEdgeInsets = UIEdgeInsetsMake(6, 12, 6, 14);
  [_resetButton addTarget:self action:@selector(onResetTapped) forControlEvents:UIControlEventTouchUpInside];
  [_topBarView addSubview:_resetButton];

  [NSLayoutConstraint activateConstraints:@[
    [_topBarView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [_topBarView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_topBarView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [_topBarView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:54],

    [_switchCameraButton.leadingAnchor constraintEqualToAnchor:_topBarView.leadingAnchor constant:20],
    [_switchCameraButton.bottomAnchor constraintEqualToAnchor:_topBarView.bottomAnchor constant:-8],
    [_switchCameraButton.widthAnchor constraintEqualToConstant:44],
    [_switchCameraButton.heightAnchor constraintEqualToConstant:44],

    [_flashButton.leadingAnchor constraintEqualToAnchor:_switchCameraButton.trailingAnchor constant:14],
    [_flashButton.centerYAnchor constraintEqualToAnchor:_switchCameraButton.centerYAnchor],
    [_flashButton.widthAnchor constraintEqualToConstant:44],
    [_flashButton.heightAnchor constraintEqualToConstant:44],

    [_resetButton.trailingAnchor constraintEqualToAnchor:_topBarView.trailingAnchor constant:-20],
    [_resetButton.centerYAnchor constraintEqualToAnchor:_switchCameraButton.centerYAnchor],
    [_resetButton.heightAnchor constraintEqualToConstant:36],
  ]];
}

- (void)setupFloatingWidgets {
  // 1. Face Status Badge (Bottom-Left)
  _faceStatusBadge = [[UILabel alloc] init];
  _faceStatusBadge.translatesAutoresizingMaskIntoConstraints = NO;
  _faceStatusBadge.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
  _faceStatusBadge.layer.cornerRadius = 14.0;
  _faceStatusBadge.layer.borderWidth = 1.0;
  _faceStatusBadge.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
  _faceStatusBadge.layer.masksToBounds = YES;
  _faceStatusBadge.text = @"人脸检测中...";
  _faceStatusBadge.textColor = [UIColor colorWithWhite:1.0 alpha:0.75];
  _faceStatusBadge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
  _faceStatusBadge.textAlignment = NSTextAlignmentCenter;
  [self.view addSubview:_faceStatusBadge];

  // 2. Compare Button (Bottom-Right, Hold to Compare)
  _compareButton = [UIButton buttonWithType:UIButtonTypeCustom];
  _compareButton.translatesAutoresizingMaskIntoConstraints = NO;
  _compareButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
  _compareButton.layer.cornerRadius = 19.0;
  _compareButton.layer.borderWidth = 1.0;
  _compareButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
  [_compareButton setTitle:@" 按住对比" forState:UIControlStateNormal];
  [_compareButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
  _compareButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
  UIImage* cmpIcon = [UIImage imageNamed:@"ic_compare"];
  if (!cmpIcon) cmpIcon = [UIImage systemImageNamed:@"square.split.2x1"];
  [_compareButton setImage:cmpIcon forState:UIControlStateNormal];
  _compareButton.tintColor = [UIColor whiteColor];
  _compareButton.contentEdgeInsets = UIEdgeInsetsMake(8, 14, 8, 16);
  [_compareButton addTarget:self action:@selector(onCompareTouchDown) forControlEvents:UIControlEventTouchDown];
  [_compareButton addTarget:self action:@selector(onCompareTouchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
  [self.view addSubview:_compareButton];

  [NSLayoutConstraint activateConstraints:@[
    [_faceStatusBadge.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
    [_faceStatusBadge.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-200],
    [_faceStatusBadge.heightAnchor constraintEqualToConstant:28],
    [_faceStatusBadge.widthAnchor constraintGreaterThanOrEqualToConstant:96],

    [_compareButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
    [_compareButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-200],
    [_compareButton.heightAnchor constraintEqualToConstant:38],
  ]];
}

- (void)setupBottomPanel {
  _bottomPanelContainer = [[UIView alloc] init];
  _bottomPanelContainer.translatesAutoresizingMaskIntoConstraints = NO;
  _bottomPanelContainer.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
  [self.view addSubview:_bottomPanelContainer];

  // 1. Mode Switch: Photo | Video
  _modeSwitchTrack = [[UIView alloc] init];
  _modeSwitchTrack.translatesAutoresizingMaskIntoConstraints = NO;
  _modeSwitchTrack.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
  _modeSwitchTrack.layer.cornerRadius = 16.0;
  _modeSwitchTrack.layer.masksToBounds = YES;
  [_bottomPanelContainer addSubview:_modeSwitchTrack];

  _modeSelectedIndicator = [[UIView alloc] init];
  _modeSelectedIndicator.translatesAutoresizingMaskIntoConstraints = NO;
  _modeSelectedIndicator.backgroundColor = [UIColor whiteColor];
  _modeSelectedIndicator.layer.cornerRadius = 14.0;
  [_modeSwitchTrack addSubview:_modeSelectedIndicator];

  _modePhotoBtn = [UIButton buttonWithType:UIButtonTypeCustom];
  _modePhotoBtn.translatesAutoresizingMaskIntoConstraints = NO;
  [_modePhotoBtn setTitle:@"Photo" forState:UIControlStateNormal];
  [_modePhotoBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
  _modePhotoBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
  [_modePhotoBtn addTarget:self action:@selector(onModePhotoTapped) forControlEvents:UIControlEventTouchUpInside];
  [_modeSwitchTrack addSubview:_modePhotoBtn];

  _modeVideoBtn = [UIButton buttonWithType:UIButtonTypeCustom];
  _modeVideoBtn.translatesAutoresizingMaskIntoConstraints = NO;
  [_modeVideoBtn setTitle:@"Video" forState:UIControlStateNormal];
  [_modeVideoBtn setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.65] forState:UIControlStateNormal];
  _modeVideoBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
  [_modeVideoBtn addTarget:self action:@selector(onModeVideoTapped) forControlEvents:UIControlEventTouchUpInside];
  [_modeSwitchTrack addSubview:_modeVideoBtn];

  // 2. Shutter Row
  _shutterRow = [[UIView alloc] init];
  _shutterRow.translatesAutoresizingMaskIntoConstraints = NO;
  [_bottomPanelContainer addSubview:_shutterRow];

  // Album button (Left) -> Tapping opens album and pushes ImageFilterController
  _albumButton = [UIButton buttonWithType:UIButtonTypeCustom];
  _albumButton.translatesAutoresizingMaskIntoConstraints = NO;
  _albumButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
  _albumButton.layer.cornerRadius = 12.0;
  _albumButton.layer.borderWidth = 2.0;
  _albumButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
  _albumButton.layer.masksToBounds = YES;
  _albumButton.imageView.contentMode = UIViewContentModeScaleAspectFill;
  UIImage* defaultAlbumIcon = [UIImage systemImageNamed:@"photo.on.rectangle.angled"];
  [_albumButton setImage:defaultAlbumIcon forState:UIControlStateNormal];
  _albumButton.tintColor = [UIColor whiteColor];
  [_albumButton addTarget:self action:@selector(onAlbumButtonTapped) forControlEvents:UIControlEventTouchUpInside];
  [_shutterRow addSubview:_albumButton];

  // Capture Shutter Button (Center)
  _shutterButton = [UIButton buttonWithType:UIButtonTypeCustom];
  _shutterButton.translatesAutoresizingMaskIntoConstraints = NO;
  _shutterButton.layer.cornerRadius = 37.0;
  _shutterButton.layer.borderWidth = 4.0;
  _shutterButton.layer.borderColor = [UIColor colorWithRed:1.0 green:0.325 blue:0.463 alpha:1.0].CGColor; // #FF5376
  _shutterButton.backgroundColor = [UIColor clearColor];
  [_shutterButton addTarget:self action:@selector(onShutterTapped) forControlEvents:UIControlEventTouchUpInside];
  [_shutterRow addSubview:_shutterButton];

  _shutterInnerCircle = [[UIView alloc] init];
  _shutterInnerCircle.translatesAutoresizingMaskIntoConstraints = NO;
  _shutterInnerCircle.backgroundColor = [UIColor whiteColor];
  _shutterInnerCircle.layer.cornerRadius = 29.0;
  _shutterInnerCircle.userInteractionEnabled = NO;
  [_shutterButton addSubview:_shutterInnerCircle];

  // Beauty Wand Satellite Button (Next to shutter)
  _beautyWandSatellite = [[UIView alloc] init];
  _beautyWandSatellite.translatesAutoresizingMaskIntoConstraints = NO;
  [_shutterRow addSubview:_beautyWandSatellite];

  _beautyWandButton = [UIButton buttonWithType:UIButtonTypeCustom];
  _beautyWandButton.translatesAutoresizingMaskIntoConstraints = NO;
  _beautyWandButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.2];
  _beautyWandButton.layer.cornerRadius = 19.0;
  _beautyWandButton.layer.masksToBounds = YES;
  UIImage* wandIcon = [UIImage imageNamed:@"ic_beauty_wand"];
  if (!wandIcon) wandIcon = [UIImage systemImageNamed:@"wand.and.stars"];
  [_beautyWandButton setImage:wandIcon forState:UIControlStateNormal];
  _beautyWandButton.tintColor = [UIColor whiteColor];
  [_beautyWandButton addTarget:self action:@selector(onToggleBeautyPanel) forControlEvents:UIControlEventTouchUpInside];
  [_beautyWandSatellite addSubview:_beautyWandButton];

  _beautyBadgeDot = [[UIView alloc] init];
  _beautyBadgeDot.translatesAutoresizingMaskIntoConstraints = NO;
  _beautyBadgeDot.backgroundColor = [UIColor colorWithRed:1.0 green:0.325 blue:0.463 alpha:1.0];
  _beautyBadgeDot.layer.cornerRadius = 3.5;
  _beautyBadgeDot.layer.masksToBounds = YES;
  [_beautyWandSatellite addSubview:_beautyBadgeDot];

  // Flip Camera Button (Right)
  _flipCameraButton = [UIButton buttonWithType:UIButtonTypeCustom];
  _flipCameraButton.translatesAutoresizingMaskIntoConstraints = NO;
  _flipCameraButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
  _flipCameraButton.layer.cornerRadius = 23.0;
  _flipCameraButton.layer.masksToBounds = YES;
  UIImage* flipIcon = [UIImage imageNamed:@"ic_switch_camera"];
  if (!flipIcon && @available(iOS 13.0, *)) {
    flipIcon = [UIImage systemImageNamed:@"camera.rotate.fill"];
  }
  [_flipCameraButton setImage:flipIcon forState:UIControlStateNormal];
  _flipCameraButton.tintColor = [UIColor whiteColor];
  [_flipCameraButton addTarget:self action:@selector(onSwitchCameraTapped) forControlEvents:UIControlEventTouchUpInside];
  [_shutterRow addSubview:_flipCameraButton];

  // 3. Bottom Navigation Bar: Memories | Camera | Chats
  _bottomNav = [[UIView alloc] init];
  _bottomNav.translatesAutoresizingMaskIntoConstraints = NO;
  [_bottomPanelContainer addSubview:_bottomNav];

  UIStackView* navStack = [[UIStackView alloc] init];
  navStack.translatesAutoresizingMaskIntoConstraints = NO;
  navStack.axis = UILayoutConstraintAxisHorizontal;
  navStack.distribution = UIStackViewDistributionFillEqually;
  navStack.alignment = UIStackViewAlignmentCenter;
  [_bottomNav addSubview:navStack];

  // Tab 1: Memories
  _navMemoriesBtn = [UIButton buttonWithType:UIButtonTypeCustom];
  _navMemoriesBtn.translatesAutoresizingMaskIntoConstraints = NO;
  [_navMemoriesBtn setTitle:@"Memories" forState:UIControlStateNormal];
  [_navMemoriesBtn setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.6] forState:UIControlStateNormal];
  _navMemoriesBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  [_navMemoriesBtn addTarget:self action:@selector(onNavMemoriesTapped) forControlEvents:UIControlEventTouchUpInside];
  [navStack addArrangedSubview:_navMemoriesBtn];

  // Tab 2: Camera (Active)
  _navCameraContainer = [[UIView alloc] init];
  _navCameraContainer.translatesAutoresizingMaskIntoConstraints = NO;

  _navCameraLabel = [[UILabel alloc] init];
  _navCameraLabel.translatesAutoresizingMaskIntoConstraints = NO;
  _navCameraLabel.text = @"Camera";
  _navCameraLabel.textColor = [UIColor colorWithRed:1.0 green:0.325 blue:0.463 alpha:1.0];
  _navCameraLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
  _navCameraLabel.textAlignment = NSTextAlignmentCenter;
  [_navCameraContainer addSubview:_navCameraLabel];

  _navCameraIndicator = [[UIView alloc] init];
  _navCameraIndicator.translatesAutoresizingMaskIntoConstraints = NO;
  _navCameraIndicator.backgroundColor = [UIColor colorWithRed:1.0 green:0.325 blue:0.463 alpha:1.0];
  _navCameraIndicator.layer.cornerRadius = 1.25;
  _navCameraIndicator.layer.masksToBounds = YES;
  [_navCameraContainer addSubview:_navCameraIndicator];

  _navCameraBtn = [UIButton buttonWithType:UIButtonTypeCustom];
  _navCameraBtn.translatesAutoresizingMaskIntoConstraints = NO;
  [_navCameraBtn addTarget:self action:@selector(onNavCameraTapped) forControlEvents:UIControlEventTouchUpInside];
  [_navCameraContainer addSubview:_navCameraBtn];

  [navStack addArrangedSubview:_navCameraContainer];

  // Tab 3: Chats
  _navChatsBtn = [UIButton buttonWithType:UIButtonTypeCustom];
  _navChatsBtn.translatesAutoresizingMaskIntoConstraints = NO;
  [_navChatsBtn setTitle:@"Chats" forState:UIControlStateNormal];
  [_navChatsBtn setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.6] forState:UIControlStateNormal];
  _navChatsBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  [_navChatsBtn addTarget:self action:@selector(onNavChatsTapped) forControlEvents:UIControlEventTouchUpInside];
  [navStack addArrangedSubview:_navChatsBtn];

  [NSLayoutConstraint activateConstraints:@[
    // Bottom Panel Container
    [_bottomPanelContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_bottomPanelContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [_bottomPanelContainer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

    // Mode Switch Track
    [_modeSwitchTrack.topAnchor constraintEqualToAnchor:_bottomPanelContainer.topAnchor constant:10],
    [_modeSwitchTrack.centerXAnchor constraintEqualToAnchor:_bottomPanelContainer.centerXAnchor],
    [_modeSwitchTrack.widthAnchor constraintEqualToConstant:144],
    [_modeSwitchTrack.heightAnchor constraintEqualToConstant:32],

    [_modeSelectedIndicator.leadingAnchor constraintEqualToAnchor:_modeSwitchTrack.leadingAnchor constant:2],
    [_modeSelectedIndicator.topAnchor constraintEqualToAnchor:_modeSwitchTrack.topAnchor constant:2],
    [_modeSelectedIndicator.bottomAnchor constraintEqualToAnchor:_modeSwitchTrack.bottomAnchor constant:-2],
    [_modeSelectedIndicator.widthAnchor constraintEqualToConstant:70],

    [_modePhotoBtn.leadingAnchor constraintEqualToAnchor:_modeSwitchTrack.leadingAnchor],
    [_modePhotoBtn.topAnchor constraintEqualToAnchor:_modeSwitchTrack.topAnchor],
    [_modePhotoBtn.bottomAnchor constraintEqualToAnchor:_modeSwitchTrack.bottomAnchor],
    [_modePhotoBtn.widthAnchor constraintEqualToConstant:72],

    [_modeVideoBtn.trailingAnchor constraintEqualToAnchor:_modeSwitchTrack.trailingAnchor],
    [_modeVideoBtn.topAnchor constraintEqualToAnchor:_modeSwitchTrack.topAnchor],
    [_modeVideoBtn.bottomAnchor constraintEqualToAnchor:_modeSwitchTrack.bottomAnchor],
    [_modeVideoBtn.widthAnchor constraintEqualToConstant:72],

    // Shutter Row
    [_shutterRow.topAnchor constraintEqualToAnchor:_modeSwitchTrack.bottomAnchor constant:8],
    [_shutterRow.leadingAnchor constraintEqualToAnchor:_bottomPanelContainer.leadingAnchor constant:20],
    [_shutterRow.trailingAnchor constraintEqualToAnchor:_bottomPanelContainer.trailingAnchor constant:-20],
    [_shutterRow.heightAnchor constraintEqualToConstant:84],

    [_albumButton.leadingAnchor constraintEqualToAnchor:_shutterRow.leadingAnchor],
    [_albumButton.centerYAnchor constraintEqualToAnchor:_shutterRow.centerYAnchor],
    [_albumButton.widthAnchor constraintEqualToConstant:46],
    [_albumButton.heightAnchor constraintEqualToConstant:46],

    [_shutterButton.centerXAnchor constraintEqualToAnchor:_shutterRow.centerXAnchor],
    [_shutterButton.centerYAnchor constraintEqualToAnchor:_shutterRow.centerYAnchor],
    [_shutterButton.widthAnchor constraintEqualToConstant:74],
    [_shutterButton.heightAnchor constraintEqualToConstant:74],

    [_shutterInnerCircle.centerXAnchor constraintEqualToAnchor:_shutterButton.centerXAnchor],
    [_shutterInnerCircle.centerYAnchor constraintEqualToAnchor:_shutterButton.centerYAnchor],
    [_shutterInnerCircle.widthAnchor constraintEqualToConstant:58],
    [_shutterInnerCircle.heightAnchor constraintEqualToConstant:58],

    [_beautyWandSatellite.leadingAnchor constraintEqualToAnchor:_shutterButton.trailingAnchor constant:6],
    [_beautyWandSatellite.topAnchor constraintEqualToAnchor:_shutterButton.topAnchor constant:4],
    [_beautyWandSatellite.widthAnchor constraintEqualToConstant:38],
    [_beautyWandSatellite.heightAnchor constraintEqualToConstant:38],

    [_beautyWandButton.centerXAnchor constraintEqualToAnchor:_beautyWandSatellite.centerXAnchor],
    [_beautyWandButton.centerYAnchor constraintEqualToAnchor:_beautyWandSatellite.centerYAnchor],
    [_beautyWandButton.widthAnchor constraintEqualToConstant:36],
    [_beautyWandButton.heightAnchor constraintEqualToConstant:36],

    [_beautyBadgeDot.topAnchor constraintEqualToAnchor:_beautyWandSatellite.topAnchor constant:1],
    [_beautyBadgeDot.trailingAnchor constraintEqualToAnchor:_beautyWandSatellite.trailingAnchor constant:-1],
    [_beautyBadgeDot.widthAnchor constraintEqualToConstant:7],
    [_beautyBadgeDot.heightAnchor constraintEqualToConstant:7],

    [_flipCameraButton.trailingAnchor constraintEqualToAnchor:_shutterRow.trailingAnchor],
    [_flipCameraButton.centerYAnchor constraintEqualToAnchor:_shutterRow.centerYAnchor],
    [_flipCameraButton.widthAnchor constraintEqualToConstant:46],
    [_flipCameraButton.heightAnchor constraintEqualToConstant:46],

    // Bottom Navigation Bar
    [_bottomNav.topAnchor constraintEqualToAnchor:_shutterRow.bottomAnchor constant:10],
    [_bottomNav.leadingAnchor constraintEqualToAnchor:_bottomPanelContainer.leadingAnchor constant:16],
    [_bottomNav.trailingAnchor constraintEqualToAnchor:_bottomPanelContainer.trailingAnchor constant:-16],
    [_bottomNav.heightAnchor constraintEqualToConstant:34],
    [_bottomNav.bottomAnchor constraintEqualToAnchor:_bottomPanelContainer.safeAreaLayoutGuide.bottomAnchor constant:-8],

    [navStack.topAnchor constraintEqualToAnchor:_bottomNav.topAnchor],
    [navStack.bottomAnchor constraintEqualToAnchor:_bottomNav.bottomAnchor],
    [navStack.leadingAnchor constraintEqualToAnchor:_bottomNav.leadingAnchor],
    [navStack.trailingAnchor constraintEqualToAnchor:_bottomNav.trailingAnchor],

    [_navMemoriesBtn.heightAnchor constraintEqualToConstant:34],
    [_navChatsBtn.heightAnchor constraintEqualToConstant:34],

    [_navCameraContainer.heightAnchor constraintEqualToConstant:34],
    [_navCameraLabel.centerXAnchor constraintEqualToAnchor:_navCameraContainer.centerXAnchor],
    [_navCameraLabel.centerYAnchor constraintEqualToAnchor:_navCameraContainer.centerYAnchor constant:-4],

    [_navCameraIndicator.topAnchor constraintEqualToAnchor:_navCameraLabel.bottomAnchor constant:3],
    [_navCameraIndicator.centerXAnchor constraintEqualToAnchor:_navCameraContainer.centerXAnchor],
    [_navCameraIndicator.widthAnchor constraintEqualToConstant:16],
    [_navCameraIndicator.heightAnchor constraintEqualToConstant:2.5],

    [_navCameraBtn.topAnchor constraintEqualToAnchor:_navCameraContainer.topAnchor],
    [_navCameraBtn.bottomAnchor constraintEqualToAnchor:_navCameraContainer.bottomAnchor],
    [_navCameraBtn.leadingAnchor constraintEqualToAnchor:_navCameraContainer.leadingAnchor],
    [_navCameraBtn.trailingAnchor constraintEqualToAnchor:_navCameraContainer.trailingAnchor],
  ]];
}

- (void)setupBeautyPanel {
  _filterToolbarView = [[FilterToolbarView alloc] initWithFrame:CGRectZero];
  _filterToolbarView.translatesAutoresizingMaskIntoConstraints = NO;
  _filterToolbarView.delegate = self;
  _filterToolbarView.hidden = YES;
  _filterToolbarView.alpha = 0.0;
  [self.view addSubview:_filterToolbarView];

  [NSLayoutConstraint activateConstraints:@[
    [_filterToolbarView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_filterToolbarView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [_filterToolbarView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
  ]];
}

- (void)applyInitialFilterParameters {
  for (BeautyOption* opt in self.filterToolbarView.allOptions) {
    if (opt.category <= BeautyCategoryMakeup) {
      [self applyOptionParam:opt];
    }
  }
}

#pragma mark - Mode Switch

- (void)onModePhotoTapped {
  self.isVideoMode = NO;
  [self updateModeSwitchVisual];
}

- (void)onModeVideoTapped {
  self.isVideoMode = YES;
  [self updateModeSwitchVisual];
}

- (void)updateModeSwitchVisual {
  [UIView animateWithDuration:0.25 animations:^{
    if (self.isVideoMode) {
      self.modeSelectedIndicator.transform = CGAffineTransformMakeTranslation(70, 0);
      [self.modePhotoBtn setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.65] forState:UIControlStateNormal];
      self.modePhotoBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];

      [self.modeVideoBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
      self.modeVideoBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];

      self.shutterInnerCircle.backgroundColor = [UIColor colorWithRed:1.0 green:0.25 blue:0.25 alpha:1.0];
    } else {
      self.modeSelectedIndicator.transform = CGAffineTransformIdentity;
      [self.modePhotoBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
      self.modePhotoBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];

      [self.modeVideoBtn setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.65] forState:UIControlStateNormal];
      self.modeVideoBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];

      self.shutterInnerCircle.backgroundColor = [UIColor whiteColor];
    }
  }];
}

#pragma mark - Actions

- (void)onSwitchCameraTapped {
  [self.videoCapturer reverseCamera];
  [self updateFlashButtonState];
}

- (void)onFlashTapped {
  [self.videoCapturer toggleTorch];
  [self updateFlashButtonState];
}

- (void)updateFlashButtonState {
  BOOL isOn = [self.videoCapturer isTorchOn];
  UIImage* icon = isOn ? [UIImage imageNamed:@"ic_flash_on"] : [UIImage imageNamed:@"ic_flash_off"];
  if (!icon) icon = isOn ? [UIImage systemImageNamed:@"bolt.fill"] : [UIImage systemImageNamed:@"bolt.slash.fill"];
  [_flashButton setImage:icon forState:UIControlStateNormal];
}

- (void)onResetTapped {
  [self.filterToolbarView resetAllToDefaults];
  for (BeautyOption* opt in self.filterToolbarView.allOptions) {
    if (opt.category <= BeautyCategoryMakeup) {
      [self applyOptionParam:opt];
    }
  }
  [self applyFilterPreset:BeautyOptionFilterOrigin];
  [self applyStickerPreset:BeautyOptionStickerNone];

  [self showToast:@"已重置所有滤镜效果"];
}

- (void)onToggleBeautyPanel {
  if (!self.isPanelCollapsed) {
    [self collapseBeautyPanel];
    return;
  }
  self.isPanelCollapsed = NO;
  self.filterToolbarView.hidden = NO;
  [UIView animateWithDuration:0.25 animations:^{
    self.bottomPanelContainer.alpha = 0.0;
    self.filterToolbarView.alpha = 1.0;
  } completion:^(BOOL finished) {
    self.bottomPanelContainer.hidden = YES;
  }];
}

- (void)collapseBeautyPanel {
  if (self.isPanelCollapsed) return;
  self.isPanelCollapsed = YES;
  self.bottomPanelContainer.hidden = NO;
  [UIView animateWithDuration:0.25 animations:^{
    self.bottomPanelContainer.alpha = 1.0;
    self.filterToolbarView.alpha = 0.0;
  } completion:^(BOOL finished) {
    self.filterToolbarView.hidden = YES;
  }];
}

- (void)beautyToolbarViewDidRequestDismiss:(FilterToolbarView*)toolbarView {
  [self collapseBeautyPanel];
}

#pragma mark - Bottom Nav Actions

- (void)onNavMemoriesTapped {
  [self onAlbumButtonTapped];
}

- (void)onNavCameraTapped {
  if (!self.isPanelCollapsed) {
    [self collapseBeautyPanel];
  }
}

- (void)onNavChatsTapped {
  [self showToast:@"Chats 功能开发中"];
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)gestureRecognizer shouldReceiveTouch:(UITouch*)touch {
  if (self.isPanelCollapsed) return NO;
  CGPoint loc = [touch locationInView:self.view];
  if (CGRectContainsPoint(self.filterToolbarView.frame, loc)) {
    return NO;
  }
  if (CGRectContainsPoint(self.topBarView.frame, loc) ||
      CGRectContainsPoint(self.compareButton.frame, loc)) {
    return NO;
  }
  return YES;
}

- (void)handleOutsideTap:(UITapGestureRecognizer*)gesture {
  if (!self.isPanelCollapsed && gesture.state == UIGestureRecognizerStateEnded) {
    [self collapseBeautyPanel];
  }
}

- (void)onCompareTouchDown {
  self.isComparing = YES;
  [self applyBypass:YES];
}

- (void)onCompareTouchUp {
  self.isComparing = NO;
  [self applyBypass:NO];
}

- (void)applyBypass:(BOOL)bypass {
  if (bypass) {
    if (_beautyFaceFilter) {
      _beautyFaceFilter->SetBlurAlpha(0);
      _beautyFaceFilter->SetWhite(0);
      _beautyFaceFilter->SetSharpen(0);
    }
    if (_faceReshapeFilter) {
      _faceReshapeFilter->SetFaceSlimLevel(0);
      _faceReshapeFilter->SetEyeZoomLevel(0);
    }
    if (_lipstickFilter) _lipstickFilter->SetBlendLevel(0);
    if (_blusherFilter) _blusherFilter->SetBlendLevel(0);
    if (_whiteBalanceFilter) {
      _whiteBalanceFilter->setTemperature(5000.0f);
      _whiteBalanceFilter->setTint(0.0f);
    }
    if (_saturationFilter) _saturationFilter->setSaturation(1.0f);
    if (_faceStickerFilter) _faceStickerFilter->ClearStickers();
  } else {
    for (BeautyOption* opt in self.filterToolbarView.allOptions) {
      if (opt.category <= BeautyCategoryMakeup) {
        [self applyOptionParam:opt];
      }
    }
    if (self.filterToolbarView.selectedOption) {
      if (self.filterToolbarView.selectedOption.category == BeautyCategoryFilter) {
        [self applyFilterPreset:self.filterToolbarView.selectedOption.optionId];
      } else if (self.filterToolbarView.selectedOption.category == BeautyCategorySticker) {
        [self applyStickerPreset:self.filterToolbarView.selectedOption.optionId];
      }
    }
  }
}

#pragma mark - Photo & Album Handling

- (void)onAlbumButtonTapped {
  if (@available(iOS 14.0, *)) {
    PHPickerConfiguration* config = [[PHPickerConfiguration alloc] init];
    config.selectionLimit = 1;
    config.filter = [PHPickerFilter imagesFilter];

    PHPickerViewController* picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
  } else {
    UIImagePickerController* picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
  }
}

- (void)picker:(PHPickerViewController*)picker didFinishPicking:(NSArray<PHPickerResult*>*)results API_AVAILABLE(ios(14.0)) {
  [picker dismissViewControllerAnimated:YES completion:nil];

  if (results.count == 0) return;

  PHPickerResult* result = results.firstObject;
  NSItemProvider* provider = result.itemProvider;

  if ([provider canLoadObjectOfClass:[UIImage class]]) {
    [provider loadObjectOfClass:[UIImage class] completionHandler:^(__kindof id<NSItemProviderReading> _Nullable object, NSError* _Nullable error) {
      if ([object isKindOfClass:[UIImage class]]) {
        UIImage* image = (UIImage*)object;
        dispatch_async(dispatch_get_main_queue(), ^{
          [self openPhotoRetouchWithImage:image];
        });
      }
    }];
  }
}

- (void)imagePickerController:(UIImagePickerController*)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id>*)info {
  [picker dismissViewControllerAnimated:YES completion:nil];
  UIImage* image = info[UIImagePickerControllerOriginalImage];
  if (image) {
    [self openPhotoRetouchWithImage:image];
  }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController*)picker {
  [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)openPhotoRetouchWithImage:(UIImage*)image {
  ImageFilterController* retouchVC = [[ImageFilterController alloc] initWithImage:image];
  [self.navigationController pushViewController:retouchVC animated:YES];
}

- (void)onShutterTapped {
  if (self.isVideoMode) {
    [self showToast:@"录像模式功能体验中"];
    return;
  }

  // Photo Capture
  self.isCapturingPhoto = YES;

  // Trigger white flash animation
  UIView* flashView = [[UIView alloc] initWithFrame:self.view.bounds];
  flashView.backgroundColor = [UIColor whiteColor];
  flashView.alpha = 0.85;
  [self.view addSubview:flashView];
  [UIView animateWithDuration:0.25 animations:^{
    flashView.alpha = 0.0;
  } completion:^(BOOL finished) {
    [flashView removeFromSuperview];
  }];
}

- (void)loadLatestAlbumThumbnail {
  [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
    if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
      PHFetchOptions* options = [[PHFetchOptions alloc] init];
      options.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO] ];
      options.fetchLimit = 1;
      PHFetchResult<PHAsset*>* assets = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:options];
      if (assets.count > 0) {
        PHAsset* latestAsset = assets.firstObject;
        PHImageRequestOptions* reqOpts = [[PHImageRequestOptions alloc] init];
        reqOpts.resizeMode = PHImageRequestOptionsResizeModeFast;
        reqOpts.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;

        [[PHImageManager defaultManager] requestImageForAsset:latestAsset
                                                   targetSize:CGSizeMake(100, 100)
                                                  contentMode:PHImageContentModeAspectFill
                                                      options:reqOpts
                                                resultHandler:^(UIImage* _Nullable result, NSDictionary* _Nullable info) {
          if (result) {
            dispatch_async(dispatch_get_main_queue(), ^{
              [self.albumButton setImage:result forState:UIControlStateNormal];
            });
          }
        }];
      }
    }
  }];
}

- (void)showToast:(NSString*)message {
  UILabel* toast = [[UILabel alloc] init];
  toast.translatesAutoresizingMaskIntoConstraints = NO;
  toast.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];
  toast.textColor = [UIColor whiteColor];
  toast.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  toast.textAlignment = NSTextAlignmentCenter;
  toast.layer.cornerRadius = 16.0;
  toast.layer.masksToBounds = YES;
  toast.text = [NSString stringWithFormat:@"  %@  ", message];
  [self.view addSubview:toast];

  [NSLayoutConstraint activateConstraints:@[
    [toast.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [toast.bottomAnchor constraintEqualToAnchor:_bottomPanelContainer.topAnchor constant:-24],
    [toast.heightAnchor constraintEqualToConstant:32],
  ]];

  [UIView animateWithDuration:0.3 delay:1.8 options:0 animations:^{
    toast.alpha = 0.0;
  } completion:^(BOOL finished) {
    [toast removeFromSuperview];
  }];
}

#pragma mark - Filter Parameter Mapping

- (void)applyOptionParam:(BeautyOption*)option {
  if (self.isComparing) return;
  float ratio = option.progress / 100.0f;

  switch (option.optionId) {
    case BeautyOptionSmooth:
      if (_beautyFaceFilter) _beautyFaceFilter->SetBlurAlpha(ratio / 10.0f);
      break;
    case BeautyOptionWhite:
      if (_beautyFaceFilter) _beautyFaceFilter->SetWhite(ratio / 20.0f);
      break;
    case BeautyOptionSharpen:
      if (_beautyFaceFilter) _beautyFaceFilter->SetSharpen(ratio / 5.0f);
      break;
    case BeautyOptionThinFace:
      if (_faceReshapeFilter) _faceReshapeFilter->SetFaceSlimLevel(ratio * 0.08f);
      break;
    case BeautyOptionBigEye:
      if (_faceReshapeFilter) _faceReshapeFilter->SetEyeZoomLevel(ratio * 0.35f);
      break;
    case BeautyOptionLipstick:
      if (_lipstickFilter) _lipstickFilter->SetBlendLevel(ratio * 0.8f);
      break;
    case BeautyOptionBlusher:
      if (_blusherFilter) _blusherFilter->SetBlendLevel(ratio * 0.7f);
      break;
    default:
      break;
  }
}

- (void)applyFilterPreset:(BeautyOptionId)filterId {
  if (!_whiteBalanceFilter || !_saturationFilter || self.isComparing) return;

  switch (filterId) {
    case BeautyOptionFilterOrigin:
      _whiteBalanceFilter->setTemperature(5000.0f);
      _whiteBalanceFilter->setTint(0.0f);
      _saturationFilter->setSaturation(1.0f);
      break;
    case BeautyOptionFilterPink:
      _whiteBalanceFilter->setTemperature(5350.0f);
      _whiteBalanceFilter->setTint(6.0f);
      _saturationFilter->setSaturation(1.15f);
      break;
    case BeautyOptionFilterCool:
      _whiteBalanceFilter->setTemperature(4550.0f);
      _whiteBalanceFilter->setTint(-4.0f);
      _saturationFilter->setSaturation(0.95f);
      break;
    case BeautyOptionFilterFilm:
      _whiteBalanceFilter->setTemperature(5600.0f);
      _whiteBalanceFilter->setTint(8.0f);
      _saturationFilter->setSaturation(1.18f);
      break;
    case BeautyOptionFilterBW:
      _whiteBalanceFilter->setTemperature(5000.0f);
      _whiteBalanceFilter->setTint(0.0f);
      _saturationFilter->setSaturation(0.0f);
      break;
    default:
      break;
  }
}

- (nullable NSString*)stickerPathForFilename:(NSString*)filename {
  NSBundle* frameworkBundle = [NSBundle bundleForClass:NSClassFromString(@"GPXObjcHelper")];
  if (!frameworkBundle) {
    frameworkBundle = [NSBundle bundleWithIdentifier:@"com.pixpark.gpupixel"];
  }
  if (!frameworkBundle) {
    NSString* fmwkPath = [[[NSBundle mainBundle] privateFrameworksPath] stringByAppendingPathComponent:@"gpupixel.framework"];
    frameworkBundle = [NSBundle bundleWithPath:fmwkPath];
  }

  if (frameworkBundle) {
    NSString* resDir = [frameworkBundle.resourcePath stringByAppendingPathComponent:@"res"];
    NSString* candidate = [resDir stringByAppendingPathComponent:filename];
    if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
      return candidate;
    }
    candidate = [frameworkBundle pathForResource:filename.stringByDeletingPathExtension ofType:filename.pathExtension inDirectory:@"res"];
    if (candidate) return candidate;
    candidate = [frameworkBundle pathForResource:filename.stringByDeletingPathExtension ofType:filename.pathExtension];
    if (candidate) return candidate;
  }

  NSString* mainCandidate = [[NSBundle mainBundle] pathForResource:filename.stringByDeletingPathExtension ofType:filename.pathExtension];
  if (mainCandidate) return mainCandidate;

  return nil;
}

- (void)applyStickerPreset:(BeautyOptionId)stickerId {
  if (!_faceStickerFilter) return;

  NSString* stickerFile = nil;
  StickerAnchor anchor = kAnchorForehead;
  float scale = 1.0f;
  float offsetX = 0.0f;
  float offsetY = 0.0f;

  switch (stickerId) {
    case BeautyOptionStickerNone:
      _faceStickerFilter->ClearStickers();
      return;
    case BeautyOptionStickerCatEars:
      stickerFile = @"cat_ears.png";
      anchor = kAnchorForehead;
      scale = 1.0f;
      break;
    case BeautyOptionStickerBunnyEars:
      stickerFile = @"bunny_ears.png";
      anchor = kAnchorForehead;
      scale = 1.15f;
      offsetY = 0.15f;
      break;
    case BeautyOptionStickerCrown:
      stickerFile = @"crown.png";
      anchor = kAnchorForehead;
      scale = 0.95f;
      offsetY = 0.05f;
      break;
    case BeautyOptionStickerAngelHalo:
      stickerFile = @"angel_halo.png";
      anchor = kAnchorForehead;
      scale = 1.05f;
      offsetY = 0.35f;
      break;
    case BeautyOptionStickerDevilHorns:
      stickerFile = @"devil_horns.png";
      anchor = kAnchorForehead;
      scale = 0.95f;
      break;
    case BeautyOptionStickerSunglasses:
      stickerFile = @"sunglasses.png";
      anchor = kAnchorEyes;
      scale = 1.0f;
      break;
    case BeautyOptionStickerHeartBlush:
      stickerFile = @"heart_blush.png";
      anchor = kAnchorCheekLeft;
      scale = 0.85f;
      break;
    case BeautyOptionStickerClownNose:
      stickerFile = @"clown_nose.png";
      anchor = kAnchorNose;
      scale = 0.75f;
      break;
    case BeautyOptionStickerMustache:
      stickerFile = @"mustache.png";
      anchor = kAnchorMouth;
      scale = 0.9f;
      offsetY = 0.1f;
      break;
    case BeautyOptionStickerFlowerHairpin:
      stickerFile = @"flower_hairpin.png";
      anchor = kAnchorForehead;
      scale = 0.85f;
      offsetX = 0.35f;
      offsetY = 0.15f;
      break;
    default:
      break;
  }

  if (stickerFile) {
    NSString* fullPath = [self stickerPathForFilename:stickerFile];
    if (fullPath) {
      _faceStickerFilter->SetStickerPath([fullPath UTF8String]);
      _faceStickerFilter->SetAnchor(anchor);
      _faceStickerFilter->SetScale(scale);
      _faceStickerFilter->SetOffset(offsetX, offsetY);
      _faceStickerFilter->SetAlpha(1.0f);
    }
  }
}

- (void)applyAnimStickerPreset:(BeautyOptionId)animId {
  if (!_faceStickerFilter) return;

  if (animId == BeautyOptionAnimNone) {
    _faceStickerFilter->ClearStickers();
    return;
  }

  NSString* folderName = nil;
  int fps = 12;
  StickerAnchor anchor = kAnchorForehead;
  float scale = 1.0f;
  float offsetX = 0.0f;
  float offsetY = 0.0f;

  switch (animId) {
    case BeautyOptionAnimHearts:
      folderName = @"anim_hearts";
      fps = 12;
      anchor = kAnchorEyes;
      scale = 1.15f;
      offsetX = 0.0f;
      offsetY = -0.22f;
      break;
    case BeautyOptionAnimCatEars:
      folderName = @"anim_cat_ears";
      fps = 12;
      anchor = kAnchorForehead;
      scale = 1.0f;
      offsetX = 0.0f;
      offsetY = 0.0f;
      break;
    case BeautyOptionAnimCrown:
      folderName = @"anim_crown";
      fps = 12;
      anchor = kAnchorForehead;
      scale = 0.95f;
      offsetX = 0.0f;
      offsetY = 0.05f;
      break;
    case BeautyOptionAnimHalo:
      folderName = @"anim_halo";
      fps = 12;
      anchor = kAnchorForehead;
      scale = 1.05f;
      offsetX = 0.0f;
      offsetY = 0.35f;
      break;
    case BeautyOptionAnimDevil:
      folderName = @"anim_devil";
      fps = 12;
      anchor = kAnchorForehead;
      scale = 0.95f;
      offsetX = 0.0f;
      offsetY = 0.0f;
      break;
    case BeautyOptionAnimFireworks:
      folderName = @"anim_fireworks";
      fps = 10;
      anchor = kAnchorForehead;
      scale = 1.25f;
      offsetX = 0.0f;
      offsetY = 0.35f;
      break;
    case BeautyOptionAnimTears:
      folderName = @"anim_tears";
      fps = 12;
      anchor = kAnchorEyes;
      scale = 1.1f;
      offsetX = 0.0f;
      offsetY = -0.4f;
      break;
    case BeautyOptionAnimSteam:
      folderName = @"anim_steam";
      fps = 12;
      anchor = kAnchorForehead;
      scale = 1.2f;
      offsetX = 0.0f;
      offsetY = 0.1f;
      break;
    case BeautyOptionAnimCoins:
      folderName = @"anim_coins";
      fps = 12;
      anchor = kAnchorForehead;
      scale = 1.2f;
      offsetX = 0.0f;
      offsetY = 0.35f;
      break;
    case BeautyOptionAnimDizzy:
      folderName = @"anim_dizzy";
      fps = 12;
      anchor = kAnchorForehead;
      scale = 1.1f;
      offsetX = 0.0f;
      offsetY = 0.35f;
      break;
    default:
      _faceStickerFilter->ClearStickers();
      return;
  }

  if (folderName) {
    NSString* fullPath = [self stickerPathForFilename:folderName];
    if (fullPath) {
      _faceStickerFilter->SetStickerPath([fullPath UTF8String]);
      _faceStickerFilter->SetAnchor(anchor);
      _faceStickerFilter->SetScale(scale);
      _faceStickerFilter->SetOffset(offsetX, offsetY);
      _faceStickerFilter->SetAlpha(1.0f);
      _faceStickerFilter->SetProperty("fps", fps);
    }
  }
}

#pragma mark - FilterToolbarViewDelegate

- (void)beautyToolbarView:(FilterToolbarView*)toolbarView didSelectOption:(BeautyOption*)option {
  if (option.category == BeautyCategoryFilter) {
    [self applyFilterPreset:option.optionId];
  } else if (option.category == BeautyCategorySticker) {
    [self applyStickerPreset:option.optionId];
  } else if (option.category == BeautyCategoryAnimSticker) {
    [self applyAnimStickerPreset:option.optionId];
  } else {
    [self applyOptionParam:option];
  }
}

- (void)beautyToolbarView:(FilterToolbarView*)toolbarView
           didChangeValue:(NSInteger)value
                forOption:(BeautyOption*)option {
  if (option.category <= BeautyCategoryMakeup) {
    [self applyOptionParam:option];
  }
}

#pragma mark - VCVideoCapturerDelegate

- (void)videoCaptureOutputDataCallback:(CMSampleBufferRef)sampleBuffer {
  CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
  if (!imageBuffer) return;

  CVPixelBufferLockBaseAddress(imageBuffer, 0);
  auto width = CVPixelBufferGetWidth(imageBuffer);
  auto height = CVPixelBufferGetHeight(imageBuffer);
  auto stride = CVPixelBufferGetBytesPerRow(imageBuffer);
  auto pixels = (const uint8_t*)CVPixelBufferGetBaseAddress(imageBuffer);

  // Face Detection
  std::vector<float> landmarks;
  if (_faceDetector && pixels) {
    landmarks = _faceDetector->Detect(pixels, width, height, stride,
                                      GPUPIXEL_MODE_FMT_VIDEO, GPUPIXEL_FRAME_TYPE_BGRA);
  }

  BOOL hasFace = !landmarks.empty();
  if (hasFace) {
    _latestLandmarks = landmarks;
    if (_lipstickFilter) _lipstickFilter->SetFaceLandmarks(landmarks);
    if (_blusherFilter) _blusherFilter->SetFaceLandmarks(landmarks);
    if (_faceReshapeFilter) _faceReshapeFilter->SetFaceLandmarks(landmarks);
    if (_faceStickerFilter) _faceStickerFilter->SetFaceLandmarks(landmarks);
  }

  if (_sourceRawData && pixels) {
    _sourceRawData->ProcessData(pixels, width, height, stride, GPUPIXEL_FRAME_TYPE_BGRA);
  }

  // Handle Photo Capture
  if (self.isCapturingPhoto && _sinkRawData) {
    self.isCapturingPhoto = NO;
    const uint8_t* outputPixels = _sinkRawData->GetRgbaBuffer();
    int outW = _sinkRawData->GetWidth();
    int outH = _sinkRawData->GetHeight();

    if (outputPixels && outW > 0 && outH > 0) {
      UIImage* capturedImage = [ImageConverter imageFromRGBAData:outputPixels width:outW height:outH];
      if (capturedImage) {
        UIImageWriteToSavedPhotosAlbum(capturedImage, self, @selector(photoSaved:didFinishSavingWithError:contextInfo:), NULL);
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.albumButton setImage:capturedImage forState:UIControlStateNormal];
        });
      }
    }
  }

  CVPixelBufferUnlockBaseAddress(imageBuffer, 0);

  // Update Face status badge on main thread
  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateFaceStatusBadge:hasFace];
  });
}

- (void)photoSaved:(UIImage*)image didFinishSavingWithError:(NSError*)error contextInfo:(void*)contextInfo {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (error) {
      [self showToast:[NSString stringWithFormat:@"保存失败: %@", error.localizedDescription]];
    } else {
      [self showToast:@"照片已保存到相册！"];
    }
  });
}

- (void)updateFaceStatusBadge:(BOOL)hasFace {
  if (hasFace != self.hasFaceDetected) {
    self.hasFaceDetected = hasFace;
    if (hasFace) {
      self.faceStatusBadge.text = @"已检测到人脸";
      self.faceStatusBadge.textColor = [UIColor colorWithRed:0.25 green:0.85 blue:0.45 alpha:1.0];
    } else {
      self.faceStatusBadge.text = @"人脸检测中...";
      self.faceStatusBadge.textColor = [UIColor colorWithWhite:1.0 alpha:0.75];
    }
  }
}

@end
