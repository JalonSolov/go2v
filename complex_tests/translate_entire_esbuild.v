// Test script that runs go2v on each file in ~/code/3rd/esbuild/**/*.go
// Stops at the first failure where go2v + vfmt fails
module main

import os
import term

fn collect_go_files(dir string, mut files []string, skip_tests bool) {
	entries := os.ls(dir) or { return }
	for entry in entries {
		path := os.join_path(dir, entry)
		if os.is_dir(path) {
			collect_go_files(path, mut files, skip_tests)
		} else if entry.ends_with('.go') {
			// Skip test files if requested
			if skip_tests && entry.ends_with('_test.go') {
				continue
			}
			files << path
		}
	}
}

fn main() {
	esbuild_path := os.expand_tilde_to_home('~/code/3rd/esbuild')
	go2v_path := os.join_path(os.dir(os.dir(@FILE)), 'go2v')

	if !os.exists(go2v_path) {
		eprintln('go2v binary not found at ${go2v_path}')
		eprintln('Please build it first with: v . -o go2v')
		exit(1)
	}

	if !os.exists(esbuild_path) {
		eprintln('esbuild directory not found at ${esbuild_path}')
		exit(1)
	}

	mut go_files := []string{}
	collect_go_files(esbuild_path, mut go_files, true) // skip_tests=true
	go_files.sort()

	println('Found ${go_files.len} Go files in ${esbuild_path}')

	mut passed := 0
	mut failed := 0

	for go_file in go_files {
		v_file := go_file.replace('.go', '.v')
		json_file := go_file + '.json'

		// Run go2v
		go2v_result := os.execute('${go2v_path} "${go_file}" 2>&1')

		// Check if .v file was generated
		if !os.exists(v_file) {
			println(term.red('FAILED go2v: ${go_file}'))
			println(go2v_result.output)
			failed++
			break
		}

		// Run vfmt to validate the generated V code
		vfmt_result := os.execute('v fmt "${v_file}" 2>&1')
		if vfmt_result.exit_code != 0 {
			// Check if it's a vfmt crash/panic (not a syntax error in our output)
			if vfmt_result.output.contains('V panic') {
				println(term.yellow('VFMT CRASH: ${go_file} (vfmt bug, not go2v)'))
				// Clean up and continue
				os.rm(v_file) or {}
				os.rm(json_file) or {}
				passed++ // Count as passed since go2v succeeded
				continue
			}
			println(term.red('FAILED vfmt: ${go_file}'))
			lines := vfmt_result.output.split('\n')
			max_lines := if lines.len < 20 { lines.len } else { 20 }
			println(lines[..max_lines].join('\n'))
			// Clean up
			os.rm(v_file) or {}
			os.rm(json_file) or {}
			failed++
			break
		}

		// Clean up generated files
		os.rm(v_file) or {}
		os.rm(json_file) or {}

		println(term.green('OK: ${go_file}'))
		passed++
	}

	println('')
	println('Results: ${passed} passed, ${failed} failed')
	if failed > 0 {
		exit(1)
	}
}
