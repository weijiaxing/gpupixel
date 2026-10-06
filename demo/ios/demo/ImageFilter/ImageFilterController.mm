/*
 * GPUPixelDemo
 *
 * Created by PixPark on 2021/6/24.
 * Copyright © 2021 PixPark. All rights reserved.
 */

#import "ImageFilterController.h"
#import <Photos/Photos.h>
#import "FilterToolbarView.h"
#import "ImageConverter.h"

#import <gpupixel/gpupixel.h>

using namespace gpupixel;

@interface ImageFilterController () <FilterToolbarViewDelegate> {
  std::shared_ptr<SinkView> _gpuPixelView;
  std::shared_ptr<BeautyFaceFilter> _beautyFaceFilter;
  std::shared_ptr<FaceReshapeFilter> _faceReshapeFilter;
  std::shared_ptr<LipstickFilter> _lipstickFilter;
  std::shared_ptr<BlusherFilter> _blusherFilter;
  std::shared_ptr<WhiteBalanceFilter> _whiteBalanceFilter;
  std::shared_ptr<SaturationFilter> _saturationFilter;
  std::shared_ptr<FaceStickerFilter> _faceStickerFilter;
  std::shared_ptr<SourceImage> _gpuSourceImage;
  std::shared_ptr<FaceDetector> _faceDetector;
  std::shared_ptr<SinkRawData> _sinkRawData;

  std::vector<float> _faceLandmarks;
}

@property(nonatomic, strong) UIImage* inputImage;
@property(nonatomic, strong) UIView* renderView;
@property(nonatomic, strong) FilterToolbarView* filterToolbarView;

// Top bar
@property(nonatomic, strong) UIView* topBarView;
@property(nonatomic, strong) UIButton* backButton;
@property(nonatomic, strong) UILabel* titleLabel;
@property(nonatomic, strong) UIButton* saveButton;

// Floating controls
@property(nonatomic, strong) UIButton* compareButton;
@property(nonatomic, strong) UIButton* resetButton;

@property(nonatomic, assign) BOOL isComparing;

@end

@implementation ImageFilterController

- (instancetype)initWithImage:(nullable UIImage*)image {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    if (image) {
      _inputImage = [self normalizeOrientation:image];
    }
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor blackColor];
  self.navigationController.navigationBarHidden = YES;
  [[UIApplication sharedApplication] setIdleTimerDisabled:YES];

  if (!_inputImage) {
    NSString* imagePath = [[NSBundle mainBundle] pathForResource:@"sample_face" ofType:@"png"];
    if (imagePath) {
      _inputImage = [UIImage imageWithContentsOfFile:imagePath];
    }
  }

  [self setupFilterPipeline];
  [self setupUI];
  [self renderInitialImage];
}

- (void)viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
}

- (void)dealloc {
  [self destroyGPUPixel];
}

- (void)destroyGPUPixel {
  _beautyFaceFilter = nullptr;
  _faceReshapeFilter = nullptr;
  _lipstickFilter = nullptr;
  _blusherFilter = nullptr;
  _whiteBalanceFilter = nullptr;
  _saturationFilter = nullptr;
  _faceStickerFilter = nullptr;
  _gpuPixelView = nullptr;
  _gpuSourceImage = nullptr;
  _faceDetector = nullptr;
  _sinkRawData = nullptr;
}

#pragma mark - Filter Setup

- (void)setupFilterPipeline {
  _renderView = [[UIView alloc] initWithFrame:self.view.bounds];
  _renderView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:_renderView];

  _gpuPixelView = SinkView::Create((__bridge void*)_renderView);
  _lipstickFilter = LipstickFilter::Create();
  _blusherFilter = BlusherFilter::Create();
  _faceReshapeFilter = FaceReshapeFilter::Create();
  _beautyFaceFilter = BeautyFaceFilter::Create();
  _whiteBalanceFilter = WhiteBalanceFilter::Create();
  _saturationFilter = SaturationFilter::Create();
  _faceStickerFilter = FaceStickerFilter::Create();
  _faceDetector = FaceDetector::Create();
  _sinkRawData = SinkRawData::Create();

  // Create Source Image from UIImage RGBA
  int width = 0, height = 0;
  unsigned char* rgbaData = [self rgbaPixelsFromImage:_inputImage width:&width height:&height];
  if (rgbaData && width > 0 && height > 0) {
    _gpuSourceImage = SourceImage::CreateFromBuffer(width, height, 4, rgbaData);

    // Detect face landmarks
    _faceLandmarks = _faceDetector->Detect(rgbaData, width, height, width * 4,
                                           GPUPIXEL_MODE_FMT_PICTURE, GPUPIXEL_FRAME_TYPE_RGBA);
    free(rgbaData);

    if (!_faceLandmarks.empty()) {
      _lipstickFilter->SetFaceLandmarks(_faceLandmarks);
      _blusherFilter->SetFaceLandmarks(_faceLandmarks);
      _faceReshapeFilter->SetFaceLandmarks(_faceLandmarks);
      _faceStickerFilter->SetFaceLandmarks(_faceLandmarks);
    }
  }

  // Connect Filter chain safely without dynamic_cast cross-cast null pointer failures across framework boundary
  if (_gpuSourceImage) {
    std::shared_ptr<Source> currentSource = _gpuSourceImage;
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
  }
}

