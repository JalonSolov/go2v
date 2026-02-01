// Copyright (c) 2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can be found in the LICENSE file.
module main

fn (mut app App) gen_zero_value(t Type) {
	match t {
		MapType {
			app.map_type(t)
			app.gen('{}')
		}
		ArrayType {
			app.force_upper = true
			app.array_type(t)
			app.gen('{}')
		}
		Ident {
			// Check if it's a basic type
			v_type := go2v_type(t.name)
			match v_type {
				'string' {
					app.gen("''")
				}
				'bool' {
					app.gen('false')
				}
				'isize', 'i8', 'i16', 'i32', 'i64', 'usize', 'u8', 'u16', 'u32', 'u64', 'f32',
				'f64', 'rune' {
					app.gen('0')
				}
				else {
					// Custom type - generate Type{}
					app.force_upper = true
					app.gen(app.go2v_ident(t.name))
					app.gen('{}')
				}
			}
		}
		StarExpr {
			// Pointer type - nil
			app.gen('unsafe { nil }')
		}
		FuncType {
			// Function type - nil
			app.gen('unsafe { nil }')
		}
		else {
			app.gen('0')
		}
	}
}
