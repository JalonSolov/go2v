package main

func testMapLookup() {
	m := map[string]int{"a": 1}
	value, ok := m["a"]
	if ok {
		println(value)
	}
}
