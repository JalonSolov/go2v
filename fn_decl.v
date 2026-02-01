// Copyright (c) 2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can be found in the LICENSE file.

fn (mut app App) func_decl(decl FuncDecl) {
	app.cur_fn_names.clear()
	app.name_mapping.clear()
	app.named_return_params.clear()
	app.named_return_types.clear()
	app.error_vars.clear() // Reset error variable tracking at function boundary
	app.force_upper = false // Reset force_upper at function boundary
	app.genln('')
	app.comments(decl.doc)
	// Function names must always be snake_case in V, regardless of whether
	// the name matches a type/struct name (which go2v_ident would preserve)
	mut method_name := decl.name.name.camel_to_snake()

	// Special handling for String() method:
	// - No args: Stringer interface -> str()
	// - With args: custom method -> string_() (with trailing underscore to avoid V's .str())
	if decl.name.name == 'String' {
		if decl.typ.params.list.len == 0 {
			method_name = 'str'
		} else {
			method_name = 'string_'
		}
	} else {
		// Escape V keywords
		if method_name in v_keywords {
			method_name = method_name + '_'
		}
		// Escape V type names (e.g., u64, u32, string, etc.)
		if method_name in v_type_names {
			method_name = method_name + '_'
		}
	}
	// Check for name collision with existing global names
	if method_name in app.global_names {
		mut i := 1
		for {
			new_name := '${method_name}_${i}'
			if new_name !in app.global_names {
				method_name = new_name
				break
			}
			i++
		}
	}
	app.global_names[method_name] = true
	// Capital? Then it's public in Go
	is_pub := decl.name.name[0].is_capital()
	if is_pub {
		app.gen('pub ')
	}
	// println('FUNC DECL ${method_name}')
	// Track named return parameters and their types
	for ret in decl.typ.results.list {
		for n in ret.names {
			if n.name != '' {
				app.named_return_params[n.name] = true
				app.named_return_types[n.name] = ret.typ
			}
		}
	}
	// Set flag if there are named return params to declare
	app.pending_named_returns = app.named_return_params.len > 0

	// Detect interface{} parameters and prepare for generic conversion
	// V requires single-character generic type names
	generic_type_names := ['T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'A', 'B', 'C', 'D', 'E', 'F', 'G',
		'H']
	mut generic_params := map[string]string{} // param_name -> generic_type_name
	mut generic_counter := 0
	for param in decl.typ.params.list {
		if param.typ is InterfaceType {
			iface := param.typ as InterfaceType
			if iface.methods.list.len == 0 {
				// Empty interface{} - convert to generic
				for name in param.names {
					generic_type := if generic_counter < generic_type_names.len {
						generic_type_names[generic_counter]
					} else {
						'T' // fallback
					}
					generic_params[name.name] = generic_type
					generic_counter++
				}
			}
		}
	}

	// mut recv := ''
	// if decl.recv.list.len > 0 {
	// recv_type := type_or_ident(decl.recv.list[0].typ)
	// recv_name := decl.recv.list[0].names[0].name
	// recv = '(${recv_name} ${recv_type})'
	//}
	// params := decl.typ.params.list.map(it.names.map(it.name).join(', ') + ' ' +
	// type_or_ident(it.typ)).join(', ')
	// if recv != '' {
	if decl.recv.list.len > 0 {
		// app.gen('fn ${recv} ')
		app.gen('fn (')
		recv_typ := decl.recv.list[0].typ
		is_ptr_recv := recv_typ is StarExpr
		if decl.recv.list[0].names.len == 0 {
			app.is_mut_recv = true
			app.gen('mut _ ')
		} else {
			recv_name := decl.recv.list[0].names[0].name
			app.cur_fn_names[recv_name] = true // Register the receiver in this scope, since some people shadow receivers too!
			// Pointer receivers should be mut in V
			// Also check if receiver is modified via indexing (for slice types)
			is_modified_via_index := app.receiver_modified_via_index(recv_name, decl.body.list)
			if is_ptr_recv || is_modified_via_index {
				app.gen('mut ')
				app.is_mut_recv = true
			}
			app.gen(recv_name + ' ')
		}
		app.typ(decl.recv.list[0].typ)
		app.gen(') ')
	} else {
		app.gen('fn ')
	}
	app.gen(method_name)
	// Add generic type parameters if we have interface{} params
	if generic_params.len > 0 {
		mut generic_types := []string{}
		for _, gtype in generic_params {
			if gtype !in generic_types {
				generic_types << gtype
			}
		}
		app.gen('[${generic_types.join(', ')}]')
	}
	app.func_params_with_generics(decl.typ.params, generic_params)
	app.func_return_type(decl.typ.results)
	app.gen(' ') // Space before block
	app.block_stmt(decl.body)
}

