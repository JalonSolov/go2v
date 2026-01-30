// Copyright (c) 2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can be found in the LICENSE file.

fn (mut app App) unique_name_anti_shadow(n string) string {
	if n == '_' {
		return '_'
	}
	if n !in app.cur_fn_names {
		return n
	}
	// Increase the i in `name_i` until it's unique.
	mut i := 1
	mut res := ''
	for {
		res = '${n}_${i}'

		if res !in app.cur_fn_names {
			break
		}
		i++
		if i > 100 {
			panic('100 levels of shadowing, that cannot be real!')
		}
	}
	// res := n + rand.intn(10000) or { 0 }.str() // LOL fix this
	return res
}

// Check if an expression contains a reference to a specific identifier
fn (app App) expr_contains_ident(e Expr, name string) bool {
	match e {
		Ident {
			return e.name == name
		}
		CallExpr {
			// Check function name and all arguments
			if app.expr_contains_ident(e.fun, name) {
				return true
			}
			for arg in e.args {
				if app.expr_contains_ident(arg, name) {
					return true
				}
			}
		}
		BinaryExpr {
			return app.expr_contains_ident(e.x, name) || app.expr_contains_ident(e.y, name)
		}
		UnaryExpr {
			return app.expr_contains_ident(e.x, name)
		}
		SelectorExpr {
			return app.expr_contains_ident(e.x, name)
		}
		IndexExpr {
			return app.expr_contains_ident(e.x, name) || app.expr_contains_ident(e.index, name)
		}
		SliceExpr {
			if app.expr_contains_ident(e.x, name) {
				return true
			}
			if e.low !is InvalidExpr && app.expr_contains_ident(e.low, name) {
				return true
			}
			if e.high !is InvalidExpr && app.expr_contains_ident(e.high, name) {
				return true
			}
		}
		StarExpr {
			return app.expr_contains_ident(e.x, name)
		}
		ParenExpr {
			return app.expr_contains_ident(e.x, name)
		}
		CompositeLit {
			for elt in e.elts {
				if app.expr_contains_ident(elt, name) {
					return true
				}
			}
		}
		KeyValueExpr {
			return app.expr_contains_ident(e.key, name) || app.expr_contains_ident(e.value, name)
		}
		else {}
	}
	return false
}

fn (mut app App) assign_stmt(assign AssignStmt, no_mut bool) {
	// Special case for 'append()' => '<<' - check this first before generating LHS
	// because we don't want to add 'mut' for append operations
	if app.check_and_handle_append_early(assign) {
		return
	}

	// Check if this is an assignment to a named return param that needs to be converted to declaration
	// But only if the LHS variable is NOT used on the RHS (to avoid circular reference)
	mut convert_to_decl := false
	if assign.tok == '=' && assign.lhs.len == 1 {
		if assign.lhs[0] is Ident {
			lhs_ident := assign.lhs[0] as Ident
			lhs_name := lhs_ident.name
			if lhs_name in app.named_return_params && lhs_name !in app.cur_fn_names {
				// Check if lhs_name is used in RHS - if so, don't convert to declaration
				// because the variable needs to be pre-declared for the RHS to reference it
				mut used_in_rhs := false
				for rhs in assign.rhs {
					if app.expr_contains_ident(rhs, lhs_name) {
						used_in_rhs = true
						break
					}
				}
				if !used_in_rhs {
					convert_to_decl = true
				}
			}
		}
	}

	// Collect pending name mappings - don't apply until after RHS processing
	// This ensures that `x := x + 1` uses the outer x on RHS, not the new x
	mut pending_mappings := map[string]string{}

	for l_idx, lhs_expr in assign.lhs {
		if l_idx == 0 {
			match lhs_expr {
				Ident {
					if lhs_expr.name != '_' {
						if !no_mut {
							if assign.tok == ':=' || convert_to_decl {
								app.gen('mut ')
							}
						}
					}
				}
				else {}
			}
		} else {
			app.gen(', ')
		}
		if lhs_expr is Ident {
			// Handle shadowing - convert to V name first before checking
			go_name := lhs_expr.name // Original Go name
			mut n := app.go2v_ident(go_name)
			if (assign.tok == ':=' || convert_to_decl) && n != '_' && n in app.cur_fn_names {
				n = app.unique_name_anti_shadow(n)
				// Queue the mapping for later - don't apply yet
				pending_mappings[go_name] = n
			}
			app.cur_fn_names[n] = true
			app.gen(n)
		} else if lhs_expr is StarExpr {
			// Can't use star_expr(), since it generates &
			app.gen('*')
			app.expr(lhs_expr.x)
		} else {
			app.expr(lhs_expr)
		}
	}

	// Use := for named return param conversion
	if convert_to_decl {
		app.gen(':=')
	} else {
		app.gen(assign.tok)
	}

	for r_idx, rhs_expr in assign.rhs {
		mut needs_close_paren := false
		if r_idx > 0 {
			app.gen(', ')
		}
		match rhs_expr {
			BasicLit {
				v_kind := rhs_expr.kind.to_lower()
				if v_kind != 'int' && v_kind != 'string' {
					app.gen('${go2v_type(v_kind)}(')
					needs_close_paren = true
				} else {
					v_type := go2v_type(v_kind)
					if v_type != v_kind {
						app.gen(go2v_type(v_kind))
						app.gen('(')
						needs_close_paren = true
					}
				}
			}
			else {}
		}
		app.expr(rhs_expr)
		if needs_close_paren {
			app.gen(')')
		}
	}

	// Now apply the pending name mappings after RHS has been processed
	for go_name, v_name in pending_mappings {
		app.name_mapping[go_name] = v_name
	}

	app.genln('')
}

