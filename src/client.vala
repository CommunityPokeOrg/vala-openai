/*
 * Copyright 2026 CommunityPokeOrg
 * SPDX-License-Identifier: MIT
 */

namespace Openai {

    /**
     * Client for the OpenAI HTTP API (`/v1`).
     *
     * Covers chat completions (one-shot and streamed), embeddings, image
     * generation and the model catalog. Every operation comes in a blocking
     * variant for use off the main thread and an `_async` variant driven by
     * the GLib main loop.
     *
     * {{{
     * var client = new Openai.Client("sk-...");
     * var request = new Openai.ChatCompletionRequest("gpt-4o");
     * request.add_system("You are terse.");
     * request.add_user("Say hi in three words.");
     * var reply = client.chat_completion(request);
     * print("%s\n", reply.text);
     * }}}
     *
     * Transient failures (HTTP 429 and 5xx, honoring `Retry-After`) are
     * retried up to {@link max_retries} times; after a failed call
     * {@link last_error} holds the parsed API error payload when one was sent.
     */
    public class Client : GLib.Object {
        private const string DEFAULT_BASE_URL = "https://api.openai.com/v1";
        private const string USER_AGENT = "vala-openai/1.0";
        private const uint DEFAULT_TIMEOUT = 60;

        /** Bearer credential sent as `Authorization`. */
        public string api_key { get; construct; }
        /** Base URL without a trailing slash; must include the `/v1` prefix. */
        public string base_url { get; construct; }
        /** Optional `OpenAI-Organization` header value. */
        public string? organization { get; set; }
        /**
         * Socket I/O timeout in seconds applied to the underlying
         * #Soup.Session.
         */
        public uint timeout_seconds {
            get { return session.timeout; }
            set { session.timeout = value; }
        }
        /**
         * Number of times a request is retried after a 429/5xx or transient
         * transport failure. Zero disables retries.
         */
        public int max_retries { get; set; default = 2; }
        /**
         * Extra headers sent with every request; checked after the built-in
         * headers, so they may override them.
         */
        public HashTable<string, string> extra_headers { get; private set; }
        /** The last structured API error received, or `null`. */
        public ApiError? last_error { get; private set; }
        /** The underlying HTTP session. */
        public Soup.Session session { get; construct; }

        /**
         * Creates a client.
         *
         * @param api_key  OpenAI API key (`sk-...`)
         * @param base_url API root including `/v1`; `null` for the public API
         */
        public Client(string api_key, string? base_url = null) {
            Object(api_key: api_key,
                   base_url: base_url ?? DEFAULT_BASE_URL);
        }

        /**
         * Creates a client with a caller-managed session (for proxies or
         * custom TLS settings).
         */
        public Client.with_session(string api_key, Soup.Session session,
                                   string? base_url = null) {
            Object(api_key: api_key,
                   base_url: base_url ?? DEFAULT_BASE_URL,
                   session: session);
        }

        /**
         * Builds a client from `OPENAI_API_KEY`, `OPENAI_BASE_URL` and
         * `OPENAI_ORGANIZATION`.
         *
         * @return `null` when `OPENAI_API_KEY` is unset or empty.
         */
        public static Client? from_environment() {
            var key = Environment.get_variable("OPENAI_API_KEY");
            if (key == null || key == "")
                return null;
            var client = new Client(key, Environment.get_variable("OPENAI_BASE_URL"));
            client.organization = Environment.get_variable("OPENAI_ORGANIZATION");
            return client;
        }

        construct {
            if (base_url == null || base_url == "")
                base_url = DEFAULT_BASE_URL;
            while (base_url.has_suffix("/"))
                base_url = base_url.substring(0, base_url.length - 1);
            if (session == null) {
                session = new Soup.Session();
                session.timeout = DEFAULT_TIMEOUT;
            }
            session.user_agent = USER_AGENT;
            extra_headers = new HashTable<string, string>(str_hash, str_equal);
        }

        /**
         * Lists the available models (`GET /models`).
         */
        public ModelList list_models(Cancellable? cancellable = null) throws Error {
            var body = perform("GET", "/models", null, cancellable);
            return ModelList.from_data(bytes_to_string(body));
        }

        /**
         * Lists the available models, asynchronously.
         */
        public async ModelList list_models_async(Cancellable? cancellable = null) throws Error {
            var body = yield perform_async("GET", "/models", null, cancellable);
            return ModelList.from_data(bytes_to_string(body));
        }

