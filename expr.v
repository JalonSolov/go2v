// Copyright (c) 2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can be found in the LICENSE file.

fn (mut app App) expr(expr Expr) {
	match expr {
		InvalidExpr {
			print_backtrace()
			eprintln('> invalid expression encountered')
		}
		ArrayType {
			app.array_type(expr)
		}
		BasicLit {
			app.basic_lit(expr)
		}
		BinaryExpr {
			app.binary_expr(expr)
		}
		CallExpr {
			app.call_expr(expr)
		}
		ChanType {
			app.chan_type(expr)
		}
		CompositeLit {
			app.composite_lit(expr)
		}
		Ellipsis {}
		FuncLit {
			app.func_lit(expr)
		}
		FuncType {
			app.func_type(expr)
		}
		Ident {
			app.ident(expr)
		}
		IndexExpr {
			app.index_expr(expr)
		}
		InterfaceType {
			app.interface_type(expr)
		}
		KeyValueExpr {
			app.key_value_expr(expr)
		}
		MapType {
			app.map_type(expr)
		}
		ParenExpr {
			app.paren_expr(expr)
		}
		SelectorExpr {
			app.selector_expr(expr)
		}
		SliceExpr {
			app.slice_expr(expr)
		}
		StarExpr {
			app.star_expr(expr)
		}
		StructType {
			app.struct_type(expr)
		}
		TypeAssertExpr {
			app.type_assert_expr(expr)
		}
		UnaryExpr {
			app.unary_expr(expr)
		}
	}
}

fn (mut app App) array_type(node ArrayType) {
	force_upper := app.force_upper
	app.gen('[')
	if node.len !is InvalidExpr {
		app.expr(node.len)
	}
	app.gen(']')
	app.force_upper = force_upper
	app.expr(node.elt)
}

fn (mut app App) basic_lit(l BasicLit) {
	if l.kind == 'CHAR' {
		app.gen(quoted_lit(l.value, '`'))
	} else if l.kind == 'STRING' {
		app.gen(quoted_lit(l.value, "'"))
	} else {
		app.gen(l.value)
	}
}

fn (mut app App) binary_expr(b BinaryExpr) {
	if b.op == '+' && (b.x is BasicLit || b.y is BasicLit) {
		x := b.x
		y := b.y
		if x is BasicLit && x.kind == 'INT' && y is BasicLit && y.kind == 'INT' {
			app.gen('${x.value}${b.op}${y.value}')
		} else {
			// Use regular concatenation to properly handle string escaping
			app.expr(x)
			app.gen('+')
			app.expr(y)
		}
	} else {
		app.expr(b.x)
		if b.op == '\u0026^' {
			app.gen('&~')
		} else {
			app.gen(b.op)
		}
		app.expr(b.y)
	}
}

fn (mut app App) chan_type(node ChanType) {
	app.gen('chan ')
	app.expr(node.value)
}

fn (mut app App) ident(node Ident) {
	app.gen(go2v_type(app.go2v_ident(node.name)))
}

fn (mut app App) index_expr(s IndexExpr) {
	app.expr(s.x)
	app.gen('[')
	app.expr(s.index)
	app.gen(']')
}

fn (mut app App) key_value_expr(expr KeyValueExpr) {
	if expr.key is Ident {
		app.gen('\t${app.go2v_ident(expr.key.name)}: ')
	} else {
		app.expr(expr.key)
		app.gen(': ')
	}
	app.expr(expr.value)
}

fn (mut app App) map_type(node MapType) {
	app.gen('map[')
	match node.key {
		Ident {
			// Map keys must be capitalized in V for struct types
			conversion := go2v_type_checked(node.key.name)
			if conversion.is_basic {
				app.gen(conversion.v_type)
			} else {
				// Capitalize struct type names for map keys (V requirement)
				app.gen(node.key.name.capitalize())
			}
		}
		SelectorExpr {
			app.typ(node.key)
		}
		else {}
	}
	app.gen(']')
	match node.val {
		ArrayType, Ident, InterfaceType, SelectorExpr, StarExpr {
			app.typ(node.val)
		}
		StructType {
			// Empty struct type, e.g., map[K]struct{}
			app.struct_type(node.val)
		}
	}
}

fn (mut app App) paren_expr(p ParenExpr) {
	app.gen('(')
	app.expr(p.x)
	app.gen(')')
}

fn quoted_lit(s string, quote string) string {
	mut quote2 := quote
	go_quote := s[0]
	mut no_quotes := s[1..s.len - 1]

	mut prefix := ''
	if go_quote == `\`` {
		prefix = 'r'
	}

	// Determine which V quote style to use
	if prefix != 'r' {
		has_single := no_quotes.contains("'")
		has_escaped_double := no_quotes.contains('\\"')

		if has_single && has_escaped_double {
			// String has both ' and \" - use double quotes and keep escaping
			quote2 = '"'
		} else if has_single {
			// String has ' but no \" - use double quotes
			quote2 = '"'
		} else if has_escaped_double {
			// String has \" but no ' - use single quotes and unescape
			quote2 = "'"
			no_quotes = no_quotes.replace('\\"', '"')
		}
		// else: no special chars, use default single quotes
	}

	// Handle '`' => `\``
	if go_quote == `'` {
		no_quotes = no_quotes.replace('`', '\\`')
	}

	return '${prefix}${quote2}${no_quotes}${quote2}'
}

fn (mut app App) selector_expr(s SelectorExpr) {
	force_upper := app.force_upper // save force upper for `mod.ForceUpper`
	app.force_upper = false
	app.expr(s.x)
	app.gen('.')
	app.force_upper = force_upper
	app.gen(app.go2v_ident(s.sel.name))
}

fn (mut app App) slice_expr(node SliceExpr) {
	app.expr(node.x)
	app.gen('[')
	if node.low is InvalidExpr {
	} else {
		app.expr(node.low)
	}
	app.gen('..')
	if node.high is InvalidExpr {
	} else {
		app.expr(node.high)
	}
	app.gen(']')
}

fn (mut app App) star_expr(node StarExpr) {
	if app.no_star {
		app.no_star = false
	} else {
		app.gen('&')
	}
	app.expr(node.x)
}

fn (mut app App) type_assert_expr(t TypeAssertExpr) {
	// TODO more?
	app.expr(t.x)
}

fn (mut app App) unary_expr(u UnaryExpr) {
	if u.op == '^' {
		// In Go bitwise NOT is ^x
		// In V it's ~x, ^ is only used for XOR: x^b
		app.gen('~')
	} else if u.op != '+' {
		app.gen(u.op)
	}
	app.expr(u.x)
}
