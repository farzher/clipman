USE_DSA :: false;  // @Cleanup: Remove?

//
// Init stuff:
//

backend_init :: (window: Window_Type,
                 window_width: s32, window_height: s32,
                 render_width: s32, render_height: s32,
                 windowed: bool, vsync: bool) {
    gl_create_context(window, MINIMUM_GL_MAJOR_VERSION, MINIMUM_GL_MINOR_VERSION);
    DumpGLErrors("context");

    gl_load(*gl);
    //gl_enable_debug_output();
    gl_enable_debug_output(break_on_error = true);

    glGenVertexArrays(1, *opengl_is_stupid_vao);
    glGenBuffers(1, *immediate_vbo);
    if !vsync  wglSwapIntervalEXT(0);


    backend_init_shaders();

    CheckInit();  // Set up context.immediate_state.
    state.window_width  = window_width;
    state.window_height = window_height;
    state.render_width  = render_width;
    state.render_height = render_height;
}

#scope_module

opengl_is_stupid_vao: GLuint;
immediate_vbo: GLuint;

is_supported :: (tf: Texture_Format) -> bool {
    return get_ogl_format(tf) != GL_INVALID_ENUM;
}

#scope_file

MINIMUM_GL_MAJOR_VERSION :: 3;
MINIMUM_GL_MINOR_VERSION :: 3;


//
// Shader stuff:
//

#scope_export

Shader_Platform :: struct {
    gl_handle: GLuint;

    position_loc:      GLint = -1;
    color_scale_loc:   GLint = -1;
    normal_loc:        GLint = -1;
    tangent_loc:       GLint = -1;
    uv_0_loc:          GLint = -1;
    uv_1_loc:          GLint = -1;

    diffuse_texture_loc: GLint = -1;

    alpha_blend := false;
}

set_parameter :: (shader: *Shader, name: *u8, m: Matrix4) {
    loc := glGetUniformLocation(shader.gl_handle, name);
    if loc < 0   log_error("Unknown parameter: '%'\n", to_string(name));
    if loc >= 0  glUniformMatrix4fv(loc, 1, GL_TRUE, *m._11);
}

clear_render_target :: (r: float, g: float, b: float, a: float) {
    glClearColor(r, g, b, a);
    glClear(GL_COLOR_BUFFER_BIT);
}

swap_buffers :: (window: Window_Type) {
    CheckInit();
    if state.current_shader immediate_flush();

    #if OS == .WINDOWS {
        dc := GetDC(window);
        SwapBuffers(dc);
    } else {
        X11 :: #import "X11";

        //
        // I think calling glXSwapBuffers is technically illegal unless we create a glXWindow that is a child of 'win'
        // and call SwapBuffers on that. But it appears to work for now... -jblow, 27 February 2021.
        X11.glXSwapBuffers(X11.x_global_display, window);
    }
}

#scope_module

backend_init_shaders :: () {
    shader_color.gl_handle   = get_shader_program(SHADER_COLOR);
    shader_color.alpha_blend = false;

    shader_color_with_blend.gl_handle   = shader_color.gl_handle;
    shader_color_with_blend.alpha_blend = true;

    shader_text.gl_handle   = get_shader_program(SHADER_TEXT);
    shader_text.alpha_blend = true;

    shader_sprite.gl_handle   = get_shader_program(SHADER_SPRITE);
    shader_sprite.alpha_blend = true;
}

#scope_file

//
//
// Shaders Here!
//
//
SHADER_TEXT :: #string END

OUT_IN vec2 TextureCoords;
OUT_IN vec4 iterated_color;

#ifdef VERTEX_SHADER
in vec4 vert_position;
in vec4 vert_color;
in vec2 vert_uv0;

uniform mat4 projection;

void main() {
    gl_Position     = projection * vec4(vert_position.xy, 0.0, 1.0);
    iterated_color  = vert_color;
    TextureCoords   = vert_uv0;
}
#endif // VERTEX_SHADER

