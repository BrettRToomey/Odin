#shared_global_scope

import "core:os.odin"
// import "core:fmt.odin" // TODO(bill): Remove the need for `fmt` here
import "core:utf8.odin"
import "core:raw.odin"
import "core:mem.odin"

// Naming Conventions:
// In general, Ada_Case for types and snake_case for values
//
// Import Name:        snake_case (but prefer single word)
// Types:              Ada_Case
// Enum Values:        Ada_Case
// Procedures:         snake_case
// Local Variables:    snake_case
// Constant Variables: SCREAMING_SNAKE_CASE


// IMPORTANT NOTE(bill): `type_info_of` cannot be used within a
// #shared_global_scope due to  the internals of the compiler.
// This could change at a later date if the all these data structures are
// implemented within the compiler rather than in this "preload" file

// NOTE(bill): This must match the compiler's
Calling_Convention :: enum {
	Invalid     = 0,
	Odin        = 1,
	Contextless = 2,
	C           = 3,
	Std         = 4,
	Fast        = 5,
}
// IMPORTANT NOTE(bill): Do not change the order of any of this data
// The compiler relies upon this _exact_ order

Type_Info_Enum_Value :: union {
	rune,
	i8, i16, i32, i64, int,
	u8, u16, u32, u64, uint, uintptr,
	f32, f64,
};

// Variant Types
Type_Info_Named    :: struct {name: string, base: ^Type_Info};
Type_Info_Integer  :: struct {signed: bool};
Type_Info_Rune     :: struct {};
Type_Info_Float    :: struct {};
Type_Info_Complex  :: struct {};
Type_Info_String   :: struct {is_cstring: bool};
Type_Info_Boolean  :: struct {};
Type_Info_Any      :: struct {};
Type_Info_Type_Id  :: struct {};
Type_Info_Pointer  :: struct {
	elem: ^Type_Info // nil -> rawptr
};
Type_Info_Procedure :: struct {
	params:     ^Type_Info, // Type_Info_Tuple
	results:    ^Type_Info, // Type_Info_Tuple
	variadic:   bool,
	convention: Calling_Convention,
};
Type_Info_Array :: struct {
	elem:      ^Type_Info,
	elem_size: int,
	count:     int,
};
Type_Info_Dynamic_Array :: struct {elem: ^Type_Info, elem_size: int};
Type_Info_Slice         :: struct {elem: ^Type_Info, elem_size: int};
Type_Info_Tuple :: struct { // Only really used for procedures
	types:        []^Type_Info,
	names:        []string,
};
Type_Info_Struct :: struct {
	types:        []^Type_Info,
	names:        []string,
	offsets:      []uintptr, // offsets may not be used in tuples
	usings:       []bool,    // usings may not be used in tuples
	is_packed:    bool,
	is_raw_union: bool,
	custom_align: bool,
};
Type_Info_Union :: struct {
	variants:   []^Type_Info,
	tag_offset: uintptr,
	tag_type:   ^Type_Info,
};
Type_Info_Enum :: struct {
	base:      ^Type_Info,
	names:     []string,
	values:    []Type_Info_Enum_Value,
	is_export: bool,
};
Type_Info_Map :: struct {
	key:              ^Type_Info,
	value:            ^Type_Info,
	generated_struct: ^Type_Info,
};
Type_Info_Bit_Field :: struct {
	names:   []string,
	bits:    []i32,
	offsets: []i32,
};


Type_Info :: struct {
	size:  int,
	align: int,
	id:    typeid,

	variant: union {
		Type_Info_Named,
		Type_Info_Integer,
		Type_Info_Rune,
		Type_Info_Float,
		Type_Info_Complex,
		Type_Info_String,
		Type_Info_Boolean,
		Type_Info_Any,
		Type_Info_Type_Id,
		Type_Info_Pointer,
		Type_Info_Procedure,
		Type_Info_Array,
		Type_Info_Dynamic_Array,
		Type_Info_Slice,
		Type_Info_Tuple,
		Type_Info_Struct,
		Type_Info_Union,
		Type_Info_Enum,
		Type_Info_Map,
		Type_Info_Bit_Field,
	},
}

// NOTE(bill): only the ones that are needed (not all types)
// This will be set by the compiler
__type_table: []Type_Info;

__args__: []cstring;

// IMPORTANT NOTE(bill): Must be in this order (as the compiler relies upon it)


Source_Code_Location :: struct {
	file_path:    string,
	line, column: int,
	procedure:    string,
}



Allocator_Mode :: enum byte {
	Alloc,
	Free,
	Free_All,
	Resize,
}


Allocator_Proc :: #type proc(allocator_data: rawptr, mode: Allocator_Mode,
	                         size, alignment: int,
	                         old_memory: rawptr, old_size: int, flags: u64 = 0, location := #caller_location) -> rawptr;


Allocator :: struct {
	procedure: Allocator_Proc,
	data:      rawptr,
}


Context :: struct {
	allocator:  Allocator,
	thread_id:  int,

	user_data:  any,
	user_index: int,

	parent:     ^Context,
	derived:    any, // May be used for derived data types
}

DEFAULT_ALIGNMENT :: 2*align_of(rawptr);

__INITIAL_MAP_CAP :: 16;

__Map_Key :: struct {
	hash: u64,
	str:  string,
}

__Map_Find_Result :: struct {
	hash_index:  int,
	entry_prev:  int,
	entry_index: int,
}

__Map_Entry_Header :: struct {
	key:  __Map_Key,
	next: int,
/*
	value: Value_Type,
*/
}

__Map_Header :: struct {
	m:             ^raw.Map,
	is_key_string: bool,
	entry_size:    int,
	entry_align:   int,
	value_offset:  uintptr,
	value_size:    int,
}



