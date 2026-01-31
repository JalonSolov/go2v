// Copyright (c) 2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can be found in the LICENSE file.

fn (mut app App) array_init(c CompositeLit) {
	typ := c.typ
	match typ {
		ArrayType {
			mut have_len := false
			mut len_val := ''
			// Any non-InvalidExpr length means fixed-size array
			mut is_fixed := typ.len !is InvalidExpr
			if typ.len is BasicLit {
				have_len = typ.len.value != ''
				len_val = typ.len.value
			}
			mut elt_name := ''
			mut elt_is_selector := false
			mut elt_is_ident := false
			match typ.elt {
				ArrayType {
					// Nested array, e.g., [][]int
					elt_name = ''
				}
				Ident {
					elt_name = go2v_type(typ.elt.name)
					elt_is_ident = true
				}
				SelectorExpr {
					// e.g., []logger.MsgData
					elt_name = ''
					elt_is_selector = true
				}
				StarExpr {
					x := typ.elt.x
					match x {
						Ident {
							elt_name = go2v_type(x.name)
						}
						SelectorExpr {
							// e.g., []*pkg.Type
							elt_name = ''
							elt_is_selector = true
						}
						else {
							app.gen('>> unhandled array type "${x.node_type}"')
						}
					}
				}
				StructType {
					// Inline/anonymous struct as array element
					struct_name := app.generate_inline_struct(typ.elt)
					elt_name = struct_name
					elt_is_ident = true
				}
				else {
					app.gen('>> unhandled array element type "${typ.elt}"')
					return
				}
			}

			// No elements, just `[]bool{}` (specify type)
			app.gen('[')
			if c.elts.len == 0 {
				if have_len {
					app.gen(len_val)
				}
				app.gen(']')
				if elt_is_selector {
					app.force_upper = true
					app.selector_expr(typ.elt as SelectorExpr)
				} else {
					app.gen(elt_name)
				}
				app.gen('{}')
			} else {
				match c.elts[0] {
					BasicLit, BinaryExpr, CallExpr, CompositeLit, Ident, IndexExpr, SelectorExpr,
					StarExpr, UnaryExpr {
						for i, elt in c.elts {
							if i > 0 {
								app.gen(',')
							}
							if elt is CompositeLit && (elt as CompositeLit).typ is InvalidExpr {
								// Array with implicit element type
								// []Type{{Field: value}} => [Type{field: value}]
								// []pkg.Type{{Field: value}} => [pkg.Type{field: value}]
								// [][]int{{1,2,3}} => [[isize(1),2,3]]
								if typ.elt is ArrayType {
									// Nested array - generate array literal with type cast on first element
									comp := elt as CompositeLit
									app.gen('[')
									inner_elt := typ.elt as ArrayType
									mut inner_type_name := ''
									if inner_elt.elt is Ident {
										inner_type_name = go2v_type((inner_elt.elt as Ident).name)
									}
									for j, e in comp.elts {
										if j > 0 {
											app.gen(', ')
										}
										// Only add type cast on first element of first inner array
										if i == 0 && j == 0 && inner_type_name != ''
											&& inner_type_name != 'string'
											&& !inner_type_name.starts_with_capital() {
											app.gen('${inner_type_name}(')
											app.expr(e)
											app.gen(')')
										} else {
											app.expr(e)
										}
									}
									app.gen(']')
								} else if elt_is_selector {
									app.force_upper = true
									app.selector_expr(typ.elt as SelectorExpr)
									app.gen('{')
									comp := elt as CompositeLit
									for j, e in comp.elts {
										if j > 0 {
											app.gen(', ')
										}
										app.expr(e)
									}
									app.gen('}')
								} else if elt_is_ident {
									app.force_upper = true
									app.gen(elt_name)
									app.gen('{')
									comp := elt as CompositeLit
									for j, e in comp.elts {
										if j > 0 {
											app.gen(', ')
										}
										app.expr(e)
									}
									app.gen('}')
								} else {
									// Fallback: just output struct literal
									app.gen('{')
									comp := elt as CompositeLit
									for j, e in comp.elts {
										if j > 0 {
											app.gen(', ')
										}
										app.expr(e)
									}
									app.gen('}')
								}
							} else if i == 0 && elt_name != '' && elt_name != 'string'
								&& !elt_name.starts_with_capital() {
								// specify type in the first element
								// [u8(1), 2, 3]
								app.gen('${elt_name}(')
								app.expr(elt)
								app.gen(')')
							} else {
								app.expr(elt)
							}
						}
						if have_len {
							diff := len_val.int() - c.elts.len
							if diff > 0 {
								for _ in 0 .. diff {
									app.gen(',')
									match elt_name {
										'isize', 'usize' { app.gen('0') }
										'string' { app.gen("''") }
										else { app.gen('unknown element type??') }
									}
								}
							}
						}
						app.gen(']')
					}
					KeyValueExpr {
						// For sparse array initialization, compute max key + 1 for length (dynamic arrays only)
						mut max_key := 0
						for elt in c.elts {
							kv := elt as KeyValueExpr
							if kv.key is BasicLit {
								key_lit := kv.key as BasicLit
								mut key_val := 0
								if key_lit.value.starts_with('0x') {
									key_val = int(key_lit.value[2..].parse_int(16, 32) or { 0 })
								} else {
									key_val = key_lit.value.int()
								}
								if key_val > max_key {
									max_key = key_val
								}
							}
						}
						// For Ellipsis [...], output computed size; otherwise output the length expression
						if typ.len is Ellipsis {
							app.gen('${max_key + 1}')
						} else if typ.len !is InvalidExpr {
							app.expr(typ.len)
						}
						// For fixed arrays, don't include len: attribute; for dynamic arrays, include it
						if is_fixed {
							app.gen(']${elt_name}{init: match index {')
						} else {
							app.gen(']${elt_name}{len: ${max_key + 1}, init: match index {')
						}
						for elt in c.elts {
							app.expr((elt as KeyValueExpr).key)
							app.gen(' { ')
							kv_value := (elt as KeyValueExpr).value
							// Check if value is a CompositeLit with implicit type
							if kv_value is CompositeLit
								&& (kv_value as CompositeLit).typ is InvalidExpr {
								// Add the element type name before the struct literal
								if elt_is_ident {
									app.force_upper = true
									app.gen(app.go2v_ident((typ.elt as Ident).name))
								} else if elt_is_selector {
									app.force_upper = true
									app.selector_expr(typ.elt as SelectorExpr)
								}
								app.gen('{')
								comp := kv_value as CompositeLit
								for j, e in comp.elts {
									if j > 0 {
										app.gen(', ')
									}
									// Handle KeyValueExpr explicitly to ensure lowercase field names
									if e is KeyValueExpr {
										kve := e as KeyValueExpr
										if kve.key is Ident {
											app.gen(app.go2v_ident((kve.key as Ident).name))
											app.gen(': ')
										} else {
											app.expr(kve.key)
											app.gen(': ')
										}
										app.expr(kve.value)
									} else {
										app.expr(e)
									}
								}
								app.gen('}')
							} else {
								app.expr(kv_value)
							}
							app.gen(' }')
						}
						// For else clause, use appropriate default based on element type
						if elt_is_ident && elt_name.starts_with_capital() {
							// Struct type - use empty struct literal
							app.gen(' else { ${elt_name}{} }}}')
						} else {
							app.gen(' else { 0 }}}')
						}
						// Don't add '!' for sparse init - size is already specified via {init:}
						is_fixed = false
					}
					else {
						app.gen('>> unhandled array element type ${c.elts[0]}')
					}
				}
				if is_fixed {
					app.gen('!')
				}
			}
		}
		else {}
	}
}

