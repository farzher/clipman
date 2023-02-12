libwebp :: #library,no_dll "windows/libwebp";

WebPDecodeRGBA :: (data: *u8, data_size: u32, width: *s32, height: *s32) -> *u8 #foreign libwebp;
WebPDecodeRGB  :: (data: *u8, data_size: u32, width: *s32, height: *s32) -> *u8 #foreign libwebp;
WebPEncodeRGBA :: (rgba: *u8, width: s32, height: s32, stride: s32, quality_factor: float, output: **u8) -> u32 #foreign libwebp;
WebPEncodeRGB  :: (rgba: *u8, width: s32, height: s32, stride: s32, quality_factor: float, output: **u8) -> u32 #foreign libwebp;
WebPFree       :: (data: *void) #foreign libwebp;