type_info_base :: proc "contextless" (info: ^Type_Info) -> ^Type_Info {
	if info == nil do return nil;

	base := info;
	loop: for {
		switch i in base.variant {
		case Type_Info_Named: base = i.base;
		case: break loop;
		}
	}
	return base;
}


type_info_base_without_enum :: proc "contextless" (info: ^Type_Info) -> ^Type_Info {
	if info == nil do return nil;

	base := info;
	loop: for {
		switch i in base.variant {
		case Type_Info_Named: base = i.base;
		case Type_Info_Enum:  base = i.base;
		case: break loop;
		}
	}
	return base;
}

__typeid_of :: proc "contextless" (ti: ^Type_Info) -> typeid {
	if ti == nil do return nil;
	return ti.id;
}
__type_info_of :: proc "contextless" (id: typeid) -> ^Type_Info {
	n := int(transmute(uintptr)id);
	if n < 0 || n >= len(__type_table) {
		n = 0;
	}
	return &__type_table[n];
}

typeid_base :: proc "contextless" (id: typeid) -> typeid {
	ti := type_info_of(id);
	ti = type_info_base(ti);
	return typeid_of(ti);
}
typeid_base_without_enum :: proc "contextless" (id: typeid) -> typeid {
	ti := type_info_base_without_enum(type_info_of(id));
	return typeid_of(ti);
}



@(default_calling_convention = "c")
foreign __llvm_core {
	@(link_name="llvm.assume")
	assume :: proc(cond: bool) ---;

	@(link_name="llvm.debugtrap")
	__debug_trap :: proc() ---;

	@(link_name="llvm.trap")
	__trap :: proc() ---;

	@(link_name="llvm.readcyclecounter")
	read_cycle_counter :: proc() -> u64 ---;
}





__init_context_from_ptr :: proc "contextless" (c: ^Context, other: ^Context) {
	if c == nil do return;
	c^ = other^;
	__init_context(c);
}

__init_context :: proc "contextless" (c: ^Context) {
	if c == nil do return;

	if c.allocator.procedure == nil {
		c.allocator = default_allocator();
	}
	if c.thread_id == 0 {
		c.thread_id = os.current_thread_id();
	}
}



alloc :: inline proc(size: int, alignment: int = DEFAULT_ALIGNMENT, loc := #caller_location) -> rawptr {
	a := context.allocator;
	return a.procedure(a.data, Allocator_Mode.Alloc, size, alignment, nil, 0, 0, loc);
}

free_ptr_with_allocator :: inline proc(a: Allocator, ptr: rawptr, loc := #caller_location) {
	if ptr == nil do return;
	if a.procedure == nil do return;
	a.procedure(a.data, Allocator_Mode.Free, 0, 0, ptr, 0, 0, loc);
}

