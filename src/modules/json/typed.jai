// Parse a JSON string into the given Type.
// All members of Type that are not present in the JSON are kept at their default values.
// All fields in the JSON that have no corresponding member in Type are ignored by default
// but you can pass ignore_unknown = false to fail instead.
//@Incomplete: The typed interface cannot yet parse into float members. (Because I haven’t needed it yet. 🙈) PRs welcome!
json_parse_string :: (content: string, $T: Type, ignore_unknown := true) -> success: bool, T {
	result: T;
	if !content then return false, result;

	info := type_info(T);
	remainder, success := parse_value(content, cast(*u8)*result, info, ignore_unknown, "");
	if !success		return false, result;

	remainder = trim_left(remainder, WHITESPACE_CHARS);
	if remainder.count {
		log_error("Unexpected trailing characters: %", remainder);
		return false, result;
	}

	return true, result;
}

json_parse_file :: (filename: string, $T: Type, ignore_unknown := true) -> success: bool, T {
	file_data, success := read_entire_file(filename);
	result: T;
	if !success		{
		log_error("Could not read file: %", filename);
		return false, result;
	}
	defer free(file_data);

	if (context.log_level >= .VERBOSE) {
		log("Read file: %", success);
	}
	success, result = json_parse_string(file_data, T, ignore_unknown);
	return success, result;
}

