//go:build !windows

package main

import "fmt"

// Outside Windows (only for tests): prints the address and keeps serving.
func openWindow(url, title string) {
	fmt.Println(title, "en", url)
	select {}
}

func revealFile(path string) {}
