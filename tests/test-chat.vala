/*
 * Copyright 2026 CommunityPokeOrg
 * SPDX-License-Identifier: MIT
 *
 * Unit tests for request serialization and response deserialization.
 * No network involved — these exercise the pure JSON layer.
 */

using Openai;

private static Json.Parser parser;

private static string node_str(Json.Node node) {
    var gen = new Json.Generator();
    gen.set_root(node);
    return gen.to_data(null);
}

private static Json.Object parse(string data) {
    try {
        parser.load_from_data(data, -1);
    } catch (GLib.Error e) {
        assert_not_reached();
    }
    return parser.get_root().get_object().ref();
}

private static ChatMessage msg_from(Json.Object obj) {
    try {
        return ChatMessage.from_json(obj);
    } catch (Openai.Error e) {
        assert_not_reached();
    }
}

private static ChatCompletion chat_from(Json.Object obj) {
    try {
        return ChatCompletion.from_json(obj);
    } catch (Openai.Error e) {
        assert_not_reached();
    }
}

private static ChatCompletionChunk chunk_from(string data) {
    try {
        return ChatCompletionChunk.from_data(data);
    } catch (Openai.Error e) {
        assert_not_reached();
    }
}

private static EmbeddingResponse emb_from(string data) {
    try {
        return EmbeddingResponse.from_data(data);
    } catch (Openai.Error e) {
        assert_not_reached();
    }
}

private static ImageGenerationResponse images_from(string data) {
    try {
        return ImageGenerationResponse.from_data(data);
    } catch (Openai.Error e) {
        assert_not_reached();
    }
}

private static ModelList models_from(string data) {
    try {
        return ModelList.from_data(data);
    } catch (Openai.Error e) {
        assert_not_reached();
    }
}

private static void test_role_wire() {
    assert_cmpstr(ChatRole.SYSTEM.to_wire(), CompareOperator.EQ, "system");
    assert_cmpstr(ChatRole.DEVELOPER.to_wire(), CompareOperator.EQ, "developer");
    assert_cmpstr(ChatRole.USER.to_wire(), CompareOperator.EQ, "user");
    assert_cmpstr(ChatRole.ASSISTANT.to_wire(), CompareOperator.EQ, "assistant");
    assert_cmpstr(ChatRole.TOOL.to_wire(), CompareOperator.EQ, "tool");
    assert(ChatRole.from_wire("assistant") == ChatRole.ASSISTANT);
    assert(ChatRole.from_wire("bogus") == ChatRole.USER);
    assert(ChatRole.from_wire(null) == ChatRole.USER);
}

private static void test_message_serialization() {
    var msg = new ChatMessage(ChatRole.USER, "Hello");
    msg.name = "alice";
    var obj = parse(node_str(msg.to_json()));
    assert_cmpstr(obj.get_string_member("role"), CompareOperator.EQ, "user");
    assert_cmpstr(obj.get_string_member("content"), CompareOperator.EQ, "Hello");
    assert_cmpstr(obj.get_string_member("name"), CompareOperator.EQ, "alice");
    assert(!obj.has_member("tool_calls"));
    assert(!obj.has_member("tool_call_id"));
}

private static void test_message_tool_fields() {
    var msg = new ChatMessage.tool("call_42", "sunny");
    var obj = parse(node_str(msg.to_json()));
    assert_cmpstr(obj.get_string_member("role"), CompareOperator.EQ, "tool");
    assert_cmpstr(obj.get_string_member("tool_call_id"),
                  CompareOperator.EQ, "call_42");

    var assistant = new ChatMessage.assistant(null);
    assistant.tool_calls = new GenericArray<ToolCall>();
    assistant.tool_calls.add(new ToolCall(
        "call_1", new FunctionCall("get_weather", "{\"city\":\"Paris\"}")));
    var obj2 = parse(node_str(assistant.to_json()));
    assert(!obj2.has_member("content"));
    var calls = obj2.get_array_member("tool_calls");
    assert_cmpint((int) calls.get_length(), CompareOperator.EQ, 1);
    var call0 = calls.get_object_element(0);
    assert_cmpstr(call0.get_string_member("id"), CompareOperator.EQ, "call_1");
    var fn = call0.get_object_member("function");
    assert_cmpstr(fn.get_string_member("name"),
                  CompareOperator.EQ, "get_weather");
    assert_cmpstr(fn.get_string_member("arguments"),
                  CompareOperator.EQ, "{\"city\":\"Paris\"}");
}