fn (mut app App) func_type(t FuncType) {
	// Skip 'fn ' prefix for interface method declarations
	if !app.in_interface_decl {
		app.gen('fn ')
	}
	app.func_params(t.params)
	app.func_return_type(t.results)
}

fn (mut app App) func_return_type(results FieldList) {
	// app.genln(results)
	// Return types
	return_types := results.list
	if return_types.len == 0 {
		return
	}
	// Add space before return type(s)
	app.gen(' ')
	needs_pars := return_types.len > 1
	//|| (return_types.len > 0 && return_types[0].names.len > 0	&& return_types[0].names[0].name != '')
	if needs_pars {
		app.gen('(')
	}
	for i, res in return_types {
		/*
		if res.names.len > 0 && res.names[0].name != '' {
			app.gen(app.go2v_ident(res.names[0].name))
			app.gen(' ')
		}
		*/
		app.typ(res.typ)
		if i < return_types.len - 1 {
			app.gen(',')
		}
		//' ${decl.typ.results.list.map(type_or_ident(it.typ)).join(', ')}'
	}
	if needs_pars {
		app.gen(')')
	}
}

fn (mut app App) func_params(params FieldList) {
	// p := params.list.map(it.names.map(it.name).join(', ') + ' ' + type_or_ident(it.typ)).join(', ')
	app.gen('(')
	// app.gen(p)
	// println(app.sb.str())
	for i, param in params.list {
		// param names can be missing. V doesn't allow that, so use `_`
		// param_names := if param.names.len > 0 { param.names } else { [Ident{name'_'] }
		if param.names.len == 0 {
			app.gen('_ ')
			app.typ(param.typ)
		} else {
			for j, name in param.names {
				// Parameter names must be lowercase in V
				saved_force_upper := app.force_upper
				app.force_upper = false
				v_name := app.go2v_ident(name.name)
				app.gen(v_name)
				app.force_upper = saved_force_upper
				app.gen(' ')
				app.force_upper = true
				app.typ(param.typ)
				if j < param.names.len - 1 {
					app.gen(',')
				}
				app.cur_fn_names[v_name] = true // Register the V name for shadowing detection
			}
		}
		// app.gen(type_or_ident(param.typ))
		if i < params.list.len - 1 {
			app.gen(',')
		}
	}
	app.gen(')')
}

fn (mut app App) func_params_with_generics(params FieldList, generic_params map[string]string) {
	app.gen('(')
	for i, param in params.list {
		if param.names.len == 0 {
			app.gen('_ ')
			app.typ(param.typ)
		} else {
			for j, name in param.names {
				// Parameter names must be lowercase in V
				saved_force_upper := app.force_upper
				app.force_upper = false
				v_name := app.go2v_ident(name.name)
				app.gen(v_name)
				app.force_upper = saved_force_upper
				app.gen(' ')
				// Check if this parameter should use a generic type
				if name.name in generic_params {
					app.gen(generic_params[name.name])
				} else {
					app.force_upper = true
					app.typ(param.typ)
				}
				if j < param.names.len - 1 {
					app.gen(',')
				}
				app.cur_fn_names[v_name] = true // Register the V name for shadowing detection
			}
		}
		if i < params.list.len - 1 {
			app.gen(',')
		}
	}
	app.gen(')')
}

fn (mut app App) comments(doc Doc) {
	if doc.list.len == 0 {
		return
	}
	for x in doc.list {
		app.genln(x.text)
	}
}

