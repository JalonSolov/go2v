// Copyright (c) 2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can be found in the LICENSE file.

fn (mut app App) func_decl(decl FuncDecl) {
	app.cur_fn_names.clear()
	app.name_mapping.clear()
	app.named_return_params.clear()
	app.force_upper = false // Reset force_upper at function boundary
	app.genln('')
	app.comments(decl.doc)
	mut method_name := app.go2v_ident(decl.name.name) // decl.name.name.to_lower()
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
	// Track named return parameters
	for ret in decl.typ.results.list {
		for n in ret.names {
			if n.name != '' {
				app.named_return_params[n.name] = true
			}
		}
	}

	// Detect interface{} parameters and prepare for generic conversion
	mut generic_params := map[string]string{} // param_name -> generic_type_name
	mut generic_counter := 0
	for param in decl.typ.params.list {
		if param.typ is InterfaceType {
			iface := param.typ as InterfaceType
			if iface.methods.list.len == 0 {
				// Empty interface{} - convert to generic
				for name in param.names {
					generic_type := if generic_counter == 0 { 'T' } else { 'T${generic_counter}' }
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
			if is_ptr_recv {
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
	app.block_stmt(decl.body)
}

fn (mut app App) func_type(t FuncType) {
	app.gen('fn ')
	app.func_params(t.params)
	app.func_return_type(t.results)
}

fn (mut app App) func_return_type(results FieldList) {
	// app.genln(results)
	// Return types
	return_types := results.list
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
				app.gen(app.go2v_ident(name.name))
				app.force_upper = saved_force_upper
				app.gen(' ')
				app.force_upper = true
				app.typ(param.typ)
				if j < param.names.len - 1 {
					app.gen(',')
				}
				app.cur_fn_names[name.name] = true // Register the parameter in this scope to fix shadowin
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
				app.gen(app.go2v_ident(name.name))
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
				app.cur_fn_names[name.name] = true
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
	app.gen('fn ')
	app.func_params(node.typ.params)
	// app.genln('/*params=${node.typ.params} */')
	app.block_stmt(node.body)
}