private static void test_message_deserialization() {
    var obj = parse("""{"role":"assistant","content":"Hi","name":"bob"}""");
    var msg = msg_from(obj);
    assert(msg.role == ChatRole.ASSISTANT);
    assert_cmpstr(msg.content, CompareOperator.EQ, "Hi");
    assert_cmpstr(msg.name, CompareOperator.EQ, "bob");
}

private static void test_request_minimal() {
    var req = new ChatCompletionRequest("gpt-4o");
    req.add_user("Hi");
    var obj = parse(node_str(req.to_json()));
    assert_cmpstr(obj.get_string_member("model"), CompareOperator.EQ, "gpt-4o");
    var msgs = obj.get_array_member("messages");
    assert_cmpint((int) msgs.get_length(), CompareOperator.EQ, 1);
    assert_cmpstr(msgs.get_object_element(0).get_string_member("content"),
                  CompareOperator.EQ, "Hi");
    // Defaults must not be serialized
    assert(!obj.has_member("temperature"));
    assert(!obj.has_member("stream"));
    assert(!obj.has_member("tools"));
    assert(!obj.has_member("tool_choice"));
    assert(!obj.has_member("response_format"));
}

private static void test_request_full() {
    var req = new ChatCompletionRequest("gpt-4o");
    req.add_system("sys");
    req.add_user("hi");
    req.temperature = 0.7;
    req.top_p = 0.9;
    req.n = 2;
    req.max_tokens = 128;
    req.max_completion_tokens = 64;
    req.stop = {"END", "STOP"};
    req.presence_penalty = 0.5;
    req.frequency_penalty = -0.5;
    req.response_format = ResponseFormat.JSON_OBJECT;
    req.seed = 42;
    req.user = "user-1";
    req.parallel_tool_calls = true;
    req.include_usage_in_stream = true;
    req.logit_bias = new HashTable<string, int>(str_hash, str_equal);
    req.logit_bias.set("1234", -100);
    req.tools = new GenericArray<Tool>();
    var schema = new Json.Parser();
    try {
        schema.load_from_data(
            """{"type":"object","properties":{"city":{"type":"string"}}}""", -1);
    } catch (GLib.Error e) {
        assert_not_reached();
    }
    req.tools.add(new Tool(new FunctionDefinition(
        "get_weather", "Get weather", schema.get_root())));
    req.tool_choice_function = "get_weather";

    var obj = parse(node_str(req.to_json()));
    assert_cmpint((int) obj.get_array_member("messages").get_length(),
                  CompareOperator.EQ, 2);
    assert(obj.get_double_member("temperature") == 0.7);
    assert(obj.get_double_member("top_p") == 0.9);
    assert(obj.get_int_member("n") == 2);
    assert(obj.get_int_member("max_tokens") == 128);
    assert(obj.get_int_member("max_completion_tokens") == 64);
    assert_cmpint((int) obj.get_array_member("stop").get_length(),
                  CompareOperator.EQ, 2);
    assert(obj.get_double_member("presence_penalty") == 0.5);
    assert(obj.get_double_member("frequency_penalty") == -0.5);
    assert_cmpstr(
        obj.get_object_member("response_format").get_string_member("type"),
        CompareOperator.EQ, "json_object");
    assert(obj.get_object_member("logit_bias").get_int_member("1234") == -100);
    assert(obj.get_boolean_member("parallel_tool_calls"));
    assert(obj.get_int_member("seed") == 42);
    assert_cmpstr(obj.get_string_member("user"), CompareOperator.EQ, "user-1");
    assert(obj.get_object_member("stream_options")
              .get_boolean_member("include_usage"));
    var tools = obj.get_array_member("tools");
    assert_cmpstr(
        tools.get_object_element(0).get_string_member("type"),
        CompareOperator.EQ, "function");
    var fn = tools.get_object_element(0).get_object_member("function");
    assert_cmpstr(fn.get_string_member("name"),
                  CompareOperator.EQ, "get_weather");
    assert(fn.get_object_member("parameters")
            .has_member("properties"));
    var tc = obj.get_object_member("tool_choice");
    assert_cmpstr(tc.get_string_member("type"), CompareOperator.EQ, "function");
    assert_cmpstr(tc.get_object_member("function").get_string_member("name"),
                  CompareOperator.EQ, "get_weather");
}

