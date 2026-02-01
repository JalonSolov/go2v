package main

import "os"

func testLookupEnv() {
	value, ok := os.LookupEnv("MY_VAR")
	if ok {
		println(value)
	}
}

func testLookupEnvDiscardOk() {
	value, _ := os.LookupEnv("MY_VAR")
	println(value)
}

func testLookupEnvDiscardValue() {
	_, ok := os.LookupEnv("MY_VAR")
	if ok {
		println("found")
	}
}
