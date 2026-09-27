project('vala-openai', 'vala', 'c',
  version : '1.0.0',
  license : 'MIT',
  meson_version : '>= 0.56.0',
  default_options : ['warning_level=1'])

glib_dep    = dependency('glib-2.0', version : '>= 2.66')
gobject_dep = dependency('gobject-2.0', version : '>= 2.66')
gio_dep     = dependency('gio-2.0', version : '>= 2.66')
soup_dep    = dependency('libsoup-3.0', version : '>= 3.0')
json_dep    = dependency('json-glib-1.0', version : '>= 1.6')

openai_deps = [glib_dep, gobject_dep, gio_dep, soup_dep, json_dep]

subdir('src')

if get_option('tests')
  subdir('tests')
endif

if get_option('docs')
  subdir('docs')
endif