private static void test_tool_choice_enum() {
    var req = new ChatCompletionRequest("gpt-4o");
    req.tool_choice = ToolChoice.NONE;
    var obj = parse(node_str(req.to_json()));
    assert_cmpstr(obj.get_string_member("tool_choice"),
                  CompareOperator.EQ, "none");
}

private static void test_completion_deserialization() {
    var obj = parse("""
        {"id":"chatcmpl-abc","object":"chat.completion","created":1727000000,
         "model":"gpt-4o-2024-05-13","system_fingerprint":"fp_x",
         "choices":[{"index":0,
                     "message":{"role":"assistant","content":"Hello there!"},
                     "finish_reason":"stop"}],
         "usage":{"prompt_tokens":12,"completion_tokens":3,"total_tokens":15}}
        """);
    var c = chat_from(obj);
    assert_cmpstr(c.id, CompareOperator.EQ, "chatcmpl-abc");
    assert(c.created == 1727000000);
    assert_cmpstr(c.model, CompareOperator.EQ, "gpt-4o-2024-05-13");
    assert_cmpstr(c.system_fingerprint, CompareOperator.EQ, "fp_x");
    assert_cmpint((int) c.choices.length, CompareOperator.EQ, 1);
    assert_cmpstr(c.choices[0].message.content,
                  CompareOperator.EQ, "Hello there!");
    assert(c.choices[0].message.role == ChatRole.ASSISTANT);
    assert_cmpstr(c.choices[0].finish_reason, CompareOperator.EQ, "stop");
    assert_cmpstr(c.text, CompareOperator.EQ, "Hello there!");
    assert(c.usage != null);
    assert(c.usage.prompt_tokens == 12);
    assert(c.usage.completion_tokens == 3);
    assert(c.usage.total_tokens == 15);
}

private static void test_completion_tool_calls() {
    var obj = parse("""
        {"id":"chatcmpl-x","created":1,"model":"gpt-4o",
         "choices":[{"index":0,
                     "message":{"role":"assistant","content":null,
                                "tool_calls":[{"id":"call_1","type":"function",
                                    "function":{"name":"f","arguments":"{}"}}]},
                     "finish_reason":"tool_calls"}]}
        """);
    var c = chat_from(obj);
    var m = c.choices[0].message;
    assert(m.content == null);
    assert(m.tool_calls != null);
    assert_cmpint((int) m.tool_calls.length, CompareOperator.EQ, 1);
    assert_cmpstr(m.tool_calls[0].id, CompareOperator.EQ, "call_1");
    assert_cmpstr(m.tool_calls[0].function.name, CompareOperator.EQ, "f");
    assert_cmpstr(c.choices[0].finish_reason, CompareOperator.EQ, "tool_calls");
    assert(c.text == null);
}

private static void test_chunk_deserialization() {
    var chunk = chunk_from("""
        {"id":"chatcmpl-abc","object":"chat.completion.chunk",
         "created":1727000000,"model":"gpt-4o",
         "choices":[{"index":0,
                     "delta":{"role":"assistant","content":"He"},
                     "finish_reason":null}]}
        """);
    assert_cmpstr(chunk.id, CompareOperator.EQ, "chatcmpl-abc");
    assert_cmpint((int) chunk.choices.length, CompareOperator.EQ, 1);
    assert(chunk.choices[0].delta.role == ChatRole.ASSISTANT);
    assert_cmpstr(chunk.choices[0].delta.content, CompareOperator.EQ, "He");
    assert(chunk.choices[0].finish_reason == null);
    assert_cmpstr(chunk.text_delta, CompareOperator.EQ, "He");
}

