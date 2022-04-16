
Clipboard :: #import "Clipboard";

#import "Basic";

#import "DPI";

main :: () {
    os_dpi_init();
    
    init_demo_app("DPI test");

    // run an event loop since X11 requires apps to stay alive to respond to selection requests.
    quit := false;
    fade := 1.0;
    decrement_fade := 0.01;
    copied_to_clipboard_text: string;

    text_to_copy_to_clipboard := copy_string("Hello, Sailor!");
    while !quit {
        update_window_events();

        for events_this_frame {
            if it.type == Event_Type.QUIT then quit = true;

            if it.type == Event_Type.KEYBOARD {
                if it.key_pressed == 0 continue;

                if        it.key_code == xx #char "T" {
                    free(copied_to_clipboard_text);
                    copied_to_clipboard_text = sprint("'%' Copied to clipboard.", text_to_copy_to_clipboard);
                    Clipboard.os_clipboard_set_text("Hello, Sailor!");
                    fade = 1.0;
                    decrement_fade = 0.01;
                } else if it.key_code == xx #char "I" {
                    free(copied_to_clipboard_text);
                    copied_to_clipboard_text = sprint("Screenshot copied to clipboard.");
                    copy_screen_shot_to_clipboard();
                    fade = 1.0;
                    decrement_fade = 0.01;
                } else if it.key_code == xx #char "P" {
                    free(copied_to_clipboard_text);
                    copied_to_clipboard_text = sprint("Text in clipboard: %", Clipboard.os_clipboard_get_text());
                    fade = 1.0;
                    decrement_fade = 0.001;
                }
            }
        }

        is_resized, record := is_a_window_resized();
        if (is_resized && record.window == the_window) {
            window_resized_to(record.width, record.height);
        }


        start_frame();
        fade -= decrement_fade;
        if fade < 0 then fade = 0;
        
        draw_text(the_font, make_vector4(1, 1, 1, fade), 20, 20 + FONT_HEIGHT*4, copied_to_clipboard_text);
        draw_text(the_font, make_vector4(1, 1, 1, 1),    20, 20 + FONT_HEIGHT*3, "Press 'P' to print the text currently in the clipboard.");
        draw_text(the_font, make_vector4(1, 1, 1, 1),    20, 20 + FONT_HEIGHT*2, "Press 'I' to copy a screenshot to the clipboard.");
        draw_text(the_font, make_vector4(1, 1, 1, 1),    20, 20 + FONT_HEIGHT*1, "Press 'T' to copy '%' to the clipboard.", text_to_copy_to_clipboard);
        draw_text(the_font, make_vector4(1, 1, 1, 1),    20, 20 + FONT_HEIGHT*0, "Window dimensions (pixels) : %, %.", window_width, window_height);
        finish_frame();
    }
}

copy_screen_shot_to_clipboard :: () {
    width : s32 = window_width;
    height: s32 = window_height;

    tex: Texture;
    tex.width = width;
    tex.height = height;
    tex.depth = 1;
    tex.mipmap_count = 1;
    tex.format = Texture_Format.RGBA8;
    tex.flags |= Texture_Flags.Render_Target;
    tex.gl_handle = 0/*default framebuffer*/;
    tex.gl_target = GL_TEXTURE_2D;
    tex.gl_internal_format = GL_RGBA;
    bitmap := get_bitmap_from_texture(*tex, Texture_Format.RGB8, width, height, srgb=true);
    
    Clipboard.os_clipboard_set_bitmap(bitmap.width, bitmap.height, bitmap.data);
}

#scope_file

#import "Basic";
#import "Render";
#import "Math";

#import "Window_Creation";
#import "Input";
#import "GL";
#import "String";

