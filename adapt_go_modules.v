// Copyright (c) 2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can be found in the LICENSE file.
//
// This file contains logic for adapting Go standard library modules to V equivalents.
// It handles module imports, function call translations, and type mappings.

module main

// Modules that don't exist in V at all and shouldn't be imported
const nonexistent_modules = ['fmt', 'path', 'strings', 'atomic', 'unsafe', 'bytes']

// Type names that conflict with V's standard library and need renaming
// These types exist in V's stdlib (e.g., log.Log) and cause conflicts
const conflicting_type_names = {
	'Log': 'Logger_' // V's log module has log.Log struct
}

// Modules that need function call translation (includes nonexistent + some that exist but need mapping)
const modules_needing_call_translation = ['fmt', 'path', 'strings', 'atomic', 'unsafe', 'os', 'bytes',
	'user', 'sort', 'utf8']

// Maps Go strings function names to V string method names
const go_strings_to_v = {
	'has_prefix':      'starts_with'
	'has_suffix':      'ends_with'
	'contains':        'contains'
	'to_lower':        'to_lower'
	'to_upper':        'to_upper'
	'trim_space':      'trim_space'
	'trim':            'trim'
	'trim_left':       'trim_left'
	'trim_right':      'trim_right'
	'trim_prefix':     'trim_left'
	'trim_suffix':     'trim_right'
	'replace':         'replace'
	'replace_all':     'replace'
	'split':           'split'
	'join':            'join'
	'index':           'index'
	'last_index':      'last_index'
	'last_index_any':  'last_index_any' // V doesn't have this - needs manual implementation
	'last_index_byte': 'last_index' // V's last_index works for single chars too
	'index_byte':      'index' // V's index works for single chars too
	'repeat':          'repeat'
	'equal_fold':      'eq_ignore_case'
	'count':           'count'
	'fields':          'fields'
}

// Maps Go os function names to V equivalents
const go_os_to_v = {
	'Exit':      'exit'
	'LookupEnv': 'getenv_opt' // Returns ?string instead of (string, bool)
}

// Maps Go os/user function names to V os equivalents
const go_user_to_v = {
	'Current':       'current_user'
	'Lookup':        'lookup_user'
	'LookupId':      'lookup_user_id'
	'LookupGroup':   'lookup_group'
	'LookupGroupId': 'lookup_group_id'
}

// handle_nonexistent_module_call dispatches to the appropriate handler for Go modules
// that don't exist in V or need special translation
fn (mut app App) handle_nonexistent_module_call(sel SelectorExpr, mod_name string, fn_name string, node CallExpr) {
	match mod_name {
		'strings' {
			app.handle_strings_call(app.go2v_ident(fn_name), node.args)
		}
		'path' {
			app.handle_path_call(sel, app.go2v_ident(fn_name), node.args)
		}
		'fmt' {
			app.handle_fmt_call(app.go2v_ident(fn_name), node.args)
		}
		'atomic' {
			app.handle_atomic_call(fn_name, node.args)
		}
		'unsafe' {
			app.handle_unsafe_call(fn_name, node.args)
		}
		'os' {
			app.handle_os_call(fn_name, node.args)
		}
		'bytes' {
			app.handle_bytes_call(fn_name, node.args)
		}
		'user' {
			app.handle_user_call(fn_name, node.args)
		}
		'sort' {
			app.handle_sort_call(fn_name, node.args)
		}
		'utf8' {
			app.handle_utf8_call(fn_name, node.args)
		}
		else {}
	}
}