private static void test_chunk_tool_call_delta() {
    var chunk = chunk_from("""
        {"id":"c","created":1,"model":"m",
         "choices":[{"index":0,"finish_reason":null,
                     "delta":{"tool_calls":[{"index":0,"id":"call_1",
                        "type":"function",
                        "function":{"name":"get_weather","arguments":""}}]}}]}
        """);
    var tc = chunk.choices[0].delta.tool_calls[0];
    assert(tc.index == 0);
    assert_cmpstr(tc.id, CompareOperator.EQ, "call_1");
    assert_cmpstr(tc.function.name, CompareOperator.EQ, "get_weather");
}

private static void test_chunk_usage() {
    var chunk = chunk_from("""
        {"id":"c","created":1,"model":"m","choices":[],
         "usage":{"prompt_tokens":5,"completion_tokens":7,"total_tokens":12}}
        """);
    assert(chunk.usage != null);
    assert(chunk.usage.total_tokens == 12);
    assert_cmpint((int) chunk.choices.length, CompareOperator.EQ, 0);
}

private static void test_embedding_request() {
    var req = new EmbeddingRequest("text-embedding-3-small",
                                   {"hello", "world"});
    req.dimensions = 512;
    var obj = parse(node_str(req.to_json()));
    assert_cmpstr(obj.get_string_member("model"),
                  CompareOperator.EQ, "text-embedding-3-small");
    var input = obj.get_array_member("input");
    assert_cmpint((int) input.get_length(), CompareOperator.EQ, 2);
    assert_cmpstr(input.get_string_element(0), CompareOperator.EQ, "hello");
    assert(obj.get_int_member("dimensions") == 512);
    assert(!obj.has_member("encoding_format"));
}

private static void test_embedding_response() {
    var r = emb_from("""
        {"object":"list","model":"text-embedding-3-small",
         "data":[{"object":"embedding","index":0,
                  "embedding":[0.5, -0.25, 1.0]}],
         "usage":{"prompt_tokens":2,"total_tokens":2}}
        """);
    assert_cmpstr(r.model, CompareOperator.EQ, "text-embedding-3-small");
    assert_cmpint((int) r.data.length, CompareOperator.EQ, 1);
    assert(r.data[0].index == 0);
    assert(r.data[0].vector.length == 3);
    assert(r.data[0].vector[0] == 0.5f);
    assert(r.data[0].vector[2] == 1.0f);
    assert(r.usage.prompt_tokens == 2);
}

private static void test_embedding_base64() {
    // two float32 values: 1.0 and -2.5, little-endian
    var r = emb_from("""
        {"object":"list","model":"m",
         "data":[{"object":"embedding","index":0,
                  "embedding":"AACAPwAAIMA="}]}
        """);
    assert(r.data[0].vector.length == 2);
    assert(r.data[0].vector[0] == 1.0f);
    assert(r.data[0].vector[1] == -2.5f);
}

private static void test_image_request() {
    var req = new ImageGenerationRequest("a cat");
    req.model = "dall-e-3";
    req.n = 2;
    req.size = "1792x1024";
    req.quality = "hd";
    req.style = "natural";
    req.user = "user-1";
    var obj = parse(node_str(req.to_json()));
    assert_cmpstr(obj.get_string_member("prompt"), CompareOperator.EQ, "a cat");
    assert_cmpstr(obj.get_string_member("model"), CompareOperator.EQ, "dall-e-3");
    assert(obj.get_int_member("n") == 2);
    assert_cmpstr(obj.get_string_member("size"), CompareOperator.EQ, "1792x1024");
    assert_cmpstr(obj.get_string_member("quality"), CompareOperator.EQ, "hd");
    assert_cmpstr(obj.get_string_member("style"), CompareOperator.EQ, "natural");
    // URL is the API default — not serialized
    assert(!obj.has_member("response_format"));

    req.format = ImageFormat.B64_JSON;
    var obj2 = parse(node_str(req.to_json()));
    assert_cmpstr(obj2.get_string_member("response_format"),
                  CompareOperator.EQ, "b64_json");
}

