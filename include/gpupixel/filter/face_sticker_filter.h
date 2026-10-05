/*
 * GPUPixel
 *
 * Created by PixPark on 2021/6/24.
 * Copyright © 2021 PixPark. All rights reserved.
 */

#pragma once

#include "gpupixel/filter/filter.h"
#include "gpupixel/source/source_image.h"

#include <chrono>
#include <mutex>
#include <string>
#include <vector>

namespace gpupixel {

/**
 * Common sticker anchor positions mapped to facial landmarks.
 */
enum StickerAnchor {
  kAnchorForehead = 0,    // 额头/猫耳朵/帽子/头饰 (Point 43 沿头部向上延伸)
  kAnchorEyes = 1,        // 眼睛/墨镜/眼眶 (两眼中心)
  kAnchorNose = 2,        // 鼻子/猪鼻/小丑红鼻头 (Point 46)
  kAnchorMouth = 3,       // 嘴部/胡子/奶嘴 (Point 87)
  kAnchorChin = 4,        // 下巴 (Point 16)
  kAnchorCheekLeft = 5,   // 左脸颊 (Point 109)
  kAnchorCheekRight = 6,  // 右脸颊 (Point 110)
  kAnchorCustom = 7       // 自定义关键点索引
};

/**
 * Representation of an individual sticker layer.
 */
struct GPUPIXEL_API StickerItem {
  std::string name;
  StickerAnchor anchor = kAnchorForehead;
  std::vector<std::shared_ptr<SourceImage>> frames;
  int fps = 25;
  float scale = 1.0f;               // Scale relative to face size (eye distance)
  float offset_x = 0.0f;            // Horizontal offset (-1.0 to 1.0, relative to face width)
  float offset_y = 0.0f;            // Vertical offset (-1.0 to 1.0, relative to face width)
  float rotation_offset_deg = 0.0f; // Rotation angle adjustment in degrees
  float alpha = 1.0f;               // Opacity [0.0, 1.0]
  bool loop = true;
  bool flip_y = false;
  int64_t start_time_ms = 0;

  // Custom anchor parameters (when anchor == kAnchorCustom)
  int custom_point_index1 = 43;
  int custom_point_index2 = -1;
  float custom_weight = 0.5f;
};

/**
 * FaceStickerFilter: Real-time 2D static & animated face sticker filter.
 */
class GPUPIXEL_API FaceStickerFilter : public Filter {
 public:
  static std::shared_ptr<FaceStickerFilter> Create();
  static std::shared_ptr<FaceStickerFilter> Create(
      const std::string& image_path,
      StickerAnchor anchor = kAnchorForehead);

  FaceStickerFilter();
  virtual ~FaceStickerFilter();

  virtual bool Init();
  virtual bool DoRender(bool update_sinks = true) override;

  // Set 106-point landmarks from FaceDetector (range [0, 1])
  void SetFaceLandmarks(const std::vector<float>& landmarks);

  // --- Convenience APIs for single sticker ---
  void SetStickerPath(const std::string& path);
  void SetStickerImage(std::shared_ptr<SourceImage> image);
  void SetStickerFrames(const std::vector<std::string>& frame_paths, int fps = 25);
  void SetStickerFrames(const std::vector<std::shared_ptr<SourceImage>>& frames, int fps = 25);
  void SetAnchor(StickerAnchor anchor);
  void SetScale(float scale);
  void SetOffset(float offset_x, float offset_y);
  void SetRotationOffset(float degrees);
  void SetAlpha(float alpha);
  void SetFlipY(bool flip_y);

  // --- Multi-sticker management APIs ---
  int AddSticker(const StickerItem& item);
  void RemoveSticker(int index);
  void ClearStickers();
  size_t GetStickerCount() const;
  StickerItem* GetSticker(int index);

 private:
  void RenderStickerItem(const StickerItem& item,
                         const std::vector<float>& face_landmarks,
                         size_t face_offset,
                         int fb_width,
                         int fb_height);

 private:
  std::vector<float> face_landmarks_;
  bool has_face_ = false;

  // Program for background copy
  GPUPixelGLProgram* filter_program2_ = nullptr;
  uint32_t filter_position_attribute2_ = 0;
  uint32_t filter_tex_coord_attribute2_ = 0;

  // Program for sticker quad rendering
  uint32_t sticker_tex_coord_attribute_ = 0;

  // Sticker items
  std::vector<StickerItem> stickers_;
  mutable std::mutex sticker_mutex_;
};

}  // namespace gpupixel