        /**
         * Retrieves one model (`GET /models/{id}`).
         */
        public ModelInfo retrieve_model(string id, Cancellable? cancellable = null) throws Error {
            var body = perform("GET", "/models/" + Uri.escape_string(id), null, cancellable);
            return ModelInfo.from_json(json_parse_object(bytes_to_string(body)));
        }

        /**
         * Retrieves one model, asynchronously.
         */
        public async ModelInfo retrieve_model_async(string id, Cancellable? cancellable = null) throws Error {
            var body = yield perform_async("GET", "/models/" + Uri.escape_string(id), null, cancellable);
            return ModelInfo.from_json(json_parse_object(bytes_to_string(body)));
        }

        /**
         * Runs a chat completion (`POST /chat/completions`).
         */
        public ChatCompletion chat_completion(ChatCompletionRequest request,
                                              Cancellable? cancellable = null) throws Error {
            var body = perform("POST", "/chat/completions", request.to_json(), cancellable);
            return ChatCompletion.from_data(bytes_to_string(body));
        }

        /**
         * Runs a chat completion, asynchronously.
         */
        public async ChatCompletion chat_completion_async(ChatCompletionRequest request,
                                                          Cancellable? cancellable = null) throws Error {
            var body = yield perform_async("POST", "/chat/completions",
                                           request.to_json(), cancellable);
            return ChatCompletion.from_data(bytes_to_string(body));
        }

        /**
         * Opens a streaming chat completion.
         *
         * The request is sent with `"stream": true`; read
         * {@link ChatCompletionChunk}s from the returned
         * {@link ChatCompletionStream}.
         */
        public ChatCompletionStream chat_completion_stream(ChatCompletionRequest request,
                                                           Cancellable? cancellable = null) throws Error {
            var msg = build_message("POST", "/chat/completions", streamed_body(request));
            InputStream stream;
            try {
                stream = session.send(msg, cancellable);
            } catch (GLib.Error e) {
                throw error_from_io(e);
            }
            if (msg.status_code < 200 || msg.status_code >= 300) {
                check_status(msg, read_all(stream, cancellable));
                assert_not_reached();
            }
            last_error = null;
            return new ChatCompletionStream(stream);
        }

        /**
         * Opens a streaming chat completion, asynchronously.
         */
        public async ChatCompletionStream chat_completion_stream_async(ChatCompletionRequest request,
                                                                       Cancellable? cancellable = null) throws Error {
            var msg = build_message("POST", "/chat/completions", streamed_body(request));
            InputStream stream;
            try {
                stream = yield session.send_async(msg, Priority.DEFAULT, cancellable);
            } catch (GLib.Error e) {
                throw error_from_io(e);
            }
            if (msg.status_code < 200 || msg.status_code >= 300) {
                check_status(msg, yield read_all_async(stream, cancellable));
                assert_not_reached();
            }
            last_error = null;
            return new ChatCompletionStream(stream);
        }

        /**
         * Computes embeddings (`POST /embeddings`).
         */
        public EmbeddingResponse create_embedding(EmbeddingRequest request,
                                                  Cancellable? cancellable = null) throws Error {
            var body = perform("POST", "/embeddings", request.to_json(), cancellable);
            return EmbeddingResponse.from_data(bytes_to_string(body));
        }

        /**
         * Computes embeddings, asynchronously.
         */
        public async EmbeddingResponse create_embedding_async(EmbeddingRequest request,
                                                              Cancellable? cancellable = null) throws Error {
            var body = yield perform_async("POST", "/embeddings",
                                           request.to_json(), cancellable);
            return EmbeddingResponse.from_data(bytes_to_string(body));
        }

        /**
         * Generates images (`POST /images/generations`).
         */
        public ImageGenerationResponse create_image(ImageGenerationRequest request,
                                                    Cancellable? cancellable = null) throws Error {
            var body = perform("POST", "/images/generations",
                               request.to_json(), cancellable);
            return ImageGenerationResponse.from_data(bytes_to_string(body));
        }

        /**
         * Generates images, asynchronously.
         */
        public async ImageGenerationResponse create_image_async(ImageGenerationRequest request,
                                                                Cancellable? cancellable = null) throws Error {
            var body = yield perform_async("POST", "/images/generations",
                                           request.to_json(), cancellable);
            return ImageGenerationResponse.from_data(bytes_to_string(body));
        }

        private Json.Node streamed_body(ChatCompletionRequest request) {
            var node = request.to_json();
            var obj = node.get_object();
            obj.set_boolean_member("stream", true);
            return node;
        }

