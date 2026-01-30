package main

import "fmt"

type InsertionModeStack []int

func (s InsertionModeStack) foo() int {
	i := len(s)
	im := s[i-1]
	a := &i
	fmt.Println(*a)
	return im
}