private static void test_image_response() {
    var r = images_from("""
        {"created":1727000000,
         "data":[{"url":"https://img.test/1.png",
                  "revised_prompt":"a nice cat"},
                 {"b64_json":"QUJD"}]}
        """);
    assert(r.created == 1727000000);
    assert_cmpint((int) r.data.length, CompareOperator.EQ, 2);
    assert_cmpstr(r.data[0].url, CompareOperator.EQ, "https://img.test/1.png");
    assert_cmpstr(r.data[0].revised_prompt, CompareOperator.EQ, "a nice cat");
    assert(r.data[0].b64_json == null);
    assert_cmpstr(r.data[1].b64_json, CompareOperator.EQ, "QUJD");
    assert(r.data[1].url == null);
}

private static void test_model_list() {
    var l = models_from("""
        {"object":"list",
         "data":[{"id":"gpt-4o","object":"model","created":1,
                  "owned_by":"system"},
                 {"id":"gpt-4o-mini","object":"model","created":2,
                  "owned_by":"system"}]}
        """);
    assert_cmpint((int) l.data.length, CompareOperator.EQ, 2);
    assert_cmpstr(l.data[0].id, CompareOperator.EQ, "gpt-4o");
    assert_cmpstr(l.data[1].owned_by, CompareOperator.EQ, "system");
}

private static void test_api_error_parse() {
    var e = ApiError.try_parse("""
        {"error":{"message":"Incorrect API key provided",
                  "type":"invalid_request_error","param":null,
                  "code":"invalid_api_key"}}
        """, 401);
    assert(e != null);
    assert(e.status == 401);
    assert_cmpstr(e.message, CompareOperator.EQ, "Incorrect API key provided");
    assert_cmpstr(e.error_type, CompareOperator.EQ, "invalid_request_error");
    assert(e.param == null);
    assert_cmpstr(e.code, CompareOperator.EQ, "invalid_api_key");

    assert(ApiError.try_parse("not json", 500) == null);
    assert(ApiError.try_parse("{\"foo\":1}", 500) == null);
}

private static void test_malformed_completion() {
    try {
        ChatCompletion.from_data("this is not json");
        assert_not_reached();
    } catch (Openai.Error e) {
        assert(e is Openai.Error);
        assert(e.code == Openai.Error.PARSE);
    }
}

public static int main(string[] args) {
    Test.init(ref args);
    parser = new Json.Parser();

    Test.add_func("/openai/role/wire", test_role_wire);
    Test.add_func("/openai/message/serialize", test_message_serialization);
    Test.add_func("/openai/message/tool-fields", test_message_tool_fields);
    Test.add_func("/openai/message/deserialize", test_message_deserialization);
    Test.add_func("/openai/request/minimal", test_request_minimal);
    Test.add_func("/openai/request/full", test_request_full);
    Test.add_func("/openai/request/tool-choice", test_tool_choice_enum);
    Test.add_func("/openai/completion/parse", test_completion_deserialization);
    Test.add_func("/openai/completion/tool-calls",
                  test_completion_tool_calls);
    Test.add_func("/openai/chunk/parse", test_chunk_deserialization);
    Test.add_func("/openai/chunk/tool-call-delta", test_chunk_tool_call_delta);
    Test.add_func("/openai/chunk/usage", test_chunk_usage);
    Test.add_func("/openai/embedding/request", test_embedding_request);
    Test.add_func("/openai/embedding/response", test_embedding_response);
    Test.add_func("/openai/embedding/base64", test_embedding_base64);
    Test.add_func("/openai/image/request", test_image_request);
    Test.add_func("/openai/image/response", test_image_response);
    Test.add_func("/openai/models/list", test_model_list);
    Test.add_func("/openai/error/parse", test_api_error_parse);
    Test.add_func("/openai/error/malformed", test_malformed_completion);

    return Test.run();
}
