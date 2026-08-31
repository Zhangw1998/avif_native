#include <avif/avif.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define AVIF_NATIVE_API __declspec(dllexport)
#else
#define AVIF_NATIVE_API __attribute__((visibility("default")))
#endif

#ifndef AVIF_NATIVE_HAS_DECODE
#define AVIF_NATIVE_HAS_DECODE 1
#endif
#ifndef AVIF_NATIVE_HAS_ENCODE
#define AVIF_NATIVE_HAS_ENCODE 1
#endif

#define AVIF_NATIVE_CAP_DECODE 1u
#define AVIF_NATIVE_CAP_ENCODE 2u

AVIF_NATIVE_API uint32_t avif_native_capabilities(void) {
  return (AVIF_NATIVE_HAS_DECODE ? AVIF_NATIVE_CAP_DECODE : 0u) |
         (AVIF_NATIVE_HAS_ENCODE ? AVIF_NATIVE_CAP_ENCODE : 0u);
}

typedef struct {
  avifDecoder* decoder;
  uint8_t* data;
} AvifNativeDecoder;

typedef struct {
  avifEncoder* encoder;
  uint32_t width;
  uint32_t height;
  int expected_frames;
  int added_frames;
  uint8_t* exif;
  size_t exif_size;
} AvifNativeEncoder;

static int avif_error(avifResult result) {
  return result == AVIF_RESULT_OK ? 0 : -((int)result);
}

static void decoder_free(AvifNativeDecoder* handle) {
  if (handle == NULL) return;
  if (handle->decoder != NULL) avifDecoderDestroy(handle->decoder);
  free(handle->data);
  free(handle);
}

AVIF_NATIVE_API int avif_native_decoder_create(
    const uint8_t* data, size_t size, AvifNativeDecoder** out_decoder,
    int* out_width, int* out_height, int* out_frame_count,
    double* out_duration_seconds, int* out_repetition_count) {
#if !AVIF_NATIVE_HAS_DECODE
  (void)data; (void)size; (void)out_width; (void)out_height;
  (void)out_frame_count; (void)out_duration_seconds; (void)out_repetition_count;
  if (out_decoder != NULL) *out_decoder = NULL;
  return avif_error(AVIF_RESULT_NOT_IMPLEMENTED);
#else
  if (data == NULL || size == 0 || out_decoder == NULL || out_width == NULL ||
      out_height == NULL || out_frame_count == NULL ||
      out_duration_seconds == NULL || out_repetition_count == NULL) {
    return avif_error(AVIF_RESULT_INVALID_ARGUMENT);
  }
  *out_decoder = NULL;

  AvifNativeDecoder* handle = calloc(1, sizeof(AvifNativeDecoder));
  if (handle == NULL) return avif_error(AVIF_RESULT_OUT_OF_MEMORY);
  handle->data = malloc(size);
  handle->decoder = avifDecoderCreate();
  if (handle->data == NULL || handle->decoder == NULL) {
    decoder_free(handle);
    return avif_error(AVIF_RESULT_OUT_OF_MEMORY);
  }
  memcpy(handle->data, data, size);

  avifResult result = avifDecoderSetIOMemory(handle->decoder, handle->data, size);
  if (result == AVIF_RESULT_OK) result = avifDecoderParse(handle->decoder);
  if (result != AVIF_RESULT_OK || handle->decoder->imageCount < 1) {
    decoder_free(handle);
    return avif_error(result == AVIF_RESULT_OK ? AVIF_RESULT_NO_CONTENT : result);
  }

  *out_width = handle->decoder->image->width;
  *out_height = handle->decoder->image->height;
  *out_frame_count = handle->decoder->imageCount;
  *out_duration_seconds = handle->decoder->duration;
  *out_repetition_count = handle->decoder->repetitionCount;
  *out_decoder = handle;
  return 0;
#endif
}