init_demo_app :: (title: string) {
    set_working_directory(path_strip_filename(get_path_of_running_executable()));

    window_width  = INIT_WINDOW_WIDTH;
    window_height = INIT_WINDOW_HEIGHT;

    the_window = create_window(window_width, window_height, title);
    gl_create_context(the_window, 3, 2);
    gl_load(*gl);

    window_resized_to(window_width, window_height);
    text_rendering_shader = compile_shader_source(TEXT_VERTEX_SOURCE, TEXT_FRAGMENT_SOURCE);

    bytes_loaded: s64;
    the_font, bytes_loaded = load_font(".", "Skytree_by_MONTAGNA.ttf", FONT_HEIGHT);

    vao: u32;
    glGenVertexArrays(1, *vao);
    glBindVertexArray(vao);
}

window_resized_to :: (width: s32, height: s32) {
    window_width = width;
    window_height = height;
    glViewport(0, 0, cast(u32) width, cast(u32) height);


    scaled_width, scaled_height := os_dpi_get_window_coordinates(the_window, cast(float) width, cast(float) height);
    projection_matrix = orthographic_projection_matrix(0, cast(float) scaled_width, 0, cast(float) scaled_height, -1, 1);
}

start_frame :: () {
    while true {
        if elapsed_time >= TICK_PERIOD {
            elapsed_time -= TICK_PERIOD;
            break;
        }

        now := get_time();
        if last_time dt = cast(float) (now - last_time);
        last_time = now;
        
        elapsed_time += dt;
        sleep_milliseconds(2);
    }

    reset_temporary_storage();

    glClear(GL_COLOR_BUFFER_BIT);
    glDisable(GL_CULL_FACE);
}

finish_frame :: () {
    swap_buffers(the_window);
}

window_width: s32;
window_height: s32;

INIT_WINDOW_WIDTH  :: 1280; // in screen points
INIT_WINDOW_HEIGHT :: 720;  // in screen points
FONT_HEIGHT :: 32;
fps_time := 0.0;
last_time: float64;
elapsed_time: float64;
TICK_PERIOD : float64 : 1.0/60.0; // time between game updates
dt: float;
the_window: Window_Type;
text_rendering_shader: u32;
projection_matrix: Matrix4;
the_font: *Dynamic_Font;

TEXT_VERTEX_SOURCE :: #string DONE
#version 330 core

layout (location = 0) in vec3 in_pos;
layout (location = 1) in vec2 in_texture_coords;
layout (location = 2) in vec4 in_vertex_color;

out vec2 texture_coords;
out vec4 vertex_color;

uniform mat4 projection;

void main() {
    vertex_color = in_vertex_color;
    texture_coords = in_texture_coords;
    gl_Position = projection * vec4(in_pos.xy, 0.0, 1.0);
}

DONE

TEXT_FRAGMENT_SOURCE :: #string DONE
#version 330 core

out vec4 out_frag_color;
in vec2 texture_coords;
in vec4 vertex_color;

uniform sampler2D texture_atlas;

void main() {
    vec4 color = texture(texture_atlas, texture_coords);
    out_frag_color = vertex_color * color;
}

DONE

Vertex :: struct {
    x, y: float;
    u, v: float;
}

make_Vertex :: (x: float, y: float, u: float, v: float) -> Vertex {
    vtx: Vertex = ---;
    vtx.x = x;
    vtx.y = y;
    vtx.u = u;
    vtx.v = v;
    return vtx;
}

ATTRIB_POSITION  :: 0;
ATTRIB_TEXCOORDS :: 1;
ATTRIB_COLOR     :: 2;

add_quad :: (arr: *[..] $T, v0: T, v1: T, v2: T, v3: T) {
    array_add(arr, v0);
    array_add(arr, v1);
    array_add(arr, v2);
    
    array_add(arr, v2);
    array_add(arr, v3);
    array_add(arr, v0);
}

set_quad :: (arr: [] $T, v0: T, v1: T, v2: T, v3: T) {
    assert(arr.count >= 6);
    arr[0] = v0;
    arr[1] = v1;
    arr[2] = v2;
    
    arr[3] = v2;
    arr[4] = v3;
    arr[5] = v0;
}