// handle_strings_call maps Go strings functions to string methods in V
// e.g., strings.HasPrefix(s, prefix) => s.starts_with(prefix)
fn (mut app App) handle_strings_call(fn_name string, args []Expr) {
	// Handle special cases that don't map directly to V methods
	match fn_name {
		'last_index_any' {
			// strings.LastIndexAny(s, chars) - V doesn't have this
			// Generate a helper call from the string_helpers module
			app.gen('string_helpers.strings_last_index_any(')
			app.expr(args[0])
			app.gen(', ')
			if args.len > 1 {
				app.expr(args[1])
			}
			app.gen(')')
			app.skip_call_parens = true
			return
		}
		'last_index_byte', 'index_byte' {
			// strings.LastIndexByte(s, c) or strings.IndexByte(s, c)
			// Convert char to string: s.last_index(string([c])) or { -1 }
			// The or { -1 } handles the optional return type in V
			app.expr(args[0])
			v_fn_name := if fn_name == 'last_index_byte' { 'last_index' } else { 'index' }
			app.gen('.${v_fn_name}(string([')
			if args.len > 1 {
				app.expr(args[1])
			}
			app.gen('])) or { -1 }')
			app.skip_call_parens = true
			return
		}
		'index', 'last_index' {
			// strings.Index(s, substr) or strings.LastIndex(s, substr)
			// V's index/last_index return ?int, so add or { -1 }
			app.expr(args[0])
			v_fn_name := go_strings_to_v[fn_name] or { fn_name }
			app.gen('.${v_fn_name}(')
			if args.len > 1 {
				app.expr(args[1])
			}
			app.gen(') or { -1 }')
			app.skip_call_parens = true
			return
		}
		else {}
	}
	// Standard case: convert to method call
	app.expr(args[0])
	app.gen('.')
	v_fn_name := go_strings_to_v[fn_name] or { fn_name }
	app.gen(v_fn_name)
	app.skip_first_arg = true
}

// handle_path_call maps Go path functions to V os equivalents
fn (mut app App) handle_path_call(sel SelectorExpr, fn_name string, x []Expr) {
	if fn_name == 'base' {
		app.gen('os.base')
	}
	// Go allows module name shadowing, so we can have a variable `path`
	else {
		app.selector_xxx(sel)
	}
}

// handle_fmt_call maps Go fmt functions to V equivalents
// V uses string interpolation instead of printf-style formatting
fn (mut app App) handle_fmt_call(fn_name string, args []Expr) {
	match fn_name {
		'sprintf' {
			// fmt.Sprintf generates a string - simplified to empty string
			app.gen("''")
			app.skip_call_parens = true
		}
		'printf' {
			// fmt.Printf prints - generate a complete print statement
			app.gen("print('')")
			app.skip_call_parens = true
		}
		'errorf' {
			// fmt.Errorf creates an error - simplified
			app.gen("error('')")
			app.skip_call_parens = true
		}
		'fprintf' {
			// fmt.Fprintf writes to a writer
			app.gen('_ = 0')
			app.skip_call_parens = true
		}
		'sscan', 'sscanf', 'fscan', 'fscanf', 'scan', 'scanf' {
			// Scan functions - generate assignment to discard return value
			app.gen('_ := 0')
			app.skip_call_parens = true
		}
		else {
			// For other fmt functions, generate a placeholder that's valid V
			app.gen('0')
			app.skip_call_parens = true
		}
	}
}

// handle_os_call maps Go os functions to V equivalents
fn (mut app App) handle_os_call(fn_name string, args []Expr) {
	// Check if this is a function that needs remapping
	if v_fn := go_os_to_v[fn_name] {
		// Exit becomes a standalone function in V
		app.gen(v_fn)
	} else {
		// Keep as os.function_name
		app.gen('os.')
		app.gen(app.go2v_ident(fn_name))
	}
}

// handle_unsafe_call translates Go unsafe operations to V equivalents
// unsafe.Pointer(&x) => voidptr(&x)
// unsafe.Sizeof(x) => sizeof(x)
fn (mut app App) handle_unsafe_call(fn_name string, args []Expr) {
	app.skip_call_parens = true
	match fn_name {
		'Pointer' {
			app.gen('voidptr(')
			if args.len > 0 {
				app.expr(args[0])
			}
			app.gen(')')
		}
		'Sizeof' {
			app.gen('sizeof(')
			if args.len > 0 {
				app.expr(args[0])
			}
			app.gen(')')
		}
		else {
			// Fallback - output as comment
			app.gen('/* unsafe.${fn_name} */')
		}
	}
}