fn (mut app App) func_lit(node FuncLit) {
	// Collect identifiers used in the closure body
	mut used_idents := map[string]bool{}
	app.collect_idents_from_stmts(node.body.list, mut used_idents)

	// Collect identifiers declared within the closure body (loop vars, local vars, etc.)
	mut declared_in_closure := map[string]bool{}
	app.collect_declarations_from_stmts(node.body.list, mut declared_in_closure)

	// Filter to only identifiers from outer scope (cur_fn_names)
	// Exclude variables declared within the closure itself
	mut captured := []string{}
	for ident, _ in used_idents {
		// Skip blank identifier
		if ident == '_' {
			continue
		}
		// Skip variables declared within the closure
		if ident in declared_in_closure {
			continue
		}
		// Check both the original Go name and V-converted name
		v_name := app.go2v_ident(ident)
		if v_name in app.cur_fn_names && v_name !in captured {
			captured << v_name
		}
	}

	// Exclude closure parameters from captures
	for param in node.typ.params.list {
		for name in param.names {
			v_name := app.go2v_ident(name.name)
			captured = captured.filter(it != v_name)
		}
	}

	app.gen('fn ')
	// Add capture list if there are captured variables
	// In V, all captured variables that might be modified need 'mut'
	if captured.len > 0 {
		app.gen('[')
		for i, cap in captured {
			if i > 0 {
				app.gen(', ')
			}
			// Add mut prefix - in most cases Go closures can modify captured variables
			app.gen('mut ')
			app.gen(cap)
		}
		app.gen('] ')
	}
	app.func_params(node.typ.params)
	app.func_return_type(node.typ.results)
	app.gen(' ') // Space before block
	app.block_stmt(node.body)
}

// Collect all identifiers referenced in a list of statements
fn (mut app App) collect_idents_from_stmts(stmts []Stmt, mut idents map[string]bool) {
	for stmt in stmts {
		app.collect_idents_from_stmt(stmt, mut idents)
	}
}

// Collect identifiers that are declared within statements (loop variables, local vars)
fn (mut app App) collect_declarations_from_stmts(stmts []Stmt, mut declared map[string]bool) {
	for stmt in stmts {
		app.collect_declarations_from_stmt(stmt, mut declared)
	}
}

fn (mut app App) collect_declarations_from_stmt(stmt Stmt, mut declared map[string]bool) {
	match stmt {
		AssignStmt {
			// := creates new declarations
			if stmt.tok == ':=' {
				for lhs in stmt.lhs {
					if lhs is Ident {
						declared[lhs.name] = true
					}
				}
			}
		}
		BlockStmt {
			app.collect_declarations_from_stmts(stmt.list, mut declared)
		}
		ForStmt {
			// For init creates declarations
			if stmt.init.tok == ':=' {
				for lhs in stmt.init.lhs {
					if lhs is Ident {
						declared[lhs.name] = true
					}
				}
			}
			app.collect_declarations_from_stmts(stmt.body.list, mut declared)
		}
		IfStmt {
			// If init creates declarations
			if stmt.init.tok == ':=' {
				for lhs in stmt.init.lhs {
					if lhs is Ident {
						declared[lhs.name] = true
					}
				}
			}
			app.collect_declarations_from_stmts(stmt.body.list, mut declared)
			app.collect_declarations_from_stmt(stmt.else_, mut declared)
		}
		RangeStmt {
			// Range loop variables
			if stmt.key.name != '' && stmt.key.name != '_' {
				declared[stmt.key.name] = true
			}
			if stmt.value.name != '' && stmt.value.name != '_' {
				declared[stmt.value.name] = true
			}
			app.collect_declarations_from_stmts(stmt.body.list, mut declared)
		}
		SwitchStmt {
			app.collect_declarations_from_stmts(stmt.body.list, mut declared)
		}
		CaseClause {
			for s in stmt.body {
				app.collect_declarations_from_stmt(s, mut declared)
			}
		}
		else {}
	}
}

