test_chat = executable('test-chat',
  'test-chat.vala',
  dependencies : openai_dep)

test_client = executable('test-client',
  'test-client.vala',
  'mock-server.vala',
  dependencies : openai_dep)

test('chat-models', test_chat,
  suite : 'openai',
  timeout : 30)

test('client', test_client,
  suite : 'openai',
  timeout : 120)