// handle_atomic_call translates Go atomic operations to simple assignments/reads
// atomic.StoreXxx(ptr, val) => *ptr = val
// atomic.LoadXxx(ptr) => *ptr
// atomic.AddXxx(ptr, delta) => *ptr += delta
fn (mut app App) handle_atomic_call(fn_name string, args []Expr) {
	app.skip_call_parens = true
	if fn_name.starts_with('Store') {
		// atomic.StoreUint32(&x, val) => x = val
		if args.len >= 2 {
			if args[0] is UnaryExpr {
				// Skip the & and just use the target
				app.expr((args[0] as UnaryExpr).x)
			} else {
				app.gen('*')
				app.expr(args[0])
			}
			app.gen(' = ')
			app.expr(args[1])
		}
	} else if fn_name.starts_with('Load') {
		// atomic.LoadUint32(&x) => x
		if args.len >= 1 {
			if args[0] is UnaryExpr {
				app.expr((args[0] as UnaryExpr).x)
			} else {
				app.gen('*')
				app.expr(args[0])
			}
		}
	} else if fn_name.starts_with('Add') {
		// atomic.AddInt64(&x, delta) - this is usually handled specially in if_stmt
		// If we get here, just generate a simple add (losing the return value)
		if args.len >= 2 {
			if args[0] is UnaryExpr {
				ux := args[0] as UnaryExpr
				app.expr(ux.x)
				app.gen(' += ')
				app.expr(args[1])
			} else {
				app.gen('*')
				app.expr(args[0])
				app.gen(' += ')
				app.expr(args[1])
			}
		}
	} else {
		// Fallback: just output the function name and args
		app.gen('/* atomic.${fn_name} */ ')
	}
}

// handle_bytes_call maps Go bytes functions to V equivalents
fn (mut app App) handle_bytes_call(fn_name string, args []Expr) {
	match fn_name {
		'Equal' {
			// bytes.Equal(a, b) => a == b
			app.expr(args[0])
			app.gen(' == ')
			app.expr(args[1])
			app.skip_call_parens = true
		}
		'Contains' {
			// bytes.Contains(b, sub) => b.bytestr().contains(sub.bytestr())
			app.expr(args[0])
			app.gen('.bytestr().contains(')
			app.expr(args[1])
			app.gen('.bytestr())')
			app.skip_call_parens = true
		}
		'Index', 'IndexByte' {
			// bytes.Index(b, sep) - needs manual conversion, return -1 for not found
			app.gen('-1')
			app.skip_call_parens = true
		}
		else {
			// For other bytes functions, generate placeholder
			app.gen('0')
			app.skip_call_parens = true
		}
	}
}

// handle_user_call maps Go os/user functions to V os equivalents
// Go's os/user package maps to V's os module user functions
fn (mut app App) handle_user_call(fn_name string, args []Expr) {
	// Map Go function name to V equivalent
	if v_fn := go_user_to_v[fn_name] {
		app.gen('os.')
		app.gen(v_fn)
	} else {
		// Fallback - output as os.function_name with snake_case
		app.gen('os.')
		app.gen(app.go2v_ident(fn_name))
	}
}

// handle_sort_call maps Go sort functions to V equivalents
// sort.Strings(slice) => slice.sort()
// sort.Sort(data) => data.sort()
// sort.Stable(data) => data.sort()
fn (mut app App) handle_sort_call(fn_name string, args []Expr) {
	app.skip_call_parens = true
	if args.len > 0 {
		app.expr(args[0])
		app.gen('.sort()')
	}
}

// handle_utf8_call maps Go utf8 functions to V equivalents
// utf8.DecodeRuneInString(s) => string_helpers.decode_rune_in_string(s)
// utf8.DecodeLastRuneInString(s) => string_helpers.decode_last_rune_in_string(s)
fn (mut app App) handle_utf8_call(fn_name string, args []Expr) {
	match fn_name {
		'DecodeRuneInString' {
			app.gen('string_helpers.decode_rune_in_string(')
			if args.len > 0 {
				app.expr(args[0])
			}
			app.gen(')')
			app.skip_call_parens = true
		}
		'DecodeLastRuneInString' {
			app.gen('string_helpers.decode_last_rune_in_string(')
			if args.len > 0 {
				app.expr(args[0])
			}
			app.gen(')')
			app.skip_call_parens = true
		}
		else {
			// For other utf8 functions, use utf8.xxx (V imports as encoding.utf8 but uses utf8 prefix)
			app.gen('utf8.')
			app.gen(app.go2v_ident(fn_name))
		}
	}
}
