/*
 * GPUPixel
 *
 * Created by PixPark on 2021/6/24.
 * Copyright © 2021 PixPark. All rights reserved.
 */

#include "gpupixel/filter/face_sticker_filter.h"
#include <algorithm>
#include <cmath>
#include "core/gpupixel_context.h"
#include "core/gpupixel_program.h"
#include "utils/logging.h"
#include "utils/util.h"

namespace gpupixel {

namespace {

struct Point2D {
  float x;
  float y;
};

const std::string kFaceStickerVertexShaderString = R"(
    attribute vec2 position;
    attribute vec2 inputTextureCoordinate;
    varying vec2 textureCoordinate;

    void main() {
      gl_Position = vec4(position, 0.0, 1.0);
      textureCoordinate = inputTextureCoordinate;
    }
)";

#if defined(GPUPIXEL_GLES_SHADER)
const std::string kFaceStickerFragmentShaderString = R"(
    precision mediump float;
    varying highp vec2 textureCoordinate;
    uniform sampler2D stickerTexture;
    uniform float alpha;

    void main() {
      vec4 color = texture2D(stickerTexture, textureCoordinate);
      gl_FragColor = vec4(color.rgb, color.a * alpha);
    }
)";
#elif defined(GPUPIXEL_GL_SHADER)
const std::string kFaceStickerFragmentShaderString = R"(
    varying vec2 textureCoordinate;
    uniform sampler2D stickerTexture;
    uniform float alpha;

    void main() {
      vec4 color = texture2D(stickerTexture, textureCoordinate);
      gl_FragColor = vec4(color.rgb, color.a * alpha);
    }
)";
#endif

}  // namespace

FaceStickerFilter::FaceStickerFilter() {}

FaceStickerFilter::~FaceStickerFilter() {
  if (filter_program2_) {
    delete filter_program2_;
    filter_program2_ = nullptr;
  }
}

std::shared_ptr<FaceStickerFilter> FaceStickerFilter::Create() {
  auto ret = std::shared_ptr<FaceStickerFilter>(new FaceStickerFilter());
  gpupixel::GPUPixelContext::GetInstance()->SyncRunWithContext([&] {
    if (ret && !ret->Init()) {
      ret.reset();
    }
  });
  return ret;
}

std::shared_ptr<FaceStickerFilter> FaceStickerFilter::Create(
    const std::string& image_path,
    StickerAnchor anchor) {
  auto ret = std::shared_ptr<FaceStickerFilter>(new FaceStickerFilter());
  gpupixel::GPUPixelContext::GetInstance()->SyncRunWithContext([&] {
    if (ret && ret->Init()) {
      ret->SetStickerPath(image_path);
      ret->SetAnchor(anchor);
    } else {
      ret.reset();
    }
  });
  return ret;
}

bool FaceStickerFilter::Init() {
  if (!Filter::InitWithShaderString(kFaceStickerVertexShaderString,
                                    kFaceStickerFragmentShaderString)) {
    return false;
  }

  filter_position_attribute_ = filter_program_->GetAttribLocation("position");
  sticker_tex_coord_attribute_ =
      filter_program_->GetAttribLocation("inputTextureCoordinate");

  // Base background pass
  filter_program2_ = GPUPixelGLProgram::CreateWithShaderString(
      kDefaultVertexShader, kDefaultFragmentShader);
  filter_position_attribute2_ = filter_program2_->GetAttribLocation("position");
  filter_tex_coord_attribute2_ =
      filter_program2_->GetAttribLocation("inputTextureCoordinate");

  // Properties registration
  std::vector<float> default_landmarks;
  RegisterProperty("face_landmark", default_landmarks,
                   "The face landmarks with range between 0 and 1.",
                   [this](std::vector<float>& val) { SetFaceLandmarks(val); });

  RegisterProperty("sticker_path", std::string(""),
                   "File path to single sticker PNG image.",
                   [this](std::string& val) { SetStickerPath(val); });

  RegisterProperty("anchor", 0,
                   "Anchor position (0: Forehead, 1: Eyes, 2: Nose, 3: Mouth, "
                   "4: Chin, 5: LeftCheek, 6: RightCheek).",
                   [this](int& val) {
                     SetAnchor(static_cast<StickerAnchor>(val));
                   });

  RegisterProperty("scale", 1.0f, "Sticker scale relative to face size.",
                   [this](float& val) { SetScale(val); });

  RegisterProperty("offset_x", 0.0f,
                   "Horizontal offset relative to eye distance.",
                   [this](float& val) {
                     float cur_y =
                         stickers_.empty() ? 0.0f : stickers_[0].offset_y;
                     SetOffset(val, cur_y);
                   });

  RegisterProperty("offset_y", 0.0f,
                   "Vertical offset relative to eye distance.",
                   [this](float& val) {
                     float cur_x =
                         stickers_.empty() ? 0.0f : stickers_[0].offset_x;
                     SetOffset(cur_x, val);
                   });

  RegisterProperty("alpha", 1.0f, "Sticker alpha between 0.0 and 1.0.",
                   [this](float& val) { SetAlpha(val); });

  return true;
}

