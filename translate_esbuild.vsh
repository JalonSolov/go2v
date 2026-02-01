#!/usr/bin/env -S v run

// Translate all esbuild Go files to V in parallel
import os
import sync
import runtime

const esbuild_src = os.home_dir() + '/code/3rd/esbuild'
const esbuild_v = '/Users/alex/code/go2v/esbuild_v'
const go2v = '/Users/alex/code/go2v/go2v'

struct Result {
	file    string
	success bool
}

fn translate_file(file string, results_ch chan Result) {
	src_file := '${esbuild_src}/${file}'
	mut v_file := file.replace('.go', '.v')
	// Flatten directory structure - remove internal/ and pkg/ prefixes
	// This avoids V module resolution issues with nested directories
	v_file = v_file.replace('internal/', '').replace('pkg/', '')
	dest_file := '${esbuild_v}/${v_file}'
	dest_dir := os.dir(dest_file)

	// Ensure destination directory exists
	os.mkdir_all(dest_dir) or {}

	// Run go2v on the source file
	res := os.execute('${go2v} "${src_file}" 2>/dev/null')
	if res.exit_code == 0 {
		// The translator creates the .v file next to the .go file
		generated := src_file.replace('.go', '.v')
		if os.exists(generated) {
			os.mv(generated, dest_file) or {
				results_ch <- Result{file, false}
				return
			}
			results_ch <- Result{file, true}
			return
		}
	}
	results_ch <- Result{file, false}
}

fn collect_go_files_recursive(dir string) []string {
	mut files := []string{}
	entries := os.ls(dir) or { return files }

	for entry in entries {
		full_path := '${dir}/${entry}'
		if os.is_dir(full_path) {
			// Skip vendor and testdata directories
			if entry == 'vendor' || entry == 'testdata' {
				continue
			}
			files << collect_go_files_recursive(full_path)
		} else if entry.ends_with('.go') && !entry.ends_with('_test.go')
			&& !entry.ends_with('_wasm.go') && !entry.ends_with('_unix.go')
			&& !entry.ends_with('_other.go')
			&& entry !in ['fs_zip.go', 'js_ident.go', 'unicode.go', 'xxhash.go'] {
			// Convert absolute path to relative
			rel_path := full_path.replace(esbuild_src + '/', '')
			files << rel_path
		}
	}
	return files
}

fn main() {
	mut files := collect_go_files_recursive(esbuild_src)
	files.sort()

	num_threads := runtime.nr_cpus()
	println('Using ${num_threads} threads to translate ${files.len} files...')
	println('')

	results_ch := chan Result{cap: files.len}
	mut wg := sync.new_waitgroup()
	wg.add(files.len)

	// Spawn all translation tasks
	for file in files {
		spawn fn (f string, ch chan Result, mut w sync.WaitGroup) {
			translate_file(f, ch)
			w.done()
		}(file, results_ch, mut wg)
	}

	// Wait for all tasks to complete
	wg.wait()
	results_ch.close()

	// Collect results
	mut success := 0
	mut failed := 0
	mut failed_files := []string{}

	for {
		res := <-results_ch or { break }
		if res.success {
			success++
			println('OK: ${res.file}')
		} else {
			failed++
			failed_files << res.file
			println('FAIL: ${res.file}')
		}
	}

	println('')
	println('=========================================')
	println('Translation complete!')
	println('Success: ${success}')
	println('Failed: ${failed}')
	if failed > 0 {
		println('')
		println('Failed files:')
		for f in failed_files {
			println('  - ${f}')
		}
	}
}