- (void)renderInitialImage {
  if (!_gpuSourceImage) return;

  // Apply default parameters from toolbar view
  for (BeautyOption* opt in self.filterToolbarView.allOptions) {
    if (opt.category <= BeautyCategoryMakeup) {
      [self applyOptionParam:opt];
    }
  }

  _gpuSourceImage->Render();
}

#pragma mark - UI Setup

- (void)setupUI {
  // 1. Top Bar
  _topBarView = [[UIView alloc] init];
  _topBarView.translatesAutoresizingMaskIntoConstraints = NO;
  _topBarView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
  [self.view addSubview:_topBarView];

  _backButton = [UIButton buttonWithType:UIButtonTypeCustom];
  _backButton.translatesAutoresizingMaskIntoConstraints = NO;
  [_backButton setTitle:@"取消" forState:UIControlStateNormal];
  [_backButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
  _backButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
  [_backButton addTarget:self action:@selector(onBackTapped) forControlEvents:UIControlEventTouchUpInside];
  [_topBarView addSubview:_backButton];

  _titleLabel = [[UILabel alloc] init];
  _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  _titleLabel.text = @"照片修图";
  _titleLabel.textColor = [UIColor whiteColor];
  _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
  _titleLabel.textAlignment = NSTextAlignmentCenter;
  [_topBarView addSubview:_titleLabel];

  _saveButton = [UIButton buttonWithType:UIButtonTypeCustom];
  _saveButton.translatesAutoresizingMaskIntoConstraints = NO;
  [_saveButton setTitle:@"保存" forState:UIControlStateNormal];
  [_saveButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
  _saveButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
  _saveButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.325 blue:0.463 alpha:1.0]; // #FF5376
  _saveButton.layer.cornerRadius = 15.0;
  _saveButton.layer.masksToBounds = YES;
  [_saveButton addTarget:self action:@selector(onSaveTapped) forControlEvents:UIControlEventTouchUpInside];
  [_topBarView addSubview:_saveButton];

  // 2. Floating Reset Button (Top Right under top bar)
  _resetButton = [UIButton buttonWithType:UIButtonTypeCustom];
  _resetButton.translatesAutoresizingMaskIntoConstraints = NO;
  _resetButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.40];
  _resetButton.layer.cornerRadius = 18.0;
  _resetButton.layer.borderWidth = 1.0;
  _resetButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.27].CGColor;
  _resetButton.layer.masksToBounds = YES;
  [_resetButton addTarget:self action:@selector(onResetTapped) forControlEvents:UIControlEventTouchUpInside];

  UIImageView* resetIconView = [[UIImageView alloc] init];
  resetIconView.translatesAutoresizingMaskIntoConstraints = NO;
  UIImage* resetIcon = [UIImage imageNamed:@"ic_reset"];
  if (!resetIcon && @available(iOS 13.0, *)) {
    resetIcon = [UIImage systemImageNamed:@"arrow.counterclockwise"];
  }
  resetIconView.image = resetIcon;
  resetIconView.contentMode = UIViewContentModeScaleAspectFit;
  resetIconView.tintColor = [UIColor whiteColor];
  resetIconView.userInteractionEnabled = NO;
  [_resetButton addSubview:resetIconView];

  UILabel* resetLabel = [[UILabel alloc] init];
  resetLabel.translatesAutoresizingMaskIntoConstraints = NO;
  resetLabel.text = @"重置";
  resetLabel.textColor = [UIColor whiteColor];
  resetLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  resetLabel.userInteractionEnabled = NO;
  [_resetButton addSubview:resetLabel];

  [self.view addSubview:_resetButton];

  // 3. Floating Compare Button (Above beauty panel)
  _compareButton = [UIButton buttonWithType:UIButtonTypeCustom];
  _compareButton.translatesAutoresizingMaskIntoConstraints = NO;
  _compareButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.40];
  _compareButton.layer.cornerRadius = 18.0;
  _compareButton.layer.borderWidth = 1.0;
  _compareButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.27].CGColor;
  _compareButton.layer.masksToBounds = YES;
  [_compareButton addTarget:self action:@selector(onCompareTouchDown) forControlEvents:UIControlEventTouchDown];
  [_compareButton addTarget:self action:@selector(onCompareTouchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

  UIImageView* cmpIconView = [[UIImageView alloc] init];
  cmpIconView.translatesAutoresizingMaskIntoConstraints = NO;
  UIImage* cmpIcon = [UIImage imageNamed:@"ic_compare"];
  if (!cmpIcon && @available(iOS 13.0, *)) {
    cmpIcon = [UIImage systemImageNamed:@"square.split.2x1"];
  }
  cmpIconView.image = cmpIcon;
  cmpIconView.contentMode = UIViewContentModeScaleAspectFit;
  cmpIconView.tintColor = [UIColor whiteColor];
  cmpIconView.userInteractionEnabled = NO;
  [_compareButton addSubview:cmpIconView];

  UILabel* cmpLabel = [[UILabel alloc] init];
  cmpLabel.translatesAutoresizingMaskIntoConstraints = NO;
  cmpLabel.text = @"按住对比";
  cmpLabel.textColor = [UIColor whiteColor];
  cmpLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
  cmpLabel.userInteractionEnabled = NO;
  [_compareButton addSubview:cmpLabel];

  [self.view addSubview:_compareButton];

  // 4. Beauty Panel
  _filterToolbarView = [[FilterToolbarView alloc] initWithFrame:CGRectZero];
  _filterToolbarView.translatesAutoresizingMaskIntoConstraints = NO;
  _filterToolbarView.delegate = self;
  [self.view addSubview:_filterToolbarView];

  [NSLayoutConstraint activateConstraints:@[
    // Top Bar
    [_topBarView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [_topBarView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_topBarView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [_topBarView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:50],

    [_backButton.leadingAnchor constraintEqualToAnchor:_topBarView.leadingAnchor constant:16],
    [_backButton.bottomAnchor constraintEqualToAnchor:_topBarView.bottomAnchor constant:-10],
    [_backButton.heightAnchor constraintEqualToConstant:32],

    [_titleLabel.centerXAnchor constraintEqualToAnchor:_topBarView.centerXAnchor],
    [_titleLabel.centerYAnchor constraintEqualToAnchor:_backButton.centerYAnchor],

    [_saveButton.trailingAnchor constraintEqualToAnchor:_topBarView.trailingAnchor constant:-16],
    [_saveButton.centerYAnchor constraintEqualToAnchor:_backButton.centerYAnchor],
    [_saveButton.widthAnchor constraintEqualToConstant:64],
    [_saveButton.heightAnchor constraintEqualToConstant:30],

    // Reset button
    [_resetButton.topAnchor constraintEqualToAnchor:_topBarView.bottomAnchor constant:12],
    [_resetButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
    [_resetButton.heightAnchor constraintEqualToConstant:36],

    [resetIconView.leadingAnchor constraintEqualToAnchor:_resetButton.leadingAnchor constant:12],
    [resetIconView.centerYAnchor constraintEqualToAnchor:_resetButton.centerYAnchor],
    [resetIconView.widthAnchor constraintEqualToConstant:16],
    [resetIconView.heightAnchor constraintEqualToConstant:16],

    [resetLabel.leadingAnchor constraintEqualToAnchor:resetIconView.trailingAnchor constant:6],
    [resetLabel.centerYAnchor constraintEqualToAnchor:_resetButton.centerYAnchor],
    [resetLabel.trailingAnchor constraintEqualToAnchor:_resetButton.trailingAnchor constant:-14],

    // Compare button
    [_compareButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
    [_compareButton.bottomAnchor constraintEqualToAnchor:_filterToolbarView.topAnchor constant:-12],
    [_compareButton.heightAnchor constraintEqualToConstant:36],

    [cmpIconView.leadingAnchor constraintEqualToAnchor:_compareButton.leadingAnchor constant:14],
    [cmpIconView.centerYAnchor constraintEqualToAnchor:_compareButton.centerYAnchor],
    [cmpIconView.widthAnchor constraintEqualToConstant:16],
    [cmpIconView.heightAnchor constraintEqualToConstant:16],

    [cmpLabel.leadingAnchor constraintEqualToAnchor:cmpIconView.trailingAnchor constant:6],
    [cmpLabel.centerYAnchor constraintEqualToAnchor:_compareButton.centerYAnchor],
    [cmpLabel.trailingAnchor constraintEqualToAnchor:_compareButton.trailingAnchor constant:-16],

    // Filter toolbar view
    [_filterToolbarView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_filterToolbarView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [_filterToolbarView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
  ]];
}

#pragma mark - Actions

- (void)onBackTapped {
  [self destroyGPUPixel];
  [self.navigationController popViewControllerAnimated:YES];
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

  if (_gpuSourceImage) {
    _gpuSourceImage->Render();
  }
}

- (void)onCompareTouchDown {
  self.isComparing = YES;
  _compareButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.325 blue:0.463 alpha:0.60];
  [self applyBypass:YES];
  if (_gpuSourceImage) _gpuSourceImage->Render();
}

- (void)onCompareTouchUp {
  self.isComparing = NO;
  _compareButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.40];
  [self applyBypass:NO];
  if (_gpuSourceImage) _gpuSourceImage->Render();
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

- (void)onSaveTapped {
  if (!_gpuSourceImage || !_sinkRawData) return;

  _gpuSourceImage->Render();

  const uint8_t* pixels = _sinkRawData->GetRgbaBuffer();
  int width = _sinkRawData->GetWidth();
  int height = _sinkRawData->GetHeight();

  if (!pixels || width <= 0 || height <= 0) {
    [self showAlert:@"保存失败" message:@"渲染数据为空，请重试"];
    return;
  }

  UIImage* resultImage = [ImageConverter imageFromRGBAData:pixels width:width height:height];
  if (!resultImage) {
    [self showAlert:@"保存失败" message:@"图像生成失败"];
    return;
  }

  UIImageWriteToSavedPhotosAlbum(resultImage, self, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)image:(UIImage*)image didFinishSavingWithError:(NSError*)error contextInfo:(void*)contextInfo {
  if (error) {
    [self showAlert:@"保存失败" message:error.localizedDescription];
  } else {
    [self showAlert:@"保存成功" message:@"修饰后的照片已保存到系统相册！"];
  }
}

- (void)showAlert:(NSString*)title message:(NSString*)message {
  UIAlertController* alert = [UIAlertController alertControllerWithTitle:title
                                                                 message:message
                                                          preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Parameter Mapping

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

  if (_gpuSourceImage) {
    _gpuSourceImage->Render();
  }
}

- (void)beautyToolbarView:(FilterToolbarView*)toolbarView
           didChangeValue:(NSInteger)value
                forOption:(BeautyOption*)option {
  if (option.category <= BeautyCategoryMakeup) {
    [self applyOptionParam:option];
    if (_gpuSourceImage) {
      _gpuSourceImage->Render();
    }
  }
}

- (void)beautyToolbarViewDidRequestDismiss:(FilterToolbarView*)toolbarView {
  // In photo retouch mode, can keep toolbar or collapse if needed
}

#pragma mark - Helpers

- (UIImage*)normalizeOrientation:(UIImage*)image {
  if (image.imageOrientation == UIImageOrientationUp) return image;
  UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
  [image drawInRect:(CGRect){0, 0, image.size}];
  UIImage* normalized = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return normalized ?: image;
}

- (unsigned char*)rgbaPixelsFromImage:(UIImage*)image width:(int*)outW height:(int*)outH {
  CGImageRef cgImage = image.CGImage;
  if (!cgImage) return NULL;

  int w = (int)CGImageGetWidth(cgImage);
  int h = (int)CGImageGetHeight(cgImage);
  *outW = w;
  *outH = h;

  unsigned char* pixels = (unsigned char*)malloc(w * h * 4);
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(pixels, w, h, 8, w * 4, colorSpace,
                                           kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
  CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cgImage);
  CGContextRelease(ctx);
  CGColorSpaceRelease(colorSpace);

  return pixels;
}

@end
