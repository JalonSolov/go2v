// Copyright (c) 2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can be found in the LICENSE file.

fn (mut app App) array_init(c CompositeLit) {
	typ := c.typ
	match typ {
		ArrayType {
			mut have_len := false
			mut len_val := ''
			mut is_fixed := false
			if typ.len is BasicLit {
				is_fixed = typ.len.value != ''
				have_len = typ.len.value != ''
				len_val = typ.len.value
			} else if typ.len is Ellipsis {
				is_fixed = true
			}
			mut elt_name := ''
			mut elt_is_selector := false
			mut elt_is_ident := false
			match typ.elt {
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
						else {
							app.gen('>> unhandled array type "${x.node_type}"')
						}
					}
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
				app.gen(']${elt_name}{}')
			} else {
				match c.elts[0] {
					BasicLit, CallExpr, CompositeLit, Ident, SelectorExpr, UnaryExpr {
						for i, elt in c.elts {
							if i > 0 {
								app.gen(',')
							}
							if i == 0 && elt_name != '' && elt_name != 'string'
								&& !elt_name.starts_with_capital() {
								// specify type in the first element
								// [u8(1), 2, 3]
								app.gen('${elt_name}(')
								app.expr(elt)
								app.gen(')')
							} else if elt is CompositeLit && (elt as CompositeLit).typ is InvalidExpr {
								// Array with implicit element type
								// []Type{{Field: value}} => [Type{field: value}]
								// []pkg.Type{{Field: value}} => [pkg.Type{field: value}]
								if elt_is_selector {
									app.force_upper = true
									app.selector_expr(typ.elt as SelectorExpr)
								} else if elt_is_ident {
									app.force_upper = true
									app.gen(app.go2v_ident((typ.elt as Ident).name))
								}
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
						if typ.len !is InvalidExpr {
							app.expr(typ.len)
						}
						app.gen(']${elt_name}{ init: match index {')
						for elt in c.elts {
							app.expr((elt as KeyValueExpr).key)
							app.gen('{')
							app.expr((elt as KeyValueExpr).value)
							app.gen('}')
						}
						app.gen('else{0}}}')
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
	for elt in node.elts {
		kv := elt as KeyValueExpr
		app.key_value_expr(kv)
		app.genln('')
	}
	app.gen('}')
}
