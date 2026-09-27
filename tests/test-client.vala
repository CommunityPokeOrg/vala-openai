/*
 * Copyright 2026 CommunityPokeOrg
 * SPDX-License-Identifier: MIT
 *
 * End-to-end client tests against an in-process loopback HTTP server.
 * They exercise the real libsoup transport: request serialization, auth
 * headers, response parsing, error mapping, retries and SSE streaming.
 */

using Openai;

private static MockServer server;

private static Client make_client() {
    var client = new Client("sk-test-123",
                            "http://127.0.0.1:%u".printf(server.port));
    client.timeout_seconds = 10;
    return client;
}

private const string MODELS_JSON = """
    {"object":"list",
     "data":[{"id":"gpt-4o","object":"model","created":1715367049,
              "owned_by":"system"},
             {"id":"gpt-4o-mini","object":"model","created":1721172741,
              "owned_by":"system"}]}
    """;

private const string CHAT_JSON = """
    {"id":"chatcmpl-abc","object":"chat.completion","created":1727000000,
     "model":"gpt-4o","system_fingerprint":"fp_abc",
     "choices":[{"index":0,
                 "message":{"role":"assistant","content":"Hello there!"},
                 "finish_reason":"stop"}],
     "usage":{"prompt_tokens":12,"completion_tokens":3,"total_tokens":15}}
    """;

private static void test_list_models() {
    server.push_response(new MockResponse(200, MODELS_JSON));
    var client = make_client();

    ModelList models;
    try {
        models = client.list_models();
    } catch (Openai.Error e) {
        assert_not_reached();
    }
    assert_cmpint((int) models.data.length, CompareOperator.EQ, 2);
    assert_cmpstr(models.data[0].id, CompareOperator.EQ, "gpt-4o");
    assert_cmpstr(models.data[1].owned_by, CompareOperator.EQ, "system");

    var req = server.last_request();
    assert(req != null);
    assert_cmpstr(req.method, CompareOperator.EQ, "GET");
    assert_cmpstr(req.path, CompareOperator.EQ, "/models");
    assert_cmpstr(req.headers.get("Authorization"),
                  CompareOperator.EQ, "Bearer sk-test-123");
}

private static void test_chat_completion() {
    server.push_response(new MockResponse(200, CHAT_JSON));
    var client = make_client();

    var request = new ChatCompletionRequest("gpt-4o");
    request.add_system("Be terse.");
    request.add_user("Say hi");
    request.temperature = 0.5;

    ChatCompletion reply;
    try {
        reply = client.chat_completion(request);
    } catch (Openai.Error e) {
        assert_not_reached();
    }
    assert_cmpstr(reply.id, CompareOperator.EQ, "chatcmpl-abc");
    assert_cmpstr(reply.text, CompareOperator.EQ, "Hello there!");
    assert(reply.usage != null);
    assert(reply.usage.total_tokens == 15);
    assert(client.last_error == null);

    var req = server.last_request();
    assert_cmpstr(req.method, CompareOperator.EQ, "POST");
    assert_cmpstr(req.path, CompareOperator.EQ, "/chat/completions");
    assert_cmpstr(req.headers.get("Authorization"),
                  CompareOperator.EQ, "Bearer sk-test-123");
    var sent = json_parse_test(req.body);
    assert_cmpstr(sent.get_string_member("model"), CompareOperator.EQ, "gpt-4o");
    var msgs = sent.get_array_member("messages");
    assert_cmpint((int) msgs.get_length(), CompareOperator.EQ, 2);
    assert_cmpstr(msgs.get_object_element(0).get_string_member("role"),
                  CompareOperator.EQ, "system");
    assert(sent.get_double_member("temperature") == 0.5);
}

private static void test_retrieve_model() {
    server.push_response(new MockResponse(
        200, """{"id":"gpt-4o","object":"model","created":1,
                 "owned_by":"system"}"""));
    var client = make_client();
    ModelInfo m;
    try {
        m = client.retrieve_model("gpt-4o");
    } catch (Openai.Error e) {
        assert_not_reached();
    }
    assert_cmpstr(m.id, CompareOperator.EQ, "gpt-4o");
    var req = server.last_request();
    assert_cmpstr(req.method, CompareOperator.EQ, "GET");
    assert_cmpstr(req.path, CompareOperator.EQ, "/models/gpt-4o");
}