free_ptr :: inline proc(ptr: rawptr, loc := #caller_location) do free_ptr_with_allocator(context.allocator, ptr);

free_all :: inline proc(loc := #caller_location) {
	a := context.allocator;
	a.procedure(a.data, Allocator_Mode.Free_All, 0, 0, nil, 0, 0, loc);
}


resize :: inline proc(ptr: rawptr, old_size, new_size: int, alignment: int = DEFAULT_ALIGNMENT, loc := #caller_location) -> rawptr {
	a := context.allocator;
	return a.procedure(a.data, Allocator_Mode.Resize, new_size, alignment, ptr, old_size, 0, loc);
}


copy :: proc "contextless" (dst, src: $T/[]$E) -> int {
	n := max(0, min(len(dst), len(src)));
	if n > 0 do __mem_copy(&dst[0], &src[0], n*size_of(E));
	return n;
}


append :: proc(array: ^$T/[dynamic]$E, args: ...E, loc := #caller_location) -> int {
	if array == nil do return 0;

	arg_len := len(args);
	if arg_len <= 0 do return len(array);


	if cap(array) <= len(array)+arg_len {
		cap := 2 * cap(array) + max(8, arg_len);
		_ = reserve(array, cap, loc);
	}
	arg_len = min(cap(array)-len(array), arg_len);
	if arg_len > 0 {
		a := (^raw.Dynamic_Array)(array);
		data := (^E)(a.data);
		assert(data != nil);
		__mem_copy(mem.ptr_offset(data, a.len), &args[0], size_of(E) * arg_len);
		a.len += arg_len;
	}
	return len(array);
}

append_string :: proc(array: ^$T/[dynamic]$E/u8, args: ...string, loc := #caller_location) -> int {
	for arg in args {
		append(array = array, args = ([]E)(arg), loc = loc);
	}
	return len(array);
}

pop :: proc "contextless" (array: ^$T/[dynamic]$E) -> E {
	if array == nil do return E{};
	assert(len(array) > 0);
	res := array[len(array)-1];
	(^raw.Dynamic_Array)(array).len -= 1;
	return res;
}

clear_dynamic_array :: inline proc "contextless" (array: ^$T/[dynamic]$E) {
	if array != nil do (^raw.Dynamic_Array)(array).len = 0;
}
clear_map :: inline proc "contextless" (m: ^$T/map[$K]$V) {
	if m == nil do return;
	raw_map := (^raw.Map)(m);
	hashes  := (^raw.Dynamic_Array)(&raw_map.hashes);
	entries := (^raw.Dynamic_Array)(&raw_map.entries);
	hashes.len  = 0;
	entries.len = 0;
}

clear :: proc[clear_dynamic_array, clear_map];

reserve_dynamic_array :: proc(array: ^$T/[dynamic]$E, capacity: int, loc := #caller_location) -> bool {
	if array == nil do return false;
	a := (^raw.Dynamic_Array)(array);

	if capacity <= a.cap do return true;

	if a.allocator.procedure == nil {
		a.allocator = context.allocator;
	}
	assert(a.allocator.procedure != nil);

	old_size  := a.cap * size_of(E);
	new_size  := capacity * size_of(E);
	allocator := a.allocator;

	new_data := allocator.procedure(
		allocator.data, Allocator_Mode.Resize, new_size, align_of(E),
		a.data, old_size, 0, loc,
	);
	if new_data == nil do return false;

	a.data = new_data;
	a.cap = capacity;
	return true;
}


__get_map_header :: proc "contextless" (m: ^$T/map[$K]$V) -> __Map_Header {
	header := __Map_Header{m = (^raw.Map)(m)};
	Entry :: struct {
		key:   __Map_Key,
		next:  int,
		value: V,
	}

	_, is_string := type_info_base(type_info_of(K)).variant.(Type_Info_String);
	header.is_key_string = is_string;
	header.entry_size    = int(size_of(Entry));
	header.entry_align   = int(align_of(Entry));
	header.value_offset  = uintptr(offset_of(Entry, value));
	header.value_size    = int(size_of(V));
	return header;
}

__get_map_key :: proc "contextless" (key: $K) -> __Map_Key {
	map_key: __Map_Key;
	ti := type_info_base_without_enum(type_info_of(K));
	switch _ in ti.variant {
	case Type_Info_Integer:
		switch 8*size_of(key) {
		case   8: map_key.hash = u64((  ^u8)(&key)^);
		case  16: map_key.hash = u64(( ^u16)(&key)^);
		case  32: map_key.hash = u64(( ^u32)(&key)^);
		case  64: map_key.hash = u64(( ^u64)(&key)^);
		case: panic("Unhandled integer size");
		}
	case Type_Info_Rune:
		map_key.hash = u64((^rune)(&key)^);
	case Type_Info_Pointer:
		map_key.hash = u64(uintptr((^rawptr)(&key)^));
	case Type_Info_Float:
		switch 8*size_of(key) {
		case 32: map_key.hash = u64((^u32)(&key)^);
		case 64: map_key.hash = u64((^u64)(&key)^);
		case: panic("Unhandled float size");
		}
	case Type_Info_String:
		str := (^string)(&key)^;
		map_key.hash = __default_hash_string(str);
		map_key.str  = str;
	case:
		panic("Unhandled map key type");
	}
	return map_key;
}

reserve_map :: proc(m: ^$T/map[$K]$V, capacity: int) {
	if m != nil do __dynamic_map_reserve(__get_map_header(m), capacity);
}

delete :: proc(m: ^$T/map[$K]$V, key: K) {
	if m != nil do __dynamic_map_delete(__get_map_header(m), __get_map_key(key));
}

reserve :: proc[reserve_dynamic_array, reserve_map];



new :: inline proc(T: type, loc := #caller_location) -> ^T {
	ptr := (^T)(alloc(size_of(T), align_of(T), loc));
	ptr^ = T{};
	return ptr;
}
new_clone :: inline proc(data: $T, loc := #caller_location) -> ^T {
	ptr := (^T)(alloc(size_of(T), align_of(T), loc));
	ptr^ = data;
	return ptr;
}

free_string :: proc(str: string, loc := #caller_location) {
	free_ptr(raw.data(str), loc);
}
free_cstring :: proc(str: cstring, loc := #caller_location) {
	free_ptr((^byte)(str), loc);
}
free_dynamic_array :: proc(array: $T/[dynamic]$E, loc := #caller_location) {
	free_ptr(raw.data(array), loc);
}
free_slice :: proc(array: $T/[]$E, loc := #caller_location) {
	free_ptr(raw.data(array), loc);
}
free_map :: proc(m: $T/map[$K]$V, loc := #caller_location) {
	raw := transmute(raw.Map)m;
	free_dynamic_array(raw.hashes, loc);
	free_ptr(raw.entries.data, loc);
}

free :: proc[
	free_ptr,
	free_string, free_cstring,
	free_dynamic_array, free_slice, free_map,
];


// NOTE(bill): This code works but I will prefer having `make` a built-in procedure
// to have better error messages
/*
make :: proc(T: type/[]$E, len: int, using loc := #caller_location) -> T {
	cap := len;
	__slice_expr_error(file_path, int(line), int(column), 0, len, cap);
	data := cast(^E)alloc(len * size_of(E), align_of(E));
	for i in 0..len do (data+i)^ = E{};
	s := raw.Slice{data = data, len = len};
	return (cast(^T)&s)^;
}
make :: proc(T: type/[dynamic]$E, len: int = 8, using loc := #caller_location) -> T {
	cap := len;
	__slice_expr_error(file_path, int(line), int(column), 0, len, cap);
	data := cast(^E)alloc(cap * size_of(E), align_of(E));
	for i in 0..len do (data+i)^ = E{};
	s := raw.Dynamic_Array{data = data, len = len, cap = cap, allocator = context.allocator};
	return (cast(^T)&s)^;
}
make :: proc(T: type/[dynamic]$E, len, cap: int, using loc := #caller_location) -> T {
	__slice_expr_error(file_path, int(line), int(column), 0, len, cap);
	data := cast(^E)alloc(cap * size_of(E), align_of(E));
	for i in 0..len do (data+i)^ = E{};
	s := raw.Dynamic_Array{data = data, len = len, cap = cap, allocator = context.allocator};
	return (cast(^T)&s)^;
}

make :: proc(T: type/map[$K]$V, cap: int = 16, using loc := #caller_location) -> T {
	if cap < 0 do cap = 16;

	m: T;
	header := __get_map_header(&m);
	__dynamic_map_reserve(header, cap);
	return m;
}
*/



default_resize_align :: proc(old_memory: rawptr, old_size, new_size, alignment: int, loc := #caller_location) -> rawptr {
	if old_memory == nil do return alloc(new_size, alignment, loc);

	if new_size == 0 {
		free(old_memory, loc);
		return nil;
	}

	if new_size == old_size do return old_memory;

	new_memory := alloc(new_size, alignment, loc);
	if new_memory == nil do return nil;

	__mem_copy(new_memory, old_memory, min(old_size, new_size));;
	free(old_memory, loc);
	return new_memory;
}


default_allocator_proc :: proc(allocator_data: rawptr, mode: Allocator_Mode,
                               size, alignment: int,
                               old_memory: rawptr, old_size: int, flags: u64 = 0, loc := #caller_location) -> rawptr {
	using Allocator_Mode;

	switch mode {
	case Alloc:
		return os.heap_alloc(size);

	case Free:
		os.heap_free(old_memory);
		return nil;

	case Free_All:
		// NOTE(bill): Does nothing

	case Resize:
		ptr := os.heap_resize(old_memory, size);
		assert(ptr != nil);
		return ptr;
	}

	return nil;
}

default_allocator :: proc() -> Allocator {
	return Allocator{
		procedure = default_allocator_proc,
		data = nil,
	};
}

nil_allocator_proc :: proc(allocator_data: rawptr, mode: Allocator_Mode,
                           size, alignment: int,
                           old_memory: rawptr, old_size: int, flags: u64 = 0, loc := #caller_location) -> rawptr {
	return nil;
}

nil_allocator :: proc() -> Allocator {
	return Allocator{
		procedure = nil_allocator_proc,
		data = nil,
	};
}


__print_u64 :: proc(fd: os.Handle, u: u64) {
	digits := "0123456789";

	a: [129]byte;
	i := len(a);
	b := u64(10);
	for u >= b {
		i -= 1; a[i] = digits[u % b];
		u /= b;
	}
	i -= 1; a[i] = digits[u % b];

	os.write(fd, a[i..]);
}

__print_i64 :: proc(fd: os.Handle, u: i64) {
	digits := "0123456789";

	neg := u < 0;
	u = abs(u);

	a: [129]byte;
	i := len(a);
	b := i64(10);
	for u >= b {
		i -= 1; a[i] = digits[u % b];
		u /= b;
	}
	i -= 1; a[i] = digits[u % b];
	if neg {
		i -= 1; a[i] = '-';
	}

	os.write(fd, a[i..]);
}

__print_caller_location :: proc(fd: os.Handle, using loc: Source_Code_Location) {
	os.write_string(fd, file_path);
	os.write_byte(fd, '(');
	__print_u64(fd, u64(line));
	os.write_byte(fd, ':');
	__print_u64(fd, u64(column));
	os.write_byte(fd, ')');
}
__print_typeid :: proc(fd: os.Handle, id: typeid) {
	ti := type_info_of(id);
	__print_type(fd, ti);
}
__print_type :: proc(fd: os.Handle, ti: ^Type_Info) {
	if ti == nil {
		os.write_string(fd, "nil");
		return;
	}

	switch info in ti.variant {
	case Type_Info_Named:
		os.write_string(fd, info.name);
	case Type_Info_Integer:
		a := any{typeid = typeid_of(ti)};
		switch _ in a {
		case int:     os.write_string(fd, "int");
		case uint:    os.write_string(fd, "uint");
		case uintptr: os.write_string(fd, "uintptr");
		case:
			os.write_byte(fd, info.signed ? 'i' : 'u');
			__print_u64(fd, u64(8*ti.size));
		}
	case Type_Info_Rune:
		os.write_string(fd, "rune");
	case Type_Info_Float:
		os.write_byte(fd, 'f');
		__print_u64(fd, u64(8*ti.size));
	case Type_Info_Complex:
		os.write_string(fd, "complex");
		__print_u64(fd, u64(8*ti.size));
	case Type_Info_String:
		os.write_string(fd, "string");
	case Type_Info_Boolean:
		a := any{typeid = typeid_of(ti)};
		switch _ in a {
		case bool: os.write_string(fd, "bool");
		case:
			os.write_byte(fd, 'b');
			__print_u64(fd, u64(8*ti.size));
		}
	case Type_Info_Any:
		os.write_string(fd, "any");
	case Type_Info_Type_Id:
		os.write_string(fd, "typeid");

	case Type_Info_Pointer:
		if info.elem == nil {
			os.write_string(fd, "rawptr");
		} else {
			os.write_string(fd, "^");
			__print_type(fd, info.elem);
		}
	case Type_Info_Procedure:
		os.write_string(fd, "proc");
		if info.params == nil {
			os.write_string(fd, "()");
		} else {
			t := info.params.variant.(Type_Info_Tuple);
			os.write_string(fd, "(");
			for t, i in t.types {
				if i > 0 do os.write_string(fd, ", ");
				__print_type(fd, t);
			}
			os.write_string(fd, ")");
		}
		if info.results != nil {
			os.write_string(fd, " -> ");
			__print_type(fd, info.results);
		}
	case Type_Info_Tuple:
		count := len(info.names);
		if count != 1 do os.write_string(fd, "(");
		for name, i in info.names {
			if i > 0 do os.write_string(fd, ", ");

			t := info.types[i];

			if len(name) > 0 {
				os.write_string(fd, name);
				os.write_string(fd, ": ");
			}
			__print_type(fd, t);
		}
		if count != 1 do os.write_string(fd, ")");

	case Type_Info_Array:
		os.write_string(fd, "[");
		__print_u64(fd, u64(info.count));
		os.write_string(fd, "]");
		__print_type(fd, info.elem);
	case Type_Info_Dynamic_Array:
		os.write_string(fd, "[dynamic]");
		__print_type(fd, info.elem);
	case Type_Info_Slice:
		os.write_string(fd, "[]");
		__print_type(fd, info.elem);

	case Type_Info_Map:
		os.write_string(fd, "map[");
		__print_type(fd, info.key);
		os.write_byte(fd, ']');
		__print_type(fd, info.value);

	case Type_Info_Struct:
		os.write_string(fd, "struct ");
		if info.is_packed    do os.write_string(fd, "#packed ");
		if info.is_raw_union do os.write_string(fd, "#raw_union ");
		if info.custom_align {
			os.write_string(fd, "#align ");
			__print_u64(fd, u64(ti.align));
			os.write_byte(fd, ' ');
		}
		os.write_byte(fd, '{');
		for name, i in info.names {
			if i > 0 do os.write_string(fd, ", ");
			os.write_string(fd, name);
			os.write_string(fd, ": ");
			__print_type(fd, info.types[i]);
		}
		os.write_byte(fd, '}');

	case Type_Info_Union:
		os.write_string(fd, "union {");
		for variant, i in info.variants {
			if i > 0 do os.write_string(fd, ", ");
			__print_type(fd, variant);
		}
		os.write_string(fd, "}");

	case Type_Info_Enum:
		os.write_string(fd, "enum ");
		__print_type(fd, info.base);
		os.write_string(fd, " {");
		for name, i in info.names {
			if i > 0 do os.write_string(fd, ", ");
			os.write_string(fd, name);
		}
		os.write_string(fd, "}");

	case Type_Info_Bit_Field:
		os.write_string(fd, "bit_field ");
		if ti.align != 1 {
			os.write_string(fd, "#align ");
			__print_u64(fd, u64(ti.align));
			os.write_byte(fd, ' ');
		}
		os.write_string(fd, " {");
		for name, i in info.names {
			if i > 0 do os.write_string(fd, ", ");
			os.write_string(fd, name);
			os.write_string(fd, ": ");
			__print_u64(fd, u64(info.bits[i]));
		}
		os.write_string(fd, "}");
	}
}


assert :: proc "contextless" (condition: bool, message := "", using loc := #caller_location) -> bool {
	if !condition {
		fd := os.stderr;
		__print_caller_location(fd, loc);
		os.write_string(fd, " Runtime assertion");
		if len(message) > 0 {
			os.write_string(fd, ": ");
			os.write_string(fd, message);
		}
		os.write_byte(fd, '\n');
		__debug_trap();
	}
	return condition;
}

panic :: proc "contextless" (message := "", using loc := #caller_location) {
	fd := os.stderr;
	__print_caller_location(fd, loc);
	os.write_string(fd, " Panic");
	if len(message) > 0 {
		os.write_string(fd, ": ");
		os.write_string(fd, message);
	}
	os.write_byte(fd, '\n');
	__debug_trap();
}


buffer_from_slice :: proc(backing: $T/[]$E) -> [dynamic]E {
	s := transmute(raw.Slice)backing;
	d := raw.Dynamic_Array{
		data      = s.data,
		len       = 0,
		cap       = s.len,
		allocator = nil_allocator(),
	};
	return transmute([dynamic]E)d;
}














__string_eq :: proc "contextless" (a, b: string) -> bool {
	switch {
	case len(a) != len(b): return false;
	case len(a) == 0:      return true;
	case &a[0] == &b[0]:   return true;
	}
	return __string_cmp(a, b) == 0;
}

__string_cmp :: proc "contextless" (a, b: string) -> int {
	return __mem_compare(&a[0], &b[0], min(len(a), len(b)));
}

__string_ne :: inline proc "contextless" (a, b: string) -> bool { return !__string_eq(a, b); }
__string_lt :: inline proc "contextless" (a, b: string) -> bool { return __string_cmp(a, b) < 0; }
__string_gt :: inline proc "contextless" (a, b: string) -> bool { return __string_cmp(a, b) > 0; }
__string_le :: inline proc "contextless" (a, b: string) -> bool { return __string_cmp(a, b) <= 0; }
__string_ge :: inline proc "contextless" (a, b: string) -> bool { return __string_cmp(a, b) >= 0; }

__cstring_len :: proc "contextless" (s: cstring) -> int {
	n := 0;
	for p := (^byte)(s); p != nil && p^ != 0; p = mem.ptr_offset(p, 1) {
		n += 1;
	}
	return n;
}

__cstring_to_string :: proc "contextless" (s: cstring) -> string {
	if s == nil do return "";
	ptr := (^byte)(s);
	n := __cstring_len(s);
	return transmute(string)raw.String{ptr, n};
}


__complex64_eq :: inline proc "contextless"  (a, b: complex64)  -> bool { return real(a) == real(b) && imag(a) == imag(b); }
__complex64_ne :: inline proc "contextless"  (a, b: complex64)  -> bool { return real(a) != real(b) || imag(a) != imag(b); }

__complex128_eq :: inline proc "contextless" (a, b: complex128) -> bool { return real(a) == real(b) && imag(a) == imag(b); }
__complex128_ne :: inline proc "contextless" (a, b: complex128) -> bool { return real(a) != real(b) || imag(a) != imag(b); }


__bounds_check_error :: proc "contextless" (file: string, line, column: int, index, count: int) {
	if 0 <= index && index < count do return;

	fd := os.stderr;
	__print_caller_location(fd, Source_Code_Location{file, line, column, ""});
	os.write_string(fd, " Index ");
	__print_i64(fd, i64(index));
	os.write_string(fd, " is out of bounds range 0..");
	__print_i64(fd, i64(count));
	os.write_byte(fd, '\n');
	__debug_trap();
}

__slice_expr_error :: proc "contextless" (file: string, line, column: int, lo, hi: int, len: int) {
	if 0 <= lo && lo <= hi && hi <= len do return;


	fd := os.stderr;
	__print_caller_location(fd, Source_Code_Location{file, line, column, ""});
	os.write_string(fd, " Invalid slice indices: ");
	__print_i64(fd, i64(lo));
	os.write_string(fd, "..");
	__print_i64(fd, i64(hi));
	os.write_string(fd, "..");
	__print_i64(fd, i64(len));
	os.write_byte(fd, '\n');
	__debug_trap();
}

__dynamic_array_expr_error :: proc "contextless" (file: string, line, column: int, low, high, max: int) {
	if 0 <= low && low <= high && high <= max do return;

	fd := os.stderr;
	__print_caller_location(fd, Source_Code_Location{file, line, column, ""});
	os.write_string(fd, " Invalid dynamic array values: ");
	__print_i64(fd, i64(low));
	os.write_string(fd, "..");
	__print_i64(fd, i64(high));
	os.write_string(fd, "..");
	__print_i64(fd, i64(max));
	os.write_byte(fd, '\n');
	__debug_trap();
}

__type_assertion_check :: proc "contextless" (ok: bool, file: string, line, column: int, from, to: typeid) {
	if ok do return;

	fd := os.stderr;
	__print_caller_location(fd, Source_Code_Location{file, line, column, ""});
	os.write_string(fd, " Invalid type assertion from");
	__print_typeid(fd, from);
	os.write_string(fd, " to ");
	__print_typeid(fd, to);
	os.write_byte(fd, '\n');
	__debug_trap();
}

__string_decode_rune :: inline proc "contextless" (s: string) -> (rune, int) {
	return utf8.decode_rune_from_string(s);
}

__bounds_check_error_loc :: inline proc "contextless" (using loc := #caller_location, index, count: int) {
	__bounds_check_error(file_path, int(line), int(column), index, count);
}
__slice_expr_error_loc :: inline proc "contextless" (using loc := #caller_location, lo, hi: int, len: int) {
	__slice_expr_error(file_path, int(line), int(column), lo, hi, len);
}

__mem_set :: proc "contextless" (data: rawptr, value: i32, len: int) -> rawptr {
	if data == nil do return nil;
	foreign __llvm_core {
		when size_of(rawptr) == 8 {
			@(link_name="llvm.memset.p0i8.i64")
			llvm_memset :: proc(dst: rawptr, val: byte, len: int, align: i32, is_volatile: bool) ---;
		} else {
			@(link_name="llvm.memset.p0i8.i32")
			llvm_memset :: proc(dst: rawptr, val: byte, len: int, align: i32, is_volatile: bool) ---;
		}
	}
	llvm_memset(data, byte(value), len, 1, false);
	return data;
}
__mem_zero :: proc "contextless" (data: rawptr, len: int) -> rawptr {
	return __mem_set(data, 0, len);
}
__mem_copy :: proc "contextless" (dst, src: rawptr, len: int) -> rawptr {
	if src == nil do return dst;
	// NOTE(bill): This _must_ be implemented like C's memmove
	foreign __llvm_core {
		when size_of(rawptr) == 8 {
			@(link_name="llvm.memmove.p0i8.p0i8.i64")
			llvm_memmove :: proc(dst, src: rawptr, len: int, align: i32, is_volatile: bool) ---;
		} else {
			@(link_name="llvm.memmove.p0i8.p0i8.i32")
			llvm_memmove :: proc(dst, src: rawptr, len: int, align: i32, is_volatile: bool) ---;
		}
	}
	llvm_memmove(dst, src, len, 1, false);
	return dst;
}
__mem_copy_non_overlapping :: proc "contextless" (dst, src: rawptr, len: int) -> rawptr {
	if src == nil do return dst;
	// NOTE(bill): This _must_ be implemented like C's memcpy
	foreign __llvm_core {
		when size_of(rawptr) == 8 {
			@(link_name="llvm.memcpy.p0i8.p0i8.i64")
	 		llvm_memcpy :: proc(dst, src: rawptr, len: int, align: i32, is_volatile: bool) ---;
		} else {
			@(link_name="llvm.memcpy.p0i8.p0i8.i32")
	 		llvm_memcpy :: proc(dst, src: rawptr, len: int, align: i32, is_volatile: bool) ---;
		}
	}
	llvm_memcpy(dst, src, len, 1, false);
	return dst;
}

__mem_compare :: proc "contextless" (a, b: ^byte, n: int) -> int {
	pa :: mem.ptr_offset;
	for i in 0..n do switch {
	case pa(a, i)^ < pa(b, i)^: return -1;
	case pa(a, i)^ > pa(b, i)^: return +1;
	}
	return 0;
}

@(default_calling_convention = "c")
foreign __llvm_core {
	@(link_name="llvm.sqrt.f32") __sqrt_f32 :: proc(x: f32) -> f32 ---;
	@(link_name="llvm.sqrt.f64") __sqrt_f64 :: proc(x: f64) -> f64 ---;

	@(link_name="llvm.sin.f32") __sin_f32  :: proc(θ: f32) -> f32 ---;
	@(link_name="llvm.sin.f64") __sin_f64  :: proc(θ: f64) -> f64 ---;

	@(link_name="llvm.cos.f32") __cos_f32  :: proc(θ: f32) -> f32 ---;
	@(link_name="llvm.cos.f64") __cos_f64  :: proc(θ: f64) -> f64 ---;

	@(link_name="llvm.pow.f32") __pow_f32  :: proc(x, power: f32) -> f32 ---;
	@(link_name="llvm.pow.f64") __pow_f64  :: proc(x, power: f64) -> f64 ---;

	@(link_name="llvm.fmuladd.f32") fmuladd32  :: proc(a, b, c: f32) -> f32 ---;
	@(link_name="llvm.fmuladd.f64") fmuladd64  :: proc(a, b, c: f64) -> f64 ---;
}
__abs_f32 :: inline proc "contextless" (x: f32) -> f32 {
	foreign __llvm_core {
		@(link_name="llvm.fabs.f32") _abs :: proc "c" (x: f32) -> f32 ---;
	}
	return _abs(x);
}
__abs_f64 :: inline proc "contextless" (x: f64) -> f64 {
	foreign __llvm_core {
		@(link_name="llvm.fabs.f64") _abs :: proc "c" (x: f64) -> f64 ---;
	}
	return _abs(x);
}

__min_f32 :: proc(a, b: f32) -> f32 {
	foreign __llvm_core {
		@(link_name="llvm.minnum.f32") _min :: proc "c" (a, b: f32) -> f32 ---;
	}
	return _min(a, b);
}
__min_f64 :: proc(a, b: f64) -> f64 {
	foreign __llvm_core {
		@(link_name="llvm.minnum.f64") _min :: proc "c" (a, b: f64) -> f64 ---;
	}
	return _min(a, b);
}
__max_f32 :: proc(a, b: f32) -> f32 {
	foreign __llvm_core {
		@(link_name="llvm.maxnum.f32") _max :: proc "c" (a, b: f32) -> f32 ---;
	}
	return _max(a, b);
}
__max_f64 :: proc(a, b: f64) -> f64 {
	foreign __llvm_core {
		@(link_name="llvm.maxnum.f64") _max :: proc "c" (a, b: f64) -> f64 ---;
	}
	return _max(a, b);
}

__abs_complex64 :: inline proc "contextless" (x: complex64) -> f32 {
	r, i := real(x), imag(x);
	return __sqrt_f32(r*r + i*i);
}
__abs_complex128 :: inline proc "contextless" (x: complex128) -> f64 {
	r, i := real(x), imag(x);
	return __sqrt_f64(r*r + i*i);
}




__dynamic_array_make :: proc(array_: rawptr, elem_size, elem_align: int, len, cap: int, loc := #caller_location) {
	array := (^raw.Dynamic_Array)(array_);
	array.allocator = context.allocator;
	assert(array.allocator.procedure != nil);

	if cap > 0 {
		__dynamic_array_reserve(array_, elem_size, elem_align, cap, loc);
		array.len = len;
	}
}

__dynamic_array_reserve :: proc(array_: rawptr, elem_size, elem_align: int, cap: int, loc := #caller_location) -> bool {
	array := (^raw.Dynamic_Array)(array_);

	if cap <= array.cap do return true;

	if array.allocator.procedure == nil {
		array.allocator = context.allocator;
	}
	assert(array.allocator.procedure != nil);

	old_size  := array.cap * elem_size;
	new_size  := cap * elem_size;
	allocator := array.allocator;

	new_data := allocator.procedure(allocator.data, Allocator_Mode.Resize, new_size, elem_align, array.data, old_size, 0, loc);
	if new_data == nil do return false;

	array.data = new_data;
	array.cap = cap;
	return true;
}

__dynamic_array_resize :: proc(array_: rawptr, elem_size, elem_align: int, len: int, loc := #caller_location) -> bool {
	array := (^raw.Dynamic_Array)(array_);

	ok := __dynamic_array_reserve(array_, elem_size, elem_align, len, loc);
	if ok do array.len = len;
	return ok;
}


__dynamic_array_append :: proc(array_: rawptr, elem_size, elem_align: int,
                               items: rawptr, item_count: int, loc := #caller_location) -> int {
	array := (^raw.Dynamic_Array)(array_);

	if items == nil    do return 0;
	if item_count <= 0 do return 0;


	ok := true;
	if array.cap <= array.len+item_count {
		cap := 2 * array.cap + max(8, item_count);
		ok = __dynamic_array_reserve(array, elem_size, elem_align, cap, loc);
	}
	// TODO(bill): Better error handling for failed reservation
	if !ok do return array.len;

	assert(array.data != nil);
	data := uintptr(array.data) + uintptr(elem_size*array.len);

	__mem_copy(rawptr(data), items, elem_size * item_count);
	array.len += item_count;
	return array.len;
}

__dynamic_array_append_nothing :: proc(array_: rawptr, elem_size, elem_align: int, loc := #caller_location) -> int {
	array := (^raw.Dynamic_Array)(array_);

	ok := true;
	if array.cap <= array.len+1 {
		cap := 2 * array.cap + max(8, 1);
		ok = __dynamic_array_reserve(array, elem_size, elem_align, cap, loc);
	}
	// TODO(bill): Better error handling for failed reservation
	if !ok do return array.len;

	assert(array.data != nil);
	data := uintptr(array.data) + uintptr(elem_size*array.len);
	__mem_zero(rawptr(data), elem_size);
	array.len += 1;
	return array.len;
}

// Map stuff

__default_hash :: proc(data: []byte) -> u64 {
	fnv64a :: proc(data: []byte) -> u64 {
		h: u64 = 0xcbf29ce484222325;
		for b in data {
			h = (h ~ u64(b)) * 0x100000001b3;
		}
		return h;
	}
	return fnv64a(data);
}
__default_hash_string :: proc(s: string) -> u64 do return __default_hash(([]byte)(s));

__dynamic_map_reserve :: proc(using header: __Map_Header, cap: int, loc := #caller_location) {
	__dynamic_array_reserve(&m.hashes, size_of(int), align_of(int), cap, loc);
	__dynamic_array_reserve(&m.entries, entry_size, entry_align,    cap, loc);
}
__dynamic_map_rehash :: proc(using header: __Map_Header, new_count: int, loc := #caller_location) #no_bounds_check {
	new_header: __Map_Header = header;
	nm: raw.Map;
	new_header.m = &nm;

	header_hashes := (^raw.Dynamic_Array)(&header.m.hashes);
	nm_hashes     := (^raw.Dynamic_Array)(&nm.hashes);

	__dynamic_array_resize(nm_hashes, size_of(int), align_of(int), new_count, loc);
	__dynamic_array_reserve(&nm.entries, entry_size, entry_align, m.entries.len, loc);
	for i in 0..new_count do nm.hashes[i] = -1;

	for i in 0..m.entries.len {
		if len(nm.hashes) == 0 do __dynamic_map_grow(new_header, loc);

		entry_header := __dynamic_map_get_entry(header, i);
		data := uintptr(entry_header);

		fr := __dynamic_map_find(new_header, entry_header.key);
		j := __dynamic_map_add_entry(new_header, entry_header.key, loc);
		if fr.entry_prev < 0 {
			nm.hashes[fr.hash_index] = j;
		} else {
			e := __dynamic_map_get_entry(new_header, fr.entry_prev);
			e.next = j;
		}

		e := __dynamic_map_get_entry(new_header, j);
		e.next = fr.entry_index;
		ndata := uintptr(e);
		__mem_copy(rawptr(ndata+value_offset), rawptr(data+value_offset), value_size);

		if __dynamic_map_full(new_header) do __dynamic_map_grow(new_header, loc);
	}
	free_ptr_with_allocator(header_hashes.allocator, header_hashes.data, loc);
	free_ptr_with_allocator(header.m.entries.allocator, header.m.entries.data, loc);
	header.m^ = nm;
}

__dynamic_map_get :: proc(h: __Map_Header, key: __Map_Key) -> rawptr {
	index := __dynamic_map_find(h, key).entry_index;
	if index >= 0 {
		data := uintptr(__dynamic_map_get_entry(h, index));
		return rawptr(data + h.value_offset);
	}
	return nil;
}

__dynamic_map_set :: proc(h: __Map_Header, key: __Map_Key, value: rawptr, loc := #caller_location) #no_bounds_check {

	index: int;
	assert(value != nil);

	if len(h.m.hashes) == 0 {
		__dynamic_map_reserve(h, __INITIAL_MAP_CAP, loc);
		__dynamic_map_grow(h, loc);
	}

	fr := __dynamic_map_find(h, key);
	if fr.entry_index >= 0 {
		index = fr.entry_index;
	} else {
		index = __dynamic_map_add_entry(h, key, loc);
		if fr.entry_prev >= 0 {
			entry := __dynamic_map_get_entry(h, fr.entry_prev);
			entry.next = index;
		} else {
			h.m.hashes[fr.hash_index] = index;
		}
	}
	{
		e := __dynamic_map_get_entry(h, index);
		e.key = key;
		val := (^byte)(uintptr(e) + h.value_offset);
		__mem_copy(val, value, h.value_size);
	}

	if __dynamic_map_full(h) {
		__dynamic_map_grow(h, loc);
	}
}


__dynamic_map_grow :: proc(using h: __Map_Header, loc := #caller_location) {
	// TODO(bill): Determine an efficient growing rate
	new_count := max(4*m.entries.cap + 7, __INITIAL_MAP_CAP);
	__dynamic_map_rehash(h, new_count, loc);
}

__dynamic_map_full :: inline proc(using h: __Map_Header) -> bool {
	return int(0.75 * f64(len(m.hashes))) <= m.entries.cap;
}


__dynamic_map_hash_equal :: proc(h: __Map_Header, a, b: __Map_Key) -> bool {
	if a.hash == b.hash {
		if h.is_key_string do return a.str == b.str;
		return true;
	}
	return false;
}

__dynamic_map_find :: proc(using h: __Map_Header, key: __Map_Key) -> __Map_Find_Result #no_bounds_check {
	fr := __Map_Find_Result{-1, -1, -1};
	if len(m.hashes) > 0 {
		fr.hash_index = int(key.hash % u64(len(m.hashes)));
		fr.entry_index = m.hashes[fr.hash_index];
		for fr.entry_index >= 0 {
			entry := __dynamic_map_get_entry(h, fr.entry_index);
			if __dynamic_map_hash_equal(h, entry.key, key) do return fr;
			fr.entry_prev = fr.entry_index;
			fr.entry_index = entry.next;
		}
	}
	return fr;
}