#ifdef FRAGMENT_SHADER
out vec4 color;

uniform sampler2D text_sampler;
uniform vec4 text_color;

void main () {
    vec4 sample = texture(text_sampler, TextureCoords);
    color = vec4(iterated_color.xyz, sample.a * iterated_color.a); // text_color * sample;
    if (sample.a < .3)  discard;
}
#endif // FRAGMENT_SHADER
END


SHADER_COLOR :: #string END
OUT_IN vec4 iterated_color;

#ifdef VERTEX_SHADER
in vec4 vert_position;
in vec4 vert_color;

uniform mat4 projection;

void main() {
    gl_Position = projection * vec4(vert_position.xy, 0.0, 1.0);
    iterated_color    = vert_color;
}
#endif // VERTEX_SHADER

#ifdef FRAGMENT_SHADER
out vec4 color;

void main () {
    color = iterated_color;
}
#endif // FRAGMENT_SHADER
END


// @Cleanup:
// shader_sprite is 1-v from shader_text. Do we pack the text texture upside down,
// or what?
SHADER_SPRITE :: #string END
OUT_IN vec2 TexCoords;
OUT_IN vec4 iterated_color;

#ifdef VERTEX_SHADER
in vec4 vert_position;
in vec4 vert_color;
in vec2 vert_uv0;

uniform mat4 projection;

void main() {
    TexCoords = vec2(vert_uv0.x, 1-vert_uv0.y);
    gl_Position = projection * vec4(vert_position.xy, 0.0, 1.0);
    iterated_color = vert_color;
}
#endif // VERTEX_SHADER

#ifdef FRAGMENT_SHADER
out vec4 color;

uniform sampler2D diffuse_texture;

void main () {
    vec4 color_tex = iterated_color * texture(diffuse_texture, TexCoords);
    if (color_tex.a < 0.1) discard;

    color = color_tex;
}
#endif // FRAGMENT_SHADER
END


get_shader_program :: (shader_text: string) -> GLuint {
    LOG_BUFFER_SIZE :: 512;

    make_shader_object :: (shader: string, prefix: string, shader_type : GLenum) -> GLuint {
        shader_object := glCreateShader(shader_type);

        //shader_str := temp_c_string(shader);
        shaders: [2] *u8;
        lengths: [2] s32;

        shaders[0] = prefix.data;
        shaders[1] = shader.data;
        lengths[0] = xx prefix.count;
        lengths[1] = xx shader.count;

        glShaderSource(shader_object, 2, shaders.data, lengths.data);

        glCompileShader(shader_object);

        success : GLint;
        glGetShaderiv(shader_object, GL_COMPILE_STATUS, *success);

        if !success then {
            log_data: [LOG_BUFFER_SIZE] u8;
            glGetShaderInfoLog(shader_object, log_data.count, null, log_data.data);
            log("%", to_string(log_data.data), flags=.ERROR);
            return 0;
        }

        return shader_object;
    }

    PREFIX_V :: #string END
    #version 330 core
    #define VERTEX_SHADER
    #define OUT_IN out
    END

    PREFIX_F :: #string END
    #version 330 core
    #define FRAGMENT_SHADER
    #define OUT_IN in
    END

    shader_v := make_shader_object(shader_text, PREFIX_V, GL_VERTEX_SHADER);
    shader_f := make_shader_object(shader_text, PREFIX_F, GL_FRAGMENT_SHADER);
    shader_p := glCreateProgram();

    glAttachShader(shader_p, shader_v);
    glAttachShader(shader_p, shader_f);
    glLinkProgram(shader_p);

    success : GLint = 0;
    glGetProgramiv(shader_p, GL_LINK_STATUS, *success);

    if !success then {
        log_data: [LOG_BUFFER_SIZE] u8;
        glGetProgramInfoLog(shader_p, log_data.count, null, log_data.data);
        log("%", to_string(log_data.data), flags=.ERROR);
        return 0;
    }

    glDeleteShader(shader_v);
    glDeleteShader(shader_f);

    return shader_p;
}