private static void test_create_embedding() {
    server.push_response(new MockResponse(200, """
        {"object":"list","model":"text-embedding-3-small",
         "data":[{"object":"embedding","index":0,"embedding":[0.1,0.2]}],
         "usage":{"prompt_tokens":1,"total_tokens":1}}
        """));
    var client = make_client();
    EmbeddingResponse resp;
    try {
        resp = client.create_embedding(
            new EmbeddingRequest.for_text("text-embedding-3-small", "hello"));
    } catch (Openai.Error e) {
        assert_not_reached();
    }
    assert_cmpint((int) resp.data.length, CompareOperator.EQ, 1);
    assert(resp.data[0].vector.length == 2);

    var req = server.last_request();
    assert_cmpstr(req.path, CompareOperator.EQ, "/embeddings");
    var sent = json_parse_test(req.body);
    assert_cmpstr(sent.get_array_member("input").get_string_element(0),
                  CompareOperator.EQ, "hello");
}

private static void test_error_auth() {
    server.push_response(new MockResponse(401, """
        {"error":{"message":"Incorrect API key provided",
                  "type":"invalid_request_error","param":null,
                  "code":"invalid_api_key"}}
        """));
    var client = make_client();
    try {
        client.list_models();
        assert_not_reached();
    } catch (Openai.Error e) {
        assert(e is Openai.Error);
        assert(e.code == Openai.Error.AUTHENTICATION);
        assert_cmpstr(e.message, CompareOperator.EQ,
                      "Incorrect API key provided");
    }
    assert(client.last_error != null);
    assert_cmpstr(client.last_error.code, CompareOperator.EQ,
                  "invalid_api_key");
    assert(client.last_error.status == 401);
}

private static void test_error_rate_limit() {
    server.push_response(new MockResponse(429, """
        {"error":{"message":"Rate limit reached",
                  "type":"rate_limit_error","param":null,
                  "code":"rate_limit_exceeded"}}
        """).header("Retry-After", "0"));
    var client = make_client();
    client.max_retries = 0;
    try {
        client.list_models();
        assert_not_reached();
    } catch (Openai.Error e) {
        assert(e.code == Openai.Error.RATE_LIMIT);
    }
    assert(client.last_error != null);
    assert_cmpstr(client.last_error.error_type, CompareOperator.EQ,
                  "rate_limit_error");
}

private static void test_retry_then_success() {
    server.push_response(new MockResponse(503, """
        {"error":{"message":"overloaded","type":"server_error"}}
        """).header("Retry-After", "0"));
    server.push_response(new MockResponse(200, MODELS_JSON));
    var client = make_client();
    client.max_retries = 1;

    int before = server.request_count;
    ModelList models;
    try {
        models = client.list_models();
    } catch (Openai.Error e) {
        assert_not_reached();
    }
    assert_cmpint((int) models.data.length, CompareOperator.EQ, 2);
    assert(server.request_count == before + 2);
    assert(client.last_error == null);
}

private static void test_retry_exhausted() {
    for (int i = 0; i < 3; i++)
        server.push_response(new MockResponse(500, """
            {"error":{"message":"boom","type":"server_error"}}
            """).header("Retry-After", "0"));
    var client = make_client();
    client.max_retries = 2;
    int before = server.request_count;
    try {
        client.list_models();
        assert_not_reached();
    } catch (Openai.Error e) {
        assert(e.code == Openai.Error.SERVER);
    }
    assert(server.request_count == before + 3);
    assert(client.last_error != null);
    assert_cmpstr(client.last_error.message, CompareOperator.EQ, "boom");
}

private static void test_streaming() {
    server.push_response(new MockResponse(200,
        "data: {\"id\":\"x\",\"created\":1,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}\n\n" +
        "data: {\"id\":\"x\",\"created\":1,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n\n" +
        ": keep-alive comment\n\n" +
        "data: {\"id\":\"x\",\"created\":1,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" world\"},\"finish_reason\":\"stop\"}]}\n\n" +
        "data: {\"id\":\"x\",\"created\":1,\"model\":\"gpt-4o\",\"choices\":[],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":2,\"total_tokens\":3}}\n\n" +
        "data: [DONE]\n\n",
        "text/event-stream"));
    var client = make_client();

    var request = new ChatCompletionRequest("gpt-4o");
    request.add_user("Hi");
    request.include_usage_in_stream = true;

    ChatCompletionStream stream;
    try {
        stream = client.chat_completion_stream(request);
    } catch (Openai.Error e) {
        assert_not_reached();
    }
    var text = new StringBuilder();
    bool saw_role = false;
    string? finish = null;
    CompletionUsage? usage = null;
    bool post_done_null = false;
    try {
        ChatCompletionChunk? chunk;
        while ((chunk = stream.next()) != null) {
            if (chunk.choices.length > 0) {
                if (chunk.choices[0].delta.role != null)
                    saw_role = true;
                if (chunk.choices[0].delta.content != null)
                    text.append(chunk.choices[0].delta.content);
                if (chunk.choices[0].finish_reason != null)
                    finish = chunk.choices[0].finish_reason;
            }
            if (chunk.usage != null)
                usage = chunk.usage;
        }
        post_done_null = stream.next() == null;
    } catch (Openai.Error e) {
        assert_not_reached();
    }
    assert(stream.is_finished);
    assert(saw_role);
    assert_cmpstr(text.str, CompareOperator.EQ, "Hello world");
    assert_cmpstr(finish, CompareOperator.EQ, "stop");
    assert(usage != null);
    assert(usage.total_tokens == 3);
    assert(post_done_null);

    var req = server.last_request();
    var sent = json_parse_test(req.body);
    assert(sent.get_boolean_member("stream"));
    assert(sent.get_object_member("stream_options")
             .get_boolean_member("include_usage"));
}

