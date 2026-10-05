// logging.h
#pragma once

#ifdef GPUPIXEL_EXTERNAL_CODE
#include "base/logging.h"
#else
#include <iostream>
#include <sstream>
#endif

#if defined(__ANDROID__) || defined(GPUPIXEL_ANDROID)
#include <android/log.h>
#endif

#ifndef GPUPIXEL_EXTERNAL_CODE
template <typename... Args>
std::string gpupixel_format(const std::string& fmt, Args... args) {
  std::ostringstream oss;
  size_t index = 0;
  ((oss << (index++ > 0 ? " " : "") << args), ...);
  return fmt.substr(0, fmt.find("{}")) + oss.str() +
         fmt.substr(fmt.find("{}") + 2);
}

// clang-format off
#define LOG_TRACE(...)                                                                \
  do {                                                                                \
  } while (0)

#if defined(__ANDROID__) || defined(GPUPIXEL_ANDROID)
#define LOG_DEBUG(...)                                                                \
  do {                                                                                \
    __android_log_print(ANDROID_LOG_DEBUG, "GPUPixelNative", "%s", gpupixel_format(__VA_ARGS__).c_str()); \
  } while (0)

#define LOG_INFO(...)                                                                 \
  do {                                                                                \
    __android_log_print(ANDROID_LOG_INFO, "GPUPixelNative", "%s", gpupixel_format(__VA_ARGS__).c_str()); \
  } while (0)

#define LOG_WARN(...)                                                                 \
  do {                                                                                \
    __android_log_print(ANDROID_LOG_WARN, "GPUPixelNative", "%s", gpupixel_format(__VA_ARGS__).c_str()); \
  } while (0)

#define LOG_ERROR(...)                                                                \
  do {                                                                                \
    __android_log_print(ANDROID_LOG_ERROR, "GPUPixelNative", "%s", gpupixel_format(__VA_ARGS__).c_str()); \
  } while (0)

#define LOG_CRITICAL(...)                                                             \
  do {                                                                                \
    __android_log_print(ANDROID_LOG_FATAL, "GPUPixelNative", "%s", gpupixel_format(__VA_ARGS__).c_str()); \
  } while (0)
#else
#define LOG_DEBUG(...)                                                                \
  do {                                                                                \
    std::cout << "[GPUPixel][ DEBUG ] " << gpupixel_format(__VA_ARGS__) << std::endl; \
  } while (0)

#define LOG_INFO(...)                                                                 \
  do {                                                                                \
    std::cout << "[GPUPixel][ INFO  ] " << gpupixel_format(__VA_ARGS__) << std::endl; \
  } while (0)

#define LOG_WARN(...)                                                                 \
  do {                                                                                \
    std::cout << "[GPUPixel][ WARN  ] " << gpupixel_format(__VA_ARGS__) << std::endl; \
  } while (0)

#define LOG_ERROR(...)                                                                \
  do {                                                                                \
    std::cout << "[GPUPixel][ERROR  ] " << gpupixel_format(__VA_ARGS__) << std::endl; \
  } while (0)

#define LOG_CRITICAL(...)                                                             \
  do {                                                                                \
    std::cout << "[GPUPixel][ CRIT ] " << gpupixel_format(__VA_ARGS__) << std::endl;  \
  } while (0)
#endif
// clang-format on
#endif
