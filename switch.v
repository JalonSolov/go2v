// Copyright (c) 2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can be found in the LICENSE file.

fn (mut app App) switch_stmt(switch_stmt SwitchStmt) {
	// Switch with no condition (tag) is just a bunch of if-elseif's
	if switch_stmt.tag is InvalidExpr {
		for i, stmt in switch_stmt.body.list {
			if i > 0 {
				app.gen('else ')
			}

			case_clause := stmt as CaseClause
			if case_clause.list.len == 0 {
				// default:
			} else if case_clause.list.len > 0 {
				app.gen('if ')
				app.expr(case_clause.list[0])
			}
			app.genln('{')
			app.stmt_list(case_clause.body)
			app.genln('}')
		}

		return
	}
	if switch_stmt.init.lhs.len > 0 {
		app.assign_stmt(switch_stmt.init, false)
	}
	if switch_stmt.body.list.len == 1 {
		app.gen('if ')
		app.expr(switch_stmt.tag)
		case_clause := switch_stmt.body.list[0] as CaseClause
		if case_clause.list.len == 1 {
			app.gen(' == ')
			app.expr(case_clause.list[0])
			app.genln('{')
			app.stmt_list(case_clause.body)
			app.genln('}')
		} else {
			app.gen(' in [')
			for i, x in case_clause.list {
				if i > 0 {
					app.gen(',')
				}
				app.expr(x)
			}
			app.genln('] {')
			app.stmt_list(case_clause.body)
			app.genln('}')
		}

		return
	}

	app.gen('match ')
	app.expr(switch_stmt.tag)
	app.genln('{')
	for stmt in switch_stmt.body.list {
		case_clause := stmt as CaseClause
		for i, x in case_clause.list {
			app.expr(x)
			if i < case_clause.list.len - 1 {
				app.gen(',')
			}
		}
		if case_clause.list.len == 0 {
			app.gen('else ')
		}
		app.genln('{')
		app.stmt_list(case_clause.body)
		app.genln('}')
	}
	app.genln('}')
}

fn (mut app App) type_switch_stmt(node TypeSwitchStmt) {
	// Handle the assignment part first (e.g., `e := x.(type)` => `mut e := x`)
	// Get the source expression from the RHS TypeAssertExpr
	mut switch_expr := Expr(InvalidExpr{})
	mut has_assignment := false
	mut assigned_var_name := ''

	// node.assign can be either AssignStmt or ExprStmt
	match node.assign {
		AssignStmt {
			if node.assign.rhs.len > 0 {
				rhs0 := node.assign.rhs[0]
				if rhs0 is TypeAssertExpr {
					switch_expr = rhs0.x
				}
			}
			has_assignment = node.assign.lhs.len > 0
		}
		ExprStmt {
			// Type switch without assignment: switch s.(type)
			if node.assign.x is TypeAssertExpr {
				switch_expr = (node.assign.x as TypeAssertExpr).x
			}
			has_assignment = false
		}
		else {}
	}

	// Generate the assignment if there's an lhs
	if has_assignment {
		assign := node.assign as AssignStmt
		lhs0 := assign.lhs[0]
		if lhs0 is Ident {
			mut lhs_name := app.go2v_ident(lhs0.name)
			// Handle shadowing - rename if the name already exists
			lhs_name = app.unique_name_anti_shadow(lhs_name)
			app.cur_fn_names[lhs_name] = true // Track the variable for shadowing
			assigned_var_name = lhs_name
			app.gen('mut ')
			app.gen(lhs_name)
			app.gen(' := ')
			app.expr(switch_expr)
			app.genln('')
		}
	}

	app.gen('match ')
	// Use the assigned variable name only for complex expressions (to avoid struct literal issues in match)
	// For simple Ident expressions, use the original to maintain expected behavior
	if assigned_var_name != '' && switch_expr !is Ident {
		app.gen(assigned_var_name)
	} else {
		app.expr(switch_expr)
	}
	app.genln('.type_name() {')
	for stmt in node.body.list {
		case_clause := stmt as CaseClause
		for i, x in case_clause.list {
			// Type cases should be converted to string names
			app.gen(app.type_case_pattern(x))
			if i < case_clause.list.len - 1 {
				app.gen(',')
			}
		}
		if case_clause.list.len == 0 {
			app.gen('else ')
		}
		app.genln('{')
		app.stmt_list(case_clause.body)
		app.genln('}')
	}
	app.genln('}')
}

// Helper to extract the type name from a case pattern in type switch
fn (app App) type_case_pattern(x Expr) string {
	match x {
		Ident {
			// Simple type like `string` or `int`
			return "'${go2v_type(x.name)}'"
		}
		StarExpr {
			// Pointer type like `*Foo`
			return app.type_case_pattern(x.x)
		}
		SelectorExpr {
			// Qualified type like `pkg.Type`
			return "'${x.sel.name}'"
		}
		else {
			return "'UNKNOWN_TYPE'"
		}
	}
}