AVIF_NATIVE_API int avif_native_decoder_next(
    AvifNativeDecoder* handle, uint8_t** out_rgba, int* out_width,
    int* out_height, double* out_duration_seconds) {
#if !AVIF_NATIVE_HAS_DECODE
  (void)handle; (void)out_width; (void)out_height; (void)out_duration_seconds;
  if (out_rgba != NULL) *out_rgba = NULL;
  return avif_error(AVIF_RESULT_NOT_IMPLEMENTED);
#else
  if (handle == NULL || out_rgba == NULL || out_width == NULL ||
      out_height == NULL || out_duration_seconds == NULL) {
    return avif_error(AVIF_RESULT_INVALID_ARGUMENT);
  }
  *out_rgba = NULL;

  avifResult result = avifDecoderNextImage(handle->decoder);
  if (result != AVIF_RESULT_OK) return avif_error(result);

  avifRGBImage rgb;
  avifRGBImageSetDefaults(&rgb, handle->decoder->image);
  rgb.format = AVIF_RGB_FORMAT_RGBA;
  rgb.depth = 8;
  result = avifRGBImageAllocatePixels(&rgb);
  if (result != AVIF_RESULT_OK) return avif_error(result);

  result = avifImageYUVToRGB(handle->decoder->image, &rgb);
  if (result == AVIF_RESULT_OK) {
    const size_t row_size = (size_t)rgb.width * 4;
    if (rgb.height > SIZE_MAX / row_size) {
      result = AVIF_RESULT_OUT_OF_MEMORY;
    } else {
      uint8_t* pixels = malloc(row_size * rgb.height);
      if (pixels == NULL) {
        result = AVIF_RESULT_OUT_OF_MEMORY;
      } else {
        for (uint32_t y = 0; y < rgb.height; ++y) {
          memcpy(pixels + y * row_size, rgb.pixels + y * rgb.rowBytes, row_size);
        }
        *out_rgba = pixels;
        *out_width = rgb.width;
        *out_height = rgb.height;
        *out_duration_seconds = handle->decoder->imageTiming.duration;
      }
    }
  }
  avifRGBImageFreePixels(&rgb);
  return avif_error(result);
#endif
}

AVIF_NATIVE_API int avif_native_decoder_reset(AvifNativeDecoder* handle) {
#if AVIF_NATIVE_HAS_DECODE
  if (handle == NULL) return avif_error(AVIF_RESULT_INVALID_ARGUMENT);
  return avif_error(avifDecoderReset(handle->decoder));
#else
  (void)handle;
  return avif_error(AVIF_RESULT_NOT_IMPLEMENTED);
#endif
}

AVIF_NATIVE_API void avif_native_decoder_destroy(AvifNativeDecoder* handle) {
#if AVIF_NATIVE_HAS_DECODE
  decoder_free(handle);
#else
  (void)handle;
#endif
}

static void encoder_free(AvifNativeEncoder* handle) {
  if (handle == NULL) return;
  if (handle->encoder != NULL) avifEncoderDestroy(handle->encoder);
  free(handle->exif);
  free(handle);
}

AVIF_NATIVE_API int avif_native_encoder_create(
    int width, int height, int frame_count, int max_threads, int speed,
    uint64_t timescale, int min_quantizer, int max_quantizer,
    int min_quantizer_alpha, int max_quantizer_alpha, int repetition_count,
    const uint8_t* exif, size_t exif_size, AvifNativeEncoder** out_encoder) {
#if !AVIF_NATIVE_HAS_ENCODE
  (void)width; (void)height; (void)frame_count; (void)max_threads; (void)speed;
  (void)timescale; (void)min_quantizer; (void)max_quantizer;
  (void)min_quantizer_alpha; (void)max_quantizer_alpha;
  (void)repetition_count; (void)exif; (void)exif_size;
  if (out_encoder != NULL) *out_encoder = NULL;
  return avif_error(AVIF_RESULT_NOT_IMPLEMENTED);
#else
  if (width <= 0 || height <= 0 || frame_count <= 0 || max_threads <= 0 ||
      speed < 0 || speed > 10 || timescale == 0 || min_quantizer < 0 ||
      min_quantizer > max_quantizer || max_quantizer > 63 ||
      min_quantizer_alpha < 0 || min_quantizer_alpha > max_quantizer_alpha ||
      max_quantizer_alpha > 63 || repetition_count < -2 || out_encoder == NULL ||
      (exif_size > 0 && exif == NULL)) {
    return avif_error(AVIF_RESULT_INVALID_ARGUMENT);
  }
  *out_encoder = NULL;

  AvifNativeEncoder* handle = calloc(1, sizeof(AvifNativeEncoder));
  if (handle == NULL) return avif_error(AVIF_RESULT_OUT_OF_MEMORY);
  handle->encoder = avifEncoderCreate();
  if (handle->encoder == NULL) {
    encoder_free(handle);
    return avif_error(AVIF_RESULT_OUT_OF_MEMORY);
  }
  if (exif_size > 0) {
    handle->exif = malloc(exif_size);
    if (handle->exif == NULL) {
      encoder_free(handle);
      return avif_error(AVIF_RESULT_OUT_OF_MEMORY);
    }
    memcpy(handle->exif, exif, exif_size);
    handle->exif_size = exif_size;
  }

  handle->width = width;
  handle->height = height;
  handle->expected_frames = frame_count;
  handle->encoder->maxThreads = max_threads;
  handle->encoder->speed = speed;
  handle->encoder->timescale = timescale;
  handle->encoder->minQuantizer = min_quantizer;
  handle->encoder->maxQuantizer = max_quantizer;
  handle->encoder->minQuantizerAlpha = min_quantizer_alpha;
  handle->encoder->maxQuantizerAlpha = max_quantizer_alpha;
  handle->encoder->repetitionCount = repetition_count;
  *out_encoder = handle;
  return 0;
#endif
}

