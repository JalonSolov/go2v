// Copyright (c) 2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can be found in the LICENSE file.

fn (mut app App) gen_decl(decl GenDecl) {
	app.comments(decl.doc)
	for spec in decl.specs {
		match spec {
			ImportSpec {
				app.import_spec(spec)
			}
			TypeSpec {
				match spec.typ {
					InterfaceType {
						app.interface_decl(spec.name.name, spec.typ)
					}
					StructType {
						app.struct_or_alias << spec.name.name
						app.struct_decl(spec.name.name, spec.typ)
					}
					else {
						app.type_decl(spec)
					}
				}
			}
			ValueSpec {
				if spec.typ.node_type == 'Ident' {
					// needs_closer = true
				}
				match decl.tok {
					'var' {
						// app.genln('// ValueSpec global')
						app.global_decl(spec)
					}
					else {
						// app.genln('// VA const')
						app.const_decl(spec)
					}
				}
			}
		}
	}
	// if needs_closer {
	if app.is_enum_decl {
		app.genln('}')
	}
	app.is_enum_decl = false
}

fn (mut app App) type_decl(spec TypeSpec) {
	// Remember the type name for the upcoming const (enum) handler if it's an enum
	name := spec.name.name
	// V requires type aliases to start with a capital letter
	v_name := name.capitalize()
	// Store alias info
	app.struct_or_alias << name
	app.struct_or_alias << v_name
	// If this type will become an enum (detected by pre-scan), skip the type alias
	if name in app.enum_types {
		app.type_decl_name = name
		return
	}
	// Generate actual type alias
	app.gen('type ${v_name} = ')
	app.typ(spec.typ)
	app.genln('')
}

fn (mut app App) global_decl(spec ValueSpec) {
	for name in spec.names {
		app.gen('__global ${name.name}')
		match spec.typ.node_type {
			'Ident' {
				app.gen(' ')
				app.genln(go2v_type(spec.typ.name))
			}
			'SelectorExpr', 'StarExpr', 'ArrayType', 'MapType', 'FuncType' {
				// For complex types, use the name as-is since we only have node_type info
				// This results in a type placeholder that needs manual fixing
				app.gen(' ')
				if spec.typ.name != '' {
					app.genln(spec.typ.name)
				} else {
					// No name available, output a placeholder
					app.genln('voidptr // TODO: complex type')
				}
			}
			'InvalidExpr' {
				app.gen(' = ')
				if spec.values.len > 0 {
					app.expr(spec.values[0])
				}
				app.genln('')
			}
			else {
				// For other type nodes, try to use value or leave blank
				if spec.values.len > 0 {
					app.gen(' = ')
					app.expr(spec.values[0])
					app.genln('')
				} else if spec.typ.name != '' {
					app.gen(' ')
					app.genln(spec.typ.name)
				} else {
					app.genln(' voidptr // TODO: unknown type')
				}
			}
		}
	}
}

fn (mut app App) const_decl(spec ValueSpec) {
	// Handle iota (V enum) - check if this const block uses iota
	// Only start a new enum if we're not already in one
	if !app.is_enum_decl && spec.values.len > 0 {
		first_val := spec.values[0]
		if app.contains_iota(first_val) {
			app.is_enum_decl = true
			// Use the type from the spec if available (for cases like `const X SomeType = iota`)
			// Otherwise fall back to type_decl_name or generate from first const name
			mut enum_name := if spec.typ.node_type == 'Ident' && spec.typ.name != '' {
				spec.typ.name
			} else if app.type_decl_name != '' {
				app.type_decl_name
			} else if spec.names.len > 0 {
				// Generate synthetic enum name from first const name
				spec.names[0].name.capitalize() + 'Enum'
			} else {
				'UnnamedEnum'
			}
			// Single letter names need to be doubled (V requires > 1 char)
			if enum_name.len == 1 {
				enum_name = enum_name.capitalize() + enum_name.capitalize()
			}
			app.genln('enum ${enum_name} {')
		}
	}
	for i, name in spec.names {
		if !app.is_enum_decl && name.name.starts_with_capital() {
			app.gen('pub ')
		}
		n := app.go2v_ident(name.name)
		if app.is_enum_decl {
			// Handle enum values - check if there's an explicit value
			if i < spec.values.len {
				val := spec.values[i]
				if val is BasicLit {
					// Explicit value like `= 5`
					app.gen(n)
					app.gen(' = ')
					app.basic_lit(val)
					app.genln('')
					continue
				} else if val is Ident && val.name == 'iota' {
					// Just iota, output the name
					app.genln(n)
					continue
				}
			}
			// No explicit value, just output the name
			app.genln(n)
		} else {
			app.gen('const ${n} = ')
			if i < spec.values.len {
				app.expr(spec.values[i])
			}
			app.genln('')
		}
	}
}

