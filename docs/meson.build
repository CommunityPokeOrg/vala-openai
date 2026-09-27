valadoc = find_program('valadoc', required : true)

run_target('docs',
  command : [
    valadoc,
    '--package-name', 'openai-1.0',
    '--package-version', meson.project_version(),
    '--pkg', 'glib-2.0', '--pkg', 'gobject-2.0', '--pkg', 'gio-2.0',
    '--pkg', 'libsoup-3.0', '--pkg', 'json-glib-1.0',
    '-o', meson.current_build_dir() / 'html',
    openai_sources,
  ])
