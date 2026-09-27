/*
 * Copyright 2026 CommunityPokeOrg
 * SPDX-License-Identifier: MIT
 */

namespace Openai {

    /**
     * The author role of a chat message.
     */
    public enum ChatRole {
        SYSTEM,
        DEVELOPER,
        USER,
        ASSISTANT,
        TOOL;

        /** The JSON wire representation of this role. */
        public string to_wire() {
            switch (this) {
                case SYSTEM:    return "system";
                case DEVELOPER: return "developer";
                case USER:      return "user";
                case ASSISTANT: return "assistant";
                case TOOL:      return "tool";
                default:        assert_not_reached();
            }
        }

        /** Parses a wire role name; unknown values map to {@link USER}. */
        public static ChatRole from_wire(string? wire) {
            switch (wire) {
                case "system":    return SYSTEM;
                case "developer": return DEVELOPER;
                case "assistant": return ASSISTANT;
                case "tool":      return TOOL;
                default:          return USER;
            }
        }
    }

    /**
     * The `response_format` of a chat completion request.
     */
    public enum ResponseFormat {
        /** Unstructured text (the API default; omitted on the wire). */
        TEXT,
        /** Constrain output to a valid JSON object (`json_object`). */
        JSON_OBJECT;
    }

    /**
     * How the model selects tools during a chat completion.
     */
    public enum ToolChoice {
        /** Let the model decide (the API default; omitted on the wire). */
        AUTO,
        /** Forbid tool use (`"none"`). */
        NONE,
        /** Require at least one tool call (`"required"`). */
        REQUIRED;

        internal string to_wire() {
            switch (this) {
                case NONE:     return "none";
                case REQUIRED: return "required";
                default:       return "auto";
            }
        }
    }

    /**
     * A single message in a chat conversation.
     *
     * `content` is the plain-text form understood by every chat model;
     * tool-calling fields ({@link tool_calls}, {@link tool_call_id}) follow
     * the OpenAI tool-calling protocol.
     */
    public class ChatMessage : GLib.Object {
        /** The author role of this message. */
        public ChatRole role { get; set; }
        /** Textual content; `null` for pure tool-call assistant messages. */
        public string? content { get; set; }
        /** Optional participant name. */
        public string? name { get; set; }
        /** Tool calls issued by an assistant message. */
        public GenericArray<ToolCall>? tool_calls { get; set; }
        /** Identifier linking a tool response to the call it answers. */
        public string? tool_call_id { get; set; }

        public ChatMessage(ChatRole role, string? content = null) {
            this.role = role;
            this.content = content;
        }

        /** Convenience constructor for a system message. */
        public ChatMessage.system(string content) {
            this(ChatRole.SYSTEM, content);
        }

        /** Convenience constructor for a user message. */
        public ChatMessage.user(string content) {
            this(ChatRole.USER, content);
        }

        /** Convenience constructor for an assistant message. */
        public ChatMessage.assistant(string? content) {
            this(ChatRole.ASSISTANT, content);
        }

        /** Convenience constructor for a tool result message. */
        public ChatMessage.tool(string tool_call_id, string content) {
            this(ChatRole.TOOL, content);
            this.tool_call_id = tool_call_id;
        }

        /** Serializes this message to a JSON node. */
        public Json.Node to_json() {
            var obj = new Json.Object();
            obj.set_string_member("role", role.to_wire());
            if (content != null)
                obj.set_string_member("content", content);
            if (name != null)
                obj.set_string_member("name", name);
            if (tool_calls != null && tool_calls.length > 0) {
                var arr = new Json.Array();
                foreach (var tc in tool_calls)
                    arr.add_element(tc.to_json());
                obj.set_array_member("tool_calls", arr);
            }
            if (tool_call_id != null)
                obj.set_string_member("tool_call_id", tool_call_id);
            return object_to_node(obj);
        }