#scope_export
draw_generated_quads :: (font: *Dynamic_Font, color := Vector4.{1, 1, 1, 1}) {
    CheckInit();
    quads := font.current_quads;

    if state.current_shader immediate_flush();

    set_shader_for_text();
    immediate_begin();

    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glEnable(GL_BLEND);
    glEnable(GL_TEXTURE_2D);

    draw_letter_quad :: (font: *Dynamic_Font, quad: Font_Quad, color: Vector4) {

/*
        // @Robustness: These assume our coordinates are in screenspace...
        if quad.x1 < 0 return;
        if quad.x0 > cast(float) render_target_width return;
        if quad.y1 < 0 return;
        if quad.y0 > cast(float) render_target_height return;
*/
        page := quad.glyph.page;

        if page.bitmap_data.width  <= 1 return;
        if page.bitmap_data.height <= 1 return;

        // @Speed: Get rid of these silly make_vector2s.
        using quad;
        uv0 := make_vector2(u0, v0);
        uv1 := make_vector2(u1, v0);
        uv2 := make_vector2(u1, v1);
        uv3 := make_vector2(u0, v1);

        immediate_quad(p0, p1, p2, p3, color, uv0, uv1, uv2, uv3);
    }

    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, 0);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    last_texture: s64 = -1;

    glBegin(GL_TRIANGLES);

    for quad, i: quads {
        page := quad.glyph.page;
        map  := *page.texture;

        if page.dirty {
            page.dirty = false;
            texture_load_from_bitmap(map, page.bitmap_data);
        }

        if map.gl_handle != last_texture {
            immediate_flush();
            handle := map.gl_handle;
            last_texture = handle;
            glEnd();

            shader := state.current_shader;
            loc := glGetUniformLocation(shader.gl_handle, "text_sampler");
            if loc < 0  log_error("Unable to find text_sampler in shader_text!");
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, handle);  // Bind handle to slot 0.
            glUniform1i(loc, 0);

            glBegin(GL_TRIANGLES);  // @Speed!
        }

        draw_letter_quad(font, quad, color);
    }

    immediate_flush();

    glEnd();
    glDisable(GL_BLEND);
    glDisable(GL_TEXTURE_2D);
}

#scope_module

Texture_Platform :: struct {
    gl_handle: GLuint;
}

deinit :: (texture: *Texture) {
    handle := texture.gl_handle;
    if !handle  return;

    /* @Incomplete: Decide what to do here that is simple.

    gl_target := texture.gl_target;
    if gl_target == GL_RENDERBUFFER {
        glDeleteRenderbuffers(1, *handle);
    } else {
        assert(gl_target == GL_TEXTURE_2D || gl_target == GL_TEXTURE_3D || gl_target == GL_TEXTURE_CUBE_MAP || gl_target == GL_TEXTURE_2D_ARRAY || gl_target == GL_TEXTURE_CUBE_MAP_ARRAY || gl_target == GL_TEXTURE_BUFFER);
        glDeleteTextures(1, *handle);
    }
*/

    texture.gl_handle = 0;
//    texture.resource_size = 0;
}