draw_text :: (font: *Dynamic_Font, color: Vector4, x: int, y: int, fmt: string, args: .. Any) {
    assert(font != null);
    builder: String_Builder;
    defer free_buffers(*builder);
    print_to_builder(*builder, fmt, ..args);
    text := builder_to_string(*builder);
    defer free(text);

    shader := text_rendering_shader;
    glUseProgram(shader);
    
    projection_loc := glGetUniformLocation(shader, "projection");    
    glUniformMatrix4fv(projection_loc, 1, true, cast(*float) *projection_matrix);

    prep_text(font, x, y, make_vector4(1, 1, 1, 1), text);

    vertices: [..] Vertex;
    defer array_reset(*vertices);

    for font.current_quads {
        V :: make_Vertex;

        v0 := V(it.x0, it.y0, it.u0, it.v0);
        v1 := V(it.x1, it.y0, it.u1, it.v0);
        v2 := V(it.x1, it.y1, it.u1, it.v1);
        v3 := V(it.x0, it.y1, it.u0, it.v1);
        add_quad(*vertices, v0, v1, v2, v3);

        if (it.map && it.map.platform_specific.gl_handle) {
            // @TODO what if the set of quads uses multiple texture maps?
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, it.map.platform_specific.gl_handle);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

            uni_texture := glGetUniformLocation(shader, "texture_atlas");
            glUniform1i(uni_texture, 0);
        }
    }

    buffer_id: u32;
    glGenBuffers(1, *buffer_id);
    defer glDeleteBuffers(1, *buffer_id);

    glBindBuffer(GL_ARRAY_BUFFER, buffer_id);
    glBufferData(GL_ARRAY_BUFFER, size_of(Vertex)*vertices.count, vertices.data, GL_DYNAMIC_DRAW);

    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    defer glDisable(GL_BLEND);

    glEnableVertexAttribArray(ATTRIB_POSITION);
    defer glDisableVertexAttribArray(ATTRIB_POSITION);
    glEnableVertexAttribArray(ATTRIB_TEXCOORDS);
    defer glDisableVertexAttribArray(ATTRIB_TEXCOORDS);

    glVertexAttribPointer(ATTRIB_POSITION, 2, GL_FLOAT, false, size_of(Vertex), null);
    glVertexAttribPointer(ATTRIB_TEXCOORDS, 2, GL_FLOAT, false, size_of(Vertex), cast(*void) (size_of(float)*2));
    glVertexAttrib4f(ATTRIB_COLOR, color.x, color.y, color.z, color.w);
    glDrawArrays(GL_TRIANGLES, 0, xx vertices.count);
}

compile_shader_source :: (vertex: string, pixel: string) -> u32 {
    vert := compile_shader(GL_VERTEX_SHADER, vertex);
    frag := compile_shader(GL_FRAGMENT_SHADER, pixel);
    program := glCreateProgram();
    glAttachShader(program, vert);
    glAttachShader(program, frag);
    glLinkProgram(program);
    
    status: GLint;
    glGetProgramiv(program, GL_LINK_STATUS, *status);
    if (status == 0) {
        len: GLint;
        glGetProgramiv(program, GL_INFO_LOG_LENGTH, *len);
        buf := cast(*u8) alloc(len);
        glGetProgramInfoLog(program, xx len, xx *len, buf);
        print("ERROR: %\n", to_string(buf));
        free(buf);
        
        glDeleteProgram(program);
        glDeleteShader(vert);
        glDeleteShader(frag);
        return 0;
    }
    
    glDetachShader(program, vert);
    glDetachShader(program, frag);

    glValidateProgram(program);
    
    return program;
}

compile_shader :: (type: GLenum, source: string) -> u32 {
    v := glCreateShader(type);
    length: GLint = xx source.count;
    glShaderSource(v, 1, *source.data, *length);
    glCompileShader(v);
    
    status: GLint;
    glGetShaderiv(v, GL_COMPILE_STATUS, *status);
    if (status == 0) {
        len: GLint;
        glGetShaderiv(v, GL_INFO_LOG_LENGTH, *len);
        buf := cast(*u8) alloc(len);
        glGetShaderInfoLog(v, xx len, xx *len, buf);
        print("ERROR: %\n", to_string(buf));
        free(buf);
        
        glDeleteShader(v);
        return 0;
    }
    
    return v;
}