json_write_native :: (builder: *String_Builder, data: *void, info: *Type_Info, indent_char := "\t", ignore := ignore_by_note, level := 0) {
	if info.type == {
		case .BOOL;
			append(builder, ifx <<(cast(*bool) data) "true" else "false");
		case .INTEGER; #through;
		case .FLOAT;
			any_val: Any;
			any_val.type = info;
			any_val.value_pointer = data;
			print_item_to_builder(builder, any_val);
		case .ENUM;
			any_val: Any;
			any_val.type = info;
			any_val.value_pointer = data;
			
			append(builder, #char "\"");
			print_item_to_builder(builder, any_val);
			append(builder, #char "\"");
		case .STRING;
			json_append_escaped(builder, <<(cast(*string) data));
		case .ARRAY;
			info_array := cast(*Type_Info_Array) info;
			element_size := info_array.element_type.runtime_size;
			assert(element_size != -1);  // @Robustness @Incomplete: Right now, this might fail.

			stride := get_array_stride(element_size);
			array_data := data;
			array_count := info_array.array_count;
			if info_array.array_count == -1 {
				// assert(info_array.relative_pointer_size == 0, "Relative pointers are not yet supported"); // @Incomplete

				array_count = << cast(*s64) data;

				array_dest: **void = data + 8;
				array_data = << array_dest;
			}

			append(builder, "[");
			if array_data {
				if indent_char.count {
					append(builder, "\n");
					for 0..level	append(builder, indent_char);
				}
				for 0..array_count-1 {
					json_write_native(builder, array_data, info_array.element_type, indent_char, ignore, level + 1);
					if it != array_count - 1		append(builder, ",");
					array_data += stride;
				}
			}
			if indent_char.count {
				append(builder, "\n");
				for 0..level-1	append(builder, indent_char);
			}
			append(builder, "]");
		case .STRUCT;
			struct_info := cast(*Type_Info_Struct) info;
			if is_generic_json_value(info) {
				value := cast(*JSON_Value) data;
				json_write_json_value(builder, <<value, indent_char, level);
			} else {
				append(builder, #char "{");
				first := true;
				json_write_native_members(builder, data, struct_info.members, indent_char, ignore, level, *first);
				if indent_char.count {
					append(builder, "\n");
					for 0..level-1	append(builder, indent_char);
				}
				append(builder, "}");
			}
		case .POINTER;
			ptr_info := cast(*Type_Info_Pointer) info;
			// assert(ptr_info.relative_pointer_size == 0, "Relative pointers are not yet supported"); // @Incomplete
			ptr := << cast(**void) data;
			if ptr {
				json_write_native(builder, ptr, ptr_info.pointer_to, indent_char, ignore, level);
			} else {
				append(builder, "null");
			}
		case;
			assert(false, "Unsupported type: %", info.type);
	}
}

#scope_file

json_write_native_members :: (builder: *String_Builder, data: *void, members: [] Type_Info_Struct_Member, indent_char := "\t", ignore := ignore_by_note, level := 0, first: *bool) {
	for * member: members {
        if member.flags & .CONSTANT     continue;
		if ignore(member)               continue;
		if (member.type.type == .STRUCT && member.flags & .USING) {
			info := cast(*Type_Info_Struct) member.type;
			json_write_native_members(builder, data + member.offset_in_bytes, info.members, indent_char, ignore, level, first);
		} else {
			if !<<first	append(builder, ",");
			<<first = false;

			if indent_char.count {
				append(builder, "\n");
				for 0..level	append(builder, indent_char);
			}

			json_append_escaped(builder, member.name);
			append(builder, ": ");
			json_write_native(builder, data + member.offset_in_bytes, member.type, indent_char, ignore, level + 1);
		}
	}
}

get_array_stride :: (size: s64) -> s64 {
	// @Robustness: We assume 8-byte alignment for now.
	return (size + 7) & ~7;
}

is_generic_json_value_or_pointer_to_it :: (info: *Type_Info) -> bool {
	value_info := info;
	if info.type == .POINTER {
		pointer_info := cast(*Type_Info_Pointer) info;
		// assert(pointer_info.relative_pointer_size == 0, "Relative pointers are not yet supported"); // @Incomplete
		value_info = pointer_info.pointer_to;
	}

	return is_generic_json_value(info);
}

is_generic_json_value :: (info: *Type_Info) -> bool {
	return info == type_info(JSON_Value);
}

parse_value :: (to_parse: string, slot: *u8, info: *Type_Info, ignore_unknown: bool, field_name: string) -> remainder: string, success: bool {
	remainder := trim_left(to_parse, WHITESPACE_CHARS);
	success := true;

	prepare_slot :: (expected_type: Type_Info_Tag, info: *Type_Info, slot: *u8, to_parse: string) -> *u8, success: bool, is_generic: bool, info: *Type_Info {
		value_info := info;
		if info.type == .POINTER {
			pointer_info := cast(*Type_Info_Pointer) info;
			// assert(pointer_info.relative_pointer_size == 0, "Relative pointers are not yet supported"); // @Incomplete
			value_info = pointer_info.pointer_to;
		}

		is_generic := is_generic_json_value(value_info);

		if value_info.type != expected_type {
			teaser := to_parse;
			if teaser.count > 50	teaser.count = 50;
			log_error("Cannot parse % value into type %. Remaining input is: %…", expected_type, <<info, teaser);
			return null, false, false, value_info;
		}

		if info.type == .POINTER {
			value_slot := alloc(value_info.runtime_size);
			initializer: (*void);
			if value_info.type == .STRUCT {
				struct_info := cast(*Type_Info_Struct) value_info;
				initializer = struct_info.initializer;
			}
			if initializer {
				initializer(value_slot);
			} else {
				memset(value_slot, 0, value_info.runtime_size);
			}
			<<cast(**u8)slot = value_slot;
			return value_slot, true, is_generic, value_info;
		} else {
			return slot, true, is_generic, value_info;
		}
	}

	is_generic: bool;
	if remainder[0] == {
		case #char "n";
			remainder, success = expect_and_slice(remainder, "null");
			if !success		return remainder, false;
			if slot {
				// @ToDo, @Incomplete: Handle null properly
				if info.type != .POINTER {
					log_error("Got NULL value for non-pointer type % of field \"%\". Assigning default value instead.", <<info, field_name);
				}
			}
			return remainder, true;
		case #char "t";
			remainder, success = expect_and_slice(remainder, "true");
			if !success		return remainder, false;
			if slot {
				value_slot: *u8;
				value_slot, success, is_generic = prepare_slot(.BOOL, info, slot, to_parse);
				if success {
					if is_generic {
						json_set(cast(*JSON_Value)value_slot, true);
					} else {
						<<cast(*bool)value_slot = true;
					}
				}
			}
		case #char "f";
			remainder, success = expect_and_slice(remainder, "false");
			if !success		return remainder, false;
			if slot {
				value_slot: *u8;
				value_slot, success, is_generic = prepare_slot(.BOOL, info, slot, to_parse);
				if success {
					if is_generic {
						json_set(cast(*JSON_Value)value_slot, false);
					} else {
						<<cast(*bool)value_slot = false;
					}
				}
			}
		case #char "\"";
			if slot && info && info.type == .ENUM {
				info_enum := cast(*Type_Info_Enum)info;
				value_slot: *u8;
				value_slot, success, is_generic = prepare_slot(.INTEGER, info_enum.internal_type, slot, to_parse);
				remainder, success = parse_enum(remainder, value_slot, info_enum);
			} else {
				value: string;
				value, remainder, success = parse_string(remainder);
				stored := false;
				defer if !stored	free(value);
				if success && slot {
					value_slot: *u8;
					value_slot, success, is_generic = prepare_slot(.STRING, info, slot, to_parse);
					if success {
						if is_generic {
							json_set(cast(*JSON_Value)value_slot, value);
						} else {
							<<cast(*string)value_slot = value;
						}
						stored = true;
					}
				}
			}
		case #char "[";
			value_slot: *u8;
			value_info: *Type_Info;
			if slot {
				value_slot, success, is_generic, value_info = prepare_slot(.ARRAY, info, slot, to_parse);
			}
			if success {
				if is_generic {
					value: [] JSON_Value;
					value, remainder, success = parse_array(remainder);
					json_set(cast(*JSON_Value)value_slot, value);
				} else {
					remainder, success = parse_array(remainder, value_slot, cast(*Type_Info_Array) value_info, ignore_unknown);
				}
			}
		case #char "{";
			value_slot: *u8;
			value_info: *Type_Info;
			if slot {
				value_slot, success, is_generic, value_info = prepare_slot(.STRUCT, info, slot, to_parse);
			}
			if success {
				if is_generic {
					value := New(JSON_Object);
					<<value, remainder, success = parse_object(remainder);
					json_set(cast(*JSON_Value)value_slot, value);
				} else {
					remainder, success = parse_object(remainder, value_slot, cast(*Type_Info_Struct) value_info, ignore_unknown);
				}
			}
		case;
			if slot == null || info.type == .FLOAT || is_generic_json_value_or_pointer_to_it(info) {
				float_value: float64;
				float_value, success, remainder = string_to_float64(remainder);
				if success && slot {
					value_slot: *u8;
					value_info: *Type_Info;
					value_slot, success, is_generic, value_info = prepare_slot(.FLOAT, info, slot, to_parse);
					if success {
						if is_generic {
							json_set(cast(*JSON_Value)value_slot, float_value);
						} else {
							if value_info.runtime_size == 4 {
								(<< cast(*float) slot) = cast(float) float_value;
							} else {
								assert(value_info.runtime_size == 8);
								(<< cast(*float64) slot) = float_value;
							}
						}
					}
				}
			} else {
				int_value: s64;
				int_value, success, remainder = to_integer(remainder);
				if success && slot {
					value_slot: *u8;
					value_info: *Type_Info;
					value_slot, success, is_generic, value_info = prepare_slot(.INTEGER, info, slot, to_parse);
					if success {
						if is_generic {
							json_set(cast(*JSON_Value)value_slot, int_value);
						} else {
							info_int := cast(*Type_Info_Integer) value_info;
							success = write_integer(info_int, value_slot, int_value);
						}
					}
				}
			}
	}
	
	return remainder, success;
}

parse_enum :: (str : string, slot: *u8, info_enum: *Type_Info_Enum) -> remainder: string, success: bool {

	value, remainder, success := parse_string(str);
	defer free(value);
	
	// Try to parse as int
	int_value: s64;
	int_remainder: string;
	int_value, success, int_remainder = to_integer(value);
	
	if success && int_remainder.count == 0 {
		success = write_integer(info_enum.internal_type, slot, int_value);
		return remainder, success;
	}
	
	// Parse by members' names
	normalize_enum_value :: inline (name : string) -> string #expand {
		normalized := trim(name);
		if starts_with(normalized, tprint("%.", info_enum.name))
			normalized = slice(normalized, info_enum.name.count+1, normalized.count-info_enum.name.count-1);
		if starts_with(normalized, ".")
			normalized = slice(normalized, 1, normalized.count-1);
		return normalized;
	}
	
	if info_enum.enum_type_flags & .FLAGS {
		parsed_count := 0;
		values := split(value, "|");
		
		for v : values {
			name := normalize_enum_value(v);
			for info_enum.names {
				if name == it {
					parsed_count += 1;
					int_value |= info_enum.values[it_index];
					break;
				}
			}
		}
		if parsed_count == values.count {
			success = write_integer(info_enum.internal_type, slot, int_value);
		} else {
			success = false;
		}
	} else {
		success = false;
		name := normalize_enum_value(value);
		for info_enum.names {
			if name == it {
				int_value = info_enum.values[it_index];
				success = write_integer(info_enum.internal_type, slot, int_value);
				break;
			}
		}
	}

	return remainder, success;
}

parse_array :: (str: string, slot: *u8, info: *Type_Info_Array, ignore_unknown: bool) -> remainder: string, success: bool {
	element_size: int;
	stride: int;
	if slot {
		assert(info.array_count == -1, "Fixed array are not implemented yet");
		// assert(info.relative_pointer_size == 0, "Relative pointers are not yet supported");  // @Incomplete

		element_size = info.element_type.runtime_size;
		assert(element_size != -1, "Unknown element size");
		stride = get_array_stride(element_size);
	}

	assert(str[0] == #char "[", "Invalid object start %", str);
	remainder := advance(str);
	remainder = trim_left(remainder, WHITESPACE_CHARS);
	if remainder[0] == #char "]" {
		remainder = advance(remainder);
		// @Robustness: Do we need to zero out the array?
		return remainder, true;
	}


	if slot {
		array: Resizable_Array;
		element_data := alloc(element_size);
		defer free(element_data);

		while true {
			memset(element_data, 0, element_size);
			success: bool;
			remainder, success = parse_value(remainder, element_data, info.element_type, ignore_unknown, "");
			if !success	return remainder, false;

			maybe_grow(*array, element_size);
			memcpy(array.data + array.count * stride, element_data, stride);
			array.count += 1;

			remainder = trim_left(remainder, WHITESPACE_CHARS);
			if remainder[0] != #char ","	break;
			remainder = advance(remainder);
			remainder = trim_left(remainder, WHITESPACE_CHARS);
		}
		if info.array_type == .VIEW {
			view := (cast(*Array_View_64) slot);
			view.count = array.count;
			view.data = array.data;
		} else {
			<<(cast(*Resizable_Array) slot) = array;
		}
	} else {
		while true {
			success: bool;
			remainder, success = parse_value(remainder, null, null, ignore_unknown, "");
			if !success	return remainder, false;

			remainder = trim_left(remainder, WHITESPACE_CHARS);
			if remainder[0] != #char ","	break;
			remainder = advance(remainder);
			remainder = trim_left(remainder, WHITESPACE_CHARS);
		}
	}

	if remainder[0] != #char "]"	return remainder, false;
	remainder = advance(remainder);
	return remainder, true;
}

maybe_grow :: (array: *Resizable_Array, element_size: s64) {
	if array.count >= array.allocated {
		reserve := 2 * array.allocated;
		if reserve < 8  reserve = 8;

		if !array.allocator.proc {
			if context.allocator.proc {
				array.allocator      = context.allocator;
			} else {
				array.allocator      = context.default_allocator;
			}
		}

		array.data = realloc(array.data, reserve * element_size, array.allocated * element_size,, array.allocator);
		assert(array.data != null); // Program will die if we couldn't get memory. We can think about an alternative strategy, but it's hard to know what would be reasonable.

		array.allocated = reserve;
	}
}

parse_object :: (str: string, slot: *u8, info: *Type_Info_Struct, ignore_unknown: bool) -> remainder: string, success: bool {
	assert(str[0] == #char "{", "Invalid object start %", str);
	remainder := advance(str);
	remainder = trim_left(remainder, WHITESPACE_CHARS);
	if remainder[0] == #char "}" {
		remainder = advance(remainder);
		return remainder, true;
	}

	while true {
		if remainder[0] != #char "\""	return remainder, false;

		key: string;
		success: bool;
		key, remainder, success = parse_string(remainder);
		if !success		return remainder, false;
		defer free(key);

		member: *Type_Info_Struct_Member;
		member_offset: s64;
		if info {
			member, member_offset = get_field(info, key);
		}

		member_slot: *u8;
		member_info: *Type_Info;
		if member {
			member_slot = slot + member_offset;
			member_info = member.type;
		} else if !ignore_unknown {
			log_error("Missing member % in %", key, <<info);
			return remainder, false;
		}

		remainder = trim_left(remainder, WHITESPACE_CHARS);
		if remainder[0] != #char ":"	return remainder, false;
		remainder = advance(remainder);
		remainder = trim_left(remainder, WHITESPACE_CHARS);
		remainder, success = parse_value(remainder, member_slot, member_info, ignore_unknown, key);
		if !success		return remainder, false;

		remainder = trim_left(remainder, WHITESPACE_CHARS);
		if remainder[0] != #char ","	break;
		remainder = advance(remainder);
		remainder = trim_left(remainder, WHITESPACE_CHARS);
	}

	if remainder[0] != #char "}"	return remainder, false;
	remainder = advance(remainder);
	return remainder, true;
}

write_integer :: (info: *Type_Info_Integer, pointer: *void, value: s64) -> bool {
	if info.signed {
		valid, low, high := range_check_and_store(value, info, pointer);

		if !valid {
			log_error("Value '%' is out of range. (The value must be between % and %.)", value, low, high);
			return false;
		}
	} else {
		valid, low, high := range_check_and_store(cast(u64) value, info, pointer);  // Different overload from the above!

		if !valid {
			log_error("Value '%' is out of range. (The value must be between % and %.)", value, low, high);
			return false;
		}
	}

	return true;
}

range_check_and_store :: (value: $T, info: *Type_Info_Integer, pointer: *void) -> (success: bool, low: T, high: T) {
	#assert((T == u64) || (T == s64));

	size := info.runtime_size;

	store :: (pointer: *void, value: T, size: int) {
		if size == {
			case 1;
			<< cast(*s8)  pointer = xx,no_check value;
			case 2;
			<< cast(*s16) pointer = xx,no_check value;
			case 4;
			<< cast(*s32) pointer = xx,no_check value;
			case 8;
			<< cast(*s64) pointer = xx,no_check value;
			case;
			assert(false);
		}
	}

	#if T == u64 {
		low, high := unsigned_integer_range_from_size(size);
		if (value < low) || (value > high)  return false, low, high;

		store(pointer, value, size);
		return true, low, high;
	} else {
		low, high := signed_integer_range_from_size(size);
		if (value < low) || (value > high)  return false, low, high;

		store(pointer, value, size);
		return true, low, high;
	}

}

signed_integer_range_from_size :: (size_in_bytes: int) -> (low: s64, high: s64) {
	assert((size_in_bytes == 1) || (size_in_bytes == 2) || (size_in_bytes == 4) || (size_in_bytes == 8));

	high := (1 << (size_in_bytes*8-1)) - 1;
	low  := ~high;

	return low, high;
}

unsigned_integer_range_from_size :: (size_in_bytes: int) -> (low: u64, high: u64) {
	assert((size_in_bytes == 1) || (size_in_bytes == 2) || (size_in_bytes == 4) || (size_in_bytes == 8));

	high: u64 = ---;
	if size_in_bytes == 8 {
		high = cast(u64) 0xffff_ffff_ffff_ffff;  // Hardcode 8 to prevent unpredictable behavior due to platform-specific details. In the future the outcome of << will be language-defined in all cases.
	} else {
		high = cast(u64) (1 << (size_in_bytes*8)) - 1;  // @CompilerBug: Why do we need to cast the 1? That is dumb.
	}

	return 0, high;
}