get_ogl_format :: (tf: Texture_Format, srgb:=false) -> (format:GLenum, src_format:GLenum=GL_INVALID_ENUM, src_type:GLenum=GL_INVALID_ENUM, compressed:=false) {
    using Texture_Format;

    format : GLenum;

    if tf == {
        case R8;
            assert(srgb == false);
            return GL_R8, src_format = GL_RED, src_type = GL_UNSIGNED_BYTE;
        case RG8;
            assert(srgb == false);
            return GL_RG8, src_format = GL_RG, src_type = GL_UNSIGNED_BYTE;
        case RGB8;
            if srgb format = GL_SRGB8;
            else format = GL_RGB8;
            return format, src_format = GL_RGB, src_type = GL_UNSIGNED_BYTE;
        case RGBA8;
            if srgb format = GL_SRGB8_ALPHA8;
            else format = GL_RGBA8;
            return format, src_format = GL_RGBA, src_type = GL_UNSIGNED_BYTE;
        case BGRA8;
            if srgb format = GL_SRGB8_ALPHA8;
            else format = GL_RGBA8;
            return format, src_format = GL_BGRA, src_type = GL_UNSIGNED_BYTE;
        case B5G6R5;
            if srgb format = GL_SRGB;
            else format = GL_RGB;
            return format, src_format = GL_BGR, src_type = GL_UNSIGNED_SHORT_5_6_5;
        case RGB10A2;
            assert(srgb == false);
            return GL_RGB10_A2, src_format = GL_RGBA, src_type = GL_UNSIGNED_INT_10_10_10_2;
        case R16;
            assert(srgb == false);
            return GL_R16, src_format = GL_RED, src_type = GL_UNSIGNED_SHORT;

        case R16F;
            assert(srgb == false);
            return GL_R16F, src_format = GL_RED, src_type = GL_HALF_FLOAT;
        case RG16F;
            assert(srgb == false);
            return GL_RG16F, src_format = GL_RG, src_type = GL_HALF_FLOAT;
        case RGBA16F;
            assert(srgb == false);
            return GL_RGBA16F, src_format = GL_RGBA, src_type = GL_HALF_FLOAT;
        case R32F;
            assert(srgb == false);
            return GL_R32F, src_format = GL_RED, src_type = GL_FLOAT;
        case RG32F;
            assert(srgb == false);
            return GL_RG32F, src_format = GL_RG, src_type = GL_FLOAT;
        case RGBA32F;
            assert(srgb == false);
            return GL_RGBA32F, src_format = GL_RGBA, src_type = GL_FLOAT;
        case RG11B10F;
            assert(srgb == false);
            return GL_R11F_G11F_B10F, src_format = GL_RGB, src_type = GL_UNSIGNED_INT_10F_11F_11F_REV;  // @@ Not tested.
        case RGB9E5F;
            assert(srgb == false);
            return GL_RGB9_E5, src_format = GL_RGB, src_type = GL_UNSIGNED_INT_5_9_9_9_REV; // @@ Not tested.

        case R16I;
            assert(srgb == false);
            return GL_R16I, src_format = GL_RED, src_type = GL_SHORT;
        case RG16I;
            assert(srgb == false);
            return GL_RG16I, src_format = GL_RG, src_type = GL_SHORT;
        case RGBA16I;
            assert(srgb == false);
            return GL_RGBA16I, src_format = GL_RGBA, src_type = GL_SHORT;
        case R32I;
            assert(srgb == false);
            return GL_R32I, src_format = GL_RED, src_type = GL_INT;
        case RG32I;
            assert(srgb == false);
            return GL_RG32I, src_format = GL_RG, src_type = GL_INT;
        case RGBA32I;
            assert(srgb == false);
            return GL_RGBA32I, src_format = GL_RGBA, src_type = GL_INT;

        case BC1;
            if srgb format = GL_COMPRESSED_SRGB_S3TC_DXT1_EXT;
            else format = GL_COMPRESSED_RGB_S3TC_DXT1_EXT;
            return format, compressed = true;
        case BC3;
            if srgb format = GL_COMPRESSED_SRGB_ALPHA_S3TC_DXT5_EXT;
            else format = GL_COMPRESSED_RGBA_S3TC_DXT5_EXT;
            return format, compressed = true;
        case BC4;
            assert(srgb == false);
            return GL_COMPRESSED_RED_RGTC1, compressed = true;
        case BC5;
            assert(srgb == false);
            return GL_COMPRESSED_RG_RGTC2, compressed = true;
        case BC6;
            assert(srgb == false);
            return GL_COMPRESSED_RGB_BPTC_UNSIGNED_FLOAT, compressed = true;
        case BC7;
            if srgb format = GL_COMPRESSED_SRGB_ALPHA_BPTC_UNORM;
            else format = GL_COMPRESSED_RGBA_BPTC_UNORM;
            return format, compressed = true;

        case D16;
            assert(srgb == false);
            return GL_DEPTH_COMPONENT16, src_format=GL_DEPTH_COMPONENT, src_type=GL_UNSIGNED_SHORT;
        case D24S8;
            assert(srgb == false);
            return GL_DEPTH24_STENCIL8, src_format=GL_DEPTH_STENCIL, src_type=GL_UNSIGNED_INT_24_8;
        case D32F;
            assert(srgb == false);
            //if NV_depth_buffer_float return GL_DEPTH_COMPONENT32F_NV, src_format=GL_DEPTH_COMPONENT, src_type=GL_FLOAT; // IC: This allows unclamped depth values.
            return GL_DEPTH_COMPONENT32F, src_format=GL_DEPTH_COMPONENT, src_type=GL_FLOAT;
        case D32FS8;
            assert(srgb == false);
            //if NV_depth_buffer_float return GL_DEPTH32F_STENCIL8_NV, src_format=GL_DEPTH_STENCIL, src_type=GL_FLOAT_32_UNSIGNED_INT_24_8_REV; // IC: This allows unclamped depth values.
            return GL_DEPTH32F_STENCIL8, src_format=GL_DEPTH_STENCIL, src_type=GL_FLOAT_32_UNSIGNED_INT_24_8_REV;

        case;
            assert(false, "Unsupported texture format %d.", tf);
    }


    return GL_INVALID_ENUM;
}