        /** Deserializes a chat message object, tolerating unknown fields. */
        public static ChatMessage from_json(Json.Object obj) throws Error {
            var msg = new ChatMessage(ChatRole.from_wire(json_opt_string(obj, "role")));
            msg.content = json_opt_string(obj, "content");
            msg.name = json_opt_string(obj, "name");
            msg.tool_call_id = json_opt_string(obj, "tool_call_id");
            var calls = json_opt_array(obj, "tool_calls");
            if (calls != null) {
                msg.tool_calls = new GenericArray<ToolCall>();
                for (uint i = 0; i < calls.get_length(); i++) {
                    var el = calls.get_element(i);
                    if (el.get_node_type() == Json.NodeType.OBJECT)
                        msg.tool_calls.add(ToolCall.from_json(el.get_object()));
                }
            }
            return msg;
        }
    }

    /**
     * The invocation of a tool issued by the model.
     */
    public class ToolCall : GLib.Object {
        /** Identifier of this tool call. */
        public string id { get; set; default = ""; }
        /**
         * Position of this call within its delta; only set inside
         * {@link ChatCompletionChunk} deltas, `-1` otherwise.
         */
        public int64 index { get; set; default = -1; }
        /** The invoked function. */
        public FunctionCall function { get; set; }

        public ToolCall(string id, FunctionCall function) {
            this.id = id;
            this.function = function;
        }

        internal ToolCall.blank() {
        }

        public Json.Node to_json() {
            var obj = new Json.Object();
            obj.set_string_member("type", "function");
            if (index >= 0)
                obj.set_int_member("index", index);
            if (id != "")
                obj.set_string_member("id", id);
            if (function != null)
                obj.set_object_member("function", function.to_json().get_object());
            return object_to_node(obj);
        }

        public static ToolCall from_json(Json.Object obj) {
            var call = new ToolCall.blank();
            call.id = json_opt_string(obj, "id") ?? "";
            call.index = json_opt_int(obj, "index", -1);
            var fn = json_opt_object(obj, "function");
            call.function = fn != null
                ? FunctionCall.from_json(fn)
                : new FunctionCall("", "");
            return call;
        }
    }

    /**
     * A function invocation: a name plus a JSON-encoded argument object.
     */
    public class FunctionCall : GLib.Object {
        /** Function name. */
        public string name { get; set; }
        /** JSON-encoded argument string as produced by the model. */
        public string arguments { get; set; }

        public FunctionCall(string name, string arguments = "") {
            this.name = name;
            this.arguments = arguments;
        }

        public Json.Node to_json() {
            var obj = new Json.Object();
            obj.set_string_member("name", name);
            obj.set_string_member("arguments", arguments);
            return object_to_node(obj);
        }

        public static FunctionCall from_json(Json.Object obj) {
            return new FunctionCall(json_opt_string(obj, "name") ?? "",
                                    json_opt_string(obj, "arguments") ?? "");
        }
    }

    /**
     * A function the model may call, described by a JSON Schema.
     */
    public class FunctionDefinition : GLib.Object {
        /** Function name. */
        public string name { get; set; }
        /** Human-readable description of what the function does. */
        public string? description { get; set; }
        /** JSON Schema node describing the parameter object. */
        public Json.Node? parameters { get; set; }
        /** Whether to enable strict schema adherence, or `null` to omit. */
        public bool? strict { get; set; }

        public FunctionDefinition(string name, string? description = null,
                                  Json.Node? parameters = null) {
            this.name = name;
            this.description = description;
            this.parameters = parameters;
        }

        public Json.Node to_json() {
            var obj = new Json.Object();
            obj.set_string_member("name", name);
            if (description != null)
                obj.set_string_member("description", description);
            if (parameters != null)
                obj.set_member("parameters", parameters);
            if (strict != null)
                obj.set_boolean_member("strict", strict);
            return object_to_node(obj);
        }
    }

    /**
     * A callable tool offered to the model. Currently only
     * `"type": "function"` tools exist.
     */
    public class Tool : GLib.Object {
        /** The function exposed by this tool. */
        public FunctionDefinition function { get; set; }

        public Tool(FunctionDefinition function) {
            this.function = function;
        }

        public Json.Node to_json() {
            var obj = new Json.Object();
            obj.set_string_member("type", "function");
            obj.set_member("function", function.to_json());
            return object_to_node(obj);
        }
    }

