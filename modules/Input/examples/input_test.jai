/*

Why does an Input example have a bunch of shader stuff in it or whatever?
@Cleanup, please.
Why is it rendering its own Font_Quads?

When we convert this to Simp, it will be much more straightforward.

*/

Input   :: #import "Input";
Unicode :: #import "Unicode";
System  :: #import "System";

character_utf32_to_utf8 :: Unicode.character_utf32_to_utf8;

main :: () {
    init_demo_app("Input Demo");

    held_keys: String_Builder;
    defer free_buffers(*held_keys);
    text_edit: [..] u8;

    window_width:  s32 = WINDOW_WIDTH;
    window_height: s32 = WINDOW_HEIGHT;

    quit := false;
    while !quit {
        Input.update_window_events();

        for Input.events_this_frame {
            if it.type == .QUIT then quit = true;

            if it.type == {
                case .KEYBOARD;
                    if it.key_pressed && it.key_code == .BACKSPACE {
                        // @FixMe this works fine for English characters since most of that character set
                        // is one-byte in UTF8, but will not work correctly for many other language characters. 
                        if text_edit.count then pop(*text_edit);
                    }
                case .TEXT_INPUT;
                    value := it.utf32;

                    str := character_utf32_to_utf8(value);
                    for 0..str.count-1 {
                        array_add(*text_edit, str[it]);
                    }
                    free(str);
                case .WINDOW; // ???? Event_Type.WINDOW events dont seem to be generated at all on any of the platforms.
                case .MOUSE_WHEEL;
            }
        }

        resizes := get_window_resizes();  // We might want to collapse all resizes down to 1 for each window, but we don't currently do this, I think.
        for record: resizes {
            if record.window == the_window {
                window_resized_to(record.width, record.height);
                window_width = record.width;
                window_height = record.height;
            }
        }

        reset(*held_keys);
        for Input.input_button_states {
            if it & .DOWN {
                if it_index >= 0x20 && it_index < 0x7F {
                    value: u8 = cast(u8) it_index;
                    str: string;
                    str.data = *value;
                    str.count = 1;
                    append(*held_keys, str);
                }
            }
        }

        held_keys_text := builder_to_string(*held_keys);
        defer free(held_keys_text);

        text_edit_text: string;
        text_edit_text.data = text_edit.data;
        text_edit_text.count = text_edit.count;

        color := Vector4.{1,1,1,1};
        start_frame();
        draw_text(the_font, color,    20, 20 + FONT_HEIGHT*5, "Window Size: %, %", window_width, window_height);
        draw_text(the_font, color,    20, 20 + FONT_HEIGHT*4, "Text Input: %", text_edit_text);
        draw_text(the_font, color,    20, 20 + FONT_HEIGHT*3, "Held keys: %", held_keys_text);
        draw_text(the_font, color,    20, 20 + FONT_HEIGHT*2, "mouse_delta_x: %", Input.mouse_delta_x);
        draw_text(the_font, color,    20, 20 + FONT_HEIGHT*1, "mouse_delta_y: %", Input.mouse_delta_y);
        draw_text(the_font, color,    20, 20 + FONT_HEIGHT*0, "mouse_delta_z: %", Input.mouse_delta_z);
        finish_frame();
    }
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
    set_working_directory(path_strip_filename(System.get_path_of_running_executable()));

    the_window = create_window(WINDOW_WIDTH, WINDOW_HEIGHT, title);
    gl_create_context(the_window, 3, 2);
    gl_load(*gl);

    projection_matrix = orthographic_projection_matrix(0, WINDOW_WIDTH, 0, WINDOW_HEIGHT, -1, 1);
    text_rendering_shader = compile_shader_source(TEXT_VERTEX_SOURCE, TEXT_FRAGMENT_SOURCE);

    bytes_loaded: s64;
    the_font, bytes_loaded = load_font(".", "Skytree_by_MONTAGNA.ttf", FONT_HEIGHT);

    vao: u32;
    glGenVertexArrays(1, *vao);
    glBindVertexArray(vao);
}

window_resized_to :: (width: s32, height: s32) {
    glViewport(0, 0, cast(u32) width, cast(u32) height);
    projection_matrix = orthographic_projection_matrix(0, cast(float) width, 0, cast(float) height, -1, 1);
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

WINDOW_WIDTH  :: 1280;
WINDOW_HEIGHT :: 720;
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

    prep_text(font, x, y, color, text);

    vertices: [..] Vertex;
    defer array_reset(*vertices);

    for font.current_quads {
        V :: make_Vertex;

        v0 := V(it.x0, it.y0, it.u0, it.v0);
        v1 := V(it.x1, it.y0, it.u1, it.v0);
        v2 := V(it.x1, it.y1, it.u1, it.v1);
        v3 := V(it.x0, it.y1, it.u0, it.v1);
        add_quad(*vertices, v0, v1, v2, v3);

        if it.map && it.map.platform_specific.gl_handle {
            // @TODO what if the set of quads uses multiple texture maps?
            glActiveTexture(GL_TEXTURE0);
            glBindTexture  (GL_TEXTURE_2D, it.map.platform_specific.gl_handle);
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
