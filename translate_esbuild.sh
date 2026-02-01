#!/bin/bash

# Translate all esbuild Go files to V

ESBUILD_SRC="$HOME/code/3rd/esbuild"
ESBUILD_V="/Users/alex/code/go2v/esbuild_v"
GO2V="/Users/alex/code/go2v/go2v"

# List of all non-test Go files
files=(
    "cmd/esbuild/main_other.go"
    "cmd/esbuild/main_wasm.go"
    "cmd/esbuild/main.go"
    "cmd/esbuild/stdio_protocol.go"
    "cmd/esbuild/version.go"
    "internal/api_helpers/use_timer.go"
    "internal/ast/ast.go"
    "internal/bundler/bundler.go"
    "internal/cache/cache_ast.go"
    "internal/cache/cache_fs.go"
    "internal/cache/cache.go"
    "internal/cli_helpers/cli_helpers.go"
    "internal/compat/compat.go"
    "internal/compat/css_table.go"
    "internal/compat/js_table.go"
    "internal/config/config.go"
    "internal/config/globals.go"
    "internal/css_ast/css_ast.go"
    "internal/css_ast/css_decl_table.go"
    "internal/css_lexer/css_lexer.go"
    "internal/css_parser/css_color_spaces.go"
    "internal/css_parser/css_decls_animation.go"
    "internal/css_parser/css_decls_border_radius.go"
    "internal/css_parser/css_decls_box_shadow.go"
    "internal/css_parser/css_decls_box.go"
    "internal/css_parser/css_decls_color.go"
    "internal/css_parser/css_decls_composes.go"
    "internal/css_parser/css_decls_container.go"
    "internal/css_parser/css_decls_font_family.go"
    "internal/css_parser/css_decls_font_weight.go"
    "internal/css_parser/css_decls_font.go"
    "internal/css_parser/css_decls_gradient.go"
    "internal/css_parser/css_decls_list_style.go"
    "internal/css_parser/css_decls_transform.go"
    "internal/css_parser/css_decls.go"
    "internal/css_parser/css_nesting.go"
    "internal/css_parser/css_parser_media.go"
    "internal/css_parser/css_parser_selector.go"
    "internal/css_parser/css_parser.go"
    "internal/css_parser/css_reduce_calc.go"
    "internal/css_printer/css_printer.go"
    "internal/fs/error_other.go"
    "internal/fs/error_wasm+windows.go"
    "internal/fs/filepath.go"
    "internal/fs/fs_mock.go"
    "internal/fs/fs_real.go"
    "internal/fs/fs_zip.go"
    "internal/fs/fs.go"
    "internal/fs/iswin_other.go"
    "internal/fs/iswin_wasm.go"
    "internal/fs/iswin_windows.go"
    "internal/fs/modkey_other.go"
    "internal/fs/modkey_unix.go"
    "internal/graph/graph.go"
    "internal/graph/input.go"
    "internal/graph/meta.go"
    "internal/helpers/bitset.go"
    "internal/helpers/comment.go"
    "internal/helpers/dataurl.go"
    "internal/helpers/float.go"
    "internal/helpers/glob.go"
    "internal/helpers/hash.go"
    "internal/helpers/joiner.go"
    "internal/helpers/mime.go"
    "internal/helpers/path.go"
    "internal/helpers/quote.go"
    "internal/helpers/serializer.go"
    "internal/helpers/stack.go"
    "internal/helpers/strings.go"
    "internal/helpers/timer.go"
    "internal/helpers/typos.go"
    "internal/helpers/utf.go"
    "internal/helpers/waitgroup.go"
    "internal/js_ast/js_ast_helpers.go"
    "internal/js_ast/js_ast.go"
    "internal/js_ast/js_ident.go"
    "internal/js_ast/unicode.go"
    "internal/js_lexer/js_lexer.go"
    "internal/js_lexer/tables.go"
    "internal/js_parser/global_name_parser.go"
    "internal/js_parser/js_parser_lower_class.go"
    "internal/js_parser/js_parser_lower.go"
    "internal/js_parser/js_parser.go"
    "internal/js_parser/json_parser.go"
    "internal/js_parser/sourcemap_parser.go"
    "internal/js_parser/ts_parser.go"
    "internal/js_printer/js_printer.go"
    "internal/linker/debug.go"
    "internal/linker/linker.go"
    "internal/logger/logger_darwin.go"
    "internal/logger/logger_linux.go"
    "internal/logger/logger_other.go"
    "internal/logger/logger_windows.go"
    "internal/logger/logger.go"
    "internal/logger/msg_ids.go"
    "internal/renamer/renamer.go"
    "internal/resolver/dataurl.go"
    "internal/resolver/package_json.go"
    "internal/resolver/resolver.go"
    "internal/resolver/tsconfig_json.go"
    "internal/resolver/yarnpnp.go"
    "internal/runtime/runtime.go"
    "internal/sourcemap/sourcemap.go"
    "internal/test/diff.go"
    "internal/test/util.go"
    "internal/xxhash/xxhash_other.go"
    "internal/xxhash/xxhash.go"
    "pkg/api/api_impl.go"
    "pkg/api/api_js_table.go"
    "pkg/api/api.go"
    "pkg/api/favicon.go"
    "pkg/api/serve_other.go"
    "pkg/api/serve_wasm.go"
    "pkg/api/watcher.go"
    "pkg/cli/cli_impl.go"
    "pkg/cli/cli_js_table.go"
    "pkg/cli/cli.go"
    "pkg/cli/mangle_cache.go"
)

success=0
failed=0
failed_files=()

for file in "${files[@]}"; do
    src_file="$ESBUILD_SRC/$file"
    # Convert .go to .v in the filename
    v_file="${file%.go}.v"
    dest_file="$ESBUILD_V/$v_file"
    dest_dir=$(dirname "$dest_file")

    echo "Translating: $file"

    # Ensure destination directory exists
    mkdir -p "$dest_dir"

    # Run go2v on the source file, output goes to same location as source
    if $GO2V "$src_file" 2>/dev/null; then
        # The translator creates the .v file next to the .go file
        generated="$ESBUILD_SRC/${file%.go}.v"
        if [ -f "$generated" ]; then
            mv "$generated" "$dest_file"
            ((success++))
        else
            echo "  ERROR: Output file not generated"
            ((failed++))
            failed_files+=("$file")
        fi
    else
        echo "  ERROR: Translation failed"
        ((failed++))
        failed_files+=("$file")
    fi
done

echo ""
echo "========================================="
echo "Translation complete!"
echo "Success: $success"
echo "Failed: $failed"
if [ $failed -gt 0 ]; then
    echo ""
    echo "Failed files:"
    for f in "${failed_files[@]}"; do
        echo "  - $f"
    done
fi