    /**
     * Parameters for a `POST /chat/completions` request.
     *
     * Only the fields that differ from the API defaults are serialized, so a
     * minimal request travels over the wire as
     * `{"model": ..., "messages": [...]}`.
     */
    public class ChatCompletionRequest : GLib.Object {
        /** Model identifier, e.g. `"gpt-4o"`. Required. */
        public string model { get; set; }
        /** Ordered conversation history. */
        public GenericArray<ChatMessage> messages { get; set; }
        /** Sampling temperature in [0, 2], or `null` for the API default. */
        public double? temperature { get; set; }
        /** Nucleus sampling mass, or `null` for the API default. */
        public double? top_p { get; set; }
        /** Number of completions to generate. */
        public int64? n { get; set; }
        /** Legacy cap on generated tokens. */
        public int64? max_tokens { get; set; }
        /** Cap on generated tokens for newer models. */
        public int64? max_completion_tokens { get; set; }
        /** Stop sequences. */
        public string[]? stop { get; set; }
        /** Presence penalty in [-2, 2]. */
        public double? presence_penalty { get; set; }
        /** Frequency penalty in [-2, 2]. */
        public double? frequency_penalty { get; set; }
        /** Per-token logit adjustments, keyed by token ID. */
        public HashTable<string, int>? logit_bias { get; set; }
        /** Desired output format. */
        public ResponseFormat response_format { get; set; default = ResponseFormat.TEXT; }
        /** Tools the model may call. */
        public GenericArray<Tool>? tools { get; set; }
        /** Tool selection policy. */
        public ToolChoice tool_choice { get; set; default = ToolChoice.AUTO; }
        /**
         * When set, forces the model to call the named function; overrides
         * {@link tool_choice} on the wire.
         */
        public string? tool_choice_function { get; set; }
        /** Whether parallel tool calls are allowed, or `null` to omit. */
        public bool? parallel_tool_calls { get; set; }
        /** Determinism seed for sampling, or `null` to omit. */
        public int64? seed { get; set; }
        /** End-user identifier for abuse tracking. */
        public string? user { get; set; }
        /**
         * Request `stream_options.include_usage` so the final streamed chunk
         * carries token usage. Only meaningful for streaming requests.
         */
        public bool include_usage_in_stream { get; set; default = false; }

        public ChatCompletionRequest(string model) {
            this.model = model;
            this.messages = new GenericArray<ChatMessage>();
        }

        /** Appends a message to the conversation. */
        public void add_message(ChatMessage message) {
            messages.add(message);
        }

        /** Appends a user message with the given content. */
        public void add_user(string content) {
            messages.add(new ChatMessage.user(content));
        }

        /** Appends a system message with the given content. */
        public void add_system(string content) {
            messages.add(new ChatMessage.system(content));
        }

        /** Serializes this request for `POST /chat/completions`. */
        public Json.Node to_json() {
            var obj = new Json.Object();
            obj.set_string_member("model", model);
            var msgs = new Json.Array();
            foreach (var m in messages)
                msgs.add_element(m.to_json());
            obj.set_array_member("messages", msgs);
            if (temperature != null)
                obj.set_double_member("temperature", temperature);
            if (top_p != null)
                obj.set_double_member("top_p", top_p);
            if (n != null)
                obj.set_int_member("n", n);
            if (max_tokens != null)
                obj.set_int_member("max_tokens", max_tokens);
            if (max_completion_tokens != null)
                obj.set_int_member("max_completion_tokens", max_completion_tokens);
            if (stop != null && stop.length > 0) {
                var arr = new Json.Array();
                foreach (var s in stop)
                    arr.add_string_element(s);
                obj.set_array_member("stop", arr);
            }
            if (presence_penalty != null)
                obj.set_double_member("presence_penalty", presence_penalty);
            if (frequency_penalty != null)
                obj.set_double_member("frequency_penalty", frequency_penalty);
            if (logit_bias != null && logit_bias.size() > 0) {
                var lb = new Json.Object();
                logit_bias.foreach((k, v) => lb.set_int_member(k, v));
                obj.set_object_member("logit_bias", lb);
            }
            if (response_format == ResponseFormat.JSON_OBJECT) {
                var rf = new Json.Object();
                rf.set_string_member("type", "json_object");
                obj.set_object_member("response_format", rf);
            }
            if (tools != null && tools.length > 0) {
                var arr = new Json.Array();
                foreach (var t in tools)
                    arr.add_element(t.to_json());
                obj.set_array_member("tools", arr);
            }
            if (tool_choice_function != null) {
                var tc = new Json.Object();
                tc.set_string_member("type", "function");
                var fn = new Json.Object();
                fn.set_string_member("name", tool_choice_function);
                tc.set_object_member("function", fn);
                obj.set_object_member("tool_choice", tc);
            } else if (tool_choice != ToolChoice.AUTO) {
                obj.set_string_member("tool_choice", tool_choice.to_wire());
            }
            if (parallel_tool_calls != null)
                obj.set_boolean_member("parallel_tool_calls", parallel_tool_calls);
            if (seed != null)
                obj.set_int_member("seed", seed);
            if (user != null)
                obj.set_string_member("user", user);
            if (include_usage_in_stream) {
                var so = new Json.Object();
                so.set_boolean_member("include_usage", true);
                obj.set_object_member("stream_options", so);
            }
            return object_to_node(obj);
        }
    }