fn (mut app App) map_init(node CompositeLit) {
	app.expr(node.typ)
	app.genln('{')
	map_typ := node.typ as MapType
	for elt in node.elts {
		kv := elt as KeyValueExpr
		// Handle key
		if kv.key is Ident {
			app.gen('\t${app.go2v_ident(kv.key.name)}: ')
		} else {
			app.expr(kv.key)
			app.gen(': ')
		}
		// Handle value - check if it's an implicit initialization
		if kv.value is CompositeLit && (kv.value as CompositeLit).typ is InvalidExpr {
			comp := kv.value as CompositeLit
			// Check if map value type is an array - generate array literal
			if map_typ.val is ArrayType {
				arr_typ := map_typ.val as ArrayType
				app.gen('[')
				for i, e in comp.elts {
					if i > 0 {
						app.gen(', ')
					}
					// Handle implicit struct in array
					if e is CompositeLit && (e as CompositeLit).typ is InvalidExpr {
						e_comp := e as CompositeLit
						// Get array element type and prefix the struct literal
						match arr_typ.elt {
							Ident {
								app.force_upper = true
								app.gen(app.go2v_ident(arr_typ.elt.name))
							}
							SelectorExpr {
								app.force_upper = true
								app.selector_expr(arr_typ.elt)
							}
							else {}
						}
						app.gen('{')
						for j, field in e_comp.elts {
							if j > 0 {
								app.gen(', ')
							}
							app.expr(field)
						}
						app.gen('}')
					} else {
						app.expr(e)
					}
				}
				app.gen(']')
			} else if map_typ.val is MapType {
				// Nested map - generate map literal with explicit type
				nested_map_typ := map_typ.val as MapType
				app.map_type(nested_map_typ)
				app.nested_map_init(comp, nested_map_typ)
			} else {
				// Implicit struct value - need to prefix with map's value type
				app.force_upper = true
				match map_typ.val {
					Ident {
						app.gen(app.go2v_ident(map_typ.val.name))
					}
					SelectorExpr {
						app.selector_expr(map_typ.val)
					}
					StarExpr {
						app.star_expr(map_typ.val)
					}
					else {}
				}
				app.gen('{')
				if comp.elts.len > 0 {
					app.genln('')
				}
				for e in comp.elts {
					app.expr(e)
					app.genln('')
				}
				app.gen('}')
			}
		} else {
			app.expr(kv.value)
		}
		app.genln('')
	}
	app.gen('}')
}