// --- async variants, driven by a main loop -----------------------------

private static MainLoop loop;
private static ChatCompletion? async_reply;
private static GLib.Error? async_error;
private static GenericArray<ChatCompletionChunk>? async_chunks;

private static async void run_chat_async(Client client,
                                         ChatCompletionRequest request) {
    try {
        async_reply = yield client.chat_completion_async(request);
    } catch (GLib.Error e) {
        async_error = e;
    }
    loop.quit();
}

private static void test_chat_completion_async() {
    server.push_response(new MockResponse(200, CHAT_JSON));
    var client = make_client();
    var request = new ChatCompletionRequest("gpt-4o");
    request.add_user("Say hi");

    loop = new MainLoop();
    async_reply = null;
    async_error = null;
    run_chat_async.begin(client, request);
    loop.run();

    assert(async_error == null);
    assert(async_reply != null);
    assert_cmpstr(async_reply.text, CompareOperator.EQ, "Hello there!");
}

private static async void run_stream_async(Client client,
                                           ChatCompletionRequest request) {
    try {
        var stream = yield client.chat_completion_stream_async(request);
        async_chunks = new GenericArray<ChatCompletionChunk>();
        ChatCompletionChunk? chunk;
        while ((chunk = yield stream.next_async()) != null)
            async_chunks.add(chunk);
    } catch (GLib.Error e) {
        async_error = e;
    }
    loop.quit();
}

private static void test_streaming_async() {
    server.push_response(new MockResponse(200,
        "data: {\"id\":\"x\",\"created\":1,\"model\":\"m\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"A\"}}]}\n\n" +
        "data: {\"id\":\"x\",\"created\":1,\"model\":\"m\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"B\"},\"finish_reason\":\"stop\"}]}\n\n" +
        "data: [DONE]\n\n",
        "text/event-stream"));
    var client = make_client();
    var request = new ChatCompletionRequest("gpt-4o");
    request.add_user("Hi");

    loop = new MainLoop();
    async_chunks = null;
    async_error = null;
    run_stream_async.begin(client, request);
    loop.run();

    assert(async_error == null);
    assert(async_chunks != null);
    assert_cmpint((int) async_chunks.length, CompareOperator.EQ, 2);
    assert_cmpstr(async_chunks[0].text_delta, CompareOperator.EQ, "A");
    assert_cmpstr(async_chunks[1].text_delta, CompareOperator.EQ, "B");
}

private static Json.Object json_parse_test(string data) {
    var parser = new Json.Parser();
    try {
        parser.load_from_data(data, -1);
    } catch (GLib.Error e) {
        assert_not_reached();
    }
    return parser.get_root().get_object().ref();
}

public static int main(string[] args) {
    Test.init(ref args);

    server = new MockServer();
    try {
        server.start();
    } catch (GLib.Error e) {
        error("cannot start mock server: %s", e.message);
    }

    Test.add_func("/openai/client/list-models", test_list_models);
    Test.add_func("/openai/client/chat-completion", test_chat_completion);
    Test.add_func("/openai/client/retrieve-model", test_retrieve_model);
    Test.add_func("/openai/client/create-embedding", test_create_embedding);
    Test.add_func("/openai/client/error-auth", test_error_auth);
    Test.add_func("/openai/client/error-rate-limit", test_error_rate_limit);
    Test.add_func("/openai/client/retry-then-success",
                  test_retry_then_success);
    Test.add_func("/openai/client/retry-exhausted", test_retry_exhausted);
    Test.add_func("/openai/client/streaming", test_streaming);
    Test.add_func("/openai/client/chat-completion-async",
                  test_chat_completion_async);
    Test.add_func("/openai/client/streaming-async", test_streaming_async);

    var result = Test.run();
    server.stop();
    return result;
}