fn (mut app App) collect_idents_from_stmt(stmt Stmt, mut idents map[string]bool) {
	match stmt {
		AssignStmt {
			for expr in stmt.lhs {
				app.collect_idents_from_expr(expr, mut idents)
			}
			for expr in stmt.rhs {
				app.collect_idents_from_expr(expr, mut idents)
			}
		}
		BlockStmt {
			app.collect_idents_from_stmts(stmt.list, mut idents)
		}
		DeferStmt {
			app.collect_idents_from_expr(stmt.call, mut idents)
		}
		ExprStmt {
			app.collect_idents_from_expr(stmt.x, mut idents)
		}
		ForStmt {
			app.collect_idents_from_expr(stmt.cond, mut idents)
			app.collect_idents_from_stmts(stmt.body.list, mut idents)
		}
		IfStmt {
			app.collect_idents_from_expr(stmt.cond, mut idents)
			app.collect_idents_from_stmts(stmt.body.list, mut idents)
			app.collect_idents_from_stmt(stmt.else_, mut idents)
		}
		IncDecStmt {
			app.collect_idents_from_expr(stmt.x, mut idents)
		}
		RangeStmt {
			app.collect_idents_from_expr(stmt.x, mut idents)
			app.collect_idents_from_stmts(stmt.body.list, mut idents)
		}
		ReturnStmt {
			for expr in stmt.results {
				app.collect_idents_from_expr(expr, mut idents)
			}
		}
		SwitchStmt {
			app.collect_idents_from_expr(stmt.tag, mut idents)
			app.collect_idents_from_stmts(stmt.body.list, mut idents)
		}
		CaseClause {
			for expr in stmt.list {
				app.collect_idents_from_expr(expr, mut idents)
			}
			for s in stmt.body {
				app.collect_idents_from_stmt(s, mut idents)
			}
		}
		else {}
	}
}

fn (mut app App) collect_idents_from_expr(expr Expr, mut idents map[string]bool) {
	match expr {
		Ident {
			idents[expr.name] = true
		}
		BinaryExpr {
			app.collect_idents_from_expr(expr.x, mut idents)
			app.collect_idents_from_expr(expr.y, mut idents)
		}
		CallExpr {
			app.collect_idents_from_expr(expr.fun, mut idents)
			for arg in expr.args {
				app.collect_idents_from_expr(arg, mut idents)
			}
		}
		IndexExpr {
			app.collect_idents_from_expr(expr.x, mut idents)
			app.collect_idents_from_expr(expr.index, mut idents)
		}
		SelectorExpr {
			app.collect_idents_from_expr(expr.x, mut idents)
		}
		SliceExpr {
			app.collect_idents_from_expr(expr.x, mut idents)
			if expr.low !is InvalidExpr {
				app.collect_idents_from_expr(expr.low, mut idents)
			}
			if expr.high !is InvalidExpr {
				app.collect_idents_from_expr(expr.high, mut idents)
			}
		}
		StarExpr {
			app.collect_idents_from_expr(expr.x, mut idents)
		}
		UnaryExpr {
			app.collect_idents_from_expr(expr.x, mut idents)
		}
		ParenExpr {
			app.collect_idents_from_expr(expr.x, mut idents)
		}
		CompositeLit {
			for elt in expr.elts {
				app.collect_idents_from_expr(elt, mut idents)
			}
		}
		KeyValueExpr {
			app.collect_idents_from_expr(expr.key, mut idents)
			app.collect_idents_from_expr(expr.value, mut idents)
		}
		FuncLit {
			// Don't recurse into nested closures - they'll capture their own variables
		}
		else {}
	}
}

// Check if a receiver variable is modified via indexing (for slice types)
fn (app App) receiver_modified_via_index(recv_name string, stmts []Stmt) bool {
	for stmt in stmts {
		if app.stmt_modifies_via_index(recv_name, stmt) {
			return true
		}
	}
	return false
}

fn (app App) stmt_modifies_via_index(recv_name string, stmt Stmt) bool {
	match stmt {
		AssignStmt {
			for lhs in stmt.lhs {
				if app.is_indexed_access_on(recv_name, lhs) {
					return true
				}
			}
		}
		BlockStmt {
			return app.receiver_modified_via_index(recv_name, stmt.list)
		}
		IfStmt {
			if app.receiver_modified_via_index(recv_name, stmt.body.list) {
				return true
			}
			return app.stmt_modifies_via_index(recv_name, stmt.else_)
		}
		ForStmt {
			return app.receiver_modified_via_index(recv_name, stmt.body.list)
		}
		RangeStmt {
			return app.receiver_modified_via_index(recv_name, stmt.body.list)
		}
		SwitchStmt {
			return app.receiver_modified_via_index(recv_name, stmt.body.list)
		}
		CaseClause {
			for s in stmt.body {
				if app.stmt_modifies_via_index(recv_name, s) {
					return true
				}
			}
		}
		else {}
	}
	return false
}

fn (app App) is_indexed_access_on(recv_name string, expr Expr) bool {
	match expr {
		IndexExpr {
			// Check if the base of the index expression is the receiver
			if expr.x is Ident {
				return (expr.x as Ident).name == recv_name
			}
		}
		else {}
	}
	return false
}