__dynamic_map_add_entry :: proc(using h: __Map_Header, key: __Map_Key, loc := #caller_location) -> int {
	prev := m.entries.len;
	c := __dynamic_array_append_nothing(&m.entries, entry_size, entry_align, loc);
	if c != prev {
		end := __dynamic_map_get_entry(h, c-1);
		end.key = key;
		end.next = -1;
	}
	return prev;
}

__dynamic_map_delete :: proc(using h: __Map_Header, key: __Map_Key) {
	fr := __dynamic_map_find(h, key);
	if fr.entry_index >= 0 {
		__dynamic_map_erase(h, fr);
	}
}

__dynamic_map_get_entry :: proc(using h: __Map_Header, index: int) -> ^__Map_Entry_Header {
	assert(0 <= index && index < m.entries.len);
	return (^__Map_Entry_Header)(uintptr(m.entries.data) + uintptr(index*entry_size));
}

__dynamic_map_erase :: proc(using h: __Map_Header, fr: __Map_Find_Result) #no_bounds_check {
	if fr.entry_prev < 0 {
		m.hashes[fr.hash_index] = __dynamic_map_get_entry(h, fr.entry_index).next;
	} else {
		__dynamic_map_get_entry(h, fr.entry_prev).next = __dynamic_map_get_entry(h, fr.entry_index).next;
	}

	__mem_copy(__dynamic_map_get_entry(h, fr.entry_index), __dynamic_map_get_entry(h, m.entries.len-1), entry_size);
	last := __dynamic_map_find(h, __dynamic_map_get_entry(h, fr.entry_index).key);
	if last.entry_prev >= 0 {
		__dynamic_map_get_entry(h, last.entry_prev).next = fr.entry_index;
	} else {
		m.hashes[last.hash_index] = fr.entry_index;
	}

	if fr.entry_index == m.entries.len-1 {
		m.entries.len -= 1;
	}
}