AVIF_NATIVE_API int avif_native_encoder_add_frame(
    AvifNativeEncoder* handle, const uint8_t* rgba, size_t rgba_size,
    uint64_t duration_in_timescales) {
#if !AVIF_NATIVE_HAS_ENCODE
  (void)handle; (void)rgba; (void)rgba_size; (void)duration_in_timescales;
  return avif_error(AVIF_RESULT_NOT_IMPLEMENTED);
#else
  if (handle == NULL || rgba == NULL ||
      handle->added_frames >= handle->expected_frames || handle->height == 0 ||
      handle->width > SIZE_MAX / handle->height / 4 ||
      rgba_size != (size_t)handle->width * handle->height * 4 ||
      (handle->expected_frames > 1 && duration_in_timescales == 0)) {
    return avif_error(AVIF_RESULT_INVALID_ARGUMENT);
  }

  avifImage* image = avifImageCreate(
      handle->width, handle->height, 8, AVIF_PIXEL_FORMAT_YUV444);
  if (image == NULL) return avif_error(AVIF_RESULT_OUT_OF_MEMORY);

  avifResult result = avifImageAllocatePlanes(image, AVIF_PLANES_YUV);
  if (result == AVIF_RESULT_OK) {
    avifRGBImage rgb;
    avifRGBImageSetDefaults(&rgb, image);
    rgb.format = AVIF_RGB_FORMAT_RGBA;
    rgb.depth = 8;
    rgb.pixels = (uint8_t*)rgba;
    rgb.rowBytes = handle->width * 4;

    result = avifImageRGBToYUV(image, &rgb);
    if (result == AVIF_RESULT_OK && handle->exif_size > 0) {
      result = avifImageSetMetadataExif(image, handle->exif, handle->exif_size);
    }
    if (result == AVIF_RESULT_OK) {
      const avifAddImageFlags flags = handle->expected_frames == 1
          ? AVIF_ADD_IMAGE_FLAG_SINGLE
          : AVIF_ADD_IMAGE_FLAG_NONE;
      result = avifEncoderAddImage(
          handle->encoder, image, duration_in_timescales, flags);
    }
  }
  avifImageDestroy(image);
  if (result == AVIF_RESULT_OK) ++handle->added_frames;
  return avif_error(result);
#endif
}

AVIF_NATIVE_API int avif_native_encoder_finish(
    AvifNativeEncoder* handle, uint8_t** out_data, size_t* out_size) {
#if !AVIF_NATIVE_HAS_ENCODE
  (void)handle; (void)out_size;
  if (out_data != NULL) *out_data = NULL;
  return avif_error(AVIF_RESULT_NOT_IMPLEMENTED);
#else
  if (handle == NULL || out_data == NULL || out_size == NULL ||
      handle->added_frames != handle->expected_frames) {
    return avif_error(AVIF_RESULT_INVALID_ARGUMENT);
  }
  *out_data = NULL;
  *out_size = 0;

  avifRWData output = {0};
  avifResult result = avifEncoderFinish(handle->encoder, &output);
  if (result == AVIF_RESULT_OK) {
    uint8_t* copy = malloc(output.size);
    if (copy == NULL) {
      result = AVIF_RESULT_OUT_OF_MEMORY;
    } else {
      memcpy(copy, output.data, output.size);
      *out_data = copy;
      *out_size = output.size;
    }
  }
  avifRWDataFree(&output);
  return avif_error(result);
#endif
}

AVIF_NATIVE_API void avif_native_encoder_destroy(AvifNativeEncoder* handle) {
#if AVIF_NATIVE_HAS_ENCODE
  encoder_free(handle);
#else
  (void)handle;
#endif
}

AVIF_NATIVE_API void avif_native_free(uint8_t* data) {
  free(data);
}