void FaceStickerFilter::SetFaceLandmarks(const std::vector<float>& landmarks) {
  if (landmarks.empty()) {
    has_face_ = false;
    face_landmarks_.clear();
    return;
  }
  face_landmarks_ = landmarks;
  has_face_ = true;
}

void FaceStickerFilter::SetStickerPath(const std::string& path) {
  if (path.empty()) return;
  auto img = SourceImage::Create(path);
  SetStickerImage(img);
}

void FaceStickerFilter::SetStickerImage(std::shared_ptr<SourceImage> image) {
  if (stickers_.empty()) {
    StickerItem item;
    stickers_.push_back(item);
  }
  stickers_[0].frames.clear();
  if (image) {
    stickers_[0].frames.push_back(image);
  }
}

void FaceStickerFilter::SetStickerFrames(
    const std::vector<std::string>& frame_paths,
    int fps) {
  if (stickers_.empty()) {
    StickerItem item;
    stickers_.push_back(item);
  }
  stickers_[0].frames.clear();
  stickers_[0].fps = fps;
  stickers_[0].start_time_ms = 0;
  for (const auto& path : frame_paths) {
    auto img = SourceImage::Create(path);
    if (img) {
      stickers_[0].frames.push_back(img);
    }
  }
}

void FaceStickerFilter::SetStickerFrames(
    const std::vector<std::shared_ptr<SourceImage>>& frames,
    int fps) {
  if (stickers_.empty()) {
    StickerItem item;
    stickers_.push_back(item);
  }
  stickers_[0].frames = frames;
  stickers_[0].fps = fps;
  stickers_[0].start_time_ms = 0;
}

void FaceStickerFilter::SetAnchor(StickerAnchor anchor) {
  if (stickers_.empty()) {
    StickerItem item;
    stickers_.push_back(item);
  }
  stickers_[0].anchor = anchor;
}

void FaceStickerFilter::SetScale(float scale) {
  if (stickers_.empty()) {
    StickerItem item;
    stickers_.push_back(item);
  }
  stickers_[0].scale = scale;
}

void FaceStickerFilter::SetOffset(float offset_x, float offset_y) {
  if (stickers_.empty()) {
    StickerItem item;
    stickers_.push_back(item);
  }
  stickers_[0].offset_x = offset_x;
  stickers_[0].offset_y = offset_y;
}

void FaceStickerFilter::SetRotationOffset(float degrees) {
  if (stickers_.empty()) {
    StickerItem item;
    stickers_.push_back(item);
  }
  stickers_[0].rotation_offset_deg = degrees;
}

void FaceStickerFilter::SetAlpha(float alpha) {
  if (stickers_.empty()) {
    StickerItem item;
    stickers_.push_back(item);
  }
  stickers_[0].alpha = alpha;
}

void FaceStickerFilter::SetFlipY(bool flip_y) {
  if (stickers_.empty()) {
    StickerItem item;
    stickers_.push_back(item);
  }
  stickers_[0].flip_y = flip_y;
}

