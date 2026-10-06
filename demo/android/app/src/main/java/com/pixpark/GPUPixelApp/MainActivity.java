package com.pixpark.GPUPixelApp;

import static android.widget.Toast.LENGTH_LONG;

import android.Manifest;
import android.annotation.SuppressLint;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraCharacteristics;
import android.os.Bundle;
import android.util.Log;
import android.transition.TransitionManager;
import android.view.LayoutInflater;
import android.view.MotionEvent;
import android.view.Surface;
import android.view.TextureView;
import android.view.View;
import android.view.WindowManager;
import android.widget.ImageView;
import android.widget.SeekBar;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import com.google.android.material.tabs.TabLayout;
import com.pixpark.GPUPixelApp.databinding.ActivityMainBinding;
import com.pixpark.GPUPixelApp.databinding.ItemBeautyOptionBinding;
import com.pixpark.gpupixel.FaceDetector;
import com.pixpark.gpupixel.GPUPixel;
import com.pixpark.gpupixel.GPUPixelFilter;
import com.pixpark.gpupixel.GPUPixelSinkRawData;
import com.pixpark.gpupixel.GPUPixelSinkSurface;
import com.pixpark.gpupixel.GPUPixelSource;
import com.pixpark.gpupixel.GPUPixelSourceRawData;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends AppCompatActivity {
    private static final int CAMERA_PERMISSION_REQUEST_CODE = 200;
    private static final String TAG = "GPUPixelCamera";

    // Item category constants
    private static final int CAT_SKIN = 0;    // 美肤
    private static final int CAT_SHAPE = 1;   // 美型
    private static final int CAT_MAKEUP = 2;  // 美妆
    private static final int CAT_FILTER = 3;  // 滤镜
    private static final int CAT_STICKER = 4; // 贴纸
    private static final int CAT_ANIM_STICKER = 5; // 动态贴纸

    // Item ID constants
    private static final int ID_SMOOTH = 1;
    private static final int ID_WHITE = 2;
    private static final int ID_SHARPEN = 3;
    private static final int ID_THIN_FACE = 4;
    private static final int ID_BIG_EYE = 5;
    private static final int ID_LIPSTICK = 6;
    private static final int ID_BLUSHER = 7;
    private static final int ID_FILTER_ORIGIN = 8;
    private static final int ID_FILTER_PINK = 9;
    private static final int ID_FILTER_COOL = 10;
    private static final int ID_FILTER_FILM = 11;
    private static final int ID_FILTER_BW = 12;
    private static final int ID_STICKER_NONE = 13;
    private static final int ID_STICKER_CAT_EARS = 14;
    private static final int ID_STICKER_BUNNY_EARS = 15;
    private static final int ID_STICKER_CROWN = 16;
    private static final int ID_STICKER_ANGEL_HALO = 17;
    private static final int ID_STICKER_DEVIL_HORNS = 18;
    private static final int ID_STICKER_SUNGLASSES = 19;
    private static final int ID_STICKER_HEART_BLUSH = 20;
    private static final int ID_STICKER_CLOWN_NOSE = 21;
    private static final int ID_STICKER_MUSTACHE = 22;
    private static final int ID_STICKER_FLOWER_HAIRPIN = 23;

    // Animated sticker IDs
    private static final int ID_ANIM_NONE = 30;
    private static final int ID_ANIM_HEARTS = 31;
    private static final int ID_ANIM_CAT_EARS = 32;
    private static final int ID_ANIM_CROWN = 33;
    private static final int ID_ANIM_HALO = 34;
    private static final int ID_ANIM_DEVIL = 35;
    private static final int ID_ANIM_FIREWORKS = 36;
    private static final int ID_ANIM_TEARS = 37;
    private static final int ID_ANIM_STEAM = 38;
    private static final int ID_ANIM_COINS = 39;
    private static final int ID_ANIM_DIZZY = 40;

    public static class BeautyOption {
        int id;
        String name;
        int iconRes;
        int category;
        int progress; // 0 - 100

        BeautyOption(int id, String name, int iconRes, int category, int initialProgress) {
            this.id = id;
            this.name = name;
            this.iconRes = iconRes;
            this.category = category;
            this.progress = initialProgress;
        }
    }

    private final List<BeautyOption> mOptions = new ArrayList<>();
    private BeautyOption mSelectedOption = null;
    private int mSelectedFilterId = ID_FILTER_ORIGIN;
    private int mSelectedStickerId = ID_STICKER_NONE;

    private Camera2Helper mCamera2Helper;
    private GPUPixelSourceRawData mSourceRawData;
    private GPUPixelFilter mLipstickFilter;
    private GPUPixelFilter mBlusherFilter;
    private GPUPixelFilter mBeautyFilter;
    private GPUPixelFilter mFaceReshapeFilter;
    private GPUPixelFilter mFaceStickerFilter;
    private GPUPixelFilter mWhiteBalanceFilter;
    private GPUPixelFilter mSaturationFilter;
    private FaceDetector mFaceDetector;
    private GPUPixelSinkSurface mSinkSurface;
    private GPUPixelSinkRawData mCaptureSinkRawData;

    private TextureView mTextureView;
    private volatile boolean mCaptureRequested = false;
    private ExecutorService mCaptureExecutor;
    private ActivityMainBinding binding;
    private ByteBuffer mTakePictureBuffer;

    private boolean mHasFaceDetected = false;
    private boolean mIsComparing = false;
    private boolean mIsPanelCollapsed = true;

    private SurfaceTexture mCachedSurfaceTexture;
    private int mCachedSurfaceWidth = 0;
    private int mCachedSurfaceHeight = 0;
    private int mFrameCount = 0;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        binding = ActivityMainBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());

        // Fullscreen & keep screen on
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        // Init GPUPixel C++ engine
        GPUPixel.Init(this);
        mCaptureExecutor = Executors.newSingleThreadExecutor();

        // Asynchronously init face detector to avoid freezing camera startup
        mCaptureExecutor.execute(() -> {
            mFaceDetector = FaceDetector.Create();
            Log.i(TAG, "FaceDetector initialized successfully");
        });

        initBeautyOptions();
        initUI();
        checkCameraPermission();
    }

    private void initBeautyOptions() {
        // 美肤
        mOptions.add(new BeautyOption(ID_SMOOTH, "磨皮", R.drawable.ic_skin_smooth, CAT_SKIN, 45));
        mOptions.add(new BeautyOption(ID_WHITE, "美白", R.drawable.ic_skin_white, CAT_SKIN, 35));
        mOptions.add(new BeautyOption(ID_SHARPEN, "清晰", R.drawable.ic_sharpen, CAT_SKIN, 25));

        // 美型
        mOptions.add(new BeautyOption(ID_THIN_FACE, "瘦脸", R.drawable.ic_thin_face, CAT_SHAPE, 30));
        mOptions.add(new BeautyOption(ID_BIG_EYE, "大眼", R.drawable.ic_big_eye, CAT_SHAPE, 25));

        // 美妆
        mOptions.add(new BeautyOption(ID_LIPSTICK, "口红", R.drawable.ic_lipstick, CAT_MAKEUP, 25));
        mOptions.add(new BeautyOption(ID_BLUSHER, "腮红", R.drawable.ic_blusher, CAT_MAKEUP, 20));

        // 滤镜 (0% 表示原图效果，100% 表示满效果)
        mOptions.add(new BeautyOption(ID_FILTER_ORIGIN, "原图", R.drawable.ic_filter, CAT_FILTER, 100));
        mOptions.add(new BeautyOption(ID_FILTER_PINK, "粉嫩", R.drawable.ic_filter, CAT_FILTER, 100));
        mOptions.add(new BeautyOption(ID_FILTER_COOL, "冷白", R.drawable.ic_filter, CAT_FILTER, 100));
        mOptions.add(new BeautyOption(ID_FILTER_FILM, "胶片", R.drawable.ic_filter, CAT_FILTER, 100));
        mOptions.add(new BeautyOption(ID_FILTER_BW, "黑白", R.drawable.ic_filter, CAT_FILTER, 100));

        // 静态贴纸 (10款)
        mOptions.add(new BeautyOption(ID_STICKER_NONE, "无贴纸", R.drawable.ic_reset, CAT_STICKER, 0));
        mOptions.add(new BeautyOption(ID_STICKER_CAT_EARS, "猫耳朵", R.drawable.ic_beauty_wand, CAT_STICKER, 100));
        mOptions.add(new BeautyOption(ID_STICKER_BUNNY_EARS, "兔耳朵", R.drawable.ic_beauty_wand, CAT_STICKER, 100));
        mOptions.add(new BeautyOption(ID_STICKER_CROWN, "金皇冠", R.drawable.ic_beauty_wand, CAT_STICKER, 100));
        mOptions.add(new BeautyOption(ID_STICKER_ANGEL_HALO, "天使环", R.drawable.ic_beauty_wand, CAT_STICKER, 100));
        mOptions.add(new BeautyOption(ID_STICKER_DEVIL_HORNS, "恶魔角", R.drawable.ic_beauty_wand, CAT_STICKER, 100));
        mOptions.add(new BeautyOption(ID_STICKER_SUNGLASSES, "酷墨镜", R.drawable.ic_beauty_wand, CAT_STICKER, 100));
        mOptions.add(new BeautyOption(ID_STICKER_HEART_BLUSH, "爱心贴", R.drawable.ic_beauty_wand, CAT_STICKER, 100));
        mOptions.add(new BeautyOption(ID_STICKER_CLOWN_NOSE, "小丑鼻", R.drawable.ic_beauty_wand, CAT_STICKER, 100));
        mOptions.add(new BeautyOption(ID_STICKER_MUSTACHE, "绅士胡", R.drawable.ic_beauty_wand, CAT_STICKER, 100));
        mOptions.add(new BeautyOption(ID_STICKER_FLOWER_HAIRPIN, "樱花夹", R.drawable.ic_beauty_wand, CAT_STICKER, 100));

        // 动态贴纸 (10款)
        mOptions.add(new BeautyOption(ID_ANIM_NONE, "无动态", R.drawable.ic_reset, CAT_ANIM_STICKER, 0));
        mOptions.add(new BeautyOption(ID_ANIM_HEARTS, "闪烁心动", R.drawable.ic_beauty_wand, CAT_ANIM_STICKER, 100));
        mOptions.add(new BeautyOption(ID_ANIM_CAT_EARS, "动感猫耳", R.drawable.ic_beauty_wand, CAT_ANIM_STICKER, 100));
        mOptions.add(new BeautyOption(ID_ANIM_CROWN, "闪耀皇冠", R.drawable.ic_beauty_wand, CAT_ANIM_STICKER, 100));
        mOptions.add(new BeautyOption(ID_ANIM_HALO, "霓虹光环", R.drawable.ic_beauty_wand, CAT_ANIM_STICKER, 100));
        mOptions.add(new BeautyOption(ID_ANIM_DEVIL, "烈焰恶魔", R.drawable.ic_beauty_wand, CAT_ANIM_STICKER, 100));
        mOptions.add(new BeautyOption(ID_ANIM_FIREWORKS, "派对礼花", R.drawable.ic_beauty_wand, CAT_ANIM_STICKER, 100));
        mOptions.add(new BeautyOption(ID_ANIM_TEARS, "二次元泪", R.drawable.ic_beauty_wand, CAT_ANIM_STICKER, 100));
        mOptions.add(new BeautyOption(ID_ANIM_STEAM, "冒烟怒火", R.drawable.ic_beauty_wand, CAT_ANIM_STICKER, 100));
        mOptions.add(new BeautyOption(ID_ANIM_COINS, "招财金币", R.drawable.ic_beauty_wand, CAT_ANIM_STICKER, 100));
        mOptions.add(new BeautyOption(ID_ANIM_DIZZY, "转圈晕星", R.drawable.ic_beauty_wand, CAT_ANIM_STICKER, 100));

        // Default selected option: 磨皮
        mSelectedOption = mOptions.get(0);
    }

    private Surface mCurrentOutputSurface = null;

    private synchronized void updateSinkSurfaceWindow(SurfaceTexture surfaceTexture, int width, int height) {
        mCachedSurfaceTexture = surfaceTexture;
        mCachedSurfaceWidth = width;
        mCachedSurfaceHeight = height;
        if (mSinkSurface != null && surfaceTexture != null && width > 0 && height > 0) {
            if (mCurrentOutputSurface != null) {
                mCurrentOutputSurface.release();
            }
            mCurrentOutputSurface = new Surface(surfaceTexture);
            mSinkSurface.SetSurface(mCurrentOutputSurface, width, height);
            Log.i(TAG, "updateSinkSurfaceWindow: SetSurface " + width + "x" + height);
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private void initUI() {
        mTextureView = binding.textureView;
        mTextureView.setSurfaceTextureListener(new TextureView.SurfaceTextureListener() {
            @Override
            public void onSurfaceTextureAvailable(SurfaceTexture surface, int width, int height) {
                updateSinkSurfaceWindow(surface, width, height);
            }

            @Override
            public void onSurfaceTextureSizeChanged(SurfaceTexture surface, int width, int height) {
                updateSinkSurfaceWindow(surface, width, height);
            }

            @Override
            public boolean onSurfaceTextureDestroyed(SurfaceTexture surface) {
                mCachedSurfaceTexture = null;
                if (mCurrentOutputSurface != null) {
                    mCurrentOutputSurface.release();
                    mCurrentOutputSurface = null;
                }
                if (mSinkSurface != null) {
                    mSinkSurface.ReleaseSurface();
                }
                return false;
            }

            @Override
            public void onSurfaceTextureUpdated(SurfaceTexture surface) {
            }
        });

        // Top bar buttons
        binding.btnSwitch.setOnClickListener(v -> {
            if (mCamera2Helper != null) {
                mCamera2Helper.switchCamera();
                updateMirrorSetting();
                updateFlashlightIcon();
            }
        });

        binding.btnFlash.setOnClickListener(v -> {
            if (mCamera2Helper != null) {
                mCamera2Helper.toggleFlashlight();
                updateFlashlightIcon();
            }
        });

        binding.btnReset.setOnClickListener(v -> resetAllBeautyParams());

        // Compare button: long press to compare with original
        binding.btnCompare.setOnTouchListener((v, event) -> {
            switch (event.getAction()) {
                case MotionEvent.ACTION_DOWN:
                    mIsComparing = true;
                    applyCompareMode(true);
                    binding.btnCompare.setBackgroundResource(R.drawable.bg_item_circle_selected);
                    return true;
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    mIsComparing = false;
                    applyCompareMode(false);
                    binding.btnCompare.setBackgroundResource(R.drawable.bg_pill_button);
                    return true;
            }
            return false;
        });

        // Panel collapse/expand toggle
        binding.btnTogglePanel.setOnClickListener(v -> togglePanel());

        // Shutter capture button
        binding.btnCapture.setOnClickListener(v -> requestCapture());

        // Category Tabs
        binding.tabLayout.addTab(binding.tabLayout.newTab().setText("美肤"));
        binding.tabLayout.addTab(binding.tabLayout.newTab().setText("美型"));
        binding.tabLayout.addTab(binding.tabLayout.newTab().setText("美妆"));
        binding.tabLayout.addTab(binding.tabLayout.newTab().setText("滤镜"));
        binding.tabLayout.addTab(binding.tabLayout.newTab().setText("贴纸"));
        binding.tabLayout.addTab(binding.tabLayout.newTab().setText("动态"));

        binding.tabLayout.addOnTabSelectedListener(new TabLayout.OnTabSelectedListener() {
            @Override
            public void onTabSelected(TabLayout.Tab tab) {
                refreshItemsForCategory(tab.getPosition());
            }

            @Override
            public void onTabUnselected(TabLayout.Tab tab) {
            }

            @Override
            public void onTabReselected(TabLayout.Tab tab) {
            }
        });

        // Active Slider change listener
        binding.activeSeekbar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                if (mSelectedOption != null && fromUser) {
                    mSelectedOption.progress = progress;
                    binding.tvSliderValue.setText(progress + "%");
                    applyFilterParam(mSelectedOption);
                }
            }

            @Override
            public void onStartTrackingTouch(SeekBar seekBar) {
            }

            @Override
            public void onStopTrackingTouch(SeekBar seekBar) {
            }
        });

        // Populate initial category: 美肤
        refreshItemsForCategory(CAT_SKIN);

        // Bottom camera switch button
        binding.btnSwitchCameraBottom.setOnClickListener(v -> {
            if (mCamera2Helper != null) {
                mCamera2Helper.switchCamera();
                updateMirrorSetting();
                updateFlashlightIcon();
            }
        });

        // Album & Memories click
        View.OnClickListener openGallery = v -> {
            Toast.makeText(this, "打开相册", Toast.LENGTH_SHORT).show();
        };
        binding.btnAlbum.setOnClickListener(openGallery);
        binding.navMemories.setOnClickListener(openGallery);

        // Bottom nav camera & chats
        binding.navCamera.setOnClickListener(v -> {
            if (!mIsPanelCollapsed) {
                togglePanel();
            }
        });
        binding.navChats.setOnClickListener(v -> {
            Toast.makeText(this, "Chats 功能开发中", Toast.LENGTH_SHORT).show();
        });

        // Mode switch (Photo | Video)
        binding.btnModePhoto.setOnClickListener(v -> {
            binding.btnModePhoto.setBackgroundResource(R.drawable.bg_mode_switch_selected);
            binding.btnModePhoto.setTextColor(ContextCompat.getColor(this, R.color.black));
            binding.btnModePhoto.setTypeface(null, android.graphics.Typeface.BOLD);

            binding.btnModeVideo.setBackground(null);
            binding.btnModeVideo.setTextColor(ContextCompat.getColor(this, R.color.camera_text_secondary));
            binding.btnModeVideo.setTypeface(null, android.graphics.Typeface.NORMAL);
        });

        binding.btnModeVideo.setOnClickListener(v -> {
            binding.btnModeVideo.setBackgroundResource(R.drawable.bg_mode_switch_selected);
            binding.btnModeVideo.setTextColor(ContextCompat.getColor(this, R.color.black));
            binding.btnModeVideo.setTypeface(null, android.graphics.Typeface.BOLD);

            binding.btnModePhoto.setBackground(null);
            binding.btnModePhoto.setTextColor(ContextCompat.getColor(this, R.color.camera_text_secondary));
            binding.btnModePhoto.setTypeface(null, android.graphics.Typeface.NORMAL);

            Toast.makeText(this, "切换至视频录制模式", Toast.LENGTH_SHORT).show();
        });

        updatePanelToggleUI();
    }

    private void togglePanel() {
        mIsPanelCollapsed = !mIsPanelCollapsed;
        TransitionManager.beginDelayedTransition(binding.bottomPanel);
        binding.layoutBeautyControls.setVisibility(mIsPanelCollapsed ? View.GONE : View.VISIBLE);

        if (!mIsPanelCollapsed) {
            int selectedTab = binding.tabLayout.getSelectedTabPosition();
            if (selectedTab != CAT_FILTER && selectedTab != CAT_STICKER && selectedTab != CAT_ANIM_STICKER) {
                binding.layoutSlider.setVisibility(View.VISIBLE);
            } else {
                binding.layoutSlider.setVisibility(View.GONE);
            }
        }
        updatePanelToggleUI();
    }

    private void updatePanelToggleUI() {
        binding.btnTogglePanel.setSelected(!mIsPanelCollapsed);
    }

    private void updateFlashlightIcon() {
        if (mCamera2Helper != null && mCamera2Helper.isFlashlightEnabled()) {
            binding.btnFlash.setImageResource(R.drawable.ic_flash_on);
        } else {
            binding.btnFlash.setImageResource(R.drawable.ic_flash_off);
        }
    }

    /**
     * Render the horizontal items for the selected category
     */
    private void refreshItemsForCategory(int category) {
        binding.layoutItemsContainer.removeAllViews();
        LayoutInflater inflater = LayoutInflater.from(this);

        BeautyOption firstInCat = null;

        for (BeautyOption option : mOptions) {
            if (option.category != category) continue;
            if (firstInCat == null) firstInCat = option;

            ItemBeautyOptionBinding itemBinding = ItemBeautyOptionBinding.inflate(
                    inflater, binding.layoutItemsContainer, false);

            itemBinding.tvTitle.setText(option.name);
            itemBinding.ivIcon.setImageResource(option.iconRes);

            boolean isSelected;
            if (category == CAT_FILTER) {
                isSelected = (option.id == mSelectedFilterId);
            } else if (category == CAT_STICKER || category == CAT_ANIM_STICKER) {
                isSelected = (option.id == mSelectedStickerId);
            } else {
                isSelected = (mSelectedOption != null && mSelectedOption.id == option.id);
            }

            updateItemSelectionVisual(itemBinding, isSelected);

            itemBinding.itemRoot.setOnClickListener(v -> {
                if (category == CAT_FILTER) {
                    mSelectedFilterId = option.id;
                    applyFilterPreset(mSelectedFilterId);
                    refreshItemsForCategory(category);
                } else if (category == CAT_STICKER || category == CAT_ANIM_STICKER) {
                    mSelectedStickerId = option.id;
                    applyStickerPreset(mSelectedStickerId);
                    refreshItemsForCategory(category);
                } else {
                    selectBeautyOption(option);
                    refreshItemsForCategory(category);
                }
            });

            binding.layoutItemsContainer.addView(itemBinding.getRoot());
        }

        // If category changed and current selected option not in this category, select first
        if (category != CAT_FILTER && category != CAT_STICKER && category != CAT_ANIM_STICKER && (mSelectedOption == null || mSelectedOption.category != category)) {
            if (firstInCat != null) {
                selectBeautyOption(firstInCat);
            }
        } else if (category == CAT_FILTER || category == CAT_STICKER || category == CAT_ANIM_STICKER) {
            // For filter/sticker/anim tab, hide the slider
            binding.layoutSlider.setVisibility(View.GONE);
        } else {
            if (!mIsPanelCollapsed) {
                binding.layoutSlider.setVisibility(View.VISIBLE);
            }
        }
    }

    private void updateItemSelectionVisual(ItemBeautyOptionBinding itemBinding, boolean isSelected) {
        if (isSelected) {
            itemBinding.ivIconContainer.setBackgroundResource(R.drawable.bg_item_circle_selected);
            itemBinding.tvTitle.setTextColor(ContextCompat.getColor(this, R.color.camera_accent));
        } else {
            itemBinding.ivIconContainer.setBackgroundResource(R.drawable.bg_item_circle);
            itemBinding.tvTitle.setTextColor(ContextCompat.getColor(this, R.color.white));
        }
    }

    private void selectBeautyOption(BeautyOption option) {
        mSelectedOption = option;
        if (!mIsPanelCollapsed) {
            binding.layoutSlider.setVisibility(View.VISIBLE);
        }
        binding.tvSliderLabel.setText(option.name);
        binding.activeSeekbar.setProgress(option.progress);
        binding.tvSliderValue.setText(option.progress + "%");
    }

    /**
     * Apply single beauty parameter to native filters
     */
    private void applyFilterParam(BeautyOption option) {
        if (mIsComparing) return;

        float ratio = option.progress / 100.0f;
        switch (option.id) {
            case ID_SMOOTH:
                if (mBeautyFilter != null) {
                    mBeautyFilter.SetProperty("skin_smoothing", ratio);
                }
                break;
            case ID_WHITE:
                if (mBeautyFilter != null) {
                    mBeautyFilter.SetProperty("whiteness", ratio);
                }
                break;
            case ID_SHARPEN:
                if (mBeautyFilter != null) {
                    mBeautyFilter.SetProperty("sharpen", ratio);
                }
                break;
            case ID_THIN_FACE:
                if (mFaceReshapeFilter != null) {
                    // thin_face max delta ~0.08
                    mFaceReshapeFilter.SetProperty("thin_face", ratio * 0.08f);
                }
                break;
            case ID_BIG_EYE:
                if (mFaceReshapeFilter != null) {
                    // big_eye max delta ~0.35
                    mFaceReshapeFilter.SetProperty("big_eye", ratio * 0.35f);
                }
                break;
            case ID_LIPSTICK:
                if (mLipstickFilter != null) {
                    mLipstickFilter.SetProperty("blend_level", ratio * 0.8f);
                }
                break;
            case ID_BLUSHER:
                if (mBlusherFilter != null) {
                    mBlusherFilter.SetProperty("blend_level", ratio * 0.7f);
                }
                break;
        }
    }

    /**
     * Apply filter color tone preset
     */
    private void applyFilterPreset(int filterId) {
        if (mWhiteBalanceFilter == null || mSaturationFilter == null) return;
        if (mIsComparing) return;

        switch (filterId) {
            case ID_FILTER_ORIGIN: // 原图标准
                mWhiteBalanceFilter.SetProperty("temperature", 5000.0f);
                mWhiteBalanceFilter.SetProperty("tint", 0.0f);
                mSaturationFilter.SetProperty("saturation", 1.0f);
                break;
            case ID_FILTER_PINK: // 奶油粉嫩
                mWhiteBalanceFilter.SetProperty("temperature", 5350.0f);
                mWhiteBalanceFilter.SetProperty("tint", 6.0f);
                mSaturationFilter.SetProperty("saturation", 1.15f);
                break;
            case ID_FILTER_COOL: // 冷白日系
                mWhiteBalanceFilter.SetProperty("temperature", 4550.0f);
                mWhiteBalanceFilter.SetProperty("tint", -4.0f);
                mSaturationFilter.SetProperty("saturation", 0.95f);
                break;
            case ID_FILTER_FILM: // 胶片复古
                mWhiteBalanceFilter.SetProperty("temperature", 5600.0f);
                mWhiteBalanceFilter.SetProperty("tint", 8.0f);
                mSaturationFilter.SetProperty("saturation", 1.18f);
                break;
            case ID_FILTER_BW: // 质感黑白
                mWhiteBalanceFilter.SetProperty("temperature", 5000.0f);
                mWhiteBalanceFilter.SetProperty("tint", 0.0f);
                mSaturationFilter.SetProperty("saturation", 0.0f);
                break;
        }
    }

    private void applyStickerPreset(int stickerId) {
        if (mFaceStickerFilter == null) return;
        File resDir = new File(getExternalFilesDir(null), "gpupixel/res");
        switch (stickerId) {
            case ID_STICKER_CAT_EARS: {
                File file = new File(resDir, "cat_ears.png");
                if (file.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", file.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("anchor", 0); // 0: Forehead
                    mFaceStickerFilter.SetProperty("scale", 1.0f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", 0.0f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_STICKER_BUNNY_EARS: {
                File file = new File(resDir, "bunny_ears.png");
                if (file.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", file.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("anchor", 0); // 0: Forehead
                    mFaceStickerFilter.SetProperty("scale", 1.15f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", 0.15f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_STICKER_CROWN: {
                File file = new File(resDir, "crown.png");
                if (file.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", file.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("anchor", 0); // 0: Forehead
                    mFaceStickerFilter.SetProperty("scale", 0.95f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", 0.05f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_STICKER_ANGEL_HALO: {
                File file = new File(resDir, "angel_halo.png");
                if (file.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", file.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("anchor", 0); // 0: Forehead
                    mFaceStickerFilter.SetProperty("scale", 1.05f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", 0.35f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_STICKER_DEVIL_HORNS: {
                File file = new File(resDir, "devil_horns.png");
                if (file.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", file.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("anchor", 0); // 0: Forehead
                    mFaceStickerFilter.SetProperty("scale", 0.95f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", 0.0f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_STICKER_SUNGLASSES: {
                File file = new File(resDir, "sunglasses.png");
                if (file.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", file.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("anchor", 1); // 1: Eyes
                    mFaceStickerFilter.SetProperty("scale", 1.05f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", 0.0f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_STICKER_HEART_BLUSH: {
                File file = new File(resDir, "heart_blush.png");
                if (file.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", file.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("anchor", 1); // 1: Eyes
                    mFaceStickerFilter.SetProperty("scale", 1.15f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", -0.25f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_STICKER_CLOWN_NOSE: {
                File file = new File(resDir, "clown_nose.png");
                if (file.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", file.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("anchor", 2); // 2: Nose
                    mFaceStickerFilter.SetProperty("scale", 0.45f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", 0.0f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_STICKER_MUSTACHE: {
                File file = new File(resDir, "mustache.png");
                if (file.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", file.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("anchor", 3); // 3: Mouth
                    mFaceStickerFilter.SetProperty("scale", 0.65f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", 0.18f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_STICKER_FLOWER_HAIRPIN: {
                File file = new File(resDir, "flower_hairpin.png");
                if (file.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", file.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("anchor", 0); // 0: Forehead
                    mFaceStickerFilter.SetProperty("scale", 0.65f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.5f);
                    mFaceStickerFilter.SetProperty("offset_y", 0.15f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_ANIM_HEARTS: {
                File dir = new File(resDir, "anim_hearts");
                if (dir.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", dir.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("fps", 12);
                    mFaceStickerFilter.SetProperty("anchor", 1); // 1: Eyes
                    mFaceStickerFilter.SetProperty("scale", 1.15f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", -0.22f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_ANIM_CAT_EARS: {
                File dir = new File(resDir, "anim_cat_ears");
                if (dir.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", dir.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("fps", 12);
                    mFaceStickerFilter.SetProperty("anchor", 0); // 0: Forehead
                    mFaceStickerFilter.SetProperty("scale", 1.0f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", 0.0f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_ANIM_CROWN: {
                File dir = new File(resDir, "anim_crown");
                if (dir.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", dir.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("fps", 12);
                    mFaceStickerFilter.SetProperty("anchor", 0); // 0: Forehead
                    mFaceStickerFilter.SetProperty("scale", 0.95f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", 0.05f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_ANIM_HALO: {
                File dir = new File(resDir, "anim_halo");
                if (dir.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", dir.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("fps", 12);
                    mFaceStickerFilter.SetProperty("anchor", 0); // 0: Forehead
                    mFaceStickerFilter.SetProperty("scale", 1.05f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", 0.35f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_ANIM_DEVIL: {
                File dir = new File(resDir, "anim_devil");
                if (dir.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", dir.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("fps", 12);
                    mFaceStickerFilter.SetProperty("anchor", 0); // 0: Forehead
                    mFaceStickerFilter.SetProperty("scale", 0.95f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", 0.0f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_ANIM_FIREWORKS: {
                File dir = new File(resDir, "anim_fireworks");
                if (dir.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", dir.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("fps", 10);
                    mFaceStickerFilter.SetProperty("anchor", 0); // 0: Forehead
                    mFaceStickerFilter.SetProperty("scale", 1.25f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", 0.35f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_ANIM_TEARS: {
                File dir = new File(resDir, "anim_tears");
                if (dir.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", dir.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("fps", 12);
                    mFaceStickerFilter.SetProperty("anchor", 1); // 1: Eyes
                    mFaceStickerFilter.SetProperty("scale", 1.1f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", -0.4f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_ANIM_STEAM: {
                File dir = new File(resDir, "anim_steam");
                if (dir.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", dir.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("fps", 12);
                    mFaceStickerFilter.SetProperty("anchor", 0); // 0: Forehead
                    mFaceStickerFilter.SetProperty("scale", 1.2f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", 0.1f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_ANIM_COINS: {
                File dir = new File(resDir, "anim_coins");
                if (dir.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", dir.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("fps", 12);
                    mFaceStickerFilter.SetProperty("anchor", 0); // 0: Forehead
                    mFaceStickerFilter.SetProperty("scale", 1.2f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", 0.35f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            case ID_ANIM_DIZZY: {
                File dir = new File(resDir, "anim_dizzy");
                if (dir.exists()) {
                    mFaceStickerFilter.SetProperty("sticker_path", dir.getAbsolutePath());
                    mFaceStickerFilter.SetProperty("fps", 12);
                    mFaceStickerFilter.SetProperty("anchor", 0); // 0: Forehead
                    mFaceStickerFilter.SetProperty("scale", 1.1f);
                    mFaceStickerFilter.SetProperty("offset_x", 0.0f);
                    mFaceStickerFilter.SetProperty("offset_y", 0.35f);
                    mFaceStickerFilter.SetProperty("alpha", 1.0f);
                }
                break;
            }
            default:
                mFaceStickerFilter.SetProperty("alpha", 0.0f);
                break;
        }
    }

    /**
     * Long-press compare mode: toggles between 0 effects and full active effects
     */
    private void applyCompareMode(boolean compareOriginal) {
        if (compareOriginal) {
            // Set all to 0
            if (mBeautyFilter != null) {
                mBeautyFilter.SetProperty("skin_smoothing", 0.0f);
                mBeautyFilter.SetProperty("whiteness", 0.0f);
                mBeautyFilter.SetProperty("sharpen", 0.0f);
            }
            if (mFaceReshapeFilter != null) {
                mFaceReshapeFilter.SetProperty("thin_face", 0.0f);
                mFaceReshapeFilter.SetProperty("big_eye", 0.0f);
            }
            if (mLipstickFilter != null) {
                mLipstickFilter.SetProperty("blend_level", 0.0f);
            }
            if (mBlusherFilter != null) {
                mBlusherFilter.SetProperty("blend_level", 0.0f);
            }
            if (mWhiteBalanceFilter != null) {
                mWhiteBalanceFilter.SetProperty("temperature", 5000.0f);
                mWhiteBalanceFilter.SetProperty("tint", 0.0f);
            }
            if (mSaturationFilter != null) {
                mSaturationFilter.SetProperty("saturation", 1.0f);
            }
            if (mFaceStickerFilter != null) {
                mFaceStickerFilter.SetProperty("alpha", 0.0f);
            }
        } else {
            // Restore all current params
            for (BeautyOption option : mOptions) {
                applyFilterParam(option);
            }
            applyFilterPreset(mSelectedFilterId);
            applyStickerPreset(mSelectedStickerId);
        }
    }

    /**
     * Reset all parameters to initial default clean state
     */
    private void resetAllBeautyParams() {
        for (BeautyOption option : mOptions) {
            option.progress = 0;
        }
        mSelectedFilterId = ID_FILTER_ORIGIN;
        mSelectedStickerId = ID_STICKER_NONE;
        if (mFaceStickerFilter != null) {
            mFaceStickerFilter.SetProperty("alpha", 0.0f);
        }

        if (mSelectedOption != null) {
            binding.activeSeekbar.setProgress(0);
            binding.tvSliderValue.setText("0%");
        }

        applyCompareMode(true); // Sets all filters to 0
        refreshItemsForCategory(binding.tabLayout.getSelectedTabPosition());
        Toast.makeText(this, "✨ 已重置所有美颜参数", Toast.LENGTH_SHORT).show();
    }

    /**
     * Setup camera and GPUPixel processing chain
     */
    private void setupCamera() {
        long start = System.currentTimeMillis();
        mCamera2Helper = new Camera2Helper(this);

        // Source Raw Data
        mSourceRawData = GPUPixelSourceRawData.Create();

        // Filters: Lipstick -> Blusher -> BeautyFace -> FaceReshape -> WhiteBalance -> Saturation
        mLipstickFilter = GPUPixelFilter.Create(GPUPixelFilter.LIPSTICK_FILTER);
        mBlusherFilter = GPUPixelFilter.Create(GPUPixelFilter.BLUSHER_FILTER);
        mBeautyFilter = GPUPixelFilter.Create(GPUPixelFilter.BEAUTY_FACE_FILTER);
        mFaceReshapeFilter = GPUPixelFilter.Create(GPUPixelFilter.FACE_RESHAPE_FILTER);
        mFaceStickerFilter = GPUPixelFilter.Create(GPUPixelFilter.FACE_STICKER_FILTER);
        File stickerFile = new File(getExternalFilesDir(null), "gpupixel/res/cat_ears.png");
        if (stickerFile.exists()) {
            mFaceStickerFilter.SetProperty("sticker_path", stickerFile.getAbsolutePath());
            mFaceStickerFilter.SetProperty("anchor", 0);
            mFaceStickerFilter.SetProperty("scale", 1.0f);
            mFaceStickerFilter.SetProperty("alpha", 0.0f);
        }
        mWhiteBalanceFilter = GPUPixelFilter.Create(GPUPixelFilter.WHITE_BALANCE_FILTER);
        mSaturationFilter = GPUPixelFilter.Create(GPUPixelFilter.SATURATION_FILTER);

        // Output SinkSurface
        mSinkSurface = GPUPixelSinkSurface.Create();
        mSinkSurface.SetFillMode(GPUPixelSinkSurface.PRESERVE_ASPECT_RATIO_AND_FILL);

        // Photo capture Sink
        mCaptureSinkRawData = GPUPixelSinkRawData.Create();

        // Bind Surface to SinkSurface
        if (mCachedSurfaceTexture != null && mCachedSurfaceWidth > 0 && mCachedSurfaceHeight > 0) {
            updateSinkSurfaceWindow(mCachedSurfaceTexture, mCachedSurfaceWidth, mCachedSurfaceHeight);
        } else if (mTextureView != null && mTextureView.isAvailable()) {
            SurfaceTexture surfaceTexture = mTextureView.getSurfaceTexture();
            if (surfaceTexture != null) {
                int width = mTextureView.getWidth() > 0 ? mTextureView.getWidth() : 1080;
                int height = mTextureView.getHeight() > 0 ? mTextureView.getHeight() : 2280;
                updateSinkSurfaceWindow(surfaceTexture, width, height);
            }
        }

        mTextureView.post(() -> {
            if (mTextureView.isAvailable()) {
                SurfaceTexture st = mTextureView.getSurfaceTexture();
                if (st != null && mTextureView.getWidth() > 0 && mTextureView.getHeight() > 0) {
                    updateSinkSurfaceWindow(st, mTextureView.getWidth(), mTextureView.getHeight());
                }
            }
        });

        // Apply initial beauty params to filters
        for (BeautyOption opt : mOptions) {
            applyFilterParam(opt);
        }
        applyFilterPreset(mSelectedFilterId);

        // Set camera frame callback
        mCamera2Helper.setFrameCallback((rgbaData, width, height) -> {
            int sensorOrientation = mCamera2Helper.getSensorOrientation();
            boolean isFrontCamera = GPUPixel.isFrontCamera(mCamera2Helper.getCameraFacing());

            int rotation = GPUPixel.calculateRotation(
                    MainActivity.this,
                    sensorOrientation,
                    isFrontCamera
            );

            byte[] rotatedData = GPUPixel.rotateRgbaImage(rgbaData, width, height, rotation);
            int outWidth = (rotation == 90 || rotation == 270) ? height : width;
            int outHeight = (rotation == 90 || rotation == 270) ? width : height;

            // Face Landmark Detection
            float[] landmarks = null;
            if (mFaceDetector != null) {
                landmarks = mFaceDetector.detect(rotatedData, outWidth, outHeight,
                        outWidth * 4, FaceDetector.GPUPIXEL_MODE_FMT_VIDEO,
                        FaceDetector.GPUPIXEL_FRAME_TYPE_RGBA);
            }

            if (mFrameCount++ % 60 == 0) {
                Log.d(TAG, "Frame: " + width + "x" + height + " rot: " + rotation + " face: " + (landmarks != null && landmarks.length > 0));
            }

            if (landmarks != null && landmarks.length > 0) {
                if (mFaceReshapeFilter != null) mFaceReshapeFilter.SetProperty("face_landmark", landmarks);
                if (mLipstickFilter != null) mLipstickFilter.SetProperty("face_landmark", landmarks);
                if (mBlusherFilter != null) mBlusherFilter.SetProperty("face_landmark", landmarks);
                if (mFaceStickerFilter != null) mFaceStickerFilter.SetProperty("face_landmark", landmarks);

                if (!mHasFaceDetected) {
                    mHasFaceDetected = true;
                    runOnUiThread(() -> {
                        binding.tvFaceStatus.setText("✨ 已识别人脸");
                        binding.tvFaceStatus.setTextColor(ContextCompat.getColor(MainActivity.this, R.color.camera_accent));
                    });
                }
            } else {
                if (mFaceReshapeFilter != null) mFaceReshapeFilter.SetProperty("face_landmark", new float[0]);
                if (mLipstickFilter != null) mLipstickFilter.SetProperty("face_landmark", new float[0]);
                if (mBlusherFilter != null) mBlusherFilter.SetProperty("face_landmark", new float[0]);
                if (mFaceStickerFilter != null) mFaceStickerFilter.SetProperty("face_landmark", new float[0]);

                if (mHasFaceDetected) {
                    mHasFaceDetected = false;
                    runOnUiThread(() -> {
                        binding.tvFaceStatus.setText("未检测到人脸");
                        binding.tvFaceStatus.setTextColor(ContextCompat.getColor(MainActivity.this, R.color.camera_text_secondary));
                    });
                }
            }

            // Process frame in GPUPixel C++ engine
            mSourceRawData.ProcessData(
                    rotatedData,
                    outWidth,
                    outHeight,
                    outWidth * 4,
                    GPUPixelSourceRawData.FRAME_TYPE_RGBA
            );

            // Capture photo if requested
            if (mCaptureRequested && mCaptureSinkRawData != null) {
                mCaptureRequested = false;
                byte[] captureRgba = mCaptureSinkRawData.GetRgbaBuffer();
                int captureWidth = mCaptureSinkRawData.GetWidth();
                int captureHeight = mCaptureSinkRawData.GetHeight();
                if (captureRgba != null && captureWidth > 0 && captureHeight > 0
                        && captureRgba.length >= captureWidth * captureHeight * 4) {
                    mCaptureExecutor.execute(() -> saveCapturedImage(captureRgba, captureWidth, captureHeight));
                } else {
                    runOnUiThread(() -> Toast.makeText(MainActivity.this, "拍照失败，数据无效", Toast.LENGTH_SHORT).show());
                }
            }
        });

        // Pipeline chain:
        // Source -> (Lipstick) -> (Blusher) -> (BeautyFace) -> (FaceReshape) -> (WhiteBalance) -> (Saturation) -> SinkSurface
        Log.i(TAG, "Connecting filter pipeline:");
        Log.i(TAG, "Source: " + mSourceRawData.getSourceNativeClassID());
        Log.i(TAG, "Lipstick: " + (mLipstickFilter != null ? mLipstickFilter.getNativeClassID() : 0));
        Log.i(TAG, "Blusher: " + (mBlusherFilter != null ? mBlusherFilter.getNativeClassID() : 0));
        Log.i(TAG, "BeautyFace: " + (mBeautyFilter != null ? mBeautyFilter.getNativeClassID() : 0));
        Log.i(TAG, "FaceReshape: " + (mFaceReshapeFilter != null ? mFaceReshapeFilter.getNativeClassID() : 0));
        Log.i(TAG, "WhiteBalance: " + (mWhiteBalanceFilter != null ? mWhiteBalanceFilter.getNativeClassID() : 0));
        Log.i(TAG, "Saturation: " + (mSaturationFilter != null ? mSaturationFilter.getNativeClassID() : 0));
        Log.i(TAG, "SinkSurface: " + (mSinkSurface != null ? mSinkSurface.getNativeClassID() : 0));

        GPUPixelSource lastSource = mSourceRawData;
        if (mLipstickFilter != null && mLipstickFilter.getNativeClassID() != 0) {
            lastSource.AddSink(mLipstickFilter);
            lastSource = mLipstickFilter;
        }
        if (mBlusherFilter != null && mBlusherFilter.getNativeClassID() != 0) {
            lastSource.AddSink(mBlusherFilter);
            lastSource = mBlusherFilter;
        }
        if (mBeautyFilter != null && mBeautyFilter.getNativeClassID() != 0) {
            lastSource.AddSink(mBeautyFilter);
            lastSource = mBeautyFilter;
        }
        if (mFaceReshapeFilter != null && mFaceReshapeFilter.getNativeClassID() != 0) {
            lastSource.AddSink(mFaceReshapeFilter);
            lastSource = mFaceReshapeFilter;
        }
        if (mFaceStickerFilter != null && mFaceStickerFilter.getNativeClassID() != 0) {
            lastSource.AddSink(mFaceStickerFilter);
            lastSource = mFaceStickerFilter;
        }
        if (mWhiteBalanceFilter != null && mWhiteBalanceFilter.getNativeClassID() != 0) {
            lastSource.AddSink(mWhiteBalanceFilter);
            lastSource = mWhiteBalanceFilter;
        }
        if (mSaturationFilter != null && mSaturationFilter.getNativeClassID() != 0) {
            lastSource.AddSink(mSaturationFilter);
            lastSource = mSaturationFilter;
        }

        if (mSinkSurface != null && mSinkSurface.getNativeClassID() != 0) {
            lastSource.AddSink(mSinkSurface);
            Log.i(TAG, "SinkSurface successfully connected to " + (lastSource instanceof GPUPixelFilter ? ((GPUPixelFilter)lastSource).GetFilterClassName() : "SourceRawData"));
        } else {
            Log.e(TAG, "mSinkSurface is invalid ID!");
        }

        if (mCaptureSinkRawData != null && mCaptureSinkRawData.getNativeClassID() != 0) {
            lastSource.AddSink(mCaptureSinkRawData);
        }

        mCamera2Helper.startCamera();
        updateMirrorSetting();
        updateFlashlightIcon();

        Log.d(TAG, "setupCamera completed in: " + (System.currentTimeMillis() - start) + "ms");
    }

    private void updateMirrorSetting() {
        if (mSinkSurface != null && mCamera2Helper != null) {
            boolean shouldMirror = mCamera2Helper.shouldMirrorPreview();
            mSinkSurface.SetMirror(shouldMirror);
        }
    }

    private void requestCapture() {
        if (mCaptureSinkRawData == null) {
            Toast.makeText(this, "拍照功能未就绪", Toast.LENGTH_SHORT).show();
            return;
        }
        if (mCaptureRequested) {
            Toast.makeText(this, "正在保存中...", Toast.LENGTH_SHORT).show();
            return;
        }
        mCaptureRequested = true;
        Toast.makeText(this, "📷 拍照成功，正在保存", Toast.LENGTH_SHORT).show();
    }

    private void saveCapturedImage(byte[] rgbaData, int width, int height) {
        int pixelCount = width * height * 4;
        if (mTakePictureBuffer != null && mTakePictureBuffer.capacity() != pixelCount) {
            mTakePictureBuffer.clear();
            mTakePictureBuffer = null;
        }
        if (mTakePictureBuffer == null) {
            mTakePictureBuffer = ByteBuffer.allocateDirect(pixelCount);
        }
        mTakePictureBuffer.rewind();
        mTakePictureBuffer.put(rgbaData);
        mTakePictureBuffer.position(0);

        Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        bitmap.copyPixelsFromBuffer(mTakePictureBuffer);

        File captureDir = new File(getCacheDir(), "captures");
        if (!captureDir.exists() && !captureDir.mkdirs()) {
            runOnUiThread(() -> Toast.makeText(MainActivity.this, "创建保存目录失败", Toast.LENGTH_SHORT).show());
            bitmap.recycle();
            return;
        }

        String timeStamp = new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new Date());
        File outFile = new File(captureDir, "gpupixel_" + timeStamp + ".png");

        try (FileOutputStream fos = new FileOutputStream(outFile)) {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, fos);
            fos.flush();
            runOnUiThread(() -> Toast.makeText(MainActivity.this, "已保存照片到：" + outFile.getName(), Toast.LENGTH_SHORT).show());
        } catch (IOException e) {
            Log.e(TAG, "Failed to save capture", e);
            runOnUiThread(() -> Toast.makeText(MainActivity.this, "保存失败: " + e.getMessage(), Toast.LENGTH_SHORT).show());
        } finally {
            bitmap.recycle();
        }
    }

    public void checkCameraPermission() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
                != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.CAMERA},
                    CAMERA_PERMISSION_REQUEST_CODE);
        } else {
            setupCamera();
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == CAMERA_PERMISSION_REQUEST_CODE) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                setupCamera();
            } else {
                Toast.makeText(this, "需要相机权限才能使用美颜相机！", LENGTH_LONG).show();
            }
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (mCamera2Helper != null && !mCamera2Helper.isCameraOpened()) {
            mCamera2Helper.startCamera();
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (mCamera2Helper != null) {
            mCamera2Helper.stopCamera();
        }
    }

    @Override
    protected void onDestroy() {
        if (mCamera2Helper != null) {
            mCamera2Helper.stopCamera();
            mCamera2Helper = null;
        }
        if (mFaceDetector != null) {
            mFaceDetector.destroy();
            mFaceDetector = null;
        }
        if (mBeautyFilter != null) {
            mBeautyFilter.Destroy();
            mBeautyFilter = null;
        }
        if (mFaceReshapeFilter != null) {
            mFaceReshapeFilter.Destroy();
            mFaceReshapeFilter = null;
        }
        if (mLipstickFilter != null) {
            mLipstickFilter.Destroy();
            mLipstickFilter = null;
        }
        if (mBlusherFilter != null) {
            mBlusherFilter.Destroy();
            mBlusherFilter = null;
        }
        if (mWhiteBalanceFilter != null) {
            mWhiteBalanceFilter.Destroy();
            mWhiteBalanceFilter = null;
        }
        if (mSaturationFilter != null) {
            mSaturationFilter.Destroy();
            mSaturationFilter = null;
        }
        if (mSourceRawData != null) {
            mSourceRawData.Destroy();
            mSourceRawData = null;
        }
        if (mCaptureSinkRawData != null) {
            mCaptureSinkRawData.Destroy();
            mCaptureSinkRawData = null;
        }
        if (mSinkSurface != null) {
            mSinkSurface.Destroy();
            mSinkSurface = null;
        }
        if (mCurrentOutputSurface != null) {
            mCurrentOutputSurface.release();
            mCurrentOutputSurface = null;
        }
        if (mCaptureExecutor != null) {
            mCaptureExecutor.shutdownNow();
            mCaptureExecutor = null;
        }
        super.onDestroy();
    }
}
