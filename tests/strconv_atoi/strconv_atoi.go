package main

import "strconv"

func testAtoi() {
	value, err := strconv.Atoi("123")
	if err == nil {
		println(value)
	}
}