int FaceStickerFilter::AddSticker(const StickerItem& item) {
  stickers_.push_back(item);
  return static_cast<int>(stickers_.size()) - 1;
}

void FaceStickerFilter::RemoveSticker(int index) {
  if (index >= 0 && index < static_cast<int>(stickers_.size())) {
    stickers_.erase(stickers_.begin() + index);
  }
}

void FaceStickerFilter::ClearStickers() {
  stickers_.clear();
}

size_t FaceStickerFilter::GetStickerCount() const {
  return stickers_.size();
}

StickerItem* FaceStickerFilter::GetSticker(int index) {
  if (index >= 0 && index < static_cast<int>(stickers_.size())) {
    return &stickers_[index];
  }
  return nullptr;
}

bool FaceStickerFilter::DoRender(bool update_sinks) {
  static const float imageVertices[] = {
      -1.0f, -1.0f, 1.0f, -1.0f, -1.0f, 1.0f, 1.0f, 1.0f,
  };

  framebuffer_->Activate();

  // 1. Render base image to framebuffer
  GPUPixelContext::GetInstance()->SetActiveGlProgram(filter_program2_);
  GL_CALL(glClearColor(background_color_.r, background_color_.g,
                       background_color_.b, background_color_.a));
  GL_CALL(glClear(GL_COLOR_BUFFER_BIT));

  GL_CALL(glActiveTexture(GL_TEXTURE4));
  GL_CALL(glBindTexture(GL_TEXTURE_2D,
                        input_framebuffers_[0].frame_buffer->GetTexture()));
  filter_program2_->SetUniformValue("inputImageTexture", 4);

  GL_CALL(glEnableVertexAttribArray(filter_position_attribute2_));
  GL_CALL(glVertexAttribPointer(filter_position_attribute2_, 2, GL_FLOAT, 0, 0,
                                imageVertices));
  GL_CALL(glEnableVertexAttribArray(filter_tex_coord_attribute2_));
  GL_CALL(glVertexAttribPointer(filter_tex_coord_attribute2_, 2, GL_FLOAT, 0, 0,
                                GetTextureCoordinate(NoRotation)));
  GL_CALL(glDrawArrays(GL_TRIANGLE_STRIP, 0, 4));

  // 2. Render stickers if face is detected
  if (has_face_ && !stickers_.empty() && face_landmarks_.size() >= 212) {
    GPUPixelContext::GetInstance()->SetActiveGlProgram(filter_program_);
    GL_CALL(glEnable(GL_BLEND));
    GL_CALL(glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA));

    int fb_width = framebuffer_->GetWidth();
    int fb_height = framebuffer_->GetHeight();

    size_t face_count = face_landmarks_.size() / 212;
    for (size_t f = 0; f < face_count; ++f) {
      size_t face_offset = f * 212;
      for (const auto& item : stickers_) {
        RenderStickerItem(item, face_landmarks_, face_offset, fb_width,
                          fb_height);
      }
    }

    GL_CALL(glDisable(GL_BLEND));
  }

  framebuffer_->Deactivate();
  return Source::DoRender(update_sinks);
}

