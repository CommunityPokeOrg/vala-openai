/*
 * Copyright 2026 CommunityPokeOrg
 * SPDX-License-Identifier: MIT
 */

namespace Openai {

    /**
     * Wire encoding for embedding vectors.
     */
    public enum EmbeddingFormat {
        /** JSON array of floats (default). */
        FLOAT,
        /** Base64-encoded little-endian float32 buffer. */
        BASE64;

        internal string to_wire() {
            return this == BASE64 ? "base64" : "float";
        }
    }

    /**
     * Parameters for a `POST /embeddings` request.
     */
    public class EmbeddingRequest : GLib.Object {
        /** Model identifier, e.g. `"text-embedding-3-small"`. Required. */
        public string model { get; set; }
        /** One or more input strings to embed. */
        public string[] input { get; set; }
        /** Encoding of the returned vectors. */
        public EmbeddingFormat format { get; set; default = EmbeddingFormat.FLOAT; }
        /** Optional output dimensionality for models that support it. */
        public int64? dimensions { get; set; }
        /** End-user identifier for abuse tracking. */
        public string? user { get; set; }

        public EmbeddingRequest(string model, string[] input) {
            this.model = model;
            this.input = input;
        }

        /** Convenience constructor for a single input string. */
        public EmbeddingRequest.for_text(string model, string input) {
            this(model, new string[] { input });
        }

        /** Serializes this request for `POST /embeddings`. */
        public Json.Node to_json() {
            var obj = new Json.Object();
            obj.set_string_member("model", model);
            var arr = new Json.Array();
            foreach (var s in input)
                arr.add_string_element(s);
            obj.set_array_member("input", arr);
            if (format == EmbeddingFormat.BASE64)
                obj.set_string_member("encoding_format", format.to_wire());
            if (dimensions != null)
                obj.set_int_member("dimensions", dimensions);
            if (user != null)
                obj.set_string_member("user", user);
            return object_to_node(obj);
        }
    }

    /**
     * A single embedding vector.
     */
    public class Embedding : GLib.Object {
        /** Position of this embedding within the request's input list. */
        public int64 index { get; private set; }
        /**
         * The embedding vector (always decoded to floats, even when a
         * base64 format was requested).
         */
        public float[] vector { get; private set; }

        internal static Embedding from_json(Json.Object obj) throws Error {
            var e = new Embedding();
            e.index = json_opt_int(obj, "index");
            var arr = json_opt_array(obj, "embedding");
            if (arr != null) {
                var vec = new float[arr.get_length()];
                for (uint i = 0; i < arr.get_length(); i++)
                    vec[i] = (float) arr.get_element(i).get_double();
                e.vector = vec;
            } else {
                var b64 = json_opt_string(obj, "embedding");
                if (b64 != null)
                    e.vector = decode_base64_vector(b64);
                else
                    e.vector = new float[0];
            }
            return e;
        }

        private static float[] decode_base64_vector(string b64) throws Error {
            uint8[] raw = GLib.Base64.decode(b64);
            if (raw.length % 4 != 0)
                throw new Error.PARSE("Truncated base64 embedding payload");
            var vec = new float[raw.length / 4];
            for (long i = 0; i < vec.length; i++) {
                uint32 bits = ((uint32) raw[i * 4])
                            | ((uint32) raw[i * 4 + 1] << 8)
                            | ((uint32) raw[i * 4 + 2] << 16)
                            | ((uint32) raw[i * 4 + 3] << 24);
                vec[i] = (float) *(float*) &bits;
            }
            return vec;
        }
    }

    /**
     * A complete `POST /embeddings` response.
     */
    public class EmbeddingResponse : GLib.Object {
        /** Embeddings in input order. */
        public GenericArray<Embedding> data { get; private set; }
        /** Model that produced the embeddings. */
        public string model { get; private set; }
        /** Token usage, when returned. */
        public CompletionUsage? usage { get; private set; }

        /** Parses a response from a decoded JSON object. */
        public static EmbeddingResponse from_json(Json.Object obj) throws Error {
            var r = new EmbeddingResponse();
            r.model = json_opt_string(obj, "model") ?? "";
            r.data = new GenericArray<Embedding>();
            var arr = json_opt_array(obj, "data");
            if (arr != null) {
                for (uint i = 0; i < arr.get_length(); i++) {
                    var el = arr.get_element(i);
                    if (el.get_node_type() == Json.NodeType.OBJECT)
                        r.data.add(Embedding.from_json(el.get_object()));
                }
            }
            r.usage = CompletionUsage.from_json(json_opt_object(obj, "usage"));
            return r;
        }

        /** Parses a response from a raw JSON document. */
        public static EmbeddingResponse from_data(string data) throws Error {
            return from_json(json_parse_object(data));
        }
    }
}