backend_realloc_texture :: (texture: *Texture, bitmap: *Bitmap) {
    // This routine needs to make sure we have enough space to store the bitmap.
    // But, that is handled invisibly by GL, so, we just make sure we have a handle.
    if !texture.gl_handle {
        glGenTextures(1, *texture.gl_handle);
        glBindTexture(GL_TEXTURE_2D, texture.gl_handle);

        // Clamp to edge due to alpha textures.
        // @Temporary. We'll want to provide more control over this.
        #if false { // HACK: farzher, pixel rendering required for pocket rumble
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S,     GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T,     GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        } else {
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S,     GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T,     GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        }
    }
}

backend_update_texture :: (texture: *Texture, bitmap: *Bitmap) {
    internal_format, gl_format, gl_type, compressed := get_ogl_format(texture.format, (texture.flags & .sRGB) != 0);

    texture_target :: GL_TEXTURE_2D;
    glBindTexture(texture_target, texture.gl_handle);

    //    print("internal_format %, gl_format %, gl_type %\n", formatInt(internal_format, base=16), formatInt(gl_format, base=16), formatInt(gl_type, base=16));
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(texture_target, 0, xx internal_format, xx bitmap.width, xx bitmap.height, 0, gl_format, gl_type, bitmap.data.data);
    //    resource_size := update_texture_2d(map, compressed, gl_format, gl_type, bittexture.data);
//    assert (texture.resource_size == xx resource_size);
}

backend_use_shader :: (s: *Shader) {
    if s.alpha_blend {
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glEnable(GL_BLEND);
    } else {
        glDisable(GL_BLEND);
    }

    glUseProgram(s.gl_handle);
}

backend_set_texture :: (shader: *Shader, texture: *Texture) {
    loc := glGetUniformLocation(shader.gl_handle, "diffuse_texture");

    if loc < 0 {
        log_error("Unable to find 'diffuse_texture' in the current shader.");
        return;
    }

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texture.gl_handle);  // Bind handle to slot 0.
    glUniform1i(loc, 0);
}

backend_resize_render_target :: (window: Window_Type, render_width: s32, render_height: s32, window_width: s32, window_height: s32) {
    offset_x := (window_width - render_width) / 2;
    offset_y := (window_height - render_height) / 2;
    glViewport(offset_x, offset_y, xx render_width, xx render_height);
}


#if OS == .WINDOWS {
    Backend_Platform_Specific :: struct {}
} else {
    Backend_Platform_Specific :: struct {
        gl_capable_window: Window_Type;
    }
}