fn (mut app App) is_append_call(assign AssignStmt) bool {
	if assign.rhs.len == 0 {
		return false
	}
	first_rhs := assign.rhs[0]
	if first_rhs is CallExpr {
		fun := first_rhs.fun
		if fun is Ident {
			if fun.name == 'append' {
				return true
			}
		}
	}
	return false
}

fn (mut app App) check_and_handle_append_early(assign AssignStmt) bool {
	if !app.is_append_call(assign) {
		return false
	}
	// Generate LHS without mut
	for l_idx, lhs_expr in assign.lhs {
		if l_idx > 0 {
			app.gen(', ')
		}
		app.expr(lhs_expr)
	}
	first_rhs := assign.rhs[0]
	if first_rhs is CallExpr {
		app.gen_append(first_rhs.args, assign.tok)
	}
	return true
}

fn (mut app App) check_and_handle_append(assign AssignStmt) bool {
	if assign.rhs.len == 0 {
		app.genln('// append no rhs')
		return false
	}
	first_rhs := assign.rhs[0]
	if first_rhs is CallExpr {
		fun := first_rhs.fun
		if fun is Ident {
			if fun.name == 'append' {
				app.gen_append(first_rhs.args, assign.tok)
				return true
			}
		}
	}
	return false
}

fn (mut app App) gen_append(args []Expr, assign_tok string) {
	// Handle special case `mut x := arr.clone()`
	// In Go it's
	// `append([]Foo{}, foo...)`

	arg0 := args[0]
	if arg0 is CompositeLit && arg0.typ is ArrayType {
		app.gen(' ${assign_tok} ')
		app.expr(args[1])
		app.gen('.')
		app.genln('clone()')
		return
	}

	app.gen(' << ')
	if args.len == 2 {
		app.expr(args[1])
		app.genln('')
		return
	}

	for i := 1; i < args.len; i++ {
		arg_i := args[i]
		match arg_i {
			BasicLit {
				v_kind := go2v_type(arg_i.kind.to_lower())
				needs_cast := v_kind != 'int'
				if i == 1 {
					app.gen('[')
					if needs_cast {
						app.gen('${go2v_type(v_kind)}(')
					}
				}
				app.expr(arg_i)
				if i == 1 && needs_cast {
					app.gen(')')
				}
				if i < args.len - 1 {
					app.gen(',')
				} else if i == args.len - 1 {
					app.gen(']')
				}
			}
			else {
				if i == 1 {
					app.gen('[')
				}
				app.expr(arg_i)
				if i < args.len - 1 {
					app.gen(',')
				} else if i == args.len - 1 {
					app.gen(']')
				}
			}
		}
	}
	app.genln('')
}
