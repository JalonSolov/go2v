package main

func testChanRecv() {
	ch := make(chan int)
	value, ok := <-ch
	if ok {
		println(value)
	}
}