        private Soup.Message build_message(string method, string path,
                                           Json.Node? body) {
            var msg = new Soup.Message(method, base_url + path);
            msg.request_headers.append("Authorization", "Bearer %s".printf(api_key));
            if (organization != null && organization != "")
                msg.request_headers.append("OpenAI-Organization", organization);
            extra_headers.foreach((k, v) => msg.request_headers.append(k, v));
            if (body != null)
                msg.set_request_body_from_bytes(
                    "application/json", new Bytes(node_to_string(body).data));
            return msg;
        }

        private static bool should_retry(uint status) {
            return status == 408 || status == 429 || status >= 500;
        }

        private static uint retry_delay_ms(Soup.Message msg, int attempt) {
            var retry_after = msg.response_headers.get_one("Retry-After");
            if (retry_after != null) {
                var seconds = int.parse(retry_after.strip());
                if (seconds >= 0)
                    return uint.min((uint) seconds * 1000, 60000);
            }
            uint64 delay = 250;
            for (int i = 1; i < attempt; i++)
                delay *= 2;
            return (uint) uint64.min(delay, 30000);
        }

        private void check_status(Soup.Message msg, GLib.Bytes? body) throws Error {
            uint status = msg.status_code;
            if (status >= 200 && status < 300)
                return;
            string text = body == null ? "" : bytes_to_string(body);
            last_error = ApiError.try_parse(text, (int) status);
            string detail = last_error != null
                ? last_error.message
                : (msg.get_reason_phrase() ?? "HTTP %u".printf(status));
            throw error_for_status(status, detail);
        }

        private Bytes perform(string method, string path, Json.Node? body,
                              Cancellable? cancellable) throws Error {
            for (int attempt = 0; attempt <= max_retries; attempt++) {
                var msg = build_message(method, path, body);
                Bytes? data = null;
                try {
                    data = session.send_and_read(msg, cancellable);
                } catch (GLib.Error e) {
                    if (e.matches(GLib.IOError.quark(), GLib.IOError.CANCELLED))
                        throw error_from_io(e);
                    if (attempt < max_retries) {
                        GLib.Thread.usleep((ulong) retry_delay_ms(msg, attempt + 1) * 1000);
                        continue;
                    }
                    throw error_from_io(e);
                }
                uint status = msg.status_code;
                if (status >= 200 && status < 300) {
                    last_error = null;
                    return data;
                }
                if (attempt < max_retries && should_retry(status)) {
                    GLib.Thread.usleep((ulong) retry_delay_ms(msg, attempt + 1) * 1000);
                    continue;
                }
                check_status(msg, data);
                assert_not_reached();
            }
            assert_not_reached();
        }

        private async Bytes perform_async(string method, string path, Json.Node? body,
                                          Cancellable? cancellable) throws Error {
            for (int attempt = 0; attempt <= max_retries; attempt++) {
                var msg = build_message(method, path, body);
                Bytes? data = null;
                try {
                    data = yield session.send_and_read_async(
                        msg, Priority.DEFAULT, cancellable);
                } catch (GLib.Error e) {
                    if (e.matches(GLib.IOError.quark(), GLib.IOError.CANCELLED))
                        throw error_from_io(e);
                    if (attempt < max_retries) {
                        yield sleep_ms(retry_delay_ms(msg, attempt + 1));
                        continue;
                    }
                    throw error_from_io(e);
                }
                uint status = msg.status_code;
                if (status >= 200 && status < 300) {
                    last_error = null;
                    return data;
                }
                if (attempt < max_retries && should_retry(status)) {
                    yield sleep_ms(retry_delay_ms(msg, attempt + 1));
                    continue;
                }
                check_status(msg, data);
                assert_not_reached();
            }
            assert_not_reached();
        }

        private Bytes read_all(InputStream stream, Cancellable? cancellable) throws Error {
            var buffer = new MemoryOutputStream.resizable();
            try {
                buffer.splice(stream, OutputStreamSpliceFlags.NONE, cancellable);
            } catch (GLib.Error e) {
                throw error_from_io(e);
            }
            return buffer.steal_as_bytes();
        }

        private async Bytes read_all_async(InputStream stream, Cancellable? cancellable) throws Error {
            var buffer = new MemoryOutputStream.resizable();
            try {
                yield buffer.splice_async(stream, OutputStreamSpliceFlags.NONE,
                                          Priority.DEFAULT, cancellable);
            } catch (GLib.Error e) {
                throw error_from_io(e);
            }
            return buffer.steal_as_bytes();
        }

        private async void sleep_ms(uint ms) {
            GLib.Timeout.add(ms, sleep_ms.callback);
            yield;
        }
    }
}