// TODO hardcoded esbuild paths
const master_module_paths = ['github.com.evanw.esbuild.internal', 'github.com.evanw.esbuild.pkg']

fn (mut app App) import_spec(spec ImportSpec) {
	mut name := spec.path.value.replace('"', '').replace('/', '.')
	// Skip modules that don't exist in V (fmt, strings etc)
	if name in nonexistent_modules {
		return
	}
	// Skip modules with V keywords in their names
	if name.contains('.sql') || name == 'database.sql' {
		return
	}
	// Skip modules that don't have V equivalents
	if name in ['bufio', 'mime.multipart', 'os.user', 'sync.atomic'] {
		return
	}
	// Go to V module mappings
	match name {
		'archive.zip' { name = 'compress.zip' }
		'compress.flate' { name = 'compress.deflate' }
		'container.list' { name = 'datatypes' }
		'io.ioutil' { name = 'io.util' }
		'mime' { name = 'net.http.mime' }
		'unicode.utf8' { name = 'encoding.utf8' }
		'net.http.cookiejar' { name = 'net.http' }
		else {}
	}
	// Check if it's a local module (internal or pkg)
	for master_module_path in master_module_paths {
		if name.starts_with(master_module_path) {
			n := name.replace(master_module_path, '')
			app.gen('import ${n[1..]}')
			if spec.name.name != '' {
				app.gen(' as ${spec.name.name}')
			}
			app.genln(' // local module')
			return
		}
	}
	// Handle golang.org/x/ imports by stripping the prefix
	if name.starts_with('golang.org.x.') {
		n := name.replace('golang.org.x.', '')
		app.gen('import ${n}')
		if spec.name.name != '' {
			app.gen(' as ${spec.name.name}')
		}
		app.genln('')
		return
	}
	// TODO a temp hack
	if name.starts_with('github') {
		return
	}
	app.gen('import ${name}')
	if spec.name.name != '' {
		app.gen(' as ${spec.name.name}')
	}
	app.genln('')
}

fn (mut app App) struct_decl(struct_name string, spec StructType) {
	// Convert struct name - single letter names need to be doubled (V requires > 1 char)
	mut v_struct_name := struct_name
	if struct_name.len == 1 {
		v_struct_name = struct_name.capitalize() + struct_name.capitalize()
	}
	// Check for name collision with existing global names
	if v_struct_name in app.global_names {
		mut i := 1
		for {
			new_name := '${v_struct_name}_${i}'
			if new_name !in app.global_names {
				v_struct_name = new_name
				break
			}
			i++
		}
	}
	// Track struct name globally
	app.global_names[v_struct_name] = true
	app.genln('struct ${v_struct_name} {')

	// First output embedded structs (fields without names)
	for field in spec.fields.list {
		if field.names.len == 0 {
			// Embedded struct - skip if it's a pointer type (V doesn't support embedded pointers)
			if field.typ is StarExpr {
				continue
			}
			// Skip primitive type embeddings (V only allows struct embeddings)
			// Generate a named field instead for primitive types
			if field.typ is Ident {
				ident := field.typ as Ident
				conversion := go2v_type_checked(ident.name)
				if conversion.is_basic {
					// Primitive type - generate as a named field
					app.genln('pub mut:')
					app.genln('\t${ident.name.camel_to_snake()} ${conversion.v_type}')
					continue
				}
			}
			app.gen('\t')
			app.force_upper = true
			app.typ(field.typ)
			app.force_upper = false
			app.genln('')
		}
	}

	// Then output named fields
	mut has_named_fields := false
	for field in spec.fields.list {
		if field.names.len > 0 {
			has_named_fields = true
			break
		}
	}
	if has_named_fields {
		app.genln('pub mut:')
	}
	for field in spec.fields.list {
		app.comments(field.doc)
		for n in field.names {
			app.gen('\t')
			app.gen(app.go2v_ident(n.name))
			app.gen(' ')
			app.typ(field.typ)
			if field.typ in [StarExpr, FuncType] {
				app.gen(' = unsafe { nil }')
			}
			app.genln('')
		}
	}
	app.genln('}\n')
}

