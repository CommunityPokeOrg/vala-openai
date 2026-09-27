openai_sources = files(
  'error.vala',
  'json-utils.vala',
  'chat.vala',
  'embeddings.vala',
  'models.vala',
  'stream.vala',
  'client.vala',
)

openai_lib = shared_library('openai-1.0',
  openai_sources,
  dependencies : openai_deps,
  vala_header : 'openai-1.0.h',
  vala_vapi : 'openai-1.0.vapi',
  install : true,
  install_dir : [true, get_option('includedir') / 'openai-1.0', true],
)

install_data('openai-1.0.deps',
  install_dir : get_option('datadir') / 'vala' / 'vapi')

pkg = import('pkgconfig')
pkg.generate(openai_lib,
  name : 'openai-1.0',
  filebase : 'openai-1.0',
  description : 'Native OpenAI API client for GLib/Vala',
  url : 'https://github.com/CommunityPokeOrg/vala-openai',
  requires : ['glib-2.0', 'gobject-2.0', 'gio-2.0', 'libsoup-3.0', 'json-glib-1.0'],
  subdirs : 'openai-1.0')

openai_dep = declare_dependency(
  link_with : openai_lib,
  include_directories : include_directories('.'),
  dependencies : openai_deps)