fn (mut app App) nested_map_init(comp CompositeLit, map_typ MapType) {
	app.genln('{')
	for elt in comp.elts {
		kv := elt as KeyValueExpr
		// Handle key
		if kv.key is Ident {
			app.gen('\t${app.go2v_ident(kv.key.name)}: ')
		} else {
			app.expr(kv.key)
			app.gen(': ')
		}
		// Handle value - check if it's an implicit initialization
		if kv.value is CompositeLit && (kv.value as CompositeLit).typ is InvalidExpr {
			inner_comp := kv.value as CompositeLit
			// Check if map value type is an array - generate array literal
			if map_typ.val is ArrayType {
				arr_typ := map_typ.val as ArrayType
				app.gen('[')
				for i, e in inner_comp.elts {
					if i > 0 {
						app.gen(', ')
					}
					// Handle implicit struct in array
					if e is CompositeLit && (e as CompositeLit).typ is InvalidExpr {
						e_comp := e as CompositeLit
						// Get array element type and prefix the struct literal
						match arr_typ.elt {
							Ident {
								app.force_upper = true
								app.gen(app.go2v_ident(arr_typ.elt.name))
							}
							else {}
						}
						app.gen('{')
						for j, field in e_comp.elts {
							if j > 0 {
								app.gen(', ')
							}
							app.expr(field)
						}
						app.gen('}')
					} else {
						app.expr(e)
					}
				}
				app.gen(']')
			} else {
				app.expr(kv.value)
			}
		} else {
			app.expr(kv.value)
		}
		app.genln('')
	}
	app.gen('}')
}