fn (mut app App) struct_type(spec StructType) {
	// Inline/anonymous struct type (e.g., struct { x int })
	app.gen('struct {')
	for field in spec.fields.list {
		for n in field.names {
			app.gen(' ')
			app.gen(app.go2v_ident(n.name))
			app.gen(' ')
			app.typ(field.typ)
		}
	}
	app.gen(' }')
}

fn (mut app App) interface_decl(interface_name string, spec InterfaceType) {
	// Convert interface name - single letter names need to be doubled (V requires > 1 char)
	mut v_interface_name := interface_name
	if interface_name.len == 1 {
		v_interface_name = interface_name.capitalize() + interface_name.capitalize()
	}
	app.genln('interface ${v_interface_name} {')
	for field in spec.methods.list {
		app.comments(field.doc)
		for n in field.names {
			app.gen('\t')
			app.gen(app.go2v_ident(n.name))
			app.force_upper = true
			app.typ(field.typ)
			app.genln('')
		}
	}
	app.genln('}\n')
}

fn (mut app App) composite_lit(c CompositeLit) {
	match c.typ {
		ArrayType {
			app.array_init(c)
		}
		BasicLit {
			app.expr(c)
		}
		CompositeLit {
			app.composite_lit(c)
		}
		Ident {
			app.struct_init(c)
		}
		InvalidExpr {
			if c.elts.len > 0 {
				app.genln('')
			}
			for elt in c.elts {
				app.expr(elt)
				app.genln('')
			}
		}
		MapType {
			app.map_init(c)
		}
		SelectorExpr {
			force_upper := app.force_upper // save force upper for `mod.ForceUpper`
			app.force_upper = true
			app.selector_expr(c.typ)
			app.force_upper = force_upper
			app.gen('{')
			if c.elts.len > 0 {
				app.genln('')
			}
			for elt in c.elts {
				app.expr(elt)
				app.genln('')
			}
			app.gen('}')
		}
		StructType {
			// Anonymous struct initialization, e.g., struct{}{}
			app.struct_type(c.typ)
			app.gen('{')
			for elt in c.elts {
				app.expr(elt)
				app.genln('')
			}
			app.gen('}')
		}
		else {
			app.genln('// UNHANDLED CompositeLit type  ${c.typ.type_name()} strtyp="${c.typ}"')
		}
	}
}

fn (mut app App) struct_init(c CompositeLit) {
	typ := c.typ
	match typ {
		Ident {
			app.force_upper = true
			n := app.go2v_ident(typ.name)
			app.force_upper = false // Reset after type name
			app.gen('${n}{')
			if c.elts.len > 0 {
				app.genln('')
			}
			for elt in c.elts {
				app.expr(elt)
				app.genln('')
			}
			app.gen('}')
		}
		else {}
	}
}

// Helper function to check if an expression contains iota
fn (app App) contains_iota(expr Expr) bool {
	match expr {
		Ident {
			return expr.name == 'iota'
		}
		BinaryExpr {
			return app.contains_iota(expr.x) || app.contains_iota(expr.y)
		}
		ParenExpr {
			return app.contains_iota(expr.x)
		}
		CallExpr {
			// Check if any arg contains iota
			for arg in expr.args {
				if app.contains_iota(arg) {
					return true
				}
			}
			return false
		}
		else {
			return false
		}
	}
}

// Generate a synthetic struct for inline/anonymous struct types
// Returns the generated struct name
fn (mut app App) generate_inline_struct(expr Expr) string {
	st := expr as StructType

	// Generate unique struct name
	mut struct_name := 'Go2VInlineStruct'
	if app.inline_struct_count > 0 {
		struct_name = 'Go2VInlineStruct_${app.inline_struct_count}'
	}
	app.inline_struct_count++

	// Build struct definition
	mut result := '\nstruct ${struct_name} {\nmut:\n'

	for field in st.fields.list {
		for n in field.names {
			result += '\t${app.go2v_ident(n.name)} '
			// Get type string
			match field.typ {
				Ident {
					result += go2v_type(field.typ.name)
				}
				ArrayType {
					result += '[]'
					if field.typ.elt is Ident {
						elt := field.typ.elt as Ident
						result += go2v_type(elt.name)
					}
				}
				else {
					result += 'voidptr'
				}
			}
			result += '\n'
		}
	}
	result += '}\n'

	app.pending_structs << result
	return struct_name
}
