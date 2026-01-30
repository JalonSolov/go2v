// Copyright (c) 2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can be found in the LICENSE file.

// go2v_type converts Go types to V types
// Returns (converted_type, is_basic_type)
fn go2v_type(typ string) string {
	return go2v_type_checked(typ).v_type
}

struct TypeConversion {
	v_type   string
	is_basic bool
}

fn go2v_type_checked(typ string) TypeConversion {
	match typ {
		// Basic types that need conversion
		'byte' {
			return TypeConversion{'u8', true}
		}
		'char' {
			return TypeConversion{'u8', true}
		}
		'float32' {
			return TypeConversion{'f32', true}
		}
		'float64' {
			return TypeConversion{'f64', true}
		}
		'int' {
			return TypeConversion{'isize', true}
		}
		'int8' {
			return TypeConversion{'i8', true}
		}
		'int16' {
			return TypeConversion{'i16', true}
		}
		'int32' {
			return TypeConversion{'i32', true}
		}
		'int64' {
			return TypeConversion{'i64', true}
		}
		'String' {
			return TypeConversion{'string', true}
		}
		'uint' {
			return TypeConversion{'usize', true}
		}
		'uint8' {
			return TypeConversion{'u8', true}
		}
		'uint16' {
			return TypeConversion{'u16', true}
		}
		'uint32' {
			return TypeConversion{'u32', true}
		}
		'uint64' {
			return TypeConversion{'u64', true}
		}
		// Basic types that stay the same
		'string', 'bool', 'voidptr', 'rune' {
			return TypeConversion{typ, true}
		}
		else {}
	}
	return TypeConversion{typ, false}
}

// V keywords that need escaping - split into regular keywords and literals
const v_keywords = ['match', 'in', 'fn', 'as', 'enum', 'typeof']
const v_literals = ['true', 'false', 'none'] // These are only escaped when converted from different case

fn (mut app App) go2v_ident(ident string) string {
	mut id := ident

	if id == 'nil' {
		return 'unsafe { nil }'
	}

	// Preserve original casing for struct/type aliases
	if ident in app.struct_or_alias {
		was_force_upper := app.force_upper
		app.force_upper = false // Reset force_upper even for early return
		// Single capital letter names need to be doubled (reserved for generics in V)
		if id.len == 1 && id[0].is_capital() {
			return id + id
		}
		// Type aliases in V must start with capital letter
		if was_force_upper && !id[0].is_capital() {
			return id.capitalize()
		}
		return id
	}

	if app.force_upper {
		app.force_upper = false
		id_typ := go2v_type(id)
		if id_typ != id {
			return id_typ
		}
		id = id.capitalize()
	} else {
		id = id.camel_to_snake()
	}

	// Always escape V keywords (match, in, fn, as, etc.)
	if id in v_keywords {
		id = id + '_'
	}

	// Only escape V literals (true, false, none) if they came from a different case
	// This allows Go boolean literals to pass through unchanged
	if id in v_literals && id != ident {
		id = id + '_'
	}

	return id
}