    /**
     * Token usage accounting reported by the API.
     */
    public class CompletionUsage : GLib.Object {
        /** Tokens consumed by the prompt. */
        public int64 prompt_tokens { get; private set; }
        /** Tokens produced by the model. */
        public int64 completion_tokens { get; private set; }
        /** `prompt_tokens + completion_tokens`. */
        public int64 total_tokens { get; private set; }

        internal static CompletionUsage? from_json(Json.Object? obj) {
            if (obj == null)
                return null;
            var u = new CompletionUsage();
            u.prompt_tokens = json_opt_int(obj, "prompt_tokens");
            u.completion_tokens = json_opt_int(obj, "completion_tokens");
            u.total_tokens = json_opt_int(obj, "total_tokens");
            return u;
        }
    }

    /**
     * One candidate completion inside a {@link ChatCompletion}.
     */
    public class ChatChoice : GLib.Object {
        /** Position of this choice in the response. */
        public int64 index { get; private set; }
        /** The generated message. */
        public ChatMessage message { get; private set; }
        /** Why generation stopped (`"stop"`, `"length"`, `"tool_calls"`, ...). */
        public string? finish_reason { get; private set; }

        internal static ChatChoice from_json(Json.Object obj) throws Error {
            var c = new ChatChoice();
            c.index = json_opt_int(obj, "index");
            var msg = json_opt_object(obj, "message");
            c.message = msg != null
                ? ChatMessage.from_json(msg)
                : new ChatMessage.assistant(null);
            c.finish_reason = json_opt_string(obj, "finish_reason");
            return c;
        }
    }

    /**
     * A complete `POST /chat/completions` response.
     */
    public class ChatCompletion : GLib.Object {
        /** Server-generated identifier (`"chatcmpl-..."`). */
        public string id { get; private set; }
        /** Creation time as a Unix timestamp. */
        public int64 created { get; private set; }
        /** Model that produced the completion. */
        public string model { get; private set; }
        /** Backend configuration fingerprint, when reported. */
        public string? system_fingerprint { get; private set; }
        /** Generated candidates, ordered by index. */
        public GenericArray<ChatChoice> choices { get; private set; }
        /** Token usage, when returned. */
        public CompletionUsage? usage { get; private set; }

        /**
         * Text of the first choice, or `null` when the response contains no
         * choices or only tool calls.
         */
        public string? text {
            get {
                if (choices == null || choices.length == 0)
                    return null;
                return choices[0].message.content;
            }
        }

        /** Parses a chat completion from a decoded JSON object. */
        public static ChatCompletion from_json(Json.Object obj) throws Error {
            var c = new ChatCompletion();
            c.id = json_opt_string(obj, "id") ?? "";
            c.created = json_opt_int(obj, "created");
            c.model = json_opt_string(obj, "model") ?? "";
            c.system_fingerprint = json_opt_string(obj, "system_fingerprint");
            c.choices = new GenericArray<ChatChoice>();
            var arr = json_opt_array(obj, "choices");
            if (arr != null) {
                for (uint i = 0; i < arr.get_length(); i++) {
                    var el = arr.get_element(i);
                    if (el.get_node_type() == Json.NodeType.OBJECT)
                        c.choices.add(ChatChoice.from_json(el.get_object()));
                }
            }
            c.usage = CompletionUsage.from_json(json_opt_object(obj, "usage"));
            return c;
        }