void FaceStickerFilter::RenderStickerItem(
    const StickerItem& item,
    const std::vector<float>& face_landmarks,
    size_t face_offset,
    int fb_width,
    int fb_height) {
  if (item.frames.empty() || item.alpha <= 0.001f) {
    return;
  }

  // Animation frame calculation
  size_t frame_index = 0;
  if (item.frames.size() > 1 && item.fps > 0) {
    int64_t now = std::chrono::duration_cast<std::chrono::milliseconds>(
                      std::chrono::steady_clock::now().time_since_epoch())
                      .count();
    int64_t start_time = item.start_time_ms;
    if (start_time == 0) {
      start_time = now;
    }
    int64_t elapsed = now - start_time;
    int frame_dur = 1000 / item.fps;
    if (frame_dur <= 0) frame_dur = 40;
    if (item.loop) {
      frame_index = (elapsed / frame_dur) % item.frames.size();
    } else {
      frame_index =
          std::min((size_t)(elapsed / frame_dur), item.frames.size() - 1);
    }
  }

  auto current_frame = item.frames[frame_index];
  if (!current_frame || !current_frame->GetFramebuffer()) {
    return;
  }

  int tex_w = current_frame->GetWidth();
  int tex_h = current_frame->GetHeight();
  if (tex_w <= 0 || tex_h <= 0) {
    return;
  }

  auto get_pt = [&](int idx) -> Point2D {
    return Point2D{
        face_landmarks[face_offset + idx * 2 + 0] * fb_width,
        face_landmarks[face_offset + idx * 2 + 1] * fb_height,
    };
  };

  Point2D p_left_eye = get_pt(52);   // outer left eye
  Point2D p_right_eye = get_pt(61);  // outer right eye
  Point2D p_left_pupil = get_pt(74);
  Point2D p_right_pupil = get_pt(77);
  Point2D p_forehead = get_pt(43);   // glabella
  Point2D p_nose = get_pt(46);       // nose tip
  Point2D p_mouth = get_pt(87);      // upper lip
  Point2D p_chin = get_pt(16);       // chin
  Point2D p_cheek_left = get_pt(109);
  Point2D p_cheek_right = get_pt(110);

  float dx = p_right_eye.x - p_left_eye.x;
  float dy = p_right_eye.y - p_left_eye.y;
  float d_eye = std::sqrt(dx * dx + dy * dy);
  if (d_eye < 1.0f) {
    return;
  }

  // Vector from chin to forehead points directly towards the top of the head in image coordinates
  float head_dx = p_forehead.x - p_chin.x;
  float head_dy = p_forehead.y - p_chin.y;
  float head_len = std::sqrt(head_dx * head_dx + head_dy * head_dy);

  Point2D head_up = {0.0f, -1.0f};
  if (head_len > 1.0f) {
    head_up = {head_dx / head_len, head_dy / head_len};
  }
  // Perpendicular vector pointing to viewer's right (person's left)
  Point2D head_right = {-head_up.y, head_up.x};

  // Apply optional rotation offset
  float rot_rad = item.rotation_offset_deg * 3.1415926535f / 180.0f;
  float cos_r = std::cos(rot_rad);
  float sin_r = std::sin(rot_rad);
  Point2D right_vec = {
      head_right.x * cos_r - head_up.x * sin_r,
      head_right.y * cos_r - head_up.y * sin_r,
  };
  Point2D up_vec = {
      head_right.x * sin_r + head_up.x * cos_r,
      head_right.y * sin_r + head_up.y * cos_r,
  };

  Point2D anchor_center = p_forehead;
  switch (item.anchor) {
    case kAnchorForehead:
      anchor_center = {
          p_forehead.x + up_vec.x * (d_eye * 0.75f),
          p_forehead.y + up_vec.y * (d_eye * 0.75f),
      };
      break;
    case kAnchorEyes:
      anchor_center = {
          (p_left_pupil.x + p_right_pupil.x) * 0.5f,
          (p_left_pupil.y + p_right_pupil.y) * 0.5f,
      };
      break;
    case kAnchorNose:
      anchor_center = p_nose;
      break;
    case kAnchorMouth:
      anchor_center = p_mouth;
      break;
    case kAnchorChin:
      anchor_center = p_chin;
      break;
    case kAnchorCheekLeft:
      anchor_center = p_cheek_left;
      break;
    case kAnchorCheekRight:
      anchor_center = p_cheek_right;
      break;
    case kAnchorCustom:
      if (item.custom_point_index2 >= 0 && item.custom_point_index2 < 106) {
        Point2D cp1 = get_pt(item.custom_point_index1);
        Point2D cp2 = get_pt(item.custom_point_index2);
        anchor_center = {
            cp1.x * (1.0f - item.custom_weight) + cp2.x * item.custom_weight,
            cp1.y * (1.0f - item.custom_weight) + cp2.y * item.custom_weight,
        };
      } else if (item.custom_point_index1 >= 0 &&
                 item.custom_point_index1 < 106) {
        anchor_center = get_pt(item.custom_point_index1);
      }
      break;
  }

  // Apply relative offset
  Point2D final_center = {
      anchor_center.x + right_vec.x * (d_eye * item.offset_x) +
          up_vec.x * (d_eye * item.offset_y),
      anchor_center.y + right_vec.y * (d_eye * item.offset_x) +
          up_vec.y * (d_eye * item.offset_y),
  };

  float aspect = static_cast<float>(tex_h) / static_cast<float>(tex_w);
  float sticker_w = d_eye * 2.0f * item.scale;
  float sticker_h = sticker_w * aspect;

  float hw = sticker_w * 0.5f;
  float hh = sticker_h * 0.5f;

  Point2D p_tl = {
      final_center.x - right_vec.x * hw + up_vec.x * hh,
      final_center.y - right_vec.y * hw + up_vec.y * hh,
  };
  Point2D p_tr = {
      final_center.x + right_vec.x * hw + up_vec.x * hh,
      final_center.y + right_vec.y * hw + up_vec.y * hh,
  };
  Point2D p_bl = {
      final_center.x - right_vec.x * hw - up_vec.x * hh,
      final_center.y - right_vec.y * hw - up_vec.y * hh,
  };
  Point2D p_br = {
      final_center.x + right_vec.x * hw - up_vec.x * hh,
      final_center.y + right_vec.y * hw - up_vec.y * hh,
  };

  // Convert image coordinates [0..fb_width, 0..fb_height] to GPUPixel FBO NDC [-1..1, -1..1]
  // In GPUPixel's internal FBO pipeline, NDC y = -1.0 corresponds to image top, and y = +1.0 corresponds to image bottom.
  // The display sink (SinkSurface / SinkRawData) performs the final Y-flip when presenting on screen.
  auto to_ndc = [&](const Point2D& p) -> Point2D {
    return Point2D{
        (p.x / fb_width) * 2.0f - 1.0f,
        (p.y / fb_height) * 2.0f - 1.0f,
    };
  };

  Point2D ndc_bl = to_ndc(p_bl);
  Point2D ndc_br = to_ndc(p_br);
  Point2D ndc_tl = to_ndc(p_tl);
  Point2D ndc_tr = to_ndc(p_tr);

  float quadVertices[8] = {
      ndc_bl.x, ndc_bl.y, ndc_br.x, ndc_br.y,
      ndc_tl.x, ndc_tl.y, ndc_tr.x, ndc_tr.y,
  };

  float texCoords[8];
  if (!item.flip_y) {
    texCoords[0] = 0.0f;
    texCoords[1] = 1.0f;  // BL
    texCoords[2] = 1.0f;
    texCoords[3] = 1.0f;  // BR
    texCoords[4] = 0.0f;
    texCoords[5] = 0.0f;  // TL
    texCoords[6] = 1.0f;
    texCoords[7] = 0.0f;  // TR
  } else {
    texCoords[0] = 0.0f;
    texCoords[1] = 0.0f;  // BL
    texCoords[2] = 1.0f;
    texCoords[3] = 0.0f;  // BR
    texCoords[4] = 0.0f;
    texCoords[5] = 1.0f;  // TL
    texCoords[6] = 1.0f;
    texCoords[7] = 1.0f;  // TR
  }

  GL_CALL(glActiveTexture(GL_TEXTURE3));
  GL_CALL(glBindTexture(GL_TEXTURE_2D,
                        current_frame->GetFramebuffer()->GetTexture()));
  filter_program_->SetUniformValue("stickerTexture", 3);
  filter_program_->SetUniformValue("alpha", item.alpha);

  GL_CALL(glEnableVertexAttribArray(filter_position_attribute_));
  GL_CALL(glVertexAttribPointer(filter_position_attribute_, 2, GL_FLOAT, 0, 0,
                                quadVertices));

  GL_CALL(glEnableVertexAttribArray(sticker_tex_coord_attribute_));
  GL_CALL(glVertexAttribPointer(sticker_tex_coord_attribute_, 2, GL_FLOAT, 0, 0,
                                texCoords));

  GL_CALL(glDrawArrays(GL_TRIANGLE_STRIP, 0, 4));
}

}  // namespace gpupixel