        /** Parses a chat completion from a raw JSON document. */
        public static ChatCompletion from_data(string data) throws Error {
            return from_json(json_parse_object(data));
        }
    }

    /**
     * A partial assistant message carried by a {@link ChatCompletionChunk}.
     *
     * Any field may be absent; concatenating the {@link content} of successive
     * deltas reconstructs the full reply.
     */
    public class ChatDelta : GLib.Object {
        /** Author role; only present on the first chunk of a stream. */
        public ChatRole? role { get; private set; }
        /** Incremental text fragment. */
        public string? content { get; private set; }
        /** Incremental tool-call fragments. */
        public GenericArray<ToolCall>? tool_calls { get; private set; }

        internal static ChatDelta from_json(Json.Object obj) {
            var d = new ChatDelta();
            var r = json_opt_string(obj, "role");
            if (r != null)
                d.role = ChatRole.from_wire(r);
            d.content = json_opt_string(obj, "content");
            var calls = json_opt_array(obj, "tool_calls");
            if (calls != null) {
                d.tool_calls = new GenericArray<ToolCall>();
                for (uint i = 0; i < calls.get_length(); i++) {
                    var el = calls.get_element(i);
                    if (el.get_node_type() == Json.NodeType.OBJECT)
                        d.tool_calls.add(ToolCall.from_json(el.get_object()));
                }
            }
            return d;
        }
    }

    /**
     * One candidate inside a {@link ChatCompletionChunk}.
     */
    public class ChatChunkChoice : GLib.Object {
        /** Position of this choice in the response. */
        public int64 index { get; private set; }
        /** The incremental message fragment. */
        public ChatDelta delta { get; private set; }
        /** Non-null once generation of this choice is finished. */
        public string? finish_reason { get; private set; }

        internal static ChatChunkChoice from_json(Json.Object obj) {
            var c = new ChatChunkChoice();
            c.index = json_opt_int(obj, "index");
            var delta = json_opt_object(obj, "delta");
            c.delta = delta != null ? ChatDelta.from_json(delta) : new ChatDelta();
            c.finish_reason = json_opt_string(obj, "finish_reason");
            return c;
        }
    }

    /**
     * One `data:` event of a streamed chat completion.
     */
    public class ChatCompletionChunk : GLib.Object {
        /** Identifier shared by all chunks of the stream. */
        public string id { get; private set; }
        /** Creation time as a Unix timestamp. */
        public int64 created { get; private set; }
        /** Model producing the completion. */
        public string model { get; private set; }
        /** Incremental candidates. */
        public GenericArray<ChatChunkChoice> choices { get; private set; }
        /**
         * Token usage; present on the final chunk when the request set
         * {@link ChatCompletionRequest.include_usage_in_stream}.
         */
        public CompletionUsage? usage { get; private set; }

        /**
         * Incremental text of the first choice, or `null` for heartbeats,
         * tool-call chunks and finish markers.
         */
        public string? text_delta {
            get {
                if (choices == null || choices.length == 0)
                    return null;
                return choices[0].delta.content;
            }
        }

        /** Parses a chunk from a decoded JSON object. */
        public static ChatCompletionChunk from_json(Json.Object obj) throws Error {
            var c = new ChatCompletionChunk();
            c.id = json_opt_string(obj, "id") ?? "";
            c.created = json_opt_int(obj, "created");
            c.model = json_opt_string(obj, "model") ?? "";
            c.choices = new GenericArray<ChatChunkChoice>();
            var arr = json_opt_array(obj, "choices");
            if (arr != null) {
                for (uint i = 0; i < arr.get_length(); i++) {
                    var el = arr.get_element(i);
                    if (el.get_node_type() == Json.NodeType.OBJECT)
                        c.choices.add(ChatChunkChoice.from_json(el.get_object()));
                }
            }
            c.usage = CompletionUsage.from_json(json_opt_object(obj, "usage"));
            return c;
        }

        /** Parses a chunk from a raw `data:` payload. */
        public static ChatCompletionChunk from_data(string data) throws Error {
            return from_json(json_parse_object(data));
        }
    }
}
